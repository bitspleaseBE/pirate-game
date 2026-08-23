class_name Ensign
extends Node2D
## The flag at a ship's stern, drawn in plan view.
##
## ## Why there is one again
##
## There was a pennant here once and it was deliberately removed — the Wave 0
## `flag_wave` frames are a **side elevation**, a flag on a staff seen from
## abeam, and laid on a deck viewed from directly overhead they render as a flat
## red disc sitting on the planks. That removal was correct, and it stays
## correct: nothing here loads that texture.
##
## What has changed is the *reason to have a flag at all*. It used to be a wind
## read-out, and the sail ([SailCanvas]) does that job properly now. It is now
## the answer to a question the player asks from a thousand units away and has no
## other way to answer: **whose ship is that**. Since [Faction] arrived, the same
## Sloop hull can be a slow, thick-timbered Crown Navy gun platform or a Brethren
## raider that reloads a fifth faster and hits a fifth harder, and the player has
## to decide whether to engage before they are close enough to count gunports.
## Two colours on a scrap of cloth is the cheapest possible way to say it.
##
## ## Why it is drawn rather than sprited
##
## Five factions times "streaming in whatever direction the wind is going" is not
## a sprite sheet, it is a sprite sheet per faction per heading. Drawn, it is one
## polygon, two colours pulled off the faction, and a wave — and it comes with
## the same thing the sail got for free: the flag actually points downwind, so on
## a still sea (an oared hull, before the wind is up) it hangs limp astern and on
## a blow it stands straight out. That is a second, redundant wind read-out at no
## cost, which matters because the pennant was the first one and players had got
## used to looking for it.
##
## ## Cost
##
## Two polygons and a line per ship, redrawn at [constant WAVE_HZ] rather than
## per frame, and not at all when the hull is culled — see
## [method set_showing]. A flag is a detail; it must never be a frame budget.

## The flag's length along the fly, as a fraction of the hull's radius, and how
## wide the ribbon of cloth is as a fraction of that length.
##
## The width is **not** the flag's hoist. Seen from directly overhead a flag
## streaming downwind is edge-on — its height is the axis pointing at the camera,
## and a literal plan view of one is a line. What is actually visible from up
## there is the snake: cloth in a breeze curls left and right along its length,
## and that lateral travel is the only part of a flag with any extent in this
## projection. So the ribbon is deliberately narrow, and most of what reads as its
## width comes from [constant SNAKE_RATIO] below.
##
## The same reasoning is what killed the sprite pennant: `flag_wave.png` is a side
## elevation, and there is no rotation of it that is a plan view of a flag.
const LENGTH_RATIO: float = 1.34
const HEIGHT_RATIO: float = 0.22

## How far aft of the hull's centre the staff is stepped, as a fraction of hull
## radius. Right on the taffrail, so the cloth starts clear of the deck rather
## than lying across it — at this size a flag drawn over planking is planking.
const STAFF_AFT_RATIO: float = 0.95

## Points along the fly. Enough that the snake reads as a curve rather than as a
## dog-leg; more is triangles nobody can see at a size where the whole flag is
## thirty pixels.
const SEGMENTS: int = 8

## The hoist band — the faction's second colour — as a fraction of the fly.
##
## A quarter. Enough to register as a colour at this size, and no more: at a
## third it stopped reading as a band on a flag and started reading as a white
## square with a red flag next to it. A canton or an actual charge is not an
## option — anything with internal detail turns to mud at thirty pixels.
const CHARGE_RATIO: float = 0.26

## The swallow tail, as a fraction of the height. A notch in the fly is what
## makes a twenty-pixel rectangle read as a *flag* rather than as a smear.
const TAIL_NOTCH: float = 0.55

## Redraws per second of the ripple. The flag is decoration; it does not need
## sixty.
const WAVE_HZ: float = 14.0
## Ripples per flag length, how far the cloth throws sideways as a fraction of
## its length, and how fast the ripple travels down it.
##
## The throw grows along the fly, because a flag is pinned at the hoist and free
## at the end — a ripple of constant amplitude reads as a wobbling stick.
const WAVE_CYCLES: float = 1.25
const SNAKE_RATIO: float = 0.26
const WAVE_SPEED: float = 5.4

## The twist: how narrow the ribbon gets where the cloth turns edge-on, how many
## turns there are along the fly, and how fast they travel. Slower and longer
## than the snake, so the two never beat against each other into a pattern.
const TWIST_MIN: float = 0.34
const TWIST_CYCLES: float = 0.7
const TWIST_RATE: float = 0.65

## How much of the fly a dead calm still gets. Cloth hangs; it does not vanish.
const LIMP_FRACTION: float = 0.42
## How quickly the flag settles onto a new wind. Cloth has some mass and a lot of
## drag, so this is fast but not instant — snapping to a new bearing in one frame
## is the single thing that reads most obviously as a shader rather than a flag.
const SETTLE_RATE: float = 6.0

## Darkens the underside of the cloth, so the ripple has a lit side and a shaded
## one rather than being a flat shape that changes outline. Same low sun the
## ocean and the land use, resolved to the one number that survives at this size:
## the far edge is darker than the near one.
const SHADE_FAR: float = 0.74
## A thin dark edge. Two mid-tone colours on open water need an outline or the
## flag dissolves into the wave field at any distance — this is the same trick
## the HUD cards use, for the same reason.
const EDGE_COLOR: Color = Color(0.05, 0.06, 0.09, 0.55)
const EDGE_WIDTH: float = 1.2

## The flag's own shadow, thrown the same way the hull and the sail throw theirs.
##
## Without it the pennant is a bright shape pasted on top of a lit ship, which is
## exactly what the first version looked like — the shape and the colours were
## right and it still read as a decal. A shadow is what says a thing is above the
## surface it is drawn over. Offset is set by [Ship] from its own, so if the sun
## moves all three move together.
const SHADOW_TINT: Color = Color(0.05, 0.05, 0.06, 0.30)
var shadow_offset: Vector2 = Vector2.ZERO

## The two colours, from the ship's [Faction].
var field: Color = Color("6b6b6b")
var charge: Color = Color("cfcfcf")

## Flag geometry, set by [method set_hull_size].
var _length: float = 24.0
var _height: float = 11.0

## The direction the cloth is streaming, in this node's parent space, and how
## hard. Eased toward the wind rather than snapped to it.
var _fly: Vector2 = Vector2.DOWN
var _stretch: float = LIMP_FRACTION

var _phase: float = 0.0
var _redraw_accum: float = 0.0
var _showing: bool = true


func _ready() -> void:
	# The ripple must not run in lockstep across a whole garrison — a wave of
	# identical flags beating together is the giveaway that they are one program.
	_phase = randf() * TAU


## Cuts the flag to the hull it is flying on, and steps the staff at the stern.
## Called once, at build time.
func set_hull_size(hull_radius: float) -> void:
	_length = hull_radius * LENGTH_RATIO
	_height = _length * HEIGHT_RATIO
	position = Vector2(0.0, hull_radius * STAFF_AFT_RATIO)
	queue_redraw()


func set_colours(a: Color, b: Color) -> void:
	field = a
	charge = b
	queue_redraw()


## Culling hook. A flag off screen, or on a hull drawn at reduced detail, costs
## nothing at all rather than costing less.
func set_showing(value: bool) -> void:
	if _showing == value:
		return
	_showing = value
	visible = value
	set_process(value)


func _process(delta: float) -> void:
	_track_wind(delta)

	_phase += delta * WAVE_SPEED
	_redraw_accum += delta
	if _redraw_accum < 1.0 / WAVE_HZ:
		return
	_redraw_accum = 0.0
	queue_redraw()


## Points the flag downwind and works out how hard it is being blown.
##
## In this node's *parent* space, which is the ship's `Visual` — so the flag
## keeps pointing the same way across the water while the hull turns underneath
## it, which is the whole of what makes it read as cloth in a breeze rather than
## as a decal on the transom.
##
## With no wind at all — an oared hull, or the opening islands before the player
## owns a sail — it falls back to hanging straight astern. A flag standing rigidly
## out to starboard on a dead calm sea is worse than no flag.
func _track_wind(delta: float) -> void:
	var target_fly: Vector2 = Vector2.DOWN
	var target_stretch: float = LIMP_FRACTION

	var wind: WindSystem = WindSystem.instance
	if wind != null and wind.active:
		# The parent carries the hull's rotation, so the world bearing has to be
		# brought back into local space before it means anything here.
		target_fly = wind.direction.rotated(-global_rotation + rotation)
		target_stretch = 1.0
	if target_fly.length_squared() < 0.0001:
		target_fly = Vector2.DOWN

	var blend: float = 1.0 - exp(-SETTLE_RATE * delta)
	_fly = _fly.lerp(target_fly.normalized(), blend).normalized()
	_stretch = lerpf(_stretch, target_stretch, blend)


func _draw() -> void:
	var fly: Vector2 = _fly * (_length * _stretch)
	var across: Vector2 = _fly.orthogonal()

	# Two edges of the same piece of cloth. They share one snake and one twist —
	# see [method _edge] for why they must, and what it cost to find out.
	var near: PackedVector2Array = _edge(fly, across, -0.5)
	var far: PackedVector2Array = _edge(fly, across, 0.5)

	# One outline round the whole thing rather than round each band, so the seam
	# between the two colours stays a seam and not a drawn line. Built first
	# because the shadow is the same outline, moved.
	var outline := PackedVector2Array()
	outline.append_array(near)
	for i: int in range(far.size() - 1, -1, -1):
		outline.append(far[i])
	outline.append(near[0])

	if shadow_offset != Vector2.ZERO:
		var shadow := PackedVector2Array()
		shadow.resize(outline.size())
		for i: int in outline.size():
			shadow[i] = outline[i] + shadow_offset
		draw_colored_polygon(shadow, SHADOW_TINT)

	# Hoist band first, then the field: the two are cut from the same rippling
	# outline, so they share every interior vertex and cannot pull apart at the
	# seam the way two independently-waved quads would.
	var split: int = maxi(1, roundi(float(SEGMENTS) * CHARGE_RATIO))
	_draw_band(near, far, 0, split, charge)
	_draw_band(near, far, split, SEGMENTS, field)

	draw_polyline(outline, EDGE_COLOR, EDGE_WIDTH, true)


## One edge of the cloth, from hoist to fly. `side` is -0.5 for the near edge and
## +0.5 for the far one, in units of the ribbon's width; `across` is a unit
## vector.
##
## Both edges are cut from **one** snake and **one** twist, and that is load
## bearing. The obvious way to put a twist in a ribbon is to lag the far edge's
## ripple behind the near one, and it works right up until the lag pushes the two
## edges past each other — at which point that segment's quad is a bow tie,
## Godot's triangulator refuses it, and the flag flickers out of existence while
## the log fills with "Invalid polygon data". Which is exactly what the first
## version did.
##
## So the twist is expressed as the ribbon getting *narrower* instead. That is
## also what a twisting ribbon actually does in a projection like this one: turn
## a strip of cloth edge-on to the camera and what you see is a thinner strip,
## not a crossed one. The width can approach zero and never goes through it, so
## the geometry cannot invert however hard the flag is snapping.
func _edge(fly: Vector2, across: Vector2, side: float) -> PackedVector2Array:
	var snake: float = _length * SNAKE_RATIO * _stretch
	var out := PackedVector2Array()
	out.resize(SEGMENTS + 1)
	for i: int in SEGMENTS + 1:
		var t: float = float(i) / float(SEGMENTS)
		# The swallow tail: the very end of the flag is cut back toward the
		# centreline, and only on the last segment, so it is a notch rather than a
		# taper. Small, but it is what makes a short ribbon read as a flag.
		var span: float = side
		if i == SEGMENTS:
			span = lerpf(side, 0.0, TAIL_NOTCH)
		var wave: float = sin(_phase + t * TAU * WAVE_CYCLES) * snake * t
		# Never zero: a segment of literally no width is a degenerate polygon, and
		# the point of this whole function is not handing the triangulator one.
		var twist: float = lerpf(
			TWIST_MIN, 1.0, absf(cos(_phase * TWIST_RATE + t * TAU * TWIST_CYCLES))
		)
		out[i] = fly * t + across * (span * _height * twist + wave)
	return out


## Fills the strip of cloth between two edges, from segment `from` to `to`.
##
## Drawn as one quad per segment rather than as a single indexed polygon, because
## Godot fans an indexed `polygons` entry from its first vertex — per-quad shading
## then disagrees across the shared diagonal and the flag comes out as a row of
## triangular teeth. That was learned the hard way on the island beach band; it is
## the same bug and this is the same fix.
func _draw_band(
	near: PackedVector2Array, far: PackedVector2Array, from: int, to: int, colour: Color
) -> void:
	for i: int in range(from, to):
		var quad := PackedVector2Array([near[i], near[i + 1], far[i + 1], far[i]])
		# Shade by how far this stretch of cloth has rippled away from the sun
		# side. Cheap, and it is the difference between cloth and coloured paper.
		var tilt: float = (far[i] - near[i]).length() / maxf(_height, 0.001)
		var lit: float = lerpf(SHADE_FAR, 1.0, clampf(tilt, 0.0, 1.0))
		draw_colored_polygon(quad, Color(colour.r * lit, colour.g * lit, colour.b * lit))
