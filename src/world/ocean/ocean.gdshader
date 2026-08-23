shader_type canvas_item;
render_mode unshaded;

// The entire ocean, at any world size, in one draw call whose cost is exactly
// one screen of fragments. World-space UVs are reconstructed from the camera
// offset the Ocean node feeds in, so the waves stay anchored to the world while
// the quad stays anchored to the camera.
//
// The surface is shaded by its **slope**, not its height. Colouring by height is
// the obvious approach and it is why the first version of this looked like a lava
// lamp: height maps smoothly to colour, so you get soft isotropic blobs with no
// edges anywhere. Water reads as water because of how light behaves on tilted
// faces — a bright side, a dark side, and a hard specular glint along the crest.
// So each wave contributes an analytic derivative as well as a height, the two
// are summed into a surface normal, and that normal is lit.
//
// The wave set is also **anisotropic**: the swell runs within about 35 degrees of
// the wind and the chop spreads out to 87. A real wind sea has long crests
// running across the wind, not circular ripples, and that directionality is most
// of what distinguishes an ocean from a texture — while the short waves being far
// more spread than the long ones is what stops those crests being ruled lines.
//
// Everything travels **downwind**, and the surf travels **onto the land**. Both
// used to run backwards, which is the kind of error that is invisible in a still
// frame and unmissable in motion: the sea sailed into the wind and every island
// sat at the centre of expanding rings.
//
// The surface also has to read as *heaving*, not sliding. From directly overhead
// a travelling wave really does just translate, so vertical motion has to be said
// in shading rather than in geometry: crests are shaped rather than sinusoidal,
// water on the way up is lifted towards the light, and whitecaps only appear on a
// crest that is still building. Ships ride the same field from the CPU side (see
// `Ocean.swell_at`) — a hull lifting and rolling on a swell is worth more than
// any of it.
//
// Octave count is driven by QualityManager, so a slow device pays for three waves
// instead of six.

uniform vec2 world_offset = vec2(0.0);
uniform vec2 world_size = vec2(1280.0, 720.0);
uniform int wave_octaves : hint_range(1, 4) = 4;
uniform bool caustics_enabled = true;
uniform float wind_angle = 0.0;

// The wave clock, fed by the Ocean node rather than taken from `TIME`. Ships ride
// this same swell, and a hull cannot rise on a crest it is a few frames out of
// phase with, so both sides have to be reading one clock. See `Ocean.swell_at`.
uniform float wave_time = 0.0;

// Saturated on purpose. These went up once the shelf's own green palette was
// retired: with the bottom carrying the warm end of the range, the open sea is
// free to be properly blue instead of splitting the difference, and the previous
// values left it reading grey-green — closer to an estuary than a reef.
uniform vec4 deep_color : source_color = vec4(0.043, 0.153, 0.290, 1.0);
uniform vec4 mid_color : source_color = vec4(0.078, 0.357, 0.553, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.235, 0.596, 0.714, 1.0);
uniform vec4 sky_color : source_color = vec4(0.478, 0.686, 0.784, 1.0);
uniform vec4 foam_color : source_color = vec4(0.878, 0.945, 0.969, 1.0);

// --- Shallow water -------------------------------------------------------
//
// The sea has no idea where the land is — it is one camera-locked quad, drawn
// before the archipelago exists. So the Ocean node feeds it a handful of
// circles, one per nearby island, and the shader shades the water inside them
// as a shelf: paler, greener, calmer, with surf marching in towards the beach.
// Circles rather than the real coastline because the outline is a 44-point
// polygon per island and a per-fragment point-in-polygon test for a full screen
// is not affordable — at shelf scale the difference is invisible anyway, since
// the shelf is hundreds of pixels wider than the raggedness it is approximating.
const int MAX_SHOALS = 8;
uniform int shoal_count = 0;
// xy = island centre, z = radius where the shelf begins (the mean coastline),
// w = how far the shelf reaches seaward from there.
uniform vec4 shoals[8];
// xyz = the three lobe counts of the island's outline, w = its raggedness.
uniform vec4 shoal_lobes[8];
// xyz = the three phases. See `coast_radius`.
uniform vec4 shoal_phase[8];
uniform bool shore_foam_enabled = true;

// --- The bottom ------------------------------------------------------------
//
// The single largest thing separating this from a sea you would look twice at:
// until now the water had no *volume*. It was a lit surface over nothing, so
// shallow water was deep water in a different colour, and the eye reads that as
// paint rather than as a few feet of sea over sand.
//
// Now the sand is drawn under it and the water absorbs light on the way down.
// Red goes first, then green, which is the entire reason tropical shallows run
// gold to turquoise to blue over about twenty metres — it is not three colours
// chosen by an artist, it is one absorption curve. Beer-Lambert per channel
// gives that ramp for nothing.
// The seabed is the *same tile the beach is drawn with*, and that is the point
// rather than a convenience. Sand does not change substance at the waterline, so
// a procedural ripple under the water and an authored texture above it put a
// material seam exactly where the eye is looking hardest. One tile, sampled in
// world space on both sides, and the bed runs continuously out of the water and
// up the beach.
uniform sampler2D seabed_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform vec4 sand_color : source_color = vec4(0.847, 0.706, 0.427, 1.0);
uniform vec4 sand_shadow : source_color = vec4(0.604, 0.478, 0.290, 1.0);
// World units per tile. Matches the beach's own tiling so the grain is the same
// size on both sides of the waterline.
const float SEABED_TILE = 307.0;
// Per-channel extinction. The ratios are what make the gradient read as water;
// the overall scale is how deep the shelf "feels".
const vec3 EXTINCTION = vec3(3.10, 1.15, 0.78);
const float EXTINCTION_SCALE = 4.3;

// Direction offset from the wind (radians), spatial frequency, amplitude, speed.
//
// Eight components, not six, at deliberately non-harmonic frequency ratios and
// with an uneven directional spread. Six regularly-spaced sinusoids interfere
// into a visibly periodic lattice — big repeating comma-shaped highlights that
// read as patterned wallpaper. Irrational-ish ratios and scattered headings hide
// the repeat.
//
// Wavelengths run 1100 units down to 41, and **the bottom of that range is the
// point**.
//
// A viewer reads how far away a surface is from the size of its features, and
// the sea and the land here were disagreeing. An island carries palms 64 units
// wide, rocks of 64, grass finer than that; a Sloop is 160 long. The sea's
// dominant feature was an 1102-unit swell — seventeen palm-widths — so the water
// read as something photographed from far higher up than the beach it was
// touching, and the two looked like different zoom levels pasted together.
//
// The amplitudes are what decide that, not the frequencies. This surface is
// shaded by **slope**, and a component's slope is amplitude x frequency, so the
// amplitude curve chooses which octave the eye lands on. The previous curve fell
// off faster than 1/f — slope decaying 0.76 an octave, the leading swell holding
// six times the slope of the shortest chop — and it was written to fix a real
// problem: the sea before it read as undifferentiated fine chop with no swell in
// it at all.
//
// That was the right diagnosis and the wrong lever. The swell should be legible
// through *shading* — the shaped crests, the heave term and the foam gate, none
// of which existed when that curve was chosen — not by starving every other
// octave of slope. With those in place the spectrum can go back to something like
// a real one: slope now decays 0.90 an octave rather than 0.76, and the surface
// texture lands in the 40-250 unit band where the island's own detail lives.
//
// It stops at 41 units rather than going finer, and that bound is the *shading*,
// not the physics. One world unit is about one screen pixel at default zoom and
// less than one zoomed out, so a 19-unit wave — which the first attempt at this
// reached for — has nothing left to be drawn with. A procedural surface has no
// mip chain, so it does not soften, it aliases: that sea came out as a field of
// hard diagonal flecks indistinguishable from television static.
//
// The ladder is also knocked deliberately off true, and the directional spread
// widens with frequency. Both stop the sea corduroying. Clean ratios between
// components beat against each other, and eight of them on an even geometric
// ladder — ratio 1.5915 throughout, which the second attempt used — interfere
// into diagonal ridges the eye finds in about a second. Real short waves are far
// more spread in heading than long ones, so the wide offsets down the table are
// physical as well as useful: they are what keeps a crest from running dead
// straight across the whole screen.
//
// Speeds follow deep-water gravity waves (w ~ sqrt(k)), so the big swell rolls
// and the chop skitters.
const int WAVE_COUNT = 8;
const vec4 WAVES[8] = {
	vec4( 0.00, 0.00570, 1.0000, 0.42),
	vec4(-0.41, 0.00982, 0.5224, 0.55),
	vec4( 0.63, 0.01340, 0.3446, 0.64),
	vec4(-0.22, 0.02438, 0.1704, 0.87),
	vec4( 1.08, 0.03336, 0.1121, 1.02),
	vec4(-0.87, 0.06428, 0.0524, 1.41),
	vec4( 1.36, 0.08794, 0.0344, 1.65),
	vec4(-1.51, 0.15310, 0.0178, 2.18)
};

// How strongly slope tilts the normal. Higher = steeper-looking sea.
//
// Tracks the spectrum inversely: flattening the amplitude curve raised the summed
// slope from 0.0216 to 0.0325, so this comes down — but by less than the ratio
// would suggest. Matching the totals is not matching the look: eight
// contributions of similar size align far less often than three big ones and
// five token ones did, so the same summed slope produces a lower peak and a
// flatter sea. This is set by eye against the previous surface's contrast, which
// is the only thing that can settle it. It has been 118 and
// then 100 on the way here, each time following a change in what the wave table
// sums to — it is a calibration constant, not a taste one, and the right way to
// move it is to divide by however much the spectrum grew.
const float NORMAL_STRENGTH = 84.0;
// Cheap value noise. Stacked sinusoids, however many and however irrationally
// spaced, always interfere into a periodic lattice — the eye finds the repeat
// within a second or two and the sea reads as patterned wallpaper. Noise is the
// only thing that actually breaks it.
//
// This is a stopgap for the seamless `water_detail_tile` in docs/ASSETS.md §4,
// which has not been produced yet. A sampled texture would be cheaper than this
// and would not band on weaker GPUs.
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Returns (value, d/dx, d/dy) of value noise, differentiated analytically.
//
// The earlier version took a finite difference a third of a cell wide, which is
// not a gradient — it is an axis-aligned average, and shading by it printed the
// noise lattice onto the sea as visible rectangular blocks. The exact derivative
// of the bilinear-smoothstep patch is continuous across cell edges, and at four
// hashes instead of twelve it is also three times cheaper than what it replaces.
vec3 value_noise_d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);

	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));

	float corner = a - b - c + d;
	return vec3(
		a + (b - a) * u.x + (c - a) * u.y + corner * u.x * u.y,
		((b - a) + corner * u.y) * du.x,
		((c - a) + corner * u.x) * du.y
	);
}

// The real coastline, evaluated in the shader.
//
// [IslandDef.build_outline] is not noise — it is three sine harmonics of the
// polar angle, and that is the whole reason this is possible. Handing the shader
// six numbers per island (three lobe counts, three phases) lets it reproduce the
// exact radius the polygon was built from, at any angle, for three sines.
//
// It matters more than a shoreline detail. The shelf used to be a circle on the
// island's *mean* radius while the land was a 44-point ragged polygon, so the
// shallows were a smooth ring that visibly disagreed with the coast it was
// supposed to belong to: pale water cutting across headlands, and a band of deep
// blue sitting inside bays. Nothing else about the water reads as wrong so
// quickly, because the eye has the beach right next to it for comparison.
float coast_radius(int i, vec2 offset) {
	vec4 s = shoals[i];
	vec4 lobes = shoal_lobes[i];
	vec4 phase = shoal_phase[i];
	float a = atan(offset.y, offset.x);
	float n = (
		sin(a * lobes.x + phase.x) * 0.55
		+ sin(a * lobes.y + phase.y) * 0.30
		+ sin(a * lobes.z + phase.z) * 0.15
	);
	return s.z * (1.0 + n * lobes.w * 0.5);
}

// How shallow the water is at `p`, and how far seaward `p` is of the coast. The
// nearest shelf wins outright rather than the contributions summing, so two
// islands whose shelves overlap make one continuous flat rather than a brighter
// patch in the channel between them.
//
// Two passes on purpose. The ragged radius costs three sines, and doing it for
// every island for every fragment is twenty-four transcendentals on a phone. The
// first pass picks a winner off the mean radius — which is never wrong at shelf
// scale, the islands being thousands of units apart — and only the winner pays
// for its real coastline.
vec2 shoal_at(vec2 p) {
	int nearest = -1;
	float best = 1.0e6;
	for (int i = 0; i < MAX_SHOALS; i++) {
		if (i >= shoal_count) {
			break;
		}
		vec4 s = shoals[i];
		float d = length(p - s.xy) - s.z;
		if (d - s.w < best) {
			best = d - s.w;
			nearest = i;
		}
	}
	if (nearest < 0) {
		return vec2(0.0, 1.0e6);
	}

	float shallowest = 0.0;
	float distance_out = 1.0e6;
	for (int i = 0; i < MAX_SHOALS; i++) {
		if (i != nearest) {
			continue;
		}
		vec4 s = shoals[i];
		vec2 offset = p - s.xy;
		float d = length(offset) - coast_radius(i, offset);
		float f = 1.0 - smoothstep(0.0, s.w, max(d, 0.0));
		if (f > shallowest) {
			shallowest = f;
			distance_out = d;
		}
	}
	return vec2(shallowest, distance_out);
}

vec2 direction_for(float offset) {
	float a = wind_angle + offset;
	return vec2(cos(a), sin(a));
}

// Returns (height, d/dx, d/dy, d/dt) of the summed wave field.
//
// The vertical rate is the fourth component and it is not decoration. Shading a
// top-down sea by slope alone gives a fixed pattern sliding across the screen —
// the sea passes by, nothing about it goes up or down. Knowing which way a patch
// of water is moving vertically is what lets the shading say "this crest is
// lifting" rather than "this stripe is over here now".
vec4 wave_field(vec2 p, float t, int octaves, out vec3 swell) {
	float height = 0.0;
	vec2 slope = vec2(0.0);
	float vertical = 0.0;
	float total = 0.0;
	// The long components on their own, returned alongside the summed field.
	//
	// Whitecaps break on swell, not on ripples, and the glitter track rides crests
	// rather than every square metre of surface — so both are gated on this. Keying
	// them off the total was harmless while the chop carried almost no slope, and
	// became the whole problem the moment it carried a realistic share: every
	// ripple cleared the foam threshold at once, the 26th-power specular fired on
	// each one, and the sea turned into television static.
	float swell_height = 0.0;
	vec2 swell_slope = vec2(0.0);
	float swell_total = 0.0;

	// The quality tier picks how many components we can afford — but they are
	// taken as a stride across the whole spectrum rather than as a prefix of it.
	// A prefix leaves a low tier with nothing but the longest swells, and the
	// result is a lava lamp: enormous smooth blobs with no surface at any scale a
	// player can see. Striding costs exactly the same and keeps a low tier a
	// coarser version of the same sea rather than a different substance.
	int count = min(octaves * 2, WAVE_COUNT);
	int stride = WAVE_COUNT / count;
	for (int i = 0; i < count; i++) {
		vec4 w = WAVES[i * stride];
		vec2 dir = direction_for(w.x);

		// Minus, not plus. A plane wave travelling along `dir` is sin(k.x - wt);
		// with the sign the other way every component ran *backwards*, so the whole
		// sea marched into the wind while the HUD compass said otherwise.
		float phase = dot(p, dir) * w.y - t * w.w;
		float s = sin(phase);
		float c = cos(phase);

		// Crest shaping. A swell is not a sinusoid — it is a narrow ridge over a
		// broad, flat trough — and a symmetric sine is a large part of why this sea
		// read as a scrolling texture: a sine has no front and no back, so there is
		// nothing to watch rise and break. Squaring the profile (h = 2u^2 - 1 for
		// u = (sin+1)/2) is the cheapest honest way to say so: the derivative is
		// exact, and it costs no transcendentals beyond the sin/cos already paid.
		//
		// Only the components carrying real amplitude are shaped. Sharpening the
		// chop just piles on fine slope, which reads as static rather than water.
		float sharp = smoothstep(0.05, 0.30, w.z);
		float u = s * 0.5 + 0.5;
		float h = mix(s, 2.0 * u * u - 1.0, sharp);
		float dh = mix(c, (s + 1.0) * c, sharp);

		height += h * w.z;
		slope += dir * dh * w.z * w.y;
		// `sharp` is already the test for "is this a swell component" — it is only
		// nonzero for the long ones — so the split costs a branch and no new state.
		if (sharp > 0.5) {
			swell_height += h * w.z;
			swell_slope += dir * dh * w.z * w.y;
			swell_total += w.z;
		}
		// dh/dt = dh/dphase * dphase/dt, and dphase/dt is -w.w.
		vertical -= dh * w.z * w.w;
		total += w.z;
	}
	swell = vec3(swell_height / max(swell_total, 0.001), swell_slope);
	return vec4(height / total, slope, vertical / total);
}

void fragment() {
	vec2 p = world_offset + UV * world_size;
	float t = wave_time;

	vec2 shoal = shoal_at(p);
	float shelf = shoal.x;

	vec3 swell;
	vec4 field = wave_field(p, t, wave_octaves, swell);
	float height = swell.x;

	// Slope to normal. The z term sets how much a given slope tilts the surface.
	vec2 slope = field.yz;
	float rise = field.w;

	// Perturb the slope with noise so no two crests are quite alike. Its gradient
	// is what we want, not its value. Both scales are coarser than the finest wave
	// octaves — noise finer than the chop reads as film grain rather than water.
	//
	// Both layers drift downwind rather than along fixed axes. They used to slide
	// north-east regardless of the weather, which put a second, contradictory
	// direction on the water and helped sell "texture scrolling past" over "sea".
	if (wave_octaves > 2) {
		vec2 drift = direction_for(0.0) * t;

		vec2 np = (p - drift * 9.0) * 0.0052;
		slope += value_noise_d(np).yz * 0.0016;

		vec2 fp = (p - drift * 4.0) * 0.0215;
		slope += value_noise_d(fp).yz * 0.0028;
	}

	// Land takes the fetch out of the swell, so the shelf is markedly calmer than
	// the open sea. It is also what stops the shallows reading as deep water that
	// happens to be a different colour.
	slope *= mix(1.0, 0.55, shelf);
	rise *= mix(1.0, 0.55, shelf);
	vec2 swell_slope = swell.yz * mix(1.0, 0.55, shelf);

	vec3 n = normalize(vec3(-slope.x * NORMAL_STRENGTH, -slope.y * NORMAL_STRENGTH, 1.0));

	// A low sun off the port bow, so crests catch light on one side and fall into
	// shadow on the other. This asymmetry is what gives the sea a direction.
	vec3 light = normalize(vec3(-0.42, -0.66, 0.62));
	float lambert = clamp(dot(n, light), 0.0, 1.0);

	// Ambient floor before the directional term. Pure lambert drives most of the
	// surface to near-black, which reads as night rather than as a lit sea.
	float lit = 0.42 + 0.58 * lambert;

	// Heave. Slope tells you the shape of the surface; it does not tell you that
	// the surface is *moving vertically*, and from directly overhead that motion
	// has nowhere else to show itself. So water on the way up is lifted towards
	// the light and water on the way down falls away from it, which puts a bright
	// leading face and a dark following face on every crest. This is what turns a
	// band sliding across the screen into something that swells and subsides.
	lit += clamp(rise * 0.50, -0.16, 0.16);

	// One water colour everywhere, deep or shallow.
	//
	// There used to be a second palette for the shelf — three hand-picked greens
	// the ramp lerped towards as the water got shallower. It has gone, and its
	// going is the point: shallow water is not a different colour of water, it is
	// the same water with less of it, and the bottom showing through. Now that the
	// sand is actually drawn and the extinction below is doing the work, keeping
	// the green would have been painting the answer on top of the calculation —
	// and the two disagreed, which is what turned the shallows into glowing jade.
	//
	// The bright band is deliberately narrow. It is the crest of the swell, and a
	// swell this wide would otherwise hand it a third of the screen.
	vec3 col = mix(deep_color.rgb, mid_color.rgb, smoothstep(0.26, 0.86, lit));
	// A narrow top band. Widening it is the fastest way to turn a sea into
	// confetti: with a realistic amount of chop, every ripple crest that clears
	// the threshold gets painted pale cyan, and a screen of those reads as fish
	// rather than water.
	col = mix(col, shallow_color.rgb, smoothstep(0.945, 1.0, lit));

	// --- The bottom, seen through the water --------------------------------
	//
	// This replaces a `mix` towards a pale green, which is what "shallow" used to
	// mean here. Tinting the surface says the water is a different colour; drawing
	// the sand under it and absorbing light on the way down says there is *water
	// on top of something*, and that is the difference between a painted sea and
	// one with a volume to it.
	if (shelf > 0.0) {
		// Depth from the shore, not from the shelf's outer edge. `pow` below 1
		// because a beach shelves steeply at first and then flattens — a linear
		// ramp puts the whole colour transition in a narrow band offshore and
		// leaves the water at the sand's edge already blue.
		float depth = pow(clamp(1.0 - shelf, 0.0, 1.0), 0.72);

		// Sand, twice. The tile is mirror-seamless, which is invisible on a strip
		// of beach and an obvious repeating diamond once it is spread over a shelf
		// hundreds of units wide — so a second sample, rotated and at an unrelated
		// scale, is laid over the first. Two fetches, and the motif stops being
		// findable.
		vec2 uv_a = p / SEABED_TILE;
		vec2 uv_b = (mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80)) * p) / (SEABED_TILE * 0.61);
		vec3 grain = texture(seabed_texture, uv_a).rgb * 0.62
			+ texture(seabed_texture, uv_b).rgb * 0.38;

		// Bars parallel to the shore. Real bedforms run along the contour, not
		// across it, and `shoal.y` is exactly distance-from-shore, so one sine of
		// it is the whole effect.
		float bars = sin(shoal.y * 0.085) * 0.5 + 0.5;
		// Dimmed, and the grain kept near unity. The tile averages about 0.72, so
		// multiplying by it darkens; the gain restores that without turning the
		// bed into a light source. It was 1.55 for one pass and the shallows came
		// out as glowing jade — sand under two metres of water is *shaded* sand,
		// and the eye knows it.
		vec3 bed = mix(sand_shadow.rgb, sand_color.rgb, 0.42 + 0.58 * bars)
			* (grain * 1.18) * 0.88;

		// Caustics. The real thing is the surface acting as a lens, so the bright
		// web on the bottom is the *wave field itself* focused down — which means
		// it belongs here, projected on the sand and fading with depth, rather
		// than as the surface sparkle it was standing in for. Two counter-running
		// fields multiplied give the interlocking cells; the sharp power turns
		// them from a wobble into lines of light.
		if (caustics_enabled) {
			// Cells about thirty units across — caustics are focused by the *short*
			// waves, so they are far finer than the swell and finer than anything
			// else in this shader. A first pass at 114 units put slow lamps on the
			// seabed rather than a moving web of light.
			//
			// Domain-warped before the sinusoids, and that is not a refinement.
			// A product of sinusoids is a *grid*: the first version of this drew
			// the seabed as rows of evenly spaced dots, which is the one thing
			// caustics never look like. Pushing the sample point around with a
			// slow noise field first bends those rows into closed cells of
			// irregular size, which is exactly what a rippled surface focusing
			// sunlight actually produces.
			vec2 warp = vec2(
				value_noise_d(p * 0.0075 + vec2(t * 0.05, 0.0)).x,
				value_noise_d(p * 0.0075 + vec2(11.3, 4.7)).x
			) - 0.5;
			vec2 cp = p + warp * 150.0;
			float ca = sin(dot(cp, direction_for(0.9)) * 0.210 - t * 2.4);
			float cb = sin(dot(cp, direction_for(-0.7)) * 0.183 + t * 1.9);
			float cc = sin(dot(cp, direction_for(2.4)) * 0.268 - t * 3.0);
			float web = pow(clamp((ca * cb + cc * 0.35) * 0.5 + 0.5, 0.0, 1.0), 5.0);
			bed += vec3(1.0, 0.96, 0.84) * web * 0.34 * (1.0 - depth);
		}

		// Beer-Lambert, per channel. Red is gone within a few metres, green holds
		// on, blue survives — which is why the ramp from wet sand out to open water
		// runs gold, then turquoise, then blue, without anyone choosing those
		// colours. `transmit` is how much of the bottom still reaches the eye.
		vec3 transmit = exp(-depth * EXTINCTION * EXTINCTION_SCALE);
		col = mix(col, bed * lit, transmit);
	}

	// Grazing faces pick up the sky, which is most of why real water is not just
	// a darker or lighter blue in the distance.
	float fresnel = pow(1.0 - clamp(n.z, 0.0, 1.0), 2.2);
	// Trimmed from 0.40. The sky here is a pale grey-blue, so every point of
	// this is a point of saturation off the water, and it was enough to keep the
	// open sea looking overcast.
	col = mix(col, sky_color.rgb, fresnel * 0.28);

	// Tight specular for the glitter track. Small and sharp on purpose — a broad
	// highlight reads as plastic.
	// Specular for the glitter track. Broad enough that a highlight is a patch
	// riding a crest rather than a pinprick — a sharper exponent than this loses
	// the long reflections entirely once the swell is this wide.
	// Off the swell's own normal rather than the full surface. A 26th-power
	// exponent is a near-threshold function, so feeding it the chop turns every
	// ripple into a hard white pinprick and the sea into glitter-glue. The
	// reflection the player should be able to watch is a patch sliding along the
	// back of a crest, which is a swell-scale event.
	// Boosted, because the swell alone carries about half the slope the whole
	// surface does, and a 26th-power exponent turns "half" into "almost none".
	const float SPEC_GAIN = 2.1;
	vec3 sn = normalize(vec3(
		-swell_slope.x * NORMAL_STRENGTH * SPEC_GAIN,
		-swell_slope.y * NORMAL_STRENGTH * SPEC_GAIN,
		1.0
	));
	vec3 halfway = normalize(light + vec3(0.0, 0.0, 1.0));
	float spec = pow(clamp(dot(sn, halfway), 0.0, 1.0), 26.0);
	col += vec3(1.0, 0.98, 0.92) * spec * 0.34;

	// Foam only where a crest is both high and steep, so it forms broken lines
	// along the wave tops rather than filling in whole regions. The threshold
	// tracks the amplitude curve: the leading swell is most of the normalised
	// height, and it sits lower than it used to now that crest shaping has pulled
	// the mean of the field down and left the peaks where they were.
	//
	// Whitecaps also only appear on a crest that is still building, and vanish
	// once it has passed its top — so the foam is gated on the water rising. A
	// crest that grows a white edge, breaks and loses it again is the clearest
	// statement the sea can make that it is doing something vertical.
	float steepness = clamp(length(swell_slope) * NORMAL_STRENGTH * 2.4, 0.0, 1.0);
	float breaking = smoothstep(-0.02, 0.14, rise);
	float foam = smoothstep(0.30, 0.58, height) * steepness * breaking;
	col = mix(col, foam_color.rgb, foam * 0.42);

	// Surf. Sets of parallel lines marching *in* onto the beach, densest right
	// against the sand. Drawn in world space off the same distance the shelf uses,
	// so the breakers and the shallow water can never disagree about where the
	// coast is.
	//
	// They used to march the other way — every island sat at the centre of a set
	// of rings radiating out into open water, which is a stone dropped in a pond,
	// not a coast. Surf only ever runs one direction: onto the land.
	if (shore_foam_enabled && shelf > 0.0) {
		float out_dist = max(shoal.y, 0.0);

		// Shoaling. The bottom coming up shortens the wavelength and slows the
		// crest, which is why real sets crowd together and stack up against a beach
		// instead of arriving evenly spaced. Advancing the phase as dist^0.72
		// rather than dist buys both effects from one exponent: the spacing closes
		// up towards the sand, and because the phase gradient steepens there, so
		// does the time each crest takes to cross the last stretch.
		float shoaled = pow(out_dist, 0.72) * 0.26;
		// Sets run out over 190 units rather than 340, and break far harder when
		// they get there. The old numbers put a soft white haze most of the way
		// across the shelf — a wide grey-white ring that read as fog on the water
		// rather than as surf, and which was the last thing making the shore look
		// painted on. Foam is thin: it is the top of a wave that has actually
		// broken, and everywhere else the water is simply water.
		float near_shore = 1.0 - smoothstep(0.0, 190.0, out_dist);

		// Plus, so a line of constant phase travels towards the island.
		float band = sin(shoaled + t * 1.5) * 0.5 + 0.5;

		// The line sharpens as it comes in. Well offshore a set is a broad swell;
		// the same set at the beach is a thin hard edge that has broken.
		float breaker = pow(band, mix(9.0, 2.6, near_shore));
		col = mix(col, foam_color.rgb, near_shore * breaker * 0.70);

		// The wash, in the last thirty units against the sand. Where the surf
		// meets the beach there is always white water; what the sets do is make it
		// surge and drain rather than appear and vanish.
		float wash = 1.0 - smoothstep(0.0, 34.0, out_dist);
		col = mix(col, foam_color.rgb, pow(wash, 1.4) * (0.42 + 0.45 * band));
	}

	// Wind streaks — the one thing that says "seen from directly above".
	//
	// Everything else here would look much the same from a low angle. Langmuir
	// streaks would not: wind blowing over water sets up counter-rotating cells
	// that sweep foam and bubbles into long thin lines running *downwind*, spaced
	// a few metres apart, and from overhead they are the most recognisable feature
	// on the whole surface. On an oblique view they foreshorten into nothing, which
	// is exactly why a top-down sea needs them and a side-on one does not.
	//
	// Noise stretched hard along the wind: cells about 45 units across the wind and
	// 600 along it, so what comes out is filaments rather than blobs. They drift
	// slowly, because the streaks are a property of the wind field rather than of
	// any wave passing through them.
	//
	// Very faint on purpose. This is a grain in the water, not a set of painted
	// lines, and the moment it is legible as stripes it stops reading as sea.
	if (wave_octaves > 2) {
		vec2 downwind = direction_for(0.0);
		vec2 across = vec2(-downwind.y, downwind.x);
		float streak = value_noise_d(vec2(
			dot(p, across) * 0.0222,
			dot(p, downwind) * 0.0017 - t * 0.03
		)).x;
		// Squared so only the tops of the noise show, which is what turns a wobbly
		// field into discrete filaments with clear water between them.
		float filament = smoothstep(0.58, 0.98, streak);
		col = mix(col, foam_color.rgb, filament * filament * 0.10 * (1.0 - shelf));
	}

	if (caustics_enabled) {
		// A second, much coarser field, used only as a sparkle mask on the glitter.
		// Broad and gentle: a glitter *track* across the swell, not a field of
		// individual white dots. High frequency here reads as falling snow.
		float fine = sin(dot(p, direction_for(0.35)) * 0.0165 - t * 1.1)
			* sin(dot(p, direction_for(-1.1)) * 0.0139 - t * 0.85);
		col += vec3(0.85, 0.95, 1.0) * pow(clamp(fine, 0.0, 1.0), 3.0) * 0.11;
	}

	COLOR = vec4(col, 1.0);
}
