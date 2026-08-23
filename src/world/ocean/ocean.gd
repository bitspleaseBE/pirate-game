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

## Must match `MAX_SHOALS` in the shader.
const MAX_SHOALS: int = 8
## How far a shelf reaches seaward of the mean coastline. Wide enough that the
## approach to an island is a stretch of water the player sails *through* rather
## than a rim they cross, and wide enough to swallow the difference between the
## mean radius and a headland.
const SHOAL_WIDTH_MIN: float = 700.0
const SHOAL_WIDTH_FACTOR: float = 1.4
## Camera travel that triggers a reselection of the nearest islands. The set only
## changes when the camera has moved a meaningful fraction of a shelf, so this is
## a handful of rebuilds per voyage rather than one per frame.
const SHOAL_REBUILD_DISTANCE: float = 128.0

## Multiplier on real time for the whole wave field.
const WAVE_SPEED: float = 1.0
## The wave clock wraps here so the phase accumulator never grows large enough for
## float32 to start quantising the fine chop. Same period Godot's own `TIME` uses.
const TIME_ROLLOVER: float = 3600.0

## The three leading lines of the shader's `WAVES` table, in the same units and
## with the same crest shaping. Ships ride this, so it has to be literally the
## water the player can see; if the two drift apart, hulls lift in the troughs.
##
## Only the swell is mirrored. The remaining five components have wavelengths
## shorter than a hull, and a ship does not rise to chop it spans — it sits
## through it. Skipping them also keeps this to three sines per ship per frame.
const SWELL: Array[Vector4] = [
	Vector4(0.00, 0.00570, 1.0000, 0.42),
	Vector4(-0.41, 0.00982, 0.5224, 0.55),
	Vector4(0.63, 0.01340, 0.3446, 0.64),
]
const SWELL_TOTAL: float = 1.8670

## The live Ocean, for [method sample]. There is exactly one sea.
static var instance: Ocean = null

## Source of the shallow-water shelves. Set by [Voyage] once the islands exist;
## until then the sea is uniformly deep, which is what an empty archipelago is.
var archipelago: Archipelago = null:
	set = _set_archipelago

var _surface: ColorRect
var _material: ShaderMaterial

## One Vector4 per island: xy = centre, z = mean radius, w = shelf width.
var _all_shoals: PackedVector4Array = PackedVector4Array()
var _shoals: PackedVector4Array = PackedVector4Array()
var _last_shoal_center: Vector2 = Vector2.INF

var _time: float = 0.0
var _wind_angle: float = 0.0


func _ready() -> void:
	instance = self
	z_index = -100
	z_as_relative = false

	_material = ShaderMaterial.new()
	_material.shader = SHADER

	_surface = ColorRect.new()
	_surface.name = "Surface"
	_surface.material = _material
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)

	_shoals.resize(MAX_SHOALS)

	Quality.tier_changed.connect(_on_quality_changed)
	_apply_quality()


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _process(delta: float) -> void:
	# Ahead of the camera check: the swell has to keep running for whatever is
	# sailing on it even on a frame where there is nothing to draw it into.
	_time = fmod(_time + delta * WAVE_SPEED, TIME_ROLLOVER)
	# Swell runs with the wind. Doing this in the shader rather than with a HUD
	# arrow alone means the player can read the wind by glancing at the sea, which
	# is how you would actually read it.
	if WindSystem.instance != null and WindSystem.instance.active:
		_wind_angle = WindSystem.instance.direction.angle()

	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return

	_material.set_shader_parameter("wave_time", _time)
	_material.set_shader_parameter("wind_angle", _wind_angle)

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

	_update_shoals(top_left + world_size * 0.5)


## Height and surface slope of the swell at a world position, as
## (height, d/dx, d/dy). Height is normalised to roughly -1..1; slope is in the
## shader's raw units, so a caller wants to scale it against a reference rather
## than read it as an angle.
##
## Static and null-safe because callers are ships, which exist in scenes that may
## have no sea at all — a ship on dry land in a test rig gets flat water.
static func sample(world_pos: Vector2) -> Vector3:
	if instance == null:
		return Vector3.ZERO
	return instance.swell_at(world_pos)


func swell_at(p: Vector2) -> Vector3:
	var height: float = 0.0
	var slope: Vector2 = Vector2.ZERO
	for w: Vector4 in SWELL:
		var angle: float = _wind_angle + w.x
		var dir: Vector2 = Vector2(cos(angle), sin(angle))
		var phase: float = p.dot(dir) * w.y - _time * w.w
		var s: float = sin(phase)
		var c: float = cos(phase)
		# Same shaped crest the shader draws: h = 2u^2 - 1 for u = (sin + 1) / 2.
		var u: float = s * 0.5 + 0.5
		height += (2.0 * u * u - 1.0) * w.z
		slope += dir * ((s + 1.0) * c) * w.z * w.y
	return Vector3(height / SWELL_TOTAL, slope.x, slope.y)


func _set_archipelago(value: Archipelago) -> void:
	archipelago = value
	_all_shoals.clear()
	_last_shoal_center = Vector2.INF
	if archipelago == null:
		return
	for island: Island in archipelago.islands:
		# The mean radius, not `outer_radius`: the shelf's inner edge is also where
		# the surf breaks, and a ring struck off the furthest headland would leave
		# a visible band of foam sitting out in open water on every bay.
		var radius: float = island.def.radius
		_all_shoals.append(
			Vector4(
				island.global_position.x,
				island.global_position.y,
				radius,
				maxf(SHOAL_WIDTH_MIN, radius * SHOAL_WIDTH_FACTOR)
			)
		)


## Hands the shader the islands nearest the camera.
##
## The shader loops over this array per fragment, so it is capped rather than
## unbounded: a screen is a fraction of the archipelago and never contains more
## than two or three islands, so the nearest eight is an approximation with no
## observable error. Islands beyond that are off screen by thousands of pixels.
func _update_shoals(center: Vector2) -> void:
	if _all_shoals.is_empty():
		return
	if center.distance_squared_to(_last_shoal_center) < SHOAL_REBUILD_DISTANCE ** 2:
		return
	_last_shoal_center = center

	var order: Array[int] = []
	for i: int in _all_shoals.size():
		order.append(i)
	if order.size() > MAX_SHOALS:
		order.sort_custom(
			func(a: int, b: int) -> bool:
				return _shoal_distance(a, center) < _shoal_distance(b, center)
		)

	var count: int = mini(order.size(), MAX_SHOALS)
	for slot: int in count:
		_shoals[slot] = _all_shoals[order[slot]]
	_material.set_shader_parameter("shoals", _shoals)
	_material.set_shader_parameter("shoal_count", count)


## Distance from `center` to the seaward edge of island `index`'s shelf.
func _shoal_distance(index: int, center: Vector2) -> float:
	var s: Vector4 = _all_shoals[index]
	return center.distance_to(Vector2(s.x, s.y)) - (s.z + s.w)


func _apply_quality() -> void:
	_material.set_shader_parameter("wave_octaves", Quality.ocean_wave_octaves)
	_material.set_shader_parameter("caustics_enabled", Quality.ocean_caustics)
	_material.set_shader_parameter("shore_foam_enabled", Quality.ocean_shore_foam)


func _on_quality_changed(_tier: int) -> void:
	_apply_quality()
