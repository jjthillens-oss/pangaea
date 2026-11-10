extends SceneTree

# Isolated review project for this asset. Run after the GLB exists and imports:
# Godot --path assets/godfrey/meat-red --script res://review_godot.gd
# The resulting image still needs a human image inspection.

func _initialize() -> void:
	call_deferred("_review")


func _review() -> void:
	var source: PackedScene = load("res://meat-red.glb")
	if source == null:
		push_error("meat-red.glb did not import")
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(900, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var prop := source.instantiate()
	stage.add_child(prop)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.83, 0.84, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1.0, 1.0, 1.0)
	env.environment.ambient_light_energy = 0.8
	stage.add_child(env)
	var camera := Camera3D.new()
	camera.position = Vector3(0.9, 1.6, 1.2)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.12
	camera.current = true
	stage.add_child(camera)
	camera.look_at(Vector3(0.0, 0.11, 0.0))
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-46, 32, -25)
	key.light_energy = 1.35
	stage.add_child(key)
	for _frame in range(12):
		await process_frame
	var screenshot := viewport.get_texture().get_image()
	if screenshot == null or screenshot.is_empty():
		push_error("Godot returned an empty review image")
		quit(2)
		return
	var result := screenshot.save_png("res://renders/godot-gameplay.png")
	if result != OK:
		push_error("Could not save Godot review image, code %d" % result)
		quit(3)
		return
	print("GODOT_REVIEW_IMAGE res://renders/godot-gameplay.png")
	quit()
