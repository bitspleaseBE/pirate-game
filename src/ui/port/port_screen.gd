class_name PortScreen
extends Control
## Where gold becomes a better ship.
##
## This closes the loop the whole game rests on: win a fight, dig up gold, come
## here, leave stronger, pick a harder island. Before this existed gold was a
## score with no use, and combat was a skill check with no memory.
##
## Design rules, all in service of "understandable in five seconds":
##   * every offer is one tappable card with its price on it — nothing is a menu
##     inside a menu, and nothing needs a second tap to confirm
##   * anything unaffordable is visible but disabled, so you can see what to save
##     for rather than discovering it exists later
##   * arriving repairs and banks automatically, because forgetting to do either
##     is a punishment for not knowing the interface, not for playing badly

## Alegreya, matching the HUD. The port was still wholly on Kenney Future after
## the HUD moved off it, so the one screen made entirely of prose the player has to
## read closely was in the wide geometric display face that was retired for being
## unreadable at small sizes. See the note at the top of hud.gd.
const FONT: String = "res://assets/fonts/Alegreya.ttf"
const PANEL_WIDTH: float = 620.0
const AMMO_RESTOCK_COST: int = 45
## Rounds of each limited shot type a restock buys.
const AMMO_RESTOCK_AMOUNT: int = 5

## Price of the second and third hull in the fleet, indexed by the slot being
## bought minus two.
##
## Diamond-gated per the design, and this is the only thing in the game that
## spends them — which is the point. Diamonds drop from tier-2-and-up chests and
## the castle (see [method Island._fallback_loot]), so a second ship lands around
## the third island rather than being grindable out of the opening one, and the
## counter in the HUD stops being a permanent zero.
const FLEET_SLOT_GOLD: Array[int] = [300, 800]
const FLEET_SLOT_DIAMONDS: Array[int] = [1, 3]
const MAX_FLEET_SLOTS: int = 3

const GOLD: Color = Color("d9a12c")
const GOLD_BRIGHT: Color = Color("f0c04a")
const TEXT: Color = Color("e6e2d3")
const DIM: Color = Color("8a97a3")

## Card chrome. All of it is drawn by [StyleBoxFlat] rather than nine-sliced from
## the brass button sprite: the sprite is a fixed-height band with riveted caps, so
## every row it painted had to be the same shape as every other row, and a shop is
## exactly the screen that needs an unaffordable row to *look* unaffordable and a
## new hull to look like the headline. Colour is free to vary; a texture is not.
const CARD_BG: Color = Color(0.071, 0.145, 0.204)
const CARD_BG_DOWN: Color = Color(0.043, 0.098, 0.145)
const CARD_BG_OFF: Color = Color(0.051, 0.094, 0.129)
const CARD_EDGE: Color = Color(0.353, 0.310, 0.220)
const CARD_EDGE_OFF: Color = Color(0.196, 0.239, 0.278)
const CARD_HEIGHT: float = 88.0

const ICON_GOLD: Texture2D = preload("res://assets/wave1/icons/icon_gold.png")
const ICON_DIAMOND: Texture2D = preload("res://assets/wave1/icons/icon_diamond.png")

const ICON_HULL: Texture2D = preload("res://assets/wave1/icons/icon_hull.png")
const ICON_SAIL: Texture2D = preload("res://assets/wave1/icons/icon_sail.png")
const ICON_CANNON: Texture2D = preload("res://assets/wave1/icons/icon_cannon.png")
const ICON_WHEEL: Texture2D = preload("res://assets/wave1/icons/icon_wheel.png")
const ICON_MAP: Texture2D = preload("res://assets/wave1/icons/icon_map.png")

signal closed()

var _island_name: String = "Port"
var _rows: VBoxContainer
var _gold_value: Label
var _diamond_value: Label
var _ship_label: Label
var _fleet_label: Label


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
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	column.add_child(
		_label("PORT OF %s" % _island_name.to_upper(), 21, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	)

	# The purse as two pills rather than a sentence. It is the number every decision
	# on this screen is measured against, so it reads better as a value you can
	# glance at than as prose you have to parse.
	var purse := HBoxContainer.new()
	purse.alignment = BoxContainer.ALIGNMENT_CENTER
	purse.add_theme_constant_override("separation", 10)
	column.add_child(purse)
	_gold_value = _label("", 19, GOLD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER)
	purse.add_child(_purse_pill(_gold_value, ICON_GOLD))
	_diamond_value = _label("", 19, Color("bfe4ec"), HORIZONTAL_ALIGNMENT_CENTER)
	purse.add_child(_purse_pill(_diamond_value, ICON_DIAMOND))

	_ship_label = _label("", 13, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_ship_label)

	# What the fleet consists of, right under what the flagship consists of. The
	# shop sells two things that both begin "a ship" — a bigger hull for the one
	# you have, and a second hull alongside it — and buying either used to change
	# nothing on screen but a price. This line is where the difference shows up.
	_fleet_label = _label("", 12, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_fleet_label)

	var rule := ColorRect.new()
	rule.color = Color(0.55, 0.44, 0.26, 0.45)
	rule.custom_minimum_size = Vector2(0, 1)
	column.add_child(rule)

	# The list can outgrow a phone screen once several upgrades are maxed, so it
	# scrolls rather than pushing the "set sail" button off the bottom.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_scrollbar(scroll.get_v_scroll_bar())
	column.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 9)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)

	var sail := Button.new()
	sail.text = "SET SAIL"
	sail.custom_minimum_size = Vector2(0, 54)
	sail.add_theme_font_size_override("font_size", 17)
	_apply_font(sail)
	_apply_sail_style(sail)
	sail.icon = preload("res://assets/wave1/icons/icon_anchor.png")
	sail.expand_icon = true
	sail.add_theme_constant_override("icon_max_width", 30)
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

	_gold_value.text = str(GameState.banked_gold)
	_diamond_value.text = str(GameState.diamonds)
	_ship_label.text = "%s · hull %d · %s · %s" % [
		stats.display_name,
		roundi(stats.max_hull),
		_guns_phrase(stats.cannons_per_side),
		UpgradeLibrary.summarise(upgrades),
	]
	_fleet_label.text = _fleet_phrase()

	for child: Node in _rows.get_children():
		child.queue_free()

	# A new hull first: it is the biggest jump available and the thing worth saving
	# for, so it should be the first thing seen rather than buried under upgrades.
	#
	# It is titled as a *refit* rather than as a new ship, and says out loud what
	# happens to the old hull. "NEW SHIP: Sloop" sitting directly above "ANOTHER
	# SHIP: Dinghy" reads as two ways to buy a second hull; one of them is not, and
	# a player who bought the wrong one watched the fleet badge stay on "1 / 1"
	# with nothing anywhere explaining why.
	var next_hull: StringName = ShipStatsLibrary.next_tier(hull_id)
	if next_hull != &"":
		var hull_cost: int = ShipStatsLibrary.upgrade_cost(hull_id)
		var next_stats: ShipStats = ShipStatsLibrary.get_stats(next_hull)
		_add_row(
			"REFIT THE %s → %s" % [stats.display_name.to_upper(), next_stats.display_name],
			"Trades her in: %s, %d hull. Upgrades carry over. Still one ship." % [
				_guns_phrase(next_stats.cannons_per_side), roundi(next_stats.max_hull)
			],
			hull_cost,
			_buy_hull.bind(next_hull),
			ICON_HULL,
			0,
			true
		)

	_add_fleet_slot_row(hull_id)

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


## "Fleet: Sloop, Dinghy — they join you when you set sail."
##
## The roster grows the moment a hull is bought, but the hull itself is not built
## until [method FleetController.refit] runs on the way out of the port, so a
## player who has just spent a diamond on a second ship is looking at a fleet
## badge that still says one. This is the line that tells them what they own,
## rather than what is currently floating.
func _fleet_phrase() -> String:
	if GameState.fleet.size() <= 1:
		return "One ship in the fleet"

	var names: PackedStringArray = []
	for entry: Dictionary in GameState.fleet:
		names.append(
			ShipStatsLibrary.get_stats(
				entry.get("stats_id", GameState.STARTING_HULL)
			).display_name
		)
	return "Fleet of %d — %s. They sail with you when you leave." % [
		names.size(), ", ".join(names)
	]


## Builds one shop card: icon tile, title and blurb, price pill.
##
## The whole card is the [Button] — its children are anchored over it and pass
## input straight through — so the tap target is the entire row rather than a word
## of text, which is what a thumb needs.
##
## [param featured] marks the two "buy a hull" rows. They are the headline
## decisions and the design wants them read first; a warmer fill and a gold edge
## does that without moving them or making them bigger.
func _add_row(
	title: String,
	blurb: String,
	cost: int,
	action: Callable,
	icon: Texture2D = null,
	diamond_cost: int = 0,
	featured: bool = false
) -> void:
	var maxed: bool = cost < 0
	# Unaffordable rows stay visible but dead, so the player can see what to save
	# for. Hiding them would make the shop look empty and the loop look broken.
	var short: bool = (
		not maxed
		and (GameState.banked_gold < cost or GameState.diamonds < diamond_cost)
	)
	var dead: bool = maxed or short

	var card := Button.new()
	card.custom_minimum_size = Vector2(0, CARD_HEIGHT)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.disabled = dead
	_apply_card_style(card, featured)
	_rows.add_child(card)

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	card.add_child(pad)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)

	if icon != null:
		row.add_child(_icon_tile(icon, dead, featured))

	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_column.add_theme_constant_override("separation", 3)
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_column)

	var title_colour: Color = TEXT
	if featured:
		title_colour = GOLD_BRIGHT
	if dead:
		title_colour = title_colour.darkened(0.45)
	text_column.add_child(_label(title, 15, title_colour, HORIZONTAL_ALIGNMENT_LEFT))
	text_column.add_child(
		_label(blurb, 12, DIM.darkened(0.3) if dead else DIM, HORIZONTAL_ALIGNMENT_LEFT)
	)

	row.add_child(_price_pill(cost, diamond_cost, maxed, short))

	if action.is_valid() and not card.disabled:
		card.pressed.connect(action)


## The price, set apart from the prose so it can be scanned down the column.
## Gold when you can pay, rust when you cannot — the colour is the answer to the
## only question the player is asking, and it survives being read at arm's length.
##
## The currency is the coin and the gem themselves rather than "g" and "dbl".
## Two abbreviations the player has to learn, in the one place where mistaking one
## currency for the other costs them the rarest thing they own, was a bad trade —
## and the same two icons appear in the HUD and the purse, so they are learned once.
func _price_pill(cost: int, diamond_cost: int, maxed: bool, short: bool) -> Control:
	var fill: Color = Color(0.851, 0.631, 0.173, 0.16)
	var edge: Color = Color(0.851, 0.631, 0.173, 0.65)
	var ink: Color = GOLD_BRIGHT
	if maxed:
		fill = Color(1.0, 1.0, 1.0, 0.04)
		edge = Color(1.0, 1.0, 1.0, 0.12)
		ink = DIM.darkened(0.15)
	elif short:
		fill = Color(0.596, 0.243, 0.196, 0.16)
		edge = Color(0.686, 0.353, 0.290, 0.5)
		ink = Color("c08072")

	var pill := PanelContainer.new()
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", _pill_style(fill, edge))

	if maxed:
		var label := _label("MAXED", 13, ink, HORIZONTAL_ALIGNMENT_CENTER)
		label.custom_minimum_size = Vector2(74, 0)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		pill.add_child(label)
		return pill

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(column)

	var faded: bool = short
	column.add_child(_price_line(ICON_GOLD, cost, ink, faded))
	if diamond_cost > 0:
		column.add_child(_price_line(ICON_DIAMOND, diamond_cost, ink, faded))
	return pill


## One currency's worth of a price: its icon, then the amount.
func _price_line(icon: Texture2D, amount: int, ink: Color, faded: bool) -> Control:
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_END
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.custom_minimum_size = Vector2(74, 0)

	line.add_child(_currency_icon(icon, 22, faded))
	var label := _label(str(amount), 15, ink, HORIZONTAL_ALIGNMENT_RIGHT)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	line.add_child(label)
	return line


func _currency_icon(icon: Texture2D, size: int, faded: bool = false) -> TextureRect:
	var texture := TextureRect.new()
	texture.texture = icon
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.custom_minimum_size = Vector2(size, size)
	texture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture.modulate = Color(1, 1, 1, 0.55) if faded else Color(1, 1, 1, 1)
	return texture


func _icon_tile(icon: Texture2D, dead: bool, featured: bool) -> Control:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(54, 54)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.024, 0.063, 0.098, 0.7 if dead else 0.9)
	style.set_border_width_all(1)
	style.border_color = (
		Color(1.0, 1.0, 1.0, 0.05) if dead else Color(0.851, 0.631, 0.173, 0.4 if featured else 0.22)
	)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	tile.add_theme_stylebox_override("panel", style)

	var texture := TextureRect.new()
	texture.texture = icon
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.custom_minimum_size = Vector2(34, 34)
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture.modulate = Color(1, 1, 1, 0.35) if dead else Color(1, 1, 1, 1)
	tile.add_child(texture)
	return tile


## Offers the next hull in the fleet, if there is a slot left to buy.
##
## Placed directly under the new-hull row because it is the same *kind* of
## decision — spend everything on one better ship, or spread it across two — and
## the design says a three-Sloop fleet and a single Galleon are both valid answers.
## The player cannot weigh that if the two options are in different parts of a
## scrolling list.
##
## The new hull matches the flagship rather than starting as a Dinghy: an escort
## two tiers below the ship it is escorting dies to the first thing it meets, and
## upgrades still only apply to the flagship (see [method _buy_upgrade]), so a
## cheap second hull would never catch up.
func _add_fleet_slot_row(flagship_hull: StringName) -> void:
	var owned: int = GameState.fleet.size()
	if owned >= MAX_FLEET_SLOTS:
		return

	var index: int = owned - 1
	if index < 0 or index >= FLEET_SLOT_GOLD.size():
		return

	var stats: ShipStats = ShipStatsLibrary.get_stats(flagship_hull)
	const ORDINAL: Array[String] = ["SECOND", "THIRD"]
	_add_row(
		"A %s SHIP: %s" % [ORDINAL[index], stats.display_name],
		(
			"Joins your fleet when you set sail. Sails beside you, holds station,"
			+ " and fires on whatever you target."
		),
		FLEET_SLOT_GOLD[index],
		_buy_fleet_slot.bind(flagship_hull),
		ICON_WHEEL,
		FLEET_SLOT_DIAMONDS[index],
		true
	)


func _buy_fleet_slot(flagship_hull: StringName) -> void:
	var index: int = GameState.fleet.size() - 1
	if index < 0 or index >= FLEET_SLOT_GOLD.size():
		return
	var gold: int = FLEET_SLOT_GOLD[index]
	var diamonds: int = FLEET_SLOT_DIAMONDS[index]

	# Both prices checked before either is debited. Spending one and failing on the
	# other would quietly eat the player's diamonds and hand back nothing, and
	# diamonds are rare enough that it would be unrecoverable.
	if GameState.banked_gold < gold or GameState.diamonds < diamonds:
		Audio.play_ui(&"ui_cancel")
		return
	if not GameState.spend_diamonds(diamonds):
		Audio.play_ui(&"ui_cancel")
		return
	if not GameState.spend_gold(gold):
		GameState.add_diamonds(diamonds)
		Audio.play_ui(&"ui_cancel")
		return

	GameState.fleet.append({"stats_id": flagship_hull, "upgrades": {}})
	GameState.fleet_slots = maxi(GameState.fleet_slots, GameState.fleet.size())
	Audio.play_ui(&"ui_confirm")
	EventBus.fleet_changed.emit()
	SaveSystem.request_save()
	_refresh()


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
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	_apply_font(label)
	return label


## What you have of one currency: its icon, then the count.
##
## The icon replaces a written caption. "GOLD" and "DIAMONDS" set side by side are
## two words of very different length that have to be read to be told apart, where
## the coin and the gem differ in shape and in temperature and are told apart
## before they are read — and they are the same two marks used on every price
## below and in the HUD, so there is one vocabulary to learn rather than three.
func _purse_pill(value: Label, icon: Texture2D) -> Control:
	var pill := PanelContainer.new()
	var style: StyleBoxFlat = _pill_style(
		Color(0.024, 0.063, 0.098, 0.8), Color(0.851, 0.631, 0.173, 0.35)
	)
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	style.content_margin_left = 14.0
	style.content_margin_right = 16.0
	pill.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(row)

	# Word wrap inside an HBox that gives a Label no width to work with collapses it
	# to one letter per line — the pill came out as a vertical column of characters.
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	value.custom_minimum_size = Vector2(34, 0)
	row.add_child(_currency_icon(icon, 26))
	row.add_child(value)
	return pill


func _apply_card_style(card: Button, featured: bool) -> void:
	var edge: Color = Color(0.851, 0.631, 0.173, 0.55) if featured else Color(CARD_EDGE)
	var base: Color = Color(0.094, 0.153, 0.192) if featured else CARD_BG
	var width: int = 2 if featured else 1

	card.add_theme_stylebox_override("normal", _card_style(base, edge, width))
	card.add_theme_stylebox_override("hover", _card_style(
		base.lightened(0.09), Color(0.941, 0.753, 0.290, 0.9), width
	))
	card.add_theme_stylebox_override("pressed", _card_style(CARD_BG_DOWN, edge, width))
	card.add_theme_stylebox_override("focus", _card_style(
		base.lightened(0.05), Color(0.941, 0.753, 0.290, 0.75), width
	))
	card.add_theme_stylebox_override("disabled", _card_style(
		CARD_BG_OFF,
		Color(0.851, 0.631, 0.173, 0.28) if featured else Color(CARD_EDGE_OFF),
		width
	))


func _card_style(bg: Color, edge: Color, border: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_border_width_all(border)
	style.border_color = edge
	style.set_corner_radius_all(10)
	# The card content is laid out by an anchored child, so the stylebox carries no
	# content margins of its own — they would offset nothing and only confuse the
	# next person to touch this.
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	return style


func _pill_style(fill: Color, edge: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_border_width_all(1)
	style.border_color = edge
	style.set_corner_radius_all(7)
	style.set_content_margin_all(6)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	return style


## The one button on the screen that is not a purchase, so it is the one solid
## brass shape — everything else is an outline against the panel.
func _apply_sail_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _sail_style(Color("bd9139")))
	button.add_theme_stylebox_override("hover", _sail_style(Color("d6a642")))
	button.add_theme_stylebox_override("focus", _sail_style(Color("d6a642")))
	button.add_theme_stylebox_override("pressed", _sail_style(Color("8f6d29")))
	button.add_theme_color_override("font_color", Color("1c1409"))
	button.add_theme_color_override("font_hover_color", Color("1c1409"))
	button.add_theme_color_override("font_focus_color", Color("1c1409"))
	button.add_theme_color_override("font_pressed_color", Color("f3dfae"))
	button.add_theme_constant_override("outline_size", 0)
	button.add_theme_constant_override("h_separation", 10)


func _sail_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_border_width_all(2)
	style.border_color = fill.darkened(0.45)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	return style


## The stock scrollbar is a light grey slab that reads as a seam down the panel.
func _style_scrollbar(bar: VScrollBar) -> void:
	if bar == null:
		return
	bar.custom_minimum_size = Vector2(8, 0)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.04)
	track.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.851, 0.631, 0.173, 0.4)
	grabber.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("grabber", grabber)

	var grabber_hot := StyleBoxFlat.new()
	grabber_hot.bg_color = Color(0.851, 0.631, 0.173, 0.7)
	grabber_hot.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("grabber_highlight", grabber_hot)
	bar.add_theme_stylebox_override("grabber_pressed", grabber_hot)


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
