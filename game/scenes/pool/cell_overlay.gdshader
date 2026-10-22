// The player's cell overlay (M1 step 2-3): drawn over every mesh of the cell as material_overlay.
// `tint` covers the whole cell (grey while starving or dead, a red flash when hurt); `rim` lights
// its edges (the soft cyan shelter rim). Alpha is the tint's, plus the rim's on the edges.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.0);
uniform vec4 rim : source_color = vec4(0.0);
uniform float rim_power = 2.5;

void fragment() {
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float ra = rim.a * edge * (1.0 - tint.a);
	float a = tint.a + ra;
	ALBEDO = a > 0.0 ? (tint.rgb * tint.a + rim.rgb * ra) / a : vec3(0.0);
	ALPHA = a;
}
