extends SceneTree
## Windows runner probe (scratch branch, not for main): does a non-zero blend shape weight on the
## cell's Body hang Direct3D 12 on the runner's software adapter? Frames 1-60 at weight 0, then the
## Ripeness shape at 0.3 and rising. A watch thread prints when no frame comes for 10 s.

var frame := 0
var body: MeshInstance3D
var last_ms := 0
var watch: Thread
var lock := Mutex.new()
var seen := 0
var stop := false


func _init() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.5, 3)
	root.add_child(cam)
	cam.look_at(Vector3.ZERO)
	root.add_child(DirectionalLight3D.new())
	var cell: Node3D = (load("res://assets/export/sample_cell.glb") as PackedScene).instantiate()
	root.add_child(cell)
	body = cell.find_child("Body", true, false) as MeshInstance3D
	print("probe: body %s, %d blend shapes, Ripeness at %d, driver %s" % [body, body.get_blend_shape_count() if body else -1,
		body.find_blend_shape_by_name(&"Ripeness") if body else -1, RenderingServer.get_current_rendering_driver_name()])
	watch = Thread.new()
	watch.start(_watch)
	last_ms = Time.get_ticks_msec()


func _watch() -> void:
	var told_ms := 0
	var last_seen := -1
	var since_ms := Time.get_ticks_msec()
	while true:
		OS.delay_msec(500)
		lock.lock()
		var s := stop
		var f := seen
		lock.unlock()
		if s:
			return
		var now := Time.get_ticks_msec()
		if f != last_seen:
			last_seen = f
			since_ms = now
		elif now - maxi(since_ms, told_ms) >= 10000:
			told_ms = now
			print("probe: no frame for %d s, after frame %d" % [(now - since_ms) / 1000, f])


func _process(_delta: float) -> bool:
	frame += 1
	lock.lock()
	seen = frame
	lock.unlock()
	var now := Time.get_ticks_msec()
	if now - last_ms > 500 or frame % 20 == 0:
		print("probe: frame %d, %d ms since the last" % [frame, now - last_ms])
	last_ms = now
	var i := body.find_blend_shape_by_name(&"Ripeness") if body else -1
	if frame == 60:
		print("probe: Ripeness to 0.3 (shape %d)" % i)
	if frame >= 60 and i >= 0:
		body.set_blend_shape_value(i, minf(0.3 + 0.002 * (frame - 60), 1.0))
	if frame >= 200:
		print("probe: done, 200 frames")
		lock.lock()
		stop = true
		lock.unlock()
		watch.wait_to_finish()
		return true
	return false
