extends TestCase
## The pool's lighting (docs/DECISIONS.md, "Pool lighting pass"): the environment, the key light
## and the passes drawn over the floor. The look itself is judged from renders; these checks keep
## the pieces consistent with each other, with the art direction's rules and with the frame budget.

const ENV_PATH := "res://game/scenes/pool/pool_environment.tres"
const POOL_SCENE := "res://game/scenes/pool/pool.tscn"
const FLOOR_MATERIAL := "res://assets/export/M_PoolFloor.tres"
const FLOOR_RECORD := "res://assets/records/pool_floor.json"
const LAYOUT_PATH := "res://game/data/pool_m1.json"
const HABITAT_MAX_SATURATION := 0.55    ## docs/art/ART_DIRECTION.md section 3 (HSL)
const FLOOR_SCENE := "res://assets/export/pool_floor.glb"
const RIM_LIP_M := Vector2(41.5, 43.0)    ## the dry lip's radii, as test_assets.gd and the generator check it
## The lip's linear albedo luminance at most (PROPOSED). The highlight is cream and never white,
## and living things read first: the old pale stone (0.68) rendered at L* 92 to 95 in Forward+,
## the brightest thing on screen and lighter than the plankton's glow (L* 87); stone at 0.39
## rendered at L* 83. Renders of both renderers are in docs/DECISIONS.md, "Pool lighting pass".
const RIM_MAX_LUMINANCE := 0.40


func _env() -> Environment:
	return load(ENV_PATH)


## The materials drawn over the floor after M_PoolFloor itself, in order.
func _floor_passes() -> Array[Material]:
	var out: Array[Material] = []
	var m: Material = (load(FLOOR_MATERIAL) as Material).next_pass
	while m != null and out.size() < 8:
		out.append(m)
		m = m.next_pass
	return out


func _render_mode(material: Material) -> PackedStringArray:
	var shader := (material as ShaderMaterial).shader if material is ShaderMaterial else null
	if shader == null:
		return PackedStringArray()
	for line in shader.code.split("\n"):
		if line.begins_with("render_mode "):
			return line.trim_prefix("render_mode ").trim_suffix(";").replace(" ", "").split(",")
	return PackedStringArray()


## Every light node in the pool scene, as its type plus the properties the scene sets.
func _lights() -> Array[Dictionary]:
	var state := (load(POOL_SCENE) as PackedScene).get_state()
	var out: Array[Dictionary] = []
	for i in state.get_node_count():
		if ClassDB.is_parent_class(state.get_node_type(i), "Light3D"):
			var props := {"type": String(state.get_node_type(i))}
			for j in state.get_node_property_count(i):
				props[state.get_node_property_name(i, j)] = state.get_node_property_value(i, j)
			out.append(props)
	return out


## Whether `object` has a property named `key`. set() ignores a name the target lacks, so a typo
## in a profile would quietly keep the Forward+ value.
func _has_property(object: Object, key: String) -> bool:
	for p in object.get_property_list():
		if p.name == key:
			return true
	return false


func _has_uniform(material: Material, key: String) -> bool:
	var shader := (material as ShaderMaterial).shader if material is ShaderMaterial else null
	if shader == null:
		return false
	for u in shader.get_shader_uniform_list():
		if u.name == key:
			return true
	return false


## Equal values, allowing for engine properties that store a float in single precision.
func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_FLOAT:
		return is_equal_approx(a, b)
	if typeof(a) == TYPE_VECTOR3 and typeof(b) == TYPE_VECTOR3:
		return (a as Vector3).is_equal_approx(b)
	return typeof(a) == typeof(b) and a == b


func _hsl_saturation(c: Color) -> float:
	var hi := maxf(c.r, maxf(c.g, c.b))
	var lo := minf(c.r, minf(c.g, c.b))
	var l := (hi + lo) / 2.0
	return 0.0 if hi - lo < 1e-6 else (hi - lo) / (1.0 - absf(2.0 * l - 1.0))


func test_the_floor_is_drawn_with_caustic_light_and_then_through_the_water() -> void:
	var passes := _floor_passes()
	var names := PackedStringArray()
	for m in passes:
		names.append(m.resource_name)
	check_eq(names, PackedStringArray(["M_PoolCaustics", "M_PoolWater"]), "the passes after M_PoolFloor")
	if passes.size() != 2:
		return
	check(_render_mode(passes[0]).has("blend_add"), "caustic light adds to the floor")
	check(_render_mode(passes[0]).has("fog_disabled"), "and fades with its own copy of the fog, not the engine's")
	check(_render_mode(passes[1]).has("blend_mul"), "the water multiplies everything drawn before it")
	check(_render_mode(passes[1]).has("unshaded") and _render_mode(passes[1]).has("fog_disabled"), "the water's share is neither lit nor fogged")
	var absorb: Vector3 = (passes[1] as ShaderMaterial).get_shader_parameter("absorb")
	check(absorb.x > absorb.y and absorb.y > absorb.z and absorb.z > 0.0, "the water takes red first, then green, then blue: %s" % absorb)
	# The water's surface sits above the swim plane and below the rim, so the lip stays dry stone.
	var surface: float = (passes[1] as ShaderMaterial).get_shader_parameter("surface_y")
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FLOOR_RECORD))
	var lip: Array = record.get("profile_m", {}).get("lip", [0.0, 0.0])
	check(surface > 0.0 and surface < float(lip[1]), "the water's surface %.2f m is between the swim plane and the lip at %.2f m" % [surface, float(lip[1])])


func test_the_caustic_light_fades_with_the_same_fog_as_the_floor() -> void:
	var env := _env()
	var passes := _floor_passes()
	if passes.is_empty():
		check(false, "the floor has a caustic pass")
		return
	var caustics := passes[0] as ShaderMaterial
	check(env.fog_enabled and env.fog_mode == Environment.FOG_MODE_EXPONENTIAL, "the pool has the exponential fog the caustic shader copies")
	for key in ["fog_density", "fog_height", "fog_height_density"]:
		check_near(float(caustics.get_shader_parameter(key)), float(env.get(key)), 1e-6, "the caustics' %s matches the environment" % key)


func test_glow_stays_off_while_the_water_multiplies_the_floor() -> void:
	# The Compatibility renderer stores a glowing frame at a quarter of its brightness, which a
	# multiply pass cannot undo: the floor turns almost black there. Glow added nothing in Forward+.
	check(not _env().glow_enabled, "no glow in the pool environment")


func test_shadows_go_blue_and_the_key_light_is_warm() -> void:
	var env := _env()
	check_eq(env.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR, "ambient light is a set colour")
	var ambient := env.ambient_light_color
	check(ambient.b > ambient.g and ambient.g > ambient.r, "the ambient light, which is all a shadow gets, is blue: %s" % ambient)
	check(ambient.get_luminance() * env.ambient_light_energy >= 0.2, "and bright enough that shadows are never black")
	check(_hsl_saturation(env.fog_light_color) <= HABITAT_MAX_SATURATION, "the water tint keeps to the habitat saturation")
	var lights := _lights()
	if lights.is_empty():
		check(false, "the pool has a key light")
		return
	var sun: Color = lights[0].get("light_color", Color.WHITE)
	check(sun.r >= sun.g and sun.g > sun.b, "the key light is warm, so living things read warmer than the water: %s" % sun)


func test_the_pool_keeps_one_shadowed_key_light_and_no_costly_screen_effects() -> void:
	var lights := _lights()
	check_eq(lights.size(), 1, "one light")
	if lights.size() == 1:
		check_eq(lights[0].type, "DirectionalLight3D", "a directional key light")
		check(lights[0].get("shadow_enabled", false), "that casts shadows")
		check_eq(lights[0].get("directional_shadow_mode", 2), DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "in two splits")
		var reach := float(lights[0].get("directional_shadow_max_distance", 100.0))
		check_near(reach, 40.0, 1e-6, "out to 40 m")
		# The sharper first split must reach the cell at the widest zoom plus the look-ahead, or
		# its shadow turns to stair steps as the player zooms out.
		var camera: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH)).get("camera", {})
		var cell_m := float(camera.get("zoom_max", 0.0)) + float(camera.get("look_ahead_max", 0.0))
		check(float(lights[0].get("directional_shadow_split_1", 0.1)) * reach >= cell_m, "the first shadow split reaches the cell at %.1f m" % cell_m)
	var env := _env()
	for key in ["ssr_enabled", "ssao_enabled", "ssil_enabled", "sdfgi_enabled", "volumetric_fog_enabled"]:
		check(not env.get(key), "%s is off" % key)


func test_caustic_light_stops_where_the_floor_rises_out_of_the_water() -> void:
	# The rim lip stands above the water; caustic light there lit dry stone up to near-white.
	var passes := _floor_passes()
	if passes.size() != 2:
		check(false, "the floor has a caustic and a water pass")
		return
	var caustic_surface: Variant = (passes[0] as ShaderMaterial).get_shader_parameter("surface_y")
	var water_surface: Variant = (passes[1] as ShaderMaterial).get_shader_parameter("surface_y")
	check(caustic_surface != null and water_surface != null and is_equal_approx(float(caustic_surface), float(water_surface)),
			"the caustics stop at the water's surface: %s, the water's %s" % [caustic_surface, water_surface])


func test_the_dry_rim_lip_is_stone_that_never_reads_near_white() -> void:
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FLOOR_RECORD))
	var stone: Array = record.get("vertex_colors", {}).get("stone", [1.0, 1.0, 1.0])
	var stone_luminance := Color(float(stone[0]), float(stone[1]), float(stone[2])).get_luminance()
	check(stone_luminance <= RIM_MAX_LUMINANCE, "the record's stone has luminance %.2f, at most %.2f" % [stone_luminance, RIM_MAX_LUMINANCE])
	var packed: PackedScene = load(FLOOR_SCENE)
	var node := packed.instantiate() if packed else null
	if node == null:
		check(false, "pool_floor loads")
		return
	var lip := 0
	var brightest := 0.0
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var arrays := (mi as MeshInstance3D).mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i in mini(verts.size(), colors.size()):
			var r := Vector2(verts[i].x, verts[i].z).length()
			if r >= RIM_LIP_M.x and r <= RIM_LIP_M.y:
				lip += 1
				# COLOR_0 holds sRGB; luminance is taken in linear light.
				brightest = maxf(brightest, colors[i].srgb_to_linear().get_luminance())
	node.free()
	check(lip > 0, "the floor has vertices on the rim lip")
	check(brightest <= RIM_MAX_LUMINANCE, "the rim lip's brightest vertex has luminance %.2f, at most %.2f" % [brightest, RIM_MAX_LUMINANCE])


func test_only_the_compatibility_renderer_swaps_in_its_own_light() -> void:
	check(PoolLook.profile_for("forward_plus").is_empty(), "Forward+, the Windows build's renderer, keeps the authored look")
	check(PoolLook.profile_for("mobile").is_empty(), "so does Mobile")
	check(not PoolLook.profile_for(PoolLook.COMPATIBILITY_METHOD).is_empty(), "Compatibility gets its own light")
	check_eq(PoolLook.COMPATIBILITY_METHOD, "gl_compatibility", "the Compatibility renderer's name")
	check_eq(PoolLook.profile_for("gl_compatibility"), PoolLook.COMPATIBILITY, "and it is the Compatibility profile")


func test_the_compatibility_light_names_real_properties_and_keeps_the_art_direction() -> void:
	var profile := PoolLook.COMPATIBILITY
	var scene := (load(POOL_SCENE) as PackedScene).instantiate()
	var sun: DirectionalLight3D = scene.get_node("Sun")
	var env := _env()
	var passes := _floor_passes()
	if passes.size() != 2:
		check(false, "the floor has a caustic and a water pass")
		scene.free()
		return
	check_eq(profile.keys(), ["sun", "environment", "caustics", "water"], "the profile's targets")
	for key in profile.get("sun", {}):
		check(_has_property(sun, key), "the sun has a %s" % key)
	for key in profile.get("environment", {}):
		check(_has_property(env, key), "the environment has a %s" % key)
	for key in profile.get("caustics", {}):
		check(_has_uniform(passes[0], key), "the caustic pass has a %s" % key)
	for key in profile.get("water", {}):
		check(_has_uniform(passes[1], key), "the water pass has a %s" % key)
	# Only strengths change: the warm sun, the blue ambient and the water's tint keep their colours.
	for target in profile.values():
		for key in target:
			check(not String(key).contains("color"), "the profile keeps the authored colours, but sets %s" % key)
	# Compatibility adds the sun's pass to the rest in sRGB, which brightens whatever both reach, so
	# after exposure its sun is never brighter than Forward+'s (the plankton's tops clip otherwise).
	var sun_energy := float(profile.sun.get("light_energy", sun.light_energy))
	var exposure := float(profile.environment.get("tonemap_exposure", env.tonemap_exposure))
	check(sun_energy * exposure > 0.0, "the sun still lights the pool")
	check(sun_energy * exposure <= sun.light_energy * env.tonemap_exposure, "sunlight after exposure %.2f is no brighter than Forward+'s %.2f" % [sun_energy * exposure, sun.light_energy * env.tonemap_exposure])
	var ambient := float(profile.environment.get("ambient_light_energy", env.ambient_light_energy))
	check(env.ambient_light_color.get_luminance() * ambient >= 0.2, "shadows are never black: ambient energy %.2f" % ambient)
	check(float(profile.environment.get("fog_density", env.fog_density)) > 0.0, "distance still fades into the water")
	# Compatibility multiplies the stored sRGB frame, which takes more of each channel than the
	# same factor in linear light, so its water absorbs less per metre for the same colour.
	var absorb: Vector3 = profile.water.get("absorb", Vector3.ZERO)
	var authored: Vector3 = (passes[1] as ShaderMaterial).get_shader_parameter("absorb")
	check(absorb.x > absorb.y and absorb.y > absorb.z and absorb.z > 0.0, "the water still takes red first, then green, then blue: %s" % absorb)
	check(absorb.x < authored.x and absorb.y < authored.y and absorb.z < authored.z, "and less of each than Forward+'s %s" % authored)
	var strength := float(profile.caustics.get("strength", 0.0))
	check(strength > 0.0, "the caustics still show")
	# Compatibility adds the caustic pass after tonemapping it, so its lines ease toward a ceiling
	# instead of clipping to white in the shallows; Forward+ draws them as they are.
	check(float(profile.caustics.get("max_light", 0.0)) > 0.0, "the Compatibility caustics ease toward a ceiling")
	check_eq(float((passes[0] as ShaderMaterial).get_shader_parameter("max_light")), 0.0, "Forward+'s caustics have none")
	scene.free()


func test_the_compatibility_light_goes_on_one_pool_and_leaves_the_shared_resources_alone() -> void:
	var profile := PoolLook.COMPATIBILITY
	var env := _env()
	var passes := _floor_passes()
	# An empty profile, the Forward+ one, leaves a pool exactly as authored.
	var authored := (load(POOL_SCENE) as PackedScene).instantiate()
	PoolLook.apply({}, authored.get_node("Sun"), authored.get_node("WorldEnvironment"), authored.get_node("Floor"))
	check((authored.get_node("WorldEnvironment") as WorldEnvironment).environment == env, "the authored pool keeps the shared environment")
	for mi in (authored.get_node("Floor") as Node).find_children("*", "MeshInstance3D", true, false):
		check((mi as MeshInstance3D).get_surface_override_material(0) == null, "and the floor's own material")
	authored.free()
	var scene := (load(POOL_SCENE) as PackedScene).instantiate()
	var sun: DirectionalLight3D = scene.get_node("Sun")
	var world: WorldEnvironment = scene.get_node("WorldEnvironment")
	var floor_node: Node3D = scene.get_node("Floor")
	PoolLook.apply(profile, sun, world, floor_node)
	for key in profile.sun:
		check(_same(sun.get(key), profile.sun[key]), "the sun's %s is %s" % [key, sun.get(key)])
	check(world.environment != env, "the pool lights its own copy of the environment")
	for key in profile.environment:
		check(_same(world.environment.get(key), profile.environment[key]), "the pool's %s is %s" % [key, world.environment.get(key)])
		check(not _same(env.get(key), profile.environment[key]), "while the shared environment keeps its %s" % key)
	var floors := floor_node.find_children("*", "MeshInstance3D", true, false)
	check(not floors.is_empty(), "the pool has a floor mesh")
	for mi in floors:
		var base := (mi as MeshInstance3D).get_surface_override_material(0)
		var caustics: ShaderMaterial = base.next_pass if base else null
		var water: ShaderMaterial = caustics.next_pass if caustics else null
		if water == null:
			check(false, "the pool's floor has its own caustic and water passes")
			continue
		check(caustics != passes[0] and water != passes[1], "copies of the shared passes")
		for key in profile.caustics:
			check(_same(caustics.get_shader_parameter(key), profile.caustics[key]), "the pool's caustic %s" % key)
		for key in profile.water:
			check(_same(water.get_shader_parameter(key), profile.water[key]), "the pool's water %s" % key)
		for key in ["fog_density", "fog_height", "fog_height_density"]:
			check_near(float(caustics.get_shader_parameter(key)), float(world.environment.get(key)), 1e-6, "the caustics fade with the pool's %s" % key)
	for key in profile.water:
		check(not _same((passes[1] as ShaderMaterial).get_shader_parameter(key), profile.water[key]), "the shared water keeps its %s" % key)
	for key in profile.caustics:
		check(not _same((passes[0] as ShaderMaterial).get_shader_parameter(key), profile.caustics[key]), "the shared caustics keep their %s" % key)
	scene.free()
