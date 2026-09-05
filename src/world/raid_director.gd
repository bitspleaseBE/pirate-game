class_name RaidDirector
extends Node
## They come back for it.
##
## ## Why this exists
##
## The game had one verb. Every island was the same sentence — sail there, kill
## the garrison, dig, shop — and factions changed *what* you fought without ever
## changing what you did. Worse, a captured island was inert: nothing could go
## wrong there, there was no reason to return, and the map was a checklist rather
## than a place. The design doc has carried the question for as long as it has
## existed ("does the player ever *lose* a captured island?"), and the answer
## turns out to be the cheapest available fix for the thing underneath it.
##
## A reprisal is the first thing in this game that happens somewhere the player
## is not. That is the whole point: it makes the sea between islands into a
## decision — press on, or turn back — where before it was only travel.
##
## ## The rules, and why each one is there
##
## **The island's own former owner comes back for it.** Not a random faction:
## [member IslandDef.faction] still holds who it was taken from, so the Crown
## wants Widow Reef back and nobody else does. It reads as a consequence rather
## than as a spawn.
##
## **The tribes never raid** ([member Faction.raid_pressure] is zero for them).
## Since the opening three islands are theirs, a new captain cannot lose ground
## before they have learned to hold any. The safety catch is characterisation
## rather than a special case — a people defending their own reef do not mount
## campaigns.
##
## **It is announced, and the warning is longer than the sail.** A leg is
## 2,200–3,000 units and a Sloop makes about 110, so [constant WARNING_SEC] is
## set above the worst case: whenever the player is told, turning back is a real
## option. A raid you cannot reach in time is not a decision, it is a tax.
##
## **It can be ignored, at a price.** Losing an island costs its port — repairs
## and banking — and puts its garrison back on the water. It does not cost the
## run, and the island can be taken again. An unignorable event in an open world
## is a leash.
##
## **One at a time, with a cooldown.** Two simultaneous reprisals is not twice
## the tension, it is whack-a-mole, and whack-a-mole is what this mechanic
## becomes if it is allowed to.
##
## **The raiders become the garrison.** Whoever is still afloat when the island
## falls is what the player has to fight to take it back. Nothing is despawned
## and respawned, so the fight the player declined is exactly the fight waiting
## for them.

## How often a reprisal is considered at all.
const CHECK_INTERVAL: float = 20.0
## Chance per check, per point of the faction's pressure. The Brethren at 1.5
## work out to a raid roughly every seventy-five seconds of eligible time; the
## Armada at 0.55 to about one in three and a half minutes.
const CHANCE_PER_PRESSURE: float = 0.18
## Quiet spell after any reprisal resolves, won or lost.
const COOLDOWN: float = 90.0
## How long an island must have been held before anyone comes for it. Taking an
## island and immediately being told it is under attack reads as the game
## cheating rather than as the world reacting.
const SETTLE_SEC: float = 60.0
## Warning before the raiders arrive. Longer than the longest leg in the
## archipelago takes to sail — see the class comment.
const WARNING_SEC: float = 30.0
## How long the raiders have to survive off the island before it falls to them.
const HOLD_SEC: float = 45.0
## How close a raider must be to the island to count as pressing the attack. A
## squadron the player has chased off is not holding anything.
const HOLD_RADIUS_MUL: float = 2.2
## The player's own island is never raided out from under them while they are
## standing on it. Measured generously — this is about not being ambushed by an
## event you had no way to see coming.
const PLAYER_PRESENCE: float = 2600.0

## Raiders per reprisal, by the island's tier. Deliberately smaller than the
## garrison that held the place: a reprisal is a squadron detached from
## somewhere else, and it should be a fight the player can win with the hull
## they already have rather than a second siege.
const RAID_SIZE: Dictionary = {1: 1, 2: 1, 3: 2, 4: 2, 5: 3}

## Turned off for every automated run except the one that tests it. A harness
## that captures an island and then measures something else does not want a
## squadron arriving in the middle of the measurement.
var enabled: bool = true

var fleet: FleetController = null
var archipelago: Archipelago = null
var director: SpawnDirector = null
var ships_parent: Node2D = null

## The reprisal in flight, if any: island, faction, the ships, and the two
## clocks. Empty when the sea is quiet.
var _raid: Dictionary = {}
var _cooldown: float = 0.0
var _accum: float = 0.0
## Island -> seconds it has been in the player's hands.
var _held_for: Dictionary = {}

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	EventBus.island_captured.connect(_on_island_captured)


func _process(delta: float) -> void:
	if not enabled or archipelago == null or fleet == null:
		return

	for island: Island in archipelago.islands:
		if island.is_captured and island != archipelago.home:
			_held_for[island] = float(_held_for.get(island, 0.0)) + delta

	if not _raid.is_empty():
		_tick_raid(delta)
		return

	_cooldown = maxf(0.0, _cooldown - delta)
	_accum += delta
	if _accum < CHECK_INTERVAL:
		return
	_accum = 0.0
	if _cooldown > 0.0:
		return
	_consider()


# --- Starting one -----------------------------------------------------------

func _consider() -> void:
	var target: Island = _pick_target()
	if target == null:
		return
	var faction: Faction = FactionLibrary.get_faction(target.def.faction)
	if _rng.randf() > faction.raid_pressure * CHANCE_PER_PRESSURE:
		return
	_begin(target, faction)


## An island somebody might plausibly come back for.
##
## Everything here is a reason *not* to raid, which is the right shape for this:
## the mechanic earns its keep by being rare and legible, so the default is that
## nothing happens.
func _pick_target() -> Island:
	var centroid: Vector2 = fleet.centroid()
	var candidates: Array[Island] = []
	for island: Island in archipelago.islands:
		if island == archipelago.home or not island.is_captured:
			continue
		# Nobody takes the castle back. It is the end of the voyage, and a boss
		# arena that can quietly revert while the player sails home is a way to
		# lose a run to something you were never shown.
		if island.def.has_castle:
			continue
		if not FactionLibrary.get_faction(island.def.faction).raids():
			continue
		if float(_held_for.get(island, 0.0)) < SETTLE_SEC:
			continue
		if island.global_position.distance_to(centroid) < PLAYER_PRESENCE:
			continue
		candidates.append(island)

	if candidates.is_empty():
		return null
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _begin(island: Island, faction: Faction) -> void:
	_raid = {
		"island": island,
		"faction": faction,
		"warning": WARNING_SEC,
		"hold": HOLD_SEC,
		"ships": [] as Array[EnemyShip],
		"landed": false,
	}
	Log.info(
		"%s are coming back for %s" % [faction.display_name, island.def.display_name],
		"Raid"
	)
	EventBus.island_threatened.emit(island, faction.display_name, WARNING_SEC)


# --- Running one ------------------------------------------------------------

func _tick_raid(delta: float) -> void:
	var island: Island = _raid["island"]
	if not is_instance_valid(island):
		_end()
		return

	# The player retook the initiative by being there — see PLAYER_PRESENCE. This
	# is not a get-out: the raiders still have to be beaten. It only means an
	# island cannot fall while the player is standing on it, which is the
	# difference between a fight and a timer.
	if float(_raid["warning"]) > 0.0:
		_raid["warning"] = float(_raid["warning"]) - delta
		if float(_raid["warning"]) <= 0.0:
			_launch(island, _raid["faction"])
		return

	var alive: Array[EnemyShip] = []
	var near_island: int = 0
	var reach: float = island.def.radius * HOLD_RADIUS_MUL
	for raw: Variant in _raid["ships"]:
		if not is_instance_valid(raw):
			continue
		var ship: EnemyShip = raw
		if not ship.alive:
			continue
		alive.append(ship)
		if ship.global_position.distance_to(island.global_position) <= reach:
			near_island += 1
	_raid["ships"] = alive

	if alive.is_empty():
		Log.info("Reprisal on %s beaten off" % island.def.display_name, "Raid")
		EventBus.raid_repelled.emit(island)
		_end()
		return

	# Whether the attack is pressing home, and the answer depends on whether
	# anybody is there to see it.
	#
	# This is the part that cannot be built out of the ships alone. A reprisal
	# happens, by definition, somewhere the player is not — and an entity far
	# enough off screen is DORMANT, which [CullingManager] documents as "nothing
	# runs at all". The raiders freeze at their spawn standoff, never close the
	# island, and the raid silently never completes. The player would get the
	# warning, sail on, and nothing would ever happen: convincingly wrong, and
	# invisible unless you go looking.
	#
	# So the *outcome* is a clock on the island and the ships are how that clock
	# is presented when there is anyone to present it to. With the player away,
	# an unopposed squadron presses by definition. With the player in range the
	# real geometry takes over, so chasing them off the island genuinely stops
	# the clock — which is the whole reason the proximity test exists.
	var player_near: bool = (
		fleet.centroid().distance_to(island.global_position) <= PLAYER_PRESENCE
	)
	var pressing: bool = near_island > 0 if player_near else true

	# The clock only runs while the attack is being pressed. Drive them out to
	# the horizon and it stops, which is what makes chasing them a real
	# alternative to sinking them.
	if pressing:
		_raid["hold"] = float(_raid["hold"]) - delta
		if float(_raid["hold"]) <= 0.0:
			_fall(island, _raid["faction"], alive)
			_end()


func _launch(island: Island, faction: Faction) -> void:
	var count: int = int(RAID_SIZE.get(clampi(island.def.tier, 1, 5), 1))
	var ships: Array[EnemyShip] = []
	# Arriving from seaward, spread over an arc, so they are visible on the
	# approach rather than appearing on top of the harbour.
	var bearing: float = _rng.randf() * TAU
	var standoff: float = island.def.radius + 900.0
	for i: int in count:
		var angle: float = bearing + (float(i) - float(count - 1) * 0.5) * 0.35
		var enemy: EnemyShip = SpawnDirector.ENEMY_SCENE.instantiate() as EnemyShip
		enemy.faction = faction
		enemy.stats = faction.build(SpawnDirector.hull_for(island.def, i))
		enemy.global_position = (
			island.global_position + Vector2(cos(angle), sin(angle)) * standoff
		)
		ships_parent.add_child(enemy)
		enemy.home_position = island.global_position
		enemy.patrol_radius = island.def.radius * 1.4
		# Clamped by the *ship*, not the island: keeping a hull off the sand is a
		# property of the hull's own radius, and asking the island produced a
		# silent runtime error that left every raider without a course. They
		# milled about at their spawn standoff and the reprisal could never press
		# home, which the gate correctly reported as an unopposed raid failing to
		# take an undefended island.
		enemy.set_course(enemy.clamp_to_navigable(island.anchor_point))
		ships.append(enemy)

	_raid["ships"] = ships
	Log.info(
		"%d raiders closing on %s" % [ships.size(), island.def.display_name], "Raid"
	)
	EventBus.raid_arrived.emit(island, faction.display_name, ships.size())


## The island changes hands.
##
## The surviving raiders are handed to [SpawnDirector] as the new garrison rather
## than being despawned and replaced. The fight the player declined is the fight
## waiting for them, at the strength they left it — which is both cheaper and a
## great deal more honest than rolling a fresh garrison.
func _fall(island: Island, faction: Faction, survivors: Array[EnemyShip]) -> void:
	Log.info(
		"%s has fallen to the %s" % [island.def.display_name, faction.display_name],
		"Raid"
	)
	island.lose_to_reprisal()
	if director != null:
		director.install_garrison(island, survivors)
	EventBus.island_lost.emit(island, faction.display_name)


func _end() -> void:
	_raid = {}
	_cooldown = COOLDOWN


func _on_island_captured(island: Node2D) -> void:
	# A newly taken island starts its settling clock from zero, including one the
	# player has just retaken off a reprisal.
	_held_for[island] = 0.0


# --- For the harness --------------------------------------------------------

## Forces a reprisal on `island` immediately, skipping the dice and the settling
## period. Only the `--reprisal` gate uses this: the mechanic is rare by design,
## and a test that waited for it to happen naturally would be a test of the
## random number generator.
func force_raid(island: Island) -> bool:
	if island == null or not island.is_captured:
		return false
	var faction: Faction = FactionLibrary.get_faction(island.def.faction)
	if not faction.raids():
		return false
	_begin(island, faction)
	return true


## Seconds left on whichever clock is running, for the harness and the HUD.
func raid_time_left() -> float:
	if _raid.is_empty():
		return 0.0
	if float(_raid["warning"]) > 0.0:
		return float(_raid["warning"])
	return float(_raid["hold"])


func raid_target() -> Island:
	return _raid.get("island", null)
