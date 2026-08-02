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
// Octave count is driven by QualityManager, so a slow device pays for three waves
// instead of six.

uniform vec2 world_offset = vec2(0.0);
uniform vec2 world_size = vec2(1280.0, 720.0);
uniform int wave_octaves : hint_range(1, 4) = 4;
uniform bool caustics_enabled = true;
uniform float wave_speed : hint_range(0.0, 3.0) = 1.0;
uniform float wind_angle = 0.0;

uniform vec4 deep_color : source_color = vec4(0.055, 0.165, 0.271, 1.0);
uniform vec4 mid_color : source_color = vec4(0.098, 0.322, 0.451, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.216, 0.510, 0.596, 1.0);
uniform vec4 sky_color : source_color = vec4(0.478, 0.686, 0.784, 1.0);
uniform vec4 foam_color : source_color = vec4(0.878, 0.945, 0.969, 1.0);

// Direction offset from the wind (radians), spatial frequency, amplitude, speed.
// Frequencies rise ~1.75x per octave and amplitudes fall off with them, which is
// roughly how real wind-sea energy is distributed across wavelengths.
//
// Eight components, not six, at deliberately non-harmonic frequency ratios and
// with an uneven directional spread. Six regularly-spaced sinusoids interfere
// into a visibly periodic lattice — big repeating comma-shaped highlights that
// read as patterned wallpaper. Irrational-ish ratios and scattered headings hide
// the repeat.
//
// Wavelengths run roughly 550px down to 25px. A Sloop is 160px long, so the
// longest swell is a few ship-lengths and the chop is a fraction of one — which
// is about right for a small vessel in open water. Waves any larger than this
// stop reading as sea state and start reading as terrain.
const int WAVE_COUNT = 8;
const vec4 WAVES[8] = {
	vec4( 0.00, 0.0114, 1.000, 0.62),
	vec4(-0.47, 0.0193, 0.610, 0.85),
	vec4( 0.68, 0.0331, 0.355, 1.14),
	vec4(-0.24, 0.0562, 0.205, 1.55),
	vec4( 1.04, 0.0917, 0.118, 2.10),
	vec4(-0.83, 0.1490, 0.070, 2.75),
	vec4( 0.31, 0.2370, 0.041, 3.40),
	vec4(-1.19, 0.3810, 0.024, 4.20)
};

// How strongly slope tilts the normal. Higher = flatter, calmer sea.
const float NORMAL_STRENGTH = 42.0;
// Finite-difference step for the noise gradient. Named, because `E` collides
// with a built-in in Godot's shading language.
const float NOISE_STEP = 0.35;

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

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

vec2 direction_for(float offset) {
	float a = wind_angle + offset;
	return vec2(cos(a), sin(a));
}

// Returns (height, d/dx, d/dy) of the summed wave field.
vec3 wave_field(vec2 p, float t, int octaves) {
	float height = 0.0;
	vec2 slope = vec2(0.0);
	float total = 0.0;

	// The quality tier picks how far down the spectrum we go. The fine components
	// are cheap and they are what stops the surface looking rubbery, so LOW still
	// gets two of them.
	int count = min(octaves * 2, WAVE_COUNT);
	for (int i = 0; i < count; i++) {
		vec4 w = WAVES[i];
		vec2 dir = direction_for(w.x);
		float phase = dot(p, dir) * w.y + t * w.w;
		height += sin(phase) * w.z;
		slope += dir * cos(phase) * w.z * w.y;
		total += w.z;
	}
	return vec3(height / total, slope);
}

void fragment() {
	vec2 p = world_offset + UV * world_size;
	float t = TIME * wave_speed;

	vec3 field = wave_field(p, t, wave_octaves);
	float height = field.x;

	// Slope to normal. The z term sets how much a given slope tilts the surface.
	vec2 slope = field.yz;

	// Perturb the slope with noise so no two crests are quite alike. Sampled by
	// finite difference because we need its gradient, not its value.
	if (wave_octaves > 2) {
		vec2 np = p * 0.0125 + vec2(t * 0.06, t * -0.04);
		float n0 = value_noise(np);
		float nx = value_noise(np + vec2(NOISE_STEP, 0.0));
		float ny = value_noise(np + vec2(0.0, NOISE_STEP));
		slope += vec2(nx - n0, ny - n0) * 0.035;

		vec2 fp = p * 0.052 + vec2(t * -0.11, t * 0.08);
		float f0 = value_noise(fp);
		slope += vec2(value_noise(fp + vec2(NOISE_STEP, 0.0)) - f0,
					  value_noise(fp + vec2(0.0, NOISE_STEP)) - f0) * 0.045;
	}

	vec3 n = normalize(vec3(-slope.x * NORMAL_STRENGTH, -slope.y * NORMAL_STRENGTH, 1.0));

	// A low sun off the port bow, so crests catch light on one side and fall into
	// shadow on the other. This asymmetry is what gives the sea a direction.
	vec3 light = normalize(vec3(-0.42, -0.66, 0.62));
	float lambert = clamp(dot(n, light), 0.0, 1.0);

	// Ambient floor before the directional term. Pure lambert drives most of the
	// surface to near-black, which reads as night rather than as a lit sea.
	float lit = 0.42 + 0.58 * lambert;
	vec3 col = mix(deep_color.rgb, mid_color.rgb, smoothstep(0.30, 0.80, lit));
	col = mix(col, shallow_color.rgb, smoothstep(0.82, 1.0, lit));

	// Grazing faces pick up the sky, which is most of why real water is not just
	// a darker or lighter blue in the distance.
	float fresnel = pow(1.0 - clamp(n.z, 0.0, 1.0), 2.2);
	col = mix(col, sky_color.rgb, fresnel * 0.40);

	// Tight specular for the glitter track. Small and sharp on purpose — a broad
	// highlight reads as plastic.
	vec3 halfway = normalize(light + vec3(0.0, 0.0, 1.0));
	float spec = pow(clamp(dot(n, halfway), 0.0, 1.0), 34.0);
	col += vec3(1.0, 0.98, 0.92) * spec * 0.30;

	// Foam only where a crest is both high and steep, so it forms broken lines
	// along the wave tops rather than filling in whole regions.
	float steepness = clamp(length(slope) * NORMAL_STRENGTH * 1.6, 0.0, 1.0);
	float foam = smoothstep(0.80, 1.0, height) * steepness;
	col = mix(col, foam_color.rgb, foam * 0.35);

	if (caustics_enabled) {
		// A second, much finer field, used only as a sparkle mask on the glitter.
		// Broad and gentle: a glitter *track* across the swell, not a field of
		// individual white dots. High frequency here reads as falling snow.
		float fine = sin(dot(p, direction_for(0.35)) * 0.0345 + t * 1.4)
			* sin(dot(p, direction_for(-1.1)) * 0.0288 - t * 1.1);
		col += vec3(0.85, 0.95, 1.0) * pow(clamp(fine, 0.0, 1.0), 3.0) * 0.09;
	}

	COLOR = vec4(col, 1.0);
}
