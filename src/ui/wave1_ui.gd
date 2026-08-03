class_name Wave1UI
extends RefCounted
## Shared Wave 1 presentation for code-built and scene-authored buttons.
##
## Two vocabularies live here, and which one a screen uses is a real decision.
##
## [method apply_brass] nine-slices the authored brass sprite. It is right for a
## single fixed-height control sitting over the world — the HUD's ammo button —
## where the sprite's riveted caps read as a physical thing on the deck.
##
## [method apply_card] and [method apply_primary] are drawn with [StyleBoxFlat]
## instead, and they are what a *screen* of buttons wants. The sprite is a
## fixed-height band, so every row it paints has to be the same shape as every
## other row, and a menu is exactly the place that needs an unavailable option to
## look unavailable and the headline action to look like the headline. Colour is
## free to vary; a texture is not. The port screen worked this out first and the
## title screen now shares it, which is why these live here rather than in either
## one — two copies of "what a card looks like" drift, and the main menu and the
## port are the only two full screens of buttons in the game, so they are the two
## a player is most likely to compare.

const BRASS_UP: Texture2D = preload("res://assets/wave1/ui/button_brass_up.png")
const BRASS_DOWN: Texture2D = preload("res://assets/wave1/ui/button_brass_down.png")
const BRASS_DISABLED: Texture2D = preload("res://assets/wave1/ui/button_brass_disabled.png")

## Card chrome, named for the role rather than the colour so a retint does not
## have to be chased through two screens.
const INK: Color = Color("e6e2d3")
const INK_FEATURED: Color = Color("f0c04a")
const CARD_BG: Color = Color(0.071, 0.145, 0.204)
const CARD_BG_FEATURED: Color = Color(0.094, 0.153, 0.192)
const CARD_BG_DOWN: Color = Color(0.043, 0.098, 0.145)
const CARD_BG_OFF: Color = Color(0.051, 0.094, 0.129)
const CARD_EDGE: Color = Color(0.353, 0.310, 0.220)
const CARD_EDGE_OFF: Color = Color(0.196, 0.239, 0.278)
const CARD_EDGE_FEATURED: Color = Color(0.851, 0.631, 0.173, 0.55)
const CARD_EDGE_FEATURED_OFF: Color = Color(0.851, 0.631, 0.173, 0.28)
const CARD_EDGE_HOVER: Color = Color(0.941, 0.753, 0.290, 0.9)
const CARD_EDGE_FOCUS: Color = Color(0.941, 0.753, 0.290, 0.75)
## What an icon fades to on a dead control, matching the port's dead icon tiles.
const ICON_OFF: Color = Color(1, 1, 1, 0.35)

## The solid brass fill, and the dark ink that sits on it.
const PRIMARY_FILL: Color = Color("bd9139")
const PRIMARY_FILL_HOVER: Color = Color("d6a642")
const PRIMARY_FILL_DOWN: Color = Color("8f6d29")
const PRIMARY_INK: Color = Color("1c1409")
const PRIMARY_INK_DOWN: Color = Color("f3dfae")


static func apply_brass(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _style(BRASS_UP))
	button.add_theme_stylebox_override("hover", _style(BRASS_UP))
	button.add_theme_stylebox_override("focus", _style(BRASS_UP))
	button.add_theme_stylebox_override("pressed", _style(BRASS_DOWN))
	button.add_theme_stylebox_override("disabled", _style(BRASS_DISABLED))
	button.add_theme_color_override("font_color", Color("241b12"))
	button.add_theme_color_override("font_hover_color", Color("171008"))
	button.add_theme_color_override("font_pressed_color", Color("f3dfae"))
	button.add_theme_color_override("font_disabled_color", Color("40382c"))
	button.add_theme_constant_override("outline_size", 0)


## An outlined dark card: one option among several. The port's shop rows, and the
## title screen's secondary actions.
##
## [param featured] is the headline variant — a warmer fill, a gold edge and gold
## ink. It marks the decision the screen wants read first: a new hull in the
## port, carrying on with a voyage in the menu.
##
## [param content_margin] stays at zero for the port's rows, whose content is an
## anchored child rather than the button's own label, so a stylebox margin there
## would inflate the row and pad nothing. A button that draws its own text needs
## the padding, and passes one.
static func apply_card(
	button: Button, featured: bool = false, content_margin: float = 0.0
) -> void:
	var edge: Color = CARD_EDGE_FEATURED if featured else CARD_EDGE
	var base: Color = CARD_BG_FEATURED if featured else CARD_BG
	var width: int = 2 if featured else 1

	button.add_theme_stylebox_override(
		"normal", _card_style(base, edge, width, content_margin)
	)
	button.add_theme_stylebox_override(
		"hover", _card_style(base.lightened(0.09), CARD_EDGE_HOVER, width, content_margin)
	)
	button.add_theme_stylebox_override(
		"pressed", _card_style(CARD_BG_DOWN, edge, width, content_margin)
	)
	button.add_theme_stylebox_override(
		"focus", _card_style(base.lightened(0.05), CARD_EDGE_FOCUS, width, content_margin)
	)
	button.add_theme_stylebox_override("disabled", _card_style(
		CARD_BG_OFF,
		CARD_EDGE_FEATURED_OFF if featured else CARD_EDGE_OFF,
		width,
		content_margin
	))

	# The port's cards carry no text of their own — they label themselves with
	# child Labels, which take their own colours — so these only bite on a button
	# that draws its own. Same ramp either way: bright when live, dulled when dead.
	var ink: Color = INK_FEATURED if featured else INK
	button.add_theme_color_override("font_color", ink)
	button.add_theme_color_override("font_hover_color", ink.lightened(0.2))
	button.add_theme_color_override("font_focus_color", ink)
	button.add_theme_color_override("font_pressed_color", ink)
	button.add_theme_color_override("font_disabled_color", ink.darkened(0.45))
	# The icon has to die with the label, not outlive it. Godot leaves a disabled
	# button's icon at full brightness, which on the title screen read as a lit map
	# beside greyed-out text — the same fade the port puts on a dead row's icon tile.
	button.add_theme_color_override("icon_disabled_color", ICON_OFF)
	button.add_theme_constant_override("outline_size", 0)
	button.add_theme_constant_override("h_separation", 10)


## The one solid brass shape on a screen: the action that is not a choice between
## options. "SET SAIL" in the port, "NEW VOYAGE" on the title screen.
##
## Deliberately at most one per screen. It is the loudest thing the button
## vocabulary has, and two of them on the same panel means neither is the answer.
static func apply_primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _primary_style(PRIMARY_FILL))
	button.add_theme_stylebox_override("hover", _primary_style(PRIMARY_FILL_HOVER))
	button.add_theme_stylebox_override("focus", _primary_style(PRIMARY_FILL_HOVER))
	button.add_theme_stylebox_override("pressed", _primary_style(PRIMARY_FILL_DOWN))
	button.add_theme_stylebox_override(
		"disabled", _primary_style(PRIMARY_FILL.darkened(0.55))
	)
	button.add_theme_color_override("font_color", PRIMARY_INK)
	button.add_theme_color_override("font_hover_color", PRIMARY_INK)
	button.add_theme_color_override("font_focus_color", PRIMARY_INK)
	button.add_theme_color_override("font_pressed_color", PRIMARY_INK_DOWN)
	button.add_theme_color_override("font_disabled_color", Color(0.918, 0.875, 0.804, 0.45))
	button.add_theme_color_override("icon_disabled_color", ICON_OFF)
	button.add_theme_constant_override("outline_size", 0)
	button.add_theme_constant_override("h_separation", 10)


static func set_icon(button: Button, texture: Texture2D, max_width: int = 40) -> void:
	button.icon = texture
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", max_width)


static func _card_style(
	bg: Color, edge: Color, border: int, content_margin: float
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_border_width_all(border)
	style.border_color = edge
	style.set_corner_radius_all(10)
	# Left unset at zero rather than set to zero: a StyleBoxFlat's margins default
	# to -1, meaning "let the control decide", and pinning them to 0 would strip
	# the padding Godot gives a button's own label.
	if content_margin > 0.0:
		style.set_content_margin_all(content_margin)
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	return style


static func _primary_style(fill: Color) -> StyleBoxFlat:
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


static func _style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	# The riveted end caps are the non-stretching part of the authored sprite.
	style.set_texture_margin(SIDE_LEFT, 34.0)
	style.set_texture_margin(SIDE_RIGHT, 34.0)
	# Vertically this is a single scalable band. Slicing the 2x source on both
	# axes made Godot preserve the source cap height inside the control, leaving
	# only ~60% of short buttons painted. Horizontal-only slicing fills every
	# authored button height while keeping the rounded riveted ends intact.
	style.set_texture_margin(SIDE_TOP, 0.0)
	style.set_texture_margin(SIDE_BOTTOM, 0.0)
	style.set_content_margin(SIDE_LEFT, 14.0)
	style.set_content_margin(SIDE_TOP, 6.0)
	style.set_content_margin(SIDE_RIGHT, 14.0)
	style.set_content_margin(SIDE_BOTTOM, 6.0)
	return style
