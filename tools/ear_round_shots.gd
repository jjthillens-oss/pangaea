extends SceneTree
# Review shots of cpart_ear_round on a stand-in head: front, back, side, three_q, front_left, game_dist.
# xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 900x900 --script res://tools/ear_round_shots.gd -- OUT_DIR/

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.33, 0.35)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.52)
	env.environment.ambient_light_energy = 0.6
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	w.add_child(sun)
	sun.look_at_from_position(Vector3(1.5, 2.5, 2.0), Vector3.ZERO)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.4
	w.add_child(fill)
	fill.look_at_from_position(Vector3(-2, 0.5, -1.5), Vector3.ZERO)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	head.mesh = sm
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.5, 0.38, 0.3)
	head.material_override = hm
	w.add_child(head)
	var views := {"front": Vector3(0, 0, 1), "back": Vector3(0, 0, -1), "side": Vector3(1, 0, 0), "three_q": Vector3(0.7, 0.3, 0.7), "front_left": Vector3(-0.7, 0.2, 0.7)}
	var scene: PackedScene = load("res://assets/export/cpart_ear_round.glb")
	for i in 3:
		var e: Node3D = scene.instantiate()
		w.add_child(e)
		# mount on the head side: the ear's +Z (out of skin) along world +X, its +Y forward = world +Z
		e.basis = Basis(Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1))
		e.position = Vector3(0.085, 0.02, 0)
		if i > 0:
			e.position.z = 1000.0
	var cam := Camera3D.new()
	cam.fov = 30
	w.add_child(cam)
	cam.current = true
	await process_frame
	for k in views:
		var d: Vector3 = views[k]
		var tgt := Vector3(0.11, 0.04, 0)
		cam.look_at_from_position(tgt + d.normalized() * 0.32, tgt)
		for f in 4:
			await process_frame
		root.get_texture().get_image().save_png(out + k + ".png")
	cam.look_at_from_position(Vector3(0.11, 0.04, 0) + Vector3(0.4, 0.5, 1).normalized() * 0.9, Vector3(0.05, 0.0, 0))
	for f in 4:
		await process_frame
	root.get_texture().get_image().save_png(out + "game_dist.png")
	quit()
