extends SceneTree
## Screenshots of the creature stage's world dressing (tools/blender/make_creature_world.py) in the engine, for
## the look review: the field, the nest ring, fruit bushes and meat chunks drawn the way creature_world.gd will
## draw them (MultiMesh instances with a colour each), under the stage's own sky, fog, ambient and sun: _light()
## takes the WorldEnvironment and the Sun out of game/scenes/creature/creature_world.tscn itself, so a retune of
## that scene shows up here too. (Until 2026-10-25 this tool built its own light, which had drifted from the
## scene: ambient 0.55 against 0.3, thin exponential fog against depth fog from 20 to 78 m, a sun of 1.4 against
## 0.75, a dark sky ground and exposure 1.0 against 0.9; art reviewed with it was seen brighter and clearer than the
## game draws it.) For frames of the running stage itself, see tools/godot/creature_world_gameplay_shots.gd.
## Run under Xvfb (docs/TOOLCHAIN.md):
##   xvfb-run -a -s "-screen 0 1920x1080x24" GODOT --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 1920x1080 --script res://tools/godot/world_dressing_shot.gd -- --out=DIR
## Writes nest.png (from inside the nest), bushes.png (a bush, a bare bush and meat up close), bush_ripe.png and
## bush_bare.png (one bush each at 2.6 m), bush_pair.png (the same two at about 6.5 m) and field.png (high over
## the clearing, where the turf gives way to earth). --probe adds a colour-path check frame and
## --no-shadow turns the sun's shadow off (Compatibility overexposes a shadowed sun; Forward+ does not).
## --kit renders only the flora and rock kit (tools/blender/creature_flora.py) instead, on the turf south of the
## nest: kit_close.png (the four cover pieces in a row at 1.6 m), kit_row.png (the same row at about 6 m, the
## gameplay camera's distance and pitch), kit_patch.png (a 9 m patch of mixed cover round the row at the gameplay
## camera), kit_boulders.png (the three boulders at 4 to 7 m, set on the turf for this review only: the game keeps
## them outside the walls) and kit_berm.png (the boulders on the berm past the wall at 80 m, from 20 m inside).
## --trees renders the two kit trees instead: tree_pair.png (the umbrella and the lantern tree side by side on the
## turf at about 12 m, set inside the walls for this review only), tree_umbrella_close.png and
## tree_lantern_close.png (from under each crown, about 4 m off), tree_berm.png (both on the berm and hills past
## the east wall, from 20 m inside) and tree_far.png (the same from the nest, about 90 m off).
## --bare-field hides the field's own scatter (its Cover* and Berm* objects), so a kit review sees only the pieces
## it places.

const FIELD := "res://assets/export/creature_field_ground.glb"
const NEST := "res://assets/export/creature_nest_ring.glb"
const BUSH := "res://assets/export/creature_fruit_bush.glb"
const MEAT := "res://assets/export/creature_meat_chunk.glb"
const WORLD_SCENE := "res://game/scenes/creature/creature_world.tscn"
const BARE_TINT := Color(0.62, 0.74, 0.58)   # the stage's bare-bush tint, over the baked leaf colour
const BUSH_COUNT := 14
const KIT_COVER := ["creature_grass_tuft", "creature_fern_clump", "creature_flower_clump", "creature_pebble_cluster"]
const KIT_BOULDERS := ["creature_boulder_a", "creature_boulder_b", "creature_boulder_c"]
const KIT_AT := Vector3(0.0, 0.0, 15.0)      # the kit row's centre: turf, south of the nest's clearing
const KIT_TREES := ["creature_tree_umbrella", "creature_tree_lantern"]
const TREES_AT := Vector3(0.0, 0.0, 30.0)    # the tree pair's centre: turf, south of the nest

var out_dir := "user://world_dressing"
var probe := false
var no_shadow := false
var kit := false
var trees := false
var bare_field := false
var camera: Camera3D


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg == "--probe":
			probe = true
		elif arg == "--no-shadow":
			no_shadow = true
		elif arg == "--kit":
			kit = true
		elif arg == "--trees":
			trees = true
		elif arg == "--bare-field":
			bare_field = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_light(world)
	var field: Node3D = load(FIELD).instantiate()
	if bare_field:
		for child in field.find_children("*", "MeshInstance3D", true, false):
			if String(child.name).begins_with("Cover") or String(child.name).begins_with("Berm"):
				(child as Node3D).visible = false
	world.add_child(field)
	world.add_child(load(NEST).instantiate())
	camera = Camera3D.new()
	camera.fov = 60.0
	world.add_child(camera)
	camera.current = true
	if trees:
		await _tree_shots(world)
		quit()
		return
	if kit:
		await _kit_shots(world)
		quit()
		return
	_food(world)
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


var _ground := PackedVector3Array()


## The field's height at (x, z): the nearest three of the CreatureField mesh's vertices (a 2.15 m grid), weighted
## by inverse distance, so review pieces stand on the relief and the berm instead of at y = 0.
func _ground_y(world: Node3D, x: float, z: float) -> float:
	if _ground.is_empty():
		var field := world.find_child("CreatureField", true, false) as MeshInstance3D
		for v: Vector3 in field.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			_ground.append(field.global_transform * v)
	var best: Array = [[INF, 0.0], [INF, 0.0], [INF, 0.0]]
	for v in _ground:
		var d := Vector2(v.x - x, v.z - z).length_squared()
		if d < best[2][0]:
			best[2] = [d, v.y]
			best.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var wsum := 0.0
	var ysum := 0.0
	for b: Array in best:
		var w := 1.0 / maxf(sqrt(b[0]), 0.01)
		wsum += w
		ysum += w * float(b[1])
	return ysum / wsum


func _kit_piece(world: Node3D, id: String, pos: Vector3, yaw: float, scale := 1.0) -> void:
	var piece: Node3D = load("res://assets/export/%s.glb" % id).instantiate()
	pos.y = _ground_y(world, pos.x, pos.z)
	piece.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), pos)
	world.add_child(piece)


func _kit_shots(world: Node3D) -> void:
	# The row: tuft, fern, flowers, pebbles, 0.8 m apart across the view.
	for i in KIT_COVER.size():
		_kit_piece(world, KIT_COVER[i], KIT_AT + Vector3(-1.2 + 0.8 * i, 0.0, 0.0), 0.7 * i)
	# A patch of mixed cover round the row (seeded, so every run draws the same patch), clear of the row itself.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5301
	var weights := [0.55, 0.15, 0.15, 0.15]
	for n in 90:
		var p := KIT_AT + Vector3(rng.randf_range(-4.5, 4.5), 0.0, rng.randf_range(-4.5, 4.5))
		if absf(p.z - KIT_AT.z) < 0.6 and absf(p.x - KIT_AT.x) < 1.8:
			continue
		var pick := rng.randf()
		var k := 0
		while k < weights.size() - 1 and pick > weights[k]:
			pick -= weights[k]
			k += 1
		_kit_piece(world, KIT_COVER[k], p, rng.randf() * TAU, rng.randf_range(0.8, 1.0))
	# The boulders for the close review, on the turf east of the row, and again on the berm past the east wall.
	for i in KIT_BOULDERS.size():
		_kit_piece(world, KIT_BOULDERS[i], KIT_AT + [Vector3(7.0, 0.0, -1.0), Vector3(9.5, 0.0, -2.5), Vector3(13.0, 0.0, -4.5)][i], 0.9 * i)
		_kit_piece(world, KIT_BOULDERS[i], Vector3(82.5 + 2.5 * i, 0.0, -6.0 + 6.0 * i), 1.3 * i)
	await _frames(20)
	camera.position = KIT_AT + Vector3(0.0, 0.75, 1.6)
	camera.look_at(KIT_AT + Vector3(0.0, 0.15, 0.0))
	await _frames(10)
	await _shot("kit_close")
	# About the creature camera's framing: 6 m back, pitched down about 22 degrees.
	camera.position = KIT_AT + Vector3(0.0, 2.6, 6.0)
	camera.look_at(KIT_AT + Vector3(0.0, 0.2, 0.0))
	await _frames(10)
	await _shot("kit_row")
	camera.position = KIT_AT + Vector3(-3.0, 4.2, 8.5)
	camera.look_at(KIT_AT + Vector3(0.5, 0.0, -1.0))
	await _frames(10)
	await _shot("kit_patch")
	camera.position = KIT_AT + Vector3(6.5, 1.8, 5.0)
	camera.look_at(KIT_AT + Vector3(10.0, 0.8, -2.5))
	await _frames(10)
	await _shot("kit_boulders")
	camera.position = Vector3(62.0, 2.2, 0.0)
	camera.look_at(Vector3(84.0, 2.5, 0.0))
	await _frames(10)
	await _shot("kit_berm")


func _tree_shots(world: Node3D) -> void:
	_kit_piece(world, KIT_TREES[0], TREES_AT + Vector3(-4.5, 0.0, 0.0), 0.4)
	_kit_piece(world, KIT_TREES[1], TREES_AT + Vector3(4.5, 0.0, 1.0), 2.1)
	_kit_piece(world, KIT_TREES[0], Vector3(85.8, 0.0, -9.0), 1.7)
	_kit_piece(world, KIT_TREES[1], Vector3(84.6, 0.0, 4.0), 0.3)
	await _frames(20)
	camera.position = TREES_AT + Vector3(0.0, 1.8, -12.5)
	camera.look_at(TREES_AT + Vector3(0.0, 3.6, 0.0))
	await _frames(10)
	await _shot("tree_pair")
	camera.position = TREES_AT + Vector3(-6.0, 1.5, -4.2)
	camera.look_at(TREES_AT + Vector3(-4.5, 4.6, 0.0))
	await _frames(10)
	await _shot("tree_umbrella_close")
	camera.position = TREES_AT + Vector3(3.2, 1.6, -3.0)
	camera.look_at(TREES_AT + Vector3(5.2, 3.4, 1.0))
	await _frames(10)
	await _shot("tree_lantern_close")
	camera.position = Vector3(64.0, 2.2, -2.0)
	camera.look_at(Vector3(88.0, 4.5, -2.0))
	await _frames(10)
	await _shot("tree_berm")
	camera.position = Vector3(0.0, 2.6, -2.0)
	camera.look_at(Vector3(88.0, 4.0, -2.0))
	await _frames(10)
	await _shot("tree_far")


func _light(world: Node3D) -> void:
	# The creature world scene's own WorldEnvironment (sky, ambient, fog, tonemap) and Sun, taken out of the packed
	# scene before it enters the tree (so its script never runs) and the rest freed, so the review sees the assets in
	# exactly the stage's light.
	var stage: Node = load(WORLD_SCENE).instantiate()
	for node_name in ["WorldEnvironment", "Sun"]:
		var node := stage.get_node(node_name)
		stage.remove_child(node)
		node.owner = null
		world.add_child(node)
	stage.free()
	# Compatibility draws a shadowed light as an additive pass in sRGB and overexposes (docs/TOOLCHAIN.md);
	# --no-shadow approximates the Forward+ exposure there when lavapipe is not to hand.
	if no_shadow:
		(world.get_node("Sun") as DirectionalLight3D).shadow_enabled = false


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
