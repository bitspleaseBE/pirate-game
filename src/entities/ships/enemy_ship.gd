class_name EnemyShip
extends Ship
## Enemy behaviour: a four-state machine that thinks at 5 Hz.
##
## This class only decides *what* to do — who to fight, whether to close, whether
## to run. The actual business of working a hull onto a firing beam lives in
## [Ship.broadside_station], so enemies and the player's ships manoeuvre by
## identical rules and the AI can never be accidentally better than the geometry
## allows. In BROADSIDE the brain simply hands the helm back to the base class.
##
## Thinking is decoupled from the physics tick because AI decisions at 60 Hz are
## both wasted work and visibly jittery.

enum AiState { IDLE, PURSUE, BROADSIDE, FLEE }

const THINK_HZ: float = 5.0
## Below this sail fraction the ship breaks off and runs.
const FLEE_SAILS: float = 0.2
## Below this hull fraction the ship runs regardless of sails.
const FLEE_HULL: float = 0.22

## Where this ship patrols when it has no quarry. Set by the spawn director.
var home_position: Vector2 = Vector2.ZERO
var patrol_radius: float = 700.0
var aggro_range: float = 1600.0

var state: AiState = AiState.IDLE

var _think_accum: float = 0.0
var _patrol_accum: float = 0.0


func _ready() -> void:
	team = Teams.ENEMY
	super()
	loaded_ammo = AmmoLibrary.get_ammo(&"round")
	home_position = global_position
	# Stagger the first think so a whole wave does not decide in lockstep.
	_think_accum = randf() / THINK_HZ


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
		_patrol(delta)
		return

	set_target(quarry)

	if hull_fraction() < FLEE_HULL or sails_fraction() < FLEE_SAILS:
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


## Called by the spawn director so a garrison patrols its own island.
func assign_station(position_: Vector2, radius: float, aggro: float) -> void:
	home_position = position_
	patrol_radius = radius
	aggro_range = aggro
