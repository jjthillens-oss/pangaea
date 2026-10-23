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
## The GPU times of the measured frames in ms, where the renderer reported one.
var gpu_ms := PackedFloat32Array()
var _running := false
var _warm_up_end_usec := -1        ## set by the first sample
var _last_usec := -1               ## the previous measured frame; -1 until the warm-up is over
var _measured_ms := 0.0


func attach(p_main: Node) -> void:
	main = p_main
	_begin.call_deferred()


## {"frames", "avg_fps", "low_1pct_fps", "max_frame_ms", "avg_frame_ms"} for frame times in ms,
## and {"gpu_frames", "gpu_avg_ms", "gpu_slow_1pct_ms", "gpu_max_ms"} for GPU times in ms. The 1%
## low is the frame rate over the slowest 1% of frames, and the GPU's slow 1% the average of its
## slowest 1% (each at least one frame). No frames give zeros.
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
		"gpu_max_ms": gpu.max,
	}


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
	main.intent_provider = load(BOT_PATH).new()
	var seed_value: int = main.flags.seed_value if main.flags.seed_value >= 0 else SEED
	var result: Dictionary = main.start_new(BODY, seed_value)
	if not result.ok:
		printerr("Perf tour could not start: %s" % "; ".join(result.errors))
		main.get_tree().quit(1)
		return
	main.pool.pause_on_focus_loss = false
	RenderingServer.viewport_set_measure_render_time(main.get_viewport().get_viewport_rid(), true)
	main.pool.died.connect(func(_cause: String, _reason: String): main.continue_after_death.call_deferred())
	_running = true
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


func _process(_delta: float) -> void:
	if _running and sample(Time.get_ticks_usec(), gpu_reading(self)):
		_finish()


## The renderer's latest GPU time of `node`'s viewport in ms: 0 when it measures nothing, the
## node is outside the tree, or measuring is off (viewport_set_measure_render_time).
static func gpu_reading(node: Node) -> float:
	var viewport := node.get_viewport()
	return RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()) if viewport != null else 0.0


func _finish() -> void:
	_running = false
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
	DirAccess.make_dir_recursive_absolute(REPORT_DIR)
	report_path = "%s/perf_%s.json" % [REPORT_DIR, BuildInfo.build_id().validate_filename()]
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		printerr("Perf tour could not write %s: %s" % [report_path, error_string(FileAccess.get_open_error())])
		main.get_tree().quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Perf tour: %.1f FPS average, %.1f FPS 1%% low, %.1f ms longest frame, GPU %.2f ms average (%d frames). Report: %s" % [
		report.avg_fps, report.low_1pct_fps, report.max_frame_ms, report.gpu_avg_ms, report.gpu_frames,
		ProjectSettings.globalize_path(report_path)])
	main.get_tree().quit(0)
