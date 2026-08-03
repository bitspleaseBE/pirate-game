extends CanvasLayer
## Gameplay HUD.
##
## Everything reachable with one thumb: the ammo cycle button sits bottom-right
## where a right thumb rests, the minimap bottom-left, and the counters top-left
## out of the way of both. No control sits in the middle third of the screen,
## because that is where the player taps to sail.
##
## The layout lives in `hud.tscn`; this script only wires it to state.
##
## Two typefaces, split by job, both defined as FontVariations in the scene:
##
## - **Cinzel** (`Font_label`) for the tags — GOLD, DBL, FLEET, the ammo name.
##   A Roman inscriptional face cut for stone and ship's nameplates, so it
##   carries the period without costing anything: these are short all-caps
##   words the player recognises by shape, never reads letter by letter.
## - **Alegreya** (`Font_number`, `Font_body`) for everything the player
##   actually has to read — the counters and the toast. `tnum` puts the digits
##   on a fixed pitch so a gold tally does not shuffle sideways as it ticks up.
##
## The old Kenney Future was a wide geometric display face: thin at 14 px over
## a moving ocean, and its zero was a plain rounded rectangle, so "GOLD 0" read
## as a missing glyph.

const TOAST_DURATION: float = 2.6
## How often the range to the hideout is recomputed. It is a number the player
## glances at between decisions, not one they steer by, so twice a second is
## generous and a per-frame distance check is pure waste.
const HIDEOUT_REFRESH: float = 0.5

const ICON_ANCHOR: Texture2D = preload("res://assets/wave1/icons/icon_anchor.png")

@onready var _gold_label: Label = %GoldLabel
@onready var _diamond_label: Label = %DiamondLabel
@onready var _ammo_button: Button = %AmmoButton
@onready var _ammo_count: Label = %AmmoCount
@onready var _fleet_label: Label = %FleetLabel
@onready var _fleet_button: Button = %FleetButton
@onready var _hideout_button: Button = %HideoutButton
@onready var _toast: Label = %Toast
@onready var minimap: Minimap = %Minimap
@onready var _root: Control = $Root

var _toast_left: float = 0.0
var _hideout_left: float = 0.0
var _wind_indicator: WindIndicator
var _fleet: FleetController = null
var _archipelago: Archipelago = null


func _ready() -> void:
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.diamonds_changed.connect(_on_diamonds_changed)
	EventBus.fleet_changed.connect(_refresh_fleet)
	EventBus.island_captured.connect(_on_island_captured)
	EventBus.island_discovered.connect(_on_island_discovered)
	EventBus.treasure_dug.connect(_on_treasure_dug)
	EventBus.ship_sunk.connect(_on_ship_sunk)

	_ammo_button.pressed.connect(_on_ammo_pressed)
	Wave1UI.apply_brass(_ammo_button)
	_hideout_button.pressed.connect(_on_hideout_pressed)
	Wave1UI.apply_brass(_hideout_button)
	Wave1UI.set_icon(_hideout_button, ICON_ANCHOR, 26)
	_fleet_button.pressed.connect(_on_fleet_pressed)

	_build_wind_indicator()
	_refresh_all()
	_toast.modulate.a = 0.0


## Called by the voyage scene once the world exists.
func bind(fleet: FleetController, archipelago: Archipelago) -> void:
	_fleet = fleet
	_archipelago = archipelago
	minimap.fleet = fleet
	minimap.archipelago = archipelago
	_wind_indicator.fleet = fleet
	fleet.selection_changed.connect(_on_selection_changed)
	_refresh_all()
	_refresh_hideout()


## The toast fades on its own, and the range home ticks over.
##
## Pauses with the world, which is what you want for both: a toast should not
## time out while the player is reading a briefing over the top of it, and the
## fleet is not moving, so neither is the range home.
func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		# Hold it solid for most of its life, then fade over the last half second:
		# a toast that starts fading immediately reads as already leaving.
		_toast.modulate.a = clampf(_toast_left * 2.0, 0.0, 1.0)

	_hideout_left -= delta
	if _hideout_left <= 0.0:
		_hideout_left = HIDEOUT_REFRESH
		_refresh_hideout()


func _build_wind_indicator() -> void:
	_wind_indicator = WindIndicator.new()
	_wind_indicator.name = "WindIndicator"
	# Top-right, clear of the counters and out of the thumb's way.
	_wind_indicator.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_wind_indicator.offset_left = -108.0
	_wind_indicator.offset_top = 14.0
	_wind_indicator.offset_right = -16.0
	_wind_indicator.offset_bottom = 106.0
	_root.add_child(_wind_indicator)


## Shows a briefing modal and returns it, so the caller can await `dismissed`.
## Returns null if one is already up — two modals at once is worse than either.
func show_briefing(
	title: String, lines: PackedStringArray, button_text: String = "GOT IT"
) -> BriefingPanel:
	if get_node_or_null(^"Briefing") != null:
		return null
	var panel := BriefingPanel.new()
	panel.name = "Briefing"
	# Runs while the tree is paused, so its own button still works when it has
	# stopped the world.
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(panel)
	panel.present(title, lines, button_text)
	return panel


## Closes any open briefing. Used by the screenshot harness, and as a guarantee
## that nothing can leave the game paused behind a modal.
func dismiss_briefing() -> bool:
	var panel: BriefingPanel = get_node_or_null(^"Briefing") as BriefingPanel
	if panel == null:
		return false
	panel.force_dismiss()
	return true


## Opens the port. Returns null if a modal is already up.
func show_port(island_name: String) -> PortScreen:
	if get_node_or_null(^"Port") != null or get_node_or_null(^"Briefing") != null:
		return null
	var screen := PortScreen.new()
	screen.name = "Port"
	screen.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(screen)
	screen.present(island_name)
	return screen


func dismiss_port() -> bool:
	var screen: PortScreen = get_node_or_null(^"Port") as PortScreen
	if screen == null:
		return false
	screen.force_close()
	return true


## Opens the fleet roster. Returns null if a modal is already up.
func show_fleet() -> FleetPanel:
	if (
		_fleet == null
		or get_node_or_null(^"Fleet") != null
		or get_node_or_null(^"Port") != null
		or get_node_or_null(^"Briefing") != null
	):
		return null
	var panel := FleetPanel.new()
	panel.name = "Fleet"
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(panel)
	panel.present(_fleet)
	return panel


func dismiss_fleet() -> bool:
	var panel: FleetPanel = get_node_or_null(^"Fleet") as FleetPanel
	if panel == null:
		return false
	panel.force_close()
	return true


func _refresh_all() -> void:
	_on_gold_changed(GameState.total_gold(), 0)
	_on_diamonds_changed(GameState.diamonds, 0)
	_refresh_ammo()
	_refresh_fleet()


## The ammo button carries the shot's *purpose*, not just its name.
##
## Five options behind one cycle button is only a decision if the player can tell
## what each one is for. "Chain Shot" teaches nothing; "shreds sails" teaches the
## whole mechanic. The colour matches the ball in flight, so the button and the
## thing it fires are visibly the same object.
func _refresh_ammo() -> void:
	var ammo: AmmoType = AmmoLibrary.get_ammo(GameState.selected_ammo)
	_ammo_button.text = "%s\n%s" % [ammo.display_name, ammo.role]
	if ammo.icon != null:
		Wave1UI.set_icon(_ammo_button, ammo.icon, 38)
	_ammo_button.add_theme_color_override("font_color", ammo.tint)
	_ammo_count.add_theme_color_override("font_color", ammo.tint)
	if ammo.unlimited:
		_ammo_count.text = "∞"
	else:
		var stock: int = GameState.get_ammo(ammo.id)
		_ammo_count.text = "%d left" % stock


## "hulls afloat / hulls owned".
##
## Counted off the fleet controller, not off `GameState.fleet`. The roster is the
## ships you own; only the controller knows which of them are still floating, and
## the whole point of the readout is to tell you when one is not. Counting the
## roster made this a constant "1 / 1" that could never report a loss — harmless
## while the fleet was capped at one hull, wrong the moment a second one exists.
##
## The denominator is the roster rather than [member GameState.fleet_slots].
## Slots are a permanent purchase and never fall, so a fleet of one that owns
## three slots read "1 / 3" for the rest of the run and looked like two ships had
## sunk. What the player wants to know is how many of the hulls they have are
## still under them.
##
## Two numbers can only ever be two numbers, though, and buying a second ship
## moves the second one silently — see [FleetPanel], which the badge opens.
func _refresh_fleet() -> void:
	var owned: int = GameState.fleet.size()
	var afloat: int = owned
	if _fleet != null and is_instance_valid(_fleet):
		afloat = _fleet.living_ships().size()
	_fleet_label.text = "%d / %d" % [afloat, owned]


func show_toast(text: String) -> void:
	_toast.text = text
	_toast_left = TOAST_DURATION
	_toast.modulate.a = 1.0


func _on_gold_changed(total: int, _delta: int) -> void:
	_gold_label.text = str(total)


func _on_diamonds_changed(total: int, _delta: int) -> void:
	_diamond_label.text = str(total)


func _on_ammo_pressed() -> void:
	EventBus.intent_cycle_ammo.emit()
	_refresh_ammo()


func _on_fleet_pressed() -> void:
	Audio.play_ui(&"ui_tap")
	show_fleet()


## Sets a course for home. The button carries the range, which is the other half
## of the decision — "push one more island or go and bank it" is not a decision
## the player can weigh without knowing how far back it is.
func _on_hideout_pressed() -> void:
	Audio.play_ui(&"ui_confirm")
	EventBus.intent_sail_home.emit()


func _refresh_hideout() -> void:
	var home: Island = null
	if _archipelago != null and is_instance_valid(_archipelago):
		home = _archipelago.home
	if home == null or _fleet == null or not is_instance_valid(_fleet):
		_hideout_button.text = "Hideout"
		_hideout_button.disabled = home == null
		return

	var range_home: float = maxf(0.0, home.distance_to_coast(_fleet.centroid()))
	_hideout_button.disabled = false
	_hideout_button.text = "Hideout\n%s" % _range_text(range_home)


## Metres up to a kilometre, then kilometres to one decimal. A four-figure number
## on a button is read as "a lot" rather than as a distance.
func _range_text(metres: float) -> String:
	if metres < 1000.0:
		return "%d m" % roundi(metres)
	return "%.1f km" % (metres / 1000.0)


func _on_selection_changed(ship: Node2D) -> void:
	if ship is Ship:
		show_toast("%s selected" % (ship as Ship).stats.display_name)


func _on_island_discovered(island: Node2D) -> void:
	show_toast("Land ho — %s" % (island as Island).def.display_name)


func _on_island_captured(island: Node2D) -> void:
	show_toast("%s captured!" % (island as Island).def.display_name)


func _on_treasure_dug(_island: Node2D, loot: Dictionary) -> void:
	var parts: PackedStringArray = []
	for kind: StringName in loot:
		parts.append("%s x%d" % [String(kind).capitalize(), int(loot[kind])])
	show_toast("Treasure! " + ", ".join(parts))
	_refresh_ammo()


## "Ship lost!" is for losing *a* ship, not for losing the last one.
##
## [method Ship._sink] emits `died` before `ship_sunk`, and `died` is what walks
## through FleetController into the voyage's game-over handler — so by the time
## this runs the "your fleet is lost, this much gold is safe ashore" toast has
## already been posted, and showing another one here silently replaced it. There
## is only one toast slot, so the wipe read as an unexplained trip back to the
## menu with the player's gold apparently untouched. The last hull is the one
## moment the smaller message has nothing to add.
func _on_ship_sunk(ship: Node2D, _killer: Node2D) -> void:
	if ship is Ship and (ship as Ship).team == Teams.PLAYER:
		var fleet_alive: bool = (
			_fleet != null and is_instance_valid(_fleet) and not _fleet.living_ships().is_empty()
		)
		if fleet_alive:
			show_toast("Ship lost!")
	_refresh_fleet()
