class_name Archipelago
extends Node2D
## Generates and owns a voyage's islands.
##
## Definitions are generated first, as plain [IslandDef] resources, and only then
## turned into nodes. That split matters: the minimap, the save file and the
## spawn director all want to reason about the archipelago without instantiating
## it, and a voyage's worth of islands is far cheaper as data than as scene tree.
##
## Islands form a chain that works its way outward from home, each one placed a
## short hop from the last, and difficulty climbs along the chain — so the player
## still picks their own difficulty by picking how far out to push.
##
## The chain replaced concentric rings, which looked reasonable on paper and put
## islands up to 8,000 m from their nearest neighbour in practice. Three islands
## at random bearings on a 10,000 m ring are a third of a circumference apart; the
## ring spacing bounds how far apart the *rings* are and says nothing at all about
## how far it is from one island to the next, which is the only distance the
## player ever actually sails.
##
## Sailing is this game's connective tissue, not its content. A leg long enough to
## become boring is a leg the player spends waiting instead of deciding, so every
## hop here is solved for directly: pick how much further out the next island
## should sit, pick how long the sail to it should be, and derive the bearing that
## satisfies both. Legs come out at 2,200–3,000 m, which is 20–25 seconds under
## oars.

const ISLAND_COUNT_MIN: int = 8
const ISLAND_COUNT_MAX: int = 12
## Distance between island centres must exceed the sum of their radii plus this,
## or a fleet cannot manoeuvre in the channel between them.
##
## It is also what fights hardest against the short-leg target, since two large
## islands then need `560 + 560 + this` between their centres and that has to fit
## inside [constant LEG_RANGE]. A channel this wide is still more than twice the
## longest gun range in the game.
const MIN_CHANNEL_WIDTH: float = 1300.0
## How far the player sails from one island to the next, centre to centre.
const LEG_RANGE: Vector2 = Vector2(2200.0, 3000.0)
## How much further from home each island sits than the one before it.
##
## Must stay below `LEG_RANGE.x`, or the geometry has no solution: a hop cannot be
## shorter than the difference in the two radii it spans, and a leg that cannot be
## solved is an island silently dropped from the voyage.
##
## This is also what keeps tier and distance agreeing with each other. Tier comes
## from a chain position ([constant TIER_LADDER]) while the design — and the
## player's expectation — is that danger grows with distance from home. Forcing
## every island strictly further out than its predecessor is what makes those the
## same statement.
const RADIAL_STEP_RANGE: Vector2 = Vector2(800.0, 1500.0)
## Where the very first island sits, and how big it is.
##
## Deliberately the shortest hop in the voyage, and the only one at an exact
## distance. It cannot go much lower: placement still has to clear
## `home.radius + island.radius + MIN_CHANNEL_WIDTH` = 2320 m.
const OPENING_ISLAND_DISTANCE: float = 2700.0
const OPENING_ISLAND_RADIUS: float = 380.0
## The castle island. Bigger than anything else in the voyage, because it is the
## one the player is sailing the whole chain to reach.
const CASTLE_ISLAND_RADIUS: float = 900.0
## Batteries ringing the castle. More than any ordinary island, because silencing
## them is the first phase of the boss — the keep shrugs off everything while one
## of them still stands. See [CastleKeep].
const CASTLE_FORT_CANNONS: int = 4
## How far off the bearing of home's own harbour the opening island may sit.
##
## The fleet starts at Port Royal's mooring buoy, not at the middle of the island,
## and the buoy is the better part of a thousand metres off centre. With islands
## this close together that offset is enough to make some *other* island the
## nearest thing to the player's actual starting position — which quietly hands a
## brand new player a tier-2 warship as their first fight. Putting the opening
## island off the home harbour fixes it at the source, and reads as a reason
## rather than a rule: the first island is the one you can see from your own quay.
const OPENING_ISLAND_BEARING_SPREAD: float = 0.30
const ISLAND_RADIUS_RANGE: Vector2 = Vector2(320.0, 560.0)
## Difficulty by position along the chain, which is the order the player meets
## them in. Written out rather than computed because it *is* the ramp, and the
## ramp is something to look at and argue with rather than to derive.
##
## The second island is the one that used to lose runs: a distance-banded tier
## could make it tier 2 *or* 3, and tier 2 meant a Navy Sloop and a skiff at once
## against a one-gun Dinghy. It is now always tier 2, and tier 2 is one warship —
## see [method SpawnDirector._hull_for_tier].
const TIER_LADDER: Array[int] = [1, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5]
const MAX_PLACEMENT_ATTEMPTS: int = 60

var defs: Array[IslandDef] = []
var islands: Array[Island] = []
var home: Island = null
var world_bounds: Rect2 = Rect2()

var _rng := RandomNumberGenerator.new()


## Builds the definitions and instantiates every island. `seed_value` of 0 means
## "pick one", which is then written back to GameState so the voyage is
## reproducible and shareable.
func generate(seed_value: int) -> void:
	clear()

	if seed_value == 0:
		seed_value = randi()
	GameState.voyage_seed = seed_value
	_rng.seed = seed_value

	defs = _generate_defs(seed_value)
	_instantiate(defs)
	_compute_bounds()

	Log.info(
		"Voyage %d: %d islands, %s, bounds %s"
		% [seed_value, islands.size(), _leg_summary(), str(world_bounds)],
		"Archipelago"
	)


## Shortest and longest hop in the voyage, for the boot log.
##
## The one number that decides whether sailing this archipelago is a breather or
## a chore, and it is not any of the constants that produce it — so it is worth
## being able to read it off a run rather than working it out from four of them.
func _leg_summary() -> String:
	var shortest: float = INF
	var longest: float = 0.0
	for def: IslandDef in defs:
		if def.id == &"home":
			continue
		var nearest: float = INF
		for other: IslandDef in defs:
			if other == def:
				continue
			nearest = minf(nearest, def.world_position.distance_to(other.world_position))
		if nearest == INF:
			continue
		shortest = minf(shortest, nearest)
		longest = maxf(longest, nearest)
	if shortest == INF:
		return "no legs"
	return "legs %d-%d m" % [roundi(shortest), roundi(longest)]


func clear() -> void:
	for island: Island in islands:
		if is_instance_valid(island):
			island.queue_free()
	islands.clear()
	defs.clear()
	home = null


func get_island_by_id(id: StringName) -> Island:
	for island: Island in islands:
		if island.def.id == id:
			return island
	return null


## Closest island to a point, and how far outside its coast that point is.
func nearest_island(world_pos: Vector2) -> Island:
	var best: Island = null
	var best_dist: float = INF
	for island: Island in islands:
		var d: float = island.distance_to_coast(world_pos)
		if d < best_dist:
			best_dist = d
			best = island
	return best


func uncaptured_count() -> int:
	var n: int = 0
	for island: Island in islands:
		if not island.is_captured:
			n += 1
	return n


func _generate_defs(seed_value: int) -> Array[IslandDef]:
	var out: Array[IslandDef] = []
	var count: int = _rng.randi_range(ISLAND_COUNT_MIN, ISLAND_COUNT_MAX)

	# --- Home port: always at the origin, always already yours. ---
	var home_def := IslandDef.new()
	home_def.id = &"home"
	home_def.display_name = "Port Royal"
	home_def.tier = 1
	home_def.biome = IslandDef.Biome.TROPICAL
	home_def.world_position = Vector2.ZERO
	home_def.radius = 640.0
	home_def.raggedness = 0.35
	home_def.shape_seed = seed_value
	home_def.fort_cannons = 0
	home_def.garrison_ships = 0
	home_def.has_shipyard = false
	home_def.discovered = true
	home_def.captured = true
	home_def.treasure_count = 0
	out.append(home_def)

	var placed: Array[Vector2] = [Vector2.ZERO]
	var placed_radius: Array[float] = [home_def.radius]

	# The bearing of home's own harbour, so the opening island can be put where a
	# fleet weighing anchor is already pointing.
	var home_bearing: float = home_def.sheltered_shore(home_def.build_outline()).angle()
	# Where the chain has reached: the last island placed, and how far out it is.
	var link: Vector2 = Vector2.ZERO
	var link_distance: float = 0.0

	for i: int in count:
		var is_final: bool = i == count - 1
		# Settled before placement, not after. The castle island is far larger than
		# any other, and clearing a spot for it as though it were an average island
		# leaves the channel to it narrower than MIN_CHANNEL_WIDTH by the difference.
		var radius: float = _rng.randf_range(ISLAND_RADIUS_RANGE.x, ISLAND_RADIUS_RANGE.y)
		if is_final:
			radius = CASTLE_ISLAND_RADIUS
		if i == 0:
			radius = OPENING_ISLAND_RADIUS

		var pos: Vector2 = Vector2.INF
		for _attempt: int in MAX_PLACEMENT_ATTEMPTS:
			var candidate: Vector2 = (
				_opening_position(home_bearing)
				if i == 0
				else _next_link(link, link_distance)
			)
			if _is_clear(candidate, radius, placed, placed_radius):
				pos = candidate
				break
		if pos == Vector2.INF:
			# The chain has wound back on itself and there is no room for the next
			# link. Skipping is better than shipping two overlapping islands with a
			# channel no ship can enter — the chain simply carries on from where it
			# had got to.
			if i == 0:
				push_error(
					"Opening island could not be placed at %.0fm — it is inside the"
					% OPENING_ISLAND_DISTANCE
					+ " minimum channel from home, so the player's first island will be"
					+ " a distant high-tier one. Raise OPENING_ISLAND_DISTANCE."
				)
			continue

		placed.append(pos)
		placed_radius.append(radius)
		link = pos
		link_distance = pos.length()

		var tier: int = TIER_LADDER[mini(i, TIER_LADDER.size() - 1)]

		var def := IslandDef.new()
		def.id = StringName("isle_%d" % i)
		def.display_name = _island_name(i, is_final)
		def.tier = 5 if is_final else tier
		def.biome = _biome_for(tier, is_final)
		def.world_position = pos
		def.radius = radius
		def.raggedness = _rng.randf_range(0.30, 0.65)
		def.outline_points = 44
		def.shape_seed = seed_value + i * 977
		def.has_castle = is_final
		# Shipyards — and so reinforcement waves — start at tier 3. A second island
		# that is "one warship" only stays that way if nothing arrives twenty
		# seconds later to make it three.
		def.has_shipyard = tier >= 3 and not is_final
		# Batteries start at tier 3 for the same reason. The tier-2 island is the
		# player's first real duel, and it should be a duel rather than a duel
		# fought inside somebody else's field of fire.
		# The castle rings itself with batteries rather than having none at all.
		# It used to be authored with `0 if is_final`, which made the objective of
		# the entire voyage the least defended island on the map — strictly easier
		# than the tier-4 islands on the way to it, which field two batteries, a
		# slipway and a bomb ketch. The ring is also what the keep's armour is
		# keyed to, so it is the first half of the boss fight.
		def.fort_cannons = CASTLE_FORT_CANNONS if is_final else clampi(tier - 2, 0, 3)
		# One defender through tier 2, then one more per tier. The count is only
		# half of it — [method SpawnDirector._hull_for_tier] decides *what* they
		# are, and tier 2's single hull is a Navy Sloop rather than a skiff, so the
		# step up from the opening island is in weight, not in numbers. Being
		# outnumbered while still working out that guns fire sideways is a losing
		# first impression, not a difficulty curve.
		def.garrison_ships = clampi(tier - 1, 1, 4)
		def.alert_radius = 900.0 + float(tier) * 80.0
		def.treasure_count = 2 if is_final else 1
		out.append(def)

	# The castle island is the objective, so guarantee one even if the last
	# placement attempt failed.
	if out.size() > 1 and not out[out.size() - 1].has_castle:
		var last: IslandDef = out[out.size() - 1]
		last.has_castle = true
		last.tier = 5
		last.display_name = "Fort Diablo"

	return out


## A candidate spot for the opening island: a fixed distance out, off the bearing
## of home's harbour. See [constant OPENING_ISLAND_BEARING_SPREAD].
func _opening_position(home_bearing: float) -> Vector2:
	var bearing: float = home_bearing + _rng.randf_range(
		-OPENING_ISLAND_BEARING_SPREAD, OPENING_ISLAND_BEARING_SPREAD
	)
	return Vector2(cos(bearing), sin(bearing)) * OPENING_ISLAND_DISTANCE


## The next link in the chain: a candidate that is both a short sail from `link`
## and further from home than it is.
##
## Solved rather than sampled. Pick how much further out the island should sit and
## how long the sail to it should be, and there are exactly two bearings that
## satisfy both — one to each side of the previous island. The law of cosines
## gives the angle between them; the coin flip picks a side, which is what makes
## the chain wander instead of marching in a straight line out to sea.
##
## Rejection-sampling a position and hoping it lands in range is the obvious
## alternative and it is what the ring layout effectively did. It cannot express
## "close to the last island *and* further out than it", which is the entire
## shape of the archipelago.
func _next_link(link: Vector2, link_distance: float) -> Vector2:
	var out_distance: float = link_distance + _rng.randf_range(
		RADIAL_STEP_RANGE.x, RADIAL_STEP_RANGE.y
	)
	var leg: float = _rng.randf_range(LEG_RANGE.x, LEG_RANGE.y)
	var cosine: float = (
		(out_distance * out_distance + link_distance * link_distance - leg * leg)
		/ (2.0 * out_distance * link_distance)
	)
	var turn: float = acos(clampf(cosine, -1.0, 1.0))
	if _rng.randf() < 0.5:
		turn = -turn
	var bearing: float = link.angle() + turn
	return Vector2(cos(bearing), sin(bearing)) * out_distance


func _is_clear(
	candidate: Vector2, radius: float, placed: Array[Vector2], radii: Array[float]
) -> bool:
	for i: int in placed.size():
		var required: float = radius + radii[i] + MIN_CHANNEL_WIDTH
		if candidate.distance_to(placed[i]) < required:
			return false
	return true


func _biome_for(tier: int, is_final: bool) -> IslandDef.Biome:
	if is_final:
		return IslandDef.Biome.VOLCANIC
	match tier:
		1:
			return IslandDef.Biome.TROPICAL
		2:
			return IslandDef.Biome.TROPICAL if _rng.randf() < 0.5 else IslandDef.Biome.JUNGLE
		3:
			return IslandDef.Biome.JUNGLE
		4:
			return IslandDef.Biome.ROCKY
		_:
			return IslandDef.Biome.FROZEN


func _island_name(index: int, is_final: bool) -> String:
	if is_final:
		return "Fort Diablo"
	const FIRST: PackedStringArray = [
		"Gallows", "Kraken", "Salt", "Widow", "Rum", "Black", "Coral", "Storm",
		"Cutlass", "Mutiny", "Pelican", "Bone",
	]
	const SECOND: PackedStringArray = ["Cay", "Isle", "Rock", "Reef", "Key", "Shoal"]
	return "%s %s" % [FIRST[index % FIRST.size()], SECOND[index % SECOND.size()]]


func _instantiate(island_defs: Array[IslandDef]) -> void:
	for def: IslandDef in island_defs:
		var island := Island.new()
		add_child(island)
		island.setup(def)
		islands.append(island)
		if def.id == &"home":
			home = island


func _compute_bounds() -> void:
	if islands.is_empty():
		world_bounds = Rect2(-4000, -4000, 8000, 8000)
		return

	var min_p: Vector2 = Vector2.INF
	var max_p: Vector2 = -Vector2.INF
	for island: Island in islands:
		var r: float = island.def.radius
		min_p = min_p.min(island.def.world_position - Vector2(r, r))
		max_p = max_p.max(island.def.world_position + Vector2(r, r))

	# Open water around the outermost islands, so the edge of the world is never
	# a hard wall right against a coastline.
	var pad := Vector2(2600, 2600)
	world_bounds = Rect2(min_p - pad, (max_p + pad) - (min_p - pad))
