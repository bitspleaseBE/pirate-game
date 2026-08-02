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
const REINFORCE_WAVE_SIZE: int = 2
## Total reinforcement waves an island will ever send.
##
## Unbounded reinforcement is only fair if the player can stop it, and the
## destructible shipyard that is supposed to do that is not built yet. Until it
## is, an island has to be finite: an endless trickle against a starting hull is
## not difficulty, it is a wall with no door. Remove this cap when killing the
## shipyard actually cuts the supply.
const MAX_REINFORCEMENT_WAVES: int = 2
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
		if distance <= island.def.alert_radius:
			_alert(island)
		return

	_prune_garrison(island)

	# Both, not either. Clearing the garrison and leaving the batteries firing is
	# not holding an island, and it is the fort that makes the last stretch of the
	# fight about position rather than about who reloads faster.
	if _garrison_count(island) == 0 and island.forts_remaining() == 0:
		island.capture()
		_reinforce_left.erase(island)
		if island.def.is_treasure_remaining():
			_begin_landing_approach(island)
		return

	if island.def.has_shipyard and int(_waves_sent.get(island, 0)) < MAX_REINFORCEMENT_WAVES:
		var left: float = float(_reinforce_left.get(island, REINFORCE_INTERVAL)) - delta
		if left <= 0.0:
			_spawn_wave(island, REINFORCE_WAVE_SIZE)
			_waves_sent[island] = int(_waves_sent.get(island, 0)) + 1
			left = REINFORCE_INTERVAL
		_reinforce_left[island] = left


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

	for i: int in count:
		# Spread across the near quarter so a wave is not a single-file column.
		var angle: float = toward_player + _rng.randf_range(-SPAWN_ARC, SPAWN_ARC)
		var radius: float = island.def.radius + SPAWN_STANDOFF + _rng.randf_range(0.0, 240.0)
		var at: Vector2 = island.global_position + Vector2(cos(angle), sin(angle)) * radius

		var enemy: EnemyShip = ENEMY_SCENE.instantiate() as EnemyShip
		enemy.stats = ShipStatsLibrary.get_stats(_hull_for_tier(island.def.tier, i))
		enemy.global_position = at
		ships_parent.add_child(enemy)
		enemy.assign_station(
			island.global_position, island.def.radius + 600.0, island.def.alert_radius * 2.0
		)
		garrison.append(enemy)

	_garrisons[island] = garrison
	Log.debug(
		"%s wave: +%d, garrison now %d" % [island.def.display_name, count, garrison.size()],
		"Spawn"
	)


## Tier decides the mix. Every garrison keeps at least one skiff pack so the
## player always has something cheap to practise angles on.
func _hull_for_tier(tier: int, index: int) -> StringName:
	if tier <= 1:
		return &"skiff"
	if tier == 2:
		return &"skiff" if index % 2 == 0 else &"enemy_sloop"
	if tier == 3:
		return &"enemy_sloop" if index % 3 != 0 else &"enemy_brig"
	return &"enemy_brig" if index % 2 == 0 else &"enemy_sloop"


func _prune_garrison(island: Island) -> void:
	var garrison: Array = _garrisons.get(island, [])
	for i: int in range(garrison.size() - 1, -1, -1):
		# Read untyped first: assigning an already-freed object to a *typed*
		# variable raises "Trying to assign invalid previously freed instance"
		# before the validity check below can ever run. Every dead defender would
		# spam the console once per tick until the garrison was emptied.
		var entry: Variant = garrison[i]
		if not is_instance_valid(entry) or not (entry as EnemyShip).alive:
			garrison.remove_at(i)
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
