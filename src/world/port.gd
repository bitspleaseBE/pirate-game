class_name Port
extends Node2D
## An island's harbour: a quay, a jetty, and a mooring buoy off the end of it.
##
## The port used to be a bare Vector2. [method IslandDef.beach_anchor] picked a
## point off the flattest stretch of coast and nothing drew it, so collecting an
## island's treasure meant drifting near an unmarked patch of open water until
## gold appeared somewhere behind you — the reward landing at random rather than
## at a place you sailed to. The one visible mark, the X, was inland on ground
## the player has no way to reach.
##
## The harbour is now that place, and it gathers up every thread that was loose:
## the buoy is exactly where the ship has to be, the cargo sits on the quay where
## the map's X now points, and the longboat rows the last stretch out to you so
## the moment of collection is something you watch arrive.
##
## Polygons rather than a sprite, on the same grounds as [Fort]: there is no
## authored harbour art, and a jetty is a deck, some pilings and two sheds.

const CHEST_TEXTURE: String = "res://assets/wave1/props/chest_closed.png"
const X_TEXTURE: String = "res://assets/wave1/props/x_marks_spot.png"
## Wave 1 masters are 2x nominal, as everywhere else in the prop pipeline.
const PROP_SCALE: float = 0.5

## Deck length as a fraction of the island's radius, and the bounds on it.
##
## Long and narrow is the whole silhouette — a jetty that does not reach well out
## into the water reads as a crate on a beach. It still stops short of the
## mooring, both because a hull of any size lies off in the roads rather than
## coming alongside timber, and because [constant Ship.COAST_STANDOFF] keeps
## ships a little beyond the head anyway. That gap is what the longboat is for.
const DECK_FRACTION: float = 0.50
const DECK_MIN: float = 150.0
const DECK_MAX: float = 200.0
const DECK_HALF_WIDTH: float = 19.0
## The landing at the shore end, where the cargo is stacked. Kept narrow enough
## to sit on the sand rather than sprawling up onto the grass behind it.
const QUAY_HALF_WIDTH: float = 40.0
const QUAY_INSET: float = 34.0
const QUAY_REACH: float = 30.0
const PILING_SPACING: float = 46.0
const BUOY_RADIUS: float = 16.0
## Radius of the footprint props must keep out of, measured from the quay. Wide
## enough to cover the sheds set furthest back from the water.
const CLEARANCE: float = 200.0

const COLOR_DECK: Color = Color("9a7649")
const COLOR_PLANK: Color = Color("6d5236")
const COLOR_PILING: Color = Color("4a3a26")
const COLOR_SHADOW: Color = Color(0.10, 0.09, 0.07, 0.28)
const COLOR_SHED: Color = Color("8d6a41")
const COLOR_SHED_ROOF: Color = Color("b98f56")
const COLOR_SHED_RIDGE: Color = Color("5c452c")
const COLOR_BUOY: Color = Color("d94f3d")
const COLOR_BUOY_BAND: Color = Color("efe4c8")
const COLOR_ROPE: Color = Color(0.93, 0.90, 0.78, 0.30)
const COLOR_BOAT: Color = Color("54402a")
const COLOR_CARGO: Color = Color("c8a24a")
const COLOR_OWNED: Color = Color("d9a12c")
const COLOR_HOSTILE: Color = Color("8c3b34")

var _island: Island = null
## Unit vector from the shore point out to sea, and its right-hand normal.
## Everything in this node is laid out along these two rather than along a
## rotation, so the sprites on the quay stay upright the way every other prop in
## the game does.
var _out: Vector2 = Vector2.RIGHT
var _side: Vector2 = Vector2.DOWN
var _deck: float = DECK_MIN
var _mooring_local: Vector2 = Vector2.ZERO

var _cargo: Node2D = null
## Where the longboat rowed from, and how far through the trip it is.
var _boat_to: Vector2 = Vector2.ZERO
var _unloading: bool = false
var _unload_total: float = 1.0
var _unload_left: float = 0.0
var _clock: float = 0.0


## Builds the harbour on `island`'s sheltered coast. `shore_local` is the point
## on the outline it is built against and `mooring_world` the buoy off the end of
## it — both come from the same [IslandDef] call, so the deck and the water the
## player is steering for cannot drift apart.
func setup(island: Island, shore_local: Vector2, mooring_world: Vector2) -> void:
	_island = island
	name = "Port_%s" % island.def.id

	# A hair inside the waterline, so the quay sits on sand rather than floating
	# off the end of the beach polygon. Same trick as Fort.setup.
	position = shore_local * 0.97
	_out = shore_local.normalized() if shore_local.length_squared() > 1.0 else Vector2.RIGHT
	_side = _out.orthogonal()
	_deck = clampf(island.def.radius * DECK_FRACTION, DECK_MIN, DECK_MAX)
	_mooring_local = (mooring_world - island.global_position) - position

	# Above the beach and interior polygons, which sit at negative z.
	z_index = 1
	_build_cargo()
	refresh()


## Where the cargo sits, in the island's local space. The minimap's X is drawn
## here, so the mark on the map is the crate on the quay.
func cargo_local() -> Vector2:
	return position + _at(-8.0, 0.0)


## Re-reads the island's state: who holds the harbour, whether there is still
## cargo on the quay, and therefore whether this node needs to animate at all.
func refresh() -> void:
	if _cargo != null:
		_cargo.visible = _island != null and _island.def.is_treasure_remaining()
	# Idle harbours cost nothing. The buoy only pulses where the player can
	# actually collect something, which is also the only place the hint is worth
	# anything — every other harbour in the archipelago is scenery.
	set_process(_unloading or _awaiting_collection())
	queue_redraw()


## Sends the boat out to a ship lying at `ship_world`. The trip lasts `seconds`
## and lands exactly when the treasure is credited, so the gold arrives with the
## boat rather than out of nowhere.
func begin_unloading(ship_world: Vector2, seconds: float) -> void:
	_boat_to = to_local(ship_world)
	_unloading = true
	_unload_total = maxf(0.01, seconds)
	_unload_left = _unload_total
	refresh()


func finish_unloading() -> void:
	_unloading = false
	refresh()


func _process(delta: float) -> void:
	_clock += delta
	if _unloading:
		_unload_left = maxf(0.0, _unload_left - delta)
	queue_redraw()


func _awaiting_collection() -> bool:
	return (
		_island != null
		and _island.is_captured
		and _island.def.is_treasure_remaining()
	)


## A point in this node's space, `along` the harbour axis and `across` it.
func _at(along: float, across: float) -> Vector2:
	return _out * along + _side * across


func _build_cargo() -> void:
	_cargo = Node2D.new()
	_cargo.name = "Cargo"
	_cargo.position = _at(-8.0, 0.0)
	add_child(_cargo)

	# The X stays: it is the one piece of treasure-map language the game has, and
	# it now marks a spot the player can actually sail to.
	if ResourceLoader.exists(X_TEXTURE):
		var mark := Sprite2D.new()
		mark.name = "XMarksSpot"
		mark.texture = load(X_TEXTURE)
		mark.scale = Vector2.ONE * PROP_SCALE
		_cargo.add_child(mark)

	if ResourceLoader.exists(CHEST_TEXTURE):
		var chest := Sprite2D.new()
		chest.name = "Chest"
		chest.texture = load(CHEST_TEXTURE)
		# Pivot at the base, per the prop convention in docs/ASSETS.md §0.
		chest.offset = Vector2(0.0, -chest.texture.get_height() * 0.5)
		chest.scale = Vector2.ONE * PROP_SCALE
		chest.position = Vector2(0.0, -4.0)
		_cargo.add_child(chest)


func _draw() -> void:
	_draw_sheds()
	_draw_quay()
	_draw_jetty()
	_draw_mooring()
	if _unloading:
		_draw_longboat()


## Two store sheds set back from the water, angled with the harbour. What makes
## the shape read as a port from a distance rather than as a pier someone left on
## an empty beach.
func _draw_sheds() -> void:
	_draw_shed(_at(-84.0, 78.0), 74.0, 54.0)
	_draw_shed(_at(-126.0, -32.0), 58.0, 44.0)


## A shed as a shadow, a wall plane and a lit roof inset into it. The inset is
## what does the work: a single flat rectangle on grass reads as a dropped plank,
## and two tones of it read as a roof with eaves.
func _draw_shed(centre: Vector2, length: float, width: float) -> void:
	var half_l: Vector2 = _out * length * 0.5
	var half_w: Vector2 = _side * width * 0.5
	_draw_box(centre + Vector2(5.0, 7.0), half_l, half_w, COLOR_SHADOW)
	_draw_box(centre, half_l, half_w, COLOR_SHED)
	_draw_box(centre, half_l * 0.78, half_w * 0.72, COLOR_SHED_ROOF)
	draw_line(centre - half_l * 0.72, centre + half_l * 0.72, COLOR_SHED_RIDGE, 3.0)


func _draw_box(centre: Vector2, half_l: Vector2, half_w: Vector2, color: Color) -> void:
	draw_colored_polygon(
		PackedVector2Array([
			centre - half_l - half_w,
			centre + half_l - half_w,
			centre + half_l + half_w,
			centre - half_l + half_w,
		]),
		color
	)


## The landing at the shore end: wider than the deck, because this is where the
## cargo is stacked and a crate is wider than a walkway.
func _draw_quay() -> void:
	draw_colored_polygon(
		PackedVector2Array([
			_at(-QUAY_INSET, -QUAY_HALF_WIDTH),
			_at(QUAY_REACH, -QUAY_HALF_WIDTH),
			_at(QUAY_REACH, QUAY_HALF_WIDTH),
			_at(-QUAY_INSET, QUAY_HALF_WIDTH),
		]),
		COLOR_DECK
	)
	for across: float in [-QUAY_HALF_WIDTH, QUAY_HALF_WIDTH]:
		draw_line(_at(-QUAY_INSET, across), _at(QUAY_REACH, across), COLOR_PLANK, 4.0)

	# The harbour flag. Ownership has to be readable from the water — this is the
	# only structure on the island the player has business with once the guns are
	# quiet, and which flag is over it is the difference between a shop and a
	# fight.
	var pole: Vector2 = _at(-QUAY_INSET + 8.0, -QUAY_HALF_WIDTH + 8.0)
	draw_line(pole, pole + Vector2(0.0, -46.0), COLOR_PILING, 4.0)
	var owned: bool = _island != null and _island.is_captured
	draw_colored_polygon(
		PackedVector2Array([
			pole + Vector2(0.0, -46.0),
			pole + Vector2(26.0, -39.0),
			pole + Vector2(0.0, -30.0),
		]),
		COLOR_OWNED if owned else COLOR_HOSTILE
	)


func _draw_jetty() -> void:
	var head: float = _deck
	var deck: PackedVector2Array = PackedVector2Array([
		_at(QUAY_REACH - 4.0, -DECK_HALF_WIDTH),
		_at(head, -DECK_HALF_WIDTH),
		_at(head, DECK_HALF_WIDTH),
		_at(QUAY_REACH - 4.0, DECK_HALF_WIDTH),
	])
	# A shadow on the water first, so the deck sits above the surface rather than
	# being painted onto it.
	var shifted := PackedVector2Array()
	for p: Vector2 in deck:
		shifted.append(p + Vector2(6.0, 9.0))
	draw_colored_polygon(shifted, COLOR_SHADOW)
	draw_colored_polygon(deck, COLOR_DECK)

	# Planks across the deck and a piling under each pair of edges. Both are what
	# keep a long brown rectangle reading as timber over water.
	var along: float = QUAY_REACH + 10.0
	while along < head:
		draw_line(_at(along, -DECK_HALF_WIDTH), _at(along, DECK_HALF_WIDTH), COLOR_PLANK, 3.0)
		for across: float in [-DECK_HALF_WIDTH, DECK_HALF_WIDTH]:
			draw_circle(_at(along, across), 5.0, COLOR_PILING)
		along += PILING_SPACING

	# Bollards at the head, where a boat ties up.
	for across: float in [-11.0, 11.0]:
		draw_circle(_at(head - 12.0, across), 6.0, COLOR_PILING)


## The buoy, and the rope out to it. This is the thing the player actually steers
## for: [member Island.anchor_point] is here, so "sail to the buoy" and "trigger
## the landing" are finally the same instruction.
func _draw_mooring() -> void:
	var head: Vector2 = _at(_deck - 6.0, 0.0)
	draw_line(head, _mooring_local, COLOR_ROPE, 2.5)

	# Bobbing, but only where there is something to collect — see refresh().
	var bob: float = sin(_clock * 2.1) * 3.0 if is_processing() else 0.0
	var at: Vector2 = _mooring_local + Vector2(0.0, bob)

	if _awaiting_collection():
		# A ring easing outward off the buoy. The reward is already earned and
		# sitting on that quay, and this is the only thing on screen saying which
		# patch of water collects it.
		var t: float = fposmod(_clock * 0.7, 1.0)
		draw_arc(
			at,
			BUOY_RADIUS + t * 58.0,
			0.0,
			TAU,
			28,
			Color(COLOR_OWNED, (1.0 - t) * 0.85),
			4.0,
			false
		)

	draw_circle(at, BUOY_RADIUS, COLOR_BUOY)
	draw_line(at + _side * BUOY_RADIUS, at - _side * BUOY_RADIUS, COLOR_BUOY_BAND, 5.0)
	draw_line(at, at + Vector2(0.0, -BUOY_RADIUS - 12.0), COLOR_PILING, 3.0)


## The boat carrying the cargo out. It leaves the jetty head when the ship moors
## and reaches her exactly as the treasure is credited, so there is one thing to
## watch and it arrives on the beat.
func _draw_longboat() -> void:
	var t: float = 1.0 - clampf(_unload_left / _unload_total, 0.0, 1.0)
	var from: Vector2 = _at(_deck + 6.0, 0.0)
	var at: Vector2 = from.lerp(_boat_to, t)
	var heading: Vector2 = (_boat_to - from).normalized()
	if heading.length_squared() < 0.5:
		heading = _out
	var beam: Vector2 = heading.orthogonal()

	# Oars first, so the hull sits over their looms. Swinging, because motion is
	# what separates a boat under way from a plank floating past.
	var stroke: float = sin(_clock * 7.0) * 9.0
	for sign_: float in [1.0, -1.0]:
		var root: Vector2 = at + beam * 9.0 * sign_
		draw_line(root, root + (beam * 24.0 + heading * stroke) * sign_, COLOR_BOAT, 3.0)

	# A pointed bow and a rounded stern. Fewer points than this and the hull reads
	# as an arrowhead rather than as a boat.
	const HULL: Array[Vector2] = [
		Vector2(28.0, 0.0), Vector2(18.0, 8.0), Vector2(4.0, 11.0), Vector2(-12.0, 9.0),
		Vector2(-20.0, 0.0), Vector2(-12.0, -9.0), Vector2(4.0, -11.0), Vector2(18.0, -8.0),
	]
	var hull := PackedVector2Array()
	var shadow := PackedVector2Array()
	var inner := PackedVector2Array()
	for p: Vector2 in HULL:
		var world: Vector2 = at + heading * p.x + beam * p.y
		hull.append(world)
		shadow.append(world + Vector2(5.0, 7.0))
		inner.append(at + (heading * p.x + beam * p.y) * 0.66)
	draw_colored_polygon(shadow, COLOR_SHADOW)
	draw_colored_polygon(hull, COLOR_BOAT)
	# The open inside of the boat, which is also what the chest sits in.
	draw_colored_polygon(inner, COLOR_DECK)

	# The chest itself, sitting amidships. The one warm note on the boat, so the
	# eye follows the cargo rather than the hull carrying it.
	var chest: Vector2 = at - heading * 3.0
	draw_colored_polygon(
		PackedVector2Array([
			chest + heading * 7.0 + beam * 6.0,
			chest - heading * 7.0 + beam * 6.0,
			chest - heading * 7.0 - beam * 6.0,
			chest + heading * 7.0 - beam * 6.0,
		]),
		COLOR_CARGO
	)
