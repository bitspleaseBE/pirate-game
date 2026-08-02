class_name WindIntro
extends Control
## The one-time "you have sails now" explanation.
##
## Built in code rather than in `hud.tscn` because it is a single self-contained
## moment with no reusable parts — inlining it would add forty nodes to the file
## a designer opens every day, for a panel that appears once per save. If it
## grows into a general tutorial system it should become a scene.
##
## Deliberately three lines. The player just bought a ship; they want to sail it,
## not read. Everything here is also discoverable by playing — this only shortens
## the discovery.

const FONT: String = "res://assets/fonts/KenneyFuture.ttf"

signal dismissed()

var _panel: PanelContainer


func _ready() -> void:
	# Anchors alone leave a code-made Control at zero size when its parent is a
	# CanvasLayer rather than a container — nothing lays it out. Without the
	# offsets the CenterContainer has no area to centre the panel in, and the
	# whole thing collapses into the top-left corner.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	# Dim the world so the panel is clearly a pause in play, not another widget.
	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.05, 0.08, 0.62)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(540, 0)
	_panel.add_theme_stylebox_override("panel", _panel_style())
	centre.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_panel.add_child(column)

	column.add_child(_label("THE WIND IS UP", 22, Color("f0c04a"), HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_rule())
	_panel.set_meta("body_column", column)


## `compass` is the point the wind blows from, e.g. "NE".
func show_intro(compass: String) -> void:
	var column: VBoxContainer = _panel.get_meta("body_column")

	for line: String in [
		"Your oars are gone. Sails answer to the wind, and it is blowing from the %s." % compass,
		"Fastest across the wind, slowest sailing into it. Watch the compass ring: green means you are making good speed on this heading.",
		"You can still steer anywhere — a bad angle only costs you time. And a rudder needs way on: a ship that stops cannot turn.",
	]:
		column.add_child(_label(line, 15, Color("e6e2d3"), HORIZONTAL_ALIGNMENT_LEFT))

	var button := Button.new()
	button.text = "WEIGH ANCHOR"
	button.custom_minimum_size = Vector2(0, 48)
	button.add_theme_font_override("font", _font())
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(_dismiss)
	column.add_child(button)

	visible = true
	get_tree().paused = true


func _dismiss() -> void:
	get_tree().paused = false
	visible = false
	Audio.play_ui(&"ui_confirm")
	dismissed.emit()
	queue_free()


func _label(text: String, font_size: int, color: Color, align: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = align as HorizontalAlignment
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	var font: FontFile = _font()
	if font != null:
		label.add_theme_font_override("font", font)
	return label


func _rule() -> Control:
	var rule := ColorRect.new()
	rule.color = Color(0.55, 0.44, 0.26, 0.6)
	rule.custom_minimum_size = Vector2(0, 2)
	return rule


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.047, 0.110, 0.165, 0.97)
	style.set_border_width_all(2)
	style.border_color = Color(0.541, 0.435, 0.263, 0.8)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(22)
	return style


func _font() -> FontFile:
	if not ResourceLoader.exists(FONT):
		return null
	return load(FONT) as FontFile
