class_name Minimap
extends Control
## The treasure map.
##
## Draws straight from the archipelago's [IslandDef] outlines — the same point
## arrays the world's coastlines are built from. That is the whole trick: there is
## no second copy of the world to keep in sync, so the map physically cannot lie
## about the shape of a coast, and rendering it costs one `_draw()` on one canvas
## item.
##
## Undiscovered islands are simply not drawn. Enemy contacts appear only inside
## the fleet's lookout radius, so the Lookout upgrade has a visible effect here.

const PARCHMENT: Color = Color("e4d5ab")
const PARCHMENT_EDGE: Color = Color("8a6f43")
const INK: Color = Color("4a3a22")
const WATER: Color = Color("c9b98d")
const ISLAND_DISCOVERED: Color = Color("b9a173")
const ISLAND_CAPTURED: Color = Color("9fb072")
const MARK_X: Color = Color("b5372c")
const SHIP_PLAYER: Color = Color("2f4a63")
const SHIP_SELECTED: Color = Color("d9a12c")
const CONTACT_ENEMY: Color = Color("8c3b34")

const MARGIN: float = 10.0
## World units the fleet can see enemy contacts from.
const LOOKOUT_RADIUS: float = 2600.0

## World units across the minimap's shorter axis. Roughly two islands and the
## water between them — enough to navigate by, small enough to read.
const WINDOW_WORLD_SIZE: float = 11000.0

const PARCHMENT_TEXTURE: String = "res://assets/wave0/ui/panel_parchment.png"
const MAP_X: Texture2D = preload("res://assets/wave1/map/map_x.png")
const MAP_SHIP: Texture2D = preload("res://assets/wave1/map/map_ship_icon.png")

var _parchment: Texture2D = null

var archipelago: Archipelago = null
var fleet: FleetController = null

var _scale: float = 1.0
var _offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists(PARCHMENT_TEXTURE):
		_parchment = load(PARCHMENT_TEXTURE)


func _process(_delta: float) -> void:
	if archipelago != null:
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if _parchment != null:
		draw_texture_rect(_parchment, rect, false)
	else:
		draw_rect(rect, PARCHMENT, true)
	draw_rect(rect, PARCHMENT_EDGE, false, 3.0)

	if archipelago == null or archipelago.islands.is_empty():
		return

	_update_transform()

	# Faint hatching to read as sea rather than blank paper.
	var step: float = 18.0
	var y: float = MARGIN
	while y < size.y - MARGIN:
		draw_line(Vector2(MARGIN, y), Vector2(size.x - MARGIN, y), WATER, 1.0)
		y += step

	for raw: Variant in archipelago.islands:
		if not is_instance_valid(raw):
			continue
		var island: Island = raw
		if not island.def.discovered:
			continue
		_draw_island(island)

	_draw_contacts()
	_draw_fleet()
	_draw_compass()


## Frames a fixed window around the fleet rather than the whole archipelago.
##
## Fitting a 30,000px voyage into a 184px corner widget makes every island a
## two-pixel smudge — technically accurate and completely useless. A local window
## keeps the nearby coastline legible, which is what the map is for; the
## full-voyage view belongs on the expanded map screen.
func _update_transform() -> void:
	var usable: Vector2 = size - Vector2(MARGIN, MARGIN) * 2.0
	var bounds: Rect2 = archipelago.world_bounds
	var centre: Vector2 = bounds.get_center()

	if fleet != null and is_instance_valid(fleet):
		centre = fleet.centroid()

	# Clamp so sailing to the edge of the world does not pan the map off paper.
	var half := Vector2(WINDOW_WORLD_SIZE, WINDOW_WORLD_SIZE) * 0.5
	centre.x = clampf(centre.x, bounds.position.x + half.x, bounds.end.x - half.x)
	centre.y = clampf(centre.y, bounds.position.y + half.y, bounds.end.y - half.y)

	_scale = minf(usable.x, usable.y) / WINDOW_WORLD_SIZE
	_offset = size * 0.5 - centre * _scale


func to_map(world_pos: Vector2) -> Vector2:
	return _offset + world_pos * _scale


func _draw_island(island: Island) -> void:
	var points := PackedVector2Array()
	points.resize(island.outline.size())
	for i: int in island.outline.size():
		points[i] = to_map(island.global_position + island.outline[i])

	draw_colored_polygon(
		points, ISLAND_CAPTURED if island.is_captured else ISLAND_DISCOVERED
	)
	# Closed outline; draw_polyline needs the first point repeated.
	var closed: PackedVector2Array = points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, INK, 1.5)

	if island.def.is_treasure_remaining() and island.def.discovered:
		_draw_x(to_map(island.treasure_world_position()), 6.0)


func _draw_x(at: Vector2, r: float) -> void:
	var size: Vector2 = Vector2.ONE * r * 2.4
	draw_texture_rect(MAP_X, Rect2(at - size * 0.5, size), false)


func _draw_contacts() -> void:
	if fleet == null or not is_instance_valid(fleet):
		return
	var centre: Vector2 = fleet.centroid()
	for node: Node2D in Grid.query_radius(
		centre, LOOKOUT_RADIUS, SpatialGrid.KIND_ENEMY_SHIP
	):
		draw_circle(to_map(node.global_position), 3.0, CONTACT_ENEMY)


func _draw_fleet() -> void:
	if fleet == null or not is_instance_valid(fleet):
		return
	for ship: Ship in fleet.living_ships():
		var at: Vector2 = to_map(ship.global_position)
		var color: Color = SHIP_SELECTED if ship.selected else SHIP_PLAYER
		var heading: Vector2 = ship.forward()
		# The icon master points up at rotation zero, while Vector2.angle() calls
		# up -PI/2. The quarter turn keeps the painted prow on the true heading.
		draw_set_transform(at, heading.angle() + PI * 0.5)
		draw_texture_rect(
			MAP_SHIP, Rect2(Vector2(-7.0, -9.0), Vector2(14.0, 18.0)), false, color
		)
		draw_set_transform(Vector2.ZERO, 0.0)


func _draw_compass() -> void:
	var at := Vector2(size.x - MARGIN - 14.0, MARGIN + 14.0)
	draw_arc(at, 10.0, 0.0, TAU, 16, INK, 1.5)
	draw_line(at + Vector2(0, 8), at + Vector2(0, -8), INK, 2.0)
	draw_colored_polygon(
		PackedVector2Array([
			at + Vector2(0, -11), at + Vector2(-3, -4), at + Vector2(3, -4)
		]),
		MARK_X
	)


## Screen position inside the minimap → world position. For tap-to-order-a-course
## from the map, once that is wired up.
func map_to_world(local_pos: Vector2) -> Vector2:
	if _scale <= 0.0:
		return Vector2.ZERO
	return (local_pos - _offset) / _scale
