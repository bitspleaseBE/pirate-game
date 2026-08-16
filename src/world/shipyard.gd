class_name Shipyard
extends Node2D
## The slipway an island builds its reinforcements on, and the reason an island
## fight has a decision in it.
##
## The design has always said this: "waves come from the island's shipyard.
## Killing the shipyard cuts off reinforcements — the tactical decision inside
## every island fight is whether to push for it early or clear the escorts
## first." It was never built. What existed instead was a constant in
## [SpawnDirector] capping every island at two reinforcement waves ever, with a
## comment admitting the cap was standing in for this class and asking to be
## removed once it landed.
##
## That stand-in quietly removed the decision. Reinforcements the player cannot
## stop are weather: you wait them out, and waiting is not a choice. With a
## slipway on the beach the same waves become a question the player answers every
## time — run the gauntlet now and take the shore battery's fire in the back, or
## grind down the escorts first and eat another wave doing it.
##
## Deliberately not a [Ship] and deliberately shaped like [Fort]: one damage bar,
## no helm, no AI. It shares what it needs to share through the two contracts a
## cannonball already understands — it registers with the [SpatialGrid] as a
## `KIND_STRUCTURE`, and it answers `apply_damage`. Nothing in the projectile
## system, the input router or the world overlay needed a special case for it.
##
## Unlike a fort it does not shoot. It is a soft, valuable target sitting behind
## the guns, which is exactly what makes going for it a risk rather than a chore.

## Tougher than a shore battery. A slipway you can delete with one broadside on
## the way past is not a decision, it is a formality — the cost of silencing it
## has to be a real commitment of time under fire.
const MAX_HEALTH: float = 120.0
## Grid radius, and how close a ball has to land to count as a hit.
const HIT_RADIUS: float = 54.0
## Prize money for burning one. The largest single bounty on an island, because
## it is the hardest thing on one to reach.
const BOUNTY_GOLD: int = 60

## Masonry and machinery: chain shot has nothing to shred and there is no crew on
## deck to sweep. Same reasoning as [constant Fort.BAR_VULNERABILITY], and the
## same real ammo decision falling out of the bars that already exist.
const BAR_VULNERABILITY: Dictionary = {
	AmmoType.Bar.HULL: 1.0,
	AmmoType.Bar.SAILS: 0.15,
	AmmoType.Bar.CANNONS: 0.5,
}

const COLOR_SLIP: Color = Color("6d5236")
const COLOR_FRAME: Color = Color("8d6a41")
const COLOR_KEEL: Color = Color("4a3a26")
const COLOR_ROOF: Color = Color("b98f56")
const COLOR_SMOKE: Color = Color(0.16, 0.14, 0.12, 0.5)

signal destroyed()

var health: float = MAX_HEALTH
var alive: bool = true

var _island: Island = null
var _facing: float = 0.0


## Places the slipway on `island`'s coast along `bearing`, and wires it up.
func setup(island: Island, bearing: float) -> void:
	_island = island
	name = "Shipyard_%s" % island.def.id

	# On the waterline, like a fort — it has to launch hulls, so it cannot sit
	# inland, and it has to be shootable from the sea or it is not a target.
	var direction := Vector2(cos(bearing), sin(bearing))
	var coast: float = island.coast_radius_towards(island.global_position + direction * 1000.0)
	position = direction * coast * 0.95
	_facing = bearing

	z_index = 1
	Grid.add(self, SpatialGrid.KIND_STRUCTURE, HIT_RADIUS)


func _exit_tree() -> void:
	Grid.remove(self)


func health_fraction() -> float:
	return clampf(health / MAX_HEALTH, 0.0, 1.0)


## See [method Fort.hit_radius].
func hit_radius() -> float:
	return HIT_RADIUS


## Takes a hit. Signature matches [method Ship.apply_damage] because the
## projectile system calls every target through the same duck-typed path.
func apply_damage(amount: float, bar: int, _source: Node2D) -> void:
	if not alive or amount <= 0.0:
		return
	health = maxf(0.0, health - amount * float(BAR_VULNERABILITY.get(bar, 1.0)))
	queue_redraw()
	if health <= 0.0:
		_burn()


## Structures do not have a bow to be raked over. Answering the same duck-typed
## call the projectile system makes of ships keeps the multiplier logic in one
## place instead of scattering `has_method` checks through it.
func rake_multiplier(_travel: Vector2) -> float:
	return 1.0


func _burn() -> void:
	alive = false
	# Out of the grid at once, so a burnt-out slipway is not still soaking the
	# broadside aimed at the battery behind it.
	Grid.remove(self)
	GameState.add_gold(BOUNTY_GOLD)
	Pools.spawn_effect(&"explosion", global_position, 0.0, 1.6)
	Audio.play_at(&"explosion", global_position)
	EventBus.shipyard_destroyed.emit(_island)
	destroyed.emit()
	queue_free()


func _draw() -> void:
	if not alive:
		return

	# A slipway running down to the water with a half-framed hull on it: two
	# angled rails, a keel, and the ribs coming off it. Vector shapes rather than
	# a sprite, on the same reasoning as [Fort] — there is no authored art for it
	# yet, and this reads at gameplay zoom for four draw calls.
	var down := Vector2(cos(_facing), sin(_facing))
	var across: Vector2 = down.orthogonal()

	draw_colored_polygon(
		PackedVector2Array([
			-down * 34.0 + across * 30.0,
			-down * 34.0 - across * 30.0,
			down * 38.0 - across * 22.0,
			down * 38.0 + across * 22.0,
		]),
		COLOR_SLIP
	)
	draw_line(-down * 30.0, down * 34.0, COLOR_KEEL, 6.0)
	for i: int in 4:
		var along: float = -22.0 + float(i) * 16.0
		var rib: float = 20.0 - absf(along) * 0.28
		draw_line(
			down * along - across * rib, down * along + across * rib, COLOR_FRAME, 4.0
		)
	# A roofed shed at the head of the slip, so the whole thing reads as a place
	# ships are made rather than as wreckage already.
	draw_colored_polygon(
		PackedVector2Array([
			-down * 34.0 + across * 26.0,
			-down * 34.0 - across * 26.0,
			-down * 54.0 - across * 20.0,
			-down * 54.0 + across * 20.0,
		]),
		COLOR_ROOF
	)

	# Damage reads on the structure itself, not only on a bar: a yard you have
	# nearly burned should look nearly burned. Same rule as the shore batteries.
	var wear: float = 1.0 - health_fraction()
	if wear > 0.05:
		draw_arc(
			Vector2.ZERO, 26.0, -PI * 0.5, -PI * 0.5 + TAU * wear, 22,
			Color(COLOR_SMOKE, 0.3 + 0.5 * wear), 5.0, false
		)
