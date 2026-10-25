shader_type spatial;
// The Aquatic stage's sea floor (PROPOSED, tools/blender/make_aquatic_world.py): sand with ripples on the flats, dark
// rock on the slopes, both darker and bluer with depth (world y; the surface is y = 0), and soft moving caustics in
// the sunlit shallows. In world space: the baked sand tile (tile_m across) carries the grain and ripples close up,
// procedural noise the large-scale variation.

uniform vec3 sand_shallow : source_color = vec3(0.80, 0.72, 0.55);
uniform vec3 sand_deep : source_color = vec3(0.16, 0.20, 0.27);
uniform vec3 rock_shallow : source_color = vec3(0.42, 0.40, 0.38);
uniform vec3 rock_deep : source_color = vec3(0.10, 0.12, 0.17);
uniform vec3 moss : source_color = vec3(0.30, 0.48, 0.36);
uniform sampler2D sand_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float tile_m = 3.0;
uniform float deep_at = 90.0;
uniform float caustic_depth = 18.0;
uniform float caustic_strength = 0.22;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float depth = clamp(-world_pos.y / deep_at, 0.0, 1.0);
	float n = fbm(world_pos.xz * 0.15);
	float ripple = sin(world_pos.x * 1.6 + world_pos.z * 0.45 + n * 6.0) * 0.5 + 0.5;
	vec3 sand = mix(sand_shallow, sand_deep, depth) * (0.86 + 0.14 * ripple) * (0.85 + 0.3 * n);
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float rocky = smoothstep(0.18, 0.42, slope + (n - 0.5) * 0.25);
	vec3 rock = mix(rock_shallow, rock_deep, depth) * (0.7 + 0.6 * fbm(world_pos.xz * 0.5 + world_pos.y * 0.3));
	float mossy = smoothstep(0.55, 0.75, fbm(world_pos.xz * 0.08 + 3.0)) * (1.0 - depth) * (1.0 - rocky);
	vec2 tuv = world_pos.xz / tile_m;
	vec3 detail = texture(sand_tex, tuv).rgb;
	sand *= detail * 1.25;
	vec3 col = mix(sand, rock, rocky);
	col = mix(col, moss * (0.7 + 0.3 * n), mossy * 0.6);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.8, rocky);
	NORMAL_MAP = texture(sand_normal, tuv).rgb;
	NORMAL_MAP_DEPTH = 1.0 - rocky * 0.7;
	float shallow = 1.0 - smoothstep(0.0, caustic_depth, -world_pos.y);
	vec2 c = world_pos.xz * 0.35;
	float caustic = pow(abs(sin(c.x + TIME * 0.7 + sin(c.y * 1.3 + TIME * 0.5)) * sin(c.y + TIME * 0.6 + sin(c.x * 1.1 - TIME * 0.4))), 6.0);
	EMISSION = vec3(0.55, 0.75, 0.8) * caustic * caustic_strength * shallow;
}
