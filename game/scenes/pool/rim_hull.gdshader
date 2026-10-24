// The green rim round a body the cell can eat now (S2, s2-view 5): an inverted hull, the body's
// own mesh pushed out along its normals and drawn from the back faces only, so it shows as an
// outline round the silhouette. CreatureView sets grow in the mesh's units (RIM_GROW_TM over the
// model's scale) so the rim is the same width in the world at any body size, and rim (0..1) as it
// fades in or out.
shader_type spatial;
render_mode unshaded, cull_front, blend_mix, depth_draw_opaque, shadows_disabled;

uniform float grow = 0.06;
uniform vec4 color : source_color = vec4(0.812, 0.91, 0.416, 1.0);
uniform float rim : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	VERTEX += NORMAL * grow;
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a * rim;
}
