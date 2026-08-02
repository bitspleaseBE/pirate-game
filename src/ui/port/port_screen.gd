class_name PortScreen
extends Control
## Where gold becomes a better ship.
##
## This closes the loop the whole game rests on: win a fight, dig up gold, come
## here, leave stronger, pick a harder island. Before this existed gold was a
## score with no use, and combat was a skill check with no memory.
##
## Design rules, all in service of "understandable in five seconds":
##   * every row is a button with a price on it — nothing is a menu inside a menu
##   * anything unaffordable is visible but disabled, so you can see what to save
##     for rather than discovering it exists later
##   * arriving repairs and banks automatically, because forgetting to do either
##     is a punishment for not knowing the interface, not for playing badly

const FONT: String = "res://assets/fonts/KenneyFuture.ttf"
const PANEL_WIDTH: float = 620.0
const AMMO_RESTOCK_COST: int = 45
## Rounds of each limited shot type a restock buys.
const AMMO_RESTOCK_AMOUNT: int = 5

const GOLD: Color = Color("d9a12c")
const TEXT: Color = Color("e6e2d3")
const DIM: Color = Color("8a97a3")

const ICON_HULL: Texture2D = preload("res://assets/wave1/icons/icon_hull.png")
const ICON_SAIL: Texture2D = preload("res://assets/wave1/icons/icon_sail.png")
const ICON_CANNON: Texture2D = preload("res://assets/wave1/icons/icon_cannon.png")
const ICON_WHEEL: Texture2D = preload("res://assets/wave1/icons/icon_wheel.png")
const ICON_MAP: Texture2D = preload("res://assets/wave1/icons/icon_map.png")

signal closed()

var _island_name: String = "Port"
var _rows: VBoxContainer
var _gold_label: Label
var _ship_label: Label


func present(island_name: String) -> void:
	_island_name = island_name
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.05, 0.08, 0.72)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	centre.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	column.add_child(_label("PORT OF %s" % _island_name.to_upper(), 20, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	_gold_label = _label("", 16, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_gold_label)
	_ship_label = _label("", 13, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_ship_label)

	var rule := ColorRect.new()
	rule.color = Color(0.55, 0.44, 0.26, 0.6)
	rule.custom_minimum_size = Vector2(0, 2)
	column.add_child(rule)

	# The list can outgrow a phone screen once several upgrades are maxed, so it
	# scrolls rather than pushing the "set sail" button off the bottom.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 7)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)

	var sail := Button.new()
	sail.text = "SET SAIL"
	sail.custom_minimum_size = Vector2(0, 52)
	sail.add_theme_font_size_override("font_size", 17)
	_apply_font(sail)
	Wave1UI.apply_brass(sail)
	Wave1UI.set_icon(sail, preload("res://assets/wave1/icons/icon_anchor.png"), 38)
	sail.pressed.connect(_close)
	column.add_child(sail)

	await get_tree().process_frame
	get_tree().paused = true
	_refresh()
	sail.grab_focus()


func _refresh() -> void:
	var entry: Dictionary = GameState.fleet[0] if not GameState.fleet.is_empty() else {}
	var hull_id: StringName = entry.get("stats_id", GameState.STARTING_HULL)
	var upgrades: Dictionary = entry.get("upgrades", {})
	var stats: ShipStats = ShipStatsLibrary.build(hull_id, upgrades)

	_gold_label.text = "%d gold in the bank" % GameState.banked_gold
	_ship_label.text = "%s · hull %d · %s · %s" % [
		stats.display_name,
		roundi(stats.max_hull),
		_guns_phrase(stats.cannons_per_side),
		UpgradeLibrary.summarise(upgrades),
	]

	for child: Node in _rows.get_children():
		child.queue_free()

	# A new hull first: it is the biggest jump available and the thing worth saving
	# for, so it should be the first thing seen rather than buried under upgrades.
	var next_hull: StringName = ShipStatsLibrary.next_tier(hull_id)
	if next_hull != &"":
		var hull_cost: int = ShipStatsLibrary.upgrade_cost(hull_id)
		var next_stats: ShipStats = ShipStatsLibrary.get_stats(next_hull)
		_add_row(
			"NEW SHIP: %s" % next_stats.display_name,
			"%s, %d hull. Upgrades carry over." % [
				_guns_phrase(next_stats.cannons_per_side), roundi(next_stats.max_hull)
			],
			hull_cost,
			_buy_hull.bind(next_hull),
			ICON_HULL
		)

	for id: StringName in UpgradeLibrary.ORDER:
		var level: int = UpgradeLibrary.level_of(upgrades, id)
		var maximum: int = UpgradeLibrary.max_level(id)
		var cost: int = UpgradeLibrary.next_cost(upgrades, id)
		var title: String = "%s  ·  %d/%d" % [UpgradeLibrary.display_name(id), level, maximum]
		if cost < 0:
			_add_row(title, "Fully upgraded.", -1, Callable(), _upgrade_icon(id))
		else:
			_add_row(
				title, UpgradeLibrary.blurb(id), cost, _buy_upgrade.bind(id), _upgrade_icon(id)
			)

	var short_of_ammo: bool = false
	for ammo_id: StringName in AmmoLibrary.ORDER:
		if not AmmoLibrary.get_ammo(ammo_id).unlimited and GameState.get_ammo(ammo_id) < 10:
			short_of_ammo = true
			break
	if short_of_ammo:
		_add_row(
			"RESTOCK SHOT",
			"+%d of every special shot type." % AMMO_RESTOCK_AMOUNT,
			AMMO_RESTOCK_COST,
			_buy_ammo,
			ICON_CANNON
		)


func _guns_phrase(count: int) -> String:
	return "1 gun a side" if count == 1 else "%d guns a side" % count


func _add_row(
	title: String, blurb: String, cost: int, action: Callable, icon: Texture2D = null
) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 62)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Unaffordable rows stay visible but dead, so the player can see what to save
	# for. Hiding them would make the shop look empty and the loop look broken.
	button.disabled = cost < 0 or GameState.banked_gold < cost
	_apply_font(button)
	Wave1UI.apply_brass(button)
	if icon != null:
		Wave1UI.set_icon(button, icon, 42)

	var price: String = "MAXED" if cost < 0 else "%d g" % cost
	button.text = "%s          %s\n%s" % [title, price, blurb]
	button.add_theme_font_size_override("font_size", 13)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Left-aligned so the rows read as a price list rather than as a stack of
	# centred captions.
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT

	if action.is_valid() and not button.disabled:
		button.pressed.connect(action)
	_rows.add_child(button)


func _upgrade_icon(id: StringName) -> Texture2D:
	match id:
		&"plating":
			return ICON_HULL
		&"rigging":
			return ICON_SAIL
		&"gunnery":
			return ICON_CANNON
		&"crew":
			return ICON_WHEEL
		&"lookout":
			return ICON_MAP
		_:
			return null


func _buy_upgrade(id: StringName) -> void:
	var entry: Dictionary = GameState.fleet[0]
	var upgrades: Dictionary = entry.get("upgrades", {})
	if UpgradeLibrary.purchase(upgrades, id):
		entry["upgrades"] = upgrades
		Audio.play_ui(&"ui_confirm")
		EventBus.fleet_changed.emit()
		SaveSystem.request_save()
	else:
		Audio.play_ui(&"ui_cancel")
	_refresh()


func _buy_hull(hull_id: StringName) -> void:
	var entry: Dictionary = GameState.fleet[0]
	var cost: int = ShipStatsLibrary.upgrade_cost(entry.get("stats_id", GameState.STARTING_HULL))
	if cost < 0 or not GameState.spend_gold(cost):
		Audio.play_ui(&"ui_cancel")
		return
	entry["stats_id"] = hull_id
	Audio.play_ui(&"ui_confirm")
	EventBus.fleet_changed.emit()
	SaveSystem.request_save()
	_refresh()


func _buy_ammo() -> void:
	if not GameState.spend_gold(AMMO_RESTOCK_COST):
		Audio.play_ui(&"ui_cancel")
		return
	for ammo_id: StringName in AmmoLibrary.ORDER:
		if not AmmoLibrary.get_ammo(ammo_id).unlimited:
			GameState.add_ammo(ammo_id, AMMO_RESTOCK_AMOUNT)
	Audio.play_ui(&"ui_confirm")
	SaveSystem.request_save()
	_refresh()


func force_close() -> void:
	_close()


func _close() -> void:
	if not is_inside_tree():
		return
	get_tree().paused = false
	Audio.play_ui(&"ui_tap")
	closed.emit()
	queue_free()


func _label(text: String, font_size: int, color: Color, align: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = align as HorizontalAlignment
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	_apply_font(label)
	return label


func _apply_font(control: Control) -> void:
	if not ResourceLoader.exists(FONT):
		return
	control.add_theme_font_override("font", load(FONT) as FontFile)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.047, 0.110, 0.165, 0.98)
	style.set_border_width_all(2)
	style.border_color = Color(0.541, 0.435, 0.263, 0.85)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(20)
	return style
