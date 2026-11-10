extends SceneTree
## Screenshots of preset creatures standing at rest with their parts on, for art review of the part catalogue.
##   xvfb-run -a -s "-screen 0 1280x720x24" GODOT --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 1280x720 --script res://tools/creature_shots.gd -- \
##     --out=DIR [--presets=raptor,boar] [--views=side,q,face]
## Writes <preset>_<view>.png: side (profile), q (three-quarter) and face (close on the head end).

const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const SkinCpu := preload("res://game/systems/creature/skin_cpu.gd")
const SpineRig := preload("res://game/scenes/creature/spine_rig.gd")
const AnchorResolver := preload("res://game/domain/creature/anchor_resolver.gd")
const BodyField := preload("res://game/domain/creature/body_field.gd")
const Look := preload("res://game/scenes/creature/creature_look.gd")

var out_dir := "user://creature_shots"
var presets := PackedStringArray()
var views := PackedStringArray(["side", "q", "face"])


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--presets="):
			presets = PackedStringArray(arg.trim_prefix("--presets=").split(","))
		elif arg.begins_with("--views="):
			views = PackedStringArray(arg.trim_prefix("--views=").split(","))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.7, 0.74)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.74, 0.8)
	env.environment.ambient_light_energy = 0.7
	world.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 150, 0)
	key.light_energy = 1.2
	world.add_child(key)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 30
	var part_rules := CreatureData.part_rules()
	var orientations := CreatureData.part_orientations(part_rules)
	var body_rules := CreatureData.rules()
	if presets.is_empty():
		presets = CreatureData.preset_names()
	for preset_name in presets:
		var body = CreatureData.preset_body(preset_name)
		var color := Color.html(String(body.extra.get("skin_color", "#5AA0D8")))
		var rig = SpineRig.new()
		world.add_child(rig)
		rig.setup(body, SkinCpu.build(body, body.preview_divisions(body_rules)), color)
		rig.add_parts(AnchorResolver.resolve_all(body, BodyField.from_description(body), orientations), orientations)
		rig.use_skin_shader(Look.shader_params(color, Look.look_of(body.extra)))
		var box: AABB = body.bounds_m()
		var c := box.get_center()
		var r := box.size.length()
		var head: Vector3 = body.position_m(0)
		for view in views:
			match view:
				"side":
					cam.look_at_from_position(c + Vector3(1.0, 0.12, 0.0).normalized() * r * 1.9, c, Vector3.UP)
				"q":
					cam.look_at_from_position(c + Vector3(0.75, 0.35, -0.8).normalized() * r * 1.9, c, Vector3.UP)
				"face":
					cam.look_at_from_position(head + Vector3(0.6, 0.2, -1.0).normalized() * r * 0.75, head, Vector3.UP)
			for f in 6:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out_dir.path_join("%s_%s.png" % [preset_name, view]))
		world.remove_child(rig)
		rig.free()
	quit()
