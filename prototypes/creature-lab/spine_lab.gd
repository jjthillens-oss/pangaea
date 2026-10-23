extends Node3D
## Spine Lab (prototype 0b) viewer. Command line (after --): --body=NAME|all, --anim=swim|rest|live,
## --duration=SECONDS, --divisions=N (skin grid), --hud=0. "live" rebuilds the skin every frame while one vertebra
## moves, to show rebuild cost.

const Lab := preload("res://lab_spine.gd")
const SkinCpu := preload("res://skin/skin_cpu.gd")
const SpineRig := preload("res://rig/spine_rig.gd")

const PALETTE := [Color(0.93, 0.55, 0.36), Color(0.36, 0.66, 0.86), Color(0.52, 0.78, 0.45), Color(0.86, 0.72, 0.36),
		Color(0.72, 0.5, 0.86), Color(0.86, 0.45, 0.56), Color(0.45, 0.8, 0.76)]

var body_choice := "all"
var anim := "swim"
var duration := 0.0
var divisions := 48
var show_hud := true

var rigs: Array = []
var time := 0.0
var camera: Camera3D
var hud: Label
var _build_ms := []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"body": body_choice = kv[1]
			"anim": anim = kv[1]
			"duration": duration = float(kv[1])
			"divisions": divisions = int(kv[1])
			"hud": show_hud = kv[1] != "0"
	_build_world()
	var names: Array = Lab.BODY_NAMES if body_choice == "all" else [body_choice]
	var x := 0.0
	for n in names.size():
		var desc = Lab.body(names[n])
		var arrays := SkinCpu.build(desc, divisions)
		_build_ms.append(arrays["ms"]["total"])
		var rig = SpineRig.new()
		rig.name = names[n]
		add_child(rig)
		rig.setup(desc, arrays, PALETTE[n % PALETTE.size()])
		var box: AABB = desc.bounds_m()
		if n > 0:
			x += 0.5 * box.size.x + 0.4
		rig.position = Vector3(x - box.get_center().x, -box.position.y + 0.02, -box.get_center().z)
		x += 0.5 * box.size.x
		rigs.append(rig)
	var span := x
	for r in rigs:
		r.position.x -= 0.5 * span
	_place_camera(span)


func _process(delta: float) -> void:
	var dt := 1.0 / 60.0
	time += dt
	if anim == "swim":
		for r in rigs:
			r.swim(dt)
	elif anim == "live":
		for n in rigs.size():
			var r = rigs[n]
			var mid: int = r.desc.vertebrae.size() / 2
			var p: Array = r.desc.vertebrae[mid]["p"]
			p[1] = int(round(120.0 * sin(TAU * 0.5 * time)))
			var arrays := SkinCpu.build(r.desc, divisions)
			_build_ms[n] = arrays["ms"]["total"]
			r.mesh_instance.mesh = SpineRig.build_mesh(arrays, PALETTE[n % PALETTE.size()])
	if show_hud:
		var lines := PackedStringArray(["SPINE LAB  (prototype 0b)  anim: %s  grid: length/%d  t=%.1f s" % [anim, divisions, time]])
		for n in rigs.size():
			var r = rigs[n]
			lines.append("%-8s %2d vertebrae  %5d triangles  skin build %.0f ms (GDScript)"
					% [r.name, r.desc.vertebrae.size(), r.mesh_instance.mesh.surface_get_array_index_len(0) / 3,
					_build_ms[n]])
		hud.text = "\n".join(lines)
	if duration > 0.0 and time >= duration:
		get_tree().quit()


func _place_camera(span: float) -> void:
	var dist := 0.9 * span + 1.5
	camera.position = Vector3(0.35 * span, 0.55 * dist, 0.75 * dist)
	camera.look_at(Vector3(0.0, 0.25, 0.0), Vector3.UP)


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
	plane.size = Vector2(60.0, 60.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.29, 0.27)
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
