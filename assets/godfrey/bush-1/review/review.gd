extends SceneTree

func _initialize() -> void:
    call_deferred("capture")

func capture() -> void:
    var packed = load("res://bush-1.glb") as PackedScene
    if packed == null:
        push_error("GLB failed to load")
        quit(2)
        return
    var root = Node3D.new()
    get_root().add_child(root)
    var shrub = packed.instantiate()
    root.add_child(shrub)
    var env = WorldEnvironment.new()
    var environment = Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.12, 0.16, 0.17)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.65, 0.68, 0.70)
    environment.ambient_light_energy = 0.75
    env.environment = environment
    root.add_child(env)
    var key = DirectionalLight3D.new()
    key.rotation_degrees = Vector3(-35, 35, 0)
    key.light_energy = 1.3
    root.add_child(key)
    var camera = Camera3D.new()
    camera.position = Vector3(2.5, 2.1, 3.0)
    camera.fov = 42
    root.add_child(camera)
    camera.look_at(Vector3(0, 0.68, 0))
    camera.current = true
    await process_frame
    await process_frame
    var img = get_root().get_texture().get_image()
    var err = img.save_png("res://godot-review.png")
    if err != OK:
        push_error("PNG save failed: %s" % err)
        quit(3)
        return
    print("GODOT_REVIEW_SAVED ", img.get_width(), "x", img.get_height())
    quit()


