// The bloom tint (S3, docs/s3/s3-view.md 7.4, V3-11): a warm glow over a meadow in bloom, laid like the
// sunlit patches under the swim plane, with no fog, no depth and under every cue. Its strength is an
// instance uniform the view eases with the meadow's bloom phase (ZoneLights.bloom_strength).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D mask : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.910, 0.761, 0.478, 1.0);
uniform float opacity = 0.05;
instance uniform float strength = 0.25;

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = texture(mask, UV).a * opacity * strength;
}
