// The floor lane of a tell (M1 step 3, functional UI drawing): the strip a strike can hit,
// from CreatureBrain.strike_lane(), lying on the swim plane. The CreatureView scales a unit quad to
// the lane (x across, -z along the strike) and sets the uniforms each frame.
// Readability rules (plan sections 14-15): the inside never above MAX_ALPHA, so the floor shows
// through the strip, and nothing flashes. Only the thin outline (EDGE_M plus ACCENT_M, about 0.2 m
// of a strip 1.5 to 3 m wide) is drawn at LINE_ALPHA: at a quarter alpha no red survives over the
// lit teal floor, which turned the frame a grey selection box (DECISIONS, 2026-10-22 visual). The
// dark spike-tip crimson border carries the shape on any floor and the thin line of the bright
// threat colour inside it carries the danger hue. The inside fills from the creature toward the far
// end as the tell runs, so the fill reaching the end is the moment of the strike, and slow dark
// chevrons inside the fill point the way.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

const float MAX_ALPHA = 0.25;     // the inside: base, fill and chevrons
const float LINE_ALPHA = 0.7;     // the outline: the dark border and the bright line inside it
const float EDGE_M = 0.14;        // width of the dark border, in metres...
const float ACCENT_M = 0.06;      // ...and of the bright line just inside it
const float BASE_ALPHA = 0.06;    // the inside before the fill reaches it
const float FILL_ALPHA = 0.14;    // the inside the fill has covered
const float CHEVRON_ALPHA = 0.11; // added by the chevrons, inside the fill only (to the cap)
const float CHEVRON_M = 0.9;      // chevron spacing along the lane
const float CHEVRON_SPEED = 0.6;  // m/s toward the far end

uniform vec4 color : source_color = vec4(0.851, 0.275, 0.420, 1.0);   // threat #D9466B
uniform vec4 shade : source_color = vec4(0.541, 0.169, 0.271, 1.0);   // spike tip #8A2B45
uniform vec2 size_m = vec2(3.0, 3.7);   // (width, length) of the lane in metres
uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;

varying vec2 local;

void vertex() {
	local = VERTEX.xz;
}

void fragment() {
	// along: 0 at the creature, size_m.y at the far end; across: 0 on the centre line.
	float along = (0.5 - local.y) * size_m.y;
	float across = abs(local.x) * size_m.x;
	float to_edge = min(size_m.x * 0.5 - across, min(along, size_m.y - along));
	float border = 1.0 - smoothstep(EDGE_M * 0.75, EDGE_M, to_edge);
	float accent = (1.0 - smoothstep(EDGE_M + ACCENT_M * 0.6, EDGE_M + ACCENT_M, to_edge)) * (1.0 - border);
	float filled = step(along, fill * size_m.y);
	// The chevrons' tips lead (the centre line is furthest along), so they point the strike's way.
	float chevron = fract((along + across * 0.6 - TIME * CHEVRON_SPEED) / CHEVRON_M);
	float chev = smoothstep(0.0, 0.08, chevron) * (1.0 - smoothstep(0.18, 0.26, chevron)) * filled;
	float inside = mix(BASE_ALPHA, FILL_ALPHA, filled) + CHEVRON_ALPHA * chev;
	vec3 rgb = mix(shade.rgb, color.rgb, accent);
	float a = max(min(inside, MAX_ALPHA), LINE_ALPHA * max(border, accent));
	ALBEDO = rgb;
	ALPHA = a * strength;
}
