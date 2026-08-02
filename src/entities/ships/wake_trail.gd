class_name WakeTrail
extends Line2D
## The turbulent water a hull leaves behind it.
##
## A ribbon rather than a particle emitter, for three reasons:
##
## 1. **It survives the LOW quality tier.** One Line2D is a single draw call, so
##    the motion cue stays on the devices that need it most. The particle wake it
##    replaces was the first thing culled, which meant the cheapest phones got a
##    game where nothing appeared to be moving.
## 2. **It curves.** A turning ship leaves a curved wake, which shows the player
##    where the hull has been and how hard it came round. Particles scatter; they
##    do not draw a line you can read.
## 3. **It shows drift.** When the hull skids, the wake visibly diverges from the
##    bow's heading. That is the clearest possible feedback that a ship has
##    momentum, and it costs nothing extra.
##
## It also communicates the wind for free: a ship clawing upwind barely has one.

## World distance between appended points. Smaller is smoother and costlier.
const POINT_SPACING: float = 26.0
## Ribbon length in points, before the quality multiplier.
const MAX_POINTS: int = 26
## Below this fraction of top speed the wake fades out entirely.
const MIN_SPEED_FRACTION: float = 0.12
## Seconds for the ribbon to fade after a ship stops.
const FADE_SEC: float = 1.1

var _ship: Ship
var _last_point: Vector2 = Vector2.ZERO
var _alpha: float = 0.0
var _max_points: int = MAX_POINTS


static func create_for(ship: Ship) -> WakeTrail:
	var trail := WakeTrail.new()
	trail._ship = ship
	trail.name = "WakeTrail"
	# World space, not ship space: the whole point is that the ribbon stays where
	# the water was churned, while the ship sails on.
	trail.top_level = true
	trail.z_index = -2
	trail.z_as_relative = false
	trail.joint_mode = Line2D.LINE_JOINT_ROUND
	trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	trail.antialiased = false
	return trail


func _ready() -> void:
	width = maxf(8.0, _ship.stats.hull_radius * 0.40)

	# Taper from a broad churn at the stern to nothing at the tail. Line2D's
	# width curve is sampled along the ribbon, and the oldest point is the far
	# end, so position along the line doubles as age.
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 0.15))
	taper.add_point(Vector2(0.25, 1.0))
	taper.add_point(Vector2(1.0, 0.35))
	width_curve = taper

	var fade := Gradient.new()
	# Churned water, not a painted stripe: low alpha even at the stern, and gone
	# entirely by the tail.
	fade.set_color(0, Color(0.82, 0.93, 1.0, 0.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.32))
	gradient = fade

	_apply_quality()
	Quality.tier_changed.connect(_on_quality_changed)
	_last_point = _stern_position()


func _process(delta: float) -> void:
	if _ship == null or not is_instance_valid(_ship) or not _ship.alive:
		_shrink(delta)
		return

	var speed_fraction: float = _ship.velocity.length() / maxf(1.0, _ship.stats.max_speed)
	# Fade with speed rather than snapping off, so a ship coasting to a stop
	# leaves a wake that settles instead of vanishing mid-frame.
	var target_alpha: float = clampf(
		(speed_fraction - MIN_SPEED_FRACTION) / (1.0 - MIN_SPEED_FRACTION), 0.0, 1.0
	)
	_alpha = move_toward(_alpha, target_alpha, delta / FADE_SEC)
	modulate.a = _alpha

	if _alpha <= 0.01:
		_shrink(delta)
		return

	var stern: Vector2 = _stern_position()
	if _last_point.distance_to(stern) < POINT_SPACING:
		# Still move the newest point with the ship so the ribbon stays attached.
		if get_point_count() > 0:
			set_point_position(get_point_count() - 1, stern)
		return

	add_point(stern)
	_last_point = stern
	while get_point_count() > _max_points:
		remove_point(0)


## Retracts the ribbon from the tail when there is nothing driving it.
func _shrink(delta: float) -> void:
	_alpha = move_toward(_alpha, 0.0, delta / FADE_SEC)
	modulate.a = _alpha
	if _alpha <= 0.01 and get_point_count() > 0:
		remove_point(0)


func _stern_position() -> Vector2:
	return _ship.global_position - _ship.forward() * _ship.stats.hull_radius * 0.85


func _apply_quality() -> void:
	match Quality.tier:
		Quality.Tier.LOW:
			_max_points = 12
		Quality.Tier.MEDIUM:
			_max_points = 18
		_:
			_max_points = MAX_POINTS
	while get_point_count() > _max_points:
		remove_point(0)


func _on_quality_changed(_tier: int) -> void:
	_apply_quality()
