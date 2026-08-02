class_name FleetController
extends Node2D
## Owns the player's ships and turns input intents into orders.
##
## The fleet is up to three hulls but the player has one thumb, so unselected
## ships keep a loose escort station on the selected one. That is the whole
## reason a three-ship fleet is playable on a phone: you steer one ship and the
## others behave sensibly.

const SHIP_SCENE: PackedScene = preload("res://src/entities/ships/ship.tscn")

## Escort stations, in multiples of the leader's hull radius, relative to the
## leader's heading. Astern and to either quarter — never ahead, where they would
## block the leader's own guns.
const ESCORT_STATIONS: Array[Vector2] = [Vector2(-2.6, 2.2), Vector2(2.6, 2.2)]
## Escorts only re-issue a course when their station has moved this far, so they
## are not given a new order every frame.
const ESCORT_REORDER_DISTANCE: float = 220.0

signal selection_changed(ship: Ship)
signal fleet_emptied()

var ships: Array[Ship] = []
var selected: Ship = null

var _spawn_origin: Vector2 = Vector2.ZERO


func _ready() -> void:
	EventBus.intent_move.connect(_on_intent_move)
	EventBus.intent_target.connect(_on_intent_target)
	EventBus.intent_select_ship.connect(_on_intent_select)
	EventBus.intent_cycle_ammo.connect(_on_intent_cycle_ammo)


## Spawns one hull per entry in GameState.fleet, in a line abeam of `origin`.
##
## Every voyage — new, continued or restarted after a wipe — reaches the water
## through here, which makes it the one place worth guaranteeing the player
## actually has something to sail.
##
## That guarantee used to live only in [method GameState.from_dict], so it covered
## loading a save and nothing else. A fleet wiped in the previous voyage leaves an
## empty roster behind, and "New Voyage" does not reload the save — it reuses live
## state — so the loop below ran zero times and the player was put on the water
## with no ship at all. Worse than it sounds: with nothing alive, nothing can die,
## so `fleet_emptied` never fires, there is no game-over, and the only way out is
## the pause key.
func spawn_fleet(origin: Vector2) -> void:
	GameState.ensure_fleet()
	_spawn_origin = origin
	for i: int in GameState.fleet.size():
		var entry: Dictionary = GameState.fleet[i]
		var stats_id: StringName = entry.get("stats_id", GameState.STARTING_HULL)
		var upgrades: Dictionary = entry.get("upgrades", {})
		var offset := Vector2(float(i) * 260.0 - float(GameState.fleet.size() - 1) * 130.0, 0.0)
		_spawn_ship(stats_id, upgrades, origin + offset)

	if not ships.is_empty():
		_select(ships[0])
	EventBus.fleet_changed.emit()


func _spawn_ship(stats_id: StringName, upgrades: Dictionary, at: Vector2) -> Ship:
	var ship: Ship = SHIP_SCENE.instantiate() as Ship
	ship.stats = ShipStatsLibrary.build(stats_id, upgrades)
	ship.team = Teams.PLAYER
	ship.global_position = at
	add_child(ship)
	ship.loaded_ammo = AmmoLibrary.get_ammo(GameState.selected_ammo)
	ship.died.connect(_on_ship_died.bind(ship))
	ships.append(ship)
	return ship


func _physics_process(_delta: float) -> void:
	_update_escorts()


func _update_escorts() -> void:
	if selected == null or not is_instance_valid(selected):
		return
	var leader_forward: Vector2 = selected.forward()
	var leader_right: Vector2 = selected.starboard()
	var station_index: int = 0

	for entry: Variant in ships:
		if not is_instance_valid(entry):
			continue
		var ship: Ship = entry
		if ship == selected or not ship.alive:
			continue
		var station_local: Vector2 = ESCORT_STATIONS[station_index % ESCORT_STATIONS.size()]
		station_index += 1

		var station: Vector2 = (
			selected.global_position
			+ leader_right * station_local.x * selected.stats.hull_radius
			+ leader_forward * -station_local.y * selected.stats.hull_radius
		)
		# An escort that is already fighting keeps fighting; station-keeping is
		# what it does when it has nothing better to do.
		if ship.target != null and is_instance_valid(ship.target):
			continue
		if not ship.has_nav_target or ship.nav_target.distance_to(station) > ESCORT_REORDER_DISTANCE:
			ship.set_course(station)


# --- Intents ---------------------------------------------------------------

func _on_intent_move(world_pos: Vector2) -> void:
	if selected == null or not is_instance_valid(selected):
		return
	selected.set_course(world_pos)
	# A movement order cancels a fire order. Tapping the sea means disengage.
	selected.set_target(null)


func _on_intent_target(entity: Node2D) -> void:
	if selected == null or not is_instance_valid(selected):
		return
	selected.set_target(entity)
	# The rest of the fleet concentrates fire on the same enemy, which is the
	# only fleet-level tactic a one-thumb interface can express.
	for entry: Variant in ships:
		if not is_instance_valid(entry):
			continue
		var ship: Ship = entry
		if ship != selected and ship.alive:
			ship.set_target(entity)


func _on_intent_select(ship: Node2D) -> void:
	if ship is Ship and ships.has(ship):
		_select(ship as Ship)


func _on_intent_cycle_ammo() -> void:
	GameState.selected_ammo = AmmoLibrary.next_available(GameState.selected_ammo)
	var ammo: AmmoType = AmmoLibrary.get_ammo(GameState.selected_ammo)
	for entry: Variant in ships:
		if is_instance_valid(entry):
			(entry as Ship).loaded_ammo = ammo
	Audio.play_ui(&"ui_tap")


func select_next() -> void:
	var alive_ships: Array[Ship] = living_ships()
	if alive_ships.size() <= 1:
		return
	var idx: int = alive_ships.find(selected)
	_select(alive_ships[(idx + 1) % alive_ships.size()])


func _select(ship: Ship) -> void:
	for entry: Variant in ships:
		if is_instance_valid(entry):
			(entry as Ship).selected = entry == ship
	selected = ship
	selection_changed.emit(ship)


# --- Queries ---------------------------------------------------------------

func living_ships() -> Array[Ship]:
	# Untyped read: a freed hull assigned to a typed variable raises before the
	# validity check, and this is the hottest such loop in the game.
	var out: Array[Ship] = []
	for entry: Variant in ships:
		if is_instance_valid(entry) and (entry as Ship).alive:
			out.append(entry)
	return out


## Centre of the living fleet. This is what the camera follows.
func centroid() -> Vector2:
	var alive_ships: Array[Ship] = living_ships()
	if alive_ships.is_empty():
		return _spawn_origin
	var sum := Vector2.ZERO
	for ship: Ship in alive_ships:
		sum += ship.global_position
	return sum / float(alive_ships.size())


## Rebuilds every hull from [GameState], keeping each one where it was.
##
## Called when leaving a port. Without it, buying a Sloop leaves you sailing the
## Dinghy you arrived in until the next voyage — the reward is invisible at exactly
## the moment the player is looking for it, which is the worst possible moment for
## a reward to be invisible.
##
## Replacing the node rather than editing its stats in place is deliberate: a new
## hull changes sprite, scale, collision radius and propulsion, and rebuilding is
## far less error-prone than remembering to re-derive all of it.
func refit() -> void:
	var placements: Array[Transform2D] = []
	for ship: Ship in living_ships():
		placements.append(ship.global_transform)
		ship.queue_free()
	ships.clear()
	selected = null

	for i: int in GameState.fleet.size():
		var entry: Dictionary = GameState.fleet[i]
		var at: Vector2 = _spawn_origin
		var facing: float = 0.0
		if i < placements.size():
			at = placements[i].origin
			facing = placements[i].get_rotation()
		elif not placements.is_empty():
			# A hull the fleet did not arrive with — a slot bought in this port. It has
			# to appear *here*, alongside the flagship, not at `_spawn_origin`, which is
			# where the voyage began and may be the far side of the archipelago. Buying a
			# second ship and watching it fail to exist is the worst possible payoff for
			# the most expensive thing in the shop.
			var lead: Transform2D = placements[0]
			facing = lead.get_rotation()
			var abeam: Vector2 = Vector2.RIGHT.rotated(facing) * 240.0
			at = lead.origin + abeam * (1.0 if i % 2 == 1 else -1.0) - Vector2.UP.rotated(facing) * 120.0
		var ship: Ship = _spawn_ship(
			entry.get("stats_id", GameState.STARTING_HULL), entry.get("upgrades", {}), at
		)
		ship.rotation = facing

	if not ships.is_empty():
		_select(ships[0])
	EventBus.fleet_changed.emit()


func repair_all() -> void:
	for ship: Ship in living_ships():
		ship.repair_all()


func _on_ship_died(_killer: Node2D, ship: Ship) -> void:
	# Drop the hull from the roster as well as from the world. `ships` and
	# `GameState.fleet` are built in lockstep by spawn_fleet and refit, so the index
	# is shared — and it has to be taken *before* the erase below.
	#
	# Without this a sunk ship is only cosmetically lost: the entry survives in the
	# save, and the next call to refit (any port visit) hands it back, free. That was
	# invisible while the fleet was capped at one hull, because losing your only ship
	# ends the voyage before any port can rebuild it.
	var slot: int = ships.find(ship)
	if slot >= 0 and slot < GameState.fleet.size():
		GameState.fleet.remove_at(slot)
	ships.erase(ship)
	# Unbanked gold goes down with the hull that carried it. That is the whole
	# reason banking at a port is a decision.
	GameState.lose_carried_gold()

	var remaining: Array[Ship] = living_ships()
	if remaining.is_empty():
		selected = null
		fleet_emptied.emit()
		EventBus.fleet_wiped.emit()
	elif selected == ship or selected == null:
		_select(remaining[0])

	EventBus.fleet_changed.emit()
