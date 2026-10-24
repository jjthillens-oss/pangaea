// The creature stage field (creature_field_ground, assets/records/creature_field_ground.json). PROPOSED, art-owned.
// Two seamless tiles, sage turf and bare earth, sampled in world space so the field mesh can be scaled or
// re-gridded without a UV pass, each at two scales against repetition, and blended by a 37 m patch mask (also in
// world space) with a bare clearing round the nest at the origin. The tiles' v runs along +Z like the mesh UV, so
// the baked normal maps keep their frame. A macro sample of the patch mask dries the turf toward a warmer, paler
// sage in places, and the turf is fully rough with almost no specular, so it reads as meadow rather than water.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D turf_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D turf_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D patch_mask : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float tile_m = 2.5;             // metres per tile repeat
uniform float detail_scale = 0.37;      // the second sample's scale against the first, so the repeat never lines up
uniform float patch_m = 37.0;           // metres per patch-mask repeat
uniform float patch_low : hint_range(0.0, 1.0) = 0.56;    // mask below this is turf
uniform float patch_high : hint_range(0.0, 1.0) = 0.7;    // mask above this is earth
uniform float edge_break : hint_range(0.0, 2.0) = 1.0;    // how much the turf's own crowns ragged the blend edge
uniform float clearing_r = 7.5;         // the nest's bare floor, metres from the origin
uniform float clearing_soft = 3.0;      // metres over which the clearing fades into the turf
uniform vec3 turf_tint : source_color = vec3(1.0);
uniform vec3 turf_dry_tint = vec3(1.08, 1.05, 0.9);       // a linear multiplier where the macro noise dries the turf
uniform float dry_amount : hint_range(0.0, 1.0) = 1.0;
uniform vec3 earth_tint : source_color = vec3(1.0);
uniform float turf_roughness : hint_range(0.0, 1.0) = 1.0;
uniform float earth_roughness : hint_range(0.0, 1.0) = 0.9;
uniform float turf_specular : hint_range(0.0, 1.0) = 0.05;
uniform float earth_specular : hint_range(0.0, 1.0) = 0.12;
uniform float normal_depth : hint_range(0.0, 2.0) = 1.0;
uniform float macro_strength : hint_range(0.0, 0.5) = 0.12;

varying vec3 world_pos;

vec4 two_scale(sampler2D tex, vec2 uv) {
	// The same tile at two scales, mixed evenly: the repeat of one never lines up with the other.
	return mix(texture(tex, uv), texture(tex, uv * detail_scale + vec2(0.17, 0.61)), 0.5);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz / tile_m;
	vec3 turf = two_scale(turf_albedo, uv).rgb * 1.08;         // the even mix of two samples sits a little dark
	vec3 earth = two_scale(earth_albedo, uv).rgb * 1.08;
	float mask = texture(patch_mask, world_pos.xz / patch_m).r;
	float t = smoothstep(patch_low, patch_high, mask);
	float clearing = 1.0 - smoothstep(clearing_r, clearing_r + clearing_soft, length(world_pos.xz));
	t = max(t, clearing);
	// The turf's lighter crowns hold out longest against the earth, so the edge is ragged, not a soft gradient.
	float crown = (dot(turf, vec3(0.299, 0.587, 0.114)) - 0.4) * 6.0;
	float w = 4.0 * t * (1.0 - t);
	t = clamp(t - crown * edge_break * 0.5 * w, 0.0, 1.0);
	float macro = texture(patch_mask, world_pos.xz / (patch_m * 0.37) + vec2(0.31, 0.77)).r;
	float dry = smoothstep(0.35, 0.75, macro) * dry_amount;
	vec3 turf_col = turf * turf_tint * mix(vec3(1.0), turf_dry_tint, dry);
	float shade = 1.0 + macro_strength * (macro - 0.5) * 2.0;
	ALBEDO = mix(turf_col, earth * earth_tint, t) * shade;
	vec3 n_turf = normalize(two_scale(turf_normal, uv).rgb * 2.0 - 1.0) * 0.5 + 0.5;
	vec3 n_earth = normalize(two_scale(earth_normal, uv).rgb * 2.0 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP = mix(n_turf, n_earth, t);
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = mix(turf_roughness, earth_roughness, t);
	SPECULAR = mix(turf_specular, earth_specular, t);
}
