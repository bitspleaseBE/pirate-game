extends Node
## First scene. Exists so the autoloads have one frame to finish initialising
## before anything tries to use them, and so there is a single place to put
## startup work (save load, feature detection) that must happen before the menu.

func _ready() -> void:
	Log.info(
		"Boot — Godot %s, %s, renderer %s"
		% [
			Engine.get_version_info()["string"],
			OS.get_name(),
			RenderingServer.get_video_adapter_name(),
		],
		"Boot"
	)

	if SaveSystem.has_save():
		SaveSystem.load_game()

	# One frame so every autoload's _ready has run and the quality tier is set
	# before the menu reads it.
	await get_tree().process_frame
	Router.goto(&"main_menu")
