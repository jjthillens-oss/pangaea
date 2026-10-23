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
	var c := content if content != null else FakeWorldGen.fixture_content()
	var r := Lineage.found(seed_value, "test+dev", catalog, "omnivore")
	var sp: SpeciesCatalog = species if with_species else null
	return PoolSim._create_endless(r.save, catalog, layout, sp, c, FakeWorldGen.new(c, sp, seed_value))


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
