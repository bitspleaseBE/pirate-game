extends Control
## Title screen.
##
## Also the only place the player can override the graphics tier, which matters
## more than usual here: the adaptive controller is good at catching a slow
## device but cannot know that someone is on a train with a hot phone and would
## rather have LOW than watch it thermal-throttle.
##
## Typography follows the HUD's split by job rather than by screen, and the
## `FontVariation`s it needs are defined in `main_menu.tscn`:
##
## - **Cinzel** for the title lockup, on the same grounds the HUD uses it for its
##   tags: a Roman inscriptional face cut for stone and ship's nameplates, so it
##   carries the period on words recognised by shape rather than read. Two
##   weights — the wordmark takes the top of the axis, the kicker under it is
##   spaced wider and left lighter, so the pair reads as one lockup rather than
##   two competing headings.
## - **Alegreya** for the buttons and the small print — the only lines here
##   actually read — which is also what the port screen puts on its buttons, so
##   the two screens of buttons in this game share a face.
##
## Kenney Future is gone from this scene, and it was the last of it: a wide
## geometric display face, thin at 11 px over a dark field. See hud.gd.
##
## **A trap worth knowing about**, because it cost a round of head-scratching:
## a `FontVariation`'s `variation_opentype` and `opentype_features` keys must be
## the raw 32-bit OpenType tags, *not* the strings. `{"wght": 900}` parses, saves
## and reloads without a single complaint, and is then silently ignored — renders
## at 400 and 900 came out byte-identical until the keys became integers. Hence
## `2003265652` (`wght`) and `1819178349` (`lnum`) in the scene. `hud.tscn` still
## has the string form, so its three fonts have never applied their weights.

@onready var _continue_button: Button = %ContinueButton
@onready var _new_button: Button = %NewVoyageButton
@onready var _quality_button: Button = %QualityButton
@onready var _version_label: Label = %VersionLabel
@onready var _stats_label: Label = %StatsLabel


## Padding inside a menu button, matching the solid primary's own margin so the
## two treatments sit at the same internal rhythm.
const BUTTON_PADDING: float = 10.0


func _ready() -> void:
	# The port screen's button vocabulary, not the brass sprite — see [Wave1UI].
	# The sprite is one fixed-height band, so it painted all three of these as the
	# same shape and left the menu with no hierarchy at all: "start a voyage" and
	# "change a graphics setting" looked like the same offer, and a Continue with
	# no save behind it looked merely dimmer rather than dead.
	#
	# Three tiers instead, which is the port's own reading of the same problem.
	# New Voyage is the one solid shape: it is the action, not a choice between
	# options, and it is the only button that is always live. Continue is the
	# featured card — the other headline, gold when there is a voyage to go back
	# to and visibly spent when there is not. Quality is a plain card, because a
	# settings toggle should never compete with either.
	Wave1UI.apply_primary(_new_button)
	Wave1UI.apply_card(_continue_button, true, BUTTON_PADDING)
	Wave1UI.apply_card(_quality_button, false, BUTTON_PADDING)

	# One icon size, because the three buttons are still one height. Hierarchy is
	# carried by the fill and the edge now, so it does not have to be faked with
	# three different heights of the same bevel.
	Wave1UI.set_icon(
		_new_button, preload("res://assets/wave1/icons/icon_chest.png"), 36
	)
	Wave1UI.set_icon(
		_continue_button, preload("res://assets/wave1/icons/icon_map.png"), 36
	)
	Wave1UI.set_icon(
		_quality_button, preload("res://assets/wave1/icons/icon_settings.png"), 36
	)

	_new_button.pressed.connect(_on_new_voyage)
	_continue_button.pressed.connect(_on_continue)
	_quality_button.pressed.connect(_on_cycle_quality)

	_continue_button.disabled = not (SaveSystem.has_save() and GameState.voyage_active)
	_version_label.text = "v%s · Godot %s" % [
		ProjectSettings.get_setting("application/config/version", "0.0.0"),
		Engine.get_version_info()["string"],
	]
	_refresh_quality()
	_refresh_stats()

	# Automation hooks. Running `voyage.tscn` directly skips boot, the save load
	# and this menu — which is exactly where entry-path bugs live, so the harness
	# needs a way in through the real front door.
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--auto-new" in args:
		call_deferred("_on_new_voyage")
	elif "--auto-continue" in args:
		call_deferred("_on_continue")
	elif "--shot-menu" in args:
		_capture_menu()


## Frames the title screen and writes it to `user://shots/`.
##
##   godot src/scenes/main_menu.tscn -- --shot-menu
##
## The menu is three buttons whose whole job is to be told apart at a glance, and
## whether they are is not something the smoke test can answer — only a rendered
## frame can. Both states go out: a fresh save has no voyage to continue, so the
## dead Continue that a first-time player actually meets would otherwise never be
## looked at.
func _capture_menu() -> void:
	var dir: String = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)

	for state: String in ["default", "continuable"]:
		if state == "continuable":
			_continue_button.disabled = false
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			"%s/menu_%s.png" % [dir, state]
		)

	print("MENU SHOT: %s" % ProjectSettings.globalize_path(dir))
	get_tree().quit(0)


func _refresh_quality() -> void:
	_quality_button.text = "Quality: %s%s" % [
		Quality.get_tier_name(), " (auto)" if Quality.auto_adapt else ""
	]


func _refresh_stats() -> void:
	_stats_label.text = "Banked %d gold · %d diamonds · %d islands taken" % [
		GameState.banked_gold, GameState.diamonds, GameState.stats_islands_captured
	]


func _on_new_voyage() -> void:
	Audio.play_ui(&"ui_confirm")
	# A new voyage keeps banked progress and rerolls the archipelago. Losing the
	# bank on every run would make the whole banking mechanic pointless.
	GameState.voyage_seed = 0
	GameState.island_progress.clear()
	GameState.carried_gold = 0
	Router.goto(&"voyage")


func _on_continue() -> void:
	Audio.play_ui(&"ui_confirm")
	Router.goto(&"voyage")


## Cycles LOW → MEDIUM → HIGH → auto, so the player can always get back to the
## adaptive behaviour without hunting for a separate toggle.
func _on_cycle_quality() -> void:
	Audio.play_ui(&"ui_tap")
	if not Quality.auto_adapt and Quality.tier == Quality.Tier.HIGH:
		Quality.resume_auto_adapt()
	else:
		var next: int = (int(Quality.tier) + 1) % 3 if not Quality.auto_adapt else int(Quality.Tier.LOW)
		Quality.set_tier_manual(next as Quality.Tier)
	SaveSystem.save_settings()
	_refresh_quality()
