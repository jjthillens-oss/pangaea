shader_type spatial;
// Caustic light on the pool floor (assets/records/pool_floor.json): a next pass of M_PoolFloor
// that adds a slow net of bright lines, made here from moving cell borders (no texture). The pass
// is lit like the floor, so the sun's shadows mask it. It skips the engine fog, which would add
// the fog colour a second time, and fades with the same fog the floor gets instead: the fog_*
// uniforms copy game/scenes/pool/pool_environment.tres (tests/test_pool_view.gd checks this).
render_mode blend_add, depth_draw_never, diffuse_lambert, specular_disabled, ambient_light_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.96, 0.82);
uniform float strength = 0.3;
uniform float cells_per_m = 0.42;     // size of the net's cells
uniform float drift = 0.35;           // how fast the lines move
uniform float line_width = 0.11;      // in cell units, before the anti-alias widening
uniform float fog_density = 0.0;
uniform float fog_height = 0.0;
uniform float fog_height_density = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

uniform int pattern = 2;
uniform float power = 4.0;
uniform float warp = 0.3;

// Nearest and second nearest distances to moving cell centres.
vec2 cells(vec2 p, float t) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 h = hash2(ip + g);
			vec2 o = 0.5 + 0.38 * sin(t + 6.2831853 * h);
			float d = length(g + o - fp);
			d2 = min(d2, max(d1, d));
			d1 = min(d1, d);
		}
	}
	return vec2(d1, d2);
}

float lines(vec2 p, float t) {
	vec2 d = cells(p, t);
	float e = d.y - d.x;
	float w = line_width + fwidth(e);
	return 1.0 - smoothstep(0.0, w, e);
}

float glowcell(vec2 p, float t) {
	vec2 d = cells(p, t);
	return pow(clamp(d.x * 1.35, 0.0, 1.0), power);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash2(i).x;
	float b = hash2(i + vec2(1.0, 0.0)).x;
	float c = hash2(i + vec2(0.0, 1.0)).x;
	float d = hash2(i + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 2.0 - 1.0;
}

float ridge(vec2 p) {
	float n = vnoise(p) * 0.65 + vnoise(p * 2.1 + 5.3) * 0.35;
	float w = line_width + fwidth(n);
	return 1.0 - smoothstep(0.0, w, abs(n));
}

float pattern_at(vec2 p, float t) {
	if (pattern == 0) {
		return lines(p, t) * 0.65 + lines(p * 1.6 + vec2(3.1, 7.4), t * 1.3) * 0.45;
	} else if (pattern == 1) {
		return glowcell(p, t);
	} else if (pattern == 2) {
		return min(glowcell(p, t), glowcell(p * 1.37 + vec2(3.1, 7.4), -t * 1.21)) * 1.6;
	} else if (pattern == 3) {
		return max(ridge(p * 1.3 + vec2(t * 0.3, 0.0)), ridge(p * 1.1 + vec2(1.7, -t * 0.25)) * 0.7);
	}
	return 0.5 * (glowcell(p, t) + glowcell(p * 1.37 + vec2(3.1, 7.4), -t * 1.21));
}

void fragment() {
	vec2 p = world_pos.xz * cells_per_m;
	// A gentle swirl bends the cell borders into curves, like light through a moving surface.
	p += warp * sin(p.yx * 1.3 + TIME * drift * 0.7);
	float t = TIME * drift;
	float c = pattern_at(p, t);
	// Where the net is finer than a few pixels it would shimmer, so it fades out there.
	float detail = 1.0 - smoothstep(0.25, 0.6, length(fwidth(p)));
	float dist = length(VERTEX);
	float fog = max(1.0 - exp(-fog_density * dist), 1.0 - exp(min(0.0, (world_pos.y - fog_height) * fog_height_density)));
	ALBEDO = tint * (c * strength * detail * (1.0 - fog));
}
