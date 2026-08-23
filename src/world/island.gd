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
const BEACH_SHADER: Shader = preload("res://src/world/terrain/beach.gdshader")
const TERRAIN_LIGHT_SHADER: Shader = preload(
	"res://src/world/terrain/terrain_light.gdshader"
)
const GRASS_TEXTURE: String = "res://assets/wave1/terrain/fill_grass.png"
const PALM_TEXTURES: Array[String] = [
	"res://assets/wave0/props/palm_0.png",
	"res://assets/wave1/props/palm_1.png",
]
const ROCK_TEXTURES: Array[String] = [
	"res://assets/wave0/props/rock_0.png",
	"res://assets/wave1/props/rock_1.png",
]
## Wave 0 masters are 2x nominal.
const PROP_SCALE: float = 0.5
## Props per 1000px of island radius.
const PROP_DENSITY: float = 14.0
## Where a prop's shadow falls, and how flat it lies. Same bearing as
## [constant Ship.SHADOW_OFFSET] and the same sun the terrain and the sea are lit
## by — one light source or the scene comes apart.
const PROP_SHADOW_BEARING: Vector2 = Vector2(0.55, 0.83)
const PROP_SHADOW_SQUASH: float = 0.42
const PROP_SHADOW_TINT: Color = Color(0.05, 0.06, 0.04, 0.32)

signal captured()
signal alerted()

var def: IslandDef
var outline: PackedVector2Array
## Where this island's treasure sits: on the quay, inside the [Port].
var treasure_local: Vector2 = Vector2.ZERO
## The mooring buoy off the end of the jetty. Everything that wants to bring a
## ship to this island steers for this.
var anchor_point: Vector2 = Vector2.ZERO
## The harbour. Every island has one, including home.
var port: Port = null

var is_alerted: bool = false
var is_captured: bool = false

## Living shore batteries. An island is not taken until this is empty — see
## [SpawnDirector].
var forts: Array[Fort] = []
## The slipway, while it stands. Null on islands that never had one and on any
## island whose yard has been burned. See [Shipyard].
var shipyard: Shipyard = null
## The castle keep, on the one island in a voyage that has one. See [CastleKeep].
var keep: CastleKeep = null

## Distance from the centre to the furthest point of the coastline. Registered as
## the island's grid radius so that a proximity query cannot miss a headland that
## reaches well beyond the mean radius.
var outer_radius: float = 0.0

var _flag: Polygon2D
var _props: Node2D
## Local position of the sheltered shore the harbour is built on. Props and
## shore batteries are laid out around it, so nothing is scattered on top of the
## one structure the player has to sail to.
var _shore_local: Vector2 = Vector2.ZERO


func setup(island_def: IslandDef) -> void:
	def = island_def
	name = "Island_%s" % def.id
	global_position = def.world_position
	outline = def.build_outline()
	for point: Vector2 in outline:
		outer_radius = maxf(outer_radius, point.length())
	_shore_local = def.sheltered_shore(outline)
	anchor_point = def.beach_anchor(outline)
	# An island can start captured two ways: the generator said so (the home port
	# always does), or the player took it on an earlier visit.
	is_captured = def.captured or GameState.is_island_captured(def.id)
	if is_captured:
		def.captured = true
		def.discovered = true

	_build_visuals()
	_build_collision()
	_build_port()
	_build_forts()
	_build_shipyard()
	_build_keep()
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
	# Faint, because it is no longer the surf — the ocean shader draws a proper
	# breaking line and a wash against the sand now, and this Line2D sat on top of
	# both as a flat white rim of constant width that followed the coast without
	# reacting to anything. What is left of it is a hint of standing spray at the
	# very edge, and it is also what covers the seam between two draw orders.
	surf.default_color = Color(1, 1, 1, 0.22)
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
	_apply_wet_band(beach)
	add_child(beach)

	# Grass over the sand, on a line of its own — see [method _vegetation_line].
	# Order matters and briefly did not: with the beach a solid polygon on the
	# full outline, drawing it second paints sand over the entire island.
	#
	# Two layers, with independent wanders. One polygon however ragged still ends
	# in a razor edge, and a treeline is not an edge — it is scrub thinning out
	# into sand over several metres. A translucent seaward layer and an opaque
	# inland one, each following a different curve, cross over each other and give
	# the boundary a broken band instead of a line, at the cost of one polygon.
	for layer: int in 2:
		var seaward: bool = layer == 0
		var grass := Polygon2D.new()
		grass.name = "Scrub" if seaward else "Interior"
		grass.polygon = _vegetation_line(0.55 if seaward else 1.0, 0 if seaward else 91)
		grass.z_index = -1
		if (
			def.biome in [IslandDef.Biome.TROPICAL, IslandDef.Biome.JUNGLE]
			and ResourceLoader.exists(GRASS_TEXTURE)
		):
			grass.texture = load(GRASS_TEXTURE)
			grass.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			grass.texture_scale = Vector2(0.6, 0.6)
			# Jungle reuses the same seamless material with the biome tint doing
			# the grading. Later biomes stay procedural until their fills land.
			grass.color = colors["interior"].lightened(0.18)
		else:
			grass.color = colors["interior"]
		if seaward:
			grass.color.a = 0.5
		add_child(grass)

	# Sun and shade over the whole island, sand and grass alike, drawn after both
	# so it lights them as one piece of ground rather than two polygons that
	# happen to touch.
	_build_terrain_light()

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
		var at: Vector2 = Vector2(cos(angle), sin(angle)) * dist
		# And off the harbour. A palm growing through the roof of a warehouse is
		# the one place scattered scenery can land on something the player has to
		# read, so the port simply wins the ground it stands on.
		if at.distance_to(_shore_local) < Port.CLEARANCE:
			continue

		var scale: float = PROP_SCALE * rng.randf_range(0.82, 1.15)

		# A shadow first, so the prop stands on the ground instead of on top of
		# it. Every ship in the game casts one and nothing on land did, which is
		# most of why palms read as stickers laid on green.
		#
		# The prop's own silhouette, squashed and laid over in the sun's
		# direction — no new art, and it is the right shape by construction. The
		# offset is the same bearing the hulls use, because there is one sun.
		var shadow := Sprite2D.new()
		shadow.texture = texture
		shadow.offset = Vector2(0, -texture.get_height() * 0.5)
		shadow.scale = Vector2(scale, scale * PROP_SHADOW_SQUASH)
		shadow.position = at + PROP_SHADOW_BEARING * texture.get_height() * scale * 0.16
		shadow.modulate = PROP_SHADOW_TINT
		shadow.z_index = -1
		_props.add_child(shadow)

		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.position = at
		# Pivot at the base, per the prop convention in docs/ASSETS.md §0.
		sprite.offset = Vector2(0, -texture.get_height() * 0.5)
		sprite.scale = Vector2.ONE * scale
		sprite.flip_h = rng.randf() < 0.5
		_props.add_child(sprite)


## Darkens the strip of sand the sea has just been over.
##
## The band follows the same three harmonics the outline was cut from, so it
## tracks headlands and bays rather than sitting at a constant radius. See
## `beach.gdshader` for why a coast needs one at all.
func _apply_wet_band(beach: Polygon2D) -> void:
	var harmonics: Dictionary = def.outline_harmonics()
	var material := ShaderMaterial.new()
	material.shader = BEACH_SHADER
	material.set_shader_parameter("island_radius", def.radius)
	material.set_shader_parameter("raggedness", def.raggedness)
	material.set_shader_parameter("lobes", harmonics["lobes"])
	material.set_shader_parameter("phases", harmonics["phases"])

	# A second polygon on the same outline rather than a material on the beach
	# itself — see the shader for why. It multiplies, so it darkens the sand Godot
	# has already drawn without having to redraw any of it.
	var wet := Polygon2D.new()
	wet.name = "WetSand"
	wet.polygon = beach.polygon
	wet.material = material
	beach.add_child(wet)


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


## Builds the harbour, and puts this island's treasure on its quay.
##
## The treasure used to be buried at a random point inland, which meant the one
## mark the player could see sat on ground the game gives them no way to walk on,
## while collection actually happened out at sea wherever the landing party
## happened to trigger. Cargo on the quay makes the mark, the place you sail to
## and the place you are paid the same place. See [Port].
func _build_port() -> void:
	port = Port.new()
	add_child(port)
	port.setup(self, _shore_local, anchor_point)
	treasure_local = port.cargo_local()


## Rings the coast with shore batteries.
##
## `fort_cannons` has been authored per island since the generator was written and
## read by nothing, so tier only ever changed how many ships came out to meet you.
## Spread evenly around the whole coast rather than clustered on the seaward side:
## a player who works out that the far side is undefended has found a real approach
## rather than a bug, and a ring is what makes circling the island worth doing.
##
## The ring is keyed to the harbour rather than to a random compass point. The
## first gun sits just round the headland from the jetty and the rest follow at
## the even spacing, which does two things: nothing is ever built on top of the
## quay, and the battery that matters is the one covering the water a ship has to
## cross to reach the mooring. A random offset gave a single-gun island a
## one-in-two chance of putting its only battery on the blind side, where it
## never fires at anything.
##
## Which side of the harbour it starts on is still random, so the approach is not
## the same picture on every island.
##
## A captured island keeps no guns — capture requires silencing them all, and an
## island the player took on an earlier visit must not rebuild its defences behind
## their back.
func _build_forts() -> void:
	if is_captured or def.fort_cannons <= 0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(def.id) + 9133
	var count: int = def.fort_cannons
	# Never closer to the harbour than half a step, so a dense ring cannot creep
	# back onto the jetty from the other side.
	const HARBOUR_CLEARANCE: float = 0.85
	var clear: float = minf(HARBOUR_CLEARANCE, PI / float(count))
	var side: float = 1.0 if rng.randf() < 0.5 else -1.0
	var offset: float = _shore_local.angle() + clear * side

	for i: int in count:
		var bearing: float = offset + TAU * float(i) / float(count)
		var fort := Fort.new()
		add_child(fort)
		fort.setup(self, bearing)
		fort.destroyed.connect(_on_fort_destroyed.bind(fort))
		forts.append(fort)


## Builds the slipway that feeds this island's reinforcement waves.
##
## Placed on the far side of the island from its harbour, which is the whole
## point of it being a place rather than a number: the yard is the one target on
## an island that is not on the way to anything. Reaching it means committing to a
## circuit of the coast, past whatever batteries are on that side, while the
## garrison is still afloat behind you. That is the decision — go for the yard
## and take the trip, or grind the escorts down and pay for it in waves.
##
## A captured island keeps no yard, on the same rule as its guns: an island the
## player took on an earlier visit must not quietly rebuild its defences.
func _build_shipyard() -> void:
	if is_captured or not def.has_shipyard:
		return
	shipyard = Shipyard.new()
	add_child(shipyard)
	shipyard.setup(self, harbour_bearing() + PI)
	shipyard.destroyed.connect(_on_shipyard_destroyed)


func _on_shipyard_destroyed() -> void:
	shipyard = null


## Builds the castle, on the one island in a voyage that has one.
func _build_keep() -> void:
	if is_captured or not def.has_castle:
		return
	keep = CastleKeep.new()
	add_child(keep)
	keep.setup(self)
	keep.destroyed.connect(_on_keep_destroyed)
	keep.shrugged_off.connect(_on_keep_shrugged_off)


func _on_keep_destroyed() -> void:
	keep = null


## The player has just put a broadside into the castle and watched it do almost
## nothing. That needs a sentence, immediately — an armoured target the game
## never explains is indistinguishable from a bug, and the player's next move
## after "my guns do not work" is to close the game rather than to go and silence
## the batteries the armour is keyed to.
func _on_keep_shrugged_off() -> void:
	EventBus.keep_shrugged_off.emit(self)


## true while the castle still stands. An island with a keep is not taken until
## the keep is broken, however quiet the water around it has gone.
func keep_standing() -> bool:
	return is_instance_valid(keep) and keep.alive


## Bearing, in island-local space, of the harbour. Both the slipway and the keep
## are placed opposite it, so the one stretch of coast the player has to sail to
## is never the one bristling with the things they came to destroy.
func harbour_bearing() -> float:
	return _shore_local.angle()


## true while this island can still send reinforcements. Read every tick by the
## spawn director.
func can_reinforce() -> bool:
	return is_instance_valid(shipyard) and shipyard.alive


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
	# The harbour changes hands with the island: its flag, and the buoy that
	# starts calling the player in to collect.
	if port != null:
		port.refresh()
	# And the slipway stops being a threat. An island can be taken without ever
	# burning its yard — grind down enough waves and the garrison empties anyway —
	# so this is the case where the player won the argument the long way and the
	# yard has to stop existing regardless.
	if is_instance_valid(shipyard):
		shipyard.queue_free()
	shipyard = null
	if is_instance_valid(keep):
		keep.queue_free()
	keep = null
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

	if port != null:
		port.refresh()

	GameState.apply_loot(loot)
	EventBus.treasure_dug.emit(self, loot)
	SaveSystem.request_save()
	return loot


## What a chest pays while no [LootTable] has been authored.
##
## Until the `.tres` tables land this is the whole treasure economy, so it is
## worth stating what it is balanced against: the first hull up from a Dinghy
## costs 260 gold, and **the opening island has to pay for it**.
##
## That is not a nicety. Island one is a skiff; islands two and three are each a
## Navy Sloop, which against a Dinghy has two barrels to one, eighty metres more
## reach and ten more hull. In a Sloop the same fight is comfortably winnable —
## 12.9 damage a second against 10.7, and a hundred hull against ninety-five — so
## the whole early ramp rests on the player arriving at island two in the better
## hull. If the opening chest does not cover it, island two is a fight the
## arithmetic says the player loses, and the ramp is a wall.
##
## A flat rate per tier could not do that job, and the version before this one
## claimed to and did not: at 140 a tier the opening island paid 140 plus 14 in
## prize money, and the Sloop stayed 106 gold out of reach through the fight it
## was needed for. The prices it has to clear do not start at zero, so neither can
## the curve — hence a base as well as a slope. The base is what buys the first
## hull; the slope is what keeps later chests level with later prices.
##
## The base then went up again, past the price of the hull, and that margin is
## deliberate rather than slack. A Sloop bought with the last coin in the purse
## meets island two on bare stats, and `--ladder` measured what that costs: down
## to nine per cent of hull before the Navy Sloop went under. The opening chest
## has to buy the hull *and* the first point of plating, because arriving at the
## second fight with no cushion at all is how a run ends on a single mistimed
## broadside.
##
## Diamonds only come from the outer islands and the castle, per the design: they
## buy fleet slots, so a second ship should be something you sail *out* for rather
## than something the opening island hands you.
func _fallback_loot() -> Dictionary:
	const CHEST_GOLD_BASE: int = 190
	const CHEST_GOLD_PER_TIER: int = 120
	const CASTLE_DIAMONDS: int = 4

	var loot: Dictionary = {&"gold": CHEST_GOLD_BASE + CHEST_GOLD_PER_TIER * def.tier}
	if def.has_castle:
		loot[&"diamond"] = CASTLE_DIAMONDS
	elif def.tier >= 2:
		loot[&"diamond"] = 1
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


## Lays the sun over the island. See `terrain_light.gdshader`.
##
## On its own polygon rather than as a material on the beach or the grass,
## because it has to cover both — the light does not stop at the treeline — and
## because multiplying leaves Godot's own drawing of each surface untouched.
func _build_terrain_light() -> void:
	var harmonics: Dictionary = def.outline_harmonics()
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_LIGHT_SHADER
	material.set_shader_parameter("island_radius", def.radius)
	material.set_shader_parameter("raggedness", def.raggedness)
	material.set_shader_parameter("lobes", harmonics["lobes"])
	material.set_shader_parameter("phases", harmonics["phases"])

	var light := Polygon2D.new()
	light.name = "TerrainLight"
	light.polygon = outline
	light.material = material
	light.z_index = -1
	add_child(light)


## Where the vegetation stops, as its own curve rather than a scaled copy of the
## coast.
##
## It used to be `_scaled_outline(0.78)` — the coastline multiplied by a constant
## — which meant the sand was exactly the same width everywhere and the boundary
## between it and the grass was a clean vector line parallel to the shore. Two
## nested copies of one curve is what it was and what it looked like, and it was
## the flattest thing left on screen once the water beside it had a graded shore.
##
## So the treeline gets harmonics of its own: its own phases, and one octave
## higher than the coast carries, so it wanders relative to the shore instead of
## echoing it. On top of that the beach is broadest where the coast cuts in — sand
## collects where the water is slow and is stripped from headlands where it is
## not — which comes free from the coast's own lowest lobe.
##
## Deliberately still a solid polygon. A ring mesh with the sand fading out
## across it is the better-looking answer and it was tried twice: Godot fans an
## indexed `polygons` entry from its first vertex, so every quad spanning the
## ring came out as two triangles whose alpha disagreed across the shared
## diagonal, and the island grew a row of dark teeth. Four thinner bands did not
## fix it and neither did smoothing the width. A clean ragged line beats a soft
## torn one.
func _vegetation_line(reach: float = 1.0, salt: int = 0) -> PackedVector2Array:
	var coast: Dictionary = def.outline_harmonics()
	var lobes: Vector3 = coast["lobes"]
	var phases: Vector3 = coast["phases"]

	var rng := RandomNumberGenerator.new()
	rng.seed = (def.shape_seed if def.shape_seed != 0 else hash(def.id)) ^ (0x5eed + salt)
	var own_phase_a: float = rng.randf() * TAU
	var own_phase_b: float = rng.randf() * TAU
	var own_lobes_a: float = float(rng.randi_range(3, 5))
	var own_lobes_b: float = float(rng.randi_range(7, 13))

	var count: int = outline.size()
	var out := PackedVector2Array()
	out.resize(count)
	for i: int in count:
		var t: float = float(i) / float(count) * TAU
		var edge: Vector2 = outline[i]
		var r: float = edge.length()

		# Wide in the bays. The coast's own lowest lobe already says where those
		# are: negative where it bulges seaward, positive where it cuts in.
		var bay: float = -sin(t * lobes.x + phases.x)
		# And a wander of its own, so the line is not a rescaled shore.
		var wander: float = (
			sin(t * own_lobes_a + own_phase_a) * 0.62
			+ sin(t * own_lobes_b + own_phase_b) * 0.38
		)
		# Swings kept modest. A first pass at ±0.5 and ±0.42 could nearly double
		# the band, which on a small island left almost nothing but sand.
		var band: float = def.radius * (1.0 - INTERIOR_INSET) * reach * clampf(
			1.0 + 0.34 * bay + 0.26 * wander, 0.45, 1.7
		)
		out[i] = edge.normalized() * maxf(r - band, r * 0.55)
	return out


func _scaled_outline(factor: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(outline.size())
	for i: int in outline.size():
		out[i] = outline[i] * factor
	return out
