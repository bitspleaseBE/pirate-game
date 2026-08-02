class_name GameCamera
extends Camera2D
## Follows the fleet, allows a temporary look-around, and snaps back.
##
## The snap-back is the important part on a phone: the player drags to see what is
## coming, then takes their thumb off and the camera returns to the fight without
## them having to find it again.
##
## Clamping is delegated to Camera2D's own limits rather than done by hand — that
## way the smoothing and the clamp cannot fight each other and jitter at the edge
## of the world.

## Larger = snappier follow. Exponential, so it is frame-rate independent.
const FOLLOW_SHARPNESS: float = 4.0
const ZOOM_SHARPNESS: float = 8.0
const MIN_ZOOM: float = 0.40
const MAX_ZOOM: float = 1.40
## Framed so a duel at gun range fits on a phone screen while the hull is still
## big enough to read its damage bars. Zoom out to see the island, in to aim.
const DEFAULT_ZOOM: float = 0.85
## Seconds of no pan input before the view slides back to the fleet.
const PAN_SNAPBACK_DELAY: float = 2.0
const PAN_SNAPBACK_SHARPNESS: float = 3.0
## How far the player may look away from the fleet, in screens.
const MAX_PAN_SCREENS: float = 1.5
## Zoom is authored against this viewport height and rescaled for everything else.
##
## The world renders inside a SubViewportContainer with `stretch`, which sizes the
## SubViewport to the container's *pixel* size — that deliberately bypasses the
## project's `canvas_items` stretch scaling so we can drop render resolution. The
## cost is that raw `zoom` no longer means the same thing on every screen: on a
## Retina display or a tablet the SubViewport is far taller than 720px, so a fixed
## zoom silently frames twice as much world. Scaling by the height ratio keeps the
## framing identical from a 720p phone to a 1600p tablet.
const REFERENCE_HEIGHT: float = 720.0

var fleet: FleetController = null
var target_zoom: float = DEFAULT_ZOOM
var pan_offset: Vector2 = Vector2.ZERO

var _pan_idle: float = 0.0
var _focus: Vector2 = Vector2.ZERO


## Converts an authored zoom into one that frames the same amount of world on
## whatever viewport we actually got.
func _resolved_zoom() -> float:
	var height: float = get_viewport_rect().size.y
	if height < 1.0:
		return target_zoom
	return target_zoom * (height / REFERENCE_HEIGHT)


func _ready() -> void:
	zoom = Vector2.ONE * _resolved_zoom()
	# Godot's own smoothing would fight ours; we need the exact focus point for
	# the culling rect, so we drive position directly.
	position_smoothing_enabled = false
	make_current()
	EventBus.camera_registered.emit(self)


## Sets the camera's hard limits from the voyage bounds.
func set_world_bounds(bounds: Rect2) -> void:
	limit_left = roundi(bounds.position.x)
	limit_top = roundi(bounds.position.y)
	limit_right = roundi(bounds.end.x)
	limit_bottom = roundi(bounds.end.y)


func _process(delta: float) -> void:
	if fleet != null and is_instance_valid(fleet):
		_focus = fleet.centroid()

	_pan_idle += delta
	if _pan_idle > PAN_SNAPBACK_DELAY and pan_offset != Vector2.ZERO:
		pan_offset = pan_offset.lerp(
			Vector2.ZERO, 1.0 - exp(-PAN_SNAPBACK_SHARPNESS * delta)
		)
		if pan_offset.length() < 2.0:
			pan_offset = Vector2.ZERO

	global_position = global_position.lerp(
		_focus + pan_offset, 1.0 - exp(-FOLLOW_SHARPNESS * delta)
	)
	zoom = zoom.lerp(Vector2.ONE * _resolved_zoom(), 1.0 - exp(-ZOOM_SHARPNESS * delta))


## `screen_delta` is the drag in screen pixels; the camera moves the opposite way
## so the world tracks the thumb.
func apply_pan(screen_delta: Vector2) -> void:
	_pan_idle = 0.0
	pan_offset -= screen_delta / zoom
	var limit: float = get_viewport_rect().size.length() / zoom.x * MAX_PAN_SCREENS * 0.5
	if pan_offset.length() > limit:
		pan_offset = pan_offset.normalized() * limit


## `factor` > 1 zooms in.
func apply_zoom(factor: float) -> void:
	target_zoom = clampf(target_zoom * factor, MIN_ZOOM, MAX_ZOOM)


func recenter() -> void:
	pan_offset = Vector2.ZERO
	_pan_idle = PAN_SNAPBACK_DELAY


## Teleports rather than easing. Used when a voyage loads, so the first frame is
## already at the fleet instead of flying in from the origin.
func snap_to(world_pos: Vector2) -> void:
	_focus = world_pos
	pan_offset = Vector2.ZERO
	global_position = world_pos
	zoom = Vector2.ONE * _resolved_zoom()
	Cull.force_tick()


func screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos
