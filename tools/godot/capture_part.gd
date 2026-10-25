extends SceneTree
## Neutral-light Godot review shots of one small creature part GLB: close 3/4, top and a distant gameplay view.
## Usage: xvfb-run godot --path . --rendering-method gl_compatibility --rendering-driver opengl3
##        --script res://tools/godot/capture_part.gd -- <res:// glb> <out dir> [--handles=H1_Fold:1000,...] [--fit]
##        [--mirror] [--no-shadow] [--views=front,side]
## --handles sets blend shapes by name (per mille) on every mesh of both copies. --fit frames the close, top and the
## extra views on the part's own bounds (for big parts such as the 0.44 m dragon wing). --mirror makes the second
## copy the left-hand one (scale.x = -1, as the game mirrors a chiral part). --no-shadow turns the sun's shadow off
## (Compatibility overexposes a shadowed sun, docs/TOOLCHAIN.md). --views adds the fitted "front" (from -Z, the
## part's front) and "side" (from +X) views.

const VIEWS := {"godot_close": [Vector3(0.12, 0.1, 0.14), 40.0], "godot_top": [Vector3(0.0, 0.26, 0.01), 40.0],
	"godot_gameplay": [Vector3(0.0, 1.6, 1.4), 30.0]}
## Fitted view directions (from the part's centre) for --fit and --views.
const FIT_DIRS := {"godot_close": Vector3(0.12, 0.1, 0.14), "godot_top": Vector3(0.0, 1.0, 0.04),
	"godot_front": Vector3(0.0, 0.05, -1.0), "godot_side": Vector3(1.0, 0.05, 0.0)}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[1]
	var handles := {}
	var fit := false
	var mirror := false
	var shadow := true
	var extra: Array[String] = []
	for a in args.slice(2):
		if a.begins_with("--handles="):
			for pair in a.trim_prefix("--handles=").split(",", false):
				var kv := pair.split(":")
				handles[kv[0]] = float(kv[1]) / 1000.0
		elif a == "--fit":
			fit = true
		elif a == "--mirror":
			mirror = true
		elif a == "--no-shadow":
			shadow = false
		elif a.begins_with("--views="):
			for v in a.trim_prefix("--views=").split(",", false):
				extra.append("godot_" + v)
	DirAccess.make_dir_recursive_absolute(out)
	var root := Node3D.new()
	get_root().add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#6F8796")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#B8C4CC")
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = shadow
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4, 4)
	ground.mesh = plane
	root.add_child(ground)
	var parts: Array[Node3D] = []
	var gap := 0.08
	for i in 2:
		var part: Node3D = (load(args[0]) as PackedScene).instantiate()
		root.add_child(part)
		for mi in part.find_children("*", "MeshInstance3D", true, false):
			for key in handles:
				var idx: int = (mi as MeshInstance3D).find_blend_shape_by_name(key)
				if idx >= 0:
					(mi as MeshInstance3D).set_blend_shape_value(idx, handles[key])
		if mirror and i == 0:
			part.scale = Vector3(-1, 1, 1)
		parts.append(part)
	var box := _bounds(parts[1])
	if fit:
		gap = maxf(0.08, box.size.x * 0.5 + 0.03)
	parts[0].position = Vector3(-gap, 0, 0)
	parts[1].position = Vector3(gap, 0, 0)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	get_root().size = Vector2i(960, 720)
	await process_frame
	var names: Array = VIEWS.keys() + extra
	for name in names:
		var target := Vector3(0, 0.01, 0.0)
		var up := Vector3.UP if name != "godot_top" else Vector3.FORWARD
		if (fit and name != "godot_gameplay") or not VIEWS.has(name):
			# Both copies' bounds, seen from FIT_DIRS[name] at a distance that fits them in a 40 degree view.
			var both := _bounds(parts[0]).merge(_bounds(parts[1]))
			target = both.get_center()
			cam.fov = 40.0
			var dir: Vector3 = (FIT_DIRS[name] as Vector3).normalized()
			cam.look_at_from_position(target + dir * (both.size.length() * 0.5 / tan(deg_to_rad(20.0)) * 1.1), target, up)
		else:
			cam.fov = VIEWS[name][1]
			cam.look_at_from_position(VIEWS[name][0], target, up)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(out.path_join(name + ".png"))
	quit()


## The world-space bounds of every mesh under `node` (blend shapes not included: Godot's AABB is the rest mesh's).
func _bounds(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out
