extends SceneTree
## Neutral-light Godot review shots of one small creature part GLB: close 3/4, top and a distant gameplay view.
## Usage: xvfb-run godot --path . --rendering-method gl_compatibility --rendering-driver opengl3
##        --script res://tools/godot/capture_part.gd -- <res:// glb> <out dir>

const VIEWS := {"godot_close": [Vector3(0.12, 0.1, 0.14), 40.0], "godot_top": [Vector3(0.0, 0.26, 0.01), 40.0],
	"godot_gameplay": [Vector3(0.0, 1.6, 1.4), 30.0]}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[1]
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
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4, 4)
	ground.mesh = plane
	root.add_child(ground)
	for x in [-0.08, 0.08]:
		var part: Node3D = (load(args[0]) as PackedScene).instantiate()
		part.position = Vector3(x, 0, 0)
		root.add_child(part)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	get_root().size = Vector2i(960, 720)
	await process_frame
	for name in VIEWS:
		cam.fov = VIEWS[name][1]
		cam.look_at_from_position(VIEWS[name][0], Vector3(0, 0.01, 0.0), Vector3.UP if name != "godot_top" else Vector3.FORWARD)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(out.path_join(name + ".png"))
	quit()
