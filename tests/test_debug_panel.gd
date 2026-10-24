extends TestCase
## The debug panel's AI section (M1 step 3, plan section 16; the debug AI lines are never cut): two
## lines per creature, then the niches, the respawn queue and the token, then the cell. They are
## built from the running sim of the real pool. The panel on screen, F9 and F10 are covered by the
## scene smoke. The render section's GPU line (micro-world plan C1) is checked from fed readings.
##
## S1 (docs/s1/s1-content.md 6.14, 7.5 and 9): the endless sea's buttons, world line, zone rows and
## AI lines, on a panel refreshed from a real endless pool on the shipped world (a fake main holds
## it); the chunk gizmo's layer; and the swim tour's route, long-frame tags and G18 gate.
##
## S2 (docs/s2/s2-view.md 9, 10.4 and 12.2): the growth buttons and commands, the growth line and the
## size refusal, on a panel over a growing endless pool (FakeWorldGen); the gizmo's posts and
## remnants; the swim route's growth steps, the grow route, the growth windows and the S2G26 gate.

const DebugPanel := preload("res://game/dev/debug_panel.gd")
const DevGizmos := preload("res://game/dev/dev_gizmos.gd")
const PerfTour := preload("res://game/dev/perf_tour.gd")
const FakeEvents := preload("res://tests/fakes/fake_world_events.gd")
const PANEL_SCENE := "res://game/dev/debug_panel.tscn"
const PLAYER := "player"
const IN_FRONT_M := 2.75              ## inside the ambush hunter's lunge window (plan section 19)
const TELL_LIMIT_TICKS := 600

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog


## What the panel reads from main: the pool, its session and the dev layer with the gizmos.
class FakeMain:
	extends Node
	signal screen_changed(screen: Node)
	var pool: PoolScene
	var session: GameSession
	var dev_layer: Node
	var last_run := {}


## A PoolSim that never steps, for the swim route: it records the dev commands, and its tick moves
## only when the test moves it.
class RouteSim:
	extends PoolSim
	var calls: Array = []                 ## [command, tick]

	func _init() -> void:
		tick = 1000
		state = ActorState.new()
		state.energy_capacity = 120.0
		state.max_health = 100.0

	func debug_set_hidden(on: bool) -> bool:
		calls.append(["hidden %s" % on, tick])
		return true

	func debug_set_energy(_value: float) -> bool:
		calls.append(["energy", tick])
		return true

	func debug_hurt_player(amount: float) -> bool:
		calls.append(["hurt %.0f" % amount, tick])
		dead = true
		return true

	func debug_fill_meter(share := 1.0) -> bool:
		calls.append(["fill %.1f" % share, tick])
		return true

	func debug_force_growth() -> bool:
		calls.append(["force", tick])
		return true

	func debug_set_size(n: int) -> bool:
		calls.append(["size %d" % n, tick])
		return true

	func absolute_position_am() -> PackedFloat64Array:
		return PackedFloat64Array([tick * 0.1, 9.0])


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()


func _sim(seed_value: int) -> PoolSim:
	var r := Lineage.found(seed_value, "test+dev", catalog, "grazer")
	r.save.player["position"] = PlaneSpace.to_save(layout.spawn)
	return PoolSim.create(r.save, catalog, layout, species)


func _at_site(sim: PoolSim, site_id: String) -> CreatureField.Creature:
	for c in sim.creatures.creatures:
		if c.site_id == site_id:
			return c
	return null


func test_the_ai_section_lists_every_creature_then_the_niches_and_the_cell() -> void:
	var sim := _sim(4242)
	var lines := DebugPanel.ai_lines(sim)
	var count := sim.creatures.creatures.size()
	check_eq(count, 7, "the real pool starts with its seven creatures")
	check_eq(lines.size(), count * 2 + 2, "two lines per creature, then the niche line and the cell's line")
	for i in count:
		var c := sim.creatures.creatures[i]
		var head := lines[i * 2]
		check(head.begins_with("%s %s @%s  " % [c.id, c.species_id, c.site_id]), "line %d names %s, its species and its site (%s)" % [i * 2, c.id, head])
		check(head.contains(c.brain.state), "and its state (%s)" % head)
		check(lines[i * 2 + 1].begins_with("    hp ") and lines[i * 2 + 1].contains("  home "), "its second line has its health and home (%s)" % lines[i * 2 + 1])
		check(lines[i * 2 + 1].contains("ignore: all 3.0 s (settling)"), "a new creature settles for 3 s first (%s)" % lines[i * 2 + 1])
	check_eq(lines[count * 2], "niches: ambush 3/3 territorial 4/4   queue: -   token: -", "the niches are full, nothing waits and no one holds the token")
	check(lines[count * 2 + 1].begins_with("player: sheltered 5.0 s  streak 0  last death -  checkpoint (%.1f, %.1f)" % [layout.spawn.x, layout.spawn.y]),
		"the cell starts sheltered for 5 s, at its checkpoint (%s)" % lines[count * 2 + 1])


func test_an_engaged_creature_shows_its_phase_timer_its_belief_its_give_up_timer_and_the_token() -> void:
	var sim := _sim(4242)
	sim.grace_until = sim.tick
	var hunter := _at_site(sim, "lair_se")
	check(hunter != null, "lair_se has its hunter")
	if hunter == null:
		return
	hunter.brain.ignore_all_until = 0
	var spot: Vector2 = hunter.brain.home + Vector2.from_angle(hunter.brain.home_heading) * IN_FRONT_M
	check(sim.debug_teleport(spot, hunter.brain.home_heading), "the cell placed in front of the lair")
	var told := false
	for i in TELL_LIMIT_TICKS:
		sim.step(SimIntent.new())
		for e in sim.drain_events():
			told = told or (e.type == "creature_tell" and e.id == hunter.id and e.target == PLAYER)
		if told:
			break
	check(told, "the hunter starts its tell on the cell")
	var lines := DebugPanel.creature_lines(sim, hunter)
	var head := lines[0]
	# The tell began on the last step: one tick in, of 72.
	check(head.contains("  attack/tell 0.02/1.20 s"), "its phase and the time in it over its length (%s)" % head)
	check(head.contains("  → player (sight, 0.0 s ago)"), "where it last sensed the cell, and how (%s)" % head)
	check(head.contains("  give-up ") and head.ends_with("/5.0 s  [token]"), "its give-up timer and the token it holds (%s)" % head)
	check(DebugPanel.summary_line(sim).ends_with("token: %s" % hunter.id), "the niche line names the token's holder")
	sim.debug_set_hidden(true)
	sim.debug_set_ai_frozen(true)
	check(DebugPanel.player_line(sim).ends_with("not sheltered  streak 0  last death -  checkpoint (%.1f, %.1f)  AI frozen  hidden from AI" % [layout.spawn.x, layout.spawn.y]),
		"the cell's line names the dev switches that are on (%s)" % DebugPanel.player_line(sim))


func test_a_killed_creature_s_site_waits_in_the_queue_and_a_death_shows_on_the_cell_s_line() -> void:
	var sim := _sim(4242)
	var hunter := _at_site(sim, "lair_se")
	check(sim.debug_teleport(hunter.motion.position + Vector2(0.0, -2.0)), "the cell beside lair_se's hunter")
	check(sim.debug_kill_nearest_creature(), "the nearest creature killed")
	var summary := DebugPanel.summary_line(sim)
	check(summary.begins_with("niches: ambush 2/3 territorial 4/4   queue: lair_se in "), "its niche drops a count and its site waits (%s)" % summary)
	var due_s := (int(sim.creatures.queue[0].at_tick) - sim.tick) / 60.0
	check(summary.contains("lair_se in %.1f s" % due_s), "the wait is counted down (%s)" % summary)
	Lineage.apply_death(sim.save, "killed:ambush_hunter")
	check(DebugPanel.player_line(sim).contains("  last death killed:ambush_hunter  "), "the cell's last death is named")
	var bare := PoolSim.create(Lineage.found(1, "test+dev", catalog, "grazer").save, catalog, layout)
	check_eq(DebugPanel.ai_lines(bare)[0], "No creatures in this pool.", "a pool without species says so")


func test_the_render_section_shows_the_gpu_time_of_the_frames_the_renderer_timed() -> void:
	check_eq(DebugPanel.gpu_line(PackedFloat32Array([2.0, 3.0, 7.0])), "GPU 4.00 ms · longest 7.00 ms (last 3 frames)",
		"the GPU line gives the average and the longest GPU time")
	check_eq(DebugPanel.gpu_line(PackedFloat32Array()), "GPU n/a (the renderer has timed no frame)",
		"a renderer that times nothing (headless) shows n/a")
	var panel: CanvasLayer = (load(PANEL_SCENE) as PackedScene).instantiate()
	var lines: PackedStringArray = panel.call("_render_lines")
	check(lines.has("GPU n/a (the renderer has timed no frame)") and panel.fields.gpu_ms == 0.0,
		"before any timed frame the render section shows n/a and gpu_ms 0 (%s)" % [lines])
	panel.take_gpu_sample(0.0)
	panel.take_gpu_sample(-1.0)
	panel.take_gpu_sample(9.0)
	for i in DebugPanel.FRAME_WINDOW:
		panel.take_gpu_sample(2.0)
	lines = panel.call("_render_lines")
	check(lines.has("GPU 2.00 ms · longest 2.00 ms (last %d frames)" % DebugPanel.FRAME_WINDOW),
		"untimed frames are skipped and the oldest leave the window (%s)" % [lines])
	check(lines.find("GPU 2.00 ms · longest 2.00 ms (last %d frames)" % DebugPanel.FRAME_WINDOW) == 1, "the GPU line follows the FPS line")
	check_eq(panel.fields.gpu_ms, 2.0, "fields.gpu_ms is the average shown")
	check_eq(panel.fields.gpu_longest_ms, 2.0, "fields.gpu_longest_ms is the longest shown")
	panel.free()


# --- S1: the endless sea (s1-content.md 7.5) ---

## A panel built from its scene and readied (itself only: its scroll box needs a viewport), reading
## `pool` through a fake main whose dev layer holds the gizmos. Free it with _free_panel.
func _panel(pool: PoolScene) -> CanvasLayer:
	var panel: CanvasLayer = (load(PANEL_SCENE) as PackedScene).instantiate()
	panel.notification(Node.NOTIFICATION_READY)
	var main := FakeMain.new()
	main.pool = pool
	main.session = pool.session
	main.dev_layer = Node.new()
	var gizmos: Node3D = DevGizmos.new()
	gizmos.name = "DevGizmos"
	gizmos.visible = false
	main.dev_layer.add_child(gizmos)
	main.add_child(main.dev_layer)
	panel.main = main
	return panel


func _free_panel(panel: CanvasLayer) -> void:
	var pool: PoolScene = panel.main.pool
	panel.main.free()
	panel.free()
	pool.free()


func _frames(pool: PoolScene, n: int) -> void:
	for i in n:
		FakeEvents.frame(pool)


func test_endless_mode_shows_the_world_buttons_and_line() -> void:
	for endless: bool in [true, false]:
		var tag := "endless" if endless else "pool"
		var panel := _panel(FakeEvents.open_pool(FakeEvents.shipped_session() if endless else FakeEvents.pool_session()))
		var pool: PoolScene = panel.main.pool
		_frames(pool, 2)
		panel.refresh()
		for command in ["teleport_far", "rebase", "chunks"]:
			check_eq((panel._buttons[command] as Button).visible, endless, "%s: the %s button shows only in the endless sea" % [tag, command])
		check_eq((panel._buttons.teleport as Button).text, "Teleport home" if endless else "Teleport to spawn", "%s: Teleport names where it goes" % tag)
		check_eq(panel.fields.has("world_line"), endless, "%s: the world line only in the endless sea" % tag)
		if endless:
			var sim := pool.sim
			check(sim.debug_teleport_abs(5000.0, -3000.0, 0.0), "the cell 5 km east and 3 km north")
			_frames(pool, 30)
			panel.refresh()
			var w := sim.world
			var line: String = panel.fields.world_line
			check_eq(line, DebugPanel.world_line(sim), "the line shown is world_line(sim)")
			check(panel._sim.text.ends_with(line + "\n" + panel.fields.growth_line), "last in the sim section but for the growth line")
			check(absf(w.origin_x_am - 5000.0) <= w.chunk_tm and absf(w.origin_y_am + 3000.0) <= w.chunk_tm, "the origin moved there (%s)" % line)
			check(line.begins_with("origin %.1f, %.1f km · tile 78,-47 " % [w.origin_x_am / 1000.0, w.origin_y_am / 1000.0]),
				"it names the origin in km and the tile under the cell (%s)" % line)
			var info := w.gen.tile_info(WorldConfig.band_of(w.size), 78, -47)
			var region := str(info.rare) if not str(info.rare).is_empty() else str(info.region)
			check(not region.is_empty() and line.contains("tile 78,-47 %s · " % region), "and the tile's region (%s)" % line)
			var counts := " · chunks %d/36 · awake %d/12 · asleep %d/30 · food %d/120 · " % [w.loaded_keys().size(),
				sim.creatures.awake().size(), w.sleeping_ids().size(), sim.plankton.items.size()]
			check(line.contains(counts), "chunks, awake, asleep and food against their caps: %s in %s" % [counts, line])
			check(w.loaded_keys().size() > 0 and sim.plankton.items.size() > 0, "with chunks and food to count")
			w.counters.awake_overflow = 1
			w.counters.chunk_waits = 2
			w.counters.food_trimmed = 3
			w.counters.evictions = 4
			check(DebugPanel.world_line(sim).ends_with(" · overflow 1 · waits 2 · trimmed 3 · evicted 4"), "then the four counters (%s)" % DebugPanel.world_line(sim))
		_free_panel(panel)


func test_teleport_home_in_endless_mode_goes_to_the_absolute_spawn() -> void:
	var panel := _panel(FakeEvents.open_pool(FakeEvents.shipped_session()))
	var pool: PoolScene = panel.main.pool
	var sim := pool.sim
	_frames(pool, 2)
	check(sim.debug_teleport_abs(5000.0, 0.0, 0.0), "the cell 5 km out")
	_frames(pool, 2)
	check(panel.run("teleport"), "Teleport applies")
	var at := sim.absolute_position_am()
	check(Vector2(at[0] - DebugPanel.HOME_AM.x, at[1] - DebugPanel.HOME_AM.y).length() <= 2.0 and DebugPanel.HOME_AM == Vector2(0.0, 9.0),
		"home: within 2 tm of (0, 9) absolute (%s)" % at)
	check(is_equal_approx(sim.motion.heading, -1.5708), "facing north (%.4f)" % sim.motion.heading)
	_frames(pool, 1)
	check(pool.cell_view.position.is_equal_approx(PlaneSpace.to_world(sim.motion.position)), "and drawn there")
	check(panel.run("teleport_far"), "Teleport 100 km east applies")
	at = sim.absolute_position_am()
	check(Vector2(at[0] - 100000.0, at[1] - 9.0).length() <= 2.0, "100 km east of home (%s)" % at)
	_frames(pool, 2)
	var w := sim.world
	var origin := Vector2(w.origin_x_am, w.origin_y_am)
	var before := sim.absolute_position_am()
	check(panel.run("rebase"), "Rebase now applies")
	check_eq(Vector2(w.origin_x_am, w.origin_y_am) - origin, Vector2(w.rebase_step_tm, 0.0), "the origin moves one rebase step east")
	var after := sim.absolute_position_am()
	check(absf(after[0] - before[0]) < 1e-6 and absf(after[1] - before[1]) < 1e-6, "and the cell stays where it was (%s, %s)" % [before, after])
	var gizmos: Node3D = panel.main.dev_layer.get_node("DevGizmos")
	check(panel.run("chunks") and gizmos.show_chunks and gizmos.visible, "Chunk gizmo turns the chunk layer on, and the gizmos with it")
	check(panel.run("chunks") and not gizmos.show_chunks, "and off again")
	_free_panel(panel)


func test_endless_zone_rows_list_the_nearest_eight_loaded_zones() -> void:
	var panel := _panel(FakeEvents.open_pool(FakeEvents.shipped_session()))
	var pool: PoolScene = panel.main.pool
	var sim := pool.sim
	_frames(pool, 60)
	panel.refresh()
	var first := _nearest_zone_ids(sim)
	check(sim.region.zones.size() > DebugPanel.ZONE_ROWS, "more loaded zones (%d) than rows" % sim.region.zones.size())
	check_eq(panel.fields.zone_rows, first, "the rows are the 8 loaded zones nearest the cell, nearest first")
	check_eq(panel._zone_rows.keys().size(), DebugPanel.ZONE_ROWS, "one row each")
	var at := sim.absolute_position_am()
	check(sim.debug_teleport_abs(at[0] + 100.0, at[1], 0.0), "the cell 100 tm east")
	_frames(pool, 60)
	panel.refresh()
	panel.refresh()
	var moved := _nearest_zone_ids(sim)
	check(moved != first, "a different 8 zones lie nearest there")
	check_eq(panel.fields.zone_rows, moved, "and the rows follow within two refreshes (2 Hz)")
	for id in moved:
		check(panel._zone_rows.has(id), "%s has its row" % id)
	var pool_sim := _sim(4242)
	var ids := []
	for z in pool_sim.region.zones:
		ids.append(z.id)
	check_eq(Array(DebugPanel.zone_row_ids(pool_sim)), ids, "the pool keeps a row per zone, in order")
	_free_panel(panel)


## The ZONE_ROWS loaded zones nearest the cell, nearest first, ties by id.
func _nearest_zone_ids(sim: PoolSim) -> Array:
	var rows := []
	for z in sim.region.zones:
		rows.append([sim.motion.position.distance_to(z.center), str(z.id)])
	rows.sort()
	var out := []
	for r in rows.slice(0, DebugPanel.ZONE_ROWS):
		out.append(r[1])
	return out


func test_endless_ai_lines_list_awake_creatures_and_count_sleepers() -> void:
	var panel := _panel(FakeEvents.open_pool(FakeEvents.shipped_session(FakeEvents.SEED, PackedFloat64Array([300.0, 9.0]))))
	var pool: PoolScene = panel.main.pool
	var sim := pool.sim
	_frames(pool, 120)
	panel.refresh()
	var awake := sim.creatures.awake()
	var sleepers := sim.world.sleeping_ids()
	check(awake.size() > 0 and sleepers.size() > 0, "creatures both awake (%d) and asleep (%d)" % [awake.size(), sleepers.size()])
	var lines := DebugPanel.ai_lines(sim)
	check_eq(lines.size(), awake.size() * 2 + 3, "two lines per awake creature, then asleep, the niche line and the cell's")
	for i in awake.size():
		check(lines[i * 2].begins_with("%s %s @%s  " % [awake[i].id, awake[i].species_id, awake[i].site_id]), "line %d names %s" % [i * 2, awake[i].id])
	check_eq(lines[awake.size() * 2], "asleep: %d" % sleepers.size(), "asleep counts the sleepers")
	for id in sleepers:
		for line in lines:
			check(not line.begins_with(id + " "), "no line for the sleeper %s" % id)
	var ids := []
	for c in awake:
		ids.append(c.id)
	check_eq(panel.fields.ai_creatures, ids, "the panel lists the awake ones")
	check(panel._ai.text.contains("asleep: %d" % sleepers.size()), "and shows the count")
	_free_panel(panel)


func test_the_chunk_gizmo_draws_the_stream_round_the_cell() -> void:
	var session := FakeEvents.shipped_session(FakeEvents.SEED, PackedFloat64Array([300.0, 9.0]))
	var sim := session.sim
	for i in 120:
		sim.step(SimIntent.new())
		sim.drain_events()
	var w := sim.world
	var layer := DevGizmos.chunk_layer(sim)
	var keys := w.loaded_keys()
	check_eq(layer.loaded.size(), keys.size(), "a square per loaded chunk")
	for i in keys.size():
		var square: Rect2 = layer.loaded[i]
		var corner := w.local_of_tm(keys[i].x * w.chunk_tm, keys[i].y * w.chunk_tm)
		check(square.position.is_equal_approx(corner) and square.size.is_equal_approx(Vector2.ONE * w.chunk_tm),
			"chunk %s's square at its local corner (%s, %s)" % [keys[i], square, corner])
		check(square.grow(-0.01).has_point(w.local_of_tm((keys[i].x + 0.5) * w.chunk_tm, (keys[i].y + 0.5) * w.chunk_tm)), "round its centre")
	check_eq(layer.view.size(), w.view_set_keys(sim.motion.position).size(), "a square per view-set chunk")
	var tile_tm: float = w.content.config.tile_bu * WorldConfig.bu_to_tm(w.size)
	var cell_tile := w.tile_of_local(sim.motion.position)
	var cell_square := Rect2(w.local_of_tm(cell_tile.x * tile_tm, cell_tile.y * tile_tm), Vector2.ONE * tile_tm)
	check(layer.tiles.any(func(r: Rect2) -> bool: return r.is_equal_approx(cell_square)), "the tile under the cell among the tile squares")
	check(layer.tiles.all(func(r: Rect2) -> bool: return is_equal_approx(r.size.x, tile_tm)), "every tile square a tile wide (%.0f tm)" % tile_tm)
	check_eq(layer.rings, {"wake": 40.0, "sleep": 44.0, "food": 52.0, "load": 56.0, "unload": 72.0}, "the rings at the stream's distances")
	var reach := 0
	for c in sim.creatures.awake():
		reach += 1 if w.sites.has(c.site_id) else 0
	check_eq(layer.reach.size(), reach, "a reach disc per awake creature with a site")
	check_eq(layer.sleepers.size(), w.sleeping_ids().size(), "a cross per sleeper")
	check(layer.sleepers.size() > 0 and reach > 0, "with both to draw")
	var flat := DevGizmos.chunk_layer(_sim(4242))
	check(flat.loaded.is_empty() and flat.rings.is_empty() and flat.sleepers.is_empty(), "the pool has no chunk layer")


# --- S1: the swim tour (s1-content.md 9; G18) ---

func test_a_route_prints_how_far_it_got_and_at_what_frame_rate() -> void:
	check_eq(PerfTour.progress_line("grow", 20.4, 1180, 190), "Perf tour (grow): 20 s, route tick 1180, 9.3 FPS",
		"the route, whole seconds, its ticks and frames over seconds")
	check_eq(PerfTour.progress_line("swim", 0.0, 0, 0), "Perf tour (swim): 0 s, route tick 0, 0.0 FPS", "no time yet reads 0 FPS")
	check(not PerfTour.progress_line("grow", 10.0, 600, 100).begins_with("Perf tour: "),
		"it never reads as the finished tour's line, which the Windows launch check looks for")
	check_eq(PerfTour.PROGRESS_EVERY_S, 10.0, "every 10 s")


func test_a_route_that_hangs_says_where_the_main_thread_is() -> void:
	check_eq(PerfTour.stall_line("grow", 30.7, "the draw", 300), "Perf tour (grow): no frame for 30 s, in the draw at route tick 300",
		"how long without a frame, where the main thread is and the route tick")
	check(not PerfTour.stall_line("grow", 10.0, "the physics step", 0).begins_with("Perf tour: "),
		"it never reads as the finished tour's line")
	check_eq(PerfTour.WATCH_STALL_S, 10.0, "after 10 s without a frame")
	check(PerfTour.WATCH_FIRST < PerfTour.WATCH_LAST, "the tour's step runs before the tail's")
	var tail := PerfTour.WatchTail.new()
	check_eq(tail.process_priority, PerfTour.WATCH_LAST, "the tail's step runs after every node's")
	tail.free()


func test_the_swim_tour_tags_long_frames_with_the_events_around_them() -> void:
	var frames := [{"t_s": 1.00, "ms": 10.0, "tick": 60}, {"t_s": 1.06, "ms": 60.0, "tick": 64}, {"t_s": 1.07, "ms": 12.0, "tick": 65}]
	var events := [{"t_s": 0.70, "text": "chunk_unloaded 2,0"}, {"t_s": 1.05, "text": "chunk_loaded 4,0"},
		{"t_s": 1.20, "text": "rebased 32,0"}, {"t_s": 1.40, "text": "tile_entered"}]
	var long := PerfTour.long_frames(frames, events)
	check_eq(long.size(), 1, "one frame over 50 ms")
	if long.size() == 1:
		check_eq(long[0], {"at_s": 1.06, "ms": 60.0, "tick": 64, "events": ["chunk_loaded 4,0", "rebased 32,0"]},
			"tagged with the events within 0.25 s of it, before and after, and no others")
	check(PerfTour.long_frames(frames, events, 60.0).is_empty(), "a frame at the limit is not long")
	check_eq(PerfTour.event_text({"type": "chunk_loaded", "key": Vector2i(4, -1)}), "chunk_loaded 4,-1", "a chunk event names its key")
	check_eq(PerfTour.event_text({"type": "rebased", "offset_tm": Vector2(32.0, -64.0)}), "rebased 32,-64", "a rebase its offset")
	check_eq(PerfTour.event_text({"type": "rebased", "offset_tm": Vector2(-32.5, 0.04)}), "rebased -32.5,0", "to a tenth")
	check_eq(PerfTour.event_text({"type": "respawned"}), "respawned", "any other event its type")


func test_the_swim_route_dies_far_out_then_swims_north() -> void:
	for step: int in [1, 7]:
		var sim := RouteSim.new()
		var route := PerfTour.SwimRoute.new()
		var tag := "%d ticks a call" % step
		var start := sim.tick
		var east := 0
		var intents: Array[Vector2] = []
		while sim.tick - start < PerfTour.SWIM_OUT_TICKS + 600:
			var v := route.next_intent(sim).move
			intents.append(v)
			if v.is_equal_approx(Vector2.RIGHT):
				east = sim.tick
			sim.tick += step
		check_eq(sim.calls[0], ["hidden true", start], "%s: hidden from the AI at once" % tag)
		var hurts := sim.calls.filter(func(c: Array) -> bool: return str(c[0]).begins_with("hurt"))
		check_eq(hurts.size(), 1, "%s: one death" % tag)
		if hurts.size() == 1:
			check_eq(hurts[0][0], "hurt 100", "%s: by the whole health" % tag)
			check(hurts[0][1] - start >= PerfTour.SWIM_OUT_TICKS and hurts[0][1] - start < PerfTour.SWIM_OUT_TICKS + step,
				"%s: at the first call from tick 18,000 (%d)" % [tag, hurts[0][1] - start])
			check(east < hurts[0][1] and east >= hurts[0][1] - step, "%s: east every call until then" % tag)
			check_eq(route.died_at_tick, hurts[0][1], "%s: the route keeps when" % tag)
			check(is_equal_approx(route.distance_tm(), (hurts[0][1] - start) * 0.1), "%s: and the out leg's distance (%.1f tm)" % [tag, route.distance_tm()])
		var refills := sim.calls.filter(func(c: Array) -> bool: return c[0] == "energy")
		check_eq(refills.size(), PerfTour.SWIM_OUT_TICKS / PerfTour.REFILL_TICKS + 1, "%s: refilled every 1,800 ticks of the way out" % tag)
		for i in refills.size():
			var due := i * PerfTour.REFILL_TICKS
			check(refills[i][1] - start >= due and refills[i][1] - start < due + step, "%s: refill %d at tick %d" % [tag, i, refills[i][1] - start])
		var lefts := intents.filter(func(v: Vector2) -> bool: return v != Vector2.ZERO and not v.is_equal_approx(Vector2.RIGHT))
		check(lefts.is_empty(), "%s: nothing but east and stillness before the respawn" % tag)
		check(intents.slice(intents.size() - 10).all(func(v: Vector2) -> bool: return v == Vector2.ZERO), "%s: still while dead" % tag)
		route.on_event({"type": "chunk_loaded"}, sim.tick)
		check_eq(route.back_from_tick, -1, "%s: only a respawn starts the way back" % tag)
		sim.dead = false
		route.on_event({"type": "respawned", "teleport": true}, sim.tick)
		var back := sim.tick
		var north := 0
		while not route.done and sim.tick - back < PerfTour.SWIM_BACK_TICKS * 2:
			var v := route.next_intent(sim).move
			if v.is_equal_approx(Vector2.UP):
				north = sim.tick
			elif not route.done:
				check(false, "%s: north every call after the respawn (%s at %d)" % [tag, v, sim.tick - back])
				break
			sim.tick += step
		check(route.done, "%s: done" % tag)
		check(north - back >= PerfTour.SWIM_BACK_TICKS - step and north - back < PerfTour.SWIM_BACK_TICKS,
			"%s: north for 1,200 ticks after the respawn (last at %d)" % [tag, north - back])
		check_eq(route.next_intent(sim).move, Vector2.ZERO, "%s: still once done" % tag)


func test_the_swim_tour_gates_g18() -> void:
	var good := {"low_1pct_fps": 125.0, "max_frame_ms": 40.0, "max_draw_calls": 96, "gpu_p99_ms": 5.0}
	var g := PerfTour.gate(good, 3.5)
	check(g.pass and g.failed.is_empty() and g.skipped.is_empty(), "within every bound it passes (%s)" % [g])
	check(is_equal_approx(g.low_1pct_ms, 8.0), "the 1%% low as a time (%.2f ms)" % g.low_1pct_ms)
	for bad: Array in [["low_1pct_fps", 100.0, "1% low 10.0 ms > 8.3"], ["max_frame_ms", 50.5, "longest frame 50.5 ms > 50"],
			["max_draw_calls", 97, "draw calls 97 > 96"], ["gpu_p99_ms", 5.6, "GPU P99 5.60 ms > M1 3.50 + 2.0"]]:
		var report := good.duplicate()
		report[bad[0]] = bad[1]
		var r := PerfTour.gate(report, 3.5)
		check(not r.pass and r.failed == [bad[2]], "%s %s fails it (%s)" % [bad[0], bad[1], r.failed])
	var no_m1 := PerfTour.gate(good.merged({"gpu_p99_ms": 50.0}, true), -1.0)
	check(no_m1.pass and no_m1.skipped.size() == 1, "without an M1 report the GPU part is skipped and said so (%s)" % [no_m1])
	check(is_equal_approx(PerfTour.percentile(PackedFloat32Array([4.0, 1.0, 3.0, 2.0]), 0.99), 4.0)
		and is_equal_approx(PerfTour.percentile(PackedFloat32Array(range(1, 201)), 0.99), 198.0)
		and PerfTour.percentile(PackedFloat32Array(), 0.99) == 0.0, "the P99 is the nearest rank")
	check(is_equal_approx(PerfTour.summarize(PackedFloat32Array([16.0]), PackedFloat32Array(range(1, 101))).gpu_p99_ms, 99.0),
		"the summary carries the GPU P99")
	var dir := "user://test_debug_panel"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + "/perf_m1.json"
	for case: Array in [[{"gpu_p99_ms": 3.25, "gpu_frames": 5000}, 3.25], [{"gpu_p99_ms": 0.0, "gpu_frames": 0}, -1.0], [{"avg_fps": 60.0}, -1.0]]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(case[0]))
		file.close()
		check_eq(PerfTour.m1_gpu_p99_ms(path), case[1], "the M1 report %s reads %.2f" % [case[0], case[1]])
	DirAccess.remove_absolute(path)
	check_eq(PerfTour.m1_gpu_p99_ms(path), -1.0, "no M1 report reads -1")



# --- S2: growth (s2-view 9 and 12.2) ---

func test_the_growth_buttons_run_the_dev_commands_and_refuse_a_size_above_the_top() -> void:
	for grows: bool in [true, false]:
		var tag := "growth on" if grows else "growth off"
		var panel := _panel(FakeEvents.open_pool(FakeEvents.endless_session(FakeEvents.SEED, PackedFloat64Array(), grows)))
		var pool: PoolScene = panel.main.pool
		var sim := pool.sim
		_frames(pool, 2)
		panel.refresh()
		for command in DebugPanel.GROWTH_BUTTONS:
			check_eq((panel._buttons[command] as Button).visible, grows, "%s: the %s button shows only where the sea grows" % [tag, command])
		check(panel._buttons.fill_meter.text == "Fill meter (F4)" and panel._buttons.force_growth.text == "Force growth (F2)"
			and panel._buttons.size_1.text == "Size 1" and panel._buttons.size_2.text == "Size 2", "%s: the buttons name what they do" % tag)
		check_eq(panel.fields.growth_line, DebugPanel.growth_line(sim), "%s: the line shown is growth_line(sim)" % tag)
		check(panel._sim.text.contains(panel.fields.growth_line), "%s: in the sim section" % tag)
		if not grows:
			check_eq(panel.fields.growth_line, "Growth: off", "growth off says so")
			check(not panel.run("fill_meter") and not panel.run("force_growth"), "growth off: fill and force do nothing")
			check(not panel.run("size_2") and sim.size() == 1, "growth off: no size 2")
			check_eq(panel.fields.refusal, "Size 2: the sea does not grow here", "and the refusal says why")
			check(panel._sim.text.ends_with("Refused: Size 2: the sea does not grow here"), "under the growth line")
			_free_panel(panel)
			continue
		var g := sim.growth
		check(panel.run("fill_meter"), "fill_meter applies")
		check(is_equal_approx(g.meter, g.ring(1)) and g.full_since >= 0, "the ring is full (%.1f of %.0f)" % [g.meter, g.ring(1)])
		check(panel.run("force_growth") and g.due, "force_growth makes the growth due")
		check(panel._sim.text.contains("Growth: size 1 · meter %.1f/%.0f · " % [g.ring(1), g.ring(1)]), "the line shows the full ring (%s)" % panel._sim.text)
		g.due = false
		var top := sim.world.max_size
		sim.world.max_size = 1
		check(not panel.run("size_2") and sim.size() == 1, "size 2 above a top of 1 is refused")
		check_eq(panel.fields.refusal, "Size 2: above this build's top (size 1)", "the refusal names the top")
		check(panel._sim.text.ends_with("Refused: Size 2: above this build's top (size 1)"), "under the growth line (%s)" % panel._sim.text)
		sim.world.max_size = top
		check(top >= 2, "the build's top is at least size 2 (%d)" % top)
		var events := []
		pool.sim_event.connect(func(e: Dictionary): events.append(e))
		check(panel.run("size_2"), "size 2 under the top applies")
		check_eq(sim.size(), 2, "the sea is at size 2")
		check_eq(panel.fields.refusal, "", "and the refusal is gone")
		check(not panel._sim.text.contains("Refused"), "from the section too")
		check(panel._sim.text.contains("Growth: size 2 · meter 0.0/%.0f · " % g.ring(2)), "the line names size 2 and its ring (%s)" % panel._sim.text)
		_frames(pool, 1)
		check(events.any(func(e: Dictionary) -> bool: return e.type == "debug" and e.command == "set_size" and e.size == 2),
			"the pool routes debug {command: set_size}")
		check(DebugPanel.threat_species(sim).has("lurker") and DebugPanel.threat_species(sim).has("elder_rammer"),
			"at size 2 F9 takes turns through the lurker and the elder rammer too (%s)" % DebugPanel.threat_species(sim))
		check(panel.run("size_1") and sim.size() == 1, "size 1 goes back")
		sim.dead = true
		check(not panel.run("size_2") and sim.size() == 1, "not while dead")
		check_eq(panel.fields.refusal, "Size 2: not now (dead or waiting to respawn)", "and the refusal says so")
		sim.dead = false
		_free_panel(panel)


func test_the_growth_line_names_every_part() -> void:
	var session := FakeEvents.endless_session(FakeEvents.SEED, PackedFloat64Array(), true)
	var sim := session.sim
	var g := sim.growth
	check_eq(DebugPanel.growth_line(sim), "Growth: size 1 · meter 0.0/%.0f · calm 0/%d · blocker none · trigger auto · remnants 0" % [
		g.ring(1), int(g.cfg.calm_ticks)], "a fresh growth")
	g.meter = 37.54
	g.calm_ticks = 12
	g.blocker = "hunted"
	g.trigger = "press"
	g.armed = true
	var r := RemnantField.Remnant.new()
	r.motion = Locomotion.MotionState.new(Vector2(3.0, 0.0), 0.0)
	sim.remnants.items.append(r)
	check_eq(DebugPanel.growth_line(sim), "Growth: size 1 · meter 37.5/%.0f · calm 12/%d · blocker hunted · trigger press (armed) · remnants 1" % [
		g.ring(1), int(g.cfg.calm_ticks)], "meter to a tenth, calm over its window, the blocker, an armed press and the remnants")
	g.armed = false
	check(DebugPanel.growth_line(sim).contains(" · trigger press · "), "a press not yet made is not armed")
	check_eq(DebugPanel.growth_line(_sim(4242)), "Growth: off", "the pool does not grow")
	check_eq(DebugPanel.threat_species(_sim(4242)), PackedStringArray(["ambush_hunter", "rammer"]),
		"F9 takes turns through the species living at size 1 only")


func test_the_gizmo_marks_posts_and_remnants() -> void:
	var session := FakeEvents.endless_session(FakeEvents.SEED, PackedFloat64Array(), true)
	var sim := session.sim
	for i in 30:
		sim.step(SimIntent.new())
		sim.drain_events()
	check(DevGizmos.growth_layer(sim).posts.is_empty() and DevGizmos.growth_layer(sim).remnants.is_empty(), "nothing without posts or remnants")
	check(sim.debug_spawn_threat_ahead(sim.species.species_ids()[0]), "a creature ahead")
	var c: CreatureField.Creature = null
	for awake in sim.creatures.awake():
		if awake.brain != null:
			c = awake
	check(c != null, "an awake creature with a brain")
	if c == null:
		return
	var a := c.brain.home
	var b := a + Vector2(4.0, 1.0)
	CreatureBrain.set_posts(c.brain, [{"home": a, "heading": 0.0, "territory": {}}, {"home": b, "heading": 1.0, "territory": {}}])
	var cell := sim.motion.position
	var r := RemnantField.Remnant.new()
	r.motion = Locomotion.MotionState.new(cell + Vector2(0.0, -5.0), 2.0)
	var on := RemnantField.Remnant.new()
	on.motion = Locomotion.MotionState.new(cell, 0.5)
	sim.remnants.items.append_array([r, on])
	var layer := DevGizmos.growth_layer(sim)
	check_eq(layer.posts, [a, b], "a cross at each post")
	check_eq(layer.remnants.size(), 2, "a mark per remnant")
	if layer.remnants.size() == 2:
		check(layer.remnants[0].at == r.motion.position and layer.remnants[0].flee.is_equal_approx(Vector2(0.0, -1.0)),
			"at the remnant, fleeing straight away from the cell (%s)" % [layer.remnants[0]])
		check(layer.remnants[1].flee.is_equal_approx(Vector2.from_angle(0.5)), "one on the cell flees along its heading (%s)" % [layer.remnants[1]])
	check(DevGizmos.growth_layer(_sim(4242)).remnants.is_empty(), "the pool has no remnants")


func test_the_tours_take_their_growth_steps() -> void:
	var settings := SettingsService.new("user://test_debug_panel/settings.cfg")
	for step: int in [1, 7]:
		var tag := "%d ticks a call" % step
		# The swim route's 16,000 ticks are walked at least 4 a call (the fast tier's time; every step
		# tick is a multiple of 4, so each is still met on its tick); the grow route's take every step.
		var swim_step := maxi(step, 4)
		var sim := RouteSim.new()
		var route := PerfTour.SwimRoute.new(settings)
		var start := sim.tick
		var reduce := {}
		while sim.tick - start < 16000:
			route.next_intent(sim)
			reduce[sim.tick - start] = settings.reduce_camera_motion()
			sim.tick += swim_step
		var steps := sim.calls.filter(func(c: Array) -> bool: return str(c[0]) in ["fill 1.0", "force", "size 1"])
		check_eq(steps.map(func(c: Array) -> String: return c[0]), ["fill 1.0", "force", "size 1", "fill 1.0", "force"],
			"%s: a growth, back to size 1, a growth" % tag)
		if steps.size() == 5:
			for i: int in 5:
				var due: int = [7200, 7200, 14400, 15000, 15000][i]
				check(steps[i][1] - start >= due and steps[i][1] - start < due + swim_step, "%s: step %d at %d (%d)" % [tag, i, due, steps[i][1] - start])
		for t: int in reduce:
			check_eq(reduce[t], t >= 15000 and t < 15900, "%s: reduce motion on from 15,000 to 15,900 only (at %d)" % [tag, t])
			if reduce[t] != (t >= 15000 and t < 15900):
				break
		var grow_sim := RouteSim.new()
		var grow := PerfTour.GrowRoute.new(settings)
		var begin := grow_sim.tick
		var seen_reduce := []
		var done_at := -1
		while grow_sim.tick - begin < 3000:
			var v := grow.next_intent(grow_sim).move
			check_eq(v, Vector2.ZERO, "%s: the grow route keeps the cell still" % tag)
			if v != Vector2.ZERO:
				break
			if grow.done:
				done_at = grow_sim.tick - begin
				break
			if settings.reduce_camera_motion():
				seen_reduce.append(grow_sim.tick - begin)
			grow_sim.tick += step
		check(done_at >= PerfTour.GROW_ROUTE_TICKS and done_at < PerfTour.GROW_ROUTE_TICKS + step,
			"%s: done at the first call from 2,400 ticks (%d)" % [tag, done_at])
		check_eq(grow_sim.calls[0], ["hidden true", begin], "%s: hidden at once" % tag)
		var acts := grow_sim.calls.filter(func(c: Array) -> bool: return str(c[0]) in ["fill 1.0", "force", "size 1"])
		check_eq(acts.map(func(c: Array) -> String: return c[0]), ["fill 1.0", "force", "size 1", "fill 1.0", "force"], "%s: the grow route's steps" % tag)
		if acts.size() == 5:
			for i: int in 5:
				var due: int = [300, 300, 1200, 1500, 1500][i]
				check(acts[i][1] - begin >= due and acts[i][1] - begin < due + step, "%s: grow step %d at %d (%d)" % [tag, i, due, acts[i][1] - begin])
		check(not seen_reduce.is_empty() and seen_reduce.min() >= 1500 and seen_reduce.max() < 2100 + step,
			"%s: reduce motion on from 1,500 to 2,100" % tag)
		check(not settings.reduce_camera_motion(), "%s: and back off after" % tag)
	settings.set_value(PerfTour.REDUCE_MOTION, true)
	var kept := RouteSim.new()
	var keep_route := PerfTour.GrowRoute.new(settings)
	var from := kept.tick
	while not keep_route.done:
		keep_route.next_intent(kept)
		kept.tick += 1
	check(settings.reduce_camera_motion(), "a player's own reduce motion is put back on (from %d)" % from)
	check(not FileAccess.file_exists("user://test_debug_panel/settings.cfg"), "and never saved")


func test_the_tours_judge_the_frames_round_each_growth() -> void:
	var frames := []
	for i in 600:
		frames.append({"t_s": i / 60.0, "ms": 16.0, "tick": i})
	frames[150].ms = 49.0
	frames[400].ms = 70.0
	var growths := [{"tick": 120, "t_s": 2.0, "reduce_motion": false}, {"tick": 480, "t_s": 8.0, "reduce_motion": true}]
	var w := PerfTour.growth_windows(frames, growths)
	check_eq(w.size(), 2, "a window per growth")
	if w.size() == 2:
		check_eq(w[0], {"tick": 120, "t_s": 2.0, "max_frame_ms": 49.0, "frames": 271, "reduce_motion": false},
			"the frames within 2.5 s either side, their longest and the setting (%s)" % [w[0]])
		check_eq(w[1].max_frame_ms, 70.0, "the second window holds the 70 ms frame (5.5 s to 10 s)")
		check_eq(w[1].reduce_motion, true, "with reduce motion on")
	check_eq(PerfTour.growth_windows(frames, growths, 0.5)[1].max_frame_ms, 16.0, "a narrower window misses it")
	var g := PerfTour.growth_gate(w)
	check(not g.growth_pass and g.growth_failed == ["growth at tick 480: 70.0 ms"], "a frame over 50 ms fails S2G26 (%s)" % [g])
	check_eq(PerfTour.growth_verdict(g), " · S2G26 FAIL: growth at tick 480: 70.0 ms", "and the line says where")
	frames[400].ms = 50.0
	var ok := PerfTour.growth_gate(PerfTour.growth_windows(frames, growths))
	check(ok.growth_pass and ok.growth_failed.is_empty(), "50 ms passes (%s)" % [ok])
	check_eq(PerfTour.growth_verdict(ok), " · S2G26 pass", "and the line says so")
	check_eq(PerfTour.growth_gate([]), {"growth_pass": false, "growth_failed": ["no growth"]}, "a tour with no growth fails")
