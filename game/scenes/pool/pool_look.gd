class_name PoolLook
extends RefCounted
## The pool's light per renderer (docs/DECISIONS.md, "Pool lighting pass"). The scene, its
## environment and the floor's passes are tuned for Forward+, the renderer of the Windows build.
## The Compatibility renderer (OpenGL: cloud screenshots, and PCs that fall back from Vulkan)
## tonemaps each pass on its own and adds the shadowed sun to the rest in sRGB, so the same values
## come out far brighter there: the lit floor turns swimming-pool cyan, and plankton and the rim
## clip to white. It gets its own values instead, chosen by matching renders of both
## (tests/test_pool_look.gd checks them against the art direction).
##
## A profile maps each target to the properties it overrides: "sun" (the DirectionalLight3D),
## "environment" (the WorldEnvironment's Environment), and "caustics" and "water" (the shader
## parameters of the floor's two passes). An empty profile keeps the authored look.

## RenderingServer.get_current_rendering_method() of the Compatibility renderer. A PC whose
## Vulkan fails falls back to it and reports this name too.
const COMPATIBILITY_METHOD := "gl_compatibility"

## Compatibility values (PROPOSED tuning, matched to Forward+ renders of the same shots; the renders
## and numbers are in DECISIONS). Everything not listed keeps its Forward+ value, including the
## light's, the ambient's and the fog's colours.
##   - A dimmer sun (0.9 after exposure, Forward+ 1.3): its pass is added to the rest in sRGB,
##     which brightens whatever both reach, and at Forward+'s strength the plankton's sunlit tops
##     clipped to white. More ambient keeps the cell, which the sun now lights less, as distinct
##     from the floor as before.
##   - A lower exposure tames the plankton's glow and the fog, and a white point of 2 keeps each
##     pass's brightest values further from white, so their sum clips less.
##   - Far less distance fog, which tints the whole frame teal there; more height fog, which gives
##     the deep floor's shadows their blue.
##   - The caustics need a stronger light to show through that height fog in deep water, and a
##     ceiling (max_light) so their brightest lines in the shallows never clip to white.
##   - The water multiplies the stored sRGB frame, which takes more of each channel than the same
##     factor in linear light, so it absorbs less per metre (fitted to Forward+'s floor colours;
##     absorbing less still only greys the floor).
const COMPATIBILITY := {
	"sun": {"light_energy": 1.5},
	"environment": {
		"tonemap_exposure": 0.6,
		"tonemap_white": 2.0,
		"ambient_light_energy": 3.0,
		"fog_density": 0.0015,
		"fog_height_density": 1.25,
	},
	"caustics": {"strength": 2.0, "max_light": 0.2},
	"water": {"absorb": Vector3(0.31, 0.077, 0.012)},
}

## The caustic pass fades with its own copy of the environment's fog (pool_caustics.gdshader).
const CAUSTIC_FOG_KEYS: Array[String] = ["fog_density", "fog_height", "fog_height_density"]


## The overrides for a renderer, by its RenderingServer.get_current_rendering_method() name.
static func profile_for(method: String) -> Dictionary:
	return COMPATIBILITY if method == COMPATIBILITY_METHOD else {}


## Applies `profile` to a pool's sun, environment and floor. The environment and the floor's
## materials are shared resources, so the pool gets its own copies before anything changes.
static func apply(profile: Dictionary, sun: DirectionalLight3D, world: WorldEnvironment, floor_node: Node3D) -> void:
	if profile.is_empty():
		return
	for key in profile.get("sun", {}):
		sun.set(key, profile.sun[key])
	var env: Environment = world.environment.duplicate()
	for key in profile.get("environment", {}):
		env.set(key, profile.environment[key])
	world.environment = env
	for mi in floor_node.find_children("*", "MeshInstance3D", true, false):
		var base := (mi as MeshInstance3D).get_active_material(0)
		if base == null or not base.next_pass is ShaderMaterial or not base.next_pass.next_pass is ShaderMaterial:
			push_error("The pool floor has no caustic and water passes to apply the look to.")
			continue
		base = base.duplicate()
		var caustics: ShaderMaterial = base.next_pass.duplicate()
		var water: ShaderMaterial = caustics.next_pass.duplicate()
		base.next_pass = caustics
		caustics.next_pass = water
		for key in CAUSTIC_FOG_KEYS:
			caustics.set_shader_parameter(key, env.get(key))
		for key in profile.get("caustics", {}):
			caustics.set_shader_parameter(key, profile.caustics[key])
		for key in profile.get("water", {}):
			water.set_shader_parameter(key, profile.water[key])
		(mi as MeshInstance3D).set_surface_override_material(0, base)
