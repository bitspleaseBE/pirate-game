class_name ProjectileSystem
extends Node2D
## Owns and integrates every shot in flight.
##
## One `_physics_process` for the whole battle instead of one per cannonball.
## With a hundred balls up that is the difference between one function call per
## frame and a hundred, and — because none of them is a physics body — zero
## physics-server work. Hit detection is a [SpatialGrid] radius query at the
## impact point.
##
## The system is a world-scoped singleton: ships need to fire without holding a
## reference to it, and there is exactly one battle at a time.

static var instance: ProjectileSystem = null

## How far outside a hull a ball still counts as a hit, in world units. Added to
## the target's own radius by the grid query. Generous on purpose: a broadside
## against a manoeuvring ship should mostly connect, or a fight with 5-second
## reloads never resolves and the player just watches splashes.
const HIT_TOLERANCE: float = 44.0

## Longest streak drawn behind a ball, in world units. Shortened near the muzzle
## and near the impact so a shot grows a tail as it leaves and loses it as it
## arrives, rather than a fixed dash sliding across the water.
const TRAIL_LENGTH: float = 74.0

## Shots beyond the quality budget are dropped at the muzzle. Dropping the
## newest is wrong (the player just fired it), so the oldest in flight is
## recycled instead.
var _active: Array[Cannonball] = []
var _fallback_ammo: AmmoType


func _ready() -> void:
	instance = self
	# So a missing .tres never means "guns do not work".
	_fallback_ammo = AmmoType.new()


func _exit_tree() -> void:
	if instance == self:
		instance = null
	_active.clear()


func active_count() -> int:
	return _active.size()


## Fires one shot. `aim_at` should already be lead-corrected by the caller.
func fire(
	from: Vector2, aim_at: Vector2, ammo: AmmoType, damage: float, shooter: Node2D, team: int,
	max_range: float
) -> void:
	if ammo == null:
		ammo = _fallback_ammo

	# Out-of-range shots fall short rather than silently not existing — the
	# splash is the feedback that tells the player they are too far away.
	var to_target: Vector2 = aim_at - from
	var reach: float = ammo.effective_range(max_range)
	if to_target.length() > reach:
		aim_at = from + to_target.normalized() * reach

	if _active.size() >= Quality.max_projectiles:
		_resolve(_active[0], false)
		_active.remove_at(0)

	var ball: Cannonball = Pools.acquire(&"cannonball") as Cannonball
	if ball == null:
		return
	ball.launch(from, aim_at, ammo, damage, shooter, team)
	_active.append(ball)


func _physics_process(delta: float) -> void:
	if _active.is_empty():
		return

	# Iterate backwards so removing a landed shot cannot skip the next one.
	for i: int in range(_active.size() - 1, -1, -1):
		var entry: Variant = _active[i]
		if not is_instance_valid(entry):
			_active.remove_at(i)
			continue
		var ball: Cannonball = entry
		if ball.advance(delta):
			_resolve(ball, true)
			_active.remove_at(i)

	# Every trail in one canvas item, on the same reasoning as [WorldOverlay]: a
	# Line2D per ball would be up to `Quality.max_projectiles` extra canvas items
	# being transformed and batched, for a two-point streak each.
	queue_redraw()


## Draws a short streak behind every ball in flight.
##
## Ballistic shot only pays off if the player can actually follow a ball and see
## whether they led the target. The ball itself is a small dark dot by necessity —
## it is iron — so the streak is what makes the trajectory legible over a moving
## ocean, and it is colour-matched to the shot type so a chain shot in the air is
## tellable from a grape at a glance.
##
## Drawn through the ball's *rendered* position, arc and all — see
## [method Cannonball.visual_position_at] for why the ground track is the wrong
## line even though it is where the shot really is.
func _draw() -> void:
	for entry: Variant in _active:
		if not is_instance_valid(entry):
			continue
		var ball: Cannonball = entry
		if ball.trail_color.a <= 0.0:
			continue

		# Fade in off the muzzle and out into the impact, so the streak has ends.
		var t: float = ball.progress()
		var taper: float = minf(1.0, minf(t, 1.0 - t) * 6.0)
		if taper <= 0.01:
			continue

		# Trail length converted into flight-time, so a short lob and a long shot both
		# carry the same length of streak instead of it scaling with range.
		var span: float = TRAIL_LENGTH * taper / maxf(1.0, ball.ground_distance())
		draw_line(
			ball.visual_position_at(t - span),
			ball.visual_position_at(t),
			Color(ball.trail_color, ball.trail_color.a * taper),
			3.0
		)


func _resolve(ball: Cannonball, spawn_effects: bool) -> void:
	var point: Vector2 = ball.impact_point
	var victims: Array[Node2D] = _find_victims(ball, point)

	for victim: Node2D in victims:
		_apply_damage(ball, victim)

	if spawn_effects:
		if victims.is_empty():
			Pools.spawn_effect(&"splash", point)
			Audio.play_at(&"splash", point, -4.0)
		else:
			var effect: StringName = &"explosion" if ball.aoe_radius > 0.0 else ball.impact_pool
			Pools.spawn_effect(&"impact" if effect == &"" else effect, point)
			Audio.play_at(&"impact_wood", point)

	Pools.release(&"cannonball", ball)


func _find_victims(ball: Cannonball, point: Vector2) -> Array[Node2D]:
	# A shot only ever hurts the other side. Friendly fire would make the swarm
	# fights unreadable, and the player would blame the game, not their aim.
	var mask: int = SpatialGrid.KIND_STRUCTURE | Teams.hostile_grid_kind(ball.shooter_team)

	if ball.aoe_radius > 0.0:
		return Grid.query_radius(point, ball.aoe_radius, mask)

	# Direct hit. The grid already accounts for each entity's hull radius, so this
	# is "the ball landed within HIT_TOLERANCE of the hull".
	var nearest: Node2D = Grid.query_nearest(point, HIT_TOLERANCE, mask)
	var out: Array[Node2D] = []
	if nearest != null:
		out.append(nearest)
	return out


func _apply_damage(ball: Cannonball, victim: Node2D) -> void:
	if not victim.has_method(&"apply_damage"):
		return

	# Area damage falls off from the centre, so clustering is punished but a
	# near-miss on a lone ship is not a full hit.
	var falloff: float = 1.0
	if ball.aoe_radius > 0.0:
		var d: float = ball.impact_point.distance_to(victim.global_position)
		falloff = clampf(1.0 - d / ball.aoe_radius, 0.25, 1.0)

	# A ball outlives the gun that fired it. If the shooter sank during the shot's
	# flight it has already been freed, and handing a freed instance to a typed
	# `Node2D` parameter fails the *whole* call — so a dying ship's last broadside
	# landed, splashed, played its impact sound and dealt no damage at all. Silent,
	# intermittent, and only in the one situation where the shot mattered most.
	var credit: Node2D = ball.shooter if is_instance_valid(ball.shooter) else null
	victim.call(&"apply_damage", ball.damage * falloff, int(ball.primary_bar), credit)

	if ball.splash_bar_mul > 0.0:
		var splash: float = ball.damage * ball.splash_bar_mul * falloff
		for bar: int in [AmmoType.Bar.HULL, AmmoType.Bar.SAILS, AmmoType.Bar.CANNONS]:
			if bar != int(ball.primary_bar):
				victim.call(&"apply_damage", splash, bar, credit)

	if ball.burn_dps > 0.0 and victim.has_method(&"apply_burn"):
		victim.call(&"apply_burn", ball.burn_dps, ball.burn_duration)
	if ball.crew_kill > 0.0 and victim.has_method(&"apply_crew_loss"):
		victim.call(&"apply_crew_loss", ball.crew_kill)

	EventBus.projectile_impact.emit(ball.impact_point, ball.impact_pool, victim)
