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
// The wave set is also **anisotropic**: every component travels within about 50
// degrees of the wind. A real wind sea has long crests running across the wind,
// not circular ripples, and that directionality is most of what distinguishes an
// ocean from a texture.
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

uniform vec4 deep_color : source_color = vec4(0.055, 0.165, 0.271, 1.0);
uniform vec4 mid_color : source_color = vec4(0.098, 0.322, 0.451, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.216, 0.510, 0.596, 1.0);
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
uniform bool shore_foam_enabled = true;

uniform vec4 shoal_deep_color : source_color = vec4(0.075, 0.271, 0.325, 1.0);
uniform vec4 shoal_mid_color : source_color = vec4(0.157, 0.451, 0.478, 1.0);
uniform vec4 shoal_bright_color : source_color = vec4(0.361, 0.667, 0.635, 1.0);

// Direction offset from the wind (radians), spatial frequency, amplitude, speed.
//
// Eight components, not six, at deliberately non-harmonic frequency ratios and
// with an uneven directional spread. Six regularly-spaced sinusoids interfere
// into a visibly periodic lattice — big repeating comma-shaped highlights that
// read as patterned wallpaper. Irrational-ish ratios and scattered headings hide
// the repeat.
//
// Wavelengths run roughly 1100px down to 30px. A Sloop is 160px long, so the
// longest swell is several ship-lengths — big enough that a reflection sweeping
// along a crest is a feature the player can watch travel, rather than glitter.
//
// The amplitudes matter more than the frequencies here. This surface is shaded
// by **slope**, and a component's slope contribution is amplitude x frequency,
// so an amplitude curve that merely tracks 1/f gives every octave an equal say —
// which is what the first version did, and why the sea read as uniform fine
// chop no matter how long the leading wavelength was: the eye sees the octave
// with the most features per square inch, and that was all of them. Amplitude
// here falls off faster than 1/f, so slope decays ~0.73 per octave and the long
// swell is what you actually see. Speeds follow deep-water gravity waves
// (w ~ sqrt(k)), so the big swell rolls and the chop skitters.
const int WAVE_COUNT = 8;
const vec4 WAVES[8] = {
	vec4( 0.00, 0.0057, 1.0000, 0.42),
	vec4(-0.47, 0.0101, 0.4290, 0.56),
	vec4( 0.68, 0.0165, 0.2000, 0.72),
	vec4(-0.24, 0.0286, 0.0897, 0.95),
	vec4( 1.04, 0.0465, 0.0429, 1.24),
	vec4(-0.83, 0.0766, 0.0201, 1.60),
	vec4( 0.31, 0.1257, 0.0095, 2.05),
	vec4(-1.19, 0.2094, 0.0044, 2.65)
};

// How strongly slope tilts the normal. Higher = steeper-looking sea. Scaled up
// with the amplitude curve above: the summed slope of the new spectrum is about
// a quarter of the old one, and without this the sea would be a flat sheet.
//
// Deliberately below the value that would match the old sea's average slope. The
// old slope was a sum of eight equal contributions, so it only peaked where all
// eight aligned — a speckle. This one is dominated by the leading swell, so it
// reaches its peak across whole crests, and matching the average would light half
// the screen at once.
// Trimmed from 118 when crest shaping went in: a shaped crest peaks about 30%
// steeper than the sine it replaced, so the old figure lit the whole leading face.
const float NORMAL_STRENGTH = 100.0;
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

// How shallow the water is at `p`, and how far seaward `p` is of the shelf's
// inner edge. The nearest shelf wins outright rather than the contributions
// summing, so two islands whose shelves overlap make one continuous flat rather
// than a brighter patch in the channel between them.
vec2 shoal_at(vec2 p) {
	float shallowest = 0.0;
	float distance_out = 1.0e6;
	for (int i = 0; i < MAX_SHOALS; i++) {
		if (i >= shoal_count) {
			break;
		}
		vec4 s = shoals[i];
		float d = length(p - s.xy) - s.z;
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
vec4 wave_field(vec2 p, float t, int octaves) {
	float height = 0.0;
	vec2 slope = vec2(0.0);
	float vertical = 0.0;
	float total = 0.0;

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
		// dh/dt = dh/dphase * dphase/dt, and dphase/dt is -w.w.
		vertical -= dh * w.z * w.w;
		total += w.z;
	}
	return vec4(height / total, slope, vertical / total);
}

void fragment() {
	vec2 p = world_offset + UV * world_size;
	float t = wave_time;

	vec2 shoal = shoal_at(p);
	float shelf = shoal.x;

	vec4 field = wave_field(p, t, wave_octaves);
	float height = field.x;

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

	// The shelf recolours the whole ramp rather than tinting the finished pixel,
	// so shallow water keeps its own light and shade instead of looking like deep
	// sea behind green glass.
	vec3 ramp_deep = mix(deep_color.rgb, shoal_deep_color.rgb, shelf);
	vec3 ramp_mid = mix(mid_color.rgb, shoal_mid_color.rgb, shelf);
	vec3 ramp_bright = mix(shallow_color.rgb, shoal_bright_color.rgb, shelf);

	// The bright band is deliberately narrow. It is the crest of the swell, and a
	// swell this wide would otherwise hand it a third of the screen.
	vec3 col = mix(ramp_deep, ramp_mid, smoothstep(0.26, 0.86, lit));
	col = mix(col, ramp_bright, smoothstep(0.90, 1.0, lit));

	// Close in, the bottom starts showing through regardless of how the surface
	// is lit — which is the actual cue that water is shallow.
	col = mix(col, shoal_bright_color.rgb, smoothstep(0.55, 1.0, shelf) * 0.38);

	// Grazing faces pick up the sky, which is most of why real water is not just
	// a darker or lighter blue in the distance.
	float fresnel = pow(1.0 - clamp(n.z, 0.0, 1.0), 2.2);
	col = mix(col, sky_color.rgb, fresnel * 0.40);

	// Tight specular for the glitter track. Small and sharp on purpose — a broad
	// highlight reads as plastic.
	// Specular for the glitter track. Broad enough that a highlight is a patch
	// riding a crest rather than a pinprick — a sharper exponent than this loses
	// the long reflections entirely once the swell is this wide.
	vec3 halfway = normalize(light + vec3(0.0, 0.0, 1.0));
	float spec = pow(clamp(dot(n, halfway), 0.0, 1.0), 26.0);
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
	float steepness = clamp(length(slope) * NORMAL_STRENGTH * 1.6, 0.0, 1.0);
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
		float near_shore = 1.0 - smoothstep(0.0, 340.0, out_dist);

		// Plus, so a line of constant phase travels towards the island.
		float band = sin(shoaled + t * 1.5) * 0.5 + 0.5;

		// The line sharpens as it comes in. Well offshore a set is a broad swell;
		// the same set at the beach is a thin hard edge that has broken.
		float breaker = pow(band, mix(5.0, 2.0, near_shore));
		col = mix(col, foam_color.rgb, near_shore * breaker * 0.60);

		// The wash. Where the surf meets the sand there is always white water —
		// what the sets do is make it surge and drain, not appear and vanish. This
		// is the part that reads as waves clashing on the beach rather than as
		// stripes that happen to stop there.
		float wash = 1.0 - smoothstep(0.0, 90.0, out_dist);
		col = mix(col, foam_color.rgb, wash * wash * (0.30 + 0.45 * band));
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
