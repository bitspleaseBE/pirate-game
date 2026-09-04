shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;

// The same sea, as geometry instead of as a picture of geometry.
//
// This is a spike, not the game. It exists to answer one question with a
// screenshot rather than an argument: is the top-down 2D ocean actually at its
// ceiling, or is there more to get out of it?
//
// The wave table below is copied verbatim from `src/world/ocean/ocean.gdshader` —
// same eight components, same jittered frequency ladder, same shaped crest. That
// is deliberate. If the table changed too, a side-by-side would be comparing two
// different seas and would prove nothing. The *only* difference here is where the
// numbers are applied: the 2D shader turns them into a colour, and this one moves
// vertices with them.
//
// Everything the 2D version has to fake falls out for free once the surface has
// height:
//
//   * a hull can sit *in* the water at four points and get its real pitch and
//     roll, instead of a scale pulse and an in-plane rotation that the code
//     comments already admit are fudges;
//   * crests occlude what is behind them;
//   * the specular is a real reflection vector off a real normal, so the glitter
//     track moves correctly as the camera tilts rather than being painted on;
//   * there is a horizon.

// (direction offset in radians, spatial frequency, relative amplitude, speed)
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
const float AMPLITUDE_TOTAL = 2.2437;

uniform float wave_time = 0.0;
uniform float wind_angle = 0.0;
// Peak-to-trough height of the whole field, in world units. A hull radius is
// about 46, so 30 is a sea a Sloop rides rather than one it disappears into.
uniform float wave_height = 30.0;

uniform vec3 deep_color : source_color = vec3(0.043, 0.153, 0.290);
uniform vec3 shallow_color : source_color = vec3(0.235, 0.596, 0.714);
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 0.97);

varying float v_height;
varying vec3 v_world;


vec2 direction_for(float offset) {
	float a = wind_angle + offset;
	return vec2(cos(a), sin(a));
}


// Height and horizontal slope of the field at a world XZ position.
//
// Returns (height, d/dx, d/dz). The crest shaping is the 2D shader's: for
// u = (sin + 1) / 2, height is 2u^2 - 1, which sharpens the peaks and flattens
// the troughs the way a real wind sea does. Its derivative is (sin + 1) * cos,
// which is what the slope terms carry — the same expression `Ocean.swell_at()`
// uses in GDScript, so the shader and the physics cannot drift apart.
vec3 wave_at(vec2 p) {
	float height = 0.0;
	vec2 slope = vec2(0.0);
	for (int i = 0; i < 8; i++) {
		vec4 w = WAVES[i];
		vec2 dir = direction_for(w.x);
		float phase = dot(p, dir) * w.y - wave_time * w.w;
		float s = sin(phase);
		float c = cos(phase);
		float u = s * 0.5 + 0.5;
		height += (2.0 * u * u - 1.0) * w.z;
		slope += dir * ((s + 1.0) * c) * w.z * w.y;
	}
	float scale = wave_height / AMPLITUDE_TOTAL;
	return vec3(height * scale, slope.x * scale, slope.y * scale);
}


void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec3 wave = wave_at(p);
	VERTEX.y += wave.x;

	// Analytic normal from the slope, rather than a finite difference. The
	// surface is a sum of sines and we already have its gradient, so there is no
	// reason to sample it three times to estimate what it hands us directly.
	NORMAL = normalize(vec3(-wave.y, 1.0, -wave.z));

	v_height = wave.x / max(wave_height * 0.5, 0.001);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	// Depth colour off the wave height rather than off a seabed: this spike has no
	// islands in it, so the only depth cue available is that troughs look deeper
	// than crests, which is true and is most of what the eye reads anyway.
	// Crests catch the sky and troughs hold the deep colour. Biased well down, or
	// the whole surface sits at the pale end of the ramp and reads as flat.
	float lift = clamp(v_height * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(deep_color, shallow_color, pow(lift, 2.4));

	// Foam on the steepest faces. In the 2D shader this had to be gated carefully
	// off the swell alone, because keying it to total slope turned every ripple
	// white. Here the geometry does the gating: only real crests are steep.
	// Tight thresholds. The first pass opened at 0.06 of tilt, which most of a
	// wave face clears, and the sea came out as a white smear with blue gaps.
	// Whitecaps break on the last few degrees before a crest topples, not on the
	// whole flank.
	// Both gates have to be tight, and the *height* one was the problem rather
	// than the slope one: at smoothstep(0.55, 0.92) it caught the whole upper
	// third of the wave field, so every crest came out as a solid white ridge
	// running the length of the swell. A whitecap is the last moment before a
	// crest topples — a small fraction of a small fraction of the surface.
	float steep = 1.0 - dot(normalize(NORMAL), vec3(0.0, 1.0, 0.0));
	float foam = smoothstep(0.045, 0.105, steep) * smoothstep(0.86, 0.99, lift);
	col = mix(col, foam_color, foam * 0.9);

	ALBEDO = col;
	ROUGHNESS = mix(0.06, 0.35, foam);
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
