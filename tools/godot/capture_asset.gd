extends SceneTree
## Renders review frames of an exported asset inside Godot (Bible section 15: compare in engine).
## Usage: godot --path . --script res://tools/godot/capture_asset.gd -- <glb path> <out prefix> [clip]
## Writes <out prefix>_game.jpg (gameplay camera from game/data pool settings: 55 deg pitch,
## 45 deg FOV, 14 m) and <out prefix>_close.jpg (3/4 close-up). Needs a display (xvfb-run works).
## The asset is reviewed over the fluid it lives in (micro-world plan C9): the pool's own
## environment, Sun, DepthGlow and Backdrop, taken from pool.tscn, so the review shows the blue
## fluid, the blue ambient and the fog the game draws, not the old teal floor.

const PITCH_DEG := 55.0
const FOV_DEG := 45.0
const DISTANCE := 14.0
const POOL_SCENE := "res://game/scenes/pool/pool.tscn"
## The pool's nodes that make the fluid and its light.
const FLUID_NODES: Array[String] = ["WorldEnvironment", "Sun", "DepthGlow", "Backdrop"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var glb: String = args[0]
	var prefix: String = args[1]
	var clip: String = args[2] if args.size() > 2 else ""
	var root := Node3D.new()
	get_root().add_child(root)

	# Borrow the fluid from the pool scene without readying the pool itself, and give it the
	# renderer's profile as pool.gd does.
	var pool := (load(POOL_SCENE) as PackedScene).instantiate()
	for node_name in FLUID_NODES:
		var node := pool.get_node(node_name)
		pool.remove_child(node)
		node.owner = null
		root.add_child(node)
	pool.free()
	PoolLook.apply(PoolLook.profile_for(RenderingServer.get_current_rendering_method()),
			root.get_node("Sun") as DirectionalLight3D, root.get_node("WorldEnvironment") as WorldEnvironment)

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
	# The close-up looks down about 30 degrees, so the backdrop's far edge stays out of frame as it
	# does in game.
	cam.fov = 30.0
	cam.look_at_from_position(target + Vector3(-2.2, 2.0, -2.6), target)
	await _shot(prefix + "_close.jpg")
	quit(0)


func _shot(path: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_jpg(path, 0.88)
	print("saved ", path)
