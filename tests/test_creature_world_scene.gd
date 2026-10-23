extends TestCase
## The creature world scene (game/scenes/creature/creature_world.tscn) headless: setup on the quadruped, a scripted
## drive moves the player and leaves the rig finite, rivals have rigs, the legless body is told so, evolve at the
## nest reaches the signal, and setup stays within its budget (rival skins at the CPU builder's clamped grid).

const Fixtures := preload("res://tests/creature_fixtures.gd")
const WORLD_SCENE := "res://game/scenes/creature/creature_world.tscn"
const WalkerRig := preload("res://game/scenes/creature/walker_rig.gd")
const DT := 1.0 / 60.0
const SETUP_BUDGET_MS := 3000
## The in-tree run: the runner's tests execute before the tree's first frame, so nothing is inside the tree and the
## skeleton's IK cannot solve. This probe runs the scene in a process of its own through the real main loop.
const PROBE_SCRIPT := "res://tests/creature_world_probe.gd"

var _evolved := []
var _deaths := []


func before_each() -> void:
	_evolved.clear()
	_deaths.clear()


func make(body_name := "s1_quadruped", seed_value := 5) -> CreatureWorld:
	var world: CreatureWorld = load(WORLD_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	world.setup(Fixtures.body(body_name).to_dict(), seed_value, 150)
	world.evolve_requested.connect(func(p): _evolved.append(p))
	world.died.connect(func(c): _deaths.append(c))
	return world


func frames(world: CreatureWorld, n: int) -> void:
	for i in n:
		world._physics_process(DT)
		world._process(DT)
		world.hud._process(DT)


func test_a_scripted_forward_drive_moves_the_player_and_keeps_the_rig_finite() -> void:
	var world := make()
	print("    creature world setup: %s" % [world.setup_ms])
	check(int(world.setup_ms["total"]) < SETUP_BUDGET_MS, "setup within %d ms (%s)" % [SETUP_BUDGET_MS, world.setup_ms])
	check(world.sim != null and world.player_rig != null, "sim and player rig")
	check_eq(world.rival_rigs.size(), 6, "six rival rigs")
	world.set_intent(Vector2(0.0, 1.0), false, false)
	frames(world, 120)
	var p: Vector3 = world.sim.player()["position"]
	check(p.z < -1.0 and absf(p.x) < 0.5, "two seconds forward (camera yaw 0) moved the player along -Z (%s)" % p)
	var skeleton: Skeleton3D = world.player_rig.body.skeleton
	for b in skeleton.get_bone_count():
		check(skeleton.get_bone_global_pose(b).origin.is_finite(), "bone %d is finite" % b)
	var body_at: Vector3 = world.player_rig.body.transform.origin
	check(body_at.is_finite() and body_at.distance_to(p) < 2.0, "the body is drawn at the sim's position (%s vs %s)" % [body_at, p])
	check(world.camera.position.is_finite() and world.camera.position.distance_to(p) > 2.0, "the camera is behind the creature")
	for id in world.rival_rigs:
		check((world.rival_rigs[id] as Node3D).body.transform.origin.is_finite(), "%s's rig is finite" % id)
	check(world.hud.notice_text() == "", "no notice while walking (%s)" % world.hud.notice_text())
	check("Bite" in world.hud._hint_text.text and "Evolve" in world.hud._hint_text.text, "the hint names the actions (%s)" % world.hud._hint_text.text)
	check(world.snapshot().has("tick") and int(world.snapshot()["tick"]) == 120, "snapshot carries the sim's")
	world.clear_intent()
	world.free()


func test_evolve_at_the_nest_reaches_the_stage_and_away_from_it_shows_the_notice() -> void:
	var world := make()
	world.set_intent(Vector2.ZERO, false, true)
	frames(world, 2)
	check_eq(_evolved.size(), 1, "evolve_requested once on the press")
	if _evolved.size() == 1:
		check_eq(_evolved[0], 150, "with the points")
	world.set_intent(Vector2(0.0, 1.0), false, false)
	frames(world, 240)
	check(not world.sim.at_nest(), "walked off the nest")
	world.set_intent(Vector2.ZERO, false, true)
	frames(world, 2)
	check_eq(_evolved.size(), 1, "no evolve away from the nest")
	check_eq(world.hud.notice_text(), "Return to the nest to evolve", "the notice line")
	world.free()


func test_the_editors_skin_colour_reaches_the_players_rig() -> void:
	var dict: Dictionary = Fixtures.body("s1_quadruped").to_dict()
	dict["skin_color"] = "4fc08a"
	var world: CreatureWorld = load(WORLD_SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	world.setup(dict, 5, 150)
	var mat := world.player_rig.body.mesh_instance.material_override as ShaderMaterial
	check(mat != null and (mat.get_shader_parameter("color_base") as Color).is_equal_approx(Color("#4fc08a")),
			"the player's skin shader takes the body's swatch (%s)" % [mat.get_shader_parameter("color_base") if mat else null])
	check(CreatureWorld.skin_color_of(Fixtures.body("s1_quadruped")).is_equal_approx(CreatureWorld.PLAYER_COLOR),
			"without one the default colour")
	for id in world.rival_rigs:
		var rival_mat := (world.rival_rigs[id] as Node3D).body.mesh_instance.material_override as ShaderMaterial
		check(not (rival_mat.get_shader_parameter("color_base") as Color).is_equal_approx(Color("#4fc08a")), "%s keeps its own colour" % id)
	world.free()


func test_a_legless_body_is_told_it_needs_legs_and_can_still_evolve() -> void:
	var world := make("s1_snake")
	check(world.player_rig != null and not (world.player_rig is WalkerRig), "a plain rig at the nest")
	check_eq(world.hud.notice_text(), "This creature needs legs to walk", "the notice")
	world.set_intent(Vector2(0.0, 1.0), true, false)
	frames(world, 60)
	check(world.sim.player()["position"].is_equal_approx(Vector3.ZERO), "it stays at the nest")
	check_eq(world.hud.notice_text(), "This creature needs legs to walk", "the notice stays")
	world.set_intent(Vector2.ZERO, false, true)
	frames(world, 2)
	check_eq(_evolved.size(), 1, "evolve is available")
	world.free()


func test_a_death_shows_the_notice_and_emits_died() -> void:
	var world := make()
	world.sim._place(world.sim.me, Vector3(20.0, 0.0, 0.0))
	world.sim.me["health"] = -1.0
	frames(world, 2)
	check_eq(_deaths.size(), 1, "died once")
	check("Back at the nest" in world.hud.notice_text() and "30 points lost" in world.hud.notice_text(), "the death notice (%s)" % world.hud.notice_text())
	check(world.sim.at_nest(), "back at the nest")
	check(world.player_rig.planner == world.sim.planner_of("player"), "the rig follows the new planner")
	world.free()


## In a process of its own, through the real main loop: the walker rig's IK solves finite legs that stay on the
## planner's feet, over two seconds of a scripted forward drive.
func test_in_the_tree_the_walker_rig_solves_finite_legs() -> void:
	var output := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--script", PROBE_SCRIPT], output, true)
	var text := "\n".join(output)
	var line := ""
	for l in text.split("\n"):
		if l.begins_with("PROBE_RESULT "):
			line = l.trim_prefix("PROBE_RESULT ")
	check(code == 0 and not line.is_empty(), "the probe ran (exit %d): %s" % [code, text.right(1200)])
	if line.is_empty():
		return
	var r: Dictionary = JSON.parse_string(line)
	check(int(r["script_errors"]) == 0, "no script errors in the probe")
	check(float(r["z"]) < -1.0, "the player walked along -Z (%.2f m)" % float(r["z"]))
	check(int(r["solved_frames"]) >= 100 and bool(r["solved_finite"]), "the IK solved every frame and stayed finite (%d)" % int(r["solved_frames"]))
	check(float(r["max_stance_slip_ratio"]) < 0.05, "stance feet stay within 5%% of a leg length of their targets (%.4f)" % float(r["max_stance_slip_ratio"]))
	check(bool(r["bones_finite"]), "every bone is finite")
	check(int(r["rivals_drawn"]) == 6, "six rivals drawn (%d)" % int(r["rivals_drawn"]))
