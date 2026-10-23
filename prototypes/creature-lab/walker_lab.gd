extends Node3D
## Walker Lab: Stage 1 generated creatures walking on Gait Lab legs. Command line (after --): --body=NAME|all
## (s1_* names; "all" is every Stage 1 body with legs), --drive=demo|walk|trot|run|turn_in_place|reversal|random,
## --duration=SECONDS, --hud=0.

const Lab := preload("res://lab_data.gd")
const LabSpine := preload("res://lab_spine.gd")
const Drives := preload("res://lab_drives.gd")
const SkinCpu := preload("res://skin/skin_cpu.gd")
const GaitBody := preload("res://domain/gait_body.gd")
const WalkerRig := preload("res://rig/walker_rig.gd")

const PALETTE := [Color(0.93, 0.55, 0.36), Color(0.36, 0.66, 0.86), Color(0.52, 0.78, 0.45), Color(0.86, 0.72, 0.36),
		Color(0.72, 0.5, 0.86), Color(0.86, 0.45, 0.56), Color(0.45, 0.8, 0.76), Color(0.8, 0.8, 0.5)]

var body_choice := "all"
var drive := "demo"
var duration := 0.0
var show_hud := true

var walkers: Array = []
var time := 0.0
var camera: Camera3D
var hud: Label
var _cam_centre := Vector3.ZERO


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"body": body_choice = kv[1]
			"drive": drive = kv[1]
			"duration": duration = float(kv[1])
			"hud": show_hud = kv[1] != "0"
	_build_world()
	var names: Array = []
	for n in (LabSpine.stage1_names() if body_choice == "all" else [body_choice]):
		if not GaitBody.from_description(LabSpine.body(n))["legs"].is_empty():
			names.append(n)
	var table = Lab.table()
	var x := 0.0
	for n in names.size():
		var desc = LabSpine.body(names[n])
		var info := GaitBody.from_description(desc)
		var mech = Lab.BodyMechanics.create(names[n], info["body"], table)
		var width: float = desc.bounds_m().size.x
		if n > 0:
			x += 0.5 * width + 0.6
		var planner = Lab.GaitPlanner.create(mech, Vector3(x, 0.0, 0.0), 0.0)
		x += 0.5 * width
		var rig = WalkerRig.new()
		rig.name = names[n]
		add_child(rig)
		rig.setup(desc, SkinCpu.build(desc, 48), planner, info, PALETTE[n % PALETTE.size()])
		walkers.append(rig)
	for w in walkers:
		w.planner.position.x -= 0.5 * x


func _process(_delta: float) -> void:
	var dt := 1.0 / 60.0
	time += dt
	var centre := Vector3.ZERO
	for w in walkers:
		var input := Drives.input(drive, time, 7)
		w.planner.step(dt, input.x, input.y)
		w.sync(dt)
		centre += w.planner.position
	if not walkers.is_empty():
		centre /= walkers.size()
	_cam_centre = _cam_centre.lerp(centre, 0.15) if time > dt else centre
	var span := 0.0
	for w in walkers:
		span = maxf(span, w.body.desc.bounds_m().get_longest_axis_size())
	span = 2.4 * span + (0.6 * walkers.size() if walkers.size() > 1 else 0.0)
	camera.position = _cam_centre + Vector3(0.35 * span, 0.45 * span, 0.75 * span)
	camera.look_at(_cam_centre + Vector3(0.0, 0.25, 0.0), Vector3.UP)
	if show_hud:
		var lines := PackedStringArray(["WALKER LAB  generated Stage 1 bodies on Gait Lab legs  drive: %s  t=%.1f s"
				% [drive, time]])
		for w in walkers:
			lines.append("%-16s %d legs  hip height %.2f m  speed %.2f m/s  max stance slip %.3f%%"
					% [w.name, w.leg_bones.size(), w.planner.mech.hip_height, w.planner.v,
					100.0 * w.max_stance_slip_ratio])
		hud.text = "\n".join(lines)
	if duration > 0.0 and time >= duration:
		get_tree().quit()


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.5, 0.78)
	sky_mat.sky_horizon_color = Color(0.72, 0.8, 0.88)
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.31, 0.29)
	mat.roughness = 0.95
	plane.material = mat
	ground.mesh = plane
	add_child(ground)
	camera = Camera3D.new()
	camera.fov = 45.0
	add_child(camera)
	if show_hud:
		var layer := CanvasLayer.new()
		add_child(layer)
		hud = Label.new()
		hud.position = Vector2(16, 12)
		hud.add_theme_font_size_override("font_size", 17)
		hud.add_theme_color_override("font_outline_color", Color.BLACK)
		hud.add_theme_constant_override("outline_size", 5)
		layer.add_child(hud)
