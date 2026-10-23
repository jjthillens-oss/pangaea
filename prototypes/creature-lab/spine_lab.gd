extends Node3D
## Spine Lab viewer (prototypes 0b and Stage 1). Command line (after --): --body=NAME|all|stage1,
## --anim=swim|pose|rest|live, --duration=SECONDS, --divisions=N (skin grid), --hud=0, --skin=art|plain (the art
## team's creature skin shader, or flat colours). Bodies with parts wear the art team's part meshes. "all" shows the spine bodies,
## "stage1" the ten Stage 1 bodies with limbs (names s1_*). "pose" sweeps the spine through +-60 degrees and the limbs
## through +-90 degrees (CREATURE_GEOMETRY_SPEC.md section 10 test 6). "live" rebuilds the skin every frame while one
## vertebra moves, to show rebuild cost.

const Lab := preload("res://lab_spine.gd")
const SkinCpu := preload("res://skin/skin_cpu.gd")
const SpineRig := preload("res://rig/spine_rig.gd")
const BodyField := preload("res://domain/body_field.gd")
const AnchorResolver := preload("res://domain/anchor_resolver.gd")

const PALETTE := [Color(0.93, 0.55, 0.36), Color(0.36, 0.66, 0.86), Color(0.52, 0.78, 0.45), Color(0.86, 0.72, 0.36),
		Color(0.72, 0.5, 0.86), Color(0.86, 0.45, 0.56), Color(0.45, 0.8, 0.76)]

var body_choice := "all"
var anim := "swim"
var duration := 0.0
var divisions := 48
var show_hud := true
var art_skin := true

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
			"skin": art_skin = kv[1] != "plain"
	_build_world()
	var orientations := Lab.part_orientations(Lab.part_rules())
	var names: Array = Lab.BODY_NAMES if body_choice == "all" else (Lab.stage1_names() if body_choice == "stage1"
			else [body_choice])
	# Display only: each body is scaled to about 1 m long and turned side-on (three-quarter view for bodies with
	# limbs), in rows of four or five; the HUD gives real sizes.
	var columns := mini(5 if names.size() > 8 else 4, names.size())
	for n in names.size():
		var desc = Lab.body(names[n])
		var arrays := SkinCpu.build(desc, divisions)
		_build_ms.append(arrays["ms"]["total"])
		var rig = SpineRig.new()
		rig.name = names[n]
		add_child(rig)
		rig.setup(desc, arrays, PALETTE[n % PALETTE.size()])
		if not desc.parts.is_empty():
			rig.add_parts(AnchorResolver.resolve_all(desc, BodyField.from_description(desc), orientations), orientations)
		if art_skin:
			rig.use_skin_shader({"color_base": PALETTE[n % PALETTE.size()], "pattern_seed": n, "coat_pattern": 1 + n % 3,
					"detail_pattern": [2, 1, 3, 0][n % 4]})
		var box: AABB = desc.bounds_m()
		var k := 1.0 / box.get_longest_axis_size()
		rig.scale = Vector3.ONE * k
		rig.rotation.y = -0.5 * PI + (0.6 if not desc.limbs.is_empty() else 0.0)
		var slot := Vector3((n % columns - 0.5 * (columns - 1)) * 1.4, 0.0, (n / columns) * 1.3)
		var centre: Vector3 = rig.transform.basis * box.get_center()
		rig.position = slot + Vector3(-centre.x, -box.position.y * k + 0.02, -centre.z)
		rigs.append(rig)
	_place_camera(1.4 * columns, int(ceil(names.size() / float(columns))))


func _process(delta: float) -> void:
	var dt := 1.0 / 60.0
	time += dt
	if anim == "swim":
		for r in rigs:
			r.swim(dt)
	elif anim == "pose":
		for r in rigs:
			r.pose_sweep(time)
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
		var lines := PackedStringArray(["SPINE LAB  (0b + Stage 1)  anim: %s  grid: length/%d  t=%.1f s" % [anim, divisions, time]])
		for n in rigs.size():
			var r = rigs[n]
			lines.append("%-16s %4.2f m  %2d vertebrae  %2d limbs  %5d triangles  skin build %.0f ms (GDScript)"
					% [r.name, r.desc.bounds_m().get_longest_axis_size(), r.desc.vertebrae.size(), r.limb_roots.size(),
					r.mesh_instance.mesh.surface_get_array_index_len(0) / 3, _build_ms[n]])
		hud.text = "\n".join(lines)
	if duration > 0.0 and time >= duration:
		get_tree().quit()


func _place_camera(span: float, rows: int) -> void:
	var depth := 1.3 * (rows - 1)
	var dist := (0.62 if span > 6.0 else 0.8) * span + 1.2
	camera.position = Vector3(0.0, 0.5 * dist, depth + 0.85 * dist)
	camera.look_at(Vector3(0.0, 0.15, 0.5 * depth), Vector3.UP)


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


func _exit_tree() -> void:
	load("res://rig/part_library.gd").clear()
