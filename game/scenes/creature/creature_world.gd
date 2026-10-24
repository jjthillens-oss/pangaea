class_name CreatureWorld
extends Node3D
## The creature stage's test field, presented (PROPOSED, creature-stage-plan.md section 5). It owns a
## CreatureWorldSim, steps it once per physics frame with the player's intent and only draws its state: the
## player's and the rivals' bodies on WalkerRigs (the legs animated by the sim's own gait planners), the fruit bushes
## and meat as MultiMeshes, the nest ring and the field. Input: move_* relative to the camera, creature_bite,
## creature_evolve; the right stick or a middle-drag orbits the camera. set_intent() scripts the drive (smokes and
## tests), and while it is set the keyboard and pad are ignored.
##
## The dressing is the art team's (docs/art/creature_world_dressing.md): the field ground at the origin (its 172 m
## grid covers the sim's 160 m field, its relief under 0.12 m while the sim stays flat at y = 0), the nest ring at the
## nest, and the bushes, fruit and meat as MultiMeshes of the GLBs' meshes with an instance colour each (white draws
## the asset as baked; a bare bush takes BUSH_BARE_TINT and no Fruit instance). Rival skins are built once at setup
## on the CPU builder, at their preview grid clamped to RIVAL_SKIN_DIVISIONS_MAX; rivals beyond RIVAL_LOD_M only move
## their bodies, their legs are not solved. No audio.

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
const Look := preload("res://game/scenes/creature/creature_look.gd")

const PLAYER_SKIN_DIVISIONS_MAX := 48
const RIVAL_SKIN_DIVISIONS_MAX := 32
const RIVAL_LOD_M := 40.0
const MEAT_INSTANCES_MAX := 64
const NO_LEGS_NOTICE := "This creature needs legs to walk"
const DEATH_NOTICE := "You were %s. Back at the nest; %d points lost."
## Camera (PROPOSED): behind and above, the distance from the body length (Spore-close: the creature fills a good
## part of the frame), orbit by the right stick or a middle-drag. The eye never goes under the field: it is held at
## least CAMERA_GROUND_CLEARANCE_M over the plane whatever the pitch.
const CAMERA_DISTANCE_PER_BODY_M := 2.4
const CAMERA_DISTANCE_MIN_M := 2.6
const CAMERA_DISTANCE_MAX_M := 12.0
const CAMERA_PITCH_DEG := 16.0
const CAMERA_PITCH_MIN_DEG := 3.0
const CAMERA_PITCH_MAX_DEG := 70.0
const CAMERA_GROUND_CLEARANCE_M := 0.35
const CAMERA_STICK_RAD_S := 2.4
const CAMERA_DRAG_RAD_PX := 0.006
const CAMERA_FOLLOW_HALF_LIFE_S := 0.1
## With no orbit input for this long, the camera eases round behind a moving creature.
const CAMERA_REALIGN_AFTER_S := 1.5
const CAMERA_REALIGN_HALF_LIFE_S := 1.2
const STICK_DEADZONE := 0.25
const PALETTE := [Color(0.36, 0.66, 0.86), Color(0.52, 0.78, 0.45), Color(0.86, 0.72, 0.36),
		Color(0.72, 0.5, 0.86), Color(0.86, 0.45, 0.56), Color(0.45, 0.8, 0.76), Color(0.8, 0.8, 0.5)]
## The player's colour when the body carries no skin_color (the editor writes its swatch as "rrggbb"); its pattern
## comes from the same extra keys (creature_look.gd), the editor's default when they are missing.
const PLAYER_COLOR := Color(0.93, 0.55, 0.36)
const SKIN_COLOR_KEY := Look.SKIN_COLOR_KEY
## The friend path's notices (sing and dance, CreatureWorldSim._sing).
const CHARMED_NOTICE := "You sing to %s: %d / %d"
const BEFRIENDED_NOTICE := "%s joins your pack"
const SNUBBED_NOTICE := "It won't listen: you bit it"
const ALLY_LOST_NOTICE := "You bit an ally. It leaves your pack"
## The world dressing (assets/records/creature_field_ground, creature_nest_ring, creature_fruit_bush,
## creature_meat_chunk). The bush GLB has two root meshes, Bush and Fruit; the meat GLB one, MeatChunk.
const FIELD_SCENE := "res://assets/export/creature_field_ground.glb"
const NEST_SCENE := "res://assets/export/creature_nest_ring.glb"
const BUSH_SCENE := "res://assets/export/creature_fruit_bush.glb"
const MEAT_SCENE := "res://assets/export/creature_meat_chunk.glb"
const BUSH_MESH_NAME := "Bush"
const FRUIT_MESH_NAME := "Fruit"
const MEAT_MESH_NAME := "MeatChunk"
## The instance colour of a bush with no fruit: a pale, desaturated tint over the baked leaf (the spec's value).
const BUSH_BARE_TINT := Color(0.62, 0.74, 0.58)

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
var _bush_mm: MultiMeshInstance3D
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
		# A species wears its preset's colour; a body without one takes the palette's next.
		var rival_color: Color = skin_color_of(r["body"]) if (r["body"].extra as Dictionary).has(SKIN_COLOR_KEY) \
				else PALETTE[rival_rigs.size() % PALETTE.size()]
		var rig := _build_rig(r["id"], r["body"], RIVAL_SKIN_DIVISIONS_MAX, rival_color, Look.rival_pattern(rival_rigs.size() + 1))
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
	return {"move": keys, "bite": Input.is_action_pressed(&"creature_bite"), "evolve": Input.is_action_pressed(&"creature_evolve"),
			"social": Input.is_action_pressed(&"creature_social")}


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
		"charmed":
			notice = CHARMED_NOTICE % [String(e["name"]), int(e["friendship"]), int(e["needed"])]
			hud.show_notice(notice)
		"befriended":
			notice = BEFRIENDED_NOTICE % String(e["name"]).capitalize()
			hud.show_notice(notice)
		"snubbed":
			notice = SNUBBED_NOTICE
			hud.show_notice(notice)
		"ally_lost":
			notice = ALLY_LOST_NOTICE
			hud.show_notice(notice)
		"earned":
			hud.flash_points(int(e["points"]))
			hud.refresh()


func _build_ground() -> void:
	# The field's pivot is at its centre on the ground and the sim's field is centred on the origin; the nest ring's
	# pivot is at its centre on the ground, so it sits at the nest with no offset.
	var field: Node3D = load(FIELD_SCENE).instantiate()
	field.name = "Field"
	add_child(field)
	var nest: Node3D = load(NEST_SCENE).instantiate()
	nest.name = "Nest"
	nest.position = sim.nest
	add_child(nest)


func _build_food() -> void:
	var count := sim.fruit.size()
	_bush_mm = _multimesh("Bushes", _mesh_of(BUSH_SCENE, BUSH_MESH_NAME), count)
	add_child(_bush_mm)
	_fruit_mm = _multimesh("Fruit", _mesh_of(BUSH_SCENE, FRUIT_MESH_NAME), count)
	add_child(_fruit_mm)
	_meat_mm = _multimesh("Meat", _mesh_of(MEAT_SCENE, MEAT_MESH_NAME), MEAT_INSTANCES_MAX)
	add_child(_meat_mm)
	_draw_food()


## Bushes draw one instance each, white while ripe and BUSH_BARE_TINT while bare; the Fruit instances are packed at
## the front of their MultiMesh, one per ripe bush. Each bush turns by a yaw from its index so the clumps differ.
## The meshes' pivots are on the ground, so everything sits at the sim's y = 0.
func _draw_food() -> void:
	var bushes := _bush_mm.multimesh
	var fruit := _fruit_mm.multimesh
	var ripe := 0
	for i in sim.fruit.size():
		var f: Dictionary = sim.fruit[i]
		var xform := Transform3D(Basis(Vector3.UP, _yaw_of(i)), f["position"] as Vector3)
		bushes.set_instance_transform(i, xform)
		bushes.set_instance_color(i, Color.WHITE if f["ripe"] else BUSH_BARE_TINT)
		if f["ripe"]:
			fruit.set_instance_transform(ripe, xform)
			fruit.set_instance_color(ripe, Color.WHITE)
			ripe += 1
	fruit.visible_instance_count = ripe
	var meat := _meat_mm.multimesh
	var n := mini(sim.meat.size(), MEAT_INSTANCES_MAX)
	meat.visible_instance_count = n
	for i in n:
		var m: Dictionary = sim.meat[i]
		meat.set_instance_transform(i, Transform3D(Basis(Vector3.UP, _yaw_of(i + 7919)), m["position"] as Vector3))
		meat.set_instance_color(i, Color.WHITE)


## A fixed yaw per instance index, so a bush or chunk keeps its turn from frame to frame.
static func _yaw_of(i: int) -> float:
	return fposmod(float(i) * 2.399963, TAU)   # the golden angle: no two neighbours alike


## `node_name`'s mesh in the imported scene at `scene_path`, with the surface materials the import mapped onto it
## (the external .tres files in the .glb.import), so the MultiMesh draws the art's materials; any surface override
## on the instance is folded in. The instance is freed; the mesh keeps the asset's resources alive.
static func _mesh_of(scene_path: String, node_name: String) -> Mesh:
	var scene: Node = (load(scene_path) as PackedScene).instantiate()
	var instance := scene.find_child(node_name, true, false) as MeshInstance3D
	assert(instance != null, "%s has no MeshInstance3D named %s" % [scene_path, node_name])
	var mesh: Mesh = instance.mesh
	for i in instance.get_surface_override_material_count():
		var override := instance.get_surface_override_material(i)
		if override != null:
			if mesh == instance.mesh:
				mesh = mesh.duplicate()
			mesh.surface_set_material(i, override)
	scene.free()
	return mesh


static func _multimesh(node_name: String, mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	mmi.multimesh = mm
	return mmi


func _build_player() -> void:
	var body = sim.body_of(Sim.PLAYER_ID)
	var color := skin_color_of(body)
	var pattern: Dictionary = Look.pattern_of(body.extra)
	if sim.player()["has_legs"]:
		player_rig = _build_rig(Sim.PLAYER_ID, body, PLAYER_SKIN_DIVISIONS_MAX, color, pattern)
	else:
		# No legs: the body stands at the nest as a plain rig, so the player sees what needs fixing.
		var rig := SpineRig.new()
		rig.name = Sim.PLAYER_ID
		var divisions := mini(body.preview_divisions(data["body_rules"]), PLAYER_SKIN_DIVISIONS_MAX)
		rig.setup(body, SkinCpu.build(body, divisions), color)
		var orientations: Dictionary = CreatureData.part_orientations(data["part_rules"])
		rig.add_parts(AnchorResolver.resolve_all(body, BodyField.from_description(body), orientations), orientations)
		rig.use_skin_shader(Look.shader_params(color, pattern))
		var box: AABB = body.bounds_m()
		rig.position = sim.nest - Vector3(0.0, box.position.y, 0.0)
		player_rig = rig
	add_child(player_rig)


## A walker rig on the sim's planner for `id`, its skin built once on the CPU builder at the body's preview grid
## clamped to `divisions_max`, in `color` with the skin-shader `pattern` (creature_look.gd).
func _build_rig(id: String, body: RefCounted, divisions_max: int, color: Color, pattern: Dictionary) -> Node3D:
	var rig := WalkerRig.new()
	rig.name = id
	var divisions := mini(body.preview_divisions(data["body_rules"]), divisions_max)
	var orientations: Dictionary = CreatureData.part_orientations(data["part_rules"])
	var placements: Array = AnchorResolver.resolve_all(body, BodyField.from_description(body), orientations)
	rig.setup(body, SkinCpu.build(body, divisions), sim.planner_of(id), sim.gait_of(id), color, placements, orientations)
	rig.body.use_skin_shader(Look.shader_params(color, pattern))
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
	var eye := _focus + offset
	eye.y = maxf(eye.y, CAMERA_GROUND_CLEARANCE_M)
	camera.look_at_from_position(eye, _focus, Vector3.UP)


## The skin colour the body carries ("skin_color", "rrggbb" or "#rrggbb" from the editor's swatch), else
## PLAYER_COLOR.
static func skin_color_of(body: RefCounted) -> Color:
	var stored := String(body.extra.get(SKIN_COLOR_KEY, "")) if body != null else ""
	return Color.html(stored) if Color.html_is_valid(stored) else PLAYER_COLOR


static func _body_length(body: RefCounted) -> float:
	return body.bounds_m().size.z if body else 1.0


func _exit_tree() -> void:
	load("res://game/scenes/creature/part_library.gd").clear()
