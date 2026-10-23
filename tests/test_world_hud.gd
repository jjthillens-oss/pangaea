extends TestCase
## The way home and the respawn message (S1 T5.2 and T5.5; docs/s1/s1-content.md 6.10 and 7.3):
## the pool reports a respawn with its shelter, and main shows "Back at the generation start ·
## sheltered for 5 s." when the respawn happens.

const FakeEvents := preload("res://tests/fakes/fake_world_events.gd")


func test_the_pool_reports_a_respawn_with_its_shelter_and_whether_it_teleported() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.pool_session())
	var heard: Array[Dictionary] = []
	pool.respawned.connect(func(grace_s: float, teleport: bool) -> void:
		heard.append({"grace_s": grace_s, "teleport": teleport, "drawn_at": pool.cell_view.position,
			"sim_at": PlaneSpace.to_world(pool.sim.motion.position), "dead": pool.cell_view._dead}))
	var sim := pool.sim
	# The cell dies away from its checkpoint (the spawn), so the respawn moves it.
	check(sim.debug_teleport(sim.layout.spawn + Vector2(12.0, 0.0)), "the cell swims off")
	FakeEvents.frame(pool)
	check(sim.debug_hurt_player(sim.state.max_health) and sim.dead, "the cell dies")
	FakeEvents.frame(pool)
	check(heard.is_empty(), "no respawn while the cell is dead")
	pool.session.respawn_after_death()
	check(heard.is_empty(), "nothing is reported before the pool routes the event")
	pool._process(FakeEvents.DT)
	check_eq(heard.size(), 1, "one respawn, routed before the frame is drawn")
	if heard.size() == 1:
		check_eq(heard[0].grace_s, 5.0, "with the 5 s shelter of a first death")
		check_eq(heard[0].teleport, false, "and no teleport in the pool")
		check(heard[0].drawn_at.is_equal_approx(heard[0].sim_at) and heard[0].sim_at.is_equal_approx(PlaneSpace.to_world(sim.layout.spawn)),
			"the cell is drawn at its checkpoint first: %s, %s" % [heard[0].drawn_at, heard[0].sim_at])
		check(not heard[0].dead, "alive again when the message shows")
		check_eq(Main.respawn_text(ceili(heard[0].grace_s)), "Back at the generation start · sheltered for 5 s.", "main's words")
		check_eq(ceili(heard[0].grace_s), Hud.shelter_seconds(sim), "the same seconds the shelter chip shows")
	# The endless world's teleport respawn adds teleport: true (spine 3.12); the pool passes it on.
	# Until T2's teleport respawn lands this is the event as the stream will emit it.
	pool._route({"type": "respawned", "grace_s": 5.0, "energy": 60.0, "relocated": [], "streak": 1, "teleport": true})
	check_eq(heard.size(), 2, "a teleport respawn is reported too")
	if heard.size() == 2:
		check_eq([heard[1].grace_s, heard[1].teleport], [5.0, true], "with its shelter and teleport: true")
	pool.free()
