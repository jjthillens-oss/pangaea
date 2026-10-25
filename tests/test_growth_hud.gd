extends TestCase
## The growth HUD and its inputs (S2G22, T5's part; s2-view 7.2, 7.3, 8 and 10.3): the meter ring's
## states and share, the growth line as Growth.hint() words it with the bound grow key (BP-19), the
## size badge, the payout toast at the top (C-V8), the grow press as one tick of the player's intent
## and the trigger setting sent at the start and on every change (V-16), main's player memory beside
## a named slot (C-V1), and none of it in the M1 pool (D-46). Growth is FakeGrowth until T2's lands.
## The ladder strip (s2-view 7.4): its phrases and preview line, and its icons tinted by role with a
## caption each; the idea hints (7.5, D-43): one at a time, paced, never again once followed (kept in
## main's player memory), the starving tip once a run. The tests use their own settings file and
## never save it.

const FakeEvents := preload("res://tests/fakes/fake_world_events.gd")
const FakeGrowthEvents := preload("res://tests/fakes/fake_growth_events.gd")
const FakeGrowth := FakeGrowthEvents.FakeGrowth
const HUD_SCENE := preload("res://game/ui/hud.tscn")
const SETTINGS_PATH := "user://test_growth_hud/settings.cfg"
const MEMORY_DIR := "user://test_growth_hud/run"

var _settings: SettingsService
var _device := ""
var _config: WorldConfig
var _top := 0


## Records cues instead of playing them, so none is dropped by the repeat limit.
class CueLog extends CellAudio:
	var cues: PackedStringArray = []

	func play(cue: String) -> void:
		cues.append(cue)

	func play_at(cue: String, _at: Vector3) -> void:
		cues.append(cue)


func before_each() -> void:
	_settings = SettingsService.new(SETTINGS_PATH)
	SettingsService.set_shared(_settings)
	_device = InputPrompts.device
	InputPrompts.device = "keys"


func after_each() -> void:
	if _config != null:
		_config.max_size_in_build = _top
		_config = null
	_settings.reset_bindings()
	SettingsService.set_shared(null)
	InputPrompts.device = _device


func test_state_of_table() -> void:
	check_eq(GrowthHud.state_of(null, 1, 2), "none", "no growth")
	var g := FakeGrowth.new()
	g.meter = 45.0
	check_eq(GrowthHud.state_of(g, 1, 2), "filling", "half full")
	g.fill(1)
	check_eq(GrowthHud.state_of(g, 1, 2), "filling", "full in auto, waiting for its window: plain")
	g.calm_ticks = 12
	check_eq(GrowthHud.state_of(g, 1, 2), "growing", "full and calm in auto")
	g.trigger = "press"
	check_eq(GrowthHud.state_of(g, 1, 2), "ready", "press mode, G not pressed: ready, never growing")
	g.armed = true
	check_eq(GrowthHud.state_of(g, 1, 2), "growing", "press mode once G is pressed")
	g.calm_ticks = 0
	g.blocker = "hunted"
	check_eq(GrowthHud.state_of(g, 1, 2), "blocked", "something is hunting the cell")
	g.trigger = "auto"
	g.armed = false
	g.blocker = "wedged"
	check_eq(GrowthHud.state_of(g, 1, 2), "blocked", "wedged in auto")
	g.blocker = ""
	g.fill(2)
	check_eq(GrowthHud.state_of(g, 2, 2), "top", "full at the build's top")
	g.meter = 60.0
	check_eq(GrowthHud.state_of(g, 2, 2), "filling", "filling at the top")
	check_near(GrowthHud.share_of(g, 2), 0.5, 1e-9, "60 of the 120 ring at size 2")
	g.meter = 500.0
	check_near(GrowthHud.share_of(g, 1), 1.0, 1e-9, "never past full")
	check_near(GrowthHud.share_of(g, 10), 0.0, 1e-9, "no ring past size 9")
	check_near(GrowthHud.share_of(null, 1), 0.0, 1e-9, "no growth")


func test_growth_line_shows_hint_verbatim() -> void:
	var g := FakeGrowth.new()
	var pool := FakeGrowthEvents.open_pool(FakeEvents.endless_session(), g)
	_grow_to_2(pool)
	var hud := _hud(pool)
	check_eq(Hud.grow_key_name(), "G", "grow is bound to G")
	for line in FakeGrowthEvents.HINTS:
		g.show_line(line)
		check_eq(g.hint(), line, "the fake words '%s'" % line)
		hud.update_growth()
		check_eq(hud.growth_line.text, line, "the line is the hint as it is (ring %s)" % hud.meter_ring.state)
		check(hud.growth_line.visible == (line != ""), "'%s' %s" % [line, "shows" if line != "" else "hides the line"])
		check(hud.growth_row.visible, "the ring and badge show with growth")
	check_eq(GrowthHud.hint_of(null), "", "no growth, no line")
	check_eq(GrowthHud.hint_of(RefCounted.new()), "", "a Growth that does not word its hint yet: no line")
	# The player rebinds grow: the line names the new key, the rest of it unchanged (BP-19).
	_settings.rebind("grow", "key:%d" % KEY_H)
	g.show_line("Ready to grow (G)")
	hud.update_growth()
	check_eq(hud.growth_line.text, "Ready to grow (H)", "the bound key, not a literal G")
	check_eq(GrowthHud.with_grow_key("Growing…", "H"), "Growing…", "a line without (G) is left alone")
	check_eq(GrowthHud.with_grow_key("Ready to grow (G)", ""), "Ready to grow (G)", "no binding: as worded")
	hud.free()
	pool.free()


func test_badge_and_message() -> void:
	var labels := FakeGrowthEvents.LABELS
	check_eq(GrowthHud.badge_text(1, labels), "Size 1 · about 20 µm", "size 1")
	check_eq(GrowthHud.badge_text(2, labels), "Size 2 · about 32 µm", "size 2")
	check_eq(GrowthHud.badge_text(3, []), "Size 3", "no label for that size")
	var g := FakeGrowth.new()
	var pool := FakeGrowthEvents.open_pool(FakeEvents.endless_session(FakeEvents.SEED, PackedFloat64Array(), true), g)
	var hud := _hud(pool)
	var ladder: Variant = pool.session.world.config.get(&"ladder")
	var shown: Array = ladder.get("labels", []) if ladder is Dictionary else []
	check_eq(hud.size_badge.text, GrowthHud.badge_text(pool.shown_size(), shown), "the badge names the size shown")
	check_eq(hud.meter_ring.size_n, pool.shown_size(), "and so does the ring")
	# Through a growth the HUD keeps the old size and a full ring until the beat's chord at 1.9 s
	# (V-7), then shows the new size's message, badge and ring at once.
	# The sim's own growth tick runs (T2.5): its ring is made due, and the next frame grows the world
	# to size 2 and sends growth_began and grew; the HUD's fake reads full, then empty once paid.
	_grow_to_2(pool)
	g.fill(1)
	var real := pool.sim.growth
	real.meter = real.ring(1)
	real.full_since = pool.sim.tick
	real.due = true
	FakeEvents.frame(pool)
	check_eq(pool.sim.size(), 2, "the tick grew the world")
	check(pool.growth_beat.running(), "and the beat runs")
	g.meter = 0.0
	g.full_since = -1
	var size_2 := GrowthHud.badge_text(2, shown)
	while true:
		FakeEvents.frame(pool)
		hud._process(FakeEvents.DT)
		if pool.growth_beat.t() >= GrowthBeat.CHORD_S:
			break
		check(not (hud.message.visible and hud.message_text.text == size_2), "no size message before 1.9 s (%.2f s)" % pool.growth_beat.t())
		check_eq(hud.size_badge.text, GrowthHud.badge_text(1, shown), "the badge names size 1 until the chord")
		check_near(hud.meter_ring.shown_share(), 1.0, 1e-9, "the ring reads full until the chord")
	check(hud.message.visible and hud.message_text.text == size_2, "the chord: \"%s\"" % hud.message_text.text)
	check_eq(hud.size_badge.text, size_2, "the badge names size 2")
	check_eq(hud.meter_ring.size_n, 2, "the ring's numeral too")
	check_near(hud.meter_ring.shown_share(), 0.0, 1e-9, "and the ring is empty")
	hud.free()
	pool.free()


func test_meter_ring_states_look() -> void:
	var ring := MeterRing.new()
	ring.show_ring(0.25, 1, "filling")
	check_near(ring.shown_share(), 0.25, 1e-9, "the meter's share")
	check(not ring.outlined(), "filling has no outline")
	ring.show_ring(1.0, 1, "growing")
	ring._process(1.0 / (2.0 * MeterRing.PULSE_HZ))
	check_near(ring.pulse_scale(), 1.0 + MeterRing.PULSE_GROW, 1e-6, "growing pulses to 1.06 half a period in")
	check(ring.scale.is_equal_approx(Vector2.ONE * ring.pulse_scale()), "the ring is drawn at the pulse")
	ring.reduce_flashing = true
	check_near(ring.pulse_scale(), 1.0, 1e-9, "no pulse under reduce flashing")
	ring.reduce_flashing = false
	ring.show_ring(1.0, 1, "blocked")
	check(ring.outlined() and is_equal_approx(ring.pulse_scale(), 1.0), "blocked: outlined, still")
	ring.show_ring(1.0, 1, "ready")
	check(ring.outlined(), "ready: outlined")
	ring.show_ring(0.0, 2, "filling")
	ring.sweep()
	check_near(ring.shown_share(), 1.0, 1e-9, "a payout sweeps from full")
	ring._process(MeterRing.SWEEP_S * 0.5)
	check_near(ring.shown_share(), 0.5, 1e-6, "halfway down after 0.3 s")
	ring._process(MeterRing.SWEEP_S)
	check_near(ring.shown_share(), 0.0, 1e-9, "then the meter's own share")
	ring.flash()
	check_near(ring.glow(), 1.0, 1e-9, "a flash lights the glow")
	ring._process(MeterRing.FLASH_S)
	check_near(ring.glow(), 0.0, 1e-9, "for 0.6 s")
	ring.free()


func test_ring_paid_toast_and_earned_ring() -> void:
	check_eq(GrowthHud.ring_paid_text(10), "Ring full: energy refilled · +10 points", "the payout's words")
	check_eq(GrowthHud.ring_paid_text(1), "Ring full: energy refilled · +1 point", "one point")
	var g := FakeGrowth.new()
	var pool := FakeGrowthEvents.open_pool(FakeEvents.endless_session(), g)
	var cues := CueLog.new()
	pool.audio = cues
	var hud := _hud(pool)
	var before := hud.toast_texts().size()
	for e in FakeGrowthEvents.ring_paid(10):
		hud._on_sim_event(e)
	var texts := hud.toast_texts()
	check_eq(texts.size(), before + 1, "one toast for the payout")
	check_eq(texts[texts.size() - 1], "Ring full: energy refilled · +10 points", "the payout's toast")
	for t in texts:
		check(not "survived" in t, "no survival toast for the ring: %s" % t)
	check_eq(hud.points_flash.text, "+10", "the points still flash")
	check_near(hud.meter_ring.shown_share(), 1.0, 1e-9, "the ring sweeps down from full")
	check_eq(Array(cues.cues), ["growth_ring"], "the ring's sound")
	hud._on_sim_event({"type": "earned", "points": 1})
	check(hud.toast_texts()[hud.toast_texts().size() - 1].contains("survived"), "survival points keep their toast")
	hud._on_sim_event(FakeGrowthEvents.ring_full(1, 90.0))
	hud._on_sim_event(FakeGrowthEvents.waiting("hunted"))
	check_eq(Array(cues.cues), ["growth_ring", "growth_ring", "refuse"], "a full ring pings; a press that must wait is refused")
	hud.meter_ring._process(MeterRing.FLASH_S)
	hud._on_sim_event(FakeGrowthEvents.lump("threat_kill", 13.5, "c1"))
	check_near(hud.meter_ring.glow(), 1.0, 1e-9, "a lump flashes the ring")
	hud.meter_ring._process(MeterRing.FLASH_S)
	hud._on_sim_event(FakeGrowthEvents.discovered("place", "giant_husk"))
	check_near(hud.meter_ring.glow(), 1.0, 1e-9, "and so does a find")
	hud.free()
	pool.free()
	cues.free()


func test_grow_warning_sounds_when_growing_at_most_every_3_s() -> void:
	var g := FakeGrowth.new().fill(1)
	var pool := FakeGrowthEvents.open_pool(FakeEvents.endless_session(), g)
	var cues := CueLog.new()
	pool.audio = cues
	_grow_to_2(pool)
	var hud := _hud(pool)
	var sim := pool.sim
	sim.tick = 600
	hud.update_growth()
	check_eq(cues.cues.size(), 0, "full and waiting: silent")
	g.calm_ticks = 1
	hud.update_growth()
	hud.update_growth()
	check_eq(Array(cues.cues), ["grow_warn"], "once when the ring starts growing")
	g.calm_ticks = 0
	hud.update_growth()
	sim.tick += 60
	g.calm_ticks = 1
	hud.update_growth()
	check_eq(cues.cues.size(), 1, "not again a second later")
	g.calm_ticks = 0
	hud.update_growth()
	sim.tick += 120
	g.calm_ticks = 1
	hud.update_growth()
	check_eq(cues.cues.size(), 2, "again 3 s after the last")
	hud.free()
	pool.free()
	cues.free()


func test_grow_press_is_one_tick() -> void:
	var g := FakeGrowth.new().fill(1)
	g.trigger = "press"
	var pool := FakeGrowthEvents.open_pool(FakeEvents.endless_session(), g)
	check(pool.intent_provider == pool.swim_input, "the player swims")
	FakeEvents.frame(pool)
	check_eq(_presses(pool, 5), 1, "a G held five frames is one press, on one tick")
	check_eq(_presses(pool, 0), 0, "and none after it")
	pool.free()
	var bot := FakeGrowthEvents.open_pool(FakeEvents.endless_session(), g, FakeEvents.Still.new())
	FakeEvents.frame(bot)
	check_eq(_presses(bot, 5), 0, "a bot's intent never gets the player's press")
	bot.free()


func test_trigger_sent_on_start_and_change() -> void:
	check(_settings.set_value("gameplay/growth_trigger", "press"), "the player chose press")
	var g := FakeGrowth.new()
	var pool := FakeGrowthEvents.open_pool(FakeEvents.endless_session(), g)
	FakeEvents.frame(pool)
	check_eq(pool.sent_trigger, "press", "the first tick carries the setting")
	check_eq(pool.sim.intent_trigger, "press", "and the sim reads it (SimIntent.trigger)")
	FakeEvents.frame(pool)
	check_eq(pool.sent_trigger, "", "once")
	check_eq(pool.sim.intent_trigger, "", "the sim too")
	check(_settings.set_value("gameplay/growth_trigger", "auto"), "the player switches to auto")
	FakeEvents.frame(pool)
	check_eq(pool.sent_trigger, "auto", "the next tick carries the change")
	FakeEvents.frame(pool)
	check_eq(pool.sent_trigger, "", "once")
	check(not pool.reduce_motion, "reduce camera motion is off")
	_settings.set_value("accessibility/reduce_camera_motion", true)
	check(pool.reduce_motion, "the pool follows it")
	pool.free()
	var bot := FakeGrowthEvents.open_pool(FakeEvents.endless_session(), g, FakeEvents.Still.new())
	FakeEvents.frame(bot)
	check_eq(bot.sent_trigger, "auto", "a bot's run gets the setting too")
	check(bot.reduce_motion, "and reduce motion, read at the start")
	bot.free()


func test_pool_mode_hides_growth_ui() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.pool_session(), null)
	check(pool.growth() == null, "the M1 pool has no growth")
	var hud := _hud(pool)
	FakeEvents.frame(pool)
	hud._process(1.0 / 60.0)
	check(not hud.growth_row.visible, "no ring or badge")
	check(not hud.growth_line.visible, "no growth line")
	hud.ladder_strip.refresh()
	check(not hud.ladder_strip.visible, "no ladder strip")
	# A meal that would offer "Eating well makes you grow" in the sea offers nothing here.
	hud.idea_hints.on_event({"type": "ate"}, {}, {"size": 1, "meter_share": 0.5})
	hud._process(1.0 / 60.0)
	check(not hud.idea_hint.visible, "no idea hints")
	check_eq(pool.sent_trigger, "", "no trigger goes out")
	var press := InputEventKey.new()
	press.physical_keycode = KEY_G
	press.pressed = true
	pool._unhandled_input(press)
	FakeEvents.frame(pool)
	check(not pool.sent_grow, "a press goes nowhere")
	hud.free()
	pool.free()
	var sea := FakeGrowthEvents.open_pool(FakeEvents.endless_session(), FakeGrowth.new())
	var sea_hud := _hud(sea)
	check(sea_hud.growth_row.visible, "the sea's HUD shows the ring")
	check(sea_hud.ladder_strip.visible, "and the ladder strip")
	sea_hud.free()
	sea.free()


func test_player_memory_lives_beside_a_named_slot() -> void:
	var main := Main.new()
	main.flags = RunFlags.from_args(PackedStringArray())
	check_eq(main.player_memory_path(), UserSettings.PATH, "the player's own by default")
	main.flags = RunFlags.from_args(PackedStringArray(["--slot=%s/slot.json" % MEMORY_DIR]))
	var path := main.player_memory_path()
	check_eq(path, MEMORY_DIR + "/player_memory.cfg", "beside a named slot")
	DirAccess.remove_absolute(path)
	main.player_memory = UserSettings.new()
	main.player_memory.hints_followed = PackedStringArray(["eat_to_grow"])
	main.memory_writable = false
	check_eq(main.save_player_memory(), ERR_SKIP, "a tool holds it")
	check(not FileAccess.file_exists(path), "nothing written")
	main.memory_writable = true
	main.flags.perf_tour = true
	check_eq(main.save_player_memory(), ERR_SKIP, "the perf tour never writes it")
	check(not FileAccess.file_exists(path), "nothing written")
	main.flags.perf_tour = false
	check_eq(main.save_player_memory(), OK, "written")
	check_eq(UserSettings.load_from(path).hints_followed, PackedStringArray(["eat_to_grow"]), "and read back")
	DirAccess.remove_absolute(path)
	main.free()


## The phrase table, and the preview line: the first two phrases by kind (flee, appear, ignore,
## morsels, haze), then entry order; at the build's top the later build's promise.
func test_ladder_phrases() -> void:
	var table := [["threat", "rival", "rammers ignore you"], ["threat", "prey", "rammers flee from you"],
		["rival", "prey", "rammers flee from you"], ["rival", "morsel", "rammers become morsels"],
		["prey", "morsel", "rammers become morsels"], ["ghost", "threat", "rammers appear"],
		["prey", "haze", "rammers fade to haze"], ["morsel", "haze", "rammers fade to haze"],
		["rival", "rival", ""], ["prey", "prey", ""], ["ghost", "ghost", ""], ["rival", "threat", ""],
		["prey", "rival", ""], ["ghost", "prey", "rammers flee from you"]]
	for row: Array in table:
		check_eq(LadderStrip.phrase("rammers", row[0], row[1]), row[2], "%s -> %s" % [row[0], row[1]])
	var ladder: Dictionary = GhostLayer.shipped().data
	var catalog := SpeciesCatalog.load_from()
	var ghosts := GhostLayer.new()
	ghosts.configure(ladder, 1, 7)
	var entries := LadderStrip.entries_for(PackedStringArray(["rammer", "ambush_hunter"]), ghosts.near_species(1), 1, catalog, ladder)
	ghosts.free()
	check_eq(entries.map(func(e: Dictionary) -> String: return e.id), ["rammer", "ambush_hunter", "lurker", "elder_rammer", "veil", "warden"],
		"the live species first, then the ghosts to come, at most six")
	check_eq(entries.map(func(e: Dictionary) -> String: return "%s>%s" % [e.role, e.next_role]),
		["threat>prey", "threat>rival", "ghost>threat", "ghost>threat", "ghost>ghost", "ghost>ghost"], "their roles now and after the growth")
	check_eq(LadderStrip.preview_line(entries, false, 1, ladder), "After your next growth: rammers flee from you; Lurkers appear",
		"near a rammer and an ambush hunter at size 1 (s2-view 7.4)")
	var reversed := entries.duplicate()
	reversed.reverse()
	check_eq(LadderStrip.preview_line(reversed, false, 1, ladder), "After your next growth: rammers flee from you; elder rammers appear",
		"fleeing comes first whatever the entry order, then the first to appear")
	check_eq(LadderStrip.preview_line(entries.slice(2), false, 1, ladder), "After your next growth: Lurkers appear; elder rammers appear",
		"a tie keeps entry order")
	check_eq(LadderStrip.preview_line(entries, true, 2, ladder), "Coming in a later build: the stinger veil", "at the build's top")
	check_eq(LadderStrip.preview_line(entries, true, 1, ladder), "", "no promise for that size: no line")
	check_eq(LadderStrip.preview_line(entries.slice(4), false, 1, ladder), "", "nothing changes: no line")
	check_eq(LadderStrip.entries_for(PackedStringArray(["rammer", "rammer"]), PackedStringArray(["rammer"]), 1, catalog, ladder).size(), 1,
		"each species once")
	# The HUD's strip on the sea draws what entries_for and preview_line say.
	var pool := FakeGrowthEvents.open_pool(FakeEvents.endless_session(), FakeGrowth.new())
	_grow_to_2(pool)
	var hud := _hud(pool)
	var strip := hud.ladder_strip
	strip.refresh()
	var shown := strip.entries()
	check(not shown.is_empty() and shown.slice(shown.size() - 2).all(func(e: Dictionary) -> bool: return e.role == "ghost"),
		"the strip ends with the ghosts to come")
	check_eq(strip.preview_text(), LadderStrip.preview_line(shown, false, 1, ladder), "and shows their preview line")
	check(strip.preview_text().begins_with(LadderStrip.PREVIEW_PREFIX), "\"%s\"" % strip.preview_text())
	hud.free()
	pool.free()


## Each icon's tint by role (ink for a threat, the rim's green for prey only with a jaw, neutral for
## rivals and haze, a ghost faint over its own sprite), and a caption under every icon.
func test_ladder_icons_by_role() -> void:
	check_eq(LadderStrip.INK.to_html(false), "d9466b", "ink is the threat colour")
	check_eq(LadderStrip.RIM.to_html(false), "cfe86a", "rim is the rim's green")
	check_eq(LadderStrip.NEUTRAL.to_html(false), "9aa0b4", "neutral is the crest's grey")
	check_eq(LadderStrip.tint_of("threat", true), LadderStrip.INK, "a threat in ink")
	check_eq(LadderStrip.tint_of("threat", false), LadderStrip.INK, "with or without a jaw")
	check_eq(LadderStrip.tint_of("prey", true), LadderStrip.RIM, "prey rimmed for a jaw")
	check_eq(LadderStrip.tint_of("prey", false), LadderStrip.NEUTRAL, "prey neutral without one")
	check_eq(LadderStrip.tint_of("morsel", true), LadderStrip.RIM, "a morsel rimmed for a jaw")
	check_eq(LadderStrip.tint_of("morsel", false), LadderStrip.NEUTRAL, "a morsel neutral without one")
	check_eq(LadderStrip.tint_of("rival", true), LadderStrip.NEUTRAL, "a rival neutral")
	check_eq(LadderStrip.tint_of("haze", true), LadderStrip.NEUTRAL, "haze neutral")
	check_eq(LadderStrip.tint_of("ghost", true), Color(1.0, 1.0, 1.0, 0.5), "a ghost faint")
	var ladder: Dictionary = GhostLayer.shipped().data
	var catalog := SpeciesCatalog.load_from()
	# At size 2: the rammer is prey, the ambush hunter a rival, the Lurker a threat, the veil to come.
	var entries := LadderStrip.entries_for(PackedStringArray(["rammer", "ambush_hunter", "lurker", "veil"]), PackedStringArray(), 2, catalog, ladder)
	check_eq(entries.map(func(e: Dictionary) -> String: return e.role), ["prey", "rival", "threat", "ghost"], "the roles at size 2")
	var strip := LadderStrip.new()
	FakeEvents.ready_tree(strip)
	for jaw in [true, false]:
		strip._show(entries, jaw, "")
		var icons := strip.icons()
		check_eq(icons.size(), 4, "an icon per entry")
		var want := [LadderStrip.RIM if jaw else LadderStrip.NEUTRAL, LadderStrip.NEUTRAL, LadderStrip.INK, Color(1.0, 1.0, 1.0, 0.5)]
		check_eq(icons.map(func(i: Dictionary) -> Color: return i.tint), want, "tinted by role (jaw %s)" % jaw)
		check_eq(icons.map(func(i: Dictionary) -> String: return i.caption), ["rammers", "ambush hunters", "Lurkers", "stinger veils"],
			"each with its plural under it")
		check(icons.all(func(i: Dictionary) -> bool: return str(i.texture) != "" and ResourceLoader.exists(str(i.texture))), "and its sprite")
		check_eq(str(icons[3].texture), str(ladder.species.veil.texture), "a ghost shows its ghost sprite")
		check_eq(str(icons[0].texture), str(GhostLayer.haze_paths(ladder).rammer), "the others their haze sprite")
	strip._show(entries.slice(0, 1), true, "")
	check_eq(strip.icons().size(), 1, "fewer entries hide the spare icons")
	strip.free()


## One idea at a time for SHOW_S, a minute between new ones, an unfollowed one back after three; a
## followed one goes at once and never comes back, in this run or the next (main's player memory); the
## starving tip once a run and never remembered.
func test_idea_hints_pacing() -> void:
	var main := Main.new()
	main.flags = RunFlags.from_args(PackedStringArray(["--slot=%s/slot.json" % MEMORY_DIR]))
	var path := main.player_memory_path()
	DirAccess.remove_absolute(path)
	main.player_memory = UserSettings.new()
	var ideas := IdeaHints.new()
	ideas.bind_memory(main.player_memory, main.save_player_memory)
	# Two moments at once: a growth 2.5 s ago with a jaw, and two minutes in the home tile.
	var ctx := {"size": 2, "has_jaw": true, "beat_t": 2.5, "in_home_tile": true, "alive_s": 130.0}
	ideas.observe(ctx)
	check_eq(ideas.step(100.0), "smaller_now", "the first waiting idea by order")
	check_eq(ideas.step(105.9), "smaller_now", "shown for 6 s")
	check_eq(ideas.step(106.0), "", "then gone")
	check_eq(ideas.step(159.9), "", "the other waits a minute from the last new one")
	check_eq(ideas.step(160.0), "sea_goes_on", "one at a time, a minute apart")
	ideas.on_event({"type": "tile_entered", "region": "home"}, {}, ctx)
	check(not ideas.is_followed("sea_goes_on"), "another home tile follows nothing")
	ideas.on_event({"type": "tile_entered", "region": "reef"}, {}, ctx)
	check(ideas.is_followed("sea_goes_on"), "leaving home follows it")
	check_eq(ideas.step(161.0), "", "a followed idea goes at once")
	check(FileAccess.file_exists(path), "saved as it is followed")
	check_eq(ideas.step(279.9), "", "an idea not followed waits three minutes from when it showed")
	check_eq(ideas.step(280.0), "smaller_now", "then comes back while its moment lasts")
	ideas.observe(ctx.merged({"near_smaller": true}))
	check_eq(main.player_memory.hints_followed, PackedStringArray(["sea_goes_on", "smaller_now", "flee_now"]),
		"coming near a smaller body follows both growth ideas")
	ideas.observe(ctx.merged({"has_jaw": false}))
	for t in [300.0, 500.0, 1000.0]:
		check_eq(ideas.step(t), "", "followed ideas never show again (%.0f s)" % t)
	check_eq(UserSettings.load_from(path).hints_followed, main.player_memory.hints_followed, "kept in the player memory's file")
	# The next run reads them back.
	var next := IdeaHints.new()
	next.bind_memory(UserSettings.load_from(path), Callable())
	next.observe(ctx)
	check_eq(next.step(0.0), "", "nor in the next run")
	# The starving tip: once a run, never remembered.
	var starving := {"size": 1, "has_jaw": true, "meat_only": true, "starving": true}
	next.observe(starving)
	check_eq(next.step(10.0), "hunt_for_meat", "a meat-only body starving")
	check_eq(IdeaHints.text_of("hunt_for_meat"), "Hunt rammers from behind for meat", "in the balance lab's words")
	check_eq(next.step(400.0), "", "once a run, though it starves still")
	next.follow("hunt_for_meat")
	check(not next.memory.hints_followed.has("hunt_for_meat"), "never remembered")
	var third := IdeaHints.new()
	third.bind_memory(UserSettings.load_from(path), Callable())
	third.observe(starving)
	check_eq(third.step(0.0), "hunt_for_meat", "a new run offers it again")
	# Eating well: the first meal a tenth into the ring at size 1, followed when the ring fills.
	var meals := IdeaHints.new()
	meals.on_event({"type": "ate"}, {}, {"size": 1, "meter_share": 0.09})
	meals.on_event({"type": "ate"}, {}, {"size": 2, "meter_share": 0.5})
	check_eq(meals.step(0.0), "", "not under a tenth, nor at size 2")
	meals.on_event({"type": "ate"}, {}, {"size": 1, "meter_share": 0.1})
	check_eq(meals.step(1.0), "eat_to_grow", "a tenth at size 1")
	meals.on_event({"type": "ring_full"}, {}, {})
	check_eq(meals.step(2.0), "", "the ring filled: followed, for this run with no memory")
	check_eq(meals.step(500.0), "", "and never again")
	# Green rim: from 8 s after a growth with a rimmed body in view; followed by eating one.
	var rims := IdeaHints.new()
	rims.observe({"has_jaw": true, "beat_t": 7.9, "rimmed_in_view": true, "near_smaller": true})
	check_eq(rims.step(0.0), "", "not before 8 s")
	rims.observe({"has_jaw": true, "beat_t": 8.0, "rimmed_in_view": true, "near_smaller": true})
	check_eq(rims.step(1.0), "green_rim", "8 s on")
	rims.on_event({"type": "ate"}, {"rimmed": true}, {"size": 2})
	check(rims.is_followed("green_rim"), "eating a rimmed morsel follows it")
	# The HUD: the idea in %IdeaHint, gone when followed; followed ideas saved through main.
	DirAccess.remove_absolute(path)
	main.player_memory = UserSettings.new()
	var pool := FakeGrowthEvents.open_pool(FakeEvents.endless_session(), FakeGrowth.new())
	var hud := _hud(pool, main.player_memory, main.save_player_memory)
	hud.idea_hints.on_event({"type": "ate"}, {}, {"size": 1, "meter_share": 0.5})
	hud._process(1.0 / 60.0)
	check(hud.idea_hint.visible and hud.idea_hint_text.text == "Eating well makes you grow", "the HUD shows the idea")
	hud._on_sim_event(FakeGrowthEvents.ring_full(1, 100.0))
	hud._process(1.0 / 60.0)
	check(not hud.idea_hint.visible, "and drops it once followed")
	check_eq(UserSettings.load_from(path).hints_followed, PackedStringArray(["eat_to_grow"]), "saved through main's player memory")
	DirAccess.remove_absolute(path)
	hud.free()
	pool.free()
	main.free()


## What the pool tells the idea hints (PoolScene.hint_context, hint_facts): the body, the ring's share,
## the home tile, a smaller body near and a rimmed one in view, and the time since the last growth.
func test_the_pool_reads_the_idea_context() -> void:
	var g := FakeGrowth.new()
	var pool := FakeGrowthEvents.open_pool(FakeEvents.endless_session(FakeEvents.SEED, PackedFloat64Array(), true), g)
	var sim := pool.sim
	sim.debug_set_ai_frozen(true)
	g.meter = g.ring(1) * 0.5
	var ctx := pool.hint_context()
	var keys := ctx.keys()
	keys.sort()
	check_eq(keys, ["alive_s", "beat_t", "has_jaw", "in_home_tile", "meat_only", "meter_share", "near_smaller", "rimmed_in_view",
		"size", "starving", "veil_in_view"], "the context's keys (s2-view 7.5, s3-view 11)")
	var p := sim.phenotype
	check_eq([ctx.size, ctx.has_jaw, ctx.meat_only, ctx.starving], [1, p.can_eat("meat"), p.diets == PackedStringArray(["meat"]), false],
		"the size and the body")
	check_near(float(ctx.meter_share), 0.5, 1e-9, "the ring's share")
	var region := str(sim.world.gen.tile_info(WorldConfig.band_of(sim.world.size), sim.world.tile_of_local(sim.motion.position).x,
		sim.world.tile_of_local(sim.motion.position).y).get("region", ""))
	check_eq(ctx.in_home_tile, region == "home", "in the home tile as the generator says (%s)" % region)
	check_eq(ctx.beat_t, -1.0, "no growth yet")
	check(not ctx.near_smaller, "nothing smaller near")
	check(sim.debug_set_size(2), "size 2, where a rammer is smaller")
	FakeEvents.frame(pool)
	var c := sim.motion.position
	var gap := 1.0
	check(sim.debug_spawn_creature("rammer", c + Vector2(p.radius + 0.6 + gap, 0.0), 0.0), "a rammer close by")
	FakeEvents.frame(pool)
	var rammer: CreatureField.Creature = sim.creatures.creatures[sim.creatures.creatures.size() - 1]
	var view := pool.creature_layer.view_of(rammer.id)
	check(view != null and view.view_q < 1.0, "drawn smaller than the cell")
	ctx = pool.hint_context()
	check(ctx.near_smaller, "a smaller body within 2 tm of the cell's surface")
	check_eq(ctx.rimmed_in_view, p.can_eat("meat"), "rimmed in view exactly when the cell has a jaw")
	var facts := pool.hint_facts({"type": "hit", "target": rammer.id, "attacker": CreatureField.PLAYER_ID})
	check_eq(facts, {"smaller": true, "rimmed": p.can_eat("meat")}, "a hit on it: smaller, rimmed with a jaw")
	check_eq(pool.hint_facts({"type": "hit", "target": "nobody"}), {"smaller": false, "rimmed": false}, "an unknown body: neither")
	sim.motion.place(c + Vector2(-40.0, 0.0), 0.0)
	FakeEvents.frame(pool)
	check(not pool.hint_context().near_smaller, "not when it is far")
	var t0 := sim.now()
	pool._route(FakeGrowthEvents.began(sim.motion.position, 2, 3))
	for i in 30:
		FakeEvents.frame(pool)
	check_near(float(pool.hint_context().beat_t), sim.now() - t0, 1e-9, "the time since the growth began")
	pool.free()


## Presses G once and holds it `frames` frames (echo events after the first), one tick each; the
## number of ticks whose intent carried the press.
func _presses(pool: PoolScene, frames: int) -> int:
	var count := 0
	for i in frames:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_G
		key.pressed = true
		key.echo = i > 0
		pool._unhandled_input(key)
		FakeEvents.frame(pool)
		count += _sent_grow(pool)
	if frames == 0:
		for i in 3:
			FakeEvents.frame(pool)
			count += _sent_grow(pool)
	return count


## 1 when the last tick's intent carried the press, as the sim read it (SimIntent.grow, T2.1).
func _sent_grow(pool: PoolScene) -> int:
	check_eq(pool.sim.intent_grow, pool.sent_grow, "the sim reads the press the pool sent")
	return 1 if pool.sim.intent_grow else 0


## The fixture world tops out at size 1, where a full ring pays out at once; this makes it grow to
## size 2 until the test ends, so a full ring waits, grows or is blocked.
func _grow_to_2(pool: PoolScene) -> void:
	_config = pool.session.world.config
	_top = _config.max_size_in_build
	_config.max_size_in_build = 2


## The HUD bound to `pool` outside the tree, as test_world_hud binds it (the threat arrows bind
## with the camera hidden from them); given a player memory, it is bound first, as main binds it.
func _hud(pool: PoolScene, memory: UserSettings = null, save := Callable()) -> Hud:
	var hud: Hud = HUD_SCENE.instantiate()
	FakeEvents.ready_tree(hud)
	if memory != null:
		hud.bind_memory(memory, save)
	var camera := pool.camera
	pool.camera = null
	hud.bind(pool)
	pool.camera = camera
	return hud


# --- S3 (s3-view 11; S3G27 HUD) ---

## The places line (D-133) reads the size shown: the old size's count through a beat until its chord.
func test_places_text() -> void:
	check_eq(GrowthHud.places_text(3, 10), "Places found at this size: 3 of 10", "the words (D-116)")
	var g := FakeGrowth.new()
	g.places = {1: Vector2i(1, 6), 2: Vector2i(0, 4)}
	var pool := FakeGrowthEvents.open_pool(FakeEvents.endless_session(FakeEvents.SEED, PackedFloat64Array(), true), g)
	var hud := _hud(pool)
	check(hud.places_line.visible, "shown in the growing sea")
	check_eq(hud.places_line.text, "Places found at this size: 1 of 6", "size 1's count")
	_grow_to_2(pool)
	g.fill(1)
	var real := pool.sim.growth
	real.meter = real.ring(1)
	real.full_since = pool.sim.tick
	real.due = true
	FakeEvents.frame(pool)
	check(pool.growth_beat.running(), "a growth beat runs")
	while pool.growth_beat.t() < GrowthBeat.CHORD_S:
		hud.refresh()
		check_eq(hud.places_line.text, "Places found at this size: 1 of 6", "%.2f s: still size 1's count" % pool.growth_beat.t())
		FakeEvents.frame(pool)
		hud._process(FakeEvents.DT)
	hud.refresh()
	check_eq(hud.places_line.text, "Places found at this size: 0 of 4", "size 2's count from the chord")
	hud.free()
	pool.free()
	var m1 := FakeGrowthEvents.open_pool(FakeEvents.pool_session(), null)
	var hud1 := _hud(m1)
	check(not hud1.places_line.visible, "no places line in the M1 pool")
	hud1.free()
	m1.free()


## V3-18: a hazard that stops being a threat stops stinging; a hunter still ignores you.
func test_hazard_phrase() -> void:
	check_eq(LadderStrip.phrase("stinger veils", "threat", "rival", "hazard"), "stinger veils stop stinging", "the veil")
	check_eq(LadderStrip.phrase("rammers", "threat", "rival"), "rammers ignore you", "a hunter")
	check_eq(LadderStrip.phrase("stinger veils", "threat", "prey", "hazard"), "stinger veils flee from you", "other changes as before")
	var catalog := SpeciesCatalog.load_from()
	var ladder: Dictionary = GhostLayer.shipped().data
	var entries := LadderStrip.entries_for(PackedStringArray(["veil"]), PackedStringArray(), 3, catalog, ladder)
	check_eq(entries[0].get("behavior"), "hazard", "entries carry the species' behaviour")
	check_eq([entries[0].role, entries[0].next_role], ["threat", "rival"], "the veil stings at 3, not at 4")
	check_eq(LadderStrip.preview_line(entries, false, 3, ladder), LadderStrip.PREVIEW_PREFIX + "stinger veils stop stinging",
		"the preview at 3 words the veil so")
	# The line shows MAX_PHRASES phrases in PHRASE_ORDER: "stop" after "ignore", before "morsels".
	var veil := {"role": "threat", "next_role": "rival", "plural": "stinger veils", "behavior": "hazard"}
	var rammers := {"role": "threat", "next_role": "rival", "plural": "rammers", "behavior": "ram"}
	var grazers := {"role": "prey", "next_role": "morsel", "plural": "grazers", "behavior": ""}
	check_eq(LadderStrip.preview_line([veil, rammers] as Array[Dictionary], false, 2, ladder),
		LadderStrip.PREVIEW_PREFIX + "rammers ignore you; stinger veils stop stinging", "after ignore")
	check_eq(LadderStrip.preview_line([grazers, veil] as Array[Dictionary], false, 2, ladder),
		LadderStrip.PREVIEW_PREFIX + "stinger veils stop stinging; grazers become morsels", "before morsels")


## V3-15 (S3G41 HUD): at the top of this build, size 4, the preview names the engulfer.
func test_preview_at_four() -> void:
	var ladder: Dictionary = GhostLayer.shipped().data
	check_eq(LadderStrip.preview_line([] as Array[Dictionary], true, 4, ladder), "Coming in a later build: the engulfer", "at size 4")


## V3-19: the veil hint shows with a veil that can sting in view, and is followed 10 s after it showed
## when a veil was in view since and nothing stung the cell; followed, it never shows again.
func test_veil_hint() -> void:
	check_eq(IdeaHints.text_of("veil_threads"), "Threads sting: swim around them", "the words (D-116)")
	var veil := {"veil_in_view": true}
	var ideas := IdeaHints.new()
	ideas.observe({})
	check_eq(ideas.step(0.0), "", "no veil, no hint")
	ideas.observe(veil)
	check_eq(ideas.step(1.0), "veil_threads", "a veil in view")
	ideas.observe(veil)
	ideas.on_event({"type": "hit", "target": "c7", "attacker": CreatureField.PLAYER_ID, "kind": "sting"}, {}, veil)
	ideas.on_event({"type": "hit", "target": CreatureField.PLAYER_ID, "attacker": "c7", "kind": "bite"}, {}, veil)
	check_eq(ideas.step(10.9), "", "gone after 6 s")
	check(not ideas.is_followed("veil_threads"), "not followed before 10 s")
	ideas.step(11.0)
	check(ideas.is_followed("veil_threads"), "10 s past it without a sting: followed")
	for t in [200.0, 400.0, 1000.0]:
		ideas.observe(veil)
		check_eq(ideas.step(t), "", "never again (%.0f s)" % t)
	# A sting since it showed: not followed, and it comes back after REPEAT_S.
	var stung := IdeaHints.new()
	stung.observe(veil)
	check_eq(stung.step(0.0), "veil_threads", "shown")
	stung.observe(veil)
	stung.on_event({"type": "hit", "target": CreatureField.PLAYER_ID, "attacker": "c7", "kind": "sting"}, {}, veil)
	stung.step(20.0)
	check(not stung.is_followed("veil_threads"), "stung since it showed: not followed")
	stung.observe(veil)
	check_eq(stung.step(IdeaHints.REPEAT_S), "veil_threads", "back after three minutes")
	stung.observe(veil)
	stung.step(IdeaHints.REPEAT_S + IdeaHints.VEIL_FOLLOW_S)
	check(stung.is_followed("veil_threads"), "then passed without a sting: followed")
	# No veil in view after it showed: not followed.
	var lost := IdeaHints.new()
	lost.observe(veil)
	check_eq(lost.step(0.0), "veil_threads", "shown")
	lost.observe({})
	lost.step(30.0)
	check(not lost.is_followed("veil_threads"), "the veil went out of view at once: not followed")
	# The pool: a veil at size 3 is in view and can sting; none at size 1.
	var pool := FakeEvents.open_pool(FakeEvents.shipped_session_at_top(4))
	var sim := pool.sim
	sim.debug_set_ai_frozen(true)
	FakeEvents.frame(pool)
	check(not pool.hint_context().veil_in_view, "no veil at size 1")
	check(sim.debug_set_size(3), "the dev's size 3")
	FakeEvents.frame(pool)
	var c := sim.motion.position
	check(sim.debug_spawn_creature("veil", c + Vector2(sim.phenotype.radius + 6.0, 0.0), 0.0), "a veil close by")
	for i in 3:
		FakeEvents.frame(pool)
	check(pool.hint_context().veil_in_view, "a veil in view at size 3")
	pool.free()
