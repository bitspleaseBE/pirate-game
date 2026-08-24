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

## The third thing here is not a look but a *unit*, and it applies to every
## screen: see [constant DESIGN_SIZE] and [method ui_scale]. A vocabulary of
## buttons is worth nothing if the buttons come out four millimetres tall.

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
## The *on* state — see [method apply_card_selected]. A warm fill against the
## cold navy of every other card, and a gold edge at full strength rather than
## the featured edge's half.
const CARD_BG_SELECTED: Color = Color(0.207, 0.149, 0.063)
const CARD_EDGE_SELECTED: Color = Color(0.941, 0.769, 0.325)
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


# --- Fitting the glass ------------------------------------------------------
#
# Every layout number in this game — a button height, a panel width, a font size
# — is written against DESIGN_SIZE. On a 1280x720 desktop window that is one unit
# per pixel and nothing here does anything. On a phone it is the difference
# between a playable game and the one that shipped: a 1280-unit-wide interface
# squeezed onto a 390 pt screen drew the shot rack fifteen points tall and set the
# port screen in five-point type. The counters were four millimetres wide.

## The viewport every screen is authored against, in UI units.
##
## One unit is one CSS pixel: the unit a phone browser reports, roughly 1/96 inch
## of actual glass, and *not* a hardware pixel — a modern phone has two or three
## of those per unit. It is the only unit in which "48 is big enough to hit with a
## thumb" is a true sentence on every device, which is why the whole interface is
## measured in it and [method ui_scale] exists to make it real.
const DESIGN_SIZE: Vector2 = Vector2(1280, 720)

## The floor under anything a finger has to hit, in UI units.
##
## Apple's guidance says 44 pt and Android's says 48 dp; the larger of the two
## costs a few units of padding and settles the argument. Below it, missing is no
## longer the player being clumsy.
const TOUCH_TARGET: float = 48.0

## The smallest type the game is allowed to set, in UI units.
##
## A floor, not a scale — most of the interface is already above it and is left
## alone. It exists for the two or three captions that were set at 10 and 12 for a
## desktop monitor viewed at arm's length, which is not where this game is played.
const MIN_FONT_SIZE: int = 13

## Below this width a screen is a phone held upright, and the corner-based layout
## the HUD is authored in stops fitting: the minimap and the shot rack together
## want more width than the screen has.
##
## Deliberately a width test rather than a device test. A desktop window dragged
## narrow gets the same treatment, which is the honest reading of the constraint —
## the layout answers the space it has, not the hardware it guesses at.
const COMPACT_WIDTH: float = 620.0

## Breathing room between a modal panel and the edge of the glass.
const MODAL_MARGIN: float = 12.0

## Below this height a screen is a phone lying on its side, and a modal has to
## account for every unit of it: the port's head and foot alone wanted 275 of the
## 390 available, which left its list below the legible minimum and pushed SET
## SAIL — the only way out of that screen — off the bottom of the glass.
const SHORT_HEIGHT: float = 520.0

## The rhythm between the parts of a modal, and the tightened version used when
## the screen is short. Six units of separation across six gaps is thirty-six
## units of list, which is the difference between showing a shop row and showing
## the top of one.
const MODAL_SEPARATION: int = 12
const MODAL_SEPARATION_TIGHT: int = 6

## Ceiling on [method ui_scale].
##
## Reached only by a window under 320 units on its short edge, where scaling the
## interface further would leave no room for the game under it. Something has to
## give at that size and it is not the touch targets, so the answer is that the
## HUD stops growing and the world keeps what is left.
const MAX_UI_SCALE: float = 4.0


## How many window pixels one UI unit should occupy on this screen.
##
## The whole mobile layout follows from this one number. Applied as the window's
## `content_scale_factor`, it makes the canvas exactly as many units across as the
## screen is CSS pixels across — so a 48-unit button is a 48 pt button, on a phone
## and on a desktop and on a tablet, and every hardcoded number in the interface
## becomes a physical measurement instead of a fraction of an unknown viewport.
##
## Never below 1.0: on anything as large as the design the interface is left
## exactly as authored, so a desktop window keeps the layout it has always had and
## a bigger monitor keeps scaling it up the way `canvas_items` stretch already did.
static func ui_scale(window: Window) -> float:
	# A headless run has a nominal 64px window that is not a screen and must not be
	# fitted to — every automated gate would otherwise play the game through a
	# 320-unit canvas that no player will ever see.
	if DisplayServer.get_name() == "headless":
		return 1.0
	var pixels: Vector2 = Vector2(window.size)
	if pixels.x < 1.0 or pixels.y < 1.0:
		return 1.0
	var logical: Vector2 = pixels / device_pixel_ratio()
	return clampf(
		maxf(DESIGN_SIZE.x / logical.x, DESIGN_SIZE.y / logical.y), 1.0, MAX_UI_SCALE
	)


## Fits the window's content scale to the screen it is on. Idempotent, and silent
## when nothing has changed — assigning the factor resizes the viewport and raises
## `size_changed`, so writing it unconditionally from a resize handler is a loop.
static func apply_ui_scale(window: Window) -> void:
	var factor: float = ui_scale(window)
	if not is_equal_approx(window.content_scale_factor, factor):
		window.content_scale_factor = factor


## Hardware pixels per CSS pixel.
##
## [method DisplayServer.screen_get_scale] is the one call that answers this on
## the platforms where it differs — the browser's `devicePixelRatio` on web, the
## display density on Android and iOS, the backing scale on a Retina Mac — and
## returns 1.0 everywhere else, which is the right answer everywhere else.
static func device_pixel_ratio() -> float:
	return maxf(DisplayServer.screen_get_scale(), 1.0)


## True when the viewport is too narrow for the two-corner layout.
static func is_compact(node: Node) -> bool:
	return node.get_viewport().get_visible_rect().size.x < COMPACT_WIDTH


## True when there is not enough height for a modal's ordinary rhythm.
static func is_short(node: Node) -> bool:
	return node.get_viewport().get_visible_rect().size.y < SHORT_HEIGHT


## The separation a modal's main column should use on this screen.
static func modal_separation(node: Node) -> int:
	return MODAL_SEPARATION_TIGHT if is_short(node) else MODAL_SEPARATION


## The width a centred modal panel may actually use.
static func modal_width(node: Node, preferred: float) -> float:
	var room: float = node.get_viewport().get_visible_rect().size.x - MODAL_MARGIN * 2.0
	return maxf(minf(preferred, room), 0.0)


## Raises a font size to the legibility floor, leaving anything already above it
## untouched.
static func readable(size: int) -> int:
	return maxi(size, MIN_FONT_SIZE)


## Sizes a modal's scrolling list so that the panel around it fits on the screen.
##
## The port and the roster are both a fixed head and foot with a list between
## them, and both asked for a list tall enough that the whole panel overflowed a
## phone in landscape — the last row and part of the button under it were simply
## painted off the bottom of the glass, which on the port screen is where SET SAIL
## lives. Measuring the panel with the list collapsed gives the height of
## everything that is *not* the list, and what is left over is what the list may
## have.
static func fit_list(panel: Control, list: Control, preferred: float, minimum: float) -> void:
	list.custom_minimum_size.y = 0.0
	var chrome: float = panel.get_combined_minimum_size().y
	var room: float = (
		panel.get_viewport().get_visible_rect().size.y - MODAL_MARGIN * 2.0 - chrome
	)
	list.custom_minimum_size.y = clampf(room, minimum, preferred)


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


## The one that is currently *on*, in a set where exactly one always is.
##
## Distinct from [method apply_card]'s `featured`, which marks the option a screen
## wants read first — that is a recommendation. This is a state. The HUD's shot
## rack always has exactly one slot loaded, and the player has to be able to find
## it in a glance mid-fight rather than by comparing five borders to each other,
## so the difference is a warm fill against cold navy as well as a brighter edge.
##
## Deliberately not [method apply_primary]. Solid brass is the loudest shape the
## vocabulary has and is reserved for the action that is not a choice between
## options; a rack of five is nothing but a choice between options.
static func apply_card_selected(button: Button) -> void:
	for state: String in ["normal", "hover", "focus", "pressed", "disabled"]:
		button.add_theme_stylebox_override(
			state, _card_style(CARD_BG_SELECTED, CARD_EDGE_SELECTED, 2, 0.0)
		)
	button.add_theme_color_override("font_color", INK_FEATURED)
	button.add_theme_constant_override("outline_size", 0)


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
