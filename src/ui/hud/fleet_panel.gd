class_name FleetPanel
extends Control
## The fleet, as a card per hull.
##
## The HUD badge could only ever say "2 / 2", which answers one question — how
## many are left — and raises three: which ones, how badly hurt, and what did the
## thing I just bought actually get me. Buying a second ship was the worst of it.
## The purchase lands in [member GameState.fleet] at the port and the hull is not
## built until [method FleetController.refit] runs on the way out, so for the
## length of a shop visit the player had paid three hundred gold and a diamond for
## a counter that still read "1". Nothing anywhere said why. A berth with no hull
## in it gets its own card here, saying exactly when the ship arrives.
##
## Tapping a card takes command of that hull, which is also the only way to select
## an escort that has drifted off screen.
##
## Same modal grammar as [BriefingPanel] and [PortScreen]: dark panel, stopped
## world, one way out.

## Alegreya, matching the HUD and the port. See the note at the top of hud.gd.
const FONT: String = "res://assets/fonts/Alegreya.ttf"
## What the panel asks for; it gives way to a narrower screen — see
## [method Wave1UI.modal_width].
const PANEL_WIDTH: float = 620.0
## What the roster asks for, and the least it will accept. A phone in landscape
## has less height than the cards alone want, and the way out of this modal is the
## button underneath them.
const LIST_HEIGHT: float = 340.0
const LIST_HEIGHT_MIN: float = 120.0

const GOLD: Color = Color("d9a12c")
const GOLD_BRIGHT: Color = Color("f0c04a")
const TEXT: Color = Color("e6e2d3")
const DIM: Color = Color("8a97a3")
const CARD_BG: Color = Color(0.071, 0.145, 0.204)
const CARD_EDGE: Color = Color(0.353, 0.310, 0.220)
const CARD_BG_EMPTY: Color = Color(0.051, 0.094, 0.129)

## The three condition bars, in the same colours [WorldOverlay] paints over the
## hulls themselves. A player reads "the red one is low" on the water and must
## find the same red bar in here, or this is a second vocabulary for one idea.
const BAR_HULL: Color = Color("d9534f")
const BAR_SAILS: Color = Color("efe4c8")
const BAR_GUNS: Color = Color("9aa7b0")
const BAR_BG: Color = Color(0, 0, 0, 0.4)
const BAR_HEIGHT: float = 7.0

const ICON_GOLD: Texture2D = preload("res://assets/wave1/icons/icon_gold.png")
const ICON_WHEEL: Texture2D = preload("res://assets/wave1/icons/icon_wheel.png")

signal closed()

var _fleet: FleetController = null
var _panel: PanelContainer
var _column: VBoxContainer
var _scroll: ScrollContainer


## Fills in and shows the panel. Pauses the tree until closed.
func present(fleet: FleetController) -> void:
	_fleet = fleet
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

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _panel_style())
	centre.add_child(_panel)

	_column = VBoxContainer.new()
	_panel.add_child(_column)

	_column.add_child(_label("YOUR FLEET", 21, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	_column.add_child(
		_label(_fleet_summary(), 13, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	)

	# The hold, once, at the top. Unbanked gold belongs to the fleet rather than to
	# any one hull — it is all lost the moment a hull goes down — so putting a copy
	# of the number on every card would be three answers to a question with one.
	_column.add_child(_hold_row())

	var rule := ColorRect.new()
	rule.color = Color(0.55, 0.44, 0.26, 0.45)
	rule.custom_minimum_size = Vector2(0, 1)
	_column.add_child(rule)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column.add_child(_scroll)

	var cards := VBoxContainer.new()
	cards.add_theme_constant_override("separation", 9)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(cards)

	for slot: int in GameState.fleet.size():
		cards.add_child(_ship_card(slot))

	var close := Button.new()
	close.text = "BACK TO THE HELM"
	close.custom_minimum_size = Vector2(0, 50)
	close.add_theme_font_size_override("font_size", 16)
	_apply_font(close)
	Wave1UI.apply_brass(close)
	close.pressed.connect(_close)
	_column.add_child(close)

	resized.connect(_fit)
	_fit()

	# A frame before pausing, so the world behind the panel is laid out and drawn.
	await get_tree().process_frame
	get_tree().paused = true
	close.grab_focus()
	_fit()


## Sizes the panel to the screen it is on.
func _fit() -> void:
	if _panel == null or _scroll == null:
		return
	_panel.custom_minimum_size.x = Wave1UI.modal_width(self, PANEL_WIDTH)
	_column.add_theme_constant_override("separation", Wave1UI.modal_separation(self))
	Wave1UI.fit_list(_panel, _scroll, LIST_HEIGHT, LIST_HEIGHT_MIN)


func force_close() -> void:
	_close()


func _close() -> void:
	if not is_inside_tree():
		return
	get_tree().paused = false
	Audio.play_ui(&"ui_tap")
	closed.emit()
	queue_free()


## "2 of 3 berths crewed, 2 afloat" — the sentence the bare counter could not say.
func _fleet_summary() -> String:
	var berths: int = GameState.fleet.size()
	var afloat: int = 0
	if _fleet != null and is_instance_valid(_fleet):
		afloat = _fleet.living_ships().size()

	var hulls: String = "One hull" if berths == 1 else "%d hulls" % berths
	if afloat >= berths:
		return "%s under your command" % hulls
	return "%s bought · %d of them already at sea" % [hulls, afloat]


func _hold_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon := TextureRect.new()
	icon.texture = ICON_GOLD
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(22, 22)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var carried: int = GameState.carried_gold
	var text: String = (
		"Nothing in the hold — %d gold banked ashore" % GameState.banked_gold
		if carried <= 0
		else "%d gold in the hold, lost if you sink · %d banked ashore" % [
			carried, GameState.banked_gold
		]
	)
	var label: Label = _label(
		text, 13, GOLD_BRIGHT if carried > 0 else DIM, HORIZONTAL_ALIGNMENT_LEFT
	)
	# Word wrap inside an HBox that gives a Label no width to work with collapses
	# it to one letter per line — the same trap the port's purse pill documents.
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(label)
	return row


## One hull's card.
##
## A [PanelContainer] carrying the chrome, with a flat [Button] laid over the top
## of it as the tap target. The port builds its cards the other way round — the
## Button *is* the card, with its contents anchored over it — which works there
## because every shop row is the same fixed height. These are not: a card is
## taller when the ship exists, taller again when its refit list wraps. A Button
## is not a container, so children of one are never laid out and never counted
## into its minimum size; three of them collapse into a single overlapping heap.
## This way round the container does the measuring and the button only listens.
func _ship_card(slot: int) -> Control:
	var entry: Dictionary = GameState.fleet[slot]
	var upgrades: Dictionary = entry.get("upgrades", {})
	var stats: ShipStats = ShipStatsLibrary.build(
		entry.get("stats_id", GameState.STARTING_HULL), upgrades
	)
	var ship: Ship = _ship_in_slot(slot)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override(
		"panel", _card_style(
			CARD_BG_EMPTY if ship == null else CARD_BG,
			Color(0.851, 0.631, 0.173, 0.75) if ship != null and ship.selected else CARD_EDGE,
			2 if ship != null and ship.selected else 1
		)
	)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 11)
	pad.add_theme_constant_override("margin_bottom", 11)
	card.add_child(pad)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 7)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(body)

	body.add_child(_card_heading(slot, stats, ship))

	if ship == null:
		body.add_child(
			_label(
				"Bought and paid for. She joins the line the moment you set sail"
				+ " from this port.",
				13,
				DIM,
				HORIZONTAL_ALIGNMENT_LEFT
			)
		)
	else:
		body.add_child(_condition_bars(ship))
		body.add_child(_label(_crew_line(ship), 13, TEXT, HORIZONTAL_ALIGNMENT_LEFT))

	body.add_child(_label(_gunnery_line(stats), 13, TEXT, HORIZONTAL_ALIGNMENT_LEFT))
	body.add_child(_label(_abilities_line(stats, upgrades), 12, DIM, HORIZONTAL_ALIGNMENT_LEFT))

	# Last child, so it sits over the contents and takes the tap. A berth whose
	# hull is still at the yard has nothing to take command of.
	var hit := Button.new()
	hit.flat = true
	hit.disabled = ship == null
	hit.focus_mode = Control.FOCUS_NONE if ship == null else Control.FOCUS_ALL
	_apply_hit_style(hit)
	if ship != null:
		hit.pressed.connect(_take_command.bind(slot))
	card.add_child(hit)
	return card


func _card_heading(slot: int, stats: ShipStats, ship: Ship) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var wheel := TextureRect.new()
	wheel.texture = ICON_WHEEL
	wheel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wheel.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wheel.custom_minimum_size = Vector2(26, 26)
	wheel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wheel.modulate = Color(1, 1, 1, 0.4) if ship == null else Color(1, 1, 1, 1)
	row.add_child(wheel)

	var name_label: Label = _label(
		stats.display_name, 16, GOLD_BRIGHT if ship != null else DIM, HORIZONTAL_ALIGNMENT_LEFT
	)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	# Slot 0 is the flagship by construction: it is the entry the port sells
	# upgrades against, and the one a wipe always hands back.
	var tag: String = "FLAGSHIP" if slot == 0 else "ESCORT"
	var tag_colour: Color = DIM
	if ship == null:
		tag = "AT THE YARD"
	elif ship.selected:
		tag = "AT THE HELM"
		tag_colour = GOLD_BRIGHT
	var tag_label: Label = _label(tag, 12, tag_colour, HORIZONTAL_ALIGNMENT_RIGHT)
	# See the note in _hold_row: wrapping is what turns a two-word tag into a
	# column of single letters, and a column of single letters is what makes the
	# card six times taller than it should be.
	tag_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	tag_label.custom_minimum_size = Vector2(96, 0)
	row.add_child(tag_label)
	return row


## Hull, sails and guns as three stacked bars, each with what is left of it.
func _condition_bars(ship: Ship) -> Control:
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE

	rows.add_child(_bar("HULL", ship.hull_fraction(), BAR_HULL))
	rows.add_child(_bar("SAILS", ship.sails_fraction(), BAR_SAILS))
	rows.add_child(_bar("GUNS", ship.cannons_fraction(), BAR_GUNS))
	return rows


func _bar(tag: String, fraction: float, colour: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tag_label: Label = _label(tag, 11, DIM, HORIZONTAL_ALIGNMENT_LEFT)
	tag_label.custom_minimum_size = Vector2(48, 0)
	tag_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(tag_label)

	var track := PanelContainer.new()
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = BAR_BG
	track_style.set_corner_radius_all(3)
	track.add_theme_stylebox_override("panel", track_style)
	row.add_child(track)

	# The fill is a ratio-anchored child of the track rather than a second bar in
	# the box, so it is measured against the track's real width after layout
	# instead of asking a container to divide itself.
	var fill := ColorRect.new()
	fill.color = colour
	fill.anchor_right = clampf(fraction, 0.0, 1.0)
	fill.anchor_bottom = 1.0
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)

	var value: Label = _label(
		"%d%%" % roundi(clampf(fraction, 0.0, 1.0) * 100.0), 11, DIM, HORIZONTAL_ALIGNMENT_RIGHT
	)
	value.custom_minimum_size = Vector2(40, 0)
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(value)
	return row


## What the crew are doing to the reload, in seconds rather than in percentages.
##
## Crew are not a headcount in this game — they are a multiplier on how fast the
## guns come back, cut by grape shot and by losing gun crews with the guns. The
## honest way to show that is the number it changes: a ship whose crew have been
## raked reloads visibly slower, and this is where a player finds out that is what
## happened to them.
func _crew_line(ship: Ship) -> String:
	var health: float = ship.crew_efficiency * ship.cannons_fraction()
	var reload: float = ship.stats.reload_time / maxf(0.05, health)
	var state: String = "Crew at their stations"
	if ship.crew_efficiency < 0.99:
		state = "Crew raked — %d%% of a full watch" % roundi(ship.crew_efficiency * 100.0)
	elif ship.cannons_fraction() < 0.99:
		state = "Guns knocked about"
	return "%s · %.1f s between broadsides" % [state, reload]


func _gunnery_line(stats: ShipStats) -> String:
	var guns: String = (
		"1 gun a side" if stats.cannons_per_side == 1
		else "%d guns a side" % stats.cannons_per_side
	)
	return "%s · %d damage a ball · %d m reach · hold %d" % [
		guns, roundi(stats.base_damage), roundi(stats.cannon_range), stats.cargo_capacity
	]


## What this hull can do that another cannot: how it is driven, and what gold has
## been spent on it. Both are "abilities" in the only sense the game has one —
## there is nothing here to activate, and a hull's drive decides more about how it
## fights than any upgrade does.
func _abilities_line(stats: ShipStats, upgrades: Dictionary) -> String:
	var drive: String = ""
	if stats.is_oared():
		drive = "Oars — ignores the wind, turns on the spot"
	else:
		match stats.rig:
			ShipStats.Rig.FORE_AFT:
				drive = "Fore-and-aft rig — points highest upwind"
			ShipStats.Rig.SQUARE:
				drive = "Square rig — owns the broad reach, miserable beating"
			_:
				drive = "Mixed rig — no bad point of sail, no great one"
	return "%s · %s" % [drive, UpgradeLibrary.summarise(upgrades)]


## The hull in a roster slot, or null if there is not one yet.
##
## [member FleetController.ships] and [member GameState.fleet] are built and torn
## down in lockstep, so the index is shared — see
## [method FleetController._on_ship_died]. A slot past the end of `ships` is a
## berth bought in the port whose hull has not been laid down yet.
func _ship_in_slot(slot: int) -> Ship:
	if _fleet == null or not is_instance_valid(_fleet):
		return null
	if slot < 0 or slot >= _fleet.ships.size():
		return null
	var entry: Variant = _fleet.ships[slot]
	if not is_instance_valid(entry) or not (entry as Ship).alive:
		return null
	return entry


func _take_command(slot: int) -> void:
	var ship: Ship = _ship_in_slot(slot)
	if ship != null:
		EventBus.intent_select_ship.emit(ship)
	_close()


## The invisible tap target over a card. Only its hover and pressed states paint
## anything — the card underneath is already drawn.
func _apply_hit_style(hit: Button) -> void:
	var clear := StyleBoxFlat.new()
	clear.bg_color = Color(1, 1, 1, 0)
	hit.add_theme_stylebox_override("normal", clear)
	hit.add_theme_stylebox_override("disabled", clear)

	var lit := StyleBoxFlat.new()
	lit.bg_color = Color(0.941, 0.753, 0.290, 0.12)
	lit.set_corner_radius_all(9)
	hit.add_theme_stylebox_override("hover", lit)
	hit.add_theme_stylebox_override("focus", lit)

	var down := StyleBoxFlat.new()
	down.bg_color = Color(0, 0, 0, 0.22)
	down.set_corner_radius_all(9)
	hit.add_theme_stylebox_override("pressed", down)


func _card_style(bg: Color, edge: Color, border: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_border_width_all(border)
	style.border_color = edge
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	return style


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
