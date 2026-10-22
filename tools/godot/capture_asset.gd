extends SceneTree
## Renders review frames of an exported asset inside Godot (Bible section 15: compare in engine).
## Usage: godot --path . --script res://tools/godot/capture_asset.gd -- <glb path> <out prefix> [clip]
## Writes <out prefix>_game.jpg (gameplay camera from game/data pool settings: 55 deg pitch,
## 45 deg FOV, 14 m) and <out prefix>_close.jpg (3/4 close-up). Needs a display (xvfb-run works).

const PITCH_DEG := 55.0
const FOV_DEG := 45.0
const DISTANCE := 14.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var glb: String = args[0]
	var prefix: String = args[1]
	var clip: String = args[2] if args.size() > 2 else ""
	var root := Node3D.new()
	get_root().add_child(root)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#2A5F6E")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8FB3C4")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var world := WorldEnvironment.new()
	world.environment = env
	root.add_child(world)

	var key := DirectionalLight3D.new()
	key.light_color = Color("#FFE8C8")
	key.light_energy = 1.6
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-50, -35, 0)
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("#8FF0DC")
	rim.light_energy = 0.7
	rim.rotation_degrees = Vector3(-25, 160, 0)
	root.add_child(rim)

	var floor_mesh := PlaneMesh.new()  # review backdrop only, not a game asset
	floor_mesh.size = Vector2(60, 60)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("#2A7F86").darkened(0.2)
	floor_mesh.material = floor_mat
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.position.y = -0.45
	root.add_child(floor_node)

	var asset: Node3D = (load(glb) as PackedScene).instantiate()
	root.add_child(asset)
	if clip != "":
		var players := asset.find_children("*", "AnimationPlayer", true, false)
		if players.size() > 0:
			(players[0] as AnimationPlayer).play(clip)
			(players[0] as AnimationPlayer).seek(0.25, true)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	var target := Vector3(0, 0, 0.35)
	cam.fov = FOV_DEG
	var pitch := deg_to_rad(PITCH_DEG)
	cam.look_at_from_position(target + Vector3(0, sin(pitch), cos(pitch)) * DISTANCE, target)
	await _shot(prefix + "_game.jpg")
	cam.fov = 30.0
	cam.look_at_from_position(target + Vector3(-2.2, 1.3, -2.6), target)
	await _shot(prefix + "_close.jpg")
	quit(0)


func _shot(path: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_jpg(path, 0.88)
	print("saved ", path)
