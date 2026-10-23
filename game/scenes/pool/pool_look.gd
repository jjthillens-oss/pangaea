class_name PoolLook
extends RefCounted
## The pool's light per renderer (docs/DECISIONS.md, "Microscopic world look"). The scene and its
## environment hold one set of values for Forward+ (the Windows build) and Compatibility (OpenGL:
## cloud screenshots, and PCs that fall back from Vulkan). The old look needed its own Compatibility
## values because that renderer draws a shadowed sun as a separate pass added in sRGB, and
## multiplies the floor's water pass into stored sRGB. The microscopic look has neither: the sun
## casts no shadow and the floor and its passes are gone, so both renderers match with no profile
## (tests/test_pool_look.gd and the look probe check it).
##
## The profile stays as an escape hatch should a renderer drift again: it maps each target to the
## properties it overrides, "sun" (the DirectionalLight3D) and "environment" (the WorldEnvironment's
## Environment). An empty profile keeps the authored look.

## RenderingServer.get_current_rendering_method() of the Compatibility renderer. A PC whose
## Vulkan fails falls back to it and reports this name too.
const COMPATIBILITY_METHOD := "gl_compatibility"

## Compatibility overrides: none. Transparent layers still come out about 6 L* darker there than in
## Forward+ (they blend after a per-object tonemap); the look is tuned on Forward+ and accepts that.
const COMPATIBILITY := {}


## The overrides for a renderer, by its RenderingServer.get_current_rendering_method() name.
static func profile_for(method: String) -> Dictionary:
	return COMPATIBILITY if method == COMPATIBILITY_METHOD else {}


## Applies `profile` to a pool's sun and environment. The environment is a shared resource, so the
## pool gets its own copy before anything changes.
static func apply(profile: Dictionary, sun: DirectionalLight3D, world: WorldEnvironment) -> void:
	if profile.is_empty():
		return
	for key in profile.get("sun", {}):
		sun.set(key, profile.sun[key])
	var env: Environment = world.environment.duplicate()
	for key in profile.get("environment", {}):
		env.set(key, profile.environment[key])
	world.environment = env
