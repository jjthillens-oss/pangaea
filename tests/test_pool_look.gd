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
