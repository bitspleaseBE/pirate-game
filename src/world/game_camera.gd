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

## Shake amplitudes, in screen pixels at the reference height.
##
## Per *gun*, not per volley: a broadside is fired as a staggered line of shots
## (see [constant Ship.gun_stagger]), so a four-gun Brig rolls four small kicks
## down its length instead of one flat thump. That is the whole reason the stagger
## exists, and until now none of it was felt.
const SHAKE_PER_GUN: float = 1.5
## Taking a hit shakes harder than giving one, and scales with the damage.
const SHAKE_HIT_BASE: float = 2.2
const SHAKE_HIT_PER_DAMAGE: float = 0.09
const SHAKE_SINK: float = 7.0
## Ceiling, so a Galleon broadside landing in a burning melee cannot make the
## screen unreadable. Shake is seasoning.
const MAX_SHAKE: float = 9.0
## Higher = the kick dies away faster. Exponential, so it is frame-rate independent.
const SHAKE_DECAY: float = 7.5

var fleet: FleetController = null
var target_zoom: float = DEFAULT_ZOOM
var pan_offset: Vector2 = Vector2.ZERO

var _pan_idle: float = 0.0
var _focus: Vector2 = Vector2.ZERO
var _point_out_at: Vector2 = Vector2.ZERO
var _point_out_left: float = 0.0
var _shake: float = 0.0


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

	# Only the player's own guns and hulls shake the screen. An enemy broadside
	# fired across the map is not something the player feels, and shaking for it
	# would turn a busy archipelago into permanent low-level rumble.
	EventBus.shot_fired.connect(_on_shot_fired)
	EventBus.ship_damaged.connect(_on_ship_damaged)
	EventBus.ship_sunk.connect(_on_ship_sunk)

	EventBus.camera_registered.emit(self)


## Sets the camera's hard limits from the voyage bounds.
func set_world_bounds(bounds: Rect2) -> void:
	limit_left = roundi(bounds.position.x)
	limit_top = roundi(bounds.position.y)
	limit_right = roundi(bounds.end.x)
	limit_bottom = roundi(bounds.end.y)


## Swings the camera to look at something for a moment, then drifts back to the
## fleet on its own.
##
## Used after a briefing: telling the player there are enemies is a sentence,
## showing them the enemies turning to meet you is the actual information. The
## return trip is automatic and uses the normal follow smoothing, so it reads as
## the camera looking over rather than as a cutscene.
func point_out(world_pos: Vector2, hold_sec: float) -> void:
	_point_out_at = world_pos
	_point_out_left = hold_sec
	pan_offset = Vector2.ZERO


func _process(delta: float) -> void:
	if fleet != null and is_instance_valid(fleet):
		_focus = fleet.centroid()

	if _point_out_left > 0.0:
		_point_out_left -= delta
		_focus = _point_out_at

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
	_apply_shake(delta)


## Shake goes on `offset`, never on `global_position`.
##
## `global_position` is the camera's logical focus: the culling rect is built from
## it and the follow lerp chases it. Jittering it would make the cull rect twitch
## and would fight the smoothing. `offset` displaces only the view, which is what
## a shake is.
func _apply_shake(delta: float) -> void:
	if _shake <= 0.01:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return
	_shake *= exp(-SHAKE_DECAY * delta)
	# Scaled the same way zoom is, so the kick is the same size on a phone as on a
	# tablet rather than shrinking with the world.
	var amplitude: float = _shake * (get_viewport_rect().size.y / REFERENCE_HEIGHT) / zoom.x
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amplitude


## Adds a kick. Amplitudes accumulate up to [constant MAX_SHAKE] so overlapping
## events build rather than the loudest one winning.
func shake(amount: float) -> void:
	_shake = minf(_shake + amount, MAX_SHAKE)


func _on_shot_fired(from: Node2D, _ammo: StringName, _origin: Vector2, _at: Vector2) -> void:
	var ship := from as Ship
	if ship != null and ship.team == Teams.PLAYER:
		shake(SHAKE_PER_GUN)


func _on_ship_damaged(ship: Node2D, amount: float, _bar: StringName) -> void:
	var hull := ship as Ship
	if hull != null and hull.team == Teams.PLAYER:
		shake(SHAKE_HIT_BASE + amount * SHAKE_HIT_PER_DAMAGE)


func _on_ship_sunk(ship: Node2D, killed_by: Node2D) -> void:
	# Either end of it is worth feeling: losing a hull, or being alongside one that
	# goes down.
	var hull := ship as Ship
	var killer := killed_by as Ship
	if (hull != null and hull.team == Teams.PLAYER) or (killer != null and killer.team == Teams.PLAYER):
		shake(SHAKE_SINK)


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
