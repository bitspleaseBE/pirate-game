extends Node
## Keeps the interface a readable, tappable size on whatever glass the game is on.
##
## One line of work, done in one place, for the whole game: the window's
## `content_scale_factor` is set to [method Wave1UI.ui_scale], which makes one UI
## unit one CSS pixel on any screen smaller than the design. Every Control in
## every scene follows from that — the HUD, the port, the roster, the title
## screen — with no per-screen plumbing and no second scaling mechanism to keep in
## step with this one.
##
## An autoload rather than a call in each scene root, because the trigger is a
## window event and the window outlives every scene. A phone turned on its side
## has to relayout, and so does a desktop window dragged narrow; both arrive as
## `size_changed` on the root window, which no scene is guaranteed to be alive
## for.
##
## Deliberately *not* applied to the world. The world renders into a SubViewport
## sized from the same canvas, so scaling the UI up does drop its render
## resolution on a phone — which is the trade this makes knowingly and in the
## direction the rest of the architecture already leans: the SubViewport exists to
## buy fill rate (see the header of `voyage.gd`), a phone browser on GL
## Compatibility has very little of it, and an unreadable HUD is a broken game
## while a slightly softer sea is not. Camera framing is unaffected: [GameCamera]
## resolves its zoom against the viewport height, so the canvas and the zoom move
## together and the player sees the same amount of sea either way.


func _ready() -> void:
	var window: Window = get_window()
	if window == null:
		return
	window.size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	# Assigning the factor resizes the viewport, which raises `size_changed`
	# again. [method Wave1UI.apply_ui_scale] only writes when the value actually
	# changes, which is what stops that from being a loop.
	Wave1UI.apply_ui_scale(get_window())
