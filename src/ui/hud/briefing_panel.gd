class_name BriefingPanel
extends Control
## A modal that stops the world, says one thing, and gets out of the way.
##
## Every briefing in the game is one of these. Keeping them uniform matters more
## than it sounds: a player learns *once* that a dark panel means "read this, then
## press the button", and after that every new mechanic costs them no interface
## learning at all.
##
## Rules the content has to follow, enforced by how small this thing is:
##   * three lines, maximum
##   * say what to *do*, not how the system works
##   * never appear twice
##
## Optionally pans the camera to something after dismissal, because "there are
## enemies now" is far better shown than described.

## Alegreya, matching the HUD. The briefing is the longest prose in the game and
## the only screen a new player is asked to actually read — and it was the last
## thing still set in Kenney Future, the wide all-caps display face the HUD was
## moved off for being unreadable at body sizes. See the note at the top of hud.gd.
const FONT: String = "res://assets/fonts/Alegreya.ttf"
const PANEL_WIDTH: float = 560.0

signal dismissed()

var _column: VBoxContainer
var _button: Button


func _ready() -> void:
	# Anchors alone leave a code-made Control at zero size when its parent is a
	# CanvasLayer rather than a container — nothing lays it out. Without offsets
	# the CenterContainer has no area to centre in and everything collapses into
	# the top-left corner.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.05, 0.08, 0.66)
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

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 12)
	panel.add_child(_column)


## Fills in and shows the panel. Pauses the tree until dismissed.
func present(title: String, lines: PackedStringArray, button_text: String = "GOT IT") -> void:
	_column.add_child(_label(title, 22, Color("f0c04a"), HORIZONTAL_ALIGNMENT_CENTER))

	var rule := ColorRect.new()
	rule.color = Color(0.55, 0.44, 0.26, 0.6)
	rule.custom_minimum_size = Vector2(0, 2)
	_column.add_child(rule)

	for line: String in lines:
		_column.add_child(_label(line, 15, Color("e6e2d3"), HORIZONTAL_ALIGNMENT_LEFT))

	_button = Button.new()
	_button.text = button_text
	_button.custom_minimum_size = Vector2(0, 50)
	_button.add_theme_font_size_override("font_size", 16)
	Wave1UI.apply_brass(_button)
	var font: FontFile = _font()
	if font != null:
		_button.add_theme_font_override("font", font)
	_button.pressed.connect(_dismiss)
	_column.add_child(_button)

	# A frame before pausing, so the world behind the panel is laid out and drawn.
	# Pausing mid-scene-change freezes a half-built frame.
	await get_tree().process_frame
	get_tree().paused = true
	_button.grab_focus()


## Closes the panel from code. Used by the screenshot harness and by anything
## that needs to guarantee the game is not left paused.
func force_dismiss() -> void:
	_dismiss()


func _dismiss() -> void:
	if not is_inside_tree():
		return
	get_tree().paused = false
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
