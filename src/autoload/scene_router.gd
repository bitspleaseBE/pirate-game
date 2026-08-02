extends Node
## Scene transitions with a fade, and one place that knows every scene path.
##
## Also the place that tears down world-scoped global state. Forgetting to clear
## the grid and the culling registry between scenes is the classic source of
## "the game slows down every time you restart" — so it happens here, once,
## instead of in every scene's `_exit_tree`.

const SCENES: Dictionary = {
	&"boot": "res://src/scenes/boot.tscn",
	&"main_menu": "res://src/scenes/main_menu.tscn",
	&"voyage": "res://src/scenes/voyage.tscn",
}

const FADE_SEC: float = 0.28

signal transition_started(to: StringName)
signal transition_finished(to: StringName)

var current: StringName = &""

var _fade: ColorRect
var _busy: bool = false
## A transition asked for while one was already running. Queued rather than
## dropped — see [method goto].
var _pending: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var layer := CanvasLayer.new()
	layer.name = "TransitionLayer"
	# Above gameplay and HUD, below the debug overlay.
	layer.layer = 100
	add_child(layer)

	_fade = ColorRect.new()
	_fade.color = Color(0.043, 0.114, 0.176, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_fade.visible = false
	layer.add_child(_fade)


func goto(key: StringName) -> void:
	if not SCENES.has(key):
		Log.error("Unknown scene key '%s'" % key, "Router")
		return

	# Queue rather than drop. A scene's `_ready` runs *inside* the previous
	# transition, so anything that routes on load — an auto-start flag, a
	# "continue" that lands straight in the world — would be silently swallowed.
	# So would a player double-tapping a menu button. Silently ignoring a
	# navigation request is the kind of bug that looks like a frozen game.
	if _busy:
		_pending = key
		return

	_transition(key)


func reload_current() -> void:
	if current != &"":
		goto(current)


func _transition(key: StringName) -> void:
	_busy = true
	transition_started.emit(key)

	# Block input during the fade so a stray tap cannot double-trigger.
	_fade.visible = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var fade_out: Tween = create_tween()
	fade_out.tween_property(_fade, "modulate:a", 1.0, FADE_SEC)
	await fade_out.finished

	_teardown_world_state()

	var err: Error = get_tree().change_scene_to_file(SCENES[key])
	if err != OK:
		Log.error("Failed to load scene '%s' (error %d)" % [key, err], "Router")
	else:
		current = key

	# One frame for the new scene to enter the tree and register its camera.
	await get_tree().process_frame

	var fade_in: Tween = create_tween()
	fade_in.tween_property(_fade, "modulate:a", 0.0, FADE_SEC)
	await fade_in.finished
	_fade.visible = false
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_busy = false
	transition_finished.emit(key)

	if _pending != &"":
		var queued: StringName = _pending
		_pending = &""
		_transition(queued)


func _teardown_world_state() -> void:
	Cull.clear()
	Cull.camera = null
	Grid.clear()
	Pools.set_world_root(null)
	Audio.stop_music()
