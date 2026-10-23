extends TestCase
## WorldStream (S1 T2): the endless world's streaming block on FakeWorldGen (tests/fakes, spine
## 3.16), whose chunks each hold one shell, one zone per 2 x 2 chunks and one rammer site per 4 x 4.
## A new world loads its view set at once round the cell at the origin; chunks then load nearest
## first within the load ring and unload beyond the unload ring unless an awake creature's reach
## holds them; creatures sleep far from the cell and wake near it; and the snapshot's "world" block
## holds exactly the spine's keys.

const FakeWorldGen := preload("res://tests/fakes/fake_world_gen.gd")
const SEED := 4301
## The spine's "world" snapshot keys (3.12).
const WORLD_KEYS := ["checkpoint_am", "chunks", "counters", "cell_tile", "gen_version", "origin_am", "respawn_pending",
	"site_counts", "size", "sleeping", "slots", "zone_rngs"]
## Measured (S1 core 0.2): no view set holds more than 11 chunks.
const VIEW_SET_MAX := 11

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()


## An endless sim on the fake generator for a new omnivore lineage. `content` defaults to the
## fixture content (the world file's rings and caps, the home spawn).
func _endless(seed_value: int = SEED, content: WorldContent = null, with_species := true) -> PoolSim:
	return FakeWorldGen.endless_sim(seed_value, catalog, layout, species if with_species else null, content)


func _of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func test_create_loads_the_view_set_at_once_and_places_the_cell_at_the_origin() -> void:
	var sim := _endless()
	check(sim.is_endless(), "endless")
	check(sim.arena is ChunkArena, "the arena streams chunks")
	check_eq(sim.world.origin_x_am, 0.0, "origin x is the home spawn's")
	check_eq(sim.world.origin_y_am, 9.0, "origin y is the home spawn's")
	check_eq(sim.motion.position, Vector2.ZERO, "the cell at the origin (the spawn is clear on the fake)")
	check_eq(sim.absolute_position_am(), PackedFloat64Array([0.0, 9.0]), "its absolute place is the spawn")
	var view := sim.world.view_set_keys(sim.motion.position)
	var loaded := sim.world.loaded_keys()
	for key in view:
		check(loaded.has(key), "view-set chunk %s loaded" % key)
	check_eq(loaded, view, "exactly the view set, nothing more yet")
	check(view.size() >= 9 and view.size() <= VIEW_SET_MAX, "9 to 11 chunks (%d)" % view.size())
	for key in loaded:
		check(sim.world.chunk(key) != null and sim.world.chunk(key).key == key, "chunk %s kept" % key)
		check((sim.arena as ChunkArena).has_chunk(key), "chunk %s in the arena" % key)
	var events := sim.drain_events()
	var keys := []
	for e in _of(events, "chunk_loaded"):
		keys.append(e.key)
	check_eq(keys, Array(view), "one chunk_loaded per chunk, in (y, x) order, left for the scene")
	check_eq(events.size(), keys.size(), "and nothing else")
	# The zones of the loaded chunks are in the region, at their local places.
	var zones := 0
	for key in loaded:
		for z in sim.world.chunk(key).zones:
			zones += 1
			var rz := sim.region.zone(z.id)
			check(not rz.is_empty(), "zone %s in the region" % z.id)
			if not rz.is_empty():
				check_eq(rz.center, Vector2(float(z.x) - 0.0, float(z.y) - 9.0), "zone %s at its local place" % z.id)
	check(zones > 0, "the view set holds zones")
	check_eq(sim.region.zones.size(), zones, "and only those")
	# B-8: a save restored inside a shell (chunk (2, 0)'s, at (88, 24)) puts the cell 1.5 tm off the
	# origin, where the view set reaches one chunk further east: that chunk is loaded before the
	# first step too.
	var moved := FakeWorldGen.endless_sim(SEED, catalog, layout, species, null, PackedFloat64Array([88.0, 24.0]))
	var place := moved.motion.position
	check(place.length() > 1.0, "the cell moved off the shell (%s)" % place)
	var extra := moved.world.view_set_keys(place).filter(func(k: Vector2i) -> bool:
		return not moved.world.view_set_keys(Vector2.ZERO).has(k))
	check(not extra.is_empty(), "its view set reaches a chunk the origin's does not")
	for key in moved.world.view_set_keys(place):
		check(moved.world.chunk(key) != null, "view-set chunk %s of the placed cell loaded" % key)


func test_a_pool_sim_has_no_world() -> void:
	var r := Lineage.found(SEED, "test+dev", catalog, "omnivore")
	r.save.player["position"] = PlaneSpace.to_save(layout.spawn)
	var sim := PoolSim.create(r.save, catalog, layout, species)
	check(not sim.is_endless(), "pool")
	check(sim.world == null, "no stream")
	check(not sim.snapshot().has("world"), "no world block in the snapshot")
	check_eq(sim.absolute_position_am(), PackedFloat64Array([layout.spawn.x, layout.spawn.y]), "the absolute place is the local one")
	check_eq(sim.checkpoint().keys(), ["position", "heading"], "M1's checkpoint")


func test_the_checkpoint_is_the_home_spawn_in_the_current_frame() -> void:
	var sim := _endless()
	var cp := sim.checkpoint()
	check_eq(cp.position, Vector2.ZERO, "the spawn is the origin")
	check_eq(cp.x_am, 0.0, "x_am")
	check_eq(cp.y_am, 9.0, "y_am")
	check_eq(cp.size, 1, "size")
	check_near(float(cp.heading), -1.5708, 1e-9, "heading")


func test_the_world_snapshot_block_has_exactly_the_spine_keys() -> void:
	var sim := _endless()
	var snap := sim.snapshot()
	check(snap.has("world"), "a world block")
	var block: Dictionary = snap.get("world", {})
	var keys := block.keys()
	keys.sort()
	var want := WORLD_KEYS.duplicate()
	want.sort()
	check_eq(keys, want, "the spine's keys, no more")
	check_eq((block.counters as Dictionary).keys().size(), 4, "four counters")
	for k in ["awake_overflow", "chunk_waits", "food_trimmed", "evictions"]:
		check(block.counters.has(k), "counter %s" % k)
	check_eq(block.origin_am, [0.0, 9.0], "origin")
	check_eq(block.chunks.size(), sim.world.loaded_keys().size(), "every loaded chunk")
	check_eq(block.gen_version, 1, "gen_version")
	check_eq(block.respawn_pending, false, "no respawn pending")
	# The whole snapshot stays plain JSON (no Vector2 or Vector2i leaks into the hash string).
	check(JSON.parse_string(JSON.stringify(snap, "", true, true)) != null, "it round-trips through JSON")
	check(_no_vectors(snap), "no vectors in it")


func test_a_view_set_holds_at_most_eleven_chunks() -> void:
	_check_view_sets(1.0, 1)


func test_slow_a_view_set_holds_at_most_eleven_chunks_on_a_quarter_metre_grid() -> void:
	_check_view_sets(0.25, 7)


## The view set's margin from the data, not from WorldStream: the camera's look-ahead, the spawn
## view's safety gap and the largest zone radius (tile rule 3), so every zone touching the view plus
## its margin has its centre in a listed chunk (S1 core C-1).
func test_the_view_set_margin_is_the_look_ahead_the_gap_and_the_largest_zone() -> void:
	check_eq(_margin(), 11.5, "2.5 + 1.0 + 8.0")
	check_eq(WorldStream.VIEW_SET_MARGIN_TM, _margin(), "the stream's constant")


## The quad-to-square distance against Godot's own polygon geometry on hand-made cases: apart
## (corner to corner, edge to corner), crossing with no corner inside either way, one inside the other.
func test_the_quad_to_square_distance_is_exact() -> void:
	var cases := [
		# [quad, square x0, y0, side]
		[[Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)], 13.0, 14.0, 5.0],    # corner to corner: 5
		[[Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)], 2.0, 12.5, 5.0],     # edge: 2.5
		[[Vector2(-20, -1), Vector2(40, -1), Vector2(40, 1), Vector2(-20, 1)], 0.0, -16.0, 32.0],   # a band across: 0
		[[Vector2(-50, -50), Vector2(50, -50), Vector2(50, 50), Vector2(-50, 50)], 0.0, 0.0, 32.0],  # square inside: 0
		[[Vector2(1, 1), Vector2(3, 1), Vector2(3, 3), Vector2(1, 3)], 0.0, 0.0, 32.0],          # quad inside: 0
		[[Vector2(-30, 40), Vector2(30, 40), Vector2(10, 60), Vector2(-10, 60)], -16.0, -2.0, 32.0],  # trapezoid: 10
		# Apart along x only, an axis of the square's and not the diamond's: 1.
		[[Vector2(0, -10), Vector2(10, 0), Vector2(0, 10), Vector2(-10, 0)], 11.0, -5.0, 10.0],
		# Apart along a diamond edge's normal only: sqrt 2.
		[[Vector2(0, -10), Vector2(10, 0), Vector2(0, 10), Vector2(-10, 0)], 6.0, 6.0, 10.0],
	]
	for case in cases:
		var quad := PackedVector2Array(case[0])
		var want := _reference_distance(quad, case[1], case[2], case[3])
		var qx := PackedFloat64Array()
		var qy := PackedFloat64Array()
		for v in quad:
			qx.append(v.x)
			qy.append(v.y)
		var got := WorldStream._quad_square_distance(qx, qy, case[1], case[2], case[3])
		check_near(got, want, 1e-4, "case %s" % [case])
	check_near(_reference_distance(PackedVector2Array(cases[0][0]), 13.0, 14.0, 5.0), 5.0, 1e-5, "the reference itself")
	check_eq(_reference_distance(PackedVector2Array(cases[2][0]), 0.0, -16.0, 32.0), 0.0, "a crossing is 0")
	check_near(_reference_distance(PackedVector2Array(cases[6][0]), 11.0, -5.0, 10.0), 1.0, 1e-5, "x only")
	check_near(_reference_distance(PackedVector2Array(cases[7][0]), 6.0, 6.0, 10.0), sqrt(2.0), 1e-5, "the diamond's axis only")


func _margin() -> float:
	return float(layout.camera.look_ahead_max) + float(species.fairness.spawn_view_margin_m) + 8.0


## For every cell position on a `step` grid over one chunk: at most VIEW_SET_MAX keys, sorted (y,
## x), the 3 x 3 round the cell's chunk included, and (on every `every`-th position) exactly the 3 x
## 3 plus the chunks within the margin of the widest view, by an independent reference: Godot's
## polygon geometry on the view quad and each chunk square, with the margin from the data.
func _check_view_sets(step: float, every: int) -> void:
	var sim := _endless()
	var w := sim.world
	var aspect := float(species.fairness.spawn_view_aspect)
	var zoom_max := float(layout.camera.zoom_max)
	var margin := _margin()
	var worst := 0
	var bad := 0
	var first := ""
	var n := roundi(32.0 / step)
	var compared := 0
	var beyond := 0
	for iy in n:
		for ix in n:
			# Positions over chunk (0, 0) in absolute tm: local = abs - origin (0, 9).
			var p := Vector2(ix * step + 0.5 * step, iy * step + 0.5 * step) - Vector2(0.0, 9.0)
			var keys := w.view_set_keys(p)
			worst = maxi(worst, keys.size())
			var sorted := keys.duplicate()
			sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
			if sorted != keys:
				bad += 1
			var home := Vector2i(floori((p.x + 0.0) / 32.0), floori((p.y + 9.0) / 32.0))
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if not keys.has(home + Vector2i(dx, dy)):
						bad += 1
			if (ix + iy * n) % every != 0:
				continue
			compared += 1
			var quad := ViewFootprint.corners(p, layout.camera, zoom_max, aspect)
			for ky in range(home.y - 3, home.y + 4):
				for kx in range(home.x - 3, home.x + 4):
					var key := Vector2i(kx, ky)
					if absi(kx - home.x) <= 1 and absi(ky - home.y) <= 1:
						continue
					# The square in local tm: absolute minus the origin.
					var d := _reference_distance(quad, kx * 32.0 - 0.0, ky * 32.0 - 9.0, 32.0)
					if d <= margin - 1e-3 and not keys.has(key):
						bad += 1
						if first.is_empty():
							first = "%s missing at %s (%.3f)" % [key, p, d]
					elif d > margin + 1e-3 and keys.has(key):
						bad += 1
						if first.is_empty():
							first = "%s extra at %s (%.3f)" % [key, p, d]
					elif d > 0.0 and d <= margin:
						beyond += 1
	check(worst <= VIEW_SET_MAX, "at most %d keys (worst %d)" % [VIEW_SET_MAX, worst])
	check(worst <= int(w.caps.view_set_chunks), "within caps.view_set_chunks")
	check(compared >= 100, "the reference ran (%d positions)" % compared)
	check(beyond > 0, "some listed chunks lie outside the view, within the margin (%d)" % beyond)
	check_eq(bad, 0, "sorted, the 3 x 3 included, and exactly the view plus margin (%s)" % first)


## The distance between a convex quad and the square [x0, x0 + side] x [y0, y0 + side] by Godot's
## polygon geometry: 0 when they intersect or one holds the other, else the closest pair of edges.
static func _reference_distance(quad: PackedVector2Array, x0: float, y0: float, side: float) -> float:
	var square := PackedVector2Array([Vector2(x0, y0), Vector2(x0 + side, y0), Vector2(x0 + side, y0 + side),
		Vector2(x0, y0 + side)])
	if not Geometry2D.intersect_polygons(quad, square).is_empty():
		return 0.0
	if Geometry2D.is_point_in_polygon(quad[0], square) or Geometry2D.is_point_in_polygon(square[0], quad):
		return 0.0
	var best := INF
	for i in quad.size():
		for k in square.size():
			var pts := Geometry2D.get_closest_points_between_segments(quad[i], quad[(i + 1) % quad.size()],
				square[k], square[(k + 1) % square.size()])
			best = minf(best, pts[0].distance_to(pts[1]))
	return best


# --- load and unload (T2.2) ---

## A swim east then back west, checked every tick against the rules worked out here from the cell's
## absolute place: the chunks beyond 72 tm unload, in (y, x) order, then the nearest missing chunk
## within 56 tm loads (ties to the lower key), one a tick; unloads before loads; the arena, the
## region and the stream agree on what is loaded.
func test_chunks_load_nearest_first_one_a_tick_within_the_load_ring() -> void:
	var sim := _endless(SEED, null, false)
	sim.drain_events()
	var bad := 0
	var first := ""
	var loads := 0
	var unloads := 0
	for t in 3000:
		var dir := Vector2.RIGHT if t < 2000 else Vector2.LEFT
		var a := sim.absolute_position_am()
		var before := sim.world.loaded_keys()
		sim.step(SimIntent.new(dir))
		var events := sim.drain_events()
		var got_unloaded: Array = []
		var got_loaded: Array = []
		var order_ok := true
		for e in events:
			if e.type == "chunk_unloaded":
				got_unloaded.append(e.key)
				order_ok = order_ok and got_loaded.is_empty()
			elif e.type == "chunk_loaded":
				got_loaded.append(e.key)
		var want_unloaded: Array = []
		for key in before:
			if _ref_nearest(key, a[0], a[1]) > 72.0:
				want_unloaded.append(key)
		var after_unload := before.filter(func(k: Vector2i) -> bool: return not want_unloaded.has(k))
		var want_loaded: Array = []
		var best: Variant = _ref_nearest_missing(after_unload, a[0], a[1], 56.0)
		if best != null:
			want_loaded.append(best)
		loads += got_loaded.size()
		unloads += got_unloaded.size()
		var problem := ""
		if got_unloaded != want_unloaded:
			problem = "unloaded %s, want %s" % [got_unloaded, want_unloaded]
		elif got_loaded != want_loaded:
			problem = "loaded %s, want %s" % [got_loaded, want_loaded]
		elif not order_ok:
			problem = "a load before an unload"
		elif (sim.arena as ChunkArena).chunk_keys() != sim.world.loaded_keys():
			problem = "the arena holds %s" % [(sim.arena as ChunkArena).chunk_keys()]
		elif not _region_matches(sim):
			problem = "the region's zones differ from the loaded chunks'"
		if not problem.is_empty():
			bad += 1
			if first.is_empty():
				first = "tick %d at %s: %s" % [t, a, problem]
	check_eq(bad, 0, "every tick as the rules say (%s)" % first)
	check(loads >= 20 and unloads >= 10, "the swim loaded %d and unloaded %d" % [loads, unloads])
	# At the end, every chunk within the load ring is in.
	var a := sim.absolute_position_am()
	for key in _ref_keys_within(a[0], a[1], 56.0):
		check(sim.world.chunk(key) != null, "chunk %s within 56 tm loaded" % key)
	check_eq(sim.world.counters.chunk_waits, 0, "no waits under the cap")


## A chunk goes when its nearest point is farther than 72 tm from the body, not at 72 tm itself.
func test_a_chunk_unloads_only_beyond_72_tm() -> void:
	var sim := _endless(SEED, null, false)
	check(sim.world.chunk(Vector2i(0, 0)) != null, "chunk (0, 0) loaded at the start")
	# Chunk (0, 0) spans x 0 to 32: from (104, 16) its nearest point is 72 tm away.
	check(sim.debug_teleport(sim.world.local_of_abs(104.0, 16.0)), "the cell 72 tm east of the chunk")
	sim.drain_events()
	sim.world.step(sim)
	check(sim.world.chunk(Vector2i(0, 0)) != null, "kept at 72 tm")
	# The chunks the jump left beyond 72 tm went together, in (y, x) order.
	var gone: Array = []
	for e in _of(sim.drain_events(), "chunk_unloaded"):
		gone.append(e.key)
	var sorted := gone.duplicate()
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	check(gone.size() >= 2, "several at once (%d)" % gone.size())
	check_eq(gone, sorted, "unloads in (y, x) order")
	check(sim.debug_teleport(sim.world.local_of_abs(104.01, 16.0)), "and 72.01 tm east")
	sim.world.step(sim)
	check(sim.world.chunk(Vector2i(0, 0)) == null, "gone at 72.01 tm")
	check(_of(sim.drain_events(), "chunk_unloaded").any(func(e: Dictionary) -> bool: return e.key == Vector2i(0, 0)),
		"with its chunk_unloaded")


## Over the chunk cap only the view set loads: every other load waits and is counted once a tick.
## B-5: at the chunk cap the nearest missing view-set chunk loads in place of a nearer chunk outside
## the view set, and chunk_waits counts the give-way; with no view-set chunk missing the load waits
## and counts.
func test_at_the_chunk_cap_a_view_set_chunk_loads_in_place_of_a_nearer_one_and_counts() -> void:
	var sim := _endless(SEED, null, false)
	# Here the view set reaches 36.7 tm sideways, and the chunk two rows up is 32 tm off.
	check(sim.debug_teleport(Vector2(-14.0, -9.0)), "the cell placed")
	for t in 40:
		sim.step(SimIntent.new())
	var body := sim.motion.position
	var view := sim.world.view_set_keys(body)
	# The farthest view-set chunk, and a loaded chunk outside the view set nearer than it.
	var far_view: Vector2i = view[0]
	for key in view:
		if sim.world.nearest(key, body) > sim.world.nearest(far_view, body):
			far_view = key
	var near_other: Variant = null
	for key in sim.world.loaded_keys():
		if not view.has(key) and sim.world.nearest(key, body) < sim.world.nearest(far_view, body):
			if near_other == null or sim.world.nearest(key, body) < sim.world.nearest(near_other, body):
				near_other = key
	check(near_other != null, "a chunk outside the view set nearer than the view set's farthest")
	if near_other == null:
		return
	sim.world._unload_chunk(sim, far_view)
	sim.world._unload_chunk(sim, near_other)
	sim.world.caps.chunks = sim.world.loaded_keys().size()
	check_eq(sim.world._nearest_missing(body, 56.0), near_other, "the nearest missing chunk is the outsider")
	sim.drain_events()
	sim.step(SimIntent.new())
	var loaded := _of(sim.drain_events(), "chunk_loaded").map(func(e: Dictionary) -> Vector2i: return e.key)
	check_eq(loaded, [far_view], "the view-set chunk loaded in its place")
	check_eq(int(sim.world.counters.chunk_waits), 1, "and the give-way counted")
	sim.step(SimIntent.new())
	check(_of(sim.drain_events(), "chunk_loaded").is_empty(), "then nothing more: the view set is whole")
	check(sim.world.chunk(near_other) == null, "the outsider waits")
	check_eq(int(sim.world.counters.chunk_waits), 2, "and the wait counted")


## An awake creature's reach holds its chunks however far the cell swims; once it is gone they go.
func test_an_awake_creatures_leash_disc_holds_its_chunks() -> void:
	# No generated creatures: only the debug one holds ground.
	var content := FakeWorldGen.fixture_content()
	content.config.switches.generated_creatures = false
	var sim := _endless(SEED, content)
	sim.debug_set_ai_frozen(true)
	sim.drain_events()
	# A siteless debug rammer at the origin: its leash disc is its default territory plus the leash.
	var c := sim.creatures.spawn_at("rammer", Vector2(-6.0, 0.0), 0.0, "", sim.tick, true)
	check(c != null, "a debug creature")
	var disc := CreatureBrain.leash_disc(c.brain)
	var held := sim.world.disc_keys(disc)
	var center := sim.world.abs_of_local(disc.center)
	check(held.size() >= 2, "its disc spans %d chunks" % held.size())
	var a := sim.absolute_position_am()
	for t in 3000:
		sim.step(SimIntent.new(Vector2.RIGHT))
		a = sim.absolute_position_am()
		if a[0] - center[0] > 94.0:
			break
	check(a[0] > 80.0, "the cell swam far (%.1f)" % a[0])
	var out: Array[Vector2i] = []
	for key in held:
		if _ref_nearest(key, a[0], a[1]) > 72.0:
			out.append(key)
			check(sim.world.chunk(key) != null, "chunk %s, beyond the unload ring, still loaded: held by the creature" % key)
	check(out.size() >= 2, "chunks of its disc beyond the unload ring (%s)" % [out])
	for key in sim.world.loaded_keys():
		check(held.has(key) or _ref_nearest(key, a[0], a[1]) <= 72.0, "nothing else beyond 72 (%s)" % key)
	# Past the hold ring (B-6) its leash centre is let go: it leaves, unloaded, and its ground with it.
	sim.drain_events()
	var gone := -1
	for t in 200:
		var from := sim.absolute_position_am()
		sim.step(SimIntent.new(Vector2.RIGHT))
		if sim.creatures.find(c.id) == null:
			gone = t
			check(Vector2(from[0] - center[0], from[1] - center[1]).length() > 96.0, "let go only beyond 96 tm")
			break
	check(gone >= 0, "the creature let go")
	var removed := _of(sim.drain_events(), "creature_removed")
	check(removed.size() == 1 and removed[0].reason == "unloaded", "unloaded (%s)" % [removed])
	check(sim.creatures.queue.is_empty(), "a debug creature is not requeued")
	sim.step(SimIntent.new(Vector2.RIGHT))
	for key in out:
		check(sim.world.chunk(key) == null, "chunk %s unloaded on the next step" % key)


## Chunks at equal distance load in key order, (y, x): at a corner shared by four chunks they are
## all at distance 0.
func test_chunks_at_equal_distance_load_in_key_order() -> void:
	var sim := _endless(SEED, null, false)
	check(sim.debug_teleport(sim.world.local_of_abs(1024.0, 0.0)), "the cell on the corner of chunks (31, -1) to (32, 0)")
	check_eq(sim.absolute_position_am(), PackedFloat64Array([1024.0, 0.0]), "exactly")
	sim.drain_events()
	var loaded: Array = []
	for t in 4:
		sim.world.step(sim)
		for e in _of(sim.drain_events(), "chunk_loaded"):
			loaded.append(e.key)
	check_eq(loaded, [Vector2i(31, -1), Vector2i(32, -1), Vector2i(31, 0), Vector2i(32, 0)], "(y, x) order")


## The disc's chunks are exactly those whose square it reaches.
func test_disc_keys_are_the_chunks_a_disc_reaches() -> void:
	var sim := _endless(SEED, null, false)
	var center := Vector2(10.0, 2.0)   # abs (10, 11)
	var keys := sim.world.disc_keys({"center": center, "radius": 23.0})
	var want: Array[Vector2i] = []
	for ky in range(-3, 4):
		for kx in range(-3, 4):
			if _ref_nearest(Vector2i(kx, ky), 10.0, 11.0) <= 23.0:
				want.append(Vector2i(kx, ky))
	check_eq(keys, want, "the keys whose square lies within 23 tm of (10, 11)")
	check(want.size() >= 4 and want.size() < 49, "a real subset (%d)" % want.size())


## A chunk that loads under a body pushes it out of its new colliders: the cell and an awake creature.
func test_a_loaded_chunk_settles_the_cell_and_awake_bodies_out_of_new_shells() -> void:
	var sim := _endless()
	sim.debug_set_ai_frozen(true)
	sim.drain_events()
	# Chunk (5, 0)'s shell is at abs (184, 24): put the cell on it before the chunk loads.
	var shell := sim.world.local_of_abs(184.0, 24.0)
	check(sim.world.chunk(Vector2i(5, 0)) == null, "the chunk is not loaded")
	check(sim.debug_teleport(shell), "the cell is placed on the shell's centre")
	# And a frozen debug creature on chunk (5, 1)'s shell (abs (184, 56)).
	var other := sim.world.local_of_abs(184.0, 56.0)
	var c := sim.creatures.spawn_at("rammer", other, 0.0, "", sim.tick, true)
	var r := FakeWorldGen.SHELL_R
	# The streaming block alone, so the M1 move after it cannot be what frees them. (5, 0) loads
	# first (distance 0), then (6, 0) and (5, 1), both at 8 tm, in key order.
	for t in 3:
		sim.world.step(sim)
	check(sim.world.chunk(Vector2i(5, 0)) != null and sim.world.chunk(Vector2i(5, 1)) != null, "both chunks loaded")
	check(sim.motion.position.distance_to(shell) >= r + sim.phenotype.radius - 1e-4,
		"the cell is out of the shell (%.3f)" % sim.motion.position.distance_to(shell))
	check(sim.arena.is_clear(sim.motion.position, sim.phenotype.radius), "and clear")
	check_eq(sim.actor.position, sim.motion.position, "its actor follows")
	check(c.motion.position.distance_to(other) >= r + c.phenotype.radius - 1e-4,
		"the creature is out of its shell (%.3f)" % c.motion.position.distance_to(other))
	check_eq(c.actor.position, c.motion.position, "its actor follows")


## A chunk's events carry its content in the frame in force: shells, zones and the key.
func test_chunk_events_carry_the_chunks_content_in_local_tm() -> void:
	var sim := _endless(SEED, null, false)
	var events := sim.drain_events()
	var gen := FakeWorldGen.new(sim.world.content, null, SEED)
	var seen := 0
	for e in _of(events, "chunk_loaded"):
		var ch := gen.chunk(1, e.key.x, e.key.y)
		check_eq(e.shells.size(), ch.shells.size(), "shells of %s" % e.key)
		for i in ch.shells.size():
			var s: Dictionary = ch.shells[i]
			check_eq(e.shells[i].id, s.id, "shell id")
			check_eq(e.shells[i].position, Vector2(s.x - 0.0, s.y - 9.0), "shell position local")
			check_eq(e.shells[i].radius, s.r, "shell radius")
			check_eq(e.shells[i].asset, s.asset, "shell asset")
		check_eq(e.zones.size(), ch.zones.size(), "zones of %s" % e.key)
		for i in ch.zones.size():
			check_eq(e.zones[i].center, Vector2(ch.zones[i].x - 0.0, ch.zones[i].y - 9.0), "zone centre local")
			check_eq(e.zones[i].region, "sunlit", "zone region")
		seen += 1
	check(seen >= 9, "checked %d chunks" % seen)


## B-15: a chunk_loaded place carries the place's yaw and mirror, and its position in local tm.
func test_chunk_events_carry_places_with_their_yaw_and_mirror() -> void:
	var sim := _endless(SEED, null, false)
	var key := FakeWorldGen.PLACE_CHUNK
	var centre := Vector2(32.0 * key.x + 16.0, 32.0 * key.y + 16.0)
	check(sim.debug_teleport_abs(centre.x + 10.0, centre.y), "beside the place")
	var places := []
	for e in _of(sim.drain_events(), "chunk_loaded"):
		if e.key == key:
			places = e.places
	check_eq(places.size(), 1, "the chunk's place")
	if places.size() == 1:
		check_eq(places[0].id, "p_f_husk", "id")
		check_eq(places[0].kind, "giant_husk", "kind")
		check_eq(places[0].yaw_deg, FakeWorldGen.PLACE_YAW, "yaw_deg")
		check_eq(places[0].mirror, true, "mirror")
		check_eq(places[0].position, Vector2(-10.0, 0.0), "local position")


## Events keep the frame of their place in the drained list: a chunk_loaded after a rebased is in
## the new frame, one before it in the old (spine 3.12). Drained once after a long swim.
func test_chunk_events_carry_positions_in_the_frame_of_their_place() -> void:
	var sim := _endless(SEED, null, false)
	var ox := sim.world.origin_x_am
	var oy := sim.world.origin_y_am
	sim.drain_events()
	for t in 3000:
		sim.step(SimIntent.new(Vector2.RIGHT))
	var rebases := 0
	var loads_after := 0
	var bad := 0
	for e in sim.drain_events():
		if e.type == "rebased":
			check_eq(e.offset_tm, Vector2(e.origin_am[0] - ox, e.origin_am[1] - oy), "the offset is the origin's move")
			ox = e.origin_am[0]
			oy = e.origin_am[1]
			rebases += 1
		elif e.type == "chunk_loaded":
			var ch := sim.world.gen.chunk(1, e.key.x, e.key.y)
			for i in ch.shells.size():
				if e.shells[i].position != Vector2(float(ch.shells[i].x) - ox, float(ch.shells[i].y) - oy):
					bad += 1
			for i in ch.zones.size():
				if e.zones[i].center != Vector2(float(ch.zones[i].x) - ox, float(ch.zones[i].y) - oy):
					bad += 1
			if rebases > 0:
				loads_after += 1
	check(rebases >= 1, "the swim rebased (%d)" % rebases)
	check(loads_after > 0, "chunks loaded after a rebase in the same drain (%d)" % loads_after)
	check_eq(bad, 0, "every payload in the frame in force at its place")


## Unloading forgets a chunk and reloading rebuilds it: one chunk per key in the arena, one zone per
## id in the region, each with its own seeded stream (G14 for chunks and zones).
func test_unload_and_reload_leave_no_duplicates_and_seed_each_zone_stream() -> void:
	var sim := _endless(SEED, null, false)
	var counts := {}
	var tally := func(events: Array[Dictionary]) -> void:
		for e in events:
			if e.type == "chunk_loaded":
				counts[e.key] = int(counts.get(e.key, 0)) + 1
			elif e.type == "chunk_unloaded":
				counts[e.key] = int(counts.get(e.key, 0)) - 1
	tally.call(sim.drain_events())
	var start := sim.world.loaded_keys()
	for t in 4200:
		sim.step(SimIntent.new(Vector2.RIGHT if t < 2100 else Vector2.LEFT))
		tally.call(sim.drain_events())
	for key in counts:
		check_eq(int(counts[key]), 1 if sim.world.chunk(key) != null else 0, "chunk %s: loads minus unloads" % key)
	var ids := {}
	for z in sim.region.zones:
		check(not ids.has(z.id), "zone %s once" % z.id)
		ids[z.id] = true
	check(_region_matches(sim), "the region holds the loaded chunks' zones")
	var reloaded := 0
	for key in start:
		if sim.world.chunk(key) != null and counts.has(key):
			reloaded += 1
	check(reloaded > 0, "some starting chunks came back")
	# Every loaded zone draws from its own stream, seeded from (seed, generator version, zone id); a
	# reloaded zone's stream starting over is test_food_view's (its first anchors repeat).
	var block: Dictionary = sim.snapshot().world
	check_eq(block.zone_rngs.size(), sim.region.zones.size(), "a stream per loaded zone")
	for z in sim.region.zones:
		var stream: RandomNumberGenerator = sim.region.streams.get(z.id)
		check(stream != null, "zone %s has a stream" % z.id)
		if stream != null:
			check_eq(stream.seed, WorldHash.hash_ints(PackedInt64Array([SEED, 1, WorldHash.str32(z.id), WorldHash.str32("plankton")])),
				"zone %s's seed" % z.id)
			check_eq(block.zone_rngs[z.id], stream.state, "its state in the snapshot")


## Step 6 ends with tile_entered when the cell's tile (64 tm at size 1) changed: once, on the first
## tick the body is in the new tile, with the generator's region and rare kind.
func test_tile_entered_fires_once_when_the_cell_crosses_into_a_new_tile() -> void:
	var sim := _endless(SEED, null, false)
	sim.drain_events()
	var entered: Array[Dictionary] = []
	var crossed_at := -1
	for t in 1800:
		var a := sim.absolute_position_am()
		if crossed_at < 0 and a[0] >= 64.0:
			crossed_at = t
		sim.step(SimIntent.new(Vector2.RIGHT))
		for e in _of(sim.drain_events(), "tile_entered"):
			e["at"] = t
			entered.append(e)
	check(crossed_at > 0, "the cell crossed x = 64")
	check_eq(entered.size(), 1, "one tile_entered")
	if entered.size() == 1:
		check_eq(entered[0].tile, Vector2i(1, 0), "tile (1, 0)")
		check_eq(entered[0].region, "sunlit", "the generator's region")
		check_eq(entered[0].rare, "", "no rare kind")
		check_eq(int(entered[0].at), crossed_at, "on the first tick in it")
	check_eq(sim.snapshot().world.cell_tile, [1, 0], "the snapshot's cell_tile")


func _region_matches(sim: PoolSim) -> bool:
	var want := []
	for key in sim.world.loaded_keys():
		for z in sim.world.chunk(key).zones:
			want.append(z.id)
	want.sort()
	var got := []
	for z in sim.region.zones:
		got.append(z.id)
	got.sort()
	return got == want


## The distance from the absolute point (x, y) to chunk `key`'s square, in float64 (a Vector2 would
## round it to float32 and tie keys that are not tied).
static func _ref_nearest(key: Vector2i, x: float, y: float) -> float:
	var dx := x - clampf(x, key.x * 32.0, key.x * 32.0 + 32.0)
	var dy := y - clampf(y, key.y * 32.0, key.y * 32.0 + 32.0)
	return sqrt(dx * dx + dy * dy)


static func _ref_keys_within(x: float, y: float, ring: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ky in range(floori(y / 32.0) - 4, floori(y / 32.0) + 5):
		for kx in range(floori(x / 32.0) - 4, floori(x / 32.0) + 5):
			if _ref_nearest(Vector2i(kx, ky), x, y) <= ring:
				out.append(Vector2i(kx, ky))
	return out


## The missing key nearest (x, y) within `ring`: least distance, then y, then x.
static func _ref_nearest_missing(loaded: Array, x: float, y: float, ring: float) -> Variant:
	var cands := _ref_keys_within(x, y, ring).filter(func(k: Vector2i) -> bool: return not loaded.has(k))
	if cands.is_empty():
		return null
	cands.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
		var dp := _ref_nearest(p, x, y)
		var dq := _ref_nearest(q, x, y)
		if dp != dq:
			return dp < dq
		return p.y < q.y or (p.y == q.y and p.x < q.x))
	return cands[0]


static func _no_vectors(value: Variant) -> bool:
	match typeof(value):
		TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_OBJECT:
			return false
		TYPE_DICTIONARY:
			for k in value:
				if not _no_vectors(value[k]):
					return false
		TYPE_ARRAY:
			for v in value:
				if not _no_vectors(v):
					return false
	return true


# --- sleep and wake (T2.6) ---

## A sim with no generated creatures and the AI frozen, so a test places site creatures (_site_creature)
## where it wants them and they stay there, calm (a frozen brain keeps its starting rest). It waits
## until every chunk within the load ring has loaded.
func _quiet() -> PoolSim:
	var content := FakeWorldGen.fixture_content()
	content.config.switches.generated_creatures = false
	var sim := _endless(SEED, content)
	sim.debug_set_ai_frozen(true)
	for t in 40:
		sim.step(SimIntent.new())
	sim.drain_events()
	return sim


## A rammer site of its own homed at local `home` (in the chunk under it, which must be loaded),
## entered into the site table with the caps recomputed, and its creature spawned now: awake unless
## `asleep`.
func _site_creature(sim: PoolSim, id: String, home: Vector2, asleep := false) -> CreatureField.Creature:
	var a := sim.world.abs_of_local(home)
	var key := sim.world.chunk_of_local(home)
	check(sim.world.chunk(key) != null, "the home chunk of %s is loaded" % id)
	var s := {"id": id, "species": "rammer", "x": a[0], "y": a[1], "heading": 0.0,
		"territory": {"x": a[0], "y": a[1], "radius": 3.0}, "reach": {"x": a[0], "y": a[1], "radius": 6.0},
		"chunks": [key] as Array[Vector2i], "sizes": [1] as Array[int], "tile": Vector2i.ZERO}
	sim.world.sites[id] = sim.world._site_record(s, key)
	sim.world.recompute_caps(sim)
	var c := sim.creatures.spawn_site(sim.world.sites[id], sim.tick, asleep)
	check(c != null and c.asleep == asleep, "%s spawned %s" % [id, "asleep" if asleep else "awake"])
	return c


## The think slots agree with the creatures: each slot's count is the awake creatures on it, and no
## sleeper holds one.
func _check_slots(sim: PoolSim, where: String) -> void:
	var counts := [0, 0, 0, 0, 0, 0]
	for c in sim.creatures.creatures:
		if c.asleep:
			check_eq(c.think_slot, -1, "%s: sleeper %s holds no slot" % [where, c.id])
		elif c.think_slot >= 0:
			counts[c.think_slot] += 1
	check_eq(Array(sim.creatures._slot_counts), counts, "%s: slot counts" % where)


## Whether a body at `p` of radius `r` is in the widest view of `place` grown by the spawn margin.
func _in_view(sim: PoolSim, place: Vector2, p: Vector2, r: float) -> bool:
	var margin := float(layout.camera.look_ahead_max) + float(species.fairness.spawn_view_margin_m) + r
	return ViewFootprint.contains(place, p, layout.camera, float(layout.camera.zoom_max), float(species.fairness.spawn_view_aspect), margin)


## Spine 3.11 step 3 and D-9: an awake, held site creature's reach chunks stay loaded past the
## unload ring for as long as it is awake and its reach centre lies within the hold ring (96 tm);
## once it sleeps they unload on the next tick, its site and its creature with them.
func test_a_chunk_under_an_awake_creatures_reach_disc_stays_loaded() -> void:
	var sim := _quiet()
	var c := _site_creature(sim, "x_hold", Vector2(-20.0, 0.0))
	var key := sim.world.chunk_of_local(c.motion.position)
	var reach: Dictionary = sim.world.sites["x_hold"].abs.reach
	sim.world.rings.wake = 990.0   # a config copy: it cannot sleep while the cell swims away
	sim.world.rings.sleep = 1000.0
	var beyond := 0
	var held_out := 0.0
	for t in 2400:
		sim.step(SimIntent.new(Vector2.RIGHT))
		var a := sim.absolute_position_am()
		held_out = Vector2(a[0] - float(reach.x), a[1] - float(reach.y)).length()
		if _ref_nearest(key, a[0], a[1]) > 72.0:
			beyond += 1
		if held_out > 94.0:
			break
	check(beyond >= 20, "%d ticks with its chunk beyond the unload ring" % beyond)
	check(held_out < 96.0, "its reach centre within the hold ring (%.2f tm)" % held_out)
	check(sim.creatures.find(c.id) == c, "it is still there")
	check(sim.world.chunk(key) != null, "held while it is awake")
	sim.world.rings.wake = 40.0
	sim.world.rings.sleep = 44.0
	sim.drain_events()
	sim.step(SimIntent.new())
	check(c.asleep, "it sleeps")
	check(sim.world.chunk(key) != null, "the chunk is still there on its sleeping tick (step 3 ran first)")
	sim.step(SimIntent.new())
	check(sim.world.chunk(key) == null, "and gone on the next")
	check(not sim.world.sites.has("x_hold"), "the site with it")
	var removed := _of(sim.drain_events(), "creature_removed")
	check(removed.size() == 1 and removed[0].id == c.id and removed[0].reason == "unloaded", "its sleeper left, unloaded")


## B-6, the hold pass: an awake site creature (kept from sleeping) whose reach centre lies beyond the
## hold ring of the cell leaves, "unloaded", out of view, in step 5 of the first tick that holds it
## beyond 96 tm; its site is refilled at once as a sleeper (no respawn delay), and on the next tick
## step 3 releases its ground, the sleeper and the site with it.
func test_a_creature_held_beyond_the_hold_ring_is_let_go_and_its_chunks_unload() -> void:
	var sim := _quiet()
	var c := _site_creature(sim, "x_far", Vector2(-20.0, 0.0))
	c.brain.state = "wander"   # not calm (a frozen brain keeps it), so it never sleeps
	c.brain.phase = "return"
	var key := sim.world.chunk_of_local(c.motion.position)
	var reach: Dictionary = sim.world.sites["x_far"].abs.reach
	var counts_before := int(sim.world.site_counts.get("x_far", 0))
	sim.drain_events()
	var gone := -1
	var from := PackedFloat64Array()
	var events: Array[Dictionary] = []
	for t in 3000:
		from = sim.absolute_position_am()
		var tick := sim.tick
		sim.step(SimIntent.new(Vector2.RIGHT))
		events = sim.drain_events()
		var d := Vector2(from[0] - float(reach.x), from[1] - float(reach.y)).length()
		if sim.creatures.find(c.id) == null:
			gone = tick
			check(d > 96.0, "let go beyond the hold ring (%.3f tm)" % d)
			break
		check(d <= 96.0 + 1e-3, "held until then (%.3f tm at tick %d)" % [d, tick])
		check(sim.world.chunk(key) != null, "its chunk held while it is")
	check(gone >= 0, "the creature was let go")
	var removed := _of(events, "creature_removed")
	check(removed.size() == 1 and removed[0].id == c.id and removed[0].reason == "unloaded", "unloaded (%s)" % [removed])
	if removed.size() == 1:
		var off: Vector2 = removed[0].position - sim.motion.position
		check(off.length() >= 85.0, "%.1f tm from the cell" % off.length())
		check(not _in_view(sim, sim.motion.position, removed[0].position, c.phenotype.radius), "out of view")
	var spawned := _of(events, "creature_spawned")
	check(spawned.size() == 1 and spawned[0].site == "x_far" and spawned[0].asleep, "refilled at once as a sleeper (%s)" % [spawned])
	check_eq(int(sim.world.site_counts.get("x_far", 0)), counts_before + 1, "one more spawn of the site")
	check(sim.world.chunk(key) != null, "its chunk still there on the tick it was let go (step 3 ran first)")
	sim.step(SimIntent.new(Vector2.RIGHT))
	check(sim.world.chunk(key) == null, "and released on the next")
	check(not sim.world.sites.has("x_far"), "the site with it")
	removed = _of(sim.drain_events(), "creature_removed")
	check(removed.size() == 1 and removed[0].reason == "unloaded", "its sleeper left, unloaded (%s)" % [removed])


## G14: out 100 tm, back and out again through a site in every chunk: every creature_spawned id is
## new, and the site counts rise by exactly one per spawn.
func test_no_creature_id_is_spawned_twice_across_sleep_wake_unload_and_reload() -> void:
	var sim := FakeWorldGen.endless_sim(SEED, catalog, layout, species, null, PackedFloat64Array(), 1)
	sim.debug_set_hidden(true)
	var before := 0
	for site in sim.world.site_counts:
		before += int(sim.world.site_counts[site])
	check(before > 0, "creatures at create (%d)" % before)
	var ids := {}
	for c in sim.creatures.creatures:
		ids[c.id] = true
	var spawns := 0
	var again := 0
	var counts := {"creature_slept": 0, "creature_woke": 0, "chunk_unloaded": 0}
	for t in 5400:
		var leg := t / 1800
		var dir := Vector2.RIGHT if leg != 1 else Vector2.LEFT
		sim.step(SimIntent.new(dir))
		for e in sim.drain_events():
			if counts.has(e.type):
				counts[e.type] += 1
			if e.type == "creature_spawned" and not e.debug:
				spawns += 1
				if ids.has(e.id):
					again += 1
				ids[e.id] = true
	var total := 0
	for site in sim.world.site_counts:
		total += int(sim.world.site_counts[site])
	check_eq(again, 0, "no id spawned twice (%d spawns)" % spawns)
	check_eq(total - before, spawns, "the site counts rose once per spawn")
	check(spawns >= 20, "%d spawns" % spawns)
	for type in counts:
		check(int(counts[type]) > 0, "%d %s" % [counts[type], type])


## Spine 3.11 step 5: a calm awake creature sleeps on the first tick it is beyond the sleep ring, out
## of view and not a token holder, and not a tick before.
func test_a_calm_creature_beyond_44_tm_and_out_of_view_sleeps() -> void:
	var sim := _quiet()
	var c := _site_creature(sim, "x_calm", Vector2(30.0, 0.0))
	var r := c.phenotype.radius
	var slept_at := -1
	var early := 0
	for t in 600:
		var d := sim.motion.position.distance_to(c.motion.position)
		var due := d > 44.0 and not _in_view(sim, sim.motion.position, c.motion.position, r) \
			and not sim.creatures.engaged_on_player.has(c.id)
		sim.step(SimIntent.new(Vector2.LEFT))
		if c.asleep and not due:
			early += 1
		if due:
			slept_at = t if c.asleep else -2
			break
	check_eq(early, 0, "not before")
	check(slept_at >= 0, "it slept on the first tick it was due (%d)" % slept_at)
	check(slept_at > 60, "after a swim (%d ticks)" % slept_at)
	check_eq(Array(sim.world.sleeping_ids()), [c.id], "sleeping_ids")
	_check_slots(sim, "after its sleep")


## Not calm (chasing, watching or going home) or holding the token: awake at 50 tm.
func test_a_creature_that_is_not_calm_or_holds_a_token_stays_awake() -> void:
	var sim := _quiet()
	var c := _site_creature(sim, "x_busy", Vector2(50.0, 0.0))
	for pair in [["chase", "pursue"], ["rest", "watch"], ["wander", "return"], ["attack", "tell"], ["flee", ""]]:
		c.brain.state = pair[0]
		c.brain.phase = pair[1]
		sim.step(SimIntent.new())
		check(not c.asleep, "%s/%s stays awake" % pair)
	c.brain.state = "rest"
	c.brain.phase = ""
	sim.creatures.engaged_on_player.append(c.id)
	sim.step(SimIntent.new())
	check(not c.asleep, "a token holder stays awake")
	sim.creatures.engaged_on_player.remove_at(sim.creatures.engaged_on_player.find(c.id))
	sim.step(SimIntent.new())
	check(c.asleep, "calm and without the token it sleeps")


## A sleeper wakes inside the wake ring (one beyond it stays asleep), and each waker takes the think
## slot with the fewest awake creatures, ties to the lowest: after 24 wakes the slots hold 4 each.
func test_a_sleeper_wakes_inside_40_tm_or_in_view_and_takes_the_emptiest_slot() -> void:
	var sim := _quiet()
	sim.world.caps.awake = 30
	sim.world.caps.sleepers = 40
	var near: Array[CreatureField.Creature] = []
	var far: Array[CreatureField.Creature] = []
	for i in 24:
		var p := Vector2.from_angle(i * TAU / 24.0) * (10.0 + i)
		near.append(_site_creature(sim, "x_n%02d" % i, p, true))
	for i in 6:
		far.append(_site_creature(sim, "x_f%d" % i, Vector2.from_angle(i * TAU / 6.0 + 0.3) * (41.0 + 2.0 * i), true))
	check(sim.creatures.awake().is_empty(), "everyone asleep")
	sim.drain_events()
	sim.step(SimIntent.new())
	var woke := _of(sim.drain_events(), "creature_woke")
	check_eq(woke.size(), 24, "the 24 inside the wake ring woke")
	var model := [0, 0, 0, 0, 0, 0]
	var wrong := 0
	for e in woke:
		var want := model.find(model.min())
		if int(e.slot) != want:
			wrong += 1
		model[want] += 1
	check_eq(wrong, 0, "each took the emptiest slot, ties to the lowest")
	check_eq(Array(sim.creatures._slot_counts), [4, 4, 4, 4, 4, 4], "equal")
	for c in near:
		check(not c.asleep, "%s awake" % c.id)
		check(c.brain.wake, "%s re-decides on its first think" % c.id)
	_check_slots(sim, "after 24 wakes")
	for c in far:
		check(c.asleep, "%s, %.1f tm out, still asleep" % [c.id, c.motion.position.length()])


## C-7: a sleeper lies still (no velocity, its previous pose its pose, an idle drive), and no awake
## brain keeps it in mind.
func test_a_sleeper_lies_still_and_no_brain_keeps_it_as_a_target() -> void:
	var sim := _quiet()
	var c := _site_creature(sim, "x_still", Vector2(50.0, 0.0))
	var other := _site_creature(sim, "x_mind", Vector2(10.0, 0.0))
	other.brain.state = "chase"
	other.brain.phase = "pursue"
	other.brain.target = c.id
	other.brain.seen[c.id] = {"position": c.motion.position, "velocity": Vector2.ZERO, "tick": sim.tick, "by": "sight",
		"species": "rammer", "radius": c.phenotype.radius, "engageable": true}
	other.brain.landed_on[c.id] = sim.tick
	c.brain.seen[other.id] = {"position": other.motion.position, "velocity": Vector2.ZERO, "tick": sim.tick, "by": "sight",
		"species": "rammer", "radius": other.phenotype.radius, "engageable": true}
	c.motion.velocity = Vector2(1.0, 0.5)
	c.motion.prev_position = c.motion.position - Vector2(0.1, 0.0)
	c.motion.prev_heading = c.motion.heading + 0.2
	c.drive = {"mode": CreatureBrain.MODE_STEER, "move": Vector2.RIGHT, "speed_mul": 1.0, "face": 0.5, "strike": false,
		"target": "", "feed": ""}
	sim.step(SimIntent.new())
	check(c.asleep, "it sleeps")
	check_eq(c.motion.velocity, Vector2.ZERO, "still")
	check_eq(c.motion.prev_position, c.motion.position, "no motion to interpolate")
	check_eq(c.motion.prev_heading, c.motion.heading, "nor a turn")
	check_eq(c.drive, CreatureField.idle_drive(c.motion.heading), "an idle drive")
	check(not other.brain.seen.has(c.id), "forgotten")
	check(not other.brain.landed_on.has(c.id), "its hits too")
	check(other.brain.target != c.id, "not a target")
	check(not sim.creatures.engaged_on_player.has(c.id), "no token")
	check(c.brain.seen.is_empty(), "and it forgets what it had seen (B-21)")


## G17: a sleeper is not among the bodies the senses read.
func test_sleepers_are_not_among_the_bodies() -> void:
	var sim := _quiet()
	var c := _site_creature(sim, "x_sleeper", Vector2(50.0, 0.0))
	var awake := _site_creature(sim, "x_awake", Vector2(10.0, 0.0))
	sim.step(SimIntent.new())
	check(c.asleep and not awake.asleep, "one asleep, one awake")
	var ids := sim.creatures.bodies({}).map(func(b: Dictionary) -> String: return b.id)
	check(not ids.has(c.id), "no sleeper among the bodies")
	check(ids.has(awake.id), "the awake one is")
	check(not sim.creatures.awake().has(c), "nor among the awake")


## Spine 3.11 step 4.1: on the tick a sleeper wakes, every chunk its site lists is loaded first.
func test_a_wakers_reach_chunks_load_before_it_wakes() -> void:
	var sim := _quiet()
	var c := _site_creature(sim, "x_waker", Vector2(60.0, 0.0), true)
	var far_key := sim.world.chunk_of_local(Vector2(0.0, -200.0))
	check(sim.world.chunk(far_key) == null, "a far chunk, not loaded")
	sim.world.sites["x_waker"].chunks = [sim.world.chunk_of_local(c.motion.position), far_key] as Array[Vector2i]
	c.motion.place(Vector2(30.0, 0.0), 0.0)   # inside the wake ring now
	sim.drain_events()
	sim.step(SimIntent.new())
	check(not c.asleep, "it woke")
	var order: Array = []
	for e in sim.drain_events():
		if (e.type == "chunk_loaded" and e.key == far_key) or e.type == "creature_woke":
			order.append(e.type)
	check_eq(order, ["chunk_loaded", "creature_woke"], "its chunk loaded first")
	check(sim.world.chunk(far_key) != null, "and is loaded")
	sim.step(SimIntent.new())
	check(sim.world.chunk(far_key) != null, "held while it is awake")


## Over caps.awake the farthest calm creature between the rings sleeps (ties by id), one at a time;
## with none there awake_overflow counts once a tick.
func test_awake_overflow_sleeps_the_farthest_calm_creature_in_the_band_or_counts() -> void:
	var sim := _quiet()
	sim.world.caps.awake = 2
	sim.world.caps.sleepers = 2
	var a := _site_creature(sim, "x_a41", Vector2(41.0, 0.0))
	var b := _site_creature(sim, "x_b43", Vector2(0.0, -43.0))
	var d := _site_creature(sim, "x_d43", Vector2(-43.5, 0.0))
	var near := _site_creature(sim, "x_near", Vector2(0.0, 20.0))
	d.brain.state = "chase"   # not calm: never picked
	d.brain.phase = "pursue"
	sim.drain_events()
	sim.step(SimIntent.new())
	var slept := _of(sim.drain_events(), "creature_slept").map(func(e: Dictionary) -> String: return e.id)
	check_eq(slept, [b.id, a.id], "the farthest calm one first, then the next")
	check(not d.asleep and not near.asleep, "the busy one and the near one stay awake")
	check_eq(int(sim.world.counters.awake_overflow), 0, "no overflow")
	# Now none is in the band: d is busy, near is inside the wake ring.
	near.motion.place(Vector2(0.0, 10.0), 0.0)
	var c2 := _site_creature(sim, "x_c2", Vector2(15.0, 5.0))
	for t in 3:
		sim.step(SimIntent.new())
	check_eq(sim.creatures.awake().size(), 3, "three awake over a cap of 2")
	check_eq(int(sim.world.counters.awake_overflow), 3, "counted once a tick")
	check(not c2.asleep, "c2 awake")


## Over caps.sleepers the farthest sleeper is evicted ("evicted") and its site waits its hashed
## respawn delay.
func test_sleeper_eviction_removes_the_farthest_and_requeues_it_with_its_hashed_delay() -> void:
	var sim := _quiet()
	sim.world.caps.awake = 2
	sim.world.caps.sleepers = 2
	var s45 := _site_creature(sim, "x_s45", Vector2(45.0, 0.0), true)
	var s55 := _site_creature(sim, "x_s55", Vector2(0.0, 55.0), true)
	var s50 := _site_creature(sim, "x_s50", Vector2(-50.0, 0.0), true)
	var delay := sim.creatures.respawn_delay_for(s55)
	sim.drain_events()
	var at := sim.tick
	sim.step(SimIntent.new())
	var removed := _of(sim.drain_events(), "creature_removed")
	check(removed.size() == 1 and removed[0].id == s55.id and removed[0].reason == "evicted", "the farthest evicted")
	check(sim.creatures.find(s45.id) != null and sim.creatures.find(s50.id) != null, "the others kept")
	check_eq(int(sim.world.counters.evictions), 1, "counted")
	var entry: Array = sim.creatures.queue.filter(func(e: Dictionary) -> bool: return e.site == "x_s55")
	check_eq(entry.size(), 1, "its site queued")
	if entry.size() == 1:
		check_eq(int(entry[0].at_tick), at + delay, "at its hashed delay")
	check(sim.world.sites.has("x_s55"), "the site stays in the table")


## Two sleepers over the cap in one tick: both farthest go, and the step returns (an evicted
## creature left among the candidates was picked again forever).
func test_two_sleepers_over_the_cap_are_both_evicted_in_one_tick() -> void:
	var sim := _quiet()
	sim.world.caps.awake = 2
	sim.world.caps.sleepers = 1
	var s45 := _site_creature(sim, "x_s45", Vector2(45.0, 0.0), true)
	var s55 := _site_creature(sim, "x_s55", Vector2(0.0, 55.0), true)
	var s50 := _site_creature(sim, "x_s50", Vector2(-50.0, 0.0), true)
	sim.drain_events()
	sim.step(SimIntent.new())
	var removed := _of(sim.drain_events(), "creature_removed")
	var ids := removed.map(func(e: Dictionary) -> String: return str(e.id))
	check_eq(ids, [s55.id, s50.id], "the two farthest evicted, farthest first")
	check(sim.creatures.find(s45.id) != null, "the nearest kept")
	check_eq(int(sim.world.counters.evictions), 2, "both counted")


## C-6: a scripted body and a siteless (debug) creature never sleep; a site creature as far does.
func test_scripted_and_siteless_creatures_never_sleep() -> void:
	var sim := _quiet()
	check(sim.debug_spawn_creature("rammer", Vector2(50.0, 0.0), 0.0), "a debug creature")
	var debug_c := sim.creatures.creatures[-1]
	var scripted := sim.creatures.spawn_scripted("decoy", sim.phenotype, Vector2(0.0, 50.0), 0.0, sim.tick)
	var site_c := _site_creature(sim, "x_far", Vector2(-50.0, 0.0))
	for t in 3:
		sim.step(SimIntent.new())
	check(not debug_c.asleep and sim.creatures.awake().has(debug_c), "the debug creature awake")
	check(not scripted.asleep and sim.creatures.awake().has(scripted), "the scripted body awake")
	check(site_c.asleep, "the site creature asleep")


## Step 5's one pass runs (slot, number, id) over the awake, then the sleepers by (number, id): the
## order of six transitions on one tick.
func test_the_pass_order_is_slot_then_number_then_id() -> void:
	var sim := _quiet()
	sim.world.caps.awake = 30
	sim.world.caps.sleepers = 30
	var awake: Array[CreatureField.Creature] = []
	for i in 8:
		awake.append(_site_creature(sim, "x_w%d" % i, Vector2.from_angle(i * TAU / 8.0) * 12.0))
	check_eq(awake.map(func(c: CreatureField.Creature) -> int: return c.think_slot), [0, 1, 2, 3, 4, 5, 0, 1], "slots in spawn order")
	var sleepers: Array[CreatureField.Creature] = []
	for i in 2:
		sleepers.append(_site_creature(sim, "x_z%d" % i, Vector2(0.0, 18.0 + 4.0 * i), true))
	# Four go far (slots 1, 0, 0, 3), the two sleepers are inside the wake ring.
	var movers: Array[CreatureField.Creature] = [awake[1], awake[0], awake[6], awake[3]]
	for i in movers.size():
		movers[i].motion.place(Vector2.from_angle(0.4 + i * TAU / 4.0) * 50.0, 0.0)
	var want: Array = []
	var by_pass := movers.duplicate()
	by_pass.sort_custom(func(p: CreatureField.Creature, q: CreatureField.Creature) -> bool:
		return p.think_slot < q.think_slot or (p.think_slot == q.think_slot and (p.number < q.number or (p.number == q.number and p.id < q.id))))
	for c in by_pass:
		want.append("slept " + c.id)
	var waking := sleepers.duplicate()
	waking.sort_custom(func(p: CreatureField.Creature, q: CreatureField.Creature) -> bool:
		return p.number < q.number or (p.number == q.number and p.id < q.id))
	for c in waking:
		want.append("woke " + c.id)
	sim.drain_events()
	sim.step(SimIntent.new())
	var got: Array = []
	for e in sim.drain_events():
		if e.type == "creature_slept":
			got.append("slept " + e.id)
		elif e.type == "creature_woke":
			got.append("woke " + e.id)
	check_eq(got, want, "slot, number, id; sleepers last")
	_check_slots(sim, "after six transitions")
	check(awake[0].number != awake[6].number, "(two on slot 0 ordered by number)")


## The snapshot's sleeping and slots: the sleepers' ids sorted, and every awake creature's slot.
func test_the_snapshot_holds_the_sleepers_and_the_slots() -> void:
	var sim := _quiet()
	var a := _site_creature(sim, "x_s1", Vector2(10.0, 0.0))
	var b := _site_creature(sim, "x_s2", Vector2(-10.0, 0.0))
	var z := _site_creature(sim, "x_s3", Vector2(0.0, 60.0), true)
	var w: Dictionary = sim.snapshot().world
	check_eq(w.sleeping, [z.id], "sleeping")
	var want := {a.id: a.think_slot, b.id: b.think_slot}
	check_eq(w.slots, want, "slots")
	var ids := want.keys()
	ids.sort()
	check_eq(w.slots.keys(), ids, "in id order")


# --- S2 (T2.5): chunk events at a size, site posts, the teleport path to a size ---

## An endless sim on the fake generator with growth on (size 2 is the build top), its start events
## drained: with the size-2 species when `with_species`, so sites get records and creatures.
func _growing(with_species := false) -> PoolSim:
	var sim := FakeWorldGen.endless_sim(SEED, catalog, layout, FakeWorldGen.s2_species() if with_species else null, null,
		PackedFloat64Array(), 4, true)
	sim.drain_events()
	return sim


## The chunk_loaded event of `key` among `events` ({} when there is none).
func _loaded_event(events: Array[Dictionary], key: Vector2i) -> Dictionary:
	for e in _of(events, "chunk_loaded"):
		if e.key == key:
			return e
	return {}


## S2 build plan 7.4 (BP-16, C-V10): chunk_loaded lists the sites live at the chunk's size, each with
## its posts [{position, heading}] in local tm (a one-post site: one post, at its home), and every
## place carries scale bu_to_tm(size): 1.0 at size 1, 0.625 at size 2. Chunk (2, 2)'s zone centre is
## (80, 80) tm at each size; at size 2 a tm is 1.6 am.
func test_chunk_loaded_lists_the_sites_live_at_its_size_with_their_posts_and_places_their_scale() -> void:
	var sim := _growing()
	var key := Vector2i(2, 2)
	var heading := FakeWorldGen.SITE_HEADING
	var husk := FakeWorldGen.PLACE_CHUNK
	var husk_at := Vector2(32.0 * husk.x + 16.0, 32.0 * husk.y + 16.0)
	check(sim.debug_teleport_abs(80.0, 70.0), "beside the site chunk at size 1")
	var e := _loaded_event(sim.drain_events(), key)
	check_eq(e.get("sites"), [{"id": "t_f_2_2", "species": "rammer",
		"posts": [{"position": sim.world.local_of_tm(83.0, 80.0), "heading": heading}]}], "size 1: the size-1 site, one post at its home")
	check(sim.debug_teleport_abs(husk_at.x + 10.0, husk_at.y), "beside the place at size 1")
	e = _loaded_event(sim.drain_events(), husk)
	check_eq(e.get("places", [{}])[0].get("scale"), 1.0, "a place's scale at size 1")
	check_eq(e.get("places", [{}])[0].get("position"), Vector2(-10.0, 0.0), "its local position")

	check(sim.debug_set_size(2), "size 2")
	var k := WorldConfig.tm_to_am(2)
	check(sim.debug_teleport_abs(80.0 * k, 70.0 * k), "beside the site chunk at size 2")
	e = _loaded_event(sim.drain_events(), key)
	var want := [
		["u_f_2_2", "rammer", [Vector2(77.0, 80.0)]],
		["l_f_2_2", "lurker", [Vector2(74.0, 72.0), Vector2(74.0 + FakeWorldGen.LURKER_GAP, 72.0)]],
		["e_f_2_2", "elder_rammer", [Vector2(82.0, 84.0), Vector2(73.0, 88.0)]]]
	var sites: Array = e.get("sites", [])
	check_eq(sites.size(), want.size(), "size 2: the three size-2 sites, not the size-1 one")
	for i in mini(sites.size(), want.size()):
		var s: Dictionary = sites[i]
		check_eq([s.id, s.species, s.posts.size()], [want[i][0], want[i][1], want[i][2].size()], "site %d" % i)
		for j in mini(s.posts.size(), want[i][2].size()):
			var at: Vector2 = want[i][2][j]
			check_eq(s.posts[j].position, sim.world.local_of_tm(at.x, at.y), "%s post %d in local tm" % [s.id, j])
			var back := sim.world.abs_of_local(s.posts[j].position)
			check(absf(back[0] - at.x * k) < 1e-3 and absf(back[1] - at.y * k) < 1e-3, "%s post %d at %s am" % [s.id, j, at * k])
			check_eq(s.posts[j].heading, heading, "%s post %d heading" % [s.id, j])
	check(sim.debug_teleport_abs((husk_at.x + 10.0) * k, husk_at.y * k), "beside the place at size 2")
	e = _loaded_event(sim.drain_events(), husk)
	check_eq(e.get("places", [{}])[0].get("scale"), 0.625, "a place's scale at size 2 (bu_to_tm(2))")
	check_eq(e.get("places", [{}])[0].get("position"), Vector2(-10.0, 0.0), "its local position (tm at size 2)")


## S1's chunk_unloaded payload is unchanged: only the growth tick's unloads carry a reason (D-67,
## test_growth_tick), so streaming and the teleport path send {type, key}, with growth on or off.
func test_a_chunk_unloaded_by_streaming_or_teleport_carries_only_its_key() -> void:
	for growth in [false, true]:
		var sim := FakeWorldGen.endless_sim(SEED, catalog, layout, null, null, PackedFloat64Array(), 4, growth)
		sim.drain_events()
		var shapes := {}
		for t in 300:
			sim.step(SimIntent.new(Vector2.RIGHT))
		for e in _of(sim.drain_events(), "chunk_unloaded"):
			shapes[str(e.keys())] = true
		var swum := shapes.size()
		check(sim.debug_teleport_abs(5000.0, 9.0), "far away")
		var gone := _of(sim.drain_events(), "chunk_unloaded")
		check(not gone.is_empty(), "the teleport unloads (growth %s)" % growth)
		for e in gone:
			shapes[str(e.keys())] = true
		check_eq(shapes.keys(), [str(["type", "key"])], "every unload is {type, key} (growth %s, %d from the swim)" % [growth, swum])


## A two-post site's record holds its posts as CreatureBrain.set_posts takes them, in local tm at the
## size (their territory centres too, or {}), and every rebase derives them again from "abs_posts",
## as it does the site's home (S2 spine 3.17, D-83).
func test_a_two_post_sites_record_holds_its_posts_in_local_tm_and_a_rebase_derives_them_again() -> void:
	var sim := _growing(true)
	check(sim.debug_set_size(2), "size 2")
	var k := WorldConfig.tm_to_am(2)
	check(sim.debug_teleport_abs(80.0 * k, 70.0 * k), "beside the site chunk")
	sim.drain_events()
	var want := {
		"l_f_2_2": [[74.0, 72.0, {}], [74.0 + FakeWorldGen.LURKER_GAP, 72.0, {}]],
		"e_f_2_2": [[82.0, 84.0, [80.0, 80.0, FakeWorldGen.ZONE_R]], [73.0, 88.0, [72.0, 88.0, FakeWorldGen.ELDER_ZONE_R]]]}
	for by in [Vector2i.ZERO, Vector2i(1, -1), Vector2i(-2, 0)]:
		if by != Vector2i.ZERO:
			check(sim.debug_rebase(by), "rebase by %s" % by)
		for id in want:
			var rec: Dictionary = sim.world.sites.get(id, {})
			check(rec.has("posts"), "%s recorded with posts (after %s)" % [id, by])
			if not rec.has("posts"):
				continue
			check_eq(rec.posts.size(), 2, "two posts")
			check_eq(rec.posts[0].home, rec.home, "the first post is the site's home")
			for j in 2:
				var w: Array = want[id][j]
				var post: Dictionary = rec.posts[j]
				check_eq(post.home, sim.world.local_of_tm(w[0], w[1]), "%s post %d home (after %s)" % [id, j, by])
				check_eq(post.heading, FakeWorldGen.SITE_HEADING, "its heading")
				if w[2] is Dictionary:
					check_eq(post.territory, {}, "no territory")
				else:
					check_eq(post.territory, {"center": sim.world.local_of_tm(w[2][0], w[2][1]), "radius": w[2][2]},
						"%s post %d territory (after %s)" % [id, j, by])
	check(not sim.world.sites.get("u_f_2_2", {}).has("posts"), "a one-post site has no posts key")


## D-76: debug set_size takes the world to size n round the cell's absolute place by the teleport
## path: every remnant leaves ("unloaded"), the checkpoint keeps its place and heading at size n, the
## creature field and the loaded chunks are size n's, the origin is the place, the cell takes the clear
## point nearest it, the meter starts again, and debug {command: "set_size", size} comes last (C-V9).
## It refuses a size outside the ladder, or a dead cell.
func test_debug_set_size_takes_the_world_to_a_size_by_the_teleport_path() -> void:
	var sim := _growing(true)
	for t in 60:
		sim.step(SimIntent.new(Vector2(0.3, 0.2)))
	var c := sim.creatures.creatures[0] if not sim.creatures.creatures.is_empty() else null
	check(c != null, "a creature to make a remnant of")
	if c == null:
		return
	var r := sim.remnants.add_from(c, sim.species.at_size(c.species_id, 2), sim.tick)
	sim.growth.meter = 1.5
	var a := sim.absolute_position_am()
	var cp := sim.world.checkpoint_am.duplicate()
	sim.drain_events()
	check(sim.debug_set_size(2), "size 2")
	var events := sim.drain_events()
	check_eq(sim.size(), 2, "size 2")
	check_eq(sim.creatures.size, 2, "the creature field's records are size 2's")
	check(sim.remnants.items.is_empty(), "no remnant left")
	var left := _of(events, "creature_removed").filter(func(e: Dictionary) -> bool: return e.id == r.id and e.species == r.species_id)
	check(not left.is_empty() and left[0].reason == "unloaded", "the remnant left, unloaded")
	check_eq(sim.world.checkpoint_am, PackedFloat64Array([cp[0], cp[1], cp[2], 2.0]), "the checkpoint at size 2, same place")
	check_eq([sim.world.origin_x_am, sim.world.origin_y_am], [a[0], a[1]], "the origin is the place exactly")
	check_eq(sim.motion.position, PoolSim.clear_point_on(sim.arena, Vector2.ZERO, sim.phenotype.radius),
		"the cell at the clear point nearest its place")
	check(sim.motion.position.length() < 3.0, "near its place (%s)" % sim.motion.position)
	check_eq(sim.world.loaded_keys(), sim.world.view_set_keys(Vector2.ZERO), "the view set round the place")
	for key in sim.world.loaded_keys():
		check_eq(sim.world.chunk(key).size, 2, "chunk %s at size 2" % key)
	check_eq(sim.growth.meter, 0.0, "the meter starts again")
	check_eq(events.back(), {"type": "debug", "command": "set_size", "size": 2}, "the debug event last")
	check(not sim.debug_set_size(3), "no size above the build top")
	check(not sim.debug_set_size(0), "no size 0")
	check(sim.debug_set_size(1), "back to size 1")
	check_eq([sim.size(), sim.creatures.size, int(sim.world.checkpoint_am[3])], [1, 1, 1], "size 1 again")
	sim._player_dies("starved", "", "", "test")
	check(not sim.debug_set_size(2), "not while dead")
