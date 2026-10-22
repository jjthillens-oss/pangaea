// The hurt vignette (M1 step 3, plan section 15): a dark red glow at the screen's edges that pulses
// once when the cell is hit. Hud drives `strength` (at most Hud.VIGNETTE_PEAK); the middle of the
// screen stays clear, so it never flashes the whole view.
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.55, 0.04, 0.1, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.0;
// Distance from the center in half-screens (1.0 at the middle of each edge, about 1.41 in the
// corners): clear inside `inner`, full by `outer`.
uniform float inner = 0.6;
uniform float outer = 1.35;

void fragment() {
	vec2 d = (UV - vec2(0.5)) * 2.0;
	float edge = smoothstep(inner, outer, length(d));
	COLOR = vec4(tint.rgb, tint.a * strength * edge);
}
