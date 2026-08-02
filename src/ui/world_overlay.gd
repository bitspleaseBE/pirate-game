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

## Alegreya, matching the HUD's counters. The overlay was still on Kenney Future
## after the HUD moved off it, so the one piece of text drawn over the world — the
## range to the objective, on screen in almost every frame — was in a typeface
## that appears nowhere else in the game. See the note at the top of hud.gd.
const FONT: String = "res://assets/fonts/Alegreya.ttf"
## How far inside the screen edge the objective arrow sits, in screen pixels.
const OBJECTIVE_INSET: float = 62.0
const COLOR_OBJECTIVE: Color = Color("e8d9a8")

const RETICLE_FRAMES: Array[Texture2D] = [
	preload("res://assets/wave1/ui/reticle_target_0.png"),
	preload("res://assets/wave1/ui/reticle_target_1.png"),
	preload("res://assets/wave1/ui/reticle_target_2.png"),
	preload("res://assets/wave1/ui/reticle_target_3.png"),
]
const WAYPOINT_FRAMES: Array[Texture2D] = [
	preload("res://assets/wave1/ui/marker_waypoint_0.png"),
	preload("res://assets/wave1/ui/marker_waypoint_1.png"),
	preload("res://assets/wave1/ui/marker_waypoint_2.png"),
	preload("res://assets/wave1/ui/marker_waypoint_3.png"),
]
var fleet: FleetController = null
var archipelago: Archipelago = null

var _font: Font = null


func _ready() -> void:
	# Above the world, below the HUD CanvasLayer.
	z_index = 50
	z_as_relative = false
	if ResourceLoader.exists(FONT):
		_font = load(FONT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return
	# One world unit per screen pixel at the current zoom.
	var s: float = 1.0 / maxf(0.01, camera.zoom.x)

	_draw_enemies(s)
	_draw_structures(s)
	_draw_fleet(s)
	_draw_objective(camera, s)


## An arrow at the screen edge pointing at whatever the player should be heading
## for, with the distance to it.
##
## Without this the opening is half a minute of open water in every direction,
## with the only confirmation you are going the right way being a two-pixel mark
## on a corner minimap. That is a rotten first impression of a game that is
## perfectly clear once anything is actually happening — and the marker keeps
## earning its place later, because an enemy that has drifted off screen mid-fight
## is the other moment a player loses the thread.
func _draw_objective(camera: Camera2D, s: float) -> void:
	var target: Vector2 = _objective_position()
	if target == Vector2.INF:
		return

	var view: Vector2 = camera.get_viewport_rect().size / camera.zoom
	var centre: Vector2 = camera.get_screen_center_position()
	var half: Vector2 = view * 0.5 - Vector2(OBJECTIVE_INSET, OBJECTIVE_INSET) * s

	var offset: Vector2 = target - centre
	# On screen already? Then the player can see it and needs no arrow.
	if absf(offset.x) < half.x and absf(offset.y) < half.y:
		return

	# Push the marker to the edge along the bearing to the objective.
	var scale_x: float = half.x / maxf(1.0, absf(offset.x))
	var scale_y: float = half.y / maxf(1.0, absf(offset.y))
	var at: Vector2 = centre + offset * minf(scale_x, scale_y)

	var dir: Vector2 = offset.normalized()
	var side: Vector2 = dir.orthogonal()
	var length: float = 20.0 * s
	draw_colored_polygon(
		PackedVector2Array([
			at + dir * length,
			at - dir * length * 0.5 + side * length * 0.6,
			at - dir * length * 0.5 - side * length * 0.6,
		]),
		COLOR_OBJECTIVE
	)

	if _font == null:
		return
	var metres: int = roundi(offset.length())
	var text: String = "%dm" % metres
	var text_size: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	draw_string(
		_font,
		at - dir * length * 1.6 - Vector2(text_size.x * 0.5 * s, 0.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		roundi(14.0 * s),
		COLOR_OBJECTIVE
	)


## What the player should be heading for: whatever they have engaged, otherwise
## the nearest island they have yet to take.
func _objective_position() -> Vector2:
	if fleet == null or not is_instance_valid(fleet):
		return Vector2.INF

	var lead: Ship = fleet.selected
	if lead != null and is_instance_valid(lead):
		if lead.target != null and is_instance_valid(lead.target):
			return lead.target.global_position

	if archipelago == null or not is_instance_valid(archipelago):
		return Vector2.INF

	var from: Vector2 = fleet.centroid()
	var best: Vector2 = Vector2.INF
	var best_distance: float = INF
	for raw: Variant in archipelago.islands:
		if not is_instance_valid(raw):
			continue
		var island: Island = raw
		if island.is_captured:
			continue
		var distance: float = island.distance_to_coast(from)
		if distance < best_distance:
			best_distance = distance
			best = island.global_position
	return best


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


## One bar per shore battery, on the same "damage is information" rule as ships:
## an untouched fort shows nothing, a fort you have been working on shows how much
## is left. Without it there is no way to tell a battery two hits from silence from
## one you have barely scratched, and forts are what gate an island's capture.
func _draw_structures(s: float) -> void:
	for node: Node2D in Grid.query_rect(Cull.get_cull_rect(), SpatialGrid.KIND_STRUCTURE):
		var fort := node as Fort
		if fort == null or not fort.alive or fort.health_fraction() >= 0.999:
			continue

		var width: float = BAR_WIDTH * s
		var height: float = BAR_HEIGHT * s
		var rect := Rect2(
			fort.global_position + Vector2(-width * 0.5, -(Fort.HIT_RADIUS + BAR_MARGIN * s)),
			Vector2(width, height)
		)
		draw_rect(rect, COLOR_BAR_BG, true)
		draw_rect(
			Rect2(rect.position, Vector2(width * fort.health_fraction(), height)),
			COLOR_HULL,
			true
		)


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
	# Wave 1's authored selection frames are perspective ellipses. Rotating those
	# in a strict top-down game reads as a wobble, so selection remains a clean
	# circular vector ring whose stroke stays constant on screen.
	var radius: float = ship.stats.hull_radius * 1.5
	draw_arc(ship.global_position, radius, 0.0, TAU, 32, COLOR_SELECT, 3.0 * s, false)


func _draw_course(ship: Ship, s: float) -> void:
	_draw_dashed(ship.global_position, ship.nav_target, COLOR_COURSE, 2.0 * s, 22.0 * s)

	var p: Vector2 = ship.nav_target
	var size: Vector2 = Vector2.ONE * 64.0 * s
	# The authored pivot is at (32, 55) in nominal pixels: the pin's point, not
	# the centre of its square texture, lands on the actual navigable destination.
	var pivot: Vector2 = Vector2(32.0, 55.0) * s
	draw_texture_rect(
		_animated_frame(WAYPOINT_FRAMES, 8.0), Rect2(p - pivot, size), false
	)


func _draw_reticle(at: Vector2, s: float) -> void:
	var size: Vector2 = Vector2.ONE * 80.0 * s
	draw_texture_rect(
		_animated_frame(RETICLE_FRAMES, 8.0), Rect2(at - size * 0.5, size), false
	)


func _animated_frame(frames: Array[Texture2D], fps: float) -> Texture2D:
	var tick: int = floori(float(Time.get_ticks_msec()) * 0.001 * fps)
	return frames[tick % frames.size()]


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
