class_name CastleKeep
extends Node2D
## The thing at the end of a voyage.
##
## Every voyage is a chain of islands that climbs in tier and ends at a castle,
## and the castle was the least defended island on the map: the generator gave
## the final island `fort_cannons = 0` and `has_shipyard = false`, so the climax
## of a twenty-minute run was four ships in open water and twice the usual
## treasure. A tier-4 island on the way there — two batteries, a slipway and a
## bomb ketch — was strictly harder than the objective.
##
## This is the piece that makes the last island a *place* to be taken rather than
## a bigger patch of sea. It is deliberately built from parts the player already
## understands, because a boss that introduces new rules at the moment of highest
## pressure is a boss nobody reads:
##
##   * a ring of [Fort] batteries, exactly like every other island's, but more of
##     them — the guns you already know how to fight;
##   * a keep that is **armoured while any battery still stands**, so the fight
##     has a shape: silence the ring first, then break the keep;
##   * a telegraphed salvo, on the same honest-ring contract as the bomb ketch —
##     it announces where it is going before it goes there.
##
## The armour is the whole design. Without it a castle is a health bar you park
## next to, and the batteries are scenery you ignore; with it the order of the
## fight is forced, and the moment the last battery falls is a real beat — the
## keep stops shrugging off your broadsides and the fight changes.
##
## Shaped like [Fort] and [Shipyard]: one damage bar, no helm, no AI, reachable
## through the two contracts a cannonball already understands.

## Heavy, because this is the last thing in a voyage and it should take a proper
## sustained pounding rather than one lucky broadside.
const MAX_HEALTH: float = 460.0
const HIT_RADIUS: float = 96.0
## How far in from the coastline the keep sits, as a fraction of the coast radius
## along its bearing. See [method setup] — this is a gunnery constraint, not a
## looks one.
const KEEP_INSET: float = 0.72
## Prize money for breaking it open, on top of the island's doubled treasure.
const BOUNTY_GOLD: int = 240

## What a ball is worth against the keep while its batteries are still firing.
##
## Not zero. An invulnerable target reads as a bug — the player shoots it, sees
## nothing at all happen, and concludes the game is broken rather than that they
## are doing the wrong thing. Ten percent still moves the bar, slowly and
## visibly, which says "this is possible but this is not the way" in the only
## language a fight has.
const ARMOURED_DAMAGE_MUL: float = 0.1

## Seconds of visible wind-up before the salvo lands, and between salvos.
const SALVO_CHARGE: float = 2.6
const SALVO_RELOAD: float = 5.5
## Shells per salvo, and how far they scatter around the aim point.
const SALVO_SHELLS: int = 3
const SALVO_SCATTER: float = 150.0
const SALVO_RANGE: float = 1500.0
const SALVO_DAMAGE: float = 30.0
## Decisions per second. A building needs frame accuracy even less than a fort.
const THINK_HZ: float = 4.0

const BAR_VULNERABILITY: Dictionary = {
	AmmoType.Bar.HULL: 1.0,
	AmmoType.Bar.SAILS: 0.05,
	AmmoType.Bar.CANNONS: 0.4,
}

const COLOR_WALL: Color = Color("8b8377")
const COLOR_WALL_DARK: Color = Color("55503f")
const COLOR_TOWER: Color = Color("a49a8a")
const COLOR_BANNER: Color = Color("2c3f5c")
const COLOR_ARMOURED: Color = Color("6fd0e8")
const COLOR_BREACH: Color = Color("e2564a")

signal destroyed()
## Emitted the first time a shot bounces off the armour, so the game can say why
## once rather than leaving the player to infer it from a bar that will not move.
signal shrugged_off()

var health: float = MAX_HEALTH
var alive: bool = true

var _island: Island = null
var _charge: float = 0.0
var _reload: float = 0.0
var _aim_at: Vector2 = Vector2.ZERO
var _think_accum: float = 0.0
var _quarry: Ship = null
var _warned: bool = false


func setup(island: Island) -> void:
	_island = island
	name = "Keep_%s" % island.def.id

	# Set back from the shore on the opposite side to the harbour, so taking the
	# castle means working right round the island under the batteries — the same
	# rule the slipway follows, for the same reason. Inland far enough to read as
	# a fortress rather than a hut on the beach, and near enough that a ship
	# standing off the coast can still bring guns to bear on it.
	var bearing: float = island.harbour_bearing() + PI
	var direction := Vector2(cos(bearing), sin(bearing))
	var coast: float = island.coast_radius_towards(island.global_position + direction * 2000.0)
	# Set back from the waterline, but not further than a broadside can reach.
	# A ship stands off at roughly `coast + hull_radius + COAST_STANDOFF`, so the
	# gap to the keep is `coast * (1 - INSET) + ~230`. On a 900-unit castle island
	# an inset of 0.62 put that at ~570 — inside a Brig's 700 but outside a
	# Sloop's 620 once a headland is in the way, which would present as a boss
	# that simply cannot be shot. 0.72 leaves ~480, comfortable for every hull
	# that has any business being here, and still visibly inland.
	position = direction * coast * KEEP_INSET

	z_index = 2
	Grid.add(self, SpatialGrid.KIND_STRUCTURE, HIT_RADIUS)


func _exit_tree() -> void:
	Grid.remove(self)


func health_fraction() -> float:
	return clampf(health / MAX_HEALTH, 0.0, 1.0)


## See [method Fort.hit_radius].
func hit_radius() -> float:
	return HIT_RADIUS


## Stone does not get raked. Answers the duck-typed call the projectile system
## makes of every target.
func rake_multiplier(_travel: Vector2) -> float:
	return 1.0


## true while the batteries are up and the keep cannot be meaningfully hurt.
func is_armoured() -> bool:
	return _island != null and is_instance_valid(_island) and _island.forts_remaining() > 0


func apply_damage(amount: float, bar: int, _source: Node2D) -> void:
	if not alive or amount <= 0.0:
		return

	var weight: float = float(BAR_VULNERABILITY.get(bar, 1.0))
	if is_armoured():
		weight *= ARMOURED_DAMAGE_MUL
		if not _warned:
			_warned = true
			shrugged_off.emit()

	health = maxf(0.0, health - amount * weight)
	queue_redraw()
	if health <= 0.0:
		_breach()


func _process(delta: float) -> void:
	# Asleep until the island wakes up. An archipelago holds one of these, but it
	# should still cost nothing until the player is in front of it.
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

	# Charging. The aim point is re-solved as it winds up, exactly like a shore
	# battery and a bomb ketch, so a ship that holds its course is hit and a ship
	# that breaks away is not. The telegraph has to be honest or dodging it is
	# guesswork, and a boss you cannot dodge is just damage on a clock.
	_charge += delta
	_aim_at = _solution(_quarry)
	queue_redraw()
	if _charge >= SALVO_CHARGE:
		_fire_salvo()


func _think() -> void:
	var found: Node2D = Grid.query_nearest(
		global_position, SALVO_RANGE, SpatialGrid.KIND_PLAYER_SHIP
	)
	var ship := found as Ship
	if ship != null and not ship.alive:
		ship = null
	# Losing the target dumps the wind-up, so breaking off does not bring you back
	# into range against an already-charged salvo.
	if ship == null and _quarry != null:
		_charge = 0.0
		queue_redraw()
	_quarry = ship


func _solution(at: Ship) -> Vector2:
	var ammo: AmmoType = AmmoLibrary.get_ammo(&"mortar")
	var speed: float = maxf(1.0, ammo.muzzle_speed)
	var target_position: Vector2 = at.global_position
	var t: float = global_position.distance_to(target_position) / speed
	for _pass: int in 2:
		t = global_position.distance_to(target_position + at.velocity * t) / speed
	return target_position + at.velocity * t


func _fire_salvo() -> void:
	_charge = 0.0
	_reload = SALVO_RELOAD
	queue_redraw()
	if ProjectileSystem.instance == null:
		return

	var ammo: AmmoType = AmmoLibrary.get_ammo(&"mortar")
	# Scattered around the aim point rather than stacked on it: three shells on
	# one spot is one big shell, where a spread is an area to get out of. The
	# telegraph ring is sized to cover the whole pattern, so the player is being
	# shown the truth about where it is dangerous to be.
	for i: int in SALVO_SHELLS:
		var angle: float = TAU * float(i) / float(SALVO_SHELLS) + randf() * 0.6
		var at: Vector2 = _aim_at + Vector2(cos(angle), sin(angle)) * SALVO_SCATTER * randf()
		ProjectileSystem.instance.fire(
			global_position, at, ammo, SALVO_DAMAGE, self, Teams.ENEMY, SALVO_RANGE
		)
	Pools.spawn_effect(&"muzzle_flash", global_position, (_aim_at - global_position).angle())
	Audio.play_at(&"cannon_fire", global_position, 0.0)
	EventBus.shot_fired.emit(self, &"mortar", global_position, _aim_at)


## Where the salvo is about to land, on the same contract [EnemyShip] uses, so
## [WorldOverlay] draws both with the same code and the player reads them as the
## same warning. `spread` sizes the ring to the whole pattern.
func mortar_telegraph() -> Dictionary:
	if not alive or _charge <= 0.0:
		return {}
	return {
		"at": _aim_at,
		"t": clampf(_charge / SALVO_CHARGE, 0.0, 1.0),
		"spread": SALVO_SCATTER,
	}


func _breach() -> void:
	alive = false
	Grid.remove(self)
	GameState.add_gold(BOUNTY_GOLD)
	# Three blasts walking outward, because this is the loudest moment in a
	# voyage and one puff of smoke is not it.
	for i: int in 3:
		Pools.spawn_effect(
			&"explosion",
			global_position + Vector2(randf_range(-70.0, 70.0), randf_range(-70.0, 70.0)),
			0.0,
			2.0
		)
	Audio.play_at(&"explosion", global_position)
	EventBus.castle_breached.emit(_island)
	destroyed.emit()
	queue_free()


func _draw() -> void:
	if not alive:
		return

	# A square keep with corner towers and a banner. Vector shapes on the same
	# reasoning as [Fort] and [Shipyard]: no authored art exists yet, and this
	# reads as masonry at gameplay zoom for a handful of draw calls.
	var half: float = 58.0
	draw_rect(Rect2(-Vector2(half, half), Vector2(half * 2.0, half * 2.0)), COLOR_WALL_DARK, true)
	draw_rect(
		Rect2(-Vector2(half - 9.0, half - 9.0), Vector2((half - 9.0) * 2.0, (half - 9.0) * 2.0)),
		COLOR_WALL,
		true
	)
	for corner: Vector2 in [
		Vector2(-half, -half), Vector2(half, -half), Vector2(-half, half), Vector2(half, half)
	]:
		draw_circle(corner, 20.0, COLOR_WALL_DARK)
		draw_circle(corner, 14.0, COLOR_TOWER)

	draw_line(Vector2(0.0, -12.0), Vector2(0.0, -74.0), COLOR_WALL_DARK, 5.0)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(0.0, -74.0), Vector2(38.0, -64.0), Vector2(0.0, -54.0)
		]),
		COLOR_BANNER
	)

	# The armour is the single most important thing on screen during the first
	# half of this fight, and it is a *rule*, not a number — so it is drawn as a
	# shell around the keep rather than left to be inferred from a health bar
	# that will barely move. It goes when the last battery does, which is the
	# moment the fight changes.
	if is_armoured():
		var pulse: float = 0.5 + 0.22 * sin(float(Time.get_ticks_msec()) * 0.004)
		draw_arc(
			Vector2.ZERO, HIT_RADIUS * 0.92, 0.0, TAU, 40,
			Color(COLOR_ARMOURED, pulse), 5.0, false
		)
		draw_arc(
			Vector2.ZERO, HIT_RADIUS * 0.82, 0.0, TAU, 40,
			Color(COLOR_ARMOURED, pulse * 0.4), 2.0, false
		)

	var wear: float = 1.0 - health_fraction()
	if wear > 0.02:
		draw_arc(
			Vector2.ZERO, HIT_RADIUS * 0.7, -PI * 0.5, -PI * 0.5 + TAU * wear, 32,
			Color(COLOR_BREACH, 0.75), 6.0, false
		)
