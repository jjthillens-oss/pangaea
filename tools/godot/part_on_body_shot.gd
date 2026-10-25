extends SceneTree
## Art review shots of a preset creature (game/data/creature/presets.json) built the way the editor builds it: the
## SpineRig skin, the parts placed by the anchor resolver, and the skin shader in the preset's colour, pattern and
## covering (fur shells included). Run under Xvfb (docs/TOOLCHAIN.md):
##   xvfb-run -a -s "-screen 0 1920x1080x24" GODOT --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 1600x900 --fixed-fps 60 --script res://tools/godot/part_on_body_shot.gd \
##     -- --preset=monkey --out=DIR [--focus=muzzle_primate] [--handles=wing_dragon:H1_Fold:1000,...] [--covering=N]
##     [--shells=N] [--views=gameplay,front,close,side,back] [--prefix=NAME] [--shadow]
## Views: "gameplay" is the creature world's camera distance (2.4 x the body length, 2.6-12 m, fov 50, 16 degrees
## up), from the front three-quarter; "front" the same distance straight on; "close" and "side" frame the --focus
## part (or the head when there is none) from its own side and from +X; "back" is the world's default behind-the-
## creature view. Files are <prefix>_<view>.png (prefix defaults to the preset name). The key light casts no
## shadow unless --shadow (Compatibility overexposes a shadowed light).

const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const SkinCpu := preload("res://game/systems/creature/skin_cpu.gd")
const SpineRig := preload("res://game/scenes/creature/spine_rig.gd")
const Look := preload("res://game/scenes/creature/creature_look.gd")
const BodyField := preload("res://game/domain/creature/body_field.gd")
const AnchorResolver := preload("res://game/domain/creature/anchor_resolver.gd")

const DISTANCE_PER_BODY_M := 2.4    # creature_world.gd CAMERA_DISTANCE_PER_BODY_M
const DISTANCE_MIN_M := 2.6
const DISTANCE_MAX_M := 12.0
const PITCH_DEG := 16.0
const FOV := 50.0

var preset_name := "monkey"
var out_dir := "user://part_on_body"
var prefix := ""
var focus := ""
var handles := {}           # part type -> {key: value 0..1}
var covering := -1
var shells := -1
var views: Array = ["gameplay", "close", "side"]
var shadow := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preset="):
			preset_name = arg.trim_prefix("--preset=")
		elif arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--prefix="):
			prefix = arg.trim_prefix("--prefix=")
		elif arg.begins_with("--focus="):
			focus = arg.trim_prefix("--focus=")
		elif arg.begins_with("--handles="):
			for triple in arg.trim_prefix("--handles=").split(",", false):
				var t := triple.split(":")
				if not handles.has(t[0]):
					handles[t[0]] = {}
				handles[t[0]][t[1]] = float(t[2]) / 1000.0
		elif arg.begins_with("--covering="):
			covering = int(arg.trim_prefix("--covering="))
		elif arg.begins_with("--shells="):
			shells = int(arg.trim_prefix("--shells="))
		elif arg.begins_with("--views="):
			views = Array(arg.trim_prefix("--views=").split(",", false))
		elif arg == "--shadow":
			shadow = true
	if prefix == "":
		prefix = preset_name
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_lights(world)
	var desc: RefCounted = CreatureData.preset_body(preset_name)
	var rules := CreatureData.rules()
	var orientations := CreatureData.part_orientations(CreatureData.part_rules())
	var skin := SkinCpu.build_within(desc, int(rules["gameplay_divisions"]), int(rules["gameplay_triangle_budget"]))
	var box: AABB = desc.bounds_m()
	var rig = SpineRig.new()
	world.add_child(rig)
	rig.position = Vector3(0.0, -box.position.y, 0.0)
	var stored := String(desc.extra.get(Look.SKIN_COLOR_KEY, ""))
	var color := Color.html(stored) if Color.html_is_valid(stored) else Color(0.6, 0.6, 0.6)
	rig.setup(desc, skin, color)
	rig.add_parts(AnchorResolver.resolve_all(desc, BodyField.from_description(desc), orientations), orientations)
	var look := Look.look_of(desc.extra)
	if covering >= 0:
		look[Look.COVERING_KEY] = covering
	var params := Look.shader_params(color, look)
	if shells >= 0:
		params["fur_shells"] = shells
	rig.use_skin_shader(params)
	for e in rig.part_nodes:
		var node: Node3D = e["node"]
		var type := String(node.name).get_slice("_p_", 0)
		if not handles.has(type):
			continue
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			for key in handles[type]:
				var idx: int = (mi as MeshInstance3D).find_blend_shape_by_name(key)
				if idx >= 0:
					(mi as MeshInstance3D).set_blend_shape_value(idx, handles[type][key])
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.45, 0.4)
	gm.roughness = 1.0
	ground.material_override = gm
	world.add_child(ground)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.fov = FOV
	for f in 3:
		await process_frame
	var body_box: AABB = box
	body_box.position.y = 0.0
	var centre := body_box.get_center()
	var dist := clampf(DISTANCE_PER_BODY_M * box.size.z, DISTANCE_MIN_M, DISTANCE_MAX_M)
	var pitch := deg_to_rad(PITCH_DEG)
	var target := _focus_box(rig, focus)
	print("part_on_body_shot %s: body %.2f m long, camera %.2f m, focus %s at %s size %.3f" % [preset_name, box.size.z,
			dist, focus, target.get_center(), target.size.length()])
	for view in views:
		match view:
			"gameplay", "front", "back":
				var yaw: float = {"gameplay": deg_to_rad(215.0), "front": PI, "back": 0.0}[view]
				var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
				cam.look_at_from_position(centre + dir * dist, centre, Vector3.UP)
			"close", "side":
				var c := target.get_center()
				var side := 1.0 if c.x >= -0.01 else -1.0
				var dir := Vector3(0.75 * side, 0.4, -0.75) if view == "close" else Vector3(side, 0.08, 0.0)
				var r := maxf(target.size.length() * 0.5, 0.04)
				cam.look_at_from_position(c + dir.normalized() * (r / tan(deg_to_rad(FOV * 0.5)) * 2.6), c, Vector3.UP)
		for f in 24:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out_dir.path_join("%s_%s.png" % [prefix, view]))
	quit()


## The world bounds of the parts of `type` (all copies), or of the body's front fifth (the head) when there is none.
func _focus_box(rig: Node3D, type: String) -> AABB:
	var out := AABB()
	var first := true
	for e in rig.part_nodes:
		var node: Node3D = e["node"]
		if type == "" or not String(node.name).begins_with(type + "_"):
			continue
		if String(node.name).ends_with("_twin") and not first:
			continue
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			out = b if first else out.merge(b)
			first = false
		break
	if first:
		var aabb: AABB = rig.mesh_instance.global_transform * rig.mesh_instance.get_aabb()
		out = AABB(aabb.position, Vector3(aabb.size.x, aabb.size.y, aabb.size.z * 0.25))
	return out


func _lights(world: Node3D) -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.43, 0.53, 0.59)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.66, 0.7)
	env.environment.ambient_light_energy = 0.55
	world.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 35, 0)
	key.light_energy = 1.2
	key.shadow_enabled = shadow
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -140, 0)
	fill.light_energy = 0.45
	world.add_child(fill)
