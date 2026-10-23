extends TestCase
## The growth HUD and its inputs (S2G22, T5's part; s2-view 7.2, 7.3, 8 and 10.3): the meter ring's
## states and share, the growth line as Growth.hint() words it with the bound grow key (BP-19), the
## size badge, the payout toast at the top (C-V8), the grow press as one tick of the player's intent
## and the trigger setting sent at the start and on every change (V-16), main's player memory beside
## a named slot (C-V1), and none of it in the M1 pool (D-46). Growth is FakeGrowth until T2's lands.
## The tests use their own settings file and never save it.

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
	var pool := FakeGrowthEvents.open_pool(FakeEvents.endless_session(), g)
	var hud := _hud(pool)
	var ladder: Variant = pool.session.world.config.get(&"ladder")
	var shown: Array = ladder.get("labels", []) if ladder is Dictionary else []
	check_eq(hud.size_badge.text, GrowthHud.badge_text(pool.shown_size(), shown), "the badge names the size shown")
	check_eq(hud.meter_ring.size_n, pool.shown_size(), "and so does the ring")
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
## with the camera hidden from them).
func _hud(pool: PoolScene) -> Hud:
	var hud: Hud = HUD_SCENE.instantiate()
	FakeEvents.ready_tree(hud)
	var camera := pool.camera
	pool.camera = null
	hud.bind(pool)
	pool.camera = camera
	return hud
