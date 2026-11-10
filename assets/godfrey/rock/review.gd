extends SceneTree
## Isolated Godot import and neutral-light view of this asset; never used by the game.


func _initialize() -> void:
	call_deferred("_review")


func _review() -> void:
	var packed := load("res://rock.glb") as PackedScene
	if packed == null:
		push_error("rock.glb did not import as a PackedScene")
		quit(1)
		return
	var stage := Node3D.new()
	root.add_child(stage)
	var rock := packed.instantiate()
	stage.add_child(rock)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.4
	camera.position = Vector3(-2.7, 2.2, -3.5)
	camera.look_at(Vector3(0.0, 0.82, 0.0))
	camera.current = true
	var key := OmniLight3D.new()
	stage.add_child(key)
	key.position = Vector3(-3.0, 4.0, -4.0)
	key.light_energy = 2.2
	key.omni_range = 12.0
	var fill := OmniLight3D.new()
	stage.add_child(fill)
	fill.position = Vector3(4.0, 2.0, -2.0)
	fill.light_energy = 0.9
	fill.omni_range = 10.0
	var environment := WorldEnvironment.new()
	stage.add_child(environment)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.48, 0.53, 0.59)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.73, 0.79)
	env.ambient_light_energy = 0.75
	environment.environment = env
	for _i in 8:
		await process_frame
	var viewport_image := root.get_texture().get_image()
	if viewport_image == null or viewport_image.is_empty():
		push_error("Godot rendered no view; visual gate remains unverified")
		quit(2)
		return
	var error := viewport_image.save_png("res://godot_review.png")
	if error != OK:
		push_error("Could not save Godot review PNG: %s" % error_string(error))
		quit(3)
		return
	print("Godot rock view: %dx%d, saved godot_review.png" % [viewport_image.get_width(), viewport_image.get_height()])
	quit()
