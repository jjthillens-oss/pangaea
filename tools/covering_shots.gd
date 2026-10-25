extends SceneTree
## Screenshots of one creature body in each skin covering (creature_skin.gdshader `covering`), for art review.
##   xvfb-run -a -s "-screen 0 1280x720x24" GODOT --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 1280x720 --script res://tools/covering_shots.gd -- --out=DIR

const Fixtures := preload("res://tests/creature_fixtures.gd")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const SkinCpu := preload("res://game/systems/creature/skin_cpu.gd")
const SpineRig := preload("res://game/scenes/creature/spine_rig.gd")

const COVERINGS := ["default", "fur", "scales", "smooth_wet"]
var out_dir := "user://covering_shots"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.33, 0.35)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.57, 0.6)
	env.environment.ambient_light_energy = 0.5
	world.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 40, 0)
	key.light_energy = 1.3
	world.add_child(key)
	var graze := DirectionalLight3D.new()
	graze.rotation_degrees = Vector3(-8, -120, 0)
	graze.light_energy = 0.6
	world.add_child(graze)
	var rules := CreatureData.rules()
	var desc = Fixtures.body("s1_quadruped")
	var skin := SkinCpu.build_within(desc, int(rules["gameplay_divisions"]), int(rules["gameplay_triangle_budget"]))
	var rig = SpineRig.new()
	world.add_child(rig)
	rig.setup(desc, skin, Color.WHITE)
	var aabb: AABB = rig.mesh_instance.get_aabb()
	var c := aabb.get_center()
	var r := aabb.size.length()
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 35
	for i in COVERINGS.size():
		rig.use_skin_shader({"covering": i, "base_pattern": 0, "coat_pattern": 1, "detail_pattern": 0})
		for view in [["side", Vector3(1.0, 0.45, -0.2), 1.25], ["close", Vector3(0.7, 0.35, 0.5), 0.45]]:
			var dir: Vector3 = (view[1] as Vector3).normalized()
			cam.look_at_from_position(c + dir * r * float(view[2]), c, Vector3.UP)
			for f in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out_dir.path_join("%d_%s_%s.png" % [i, COVERINGS[i], view[0]]))
	quit()
