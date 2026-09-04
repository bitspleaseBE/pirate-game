extends Node3D
## A vertical slice of the game in 3D, to decide whether the 2D one is at its
## ceiling.
##
##   godot spike/spike3d.tscn -- --shot          # four camera angles to PNG
##   godot spike/spike3d.tscn                    # or just look at it
##
## **This is a spike. Nothing in the game imports it and nothing here is meant to
## survive.** It exists because "we have hit a ceiling with 2D" is a claim that
## can be settled with a screenshot far more cheaply than with a rewrite, and
## because the parts of a 3D port that are actually risky — a displaced ocean that
## still runs on WebGL2, and a hull that floats on it convincingly — are exactly
## the parts you can build in one file.
##
## What it deliberately does *not* do: any of the 187 sprites, the HUD, the
## gunnery, the islands, the AI. Those are work, but they are known work. The
## unknowns are here.
##
## The hull is a box. That is the point of a spike — if the sea and the motion do
## not convince with a box on them, no amount of ship modelling will save it, and
## if they do convince, the box is the cheapest possible way to have learned it.

const SEA_SHADER: Shader = preload("res://spike/sea3d.gdshader")

## Extent of the water plane, and how finely it is cut.
##
## 240 subdivisions over 6000 units is a 25-unit quad — about half the beam of a
## Sloop, which is fine enough that the hull sits on a smooth surface rather than
## on visible facets. It is 58k vertices, which is nothing for a desktop GPU and
## is the number worth watching on a phone: the real game would carry a couple of
## LOD rings rather than one dense plane.
const SEA_EXTENT: float = 6000.0
const SEA_SUBDIVIDE: int = 240

## Same units the 2D game uses — one unit is one pixel there — so the wave table
## transfers without rescaling and a hull radius is still 46.
const HULL_RADIUS: float = 46.0
const HULL_LENGTH: float = 150.0
const HULL_BEAM: float = 52.0
const HULL_DRAFT: float = 26.0

## Peak-to-trough of the whole wave field.
const WAVE_HEIGHT: float = 30.0

## How far the hull is sampled fore, aft and abeam to work out how it is lying.
## Slightly inside its own ends, because a hull rides on its waterline length
## rather than pivoting about its extremities.
const SAMPLE_FORE: float = HULL_LENGTH * 0.38
const SAMPLE_BEAM: float = HULL_BEAM * 0.45

## Camera angles the screenshot pass walks through, in degrees below horizontal.
## 90 is the game's present view, straight down; the rest are what tilting buys.
const SHOT_PITCHES: Array[float] = [90.0, 62.0, 40.0, 24.0]
## Far enough back that several wavelengths are in frame. The dominant swell is
## about 1100 units long, and the first attempt at 620 put the camera inside a
## single flank of it — the sea rendered as one smooth hill and the spike looked
## worse than the 2D game it was meant to be tested against. This is also roughly
## the width of world the 2D camera shows, so the two are comparable.
const CAMERA_DISTANCE: float = 2100.0

var _sea: MeshInstance3D
var _sea_material: ShaderMaterial
var _hull: Node3D
var _camera: Camera3D
var _time: float = 0.0
var _wind_angle: float = 0.6
## Where the hull is on the water, and which way it is pointing. Driven on a slow
## circle so a screenshot catches it on a different point of sail each time.
var _sail_angle: float = 0.0


func _ready() -> void:
	_build_environment()
	_build_sea()
	_build_hull()
	_build_camera()

	if "--shot" in OS.get_cmdline_user_args():
		_capture()


func _process(delta: float) -> void:
	_time += delta
	_sea_material.set_shader_parameter("wave_time", _time)
	_sail_angle += delta * 0.12
	_place_hull()
	_place_camera(_camera_pitch)


# --- Scene ------------------------------------------------------------------

## Sky and sun. The 2D game has one hard-coded sun vector shared between the
## ocean shader, the terrain shader and every drop shadow; here it is an actual
## light, and everything is lit by it because it is there rather than because
## three files agree about a constant.
func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.28, 0.45, 0.72)
	sky_material.sky_horizon_color = Color(0.72, 0.80, 0.86)
	sky_material.ground_bottom_color = Color(0.16, 0.24, 0.34)
	sky_material.ground_horizon_color = Color(0.72, 0.80, 0.86)
	sky_material.sun_angle_max = 12.0

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	# Haze at the far edge of the plane, so the sea does not simply stop at a hard
	# line. In the 2D game there is no distance for anything to fade into.
	env.fog_enabled = true
	env.fog_light_color = Color(0.70, 0.79, 0.86)
	env.fog_density = 0.00012

	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	# The same low sun the 2D ocean and terrain shaders share, as a real light.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34.0, -128.0, 0.0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	add_child(sun)


func _build_sea() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SEA_EXTENT, SEA_EXTENT)
	plane.subdivide_width = SEA_SUBDIVIDE
	plane.subdivide_depth = SEA_SUBDIVIDE

	_sea_material = ShaderMaterial.new()
	_sea_material.shader = SEA_SHADER
	_sea_material.set_shader_parameter("wind_angle", _wind_angle)
	_sea_material.set_shader_parameter("wave_height", WAVE_HEIGHT)

	_sea = MeshInstance3D.new()
	_sea.name = "Sea"
	_sea.mesh = plane
	_sea.material_override = _sea_material
	# The displacement happens in the vertex shader, so Godot's culling still
	# thinks the plane is flat and clips it early at a low camera angle.
	_sea.custom_aabb = AABB(
		Vector3(-SEA_EXTENT, -WAVE_HEIGHT * 2.0, -SEA_EXTENT),
		Vector3(SEA_EXTENT * 2.0, WAVE_HEIGHT * 4.0, SEA_EXTENT * 2.0)
	)
	add_child(_sea)


## A box with a bow on it. Deliberately crude — see the class comment.
func _build_hull() -> void:
	_hull = Node3D.new()
	_hull.name = "Hull"
	add_child(_hull)

	var timber := StandardMaterial3D.new()
	timber.albedo_color = Color(0.42, 0.29, 0.18)
	timber.roughness = 0.85

	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(HULL_BEAM, HULL_DRAFT, HULL_LENGTH * 0.72)
	body.mesh = box
	body.material_override = timber
	_hull.add_child(body)

	# A wedge forward, so the box has a heading you can read at a glance. Enough
	# to tell pitch from roll in a still frame, which is the whole job.
	var bow := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(HULL_BEAM, HULL_DRAFT, HULL_LENGTH * 0.28)
	bow.mesh = prism
	bow.material_override = timber
	bow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	bow.position = Vector3(0.0, 0.0, -HULL_LENGTH * 0.5)
	_hull.add_child(bow)

	var canvas := StandardMaterial3D.new()
	canvas.albedo_color = Color(0.88, 0.84, 0.74)
	canvas.cull_mode = BaseMaterial3D.CULL_DISABLED
	canvas.roughness = 0.9

	var mast := MeshInstance3D.new()
	var pole := CylinderMesh.new()
	pole.top_radius = 2.4
	pole.bottom_radius = 3.2
	pole.height = 150.0
	mast.mesh = pole
	mast.material_override = timber
	mast.position = Vector3(0.0, 75.0, -8.0)
	_hull.add_child(mast)

	var sail := MeshInstance3D.new()
	var cloth := QuadMesh.new()
	cloth.size = Vector2(96.0, 92.0)
	sail.mesh = cloth
	sail.material_override = canvas
	sail.position = Vector3(0.0, 88.0, 6.0)
	_hull.add_child(sail)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 48.0
	_camera.far = 12000.0
	add_child(_camera)
	_place_camera(_camera_pitch)


# --- Motion -----------------------------------------------------------------

var _camera_pitch: float = 62.0


## Sits the hull in the water and lets the water decide how it is lying.
##
## This is the part that cannot be done in the 2D game at all. There, heave is a
## scale pulse, roll is an in-plane rotation the code comments admit is a fudge,
## and pitch is a foreshortening — three tricks that each approximate one axis and
## never interact. Here the surface is sampled at four points around the hull and
## the orientation simply *is* whatever plane those points describe. A quartering
## sea rolls and pitches her at once, because it does.
func _place_hull() -> void:
	var pos := Vector2(cos(_sail_angle), sin(_sail_angle)) * 900.0
	# Heading tangent to the circle she is sailing, so she works through every
	# point of sail relative to a fixed wind.
	var heading: Vector2 = Vector2(-sin(_sail_angle), cos(_sail_angle))

	var fore: Vector2 = pos + heading * SAMPLE_FORE
	var aft: Vector2 = pos - heading * SAMPLE_FORE
	var beam: Vector2 = Vector2(-heading.y, heading.x) * SAMPLE_BEAM
	var port: Vector2 = pos - beam
	var starboard: Vector2 = pos + beam

	var h_fore: float = _wave_height_at(fore)
	var h_aft: float = _wave_height_at(aft)
	var h_port: float = _wave_height_at(port)
	var h_starboard: float = _wave_height_at(starboard)

	var centre: float = (h_fore + h_aft + h_port + h_starboard) * 0.25
	# Trim by the bow-to-stern difference, heel by the beam-to-beam one. Both are
	# real angles off real samples rather than a curve fitted to look right.
	var pitch: float = atan2(h_fore - h_aft, SAMPLE_FORE * 2.0)
	var roll: float = atan2(h_starboard - h_port, SAMPLE_BEAM * 2.0)

	# Down by most of her draft, so she sits *in* the water. The first pass had
	# her centre on the surface and she read as hovering above it.
	_hull.position = Vector3(pos.x, centre - HULL_DRAFT * 0.30, pos.y)
	_hull.rotation = Vector3.ZERO
	_hull.rotate_y(-heading.angle() - PI * 0.5)
	_hull.rotate_object_local(Vector3.RIGHT, pitch)
	_hull.rotate_object_local(Vector3.FORWARD, roll)


## The GDScript twin of the shader's `wave_at`. Same table, same crest shaping —
## if these two ever disagree the hull floats above or sinks into its own sea,
## which is exactly the failure the 2D game guards against by having
## `Ocean.SWELL` mirror the first three rows of the shader's table.
func _wave_height_at(p: Vector2) -> float:
	const WAVES: Array[Vector4] = [
		Vector4(0.00, 0.00570, 1.0000, 0.42),
		Vector4(-0.41, 0.00982, 0.5224, 0.55),
		Vector4(0.63, 0.01340, 0.3446, 0.64),
		Vector4(-0.22, 0.02438, 0.1704, 0.87),
		Vector4(1.08, 0.03336, 0.1121, 1.02),
		Vector4(-0.87, 0.06428, 0.0524, 1.41),
		Vector4(1.36, 0.08794, 0.0344, 1.65),
		Vector4(-1.51, 0.15310, 0.0178, 2.18),
	]
	const AMPLITUDE_TOTAL: float = 2.2437
	var height: float = 0.0
	for w: Vector4 in WAVES:
		var angle: float = _wind_angle + w.x
		var dir := Vector2(cos(angle), sin(angle))
		var phase: float = p.dot(dir) * w.y - _time * w.w
		var u: float = sin(phase) * 0.5 + 0.5
		height += (2.0 * u * u - 1.0) * w.z
	return height * (WAVE_HEIGHT / AMPLITUDE_TOTAL)


## Frames the hull from `pitch` degrees above the horizontal.
##
## 90 is the game as it stands — straight down, which is the only angle a
## sprite-based top-down game can offer, because every hull is a painted plan view
## and tilting the camera would show it edge-on as a flat card.
func _place_camera(pitch_deg: float) -> void:
	var focus: Vector3 = _hull.position
	var pitch: float = deg_to_rad(pitch_deg)
	# Behind and above, on the hull's own quarter, so a tilted shot has the ship
	# working away from the camera rather than sideways across it.
	var bearing: float = _sail_angle + PI * 0.35
	var offset := Vector3(
		cos(bearing) * cos(pitch), sin(pitch), sin(bearing) * cos(pitch)
	) * CAMERA_DISTANCE
	_camera.position = focus + offset
	# Straight down is the one angle where the view direction is colinear with
	# world up, which leaves the roll undefined. Hand it the hull's own heading to
	# keep the frame stable — which is, incidentally, the whole reason a top-down
	# game never has to think about camera roll and a tilted one does.
	var up: Vector3 = Vector3.UP
	if pitch_deg > 88.0:
		up = Vector3(cos(bearing), 0.0, sin(bearing))
	_camera.look_at(focus + Vector3(0.0, 20.0, 0.0), up)


# --- Screenshots ------------------------------------------------------------

func _capture() -> void:
	var dir: String = "user://shots"
	DirAccess.make_dir_recursive_absolute(dir)
	# Let the sea build up some texture before photographing it — at t=0 every
	# component is in phase and the surface is at its least characteristic.
	var settle: float = 0.0
	while settle < 6.0:
		await get_tree().process_frame
		settle += 1.0 / 60.0

	for pitch: float in SHOT_PITCHES:
		_camera_pitch = pitch
		_place_camera(pitch)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path: String = "%s/spike3d_%02d.png" % [dir, int(pitch)]
		get_viewport().get_texture().get_image().save_png(path)

	print("SPIKE3D: %s" % ProjectSettings.globalize_path(dir))
	get_tree().quit(0)
