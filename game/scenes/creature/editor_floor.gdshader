// The creature editor's floor disc (creature_editor.tscn, placeholder creature_editor_floor): a dark blue disc whose
// edge feathers out over the outer third of its radius, with a soft pool of light under the body, so the Spore-style
// room has a floor that fades into its backdrop instead of a hard rim. VERTEX is the unit disc's model space (the
// node's scale sizes it), so the feather follows the disc whatever its size.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 color_floor : source_color = vec3(0.06, 0.14, 0.3);
uniform vec3 color_pool : source_color = vec3(0.12, 0.26, 0.48);
uniform float pool_radius : hint_range(0.05, 1.0) = 0.42;
uniform float feather_from : hint_range(0.0, 1.0) = 0.62;
uniform float roughness_floor : hint_range(0.0, 1.0) = 0.9;

varying float radius;

void vertex() {
	radius = length(VERTEX.xz);
}

void fragment() {
	float pool = 1.0 - smoothstep(0.0, pool_radius, radius);
	ALBEDO = mix(color_floor, color_pool, pool * pool);
	ALPHA = 1.0 - smoothstep(feather_from, 1.0, radius);
	ROUGHNESS = roughness_floor;
	SPECULAR = 0.2;
}
