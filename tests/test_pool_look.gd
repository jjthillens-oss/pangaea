extends TestCase
## The pool's look: a microscopic world, a deep-blue fluid with depth layers (docs/DECISIONS.md,
## "Microscopic world look"; docs/micro-world-plan.md section 5, C4, in the project files). The
## fluid is the engine's height fog over an opaque, fogged Backdrop 40 m down, with a DepthGlow
## that lights only the fog around the view centre. The look itself is judged from renders by
## tools/godot/look_probe.gd in both renderers; these checks keep the pieces consistent with each
## other, with the art direction's rules and with the frame budget.

const ENV_PATH := "res://game/scenes/pool/pool_environment.tres"
const POOL_SCENE := "res://game/scenes/pool/pool.tscn"
const POOL_DIR := "res://game/scenes/pool"
const RIM_SCENE := "res://assets/export/pool_rim.glb"
const RIM_RECORD := "res://assets/records/pool_rim.json"
const LookProbe := preload("res://tools/godot/look_probe.gd")
const ViewReach := preload("res://tests/view_reach.gd")
const FakeEvents := preload("res://tests/fakes/fake_world_events.gd")
## The widest window the Backdrop is checked against (S1: s1-content.md 6.7), wider than 21:9.
const WIDEST_ASPECT := 2.4
## Height fog at these depths under the swim plane (m) lies in these ranges: none at the plane,
## about half at 10 m, nearly all at 30 m and at the Backdrop (PROPOSED, plan section 3).
const FOG_AT_DEPTH := {0.0: Vector2(0.0, 0.0), 10.0: Vector2(0.45, 0.65), 30.0: Vector2(0.9, 1.0), 40.0: Vector2(0.95, 1.0)}
const FOG_HEIGHT_M := Vector2(-1.2, -0.8)
## The Backdrop lies at least this deep, where the fog is at least 93%.
const BACKDROP_MAX_Y := -30.0
## The fluid's brightest radiance, the fog colour plus the glow's scatter, has at most this
## luminance (the stored colours, as the plan measured them). At 0.15 the fluid behind the cell
## rendered L* 46, darker than the cell by only 7.5; at 0.10 it renders L* 33 to 34.
const FLUID_MAX_LUMINANCE := 0.12
## The fluid's LAB hue band (plan section 6, measured on screen; mood frame h 278). It also carries
## the plan's hue gap from food and threat for the stored colours: anywhere in it the fluid is more
## than 150 degrees of LAB hue from food's #CFE86A (h 114) and at least 83 from the threat pink
## #D9466B (h 11), at its violet end. The plan's 90 from the pink would fail its own fog colour,
## h 281.8, by a degree; the look probe holds the 90 on screen instead (gate fluid_threat_gap: the
## fluid renders at h 273.5, 98 degrees from the pink).
const FLUID_HUE := Vector2(268.0, 288.0)
## ...and its value band on screen (L*), which the start fade matches so it does not flash.
const FLUID_L := Vector2(26.0, 36.0)
const RIM_LIP_M := Vector2(41.5, 43.0)    ## the dry lip's radii, as test_assets.gd checks the rim
## The lip's linear albedo luminance at most (PROPOSED). The highlight is cream and never white,
## and living things read first: the old floor's pale stone (0.68) rendered at L* 92 to 95 in
## Forward+, the brightest thing on screen. The rim's dark stone is far under it.
const RIM_MAX_LUMINANCE := 0.40


func _env() -> Environment:
	return load(ENV_PATH)


func _pool() -> Node:
	return (load(POOL_SCENE) as PackedScene).instantiate()


func _layout_camera() -> Dictionary:
	return PoolLayout.load_from().camera


## The pool camera as the layout configures it, looking at `focus` from `zoom` m. Free it.
func _camera(zoom: float, focus := Vector3.ZERO) -> PoolCamera:
	var camera := PoolCamera.new()
	camera.configure(_layout_camera())
	camera.distance = zoom
	camera.snap_to(focus)
	return camera


## Height fog at `y` as both renderers compute it (fog_process in their scene shaders), with no
## distance fog: none above fog_height, rising toward 1 below it.
func _height_fog(env: Environment, y: float) -> float:
	return 1.0 - exp(minf(0.0, (y - env.fog_height) * env.fog_height_density))


## The render_mode flags of a shader's code, from every render_mode statement, comments removed.
func _render_modes(code: String) -> PackedStringArray:
	var text := RegEx.create_from_string("(?s)/\\*.*?\\*/").sub(code, "", true)
	text = RegEx.create_from_string("//[^\\n]*").sub(text, "", true)
	var out := PackedStringArray()
	for m in RegEx.create_from_string("render_mode\\s+([^;]+);").search_all(text):
		for flag in m.get_string(1).split(","):
			out.append(flag.strip_edges())
	return out


## Every file under `dir` ending in `extension`, recursively.
func _files(dir: String, extension: String, out: PackedStringArray) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(extension):
			out.append(dir + "/" + f)
	for sub in DirAccess.get_directories_at(dir):
		_files(dir + "/" + sub, extension, out)


func _lab_hue(c: Color) -> float:
	return LookProbe.hue(LookProbe.lab(c))


## The fluid's brightest radiance in stored colours: the fog colour, plus the DepthGlow's colour
## times its energy times the fog's sun scatter (the glow is the fog's scatter around the view
## centre, and nothing else).
func _fluid_radiance(env: Environment, glow: DirectionalLight3D) -> Color:
	var scatter := glow.light_color * glow.light_energy * env.fog_sun_scatter
	return Color(env.fog_light_color.r + scatter.r, env.fog_light_color.g + scatter.g, env.fog_light_color.b + scatter.b)


## Whether `object` has a property named `key`. set() ignores a name the target lacks, so a typo
## in a profile would quietly keep the authored value.
func _has_property(object: Object, key: String) -> bool:
	for p in object.get_property_list():
		if p.name == key:
			return true
	return false


## Equal values, allowing for engine properties that store a float in single precision.
func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_FLOAT:
		return is_equal_approx(a, b)
	return typeof(a) == typeof(b) and a == b


# 1 (successor of the floor's water pass, which darkened the floor by depth)
func test_the_fluid_fades_with_depth() -> void:
	var env := _env()
	check(env.fog_enabled and env.fog_mode == Environment.FOG_MODE_EXPONENTIAL, "the pool has the exponential fog both renderers draw")
	check(env.fog_height >= FOG_HEIGHT_M.x and env.fog_height <= FOG_HEIGHT_M.y,
		"the fog starts %.2f m under the swim plane, within %.1f to %.1f m" % [-env.fog_height, -FOG_HEIGHT_M.y, -FOG_HEIGHT_M.x])
	for depth: float in FOG_AT_DEPTH:
		var fog := _height_fog(env, -depth)
		var band: Vector2 = FOG_AT_DEPTH[depth]
		check(fog >= band.x - 1e-6 and fog <= band.y + 1e-6, "%.0f m down the fog is %.3f, within %.2f to %.2f" % [depth, fog, band.x, band.y])


# 2 (new: distance fog turned the coral cell toward the threat pink)
func test_distance_fog_is_off_so_the_cell_keeps_its_coral_at_every_zoom() -> void:
	# Even 0.004 moved the cell from LAB h 43 to 37 in Compatibility, toward the threat's h 11.
	check_eq(_env().fog_density, 0.0, "fog_density")


# 3 (successor of the floor's shelf and corner-reach checks: the Backdrop is the new floor)
func test_the_backdrop_covers_every_view_inside_the_far_plane() -> void:
	var pool := _pool()
	var backdrop := pool.get_node_or_null("Backdrop") as MeshInstance3D
	var camera_node := pool.get_node_or_null("Camera") as Camera3D
	if backdrop == null or camera_node == null:
		check(false, "the pool has a Backdrop mesh and a Camera")
		pool.free()
		return
	check(backdrop.unique_name_in_owner, "the Backdrop is %Backdrop")
	check_eq(backdrop.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the Backdrop casts no shadow")
	var y := backdrop.position.y
	check(y <= BACKDROP_MAX_Y, "the Backdrop lies at y %.1f, at or below %.0f" % [y, BACKDROP_MAX_Y])
	check(backdrop.basis.is_equal_approx(Basis.IDENTITY), "the Backdrop is level and unscaled")
	var plane := backdrop.mesh as PlaneMesh
	check(plane != null, "the Backdrop is a plane")
	var half := minf(plane.size.x, plane.size.y) / 2.0 if plane else 0.0
	# The Backdrop sits under the camera's focus wherever it is (S1: the pool's _follow_camera, so it
	# covers the endless sea too), so the view is measured from the focus: the top corners at the
	# widest zoom, on the widest window, land within the plane's half-size.
	var camera := PoolLayout.load_from().camera
	for aspect in [ViewReach.SCREEN_ASPECT, ViewReach.WIDE_ASPECT, WIDEST_ASPECT]:
		var reach := ViewReach.corner_reach(camera, float(camera.zoom_max), y, aspect)
		check(half >= reach, "at the widest zoom (aspect %.2f) the view reaches r %.1f from the focus at y %.0f; the Backdrop covers r %.1f" % [aspect, reach, y, half])
		var slant := ViewReach.corner_slant(camera, float(camera.zoom_max), y, aspect)
		check(slant < camera_node.far, "and its farthest point (%.1f m away) is inside the camera's far plane at %.0f m" % [slant, camera_node.far])
	check(PoolCamera.FAR_M == camera_node.far, "the pool camera keeps the scene's far plane")
	# It is the fluid's floor: opaque, unshaded and fogged by the engine, so decor fades into it.
	var material := plane.material as ShaderMaterial if plane else null
	var code := material.shader.code if material and material.shader else ""
	var modes := _render_modes(code)
	check(modes.has("unshaded"), "the Backdrop is unshaded: %s" % [modes])
	check(not modes.has("fog_disabled"), "and keeps the engine's fog")
	for flag in modes:
		check(not flag.begins_with("blend_") or flag == "blend_mix", "and is opaque, not %s" % flag)
	check(not code.is_empty() and not code.contains("ALPHA"), "it writes no ALPHA, so it stays opaque")
	pool.free()


func test_the_backdrop_centres_on_the_focus() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.pool_session(), FakeEvents.Straight.new(Vector2(1.0, -1.0).normalized()))
	for i in 90:
		FakeEvents.frame(pool)
	var focus := pool.camera.focus
	check(Vector2(focus.x, focus.z).distance_to(pool.session.layout.spawn) > 1.0,
		"the camera has followed the cell away from the spawn (focus %s)" % focus)
	check(is_equal_approx(pool.backdrop.position.x, focus.x) and is_equal_approx(pool.backdrop.position.z, focus.z),
		"the Backdrop's x and z are the focus's: %s, %s" % [pool.backdrop.position, focus])
	# Far out in the endless sea, after a teleport's snap.
	pool.camera.snap_to(Vector3(5000.0, 0.0, -3000.0))
	pool._process(FakeEvents.DT)
	check(is_equal_approx(pool.backdrop.position.x, pool.camera.focus.x) and is_equal_approx(pool.backdrop.position.z, pool.camera.focus.z),
		"and it follows the focus to %s: %s" % [pool.camera.focus, pool.backdrop.position])
	pool.free()


func test_the_corner_reach_matches_the_camera_geometry() -> void:
	# Looking straight down with a 90 degree FOV from 10 m, the top corners land 10 m up and
	# 10 x 16/9 m across from the focus, 10 x sqrt(1 + 1 + (16/9)^2) m from the eye.
	var down := {"pitch_deg": 90.0, "fov_deg": 90.0}
	var reach := ViewReach.corner_reach(down, 10.0, 0.0)
	check_near(reach, Vector2(10.0, 10.0 * ViewReach.SCREEN_ASPECT).length(), 1e-3, "straight-down reach")
	check_near(ViewReach.corner_slant(down, 10.0, 0.0), Vector3(10.0, 10.0, 10.0 * ViewReach.SCREEN_ASPECT).length(), 1e-3, "straight-down slant")
	check_near(ViewReach.corner_reach(down, 10.0, 5.0), reach / 2.0, 1e-3, "a plane halfway up halves it")
	check(ViewReach.corner_reach(down, 10.0, 0.0, ViewReach.WIDE_ASPECT) > reach, "a wider window reaches further")
	check(ViewReach.corner_reach({"pitch_deg": 10.0, "fov_deg": 45.0}, 10.0, 0.0) == INF, "a corner above the horizon never lands")


# 4 (new: the microscope's lit field)
func test_the_depth_glow_lights_only_the_fog_along_the_view_axis() -> void:
	var pool := _pool()
	var glow := pool.get_node_or_null("DepthGlow") as DirectionalLight3D
	if glow == null:
		check(false, "the pool has a DepthGlow directional light")
		pool.free()
		return
	check_eq(glow.light_cull_mask, 0, "it lights no layer")
	check(not glow.shadow_enabled, "it casts no shadow")
	check_eq(glow.sky_mode, DirectionalLight3D.SKY_MODE_LIGHT_ONLY, "sky mode")
	check(glow.light_color.b > glow.light_color.g and glow.light_color.g > glow.light_color.r, "its light is blue: %s" % glow.light_color)
	# The fog scatters a light around the direction it comes from, its +Z: the view axis puts the
	# lit field at the centre of every frame. The camera never turns, so the glow never moves.
	var axis := glow.transform.basis.z.normalized()
	for zoom in [10.0, 14.0, 20.0]:
		var camera := _camera(zoom, Vector3(12.0, 0.0, -30.0))
		var forward := -camera.transform.basis.z
		check(axis.dot(forward) >= 0.99, "the glow's axis %s follows the camera's view %s at zoom %d (dot %.4f)" % [axis, forward, zoom, axis.dot(forward)])
		camera.free()
	pool.free()


# 5 (successor of "one shadowed key light and no costly screen effects")
func test_one_warm_key_light_without_shadows_and_nothing_costly() -> void:
	var pool := _pool()
	var lit := []
	for light in pool.find_children("*", "Light3D", true, false):
		if (light as Light3D).light_cull_mask != 0:
			lit.append(light)
	check_eq(lit.size(), 1, "lights that light anything")
	if lit.size() == 1:
		var sun := lit[0] as DirectionalLight3D
		check(sun != null and sun.name == "Sun", "the key light is the directional Sun")
		check(sun != null and not sun.shadow_enabled, "it casts no shadow: nothing under the swim plane catches one, and a shadowed sun is a separate pass in Compatibility")
		var c := sun.light_color if sun else Color.BLACK
		check(c.r >= c.g and c.g > c.b, "it is warm, so living things read warmer than the fluid: %s" % c)
	var env := _env()
	for key in ["glow_enabled", "ssr_enabled", "ssao_enabled", "ssil_enabled", "sdfgi_enabled", "volumetric_fog_enabled"]:
		check(not env.get(key), "%s is off" % key)
	check_eq(env.fog_aerial_perspective, 0.0, "fog_aerial_perspective (compiled out of Compatibility)")
	check_eq(env.fog_sky_affect, 0.0, "fog_sky_affect")
	var camera := pool.get_node_or_null("Camera") as Camera3D
	check(camera != null and camera.attributes == null, "the camera has no attributes (depth of field, exposure)")
	var world := pool.get_node_or_null("WorldEnvironment") as WorldEnvironment
	check(world != null and world.camera_attributes == null, "nor does the world environment")
	pool.free()


# 6 (successor of "shadows go blue and the key light is warm")
func test_shadows_go_blue_never_black() -> void:
	var env := _env()
	check_eq(env.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR, "ambient light is a set colour")
	var ambient := env.ambient_light_color
	check(ambient.b > ambient.g and ambient.g > ambient.r, "the ambient light, which is all a shadow gets, is blue: %s" % ambient)
	check(ambient.get_luminance() * env.ambient_light_energy >= 0.2, "and bright enough that shadows are never black: %.2f" % [ambient.get_luminance() * env.ambient_light_energy])


# 7 (successor of the habitat saturation cap, which the owner-approved fluid exceeds)
func test_the_fluid_keeps_to_its_value_and_hue_rule() -> void:
	var env := _env()
	var pool := _pool()
	var glow := pool.get_node_or_null("DepthGlow") as DirectionalLight3D
	if glow == null:
		check(false, "the pool has a DepthGlow")
		pool.free()
		return
	var fluid := _fluid_radiance(env, glow)
	check(fluid.get_luminance() <= FLUID_MAX_LUMINANCE, "the fluid's brightest radiance %s has luminance %.3f, at most %.2f" % [fluid, fluid.get_luminance(), FLUID_MAX_LUMINANCE])
	for named: Array in [["the fog colour", env.fog_light_color], ["the fluid's brightest radiance", fluid]]:
		var c: Color = named[1]
		var h := _lab_hue(c)
		check(c.b > c.g and c.g > c.r, "%s is blue: %s" % [named[0], c])
		check(h >= FLUID_HUE.x and h <= FLUID_HUE.y, "%s has LAB hue %.1f, in the fluid's band %.0f to %.0f, clear of food and the threat pink" % [named[0], h, FLUID_HUE.x, FLUID_HUE.y])
	# Shown only should the Backdrop go missing.
	var bg := env.background_color
	check(bg.b > bg.g and bg.g > bg.r, "the background is blue: %s" % bg)
	# The fog colours sit about 3 times under their on-screen values because of the tonemap, so any
	# change to it shifts the whole fluid.
	check_eq(env.tonemap_mode, Environment.TONE_MAPPER_FILMIC, "the Filmic tonemap")
	check_eq(env.tonemap_white, 1.0, "tonemap_white")
	check_eq(env.tonemap_exposure, 1.0, "tonemap_exposure")
	pool.free()


# 8 (successor of the caustics' own fog copy: additive light must not take the engine's fog)
func test_every_additive_pool_shader_takes_no_fog() -> void:
	# Additive plus engine fog adds the fog colour over the whole quad: a bright hard square. The
	# walk takes in every folder under the pool's, so art's ambience/ is checked once it lands.
	var shaders := PackedStringArray()
	_files(POOL_DIR, ".gdshader", shaders)
	check(shaders.has(POOL_DIR + "/backdrop.gdshader"), "the walk finds the pool's shaders: %s" % [shaders])
	for path in shaders:
		var modes := _render_modes(FileAccess.get_file_as_string(path))
		if modes.has("blend_add"):
			check(modes.has("fog_disabled"), "%s adds light, so it declares fog_disabled: %s" % [path, modes])


# 9 (successor of the Compatibility profile tests)
func test_both_renderers_take_one_set_of_values_and_the_escape_hatch_works_on_copies() -> void:
	check_eq(PoolLook.COMPATIBILITY_METHOD, "gl_compatibility", "the Compatibility renderer's name")
	for method in ["forward_plus", "gl_compatibility", "mobile"]:
		check(PoolLook.profile_for(method).is_empty(), "%s keeps the authored look" % method)
	# An empty profile leaves a pool exactly as authored.
	var env := _env()
	var authored := _pool()
	var sun_energy := (authored.get_node("Sun") as DirectionalLight3D).light_energy
	PoolLook.apply({}, authored.get_node("Sun"), authored.get_node("WorldEnvironment"))
	check((authored.get_node("WorldEnvironment") as WorldEnvironment).environment == env, "the authored pool keeps the shared environment")
	check_eq((authored.get_node("Sun") as DirectionalLight3D).light_energy, sun_energy, "and its sun")
	authored.free()
	# Should a renderer drift again, a profile goes on that pool's own copy of the environment.
	var profile := {"sun": {"light_energy": 1.2}, "environment": {"fog_height_density": 0.08, "ambient_light_energy": 0.9}}
	var pool := _pool()
	var sun: DirectionalLight3D = pool.get_node("Sun")
	var world: WorldEnvironment = pool.get_node("WorldEnvironment")
	for key in profile.sun:
		check(_has_property(sun, key), "the sun has a %s" % key)
	for key in profile.environment:
		check(_has_property(env, key), "the environment has a %s" % key)
	PoolLook.apply(profile, sun, world)
	for key in profile.sun:
		check(_same(sun.get(key), profile.sun[key]), "the sun's %s is %s" % [key, sun.get(key)])
	check(world.environment != env, "the pool lights its own copy of the environment")
	for key in profile.environment:
		check(_same(world.environment.get(key), profile.environment[key]), "the pool's %s is %s" % [key, world.environment.get(key)])
		check(not _same(env.get(key), profile.environment[key]), "while the shared environment keeps its %s" % key)
	pool.free()


# 10 (successor of "the dry rim lip is stone that never reads near white", now on pool_rim)
func test_the_rim_lip_is_stone_that_never_reads_near_white() -> void:
	var pool := _pool()
	var rim := pool.get_node_or_null("Rim") as Node3D
	check(rim != null and rim.unique_name_in_owner, "the pool has %Rim")
	check(rim != null and rim.scene_file_path == RIM_SCENE, "instanced from %s, got %s" % [RIM_SCENE, rim.scene_file_path if rim else ""])
	pool.free()
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RIM_RECORD))
	var stone: Array = record.get("vertex_colors", {}).get("stone", [1.0, 1.0, 1.0])
	var stone_luminance := Color(float(stone[0]), float(stone[1]), float(stone[2])).get_luminance()
	check(stone_luminance <= RIM_MAX_LUMINANCE, "the record's stone has luminance %.2f, at most %.2f" % [stone_luminance, RIM_MAX_LUMINANCE])
	var node := (load(RIM_SCENE) as PackedScene).instantiate()
	var lip := 0
	var brightest := 0.0
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s) as BaseMaterial3D
			var arrays := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			for i in verts.size():
				var r := Vector2(verts[i].x, verts[i].z).length()
				if r < RIM_LIP_M.x or r > RIM_LIP_M.y:
					continue
				lip += 1
				# The albedo as the material draws it, in linear light.
				var albedo := mat.albedo_color.srgb_to_linear() if mat else Color.WHITE
				if mat and mat.vertex_color_use_as_albedo and i < colors.size():
					albedo *= colors[i].srgb_to_linear() if mat.vertex_color_is_srgb else colors[i]
				brightest = maxf(brightest, albedo.get_luminance())
	node.free()
	check(lip > 0, "the rim has vertices on its lip")
	check(brightest <= RIM_MAX_LUMINANCE, "the lip's brightest albedo has luminance %.3f, at most %.2f" % [brightest, RIM_MAX_LUMINANCE])


# 11 (new: the start fade was the old teal water)
func test_the_start_fade_is_the_fluids_mid_tone() -> void:
	var pool := _pool()
	var fade := pool.get_node_or_null("UI/Fade") as ColorRect
	if fade == null:
		check(false, "the pool has UI/Fade")
		pool.free()
		return
	var c := fade.color
	var lab := LookProbe.lab(c)
	check_eq(c.a, 1.0, "the fade starts opaque")
	check(c.b > c.g and c.g > c.r, "the fade is blue: %s" % c)
	check(LookProbe.hue(lab) >= FLUID_HUE.x and LookProbe.hue(lab) <= FLUID_HUE.y, "its LAB hue %.1f is in the fluid's band" % LookProbe.hue(lab))
	check(lab.x >= FLUID_L.x and lab.x <= FLUID_L.y, "its L* %.1f is the fluid's on screen, %.0f to %.0f, so the fade-in does not flash" % [lab.x, FLUID_L.x, FLUID_L.y])
	pool.free()
