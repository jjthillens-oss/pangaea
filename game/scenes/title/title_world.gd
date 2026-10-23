class_name TitleWorld
extends Node3D
## The living scene behind the title screen (UI pass, "alive like Spore, in Pangaea's style"):
## the deep-blue microscopic sea with the pool's own light, fog and art's drifting ambience, a few
## of art's shells and landmarks in the haze, and the player's cell swimming lazy loops as the
## star of the screen, with two other cells passing in the distance. A slow camera drifts around
## the hero. It only draws: nothing here touches a save or the sim.
##
## The hero swims with the game's own Locomotion and its phenotype, so it moves the way that body
## moves in play. show_genome() swaps the body (the saved lineage, or the body picked on the New
## lineage screen) with a little pop. `motion` scales the camera's drift (Reduce camera motion).
##
## The ambience scene looks for `cell_view` and `camera` on its parent, as it does on the pool.

const ENVIRONMENT := preload("res://game/scenes/pool/pool_environment.tres")
const BACKDROP_SHADER := preload("res://game/scenes/pool/backdrop.gdshader")
const CELL_SCENE := preload("res://game/scenes/pool/player_cell_view.tscn")
const AMBIENCE_SCENE := "res://game/scenes/pool/ambience/ambience.tscn"
const DT := 1.0 / 60.0
## Art's pieces set around the stage: [file, position, yaw (deg), scale]. Below and behind the swim
## plane, so they read through the haze like the far side of the sea.
const DECOR := [
	["landmark_great_shell", Vector3(-13.0, -15.0, -21.0), 30.0, 1.0],
	["landmark_b1_sponge_tower", Vector3(11.0, -8.0, -17.0), -20.0, 1.0],
	["landmark_spire", Vector3(16.0, -9.0, -22.0), 70.0, 1.0],
	["landmark_b1_foram_spiral", Vector3(-17.0, -8.0, -26.0), 10.0, 1.0],
	["shell_radiolarian_lens", Vector3(4.2, -3.2, -6.5), 40.0, 1.0],
	["shell_diatom_disc", Vector3(-4.8, -3.6, -8.0), -35.0, 1.0],
	["rock_a", Vector3(6.5, -4.2, -9.0), 15.0, 1.0],
	["rock_c", Vector3(-7.5, -4.5, -11.0), -60.0, 1.0],
	["algae_ball", Vector3(3.4, -1.4, -3.2), 0.0, 1.0],
	["bead_cluster", Vector3(-0.6, -1.6, -3.0), 0.0, 1.0],
]
## Where the hero loops (plane metres) and how wide its loops are.
const STAGE := Vector2(0.0, 0.0)
const LOOP := Vector2(1.6, 0.9)
const LOOP_HZ := 0.035
const THROTTLE := 0.55
## The camera: its distance and height from the hero, and its slow drift around it.
const CAM_DISTANCE := 4.0
const CAM_HEIGHT := 2.9
const CAM_DRIFT_DEG := 14.0
const CAM_DRIFT_HZ := 0.02
const CAM_FOLLOW_HALF_LIFE_S := 0.6
## The hero sits right of centre, so the menu on the left never covers it.
const FRAME := Vector2(-1.15, 0.0)
const FRAME_HALF_LIFE_S := 0.35
const POP_S := 0.35

var camera: Camera3D
## The hero's view: the ambience reads it as the pool's player.
var cell_view: PlayerCellView
var hero: PlayerCellView:
	get:
		return cell_view
var motion := 1.0
## The genome the hero shows now (null before the first show_genome).
var hero_genome: Genome
## How far the camera slides along its right and up (metres) so the hero sits clear of the menus
## (negative x puts the hero right of centre); the screens set it and the camera eases there.
var frame := FRAME
## How wide the hero's loops are (1 = LOOP); the picker narrows them so the body stays in view.
var roam := 1.0

var _swimmers: Array[Dictionary] = []   ## {view, state, phenotype, anchor, loop, phase, hz, throttle}
var _t := 0.0
var _accum := 0.0
var _look := Vector3.ZERO
var _pop_t := -1.0
var _frame := FRAME


func _ready() -> void:
	_build_world()


## The hero becomes this body.
func show_genome(genome: Genome, phenotype: Phenotype) -> void:
	if cell_view == null:
		_build_world()
	cell_view.build(genome, phenotype)
	hero_genome = genome
	_swimmers[0].phenotype = phenotype
	_pop_t = 0.0


## Two other starting bodies, smaller in the distance, so the sea is shared.
func set_companions(bodies: Array, catalog: PartCatalog) -> void:
	if cell_view == null:
		_build_world()
	for i in range(1, _swimmers.size()):
		var s: Dictionary = _swimmers[i]
		var body: String = bodies[(i - 1) % bodies.size()] if not bodies.is_empty() else "grazer"
		var founded := Lineage.found(0, BuildInfo.build_id(), catalog, body)
		if founded.ok:
			var genome: Genome = founded.save.genome
			var p := Phenotype.derive(genome, catalog)
			(s.view as PlayerCellView).build(genome, p)
			s.phenotype = p


func _build_world() -> void:
	if cell_view != null:
		return
	var env := WorldEnvironment.new()
	env.environment = ENVIRONMENT
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.transform = Transform3D(Basis(Vector3(-0.7071068, 0, 0.7071068), Vector3(0.579228, 0.5735764, 0.579228),
		Vector3(-0.4055798, 0.819152, -0.4055798)), Vector3(0, 20, 0))
	sun.light_color = Color(0.957, 0.918, 0.824)
	sun.light_energy = 1.5
	add_child(sun)
	var glow := DirectionalLight3D.new()
	glow.name = "DepthGlow"
	glow.transform = Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, -0.5735764, 0.819152), Vector3(0, -0.819152, -0.5735764)), Vector3(0, 20, 0))
	glow.light_color = Color(0.298, 0.608, 0.878)
	glow.light_cull_mask = 0
	glow.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(glow)
	var backdrop := MeshInstance3D.new()
	backdrop.name = "Backdrop"
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	var mat := ShaderMaterial.new()
	mat.shader = BACKDROP_SHADER
	plane.material = mat
	backdrop.mesh = plane
	backdrop.position = Vector3(0, -40, 0)
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(backdrop)
	for item in DECOR:
		var path := "res://assets/export/%s.glb" % item[0]
		if not ResourceLoader.exists(path):
			continue
		var node: Node3D = (load(path) as PackedScene).instantiate()
		node.name = str(item[0])
		node.position = item[1]
		node.rotation.y = deg_to_rad(item[2])
		node.scale = Vector3.ONE * float(item[3])
		add_child(node)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 40.0
	camera.near = 0.05
	camera.far = 200.0
	add_child(camera)
	camera.current = true

	# The hero, then two companions further out on wider, slower loops.
	var specs := [
		{"anchor": STAGE, "loop": LOOP, "hz": LOOP_HZ, "phase": 0.0, "throttle": THROTTLE},
		{"anchor": Vector2(-5.5, 7.5), "loop": Vector2(3.0, 1.4), "hz": 0.022, "phase": 1.7, "throttle": 0.45},
		{"anchor": Vector2(5.0, 10.0), "loop": Vector2(2.5, 1.8), "hz": 0.018, "phase": 4.1, "throttle": 0.4},
	]
	for spec in specs:
		var view: PlayerCellView = CELL_SCENE.instantiate()
		add_child(view)
		var start: Vector2 = spec.anchor + _loop_point(spec, 0.0)
		var state := Locomotion.MotionState.new(start, 0.0)
		var s: Dictionary = spec.duplicate()
		s.view = view
		s.state = state
		s.phenotype = null
		_swimmers.append(s)
	cell_view = _swimmers[0].view
	_look = PlaneSpace.to_world(STAGE)
	if ResourceLoader.exists(AMBIENCE_SCENE):
		var ambience: Node = (load(AMBIENCE_SCENE) as PackedScene).instantiate()
		ambience.name = "Ambience"
		add_child(ambience)
	_place_camera(1.0)


func _loop_point(spec: Dictionary, t: float) -> Vector2:
	var a := TAU * float(spec.hz) * t + float(spec.phase)
	var loop: Vector2 = spec.loop
	# A lazy figure of eight, so the cell turns both ways and shows both sides.
	return Vector2(loop.x * sin(a), loop.y * sin(2.0 * a))


func _process(delta: float) -> void:
	_accum = minf(_accum + delta, 0.25)
	while _accum >= DT:
		_accum -= DT
		_t += DT
		for s in _swimmers:
			_step(s)
	var fraction := _accum / DT
	for s in _swimmers:
		if s.phenotype != null:
			(s.view as PlayerCellView).show_motion(s.state, fraction)
	if _pop_t >= 0.0:
		_pop_t += delta
		var k := clampf(_pop_t / POP_S, 0.0, 1.0)
		# A soft pop in: a little overshoot, then settle.
		cell_view.scale = Vector3.ONE * (lerpf(0.6, 1.0, k) + 0.15 * sin(k * PI))
		if k >= 1.0:
			cell_view.scale = Vector3.ONE
			_pop_t = -1.0
	_frame = _frame.lerp(frame, 1.0 - pow(0.5, delta / FRAME_HALF_LIFE_S))
	_place_camera(1.0 - pow(0.5, delta / CAM_FOLLOW_HALF_LIFE_S))


func _step(s: Dictionary) -> void:
	var p: Phenotype = s.phenotype
	if p == null:
		return
	var m: Locomotion.MotionState = s.state
	var target: Vector2 = s.anchor + _loop_point(s, _t + 1.5) * (roam if s.view == cell_view else 1.0)
	var to := target - m.position
	var move := to.normalized() * float(s.throttle) * clampf(to.length() / 0.5, 0.0, 1.0)
	Locomotion.steer(m, move, p, 1.0, DT)
	m.prev_position = m.position
	m.position += m.velocity * DT


func _place_camera(follow: float) -> void:
	if camera == null or cell_view == null:
		return
	var focus := cell_view.position
	_look = _look.lerp(focus, follow)
	var drift := deg_to_rad(CAM_DRIFT_DEG) * sin(TAU * CAM_DRIFT_HZ * _t) * motion
	var back := Vector3(sin(drift), 0.0, cos(drift)) * CAM_DISTANCE
	var eye := _look + back + Vector3(0.0, CAM_HEIGHT, 0.0)
	camera.look_at_from_position(eye, _look, Vector3.UP)
	# Slide the view so the hero sits clear of the menus.
	camera.position += camera.basis.x * _frame.x + camera.basis.y * _frame.y
