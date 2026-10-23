extends TestCase
## A rebase never shows (S1 G10; docs/s1/s1-content.md 7.2). Two endless runs, A and B, on the same
## seed and the same intents: the cell swims east and turns 90 degrees every TURN_TICKS, so the
## camera lags behind it. Between frames T and T + 1, B shifts the origin (sim.debug_rebase) and its
## pool routes the events before the next frame is drawn. Every tracked point (the cell, the creature
## views, shell instances, landmark pieces, the zone and meal labels, the column and the arrow, the
## Backdrop's centre) must land on the same pixel in both runs, frame by frame.
##
## The runner has no scene tree, so frames run by hand (_frame): the sim ticks, then the pool and the
## nodes under it process, as the engine runs them. Points are projected with Camera3D's own
## projection for a camera outside the tree (as tests/test_pool_view.gd's _unproject). A tween bound
## to a node outside the tree does not step, so the meal ghost's flight across a rebase is checked
## in the tree, by tests/smoke/endless_smoke.gd; here the ghost is checked where it starts.
##
## The look probe's rebase_pair measures the same promise in the real renderers (tools/godot/
## look_probe.gd, --world=endless); its pure parts are checked at the end of this file.

const FakeEvents := preload("res://tests/fakes/fake_world_events.gd")
const LookProbe := preload("res://tools/godot/look_probe.gd")
const Frames := preload("res://tests/scene_frames.gd")
const T := 180
const TURN_TICKS := 120
const SCREEN := Vector2(1920.0, 1080.0)
const TOLERANCE_PX := 0.5
const SHELLS_TRACKED := 20
const FOOD_TRACKED := 20
const REBASE_BY := Vector2i(1, 0)


## Swims at full throttle, east first, turning 90 degrees left every TURN_TICKS.
class Turning:
	func next_intent(sim: PoolSim) -> SimIntent:
		return SimIntent.new(Vector2.RIGHT.rotated(-PI / 2.0 * float(sim.tick / TURN_TICKS)))


## The cues, silent: a positional cue places its player by global_position, which a
## pool outside the tree has none of. Cues are not tracked points.
class QuietAudio extends CellAudio:
	func play(_cue: String) -> void:
		pass

	func play_at(_cue: String, _at: Vector3) -> void:
		pass


func test_a_rebase_moves_nothing_on_screen() -> void:
	var runs := _runs()
	check(runs.origins[0] == 0.0 and runs.origins[1] != 0.0, "only B's origin moved: %s" % [runs.origins])
	var worst := 0.0
	var worst_what := ""
	var compared := 0
	for frame in range(T - 2, T + 3):
		var pa: Dictionary = runs.frames[frame][0].screen
		var pb: Dictionary = runs.frames[frame][1].screen
		check_eq(pb.keys(), pa.keys(), "frame %d: both runs track the same points" % frame)
		for key in pa:
			if not pb.has(key):
				continue
			var d: float = (pa[key] as Vector2).distance_to(pb[key])
			compared += 1
			if d > worst:
				worst = d
				worst_what = "%s at frame %d (A %s, B %s)" % [key, frame, pa[key], pb[key]]
	check(compared >= 5 * 40, "about 50 points a frame over 5 frames: %d compared" % compared)
	check(worst <= TOLERANCE_PX, "every tracked point stays on its pixel across the rebase (worst %.4f px: %s)" % [worst, worst_what])


## S2: a rebase half a second into a growth beat moves nothing either: the retiring and fresh
## shells, the landmarks, the patches and labels, the beat's effects and the dollying camera all
## follow it (two runs, B rebasing at beat t 0.5 s).
func test_a_rebase_during_a_growth_beat_moves_nothing() -> void:
	var a := _open()
	var b := _open()
	# The ghosts hash from the lineage, which each session founds afresh: B takes A's.
	b.ghosts.configure(GhostLayer.shipped().data, b.sim_size(), hash(a.sim.save.lineage_id))
	var key: Vector2i = a.loaded_keys()[0]
	for pool in [a, b]:
		for i in 20:
			_frame(pool)
		var c: Vector2 = pool.sim.motion.position
		pool._route({"type": "growth_began", "from": 1, "to": 2, "center_old": c, "center_am": [0.0, 0.0], "factor": 1.6})
		pool._route(FakeEvents.unloaded(key, "growth"))
		pool._route(FakeEvents.loaded(Vector2i(901, 901), [FakeEvents.shell("fresh_rv", Vector2(2.0, -3.0), 0.4, "rock_a")]))
		var haze := [{"kind": "plant", "look": "plankton", "position": c + Vector2(3.0, 2.0)},
			{"kind": "plant", "look": "plankton", "position": c + Vector2(-4.0, 1.0)}]
		pool._route({"type": "grew", "from": 1, "to": 2, "settled_to": Vector2.ZERO, "haze": haze, "remnants": [], "morsels": [],
			"checkpoint_am": [0.0, 0.0, 0.0, 2.0]})
	check(not a.rocks.retiring_of("rock_a").is_empty() and not a.rocks.fresh_of("rock_a").is_empty(), "shells retire and come in")
	check(not a.growth_beat.glitter().is_empty() and not a.growth_beat.old_food().is_empty(), "the old food and its glitter")
	var worst := 0.0
	var worst_what := ""
	var compared := 0
	var rebased := false
	while a.growth_beat.t() < 0.8:
		if not rebased and a.growth_beat.t() >= 0.5:
			rebased = true
			check(b.sim.debug_rebase(REBASE_BY), "B shifts the origin at beat t 0.5 s")
		_frame(a)
		_frame(b)
		if rebased:
			var pa := _beat_pixels(a)
			var pb := _beat_pixels(b)
			check_eq(pb.keys(), pa.keys(), "both runs track the same points")
			for k in pa:
				if pb.has(k):
					compared += 1
					var d: float = (pa[k] as Vector2).distance_to(pb[k])
					if d > worst:
						worst = d
						worst_what = "%s (A %s, B %s)" % [k, pa[k], pb[k]]
	check(rebased and b.sim.world.origin_x_am != a.sim.world.origin_x_am, "only B's origin moved")
	check(compared > 100, "points compared over the beat: %d" % compared)
	check(worst <= TOLERANCE_PX, "every point stays on its pixel (worst %.4f px: %s)" % [worst, worst_what])
	_close(a)
	_close(b)


## The growth beat's tracked points (tests/scene_frames.gd), as pixels.
func _beat_pixels(pool: PoolScene) -> Dictionary:
	var out := {}
	var points := Frames.tracked_points(pool)
	for k in points:
		out[k] = _project(pool.camera, points[k])
	return out


func test_a_lane_shown_before_a_rebase_stays_on_its_creature() -> void:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session())
	var sim := pool.sim
	check(sim.debug_spawn_creature("rammer", sim.motion.position + Vector2(6.0, 4.0), 0.0), "a rammer")
	FakeEvents.frame(pool)
	var view: CreatureView = pool.creature_layer.views().back()
	var length := 6.0
	view.show_lane({"origin": Vector2(10.0 - length * 0.5, 0.0), "heading": 0.0, "length": length, "half_width": 0.5})
	var lane := view.lane()
	check(lane.top_level, "the lane is drawn in the pool's space")
	check_near(lane.transform.origin.x, 10.0, 1e-6, "shown at local (10, 0)")
	pool.world_space.apply_rebase(Vector2(32.0, 0.0))
	check_near(lane.transform.origin.x, 10.0 - 32.0, 1e-6, "and moved with the world by the rebase")
	pool.free()


func test_a_dying_creature_and_a_meal_ghost_stay_put_across_a_rebase() -> void:
	var runs := _runs()
	var worst := 0.0
	var worst_what := ""
	for frame in range(T, T + 11):
		var ra: Array = runs.frames[frame][0].dying
		var rb: Array = runs.frames[frame][1].dying
		check_eq(rb.size(), ra.size(), "frame %d: the same dying views and ghosts in both runs" % frame)
		check(ra.size() == 2, "frame %d: a dying view and a ghost are in the air: %d" % [frame, ra.size()])
		for i in mini(ra.size(), rb.size()):
			var d: float = (ra[i] as Vector3).distance_to(rb[i])
			if d > worst:
				worst = d
				worst_what = "point %d at frame %d (A %s, B %s)" % [i, frame, ra[i], rb[i]]
	check(worst <= 1e-4, "they keep their place relative to the camera (worst %.6f: %s)" % [worst, worst_what])


func test_particles_in_the_air_move_with_the_world() -> void:
	var runs := _runs()
	check(runs.fx_under_world_fx, "after attach_fx, EatFx is under WorldFx")
	check(runs.fx_local, "with its particles local to it")
	var worst := 0.0
	for frame in range(T, T + 11):
		worst = maxf(worst, (runs.frames[frame][0].fx as Vector3).distance_to(runs.frames[frame][1].fx))
	check(worst <= 1e-4, "the burst keeps its place relative to the camera across the rebase (worst %.6f)" % worst)


## The look probe reads its rebase pair over the whole frame: the median, the 99th percentile and
## the largest CIE76 of the pixels it samples, so a few moved pixels show in p99 and max.
func test_the_look_probe_reads_a_rebase_pair_by_its_spread() -> void:
	var a := Image.create(20, 10, false, Image.FORMAT_RGB8)
	a.fill(Color.BLACK)
	var b := a.duplicate() as Image
	var whole := Rect2i(0, 0, 20, 10)
	check_eq(LookProbe.delta_e_spread(a, b, whole), {"median": 0.0, "p99": 0.0, "max": 0.0}, "the same frame")
	b.set_pixel(19, 9, Color.WHITE)
	var one := LookProbe.delta_e_spread(a, b, whole)
	check_eq([one.median, one.p99, one.max], [0.0, 0.0, 100.0], "one pixel of 200 changed: above the 99th percentile")
	b.set_pixel(18, 9, Color.WHITE)
	b.set_pixel(17, 9, Color.WHITE)
	check_eq(LookProbe.delta_e_spread(a, b, whole).p99, 100.0, "three of 200 reach it")
	check_eq(LookProbe.delta_e_spread(a, b, whole, 2).max, 0.0, "every second pixel on both axes: row 9 is not sampled")
	check(LookProbe.delta_e_spread(a, b, Rect2i(30, 0, 5, 5)).is_empty(), "no pixel, no spread")


## --world=endless stages the endless scenes and judges them by the endless gates; the pool keeps
## its own scenes and looks, so today's commands and baselines are unchanged (content doc section 10).
func test_the_look_probe_keeps_the_endless_scenes_apart_from_the_pool() -> void:
	check_eq(str(LookProbe.scenes_for("pool")), str(LookProbe.POOL_SCENES), "the pool's scenes by default there")
	check_eq(str(LookProbe.scenes_for("endless")), str(LookProbe.ENDLESS_SCENES), "the endless sea's there")
	check(LookProbe.scenes_for("nowhere").is_empty(), "no other world")
	check_eq(str(LookProbe.SCENES), str(LookProbe.POOL_SCENES + LookProbe.ENDLESS_SCENES), "every scene is one world's")
	check_eq(LookProbe.LOOK_WORLDS.keys(), LookProbe.GATES.keys(), "every look measures one world")
	for look: String in LookProbe.GATES:
		var world: String = LookProbe.LOOK_WORLDS.get(look, "")
		for gate: Dictionary in LookProbe.GATES[look]:
			check(LookProbe.scenes_for(world).has(gate.path.get_slice(".", 0)), "%s/%s reads a %s scene: %s" % [look, gate.id, world, gate.path])
	var paths: Array = LookProbe.GATES.endless.map(func(g: Dictionary) -> String: return g.path)
	for scene in LookProbe.ENDLESS_SCENES:
		check(paths.any(func(path: String) -> bool: return path.begins_with(scene + ".")), "an endless gate reads %s" % scene)
	for path in ["rebase_pair.median_dE", "rebase_pair.p99_dE", "markers.pip_present"]:
		check(paths.has(path), "the endless gates read %s" % path)


# --- the runs ---

var _pair := {}


## The pair of runs, made once for the file: A and B to frame T + 10, with a meal at T - 1 (its label
## rises across the rebase), and at T the nearest creature killed, a meal ghost made and the eat
## burst started; B rebases between frames T and T + 1. Per frame from T - 2: each run's tracked
## pixels (screen), its dying views and ghosts relative to the camera (dying) and its eat burst
## relative to the camera (fx).
func _runs() -> Dictionary:
	if not _pair.is_empty():
		return _pair
	var a := _open()
	var b := _open()
	var frames := {}
	for frame in range(1, T + 11):
		if frame == T - 1:
			for pool in [a, b]:
				pool.feedback.show_meal({"type": "ate", "position": pool.sim.motion.position + Vector2(1.5, -1.0), "absorbed": 8.0, "points": 1})
		if frame == T:
			for pool in [a, b]:
				check(pool.sim.debug_kill_nearest_creature(), "the nearest creature dies at T")
				# swallow() draws nothing outside the tree; its ghost and burst are made as it makes them.
				var at: Vector2 = pool.sim.motion.position
				pool.cell_view._ghost(pool.plankton_view.food_mesh(), PlaneSpace.to_world(at + Vector2(1.0, 0.5)), PlaneSpace.to_world(at))
				pool.cell_view._burst(PlaneSpace.to_world(at, 0.3), Color.WHITE)
		if frame == T + 1:
			check(b.sim.debug_rebase(REBASE_BY), "B shifts the origin between frames T and T + 1")
		_frame(a)
		_frame(b)
		if frame >= T - 2:
			frames[frame] = [_record(a), _record(b)]
	var fx: CPUParticles3D = a.cell_view._fx()
	_pair = {"frames": frames, "origins": [a.sim.world.origin_x_am, b.sim.world.origin_x_am],
		"fx_under_world_fx": fx.get_parent() == a.world_fx, "fx_local": fx.local_coords}
	_close(a)
	_close(b)
	return _pair


func _record(pool: PoolScene) -> Dictionary:
	return {"screen": _screen_points(pool), "dying": _dying_and_ghosts(pool), "fx": _eat_fx_from_camera(pool)}

## An endless pool on the shared seed with Turning swimming, a rammer near the cell and a chunk with
## a landmark and a rare piece in view (FakeWorldGen has none), so every kind of point is tracked.
func _open() -> PoolScene:
	var pool := FakeEvents.open_pool(FakeEvents.endless_session(), Turning.new())
	var sim := pool.sim
	pool.audio = QuietAudio.new()
	sim.debug_spawn_creature("rammer", sim.motion.position + Vector2(9.0, -6.0), PI)
	sim.debug_spawn_creature("rammer", sim.motion.position + Vector2(-9.0, 7.0), 0.0)
	var c := sim.motion.position
	pool.apply_world_event(FakeEvents.loaded(Vector2i(900, 900), [
			FakeEvents.shell("lm_rv", c + Vector2(12.0, -6.0), 2.0, "landmark_great_shell", 90.0, 0.95, "#D6E0F5", "landmark"),
			FakeEvents.shell("sp_rv", c + Vector2(-14.0, -10.0), 1.1, "rare_giant_husk", 0.0, 1.0, "", "set_piece")],
		[FakeEvents.zone("z_rv", c + Vector2(4.0, 10.0), 4.0, "sunlit")],
		[FakeEvents.anchor("a_rv", c + Vector2(12.0, -6.0), "landmark_great_shell", "frosted")],
		[FakeEvents.place("p_rv", "giant_husk", c + Vector2(-14.0, -10.0))]))
	return pool


## Frees a pool _open made, with its quiet audio.
func _close(pool: PoolScene) -> void:
	pool.audio.free()
	pool.free()


## One frame as the engine runs it at 60 fps: the sim ticks and its events route, then the pool
## processes, and so do the nodes under it that move tracked points (the labels, the cell and the
## creature views).
func _frame(pool: PoolScene) -> void:
	pool._physics_process(FakeEvents.DT)
	pool._process(FakeEvents.DT)
	pool.feedback._process(FakeEvents.DT)
	pool.cell_view._process(FakeEvents.DT)
	for view in pool.creature_layer.get_children():
		if not view.is_queued_for_deletion():
			view._process(FakeEvents.DT)


## The tracked points' pixels: name -> Vector2.
func _screen_points(pool: PoolScene) -> Dictionary:
	var out := {}
	var add := func(key: String, p: Vector3) -> void:
		out[key] = _project(pool.camera, p)
	add.call("cell", pool.cell_view.position)
	for view in pool.creature_layer.views():
		add.call("creature " + view.name, _in_pool(pool, view))
	var shells := _shell_points(pool)
	for i in mini(shells.size(), SHELLS_TRACKED):
		add.call("shell %d" % i, shells[i])
	# Food is drawn in the sim's item order; each drawn instance is tracked by its item's id, from
	# the buffer the view hands its MultiMesh (the headless renderer keeps no instance data to read).
	var food := pool.plankton_view
	var items := pool.sim.plankton.items
	var ids := []
	for i in mini(food.shown_count(), items.size()):
		ids.append([str(items[i].id), i])
	ids.sort()
	for pair in ids.slice(0, FOOD_TRACKED):
		var o: int = pair[1] * FoodView.FLOATS_PER_INSTANCE
		add.call("food " + pair[0], food.transform * Vector3(food._buffer[o + 3], food._buffer[o + 7], food._buffer[o + 11]))
	for piece in pool.landmarks.pieces():
		add.call("landmark " + piece.name, _in_pool(pool, piece))
	for child in pool.feedback.get_children():
		if child is Label3D and child.visible:
			add.call("label " + child.name, _in_pool(pool, child))
	if pool.markers.column() != null:
		add.call("column", _in_pool(pool, pool.markers.column()))
	if pool.markers.arrow() != null and pool.markers.arrow().visible:
		add.call("arrow", _in_pool(pool, pool.markers.arrow()))
	add.call("backdrop", pool.backdrop.position * Vector3(1.0, 0.0, 1.0))
	return out


## The dying creature views and the meal ghosts, each relative to the camera, in a fixed order.
func _dying_and_ghosts(pool: PoolScene) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var to_camera := pool.camera.transform.affine_inverse()
	for child in pool.creature_layer.get_children():
		if child is CreatureView and (child as CreatureView).dying:
			out.append(to_camera * _in_pool(pool, child))
	for child in pool.world_fx.get_children():
		if child is MeshInstance3D:
			out.append(to_camera * _in_pool(pool, child))
	return out


func _eat_fx_from_camera(pool: PoolScene) -> Vector3:
	var fx: Node3D = pool.cell_view._fx()
	return pool.camera.transform.affine_inverse() * _in_pool(pool, fx)


## Every shell instance's centre in the pool's space, piece by piece in name order.
func _shell_points(pool: PoolScene) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var assets := pool.rocks.assets_in_use()
	assets.sort()
	for asset in assets:
		for e in pool.rocks.instances_of(asset):
			out.append(pool.rocks.transform * (e.transform as Transform3D).origin)
	return out


## `node`'s origin in the pool's space, from its own transforms up to the pool (a top_level node's
## transform is already the pool's space).
static func _in_pool(pool: PoolScene, node: Node3D) -> Vector3:
	var t := node.transform
	var n := node
	while not n.top_level and n.get_parent() != pool and n.get_parent() is Node3D:
		n = n.get_parent()
		t = n.transform * t
	return t.origin


## Camera3D.unproject_position for a camera outside the tree on a SCREEN-sized view (keep-height fov).
static func _project(camera: Camera3D, p: Vector3) -> Vector2:
	var view := camera.transform.affine_inverse() * p
	var clip := Projection.create_perspective(camera.fov, SCREEN.aspect(), camera.near, camera.far) * Vector4(view.x, view.y, view.z, 1.0)
	var ndc := Vector2(clip.x, clip.y) / clip.w
	return Vector2((ndc.x + 1.0) * 0.5 * SCREEN.x, (1.0 - ndc.y) * 0.5 * SCREEN.y)
