extends CanvasLayer
## Gameplay HUD.
##
## Everything reachable with one thumb: the ammo cycle button sits bottom-right
## where a right thumb rests, the minimap bottom-left, and the counters top-left
## out of the way of both. No control sits in the middle third of the screen,
## because that is where the player taps to sail.
##
## The layout lives in `hud.tscn`; this script only wires it to state.

const TOAST_DURATION: float = 2.6

@onready var _gold_label: Label = %GoldLabel
@onready var _doubloon_label: Label = %DoubloonLabel
@onready var _ammo_button: Button = %AmmoButton
@onready var _ammo_count: Label = %AmmoCount
@onready var _fleet_label: Label = %FleetLabel
@onready var _toast: Label = %Toast
@onready var minimap: Minimap = %Minimap
@onready var _root: Control = $Root

var _toast_left: float = 0.0
var _wind_indicator: WindIndicator


func _ready() -> void:
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.doubloons_changed.connect(_on_doubloons_changed)
	EventBus.fleet_changed.connect(_refresh_fleet)
	EventBus.island_captured.connect(_on_island_captured)
	EventBus.island_discovered.connect(_on_island_discovered)
	EventBus.treasure_dug.connect(_on_treasure_dug)
	EventBus.ship_sunk.connect(_on_ship_sunk)

	_ammo_button.pressed.connect(_on_ammo_pressed)

	_build_wind_indicator()
	_refresh_all()
	_toast.modulate.a = 0.0


## Called by the voyage scene once the world exists.
func bind(fleet: FleetController, archipelago: Archipelago) -> void:
	minimap.fleet = fleet
	minimap.archipelago = archipelago
	_wind_indicator.fleet = fleet
	fleet.selection_changed.connect(_on_selection_changed)
	_refresh_all()


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


func _refresh_all() -> void:
	_on_gold_changed(GameState.total_gold(), 0)
	_on_doubloons_changed(GameState.doubloons, 0)
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
	_ammo_button.add_theme_color_override("font_color", ammo.tint)
	_ammo_count.add_theme_color_override("font_color", ammo.tint)
	if ammo.unlimited:
		_ammo_count.text = "∞"
	else:
		var stock: int = GameState.get_ammo(ammo.id)
		_ammo_count.text = "%d left" % stock


func _refresh_fleet() -> void:
	var alive: int = 0
	for entry: Dictionary in GameState.fleet:
		alive += 1
	_fleet_label.text = "%d / %d" % [alive, GameState.fleet_slots]


func show_toast(text: String) -> void:
	_toast.text = text
	_toast_left = TOAST_DURATION
	_toast.modulate.a = 1.0


func _on_gold_changed(total: int, _delta: int) -> void:
	_gold_label.text = str(total)


func _on_doubloons_changed(total: int, _delta: int) -> void:
	_doubloon_label.text = str(total)


func _on_ammo_pressed() -> void:
	EventBus.intent_cycle_ammo.emit()
	_refresh_ammo()


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


func _on_ship_sunk(ship: Node2D, _killer: Node2D) -> void:
	if ship is Ship and (ship as Ship).team == Teams.PLAYER:
		show_toast("Ship lost!")
	_refresh_fleet()
