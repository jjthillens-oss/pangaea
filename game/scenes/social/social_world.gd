class_name SocialWorld
extends Node3D
## The Social stage preview's world view (PROPOSED, docs/stages/social-plan.md section 14): it draws a SocialSim and
## never changes it. Built in code from recorded art only: the creature stage's field ground, its nest ring at the
## player's nest and again (smaller) at the band's den, one fruit bush per grove bush (its Fruit mesh hidden while the
## bush is bare), three meat chunks at the hunter's lair, and the creatures' generated skins with their part GLBs on
## walker rigs, built exactly as the creature world builds its rivals (CreatureWorld._build_rig). A fruit being
## carried shows as a small copy of the bush's Fruit mesh over the carrier. The sky, fog and sun match the creature
## world's scene.
##
## sync(delta) once a frame: near bodies (within RIG_LOD_M of the player) run their planner's pose and feet with an
## IK solve, far ones only their body transform; then the bushes, the carried fruit and the camera. The camera sits
## behind and above the player and orbits on the right stick or a middle-button drag; it swings back behind the
## player a moment after the orbit stops while the player walks.

const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const SkinCpu := preload("res://game/systems/creature/skin_cpu.gd")
const BodyField := preload("res://game/domain/creature/body_field.gd")
const AnchorResolver := preload("res://game/domain/creature/anchor_resolver.gd")
const WalkerRig := preload("res://game/scenes/creature/walker_rig.gd")
const Look := preload("res://game/scenes/creature/creature_look.gd")

const FIELD_SCENE := "res://assets/export/creature_field_ground.glb"
const NEST_SCENE := "res://assets/export/creature_nest_ring.glb"
const BUSH_SCENE := "res://assets/export/creature_fruit_bush.glb"
const MEAT_SCENE := "res://assets/export/creature_meat_chunk.glb"
const FRUIT_NODE := "Fruit"
## The nest ring's outer radius as modelled (m); a site's ring is scaled to the site's radius.
const NEST_RING_RADIUS_M := 6.45
## The Fruit mesh's centre above a bush's pivot (m), and the carried copy's size against the bush's.
const FRUIT_CENTRE_Y_M := 0.54
const CARRIED_FRUIT_SCALE := 0.9
## Where the meat lies round the lair's centre (m).
const MEAT_RING_M := 1.1

const PLAYER_SKIN_DIVISIONS_MAX := 48
const CAST_SKIN_DIVISIONS_MAX := 32
## Beyond this from the player a body only follows its planner's transform (no IK solve).
const RIG_LOD_M := 40.0
const PLAYER_COLOR := Color(0.93, 0.55, 0.36)

## Higher and further back than the creature world's camera, so a band trailing the player stays in view around it
## instead of filling the foreground.
const CAMERA_DISTANCE_PER_BODY_M := 5.0
const CAMERA_DISTANCE_MIN_M := 9.5
const CAMERA_DISTANCE_MAX_M := 16.0
const CAMERA_PITCH_DEG := 34.0
const CAMERA_PITCH_MIN_DEG := 6.0
const CAMERA_PITCH_MAX_DEG := 70.0
const CAMERA_GROUND_CLEARANCE_M := 0.4
const CAMERA_STICK_RAD_S := 2.4
const CAMERA_DRAG_RAD_PX := 0.006
const CAMERA_FOLLOW_HALF_LIFE_S := 0.1
const CAMERA_REALIGN_AFTER_S := 1.5
const CAMERA_REALIGN_HALF_LIFE_S := 1.2
const STICK_DEADZONE := 0.25
## The camera frames the band with the player: members within BAND_FRAME_M pull its focus BAND_PULL of the way.
const BAND_FRAME_M := 9.0
const BAND_PULL := 0.35

var sim: SocialSim
var data: Dictionary
var camera: Camera3D
## id -> WalkerRig ("player", the individuals' ids and the hunter's).
var rigs := {}
## bush id -> its instanced scene, and -> its Fruit MeshInstance3D (null when the art has none).
var bush_nodes := {}
var bush_fruit := {}
## id -> the carried-fruit MeshInstance3D over that body (hidden while it carries nothing).
var carried := {}
## Setup timings in ms: {skins, total}.
var setup_ms := {}
var camera_yaw := 0.0
var camera_pitch := deg_to_rad(CAMERA_PITCH_DEG)
var camera_distance := 8.0
var _focus := Vector3.ZERO
var _since_orbit := INF
var _fruit_mesh: Mesh


## Builds the view of `p_sim`. `p_data` is SocialData.creature_data() (the body and part rules for the skins).
func setup(p_sim: SocialSim, p_data: Dictionary) -> void:
	var t0 := Time.get_ticks_msec()
	sim = p_sim
	data = p_data
	_build_environment()
	_build_sites()
	_build_grove()
	var t1 := Time.get_ticks_msec()
	_build_rigs()
	var t2 := Time.get_ticks_msec()
	setup_ms = {"skins": t2 - t1, "total": t2 - t0}
	var length := _body_length(sim.body_of(SocialSim.PLAYER_ID))
	camera_distance = clampf(CAMERA_DISTANCE_PER_BODY_M * length, CAMERA_DISTANCE_MIN_M, CAMERA_DISTANCE_MAX_M)
	camera_yaw = float(sim.player()["yaw"])
	snap_camera()


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.13, 0.3, 0.6)
	sky_material.sky_horizon_color = Color(0.52, 0.64, 0.78)
	sky_material.sky_curve = 0.09
	sky_material.ground_bottom_color = Color(0.42, 0.54, 0.66)
	sky_material.ground_horizon_color = Color(0.52, 0.64, 0.78)
	sky_material.ground_curve = 0.08
	sky_material.sun_angle_max = 18.0
	sky_material.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	env.tonemap_white = 1.3
	env.ssao_enabled = false
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.52, 0.64, 0.78)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.0
	env.fog_density = 1.0
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.0
	env.fog_depth_curve = 1.2
	env.fog_depth_begin = 20.0
	env.fog_depth_end = 78.0
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(-0.872665, -0.523599, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 50.0
	camera.near = 0.1
	camera.far = 400.0
	camera.current = true
	add_child(camera)


## The field (its pivot at its centre on the ground; the sim's field is centred on the origin), the nest ring at the
## player's nest and at the den, each scaled to its site's radius, and the lair's meat.
func _build_sites() -> void:
	var field: Node3D = load(FIELD_SCENE).instantiate()
	field.name = "Field"
	add_child(field)
	for site in ["nest", "den"]:
		var s: Dictionary = sim.sites[site]
		var ring: Node3D = load(NEST_SCENE).instantiate()
		ring.name = site.capitalize()
		var centre: Vector2 = s["position"]
		ring.position = Vector3(centre.x, 0.0, centre.y)
		ring.scale = Vector3.ONE * (float(s["radius"]) / NEST_RING_RADIUS_M)
		add_child(ring)
	var lair: Dictionary = sim.sites["lair"]
	var meat_count := int(sim.tuning["lair"].get("meat", 3))
	var lair_at: Vector2 = lair["position"]
	for i in meat_count:
		var meat: Node3D = load(MEAT_SCENE).instantiate()
		meat.name = "Meat%d" % (i + 1)
		var angle := TAU * float(i) / float(maxi(1, meat_count)) + 0.4
		meat.position = Vector3(lair_at.x + cos(angle) * MEAT_RING_M, 0.0, lair_at.y + sin(angle) * MEAT_RING_M)
		meat.rotation.y = fposmod(float(i) * 2.399963, TAU)
		add_child(meat)


## One bush scene per grove bush, each turned by a yaw from its index so the clumps differ.
func _build_grove() -> void:
	var grove := Node3D.new()
	grove.name = "Grove"
	add_child(grove)
	var states: Array = sim.bush_states()
	for i in states.size():
		var b: Dictionary = states[i]
		var bush: Node3D = load(BUSH_SCENE).instantiate()
		bush.name = String(b["id"])
		var at: Vector2 = b["position"]
		bush.position = Vector3(at.x, 0.0, at.y)
		bush.rotation.y = fposmod(float(i) * 2.399963, TAU)
		grove.add_child(bush)
		bush_nodes[b["id"]] = bush
		var fruit := bush.find_child(FRUIT_NODE, true, false) as MeshInstance3D
		bush_fruit[b["id"]] = fruit
		if fruit != null and _fruit_mesh == null:
			_fruit_mesh = _mesh_with_overrides(fruit)


## The instance's mesh with any surface override folded in, so a copy draws the art's materials.
static func _mesh_with_overrides(instance: MeshInstance3D) -> Mesh:
	var mesh: Mesh = instance.mesh
	for i in instance.get_surface_override_material_count():
		var override := instance.get_surface_override_material(i)
		if override != null:
			if mesh == instance.mesh:
				mesh = mesh.duplicate()
			mesh.surface_set_material(i, override)
	return mesh


func _build_rigs() -> void:
	var bodies := Node3D.new()
	bodies.name = "Bodies"
	add_child(bodies)
	var ids: Array = [SocialSim.PLAYER_ID]
	for c in sim.individuals():
		ids.append(String(c["id"]))
	ids.append(String(sim.hunter()["id"]))
	for i in ids.size():
		var id: String = ids[i]
		var body: RefCounted = sim.body_of(id)
		if body == null or sim.planner_of(id) == null:
			continue
		var color := skin_color_of(body)
		var player := id == SocialSim.PLAYER_ID
		var pattern: Dictionary = Look.look_of(body.extra) if player else Look.rival_pattern(i, body.extra)
		var rig := _build_rig(id, body, PLAYER_SKIN_DIVISIONS_MAX if player else CAST_SKIN_DIVISIONS_MAX, color, pattern)
		bodies.add_child(rig)
		rigs[id] = rig
		if _fruit_mesh != null and id != String(sim.hunter()["id"]):
			var fruit := MeshInstance3D.new()
			fruit.name = "Carried_%s" % id
			fruit.mesh = _fruit_mesh
			fruit.scale = Vector3.ONE * CARRIED_FRUIT_SCALE
			fruit.visible = false
			fruit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			bodies.add_child(fruit)
			carried[id] = fruit


## A walker rig on the sim's planner for `id`: its skin built once on the CPU at the body's preview grid clamped to
## `divisions_max`, in `color` with the skin-shader `pattern`, its parts placed by the anchor resolver.
func _build_rig(id: String, body: RefCounted, divisions_max: int, color: Color, pattern: Dictionary) -> Node3D:
	var rig := WalkerRig.new()
	rig.name = id
	var divisions := mini(body.preview_divisions(data["body_rules"]), divisions_max)
	var orientations: Dictionary = CreatureData.part_orientations(data["part_rules"])
	var placements: Array = AnchorResolver.resolve_all(body, BodyField.from_description(body), orientations)
	rig.setup(body, SkinCpu.build(body, divisions), sim.planner_of(id), sim.gait_of(id), color, placements, orientations)
	rig.body.use_skin_shader(Look.shader_params(color, pattern))
	return rig


## Once a frame: the bodies, the grove, the carried fruit and the camera.
func sync(delta: float) -> void:
	if sim == null:
		return
	var me: Vector3 = sim.player()["position"]
	for id in rigs:
		var planner = sim.planner_of(id)
		var near := (planner.position as Vector3).distance_to(me) <= RIG_LOD_M
		_sync_walker(rigs[id], planner, delta, near)
	_sync_grove()
	_sync_carried()
	_orbit(delta)
	_follow_camera(delta)


## Full: the planner's pose and feet, with an IK solve. Far: only the body's transform, no solve.
func _sync_walker(rig: Node3D, planner: RefCounted, delta: float, full: bool) -> void:
	if rig.planner != planner:
		rig.planner = planner
	if full and is_inside_tree():
		rig.sync(delta)
	else:
		# The body is top_level under a rig at the origin, so its own transform is its world transform; this also
		# serves outside the tree (a headless test before the first frame), where the IK cannot solve.
		rig.body.transform = Transform3D(Basis(Vector3.UP, planner.yaw), planner.position) \
				* planner.body_pose_local() * Transform3D(Basis(), -(rig.gait["centre"] as Vector3))


func _sync_grove() -> void:
	for b in sim.bush_states():
		var fruit: MeshInstance3D = bush_fruit.get(b["id"])
		if fruit != null:
			fruit.visible = bool(b["ripe"])


func _sync_carried() -> void:
	for id in carried:
		var count := int(sim.player()["carrying"]) if id == SocialSim.PLAYER_ID else int(sim.individual(id).get("carrying", 0))
		var fruit: MeshInstance3D = carried[id]
		fruit.visible = count > 0
		if count > 0:
			var body: RefCounted = sim.body_of(id)
			var planner = sim.planner_of(id)
			var height: float = body.bounds_m().size.y if body != null else 1.0
			fruit.position = (planner.position as Vector3) \
					+ Vector3(0.0, height + 0.15 - FRUIT_CENTRE_Y_M * CARRIED_FRUIT_SCALE, 0.0)


## Where a body's tag sits: just over its head (m), for SocialTags.
func tag_point(id: String) -> Vector3:
	var planner = sim.planner_of(id)
	var body: RefCounted = sim.body_of(id)
	if planner == null:
		return Vector3.ZERO
	var height: float = body.bounds_m().size.y if body != null else 1.0
	return (planner.position as Vector3) + Vector3(0.0, height + 0.2, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		camera_yaw -= rel.x * CAMERA_DRAG_RAD_PX
		camera_pitch = clampf(camera_pitch + rel.y * CAMERA_DRAG_RAD_PX, deg_to_rad(CAMERA_PITCH_MIN_DEG),
				deg_to_rad(CAMERA_PITCH_MAX_DEG))
		_since_orbit = 0.0


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
	var planner = sim.planner_of(SocialSim.PLAYER_ID)
	if _since_orbit > CAMERA_REALIGN_AFTER_S and planner != null and planner.v > 0.05:
		var k := 1.0 - pow(0.5, delta / CAMERA_REALIGN_HALF_LIFE_S)
		camera_yaw += wrapf(float(sim.player()["yaw"]) - camera_yaw, -PI, PI) * k


## A camera-relative move (x right, y forward, -1..1) as the sim's ground direction (x along +X, y along +Z).
func camera_relative(move: Vector2) -> Vector2:
	if move.length_squared() < 1e-9:
		return Vector2.ZERO
	var forward := Vector2(-sin(camera_yaw), -cos(camera_yaw))
	var right := Vector2(-forward.y, forward.x)
	return (right * move.x + forward * move.y).limit_length(1.0)


## Puts the camera straight at its place behind the player, with no easing (setup, and tools after moving the player).
func snap_camera() -> void:
	_focus = _focus_point()
	_place_camera()


## Just over the player, drawn BAND_PULL of the way toward the band members within BAND_FRAME_M, so a band
## trailing the player stays in the frame with it.
func _focus_point() -> Vector3:
	var body: RefCounted = sim.body_of(SocialSim.PLAYER_ID)
	var height: float = body.bounds_m().size.y if body != null else 1.0
	var me: Vector3 = sim.player()["position"]
	var sum := Vector3.ZERO
	var count := 0
	for id in sim.band():
		var at: Vector3 = sim.individual(id)["position"]
		if at.distance_to(me) <= BAND_FRAME_M:
			sum += at
			count += 1
	var ground := me if count == 0 else me.lerp(sum / float(count), BAND_PULL)
	return Vector3(ground.x, 0.6 * height + 0.3, ground.z)


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


## The skin colour a body carries ("skin_color", "rrggbb" or "#rrggbb"), else PLAYER_COLOR.
static func skin_color_of(body: RefCounted) -> Color:
	var stored := String(body.extra.get(Look.SKIN_COLOR_KEY, "")) if body != null else ""
	return Color.html(stored) if Color.html_is_valid(stored) else PLAYER_COLOR


static func _body_length(body: RefCounted) -> float:
	return body.bounds_m().size.z if body != null else 1.0


func _exit_tree() -> void:
	load("res://game/scenes/creature/part_library.gd").clear()
