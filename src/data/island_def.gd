class_name IslandDef
extends Resource
## Generation parameters for one island.
##
## The archipelago generator produces these, then islands build themselves from
## them. Keeping the definition separate from the node means the minimap, the
## save file and the generator can all reason about an island without it being
## instantiated — which is how a large voyage stays cheap.

enum Biome { TROPICAL, JUNGLE, ROCKY, VOLCANIC, FROZEN }

@export var id: StringName = &"isle_0"
@export var display_name: String = "Nameless Cay"
@export_range(1, 5) var tier: int = 1
@export var biome: Biome = Biome.TROPICAL

@export_group("Shape")
@export var world_position: Vector2 = Vector2.ZERO
## Mean radius in pixels. The outline is this, perturbed by noise.
@export var radius: float = 520.0
## 0 = a circle, 1 = a very ragged coast.
@export_range(0.0, 1.0) var raggedness: float = 0.45
## Outline resolution. Below about 40 the coastline reads as visibly straight
## segments at gameplay zoom; above it the collision polygon and the minimap draw
## start costing more than the extra smoothness is worth.
@export_range(10, 96) var outline_points: int = 44
@export var shape_seed: int = 0

@export_group("Defence")
@export var fort_cannons: int = 2
@export var garrison_ships: int = 3
@export var has_shipyard: bool = true
@export var has_castle: bool = false
## Distance from the coast at which defenders wake up.
@export var alert_radius: float = 1100.0

@export_group("Rewards")
@export var loot_table: LootTable
@export var treasure_count: int = 1

@export_group("Runtime state")
@export var discovered: bool = false
@export var captured: bool = false
@export var treasure_dug: int = 0


func is_treasure_remaining() -> bool:
	return treasure_dug < treasure_count


## Deterministic outline for this island. Both the world node and the minimap
## call this, so the map is guaranteed to match the coastline the player sails.
## The three angular harmonics this island's coastline is built from: the lobe
## counts and their phases.
##
## Exposed rather than kept inside [method build_outline] because the ocean
## shader evaluates the *same curve* to decide where the shallows are — the
## shelf used to be a circle on the mean radius, which visibly cut across
## headlands and left deep blue sitting inside bays. Two pieces of code drawing
## one coastline have to be reading one function, so this is that function and
## [method build_outline] is a caller of it. The draw order matters: phases
## first, then lobe counts, or the same seed produces a different island.
func outline_harmonics() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = shape_seed if shape_seed != 0 else hash(id)
	var phase_a: float = rng.randf() * TAU
	var phase_b: float = rng.randf() * TAU
	var phase_c: float = rng.randf() * TAU
	return {
		"lobes": Vector3(
			float(rng.randi_range(2, 3)),
			float(rng.randi_range(4, 6)),
			float(rng.randi_range(8, 11))
		),
		"phases": Vector3(phase_a, phase_b, phase_c),
	}


## The coast's radius at a bearing, in island-local units. The curve itself.
func coast_radius(angle: float, harmonics: Dictionary) -> float:
	var lobes: Vector3 = harmonics["lobes"]
	var phases: Vector3 = harmonics["phases"]
	var n: float = (
		sin(angle * lobes.x + phases.x) * 0.55
		+ sin(angle * lobes.y + phases.y) * 0.30
		+ sin(angle * lobes.z + phases.z) * 0.15
	)
	return radius * (1.0 + n * raggedness * 0.5)


func build_outline() -> PackedVector2Array:
	# Three octaves of angular noise gives bays and headlands rather than the
	# uniform fuzz a single random offset per point produces.
	var harmonics: Dictionary = outline_harmonics()
	var points := PackedVector2Array()
	points.resize(outline_points)
	for i: int in outline_points:
		var t: float = float(i) / float(outline_points) * TAU
		points[i] = Vector2(cos(t), sin(t)) * coast_radius(t, harmonics)
	return points


## The sheltered stretch of coast, in island-local space: where the harbour is
## built.
##
## The widest, flattest stretch of coast makes the most believable beach; the
## point furthest from the centre is a cliff, so take the closest instead.
func sheltered_shore(outline: PackedVector2Array) -> Vector2:
	if outline.is_empty():
		return Vector2.ZERO
	var best: Vector2 = outline[0]
	for p: Vector2 in outline:
		if p.length_squared() < best.length_squared():
			best = p
	return best


## A point off the coast where a ship can moor — the mooring buoy at the end of
## the island's [Port].
##
## Derived from [method sheltered_shore] rather than found independently, so the
## water the player is steering for is always straight off the jetty they can
## see. The default offset clears the largest hull's keep-out ring (see
## [constant Ship.COAST_STANDOFF]), so it is somewhere a ship will willingly
## sail to. The last stretch to the quay is the longboat's job.
func beach_anchor(outline: PackedVector2Array, offset: float = 320.0) -> Vector2:
	if outline.is_empty():
		return world_position
	var shore: Vector2 = sheltered_shore(outline)
	return world_position + shore + shore.normalized() * offset
