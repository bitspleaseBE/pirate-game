class_name WindIndicator
extends Control
## Compass arrow showing where the wind blows and how well the selected ship is
## using it.
##
## Two pieces of information, deliberately: the arrow is the wind (a world fact),
## the coloured ring is *your* speed on this heading (a consequence). Showing only
## the wind would leave the player doing trigonometry; showing only the speed
## would leave them unable to plan a turn.
##
## Hidden entirely until the wind is up, so the opening islands are not cluttered
## with a widget that does nothing.

## Cinzel, matching the HUD's other short all-caps tags.
const FONT: String = "res://assets/fonts/Cinzel.ttf"
const CARDINAL_SIZE: int = 13
const CARDINAL_COLOR: Color = Color(0.82, 0.87, 0.91, 0.62)

## Screen-space compass points. -Y is north, which is the convention
## [method WindSystem._compass_name] already reports against, so a wind it calls
## "NE" has its arrow pointing down-left past the N and E marks.
const CARDINALS: Array[Array] = [
	["N", Vector2(0, -1)],
	["E", Vector2(1, 0)],
	["S", Vector2(0, 1)],
	["W", Vector2(-1, 0)],
]

const ARROW_COLOR: Color = Color("cfe6f2")
const DIAL_COLOR: Color = Color(1, 1, 1, 0.22)
const GOOD_COLOR: Color = Color("7fc98a")
const POOR_COLOR: Color = Color("d98b5a")
const BAD_COLOR: Color = Color("c25b4e")

var fleet: FleetController = null

var _font: Font = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	if ResourceLoader.exists(FONT):
		_font = load(FONT)


func _process(_delta: float) -> void:
	var wind: WindSystem = WindSystem.instance
	visible = wind != null and wind.active
	if visible:
		queue_redraw()


func _draw() -> void:
	var wind: WindSystem = WindSystem.instance
	if wind == null or not wind.active:
		return

	var centre: Vector2 = size * 0.5
	# Pulled in from 0.42 to leave room for the cardinal letters inside the
	# control's own rect — at 0.42 the N and S marks clipped against the panel edge.
	var radius: float = minf(size.x, size.y) * 0.36

	draw_arc(centre, radius, 0.0, TAU, 28, DIAL_COLOR, 2.0, true)
	_draw_cardinals(centre, radius)

	# The performance ring: how much of your top speed this heading is earning.
	var ship: Ship = fleet.selected if fleet != null and is_instance_valid(fleet) else null
	if ship != null and is_instance_valid(ship) and not ship.stats.is_oared():
		var efficiency: float = wind.speed_multiplier(ship.forward(), ship.stats.rig_tilt())
		var tint: Color = BAD_COLOR
		if efficiency > 0.85:
			tint = GOOD_COLOR
		elif efficiency > 0.6:
			tint = POOR_COLOR
		draw_arc(
			centre, radius - 4.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(efficiency, 0.0, 1.0),
			24, tint, 3.0, true
		)

	# The arrow points the way the wind pushes, which is the way a ship running
	# before it would travel — the reading a player actually wants.
	var dir: Vector2 = wind.direction
	var tip: Vector2 = centre + dir * radius * 0.82
	var tail: Vector2 = centre - dir * radius * 0.6
	var side: Vector2 = dir.orthogonal() * radius * 0.28

	draw_line(tail, tip, ARROW_COLOR, 3.0)
	draw_colored_polygon(
		PackedVector2Array([tip + dir * radius * 0.2, tip - dir * 0.05 + side, tip - dir * 0.05 - side]),
		ARROW_COLOR
	)


## N/E/S/W around the dial.
##
## Without them this widget is a ring and a line: it says the wind has *a*
## direction but gives the player nothing to name it with, no way to relate it to
## where they are sailing, and nothing to match against the "wind is up: NW" the
## game tells them when it arrives. Four glyphs turn a decoration into an
## instrument, which matters for the one mechanic in the game that is a permanent
## map-wide tactical axis.
func _draw_cardinals(centre: Vector2, radius: float) -> void:
	if _font == null:
		return
	for entry: Array in CARDINALS:
		var label: String = entry[0]
		var direction: Vector2 = entry[1]
		var extent: Vector2 = _font.get_string_size(
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, CARDINAL_SIZE
		)
		# draw_string anchors on the text baseline, so centre horizontally by half the
		# width and vertically by roughly a third of the cap height.
		var at: Vector2 = (
			centre
			+ direction * (radius + CARDINAL_SIZE * 0.62)
			- Vector2(extent.x * 0.5, -extent.y * 0.32)
		)
		draw_string(
			_font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, CARDINAL_SIZE, CARDINAL_COLOR
		)
