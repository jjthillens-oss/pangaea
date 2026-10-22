shader_type spatial;
// The water over the pool floor (assets/records/pool_floor.json): the last pass drawn over it
// (M_PoolFloor, then M_PoolCaustics, then this). It multiplies the drawn floor by how much light
// the water above it lets through. Water takes red first, so the floor turns teal and darker
// with depth while its shadows keep their contrast, which a fog mix would wash out. Only the
// floor is drawn through it: the cell and the food on the swim plane keep their own colours, so
// they read first. The rim above the surface stays dry. Keep glow off in the pool environment:
// the Compatibility renderer stores a glowing frame at a quarter of its brightness, which a
// multiply cannot undo, and the floor turns almost black (tests/test_pool_look.gd).
render_mode blend_mul, unshaded, depth_draw_never, fog_disabled, cull_back;

// How fast each channel fades with the water above the floor, per metre (red, green, blue):
// the floor keeps exp(-absorb * depth) of its light.
uniform vec3 absorb = vec3(0.95, 0.27, 0.14);
// The water's surface in world metres; the swim plane is y = 0.
uniform float surface_y = 0.8;

varying float depth_m;

void vertex() {
	depth_m = max(0.0, surface_y - (MODEL_MATRIX * vec4(VERTEX, 1.0)).y);
}

void fragment() {
	ALBEDO = exp(-absorb * depth_m);
}
