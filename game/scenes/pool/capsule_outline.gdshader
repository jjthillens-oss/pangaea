// The soft outline of a veil's thread capsule (S3, docs/s3/s3-view.md 8.2): a thin line on the
// capsule's edge and a faint fill inside, so the whole stinging area reads, not just the threads.
// The fill is fill_alpha at the rim and fades to nothing on the axis ((d / r)^3): a flat fill
// blends to a purple wash over the deep blue in Forward+ that outweighs the pink line.
// The quad lies on the swim plane in the capsule's frame (the segment runs from (0, 0) to (0, L)
// in x and z), unscaled, so distances are in tm.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 ink_color : source_color = vec4(0.851, 0.275, 0.420, 1.0);
uniform vec4 neutral_color : source_color = vec4(0.784, 0.745, 0.878, 1.0);
uniform float ink : hint_range(0.0, 1.0) = 1.0;
uniform float outline_alpha = 0.85;
uniform float outline_w = 0.06;
uniform float fill_alpha = 0.10;
instance uniform float length_tm = 1.0;
instance uniform float radius_tm = 0.35;

varying vec2 plane;

void vertex() {
	plane = VERTEX.xz;
}

void fragment() {
	float t = clamp(plane.y / max(length_tm, 1e-4), 0.0, 1.0);
	float d = length(plane - vec2(0.0, t * length_tm));
	float line = 1.0 - smoothstep(0.5 * outline_w, outline_w, abs(d - radius_tm));
	float fill = (1.0 - smoothstep(radius_tm - 0.03, radius_tm, d)) * pow(clamp(d / max(radius_tm, 1e-4), 0.0, 1.0), 3.0);
	ALBEDO = mix(neutral_color.rgb, ink_color.rgb, ink);
	ALPHA = clamp(outline_alpha * line + fill_alpha * fill, 0.0, 1.0);
}
