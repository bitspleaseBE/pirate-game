class_name Island
extends Node2D
## One island, built entirely from its [IslandDef].
##
## Polygons, not a tilemap. An island is two [Polygon2D]s (beach and interior), a
## [Line2D] for the surf, and one collision polygon — four canvas items total,
## which Godot's own rect culling handles for free. A tilemap of the same island
## would be several hundred quads and would need an autotile set we would have to
## draw. See docs/ARCHITECTURE.md §8.
##
## The outline is also handed to the minimap, so the treasure map cannot drift
## out of sync with the coastline the player is actually sailing along.

const BIOME_COLORS: Dictionary = {
	IslandDef.Biome.TROPICAL: {"beach": Color("e8d9a8"), "interior": Color("6fae55")},
	IslandDef.Biome.JUNGLE: {"beach": Color("d8c48f"), "interior": Color("3f8446")},
	IslandDef.Biome.ROCKY: {"beach": Color("c9c2ae"), "interior": Color("7d7f72")},
	IslandDef.Biome.VOLCANIC: {"beach": Color("8a7c72"), "interior": Color("4a4340")},
	IslandDef.Biome.FROZEN: {"beach": Color("dfe9ef"), "interior": Color("b9cfd8")},
}

## Fraction of the outline radius at which the interior polygon sits.
const INTERIOR_INSET: float = 0.78
const SURF_WIDTH: float = 14.0

const SAND_TEXTURE: String = "res://assets/wave0/terrain/fill_sand.png"
const GRASS_TEXTURE: String = "res://assets/wave1/terrain/fill_grass.png"
const PALM_TEXTURES: Array[String] = [
	"res://assets/wave0/props/palm_0.png",
	"res://assets/wave1/props/palm_1.png",
]
const ROCK_TEXTURES: Array[String] = [
	"res://assets/wave0/props/rock_0.png",
	"res://assets/wave1/props/rock_1.png",
]
const TREASURE_MOUND: String = "res://assets/wave1/props/treasure_mound.png"
const TREASURE_X: String = "res://assets/wave1/props/x_marks_spot.png"
## Wave 0 masters are 2x nominal.
const PROP_SCALE: float = 0.5
## Props per 1000px of island radius.
const PROP_DENSITY: float = 14.0

signal captured()
signal alerted()

var def: IslandDef
var outline: PackedVector2Array
var treasure_local: Vector2 = Vector2.ZERO
var anchor_point: Vector2 = Vector2.ZERO

var is_alerted: bool = false
var is_captured: bool = false

## Living shore batteries. An island is not taken until this is empty — see
## [SpawnDirector].
var forts: Array[Fort] = []

## Distance from the centre to the furthest point of the coastline. Registered as
## the island's grid radius so that a proximity query cannot miss a headland that
## reaches well beyond the mean radius.
var outer_radius: float = 0.0

var _flag: Polygon2D
var _props: Node2D
var _treasure_marker: Node2D


func setup(island_def: IslandDef) -> void:
	def = island_def
	name = "Island_%s" % def.id
	global_position = def.world_position
	outline = def.build_outline()
	for point: Vector2 in outline:
		outer_radius = maxf(outer_radius, point.length())
	anchor_point = def.beach_anchor(outline)
	# An island can start captured two ways: the generator said so (the home port
	# always does), or the player took it on an earlier visit.
	is_captured = def.captured or GameState.is_island_captured(def.id)
	if is_captured:
		def.captured = true
		def.discovered = true

	_build_visuals()
	_build_collision()
	_place_treasure()
	_build_forts()
	_build_flag()

	Grid.add(self, SpatialGrid.KIND_ISLAND, outer_radius)
	# Deliberately NOT registered with the culling manager: its collision must
	# stay live even off screen or ships would sail through it, and its four
	# canvas items are already rect-culled by the renderer.


func _exit_tree() -> void:
	Grid.remove(self)


func _build_visuals() -> void:
	var colors: Dictionary = BIOME_COLORS.get(def.biome, BIOME_COLORS[IslandDef.Biome.TROPICAL])

	var surf := Line2D.new()
	surf.name = "Surf"
	surf.points = outline
	surf.closed = true
	surf.width = SURF_WIDTH
	surf.default_color = Color(1, 1, 1, 0.5)
	surf.joint_mode = Line2D.LINE_JOINT_ROUND
	surf.antialiased = false
	surf.z_index = -2
	add_child(surf)

	var beach := Polygon2D.new()
	beach.name = "Beach"
	beach.polygon = outline
	beach.z_index = -1
	if ResourceLoader.exists(SAND_TEXTURE):
		# Polygon2D derives UVs from the polygon's own coordinates, so a seamless
		# fill tiles across any shape with no UV authoring at all. This is the
		# saving that let the asset list drop a 47-piece autotile set.
		beach.texture = load(SAND_TEXTURE)
		beach.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		beach.texture_scale = Vector2(0.6, 0.6)
		beach.color = colors["beach"].lightened(0.35)
	else:
		beach.color = colors["beach"]
	add_child(beach)

	var interior := Polygon2D.new()
	interior.name = "Interior"
	interior.polygon = _scaled_outline(INTERIOR_INSET)
	if (
		def.biome in [IslandDef.Biome.TROPICAL, IslandDef.Biome.JUNGLE]
		and ResourceLoader.exists(GRASS_TEXTURE)
	):
		interior.texture = load(GRASS_TEXTURE)
		interior.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		interior.texture_scale = Vector2(0.6, 0.6)
		# Jungle reuses the same seamless material with the biome tint doing the
		# grading. Later biomes remain procedural colours until their own fills land.
		interior.color = colors["interior"].lightened(0.18)
	else:
		interior.color = colors["interior"]
	add_child(interior)

	_props = Node2D.new()
	_props.name = "Props"
	_props.y_sort_enabled = true
	add_child(_props)
	_scatter_props()


## Scatters palms and rocks inside the interior polygon.
##
## Props are plain Sprite2Ds with no script, so the renderer's own rect culling
## handles them for free — there is nothing to disable when they leave the screen,
## and adding a VisibleOnScreenEnabler2D per prop would cost more than it saves.
## They are y-sorted within the Props container so a ship never draws behind a
## palm on the far side of the island.
func _scatter_props() -> void:
	var palms: Array[Texture2D] = _load_textures(PALM_TEXTURES)
	var rocks: Array[Texture2D] = _load_textures(ROCK_TEXTURES)
	if palms.is_empty() and rocks.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(def.id) + 4211
	var count: int = maxi(3, roundi(def.radius / 1000.0 * PROP_DENSITY))
	# Rocky and frozen coasts get stone instead of palms.
	var palm_chance: float = 0.25 if def.biome >= IslandDef.Biome.ROCKY else 0.75

	for i: int in count:
		var family: Array[Texture2D] = palms if rng.randf() < palm_chance else rocks
		if family.is_empty():
			family = rocks if not rocks.is_empty() else palms
		if family.is_empty():
			continue
		var texture: Texture2D = family[rng.randi_range(0, family.size() - 1)]

		var angle: float = rng.randf() * TAU
		# Keep props off the waterline so none of them appear to float.
		var dist: float = def.radius * rng.randf_range(0.12, INTERIOR_INSET * 0.85)

		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.position = Vector2(cos(angle), sin(angle)) * dist
		# Pivot at the base, per the prop convention in docs/ASSETS.md §0.
		sprite.offset = Vector2(0, -texture.get_height() * 0.5)
		sprite.scale = Vector2.ONE * PROP_SCALE * rng.randf_range(0.82, 1.15)
		sprite.flip_h = rng.randf() < 0.5
		_props.add_child(sprite)


func _load_textures(paths: Array[String]) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for path: String in paths:
		if ResourceLoader.exists(path):
			out.append(load(path) as Texture2D)
	return out


func _build_collision() -> void:
	var body := StaticBody2D.new()
	body.name = "Land"
	# Layer 3 = land. Ships collide with it; projectiles ignore it entirely,
	# because a cannonball's impact is resolved analytically, not by contact.
	body.collision_layer = 1 << 2
	body.collision_mask = 0
	add_child(body)

	var shape := CollisionPolygon2D.new()
	# Solid from the waterline. Anything inset lets hulls ride up onto the sand,
	# which looks broken however small the overlap is — a ship is either afloat
	# or aground, and aground is not a state this game has.
	shape.polygon = outline
	body.add_child(shape)


func _place_treasure() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(def.id) + 7717
	var angle: float = rng.randf() * TAU
	var dist: float = def.radius * rng.randf_range(0.15, INTERIOR_INSET * 0.7)
	treasure_local = Vector2(cos(angle), sin(angle)) * dist

	if not def.is_treasure_remaining():
		return

	_treasure_marker = Node2D.new()
	var marker: Node2D = _treasure_marker
	marker.name = "TreasureMarker"
	marker.position = treasure_local
	add_child(marker)

	if ResourceLoader.exists(TREASURE_MOUND):
		var mound := Sprite2D.new()
		mound.name = "Mound"
		mound.texture = load(TREASURE_MOUND)
		mound.offset = Vector2(0.0, -mound.texture.get_height() * 0.5)
		mound.scale = Vector2.ONE * PROP_SCALE
		marker.add_child(mound)

	if ResourceLoader.exists(TREASURE_X):
		var mark := Sprite2D.new()
		mark.name = "XMarksSpot"
		mark.texture = load(TREASURE_X)
		mark.scale = Vector2.ONE * PROP_SCALE
		mark.position = Vector2(0.0, -8.0)
		marker.add_child(mark)


## Rings the coast with shore batteries.
##
## `fort_cannons` has been authored per island since the generator was written and
## read by nothing, so tier only ever changed how many ships came out to meet you.
## Spread evenly around the whole coast rather than clustered on the seaward side:
## a player who works out that the far side is undefended has found a real approach
## rather than a bug, and a ring is what makes circling the island worth doing.
##
## A captured island keeps no guns — capture requires silencing them all, and an
## island the player took on an earlier visit must not rebuild its defences behind
## their back.
func _build_forts() -> void:
	if is_captured or def.fort_cannons <= 0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(def.id) + 9133
	# A random start angle, so forts are not always at the same compass points.
	var offset: float = rng.randf() * TAU

	for i: int in def.fort_cannons:
		var bearing: float = offset + TAU * float(i) / float(def.fort_cannons)
		var fort := Fort.new()
		add_child(fort)
		fort.setup(self, bearing)
		fort.destroyed.connect(_on_fort_destroyed.bind(fort))
		forts.append(fort)


func _on_fort_destroyed(fort: Fort) -> void:
	forts.erase(fort)


## Shore batteries still firing. Read every tick by the spawn director, so it
## prunes freed entries rather than trusting the signal alone.
func forts_remaining() -> int:
	for i: int in range(forts.size() - 1, -1, -1):
		var entry: Variant = forts[i]
		if not is_instance_valid(entry) or not (entry as Fort).alive:
			forts.remove_at(i)
	return forts.size()


func _build_flag() -> void:
	var pole := Line2D.new()
	pole.points = PackedVector2Array([Vector2.ZERO, Vector2(0, -54)])
	pole.width = 5.0
	pole.default_color = Color("5a4632")
	pole.position = Vector2(0, -def.radius * INTERIOR_INSET * 0.35)
	add_child(pole)

	_flag = Polygon2D.new()
	_flag.polygon = PackedVector2Array(
		[Vector2(0, -54), Vector2(34, -46), Vector2(0, -34)]
	)
	_flag.color = _flag_color()
	pole.add_child(_flag)


func _flag_color() -> Color:
	if is_captured:
		return Color("d9a12c")
	return Color("2c3f5c") if def.has_castle else Color("8c3b34")


## Called by the spawn director when the player enters the alert radius.
func alert() -> void:
	if is_alerted or is_captured:
		return
	is_alerted = true
	EventBus.island_alerted.emit(self)
	alerted.emit()


func mark_discovered() -> void:
	if def.discovered:
		return
	def.discovered = true
	GameState.mark_island(def.id, true, false)
	EventBus.island_discovered.emit(self)


func capture() -> void:
	if is_captured:
		return
	is_captured = true
	def.captured = true
	if _flag != null:
		_flag.color = _flag_color()
	GameState.mark_island(def.id, true, true)
	Audio.play_at(&"island_captured", global_position)
	EventBus.island_captured.emit(self)
	captured.emit()


## Rolls this island's treasure and hands it to the player.
func dig_treasure(rng: RandomNumberGenerator) -> Dictionary:
	if not def.is_treasure_remaining():
		return {}
	def.treasure_dug += 1

	var loot: Dictionary = {}
	if def.loot_table != null:
		loot = def.loot_table.roll(rng, def.tier)
	else:
		loot = _fallback_loot()

	if not def.is_treasure_remaining() and _treasure_marker != null:
		_treasure_marker.queue_free()
		_treasure_marker = null

	GameState.apply_loot(loot)
	EventBus.treasure_dug.emit(self, loot)
	SaveSystem.request_save()
	return loot


## What a chest pays while no [LootTable] has been authored.
##
## Until the `.tres` tables land this is the whole treasure economy, so it is
## worth stating what it is balanced against: the first hull up from a Dinghy
## costs 260 gold. At the old 50-per-tier a captured opening island paid 50, which
## put the shop five more islands away and left a new player holding a currency
## that visibly did nothing. Together with prize money from the garrison
## ([method Ship._pay_bounty]) this pays the first hull off by the second island,
## which is where the loop starts teaching itself.
##
## Doubloons only come from the outer islands and the castle, per the design: they
## buy fleet slots, so a second ship should be something you sail *out* for rather
## than something the opening island hands you.
func _fallback_loot() -> Dictionary:
	const CHEST_GOLD_PER_TIER: int = 140
	const CASTLE_DOUBLOONS: int = 4

	var loot: Dictionary = {&"gold": CHEST_GOLD_PER_TIER * def.tier}
	if def.has_castle:
		loot[&"doubloon"] = CASTLE_DOUBLOONS
	elif def.tier >= 2:
		loot[&"doubloon"] = 1
	return loot


func treasure_world_position() -> Vector2:
	return global_position + treasure_local


## Distance from the island centre to the coastline, along the bearing of
## `world_pos`.
##
## The outline is sampled at uniform angles, so the bearing maps straight to an
## index — an exact answer for the cost of one lookup. Navigation needs this
## rather than the mean radius: on a ragged coast the mean is optimistic off a
## headland and needlessly cautious inside a bay, and ships would either clip land
## or refuse to enter perfectly good water.
func coast_radius_towards(world_pos: Vector2) -> float:
	if outline.is_empty():
		return def.radius
	var local: Vector2 = world_pos - global_position
	if local.length_squared() < 1.0:
		return def.radius
	var t: float = fposmod(local.angle(), TAU) / TAU
	return outline[int(round(t * outline.size())) % outline.size()].length()


func distance_to_coast(world_pos: Vector2) -> float:
	return global_position.distance_to(world_pos) - def.radius


func contains_point(world_pos: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(world_pos - global_position, outline)


func add_prop(node: Node2D) -> void:
	_props.add_child(node)


func _scaled_outline(factor: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(outline.size())
	for i: int in outline.size():
		out[i] = outline[i] * factor
	return out
