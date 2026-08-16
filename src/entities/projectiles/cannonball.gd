class_name Cannonball
extends Node2D
## A single shot in flight. Pooled, and driven by [ProjectileSystem] rather than
## by its own `_process`.
##
## The trajectory is analytic: given a launch point, an impact point and a flight
## time, position is a lerp and altitude is a sine bump. Nothing integrates, so
## the impact point is known the instant the gun fires. That is not just cheaper
## than gravity — it is what lets the AI lead a moving target correctly and lets
## the HUD draw an accurate incoming-fire telegraph.

## Altitude is faked by offsetting the sprite upward and shrinking its shadow.
## These are the shadow's scale at ground level and at the top of the arc.
const SHADOW_SCALE_GROUND: float = 1.0
const SHADOW_SCALE_APEX: float = 0.45
const SHADOW_ALPHA: float = 0.28
## Shipping PNGs are rendered at 2x nominal size, so 0.5 is nominal.
##
## Held above nominal deliberately. Ballistic shot is the game's most-repeated
## read — you are meant to watch a ball travel and see whether you led the target
## correctly — and at 0.5 the 24px master lands as a ~10px dark speck that is
## genuinely hard to follow over the ocean shader. The ball is a gameplay
## indicator first and a physical object second.
const ART_SCALE: float = 0.95

var origin: Vector2 = Vector2.ZERO
var impact_point: Vector2 = Vector2.ZERO
var flight_time: float = 1.0
var elapsed: float = 0.0
var arc_height: float = 40.0

var damage: float = 10.0
var primary_bar: AmmoType.Bar = AmmoType.Bar.HULL
var splash_bar_mul: float = 0.0
var aoe_radius: float = 0.0
var burn_dps: float = 0.0
var burn_duration: float = 0.0
var crew_kill: float = 0.0
var impact_pool: StringName = &"impact"
var shooter: Node2D = null
var shooter_team: int = 0
## The gun's maximum reach for this shot, so the impact can be priced against how
## far the ball actually had to travel. See [ProjectileSystem._range_falloff].
var reach: float = 1.0
## Colour of the streak [ProjectileSystem] draws behind this ball. Taken from the
## ammo's own tint, so the trail carries the same "what is in the air" information
## the ball does, at a size that is readable while it is still moving.
var trail_color: Color = Color(1, 1, 1, 0)
## Scale the ball was launched at, so altitude does not fight the ammo's size.
var _visual_scale: float = 1.0

var _ball: Sprite2D
var _shadow: Sprite2D


func _ready() -> void:
	_ball = get_node_or_null(^"Ball") as Sprite2D
	_shadow = get_node_or_null(^"Shadow") as Sprite2D
	if _shadow != null:
		_shadow.modulate.a = SHADOW_ALPHA


func launch(
	from: Vector2, to: Vector2, ammo: AmmoType, shot_damage: float, from_ship: Node2D, team: int
) -> void:
	origin = from
	impact_point = to
	elapsed = 0.0
	shooter = from_ship
	shooter_team = team
	damage = shot_damage

	primary_bar = ammo.primary_bar
	splash_bar_mul = ammo.splash_bar_mul
	aoe_radius = ammo.aoe_radius
	burn_dps = ammo.burn_dps
	burn_duration = ammo.burn_duration
	crew_kill = ammo.crew_kill
	impact_pool = ammo.impact_pool

	var distance: float = from.distance_to(to)
	flight_time = maxf(0.08, distance / maxf(1.0, ammo.muzzle_speed))
	# A long shot arcs higher, which is what makes range legible at a glance.
	arc_height = ammo.arc_height * clampf(distance / 600.0, 0.5, 2.2)

	if _ball != null:
		if ammo.projectile_texture != null:
			_ball.texture = ammo.projectile_texture
		# Colour and size are what make five shot types tellable apart in flight
		# without five sprites. Mid-fight the player needs to know at a glance what
		# is in the air, both theirs and the enemy's.
		_ball.self_modulate = ammo.tint
		_ball.scale = Vector2.ONE * ammo.visual_scale * ART_SCALE
	_visual_scale = ammo.visual_scale
	# `AmmoType.trail_color` is authored transparent and nothing sets it yet, so
	# fall back to the tint. That way all five shot types get a colour-matched
	# streak for free and none of them can be authored into invisibility by accident.
	trail_color = ammo.trail_color if ammo.trail_color.a > 0.0 else Color(ammo.tint, 0.7)

	global_position = from
	_apply_altitude(0.0)


## Advances the shot. Returns true on the frame it lands.
func advance(delta: float) -> bool:
	elapsed += delta
	var t: float = elapsed / flight_time
	if t >= 1.0:
		global_position = impact_point
		_apply_altitude(0.0)
		return true

	global_position = origin.lerp(impact_point, t)
	_apply_altitude(sin(t * PI))
	return false


## `height01` is 0 at the muzzle and at the impact, 1 at the apex.
func _apply_altitude(height01: float) -> void:
	if _ball != null:
		_ball.position.y = -arc_height * height01
	if _shadow != null:
		# Altitude and ammo size both scale the shadow, so they multiply rather
		# than one overwriting the other.
		_shadow.scale = (
			Vector2.ONE
			* lerpf(SHADOW_SCALE_GROUND, SHADOW_SCALE_APEX, height01)
			* _visual_scale
			* ART_SCALE
		)


## Unit vector along the ball's ground track. What raking fire is measured
## against — see [method Ship.rake_multiplier].
func travel_direction() -> Vector2:
	var track: Vector2 = impact_point - origin
	return track.normalized() if track.length_squared() > 0.01 else Vector2.UP


## How far along the flight this ball is, 0 to 1.
func progress() -> float:
	return clampf(elapsed / maxf(0.001, flight_time), 0.0, 1.0)


func ground_distance() -> float:
	return origin.distance_to(impact_point)


## Where the *sprite* is at normalised flight time `t`: the ground track plus the
## faked altitude.
##
## The trail has to be drawn through this rather than through `global_position`.
## The node itself sits on the ground track — that is where the shadow belongs and
## where the hit is resolved — while the ball is offset upward by as much as the
## full arc height. A streak along the ground reads as a line the ball is nowhere
## near, which looks like a rendering fault rather than like a shot.
func visual_position_at(t: float) -> Vector2:
	var clamped: float = clampf(t, 0.0, 1.0)
	return (
		origin.lerp(impact_point, clamped)
		+ Vector2(0.0, -arc_height * sin(clamped * PI))
	)


func _pool_release() -> void:
	shooter = null
	elapsed = 0.0
	reach = 1.0
	_visual_scale = 1.0
	trail_color = Color(1, 1, 1, 0)
