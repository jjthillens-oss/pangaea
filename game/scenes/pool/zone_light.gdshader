// A sunlit patch (micro-world plan C7, zone_lights.gd): soft cream light under a plankton zone,
// added to the fluid behind it. Additive decor takes no fog: with the engine's fog it would paint a
// bright, hard-edged quad. It writes no depth and draws under every cue (render priority −2).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.957, 0.918, 0.824, 1.0);   // the Sun's colour
uniform float strength = 0.006;  // the share of it added at the centre (zone_lights.gd sets it)

void fragment() {
	// Full to 35% of the disc's radius, half at about the zone's edge, nothing at the disc's rim.
	float r = length(UV - 0.5) * 2.0;
	ALBEDO = tint.rgb * (1.0 - smoothstep(0.35, 1.0, r)) * strength;
}
