class_name CreatureWorld
extends Node3D
## The creature stage's test field, presented (PROPOSED, creature-stage-plan.md section 5). It owns a
## CreatureWorldSim, steps it once per physics frame with the player's intent and only draws its state: the
## player's and the rivals' bodies on WalkerRigs (the legs animated by the sim's own gait planners), the fruit bushes
## and meat as MultiMeshes, the nest ring and the field. Input: move_* relative to the camera, creature_bite,
## creature_evolve; the right stick or a middle-drag orbits the camera. set_intent() scripts the drive (smokes and
## tests), and while it is set the keyboard and pad are ignored.
##
## Placeholders (assets/records/placeholders/inventory.json): the field plane, the nest ring, the fruit spheres and
## the meat boxes, until the creature stage art pass. Rival skins are built once at setup on the CPU builder, at
## their preview grid clamped to RIVAL_SKIN_DIVISIONS_MAX; rivals beyond RIVAL_LOD_M only move their bodies, their
## legs are not solved. No audio.

signal evolve_requested(points: int)
signal died(cause: String)

const Sim := preload("res://game/systems/creature/creature_world_sim.gd")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const SkinCpu := preload("res://game/systems/creature/skin_cpu.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const BodyField := preload("res://game/domain/creature/body_field.gd")
const AnchorResolver := preload("res://game/domain/creature/anchor_resolver.gd")
const WalkerRig := preload("res://game/scenes/creature/walker_rig.gd")
const SpineRig := preload("res://game/scenes/creature/spine_rig.gd")

const PLAYER_SKIN_DIVISIONS_MAX := 48
const RIVAL_SKIN_DIVISIONS_MAX := 32
const RIVAL_LOD_M := 40.0
const MEAT_INSTANCES_MAX := 64
const NO_LEGS_NOTICE := "This creature needs legs to walk"
const DEATH_NOTICE := "You were %s. Back at the nest; %d points lost."
## Camera (PROPOSED): behind and above, the distance from the body length, orbit by the right stick or a middle-drag.
const CAMERA_DISTANCE_PER_BODY_M := 3.2
const CAMERA_DISTANCE_MIN_M := 3.0
const CAMERA_DISTANCE_MAX_M := 14.0
const CAMERA_PITCH_DEG := 22.0
const CAMERA_PITCH_MIN_DEG := 5.0
const CAMERA_PITCH_MAX_DEG := 70.0
const CAMERA_STICK_RAD_S := 2.4
const CAMERA_DRAG_RAD_PX := 0.006
const CAMERA_FOLLOW_HALF_LIFE_S := 0.1
## With no orbit input for this long, the camera eases round behind a moving creature.
const CAMERA_REALIGN_AFTER_S := 1.5
const CAMERA_REALIGN_HALF_LIFE_S := 1.2
const STICK_DEADZONE := 0.25
const PALETTE := [Color(0.36, 0.66, 0.86), Color(0.52, 0.78, 0.45), Color(0.86, 0.72, 0.36),
		Color(0.72, 0.5, 0.86), Color(0.86, 0.45, 0.56), Color(0.45, 0.8, 0.76), Color(0.8, 0.8, 0.5)]
const PLAYER_COLOR := Color(0.93, 0.55, 0.36)
const FIELD_COLOR := Color(0.36, 0.47, 0.27)
const NEST_COLOR := Color(0.78, 0.66, 0.42)
const FRUIT_RIPE_COLOR := Color(0.82, 0.3, 0.32)
const FRUIT_BARE_COLOR := Color(0.3, 0.45, 0.24)
const MEAT_COLOR := Color(0.6, 0.2, 0.18)

var sim: CreatureWorldSim
var tuning := {}
var data := {}
var player_rig: Node3D
var rival_rigs := {}
var notice := ""
## Setup timings in ms: {player_skin, rival_skins, rigs, total}.
var setup_ms := {}
var camera_yaw := 0.0
var camera_pitch := deg_to_rad(CAMERA_PITCH_DEG)
var camera_distance := 6.0
var _focus := Vector3.ZERO
var _since_orbit := INF
var _scripted := false
var _intent := {"move": Vector2.ZERO, "bite": false, "evolve": false}
var _last_tick_events: Array = []

var camera: Camera3D
var hud: Control
var _rivals_node: Node3D
var _fruit_mm: MultiMeshInstance3D
var _meat_mm: MultiMeshInstance3D


## Builds the field for `body_dict` (a codec dictionary) at `world_seed`, with `points` to start.
func setup(body_dict: Dictionary, world_seed: int, points: int) -> void:
	var t0 := Time.get_ticks_msec()
	# Resolved here, not @onready: a headless test adds the scene before the tree's first frame readies it.
	camera = $Camera
	hud = $UI/Hud
	_rivals_node = $Rivals
	tuning = Sim.load_tuning()
	data = Sim.load_data()
	sim = Sim.new(body_dict, world_seed, tuning, data)
	sim.points = points
	_build_ground()
	_build_food()
	var t1 := Time.get_ticks_msec()
	_build_player()
	var t2 := Time.get_ticks_msec()
	var skin_ms := 0
	for r in sim.rivals:
		var s := Time.get_ticks_msec()
		var rig := _build_rig(r["id"], r["body"], RIVAL_SKIN_DIVISIONS_MAX, PALETTE[rival_rigs.size() % PALETTE.size()],
				rival_rigs.size() + 1)
		skin_ms += Time.get_ticks_msec() - s
		_rivals_node.add_child(rig)
		rival_rigs[r["id"]] = rig
	var t3 := Time.get_ticks_msec()
	setup_ms = {"player_skin": t2 - t1, "rival_skins": skin_ms, "rigs": t3 - t2, "total": t3 - t0}
	var p: Dictionary = sim.player()
	camera_distance = clampf(CAMERA_DISTANCE_PER_BODY_M * float(p.get("body_length_m", _body_length(sim.body_of("player")))),
			CAMERA_DISTANCE_MIN_M, CAMERA_DISTANCE_MAX_M)
	_focus = _focus_point()
	_place_camera()
	hud.bind(self)
	if not p["has_legs"]:
		notice = NO_LEGS_NOTICE
		hud.show_notice(NO_LEGS_NOTICE, true)


## Scripted drive: `move` is camera-relative (x right, y forward, -1..1). Keyboard and pad are ignored until
## clear_intent().
func set_intent(move: Vector2, bite: bool, evolve: bool) -> void:
	_scripted = true
	_intent = {"move": move, "bite": bite, "evolve": evolve}


func clear_intent() -> void:
	_scripted = false
	_intent = {"move": Vector2.ZERO, "bite": false, "evolve": false}


func snapshot() -> Dictionary:
	var out := sim.snapshot() if sim else {}
	out["camera_yaw"] = camera_yaw
	out["notice"] = notice
	out["setup_ms"] = setup_ms
	return out


func last_events() -> Array:
	return _last_tick_events


func _physics_process(_delta: float) -> void:
	if sim == null:
		return
	var intent := _intent.duplicate() if _scripted else _read_input()
	intent["move"] = _camera_relative_to_world(intent["move"])
	_last_tick_events = sim.tick(intent)
	for e in _last_tick_events:
		_on_event(e)


func _process(delta: float) -> void:
	if sim == null:
		return
	_sync_rigs(delta)
	_orbit(delta)
	_follow_camera(delta)
	_draw_food()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		camera_yaw -= rel.x * CAMERA_DRAG_RAD_PX
		camera_pitch = clampf(camera_pitch + rel.y * CAMERA_DRAG_RAD_PX, deg_to_rad(CAMERA_PITCH_MIN_DEG),
				deg_to_rad(CAMERA_PITCH_MAX_DEG))
		_since_orbit = 0.0


func _read_input() -> Dictionary:
	var keys := Input.get_vector(&"move_left", &"move_right", &"move_down", &"move_up")
	return {"move": keys, "bite": Input.is_action_pressed(&"creature_bite"), "evolve": Input.is_action_pressed(&"creature_evolve")}


## A camera-relative move (x right, y forward) as the sim's ground direction (x along +X, y along +Z).
func _camera_relative_to_world(move: Vector2) -> Vector2:
	if move.length_squared() < 1e-9:
		return Vector2.ZERO
	var forward := Vector2(-sin(camera_yaw), -cos(camera_yaw))
	var right := Vector2(-forward.y, forward.x)
	var out := right * move.x + forward * move.y
	return out.limit_length(1.0)


func _on_event(e: Dictionary) -> void:
	match e["kind"]:
		"ate":
			if e["who"] == Sim.PLAYER_ID:
				hud.flash_points(int(e["points"]))
				hud.refresh()
		"died":
			if e["who"] == Sim.PLAYER_ID:
				notice = DEATH_NOTICE % [e["cause"], int(e["points_lost"])]
				hud.show_notice(notice)
				hud.refresh()
				_focus = _focus_point()
				died.emit(String(e["cause"]))
		"evolve":
			evolve_requested.emit(int(e["points"]))
		"refused":
			notice = String(e["reason"])
			hud.show_notice(notice)


func _build_ground() -> void:
	var field := MeshInstance3D.new()
	field.name = "Field"
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0 * sim.half_size, 2.0 * sim.half_size)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = FIELD_COLOR
	mat.roughness = 0.95
	plane.material = mat
	field.mesh = plane
	add_child(field)
	var nest := MeshInstance3D.new()
	nest.name = "Nest"
	var ring := TorusMesh.new()
	ring.inner_radius = sim.nest_radius - 0.5
	ring.outer_radius = sim.nest_radius
	ring.rings = 48
	ring.ring_segments = 8
	var nest_mat := StandardMaterial3D.new()
	nest_mat.albedo_color = NEST_COLOR
	nest_mat.roughness = 0.9
	ring.material = nest_mat
	nest.mesh = ring
	nest.scale = Vector3(1.0, 0.12, 1.0)
	nest.position = sim.nest
	add_child(nest)


func _build_food() -> void:
	_fruit_mm = MultiMeshInstance3D.new()
	_fruit_mm.name = "Fruit"
	var bush := SphereMesh.new()
	bush.radius = Sim.FRUIT_RADIUS_M
	bush.height = 2.0 * Sim.FRUIT_RADIUS_M
	bush.radial_segments = 12
	bush.rings = 6
	var bush_mat := StandardMaterial3D.new()
	bush_mat.vertex_color_use_as_albedo = true
	bush_mat.roughness = 0.85
	bush.material = bush_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bush
	mm.instance_count = sim.fruit.size()
	_fruit_mm.multimesh = mm
	add_child(_fruit_mm)
	_meat_mm = MultiMeshInstance3D.new()
	_meat_mm.name = "Meat"
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 2.0 * Sim.MEAT_RADIUS_M
	var meat_mat := StandardMaterial3D.new()
	meat_mat.albedo_color = MEAT_COLOR
	meat_mat.roughness = 0.7
	box.material = meat_mat
	var mmm := MultiMesh.new()
	mmm.transform_format = MultiMesh.TRANSFORM_3D
	mmm.mesh = box
	mmm.instance_count = MEAT_INSTANCES_MAX
	mmm.visible_instance_count = 0
	_meat_mm.multimesh = mmm
	add_child(_meat_mm)
	_draw_food()


func _draw_food() -> void:
	var mm := _fruit_mm.multimesh
	for i in sim.fruit.size():
		var f: Dictionary = sim.fruit[i]
		var s := 1.0 if f["ripe"] else 0.45
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s * 0.8, s)),
				(f["position"] as Vector3) + Vector3(0.0, 0.4 * s, 0.0)))
		mm.set_instance_color(i, FRUIT_RIPE_COLOR if f["ripe"] else FRUIT_BARE_COLOR)
	var meat := _meat_mm.multimesh
	var n := mini(sim.meat.size(), MEAT_INSTANCES_MAX)
	meat.visible_instance_count = n
	for i in n:
		meat.set_instance_transform(i, Transform3D(Basis(), (sim.meat[i]["position"] as Vector3) + Vector3(0.0, Sim.MEAT_RADIUS_M, 0.0)))


func _build_player() -> void:
	var body = sim.body_of(Sim.PLAYER_ID)
	if sim.player()["has_legs"]:
		player_rig = _build_rig(Sim.PLAYER_ID, body, PLAYER_SKIN_DIVISIONS_MAX, PLAYER_COLOR, 0)
	else:
		# No legs: the body stands at the nest as a plain rig, so the player sees what needs fixing.
		var rig := SpineRig.new()
		rig.name = Sim.PLAYER_ID
		var divisions := mini(body.preview_divisions(data["body_rules"]), PLAYER_SKIN_DIVISIONS_MAX)
		rig.setup(body, SkinCpu.build(body, divisions), PLAYER_COLOR)
		var orientations: Dictionary = CreatureData.part_orientations(data["part_rules"])
		rig.add_parts(AnchorResolver.resolve_all(body, BodyField.from_description(body), orientations), orientations)
		rig.use_skin_shader({"color_base": PLAYER_COLOR, "pattern_seed": 0, "coat_pattern": 1, "detail_pattern": 2})
		var box: AABB = body.bounds_m()
		rig.position = sim.nest - Vector3(0.0, box.position.y, 0.0)
		player_rig = rig
	add_child(player_rig)


## A walker rig on the sim's planner for `id`, its skin built once on the CPU builder at the body's preview grid
## clamped to `divisions_max`.
func _build_rig(id: String, body: RefCounted, divisions_max: int, color: Color, seed_index: int) -> Node3D:
	var rig := WalkerRig.new()
	rig.name = id
	var divisions := mini(body.preview_divisions(data["body_rules"]), divisions_max)
	var orientations: Dictionary = CreatureData.part_orientations(data["part_rules"])
	var placements: Array = AnchorResolver.resolve_all(body, BodyField.from_description(body), orientations)
	rig.setup(body, SkinCpu.build(body, divisions), sim.planner_of(id), sim.gait_of(id), color, placements, orientations)
	rig.body.use_skin_shader({"color_base": color, "pattern_seed": seed_index, "coat_pattern": 1 + seed_index % 3,
			"detail_pattern": [2, 1, 3, 0][seed_index % 4]})
	return rig


func _sync_rigs(delta: float) -> void:
	if player_rig is WalkerRig:
		_sync_walker(player_rig, Sim.PLAYER_ID, delta, true)
	var me: Vector3 = sim.player()["position"]
	for r in sim.rivals:
		var rig: Node3D = rival_rigs[r["id"]]
		rig.visible = r["alive"]
		if not r["alive"]:
			continue
		var near := (r["position"] as Vector3).distance_to(me) <= RIVAL_LOD_M
		_sync_walker(rig, r["id"], delta, near)


## Full: the planner's pose and feet, with an IK solve. Far: only the body's transform, no solve.
func _sync_walker(rig: Node3D, id: String, delta: float, full: bool) -> void:
	var planner = sim.planner_of(id)
	if planner == null:
		return
	if rig.planner != planner:
		rig.planner = planner
	if full and is_inside_tree():
		rig.sync(delta)
	else:
		# The body is top_level under a rig at the origin, so its own transform is its world transform; this also
		# serves outside the tree (a headless test before the first frame), where the IK cannot solve.
		rig.body.transform = Transform3D(Basis(Vector3.UP, planner.yaw), planner.position) \
				* planner.body_pose_local() * Transform3D(Basis(), -(rig.gait["centre"] as Vector3))


func _orbit(delta: float) -> void:
	var stick := Vector2.ZERO
	for device in Input.get_connected_joypads():
		var s := Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
		if s.length() > stick.length():
			stick = s
	if stick.length() > STICK_DEADZONE:
		camera_yaw -= stick.x * CAMERA_STICK_RAD_S * delta
		camera_pitch = clampf(camera_pitch + stick.y * CAMERA_STICK_RAD_S * delta, deg_to_rad(CAMERA_PITCH_MIN_DEG),
				deg_to_rad(CAMERA_PITCH_MAX_DEG))
		_since_orbit = 0.0
	else:
		_since_orbit += delta
	var p: Dictionary = sim.player()
	if _since_orbit > CAMERA_REALIGN_AFTER_S and p["has_legs"] and sim.planner_of(Sim.PLAYER_ID).v > 0.05:
		var k := 1.0 - pow(0.5, delta / CAMERA_REALIGN_HALF_LIFE_S)
		camera_yaw += wrapf(float(p["yaw"]) - camera_yaw, -PI, PI) * k


func _focus_point() -> Vector3:
	var p: Dictionary = sim.player()
	var body = sim.body_of(Sim.PLAYER_ID)
	var height: float = body.bounds_m().size.y if body else 1.0
	return (p["position"] as Vector3) + Vector3(0.0, 0.6 * height + 0.3, 0.0)


func _follow_camera(delta: float) -> void:
	var goal := _focus_point()
	_focus = goal.lerp(_focus, pow(0.5, delta / CAMERA_FOLLOW_HALF_LIFE_S))
	_place_camera()


func _place_camera() -> void:
	var back := Vector3(sin(camera_yaw), 0.0, cos(camera_yaw))
	var offset := back * cos(camera_pitch) * camera_distance + Vector3(0.0, sin(camera_pitch) * camera_distance, 0.0)
	camera.look_at_from_position(_focus + offset, _focus, Vector3.UP)


static func _body_length(body: RefCounted) -> float:
	return body.bounds_m().size.z if body else 1.0


func _exit_tree() -> void:
	load("res://game/scenes/creature/part_library.gd").clear()
