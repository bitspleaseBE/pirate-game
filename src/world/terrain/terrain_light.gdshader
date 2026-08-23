shader_type canvas_item;
render_mode unshaded, blend_mul;

// Light and shade on the land, from the same sun that lights the sea.
//
// The islands were the only unlit surface in the game. The water has a
// directional light, a specular track and shading that says which way each face
// is tilted; the land beside it was two flat polygons of constant colour with
// props standing on them, and once the water got a bottom and a graded shore
// that flatness was the thing that read as unfinished. Nothing about the shapes
// was wrong. There was simply no sun on them.
//
// An island here is a low dome: sand at the waterline, ground rising inland. So
// the surface normal tilts *outward* near the coast and stands up in the middle,
// which is enough to shade with — the seaward slope facing the sun catches the
// light, the far side falls away from it, and the interior sits between. That
// single gradient does most of the work of making a flat polygon look like a
// piece of ground rather than a sticker.
//
// It multiplies, for the same reason the wet-sand band does: the beach and the
// grass are drawn by Godot with their own textures and tints, and reproducing
// that in a shader means re-implementing the engine's own sampler. This says
// only how much lighter or darker each part of the island should be, and leaves
// the drawing alone.

// The coastline, in the same six numbers everything else reads.
uniform float island_radius = 520.0;
uniform float raggedness = 0.45;
uniform vec3 lobes = vec3(2.0, 5.0, 9.0);
uniform vec3 phases = vec3(0.0);

// How far inland the ground goes on rising, as a fraction of the radius. Past
// this the dome is flat and the shading is even, which is what an interior
// plateau looks like from above.
uniform float shoulder = 0.45;
// How steep that rise is. This is the only thing setting how strong the light
// and shade are, so it is the knob to turn.
uniform float relief = 1.75;

// The same low sun the ocean shader uses. If one of them moves, both must.
const vec3 SUN = vec3(-0.42, -0.66, 0.62);

// How dark the shadowed side goes and how bright the lit side comes up. Above
// one is a brighten, which a multiply blend can do — the clamp is on the result,
// not on the multiplier.
uniform float shade_floor = 0.70;
uniform float shade_ceiling = 1.14;

// Broad mottling: clearings, canopy, patches of bare ground. Large, because at
// this scale anything finer is the grass texture's job and two layers of detail
// at the same size just look noisy.
uniform float mottle_scale = 0.0042;
uniform float mottle_depth = 0.24;

varying vec2 local_pos;


float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}


float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return a + (b - a) * u.x + (c - a) * u.y + (a - b - c + d) * u.x * u.y;
}


void vertex() {
	local_pos = VERTEX;
}


void fragment() {
	float r = length(local_pos);
	float a = atan(local_pos.y, local_pos.x);
	float n = (
		sin(a * lobes.x + phases.x) * 0.55
		+ sin(a * lobes.y + phases.y) * 0.30
		+ sin(a * lobes.z + phases.z) * 0.15
	);
	float coast = island_radius * (1.0 + n * raggedness * 0.5);

	// 0 at the waterline, 1 once the ground has finished rising.
	float climb = clamp((coast - r) / max(coast * shoulder, 1.0), 0.0, 1.0);
	// Smoothstep's derivative is zero at both ends, which is what puts a rounded
	// shoulder on the dome instead of a cone with a crease round its base.
	float height = smoothstep(0.0, 1.0, climb);
	// d(height)/d(inland), pointing away from the island's centre.
	float grade = 6.0 * climb * (1.0 - climb) * relief;

	vec2 outward = local_pos / max(r, 0.001);
	vec3 normal = normalize(vec3(outward * grade, 1.0));
	float lambert = dot(normal, normalize(SUN)) * 0.5 + 0.5;

	float shade = mix(shade_floor, shade_ceiling, lambert);
	// Mottling, faded out at the shore so it never breaks up clean sand. Two
	// octaves: broad clearings, and a finer break-up inside them. One octave
	// alone reads as a stain rather than as ground.
	float mottle = (value_noise(local_pos * mottle_scale) - 0.5)
		+ (value_noise(local_pos * mottle_scale * 3.7 + vec2(19.0, 7.0)) - 0.5) * 0.45;
	shade *= 1.0 + mottle * mottle_depth * height;

	COLOR = vec4(vec3(shade), 1.0);
}
