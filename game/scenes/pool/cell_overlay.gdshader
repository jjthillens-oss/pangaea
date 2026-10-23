// The player's cell overlay (M1 step 2-3): drawn over every mesh of the cell as material_overlay.
// `tint` covers the whole cell (grey while starving or dead, a red flash when hurt) and blends over
// it; `rim` lights its edges (the soft cyan shelter rim) and adds to it, because a cyan rim mixed
// over a cyan cell at alpha 0.25 does not show. Premultiplied alpha does both in one pass: the
// tint's colour and alpha, plus the rim's colour times its alpha with no alpha of its own.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.0);
uniform vec4 rim : source_color = vec4(0.0);
uniform float rim_power = 1.8;   // lower is a wider band in from the silhouette

void fragment() {
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = tint.rgb * tint.a + rim.rgb * rim.a * edge * (1.0 - tint.a);
	ALPHA = tint.a;
}
