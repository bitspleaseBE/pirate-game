class_name SpawnDirector
extends Node
## Runs the island loop: alert, defend, reinforce, capture, land, dig.
##
## All of it on a 2 Hz tick. Proximity checks, garrison bookkeeping and capture
## conditions do not need frame accuracy, and an archipelago-wide distance check
## every frame would be pure waste.
##
## Reinforcement waves come from the island's shipyard, and destroying it stops
## them — the tactical decision inside every island fight is whether to push for
## the shipyard early or clear the escorts first.

const ENEMY_SCENE: PackedScene = preload("res://src/entities/ships/enemy_ship.tscn")

const TICK_HZ: float = 2.0
## Seconds between reinforcement waves while a shipyard lives.
const REINFORCE_INTERVAL: float = 22.0
## Total reinforcement waves an island will send while its slipway still stands.
##
## Unbounded reinforcement is only fair if the player can stop it. For a long
## time they could not — the destructible shipyard the design called for did not
## exist — so this was a hard cap of two, with a comment asking for the cap to be
## lifted once the yard was built. It is built now ([Shipyard]), so the door is
## there: burn the yard and the waves stop.
##
## The cap survives, much higher, purely as a backstop against an island that is
## somehow never resolved. It is not meant to be reached in play; what ends the
## waves is the player deciding to go and end them.
const MAX_REINFORCEMENT_WAVES: int = 12
## Garrison ships spawn this far outside the island's coast.
const SPAWN_STANDOFF: float = 420.0
## Half-width of the arc defenders spawn within, centred on the player's bearing.
const SPAWN_ARC: float = 1.0
## How close a ship must be to the mooring buoy for the port to send a boat out.
const LANDING_DISTANCE: float = 260.0
## Seconds the boat takes to bring the cargo out from the quay.
const LANDING_DURATION: float = 3.5

signal landing_started(island: Island)
signal landing_finished(island: Island, loot: Dictionary)

var fleet: FleetController = null
var archipelago: Archipelago = null
## Enemies are parented here rather than to the island, so a captured island can
## never take its attackers down with it.
var ships_parent: Node2D = null

var _accum: float = 0.0
var _garrisons: Dictionary = {}       # Island -> Array[EnemyShip]
var _reinforce_left: Dictionary = {}   # Island -> float
var _waves_sent: Dictionary = {}       # Island -> int
## Island -> hulls ever spawned there. Feeds the index into the hull mix, so a
## reinforcement wave sends what comes *after* the garrison in the mix rather
## than starting again at its heaviest hull.
var _spawned_total: Dictionary = {}    # Island -> int
var _landing_left: Dictionary = {}     # Island -> float
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = GameState.voyage_seed if GameState.voyage_seed != 0 else randi()
	EventBus.intent_dig.connect(_on_intent_dig)


func _process(delta: float) -> void:
	if fleet == null or archipelago == null:
		return
	_accum += delta
	if _accum < 1.0 / TICK_HZ:
		return
	var tick_delta: float = _accum
	_accum = 0.0

	var focus: Vector2 = fleet.centroid()
	for raw: Variant in archipelago.islands:
		if not is_instance_valid(raw):
			continue
		_tick_island(raw, focus, tick_delta)


func _tick_island(island: Island, focus: Vector2, delta: float) -> void:
	var distance: float = island.distance_to_coast(focus)

	if distance < island.def.alert_radius * 1.6:
		island.mark_discovered()

	if island.is_captured:
		_tick_landing(island, delta)
		return

	if not island.is_alerted:
		if distance <= island.def.alert_radius and not _fleet_is_already_busy(island):
			_alert(island)
		return

	_prune_garrison(island)

	# All three, not any. Clearing the garrison and leaving the batteries firing is
	# not holding an island, and it is the fort that makes the last stretch of the
	# fight about position rather than about who reloads faster. The keep is the
	# same argument at the end of a voyage: a castle whose walls are intact has
	# not fallen because the water around it went quiet.
	if (
		_garrison_count(island) == 0
		and island.forts_remaining() == 0
		and not island.keep_standing()
	):
		island.capture()
		_reinforce_left.erase(island)
		if island.def.is_treasure_remaining():
			_begin_landing_approach(island)
		return

	# The slipway itself, not the flag on the def: burning it is what stops the
	# waves, and that is the one tactical decision inside an island fight.
	if island.can_reinforce() and int(_waves_sent.get(island, 0)) < MAX_REINFORCEMENT_WAVES:
		var left: float = float(_reinforce_left.get(island, REINFORCE_INTERVAL)) - delta
		if left <= 0.0:
			_spawn_wave(island, _wave_size(island.def.tier))
			_waves_sent[island] = int(_waves_sent.get(island, 0)) + 1
			left = REINFORCE_INTERVAL
		_reinforce_left[island] = left


## One island at a time.
##
## Islands sit 2,000–3,000 m apart, which is close enough that a fleet cutting
## through the channel between two of them can stand inside both alert radii at
## once. Two garrisons arriving together is not a harder island, it is two
## islands — and it is indistinguishable, from the deck, from the game simply
## deciding to drown you. The player picks their fights; the generator's job is
## to make sure the game cannot pick one for them.
##
## Only a fight the fleet is still *in* holds the line. An island alerted and
## then left astern releases it, so running from a losing fight is still a way
## out of it rather than a way to lock the rest of the voyage down.
func _fleet_is_already_busy(candidate: Island) -> bool:
	var focus: Vector2 = fleet.centroid()
	for raw: Variant in archipelago.islands:
		if not is_instance_valid(raw):
			continue
		var other: Island = raw
		if other == candidate or other.is_captured or not other.is_alerted:
			continue
		if _garrison_count(other) == 0 and other.forts_remaining() == 0:
			continue
		if other.distance_to_coast(focus) <= other.def.alert_radius * 2.0:
			return true
	return false


func _alert(island: Island) -> void:
	island.alert()
	_garrisons[island] = [] as Array[EnemyShip]
	_reinforce_left[island] = REINFORCE_INTERVAL
	_waves_sent[island] = 0
	_spawn_wave(island, island.def.garrison_ships)
	Log.info(
		"%s alerted: %d defenders, %d batteries"
		% [island.def.display_name, island.def.garrison_ships, island.forts_remaining()],
		"Spawn"
	)


## Spawns defenders on the side of the island the player is approaching from.
##
## A random bearing puts a small garrison behind the island as often as not, where
## it may never notice the player at all — you sail up to your first island and
## nothing happens, which reads as the game being broken rather than as bad luck.
## Coming out to meet you is also simply what a garrison would do.
func _spawn_wave(island: Island, count: int) -> void:
	if ships_parent == null:
		return
	var garrison: Array = _garrisons.get(island, [])

	var toward_player: float = (fleet.centroid() - island.global_position).angle()
	var already: int = int(_spawned_total.get(island, 0))

	for i: int in count:
		# Spread across the near quarter so a wave is not a single-file column.
		var angle: float = toward_player + _rng.randf_range(-SPAWN_ARC, SPAWN_ARC)
		var radius: float = island.def.radius + SPAWN_STANDOFF + _rng.randf_range(0.0, 240.0)
		var at: Vector2 = island.global_position + Vector2(cos(angle), sin(angle)) * radius

		var enemy: EnemyShip = ENEMY_SCENE.instantiate() as EnemyShip
		enemy.stats = ShipStatsLibrary.get_stats(_hull_for_tier(island.def.tier, already + i))
		enemy.global_position = at
		ships_parent.add_child(enemy)
		enemy.assign_station(
			island.global_position, island.def.radius + 600.0, island.def.alert_radius * 2.0
		)
		garrison.append(enemy)

	_garrisons[island] = garrison
	_spawned_total[island] = already + count
	Log.debug(
		"%s wave: +%d, garrison now %d" % [island.def.display_name, count, garrison.size()],
		"Spawn"
	)


## What each tier puts on the water, in the order it puts it there.
##
## Written out as a list per tier rather than a chain of ifs, because it *is* the
## enemy ramp and the ramp is something to read down a column and argue with.
## `index` is how many hulls this island has already launched, so the front of
## each list leads the garrison and reinforcements arrive further down it; past
## the end it wraps.
##
## The whole shape of the early game lives in the tier-2 line. It used to read
## `skiff if index % 2 == 0 else enemy_sloop`, which against a two-hull garrison
## meant a Navy Sloop *and* a skiff for a player who had, at that point, one gun
## a side and eighty-five points of hull. The step from island one to island two
## is a step in weight — one proper warship instead of one pop-gun boat — rather
## than a step in numbers, and numbers do not start climbing until tier 3.
##
## Where the *variety* arrives is the other half of it. Tier 3 is where the
## player meets something that is not a gun duel at all: a fireship, which cannot
## be traded with and has to be shot off or dodged. Tier 4 adds the bomb ketch,
## which cannot be dodged and has to be closed on. Between them they are what
## stops the back half of a voyage being the front half with bigger numbers.
const HULL_MIX: Dictionary = {
	1: [&"skiff"],
	2: [&"enemy_sloop"],
	3: [&"enemy_sloop", &"fireship", &"skiff"],
	4: [&"enemy_brig", &"bomb_ketch", &"enemy_sloop", &"fireship"],
	5: [&"enemy_brig", &"bomb_ketch", &"enemy_sloop", &"fireship", &"enemy_brig", &"skiff"],
}


func _hull_for_tier(tier: int, index: int) -> StringName:
	var mix: Array = HULL_MIX.get(clampi(tier, 1, 5), HULL_MIX[1])
	return mix[index % mix.size()]


## Reinforcements per wave. A shipyard only exists from tier 3, and at tier 3 it
## sends one hull at a time — two is what turns a fight you are winning into a
## fight that never ends.
func _wave_size(tier: int) -> int:
	return 1 if tier <= 3 else 2


## Drops the dead — and the routed — from an island's garrison.
##
## A defender used to leave the roll only by sinking, which meant a ship that
## broke off and ran held the island hostage: the capture condition wants an
## empty garrison, so the player had to chase a beaten hull across open water to
## claim an island they had plainly already won. That is not tension, it is
## admin, and it is the single most annoying thing a fight could end with.
##
## Letting a routed ship go is now a real option, which is also what finally gives
## chain shot a job. A hull whose rigging you have shredded makes 45% speed and
## cannot reach the routed distance, so the choice at the end of every fight is:
## let them run and take the island now, or chain them, run them down and take the
## prize money too. That decision costs a shot type, which is the entire point of
## having shot types.
func _prune_garrison(island: Island) -> void:
	## How far past the alert radius a beaten ship has to get before it counts as
	## gone rather than merely running.
	const ROUTED_MARGIN: float = 1.25

	var garrison: Array = _garrisons.get(island, [])
	var routed: float = island.def.radius + island.def.alert_radius * ROUTED_MARGIN

	for i: int in range(garrison.size() - 1, -1, -1):
		# Read untyped first: assigning an already-freed object to a *typed*
		# variable raises "Trying to assign invalid previously freed instance"
		# before the validity check below can ever run. Every dead defender would
		# spam the console once per tick until the garrison was emptied.
		var entry: Variant = garrison[i]
		if not is_instance_valid(entry) or not (entry as EnemyShip).alive:
			garrison.remove_at(i)
			continue

		var enemy: EnemyShip = entry
		if enemy.is_routed(island.global_position, routed):
			garrison.remove_at(i)
			# Still afloat, still worth prize money, and it will still fight if the
			# player goes after it — it has simply stopped being this island's
			# problem. Announced, because a garrison count silently dropping is
			# indistinguishable from a bug.
			EventBus.enemy_routed.emit(enemy, island)
			Log.info(
				"%s routed from %s — garrison now %d"
				% [enemy.stats.display_name, island.def.display_name, garrison.size()],
				"Spawn"
			)

	_garrisons[island] = garrison


func _garrison_count(island: Island) -> int:
	return (_garrisons.get(island, []) as Array).size()


## The player asked for the treasure waiting on an island they hold. Same
## approach the capture triggers automatically — this is the way back to the
## harbour after the player has sailed off and the automatic course was
## cancelled.
func _on_intent_dig(node: Node2D) -> void:
	var island := node as Island
	if island == null or fleet == null or not is_instance_valid(fleet):
		return
	if not island.is_captured or not island.def.is_treasure_remaining():
		return
	_begin_landing_approach(island)


## Send a ship to the island's mooring buoy so the port can bring the cargo out.
## The player can override it — tapping elsewhere cancels the approach, and the
## treasure stays on the quay until they come back.
##
## The order goes to the *selected* hull, not to whichever one happens to be
## nearest: an unselected ship is station-keeping on the leader, so
## [method FleetController._update_escorts] would overwrite its course on the
## next physics frame and the landing party would never arrive. Ordering the
## leader also brings the escorts along behind it.
func _begin_landing_approach(island: Island) -> void:
	var ship: Ship = fleet.selected
	if ship == null or not is_instance_valid(ship) or not ship.alive:
		ship = _nearest_ship(island.anchor_point)
	if ship == null:
		return
	ship.set_target(null)
	ship.set_course(ship.clamp_to_navigable(island.anchor_point))


func _tick_landing(island: Island, delta: float) -> void:
	if not island.def.is_treasure_remaining():
		return

	if _landing_left.has(island):
		var left: float = float(_landing_left[island]) - delta
		if left > 0.0:
			_landing_left[island] = left
			return
		_landing_left.erase(island)
		var loot: Dictionary = island.dig_treasure(_rng)
		if island.port != null:
			island.port.finish_unloading()
		Audio.play_ui(&"coin_pickup")
		landing_finished.emit(island, loot)
		return

	# Any single hull at the mooring launches the boat. Measuring the fleet
	# centroid instead means two escorts trailing astern can hold the average out
	# past the trigger while the ship the player actually steered is sitting on
	# top of the buoy, waiting for nothing.
	var nearest: Ship = _nearest_ship(island.anchor_point)
	if nearest == null:
		return
	if nearest.global_position.distance_to(island.anchor_point) <= LANDING_DISTANCE:
		_landing_left[island] = LANDING_DURATION
		# The boat rows to the ship that actually moored, not to the buoy, so the
		# cargo is delivered to the hull the player steered in.
		if island.port != null:
			island.port.begin_unloading(nearest.global_position, LANDING_DURATION)
		landing_started.emit(island)
		Log.info("Boat away from the quay at %s" % island.def.display_name, "Spawn")


func _nearest_ship(at: Vector2) -> Ship:
	var best: Ship = null
	var best_dist: float = INF
	for ship: Ship in fleet.living_ships():
		var d: float = ship.global_position.distance_to(at)
		if d < best_dist:
			best_dist = d
			best = ship
	return best


## Total living enemies, for the HUD and the debug overlay.
func active_enemy_count() -> int:
	var n: int = 0
	for island: Island in _garrisons:
		n += _garrison_count(island)
	return n
