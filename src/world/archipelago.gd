class_name Archipelago
extends Node2D
## Generates and owns a voyage's islands.
##
## Definitions are generated first, as plain [IslandDef] resources, and only then
## turned into nodes. That split matters: the minimap, the save file and the
## spawn director all want to reason about the archipelago without instantiating
## it, and a voyage's worth of islands is far cheaper as data than as scene tree.
##
## Difficulty is expressed purely as distance from the home port, so the player
## chooses their own difficulty by choosing a route.

const ISLAND_COUNT_MIN: int = 8
const ISLAND_COUNT_MAX: int = 12
## Distance between island centres must exceed the sum of their radii plus this,
## or a fleet cannot manoeuvre in the channel between them.
const MIN_CHANNEL_WIDTH: float = 1500.0
## Radius of the first ring of islands around home.
const FIRST_RING_DISTANCE: float = 4200.0
const RING_SPACING: float = 3600.0
## Distance band that maps to one difficulty tier.
const TIER_BAND: float = 4600.0
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
		"Voyage %d: %d islands, bounds %s" % [seed_value, islands.size(), str(world_bounds)],
		"Archipelago"
	)


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

	for i: int in count:
		var ring: int = 1 + i / 3
		var target_distance: float = FIRST_RING_DISTANCE + float(ring - 1) * RING_SPACING
		var radius: float = _rng.randf_range(360.0, 780.0)

		var pos: Vector2 = Vector2.INF
		for _attempt: int in MAX_PLACEMENT_ATTEMPTS:
			var angle: float = _rng.randf() * TAU
			var dist: float = target_distance * _rng.randf_range(0.82, 1.18)
			var candidate: Vector2 = Vector2(cos(angle), sin(angle)) * dist
			if _is_clear(candidate, radius, placed, placed_radius):
				pos = candidate
				break
		if pos == Vector2.INF:
			# Could not find room on this ring. Skipping is better than shipping
			# two overlapping islands with a channel no ship can enter.
			continue

		placed.append(pos)
		placed_radius.append(radius)

		var tier: int = clampi(1 + floori(pos.length() / TIER_BAND), 1, 5)
		var is_final: bool = i == count - 1

		var def := IslandDef.new()
		def.id = StringName("isle_%d" % i)
		def.display_name = _island_name(i, is_final)
		def.tier = 5 if is_final else tier
		def.biome = _biome_for(tier, is_final)
		def.world_position = pos
		def.radius = 900.0 if is_final else radius
		def.raggedness = _rng.randf_range(0.30, 0.65)
		def.outline_points = 44
		def.shape_seed = seed_value + i * 977
		def.has_castle = is_final
		def.has_shipyard = tier >= 2 and not is_final
		def.fort_cannons = 0 if is_final else clampi(tier - 1, 0, 4)
		# One defender at tier 1. The opening island is where the player learns
		# that guns fire sideways; being outnumbered two to one in an oared dinghy
		# while working that out is a losing first impression, not a difficulty
		# curve. Reinforcement waves from tier 2 shipyards carry the scaling.
		def.garrison_ships = clampi(tier, 1, 8)
		def.alert_radius = 1100.0 + float(tier) * 120.0
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
