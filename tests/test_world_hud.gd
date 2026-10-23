extends TestCase
## The way home and the respawn message (S1 T5.2 and T5.5; docs/s1/s1-content.md 6.10 to 6.12 and
## 7.3): the column at the generation start and its edge pip, the arrow home and its distance, the
## region toasts, and the pool reporting a respawn with its shelter, which main words as "Back at
## the generation start · sheltered for 5 s.".

const FakeEvents := preload("res://tests/fakes/fake_world_events.gd")
const HUD_SCENE := preload("res://game/ui/hud.tscn")
const SCREEN := Vector2(1920.0, 1080.0)


## FakeWorldGen with the home tile at (0, 0), as the real arrangement has it (its own tiles are all
## sunlit).
class HomeTileGen extends "res://tests/fakes/fake_world_gen.gd":
	func tile_info(band: int, tx: int, ty: int) -> Dictionary:
		var info := super(band, tx, ty)
		if tx == 0 and ty == 0:
			info.region = "home"
		return info


func test_the_origin_arrow_hides_within_40_tm_and_points_to_the_origin() -> void:
	check(not WorldMarkers.origin_arrow(PackedFloat64Array([30.0, 0.0])).visible, "hidden 30 tm from the origin")
	var near := WorldMarkers.origin_arrow(PackedFloat64Array([41.0, 0.0]))
	check(near.visible, "shown 41 tm away")
	check(near.direction.is_equal_approx(Vector2(-1.0, 0.0)), "pointing back along -x: %s" % near.direction)
	check_near(near.distance_tm, 41.0, 1e-9, "41 tm from home")
	var far := WorldMarkers.origin_arrow(PackedFloat64Array([100000.5, -3.0]))
	check(far.direction.distance_to(Vector2(-100000.5, 3.0).normalized()) < 1e-6,
		"far out it points home from float64 differences: %s" % far.direction)
	# In the sea: the checkpoint east of the cell and the origin west of it. The arrow points home.
	var pool := FakeEvents.open_pool(FakeEvents.endless_session(FakeEvents.SEED, PackedFloat64Array([200.0, 0.0])))
	var sim := pool.sim
	sim.world.checkpoint_am = PackedFloat64Array([500.0, 0.0, 0.0, 1.0])
	FakeEvents.frame(pool)
	var arrow := pool.markers.arrow()
	check(arrow != null and arrow.visible, "the arrow shows 200 tm out")
	if arrow != null:
		var forward := -arrow.transform.basis.z
		check(forward.dot(Vector3.LEFT) > cos(deg_to_rad(1.0)), "its front faces -x, toward the origin, not the checkpoint: %s" % forward)
		var cell := PlaneSpace.to_plane(pool.cell_view.position)
		var expected := PlaneSpace.to_world(cell + Vector2.LEFT * (sim.phenotype.radius + WorldMarkers.ARROW_RING_GAP), WorldMarkers.ARROW_Y)
		check(arrow.position.is_equal_approx(expected), "beside the cell, outside its radius: %s, %s" % [arrow.position, expected])
		check(pool.markers.arrow_tip().x < arrow.position.x, "its tip is the end toward home")
	check(sim.debug_hurt_player(sim.state.max_health) and sim.dead, "the cell dies")
	FakeEvents.frame(pool)
	check(arrow != null and not arrow.visible, "the arrow hides while the cell is dead")
	pool.free()


func test_distance_text_reads_metres_then_kilometres() -> void:
	var cases := [[0.0, "0 m"], [312.4, "312 m"], [999.4, "999 m"], [999.6, "1.0 km"], [1400.0, "1.4 km"],
		[99949.0, "99.9 km"], [100000.0, "100 km"], [123456.0, "123 km"]]
	for c in cases:
		check_eq(WorldMarkers.distance_text(c[0]), c[1], "%s tm" % c[0])


func test_the_column_stands_at_the_checkpoint_across_a_rebase() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var sim := pool.sim
	var world := sim.world
	var column := pool.markers.column()
	check(column != null and pool.markers.visible, "the sea has a column")
	if column == null:
		pool.free()
		return
	var at_checkpoint := func() -> Vector3:
		return PlaneSpace.to_world(world.local_of_abs(world.checkpoint_am[0], world.checkpoint_am[1]))
	check(column.position.is_equal_approx(at_checkpoint.call()), "at the checkpoint from the first frame: %s" % column.position)
	var before := column.position
	check(sim.debug_rebase(Vector2i(3, -2)), "a dev rebase")
	for e in sim.drain_events():
		pool._route(e)
	check(not column.position.is_equal_approx(before), "the checkpoint's local place moved with the origin")
	check(column.position.is_equal_approx(at_checkpoint.call()), "and the column with it: %s, %s" % [column.position, at_checkpoint.call()])
	world.checkpoint_am = PackedFloat64Array([world.checkpoint_am[0] + 70.0, world.checkpoint_am[1] - 20.0, 0.0, 1.0])
	FakeEvents.frame(pool)
	check(column.position.is_equal_approx(at_checkpoint.call()), "a moved checkpoint moves the column: %s" % column.position)
	check(sim.debug_hurt_player(sim.state.max_health) and sim.dead, "the cell dies")
	FakeEvents.frame(pool)
	check(column.visible and pool.markers.visible, "the column stays while the cell is dead")
	pool.free()


func test_the_column_pip_shows_only_when_the_column_is_off_screen() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var sim := pool.sim
	var world := sim.world
	var hud := _hud(pool)
	var overlay := hud.world_overlay
	check(overlay != null and overlay.get_parent() == hud, "the endless HUD has the world overlay")
	if overlay == null:
		hud.free()
		pool.free()
		return
	var rect := Rect2(Vector2.ZERO, SCREEN)
	var project := _projector(pool.camera)
	# A new lineage starts on its checkpoint: the column is on screen.
	FakeEvents.frame(pool)
	overlay.refresh(rect, project)
	check(overlay.pip.is_empty(), "no pip while the column is on screen")
	world.checkpoint_am = PackedFloat64Array([world.checkpoint_am[0] + 200.0, world.checkpoint_am[1], 0.0, 1.0])
	FakeEvents.frame(pool)
	overlay.refresh(rect, project)
	check(not overlay.pip.is_empty(), "a pip once the column is 200 tm away")
	if not overlay.pip.is_empty():
		var p: Dictionary = project.call(pool.markers.column().position)
		var expected := ThreatIndicators.edge_point(rect, p.at, p.behind, ThreatIndicators.MARGIN_PX)
		check(overlay.pip.at.is_equal_approx(expected), "where an edge arrow would sit: %s, %s" % [overlay.pip.at, expected])
		var at: Vector2 = overlay.pip.at
		var to_edge := minf(minf(at.x, SCREEN.x - at.x), minf(at.y, SCREEN.y - at.y))
		check(rect.has_point(at) and to_edge <= ThreatIndicators.MARGIN_PX + 0.01, "inside the screen, %.1f px from its edge" % to_edge)
		check(at.x > SCREEN.x * 0.5, "on the side the column is (east)")
	check(overlay.label.is_empty(), "no distance label while the arrow is hidden")
	hud.free()
	pool.free()


func test_the_arrow_label_reads_the_distance_home_beside_its_tip() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session(FakeEvents.SEED, PackedFloat64Array([1400.0, 0.0])))
	var hud := _hud(pool)
	var overlay := hud.world_overlay
	var project := _projector(pool.camera)
	FakeEvents.frame(pool)
	overlay.refresh(Rect2(Vector2.ZERO, SCREEN), project)
	check(not overlay.label.is_empty(), "the label shows with the arrow")
	if not overlay.label.is_empty():
		check_eq(overlay.label.text, "Where you began · 1.4 km", "its words")
		var tip: Dictionary = project.call(pool.markers.arrow_tip())
		check(overlay.label.at.is_equal_approx(tip.at), "at the arrow tip's screen point")
		check(overlay.label.side.x < -0.99, "with its words on the side the arrow points (west): %s" % overlay.label.side)
	hud.free()
	pool.free()


func test_region_toasts_follow_tiles_and_wait_30_s_per_region() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var sim := pool.sim
	sim.world.gen = HomeTileGen.new(sim.world.content, sim.species, FakeEvents.SEED)
	sim.tick = 0
	var hud := _hud(pool)
	check_eq(_last_toast(hud), "Home waters", "bind names the start tile at once")
	var steps := [[5.0, "sunlit", "", "Sunlit shallows"], [10.0, "home", "", ""], [20.0, "sunlit", "", ""],
		[25.0, "reef", "", "Shell reef"], [31.0, "home", "", "Home waters"], [32.0, "rare", "giant_husk", "The giant husk"]]
	for step in steps:
		sim.tick = roundi(step[0] / PoolSim.DT)
		var count := hud.toast_texts().size()
		var last := _last_toast(hud)
		hud._on_sim_event(FakeEvents.tile_entered(Vector2i(1, 0), step[1], step[2]))
		if step[3] == "":
			check(hud.toast_texts().size() == count and _last_toast(hud) == last, "%s at %.0f s is not shown again" % [step[1], step[0]])
		else:
			check_eq(_last_toast(hud), step[3], "%s at %.0f s" % [step[2] if step[2] != "" else step[1], step[0]])
	check_eq(Hud.region_toast("rare", "shell_cathedral"), "The shell cathedral", "the other rare kind")
	check_eq(Hud.region_toast("drift", ""), "Open drift", "and the drift")
	check_eq(Hud.region_toast("nowhere", ""), "", "an unknown region has no toast")
	hud.free()
	pool.free()


func test_pool_mode_shows_no_markers_and_no_overlay() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.pool_session())
	FakeEvents.frame(pool)
	check(not pool.markers.visible, "the pool hides the markers")
	check(pool.markers.column() == null and pool.markers.arrow() == null and pool.markers.get_child_count() == 0, "and builds none")
	var hud := _hud(pool)
	check(hud.world_overlay == null and hud.get_node_or_null("WorldOverlay") == null, "the pool's HUD has no world overlay")
	check(hud.toast_texts().is_empty(), "and no region toast")
	hud.free()
	pool.free()


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
	pool.free()


## The endless world respawns on the step after the death is resolved (spine 3.11 step 0): far from
## the checkpoint the world moves home (teleport: true), near it the cell comes back in place
## (teleport: false). Either way the pool reports it once, with the cell already drawn where the sim
## put it, the camera on it and the column at the checkpoint.
func test_an_endless_respawn_reports_whether_the_world_moved_home() -> void:
	for case in [{"died_at": Vector2(600.0, 9.0), "teleport": true}, {"died_at": Vector2(6.0, 9.0), "teleport": false}]:
		var pool := FakeEvents.open_pool(FakeEvents.endless_session())
		var heard: Array[Dictionary] = []
		pool.respawned.connect(func(grace_s: float, teleport: bool) -> void:
			heard.append({"grace_s": grace_s, "teleport": teleport, "drawn_at": pool.cell_view.position,
				"sim_at": PlaneSpace.to_world(pool.sim.motion.position), "focus": pool.camera.focus,
				"abs": pool.sim.absolute_position_am(), "dead": pool.cell_view._dead}))
		var sim := pool.sim
		var tag := "died at %s" % case.died_at
		FakeEvents.frame(pool)
		check(sim.debug_teleport_abs(case.died_at.x, case.died_at.y, 0.0), "%s: the cell swims there" % tag)
		FakeEvents.frame(pool)
		check(sim.debug_hurt_player(sim.state.max_health) and sim.dead, "%s: the cell dies" % tag)
		FakeEvents.frame(pool)
		pool.session.respawn_after_death()
		check(heard.is_empty() and sim.respawn_pending, "%s: the respawn waits for the next step" % tag)
		FakeEvents.frame(pool)
		check_eq(heard.size(), 1, "%s: one respawn, on the next step" % tag)
		if heard.size() == 1:
			var h: Dictionary = heard[0]
			check_eq([h.grace_s, h.teleport], [5.0, case.teleport], "%s: the shelter, and teleport %s" % [tag, case.teleport])
			check(h.drawn_at.is_equal_approx(h.sim_at), "%s: the cell is drawn where the sim put it: %s, %s" % [tag, h.drawn_at, h.sim_at])
			check(Vector2(h.focus.x, h.focus.z).is_equal_approx(Vector2(h.sim_at.x, h.sim_at.z)),
				"%s: the camera is on it at once: %s" % [tag, h.focus])
			var cp: PackedFloat64Array = sim.world.checkpoint_am
			check(Vector2(h.abs[0] - cp[0], h.abs[1] - cp[1]).length() < 3.0,
				"%s: back at the checkpoint: %s, %s" % [tag, h.abs, cp])
			check(not h.dead, "%s: alive when the message shows" % tag)
			if case.teleport:
				check(sim.world.local_of_abs(cp[0], cp[1]).length() < 1e-3, "%s: the origin moved to the checkpoint" % tag)
			var column := PlaneSpace.to_world(sim.world.local_of_abs(cp[0], cp[1]))
			FakeEvents.frame(pool)
			check(pool.markers.column().position.is_equal_approx(column), "%s: the column stands at the checkpoint" % tag)
		pool.free()


## The HUD bound to `pool` outside the tree. The threat arrows read the live viewport when they
## bind, which a pool outside the tree lacks, so they bind with the camera hidden from them.
func _hud(pool: PoolScene) -> Hud:
	var hud: Hud = HUD_SCENE.instantiate()
	FakeEvents.ready_tree(hud)
	var camera := pool.camera
	pool.camera = null
	hud.bind(pool)
	pool.camera = camera
	return hud


func _last_toast(hud: Hud) -> String:
	var texts := hud.toast_texts()
	return texts[texts.size() - 1] if not texts.is_empty() else ""


## Camera3D's projection for a camera outside the tree on a SCREEN-sized view (as
## tests/test_pool_view.gd's _unproject, keep-height fov), with a point behind the camera mirrored
## as Camera3D.unproject_position mirrors it: {"at": Vector2, "behind": bool}.
func _projector(camera: Camera3D) -> Callable:
	return func(at: Vector3) -> Dictionary:
		var view := camera.transform.affine_inverse() * at
		var clip := Projection.create_perspective(camera.fov, SCREEN.aspect(), camera.near, camera.far) * Vector4(view.x, view.y, view.z, 1.0)
		var ndc := Vector2(clip.x, clip.y) / clip.w
		return {"at": Vector2((ndc.x + 1.0) * 0.5 * SCREEN.x, (1.0 - ndc.y) * 0.5 * SCREEN.y), "behind": view.z >= 0.0}
