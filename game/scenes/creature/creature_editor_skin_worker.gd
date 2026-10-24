extends RefCounted
## The creature editor's live skin builder: a worker thread that builds the newest body it is given, with its own
## GPU device when the renderer has compute (game/systems/creature/skin_gpu.gd; a local RenderingDevice belongs to
## the thread that made it) and the GDScript builder otherwise. A body posted while a build runs is built next; the
## editor collects the newest result each frame. A thread calls into the object that owns its function, so the
## worker is its own object: the editor node stays free to be freed once stop() has joined the thread.
## Ported from the creature lab's editor_lab.gd (_work, _rebuild, _collect_skin).

const SkinCpu := preload("res://game/systems/creature/skin_cpu.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")

## The GDScript builder's grid is capped here so a build stays interactive.
const CPU_DIVISIONS_MAX := 32

var rules := {}
## 0: the body's own preview grid (BodyDescription.preview_divisions).
var divisions := 0
## "GPU", "CPU" or "" before the first build.
var builder := ""

var _thread: Thread
var _mutex := Mutex.new()
var _signal := Semaphore.new()
var _job := {}
var _built := {}
var _quit := false
var _building := false
var _gpu: RefCounted


func _init(body_rules: Dictionary, grid_divisions := 0) -> void:
	rules = body_rules
	divisions = grid_divisions


## Starts the thread; it makes its own GPU device, if any.
func start() -> void:
	if _thread != null:
		return
	_thread = Thread.new()
	_thread.start(_work)


## Builds `body` (a codec dictionary) in step on the calling thread: for runs without a worker.
func build_now(body: Dictionary) -> Dictionary:
	if _gpu == null and builder == "":
		_gpu = _make_gpu()
		builder = "GPU" if _gpu else "CPU"
	return _build(body)


## Posts the newest body; it replaces one the worker has not started on.
func post(body: Dictionary) -> void:
	_mutex.lock()
	_job = body
	_building = true
	_mutex.unlock()
	_signal.post()


## The newest finished build, {desc, arrays, ms}, or {} when none is ready.
func collect() -> Dictionary:
	_mutex.lock()
	var built := _built
	_built = {}
	if not built.is_empty():
		_building = not _job.is_empty()
	_mutex.unlock()
	return built


func is_building() -> bool:
	_mutex.lock()
	var b := _building
	_mutex.unlock()
	return b


## Joins the thread (it frees its GPU device) or frees the main thread's one.
func stop() -> void:
	if _thread != null:
		_mutex.lock()
		_quit = true
		_mutex.unlock()
		_signal.post()
		_thread.wait_to_finish()
		_thread = null
	elif _gpu:
		_gpu.free_resources()
		_gpu = null


static func _make_gpu() -> RefCounted:
	var g = load("res://game/systems/creature/skin_gpu.gd").new()
	return g if g.is_available() else null


func _work() -> void:
	_gpu = _make_gpu()
	_mutex.lock()
	builder = "GPU" if _gpu else "CPU"
	_mutex.unlock()
	while true:
		_signal.wait()
		_mutex.lock()
		var job: Dictionary = _job
		_job = {}
		var quit := _quit
		_mutex.unlock()
		if quit:
			break
		if job.is_empty():
			continue
		var built := _build(job)
		_mutex.lock()
		_built = built
		_mutex.unlock()
	if _gpu:
		_gpu.free_resources()
		_gpu = null


func _build(body: Dictionary) -> Dictionary:
	var desc = BodyCodec.from_dict(body)
	var t0 := Time.get_ticks_usec()
	var d: int = divisions if divisions > 0 else desc.preview_divisions(rules)
	var arrays: Dictionary = _gpu.build(desc, d) if _gpu else SkinCpu.build(desc, mini(d, CPU_DIVISIONS_MAX))
	return {"desc": desc, "arrays": arrays, "ms": (Time.get_ticks_usec() - t0) / 1000.0}
