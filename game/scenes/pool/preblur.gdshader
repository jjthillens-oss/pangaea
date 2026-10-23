// The growth beat's "pre-blurred to sharp" veil (S2, s2-view 4.5; Q-V6): an overlay pass that lays
// the fluid's mid-tone over a piece, thickest at its silhouette, so a piece fading in or sinking away
// reads soft rather than crisp. `amount` 1 is fully veiled, 0 is no veil (the piece as it is). It is a
// transparency fade with a soft fresnel veil, not a real blur.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

// The start fade's fluid mid-tone (pool.tscn %Fade).
uniform vec4 veil : source_color = vec4(0.098, 0.29, 0.486, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float edge = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = veil.rgb;
	ALPHA = clamp(amount * (0.35 + 0.65 * edge), 0.0, 1.0) * veil.a;
}
