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
func spawn_fleet(origin: Vector2) -> void:
	_spawn_origin = origin
	for i: int in GameState.fleet.size():
		var entry: Dictionary = GameState.fleet[i]
		var stats_id: StringName = entry.get("stats_id", &"sloop")
		var offset := Vector2(float(i) * 260.0 - float(GameState.fleet.size() - 1) * 130.0, 0.0)
		_spawn_ship(stats_id, origin + offset)

	if not ships.is_empty():
		_select(ships[0])
	EventBus.fleet_changed.emit()


func _spawn_ship(stats_id: StringName, at: Vector2) -> Ship:
	var ship: Ship = SHIP_SCENE.instantiate() as Ship
	ship.stats = ShipStatsLibrary.get_stats(stats_id)
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
	for ship: Ship in ships:
		if ship != selected and is_instance_valid(ship) and ship.alive:
			ship.set_target(entity)


func _on_intent_select(ship: Node2D) -> void:
	if ship is Ship and ships.has(ship):
		_select(ship as Ship)


func _on_intent_cycle_ammo() -> void:
	GameState.selected_ammo = AmmoLibrary.next_available(GameState.selected_ammo)
	var ammo: AmmoType = AmmoLibrary.get_ammo(GameState.selected_ammo)
	for ship: Ship in ships:
		if is_instance_valid(ship):
			ship.loaded_ammo = ammo
	Audio.play_ui(&"ui_tap")


func select_next() -> void:
	var alive_ships: Array[Ship] = living_ships()
	if alive_ships.size() <= 1:
		return
	var idx: int = alive_ships.find(selected)
	_select(alive_ships[(idx + 1) % alive_ships.size()])


func _select(ship: Ship) -> void:
	for other: Ship in ships:
		if is_instance_valid(other):
			other.selected = other == ship
	selected = ship
	selection_changed.emit(ship)


# --- Queries ---------------------------------------------------------------

func living_ships() -> Array[Ship]:
	var out: Array[Ship] = []
	for ship: Ship in ships:
		if is_instance_valid(ship) and ship.alive:
			out.append(ship)
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


func repair_all() -> void:
	for ship: Ship in living_ships():
		ship.repair_all()


func _on_ship_died(_killer: Node2D, ship: Ship) -> void:
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
