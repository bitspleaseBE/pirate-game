class_name WorldOverlay
extends Node2D
## Draws every in-world UI element — health bars, selection rings, the target
## reticle, the course marker — in a single canvas item.
##
## The obvious alternative is a little bar node parented to each ship. With 30
## ships that is 90+ canvas items being transformed and batched every frame, plus
## the counter-rotation each one needs so the bar does not tilt with the hull.
## Here it is one `_draw()` and one batch, and the counter-rotation problem simply
## does not exist because nothing is parented to a ship.
##
## Sizes are divided by the camera zoom so the UI stays a constant size on screen
## while the world scales.

const BAR_WIDTH: float = 56.0
const BAR_HEIGHT: float = 5.0
const BAR_GAP: float = 2.0
const BAR_MARGIN: float = 18.0

const COLOR_HULL: Color = Color("d9534f")
const COLOR_SAILS: Color = Color("efe4c8")
const COLOR_CANNONS: Color = Color("9aa7b0")
const COLOR_BAR_BG: Color = Color(0, 0, 0, 0.45)
const COLOR_SELECT: Color = Color("f0c04a")
const COLOR_TARGET: Color = Color("e2564a")
const COLOR_COURSE: Color = Color(0.95, 0.95, 0.85, 0.55)

var fleet: FleetController = null


func _ready() -> void:
	# Above the world, below the HUD CanvasLayer.
	z_index = 50
	z_as_relative = false


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return
	# One world unit per screen pixel at the current zoom.
	var s: float = 1.0 / maxf(0.01, camera.zoom.x)

	_draw_enemies(s)
	_draw_fleet(s)


func _draw_enemies(s: float) -> void:
	for node: Node2D in Grid.query_rect(Cull.get_cull_rect(), SpatialGrid.KIND_ENEMY_SHIP):
		var ship := node as Ship
		if ship == null or not ship.alive:
			continue
		# An untouched enemy shows no bar. Bars everywhere is noise; a bar
		# appearing is information.
		if ship.hull_fraction() >= 0.999 and ship.sails_fraction() >= 0.999:
			continue
		_draw_bars(ship, s, false)


func _draw_fleet(s: float) -> void:
	if fleet == null or not is_instance_valid(fleet):
		return

	for ship: Ship in fleet.living_ships():
		_draw_bars(ship, s, true)

		if ship.selected:
			_draw_selection(ship, s)
			if ship.has_nav_target:
				_draw_course(ship, s)
			if ship.target != null and is_instance_valid(ship.target):
				_draw_reticle(ship.target.global_position, s)
		# The firing arc is the most useful feedback in the game, but drawn all the
		# time it swamps the screen — two cones the size of the viewport. So it
		# only appears once you have picked something to shoot at, which is
		# exactly when the angle matters.
		if ship.selected and ship.can_shoot() and ship.target != null:
			_draw_broadside_arcs(ship)


func _draw_bars(ship: Ship, s: float, include_cannons: bool) -> void:
	var width: float = BAR_WIDTH * s
	var height: float = BAR_HEIGHT * s
	var gap: float = BAR_GAP * s
	var origin: Vector2 = ship.global_position + Vector2(
		-width * 0.5, -(ship.stats.hull_radius + BAR_MARGIN * s)
	)

	var rows: Array = [[ship.hull_fraction(), COLOR_HULL], [ship.sails_fraction(), COLOR_SAILS]]
	if include_cannons:
		rows.append([ship.cannons_fraction(), COLOR_CANNONS])

	for i: int in rows.size():
		var y: float = origin.y - float(rows.size() - 1 - i) * (height + gap)
		var rect := Rect2(Vector2(origin.x, y), Vector2(width, height))
		draw_rect(rect, COLOR_BAR_BG, true)
		var fraction: float = clampf(rows[i][0], 0.0, 1.0)
		if fraction > 0.0:
			draw_rect(
				Rect2(rect.position, Vector2(width * fraction, height)), rows[i][1], true
			)


func _draw_selection(ship: Ship, s: float) -> void:
	var radius: float = ship.stats.hull_radius * 1.5
	draw_arc(ship.global_position, radius, 0.0, TAU, 32, COLOR_SELECT, 3.0 * s, false)


func _draw_course(ship: Ship, s: float) -> void:
	_draw_dashed(ship.global_position, ship.nav_target, COLOR_COURSE, 2.0 * s, 22.0 * s)

	var r: float = 12.0 * s
	var p: Vector2 = ship.nav_target
	draw_line(p + Vector2(-r, 0), p + Vector2(r, 0), COLOR_COURSE, 2.5 * s)
	draw_line(p + Vector2(0, -r), p + Vector2(0, r), COLOR_COURSE, 2.5 * s)


func _draw_reticle(at: Vector2, s: float) -> void:
	var radius: float = 40.0 * s
	var spin: float = float(Time.get_ticks_msec()) * 0.0012
	# Four corner brackets rather than a full circle: it reads as a lock-on and
	# does not hide the ship underneath it.
	for i: int in 4:
		var start: float = spin + float(i) * TAU / 4.0
		draw_arc(at, radius, start, start + 0.42, 6, COLOR_TARGET, 3.0 * s, false)


func _draw_broadside_arcs(ship: Ship) -> void:
	var arc: float = deg_to_rad(ship.stats.broadside_arc_deg)
	var reach: float = ship.stats.cannon_range
	if ship.loaded_ammo != null:
		reach = ship.loaded_ammo.effective_range(reach)

	# Only the range arc and a short tick at each shoulder. A filled wedge tints a
	# third of the screen, and full-length radial lines cut across the hull and
	# every other ship in frame — both make the picture harder to read, which is
	# the opposite of what this is for.
	var edge := Color(COLOR_SELECT.r, COLOR_SELECT.g, COLOR_SELECT.b, 0.34)
	var width: float = 2.0 / maxf(0.01, get_viewport().get_camera_2d().zoom.x)
	var tick_from: float = reach * 0.86

	for side: float in [1.0, -1.0]:
		var mid: float = (ship.starboard() * side).angle()
		draw_arc(ship.global_position, reach, mid - arc, mid + arc, 24, edge, width, false)
		for bound: float in [mid - arc, mid + arc]:
			var dir := Vector2(cos(bound), sin(bound))
			draw_line(
				ship.global_position + dir * tick_from,
				ship.global_position + dir * reach,
				edge,
				width
			)


func _draw_dashed(
	from: Vector2, to: Vector2, color: Color, width: float, dash: float
) -> void:
	var total: float = from.distance_to(to)
	if total < 1.0:
		return
	var dir: Vector2 = (to - from) / total
	var travelled: float = 0.0
	while travelled < total:
		var end: float = minf(travelled + dash, total)
		draw_line(from + dir * travelled, from + dir * end, color, width)
		travelled = end + dash
