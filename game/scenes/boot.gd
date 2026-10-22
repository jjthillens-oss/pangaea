extends Node3D
## M0 launch check. Shows the Blender sample asset in a lit scene and runs the foundation checks
## a fresh install must pass: build identity, data loading, asset loading and a save round trip.
## This is a toolchain verification scene, not gameplay.
##
## Pass `-- --smoke` on the command line to print results and exit (code 0 = all checks passed).
## Pass `-- --screenshot=<path.png>` to save one rendered frame and exit (needs a real renderer).

const SAMPLE_ASSET := "res://assets/export/sample_cell.glb"
const CHECK_SAVE_PATH := "user://saves/m0_check.json"

var _sample: Node3D
var _results: Array[Dictionary] = []


func _ready() -> void:
	_build_stage()
	_run_checks()
	_build_overlay()
	for r in _results:
		print("[%s] %s: %s" % ["PASS" if r.ok else "FAIL", r.name, r.detail])
	var args := OS.get_cmdline_user_args()
	if "--smoke" in args:
		get_tree().quit(0 if _all_passed() else 1)
	for arg in args:
		if arg.begins_with("--screenshot="):
			_capture(arg.trim_prefix("--screenshot="))


func _capture(path: String) -> void:
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("Screenshot %s: %s" % [path, error_string(err)])
	get_tree().quit(0 if err == OK and _all_passed() else 1)


func _process(delta: float) -> void:
	if _sample:
		_sample.rotate_y(delta * 0.4)


func _all_passed() -> bool:
	return _results.all(func(r): return r.ok)


func _check(name: String, ok: bool, detail: String) -> void:
	_results.append({"name": name, "ok": ok, "detail": detail})


func _run_checks() -> void:
	var info := BuildInfo.read()
	_check("Build", true, "%s (%s), engine %s" % [info.version, info.commit, info.engine])

	var catalog := PartCatalog.load_from()
	_check("Part catalog", catalog != null and catalog.parts.size() > 0,
		"%d part types" % (catalog.parts.size() if catalog else 0))

	_check("Sample asset", _sample != null and _sample.find_child("socket_mouth", true, false) != null,
		"sample_cell.glb with sockets" if _sample else "could not load %s" % SAMPLE_ASSET)

	if catalog == null:
		_check("Save round trip", false, "skipped: no part catalog")
		return
	var service := PersistenceService.new(catalog)
	var save := SaveGame.new_run(randi() % 1000000, BuildInfo.build_id())
	save.genome.add_part("mouth_filter", 0.0)
	save.genome.add_part("flagellum", PI)
	var err := service.save_to(CHECK_SAVE_PATH, save)
	var loaded := service.load_from(CHECK_SAVE_PATH)
	var same: bool = loaded.ok and loaded.save.lineage_id == save.lineage_id \
		and loaded.save.genome.parts.size() == save.genome.parts.size()
	_check("Save round trip", err == OK and same,
		ProjectSettings.globalize_path(CHECK_SAVE_PATH) if same else "error %d, %s" % [err, loaded.errors])


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b2f37")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("7fb8b0")
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("0b2f37")
	env.fog_density = 0.02
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)

	# Three-quarter front view of the sample so its face and sockets are visible.
	var camera := Camera3D.new()
	camera.position = Vector3(1.4, 1.9, -2.2)
	camera.fov = 40
	add_child(camera)
	camera.look_at(Vector3.ZERO)

	var packed: PackedScene = load(SAMPLE_ASSET)
	if packed:
		_sample = packed.instantiate()
		add_child(_sample)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(32, 32)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "Pangaea · M0 foundations check"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var note := Label.new()
	note.text = "Toolchain verification scene. Not gameplay."
	note.modulate = Color(1, 1, 1, 0.6)
	box.add_child(note)
	for r in _results:
		var line := Label.new()
		line.text = "%s  %s: %s" % ["PASS" if r.ok else "FAIL", r.name, r.detail]
		line.modulate = Color("8fe3a8") if r.ok else Color("ff6b6b")
		box.add_child(line)
