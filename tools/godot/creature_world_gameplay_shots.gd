extends SceneTree
## Frames of the creature stage's art in the REAL scenes, for the look review of the world dressing
## (tools/blender/make_creature_world.py): game/scenes/creature/creature_world.tscn with its own sky, fog, ambient
## and sun, and game/scenes/creature/creature_editor.tscn with its own room lights. Nothing here builds light of its
## own, so what these frames show is what the game shows. Run under Xvfb (docs/TOOLCHAIN.md):
##   xvfb-run -a -s "-screen 0 1920x1080x24" GODOT --path . --audio-driver Dummy --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 1920x1080 --fixed-fps 60 \
##     --script res://tools/godot/creature_world_gameplay_shots.gd -- --out=DIR --no-hud
## Options after `--`:
##   --out=DIR      where the PNGs go (default user://creature_world_shots)
##   --no-hud       hides the HUD, so art comparisons are not muddied by HUD restyles
##   --no-shadow    turns the sun's (or the editor key light's) shadow off: Compatibility overexposes a shadowed
##                  light (docs/TOOLCHAIN.md), Forward+ does not
##   --editor       the editor room instead of the world
##   --body=NAME    the starter body (default quadruped); --seed=N the world seed (default 4242)
##   --perf         also times PERF_FRAMES frames at the spawn and roam poses (wall clock per frame)
##   --only=a,b     only these frames (and only the walk they need): Forward+ on lavapipe takes about 30 s a frame
##   --warmup=N     frames before the first shot (default 30); --settle=N frames before each later shot (default 8)
## World frames: world_spawn (the gameplay camera as setup leaves it), world_roam (after walking forward 4 s),
## world_overview (the gameplay camera at 45 degrees, 12 m), world_low (3 degrees, 12 m: the horizon), then, with the
## world's processing stopped, fixed close-ups: close_ground, close_nest, close_bush and close_meat (a chunk dropped
## beside the bush through the sim's own drop, so it is drawn by the world's own MultiMesh), world_edge (the berm,
## its boulders and trees and the hills, from just inside the east wall) and world_treeline (from the nest across the
## field to the trees past the north-east corner).
## Editor frames: editor_default (the editor's framing), editor_close (ZOOM_MIN), editor_far (ZOOM_MAX),
## editor_far_low (ZOOM_MAX at PITCH_MIN) and editor_far_high (ZOOM_MAX at PITCH_MAX).
## Every frame prints "SHOT name draw_calls=.. primitives=.. objects=..", and the world prints setup_ms.

const WORLD_SCENE := "res://game/scenes/creature/creature_world.tscn"
const EDITOR_SCENE := "res://game/scenes/creature/creature_editor.tscn"
const CREATURE_DATA := "res://game/systems/creature/creature_data.gd"
const PERF_FRAMES := 120
const ROAM_FRAMES := 240

var out_dir := "user://creature_world_shots"
var no_hud := false
var no_shadow := false
var editor_mode := false
var perf := false
var body_name := "quadruped"
var world_seed := 4242
var only := PackedStringArray()
var warmup := 30
var settle := 8
var camera: Camera3D


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg == "--no-hud":
			no_hud = true
		elif arg == "--no-shadow":
			no_shadow = true
		elif arg == "--editor":
			editor_mode = true
		elif arg == "--perf":
			perf = true
		elif arg.begins_with("--body="):
			body_name = arg.trim_prefix("--body=")
		elif arg.begins_with("--seed="):
			world_seed = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",", false)
		elif arg.begins_with("--warmup="):
			warmup = int(arg.trim_prefix("--warmup="))
		elif arg.begins_with("--settle="):
			settle = int(arg.trim_prefix("--settle="))
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("renderer ", RenderingServer.get_current_rendering_method(), " / ", RenderingServer.get_video_adapter_name())
	if editor_mode:
		_run_editor.call_deferred()
	else:
		_run_world.call_deferred()


func _run_world() -> void:
	var world: Node3D = load(WORLD_SCENE).instantiate()
	world.mate_beat_s = 0.0
	root.add_child(world)
	world.setup(load(CREATURE_DATA).body(body_name).to_dict(), world_seed, 150)
	print("setup_ms ", JSON.stringify(world.setup_ms))
	if no_hud:
		world.hud.visible = false
	if no_shadow:
		(world.get_node("Sun") as DirectionalLight3D).shadow_enabled = false
	camera = world.camera
	await _frames(warmup)
	if _want("world_spawn"):
		await _shot("world_spawn")
		if perf:
			await _time("spawn")

	if _want("world_roam"):
		world.set_intent(Vector2(0.0, 1.0), false, false)
		await _frames(ROAM_FRAMES)
		world.clear_intent()
		await _frames(20)
		await _shot("world_roam")
		if perf:
			await _time("roam")

	world.camera_pitch = deg_to_rad(45.0)
	world.camera_distance = 12.0
	if _want("world_overview"):
		await _frames(20)
		await _shot("world_overview")
	world.camera_pitch = deg_to_rad(3.0)
	if _want("world_low"):
		await _frames(20)
		await _shot("world_low")

	# Fixed close-ups: a chunk of meat goes down beside the first bush through the sim's own drop, the world draws
	# it on its next frame, and then the world stops so the camera holds still.
	var bush: Vector3 = world.sim.fruit[0]["position"]
	var meat_at := bush + Vector3(1.1, 0.0, 0.6)
	world.sim._drop_meat(meat_at)
	await _frames(3)
	world.set_process(false)
	world.set_physics_process(false)
	var ground_at := _open_ground(world.sim)
	var poses := {
		"close_ground": [ground_at + Vector3(0.0, 1.1, 2.2), ground_at + Vector3(0.0, 0.0, -0.6)],
		"close_nest": [Vector3(1.4, 1.5, 9.2), Vector3(0.0, 0.25, 5.8)],
		"close_bush": [bush + Vector3(-1.4, 1.0, 1.6), bush + Vector3(0.0, 0.35, 0.0)],
		"close_meat": [meat_at + Vector3(-0.7, 0.55, 0.8), meat_at + Vector3(0.0, 0.08, 0.0)],
		# The field's edge: the berm's boulders and trees and the hills behind, from just inside the east wall.
		"world_edge": [Vector3(62.0, 2.0, 40.0), Vector3(80.0, 1.0, 60.0)],
		# The treeline from the nest, across the whole field.
		"world_treeline": [Vector3(0.0, 2.4, 6.0), Vector3(40.0, 3.0, 40.0)],
	}
	for pose in poses:
		if _want(pose):
			camera.look_at_from_position(poses[pose][0], poses[pose][1], Vector3.UP)
			await _frames(settle)
			await _shot(pose)
	quit()


func _want(shot_name: String) -> bool:
	return only.is_empty() or only.has(shot_name)


## A spot of open turf away from the nest, every bush and the player, for the ground close-up.
func _open_ground(sim) -> Vector3:
	for i in 64:
		var a := 0.7 + i * 2.399963
		var p := Vector3(cos(a), 0.0, sin(a)) * (22.0 + (i % 5) * 6.0)
		var clear := (p - (sim.player()["position"] as Vector3)).length() > 6.0
		for f in sim.fruit:
			clear = clear and (p - (f["position"] as Vector3)).length() > 5.0
		if clear:
			return p
	return Vector3(24.0, 0.0, -18.0)


func _run_editor() -> void:
	var editor: Node3D = load(EDITOR_SCENE).instantiate()
	root.add_child(editor)
	editor.setup(load(CREATURE_DATA).body(body_name), 150)
	if no_hud:
		editor.hud.visible = false
	if no_shadow:
		(editor.get_node("KeyLight") as DirectionalLight3D).shadow_enabled = false
	camera = editor.camera
	print("floor_scale ", editor.floor_disc.scale)
	await _frames(maxi(warmup, 60))   # the skin worker builds the body off the main thread
	if _want("editor_default"):
		await _shot("editor_default")
	for i in 16:
		editor.zoom(1)
	if _want("editor_close"):
		await _frames(settle)
		await _shot("editor_close")
	for i in 32:
		editor.zoom(-1)
	if _want("editor_far"):
		await _frames(settle)
		await _shot("editor_far")
	editor.orbit(Vector2(0.0, -2.0))
	if _want("editor_far_low"):
		await _frames(settle)
		await _shot("editor_far_low")
	editor.orbit(Vector2(0.0, 4.0))
	if _want("editor_far_high"):
		await _frames(settle)
		await _shot("editor_far_high")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Wall-clock time per frame over PERF_FRAMES frames (--fixed-fps runs frames back to back, so this is the frame's
## cost on this machine), with the engine's own process time.
func _time(pose: String) -> void:
	var t0 := Time.get_ticks_usec()
	for i in PERF_FRAMES:
		await process_frame
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / PERF_FRAMES
	print("PERF %s frame_ms=%.2f process_ms=%.2f" % [pose, ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("SHOT %s draw_calls=%d primitives=%d objects=%d" % [shot_name,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
