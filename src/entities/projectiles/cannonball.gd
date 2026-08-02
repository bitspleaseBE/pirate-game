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
		_ball.scale = Vector2.ONE * ammo.visual_scale
	_visual_scale = ammo.visual_scale

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
		)


func _pool_release() -> void:
	shooter = null
	elapsed = 0.0
	_visual_scale = 1.0
