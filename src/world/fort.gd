class_name Fort
extends Node2D
## A shore battery: static, long-ranged, slow, and telegraphed.
##
## This is what makes an island a *place* rather than a patch of sea with ships
## floating near it. A garrison can be fought anywhere, so an island without forts
## has no geography — you meet its defenders in open water and the land is
## scenery. A fort can only be fought *here*, it out-ranges you, and it punishes
## sailing straight in. That is the whole reason the island loop has an approach
## phase at all.
##
## Deliberately not a [Ship]. It has one damage bar, no helm, no AI states and no
## wake, and everything it needs to share with a hull it shares through the two
## contracts a cannonball already knows about: it registers with the [SpatialGrid]
## as a `KIND_STRUCTURE`, and it answers `apply_damage`. Nothing in the projectile
## system, the input router or the world overlay needed a special case for it.
##
## Built from polygons rather than a sprite, like the island's own flag — there is
## no authored fort art yet, and a stone bastion is three convex shapes.

## Seconds of visible wind-up before a shot leaves the gun.
##
## This is the dodge window, and it is the only thing that keeps a static gun with
## twice your reach from being unfair. Long enough to read the telegraph, turn, and
## be somewhere else — which is a real decision, because turning costs you way.
const CHARGE_TIME: float = 1.9
## Seconds between shots, after the wind-up. A fort is a hazard to be timed, not a
## stream of fire to be tanked.
const RELOAD_TIME: float = 4.4
## Reaches well beyond a starting hull's guns on purpose: closing the gap under
## fire is the fight. See the class comment.
const RANGE: float = 1150.0
const DAMAGE: float = 26.0
const MAX_HEALTH: float = 70.0
## Grid radius, and how close a ball has to land to count as a hit.
const HIT_RADIUS: float = 46.0
## Prize money for silencing one. Worth more than a Skiff — it is harder.
const BOUNTY_GOLD: int = 30
## Decisions per second. A static gun needs frame accuracy even less than the
## ship AI does.
const THINK_HZ: float = 5.0

## Masonry does not care what shreds rigging, and there is no crew on deck to
## sweep. Chain and grape are the wrong tools here, which is a real ammo decision
## rather than a special case — the bars already exist, this only prices them.
const BAR_VULNERABILITY: Dictionary = {
	AmmoType.Bar.HULL: 1.0,
	AmmoType.Bar.SAILS: 0.1,
	AmmoType.Bar.CANNONS: 0.45,
}

const COLOR_STONE: Color = Color("9a9184")
const COLOR_STONE_DARK: Color = Color("60594e")
const COLOR_MUZZLE: Color = Color("2b2620")
const COLOR_TELEGRAPH: Color = Color("e2564a")

signal destroyed()

var health: float = MAX_HEALTH
var alive: bool = true

var _island: Island = null
var _charge: float = 0.0
var _reload: float = 0.0
var _aim_at: Vector2 = Vector2.ZERO
var _facing: float = 0.0
var _think_accum: float = 0.0
var _quarry: Ship = null


## Places this battery on `island`'s coast along `bearing`, and wires it up.
func setup(island: Island, bearing: float) -> void:
	_island = island
	name = "Fort_%s_%d" % [island.def.id, roundi(rad_to_deg(bearing))]

	# Just inside the waterline: on the sand, clear of the surf, and close enough
	# to the sea that a ship can actually bring guns to bear on it.
	var direction := Vector2(cos(bearing), sin(bearing))
	var coast: float = island.coast_radius_towards(island.global_position + direction * 1000.0)
	position = direction * coast * 0.94
	_facing = bearing

	# Above the beach and interior polygons, which sit at negative z.
	z_index = 1
	Grid.add(self, SpatialGrid.KIND_STRUCTURE, HIT_RADIUS)


func _exit_tree() -> void:
	Grid.remove(self)


func health_fraction() -> float:
	return clampf(health / MAX_HEALTH, 0.0, 1.0)


## Where this structure's outline ends, for anything drawing over it. Duck-typed
## alongside `health_fraction` so [WorldOverlay] can treat every shore structure
## the same way rather than branching on class.
func hit_radius() -> float:
	return HIT_RADIUS


## Masonry has no bow to be raked over. Answering the same duck-typed call the
## projectile system makes of ships keeps that logic in one place.
func rake_multiplier(_travel: Vector2) -> float:
	return 1.0


func _process(delta: float) -> void:
	# Asleep until the island wakes up, and gone as a threat once it is taken. An
	# archipelago holds dozens of these; none of them should cost anything until
	# the player is actually in a fight with one.
	if not alive or _island == null or _island.is_captured or not _island.is_alerted:
		return

	_think_accum += delta
	if _think_accum >= 1.0 / THINK_HZ:
		_think()
		_think_accum = 0.0

	if _reload > 0.0:
		_reload -= delta
		return

	if _quarry == null:
		return

	# Charging. The aim point is re-solved as it winds up, so a ship that holds its
	# course is hit and a ship that breaks away is not — the telegraph has to be
	# honest about where the shot is going or dodging it is guesswork.
	_charge += delta
	_aim_at = _lead(_quarry)
	queue_redraw()

	if _charge >= CHARGE_TIME:
		_fire()


func _think() -> void:
	var found: Node2D = Grid.query_nearest(
		global_position, RANGE, SpatialGrid.KIND_PLAYER_SHIP
	)
	var ship := found as Ship
	if ship != null and not ship.alive:
		ship = null

	# Losing sight of the target dumps the wind-up, so a player who breaks off
	# does not come back into range to an already-charged gun.
	if ship == null and _quarry != null:
		_charge = 0.0
		queue_redraw()
	_quarry = ship


## Where to aim so a shot with real flight time connects. Two passes is plenty at
## these speeds, and the fort is stationary so there is no launch-point motion to
## account for — see [method Ship._lead] for the version that also corrects for a
## target's curvature.
func _lead(at: Ship) -> Vector2:
	var ammo: AmmoType = AmmoLibrary.get_ammo(&"round")
	var speed: float = maxf(1.0, ammo.muzzle_speed)
	var target_position: Vector2 = at.global_position
	var t: float = global_position.distance_to(target_position) / speed
	for _pass: int in 2:
		t = global_position.distance_to(target_position + at.velocity * t) / speed
	return target_position + at.velocity * t


func _fire() -> void:
	_charge = 0.0
	_reload = RELOAD_TIME
	queue_redraw()

	if ProjectileSystem.instance == null:
		return

	_facing = (_aim_at - global_position).angle()
	var muzzle: Vector2 = global_position + Vector2(cos(_facing), sin(_facing)) * 26.0
	ProjectileSystem.instance.fire(
		muzzle,
		_aim_at,
		AmmoLibrary.get_ammo(&"round"),
		DAMAGE,
		self,
		Teams.ENEMY,
		RANGE
	)
	Pools.spawn_effect(&"muzzle_flash", muzzle, _facing)
	Audio.play_at(&"cannon_fire", muzzle, -1.0)
	EventBus.shot_fired.emit(self, &"round", muzzle, _aim_at)


## Takes a hit. Signature matches [method Ship.apply_damage] because the
## projectile system calls both through the same duck-typed path.
func apply_damage(amount: float, bar: int, _source: Node2D) -> void:
	if not alive or amount <= 0.0:
		return
	health = maxf(0.0, health - amount * float(BAR_VULNERABILITY.get(bar, 1.0)))
	queue_redraw()
	if health <= 0.0:
		_collapse()


func _collapse() -> void:
	alive = false
	# Out of the grid at once: a rubble pile must not be targetable, and must not
	# keep soaking the broadside aimed at the next gun along.
	Grid.remove(self)
	GameState.add_gold(BOUNTY_GOLD)
	Pools.spawn_effect(&"explosion", global_position, 0.0, 1.2)
	Audio.play_at(&"explosion", global_position)
	destroyed.emit()
	queue_free()


func _draw() -> void:
	if not alive:
		return

	# A squat bastion with a darker parapet, then the gun barrel. Three convex
	# polygons and a line — cheaper than a sprite and it reads at gameplay zoom.
	var barrel := Vector2(cos(_facing), sin(_facing))
	draw_circle(Vector2.ZERO, 22.0, COLOR_STONE_DARK)
	draw_circle(Vector2.ZERO, 17.0, COLOR_STONE)
	draw_line(barrel * 8.0, barrel * 30.0, COLOR_MUZZLE, 7.0)

	# Damage reads on the fort itself rather than only on a bar, so a battery you
	# have nearly silenced looks nearly silenced.
	var wear: float = 1.0 - health_fraction()
	if wear > 0.05:
		draw_arc(
			Vector2.ZERO, 19.0, -PI * 0.5, -PI * 0.5 + TAU * wear, 20,
			Color(COLOR_MUZZLE, 0.55), 4.0, false
		)

	if _charge <= 0.0:
		return

	# The telegraph: a ring closing on the spot the ball is going to land, plus a
	# thread showing which gun is aiming there. Drawn in local space, so the aim
	# point has to come back out of global.
	var t: float = clampf(_charge / CHARGE_TIME, 0.0, 1.0)
	var local_aim: Vector2 = _aim_at - global_position
	var alpha: float = 0.25 + 0.55 * t
	draw_line(barrel * 30.0, local_aim, Color(COLOR_TELEGRAPH, alpha * 0.45), 2.0)
	# Shrinking, not growing: the ring tightening onto the water is what reads as
	# "about to happen" rather than "happening slowly".
	draw_arc(
		local_aim, lerpf(150.0, 44.0, t), 0.0, TAU, 28, Color(COLOR_TELEGRAPH, alpha), 3.0, false
	)
