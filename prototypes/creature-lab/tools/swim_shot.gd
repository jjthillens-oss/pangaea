extends SceneTree
## Capture a side (90-degree) view at the swim cycle's quarter stroke.

const Lab := preload("res://lab_swim.gd")
const Drive := preload("res://domain/swim_drive.gd")
const Rig := preload("res://rig/swim_rig.gd")
const SkinCpu := preload("res://skin/skin_cpu.gd")
const BodyField := preload("res://domain/body_field.gd")
const AnchorResolver := preload("res://domain/anchor_resolver.gd")
const LabSpine := preload("res://lab_spine.gd")

var body_name := "swim_tail"
var out_path := "user://swim.png"


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"body": body_name = kv[1]
			"out": out_path = kv[1]
	var desc = Lab.body(body_name)
	if desc == null:
		printerr("unknown swim body: ", body_name)
		quit(1)
		return
	var drive = Drive.create(desc)
	var rig = Rig.new()
	root.add_child(rig)
	var orientations: Dictionary = LabSpine.part_orientations(LabSpine.part_rules())
	rig.setup(desc, SkinCpu.build(desc, 48), drive, Color(0.27, 0.61, 0.81),
		AnchorResolver.resolve_all(desc, BodyField.from_description(desc), orientations), orientations)
	# Advance exactly one quarter of the body-derived stroke period.
	for i in 15:
		drive.step(1.0 / (60.0 * drive.wave_hz), 1.0, 0.0)
		rig.sync(1.0 / 60.0)
	_build_world(desc, rig)
	for i in 3:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(out_path)
	print("swim_shot %s quarter-cycle side view -> %s (%s)" % [body_name,
		ProjectSettings.globalize_path(out_path), error_string(err)])
	for child in root.get_children():
		child.queue_free()
	await process_frame
	load("res://rig/part_library.gd").clear()
	quit(0 if err == OK else 1)


func _build_world(desc: RefCounted, rig: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.11, 0.28, 0.39)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.52, 0.72, 0.82)
	e.ambient_light_energy = 0.9
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	root.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 38.0
	root.add_child(camera)
	var centre: Vector3 = rig.planner.position
	var distance: float = maxf(0.55, 1.8 * desc.bounds_m().get_longest_axis_size())
	camera.look_at_from_position(centre + Vector3(distance, 0.3 * distance, 0.0), centre, Vector3.UP)
