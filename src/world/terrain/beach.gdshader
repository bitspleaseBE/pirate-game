shader_type canvas_item;
render_mode unshaded, blend_mul;

// The wet strip a beach carries at the waterline.
//
// Sand above the tide line is pale, dry and scatters light in every direction.
// Sand the sea has just been over is darker, more saturated and slightly glossy,
// because the water between the grains removes the air that was doing the
// scattering. It is a narrow band — a few metres — and it is one of the most
// reliable cues in any photograph of a coast that the thing on the left is
// *water* and the thing on the right is *land*.
//
// Without it the beach is a flat sand-coloured polygon that stops, and the eye
// reads the boundary as the edge of a sprite rather than as a shore. That was the
// last obviously-flat thing left touching the sea after the water itself got a
// bottom and a proper surf line.
//
// The band has to follow the real coastline, which it can for the same reason
// the ocean's shallows can: [method IslandDef.build_outline] is three sine
// harmonics of the polar angle, not noise, so six numbers reproduce it exactly.
// This is the third place that curve is evaluated and all three read the same
// six numbers off [method IslandDef.outline_harmonics] — the alternative is
// three drawings of one coast that agree until somebody edits one of them.
//
// **This is a multiply overlay, not the beach's own material**, and that is worth
// stating because the obvious approach failed twice. Shading the beach polygon
// directly means writing a `fragment()`, which replaces the default one — the
// one that was sampling the sand tile. Reproducing it by hand turned every
// island into a smeared brown gradient, because a Polygon2D's UVs are not the
// normalised coordinates a hand-written sampler assumes and the node's
// `texture_repeat` does not reach one either. Chasing that is fighting the
// engine to re-implement something it already does correctly. A second polygon
// on the same outline, multiplying, leaves the sand exactly as Godot drew it and
// only says how much darker each part of it should be.
//
// Multiply cannot brighten, so there is no wet sheen here. That is no loss: the
// sheen was worth about a tenth of the effect and the first version of it put a
// pale chalk rim round every island that undid the darkening it sat beside.

// The island's mean radius and how ragged its coast is.
uniform float island_radius = 520.0;
uniform float raggedness = 0.45;
// The three angular harmonics: lobe counts and their phases.
uniform vec3 lobes = vec3(2.0, 5.0, 9.0);
uniform vec3 phases = vec3(0.0);

// How far inland the wet strip reaches, in world units. A tide's reach, not a
// gradient across the whole beach — the beach is only ~110 units wide at the
// narrowest and a soft ramp over that reads as the sand being dirty rather than
// as the sea having been there.
uniform float wet_band = 56.0;
// What wet sand does to dry sand. Darker and a shade cooler — water kills the
// red scatter first, the same absorption that runs the shallows turquoise.
uniform vec3 wet_tint = vec3(0.60, 0.585, 0.565);
uniform float wet_strength = 0.88;

varying vec2 local_pos;


void vertex() {
	// Polygon2D hands the fragment stage no position of its own, so the local
	// vertex coordinate is carried across. It is already in island space, which
	// is the space the coastline curve is defined in.
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

	// Distance inland from the waterline. Negative outside it, which cannot
	// happen on a polygon cut to the same curve, but clamping costs nothing and
	// float error at the very edge is real.
	float inland = max(coast - r, 0.0);

	float wet = 1.0 - smoothstep(0.0, wet_band, inland);
	// Biased towards the sea, so the strip has a soft inland edge and a definite
	// seaward one rather than fading evenly across its width — a tide line is a
	// line. Squaring it was too aggressive: it put the whole of the darkening in
	// the outermost few units, which is exactly the ground the surf draws over,
	// so the band was there and invisible.
	wet = pow(wet, 1.35);

	// White is "leave the sand alone". Everything this shader does is in how far
	// below white it goes.
	COLOR = vec4(mix(vec3(1.0), wet_tint, wet * wet_strength), 1.0);
}
