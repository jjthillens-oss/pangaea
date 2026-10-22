shader_type spatial;
// Caustic light on the pool floor (assets/records/pool_floor.json): a next pass of M_PoolFloor
// that adds a slow net of soft bright lines, made here from two layers of moving cells (no
// texture). The pass is lit like the floor, so the sun's shadows mask it. It skips the engine
// fog, which would add the fog colour a second time, and fades with the same fog the floor gets
// instead: the fog_* uniforms copy game/scenes/pool/pool_environment.tres
// (tests/test_pool_look.gd checks this). Caustics come from the water's surface, so they stop
// where the floor rises out of the water and the dry rim lip gets none; surface_y copies
// M_PoolWater's. M_PoolWater, the next pass, then takes the water's share of it like the floor's.
// max_light is for the Compatibility renderer (game/scenes/pool/pool_look.gd), which adds this
// pass after tonemapping it: its bright lines in the shallows clip to white unless they ease
// toward a ceiling.
render_mode blend_add, depth_draw_never, diffuse_lambert, specular_disabled, ambient_light_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.957, 0.918, 0.824);   // cream highlight, never pure white
uniform float strength = 0.13;
uniform float cells_per_m = 0.34;     // how many cells of the net fit in a metre
uniform float drift = 0.35;           // how fast the cells move
uniform float warp = 0.3;             // how far a slow swirl bends the lines
uniform float fog_density = 0.0;
uniform float fog_height = 0.0;
uniform float fog_height_density = 0.0;
uniform float surface_y = 0.8;        // the water's surface in world metres (M_PoolWater)
uniform float max_light = 0.0;        // the light eases toward this and never passes it; 0 leaves it as it is

const float SHARPNESS = 4.0;          // higher keeps the light closer to the cell borders
const float LAYER_SCALE = 1.37;
const vec2 LAYER_OFFSET = vec2(3.1, 7.4);
const float SURFACE_FADE_M = 0.2;     // the light fades out over this much floor below the surface

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Bright near the borders of moving cells, dark at their centres.
float cell_borders(vec2 p, float t) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float nearest = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = 0.5 + 0.38 * sin(t + 6.2831853 * hash2(ip + g));
			nearest = min(nearest, length(g + o - fp));
		}
	}
	return pow(clamp(nearest * 1.35, 0.0, 1.0), SHARPNESS);
}

void fragment() {
	vec2 p = world_pos.xz * cells_per_m;
	float t = TIME * drift;
	p += warp * sin(p.yx * 1.3 + t * 0.7);
	// Light gathers where the borders of two drifting layers meet.
	float c = min(cell_borders(p, t), cell_borders(p * LAYER_SCALE + LAYER_OFFSET, -t * 1.21)) * 1.6;
	// Where the net is finer than a few pixels it would shimmer, so it fades out there.
	float detail = 1.0 - smoothstep(0.25, 0.6, length(fwidth(p)));
	float depth_fog = 1.0 - exp(-fog_density * length(VERTEX));
	float height_fog = 1.0 - exp(min(0.0, (world_pos.y - fog_height) * fog_height_density));
	float fog = max(depth_fog, height_fog);
	float wet = 1.0 - smoothstep(surface_y - SURFACE_FADE_M, surface_y, world_pos.y);
	float light = c * strength * detail * (1.0 - fog) * wet;
	if (max_light > 0.0) {
		light /= 1.0 + light / max_light;
	}
	ALBEDO = tint * light;
}
