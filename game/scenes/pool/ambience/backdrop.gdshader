shader_type spatial;
// A huge organism far below the swim plane (pool_ambience.gd): a pre-blurred painting on a flat
// quad, so it reads out of focus in every renderer without depth of field. The scene's fog takes
// it toward the water's colour with depth.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D image : source_color, filter_linear_mipmap, repeat_disable;
uniform float opacity = 0.5;

void fragment() {
	vec4 c = texture(image, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a * opacity;
}
