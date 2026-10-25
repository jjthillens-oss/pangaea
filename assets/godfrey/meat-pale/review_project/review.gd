extends SceneTree
## Isolated import/render; no production scene or project setting changes.


func _initialize() -> void:
	call_deferred("_review")


func _review() -> void:
	var packed := load("res://meat-pale.glb") as PackedScene
	if packed == null:
		push_error("meat-pale.glb did not import")
		quit(1)
		return
	var stage := Node3D.new()
	root.add_child(stage)
	stage.add_child(packed.instantiate())
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.2
	camera.position = Vector3(1.6, 1.9, -2.3)
	camera.look_at(Vector3(0.0, 0.11, 0.0))
	camera.current = true
	var key := OmniLight3D.new()
	stage.add_child(key)
	key.position = Vector3(-2.0, 2.8, -2.4)
	key.light_energy = 2.0
	key.omni_range = 9.0
	var fill := OmniLight3D.new()
	stage.add_child(fill)
	fill.position = Vector3(2.3, 1.8, 1.7)
	fill.light_energy = 0.9
	fill.omni_range = 9.0
	var environment := WorldEnvironment.new()
	stage.add_child(environment)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.49, 0.54)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.76, 0.81, 0.88)
	env.ambient_light_energy = 0.75
	environment.environment = env
	for _frame in 8:
		await process_frame
	var pixels := root.get_texture().get_image()
	if pixels == null or pixels.is_empty():
		push_error("Godot rendered no image; visual gate remains unverified")
		quit(2)
		return
	var error := pixels.save_png("res://godot_review.png")
	if error != OK:
		push_error("Could not save review image: %s" % error_string(error))
		quit(3)
		return
	print("Pale food Godot view: %dx%d" % [pixels.get_width(), pixels.get_height()])
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 45.0
	camera.position = Vector3(0.0, 11.47, 8.03)
	camera.look_at(Vector3(0.0, 0.10, 0.0))
	for _frame in 8:
		await process_frame
	var gameplay := root.get_texture().get_image()
	if gameplay == null or gameplay.is_empty():
		push_error("Gameplay view did not render")
		quit(4)
		return
	var gameplay_error := gameplay.save_png("res://godot_gameplay.png")
	if gameplay_error != OK:
		push_error("Could not save gameplay view: %s" % error_string(gameplay_error))
		quit(5)
		return
	quit()
