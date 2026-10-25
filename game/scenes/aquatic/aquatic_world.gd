extends Node3D
## The Aquatic stage's world, presented (aquatic plan section 8, PROPOSED). It draws an AquaticSim's state and owns
## nothing the sim decides: the Blender-authored sea floor, the nest, shelters and reef dressing, the food sites, and
## every animal as a generated-skin fish (fish_view.gd). The water's colour, fog and light follow the camera's
## depth, from sunlit turquoise to the dark deep, so depth reads before any number does (Bible §6). The camera is
## behind and above, steady (plan section 4).

const FishView := preload("res://game/scenes/aquatic/fish_view.gd")

const SEAFLOOR := "res://assets/export/aquatic_seafloor.glb"
const NEST := "res://assets/export/creature_nest_ring.glb"
const SHELTER := "res://assets/export/landmark_arch.glb"
const FOOD_SCENES := {"plankton": "res://assets/export/plankton.glb", "algae": "res://assets/export/algae_ball.glb",
		"vent": "res://assets/export/bead_cluster.glb"}
const FOOD_SCALE := {"plankton": 2.2, "algae": 2.6, "vent": 3.2}
const DRESSING := ["res://assets/export/landmark_fan.glb", "res://assets/export/landmark_spire.glb",
		"res://assets/export/rare_sponge_grove.glb", "res://assets/export/rock_a.glb", "res://assets/export/rock_b.glb",
		"res://assets/export/rock_c.glb", "res://assets/export/landmark_great_shell.glb"]
const DRESSING_COUNT := 46
const PLAYER_DIVISIONS := 36
const ANIMAL_DIVISIONS := 22
const CAMERA_BACK := 4.2
const CAMERA_UP := 1.5
const CAMERA_FOLLOW := 4.0
## Water by depth (m): colour of the water and of its fog, light energy, fog density.
const WATER := [
	[0.0, Color(0.33, 0.72, 0.80), 1.25, 0.012],
	[14.0, Color(0.13, 0.50, 0.66), 0.9, 0.018],
	[32.0, Color(0.05, 0.25, 0.42), 0.55, 0.026],
	[62.0, Color(0.03, 0.10, 0.21), 0.42, 0.03],
	[100.0, Color(0.02, 0.05, 0.12), 0.32, 0.034],
]

var sim: AquaticSim
var camera: Camera3D
var sun: DirectionalLight3D
var environment: Environment
var player_rig: Node3D
var kin_rig: Node3D
var lancer_rig: Node3D
var drifter_rig: Node3D
var animal_rigs := {}
var food_nodes := {}
var lancer_tell: Label3D

var _cam_pos := Vector3.ZERO
var _player_body_key := ""


func setup(p_sim: AquaticSim) -> void:
	sim = p_sim
	_build_environment()
	_add_scene(SEAFLOOR, Transform3D.IDENTITY)
	var nest := sim.nest_pos()
	_add_scene(NEST, Transform3D(Basis().scaled(Vector3.ONE * 0.55), Vector3(nest.x, sim.floor_at(nest.x, nest.z), nest.z)))
	for s in sim.rules.world.shelters:
		var p := AquaticSim._v(s.pos)
		_add_scene(SHELTER, Transform3D(Basis(Vector3.UP, float(p.x) * 0.1).scaled(Vector3.ONE * 1.35),
				Vector3(p.x, sim.floor_at(p.x, p.z) - 0.4, p.z)))
	_dress_reef()
	for f in sim.food:
		var node := _add_scene(FOOD_SCENES[f.kind], Transform3D(Basis().scaled(Vector3.ONE * FOOD_SCALE[f.kind]), f.pos))
		food_nodes[f.id] = node
	for a in sim.animals:
		var rig := FishView.make_species(a.species, ANIMAL_DIVISIONS, animal_rigs.size())
		rig.name = a.id
		add_child(rig)
		animal_rigs[a.id] = rig
	lancer_rig = FishView.make_species("lancer", ANIMAL_DIVISIONS + 6)
	lancer_rig.name = "Lancer"
	add_child(lancer_rig)
	lancer_tell = Label3D.new()
	lancer_tell.name = "LancerTell"
	lancer_tell.text = "?"
	lancer_tell.font_size = 160
	lancer_tell.modulate = Color(1.0, 0.85, 0.3)
	lancer_tell.outline_size = 24
	lancer_tell.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lancer_tell.no_depth_test = true
	lancer_tell.position = Vector3(0.0, 2.2, 0.0)
	lancer_rig.add_child(lancer_tell)
	drifter_rig = FishView.make_species("drifter", 40)
	drifter_rig.name = "Drifter"
	add_child(drifter_rig)
	rebuild_player()
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 68.0
	camera.far = 260.0
	add_child(camera)
	camera.current = true
	_cam_pos = _camera_goal()
	sync(0.0)


## Rebuilds the player's and the kin's fish from the sim's body (after a new generation).
func rebuild_player() -> void:
	var key := JSON.stringify(sim.player.body, "", true)
	if key == _player_body_key:
		return
	_player_body_key = key
	for rig in [player_rig, kin_rig]:
		if rig != null:
			remove_child(rig)
			rig.queue_free()
	var color := FishView.color_of(float(sim.player.body.hue))
	player_rig = FishView.make(sim.player.body, FishView.PLAYER_SCALE_M, PLAYER_DIVISIONS, color, 0)
	player_rig.name = "Player"
	add_child(player_rig)
	kin_rig = FishView.make(sim.player.body, FishView.PLAYER_SCALE_M, PLAYER_DIVISIONS, color.lightened(0.15), 1)
	kin_rig.name = "Kin"
	add_child(kin_rig)


func _add_scene(path: String, xform: Transform3D) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("Aquatic world: %s is missing." % path)
		return null
	var node := packed.instantiate() as Node3D
	node.transform = xform
	add_child(node)
	return node


## Seeded reef dressing on the reef and twilight slopes, clear of the route's sites (the same seed, the same reef).
func _dress_reef() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.world_seed, "aquatic.dressing"])
	var keep_clear: Array[Vector3] = [sim.nest_pos()]
	for list in [sim.rules.world.shelters, sim.rules.world.feeding]:
		for s in list:
			keep_clear.append(AquaticSim._v(s.pos))
	var placed := 0
	var tries := 0
	while placed < DRESSING_COUNT and tries < DRESSING_COUNT * 6:
		tries += 1
		var z := rng.randf_range(-250.0, -15.0)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := side * rng.randf_range(8.0, 40.0)
		var p := Vector3(x, sim.floor_at(x, z) - 0.3, z)
		var clear := true
		for c in keep_clear:
			if Vector2(c.x - p.x, c.z - p.z).length() < 9.0:
				clear = false
				break
		if not clear:
			continue
		var s := rng.randf_range(0.8, 1.9)
		_add_scene(DRESSING[rng.randi() % DRESSING.size()], Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))
		placed += 1


func _build_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.5
	var we := WorldEnvironment.new()
	we.name = "Water"
	we.environment = environment
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-62.0), deg_to_rad(25.0), 0.0)
	sun.light_color = Color(0.85, 0.97, 1.0)
	sun.shadow_enabled = true
	add_child(sun)
	_tint_water(5.0)


## The water at `depth` m: its colour, fog and light, blended between the WATER rows.
func _tint_water(depth: float) -> void:
	var a: Array = WATER[0]
	var b: Array = WATER[WATER.size() - 1]
	for i in range(1, WATER.size()):
		if depth <= float(WATER[i][0]):
			a = WATER[i - 1]
			b = WATER[i]
			break
	var t := clampf((depth - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0])), 0.0, 1.0)
	var col: Color = (a[1] as Color).lerp(b[1], t)
	environment.background_color = col
	environment.fog_light_color = col
	environment.fog_density = lerpf(float(a[3]), float(b[3]), t)
	environment.ambient_light_color = col.lightened(0.35)
	environment.ambient_light_energy = lerpf(float(a[2]), float(b[2]), t) * 1.1
	sun.light_energy = lerpf(float(a[2]), float(b[2]), t)


func _camera_goal() -> Vector3:
	var fwd := AquaticSim.forward_of(float(sim.player.heading))
	var goal: Vector3 = sim.player.pos - fwd * CAMERA_BACK + Vector3.UP * CAMERA_UP
	goal.y = minf(goal.y, -0.4)
	goal.y = maxf(goal.y, sim.floor_at(goal.x, goal.z) + 1.2)
	return goal


## Draws the sim's state; `delta` animates swim waves and eases the camera.
func sync(delta: float) -> void:
	_place(player_rig, sim.player.pos, float(sim.player.heading), float(sim.player.speed), delta)
	_place(kin_rig, sim.kin.pos, float(sim.kin.heading), 0.3, delta)
	for a in sim.animals:
		var rig: Node3D = animal_rigs[a.id]
		rig.visible = a.alive
		if a.alive:
			_place(rig, a.pos, float(a.heading), 2.5 if a.state == "flee" else 1.2, delta)
	_place(lancer_rig, sim.lancer.pos, float(sim.lancer.heading), 5.0 if sim.lancer.state == "pursue" else 1.5, delta)
	lancer_tell.visible = String(sim.lancer.state) in ["investigate", "pursue"]
	lancer_tell.text = "?" if sim.lancer.state == "investigate" else "!"
	lancer_tell.modulate = Color(1.0, 0.85, 0.3) if sim.lancer.state == "investigate" else Color(1.0, 0.35, 0.3)
	_place(drifter_rig, sim.drifter.pos, float(sim.drifter.heading), 0.4, delta)
	for f in sim.food:
		var node: Node3D = food_nodes.get(f.id)
		if node != null:
			node.visible = f.alive
			if f.kind == "plankton":
				node.position = f.pos + Vector3(0.0, sin(Time.get_ticks_msec() * 0.001 + float(f.pos.x)) * 0.25, 0.0)
	var goal := _camera_goal()
	_cam_pos = goal if delta <= 0.0 else _cam_pos.lerp(goal, minf(1.0, CAMERA_FOLLOW * delta))
	camera.position = _cam_pos
	var look: Vector3 = sim.player.pos + AquaticSim.forward_of(float(sim.player.heading)) * 3.0 + Vector3.UP * 0.4
	if camera.position.distance_to(look) > 0.1:
		camera.look_at(look, Vector3.UP)
	_tint_water(-camera.position.y)


func _place(rig: Node3D, pos: Vector3, heading: float, speed: float, delta: float) -> void:
	if rig == null:
		return
	rig.position = pos
	rig.rotation = Vector3(0.0, heading, 0.0)
	if delta > 0.0:
		FishView.animate(rig, speed, delta)
