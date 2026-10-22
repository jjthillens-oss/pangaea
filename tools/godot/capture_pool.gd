extends SceneTree
## Art review capture: plays the real pool with the dev ForageBot and saves frames, so new assets
## are judged in the game's own camera and lighting. Saves go to user://capture/, never the
## player's slot. Needs a real renderer (in the cloud: xvfb-run and gl_compatibility).
##
##   godot --path . --rendering-method gl_compatibility --script res://tools/godot/capture_pool.gd \
##     -- --out=docs/art/renders/production/pool --body=hunter --seed=4242 --frames=300,900 --zoom=0
##   --at=x,y places the cell at that plane point and leaves it idle (no ForageBot).
##   --floor-y=Y moves the floor down to Y for micro-world look previews until the pool has its own
##   floor-depth setting (review only; the sim's floor cues stay where they are).
##   --micro-look applies the micro-world mood frame's water values (DECISIONS, "The cell stage
##   reads as a microscopic world") to the environment, as a preview of engineering's tuning.

const MAIN_SCENE := "res://game/scenes/main.tscn"
const ForageBot := preload("res://game/dev/forage_bot.gd")


func _initialize() -> void:
	var out := "pool_capture"
	var body := "omnivore"
	var seed_value := 4242
	var frames := [300, 900]
	var zoom := 0
	var at := Vector2.INF
	var floor_y := NAN
	var micro := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--body="):
			body = arg.trim_prefix("--body=")
		elif arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--frames="):
			frames = Array(arg.trim_prefix("--frames=").split(",")).map(func(f): return int(f))
		elif arg.begins_with("--at="):
			var xy := arg.trim_prefix("--at=").split(",")
			at = Vector2(float(xy[0]), float(xy[1]))
		elif arg.begins_with("--floor-y="):
			floor_y = float(arg.trim_prefix("--floor-y="))
		elif arg == "--micro-look":
			micro = true
		elif arg.begins_with("--zoom="):
			zoom = int(arg.trim_prefix("--zoom="))
	root.size = Vector2i(1920, 1080)
	var main: Main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	main.open_session("user://capture/slot.json")
	if at == Vector2.INF:
		main.intent_provider = ForageBot.new()
	main.start_new(body, seed_value)
	await process_frame
	if at != Vector2.INF:
		# Review only: put the cell at a plane point (for example over the rim shallows) and leave it idle.
		var sim := main.pool.sim
		sim.motion.position = at
		sim.motion.prev_position = at
		sim.actor.position = at
	if not is_nan(floor_y):
		main.pool.floor_node.position.y = floor_y
	if micro:
		var world := main.pool.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment
		var env := world.environment.duplicate() as Environment
		env.background_color = Color("#1D4E8C")
		env.ambient_light_color = Color("#2F6FB8")
		env.fog_light_color = Color("#3A78B8")
		env.fog_density = 0.006
		env.fog_height = -0.5
		env.fog_height_density = 0.12
		world.environment = env
	if zoom != 0:
		main.pool.camera.zoom_by(zoom)
	var frame := 0
	for target: int in frames:
		while frame < target:
			await process_frame
			frame += 1
		await RenderingServer.frame_post_draw
		var path := "%s_%s_%d.png" % [out, body, target]
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
	quit(0)
