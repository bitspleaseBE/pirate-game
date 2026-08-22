class_name SailCanvas
extends Node2D
## The canvas on a yard, drawn rather than blitted.
##
## The first attempt at this rotated `sail_med.png` about the mast to brace the
## yards. It looked terrible, and the reason turned out to be a mistake in the
## art pipeline rather than in the code.
##
## `assets_src/ships/sloop/sail_med.svg` — the Wave 0 master — is a **plan view**:
## a bowed yard across the top, a canvas bellying away from it, and the mast as a
## small circle where the two meet. That is the correct thing to draw on a hull
## sprite that is orthographic from directly overhead, which every hull in this
## game is. The v2 raster master that replaced it, and which became the
## `sail_med.png` the project ships, is a **side elevation** — mast, yard, two
## hanging panels and the standing rigging, seen from abeam. Beautiful, and
## unusable here: laying it on a deck puts a mast lying flat along the planks,
## and turning it to brace the yard swings that mast round with it. Masts do not
## turn. Only the yard does.
##
## So the canvas is drawn, to the SVG's geometry and in the SVG's palette, which
## makes this a moving version of the art that was authored for the job rather
## than an invention. That is the same call [Fort], [Shipyard] and [CastleKeep]
## all make, and it buys more here than it does for a building, because a drawn
## sail can do what no single sprite can:
##
##   * **belly to leeward**, and flip that belly to the other side when the ship
##     tacks, which is the one thing that makes a sail look like it is holding
##     wind rather than pinned to a mast;
##   * **deepen as it fills** and go slack and pale when it is luffing;
##   * **shrink and tear** as the rigging is shot away, instead of just fading.
##
## Six draw calls per hull, on a ship that already carries a hull sprite, a
## shadow, bow foam and a wake ribbon, and only when something about the trim has
## actually moved — see [method set_trim]. It is parented under the ship's
## `Visual` node, so it heaves and rolls on the swell with everything else.

## Points along each edge. Eight is enough for a curve this size to read as a
## curve; more is just triangles nobody can see.
const SEGMENTS: int = 8

## How much of the belly is there at all times versus earned by filling. Cloth
## with no wind in it still hangs in a curve — it is canvas, not board.
const SLACK_BELLY: float = 0.40

## The foot is narrower than the head, which is what gives a square sail its
## trapezoid. Straight from the master: head spans 80 units, foot 58.
const FOOT_RATIO: float = 0.82

## The yard bows to windward over its length, again from the master (11 units of
## sag over a 110-unit box). Small, but it is the difference between a spar and a
## ruled line.
const YARD_BOW: float = 0.08

## How far the yardarms stand out past the cloth, as a fraction of half-span.
##
## Also from the master, where the spar runs 12..98 and the canvas only 15..95.
## It matters more than three units of drawing suggests: with the yard cropped to
## the canvas, the sail's two curved edges meet at a point and the whole thing
## reads as a leaf lying on the deck. The bare yardarms are what make it a spar
## with cloth on it.
const YARDARM_OVERHANG: float = 0.13

## Palette, lifted from `sail_med.svg` so the drawn sail and the authored art
## agree if the master is ever rendered again.
const COLOR_CANVAS: Color = Color("f3e3b5")
const COLOR_HIGHLIGHT: Color = Color("fff2cf")
const COLOR_SEAM: Color = Color("d8c487")
const COLOR_OUTLINE: Color = Color("082638")
const COLOR_MAST: Color = Color("a65e2e")

## Canvas is never quite opaque. Which way a hull is pointing is how the player
## reads a broadside arc, so the deck has to stay legible under the rig.
const BASE_ALPHA: float = 0.93

## Fixed jitter, so a torn sail is ragged in a consistent way rather than
## shimmering into a different set of holes every frame. Nine entries against
## nine foot points, deliberately coprime with nothing — it just has to not be
## periodic across the span.
const TATTER: PackedFloat32Array = [
	0.00, 0.62, 0.18, 0.91, 0.35, 0.74, 0.08, 0.55, 0.27,
]

## Below this much difference in any driver, the shape would not visibly change,
## so the redraw is skipped. A fleet sitting at anchor costs nothing.
const REDRAW_EPSILON: float = 0.004

## Yard angle in radians, 0 being square across the beam.
var yard_angle: float = 0.0
## Which side the canvas bellies toward: +1 or -1.
var lee_sign: float = 1.0
## How hard the sail is drawing, 0 (slatting) to 1 (full).
var fill: float = 1.0
## Rigging left, 0 to 1. Drives the size of the canvas and how ragged it is.
var canvas: float = 1.0
## Half the yard's length, and how far the foot hangs from it, in world units.
var half_span: float = 40.0
var depth: float = 34.0


## Sets the trim and redraws only if it moved.
##
## Called every frame by [method Ship._trim_sail] for every hull in the fight,
## which is why it filters rather than redrawing unconditionally: bracing eases
## over about a second, so a ship holding a course is trimmed and static for far
## longer than it is turning.
func set_trim(p_yard: float, p_lee: float, p_fill: float, p_canvas: float) -> void:
	var moved: bool = (
		absf(p_yard - yard_angle) > REDRAW_EPSILON
		or absf(p_fill - fill) > REDRAW_EPSILON
		or absf(p_canvas - canvas) > REDRAW_EPSILON
		or not is_equal_approx(p_lee, lee_sign)
	)
	yard_angle = p_yard
	lee_sign = p_lee
	fill = p_fill
	canvas = p_canvas
	if moved:
		queue_redraw()


func set_rig_size(p_half_span: float, p_depth: float) -> void:
	if is_equal_approx(p_half_span, half_span) and is_equal_approx(p_depth, depth):
		return
	half_span = p_half_span
	depth = p_depth
	queue_redraw()


func _draw() -> void:
	if canvas <= 0.001:
		return

	var yard: Vector2 = Vector2.RIGHT.rotated(yard_angle)
	var lee: Vector2 = yard.orthogonal() * signf(lee_sign)
	var drawing: float = clampf(fill, 0.0, 1.0)
	var left: float = clampf(canvas, 0.0, 1.0)

	# The yard shortens as the sail is shot away — reefed by gunfire rather than
	# by choice — so a battered ship is visibly carrying less canvas before any
	# bar says so.
	var span: float = half_span * lerpf(0.70, 1.0, left)
	var hang: float = depth * lerpf(0.52, 1.0, left)
	var belly: float = hang * (SLACK_BELLY + (1.0 - SLACK_BELLY) * drawing)
	var alpha: float = BASE_ALPHA * left

	var head: PackedVector2Array = _head_curve(yard, lee, span)
	var foot: PackedVector2Array = _foot_curve(yard, lee, span, belly, left)

	# Head down one edge, foot back up the other, which is the winding
	# `draw_colored_polygon` wants and also the order the seams read in.
	var shape := PackedVector2Array(head)
	for i: int in range(foot.size() - 1, -1, -1):
		shape.append(foot[i])

	# A luffing sail is flatter *and* paler, because it is edge-on to the light
	# as much as anything. Both cues point the same way, which is what makes the
	# state readable at a glance rather than something to squint at.
	var lit: float = lerpf(0.74, 1.0, drawing)
	draw_colored_polygon(shape, Color(COLOR_CANVAS * lit, alpha))

	# The lit band along the head, straight out of the master. It is what stops
	# the sail reading as a flat cut-out at gameplay zoom.
	_draw_highlight(head, foot, alpha * 0.8 * drawing)

	# Cloth is sewn in strips. Three seams running head to foot are enough to say
	# so, and they curve with the belly, which sells the bulge better than the
	# silhouette alone does.
	for t: float in [-0.5, 0.0, 0.5]:
		var a: Vector2 = _point_on(head, t)
		var b: Vector2 = _point_on(foot, t)
		draw_line(a, b, Color(COLOR_SEAM, alpha * 0.7), 1.5, true)

	# Outline last so nothing paints over it. The art bible puts a dark navy line
	# round everything; without it the cream sits on the pale sea and vanishes.
	var outline := PackedVector2Array(shape)
	outline.append(shape[0])
	draw_polyline(outline, Color(COLOR_OUTLINE, alpha * 0.85), 1.6, true)

	# The yard, over the head of the sail and standing out past it at both ends,
	# and the mast where they cross. The mast is the one part of a rig that is
	# honestly a dot from overhead.
	draw_polyline(
		_head_curve(yard, lee, span * (1.0 + YARDARM_OVERHANG)),
		Color(COLOR_OUTLINE, alpha),
		maxf(2.0, span * 0.09),
		true
	)
	var mast: float = maxf(2.0, half_span * 0.11)
	draw_circle(Vector2.ZERO, mast, Color(COLOR_MAST, alpha))
	draw_arc(Vector2.ZERO, mast, 0.0, TAU, 12, Color(COLOR_OUTLINE, alpha), 1.5, true)


## The head of the sail: along the yard, bowed a little to windward.
func _head_curve(yard: Vector2, lee: Vector2, span: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i: int in SEGMENTS + 1:
		var t: float = lerpf(-1.0, 1.0, float(i) / float(SEGMENTS))
		var bow: float = YARD_BOW * span * (1.0 - t * t)
		points.append(yard * (t * span) - lee * bow)
	return points


## The foot: narrower, and bulging to leeward. The bulge is fullest amidships and
## pinned at the clews, which is what a filled sail does and what makes the shape
## read as cloth under pressure rather than a curved plate.
func _foot_curve(
	yard: Vector2, lee: Vector2, span: float, belly: float, left: float
) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i: int in SEGMENTS + 1:
		var t: float = lerpf(-1.0, 1.0, float(i) / float(SEGMENTS))
		var bulge: float = belly * (1.0 - t * t * 0.55)
		if left < 0.999:
			# Ragged along the foot, worse the less rigging is left. Tearing eats
			# into the sail, so the tatter subtracts from the bulge — a shot-up
			# sail has holes in its belly, not a fringe hanging off it.
			bulge *= 1.0 - TATTER[i % TATTER.size()] * (1.0 - left) * 0.8
		points.append(yard * (t * span * FOOT_RATIO) + lee * bulge)
	return points


## The bleached panel across the top third, between the head and a shallow line
## traced back toward it from the belly.
func _draw_highlight(
	head: PackedVector2Array, foot: PackedVector2Array, alpha: float
) -> void:
	if alpha <= 0.01:
		return
	var band := PackedVector2Array()
	for i: int in head.size():
		band.append(head[i].lerp(foot[i], 0.08))
	for i: int in range(head.size() - 1, -1, -1):
		# Deeper amidships than at the yardarms, following the belly.
		var t: float = lerpf(-1.0, 1.0, float(i) / float(SEGMENTS))
		var reach: float = 0.34 * (1.0 - t * t * 0.6)
		band.append(head[i].lerp(foot[i], reach))
	draw_colored_polygon(band, Color(COLOR_HIGHLIGHT, alpha))


## Samples a curve at `t` in -1..1, the same parameter the curves were built on.
func _point_on(curve: PackedVector2Array, t: float) -> Vector2:
	var f: float = (clampf(t, -1.0, 1.0) + 1.0) * 0.5 * float(SEGMENTS)
	var i: int = clampi(int(f), 0, SEGMENTS - 1)
	return curve[i].lerp(curve[i + 1], f - float(i))
