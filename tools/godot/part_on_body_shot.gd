extends SceneTree
## Art review shots of a preset creature (game/data/creature/presets.json) in the creature editor scene
## (game/scenes/creature/creature_editor.tscn, driven through setup() like its tests): the SpineRig skin, the parts
## placed by the anchor resolver, and the skin shader in the preset's colour, pattern and covering (fur shells
## included), in the editor's own room and lights. --scene=bare builds the same body on a plain ground plane under
## neutral lights instead. Run under Xvfb (docs/TOOLCHAIN.md):
##   xvfb-run -a -s "-screen 0 1920x1080x24" GODOT --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 1600x900 --fixed-fps 60 --script res://tools/godot/part_on_body_shot.gd \
##     -- --preset=monkey --out=DIR [--focus=muzzle_primate] [--handles=wing_dragon:H1_Fold:1000,...] [--covering=N]
##     [--shells=N] [--views=editor,gameplay,front,close,side,back] [--prefix=NAME] [--shadow] [--scene=bare]
##     [--no-floor] [--zoom=F] [--mark=eye_bulge:M_EyeBulgeLid:#ff0000,...] [--param=fur_shag:0.6,...]
## Views: "editor" is the editor's own camera with its HUD and handle dots (editor scene only); "gameplay" is the
## creature world's camera distance (2.4 x the body length, 2.6-12 m, fov 50, 16 degrees up) from the front
## three-quarter; "front" the same distance straight on; "back" the world's default view from behind; "close" and
## "side" frame the --focus part (or the head when there is none) from its own side and from +X, --zoom times
## closer. --no-floor hides the editor's floor pad in the views other than "editor" (the frog feet sit under it).
## Files are <prefix>_<view>.png (prefix defaults to the preset name). In the bare scene the key light casts no
## shadow unless --shadow (Compatibility overexposes a shadowed light). --mark (diagnostic) paints every surface of
## that part type whose material has that name a flat unlit colour, to find which faces make a highlight or a band.
## --param sets skin shader uniforms (float values) on the body and every fur shell pass (SpineRig.set_skin_param),
## to compare settings without editing the shader. Each view prints "part_on_body <prefix> <view>: X ms/frame".

const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const SkinCpu := preload("res://game/systems/creature/skin_cpu.gd")
const SpineRig := preload("res://game/scenes/creature/spine_rig.gd")
const Look := preload("res://game/scenes/creature/creature_look.gd")
const BodyField := preload("res://game/domain/creature/body_field.gd")
const AnchorResolver := preload("res://game/domain/creature/anchor_resolver.gd")
const EDITOR_SCENE := "res://game/scenes/creature/creature_editor.tscn"

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
var views: Array = ["editor", "gameplay", "close", "side"]
var shadow := false
var bare := false
var no_floor := false
var zoom := 1.0
var marks := []             # [part type, material name, colour]
var skin_params := {}       # --param: skin shader uniform -> float


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
		elif arg == "--scene=bare":
			bare = true
		elif arg == "--no-floor":
			no_floor = true
		elif arg.begins_with("--zoom="):
			zoom = float(arg.trim_prefix("--zoom="))
		elif arg.begins_with("--param="):
			for pair in arg.trim_prefix("--param=").split(",", false):
				skin_params[pair.get_slice(":", 0)] = float(pair.get_slice(":", 1))
		elif arg.begins_with("--mark="):
			for triple in arg.trim_prefix("--mark=").split(",", false):
				var t := triple.split(":")
				marks.append([t[0], t[1], Color(t[2])])
	if prefix == "":
		prefix = preset_name
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var desc: RefCounted = CreatureData.preset_body(preset_name)
	var box: AABB = desc.bounds_m()
	var rig: Node3D
	var cam: Camera3D
	var ui: CanvasItem = null
	var handles_node: Node3D = null
	var editor_cam: Camera3D = null
	var floor_node: Node3D = null
	if bare:
		var world := Node3D.new()
		root.add_child(world)
		_lights(world)
		rig = _bare_rig(world, desc)
		_ground(world)
		cam = Camera3D.new()
		world.add_child(cam)
		cam.current = true
	else:
		var ed: Node = load(EDITOR_SCENE).instantiate()
		ed.threaded = false
		root.add_child(ed)
		await process_frame
		ed.setup(desc, 1000)
		if covering >= 0:
			ed.set_skin_covering(covering)
		rig = ed.rig
		editor_cam = ed.camera
		# The editor places its own camera every frame, so the other views use a camera of their own.
		cam = Camera3D.new()
		ed.add_child(cam)
		ui = ed.get_node("UI/Hud")
		handles_node = ed.handle_root
		floor_node = ed.floor_disc
		if shells >= 0:
			var params: Dictionary = ed._shader_params()
			params["fur_shells"] = shells
			rig.use_skin_shader(params)
	for k in skin_params:
		rig.set_skin_param(k, skin_params[k])
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
	for m in marks:
		_mark(rig, m[0], m[1], m[2])
	for f in 3:
		await process_frame
	cam.fov = FOV
	var body_box: AABB = rig.mesh_instance.global_transform * rig.mesh_instance.get_aabb()
	var centre := body_box.get_center()
	var dist := clampf(DISTANCE_PER_BODY_M * box.size.z, DISTANCE_MIN_M, DISTANCE_MAX_M)
	var pitch := deg_to_rad(PITCH_DEG)
	var target := _focus_box(rig, focus)
	print("part_on_body_shot %s: body %.2f m long, camera %.2f m, focus %s at %s size %.3f" % [preset_name, box.size.z,
			dist, focus, target.get_center(), target.size.length()])
	for view in views:
		if ui:
			ui.visible = view == "editor"
			handles_node.visible = view == "editor"
			floor_node.visible = view == "editor" or not no_floor
		match view:
			"editor":
				editor_cam.current = true
			"gameplay", "front", "back":
				cam.current = true
				var yaw: float = {"gameplay": deg_to_rad(215.0), "front": PI, "back": 0.0}[view]
				var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
				cam.look_at_from_position(centre + dir * dist, centre, Vector3.UP)
			"close", "side":
				cam.current = true
				var c := target.get_center()
				var side := 1.0 if c.x >= -0.01 else -1.0
				var dir := Vector3(0.75 * side, 0.4, -0.75) if view == "close" else Vector3(side, 0.08, 0.0)
				var r := maxf(target.size.length() * 0.5, 0.04)
				cam.look_at_from_position(c + dir.normalized() * (r / tan(deg_to_rad(FOV * 0.5)) * 1.2 + 0.15) / zoom, c, Vector3.UP)
		for f in 14:
			await process_frame
		var t0 := Time.get_ticks_usec()
		for f in 10:
			await RenderingServer.frame_post_draw
		print("part_on_body %s %s: %.1f ms/frame" % [prefix, view, (Time.get_ticks_usec() - t0) / 10000.0])
		root.get_texture().get_image().save_png(out_dir.path_join("%s_%s.png" % [prefix, view]))
	quit()


func _mark(rig: Node3D, type: String, material_name: String, colour: Color) -> void:
	var flat := StandardMaterial3D.new()
	flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flat.albedo_color = colour
	flat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var hits := 0
	for e in rig.part_nodes:
		var node: Node3D = e["node"]
		if not String(node.name).begins_with(type + "_"):
			continue
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			for si in mesh.get_surface_count():
				var mat := mesh.surface_get_material(si)
				var surface_name := (mesh as ArrayMesh).surface_get_name(si) if mesh is ArrayMesh else ""
				if (mat and mat.resource_name == material_name) or surface_name == material_name:
					(mi as MeshInstance3D).set_surface_override_material(si, flat)
					hits += 1
	print("part_on_body_shot mark %s %s: %d surfaces" % [type, material_name, hits])


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
		# The rest vertices (a mesh's AABB also spans its blend shapes, which can be far bigger than the part).
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var t: Transform3D = (mi as MeshInstance3D).global_transform
			for si in (mi as MeshInstance3D).mesh.get_surface_count():
				for v: Vector3 in (mi as MeshInstance3D).mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
					out = AABB(t * v, Vector3.ZERO) if first else out.expand(t * v)
					first = false
		break
	if first:
		var aabb: AABB = rig.mesh_instance.global_transform * rig.mesh_instance.get_aabb()
		out = AABB(aabb.position, Vector3(aabb.size.x, aabb.size.y, aabb.size.z * 0.25))
	return out


## The body as the editor builds it (SpineRig, anchored parts, skin shader), standing on y = 0.
func _bare_rig(world: Node3D, desc: RefCounted) -> Node3D:
	var rules := CreatureData.rules()
	var orientations := CreatureData.part_orientations(CreatureData.part_rules())
	var skin := SkinCpu.build_within(desc, int(rules["gameplay_divisions"]), int(rules["gameplay_triangle_budget"]))
	var rig = SpineRig.new()
	world.add_child(rig)
	rig.position = Vector3(0.0, -(desc.bounds_m() as AABB).position.y, 0.0)
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
	return rig


func _ground(world: Node3D) -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.45, 0.4)
	gm.roughness = 1.0
	ground.material_override = gm
	world.add_child(ground)


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
