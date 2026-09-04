class_name Spike3DShip
extends RefCounted
## Builds an adventure ship out of arithmetic.
##
## Part of the 3D spike — see `spike/spike3d.gd`. Nothing in `src/` uses it yet.
##
## ## Why generated rather than modelled
##
## The game has ten hulls (Dinghy, Skiff, Cutter, War Canoe, War Raft, Sloop,
## Brig, Galleon, Fireship, Bomb Ketch) and five factions, and three of the things
## asked for are not properties a model file has:
##
##   * **a flag per faction**, which is a colour pair the ship does not know until
##     it is spawned;
##   * **loose planks**, which should appear as a hull is shot to pieces rather
##     than being painted on from the start;
##   * **a ragged sail**, which the 2D game already tears progressively as the
##     rigging goes — see [SailCanvas], which does exactly this in two dimensions.
##
## A bought model is a fixed object. Every one of those wants a hull that knows
## its own damage state, so the shape is a function and the damage is one of its
## arguments. It is also how the rest of this project already works: the sail, the
## ensign, the islands, the ocean and the forts are all generated.
##
## ## How the hull is built
##
## Lofted from transverse sections, the way a real one is drawn. A series of
## stations runs from stem to transom; each carries a cross-section from keel to
## rail; consecutive sections are stitched into quads. Three curves control the
## whole shape and they are the same three a naval architect would name:
##
##   * **beam** — how wide she is at each station: nothing at the stem, widest a
##     little forward of amidships, still broad at the transom;
##   * **sheer** — how high the rail sits: high at the bow to keep the sea out,
##     lowest amidships, rising again aft;
##   * **draft** — how deep she sits: shallow forward, deepest under the mainmast.
##
## They are written as keyframes rather than as formulas because that is what
## makes the shape arguable. A curve you can read down a column is one somebody
## can disagree with; `pow(sin(t * PI), 0.7)` is not.

## Stations from stem to transom, and points per half-section from keel to rail.
## Eighteen by nine is about 300 vertices a hull — nothing, and fine enough that
## the turn of the bilge reads as a curve.
const STATIONS: int = 18
const RING: int = 9

## Beam at each station as a fraction of maximum, from stem (0) to transom (1).
## The widest point is forward of amidships, which is what gives a sailing hull
## its cod's-head-and-mackerel-tail look rather than a symmetrical canoe.
const BEAM_CURVE: Array[Vector2] = [
	Vector2(0.00, 0.11), Vector2(0.08, 0.34), Vector2(0.18, 0.60),
	Vector2(0.30, 0.82), Vector2(0.42, 0.99), Vector2(0.55, 1.00),
	Vector2(0.70, 0.94), Vector2(0.85, 0.80), Vector2(1.00, 0.60),
]
## Rail height above the waterline, as a fraction of nominal freeboard. High
## forward to keep a head sea on the outside, and higher still aft where the
## captain's cabin goes.
const SHEER_CURVE: Array[Vector2] = [
	Vector2(0.00, 1.30), Vector2(0.15, 1.10), Vector2(0.40, 1.00),
	Vector2(0.65, 1.03), Vector2(0.85, 1.16), Vector2(1.00, 1.30),
]
## Depth below the waterline. A hull drags her deepest under the mainmast, where
## the load is.
const DRAFT_CURVE: Array[Vector2] = [
	Vector2(0.00, 0.35), Vector2(0.15, 0.72), Vector2(0.45, 1.00),
	Vector2(0.75, 0.95), Vector2(1.00, 0.78),
]

## How square the sections are. 1 is a wedge, higher is a fuller, boxier body
## that carries her beam further down toward the keel.
const SECTION_FULLNESS: float = 1.55
## How far the topsides tumble *in* above the waterline, as a fraction of beam.
## Real ships of this era did this — the widest point is at the waterline and the
## rail is drawn in above it — and it is most of why a wooden hull reads as
## wooden rather than as an extruded tub.
const TUMBLEHOME: float = 0.10

## Timber. Two tones a strake apart, so planking reads without a texture.
const PLANK_DARK: Color = Color(0.243, 0.157, 0.090)
const PLANK_LIGHT: Color = Color(0.365, 0.243, 0.145)
const WALE_COLOR: Color = Color(0.128, 0.086, 0.055)
const DECK_COLOR: Color = Color(0.482, 0.376, 0.243)
const CABIN_COLOR: Color = Color(0.298, 0.184, 0.106)
const TRIM_COLOR: Color = Color(0.545, 0.404, 0.157)
## Sailcloth, not paper. The first pass was near-white and blew out to a flat
## silhouette in sunlight — real canvas is oiled flax, closer to old bone, and it
## needs to sit below the foam on the water or the sea looks dirty by comparison.
const CANVAS_COLOR: Color = Color(0.706, 0.663, 0.573)

## Which strake carries the wale — the heavy rubbing band along the topsides. A
## real one is structural; here it is the single line that stops the side of the
## hull being one flat field of brown.
const WALE_RING: int = 6
## The strake the gunports are cut through, one above the wale.
const GUNPORT_RING: int = 7
## Fore and aft limits of the gun deck, as a fraction of the length. Nothing
## forward of the cathead and nothing through the transom.
const GUNPORT_FROM: float = 0.22
const GUNPORT_TO: float = 0.80

## Below the waterline a hull is not the colour of her topsides — she is payed
## with tallow and pitch against weed and worm. It is the single cheapest thing
## that stops a generated hull reading as one extruded lump of brown, because it
## puts a hard horizontal line exactly where the eye expects the waterline.
const ANTIFOUL: Color = Color(0.180, 0.196, 0.157)
const GUNPORT_COLOR: Color = Color(0.055, 0.043, 0.035)
const LANTERN_COLOR: Color = Color(1.0, 0.83, 0.45)

## A hull this long or longer steps two masts. Below it she is a single-master,
## which is the difference between the Sloop and the Brig in the game's roster.
const TWO_MAST_LENGTH: float = 170.0


## Builds one ship.
##
## `damage` runs 0 (sound) to 1 (a wreck still afloat) and is the argument a
## bought model could not take: it springs planks off the topsides and tears the
## foot of the sail. `flag_field` and `flag_charge` come straight from the
## faction.
static func build(
	length: float,
	beam: float,
	draft: float,
	freeboard: float,
	flag_field: Color,
	flag_charge: Color,
	damage: float = 0.0
) -> Node3D:
	var root := Node3D.new()
	root.name = "Ship"

	var timber := StandardMaterial3D.new()
	timber.vertex_color_use_as_albedo = true
	timber.roughness = 0.82
	timber.specular = 0.2

	var spar := StandardMaterial3D.new()
	spar.albedo_color = PLANK_DARK.lightened(0.12)
	spar.roughness = 0.9

	root.add_child(_hull(length, beam, draft, freeboard, timber, damage))
	root.add_child(_deck(length, beam, freeboard, timber))
	root.add_child(_cabin(length, beam, freeboard, timber))
	root.add_child(_fittings(length, beam, freeboard, timber, spar))
	root.add_child(_bowsprit(length, beam, draft, freeboard, spar))
	root.add_child(_rig(length, beam, draft, freeboard, spar, damage))
	root.add_child(_ensign(length, freeboard, flag_field, flag_charge))
	return root


## A point on the finished hull surface, in ship space.
##
## Shared, so anything bolted to the outside of her — gunports, the ends of the
## shrouds, the cathead — lands *on* the planking rather than near it. Guessing
## those positions from the same numbers a second time is how a shroud ends up
## hanging in mid-air a foot outboard of the rail, and it is invisible until you
## look from exactly the wrong angle.
static func hull_point(
	t: float, s: float, length: float, beam: float, draft: float, freeboard: float
) -> Vector3:
	var half_beam: float = beam * 0.5 * _curve(BEAM_CURVE, t)
	var depth: float = draft * _curve(DRAFT_CURVE, t)
	var rail: float = freeboard * _curve(SHEER_CURVE, t)
	var rake: float = 0.0
	if t < 0.12:
		rake = -(0.12 - t) * length * 0.40
	elif t > 0.9:
		rake = (t - 0.9) * length * 0.30
	var p: Vector3 = _section_point(s, half_beam, depth, rail)
	var lean: float = clampf(p.y / maxf(rail, 0.001), 0.0, 1.0)
	return Vector3(p.x, p.y, lerpf(-length * 0.5, length * 0.5, t) + rake * lean)


# --- Curves -----------------------------------------------------------------

## Piecewise-linear read of a keyframed curve. Deliberately not a spline: the
## point of writing these as a table is that the number in the table is the
## number the hull has, and a spline would quietly overshoot between them.
static func _curve(curve: Array[Vector2], t: float) -> float:
	if t <= curve[0].x:
		return curve[0].y
	for i: int in range(1, curve.size()):
		if t <= curve[i].x:
			var a: Vector2 = curve[i - 1]
			var b: Vector2 = curve[i]
			var span: float = maxf(b.x - a.x, 0.0001)
			return lerpf(a.y, b.y, (t - a.x) / span)
	return curve[curve.size() - 1].y


## Where in the half-section the waterline sits, as a fraction of the ring.
## Below it the hull is rounding out from the keel; above it, it is topside.
const WATERLINE_RING: float = 0.55


## One point on a transverse section.
##
## `s` runs -1 (port rail) through 0 (keel) to +1 (starboard rail); `half_beam`,
## `depth` and `rail` are that station's own numbers.
##
## Two arcs, not one, and that is the whole difference between a ship and a
## washing-up bowl. The first attempt ran a single curve from keel to rail and so
## reached its maximum beam *at the rail* — meaning the sides flared outward all
## the way up and there were no topsides at all. She rendered as a shallow open
## dish with a mast in it. A hull is widest at or just below her waterline and
## then goes up nearly vertically, and it is those few feet of near-vertical
## planking that carry the wale, the gunports and every bit of the silhouette
## that says the thing is a ship.
static func _section_point(s: float, half_beam: float, depth: float, rail: float) -> Vector3:
	var a: float = absf(s)
	if a <= WATERLINE_RING:
		# Keel to waterline: filling out fast off the keel, then flattening
		# through the turn of the bilge.
		var u: float = a / WATERLINE_RING
		return Vector3(
			signf(s) * half_beam * pow(sin(u * PI * 0.5), 1.0 / SECTION_FULLNESS),
			-depth * (1.0 - pow(u, 1.9)),
			0.0
		)
	# Waterline to rail: near vertical, drawing very slightly inboard as it rises.
	var v: float = (a - WATERLINE_RING) / (1.0 - WATERLINE_RING)
	return Vector3(
		signf(s) * half_beam * (1.0 - TUMBLEHOME * v * v),
		rail * v,
		0.0
	)


# --- Parts ------------------------------------------------------------------

static func _hull(
	length: float, beam: float, draft: float, freeboard: float,
	material: StandardMaterial3D, damage: float
) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rows: Array = []
	for i: int in STATIONS:
		var t: float = float(i) / float(STATIONS - 1)
		var row: Array[Vector3] = []
		for j: int in RING * 2 + 1:
			row.append(hull_point(
				t, float(j) / float(RING) - 1.0, length, beam, draft, freeboard
			))
		rows.append(row)

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EA1
	for i: int in STATIONS - 1:
		var a: Array = rows[i]
		var b: Array = rows[i + 1]
		for j: int in RING * 2:
			# Strakes alternate tone, and the wale is one heavy dark band. Two
			# colours a plank apart is all it takes for a lofted surface to read
			# as planked rather than as moulded.
			var strake: int = absi(j - RING)
			var t_station: float = float(i) / float(STATIONS - 1)
			var colour: Color = PLANK_LIGHT if strake % 2 == 0 else PLANK_DARK
			if strake == WALE_RING:
				colour = WALE_COLOR
			elif (
				strake == GUNPORT_RING + 1
				and t_station > GUNPORT_FROM and t_station < GUNPORT_TO
			):
				# The lintel over the ports. Without a lighter band above them the
				# holes have no edge and read as a stain on the planking.
				colour = TRIM_COLOR.darkened(0.30)
			# Weathering, so no two strakes are quite the same age.
			var wear: float = rng.randf_range(-0.035, 0.035)
			colour = Color(
				clampf(colour.r + wear, 0.0, 1.0),
				clampf(colour.g + wear, 0.0, 1.0),
				clampf(colour.b + wear, 0.0, 1.0)
			)

			var p0: Vector3 = a[j]
			var p1: Vector3 = a[j + 1]
			var p2: Vector3 = b[j + 1]
			var p3: Vector3 = b[j]

			# Everything under water is payed against weed and worm — and *under
			# water* means below y = 0, not below some strake number. Keying it to
			# the strake index put the boot-top wherever the planking happened to
			# be, so at the bow, where she is shallowest, the dark paint climbed
			# clear of the sea and left a black wedge above the waterline. The
			# waterline is a property of the water.
			if (p0.y + p1.y + p2.y + p3.y) * 0.25 < 0.0:
				colour = ANTIFOUL if strake % 2 == 0 else ANTIFOUL.darkened(0.10)

			# Gunports, cut straight into the planking rather than modelled on top
			# of it. A port is a hole in a strake, so the cheapest correct way to
			# have one is to recolour that strake's quad and push it inboard — it
			# is guaranteed to sit flush on a curved surface, which a separate box
			# laid against the topsides never quite is.
			if (
				strake == GUNPORT_RING
				and t_station > GUNPORT_FROM and t_station < GUNPORT_TO
				and i % 2 == 0
			):
				colour = GUNPORT_COLOR
				var inboard: float = beam * 0.045
				var shove := Vector3(-signf(p0.x) * inboard, 0.0, 0.0)
				p0 += shove
				p1 += shove
				p2 += shove
				p3 += shove

			# Damage springs planks off the topsides. Only above the waterline and
			# only outboard — a hull with its bottom hanging open would have sunk,
			# and this is a ship that is still fighting.
			if damage > 0.01 and strake > WALE_RING - 2:
				if rng.randf() < damage * 0.5:
					var kick: float = rng.randf_range(0.04, 0.16) * damage
					var out := Vector3(signf(p0.x) * beam * kick, beam * kick * 0.3, 0.0)
					p1 += out
					p2 += out
					colour = colour.darkened(0.25)

			# The port half is traversed in the opposite sense to the starboard
			# half, so its quads have to be wound the other way or they face into
			# the hull. This is why only one side of her was rendering, and it is a
			# horrible thing to spot by eye: the silhouette stays perfectly correct
			# and the missing side just reads as "the model is a bit flat".
			_quad(st, p0, p1, p2, p3, colour, j < RING)

	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "Hull"
	mesh.mesh = st.commit()
	mesh.material_override = material
	return mesh


## The deck, set a little below the rail so the topsides stand up as bulwarks.
static func _deck(
	length: float, beam: float, freeboard: float, material: StandardMaterial3D
) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i: int in STATIONS - 1:
		var t0: float = float(i) / float(STATIONS - 1)
		var t1: float = float(i + 1) / float(STATIONS - 1)
		var w0: float = beam * 0.5 * _curve(BEAM_CURVE, t0) * 0.84
		var w1: float = beam * 0.5 * _curve(BEAM_CURVE, t1) * 0.84
		var y0: float = freeboard * _curve(SHEER_CURVE, t0) * 0.55
		var y1: float = freeboard * _curve(SHEER_CURVE, t1) * 0.55
		var z0: float = lerpf(-length * 0.5, length * 0.5, t0)
		var z1: float = lerpf(-length * 0.5, length * 0.5, t1)
		# Deck planks run fore and aft, so the tone alternates across the beam.
		var colour: Color = DECK_COLOR.darkened(0.06) if i % 2 == 0 else DECK_COLOR
		_quad(st,
			Vector3(-w0, y0, z0), Vector3(w0, y0, z0),
			Vector3(w1, y1, z1), Vector3(-w1, y1, z1), colour)

	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "Deck"
	mesh.mesh = st.commit()
	mesh.material_override = material
	return mesh


## The captain's cabin: a raised quarterdeck aft with a stern window in it. The
## one piece of a ship that says somebody *lives* on it.
static func _cabin(
	length: float, beam: float, freeboard: float, material: StandardMaterial3D
) -> Node3D:
	var root := Node3D.new()
	root.name = "Cabin"

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var front: float = length * 0.22
	var back: float = length * 0.47
	var height: float = freeboard * 0.95
	var base: float = freeboard * 0.55
	var w_front: float = beam * 0.5 * _curve(BEAM_CURVE, 0.72) * 0.78
	var w_back: float = beam * 0.5 * _curve(BEAM_CURVE, 0.96) * 0.72

	var fbl := Vector3(-w_front, base, front)
	var fbr := Vector3(w_front, base, front)
	var bbl := Vector3(-w_back, base, back)
	var bbr := Vector3(w_back, base, back)
	var ftl := Vector3(-w_front * 0.94, base + height, front)
	var ftr := Vector3(w_front * 0.94, base + height, front)
	var btl := Vector3(-w_back * 0.94, base + height * 0.92, back)
	var btr := Vector3(w_back * 0.94, base + height * 0.92, back)

	_quad(st, fbl, fbr, ftr, ftl, CABIN_COLOR)                 # forward bulkhead
	_quad(st, bbr, bbl, btl, btr, CABIN_COLOR.darkened(0.12))  # transom
	_quad(st, fbr, bbr, btr, ftr, CABIN_COLOR.darkened(0.05))  # starboard side
	_quad(st, bbl, fbl, ftl, btl, CABIN_COLOR.darkened(0.05))  # port side
	_quad(st, ftl, ftr, btr, btl, TRIM_COLOR.darkened(0.25))   # poop deck

	st.generate_normals()
	var body := MeshInstance3D.new()
	body.name = "Quarterdeck"
	body.mesh = st.commit()
	body.material_override = material
	root.add_child(body)

	# Stern windows — the detail that reads as "captain's lodge" from further away
	# than any amount of planking does, because nothing else on a ship is a row of
	# bright rectangles.
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.92, 0.82, 0.48)
	glass.emission_enabled = true
	glass.emission = Color(0.85, 0.68, 0.32)
	glass.emission_energy_multiplier = 0.35

	for k: int in 3:
		var pane := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(w_back * 0.42, height * 0.34)
		pane.mesh = quad
		pane.material_override = glass
		pane.position = Vector3(
			lerpf(-w_back * 0.5, w_back * 0.5, float(k) / 2.0),
			base + height * 0.52,
			back + 0.6
		)
		root.add_child(pane)

	return root


## Masts, yards, standing rigging and canvas.
##
## Two masts on anything big enough to carry them. The single biggest thing that
## separates a ship from a boat in silhouette is not the hull at all — it is how
## much of her is above the rail, and how much of *that* is thin. Shrouds and
## stays cost four cylinders each and do more for the read at a distance than any
## amount of planking, because they break the sky.
static func _rig(
	length: float, beam: float, draft: float, freeboard: float,
	spar: StandardMaterial3D, damage: float
) -> Node3D:
	var root := Node3D.new()
	root.name = "Rig"

	var deck_y: float = freeboard * 0.55
	var two: bool = length >= TWO_MAST_LENGTH

	# Main is a little aft of amidships and the taller of the two; fore is well
	# forward and shorter. Both stepped on the centreline.
	_step_mast(root, length, beam, draft, freeboard, spar, damage,
		length * 0.04, length * 0.78, beam * 1.55, true)
	if two:
		_step_mast(root, length, beam, draft, freeboard, spar, damage,
			-length * 0.26, length * 0.62, beam * 1.25, false)

	# Forestay: masthead down to the end of the bowsprit. The one line that most
	# reads as rigging, because it is the longest unbroken diagonal on the ship.
	var stem: Vector3 = hull_point(0.0, 1.0, length, beam, draft, freeboard)
	var bow_tip := Vector3(0.0, stem.y + length * 0.05, stem.z - length * 0.17)
	var fore_head := Vector3(
		0.0, deck_y + length * (0.62 if two else 0.78) * 0.94,
		(-length * 0.26) if two else (length * 0.04)
	)
	root.add_child(_spar_between(fore_head, bow_tip, length * 0.0022, spar))
	return root


## One mast, its yards, its shrouds and its canvas.
static func _step_mast(
	root: Node3D, length: float, beam: float, draft: float, freeboard: float,
	spar: StandardMaterial3D, damage: float,
	z: float, height: float, sail_width: float, is_main: bool
) -> void:
	var deck_y: float = freeboard * 0.55
	var foot := Vector3(0.0, deck_y, z)
	var head := Vector3(0.0, deck_y + height, z)

	var mast := MeshInstance3D.new()
	var pole := CylinderMesh.new()
	pole.top_radius = length * 0.0045
	pole.bottom_radius = length * 0.0095
	pole.height = height
	pole.radial_segments = 8
	mast.mesh = pole
	mast.material_override = spar
	mast.position = (foot + head) * 0.5
	root.add_child(mast)

	# Shrouds: three a side, from high on the mast down to the rail abreast of it,
	# fanning aft. They are what a mast is actually held up by, and the fan is the
	# shape the eye recognises.
	var t_mast: float = clampf((z + length * 0.5) / length, 0.05, 0.95)
	for side: int in 2:
		var s: float = 1.0 if side == 0 else -1.0
		for k: int in 3:
			var t_foot: float = clampf(t_mast + 0.06 + float(k) * 0.055, 0.05, 0.95)
			var anchor: Vector3 = hull_point(t_foot, s, length, beam, draft, freeboard)
			var top: Vector3 = head.lerp(foot, 0.16 + float(k) * 0.035)
			root.add_child(_spar_between(top, anchor, length * 0.0016, spar))

	# Course, and a topsail above it on the mainmast. A single square sail on a
	# bare pole reads as a raft; two stacked reads as a ship.
	_hang_sail(root, spar, damage, head, foot, z, sail_width, 0.74, 0.30, length)
	if is_main:
		_hang_sail(root, spar, damage, head, foot, z, sail_width * 0.72, 0.96, 0.18, length)


## A yard with canvas on it, at `at_height` up the mast.
static func _hang_sail(
	root: Node3D, spar: StandardMaterial3D, damage: float,
	head: Vector3, foot: Vector3, z: float, width: float,
	at_height: float, drop_ratio: float, length: float
) -> void:
	var y: float = lerpf(foot.y, head.y, at_height)

	var yard := MeshInstance3D.new()
	var bar := CylinderMesh.new()
	bar.top_radius = length * 0.0026
	bar.bottom_radius = length * 0.0034
	bar.height = width * 1.06
	bar.radial_segments = 6
	yard.mesh = bar
	yard.material_override = spar
	yard.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	yard.position = Vector3(0.0, y, z)
	root.add_child(yard)

	var canvas: MeshInstance3D = _sail(length, width, y, length * drop_ratio, damage)
	canvas.position = Vector3(0.0, 0.0, z)
	root.add_child(canvas)


## The bowsprit, and the beakhead it grows out of.
##
## Pure silhouette. A ship without one is a hull with sticks in it; a ship with
## one has a *direction*, because the longest line on her points where she is
## going.
static func _bowsprit(
	length: float, beam: float, draft: float, freeboard: float,
	spar: StandardMaterial3D
) -> Node3D:
	var root := Node3D.new()
	root.name = "Bowsprit"
	var stem: Vector3 = hull_point(0.02, 1.0, length, beam, draft, freeboard)
	var butt := Vector3(0.0, stem.y * 0.9, stem.z + length * 0.04)
	var tip := Vector3(0.0, stem.y + length * 0.05, stem.z - length * 0.17)
	root.add_child(_spar_between(butt, tip, length * 0.0075, spar))
	return root


## Hatch, capstan and a stern lantern. Small things, but a deck with nothing on
## it reads as a lid rather than as somewhere people work.
static func _fittings(
	length: float, beam: float, freeboard: float,
	timber: StandardMaterial3D, spar: StandardMaterial3D
) -> Node3D:
	var root := Node3D.new()
	root.name = "Fittings"
	var deck_y: float = freeboard * 0.55

	var grating := MeshInstance3D.new()
	var hatch := BoxMesh.new()
	hatch.size = Vector3(beam * 0.30, freeboard * 0.16, length * 0.11)
	grating.mesh = hatch
	grating.material_override = spar
	grating.position = Vector3(0.0, deck_y + freeboard * 0.08, length * 0.10)
	root.add_child(grating)

	var capstan := MeshInstance3D.new()
	var drum := CylinderMesh.new()
	drum.top_radius = beam * 0.055
	drum.bottom_radius = beam * 0.075
	drum.height = freeboard * 0.42
	drum.radial_segments = 8
	capstan.mesh = drum
	capstan.material_override = spar
	capstan.position = Vector3(0.0, deck_y + freeboard * 0.21, -length * 0.13)
	root.add_child(capstan)

	# The stern lantern. One warm point of light on a ship that is otherwise all
	# timber and canvas, and the thing that will read first at dusk.
	var glow := StandardMaterial3D.new()
	glow.albedo_color = LANTERN_COLOR
	glow.emission_enabled = true
	glow.emission = LANTERN_COLOR
	glow.emission_energy_multiplier = 0.45
	var lantern := MeshInstance3D.new()
	var globe := SphereMesh.new()
	globe.radius = freeboard * 0.10
	globe.height = freeboard * 0.24
	globe.radial_segments = 8
	globe.rings = 5
	lantern.mesh = globe
	lantern.material_override = glow
	lantern.position = Vector3(0.0, deck_y + freeboard * 1.75, length * 0.455)
	root.add_child(lantern)
	return root


## A cylinder running between two points. Godot's CylinderMesh stands on its own
## +Y, so the basis has to be built rather than a rotation guessed.
static func _spar_between(
	a: Vector3, b: Vector3, radius: float, material: Material
) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = maxf(a.distance_to(b), 0.001)
	cyl.radial_segments = 5
	mesh.mesh = cyl
	mesh.material_override = material

	var along: Vector3 = (b - a).normalized()
	var reference: Vector3 = Vector3.UP
	if absf(along.dot(reference)) > 0.99:
		reference = Vector3.FORWARD
	var right: Vector3 = reference.cross(along).normalized()
	var out: Vector3 = along.cross(right).normalized()
	mesh.transform = Transform3D(Basis(right, along, out), (a + b) * 0.5)
	return mesh


## The canvas, with a foot that goes to ribbons as the rigging is shot away.
##
## Built as a grid so it can belly and tear rather than being one quad. The
## tearing is the same idea [SailCanvas] uses in the 2D game — a sail that only
## faded out never read as *damaged*, it read as being turned off.
static func _sail(
	length: float, width: float, head_height: float, drop: float, damage: float
) -> MeshInstance3D:
	const COLS: int = 26
	const ROWS: int = 18

	var canvas := StandardMaterial3D.new()
	canvas.vertex_color_use_as_albedo = true
	canvas.cull_mode = BaseMaterial3D.CULL_DISABLED
	canvas.roughness = 1.0
	canvas.specular = 0.05

	var rng := RandomNumberGenerator.new()
	rng.seed = 0xCA5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for r: int in ROWS:
		for c: int in COLS:
			var v0: Vector3 = _sail_point(c, r, COLS, ROWS, width, drop, head_height)
			var v1: Vector3 = _sail_point(c + 1, r, COLS, ROWS, width, drop, head_height)
			var v2: Vector3 = _sail_point(c + 1, r + 1, COLS, ROWS, width, drop, head_height)
			var v3: Vector3 = _sail_point(c, r + 1, COLS, ROWS, width, drop, head_height)

			# Holes, from the foot upward. Canvas blows out along the bottom edge
			# first because that is the unsupported one, so a torn sail should be
			# ragged along its foot and sound along its head.
			var depth_from_foot: float = 1.0 - float(r) / float(ROWS - 1)
			# Squared, so light damage frays the foot and only heavy damage opens
			# real holes. Linear made a lightly-scarred sail look moth-eaten all
			# over, which is not what shot does to canvas.
			# Clustered: a cell is far likelier to blow out next to one that already
			# has. Independent per-cell rolls gave an even scatter of pinholes,
			# which reads as moth damage; shot tears canvas in runs.
			var cluster: float = 0.5 + 0.5 * sin(float(c) * 1.7 + float(r) * 2.3)
			if rng.randf() < damage * damage * cluster * (0.15 + depth_from_foot * 0.85):
				continue

			var shade: float = 1.0 - float(r) / float(ROWS) * 0.18
			var tone: Color = Color(
				CANVAS_COLOR.r * shade, CANVAS_COLOR.g * shade, CANVAS_COLOR.b * shade
			)
			_quad(st, v0, v1, v2, v3, tone)

	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "Sail"
	mesh.mesh = st.commit()
	mesh.material_override = canvas
	return mesh


static func _sail_point(
	c: int, r: int, cols: int, rows: int, width: float, drop: float, head: float
) -> Vector3:
	var u: float = float(c) / float(cols)
	var v: float = float(r) / float(rows)
	# The foot is narrower than the head, and the whole sail bellies away to
	# leeward — the same trapezoid and the same curve the 2D canvas draws.
	var span: float = lerpf(1.0, 0.86, v)
	var belly: float = sin(u * PI) * sin(v * PI * 0.85) * width * 0.16
	return Vector3((u - 0.5) * width * span, head - v * drop, belly)


## The ensign at the taffrail, in the faction's two colours.
static func _ensign(
	length: float, freeboard: float, field: Color, charge: Color
) -> Node3D:
	var root := Node3D.new()
	root.name = "Ensign"

	var staff_material := StandardMaterial3D.new()
	staff_material.albedo_color = PLANK_DARK

	var staff_height: float = length * 0.22
	var staff := MeshInstance3D.new()
	var pole := CylinderMesh.new()
	pole.top_radius = length * 0.003
	pole.bottom_radius = length * 0.004
	pole.height = staff_height
	pole.radial_segments = 5
	staff.mesh = pole
	staff.material_override = staff_material
	staff.position = Vector3(0.0, freeboard * 1.4 + staff_height * 0.5, length * 0.47)
	root.add_child(staff)

	var cloth := StandardMaterial3D.new()
	cloth.vertex_color_use_as_albedo = true
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.roughness = 0.95

	const SEGMENTS: int = 6
	var fly: float = length * 0.18
	var hoist: float = length * 0.09
	var base_y: float = freeboard * 1.4 + staff_height * 0.92
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in SEGMENTS:
		var t0: float = float(i) / float(SEGMENTS)
		var t1: float = float(i + 1) / float(SEGMENTS)
		# Streaming aft with a wave in it, growing toward the free end.
		var w0: float = sin(t0 * PI * 1.6) * fly * 0.18 * t0
		var w1: float = sin(t1 * PI * 1.6) * fly * 0.18 * t1
		# The hoist third carries the charge, same split the 2D ensign uses.
		var colour: Color = charge if t0 < 0.34 else field
		_quad(st,
			Vector3(w0, base_y, length * 0.47 + t0 * fly),
			Vector3(w1, base_y, length * 0.47 + t1 * fly),
			Vector3(w1, base_y - hoist, length * 0.47 + t1 * fly),
			Vector3(w0, base_y - hoist, length * 0.47 + t0 * fly),
			colour)
	st.generate_normals()

	var flag := MeshInstance3D.new()
	flag.name = "Flag"
	flag.mesh = st.commit()
	flag.material_override = cloth
	root.add_child(flag)
	return root


## Two triangles with one flat colour. Winding matters: these all face outward,
## and a hull with half its quads inside out is a very confusing thing to debug
## by eye because the silhouette stays perfectly correct.
static func _quad(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color,
	flip: bool = false
) -> void:
	# Spelled out rather than built from a ternary of array literals: GDScript
	# types the branches of that expression as plain `Array` and refuses to assign
	# it to `Array[Vector3]`, which fails at runtime inside the mesh build. Every
	# surface silently vanished and left the ship as two floating spars.
	var p := PackedVector3Array()
	if flip:
		p.append_array([d, c, b, a])
	else:
		p.append_array([a, b, c, d])
	for index: int in [0, 1, 2, 0, 2, 3]:
		st.set_color(colour)
		st.add_vertex(p[index])
