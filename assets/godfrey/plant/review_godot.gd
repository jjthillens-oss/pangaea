extends SceneTree

# Copy this script and tideleaf.glb into an isolated Godot project, import with
# --headless --editor --import, then run with --rendering-method gl_compatibility.
func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var packed := load("res://tideleaf.glb") as PackedScene
	if packed == null:
		push_error("Tideleaf GLB did not import as a PackedScene")
		quit(2)
		return

	var stage := Node3D.new()
	root.add_child(stage)
	var model := packed.instantiate()
	stage.add_child(model)
	var light := DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees = Vector3(-40, 35, 0)
	light.light_energy = 1.25
	var fill := DirectionalLight3D.new()
	stage.add_child(fill)
	fill.rotation_degrees = Vector3(-25, -125, 0)
	fill.light_energy = 0.5
	var environment := WorldEnvironment.new()
	stage.add_child(environment)
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.16, 0.18, 0.21)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0, 0.88, 3.4)
	camera.look_at(Vector3(0, 0.78, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.2
	camera.current = true
	for frame in range(5):
		await process_frame
	var shot := root.get_viewport().get_texture().get_image()
	if shot == null or shot.get_width() < 100:
		push_error("Godot viewport capture failed")
		quit(3)
		return
	var result := shot.save_png("res://godot-review.png")
	if result != OK:
		push_error("Godot viewport image could not be saved")
		quit(4)
		return
	print("Godot review screenshot: ", ProjectSettings.globalize_path("res://godot-review.png"))
	quit()
