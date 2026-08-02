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


## Shows the one-time wind explanation. `compass` is where the wind blows from.
func show_wind_intro(compass: String) -> void:
	var intro := WindIntro.new()
	intro.name = "WindIntro"
	# Above the rest of the HUD, and running while the tree is paused so the
	# panel can stop the world without freezing its own button.
	intro.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(intro)
	intro.show_intro(compass)


## Closes the wind intro if it is open. Used by the screenshot harness, which
## needs the world running again after capturing the panel.
func dismiss_wind_intro() -> bool:
	var intro: Node = get_node_or_null(^"WindIntro")
	if intro == null:
		return false
	get_tree().paused = false
	intro.queue_free()
	return true


func _process(delta: float) -> void:
	if _toast_left <= 0.0:
		return
	_toast_left -= delta
	# Hold at full opacity, then fade over the last half second.
	_toast.modulate.a = clampf(_toast_left / 0.5, 0.0, 1.0)


func _refresh_all() -> void:
	_on_gold_changed(GameState.total_gold(), 0)
	_on_doubloons_changed(GameState.doubloons, 0)
	_refresh_ammo()
	_refresh_fleet()


func _refresh_ammo() -> void:
	var ammo: AmmoType = AmmoLibrary.get_ammo(GameState.selected_ammo)
	_ammo_button.text = ammo.display_name
	if ammo.unlimited:
		_ammo_count.text = "∞"
	else:
		_ammo_count.text = str(GameState.get_ammo(ammo.id))


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
