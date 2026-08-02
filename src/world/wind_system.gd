class_name WindSystem
extends Node
## The voyage's wind: one slowly-turning vector that every sail answers to.
##
## Wind gives the map a permanent tactical axis that has nothing to do with where
## the islands are. Being **upwind of your enemy** — the weather gage, and the
## thing age-of-sail captains actually fought over — means you choose when to
## close and they cannot run from you. That is the whole reason this exists.
##
## Deliberately a *soft* model: there is no no-go zone and no being caught in
## irons. A ship pointed straight into the wind still makes way, just badly. On a
## one-thumb mobile game an unforgiving wind reads as a broken game rather than a
## deep one, and the tactical payoff survives the softening intact.
##
## World-scoped singleton, like [ProjectileSystem] — there is one wind.

static var instance: WindSystem = null

## Speed as a fraction of a hull's maximum, sampled every 18° from dead upwind
## (index 0) to dead downwind (index 10).
##
## The shape is real: the fastest point of sail is a **broad reach** around 110°,
## not downwind. Running dead before the wind is slower because the sails blanket
## each other and the apparent wind drops. Beating straight upwind is worst.
##
## The floor is 0.55, not the ~0.40 realism would suggest. At a Sloop's 108 px/s
## a 0.40 upwind leg is 43 px/s, which turns crossing the archipelago into a
## chore — the penalty stopped reading as a tactical cost and started reading as
## the game being slow. 0.55 still makes the weather gage worth having and still
## makes a downwind escape work, without taxing ordinary travel.
const POLAR: PackedFloat32Array = [
	0.55, 0.62, 0.72, 0.84, 0.93, 0.98, 1.00, 0.99, 0.94, 0.89, 0.85
]

## How far a rig's character bends the polar toward its favoured points of sail.
const RIG_TILT_STRENGTH: float = 0.30

## Degrees the wind backs or veers per second. Slow enough to be a condition you
## sail in rather than a mechanic you fight, fast enough that the weather gage is
## never permanently settled.
const SHIFT_DEG_PER_SEC: float = 0.9
## Seconds per full cycle of the strength oscillation.
const GUST_PERIOD: float = 23.0
const GUST_AMOUNT: float = 0.18

signal wind_changed(direction: Vector2, strength: float)
signal became_active()

## Wind does nothing until the player owns a hull that has sails.
##
## The first boat is oared, so the opening islands teach tap-to-move, broadsides
## and the capture loop against a still sea. Wind arrives *with* the first sail —
## as something the upgrade gave you to think about, not as a rule you were
## silently failing at while learning everything else.
var active: bool = false

## Unit vector pointing the way the wind **blows toward**. A ship heading this
## way is running downwind. (Sailors name winds by where they come *from*; this
## is the opposite, because every use in the code wants the push direction.)
var direction: Vector2 = Vector2.RIGHT
## Multiplies the polar. Around 1.0, drifting with gusts and lulls.
var strength: float = 1.0

var _angle: float = 0.0
var _shift_dir: float = 1.0
var _elapsed: float = 0.0


func _ready() -> void:
	instance = self
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.voyage_seed if GameState.voyage_seed != 0 else randi()
	_angle = rng.randf() * TAU
	_shift_dir = 1.0 if rng.randf() < 0.5 else -1.0
	direction = Vector2.RIGHT.rotated(_angle)


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Called when the fleet gains its first sailed hull. Idempotent.
func activate() -> void:
	if active:
		return
	active = true
	became_active.emit()
	Log.info("Wind is up: %s" % _compass_name(), "Wind")


func _process(delta: float) -> void:
	if not active:
		return
	_elapsed += delta
	_angle += deg_to_rad(SHIFT_DEG_PER_SEC) * _shift_dir * delta
	direction = Vector2.RIGHT.rotated(_angle)
	strength = 1.0 + sin(_elapsed * TAU / GUST_PERIOD) * GUST_AMOUNT
	wind_changed.emit(direction, strength)


## Direction the wind blows *from* — what a compass rose would show.
func origin_direction() -> Vector2:
	return -direction


## Radians between a heading and the wind's eye. 0 = pointing straight into the
## wind, PI = running dead before it.
func angle_off_wind(heading: Vector2) -> float:
	return absf(heading.angle_to(-direction))


## Speed multiplier for a hull on this heading. 1.0 is a perfect broad reach.
## Returns 1.0 while the wind is dormant, so early islands play on a still sea.
func speed_multiplier(heading: Vector2, rig_tilt: float = 0.0) -> float:
	if not active:
		return 1.0
	var off: float = angle_off_wind(heading)
	var t: float = clampf(off / PI, 0.0, 1.0)

	# Linear interpolation between polar samples.
	var scaled: float = t * float(POLAR.size() - 1)
	var lower: int = clampi(int(floor(scaled)), 0, POLAR.size() - 1)
	var upper: int = mini(lower + 1, POLAR.size() - 1)
	var value: float = lerpf(POLAR[lower], POLAR[upper], scaled - float(lower))

	# Rig character: a fore-and-aft rig points higher and gives up some downwind
	# power; a square rig is the reverse. `t` is 0 upwind and 1 downwind, so this
	# tilts the curve about its midpoint without changing its overall level.
	if not is_zero_approx(rig_tilt):
		value *= 1.0 + rig_tilt * (0.5 - t) * RIG_TILT_STRENGTH

	return maxf(0.15, value * strength)


## Compass point the wind is blowing from, e.g. "NE".
func _compass_name() -> String:
	const POINTS: PackedStringArray = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]
	var from_angle: float = fposmod(origin_direction().angle(), TAU)
	return POINTS[int(round(from_angle / TAU * 8.0)) % 8]


func compass_name() -> String:
	return _compass_name()


## Human-readable point of sail, for the HUD and the debug overlay.
func point_of_sail(heading: Vector2) -> String:
	if not active:
		return "Becalmed"
	var degrees: float = rad_to_deg(angle_off_wind(heading))
	if degrees < 45.0:
		return "Into the wind"
	if degrees < 75.0:
		return "Close-hauled"
	if degrees < 105.0:
		return "Beam reach"
	if degrees < 150.0:
		return "Broad reach"
	return "Running"
