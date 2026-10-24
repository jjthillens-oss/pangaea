extends Node
## Debug builds only (M1 step 2): `-- --perf-tour` lets the dev ForageBot swim a grazer for
## DURATION_S at the current window size, then writes user://reports/perf_<build>.json and quits.
## The report holds the average FPS, the 1% low, the longest frame, the GPU frame time, the
## adapter, driver, resolution and vsync. It uses its own save slot unless --slot is given, so the
## player's lineage is never touched. Main loads it by path when the flag is given.
##
## Frames are timed by the wall clock, not the process delta: the engine smooths delta and caps it
## near (max_physics_steps_per_frame + 1) physics ticks, about 150 ms, so a longer stall would read
## short and its lost time would drop out of the averages. DURATION_S and WARM_UP_S are wall time.
##
## GPU time (micro-world plan C1): the renderer times each frame of the root viewport on the GPU
## (RenderingServer.viewport_set_measure_render_time), so the look's own cost shows apart from the
## CPU and the vsync wait. Each measured frame records the latest reading, which trails the frame by
## a few frames. A renderer that measures nothing (headless) reports 0, and gpu_frames is then 0.
##
## `-- --perf-tour=swim` (S1, docs/s1/s1-content.md section 9; G18) runs the endless sea's swim route
## instead (SwimRoute, the same on every machine): hidden from the AI, refilled every REFILL_TICKS,
## SWIM_OUT_TICKS (5 min) east, a death far out (a teleport respawn: unload, rebase, load), then
## SWIM_BACK_TICKS north after the respawn. It ends when the route does and writes
## perf_swim_<build>.json with the world's streaming (rebases, chunk loads and unloads, the most
## loaded chunks, awake creatures and sleepers, the stream's counters), the most draw calls and
## primitives in a frame, the long frames (over LONG_FRAME_MS) tagged with the events within
## TAG_WINDOW_S of them, and the G18 gate (gate()). The pool (--world=pool) has no swim route.
##
## S2 (docs/s2/s2-view.md 12.2; S2G26) puts growths on the swim route's way out (SWIM_GROWTH_STEPS:
## a forced growth at 2:00, back to size 1 (at 4:00, at 3:20 from S3), a growth under reduce camera
## motion at 4:10)
## and adds `-- --perf-tour=grow` (GrowRoute, GROW_ROUTE_TICKS of a still cell, GROW_STEPS). Both
## record each growth_began with the reduce-motion setting then, report the frames within
## GROWTH_WINDOW_S of each (growth_windows()) as `growths`, and judge S2G26 (growth_gate(): no such
## frame over GROWTH_MAX_FRAME_MS) as gate.growth_pass; the printed line ends with the verdict. The
## setting is changed in the shared settings and put back, never saved.
##
## S3 (docs/s3/s3-view.md 16.1; S3G36) adds band-ups to both routes: on the swim route 2 to 3 at
## 2:30, the debug panel's Go to cradle at 2:40, 3 to 4 at 3:00, back to size 1 at 3:20 (S2's later
## steps keep their ticks) and a band-up under reduce motion at 4:35; the grow route runs
## GROW_ROUTE_TICKS (60 s) through 1 to 4 and a band-up under reduce motion. The gate gains `s3`
## (s3_gate(): every growth window within 50 ms and no frame over S3G36_MAX_DRAW_CALLS), and the
## printed line ends with its verdict too.

const DURATION_S := 90.0
const WARM_UP_S := 2.0             ## the first frames (shader warm-up, fade-in) are not measured
const SLOT := "user://reports/perf_tour_slot.json"
const REPORT_DIR := "user://reports"
const BODY := "grazer"
const SEED := 4242
const BOT_PATH := "res://game/dev/forage_bot.gd"
# The swim route (section 9).
const SWIM_OUT_TICKS := 18000      ## 5 min east
const SWIM_BACK_TICKS := 1200      ## 20 s north after the far respawn
const REFILL_TICKS := 1800         ## the energy is refilled this often
## A route prints where it is this often (wall clock), so a run stopped from outside (CI's limit on a
## software renderer) shows how far it got and at what frame rate.
const PROGRESS_EVERY_S := 10.0
## A route's watch thread speaks when the main thread has not started a frame's process step for
## this long: how long, what the main thread was doing (physics, process, the draw) and at which
## route tick, so a run that hangs (no progress lines at all) still shows where.
const WATCH_STALL_S := 10.0
const WATCH_FIRST := -2147483648   ## the tour's process_priority on a route: before every node
const WATCH_LAST := 2147483647     ## WatchTail's: after every node
const LONG_FRAME_MS := 50.0
const TAG_WINDOW_S := 0.25         ## a long frame is tagged with the events this near it, either side
const SWIM_BOT_PATH := "res://game/dev/swim_bot.gd"
# G18 on the swim route (plan :698; build plan B-20).
const G18_LOW_1PCT_MS := 8.3       ## the slowest 1% of frames average at most this...
const G18_MAX_FRAME_MS := 50.0     ## ...no frame is longer...
const G18_MAX_DRAW_CALLS := 96     ## ...no frame draws more...
const G18_GPU_OVER_M1_MS := 2.0    ## ...and the GPU's P99 is at most the M1 tour's P99 plus this
# S2's growths (s2-view 12.2; S2G26) and S3's band-ups (s3-view 16.1; S3G36). Steps are [tick from
# the route's start, action], taken in order at the first call at or after their tick: "grow" fills
# the ring and forces a growth, "size_1" and "size_2" set the size, "go_to_cradle" runs the debug
# panel's Go to cradle, "reduce_on" and "reduce_off" turn reduce camera motion on and back.
const SWIM_GROWTH_STEPS := [[7200, "grow"], [9000, "grow"], [9600, "go_to_cradle"], [10800, "grow"], [12000, "size_1"],
	[15000, "reduce_on"], [15000, "grow"], [15900, "reduce_off"],
	[16500, "size_2"], [16500, "reduce_on"], [16500, "grow"], [17100, "reduce_off"]]
const GROW_ROUTE_TICKS := 3600     ## 60 s still
const GROW_STEPS := [[300, "grow"], [900, "grow"], [1500, "grow"], [2100, "size_2"], [2400, "reduce_on"], [2400, "grow"],
	[3000, "reduce_off"]]
const S3G36_MAX_DRAW_CALLS := 104  ## S3G36: no frame of a route draws more
const REDUCE_MOTION := "accessibility/reduce_camera_motion"
const GROWTH_WINDOW_S := 2.5       ## the frames this near a growth, either side, are its window
const GROWTH_MAX_FRAME_MS := 50.0  ## S2G26: no frame in a growth's window is longer


## A route's growth steps (SWIM_GROWTH_STEPS or GROW_STEPS), taken through PoolSim's dev commands
## and `settings` (the shared settings unless given). Reduce camera motion goes back to what it was.
class GrowthSteps:
	extends RefCounted

	var steps: Array
	var settings: SettingsService
	## Runs Go to cradle (the tour sets the debug panel's run); with none the step does nothing.
	var go_to_cradle := Callable()
	var taken := 0                      ## how many steps have run
	var _reduce_before := false

	func _init(p_steps: Array, p_settings: SettingsService = null) -> void:
		steps = p_steps
		settings = p_settings if p_settings != null else SettingsService.shared()

	## Runs every step due by `t` ticks from the route's start that has not run yet, in order, and
	## prints each one ("Perf tour: step grow at route tick 300").
	func take(sim, t: int) -> void:
		while taken < steps.size() and t >= int(steps[taken][0]):
			print("Perf tour: step %s at route tick %d" % [steps[taken][1], t])
			match str(steps[taken][1]):
				"grow":
					sim.debug_fill_meter(1.0)
					sim.debug_force_growth()
				"size_1":
					sim.debug_set_size(1)
				"size_2":
					sim.debug_set_size(2)
				"go_to_cradle":
					if go_to_cradle.is_valid():
						go_to_cradle.call()
				"reduce_on":
					_reduce_before = settings.reduce_camera_motion()
					settings.set_value(REDUCE_MOTION, true)
				"reduce_off":
					settings.set_value(REDUCE_MOTION, _reduce_before)
			taken += 1


## The swim route, keyed on the sim's ticks from the first it sees, so it does not matter how often
## it is asked: hidden from the AI at once, the energy refilled every REFILL_TICKS, SWIM_OUT_TICKS
## east, then debug_hurt_player(max_health) far out; after the "respawned" event (on_event),
## SWIM_BACK_TICKS north; then done. It takes any sim with PoolSim's dev commands.
class SwimRoute:
	extends RefCounted

	var done := false
	var start_tick := -1
	var died_at_tick := -1              ## when it sent the cell to its death
	var back_from_tick := -1            ## when the cell came back
	var out_from_am := PackedFloat64Array()
	var out_to_am := PackedFloat64Array()
	var growth_steps: GrowthSteps
	var _next_refill := 0
	var _east: RefCounted
	var _north: RefCounted

	func _init(settings: SettingsService = null) -> void:
		var bot: GDScript = load(SWIM_BOT_PATH)
		_east = bot.new(Vector2.RIGHT)
		_north = bot.new(Vector2.UP)
		growth_steps = GrowthSteps.new(SWIM_GROWTH_STEPS, settings)

	func next_intent(sim) -> SimIntent:
		if start_tick < 0:
			start_tick = sim.tick
			sim.debug_set_hidden(true)
			out_from_am = sim.absolute_position_am()
		if done or sim.dead:
			return SimIntent.new()
		var t: int = sim.tick - start_tick
		if t >= _next_refill:
			sim.debug_set_energy(sim.state.energy_capacity)
			_next_refill = (t / REFILL_TICKS + 1) * REFILL_TICKS
		if died_at_tick < 0:
			if t < SWIM_OUT_TICKS:
				growth_steps.take(sim, t)
				return _east.next_intent(sim)
			out_to_am = sim.absolute_position_am()
			died_at_tick = sim.tick
			sim.debug_hurt_player(sim.state.max_health)
			return SimIntent.new()
		if back_from_tick < 0:
			return SimIntent.new()
		if sim.tick - back_from_tick < SWIM_BACK_TICKS:
			return _north.next_intent(sim)
		done = true
		return SimIntent.new()

	## The tour routes the pool's sim events here: the "respawned" after the far death starts the
	## way back.
	func on_event(e: Dictionary, tick: int) -> void:
		if e.get("type", "") == "respawned" and died_at_tick >= 0 and back_from_tick < 0:
			back_from_tick = tick

	## The out leg's length (tm, from the absolute places; am is tm at S1's size 1).
	func distance_tm() -> float:
		if out_from_am.size() < 2 or out_to_am.size() < 2:
			return 0.0
		return Vector2(out_to_am[0] - out_from_am[0], out_to_am[1] - out_from_am[1]).length()


## The grow route (S2): a still cell, hidden from the AI at once and refilled every REFILL_TICKS,
## takes GROW_STEPS and is done GROW_ROUTE_TICKS from its first tick. Keyed on the sim's ticks, like
## SwimRoute.
class GrowRoute:
	extends RefCounted

	var done := false
	var start_tick := -1
	var growth_steps: GrowthSteps
	var _next_refill := 0

	func _init(settings: SettingsService = null) -> void:
		growth_steps = GrowthSteps.new(GROW_STEPS, settings)

	func next_intent(sim) -> SimIntent:
		if start_tick < 0:
			start_tick = sim.tick
			sim.debug_set_hidden(true)
		if done or sim.dead:
			return SimIntent.new()
		var t: int = sim.tick - start_tick
		if t >= GROW_ROUTE_TICKS:
			done = true
			return SimIntent.new()
		if t >= _next_refill:
			sim.debug_set_energy(sim.state.energy_capacity)
			_next_refill = (t / REFILL_TICKS + 1) * REFILL_TICKS
		growth_steps.take(sim, t)
		return SimIntent.new()

	func on_event(_e: Dictionary, _tick: int) -> void:
		pass

	func distance_tm() -> float:
		return 0.0


var main: Node
var report_path := ""
## The measured frame times in ms, by the wall clock.
var frame_ms := PackedFloat32Array()
## The GPU times of the measured frames in ms, where the renderer reported one.
var gpu_ms := PackedFloat32Array()
var _running := false
var _warm_up_end_usec := -1        ## set by the first sample
var _last_usec := -1               ## the previous measured frame; -1 until the warm-up is over
var _measured_ms := 0.0
# The route's state (null and empty on the M1 tour): a SwimRoute or a GrowRoute.
var _route: RefCounted
var _route_name := ""
var _next_progress_s := PROGRESS_EVERY_S
# The watch (WATCH_STALL_S): its thread, and what the main thread last did, under _watch_lock.
var _watch: Thread
var _watch_lock := Mutex.new()
var _watch_stop := false
var _watch_usec := 0               ## when the main thread last started a process step
var _watch_doing := "the start"    ## where the main thread is now, as stall_line() words it
var _watch_tick := 0               ## the route tick then
var _growths: Array[Dictionary] = []     ## {tick, t_s, reduce_motion} of each growth_began
var _frames: Array[Dictionary] = []      ## {t_s, ms, tick} of each measured frame
var _events: Array[Dictionary] = []      ## {t_s, text} of each sim event
var _world := {"rebases": 0, "chunk_loads": 0, "chunk_unloads": 0, "max_loaded_chunks": 0, "max_awake": 0,
	"max_sleepers": 0, "max_draw_calls": 0, "max_primitives": 0}


func attach(p_main: Node) -> void:
	main = p_main
	_begin.call_deferred()


## {"frames", "avg_fps", "low_1pct_fps", "max_frame_ms", "avg_frame_ms"} for frame times in ms,
## and {"gpu_frames", "gpu_avg_ms", "gpu_slow_1pct_ms", "gpu_p99_ms", "gpu_max_ms"} for GPU times
## in ms. The 1% low is the frame rate over the slowest 1% of frames, and the GPU's slow 1% the
## average of its slowest 1% (each at least one frame); its P99 is the time 99% of its frames come
## within (G18 on the swim route compares it with the M1 tour's). No frames give zeros.
static func summarize(frame_ms: PackedFloat32Array, gpu_ms := PackedFloat32Array()) -> Dictionary:
	var frames := _spread(frame_ms)
	var gpu := _spread(gpu_ms)
	return {
		"frames": frame_ms.size(),
		"avg_fps": 1000.0 / frames.avg if frames.avg > 0.0 else 0.0,
		"low_1pct_fps": 1000.0 / frames.slow_1pct if frames.slow_1pct > 0.0 else 0.0,
		"max_frame_ms": frames.max,
		"avg_frame_ms": frames.avg,
		"gpu_frames": gpu_ms.size(),
		"gpu_avg_ms": gpu.avg,
		"gpu_slow_1pct_ms": gpu.slow_1pct,
		"gpu_p99_ms": percentile(gpu_ms, 0.99),
		"gpu_max_ms": gpu.max,
	}


## The time `share` of the times come within (nearest rank); 0 for none.
static func percentile(ms: PackedFloat32Array, share: float) -> float:
	if ms.is_empty():
		return 0.0
	var sorted := ms.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(share * sorted.size()) - 1, 0, sorted.size() - 1)]


## The frames over `limit_ms`, each tagged with every event within `window_s` of it, before or
## after: [{at_s, ms, tick, events: ["chunk_loaded 4,0", "rebased 32,0", ...]}]. `frames` are
## {t_s, ms, tick} and `events` {t_s, text}, on the same clock.
static func long_frames(frames: Array, events: Array, limit_ms := LONG_FRAME_MS, window_s := TAG_WINDOW_S) -> Array:
	var out := []
	for f: Dictionary in frames:
		if float(f.ms) <= limit_ms:
			continue
		var tags := []
		for e: Dictionary in events:
			if absf(float(e.t_s) - float(f.t_s)) <= window_s:
				tags.append(e.text)
		out.append({"at_s": f.t_s, "ms": f.ms, "tick": f.tick, "events": tags})
	return out


## An event as a long frame's tag: its type, and for the world's own events the chunk key or the
## rebase offset ("chunk_loaded 4,0", "rebased 32,0").
static func event_text(e: Dictionary) -> String:
	var type := str(e.get("type", "?"))
	match type:
		"chunk_loaded", "chunk_unloaded":
			var key: Vector2i = e.get("key", Vector2i.ZERO)
			return "%s %d,%d" % [type, key.x, key.y]
		"rebased":
			var o: Vector2 = e.get("offset_tm", Vector2.ZERO)
			return "rebased %s,%s" % [_tm_text(o.x), _tm_text(o.y)]
	return type


## A distance in tm to a tenth, whole numbers without the decimal ("32", "-32.5").
static func _tm_text(v: float) -> String:
	var r := snappedf(v, 0.1)
	return str(int(r)) if r == roundf(r) else "%.1f" % r


## The frames within `window_s` of each growth, either side: [{tick, t_s, max_frame_ms, frames,
## reduce_motion}] in growth order, `frames` counting them. `frames` are {t_s, ms, tick} and `growths`
## {tick, t_s, reduce_motion}, on the same clock.
static func growth_windows(frames: Array, growths: Array, window_s := GROWTH_WINDOW_S) -> Array:
	var out := []
	for g: Dictionary in growths:
		var worst := 0.0
		var n := 0
		for f: Dictionary in frames:
			if absf(float(f.t_s) - float(g.t_s)) <= window_s:
				worst = maxf(worst, float(f.ms))
				n += 1
		out.append({"tick": g.tick, "t_s": g.t_s, "max_frame_ms": worst, "frames": n, "reduce_motion": g.reduce_motion})
	return out


## S2G26 on the growth windows: {"growth_pass", "growth_failed": [which]}. It passes when there was a
## growth and no window holds a frame over GROWTH_MAX_FRAME_MS; the failures name the first such
## growth ("growth at tick 7201: 62.5 ms") or say there was none.
static func growth_gate(windows: Array) -> Dictionary:
	var failed := []
	if windows.is_empty():
		failed.append("no growth")
	for w: Dictionary in windows:
		if float(w.max_frame_ms) > GROWTH_MAX_FRAME_MS:
			failed.append("growth at tick %d: %.1f ms" % [int(w.tick), float(w.max_frame_ms)])
	return {"growth_pass": failed.is_empty(), "growth_failed": failed}


## The verdict the printed line ends with: " · S2G26 pass", or " · S2G26 FAIL: " and the first failure.
static func growth_verdict(g: Dictionary) -> String:
	return " · S2G26 pass" if g.growth_pass else " · S2G26 FAIL: %s" % g.growth_failed[0]


## S3G36 on a route: {"growth_pass" (every growth window's longest frame at most
## GROWTH_MAX_FRAME_MS, with a growth), "draw_pass" (max_draw_calls at most S3G36_MAX_DRAW_CALLS),
## "failed": [which], "pass"}.
static func s3_gate(windows: Array, max_draw_calls: int) -> Dictionary:
	var growth := growth_gate(windows)
	var failed: Array = growth.growth_failed.duplicate()
	if max_draw_calls > S3G36_MAX_DRAW_CALLS:
		failed.append("draw calls %d > %d" % [max_draw_calls, S3G36_MAX_DRAW_CALLS])
	return {"growth_pass": growth.growth_pass, "draw_pass": max_draw_calls <= S3G36_MAX_DRAW_CALLS, "failed": failed,
		"pass": failed.is_empty()}


## The verdict the printed line ends with: " · S3G36 pass", or " · S3G36 FAIL: " and the first failure.
static func s3_verdict(s3: Dictionary) -> String:
	return " · S3G36 pass" if s3.pass else " · S3G36 FAIL: %s" % s3.failed[0]


## G18 on the swim route: {"low_1pct_ms", "max_frame_ms", "max_draw_calls", "gpu_p99_ms",
## "gpu_m1_p99_ms", "failed": [which], "pass"}. `report` is a swim report so far (summarize's
## fields and max_draw_calls); `m1_gpu_p99_ms` is the M1 tour's GPU P99 on the same machine, or a
## negative number when there is none, and then the GPU part is not judged (it is named in "skipped").
static func gate(report: Dictionary, m1_gpu_p99_ms: float) -> Dictionary:
	var low_ms := 1000.0 / float(report.low_1pct_fps) if float(report.get("low_1pct_fps", 0.0)) > 0.0 else 0.0
	var out := {"low_1pct_ms": low_ms, "max_frame_ms": float(report.get("max_frame_ms", 0.0)),
		"max_draw_calls": int(report.get("max_draw_calls", 0)), "gpu_p99_ms": float(report.get("gpu_p99_ms", 0.0)),
		"gpu_m1_p99_ms": m1_gpu_p99_ms, "failed": [], "skipped": []}
	if out.low_1pct_ms > G18_LOW_1PCT_MS:
		out.failed.append("1%% low %.1f ms > %.1f" % [out.low_1pct_ms, G18_LOW_1PCT_MS])
	if out.max_frame_ms > G18_MAX_FRAME_MS:
		out.failed.append("longest frame %.1f ms > %.0f" % [out.max_frame_ms, G18_MAX_FRAME_MS])
	if out.max_draw_calls > G18_MAX_DRAW_CALLS:
		out.failed.append("draw calls %d > %d" % [out.max_draw_calls, G18_MAX_DRAW_CALLS])
	if m1_gpu_p99_ms < 0.0:
		out.skipped.append("GPU P99: no M1 tour report on this machine")
	elif out.gpu_p99_ms > m1_gpu_p99_ms + G18_GPU_OVER_M1_MS:
		out.failed.append("GPU P99 %.2f ms > M1 %.2f + %.1f" % [out.gpu_p99_ms, m1_gpu_p99_ms, G18_GPU_OVER_M1_MS])
	out.pass = out.failed.is_empty()
	return out


## {"avg", "slow_1pct", "max"} of times in ms, slow_1pct averaging the slowest 1% (at least one);
## zeros for no times.
static func _spread(ms: PackedFloat32Array) -> Dictionary:
	if ms.is_empty():
		return {"avg": 0.0, "slow_1pct": 0.0, "max": 0.0}
	var sorted := ms.duplicate()
	sorted.sort()
	var total := 0.0
	for t in sorted:
		total += t
	var worst_n := maxi(1, sorted.size() / 100)
	var worst_total := 0.0
	for i in worst_n:
		worst_total += sorted[sorted.size() - 1 - i]
	return {"avg": total / sorted.size(), "slow_1pct": worst_total / worst_n, "max": sorted[sorted.size() - 1]}


func _begin() -> void:
	if main.flags.slot.is_empty():
		main.open_session(SLOT)
	_route_name = main.flags.perf_route
	match _route_name:
		"swim":
			_route = SwimRoute.new()
		"grow":
			_route = GrowRoute.new()
	if _route != null:
		_route.growth_steps.go_to_cradle = func() -> void:
			if main.debug_panel != null:
				main.debug_panel.run("go_to_cradle")
	main.intent_provider = _route if _route != null else load(BOT_PATH).new()
	var seed_value: int = main.flags.seed_value if main.flags.seed_value >= 0 else SEED
	var result: Dictionary = main.start_new(BODY, seed_value)
	if not result.ok:
		printerr("Perf tour could not start: %s" % "; ".join(result.errors))
		main.get_tree().quit(1)
		return
	if _route != null and not main.pool.is_endless():
		printerr("--perf-tour=%s needs the endless world" % _route_name)
		main.get_tree().quit(1)
		return
	main.pool.pause_on_focus_loss = false
	RenderingServer.viewport_set_measure_render_time(main.get_viewport().get_viewport_rid(), true)
	main.pool.died.connect(func(_cause: String, _reason: String): main.continue_after_death.call_deferred())
	if _route != null:
		main.pool.sim_event.connect(_on_event)
	_running = true
	if _route != null:
		RenderingServer.frame_pre_draw.connect(_watch_note.bind("the draw"))
		RenderingServer.frame_post_draw.connect(_watch_note.bind("the engine between frames"))
		# The tour's process step runs first and WatchTail's last, so a stall names the tour's own
		# step, the other nodes' or what the engine does after them.
		process_priority = WATCH_FIRST
		var tail := WatchTail.new()
		tail.tour = self
		add_child(tail)
		_watch_usec = Time.get_ticks_usec()
		_watch = Thread.new()
		_watch.start(_watch_loop)
	if _route_name == "swim":
		print("Perf tour (swim): %d s east, a far death, %d s north, after a %d s warm-up." % [
			SWIM_OUT_TICKS / 60, SWIM_BACK_TICKS / 60, WARM_UP_S])
	elif _route_name == "grow":
		print("Perf tour (grow): %d s still with %d growths, after a %d s warm-up." % [
			GROW_ROUTE_TICKS / 60, GROW_STEPS.filter(func(step: Array) -> bool: return step[1] == "grow").size(), WARM_UP_S])
	else:
		print("Perf tour: measuring %d s after a %d s warm-up." % [DURATION_S, WARM_UP_S])


## Takes one frame's wall clock reading (Time.get_ticks_usec()) and the renderer's latest GPU time
## in ms (0 or less: none). The first sample starts the warm-up; the first one after it starts the
## clock, and each later one records the time since the one before, and the GPU time if there is
## one. Returns whether DURATION_S of frames have been measured.
func sample(now_usec: int, gpu_frame_ms := 0.0) -> bool:
	if _warm_up_end_usec < 0:
		_warm_up_end_usec = now_usec + int(WARM_UP_S * 1e6)
	if now_usec < _warm_up_end_usec:
		return false
	if _last_usec >= 0:
		var ms := (now_usec - _last_usec) / 1000.0
		frame_ms.append(ms)
		_measured_ms += ms
		if gpu_frame_ms > 0.0:
			gpu_ms.append(gpu_frame_ms)
	_last_usec = now_usec
	return _measured_ms >= DURATION_S * 1000.0


func _physics_process(_delta: float) -> void:
	if _running and _route != null:
		_watch_note("the physics step")


func _process(_delta: float) -> void:
	if not _running:
		return
	if _route != null:
		_watch_note("the tour's GPU reading", true)
	var now := Time.get_ticks_usec()
	var measured := frame_ms.size()
	var over := sample(now, gpu_reading(self))
	if _route == null:
		if over:
			_finish()
		return
	if frame_ms.size() > measured:
		_frames.append({"t_s": _clock_s(now), "ms": frame_ms[frame_ms.size() - 1], "tick": main.pool.sim.tick})
		_sample_world()
	if _clock_s(now) >= _next_progress_s:
		_next_progress_s += PROGRESS_EVERY_S
		print(progress_line(_route_name, _clock_s(now), main.pool.sim.tick - int(_route.start_tick), frame_ms.size()))
	if _route.done:
		_finish()
	else:
		_watch_note("the other nodes' process steps")


## Notes where the main thread is now, and with `frame` that a frame's process step starts (the
## watch reads them).
func _watch_note(doing: String, frame := false) -> void:
	_watch_lock.lock()
	_watch_doing = doing
	if frame:
		_watch_usec = Time.get_ticks_usec()
	_watch_tick = main.pool.sim.tick - int(_route.start_tick) if _route.start_tick >= 0 else 0
	_watch_lock.unlock()


## The watch thread: every half second it looks at when the main thread last started a process step,
## and after WATCH_STALL_S without one it prints stall_line(), then again each WATCH_STALL_S the
## stall lasts. It ends when _stop_watch() asks.
func _watch_loop() -> void:
	var told_usec := 0
	while true:
		OS.delay_msec(500)
		_watch_lock.lock()
		var stop := _watch_stop
		var last := _watch_usec
		var doing := _watch_doing
		var tick := _watch_tick
		_watch_lock.unlock()
		if stop:
			return
		var now := Time.get_ticks_usec()
		var since := maxi(last, told_usec)
		if now - since >= int(WATCH_STALL_S * 1e6):
			told_usec = now
			print(stall_line(_route_name, (now - last) / 1e6, doing, tick))


## Ends the watch thread and waits for it.
func _stop_watch() -> void:
	if _watch == null:
		return
	_watch_lock.lock()
	_watch_stop = true
	_watch_lock.unlock()
	_watch.wait_to_finish()
	_watch = null


func _exit_tree() -> void:
	_stop_watch()


## The watch's last word each frame (process_priority last): every node's process step is done.
class WatchTail:
	extends Node

	var tour: Node

	func _init() -> void:
		process_priority = WATCH_LAST

	func _process(_delta: float) -> void:
		tour.call("_watch_note", "the engine after the process step")


## The watch's line: "Perf tour (grow): no frame for 30 s, in the draw at route tick 300".
static func stall_line(route: String, stalled_s: float, doing: String, route_ticks: int) -> String:
	return "Perf tour (%s): no frame for %d s, in %s at route tick %d" % [
		route, int(stalled_s), doing, route_ticks]


## A route's progress line: "Perf tour (grow): 20 s, route tick 1180, 9.5 FPS".
static func progress_line(route: String, clock_s: float, route_ticks: int, frames: int) -> String:
	return "Perf tour (%s): %d s, route tick %d, %.1f FPS" % [route, int(clock_s), route_ticks, frames / maxf(clock_s, 0.001)]


## Seconds on the tour's clock: from the end of the warm-up.
func _clock_s(now_usec: int) -> float:
	return (now_usec - _warm_up_end_usec) / 1e6 if _warm_up_end_usec >= 0 else 0.0


## The swim route's per-frame maxima: loaded chunks, awake creatures, sleepers, draw calls and
## primitives.
func _sample_world() -> void:
	var sim: PoolSim = main.pool.sim
	var w := sim.world
	_watch_note("the tour's chunk count")
	_world.max_loaded_chunks = maxi(_world.max_loaded_chunks, w.loaded_keys().size())
	_watch_note("the tour's creature count")
	_world.max_awake = maxi(_world.max_awake, sim.creatures.awake().size() if sim.creatures != null else 0)
	_world.max_sleepers = maxi(_world.max_sleepers, w.sleeping_ids().size())
	_watch_note("the tour's draw-call reading")
	_world.max_draw_calls = maxi(_world.max_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	_world.max_primitives = maxi(_world.max_primitives, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))


## The route's sim events: counted, kept for the long frames' tags, and passed to the route; each
## growth_began is kept with the reduce-motion setting then.
func _on_event(e: Dictionary) -> void:
	var now_s := _clock_s(Time.get_ticks_usec())
	match str(e.get("type", "")):
		"growth_began":
			_growths.append({"tick": main.pool.sim.tick, "t_s": now_s,
				"reduce_motion": SettingsService.shared().reduce_camera_motion()})
		"rebased":
			_world.rebases += 1
		"chunk_loaded":
			_world.chunk_loads += 1
		"chunk_unloaded":
			_world.chunk_unloads += 1
	_events.append({"t_s": now_s, "text": event_text(e)})
	_route.on_event(e, main.pool.sim.tick)


## The renderer's latest GPU time of `node`'s viewport in ms: 0 when it measures nothing, the
## node is outside the tree, or measuring is off (viewport_set_measure_render_time).
static func gpu_reading(node: Node) -> float:
	var viewport := node.get_viewport()
	return RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()) if viewport != null else 0.0


func _finish() -> void:
	_running = false
	_stop_watch()
	var report := summarize(frame_ms, gpu_ms)
	var headless := DisplayServer.get_name() == "headless"
	var window := Vector2i.ZERO if headless else DisplayServer.window_get_size()
	report.merge({
		"build": BuildInfo.build_id(),
		"duration_s": DURATION_S,
		"adapter": RenderingServer.get_video_adapter_name(),
		"adapter_vendor": RenderingServer.get_video_adapter_vendor(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"resolution": [window.x, window.y],
		"window_mode": "headless" if headless else str(DisplayServer.window_get_mode()),
		"vsync": "n/a" if headless else str(DisplayServer.window_get_vsync_mode()),
		"step_cost_usec": main.pool.step_cost_usec(),
	})
	if _route != null:
		_add_route_fields(report)
	DirAccess.make_dir_recursive_absolute(REPORT_DIR)
	report_path = "%s/perf_%s%s.json" % [REPORT_DIR, _route_name + "_" if _route != null else "", BuildInfo.build_id().validate_filename()]
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		printerr("Perf tour could not write %s: %s" % [report_path, error_string(FileAccess.get_open_error())])
		main.get_tree().quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	var line := "Perf tour: %.1f FPS average, %.1f FPS 1%% low, %.1f ms longest frame, GPU %.2f ms average (%d frames). Report: %s" % [
		report.avg_fps, report.low_1pct_fps, report.max_frame_ms, report.gpu_avg_ms, report.gpu_frames,
		ProjectSettings.globalize_path(report_path)]
	if _route_name == "swim":
		line += " · G18 pass" if report.gate.pass else " · G18 FAIL: %s" % "; ".join(report.gate.failed)
	if _route != null:
		line += growth_verdict(report.gate) + s3_verdict(report.gate.s3)
	print(line)
	main.get_tree().quit(0)


## The route's fields (S1 section 9, S2 12.2): the route, its ticks and the out leg's distance, the
## world's streaming, the frame maxima, the long frames, the growths' windows, and the gate: on the
## swim route G18 against this machine's M1 tour, on both S2G26 (growth_pass) and S3G36 (s3).
func _add_route_fields(report: Dictionary) -> void:
	var w: WorldStream = main.pool.sim.world
	var windows := growth_windows(_frames, _growths)
	report.merge(_world)
	report.merge({
		"route": _route_name,
		"ticks": main.pool.sim.tick - int(_route.start_tick),
		"distance_tm": _route.distance_tm(),
		"counters": w.counters.duplicate(),
		"long_frames": long_frames(_frames, _events),
		"growths": windows,
	})
	report.gate = gate(report, m1_gpu_p99_ms("%s/perf_%s.json" % [REPORT_DIR, BuildInfo.build_id().validate_filename()])) \
		if _route_name == "swim" else {}
	report.gate.merge(growth_gate(windows))
	report.gate.s3 = s3_gate(windows, int(report.get("max_draw_calls", 0)))


## The GPU P99 in the M1 tour's report at `path` (this machine and build's perf_<build>.json), or
## -1 when there is no report or it timed no GPU frame.
static func m1_gpu_p99_ms(path: String) -> float:
	if not FileAccess.file_exists(path):
		return -1.0
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not (data as Dictionary).has("gpu_p99_ms") or int(data.get("gpu_frames", 0)) == 0:
		return -1.0
	return float(data.gpu_p99_ms)
