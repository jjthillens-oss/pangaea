extends SceneTree
## Screenshots of the creature editor's floor pad (creature_editor_room, tools/blender/make_creature_world.py)
## in the editor's own room, for the look review: _room() takes the sky and environment, the key, fill, rim and
## under lights out of game/scenes/creature/creature_editor.tscn itself (until 2026-10-25 this tool hand-copied
## them and had drifted: other sky colours, ambient 0.7 against the scene's 0.85, no UnderLight), the pad where the
## editor puts its floor (y = -0.01, scaled (s, 1, s) with s = max(1.2, 1.4 x the body length), as
## creature_editor.gd _frame_body does), a 1 m sphere standing in for the body, and the editor camera's orbit.
## For frames of the real editor with a real body, see tools/godot/creature_world_gameplay_shots.gd --editor.
## Run under Xvfb (docs/TOOLCHAIN.md):
##   xvfb-run -a -s "-screen 0 1920x1080x24" GODOT --path . --audio-driver Dummy --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 1920x1080 --fixed-fps 60 --script res://tools/godot/editor_room_shot.gd \
##     -- --out=DIR --no-shadow [--body-length=M]
## Forward+ (the renderer the game ships with) on lavapipe takes about five minutes:
##   VK_ICD_FILENAMES=/tmp/lvp/lvp_icd.json xvfb-run -a -s "-screen 0 1920x1080x24" GODOT --path . --audio-driver Dummy \
##     --rendering-method forward_plus --rendering-driver vulkan --resolution 1920x1080 --fixed-fps 60 \
##     --script res://tools/godot/editor_room_shot.gd -- --out=DIR
## Writes room.png (the scene's initial camera: position (0, 1, 3), fov 40, looking at the body), detail.png
## (closer and higher, over the rim and the grooves), orbit.png (the editor's opening orbit: yaw 2.05, pitch 0.3 at
## 2.2 x the body length), far.png (that orbit at ZOOM_MAX), far_low.png (ZOOM_MAX at PITCH_MIN) and far_high.png
## (ZOOM_MAX at PITCH_MAX). --body-length sets the body length the pad and the orbit are sized for (default 1.8 m);
## --no-shadow turns the key light's shadow off (Compatibility overexposes a shadowed light, docs/TOOLCHAIN.md;
## Forward+ does not).

const ROOM := "res://assets/export/creature_editor_room.glb"
const EDITOR_SCENE := "res://game/scenes/creature/creature_editor.tscn"
const LIGHTS := ["Environment", "KeyLight", "FillLight", "RimLight", "UnderLight"]
## creature_editor.gd's camera: the opening orbit (yaw, pitch), the framing distance per metre of body, and the
## zoom and pitch limits.
const ORBIT := Vector2(2.05, 0.3)
const FRAME_PER_M := 2.2
const ZOOM_MAX := 4.0
const PITCH_MIN := 0.05
const PITCH_MAX := 1.4

var body_length := 1.8

var out_dir := "user://editor_room"
var no_shadow := false
var camera: Camera3D


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg == "--no-shadow":
			no_shadow = true
		elif arg.begins_with("--body-length="):
			body_length = float(arg.trim_prefix("--body-length="))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_room(world)
	var floor_pad: Node3D = load(ROOM).instantiate()
	floor_pad.position = Vector3(0.0, -0.01, 0.0)
	var floor_scale := maxf(1.2, 1.4 * body_length)
	floor_pad.scale = Vector3(floor_scale, 1.0, floor_scale)
	world.add_child(floor_pad)
	world.add_child(_stand_in_body())
	camera = Camera3D.new()
	camera.fov = 40.0
	world.add_child(camera)
	camera.current = true
	await _frames(20)

	# The editor camera's pose: creature_editor.tscn's Camera at (0, 1, 3), fov 40, looking at the body.
	camera.position = Vector3(0.0, 1.0, 3.0)
	camera.look_at(Vector3(0.0, 0.5, 0.0))
	await _frames(10)
	await _shot("room")

	# Closer and higher, over the near rim and the grooves, where the rim light catches them.
	camera.position = Vector3(1.1, 1.5, 2.3)
	camera.look_at(Vector3(0.3, 0.1, -0.2))
	await _frames(10)
	await _shot("detail")

	# The editor's own orbit round the body's centre, at its framing distance and at the zoom and pitch extremes.
	var frame := FRAME_PER_M * body_length
	for pose in [["orbit", ORBIT, frame], ["far", ORBIT, frame * ZOOM_MAX],
			["far_low", Vector2(ORBIT.x, PITCH_MIN), frame * ZOOM_MAX], ["far_high", Vector2(ORBIT.x, PITCH_MAX), frame * ZOOM_MAX]]:
		_orbit_camera(pose[1], pose[2])
		await _frames(10)
		await _shot(pose[0])
	quit()


## creature_editor.gd _update_camera's placement: `distance` from the focus along (yaw, pitch).
func _orbit_camera(orbit: Vector2, distance: float) -> void:
	var focus := Vector3(0.0, 0.5, 0.0)
	var at := focus + distance * Vector3(sin(orbit.x) * cos(orbit.y), sin(orbit.y), cos(orbit.x) * cos(orbit.y))
	camera.transform = Transform3D(Basis.looking_at(focus - at, Vector3.UP), at)


func _room(world: Node3D) -> void:
	# The creature editor scene's own environment and lights, taken out of the packed scene before it enters the tree
	# (so its script never runs) and the rest freed.
	var editor: Node = load(EDITOR_SCENE).instantiate()
	for node_name in LIGHTS:
		var node := editor.get_node(node_name)
		editor.remove_child(node)
		node.owner = null
		world.add_child(node)
	editor.free()
	if no_shadow:
		(world.get_node("KeyLight") as DirectionalLight3D).shadow_enabled = false


## A 1 m sphere in a neutral clay, standing on the pivot's plane where the working body stands.
func _stand_in_body() -> MeshInstance3D:
	var body := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var clay := StandardMaterial3D.new()
	clay.albedo_color = Color(0.72, 0.66, 0.6)
	clay.roughness = 0.65
	mesh.material = clay
	body.mesh = mesh
	body.position = Vector3(0.0, 0.5, 0.0)
	return body


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("shot ", shot_name)
