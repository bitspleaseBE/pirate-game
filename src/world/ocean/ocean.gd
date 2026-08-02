class_name Ocean
extends Node2D
## A single camera-locked quad that is the whole sea.
##
## Every frame the quad is repositioned and resized to exactly cover the camera's
## world rect, and the shader is told where that rect sits in world space. The
## result is one draw call and one screen of fragments no matter how large the
## voyage is. A tiled ocean would have been thousands of quads and a streaming
## problem, for an identical image.

const SHADER: Shader = preload("res://src/world/ocean/ocean.gdshader")

## Slight overdraw so a fast camera never shows a seam at the screen edge.
const OVERDRAW: float = 1.02

var _surface: ColorRect
var _material: ShaderMaterial


func _ready() -> void:
	z_index = -100
	z_as_relative = false

	_material = ShaderMaterial.new()
	_material.shader = SHADER

	_surface = ColorRect.new()
	_surface.name = "Surface"
	_surface.material = _material
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)

	Quality.tier_changed.connect(_on_quality_changed)
	_apply_quality()


func _process(_delta: float) -> void:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	var zoom: Vector2 = camera.zoom
	var world_size: Vector2 = (
		Vector2(viewport_size.x / maxf(0.01, zoom.x), viewport_size.y / maxf(0.01, zoom.y))
		* OVERDRAW
	)
	var top_left: Vector2 = camera.get_screen_center_position() - world_size * 0.5

	global_position = top_left
	_surface.size = world_size
	_material.set_shader_parameter("world_offset", top_left)
	_material.set_shader_parameter("world_size", world_size)


func _apply_quality() -> void:
	_material.set_shader_parameter("wave_octaves", Quality.ocean_wave_octaves)
	_material.set_shader_parameter("caustics_enabled", Quality.ocean_caustics)


func _on_quality_changed(_tier: int) -> void:
	_apply_quality()
