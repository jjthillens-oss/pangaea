extends Node
## Debug builds only (M1 step 2): `-- --perf-tour` lets the dev ForageBot swim a grazer for
## DURATION_S at the current window size, then writes user://reports/perf_<build>.json and quits.
## The report holds the average FPS, the 1% low, the longest frame, the adapter, driver,
## resolution and vsync. It uses its own save slot unless --slot is given, so the player's
## lineage is never touched. Main loads it by path when the flag is given.
##
## Frames are timed by the wall clock, not the process delta: the engine smooths delta and caps it
## near (max_physics_steps_per_frame + 1) physics ticks, about 150 ms, so a longer stall would read
## short and its lost time would drop out of the averages. DURATION_S and WARM_UP_S are wall time.

const DURATION_S := 90.0
const WARM_UP_S := 2.0             ## the first frames (shader warm-up, fade-in) are not measured
const SLOT := "user://reports/perf_tour_slot.json"
const REPORT_DIR := "user://reports"
const BODY := "grazer"
const SEED := 4242
const BOT_PATH := "res://game/dev/forage_bot.gd"

var main: Node
var report_path := ""
## The measured frame times in ms, by the wall clock.
var frame_ms := PackedFloat32Array()
var _running := false
var _warm_up_end_usec := -1        ## set by the first sample
var _last_usec := -1               ## the previous measured frame; -1 until the warm-up is over
var _measured_ms := 0.0


func attach(p_main: Node) -> void:
	main = p_main
	_begin.call_deferred()


## {"frames", "avg_fps", "low_1pct_fps", "max_frame_ms", "avg_frame_ms"} for frame times in ms.
## The 1% low is the frame rate over the slowest 1% of frames (at least one frame).
static func summarize(frame_ms: PackedFloat32Array) -> Dictionary:
	if frame_ms.is_empty():
		return {"frames": 0, "avg_fps": 0.0, "low_1pct_fps": 0.0, "max_frame_ms": 0.0, "avg_frame_ms": 0.0}
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var total := 0.0
	for ms in sorted:
		total += ms
	var worst_n := maxi(1, sorted.size() / 100)
	var worst_total := 0.0
	for i in worst_n:
		worst_total += sorted[sorted.size() - 1 - i]
	var avg_ms := total / sorted.size()
	return {
		"frames": sorted.size(),
		"avg_fps": 1000.0 / avg_ms,
		"low_1pct_fps": 1000.0 / (worst_total / worst_n),
		"max_frame_ms": sorted[sorted.size() - 1],
		"avg_frame_ms": avg_ms,
	}


func _begin() -> void:
	if main.flags.slot.is_empty():
		main.open_session(SLOT)
	main.intent_provider = load(BOT_PATH).new()
	var seed_value: int = main.flags.seed_value if main.flags.seed_value >= 0 else SEED
	var result: Dictionary = main.start_new(BODY, seed_value)
	if not result.ok:
		printerr("Perf tour could not start: %s" % "; ".join(result.errors))
		main.get_tree().quit(1)
		return
	main.pool.pause_on_focus_loss = false
	main.pool.died.connect(func(_cause: String): main.continue_after_death.call_deferred())
	_running = true
	print("Perf tour: measuring %d s after a %d s warm-up." % [DURATION_S, WARM_UP_S])


## Takes one frame's wall clock reading (Time.get_ticks_usec()). The first sample starts the
## warm-up; the first one after it starts the clock, and each later one records the time since
## the one before. Returns whether DURATION_S of frames have been measured.
func sample(now_usec: int) -> bool:
	if _warm_up_end_usec < 0:
		_warm_up_end_usec = now_usec + int(WARM_UP_S * 1e6)
	if now_usec < _warm_up_end_usec:
		return false
	if _last_usec >= 0:
		var ms := (now_usec - _last_usec) / 1000.0
		frame_ms.append(ms)
		_measured_ms += ms
	_last_usec = now_usec
	return _measured_ms >= DURATION_S * 1000.0


func _process(_delta: float) -> void:
	if _running and sample(Time.get_ticks_usec()):
		_finish()


func _finish() -> void:
	_running = false
	var report := summarize(frame_ms)
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
	DirAccess.make_dir_recursive_absolute(REPORT_DIR)
	report_path = "%s/perf_%s.json" % [REPORT_DIR, BuildInfo.build_id().validate_filename()]
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		printerr("Perf tour could not write %s: %s" % [report_path, error_string(FileAccess.get_open_error())])
		main.get_tree().quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Perf tour: %.1f FPS average, %.1f FPS 1%% low, %.1f ms longest frame. Report: %s" % [
		report.avg_fps, report.low_1pct_fps, report.max_frame_ms, ProjectSettings.globalize_path(report_path)])
	main.get_tree().quit(0)
