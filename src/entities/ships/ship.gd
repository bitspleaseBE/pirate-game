class_name Ship
extends CharacterBody2D
## Base class for everything that floats and shoots.
##
## Three things here are deliberate design, not implementation detail:
##
## 1. **Broadsides.** Guns fire from the port and starboard beam inside a limited
##    arc. You cannot shoot over the bow. That single constraint is what makes
##    tap-to-move a skill expression rather than a taxi service.
## 2. **Three damage bars.** Hull kills, sails cripple, cannons disarm. Each
##    reaches zero differently and changes how the ship plays.
## 3. **Lead-corrected aim.** Shots have travel time, so guns aim where the
##    target will be. Both the player's ships and the AI use the same solver, so
##    the AI is never accidentally better or worse than the geometry allows.
##
## Culling contract: implements `set_lod_tier`, `sim_step` and `get_cull_radius`
## for [CullingManager].

signal died(killer: Node2D)
signal bars_changed()

## How close counts as arriving at a waypoint. Scaled by hull size.
const ARRIVE_RADIUS_MUL: float = 1.4
## Clear water a hull tries to keep between itself and any coastline. Ships do not
## merely avoid running aground — they stand off, the way a real captain would with
## a lee shore and no chart of the shallows.
const COAST_STANDOFF: float = 170.0
## How far ahead, in seconds of travel, the coast is probed.
const COAST_LOOKAHEAD_SEC: float = 2.2
## Avoidance fades out over this many hull radii from the destination, so a ship
## can settle on a coastal waypoint instead of being nudged past it. Kept small,
## and a fade rather than a cut-off: release too early or too abruptly and the
## final approach has no coast avoidance at all.
const ARRIVAL_RELEASE_RADII: float = 1.8
## Weights for the two halves of the avoidance vector: straight out from the coast,
## and along it. The tangential part is what makes a ship skirt a headland instead
## of stalling nose-on to it.
const COAST_PUSH_WEIGHT: float = 1.5
const COAST_SLIDE_WEIGHT: float = 1.1
## Seconds a ship keeps returning fire after being hit by someone it cannot see.
const RETALIATE_MEMORY: float = 6.0
## Fraction of a hull's turn rate still available when it is dead in the water.
##
## A rudder is a wing in a moving fluid: no flow, no authority. This is why
## stopping in a fight is a mistake and why "keep your way on" is the first
## instinct a player should develop. Oared hulls ignore it — see [method steerage].
const MIN_STEERAGE: float = 0.18
## Speed lost while turning at the maximum rate. You cannot corner and keep way.
const TURN_SPEED_PENALTY: float = 0.28
## Where the hull pivots, as a fraction of hull radius forward of amidships.
## Real ships turn about a point roughly a third back from the bow, which throws
## the stern wide — the most recognisable thing a turning hull does.
const PIVOT_FORWARD_RATIO: float = 0.55
## Chain shot against a hull that has almost no rigging to shred.
const OARED_SAIL_DAMAGE_MUL: float = 0.15
# --- Ramming ---------------------------------------------------------------
#
# Hulls have always collided; the collision just did nothing. Two ships would
# grind against each other at full speed and trade paint, which quietly said that
# the most physical thing that can happen at sea does not count.
#
# It costs both parties, scaled by tonnage and by closing speed, so it is a real
# decision rather than a free attack: a Galleon running down a skiff is a
# massacre, and the same manoeuvre in a Dinghy is suicide. That asymmetry falls
# out of the tonnage ratio without a special case anywhere.

## Damage at a full-speed head-on collision between two equal hulls, before the
## tonnage ratio is applied.
const RAM_BASE_DAMAGE: float = 34.0
## Closing speed below which a bump is just a bump. Ships drift into each other
## constantly in a melee and none of that should be an attack.
const RAM_MIN_CLOSING_SPEED: float = 55.0
## Reference closing speed for full damage — about two hulls meeting bow to bow.
const RAM_REFERENCE_SPEED: float = 220.0
## Ceiling on the tonnage ratio, so a Galleon against a skiff is devastating
## rather than arbitrarily large.
const RAM_TONNAGE_RATIO_MAX: float = 3.2
## Seconds before the same pair can collide again. Without it a grinding contact
## resolves every physics frame and deletes both ships in under a second.
const RAM_COOLDOWN: float = 1.1

## Crew efficiency at or below which a deck can no longer be held against a
## boarding party — the threshold grape shot exists to push a ship past.
const BOARDABLE_CREW: float = 0.62
## Or a hull so far gone its people are fighting the sea instead of you.
const BOARDABLE_HULL: float = 0.35
## Fraction of gun range a ship tries to hold while engaging.
##
## Pulled in from 0.72 to sit inside the band where shot still lands at full
## weight (see [constant ProjectileSystem.POINT_BLANK_BAND]). A standoff chosen
## where every ball arrives spent is a standoff that makes fights long and limp,
## and it applies to the player's own assist as much as to the enemy.
const ENGAGE_RANGE_MUL: float = 0.58
## How far off the direct line the standoff point sits. Bigger = wider circles.
const ORBIT_OFFSET_RAD: float = 0.78
## Engagement steering re-evaluates at this rate. It is a course correction, not
## a per-frame servo, and running it at 60 Hz just produces a twitchy helm.
const ENGAGE_HZ: float = 5.0

# --- Raking fire -----------------------------------------------------------
#
# A ball that arrives along a ship's length travels the whole gun deck: it takes
# out frames, dismounts guns and scythes down the crew, where the same ball on
# the beam punches one hole and stops. Crossing an enemy's bow or stern to rake
# them is *the* age-of-sail tactic, and it is the reason a fight should be about
# where you are rather than about who reloads faster.
#
# Mechanically this is what pays for the helm being back in the player's hands.
# Auto-orbit parks you on a beam-to-beam circle, which is precisely the angle
# that rakes nobody; steering yourself is how you get across their stern, and
# this is what you get for it.

## Damage multiplier for a ball that arrives dead along the hull's axis.
const RAKE_DAMAGE_MUL: float = 2.15
## Alignment (as |cos| of the angle between the shot's track and the hull's axis)
## at which the full multiplier applies, and where it fades out entirely.
## ~20° and ~55° off the axis.
const RAKE_ALIGN_FULL: float = 0.94
const RAKE_ALIGN_NONE: float = 0.57

# --- Riding the swell -------------------------------------------------------
#
# The sea is drawn from directly overhead, and from directly overhead a
# travelling wave just slides: nothing in the shader can prove the water has any
# vertical extent at all. A hull does. A ship that lifts on a crest, leans on the
# flank and settles in the trough is the only thing on screen that can say the
# surface goes up and down, and once one thing on the water is doing it the sea
# behind it stops reading as a scrolling texture.
#
# Deliberately small numbers. This is meant to be felt while watching the ship
# sail, not noticed as an animation, and anything larger turns a ship of the line
# into a cork.

## Extra scale on the hull at the top of a crest — the deck lifting towards the
## camera. Past about 5% it stops reading as height and starts reading as the
## sprite changing size.
const SWELL_HEAVE: float = 0.035
## Peak roll, in radians (~3°), on the flank of a swell.
const SWELL_ROLL: float = 0.055
## Surface slope that counts as a full lean. Set against the summed slope of the
## three swell lines in [constant Ocean.SWELL] rather than picked by eye.
const SWELL_SLOPE_REF: float = 0.007
## How much the drop shadow slides out as the hull rises. A shadow that holds
## station while the ship grows reads as a zoom; one that opens a gap reads as
## the hull climbing away from the water.
const SWELL_SHADOW_LIFT: float = 0.30
## Where the shadow sits with the hull at rest, before any lift.
const SHADOW_OFFSET: Vector2 = Vector2(8.0, 12.0)

const SHIP_SHADOW: Texture2D = preload("res://assets/wave1/ships/ship_shadow.png")
const WAKE_FOAM_FRAMES: Array[Texture2D] = [
	preload("res://assets/wave1/ships/wake_foam_0.png"),
	preload("res://assets/wave1/ships/wake_foam_1.png"),
	preload("res://assets/wave1/ships/wake_foam_2.png"),
	preload("res://assets/wave1/ships/wake_foam_3.png"),
]

@export var stats: ShipStats
@export var team: int = Teams.PLAYER

var hull: float = 1.0
var sails: float = 1.0
var cannons_hp: float = 1.0
var alive: bool = true

var nav_target: Vector2 = Vector2.ZERO
var has_nav_target: bool = false
var target: Node2D = null
var selected: bool = false

## Set by the fleet controller (player) or fixed per hull (enemies).
var loaded_ammo: AmmoType = null
## Reduced by grape shot. Multiplies reload speed.
var crew_efficiency: float = 1.0
## Set while grapples are across and a boarding party is fighting for this hull.
## A grappled ship neither steers nor thinks — it is being fought over.
var grappled: bool = false

var lod: int = 0
## Set while fleeing, so a broken ship runs instead of politely presenting a beam.
var suppress_engage_steering: bool = false
## Set when the player steers this hull by hand while a target is still marked.
##
## The single most important flag in the combat model. Engagement steering used
## to own the helm outright: tap an enemy and the ship sailed itself onto a fixed
## orbit and shot from there, which left the player with exactly one decision per
## fight. Now a course order wins — the target stays marked, the guns keep firing
## the instant a beam bears, and *where the ship goes* is the player's problem.
##
## It clears itself on arrival (see [method _tick_engagement]) so the ship is
## never left drifting with a target it is no longer working towards. That is
## what keeps the assist an assist: it fills a vacuum, it does not take over.
var manual_helm: bool = false
## Per-ship standoff, so a future "beach the ship" action can lower it without
## every other hull forgetting how to navigate.
var coast_standoff: float = COAST_STANDOFF

## Seconds until this hull can be involved in another ram. Without it a grinding
## contact resolves every physics frame and deletes both ships in under a second.
var _ram_cooldown: float = 0.0
var _orbit_dir: float = 1.0
var _engage_accum: float = 0.0
var _speed: float = 0.0
var _reload: Array[float] = [0.0, 0.0]  # [port, starboard]
var _volley: Array[Dictionary] = []
var _burn_left: float = 0.0
var _burn_dps: float = 0.0
var _retaliate_left: float = 0.0
## Last thing to land a hit on this hull. Burn damage arrives with no source —
## it is a fire, not a shot — so without remembering the ship that started it a
## kill by fire would credit nobody and pay no prize money. See [method _sink].
var _last_attacker: Node2D = null
var _wake: GPUParticles2D = null
var _wake_trail: WakeTrail = null
var _hull_sprite: Sprite2D = null
var _ship_shadow: Sprite2D = null
var _bow_foam: AnimatedSprite2D = null
## Everything the swell moves. Held as one node so heave and roll never fight the
## hull's own scale or the ship's heading.
var _visual: Node2D = null


func _ready() -> void:
	if stats == null:
		stats = ShipStats.new()

	hull = stats.max_hull
	sails = stats.max_sails
	cannons_hp = stats.max_cannons_health

	_visual = get_node_or_null(^"Visual") as Node2D
	_hull_sprite = get_node_or_null(^"Visual/Hull") as Sprite2D
	_apply_stats_to_visual()
	_build_ship_art()
	_setup_collision()
	_build_wake_visuals()
	Quality.tier_changed.connect(_on_ship_quality_changed)

	Grid.add(self, Teams.grid_kind(team), stats.hull_radius)
	Cull.register(self)


func _exit_tree() -> void:
	Grid.remove(self)


# --- Culling contract -------------------------------------------------------

func get_cull_radius() -> float:
	return stats.hull_radius * 2.0


func set_lod_tier(tier: int) -> void:
	lod = tier
	var full: bool = tier == Cull.Lod.FULL
	if _wake != null:
		# The foam spray is the single biggest particle cost in the game, so it is
		# the first thing to go when a ship is far away. The trail stays: it is one
		# draw call and it is the only thing telling the player anything is moving.
		_wake.emitting = full and _wake_allowed()
	_update_ship_art_visibility()


## Called by [CullingManager] while off screen. Deliberately coarse: no steering
## behaviours, no collision, no gunnery. Enough that a fleeing enemy really does
## get away and a convoy really does arrive, for a fraction of the full cost.
func sim_step(delta: float) -> void:
	if not alive or not has_nav_target:
		return
	var to_target: Vector2 = nav_target - global_position
	var arrive: float = stats.hull_radius * ARRIVE_RADIUS_MUL
	if to_target.length() <= arrive:
		has_nav_target = false
		return
	var speed: float = current_speed_cap()
	# Off-screen movement bypasses the physics server, so the keep-out ring has to
	# be applied by hand — otherwise ships sail straight through islands while
	# nobody is looking and pop back into view sitting on a beach.
	global_position = clamp_to_navigable(
		global_position + to_target.normalized() * speed * delta
	)
	rotation = to_target.angle() + PI * 0.5
	Grid.update(self)


# --- Main loop --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not alive:
		return
	_tick_burn(delta)
	# A grappled hull is lashed alongside and being fought over hand to hand. It
	# still burns, still takes fire and can still be sunk under everyone's feet —
	# it simply has no say in where it is going.
	if grappled:
		velocity = velocity.lerp(Vector2.ZERO, 1.0 - exp(-2.5 * delta))
		move_and_slide()
		Grid.update(self)
		_ride_swell()
		return
	_tick_engagement(delta)
	_steer(delta)
	move_and_slide()
	_resolve_collisions()
	# Belt and braces. Steering holds the standoff and collision holds the
	# waterline, but "a ship is never on land" is a rule of the game, not an
	# emergent property of two approximations — one shove from another hull or
	# one frame of depenetration slop should not be able to break it.
	global_position = clamp_out_of_land(global_position)
	Grid.update(self)
	_tick_guns(delta)
	_ride_swell()
	_update_ship_art_visibility()
	if _retaliate_left > 0.0:
		_retaliate_left -= delta
	if _ram_cooldown > 0.0:
		_ram_cooldown -= delta


## Steers to bring a beam onto the target — when, and only when, nobody else is
## steering.
##
## This is what "tap an enemy to attack" means. Guns only fire from the port and
## starboard arcs, so a ship that merely sails at its target points the one part
## of the hull that has no cannons on it and never fires a shot. Left to itself
## the ship steers for a standoff point offset around the target, which puts it
## on a tangential course — arriving beam-on, at gun range, already bearing.
##
## It yields to the player. A course order sets [member manual_helm] and this
## keeps its hands off until the ship gets where it was sent; the target stays
## marked and the guns keep working throughout. That is the difference between an
## autopilot and an assist, and it is the difference between watching a fight and
## sailing one.
func _tick_engagement(delta: float) -> void:
	if suppress_engage_steering:
		return
	if manual_helm:
		if has_nav_target:
			return
		# Arrived. The helm comes back to the solver rather than leaving a ship
		# sitting still with an enemy marked and nothing happening.
		manual_helm = false
	if target == null or not is_instance_valid(target) or not _is_alive_target(target):
		return

	_engage_accum += delta
	if _engage_accum < 1.0 / ENGAGE_HZ:
		return
	_engage_accum = 0.0
	set_course(broadside_station(target))


## How far off a target this hull wants to sit while fighting.
##
## Per-hull rather than one constant, because it is most of what separates a
## skiff from a bomb ketch: one wants to be inside your arc, the other wants to
## be nowhere you can reach. See [enum ShipStats.Doctrine].
func engage_range() -> float:
	var mul: float = stats.engage_range_mul
	if mul <= 0.0:
		mul = ENGAGE_RANGE_MUL
	return stats.cannon_range * mul


## The point to steer for in order to arrive beam-on to `shoot_at`.
func broadside_station(shoot_at: Node2D) -> Vector2:
	var ideal: float = engage_range()
	var from_target: Vector2 = global_position - shoot_at.global_position
	if from_target.length_squared() < 1.0:
		from_target = Vector2.RIGHT

	# Too close to bring anything to bear — swing the circle the other way rather
	# than grinding hull to hull with the guns pointing at empty sea.
	if from_target.length() < ideal * 0.45:
		_orbit_dir = -_orbit_dir

	var offset: Vector2 = from_target.normalized().rotated(ORBIT_OFFSET_RAD * _orbit_dir)
	return shoot_at.global_position + offset * ideal


## Picks the circling direction that brings the *nearer* beam to bear, so the ship
## turns the short way instead of swinging its whole length around.
##
## Circling counter-clockwise puts the centre to port, so the port battery ends up
## facing the target; clockwise presents starboard.
func _choose_orbit_dir(shoot_at: Node2D) -> void:
	var to_target: Vector2 = shoot_at.global_position - global_position
	var off_starboard: float = absf(starboard().angle_to(to_target))
	_orbit_dir = -1.0 if off_starboard <= PI * 0.5 else 1.0


func _steer(delta: float) -> void:
	var speed_cap: float = current_speed_cap()

	if has_nav_target:
		var to_target: Vector2 = nav_target - global_position
		if to_target.length() <= stats.hull_radius * ARRIVE_RADIUS_MUL:
			has_nav_target = false
		else:
			var desired: Vector2 = to_target.normalized() + _coast_avoidance()
			var desired_rotation: float = desired.angle() + PI * 0.5

			var max_turn: float = deg_to_rad(stats.turn_rate_deg) * steerage() * delta
			var previous_rotation: float = rotation
			rotation = rotate_toward(rotation, desired_rotation, max_turn)
			var turn_used: float = absf(angle_difference(previous_rotation, rotation))
			_apply_pivot(previous_rotation)

			# Hard helm scrubs way. Cornering has to cost something or the fastest
			# line through a fight is always a series of right angles.
			var scrub: float = 1.0 - TURN_SPEED_PENALTY * (turn_used / maxf(1e-5, max_turn))
			_speed = move_toward(_speed, speed_cap * scrub, stats.acceleration * delta)
	else:
		# Ships do not stop on a coin. Coasting to a halt is most of what makes
		# them feel heavy.
		_speed = move_toward(_speed, 0.0, stats.acceleration * 0.6 * delta)

	# Velocity lags heading, so the hull skids through a turn before it bites.
	# Without this a ship changes direction the instant it changes facing, which
	# is how a car behaves, not a few hundred tons of timber.
	velocity = velocity.lerp(forward() * _speed, 1.0 - exp(-stats.hull_grip * delta))


## One-line helm state, for the debug overlay and the smoke test.
func debug_state() -> String:
	return "spd=%.1f cap=%.1f vel=%.1f nav=%s steerage=%.2f" % [
		_speed, current_speed_cap(), velocity.length(), has_nav_target, steerage()
	]


## Top speed available right now: rigging damage, then propulsion, then the wind.
func current_speed_cap() -> float:
	if stats.is_oared():
		# Rowers, not rigging. Oars ignore the wind entirely and answer to crew
		# losses instead — which is precisely why grape shot is the counter to a
		# skiff swarm and chain shot is very nearly useless against one.
		return stats.max_speed * lerpf(0.35, 1.0, crew_efficiency)

	var cap: float = stats.max_speed * stats.speed_multiplier(sails_fraction())
	if WindSystem.instance != null:
		cap *= WindSystem.instance.speed_multiplier(forward(), stats.rig_tilt())
	return cap


## Fraction of the hull's turn rate currently available.
func steerage() -> float:
	if stats.is_oared():
		# Back one bank of oars and the hull turns on the spot, at any speed.
		return 1.0
	var fraction: float = _speed / maxf(1.0, stats.max_speed)
	return lerpf(MIN_STEERAGE, 1.0, sqrt(clampf(fraction, 0.0, 1.0)))


## Rotates the hull about a point forward of amidships rather than its centre, so
## the stern swings outward through a turn. Two vector ops for most of what makes
## a hull read as a hull instead of a sprite being spun about its middle.
func _apply_pivot(previous_rotation: float) -> void:
	if stats.is_oared():
		return  # Oars turn a boat about its own centre.
	var local := Vector2(0.0, -stats.hull_radius * PIVOT_FORWARD_RATIO)
	global_position += local.rotated(previous_rotation) - local.rotated(rotation)


## Steers to hold clear water off every nearby coast.
##
## Probed at a point the ship's own velocity carries it to, so a fast hull begins
## its alteration earlier than a slow one without any per-ship tuning.
##
## The ramp is measured against the *hull*, not against the standoff, and spans
## exactly [member coast_standoff]: zero correction at a full standoff of clear
## water, rising to full as the hull nears the sand, and past full if the ship is
## somehow already inside — so this recovers as well as prevents.
##
## That the ramp ends precisely where [method clamp_to_navigable] places
## waypoints is the whole point, and getting it wrong is subtle: if avoidance is
## still pushing at the destination, a ship ordered close to shore never arrives.
## It gets shoved tangentially, re-aims, gets shoved again, and orbits the island
## forever. Destination and avoidance have to agree on where "safe water" ends.
##
## Physics collision is still there as the last line of defence, but it should
## never actually fire: hitting the coast means this failed.
func _coast_avoidance() -> Vector2:
	var probe: Vector2 = global_position + velocity * COAST_LOOKAHEAD_SEC
	var bias := Vector2.ZERO

	# Ease the helm as we close on the destination. The waypoint is already known
	# to be in navigable water, so corrections there can only push us off it.
	var damping: float = 1.0
	if has_nav_target:
		var release: float = stats.hull_radius * ARRIVAL_RELEASE_RADII
		damping = clampf(global_position.distance_to(nav_target) / maxf(1.0, release), 0.0, 1.0)
		if damping < 0.02:
			return Vector2.ZERO

	for node: Node2D in Grid.query_radius(
		probe, stats.hull_radius + coast_standoff, SpatialGrid.KIND_ISLAND
	):
		var island := node as Island
		if island == null:
			continue

		var out: Vector2 = probe - island.global_position
		if out.length_squared() < 1.0:
			out = Vector2.UP
		# Gap between the hull and the sand, ignoring the standoff.
		var hull_clearance: float = (
			out.length() - island.coast_radius_towards(probe) - stats.hull_radius
		)
		if hull_clearance > coast_standoff:
			continue

		var away: Vector2 = out.normalized()
		var strength: float = clampf(1.0 - hull_clearance / maxf(1.0, coast_standoff), 0.0, 3.0)
		# Slide along the coast in whichever direction we are already heading.
		var tangent: Vector2 = away.orthogonal()
		if tangent.dot(forward()) < 0.0:
			tangent = -tangent
		bias += (away * COAST_PUSH_WEIGHT + tangent * COAST_SLIDE_WEIGHT) * strength

	return bias * damping


## Pushes a position out of any island's hull-radius exclusion — the hard "not on
## land" rule, with no standoff attached.
##
## Distinct from [method clamp_to_navigable] on purpose: that one enforces the
## comfortable standoff and is right for *destinations*, but applying it to a
## ship's actual position every frame would be an invisible wall the player can
## feel. This only ever fires when a hull is genuinely overlapping sand.
func clamp_out_of_land(world_pos: Vector2) -> Vector2:
	var out_pos: Vector2 = world_pos

	for node: Node2D in Grid.query_radius(out_pos, stats.hull_radius, SpatialGrid.KIND_ISLAND):
		var island := node as Island
		if island == null:
			continue
		var offset: Vector2 = out_pos - island.global_position
		if offset.length_squared() < 1.0:
			offset = Vector2.UP
		var keep_out: float = island.coast_radius_towards(out_pos) + stats.hull_radius
		if offset.length() >= keep_out:
			continue
		out_pos = island.global_position + offset.normalized() * keep_out

	return out_pos


## Pushes a destination out of any island's keep-out ring.
##
## The other half of "ships should not want to go aground": avoidance stops a ship
## reaching land, but a course plotted into a bay still has it grinding against the
## avoidance force forever. Fixing the order at source means it never wants to.
func clamp_to_navigable(world_pos: Vector2) -> Vector2:
	var margin: float = stats.hull_radius + coast_standoff
	var out_pos: Vector2 = world_pos

	for node: Node2D in Grid.query_radius(out_pos, margin + 64.0, SpatialGrid.KIND_ISLAND):
		var island := node as Island
		if island == null:
			continue
		var offset: Vector2 = out_pos - island.global_position
		if offset.length_squared() < 1.0:
			offset = Vector2.UP
		var keep_out: float = island.coast_radius_towards(out_pos) + margin
		if offset.length() >= keep_out:
			continue
		out_pos = island.global_position + offset.normalized() * keep_out

	return out_pos


## Lifts and leans the hull on the swell it is actually sitting on.
##
## Presentation only — it moves nothing the simulation reads, so a ship's guns,
## collision and steering are all unaffected by which part of a wave it is on.
func _ride_swell() -> void:
	if _visual == null:
		return

	var swell: Vector3 = Ocean.sample(global_position)
	_visual.scale = Vector2.ONE * (1.0 + swell.x * SWELL_HEAVE)

	# Roll is the athwartships part of the surface slope, not its magnitude: a hull
	# lying along a crest leans hard, the same hull pointing straight up the face
	# of it stays level and pitches instead — which top-down we cannot show anyway.
	var lean: float = Vector2(swell.y, swell.z).dot(starboard())
	_visual.rotation = clampf(lean / SWELL_SLOPE_REF, -1.0, 1.0) * SWELL_ROLL

	if _ship_shadow != null:
		_ship_shadow.position = SHADOW_OFFSET * (1.0 + swell.x * SWELL_SHADOW_LIFT)


func forward() -> Vector2:
	# Bow points up (-Y) at rotation 0. See the pivot convention in docs/ASSETS.md.
	return Vector2.UP.rotated(rotation)


func starboard() -> Vector2:
	return Vector2.RIGHT.rotated(rotation)


# --- Gunnery ---------------------------------------------------------------

func _tick_guns(delta: float) -> void:
	var reload_speed: float = crew_efficiency * cannons_fraction()
	for side: int in 2:
		if _reload[side] > 0.0:
			_reload[side] = maxf(0.0, _reload[side] - delta * reload_speed)

	_tick_volley(delta)

	if not can_shoot():
		return

	var shoot_at: Node2D = _current_target()
	if shoot_at == null:
		return

	for side: int in 2:
		if _reload[side] > 0.0:
			continue
		if _bears_on(side, shoot_at):
			_begin_volley(side, shoot_at)


## true when the gun deck is functional enough to fire at all. A fireship has no
## gun deck at all and must never enter the gunnery path.
func can_shoot() -> bool:
	return alive and stats.has_broadside() and cannons_fraction() > 0.05


## How ready one battery is to fire, 0 (just fired) to 1 (loaded).
##
## Drawn on the selected hull by [WorldOverlay]. With the helm back in the
## player's hands this stops being a nicety: the whole skill of the fight is
## arriving beam-on at the moment a battery comes loaded, and you cannot time
## something you cannot see.
func reload_fraction(side: int) -> float:
	if stats.reload_time <= 0.0:
		return 1.0
	return clampf(1.0 - _reload[side] / stats.reload_time, 0.0, 1.0)


## true when this battery is loaded and the target is inside its arc.
func battery_bears(side: int) -> bool:
	var shoot_at: Node2D = target
	if shoot_at == null or not is_instance_valid(shoot_at):
		return false
	return _reload[side] <= 0.0 and _bears_on(side, shoot_at)


## Turns a hull-to-hull collision into damage on both parties.
##
## `move_and_slide` already resolved the physics; this only prices what happened.
## Both ships take it, scaled by the tonnage ratio between them, which is what
## makes ramming a decision rather than a free attack — the same manoeuvre is a
## massacre in a Galleon and suicide in a Dinghy, and neither case is special
## -cased anywhere.
##
## Only the heavier party's own tick needs to fire: it damages both sides, and the
## cooldown then suppresses the mirror-image resolution on the other hull's tick.
## Doing it from both would double every ram.
func _resolve_collisions() -> void:
	for i: int in get_slide_collision_count():
		var collision: KinematicCollision2D = get_slide_collision(i)
		var other := collision.get_collider() as Ship
		if other == null or not other.alive or other.team == team:
			continue
		if _ram_cooldown > 0.0 or other._ram_cooldown > 0.0:
			continue

		# Closing speed along the line between the hulls, not raw speed: two ships
		# running parallel and rubbing shoulders are not ramming each other.
		var axis: Vector2 = (other.global_position - global_position)
		if axis.length_squared() < 1.0:
			continue
		axis = axis.normalized()
		var closing: float = (velocity - other.velocity).dot(axis)
		if closing < RAM_MIN_CLOSING_SPEED:
			continue

		var force: float = clampf(closing / RAM_REFERENCE_SPEED, 0.0, 1.6)
		var ratio: float = clampf(
			stats.tonnage / maxf(1.0, other.stats.tonnage), 1.0 / RAM_TONNAGE_RATIO_MAX,
			RAM_TONNAGE_RATIO_MAX
		)

		_ram_cooldown = RAM_COOLDOWN
		other._ram_cooldown = RAM_COOLDOWN

		# Some hulls answer contact with something other than taking the blow. A
		# fireship is the whole reason this hook exists: without it the tonnage
		# ratio simply crushes one — 40 tons against a Galleon's 460 is over a
		# hundred points of ram damage against its 46 of hull — so the enemy whose
		# entire design is "it reaches you and goes off" was being deleted by the
		# act of reaching you.
		if _on_ram_contact(other) or other._on_ram_contact(self):
			continue

		Pools.spawn_effect(&"impact", global_position.lerp(other.global_position, 0.5))
		Audio.play_at(&"impact_wood", global_position)
		EventBus.ships_collided.emit(self, other, force)

		# Order matters: damage the other hull first. If we sink on our own ram —
		# which a light hull ramming a heavy one absolutely should — `_sink` frees
		# nothing immediately but does clear state, and the blow we dealt has to
		# have landed before ours does.
		other.apply_damage(RAM_BASE_DAMAGE * force * ratio, AmmoType.Bar.HULL, self)
		apply_damage(RAM_BASE_DAMAGE * force / ratio, AmmoType.Bar.HULL, other)


## Hook for hulls that answer a collision with something other than taking it.
##
## Returns true when this ship handled the contact, which cancels the ordinary
## ram damage for both parties. Overridden by [EnemyShip] for fireships; the
## default is that a ship is simply hit, which is what ramming means.
func _on_ram_contact(_other: Ship) -> bool:
	return false


## Damage multiplier for a ball whose ground track runs along `travel`.
##
## Raking fire: a shot that enters over the bow or the stern runs the length of
## the gun deck, where the same ball on the beam stops at the first frame it
## hits. This is what makes crossing an enemy's stern worth the manoeuvre, and it
## is the payoff for steering yourself instead of letting the assist park you on
## a beam-to-beam circle where nobody rakes anybody.
##
## Symmetric about the hull's axis — bow and stern both count. A stern rake is
## the more devastating of the two in reality, but telling them apart asks the
## player to read a hull's facing to within a half-turn while it is manoeuvring,
## which at gameplay zoom is a coin flip rather than a skill.
func rake_multiplier(travel: Vector2) -> float:
	if travel.length_squared() < 0.01:
		return 1.0
	var alignment: float = absf(travel.normalized().dot(forward()))
	var t: float = clampf(
		inverse_lerp(RAKE_ALIGN_NONE, RAKE_ALIGN_FULL, alignment), 0.0, 1.0
	)
	return lerpf(1.0, RAKE_DAMAGE_MUL, t)


func _current_target() -> Node2D:
	if target != null and is_instance_valid(target) and _is_alive_target(target):
		return target
	target = null
	# Nothing ordered, but someone has been shooting at us recently: shoot back.
	if _retaliate_left > 0.0:
		return Grid.query_nearest(
			global_position, stats.cannon_range, Teams.hostile_grid_kind(team), self
		)
	return null


func _is_alive_target(node: Node2D) -> bool:
	if node is Ship:
		return (node as Ship).alive
	return true


## Is the target inside this side's firing arc and range?
func _bears_on(side: int, shoot_at: Node2D) -> bool:
	var to_target: Vector2 = shoot_at.global_position - global_position
	var reach: float = stats.cannon_range
	if loaded_ammo != null:
		reach = loaded_ammo.effective_range(reach)
	if to_target.length() > reach:
		return false

	var beam: Vector2 = starboard() * (1.0 if side == 1 else -1.0)
	return absf(beam.angle_to(to_target)) <= deg_to_rad(stats.broadside_arc_deg)


## Queues the guns on one side. The stagger is what makes a broadside roll along
## the hull instead of cracking off as one flat noise.
func _begin_volley(side: int, shoot_at: Node2D) -> void:
	var guns: int = maxi(1, roundi(float(stats.cannons_per_side) * cannons_fraction()))
	_reload[side] = stats.reload_time * _ammo_reload_mul()

	for i: int in guns:
		_volley.append({
			"delay": float(i) * stats.gun_stagger,
			"side": side,
			"slot": float(i) / maxf(1.0, float(guns) - 1.0) - 0.5,
			"target": shoot_at,
		})


func _tick_volley(delta: float) -> void:
	if _volley.is_empty():
		return
	for i: int in range(_volley.size() - 1, -1, -1):
		var shot: Dictionary = _volley[i]
		shot["delay"] = float(shot["delay"]) - delta
		if float(shot["delay"]) > 0.0:
			continue
		_fire_one(shot)
		_volley.remove_at(i)


func _fire_one(shot: Dictionary) -> void:
	var raw_target: Variant = shot["target"]
	if not is_instance_valid(raw_target) or ProjectileSystem.instance == null:
		return
	var shoot_at: Node2D = raw_target

	var ammo: AmmoType = loaded_ammo
	if ammo == null:
		ammo = AmmoLibrary.get_ammo(&"round")
	if not _consume_ammo(ammo):
		return

	var side_sign: float = 1.0 if int(shot["side"]) == 1 else -1.0
	# Guns are spread along the beam, so a volley leaves the hull as a line of
	# muzzle flashes rather than all from one point.
	var along: Vector2 = forward() * (float(shot["slot"]) * stats.hull_radius * 1.5)
	var out: Vector2 = starboard() * side_sign * (stats.hull_radius * 0.75)
	var muzzle: Vector2 = global_position + along + out

	var aim: Vector2 = _lead(shoot_at, muzzle, ammo.muzzle_speed)
	ProjectileSystem.instance.fire(
		muzzle, aim, ammo, stats.base_damage * ammo.damage_mul, self, team, stats.cannon_range
	)

	if lod == Cull.Lod.FULL:
		Pools.spawn_effect(&"muzzle_flash", muzzle, out.angle())
	Audio.play_at(&"cannon_fire", muzzle, -2.0)
	EventBus.shot_fired.emit(self, ammo.id, muzzle, aim)


## Where to aim so a shot with finite travel time actually connects.
##
## Fixed-point iteration on the flight time: guess, re-measure the distance to
## where the target will be by then, repeat. Three passes converges well inside a
## hull width at these speeds.
##
## The curvature correction matters more than it looks. Ships in a broadside duel
## are circling, so a straight-line prediction always aims at a point the target
## curves away from — and consistently misses to the outside of the turn. Rotating
## the predicted velocity by half the turn the target will make over the shot's
## flight puts the aim point back on the arc it is actually following.
func _lead(shoot_at: Node2D, from: Vector2, muzzle_speed: float) -> Vector2:
	var target_pos: Vector2 = shoot_at.global_position
	var target_vel := Vector2.ZERO
	var turn_rate: float = 0.0
	if shoot_at is CharacterBody2D:
		target_vel = (shoot_at as CharacterBody2D).velocity
	if shoot_at is Ship:
		var other := shoot_at as Ship
		# Only a ship that is actually turning has curvature worth correcting for.
		if other.has_nav_target and other.velocity.length() > 1.0:
			var desired: float = (other.nav_target - other.global_position).angle() + PI * 0.5
			turn_rate = signf(angle_difference(other.rotation, desired)) * deg_to_rad(
				other.stats.turn_rate_deg
			)

	var t: float = from.distance_to(target_pos) / maxf(1.0, muzzle_speed)
	for _pass: int in 3:
		var lead_vel: Vector2 = target_vel.rotated(turn_rate * t * 0.5)
		t = from.distance_to(target_pos + lead_vel * t) / maxf(1.0, muzzle_speed)
	return target_pos + target_vel.rotated(turn_rate * t * 0.5) * t


## Enemies have unlimited shot; only the player's stock is finite.
func _consume_ammo(ammo: AmmoType) -> bool:
	if team != Teams.PLAYER or ammo.unlimited:
		return true
	return GameState.consume_ammo(ammo.id)


func _ammo_reload_mul() -> float:
	return loaded_ammo.reload_mul if loaded_ammo != null else 1.0


# --- Damage ----------------------------------------------------------------

func apply_damage(amount: float, bar: int, source: Node2D) -> void:
	if not alive or amount <= 0.0:
		return

	# Chain shot works by shredding rigging. An oared hull has barely any, so the
	# counters fall out of the physics rather than being bolted on: chain answers
	# sails, grape answers oars.
	if bar == AmmoType.Bar.SAILS and stats.is_oared():
		amount *= OARED_SAIL_DAMAGE_MUL

	match bar:
		AmmoType.Bar.SAILS:
			var was_crippled: bool = is_crippled()
			sails = maxf(0.0, sails - amount)
			if is_crippled() and not was_crippled:
				EventBus.ship_crippled.emit(self)
		AmmoType.Bar.CANNONS:
			cannons_hp = maxf(0.0, cannons_hp - amount)
		_:
			hull = maxf(0.0, hull - amount)

	_retaliate_left = RETALIATE_MEMORY
	if source != null and is_instance_valid(source):
		_last_attacker = source
		# Being shot at by someone we are not engaging makes them the new problem.
		if target == null:
			target = source

	bars_changed.emit()
	EventBus.ship_damaged.emit(self, amount, _bar_name(bar))

	if Quality.damage_numbers and lod == Cull.Lod.FULL:
		_spawn_damage_number(amount)

	if hull <= 0.0:
		_sink(source)


func apply_burn(dps: float, duration: float) -> void:
	# Fire refreshes rather than stacking, so a burning ship cannot be shredded
	# by spamming one shot type.
	_burn_dps = maxf(_burn_dps, dps)
	_burn_left = maxf(_burn_left, duration)


func apply_crew_loss(fraction: float) -> void:
	crew_efficiency = clampf(crew_efficiency - fraction, 0.2, 1.0)


func heal(amount: float) -> void:
	hull = minf(stats.max_hull, hull + amount)
	bars_changed.emit()


## Prize crew coming back aboard. A successful boarding refills the ranks the
## fight cost you, which is what stops a run of captures leaving the player with
## a fleet that cannot reload.
func repair_all_crew() -> void:
	crew_efficiency = 1.0
	bars_changed.emit()


func repair_all() -> void:
	hull = stats.max_hull
	sails = stats.max_sails
	cannons_hp = stats.max_cannons_health
	crew_efficiency = 1.0
	_burn_left = 0.0
	bars_changed.emit()


func _tick_burn(delta: float) -> void:
	if _burn_left <= 0.0:
		if stats.repair_rate > 0.0 and hull < stats.max_hull:
			heal(stats.repair_rate * delta)
		return
	_burn_left -= delta
	apply_damage(_burn_dps * delta, AmmoType.Bar.HULL, null)


func _sink(killer: Node2D) -> void:
	alive = false
	hull = 0.0
	_volley.clear()

	# Leave the grid and the culling registry immediately: a wreck must not be
	# targetable, and must not keep costing a culling slot while it animates out.
	Grid.remove(self)
	Cull.unregister(self)
	set_collision_layer(0)
	set_collision_mask(0)
	if _wake != null:
		_wake.emitting = false

	Log.debug("%s sunk by %s" % [stats.display_name, killer.name if killer != null else "?"], "Ship")
	Audio.play_at(&"ship_sink", global_position)
	Pools.spawn_effect(&"explosion", global_position, 0.0, 1.4)
	if team == Teams.ENEMY:
		GameState.stats_ships_sunk += 1
		# A fireship that reaches its mark clears its own credit first, so blowing
		# up on the player's bow is not a payday for the player. See
		# [method EnemyShip._detonate].
		_pay_bounty(killer if killer != null else _last_attacker)

	died.emit(killer)
	EventBus.ship_sunk.emit(self, killer)

	# Spin down and fade rather than vanishing. `PROCESS_MODE_ALWAYS` because the
	# node is out of the culling system now and must finish its own animation.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE * 0.55, 1.6)
	tween.tween_property(self, "modulate:a", 0.0, 1.6)
	tween.tween_property(self, "rotation", rotation + 0.9, 1.6)
	tween.chain().tween_callback(queue_free)


## Hands the player prize money for sinking this hull.
##
## Only when the player actually did it: an enemy that burns down after the fleet
## has sailed away still counts, because the fire was theirs, but one sunk by a
## fort's stray shot or by scuttling itself is not a payday.
##
## Paid into *carried* gold like every other coin, so it goes down with the hull
## that earned it. A hold full of prize money is exactly the situation the
## push-on-or-sail-home decision is made of.
func _pay_bounty(credit: Node2D) -> void:
	if stats.bounty_gold <= 0 or credit == null or not is_instance_valid(credit):
		return
	var ship := credit as Ship
	if ship == null or ship.team != Teams.PLAYER:
		return
	GameState.add_gold(stats.bounty_gold)


func _spawn_damage_number(amount: float) -> void:
	var node: Node2D = Pools.spawn_effect(
		&"damage_number", global_position + Vector2(0, -stats.hull_radius)
	)
	if node != null and node.has_method(&"show_amount"):
		node.call(&"show_amount", amount, team == Teams.PLAYER)


func _bar_name(bar: int) -> StringName:
	match bar:
		AmmoType.Bar.SAILS:
			return &"sails"
		AmmoType.Bar.CANNONS:
			return &"cannons"
		_:
			return &"hull"


# --- Queries ---------------------------------------------------------------

func hull_fraction() -> float:
	return hull / maxf(1.0, stats.max_hull)


func sails_fraction() -> float:
	return sails / maxf(1.0, stats.max_sails)


func cannons_fraction() -> float:
	return cannons_hp / maxf(1.0, stats.max_cannons_health)


func is_crippled() -> bool:
	return sails_fraction() <= 0.001


## Whether this hull could be taken by a boarding party rather than sunk.
##
## The condition is that its people cannot hold it: either grape shot has swept
## the deck, or the hull is so far gone the crew are fighting the water instead.
## That is what finally gives grape a reason to exist — until now it cut a
## reload speed the player could not see, on a ship they were about to sink
## anyway, which is not a decision anyone was ever going to make twice.
##
## Sails and guns deliberately do not count. Shooting the rig off something is
## how you stop it running away; it says nothing about whether its crew will
## throw you back over the side.
func is_boardable() -> bool:
	return alive and (crew_efficiency <= BOARDABLE_CREW or hull_fraction() <= BOARDABLE_HULL)


func set_course(world_pos: Vector2) -> void:
	nav_target = clamp_to_navigable(world_pos)
	has_nav_target = true


## A course the *player* ordered. Identical to [method set_course] except that it
## takes the helm off the engagement solver until the ship arrives — see
## [member manual_helm]. Crucially it does not touch [member target]: steering
## yourself must never mean holstering your guns.
func steer_by_hand(world_pos: Vector2) -> void:
	set_course(world_pos)
	manual_helm = true


func stop() -> void:
	has_nav_target = false


func set_target(node: Node2D) -> void:
	if node != null and node != target:
		_choose_orbit_dir(node)
		# Steer this frame rather than waiting out the engagement tick, so tapping
		# an enemy produces an immediate, visible turn onto them.
		_engage_accum = 1.0 / ENGAGE_HZ
		# Tapping an enemy is an order to go and fight it, so it hands the helm
		# back to the solver — otherwise a ship still running out an old waypoint
		# would acknowledge the order and sail away from it.
		manual_helm = false
	target = node


# --- Setup helpers --------------------------------------------------------

func _apply_stats_to_visual() -> void:
	if _hull_sprite == null:
		return
	if stats.hull_texture != null:
		_hull_sprite.texture = stats.hull_texture
	_hull_sprite.scale = Vector2.ONE * stats.sprite_scale
	_hull_sprite.self_modulate = stats.accent_color


## Adds the Wave 1 shadow and animated bow churn without changing the modular
## Wave 0 hull composition. Both are presentation-only children of the hull.
func _build_ship_art() -> void:
	var visual: Node2D = get_node_or_null(^"Visual") as Node2D
	if visual == null:
		return

	_ship_shadow = Sprite2D.new()
	_ship_shadow.name = "ShipShadow"
	_ship_shadow.texture = SHIP_SHADOW
	_ship_shadow.position = SHADOW_OFFSET
	_ship_shadow.z_index = -2
	# The authored shadow is Sloop-sized; derive scale from physical hull width so
	# the Skiff does not inherit a Sloop's silhouette.
	var shadow_scale: float = 0.5 * (stats.hull_radius * 2.0) / 96.0
	_ship_shadow.scale = Vector2.ONE * shadow_scale
	visual.add_child(_ship_shadow)
	visual.move_child(_ship_shadow, 0)

	var frames := SpriteFrames.new()
	frames.set_animation_speed(&"default", 10.0)
	frames.set_animation_loop(&"default", true)
	for texture: Texture2D in WAKE_FOAM_FRAMES:
		frames.add_frame(&"default", texture)

	_bow_foam = AnimatedSprite2D.new()
	_bow_foam.name = "BowFoam"
	_bow_foam.sprite_frames = frames
	_bow_foam.position = Vector2(0.0, -stats.hull_radius * 0.88)
	_bow_foam.scale = Vector2.ONE * 0.5 * stats.hull_radius / 48.0
	_bow_foam.z_index = -1
	_bow_foam.play(&"default")
	visual.add_child(_bow_foam)
	visual.move_child(_bow_foam, 1)
	_update_ship_art_visibility()


func _update_ship_art_visibility() -> void:
	if _ship_shadow != null:
		_ship_shadow.visible = Quality.shadow_mode >= 1
	if _bow_foam != null:
		var speed_fraction: float = velocity.length() / maxf(1.0, stats.max_speed)
		var should_show: bool = (
			lod == Cull.Lod.FULL
			and _wake_allowed()
			and speed_fraction >= WakeTrail.MIN_SPEED_FRACTION
		)
		if _bow_foam.visible != should_show:
			_bow_foam.visible = should_show
			if should_show:
				_bow_foam.play(&"default")
			else:
				_bow_foam.pause()


func _on_ship_quality_changed(_tier: int) -> void:
	_update_ship_art_visibility()


func _setup_collision() -> void:
	collision_layer = Teams.physics_layer(team)
	# Ships collide with land and with the other team's hulls, but not with their
	# own fleet — allies jostling each other in a channel is pure frustration.
	collision_mask = (1 << 2) | Teams.physics_layer(
		Teams.ENEMY if team == Teams.PLAYER else Teams.PLAYER
	)

	var shape_node: CollisionShape2D = get_node_or_null(^"Collision") as CollisionShape2D
	if shape_node == null:
		return
	var circle := CircleShape2D.new()
	circle.radius = stats.hull_radius
	shape_node.shape = circle


## The wake is two things: a ribbon that every device gets, and a spray of foam
## that only the fast ones do. Splitting them is what stops the cheapest phones
## from losing all sense of motion — see [WakeTrail].
func _build_wake_visuals() -> void:
	_wake_trail = WakeTrail.create_for(self)
	add_child(_wake_trail)

	if Quality.wake_mode > 0:
		_build_wake_particles()


func _build_wake_particles() -> void:
	_wake = GPUParticles2D.new()
	_wake.name = "Wake"
	_wake.amount = Quality.scaled_particles(18)
	_wake.lifetime = 1.5
	_wake.local_coords = false
	_wake.position = Vector2(0, stats.hull_radius * 0.9)
	_wake.z_index = -1

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = stats.hull_radius * 0.35
	material.direction = Vector3(0, 1, 0)
	material.spread = 18.0
	material.initial_velocity_min = 12.0
	material.initial_velocity_max = 34.0
	material.gravity = Vector3.ZERO
	material.scale_min = 0.35
	material.scale_max = 0.9
	material.color = Color(1, 1, 1, 0.5)

	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.45))
	ramp.set_color(1, Color(0.7, 0.9, 1.0, 0.0))
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	material.color_ramp = ramp_texture

	_wake.process_material = material

	var dot := GradientTexture2D.new()
	dot.width = 16
	dot.height = 16
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var dot_ramp := Gradient.new()
	dot_ramp.set_color(0, Color(1, 1, 1, 1))
	dot_ramp.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = dot_ramp
	_wake.texture = dot

	_wake.emitting = _wake_allowed()
	add_child(_wake)


func _wake_allowed() -> bool:
	match Quality.wake_mode:
		0:
			return false
		1:
			return selected or team == Teams.PLAYER
		_:
			return true
