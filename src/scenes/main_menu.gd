extends Control
## Title screen.
##
## Also the only place the player can override the graphics tier, which matters
## more than usual here: the adaptive controller is good at catching a slow
## device but cannot know that someone is on a train with a hot phone and would
## rather have LOW than watch it thermal-throttle.

@onready var _continue_button: Button = %ContinueButton
@onready var _new_button: Button = %NewVoyageButton
@onready var _quality_button: Button = %QualityButton
@onready var _version_label: Label = %VersionLabel
@onready var _stats_label: Label = %StatsLabel


func _ready() -> void:
	for button: Button in [_new_button, _continue_button, _quality_button]:
		Wave1UI.apply_brass(button)
	# One icon size, because the three buttons are now one height. The brass
	# stylebox is a horizontal-only 9-slice, so its vertical band stretches to
	# whatever height the button is: three different heights meant three
	# different stretches of the same bevel, which read as a bug rather than as
	# hierarchy. New Voyage is the primary action by being first and by being the
	# only lit button when there is no save to continue.
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
