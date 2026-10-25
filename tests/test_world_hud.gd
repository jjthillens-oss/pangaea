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
		pool._route({"type": "growth_began", "from": 1, "to": 2, "center_old": sim.motion.position, "center_am": [0.0, 0.0], "factor": 1.6})
		FakeEvents.frame(pool)
		cell = PlaneSpace.to_plane(pool.cell_view.position)
		var k := pool.depth_k()
		expected = PlaneSpace.to_world(cell + Vector2.LEFT * (sim.phenotype.radius + WorldMarkers.ARROW_RING_GAP) * k, WorldMarkers.ARROW_Y)
		check(k < 1.0 and arrow.position.is_equal_approx(expected), "through a growth (S2) at k of its offset from the cell (k %.3f): %s, %s" % [k, arrow.position, expected])
	check(sim.debug_hurt_player(sim.state.max_health) and sim.dead, "the cell dies")
	FakeEvents.frame(pool)
	check(arrow != null and not arrow.visible, "the arrow hides while the cell is dead")
	pool.free()


## S2 (V-18): the arrow's threshold is 40 tm at every size, so 64 am at size 2, and the distance it
## reports stays in am, the same number before and after a growth.
func test_the_arrow_threshold_is_in_tm_and_its_distance_in_am() -> void:
	var at_2 := WorldConfig.tm_to_am(2)
	check_near(at_2, 1.6, 1e-12, "1 tm is 1.6 am at size 2")
	check(WorldMarkers.origin_arrow(PackedFloat64Array([50.0, 0.0])).visible, "50 am out: shown at size 1")
	check(not WorldMarkers.origin_arrow(PackedFloat64Array([50.0, 0.0]), PackedFloat64Array([0.0, 0.0]), at_2).visible,
		"hidden at size 2 (31 tm)")
	check(WorldMarkers.origin_arrow(PackedFloat64Array([65.0, 0.0]), PackedFloat64Array([0.0, 0.0]), at_2).visible,
		"shown beyond 64 am at size 2")
	var one := WorldMarkers.origin_arrow(PackedFloat64Array([300.0, 40.0]))
	var two := WorldMarkers.origin_arrow(PackedFloat64Array([300.0, 40.0]), PackedFloat64Array([0.0, 0.0]), at_2)
	check_near(two.distance_am, one.distance_am, 1e-12, "the distance is the same across a growth")
	check_eq(WorldMarkers.distance_text(two.distance_am), WorldMarkers.distance_text(one.distance_am), "and so is its text")


## S2: through a growth the column keeps standing at the old checkpoint until the relations change
## (2.0 s), then fades out there and in at the new one; both markers are drawn at k of their size.
func test_the_column_holds_through_a_growth_then_cross_fades() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var sim := pool.sim
	var world := sim.world
	var column := pool.markers.column()
	check(column != null, "the sea has a column")
	if column == null:
		pool.free()
		return
	FakeEvents.frame(pool)
	var old_cp := world.local_of_abs(world.checkpoint_am[0], world.checkpoint_am[1])
	var height := column.scale.y
	pool._route({"type": "growth_began", "from": 1, "to": 2, "center_old": sim.motion.position, "center_am": [0.0, 0.0], "factor": 1.6})
	world.checkpoint_am = PackedFloat64Array([world.checkpoint_am[0] + 30.0, world.checkpoint_am[1], 0.0, 2.0])
	var new_place := PlaneSpace.to_world(WorldMarkers.column_point(world.local_of_abs(world.checkpoint_am[0], world.checkpoint_am[1])))
	FakeEvents.frame(pool)
	check_near(column.scale.y, height * pool.depth_k(), 1e-6, "drawn at k of its height")
	check(column.position.is_equal_approx(PlaneSpace.to_world(old_cp + WorldMarkers.COLUMN_BESIDE_TM * pool.depth_k())),
		"beside the old checkpoint at k of its offset too (%s)" % column.position)
	var old_place := PlaneSpace.to_world(WorldMarkers.column_point(old_cp, pool.depth_k()))
	while pool.growth_beat.t() < GrowthBeat.RELATIONS_S - 1e-9:
		old_place = PlaneSpace.to_world(WorldMarkers.column_point(old_cp, pool.depth_k()))
		check(column.position.is_equal_approx(old_place), "at the old checkpoint at %.2f s" % pool.growth_beat.t())
		check_near(pool.markers.column_fade(), 0.0, 1e-9, "whole until 2.0 s")
		FakeEvents.frame(pool)
	var mid_out := false
	var mid_in := false
	while pool.growth_beat.t() < GrowthBeat.RELATIONS_S + 2.0 * WorldMarkers.COLUMN_FADE_S + 0.05:
		FakeEvents.frame(pool)
		var since := pool.growth_beat.t() - GrowthBeat.RELATIONS_S
		if since > 0.2 and since < 0.3:
			mid_out = column.position.is_equal_approx(old_place) and pool.markers.column_fade() > 0.3
		if since > 0.7 and since < 0.8:
			mid_in = column.position.is_equal_approx(new_place) and pool.markers.column_fade() < 0.7
	check(mid_out, "fading out at the old checkpoint")
	check(mid_in, "then in at the new one")
	check(column.position.is_equal_approx(new_place) and is_zero_approx(pool.markers.column_fade()), "then whole at the new one")
	check_near(column.scale.y, height, 1e-6, "at its own height again")
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
		return PlaneSpace.to_world(WorldMarkers.column_point(world.local_of_abs(world.checkpoint_am[0], world.checkpoint_am[1])))
	var checkpoint := PlaneSpace.to_world(world.local_of_abs(world.checkpoint_am[0], world.checkpoint_am[1]))
	check_near(column.position.distance_to(checkpoint), WorldMarkers.COLUMN_BESIDE_TM.length(), 1e-4,
		"beside the checkpoint, not on it")
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


## The cell starts next to the column, never inside it, and the column's top shows on screen at the
## default camera (art may hand over a taller or opaque piece: its drawn height is clamped).
func test_a_new_cell_starts_beside_the_column_and_sees_its_top() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	FakeEvents.frame(pool)
	var column := pool.markers.column()
	check(column != null, "the sea has a column")
	if column == null:
		pool.free()
		return
	var cell := PlaneSpace.to_plane(pool.cell_view.position)
	var base := PlaneSpace.to_plane(column.position)
	var radius := pool.sim.phenotype.radius
	check(base.distance_to(cell) >= radius + 0.25 + 1.0, "a clear gap between the cell (r %.2f) and the column: %.2f tm apart" % [radius, base.distance_to(cell)])
	var top := WorldMarkers._top_of(column) * column.scale.y
	check(top <= WorldMarkers.COLUMN_TOP_MAX_M + 1e-4 and top > 1.0, "drawn up to %.2f m above the plane" % top)
	var project := _projector(pool.camera)
	var at_cell: Dictionary = project.call(pool.cell_view.position)
	var cell_px: float = (project.call(pool.cell_view.position + Vector3.RIGHT * radius).at as Vector2).distance_to(at_cell.at)
	var foot: Vector2 = project.call(column.position).at
	var head: Dictionary = project.call(column.position + Vector3.UP * top)
	check(not head.behind and Rect2(Vector2.ZERO, SCREEN).grow(-40.0).has_point(head.at),
		"its top is on screen, 40 px clear of the edge: %s" % head.at)
	var nearest := Geometry2D.get_closest_point_to_segment(at_cell.at, foot, head.at)
	check(nearest.distance_to(at_cell.at) > cell_px * 1.5, "and on screen it stands beside the cell, not across it: %.0f px from its centre, the cell %.0f px across" % [nearest.distance_to(at_cell.at), cell_px * 2.0])
	# A piece taller than the kit's, and opaque (the rough kit's 12 m pillar), is squashed to
	# COLUMN_TOP_MAX_M; a shorter one keeps its height.
	var tall := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 12.0, 0.5)
	box.material = StandardMaterial3D.new()
	mesh.mesh = box
	mesh.position.y = 4.5
	tall.add_child(mesh)
	mesh.owner = tall
	var packed := PackedScene.new()
	packed.pack(tall)
	tall.free()
	var path := "user://test_world_hud/tall_column.tscn"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	check_eq(ResourceSaver.save(packed, path), OK, "a tall stand-in column saved")
	var kit := PlacementKit.load_from()
	kit.assets[WorldMarkers.COLUMN_ID] = {"glb": path}
	pool.markers.setup(pool.sim, kit)
	FakeEvents.frame(pool)
	column = pool.markers.column()
	check_near(WorldMarkers._top_of(column), 10.5, 1e-4, "the stand-in reaches 10.5 m as made")
	check_near(WorldMarkers._top_of(column) * column.scale.y, WorldMarkers.COLUMN_TOP_MAX_M, 1e-4, "and is drawn to the cap")
	check_eq(WorldMarkers.column_scale(3.0), 1.0, "a shorter piece keeps its height")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
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


func test_the_pip_and_its_words_keep_off_the_panels() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var world := pool.sim.world
	var hud := _hud(pool)
	var overlay := hud.world_overlay
	var rect := Rect2(Vector2.ZERO, SCREEN)
	var project := _projector(pool.camera)
	# The panels where hud.tscn lays them out at 1920 x 1080 (read off the running game): status,
	# points, a message, a hint and the controls (bottom left, 30 s from a new lineage); the toasts
	# as a box wide and tall enough for several.
	var controls := Rect2(32.0, 691.0, 500.0, 361.0)
	var panels: Array[Rect2] = [Rect2(32.0, 28.0, 480.0, 176.0), Rect2(1500.0, 28.0, 388.0, 64.0),
		Rect2(1560.0, 102.0, 328.0, 220.0), Rect2(842.0, 28.0, 236.0, 64.0), Rect2(759.0, 888.0, 402.0, 64.0), controls]
	var home: PackedFloat64Array = world.checkpoint_am
	var band := rect.grow(-ThreatIndicators.MARGIN_PX)
	var font := overlay.get_theme_default_font()
	var under := 0
	for i in 72:
		var bearing := TAU * i / 72.0
		var off := Vector2.from_angle(bearing) * 200.0
		world.checkpoint_am = PackedFloat64Array([home[0] + off.x, home[1] + off.y, 0.0, 1.0])
		FakeEvents.frame(pool)
		var p: Dictionary = project.call(pool.markers.column().position)
		var natural := ThreatIndicators.edge_point(rect, p.at, p.behind, ThreatIndicators.MARGIN_PX)
		overlay.refresh(rect, project, [])
		check(overlay.pip.at.is_equal_approx(natural), "with no panel the pip sits where an edge arrow would (%d)" % i)
		var plain_clear := Hud.WorldOverlay._clear(overlay.pip, panels)
		overlay.refresh(rect, project, panels)
		if overlay.pip.is_empty():
			check(false, "a pip at bearing %d" % i)
			continue
		var at: Vector2 = overlay.pip.at
		var reach := Hud.WorldOverlay.PIP_RADIUS_PX + Hud.WorldOverlay.PIP_OUTLINE_PX
		var disc := Rect2(at - Vector2(reach, reach), Vector2(reach, reach) * 2.0)
		for r in panels:
			check(not r.intersects(disc) and not r.intersects(overlay.pip.text),
				"bearing %d: the pip %s and its words %s keep off the panel %s" % [i, at, overlay.pip.text, r])
		var to_band := minf(minf(at.x - band.position.x, band.end.x - at.x), minf(at.y - band.position.y, band.end.y - at.y))
		check(absf(to_band) <= 0.01, "bearing %d: on the edge band (%.2f px off)" % [i, to_band])
		check(rect.grow(-Hud.WorldOverlay.TEXT_PAD_PX).encloses(overlay.pip.text), "bearing %d: its words on screen" % i)
		if plain_clear:
			check(at.is_equal_approx(natural), "bearing %d: a clear pip stays put" % i)
		else:
			under += 1
			# Nothing nearer round the band (either way) is clear.
			var around := 2.0 * (band.size.x + band.size.y)
			var ahead := fposmod(Hud.WorldOverlay._along(band, at) - Hud.WorldOverlay._along(band, natural), around)
			var slid := minf(ahead, around - ahead)
			var nearer := 0
			for k in floori(slid / Hud.WorldOverlay.SLIDE_STEP_PX):
				for way in [1.0, -1.0]:
					var q := Hud.WorldOverlay._band_point(band, Hud.WorldOverlay._along(band, natural) + way * k * Hud.WorldOverlay.SLIDE_STEP_PX)
					if Hud.WorldOverlay._clear(overlay._pip_at(font, rect, q), panels):
						nearer += 1
			check(nearer == 0, "bearing %d: slid %.0f px round the band, to the nearest clear point (%d nearer)" % [i, slid, nearer])
			check(signf(at.x - SCREEN.x * 0.5) == signf(natural.x - SCREEN.x * 0.5) or absf(natural.x - SCREEN.x * 0.5) < 400.0,
				"bearing %d: still on the column's side (%s from %s)" % [i, at, natural])
	check(under >= 8, "some bearings put the pip under a panel and it slid (%d)" % under)
	# The case the S1 frames showed: the column west and a little south, the pip under the controls.
	world.checkpoint_am = PackedFloat64Array([home[0] - 200.0, home[1] + 40.0, 0.0, 1.0])
	FakeEvents.frame(pool)
	overlay.refresh(rect, project, [])
	var natural_at: Vector2 = overlay.pip.at
	check(controls.grow(Hud.WorldOverlay.PIP_RADIUS_PX).has_point(natural_at) or controls.intersects(overlay.pip.text),
		"west-south-west the pip would sit on the controls (%s)" % natural_at)
	overlay.refresh(rect, project, panels)
	var moved: Vector2 = overlay.pip.at
	check(moved.x < SCREEN.x * 0.5 and moved.y < controls.position.y, "it slides up the west edge above them (%s)" % moved)
	for s in [0.0, 300.0, 1780.0, 2500.0, 4000.0, 5000.0]:
		var point := Hud.WorldOverlay._band_point(band, s)
		check_near(Hud.WorldOverlay._along(band, point), fposmod(s, 2.0 * (band.size.x + band.size.y)), 0.01, "round the band at %.0f" % s)
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
			var column := PlaneSpace.to_world(WorldMarkers.column_point(sim.world.local_of_abs(cp[0], cp[1])))
			FakeEvents.frame(pool)
			check(pool.markers.column().position.is_equal_approx(column), "%s: the column stands beside the checkpoint" % tag)
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


# --- S3 (s3-view 11; S3G41) ---

## Band 1's regions and rare places by their D-116 names; home from band 1 is the cradle.
func test_band_one_names() -> void:
	var names := {"veil_garden": "Veil gardens", "warden_flat": "Warden flats", "glass_reef": "Glass reef"}
	for region: String in names:
		check_eq(Hud.region_toast(region, "", 1), names[region], region)
	var rares := {"sunbeam_well": "Sunbeam well", "fallen_lattice": "Fallen lattice", "sponge_grove": "Sponge grove",
		"shed_shell": "Shed shell"}
	for rare: String in rares:
		check_eq(Hud.region_toast("rare", rare, 1), rares[rare], rare)
	for rare in TileCatalog.RARE_KINDS_BY_BAND[1]:
		check(rares.has(rare), "%s has a name" % rare)
	check_eq(str(TranslationServer.translate(Hud.CRADLE_TOAST)), "Your lineage began here", "cradle English is unchanged")
	check_eq(Hud.region_toast("home", "", 1), str(TranslationServer.translate(Hud.CRADLE_TOAST)), "home at band 1: the cradle")
	check_eq(Hud.region_toast("home", "", 0), "Home waters", "home at band 0")


## The cradle's toast shows once a session (a bind), however often the cell comes home.
func test_cradle_toast_once() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.shipped_session_at_top(4))
	var sim := pool.sim
	check(sim.debug_set_size(3), "the dev's size 3")
	FakeEvents.frame(pool)
	sim.tick = 0
	var hud := _hud(pool)
	var count := func() -> int: return hud.toast_texts().count(str(TranslationServer.translate(Hud.CRADLE_TOAST)))
	check_eq(count.call(), 1, "bind at home toasts the cradle")
	for s in [40.0, 70.0, 100.0]:
		sim.tick = roundi(s / PoolSim.DT)
		hud._on_sim_event(FakeEvents.tile_entered(Vector2i(0, 0), "home", ""))
	check_eq(count.call(), 1, "three more homecomings in 100 s: no more")
	hud._on_sim_event(FakeEvents.tile_entered(Vector2i(1, 0), "glass_reef", ""))
	check_eq(_last_toast(hud), "Glass reef", "other regions still toast")
	var camera := pool.camera
	pool.camera = null
	hud.bind(pool)
	pool.camera = camera
	check_eq(count.call(), 2, "a new bind toasts it again")
	hud.free()
	pool.free()


## A tile entered during a growth beat before its chord toasts at the chord, once.
func test_toast_waits_for_the_chord() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.shipped_session_at_top(4))
	var sim := pool.sim
	sim.debug_set_ai_frozen(true)
	var hud := _hud(pool)
	check(sim.debug_force_growth(), "a forced growth")
	FakeEvents.frame(pool)
	check(pool.growth_beat.running(), "the beat runs")
	var count := hud.toast_texts().size()
	hud._on_sim_event(FakeEvents.tile_entered(Vector2i(3, 0), "reef", ""))
	while pool.growth_beat.running() and pool.growth_beat.t() < GrowthBeat.CHORD_S:
		check_eq(hud.toast_texts().size(), count, "%.2f s: no toast yet" % pool.growth_beat.t())
		FakeEvents.frame(pool)
	check_eq(hud.toast_texts().size(), count + 1, "one toast at the chord")
	check_eq(_last_toast(hud), "Shell reef", "the region entered")
	for i in 30:
		FakeEvents.frame(pool)
	check_eq(hud.toast_texts().size(), count + 1, "and only one")
	hud.free()
	pool.free()


## A band-up where the cell keeps its tile (home, at the origin) gets no tile_entered: the chord
## names the tile under the new band, so home is the cradle once; an in-band growth names nothing.
func test_band_up_names_the_tile_at_the_chord() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.shipped_session_at_top(4))
	var sim := pool.sim
	sim.debug_set_ai_frozen(true)
	check(sim.debug_set_size(2), "the dev's size 2")
	FakeEvents.frame(pool)
	var hud := _hud(pool)
	check_eq(str(Hud.start_tile_info(sim).get("region", "")), "home", "the cell is in the home tile")
	var before := hud.toast_texts().size()
	check(sim.debug_force_growth(), "a forced growth, 2 to 3")
	FakeEvents.frame(pool)
	while pool.growth_beat.running() and pool.growth_beat.t() < GrowthBeat.CHORD_S:
		check_eq(hud.toast_texts().size(), before, "%.2f s: no toast before the chord" % pool.growth_beat.t())
		FakeEvents.frame(pool)
	check_eq(hud.toast_texts().count(str(TranslationServer.translate(Hud.CRADLE_TOAST))), 1, "the chord names home the cradle")
	# Away from home, its name's 30 s window over: the next growth is in band, and names nothing.
	check(sim.debug_teleport_abs(400.0, 400.0, 0.0), "the cell far from home")
	for i in 240:
		FakeEvents.frame(pool)
	hud._region_shown.clear()
	var added := 0
	var on_screen := hud.toast_texts().size()
	check(sim.debug_force_growth(), "a forced growth, 3 to 4")
	for i in 240:
		FakeEvents.frame(pool)
		var now := hud.toast_texts().size()
		added += maxi(now - on_screen, 0)
		on_screen = now
	check_eq(added, 0, "an in-band growth names nothing (%s)" % [hud.toast_texts()])
	hud.free()
	pool.free()
