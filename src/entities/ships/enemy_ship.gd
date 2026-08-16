class_name EnemyShip
extends Ship
## Enemy behaviour: a small state machine that thinks at 5 Hz, dispatched by the
## hull's [enum ShipStats.Doctrine].
##
## This class only decides *what* to do — who to fight, whether to close, whether
## to run. The actual business of working a hull onto a firing beam lives in
## [Ship.broadside_station], so enemies and the player's ships manoeuvre by
## identical rules and the AI can never be accidentally better than the geometry
## allows. In BROADSIDE the brain simply hands the helm back to the base class.
##
## Doctrine is what stops the roster being one ship at three sizes. Every hull
## used to run the code below verbatim, so the only thing that changed across a
## whole voyage was how much health was aimed at you — the player never had to
## *do* anything different, and a fight with one answer is a chore with a health
## bar. The two doctrines worth the code are RAMMER and MORTAR, because they are
## the only enemies in the game that make the player move.
##
## Thinking is decoupled from the physics tick because AI decisions at 60 Hz are
## both wasted work and visibly jittery.

enum AiState { IDLE, PURSUE, BROADSIDE, FLEE, CHARGE, STANDOFF }

const THINK_HZ: float = 5.0
## Below this sail fraction the ship breaks off and runs.
const FLEE_SAILS: float = 0.2
## Below this hull fraction the ship runs regardless of sails.
const FLEE_HULL: float = 0.22

# --- Fireship --------------------------------------------------------------

## Extra clearance beyond the two hull radii at which a fireship goes up. Slightly
## generous: the moment that has to read is "it got alongside", and waiting for
## literal contact means a hull that is visibly touching yours has not yet gone
## off, which looks like it failed rather than like you dodged.
const DETONATE_MARGIN: float = 26.0

# --- Bomb ketch ------------------------------------------------------------

## Seconds of visible wind-up before a mortar leaves the tube.
##
## The dodge window, and the only thing that keeps a gun with twice your reach
## fair. Long enough to read the ring, turn, and be somewhere else — which costs
## way, so it is a real decision rather than a free reaction. Longer than a
## fort's, because the ketch is also moving and harder to read.
const MORTAR_CHARGE: float = 2.2
## Below this fraction of its own reach the ketch stops shelling and runs: it is
## a siege weapon, and at knife range it is only a slow hull with one gun.
const MORTAR_MIN_RANGE_MUL: float = 0.32

## Where this ship patrols when it has no quarry. Set by the spawn director.
var home_position: Vector2 = Vector2.ZERO
var patrol_radius: float = 700.0
var aggro_range: float = 1600.0

var state: AiState = AiState.IDLE

var _think_accum: float = 0.0
var _patrol_accum: float = 0.0
var _mortar_charge: float = 0.0
var _mortar_reload: float = 0.0
var _mortar_aim: Vector2 = Vector2.ZERO


func _ready() -> void:
	team = Teams.ENEMY
	super()
	loaded_ammo = AmmoLibrary.get_ammo(&"round")
	home_position = global_position
	# Stagger the first think so a whole wave does not decide in lockstep.
	_think_accum = randf() / THINK_HZ
	# A mortar wave that all fires on the same beat is one enormous shell, not
	# four; staggering the first reload is what makes the shelling read as a
	# barrage the player has to keep moving through.
	_mortar_reload = randf() * stats.reload_time


func _physics_process(delta: float) -> void:
	if alive:
		_tick_brain(delta)
	super(delta)


## Off-screen defenders keep thinking, at the same 5 Hz, even though their node is
## disabled. Without this a garrison spawned on the far side of an island simply
## drifts: [Ship.sim_step] only walks toward an existing nav target, and an enemy
## that has never thought does not have one. The coarse simulation has to include
## enough decision-making to be coherent, or "the fight continues off screen"
## quietly becomes "the fight stops off screen".
func sim_step(delta: float) -> void:
	if alive:
		_tick_brain(delta)
	super(delta)


func _tick_brain(delta: float) -> void:
	# Nothing to decide with boarders on the deck.
	if grappled:
		return
	_think_accum += delta
	if _think_accum < 1.0 / THINK_HZ:
		return
	_think(_think_accum)
	_think_accum = 0.0


func _think(delta: float) -> void:
	var quarry: Node2D = _find_quarry()

	if quarry == null:
		state = AiState.IDLE
		set_target(null)
		suppress_engage_steering = true
		_mortar_charge = 0.0
		_patrol(delta)
		return

	set_target(quarry)

	match stats.doctrine:
		ShipStats.Doctrine.RAMMER:
			_think_rammer(quarry)
		ShipStats.Doctrine.MORTAR:
			_think_mortar(quarry, delta)
		ShipStats.Doctrine.SWARM:
			# Never breaks off. A skiff is cheap, it is sent to be spent, and a
			# swarm that scatters the moment it is hurt is a swarm the player can
			# ignore — which is the one thing a swarm must never be.
			_think_line(quarry, false)
		_:
			_think_line(quarry, true)


## The honest broadside duel, and still what most hulls do.
func _think_line(quarry: Node2D, may_flee: bool) -> void:
	if may_flee and (hull_fraction() < FLEE_HULL or sails_fraction() < FLEE_SAILS):
		state = AiState.FLEE
		# Keep the target so a passing shot still gets returned, but stop trying
		# to hold a firing position — a broken ship runs.
		suppress_engage_steering = true
		_flee_from(quarry)
		return

	var distance: float = global_position.distance_to(quarry.global_position)
	if distance > aggro_range * 1.2:
		state = AiState.PURSUE
		suppress_engage_steering = true
		set_course(quarry.global_position)
		return

	# Inside engagement range the base class takes the helm and works the ship
	# onto a beam. Player and enemy hulls manoeuvre by the same rules.
	#
	# Also pin a course here. While FULL/REDUCED, `_tick_engagement` refreshes it;
	# while SIMULATED, physics is off and `sim_step` only walks toward an existing
	# nav target. Without one the ship freezes in place — which is exactly the
	# "fight silently stops off-camera" bug culling exists to prevent. Spawning
	# just outside the camera's outer rect is common for a garrison meeting the
	# player, so this is not a rare edge case.
	state = AiState.BROADSIDE
	suppress_engage_steering = false
	set_course(broadside_station(quarry))


## A fireship: steer straight down the throat and go up alongside.
##
## No standoff, no arc, no reload — the hull is the weapon, so it aims itself.
## What makes it interesting is that it commits: it steers for where the target
## *is*, not where it will be, so a ship that holds its course is hit and a ship
## that turns late watches it slide past and come lumbering around again. That is
## the whole minigame, and it is why [member ShipStats.turn_rate_deg] on this
## hull is a balance number rather than a flavour one.
func _think_rammer(quarry: Node2D) -> void:
	state = AiState.CHARGE
	suppress_engage_steering = true
	# Straight at it, and deliberately *not* through clamp_to_navigable: a
	# fireship closing on a ship near a shoreline should follow it in, not veer
	# off to keep a polite standoff from the beach.
	nav_target = quarry.global_position
	has_nav_target = true

	var reach: float = stats.hull_radius + DETONATE_MARGIN
	if quarry is Ship:
		reach += (quarry as Ship).stats.hull_radius
	if global_position.distance_to(quarry.global_position) <= reach:
		_detonate()


## A bomb ketch: hold the range it owns and drop shells on you.
##
## It will not fight at close quarters — it runs — so the fight is entirely about
## whether the player is willing to cross the water it is shelling. Everything
## about the shell is honest: the aim point is re-solved every think while the
## tube charges, so the ring on the water is always where the shot is actually
## going. Dodging it is reading, not guessing.
func _think_mortar(quarry: Node2D, delta: float) -> void:
	var distance: float = global_position.distance_to(quarry.global_position)
	var keep_off: float = stats.cannon_range * MORTAR_MIN_RANGE_MUL

	suppress_engage_steering = true
	if distance < keep_off:
		# Caught. Break off and try to open the range again — and stop charging,
		# because a shell it cannot aim is not a threat the player should be
		# dodging while they are busy earning this.
		state = AiState.FLEE
		_mortar_charge = 0.0
		_flee_from(quarry)
		return

	state = AiState.STANDOFF
	set_course(broadside_station(quarry))

	if _mortar_reload > 0.0:
		_mortar_reload -= delta
		return

	_mortar_charge += delta
	_mortar_aim = _mortar_solution(quarry)
	if _mortar_charge >= MORTAR_CHARGE:
		_fire_mortar()


## Keeps the current target if it is still alive and in range, so the ship does
## not flip-flop between two equidistant enemies every think tick.
func _find_quarry() -> Node2D:
	if target != null and is_instance_valid(target) and target is Ship:
		var current := target as Ship
		if current.alive and global_position.distance_to(current.global_position) <= aggro_range * 1.5:
			return current

	return Grid.query_nearest(
		global_position, aggro_range, SpatialGrid.KIND_PLAYER_SHIP, self
	)


func _flee_from(quarry: Node2D) -> void:
	var away: Vector2 = (global_position - quarry.global_position).normalized()
	if away.length_squared() < 0.5:
		away = Vector2.UP
	set_course(global_position + away * 2200.0)
	# A crippled ship still fires if something wanders into its arc, but it is no
	# longer trying to make that happen.
	target = quarry


func _patrol(delta: float) -> void:
	_patrol_accum -= delta
	if has_nav_target and _patrol_accum > 0.0:
		return
	_patrol_accum = randf_range(4.0, 9.0)
	var angle: float = randf() * TAU
	set_course(home_position + Vector2(cos(angle), sin(angle)) * randf_range(0.3, 1.0) * patrol_radius)


## Blows the fireship up alongside whatever it reached.
##
## Damage is dealt straight through the grid rather than as a projectile: there
## is no ball, no flight and nothing to dodge by this point — the dodge was the
## twenty seconds before it, which is where this enemy's whole design lives.
func _detonate() -> void:
	if not alive:
		return
	var hurt: Array[Node2D] = Grid.query_radius(
		global_position, stats.detonation_radius, Teams.hostile_grid_kind(team)
	)
	for victim: Node2D in hurt:
		if not victim.has_method(&"apply_damage"):
			continue
		# Measured to the victim's *hull*, not to its centre. A fireship that has
		# gone off alongside is by definition two hull radii from the middle of
		# the ship it hit, so a centre-to-centre falloff charged its intended
		# victim as though it were a bystander — the enemy whose entire purpose is
		# to punish being ignored was landing a graze, and landing a smaller one
		# the bigger the ship it hit.
		var surface: float = maxf(
			0.0, global_position.distance_to(victim.global_position) - _hull_radius_of(victim)
		)
		var falloff: float = clampf(
			1.0 - surface / maxf(1.0, stats.detonation_radius), 0.3, 1.0
		)
		victim.call(&"apply_damage", stats.detonation_damage * falloff, AmmoType.Bar.HULL, self)
		if victim.has_method(&"apply_burn"):
			victim.call(&"apply_burn", 4.0, 4.0)

	Pools.spawn_effect(&"explosion", global_position, 0.0, 2.2)
	Audio.play_at(&"explosion", global_position)
	EventBus.fireship_detonated.emit(global_position)

	# Clear the credit before sinking. A fireship that reaches its mark did its
	# job, and paying the player prize money for having been rammed reads as a
	# reward for the one outcome this enemy exists to punish.
	_last_attacker = null
	_sink(null)


func _hull_radius_of(node: Node2D) -> float:
	var ship := node as Ship
	return ship.stats.hull_radius if ship != null else 0.0


## Where to drop a shell so it lands on a moving ship.
##
## Same fixed-point iteration as [method Ship._lead], against the mortar's own
## much slower shell. Re-solved on every think while the tube charges, which is
## what makes the telegraph honest.
func _mortar_solution(quarry: Node2D) -> Vector2:
	var ammo: AmmoType = AmmoLibrary.get_ammo(&"mortar")
	return _lead(quarry, global_position, ammo.muzzle_speed)


func _fire_mortar() -> void:
	_mortar_charge = 0.0
	_mortar_reload = stats.reload_time
	if ProjectileSystem.instance == null:
		return

	var ammo: AmmoType = AmmoLibrary.get_ammo(&"mortar")
	ProjectileSystem.instance.fire(
		global_position, _mortar_aim, ammo, stats.base_damage * ammo.damage_mul,
		self, team, stats.cannon_range
	)
	Pools.spawn_effect(&"muzzle_flash", global_position, (_mortar_aim - global_position).angle())
	Audio.play_at(&"cannon_fire", global_position, -1.0)
	EventBus.shot_fired.emit(self, ammo.id, global_position, _mortar_aim)


## Where a shell is about to land, and how far through its wind-up it is, for the
## ring [WorldOverlay] draws on the water. Empty when nothing is in the tube.
##
## Read by the overlay rather than drawn here on purpose: every other piece of
## in-world UI in the game lives in that one canvas item, and a per-ship draw
## call for an occasional ring is exactly the cost that class exists to avoid.
func mortar_telegraph() -> Dictionary:
	if not alive or _mortar_charge <= 0.0:
		return {}
	return {"at": _mortar_aim, "t": clampf(_mortar_charge / MORTAR_CHARGE, 0.0, 1.0)}


## Called by the spawn director so a garrison patrols its own island.
func assign_station(position_: Vector2, radius: float, aggro: float) -> void:
	home_position = position_
	patrol_radius = radius
	aggro_range = aggro
