shader_type canvas_item;
render_mode unshaded;

// The entire ocean, at any world size, in one draw call whose cost is exactly
// one screen of fragments. World-space UVs are reconstructed from the camera
// offset the Ocean node feeds in, so the waves stay anchored to the world while
// the quad stays anchored to the camera.
//
// Octave count and caustics are driven by QualityManager, so a slow device pays
// for two sine waves instead of four plus a caustic layer.

uniform vec2 world_offset = vec2(0.0);
uniform vec2 world_size = vec2(1280.0, 720.0);
uniform int wave_octaves : hint_range(1, 4) = 4;
uniform bool caustics_enabled = true;
uniform float wave_speed : hint_range(0.0, 3.0) = 1.0;

uniform vec4 deep_color : source_color = vec4(0.043, 0.145, 0.243, 1.0);
uniform vec4 mid_color : source_color = vec4(0.078, 0.310, 0.435, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.184, 0.510, 0.596, 1.0);
uniform vec4 crest_color : source_color = vec4(0.650, 0.850, 0.880, 1.0);

// Rotates the whole wave field so the swell runs with the wind. This is the only
// thing that makes the wind legible without reading a HUD widget: you glance at
// the sea and you know which way it is blowing.
uniform float wind_angle = 0.0;

vec2 rotated(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// Each octave is a plane wave travelling in its own direction. The directions are
// deliberately non-parallel and off-axis: waves aligned to X and Y (or to the
// diagonal) interfere into an obvious repeating lattice that reads as tiling
// rather than as water.
//
// Frequencies are tuned so the shortest wavelength is a couple of ship-lengths at
// the default zoom — lower and the sea looks like slow cloud, higher and it turns
// into noise at a phone's pixel density.
float ocean_height(vec2 p, float t, int octaves) {
	float w = sin(dot(p, rotated(vec2(0.94, 0.34), wind_angle)) * 0.0081 + t * 0.80) * 0.46;
	w += sin(dot(p, rotated(vec2(-0.37, 0.93), wind_angle)) * 0.0117 - t * 0.61) * 0.30;
	if (octaves > 2) {
		w += sin(dot(p, rotated(vec2(0.63, -0.78), wind_angle)) * 0.0212 + t * 1.32) * 0.16;
	}
	if (octaves > 3) {
		w += sin(dot(p, rotated(vec2(0.19, 0.98), wind_angle)) * 0.0347 - t * 1.95) * 0.09;
	}
	return w;
}

void fragment() {
	vec2 p = world_offset + UV * world_size;
	float t = TIME * wave_speed;

	float h = clamp(ocean_height(p, t, wave_octaves) * 0.5 + 0.5, 0.0, 1.0);

	vec3 col = mix(deep_color.rgb, mid_color.rgb, smoothstep(0.15, 0.60, h));
	col = mix(col, shallow_color.rgb, smoothstep(0.60, 0.90, h));

	// A narrow band at the top of the wave reads as a breaking crest and gives
	// the sea a direction of travel without any texture at all.
	float crest = smoothstep(0.86, 0.99, h);
	col = mix(col, crest_color.rgb, crest * 0.55);

	if (caustics_enabled) {
		float c = sin(dot(p, vec2(0.81, 0.59)) * 0.0268 + t * 1.6)
			* sin(dot(p, vec2(-0.55, 0.84)) * 0.0233 - t * 1.2);
		col += vec3(0.05, 0.07, 0.06) * max(c, 0.0);
	}

	COLOR = vec4(col, 1.0);
}
