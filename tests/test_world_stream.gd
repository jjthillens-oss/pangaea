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
func test_at_the_chunk_cap_loads_outside_the_view_set_wait_and_count() -> void:
	var sim := _endless(SEED, null, false)
	sim.drain_events()
	var cap := sim.world.loaded_keys().size() + 2
	sim.world.caps.chunks = cap
	var waits := 0
	var bad := 0
	var first := ""
	for t in 600:
		var a := sim.absolute_position_am()
		var before := sim.world.loaded_keys()
		var view := sim.world.view_set_keys(sim.motion.position)
		var waits_before := int(sim.world.counters.chunk_waits)
		sim.step(SimIntent.new(Vector2.DOWN))
		var loaded: Array = []
		for e in sim.drain_events():
			if e.type == "chunk_loaded":
				loaded.append(e.key)
		var kept := before.filter(func(k: Vector2i) -> bool: return _ref_nearest(k, a[0], a[1]) <= 72.0)
		var best: Variant = _ref_nearest_missing(kept, a[0], a[1], 56.0)
		var want_wait := best != null and kept.size() >= cap and not view.has(best)
		var waited := int(sim.world.counters.chunk_waits) - waits_before
		if waited != (1 if want_wait else 0) or (want_wait and not loaded.is_empty()):
			bad += 1
			if first.is_empty():
				first = "tick %d: waited %d, loaded %s, want a wait %s" % [t, waited, loaded, want_wait]
		for key in loaded:
			if kept.size() >= cap and not view.has(key):
				bad += 1
		waits += waited
	check_eq(bad, 0, "a wait exactly when the nearest missing chunk is outside the view set at the cap (%s)" % first)
	check(waits > 0, "the cap was reached (%d waits)" % waits)
	for key in sim.world.view_set_keys(sim.motion.position):
		check(sim.world.chunk(key) != null, "view-set chunk %s loaded past the cap" % key)


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
	check(held.size() >= 2, "its disc spans %d chunks" % held.size())
	for t in 3000:
		sim.step(SimIntent.new(Vector2.RIGHT))
	var a := sim.absolute_position_am()
	check(a[0] > 100.0, "the cell swam far (%.1f)" % a[0])
	for key in held:
		check(_ref_nearest(key, a[0], a[1]) > 72.0, "chunk %s is beyond the unload ring" % key)
		check(sim.world.chunk(key) != null, "and still loaded, held by the creature")
	for key in sim.world.loaded_keys():
		check(held.has(key) or _ref_nearest(key, a[0], a[1]) <= 72.0, "nothing else beyond 72 (%s)" % key)
	sim.creatures.remove(c, "test", sim.tick, false)
	sim.step(SimIntent.new())
	for key in held:
		check(sim.world.chunk(key) == null, "chunk %s unloaded once the creature is gone" % key)


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
