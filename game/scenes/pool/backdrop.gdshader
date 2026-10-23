// The bottom of the fluid (micro-world plan section 3): an opaque plane 40 m under the swim plane,
// past every view. It is unshaded and keeps the engine's fog, so the height fog all but replaces
// it (97% at 40 m) and every pixel shows the fog colour at that depth, lit by the DepthGlow's
// scatter. Decor that art adds keeps the same fog, so it fades into exactly the colour behind it
// in both renderers. Its own colour shows only in the last 3%, and alone if the fog were off.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.043, 0.18, 0.42, 1.0);   // #0B2E6B, fluid deep

void fragment() {
	ALBEDO = color.rgb;
}
