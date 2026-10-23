extends TestCase
## The debug panel's AI section (M1 step 3, plan section 16; the debug AI lines are never cut): two
## lines per creature, then the niches, the respawn queue and the token, then the cell. They are
## built from the running sim of the real pool. The panel on screen, F9 and F10 are covered by the
## scene smoke. The render section's GPU line (micro-world plan C1) is checked from fed readings.

const DebugPanel := preload("res://game/dev/debug_panel.gd")
const PANEL_SCENE := "res://game/dev/debug_panel.tscn"
const PLAYER := "player"
const IN_FRONT_M := 2.75              ## inside the ambush hunter's lunge window (plan section 19)
const TELL_LIMIT_TICKS := 600

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog


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
