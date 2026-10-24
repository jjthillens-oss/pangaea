// The haze of older sizes (S3, docs/s3/s3-view.md 9.3, V3-14): the food of the size before lies far
// under the swim plane, each instance a billboard of its haze sprite that keeps the instance's scale,
// tinted, faint and in the fog (midground). height_range names the band OlderHaze places them in, so
// the ambience contract reads their heights from it.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D image : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.722, 0.769, 0.839, 1.0);
uniform float brightness = 0.7;
uniform float opacity = 0.25;
uniform vec2 height_range = vec2(-3.4, -2.6);

void vertex() {
	// StandardMaterial3D's BILLBOARD_ENABLED with billboard_keep_scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 c = texture(image, UV);
	ALBEDO = c.rgb * tint.rgb * brightness;
	ALPHA = c.a * tint.a * opacity;
}
