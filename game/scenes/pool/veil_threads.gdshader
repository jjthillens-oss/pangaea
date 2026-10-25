// A stinger veil's threads (S3, docs/s3/s3-view.md 8.2): the rig remapped into the unit capsule,
// swaying sideways more toward each tip (COLOR.r is 0 at the rim and 1 at a tip), coloured between
// art's neutral and threat ink, and brightened by a sting's flash.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, shadows_disabled;

uniform vec4 ink_color : source_color = vec4(0.851, 0.275, 0.420, 1.0);
uniform vec4 neutral_color : source_color = vec4(0.784, 0.745, 0.878, 1.0);
uniform float ink_energy = 0.8;
uniform float neutral_energy = 0.25;
uniform float ink : hint_range(0.0, 1.0) = 1.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float sway = 0.15;
uniform float phase = 0.0;

void vertex() {
	VERTEX.x += sway * COLOR.r * sin(TIME * 2.1 + phase + COLOR.r * 3.0);
}

void fragment() {
	vec3 c = mix(neutral_color.rgb, ink_color.rgb, ink);
	ALBEDO = c;
	EMISSION = c * mix(neutral_energy, ink_energy, ink) * (1.0 + 2.0 * flash);
}
