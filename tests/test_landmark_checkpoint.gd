extends TestCase
## The landmark return point (S3 T2.6; docs/s3: s3-sim 3.7 to 3.9, D-132, D-132a, D-132b, BP3-8,
## BP3-17): on FakeWorldGen at sizes 3 and 4, chunk (2, -2) holds the anchor "a_f_lm" inside a
## landmark collider (D-145). At the build's top (4) a calm cell within landmark_find_tm of it moves
## the checkpoint to its clear point, once (S3G24); the point is spiralled once per anchor per size
## (S3G24b); a blocked anchor, a chunk within D not loaded, a disc within respawn_clear_m and the
## switch off each keep the checkpoint where it is (S3G24, S3G24d).

const FakeWorldGen := preload("res://tests/fakes/fake_world_gen.gd")
const B1_WORLD := "res://tests/fixtures/world/world_b1_min.json"
const ANCHOR := "a_f_lm"
const ANCHOR_TM := Vector2(80.0, -48.0)   ## ANCHOR_CHUNK's centre (tm at the sim's size)
const PERIOD := 8                         ## no creature site within reach of the anchor
const WARM_TICKS := 60

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog


func before_each() -> void:
	if species != null:
		return
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()


## An endless sim at `size` (the top is 4) with the cell `offset` tm from the anchor, every brain
## frozen, the events drained. `blocked` covers the anchor with a shell of
## ChunkArena.MAX_COLLIDER_R (4 tm, the spiral's reach).
func _sim(size := 4, offset := Vector2(4.0, 0.0), switch_on := true, blocked := false) -> PoolSim:
	var content := FakeWorldGen.fixture_content(B1_WORLD)
	content.config.switches["landmark_return"] = switch_on
	var sim := FakeWorldGen.endless_sim(7, catalog, layout, species, content, PackedFloat64Array(), PERIOD, true)
	if blocked:
		sim.world.gen.extra_shells[Vector3i(FakeWorldGen.ANCHOR_CHUNK.x, FakeWorldGen.ANCHOR_CHUNK.y, size)] = [
			{"x": ANCHOR_TM.x, "y": ANCHOR_TM.y, "r": ChunkArena.MAX_COLLIDER_R}]
	check(sim.debug_set_size(size), "size %d" % size)
	var k := WorldConfig.tm_to_am(size)
	var at := ANCHOR_TM + offset
	check(sim.debug_teleport_abs(at.x * k, at.y * k), "the cell %s tm from the anchor" % offset)
	sim.debug_set_ai_frozen(true)
	sim.motion.velocity = Vector2.ZERO
	sim.drain_events()
	return sim


## Steps `ticks` times holding the cell still; the events, each stamped with its tick.
func _run(sim: PoolSim, ticks: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var at := sim.motion.position
	for i in ticks:
		var t := sim.tick
		sim.step(SimIntent.new())
		sim.motion.position = at
		sim.motion.velocity = Vector2.ZERO
		for e in sim.drain_events():
			e["tick"] = t
			out.append(e)
	return out


static func _moved(events: Array[Dictionary]) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "checkpoint_moved")


func _anchor(sim: PoolSim) -> Dictionary:
	var ch := sim.world.chunk(FakeWorldGen.ANCHOR_CHUNK)
	check(ch != null, "the anchor's chunk loaded")
	if ch == null:
		return {}
	for a in ch.anchors:
		if a.id == ANCHOR:
			return a
	return {}


## Holds the cell not calm (a meal every tick) through `ticks`, so the pass refuses meanwhile; then
## the meal is quiet_ticks back, so the cell is calm again.
func _hold_unsettled(sim: PoolSim, ticks: int) -> void:
	var g := sim.growth
	for i in ticks:
		g.last_meal = sim.tick
		_run(sim, 1)
	g.last_meal = sim.tick - int(g.cfg.quiet_ticks)


## S3G24: a calm cell beside the anchor at the top moves the checkpoint to the anchor's clear point:
## checkpoint_moved (reason landmark), the point clear and within the spiral of the anchor, the size
## the top's; the anchor is then the checkpoint's own and never fires again.
func test_a_calm_cell_by_an_anchor_at_the_top_moves_the_checkpoint() -> void:
	var sim := _sim()
	var w := sim.world
	var before := w.checkpoint_am.duplicate()
	var moved := _moved(_run(sim, WARM_TICKS))
	check_eq(moved.size(), 1, "one checkpoint_moved")
	if moved.size() != 1:
		return
	check_eq([moved[0].reason, moved[0].anchor], ["landmark", ANCHOR], "for the landmark")
	check(w.checkpoint_am != before, "the checkpoint moved")
	check_eq(Array(w.checkpoint_am), moved[0].checkpoint_am, "to the event's place")
	check_eq(int(w.checkpoint_am[3]), 4, "at the top's size")
	var p := w.local_of_abs(w.checkpoint_am[0], w.checkpoint_am[1])
	var anchor_at := w.local_of_tm(ANCHOR_TM.x, ANCHOR_TM.y)
	check(sim.arena.is_clear(p, sim.phenotype.radius), "a clear point")
	check(p.distance_to(anchor_at) <= WorldStream.LANDMARK_SPIRAL_RINGS * PoolSim.CLEAR_SPIRAL_STEP_M + 1e-4,
		"within the spiral of the anchor (%.2f tm)" % p.distance_to(anchor_at))
	check_eq(w.landmark_anchor, ANCHOR, "the anchor is the checkpoint's")
	check_eq(sim.snapshot().world.get("landmark_anchor", ""), ANCHOR, "and in the snapshot")
	check(_moved(_run(sim, WARM_TICKS)).is_empty(), "a seen anchor never fires again")
	check_eq(w.landmark_candidate(sim, _anchor(sim)).reason, "seen", "the candidate says seen")


## S3G24: only at the build's top: at size 3 (below 4) nothing moves.
func test_no_return_point_below_the_top() -> void:
	var sim := _sim(3)
	check_eq(sim.world.max_size, 4, "the top is 4")
	check(_moved(_run(sim, WARM_TICKS)).is_empty(), "no checkpoint_moved at size 3")
	check_eq(sim.world.landmark_anchor, "", "no landmark")


## S3G24: only calm (Growth.is_calm without the wedge): a token holder on the cell refuses it.
func test_a_cell_that_is_not_calm_is_refused() -> void:
	var sim := _sim()
	_hold_unsettled(sim, WARM_TICKS)
	check_eq(sim.world.landmark_anchor, "", "nothing moved while held")
	sim.creatures.engaged_on_player = PackedStringArray(["c_hold"])
	check_eq(sim.world.landmark_candidate(sim, _anchor(sim)).reason, "not_calm", "not calm")
	sim.creatures.engaged_on_player.clear()
	check(sim.world.landmark_candidate(sim, _anchor(sim)).ok, "calm again: accepted")


## S3G24 (the mutation "accept with a live disc 10 tm away"): a loaded site of a species at the cell's
## size whose reach comes within respawn_clear_m of a cell at the point refuses it ("reach"); 12.5 tm
## off it does not.
func test_a_reach_disc_within_respawn_clear_m_refuses_the_point() -> void:
	var sim := _sim()
	_hold_unsettled(sim, WARM_TICKS)
	var w := sim.world
	var a := _anchor(sim)
	var r := w.landmark_candidate(sim, a)
	check(r.ok, "accepted with no site near (%s)" % r.reason)
	var p: Vector2 = r.point
	var clear := float(species.fairness.respawn_clear_m)
	var body := species.radius_at("elder_warden", 4) + sim.phenotype.radius
	check_eq(species.q_of("elder_warden", 4), 1.0, "an elder Warden is the cell's size at 4")
	for gap in [10.0, clear - 0.01, clear + 0.5]:
		w.sites["t_test"] = {"species": "elder_warden", "reach": {"center": p + Vector2(gap + 3.0 + body, 0.0), "radius": 3.0}}
		var got := w.landmark_candidate(sim, a)
		w.sites.erase("t_test")
		if gap < clear:
			check_eq(got.reason, "reach", "a disc %.2f tm from a cell there refuses it" % gap)
		else:
			check(got.ok, "a disc %.2f tm off does not (%s)" % [gap, got.reason])


## S3G24b: the point is spiralled once per anchor per size, however often it is asked for; a size
## change asks again.
func test_one_spiral_per_anchor_per_size() -> void:
	var sim := _sim()
	_hold_unsettled(sim, WARM_TICKS)
	var w := sim.world
	var a := _anchor(sim)
	var was := w._landmark_spirals
	for i in 4:
		w.landmark_candidate(sim, a)
	check_eq(w._landmark_spirals - was, 1, "one spiral for four asks")
	check(sim.debug_set_size(3) and sim.debug_set_size(4), "4 to 3 to 4")
	check(w._landmark_points.is_empty(), "the size change forgot the points")
	sim.motion.velocity = Vector2.ZERO
	w.landmark_candidate(sim, a)
	check_eq(w._landmark_spirals - was, 2, "a new spiral at the new size")


## S3G24d: an anchor under a collider out to 4 tm (the spiral's last ring) has no clear point within the bounded spiral:
## refused ("no_clear_point", memoised) and the checkpoint stays.
func test_a_blocked_anchor_is_refused_and_the_checkpoint_stays() -> void:
	var sim := _sim(4, Vector2(5.9, 0.0), true, true)
	var w := sim.world
	var before := w.checkpoint_am.duplicate()
	check(_moved(_run(sim, WARM_TICKS)).is_empty(), "no checkpoint_moved")
	check_eq(w.checkpoint_am, before, "the checkpoint unmoved")
	check_eq(w.landmark_candidate(sim, _anchor(sim)).reason, "no_clear_point", "no clear point")
	check(not is_finite(w._landmark_points.get(ANCHOR, PackedFloat64Array([0.0]))[0]), "memoised as none")


## S3G24d: with a chunk within D of the point not loaded the candidate is refused ("unloaded", never
## memoised); the pass accepts once the stream has loaded it again, not before.
func test_an_unloaded_chunk_within_d_waits_for_its_load() -> void:
	var sim := _sim()
	_hold_unsettled(sim, WARM_TICKS)
	var w := sim.world
	var a := _anchor(sim)
	var r := w.landmark_candidate(sim, a)
	check(r.ok, "accepted with everything loaded (%s)" % r.reason)
	var d := w._landmark_d
	check(d > 0.0, "D measured (%.2f tm)" % d)
	var near := w.chunk_of_local(sim.motion.position)
	var gone := Vector2i(999, 999)
	for key in w.disc_keys({"center": r.point, "radius": d}):
		if key != near:
			gone = key
			break
	check(w._chunks.has(gone), "a loaded chunk within D, not the cell's own (%s)" % gone)
	if not w._chunks.has(gone):
		return
	w._unload_chunk(sim, gone)
	sim.drain_events()
	check_eq(w.landmark_candidate(sim, a).reason, "unloaded", "refused while it is out")
	var loaded_at := -1
	var moved_at := -1
	for i in 120:
		for e in _run(sim, 1):
			if e.type == "chunk_loaded" and e.key == gone and loaded_at < 0:
				loaded_at = e.tick
			if e.type == "checkpoint_moved" and moved_at < 0:
				moved_at = e.tick
		if moved_at >= 0:
			break
	check(loaded_at >= 0, "the chunk loaded again")
	check(moved_at >= loaded_at and moved_at <= loaded_at + 1, "accepted once it loaded (loaded %d, moved %d)" % [loaded_at, moved_at])


## S3G24d (BP3-17): with landmark_return off the pass never runs.
func test_the_switch_off_means_no_pass() -> void:
	var sim := _sim(4, Vector2(4.0, 0.0), false)
	check(_moved(_run(sim, WARM_TICKS * 2)).is_empty(), "no checkpoint_moved")
	check_eq(sim.world.landmark_anchor, "", "no landmark")
	check_eq(sim.world._landmark_spirals, 0, "not even a spiral")
