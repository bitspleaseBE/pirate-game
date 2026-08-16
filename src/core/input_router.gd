class_name InputRouter
extends Node
## The only place in the game that reads raw pointer input.
##
## Everything downstream listens for intents on [EventBus] instead. That is what
## makes it possible to add a virtual joystick, gamepad support, a tutorial that
## fakes input, or a replay system later without touching a line of gameplay code.
##
## Mouse and touch are normalised here into one pointer model rather than relying
## on Godot's `emulate_touch_from_mouse`: that setting is applied per-Viewport, and
## the world lives inside a SubViewport, so depending on it makes desktop and
## device behaviour diverge in ways that are painful to debug.
##
## Gesture rules, in priority order:
##   two pointers      → pinch zoom
##   one pointer moved → pan the camera (snaps back on release)
##   one pointer tap   → pick
##
## The pick order matters: a tap near your own ship always selects it, even if an
## enemy is slightly closer. Selecting is recoverable; firing at the wrong thing
## is not.

## A press that moves further than this becomes a pan, not a tap.
const TAP_MAX_MOVE: float = 20.0
## A press held longer than this is not a tap either.
const TAP_MAX_TIME: float = 0.4
## Pick radii in world units — generous, because fingers are imprecise.
const PICK_RADIUS_SHIP: float = 130.0
const PICK_RADIUS_ENEMY: float = 150.0
## Pinch must change by this fraction before it counts, to avoid jitter.
const PINCH_DEADZONE: float = 0.02
const WHEEL_ZOOM_STEP: float = 1.12
## Pointer index used for the mouse, kept out of the touch index range.
const MOUSE_INDEX: int = -1

@export var camera: GameCamera
## Set by the voyage scene. Used only to resolve a tap to reachable water.
var fleet: FleetController = null

var enabled: bool = true

var _pointers: Dictionary = {}  # index -> { start: Vector2, current: Vector2, time: float }
var _pinch_reference: float = 0.0
var _gesture_is_pinch: bool = false
var _gesture_is_pan: bool = false


func _process(delta: float) -> void:
	for index: int in _pointers:
		_pointers[index]["time"] = float(_pointers[index]["time"]) + delta


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or camera == null:
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_pointer_down(touch.index, touch.position)
		else:
			_pointer_up(touch.index, touch.position)

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_pointer_move(drag.index, drag.position, drag.relative)

	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					_pointer_down(MOUSE_INDEX, button.position)
				else:
					_pointer_up(MOUSE_INDEX, button.position)
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					camera.apply_zoom(WHEEL_ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					camera.apply_zoom(1.0 / WHEEL_ZOOM_STEP)

	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _pointers.has(MOUSE_INDEX):
			_pointer_move(MOUSE_INDEX, motion.position, motion.relative)

	elif event.is_action_pressed(&"zoom_in"):
		camera.apply_zoom(WHEEL_ZOOM_STEP)
	elif event.is_action_pressed(&"zoom_out"):
		camera.apply_zoom(1.0 / WHEEL_ZOOM_STEP)


# --- Normalised pointer model ----------------------------------------------

func _pointer_down(index: int, pos: Vector2) -> void:
	_pointers[index] = {"start": pos, "current": pos, "time": 0.0}
	if _pointers.size() == 2:
		_gesture_is_pinch = true
		_pinch_reference = _pointer_distance()


func _pointer_move(index: int, pos: Vector2, relative: Vector2) -> void:
	if not _pointers.has(index):
		return
	_pointers[index]["current"] = pos

	if _gesture_is_pinch and _pointers.size() >= 2:
		var distance: float = _pointer_distance()
		if _pinch_reference > 1.0 and distance > 1.0:
			var ratio: float = distance / _pinch_reference
			if absf(ratio - 1.0) > PINCH_DEADZONE:
				camera.apply_zoom(ratio)
				_pinch_reference = distance
		return

	if not _gesture_is_pan:
		# Stay a candidate tap until the pointer has clearly travelled.
		if _pointers[index]["start"].distance_to(pos) <= TAP_MAX_MOVE:
			return
		_gesture_is_pan = true
	camera.apply_pan(relative)


func _pointer_up(index: int, pos: Vector2) -> void:
	var record: Dictionary = _pointers.get(index, {})
	_pointers.erase(index)

	# A tap only fires when this gesture never became a pan or a pinch. Checking
	# the flags rather than just the distance is what stops the second finger of
	# a pinch from registering as a tap when it lifts.
	if not record.is_empty() and not _gesture_is_pan and not _gesture_is_pinch:
		var moved: float = record["start"].distance_to(record["current"])
		if moved <= TAP_MAX_MOVE and float(record["time"]) <= TAP_MAX_TIME:
			_tap(pos)

	if _pointers.is_empty():
		_gesture_is_pinch = false
		_gesture_is_pan = false


func _pointer_distance() -> float:
	var points: Array = _pointers.values()
	if points.size() < 2:
		return 0.0
	return (points[0]["current"] as Vector2).distance_to(points[1]["current"] as Vector2)


# --- Picking ---------------------------------------------------------------

func _tap(screen_pos: Vector2) -> void:
	var world: Vector2 = camera.screen_to_world(screen_pos)

	var own_ship: Node2D = Grid.query_nearest(
		world, PICK_RADIUS_SHIP, SpatialGrid.KIND_PLAYER_SHIP
	)
	if own_ship != null:
		EventBus.intent_select_ship.emit(own_ship)
		Audio.play_ui(&"ui_tap")
		return

	var hostile: Node2D = Grid.query_nearest(
		world, PICK_RADIUS_ENEMY, SpatialGrid.KIND_ENEMY_SHIP | SpatialGrid.KIND_STRUCTURE
	)
	if hostile != null:
		# Tapping the enemy you are already engaging breaks off. Since a course
		# order no longer clears the target — steering yourself must not mean
		# holstering your guns — this is the gesture that does, and putting it on
		# the target itself keeps it where the player is already looking.
		if _is_current_target(hostile):
			EventBus.intent_target.emit(null)
			Audio.play_ui(&"ui_tap")
		else:
			EventBus.intent_target.emit(hostile)
			Audio.play_ui(&"ui_confirm")
		return

	var island: Island = _island_at(world)
	if island != null and island.is_captured:
		# Treasure first, port second. An island you hold with gold still buried on
		# it has exactly one thing the player wants from it, and opening a shop
		# instead is the one interaction in the game with no visible way back out:
		# the landing party is otherwise only triggered by drifting near an
		# unmarked point off the beach, which nobody finds twice.
		if island.def.is_treasure_remaining():
			EventBus.intent_dig.emit(island)
		else:
			EventBus.intent_open_port.emit(island)
		return

	# Snap the order to water the fleet can actually settle in, rather than
	# emitting a destination inside an island and leaving the ship to fight its
	# own avoidance forever. The marker the player sees is the point the ship is
	# really going to, so a tap on land reads as "as close as I can get" instead
	# of as a bug.
	EventBus.intent_move.emit(_nearest_navigable(world))


## Nearest point to `world` that the selected ship can hold station at.
##
## Uses the selected hull rather than searching the grid: the keep-out ring
## depends on hull radius, and a grid query wide enough to always find a ship
## would sweep the whole world (see [constant SpatialGrid.MAX_QUERY_CELLS]).
func _nearest_navigable(world: Vector2) -> Vector2:
	if fleet == null or not is_instance_valid(fleet):
		return world
	var ship: Ship = fleet.selected
	if ship == null or not is_instance_valid(ship):
		return world
	return ship.clamp_to_navigable(world)


func _is_current_target(entity: Node2D) -> bool:
	if fleet == null or not is_instance_valid(fleet):
		return false
	var ship: Ship = fleet.selected
	return ship != null and is_instance_valid(ship) and ship.target == entity


func _island_at(world: Vector2) -> Island:
	for node: Node2D in Grid.query_radius(world, 8.0, SpatialGrid.KIND_ISLAND):
		var island := node as Island
		if island != null and island.contains_point(world):
			return island
	return null
