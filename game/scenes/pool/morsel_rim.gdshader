// The green rim round a morsel site's item (S3, docs/s3/s3-view.md 9.1): S2's inverted hull
// (rim_hull.gdshader) for a MultiMesh, where each instance has its own scale. The push is `grow` tm
// in the world, so it is divided by the instance basis length, and it follows the item's grow-in
// and shrink-out through INSTANCE_CUSTOM.r (0..1), so a hidden item leaves no green speck.
shader_type spatial;
render_mode unshaded, cull_front, blend_mix, depth_draw_opaque, shadows_disabled;

uniform float grow = 0.06;
uniform vec4 color : source_color = vec4(0.812, 0.91, 0.416, 1.0);

varying float shown;

void vertex() {
	float s = max(length(MODEL_MATRIX[0].xyz), 1e-4);
	shown = INSTANCE_CUSTOM.r;
	VERTEX += NORMAL * grow * shown / s;
}

void fragment() {
	if (shown <= 0.0) {
		discard;
	}
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
