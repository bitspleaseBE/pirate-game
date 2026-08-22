class_name SailCanvas
extends Node2D
## The canvas on a yard: drawn as a shape, surfaced with real cloth.
##
## ## Why it is drawn at all
##
## The first attempt rotated `sail_med.png` about the mast to brace the yards. It
## looked terrible, and the reason turned out to be a mistake in the art pipeline
## rather than in the code.
##
## `assets_src/ships/sloop/sail_med.svg` — the Wave 0 master — is a **plan view**:
## a bowed yard across the top, a canvas bellying away from it, and the mast as a
## small circle where the two meet. That is the right thing to draw on a hull
## sprite that is orthographic from directly overhead, which every hull here is.
## The v2 raster master that replaced it, and which became the `sail_med.png` the
## project ships, is a **side elevation** — mast, yard, two hanging panels and the
## standing rigging, seen from abeam. Beautiful, and unusable: laid on a deck it
## puts a mast flat along the planks, and turning it to brace the yard swings the
## mast round with it. Masts do not turn. Only the yard does.
##
## ## Why drawing it was not enough
##
## The version after that drew the plan view as flat vector shapes — cream fill,
## hard navy outline — and it still looked wrong, for a reason no amount of
## reshaping would have fixed. The hulls in this game are rendered assets: weave,
## grain, weathering, soft shadow. A flat polygon with a stroke around it is a
## different medium, and putting the two on one ship reads as a placeholder
## sitting on finished art. The problem was never the *shape*. It was the
## *material*.
##
## So the shape stays procedural and the surface comes from the elevation master
## after all — `tools/assets/make_sail_linen.py` lifts a clean patch of its canvas
## out, away from the mast and the rigging, and this stretches that over the
## polygon. Cloth looks like cloth from any angle, so the one part of that master
## that was never projection-dependent is the part worth keeping. The sail is lit
## per-vertex over the top, and lays a shadow on the deck in the same direction
## the hull lays its own, which is what actually seats it on the ship.
##
## ## What the shape buys
##
## Everything a single sprite cannot do, and all of it is gameplay information:
##
##   * **belly to leeward**, and carry that belly across when the ship tacks,
##     which is the one thing that makes a sail look like it is holding wind
##     rather than pinned to a mast;
##   * **deepen and brighten as it fills**, going slack and flat when it luffs;
##   * **shrink and tear** as the rigging is shot away, instead of just fading.
##
## Five draw calls per hull, and only when the trim has actually moved — see
## [method set_trim]. It is parented under the ship's `Visual` node, so it heaves
## and rolls on the swell with everything else.

## The cloth. See `tools/assets/make_sail_linen.py` for where it comes from and
## why it is a crop rather than a master of its own.
const LINEN: Texture2D = preload("res://assets/wave1/ships/sail_linen.png")

## Points along each edge. Eight is enough for a curve this size to read as a
## curve; more is just triangles nobody can see.
const SEGMENTS: int = 8

## How much of the belly is there at all times versus earned by filling. Cloth
## with no wind in it still hangs in a curve — it is canvas, not board.
const SLACK_BELLY: float = 0.40

## The foot is narrower than the head, which is what gives a square sail its
## trapezoid. Straight from the vector master: head spans 80 units, foot 58.
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

## Spars are wood, like everything else on the deck. The vector master strokes
## them in the art bible's dark navy, which is correct for a flat illustration and
## wrong against a photographed plank.
const COLOR_YARD: Color = Color("4a3626")
const COLOR_YARD_LIT: Color = Color("7a5c3e")
const COLOR_MAST: Color = Color("6b4b2c")

## Brightness applied to the linen at the head and at the foot. The head is close
## to the yard and catches the light; the foot is the deepest part of the belly
## and falls away from it.
##
## The first pass at these ran 1.06 down to 0.62 and made a sail that looked like
## it was permanently in someone else's shadow — grey against a deck that is warm
## brown. The swatch already carries a good deal of its own fold contrast, so the
## renderer only needs to say which end is nearer the sun, not relight the cloth
## from scratch.
##
## They then went up again, because the deck is warm brown and cloth at the same
## value simply merges into it. Canvas in sun really is much lighter than wet
## planks, and the sail has to be the lightest thing on the ship or the shape
## stops reading at gameplay zoom.
const SHADE_HEAD: float = 1.30
const SHADE_FOOT: float = 0.96
## And the yardarms sit in the shade of their own curl, so the middle of the sail
## is the brightest part of it.
const SHADE_EDGE: float = 0.94
## Warmth, so the shading tints toward sun on cloth rather than washing the
## swatch out to neutral grey on its way down.
const SHADE_WARM: Color = Color(1.04, 0.99, 0.90)

## How far the whole sail dims when it stops drawing. A luffing sail is edge-on to
## the light as much as it is flat, so brightness and belly say the same thing and
## the state is readable without squinting.
const LUFF_DIM: float = 0.84

## Canvas is never quite opaque. Which way a hull is pointing is how the player
## reads a broadside arc, so the deck has to stay legible under the rig.
const BASE_ALPHA: float = 0.95

## The shadow the canvas throws on the deck, and how far it slides. Same direction
## as the hull's own drop shadow, at a fraction of the distance — the sail is
## metres above the planks, not tens of them.
const SHADOW_TINT: Color = Color(0.06, 0.05, 0.04, 0.34)
const SHADOW_SLIDE: float = 0.42

## Fixed jitter, so a torn sail is ragged in a consistent way rather than
## shimmering into a different set of holes every frame.
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
## Where the deck shadow falls, in the hull's own frame. Set from the ship so the
## rig and the hull agree about where the sun is.
var shadow_offset: Vector2 = Vector2(8.0, 12.0)


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

	# Head along one edge, foot back along the other, which is the winding the
	# triangulator wants and also the order the UVs and the shading run in.
	var shape := PackedVector2Array(head)
	for i: int in range(foot.size() - 1, -1, -1):
		shape.append(foot[i])

	# On the deck first. This is the single thing that stopped the sail looking
	# pasted on: without it the canvas floats, and no amount of shading on the
	# cloth itself substitutes for the ship casting it.
	var slid := PackedVector2Array()
	for point: Vector2 in shape:
		slid.append(point + shadow_offset * SHADOW_SLIDE)
	draw_colored_polygon(slid, Color(SHADOW_TINT, SHADOW_TINT.a * left))

	# Then the cloth, stretched once across the shape rather than tiled: the
	# swatch already carries folds running the way a sail's do, and repeating it
	# would put a seam down the middle of the belly.
	var lit: float = lerpf(LUFF_DIM, 1.0, drawing) * alpha
	draw_polygon(shape, _shading(lit, alpha), _uvs(), LINEN)

	# A soft line along the foot. The cloth and the deck are both warm mid-tones,
	# so without it the trailing edge of the sail dissolves into the planks — but
	# it has to stay soft, because a hard stroke is what made the flat version
	# read as vector art on top of a photograph.
	draw_polyline(foot, Color(0.16, 0.12, 0.09, alpha * 0.38), 1.4, true)

	# The yard, over the head of the sail and standing out past it at both ends.
	# Two strokes: the spar, and a thinner lit edge along the side the sun is on,
	# which is what keeps it from reading as a drawn line.
	var arm: PackedVector2Array = _head_curve(yard, lee, span * (1.0 + YARDARM_OVERHANG))
	var thickness: float = maxf(2.0, span * 0.085)
	draw_polyline(arm, Color(COLOR_YARD, alpha), thickness, true)
	var edge := PackedVector2Array()
	for point: Vector2 in arm:
		edge.append(point - lee * thickness * 0.28)
	draw_polyline(edge, Color(COLOR_YARD_LIT, alpha * 0.7), thickness * 0.34, true)

	# And the mast, which is the one part of a rig that is honestly a dot from
	# directly overhead.
	var mast: float = maxf(2.0, half_span * 0.10)
	draw_circle(Vector2.ZERO, mast, Color(COLOR_MAST, alpha))
	draw_circle(Vector2.ZERO, mast * 0.55, Color(COLOR_YARD, alpha))


## Per-vertex brightness: bright along the head, falling away into the belly, and
## dimmer at the yardarms than amidships.
##
## Per-vertex rather than one flat modulate because a single colour over a
## stretched texture is exactly the flat cut-out this was trying to stop being.
func _shading(lit: float, alpha: float) -> PackedColorArray:
	var colors := PackedColorArray()
	for pass_index: int in 2:
		for i: int in SEGMENTS + 1:
			# Foot points were appended in reverse, so walk them that way too.
			var index: int = i if pass_index == 0 else SEGMENTS - i
			var t: float = lerpf(-1.0, 1.0, float(index) / float(SEGMENTS))
			var along: float = lerpf(SHADE_EDGE, 1.0, 1.0 - t * t)
			var across: float = SHADE_HEAD if pass_index == 0 else SHADE_FOOT
			var k: float = lit * along * across
			colors.append(
				Color(k * SHADE_WARM.r, k * SHADE_WARM.g, k * SHADE_WARM.b, alpha)
			)
	return colors


## Texture coordinates, normalised. `u` runs across the sail with the yard and
## `v` from head to foot, so the swatch's folds hang the way a sail's do whatever
## angle the yard is braced to.
func _uvs() -> PackedVector2Array:
	var uvs := PackedVector2Array()
	for pass_index: int in 2:
		for i: int in SEGMENTS + 1:
			var index: int = i if pass_index == 0 else SEGMENTS - i
			var u: float = float(index) / float(SEGMENTS)
			uvs.append(Vector2(u, 0.0 if pass_index == 0 else 1.0))
	return uvs


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
