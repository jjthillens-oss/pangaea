extends SceneTree
## A screenshot of the creature editor's floor pad (creature_editor_room, tools/blender/make_creature_world.py)
## in the editor's own room, for the look review: the dark blue sky, the warm key, the cool fill and the cyan
## rim light of game/scenes/creature/creature_editor.tscn, the pad where the editor puts its floor (y = -0.01,
## scaled (2.5, 1, 2.5) as for a body about 1.8 m long), a 1 m sphere standing in for the body, and the editor
## camera's pose. Run under Xvfb (docs/TOOLCHAIN.md):
##   xvfb-run -a -s "-screen 0 1920x1080x24" GODOT --path . --audio-driver Dummy --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 1920x1080 --fixed-fps 60 --script res://tools/godot/editor_room_shot.gd \
##     -- --out=DIR --no-shadow
## Forward+ (the renderer the game ships with) on lavapipe takes about five minutes:
##   VK_ICD_FILENAMES=/tmp/lvp/lvp_icd.json xvfb-run -a -s "-screen 0 1920x1080x24" GODOT --path . --audio-driver Dummy \
##     --rendering-method forward_plus --rendering-driver vulkan --resolution 1920x1080 --fixed-fps 60 \
##     --script res://tools/godot/editor_room_shot.gd -- --out=DIR
## Writes room.png (the editor camera: position (0, 1, 3), fov 40, looking at the body) and detail.png (closer and
## higher, over the rim and the grooves). --no-shadow turns the key light's shadow off (Compatibility overexposes
## a shadowed light, docs/TOOLCHAIN.md; Forward+ does not).

const ROOM := "res://assets/export/creature_editor_room.glb"
## The editor's floor scale for a body about 1.8 m long (max(1.2, 1.4 x the body's longest axis)).
const FLOOR_SCALE := 2.5

var out_dir := "user://editor_room"
var no_shadow := false
var camera: Camera3D


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg == "--no-shadow":
			no_shadow = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_room(world)
	var floor_pad: Node3D = load(ROOM).instantiate()
	floor_pad.position = Vector3(0.0, -0.01, 0.0)
	floor_pad.scale = Vector3(FLOOR_SCALE, 1.0, FLOOR_SCALE)
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
	quit()


func _room(world: Node3D) -> void:
	# The creature editor scene's sky, environment and lights (game/scenes/creature/creature_editor.tscn), value
	# for value, so the review sees the pad in the room's light. The .tscn writes each light's Transform3D
	# row-major; the Basis here takes the same numbers as columns.
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.02, 0.05, 0.13)
	sky_material.sky_horizon_color = Color(0.16, 0.34, 0.62)
	sky_material.sky_curve = 0.2
	sky_material.ground_bottom_color = Color(0.012, 0.03, 0.08)
	sky_material.ground_horizon_color = Color(0.1, 0.22, 0.42)
	sky_material.ground_curve = 0.15
	sky_material.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var key := DirectionalLight3D.new()
	key.transform = Transform3D(Vector3(0.866, 0.0, -0.5), Vector3(-0.321, 0.766, -0.557), Vector3(0.383, 0.643, 0.663), Vector3(0.0, 4.0, 0.0))
	key.light_color = Color(1.0, 0.96, 0.9)
	key.light_energy = 1.3
	key.shadow_enabled = not no_shadow
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.transform = Transform3D(Vector3(-0.766, 0.0, 0.643), Vector3(-0.21, 0.945, -0.25), Vector3(-0.608, -0.327, -0.724), Vector3(0.0, 4.0, 0.0))
	fill.light_color = Color(0.6, 0.78, 1.0)
	fill.light_energy = 0.45
	world.add_child(fill)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0.0, 2.2, -2.5)
	rim.light_color = Color(0.55, 0.8, 1.0)
	rim.light_energy = 1.2
	rim.omni_range = 8.0
	world.add_child(rim)


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
