// The creature stage field (creature_field_ground, assets/records/creature_field_ground.json). PROPOSED, art-owned.
// Two seamless 2 m tiles, blue-green turf and bare earth, sampled in world space so the field mesh can be scaled or
// re-gridded without a UV pass, and blended by a 37 m patch mask (also in world space) with a bare clearing round
// the nest at the origin. The tiles' v runs along +Z like the mesh UV, so the baked normal maps keep their frame.
// A macro sample of the patch mask breaks up the 2 m repeat at a distance.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D turf_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D turf_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D patch_mask : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float tile_m = 2.0;             // metres per tile repeat
uniform float patch_m = 37.0;           // metres per patch-mask repeat
uniform float patch_low : hint_range(0.0, 1.0) = 0.46;    // mask below this is turf
uniform float patch_high : hint_range(0.0, 1.0) = 0.62;   // mask above this is earth
uniform float edge_break : hint_range(0.0, 2.0) = 1.0;    // how much the turf's own crowns ragged the blend edge
uniform float clearing_r = 7.5;         // the nest's bare floor, metres from the origin
uniform float clearing_soft = 3.0;      // metres over which the clearing fades into the turf
uniform vec3 turf_tint : source_color = vec3(1.0);
uniform vec3 earth_tint : source_color = vec3(1.0);
uniform float turf_roughness : hint_range(0.0, 1.0) = 0.92;
uniform float earth_roughness : hint_range(0.0, 1.0) = 0.84;
uniform float normal_depth : hint_range(0.0, 2.0) = 1.0;
uniform float macro_strength : hint_range(0.0, 0.5) = 0.14;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz / tile_m;
	vec3 turf = texture(turf_albedo, uv).rgb;
	vec3 earth = texture(earth_albedo, uv).rgb;
	float mask = texture(patch_mask, world_pos.xz / patch_m).r;
	float t = smoothstep(patch_low, patch_high, mask);
	float clearing = 1.0 - smoothstep(clearing_r, clearing_r + clearing_soft, length(world_pos.xz));
	t = max(t, clearing);
	// The turf's lighter crowns hold out longest against the earth, so the edge is ragged, not a soft gradient.
	float crown = (dot(turf, vec3(0.299, 0.587, 0.114)) - 0.42) * 6.0;
	float w = 4.0 * t * (1.0 - t);
	t = clamp(t - crown * edge_break * 0.5 * w, 0.0, 1.0);
	float macro = texture(patch_mask, world_pos.xz / (patch_m * 0.37) + vec2(0.31, 0.77)).r;
	float shade = 1.0 + macro_strength * (macro - 0.5) * 2.0;
	ALBEDO = mix(turf * turf_tint, earth * earth_tint, t) * shade;
	NORMAL_MAP = mix(texture(turf_normal, uv).rgb, texture(earth_normal, uv).rgb, t);
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = mix(turf_roughness, earth_roughness, t);
	SPECULAR = 0.25;
}
