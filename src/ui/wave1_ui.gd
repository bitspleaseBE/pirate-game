class_name Wave1UI
extends RefCounted
## Shared Wave 1 presentation for code-built and scene-authored buttons.

const BRASS_UP: Texture2D = preload("res://assets/wave1/ui/button_brass_up.png")
const BRASS_DOWN: Texture2D = preload("res://assets/wave1/ui/button_brass_down.png")
const BRASS_DISABLED: Texture2D = preload("res://assets/wave1/ui/button_brass_disabled.png")


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


static func set_icon(button: Button, texture: Texture2D, max_width: int = 40) -> void:
	button.icon = texture
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", max_width)


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
