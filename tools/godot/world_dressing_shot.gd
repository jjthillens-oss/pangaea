extends SceneTree
## Screenshots of the creature stage's world dressing (tools/blender/make_creature_world.py) in the engine, for
## the look review: the field, the nest ring, fruit bushes and meat chunks drawn the way creature_world.gd will
## draw them (MultiMesh instances with a colour each), under a plain sun and sky. Run under Xvfb
## (docs/TOOLCHAIN.md):
##   xvfb-run -a -s "-screen 0 1920x1080x24" GODOT --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 1920x1080 --script res://tools/godot/world_dressing_shot.gd -- --out=DIR
## Writes nest.png (from inside the nest), bushes.png (a bush, a bare bush and meat up close), bush_ripe.png and
## bush_bare.png (one bush each at 2.6 m), bush_pair.png (the same two at about 6.5 m) and field.png (high over
## the clearing, where the turf gives way to earth). --probe adds a colour-path check frame and
## --no-shadow turns the sun's shadow off (Compatibility overexposes a shadowed sun; Forward+ does not).

const FIELD := "res://assets/export/creature_field_ground.glb"
const NEST := "res://assets/export/creature_nest_ring.glb"
const BUSH := "res://assets/export/creature_fruit_bush.glb"
const MEAT := "res://assets/export/creature_meat_chunk.glb"
const BARE_TINT := Color(0.62, 0.74, 0.58)   # the stage's bare-bush tint, over the baked leaf colour
const BUSH_COUNT := 14

var out_dir := "user://world_dressing"
var probe := false
var no_shadow := false
var camera: Camera3D


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg == "--probe":
			probe = true
		elif arg == "--no-shadow":
			no_shadow = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_light(world)
	world.add_child(load(FIELD).instantiate())
	world.add_child(load(NEST).instantiate())
	_food(world)
	camera = Camera3D.new()
	camera.fov = 60.0
	world.add_child(camera)
	camera.current = true
	await _frames(20)
	if probe:
		# Three upright 1 m squares: the turf tile's mean as a flat colour, the tile on a standard material, and
		# the field material; they should read alike, so a mismatch points at the texture path, not the tiles.
		var flat := StandardMaterial3D.new()
		flat.albedo_color = Color(0.247, 0.473, 0.401)
		var textured := StandardMaterial3D.new()
		textured.albedo_texture = load("res://assets/export/creature_field/T_CreatureField_Turf_Albedo.png")
		var mats: Array[Material] = [flat, textured, load("res://assets/export/M_CreatureField.tres")]
		for i in 3:
			var quad := MeshInstance3D.new()
			var mesh := QuadMesh.new()
			mesh.size = Vector2(1.0, 1.0)
			quad.mesh = mesh
			quad.material_override = mats[i]
			quad.position = Vector3(-1.2 + 1.2 * i, 0.6, -1.0)
			world.add_child(quad)
		camera.position = Vector3(0.0, 0.8, 2.2)
		camera.look_at(Vector3(0.0, 0.6, -1.0))
		await _frames(10)
		await _shot("probe")

	# From inside the nest, at a creature's eye height, across the ring to the bushes beyond.
	camera.position = Vector3(-1.5, 1.3, 2.5)
	camera.look_at(Vector3(4.0, 0.3, -9.0))
	await _frames(10)
	await _shot("nest")

	# A ripe bush, a bare one and a meat chunk, up close.
	camera.position = Vector3(9.5, 1.1, -7.5)
	camera.look_at(Vector3(12.0, 0.35, -11.0))
	await _frames(10)
	await _shot("bushes")

	# One ripe bush (instance 12) and one bare bush (instance 11) at 2.6 m, where the leaf cards must read.
	camera.position = Vector3(9.49, 1.0, -4.64)
	camera.look_at(Vector3(11.49, 0.35, -6.24))
	await _frames(10)
	await _shot("bush_ripe")
	camera.position = Vector3(6.76, 1.0, -10.56)
	camera.look_at(Vector3(8.76, 0.35, -12.16))
	await _frames(10)
	await _shot("bush_bare")
	# The same two at about 6.5 m, with the meat between them.
	camera.position = Vector3(4.9, 1.3, -7.0)
	camera.look_at(Vector3(10.1, 0.35, -9.2))
	await _frames(10)
	await _shot("bush_pair")

	# High over the clearing: the nest, the bare clearing and the turf patches.
	camera.position = Vector3(-18.0, 16.0, 26.0)
	camera.look_at(Vector3(4.0, 0.0, -6.0))
	await _frames(10)
	await _shot("field")
	quit()


func _light(world: Node3D) -> void:
	# The creature world scene's own sky, environment and sun (game/scenes/creature/creature_world.tscn), so the
	# review sees the assets in the stage's light.
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.16, 0.3, 0.62)
	sky_material.sky_horizon_color = Color(0.68, 0.78, 0.9)
	sky_material.sky_curve = 0.12
	sky_material.ground_bottom_color = Color(0.12, 0.17, 0.22)
	sky_material.ground_horizon_color = Color(0.62, 0.7, 0.78)
	sky_material.sun_angle_max = 20.0
	sky_material.sun_curve = 0.1
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.3
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.8, 0.9)
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.15
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.872665, -0.523599, 0.0)
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.light_energy = 1.4
	# Compatibility draws a shadowed light as an additive pass in sRGB and overexposes (docs/TOOLCHAIN.md);
	# --no-shadow approximates the Forward+ exposure there when lavapipe is not to hand.
	sun.shadow_enabled = not no_shadow
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 80.0
	world.add_child(sun)


func _food(world: Node3D) -> void:
	var bush_scene: Node3D = load(BUSH).instantiate()
	var bush_mesh: Mesh = (bush_scene.find_child("Bush", true, false) as MeshInstance3D).mesh
	var fruit_mesh: Mesh = (bush_scene.find_child("Fruit", true, false) as MeshInstance3D).mesh
	bush_scene.free()
	var bushes := _multimesh(bush_mesh, BUSH_COUNT)
	var fruit := _multimesh(fruit_mesh, BUSH_COUNT)
	var ripe := 0
	for i in BUSH_COUNT:
		var angle := TAU * i / BUSH_COUNT + 0.4
		var radius := 11.0 + 5.0 * fposmod(i * 0.618, 1.0)
		var pos := Vector3(radius * cos(angle), 0.0, radius * sin(angle))
		var xform := Transform3D(Basis(Vector3.UP, angle * 2.3), pos)
		var is_ripe := i % 3 != 2
		bushes.multimesh.set_instance_transform(i, xform)
		bushes.multimesh.set_instance_color(i, Color.WHITE if is_ripe else BARE_TINT)
		if is_ripe:
			fruit.multimesh.set_instance_transform(ripe, xform)
			fruit.multimesh.set_instance_color(ripe, Color.WHITE)
			ripe += 1
	fruit.multimesh.visible_instance_count = ripe
	world.add_child(bushes)
	world.add_child(fruit)
	var meat_scene: Node3D = load(MEAT).instantiate()
	var meat_mesh: Mesh = (meat_scene.find_child("MeatChunk", true, false) as MeshInstance3D).mesh
	meat_scene.free()
	var meat := _multimesh(meat_mesh, 3)
	for i in 3:
		var pos := Vector3(11.0 + i * 1.1, 0.0, -9.5 - i * 0.7)
		meat.multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.UP, 0.9 * i), pos))
		meat.multimesh.set_instance_color(i, Color.WHITE)
	world.add_child(meat)


func _multimesh(mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	mmi.multimesh = mm
	return mmi


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("shot ", shot_name)
