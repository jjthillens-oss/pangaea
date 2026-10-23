extends Node3D
## Gait Lab scene. Keyboard: hold W to move (1 walk, 2 trot, 3 run sets the pace), S backs up, A/D turn, Tab changes
## the body, R resets. Command line (after --): --body=quad_short|quad_long|hexapod|all, --drive=keyboard|demo|walk|
## trot|run|turn_in_place|reversal|random, --duration=SECONDS (quit after), --hud=0 to hide the text.

const Lab := preload("res://lab_data.gd")
const Drives := preload("res://lab_drives.gd")
const CreatureRig := preload("res://rig/creature_rig.gd")

const COLORS := {"quad_short": Color(0.86, 0.55, 0.25), "quad_long": Color(0.3, 0.62, 0.85),
		"hexapod": Color(0.45, 0.75, 0.4)}
const FOOTPRINTS := 160

var body_choice := "quad_short"
var drive := "keyboard"
var duration := 0.0
var show_hud := true
var pace := 0.3

var rigs: Array = []
var time := 0.0
var camera: Camera3D
var hud: Label
var _footprints: Array[MeshInstance3D] = []
var _next_print := 0
var _last_state: Array = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"body": body_choice = kv[1]
			"drive": drive = kv[1]
			"duration": duration = float(kv[1])
			"hud": show_hud = kv[1] != "0"
	_build_world()
	_spawn()


func _spawn() -> void:
	for r in rigs:
		r.queue_free()
	rigs.clear()
	_last_state.clear()
	time = 0.0
	var names: Array = Lab.BODY_NAMES if body_choice == "all" else [body_choice]
	var bodies: Dictionary = Lab.read_json("res://data/test_bodies.json")["bodies"]
	var table = Lab.table()
	for n in names.size():
		var body_name: String = names[n]
		var mech = Lab.BodyMechanics.create(body_name, bodies[body_name], table)
		var start := Vector3((n - (names.size() - 1) * 0.5) * 2.5, 0.0, 0.0)
		var planner = Lab.GaitPlanner.create(mech, start, 0.0)
		var rig = CreatureRig.new()
		rig.name = body_name
		add_child(rig)
		rig.setup(planner, bodies[body_name], COLORS[body_name])
		rig.sync(0.0)
		rigs.append(rig)
		_last_state.append(planner.state.duplicate())


func _process(delta: float) -> void:
	var dt := 1.0 / 60.0 if drive != "keyboard" else minf(delta, 1.0 / 30.0)
	var input := Drives.input(drive, time) if drive != "keyboard" else _keyboard_input()
	for n in rigs.size():
		var p = rigs[n].planner
		p.step(dt, input.x, input.y)
		rigs[n].sync(dt)
		for i in p.foot.size():
			if _last_state[n][i] == 1 and p.state[i] == 0:
				_drop_footprint(p.foot[i], p.mech.legs[i]["length"])
		_last_state[n] = p.state.duplicate()
	time += dt
	_update_camera(dt)
	if show_hud:
		_update_hud(input)
	if duration > 0.0 and time >= duration:
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_1: pace = 0.3
		KEY_2: pace = 0.6
		KEY_3: pace = 1.0
		KEY_R: _spawn()
		KEY_TAB:
			var order := ["quad_short", "quad_long", "hexapod", "all"]
			body_choice = order[(order.find(body_choice) + 1) % order.size()]
			_spawn()


func _keyboard_input() -> Vector2:
	var throttle := 0.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		throttle = pace
	elif Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		throttle = -0.3
	var turn := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		turn += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		turn -= 1.0
	return Vector2(throttle, turn)


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.5, 0.78)
	sky_mat.sky_horizon_color = Color(0.72, 0.8, 0.88)
	sky_mat.ground_horizon_color = Color(0.6, 0.62, 0.6)
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(600.0, 600.0)
	var grid := ShaderMaterial.new()
	grid.shader = Shader.new()
	grid.shader.code = """
shader_type spatial;
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = abs(fract(world_pos.xz - 0.5) - 0.5) / fwidth(world_pos.xz);
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	vec2 c = floor(world_pos.xz * 0.2);
	float checker = mod(c.x + c.y, 2.0);
	ALBEDO = mix(vec3(0.30, 0.31, 0.28), vec3(0.26, 0.27, 0.24), checker) * (1.0 - 0.35 * line);
	ROUGHNESS = 0.95;
}
"""
	plane.material = grid
	ground.mesh = plane
	add_child(ground)
	var print_mat := StandardMaterial3D.new()
	print_mat.albedo_color = Color(0.2, 0.18, 0.16)
	print_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for k in FOOTPRINTS:
		var fp := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 1.0
		disc.bottom_radius = 1.0
		disc.height = 0.002
		disc.radial_segments = 16
		disc.material = print_mat
		fp.mesh = disc
		fp.visible = false
		fp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fp)
		_footprints.append(fp)
	camera = Camera3D.new()
	camera.fov = 50.0
	add_child(camera)
	if show_hud:
		var layer := CanvasLayer.new()
		add_child(layer)
		hud = Label.new()
		hud.position = Vector2(16, 12)
		hud.add_theme_font_size_override("font_size", 18)
		hud.add_theme_color_override("font_outline_color", Color.BLACK)
		hud.add_theme_constant_override("outline_size", 5)
		layer.add_child(hud)


func _drop_footprint(at: Vector3, leg_length: float) -> void:
	var fp := _footprints[_next_print]
	_next_print = (_next_print + 1) % FOOTPRINTS
	fp.scale = Vector3.ONE * 0.06 * leg_length / 0.5
	fp.scale.y = 1.0
	fp.position = Vector3(at.x, 0.002, at.z)
	fp.visible = true


func _update_camera(dt: float) -> void:
	var centre := Vector3.ZERO
	var size := 0.0
	for r in rigs:
		centre += r.planner.position
		size = maxf(size, r.planner.mech.hip_height)
	centre /= maxf(1.0, rigs.size())
	var yaw: float = rigs[0].planner.yaw if rigs.size() == 1 else 0.0
	var distance := 1.4 + 3.6 * size + (3.5 if rigs.size() > 1 else 0.0)
	# Three-quarter view from the front-left of the lead body, smoothed.
	var offset := Basis(Vector3.UP, yaw + deg_to_rad(-40.0)) * Vector3(0.0, 0.0, -1.0) * distance
	var eye := centre + offset + Vector3.UP * (0.55 * distance)
	var k := 1.0 if time <= dt else 1.0 - exp(-3.0 * dt)
	camera.global_position = camera.global_position.lerp(eye, k)
	camera.look_at(centre + Vector3.UP * 0.5 * size, Vector3.UP)


func _update_hud(input: Vector2) -> void:
	var lines := PackedStringArray()
	lines.append("GAIT LAB  (prototype; W/S A/D, 1-2-3 pace, Tab body, R reset)" if drive == "keyboard"
			else "GAIT LAB  drive: %s  t=%.1f s" % [drive, time])
	for r in rigs:
		var p = r.planner
		var cadence: float = 0.0 if not is_finite(p.period) else 1.0 / p.period
		lines.append("%-10s  leg %.2f m  %-4s  %.2f m/s  Fr %.2f  %.2f steps/s  max slip %.2f%%  knee flips %d"
				% [p.mech.name, p.mech.legs[0]["length"], p.table.bands[p.band]["name"], absf(p.v),
				p.froude_now, cadence, 100.0 * r.max_stance_slip_ratio, r.knee_flips])
	hud.text = "\n".join(lines)
