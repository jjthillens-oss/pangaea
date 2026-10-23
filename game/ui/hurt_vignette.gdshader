// The hurt vignette (M1 step 3, plan section 15): a red glow at the screen's edges that pulses once
// when the cell is hit. Hud drives `strength` (at most Hud.VIGNETTE_PEAK); the middle of the screen
// stays clear, so it never flashes the whole view.
// Over the micro look's navy fluid a thin dark red blends to purple (the outer band read LAB h 316),
// so the tint is warmer and the outermost band, from `band_from` out, gets up to `band` more of it
// (micro-world plan C8): the corners then read red (h 26) while the middle of each edge is as before.
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.96, 0.25, 0.04, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.0;
// Distance from the center in half-screens (1.0 at the middle of each edge, about 1.41 in the
// corners): clear inside `inner`, full by `outer`.
uniform float inner = 0.6;
uniform float outer = 1.35;
uniform float band_from = 1.0;
uniform float band = 0.35;

void fragment() {
	vec2 d = (UV - vec2(0.5)) * 2.0;
	float r = length(d);
	float edge = smoothstep(inner, outer, r) * (1.0 + band * smoothstep(band_from, outer, r));
	COLOR = vec4(tint.rgb, tint.a * strength * edge);
}
