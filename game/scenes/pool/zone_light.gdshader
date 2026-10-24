// A sunlit patch (micro-world plan C7; zone_lights.gd): soft shafts of the Sun's cream light falling
// round a plankton zone, over the fluid behind it. The light lies in a broad band round the zone's
// edge and leaves the feeding middle clear, so the coral cell and the food in it keep their
// contrast; within the band it falls in uneven soft shafts along the Sun's way, brighter on the
// side the Sun shines from, so it reads as light through the fluid and not as a ring round a
// target. Blended over the fluid (not added: faint added light is lost in Compatibility), with no
// fog, no depth and under every cue (render priority −2).
// The shafts are laid in the disc's own frame (anchor and laid_span, set per disc when it is laid),
// so a rebase, which moves the world under the camera, or a growth, which moves and shrinks the
// disc round the cell, carries them with it instead of sliding them across it (S2G13, G10). As
// laid they fall exactly where the world-space shafts did.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

const float BAND_IN = 0.45;     // in zone radii from the centre: no light inside this...
const float BAND_PEAK = 0.95;   // ...full here, about the zone's edge...
const float BAND_OUT = 1.3;     // ...and none past this
const float SHAFT_M = 2.9;      // the shafts' main spacing across the Sun's way, in metres...
const float SHAFT_M2 = 1.7;     // ...and a second, so they fall unevenly

uniform vec4 tint : source_color = vec4(0.957, 0.918, 0.824, 1.0);   // the Sun's colour
uniform float strength = 0.1;          // alpha where the light is fullest (zone_lights.gd sets it)
uniform float span_per_radius = 2.6;   // the disc spans this many zone radii (zone_lights.gd)
uniform vec2 sun_way = vec2(0.7071, 0.7071);   // the Sun's light across the plane (x, z), normalised
uniform vec2 anchor = vec2(0.0);       // the disc's centre (x, z) where it was laid...
uniform float laid_span = 1.0;         // ...and its span then, in metres: the shafts' frame

varying vec2 world_xz;
varying vec2 shaft_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	shaft_xz = anchor + VERTEX.xz * laid_span;
}

void fragment() {
	vec2 centre = NODE_POSITION_WORLD.xz;
	float radius = length(MODEL_MATRIX[0].xyz) / span_per_radius;
	vec2 d = world_xz - centre;
	float r = length(d) / radius;
	float band = smoothstep(BAND_IN, BAND_PEAK, r) * (1.0 - smoothstep(BAND_PEAK, BAND_OUT, r));
	// Each zone's shafts fall at their own phase, from where it was laid.
	float seed = dot(anchor, vec2(0.37, 0.61));
	vec2 across = vec2(-sun_way.y, sun_way.x);
	float s = dot(shaft_xz, across);
	float t = dot(shaft_xz, sun_way);
	float waves = 0.6 * sin(6.2832 * s / SHAFT_M + seed) + 0.4 * sin(6.2832 * s / SHAFT_M2 + 1.7 * seed);
	float shafts = smoothstep(-0.3, 0.7, waves) * (0.8 + 0.2 * sin(0.8 * t + 2.3 * seed));
	float side = 0.75 + 0.25 * dot(d / max(length(d), 1e-4), -sun_way);
	ALBEDO = tint.rgb;
	ALPHA = strength * band * shafts * side;
}
