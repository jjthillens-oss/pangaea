extends TestCase
## The endless world's generator (S1, docs/s1/s1-interfaces.md section 3.6, docs/s1/s1-core.md 6.4
## and 12.2): the arrangement of regions, tiles, rare tiles and landmarks on the fixture world, the
## orientation helpers, and chunks as plain data with a stable digest. The same inputs always give
## the same results, with or without the memo (G6); neighbouring tiles never repeat (G15).

const WORLD := "res://tests/fixtures/world/world_min.json"
const GOLDEN := "res://tests/fixtures/world/arrangement_golden.json"
const ORDINARY: PackedStringArray = ["drift", "sunlit", "reef"]

static var _content_cache: WorldContent = null
static var _species_cache: SpeciesCatalog = null


## The fixture world, loaded once for the file (the tests only read it).
static func _content() -> WorldContent:
	if _content_cache == null:
		_species_cache = SpeciesCatalog.load_from()
		_content_cache = WorldContent.load_from(WORLD, PoolLayout.load_from(), _species_cache)
	return _content_cache


static func _gen(seed_value: int) -> WorldGen:
	return WorldGen.create(_content(), _species_cache, seed_value)


static var _shared := {}


## One generator per seed for the tests that only read the arrangement, so their memos are warm
## (results do not depend on the memo: test_tile_info_is_the_same_with_the_memo_cleared).
static func _shared_gen(seed_value: int) -> WorldGen:
	if not _shared.has(seed_value):
		_shared[seed_value] = _gen(seed_value)
	return _shared[seed_value]


static var _cells := {}


## landmark_of_cell for every cell of [-18, 18)^2 at seed 4242, keyed Vector2i(lx, ly).
static func _landmarks() -> Dictionary:
	if _cells.is_empty():
		var gen := _shared_gen(4242)
		for ly in range(-18, 18):
			for lx in range(-18, 18):
				_cells[Vector2i(lx, ly)] = gen.landmark_of_cell(0, lx, ly)
	return _cells


func test_a_chunk_is_plain_data_with_a_stable_digest() -> void:
	var c := WorldChunk.new()
	c.key = Vector2i(-2, 3)
	c.size = 1
	# 0.1 + 0.2 is 0.30000000000000004, one ulp above 0.3: only full precision tells them apart.
	c.zones.append({"id": "z_0_1_2_a", "x": 0.1 + 0.2, "y": -64.0, "radius": 5.0, "capacity": 40.0, "growth_rate": 0.08,
		"tile": Vector2i(1, 2), "region": "reef"})
	c.sites.append({"id": "t_0_1_2_a", "chunks": [Vector2i(2, 4), Vector2i(3, 4)], "sizes": [1]})
	var d := c.to_dict()
	check_eq(d.key, [-2, 3], "the key as [x, y]")
	check_eq(d.zones[0].tile, [1, 2], "a tile as [x, y]")
	check_eq(d.sites[0].chunks, [[2, 4], [3, 4]], "chunk lists as pairs")
	check_eq(c.zones[0].tile, Vector2i(1, 2), "to_dict leaves the chunk itself alone")
	var text := JSON.stringify(d, "", true, true)
	check_eq(c.digest(), text.sha256_text(), "the digest is the SHA-256 of the sorted, full-precision JSON")
	check_eq(c.digest().length(), 64, "64 hex digits")
	var same := WorldChunk.new()
	same.key = Vector2i(-2, 3)
	same.zones = c.zones.duplicate(true)
	same.sites = c.sites.duplicate(true)
	check_eq(same.digest(), c.digest(), "equal chunks, equal digests")
	same.zones[0].x = 0.3
	check(same.digest() != c.digest(), "full precision: a one-ulp move changes the digest")


func test_create_binds_the_seed_and_the_generator_version() -> void:
	var content := _content()
	var gen := WorldGen.create(content, _species_cache, 4242)
	check_eq(gen.world_seed, 4242, "seed")
	check_eq(gen.gen_version, content.config.gen_version, "gen_version from the world file")
	var c := gen.chunk(1, -3, 5)
	check_eq(c.key, Vector2i(-3, 5), "key")
	check_eq(c.size, 1, "size")
	check_eq(c.digest(), gen.chunk(1, -3, 5).digest(), "the same chunk twice")


# --- the arrangement ---

## An independent reference (tests/fixtures/world/make_arrangement_golden.py, written from the
## spine's rules and tools/world_hash_ref.py) agrees on 686 tiles and 76 landmark cells, two seeds.
func test_tile_info_and_landmarks_equal_the_python_reference() -> void:
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	var gens := {}
	var bad := 0
	for e in golden.tiles:
		var s := int(e.seed)
		if not gens.has(s):
			gens[s] = _gen(s)
		var info: Dictionary = gens[s].tile_info(0, int(e.tx), int(e.ty))
		var want: Dictionary = e.info
		var same: bool = info.id == want.id and info.region == want.region and info.rare == want.rare \
			and info.set == int(want.set) and info.orientation == int(want.orientation)
		if not same:
			bad += 1
			if bad <= 5:
				check(false, "seed %d tile (%d, %d): %s, the reference %s" % [s, e.tx, e.ty, info, want])
	for e in golden.landmarks:
		var got: Dictionary = gens[int(e.seed)].landmark_of_cell(0, int(e.lx), int(e.ly))
		var want: Dictionary = e.value
		var same := got.is_empty() == want.is_empty()
		if same and not got.is_empty():
			same = got.tile == Vector2i(int(want.tile[0]), int(want.tile[1])) and got.model == want.model and got.dressing == want.dressing
		if not same:
			bad += 1
			if bad <= 5:
				check(false, "seed %d cell (%d, %d): %s, the reference %s" % [e.seed, e.lx, e.ly, got, want])
	check_eq(bad, 0, "disagreements with the reference")
	check_eq(golden.tiles.size(), 686, "every tile of the golden read")


func _shares(gen: WorldGen, n: int, raw: bool) -> Dictionary:
	var counts := {"drift": 0, "sunlit": 0, "reef": 0}
	var order: PackedStringArray = gen.content.config.arrangement.region_order
	for ty in range(-n / 2, n / 2):
		for tx in range(-n / 2, n / 2):
			counts[order[gen._raw(0, tx, ty)] if raw else gen._region(0, tx, ty)] += 1
	var out := {}
	for r in counts:
		out[r] = float(counts[r]) / (n * n)
	return out


## The thresholds are the region noise's measured third quantiles (core 0.2), so before the swap
## each region holds a third of the tiles (measured worst 0.026 off at this size).
func test_region_shares_are_a_third_each_before_the_drift_rule() -> void:
	var shares := _shares(_gen(401), 320, true)
	print("test-world-gen: raw shares at seed 401 over 320 x 320 tiles: %s" % [shares])
	for r in shares:
		check_near(shares[r], 1.0 / 3.0, 0.05, "%s share" % r)


func test_slow_region_shares_are_a_third_each_on_four_seeds() -> void:
	for s in [0, 1, 401, 4242]:
		var shares := _shares(_gen(s), 320, true)
		print("test-world-gen: raw shares at seed %d: %s" % [s, shares])
		for r in shares:
			check_near(shares[r], 1.0 / 3.0, 0.05, "seed %d %s share" % [s, r])


static var _region_grids := {}


## Final regions of the ordinary rule over [-64, 64)^2 tiles, row-major, per seed (shared by two tests).
static func _region_grid(seed_value: int) -> PackedStringArray:
	if not _region_grids.has(seed_value):
		var gen := _gen(seed_value)
		var out := PackedStringArray()
		for ty in range(-64, 64):
			for tx in range(-64, 64):
				out.append(gen._region(0, tx, ty))
		_region_grids[seed_value] = out
	return _region_grids[seed_value]


func test_no_three_drift_tiles_run_in_a_row_or_a_column() -> void:
	for s in [401, 4242]:
		var g := _region_grid(s)
		var runs := 0
		for y in 128:
			for x in 128:
				if g[y * 128 + x] != "drift":
					continue
				if x >= 2 and g[y * 128 + x - 1] == "drift" and g[y * 128 + x - 2] == "drift":
					runs += 1
				if y >= 2 and g[(y - 1) * 128 + x] == "drift" and g[(y - 2) * 128 + x] == "drift":
					runs += 1
		check_eq(runs, 0, "seed %d: runs of three drift tiles" % s)


## The pinned swap (spine 3.6 step 2) keeps 1% to 3% drift (measured 1.7%; core C-15 and question 1).
func test_the_drift_share_after_the_rule_is_as_measured() -> void:
	var drift := 0
	var total := 0
	for s in [401, 4242]:
		for r in _region_grid(s):
			total += 1
			if r == "drift":
				drift += 1
	var share := float(drift) / total
	print("test-world-gen: drift after the swap is %.2f%% of %d tiles" % [share * 100.0, total])
	check(share >= 0.01 and share <= 0.03, "drift share %.4f in [0.01, 0.03]" % share)


## G15: a tile and its east and south neighbours never share an id (sets alternate, and the rare
## and home tiles have their own ids).
func test_edge_neighbours_never_repeat_a_tile_id() -> void:
	var gen := _shared_gen(4242)
	var repeats := 0
	for ty in range(-32, 32):
		for tx in range(-32, 32):
			var a: Dictionary = gen.tile_info(0, tx, ty)
			if a.region == "home":
				continue
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var b: Dictionary = gen.tile_info(0, tx + d.x, ty + d.y)
				if a.id == b.id:
					repeats += 1
					if repeats <= 3:
						check(false, "(%d, %d) and its neighbour %s are both '%s'" % [tx, ty, d, a.id])
	check_eq(repeats, 0, "repeated neighbours")


## Every ordinary tile takes one of its (region, set)'s three ids, and all three occur; the set is
## the parity of tx + ty and the orientation is in 0..7.
func test_ordinary_tiles_use_every_id_of_their_region_and_set() -> void:
	var gen := _shared_gen(4242)
	var seen := {}
	for ty in range(-32, 32):
		for tx in range(-32, 32):
			var info: Dictionary = gen.tile_info(0, tx, ty)
			if not ORDINARY.has(info.region):
				continue
			check(gen.content.tiles.ids_of(0, info.region, info.set).has(info.id), "(%d, %d) %s" % [tx, ty, info])
			check(info.set == posmod(tx + ty, 2) and info.orientation >= 0 and info.orientation < 8, "(%d, %d) %s" % [tx, ty, info])
			seen[info.id] = true
	for r in ["sunlit", "reef"]:
		for s in 2:
			for id in gen.content.tiles.ids_of(0, r, s):
				check(seen.has(id), "%s is used" % id)


func test_landmark_groups_differ_between_neighbouring_cells() -> void:
	var gen := _shared_gen(4242)
	var kit := gen.content.kit
	var cells := _landmarks()
	var same := 0
	var empty := 0
	for ly in range(-16, 16):
		for lx in range(-16, 16):
			var a: Dictionary = cells[Vector2i(lx, ly)]
			if a.is_empty():
				empty += 1
				continue
			check_eq(int(kit.assets[a.model].group), posmod(lx, 2) + 2 * posmod(ly, 2), "cell (%d, %d)'s group" % [lx, ly])
			for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
				var b: Dictionary = cells[Vector2i(lx + d.x, ly + d.y)]
				if not b.is_empty() and kit.assets[a.model].group == kit.assets[b.model].group:
					same += 1
	check_eq(same, 0, "neighbouring cells of one group")
	check_eq(empty, 0, "every cell holds an ordinary tile, so a landmark")


## A model's cells share both parities, so two of them are 2 cells apart in some axis and their
## tiles at least 3 apart (2lx + 1 against 2lx + 4). Cells 3 or more apart are 5 or more tiles
## apart, so comparing each cell with its 5 x 5 neighbourhood is exhaustive.
func test_a_landmark_model_repeats_no_closer_than_three_tiles() -> void:
	var cells := _landmarks()
	var nearest := 1 << 30
	for ly in range(-16, 16):
		for lx in range(-16, 16):
			var a: Dictionary = cells[Vector2i(lx, ly)]
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if dx == 0 and dy == 0:
						continue
					var b: Dictionary = cells[Vector2i(lx + dx, ly + dy)]
					if a.is_empty() or b.is_empty() or a.model != b.model:
						continue
					var gap := maxi(absi(a.tile.x - b.tile.x), absi(a.tile.y - b.tile.y))
					nearest = mini(nearest, gap)
	print("test-world-gen: the nearest repeat of a landmark model is %d tiles" % nearest)
	check(nearest >= 3, "a model repeats %d tiles away" % nearest)


## Rare tiles of blocks -5 to 5 are at least 3 tiles apart (Chebyshev) on every seed; the fixed
## tile (2, -1) and block (1, 0)'s are 3 apart when that block's pick is its west column, which
## some of the seeds give, so the bound is exact.
func test_rare_tiles_are_at_least_three_tiles_apart_and_exactly_three_at_the_fixed_one() -> void:
	var lowest := 1 << 30
	for s in [0, 1, 2, 3, 401, 4242]:
		var gen := _gen(s)
		var rares: Array[Vector2i] = []
		for by in range(-5, 6):
			for bx in range(-5, 6):
				var r := gen.rare_of_block(0, bx, by)
				rares.append(r.tile)
				var info := gen.tile_info(0, r.tile.x, r.tile.y)
				check(info.region == "rare" and info.rare == r.kind, "seed %d block (%d, %d): %s" % [s, bx, by, info])
		var nearest := 1 << 30
		for i in rares.size():
			for j in range(i + 1, rares.size()):
				nearest = mini(nearest, maxi(absi(rares[i].x - rares[j].x), absi(rares[i].y - rares[j].y)))
		var east: Vector2i = gen.rare_of_block(0, 1, 0).tile
		var expected := 3 if east.x == 5 else 4
		check_eq(nearest, expected, "seed %d: the nearest pair (block (1, 0)'s rare at %s)" % [s, east])
		lowest = mini(lowest, nearest)
	check_eq(lowest, 3, "some seed puts two rare tiles exactly 3 apart")


func test_the_fixed_rare_tile_is_at_2_minus_1() -> void:
	for s in [0, 401, 4242]:
		var info := _gen(s).tile_info(0, 2, -1)
		check_eq(info.region, "rare", "region")
		check_eq(info.rare, "giant_husk", "kind")
		check_eq(info.orientation, 0, "orientation")
		check_eq(info.id, _content().tiles.rare_tile(0, "giant_husk").id, "the husk's tile")
		check_eq(_gen(s).tile_info(0, 3, -1).region != "rare", true, "only (2, -1) in block (0, 0)")


func test_home_tiles_are_home_and_hold_no_rare_or_landmark() -> void:
	var gen := _gen(4242)
	for ty in range(-1, 1):
		for tx in range(-1, 1):
			check_eq(gen.tile_info(0, tx, ty), {"id": "", "region": "home", "rare": "", "set": -1, "orientation": 0},
				"tile (%d, %d)" % [tx, ty])
	for ty in range(-3, 3):
		for tx in range(-3, 3):
			if not gen.is_home_tile(tx, ty):
				check(gen.tile_info(0, tx, ty).region != "home", "(%d, %d) is not home" % [tx, ty])
	for ly in range(-2, 2):
		for lx in range(-2, 2):
			var lm := gen.landmark_of_cell(0, lx, ly)
			check(lm.is_empty() or not gen.is_home_tile(lm.tile.x, lm.tile.y), "cell (%d, %d)'s landmark %s" % [lx, ly, lm])
			check(lm.is_empty() or gen.tile_info(0, lm.tile.x, lm.tile.y).region != "rare", "cell (%d, %d)'s landmark %s" % [lx, ly, lm])


## G6: a fresh generator (its memo filled in this test's order), the shared one (filled by the
## tests before) and one whose memo is cleared before every call give equal tile infos and
## landmarks over 2,000 random tiles; changing a returned dictionary changes no later result.
func test_tile_info_is_the_same_with_the_memo_cleared() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6401
	var fresh := _gen(4242)
	var shared := _shared_gen(4242)
	var cleared := _gen(4242)
	var differ := 0
	for i in 2000:
		var tx := rng.randi_range(-48, 47)
		var ty := rng.randi_range(-48, 47)
		var a := fresh.tile_info(0, tx, ty)
		var b := shared.tile_info(0, tx, ty)
		cleared.clear_memo()
		var c := cleared.tile_info(0, tx, ty)
		if a != b or a != c:
			differ += 1
		if i % 10 == 0:
			var lx := WorldGen.fdiv(tx, 2)
			var ly := WorldGen.fdiv(ty, 2)
			cleared.clear_memo()
			var lm := fresh.landmark_of_cell(0, lx, ly)
			if lm != shared.landmark_of_cell(0, lx, ly) or lm != cleared.landmark_of_cell(0, lx, ly):
				differ += 1
	check_eq(differ, 0, "results that depend on the memo")
	var far := _gen(4242).tile_info(0, 1562, -1563)
	cleared.clear_memo()
	check_eq(cleared.tile_info(0, 1562, -1563), far, "100 km out too")
	var first := shared.tile_info(0, 5, 7)
	first.id = "changed"
	check(shared.tile_info(0, 5, 7).id != "changed", "the memo hands out copies")
	var other := WorldGen.create(_content(), _species_cache, 4243)
	var moved := 0
	for i in 50:
		if other.tile_info(0, i, 3 * i) != shared.tile_info(0, i, 3 * i):
			moved += 1
	check(moved > 25, "another seed gives another arrangement (%d of 50 tiles differ)" % moved)


func test_fdiv_floors_negative_numbers() -> void:
	check_eq([WorldGen.fdiv(-1, 8), WorldGen.fdiv(-8, 8), WorldGen.fdiv(-9, 8), WorldGen.fdiv(7, 8), WorldGen.fdiv(8, 8)],
		[-1, -1, -2, 0, 1], "floor division")


## The point, heading and yaw maps agree for all eight orientations: a heading's unit vector maps as
## the point does (Vector2.from_angle in float64), and a piece drawn mirrored in its own x and then at the mapped yaw puts every
## point where orient_point does (17.10: the scene's basis is yaw * diag(-1, 1, 1) when mirrored).
func test_orientation_helpers_agree_for_all_eight_orientations() -> void:
	var worst := 0.0
	for o in 8:
		for i in 36:
			var h := -PI + i * TAU / 36.0 + 0.01
			# float64 throughout (Vector2.from_angle would round to float32).
			var p := WorldGen.orient_point(cos(h), sin(h), o)
			var oh := WorldGen.orient_heading(h, o)
			worst = maxf(worst, maxf(absf(p[0] - cos(oh)), absf(p[1] - sin(oh))))
			check(oh >= -PI and oh < PI, "heading in [-PI, PI)")
		for yaw in [0.0, 90.0, 180.0, 270.0]:
			for q in [Vector2(3.0, 1.0), Vector2(-2.0, 5.0), Vector2(0.0, -4.0)]:
				var placed := TileCatalog.yaw_point(q.x, q.y, yaw)
				var want := WorldGen.orient_point(placed[0], placed[1], o)
				var mx: float = -q.x if (o >> 2) == 1 else q.x
				var got := TileCatalog.yaw_point(mx, q.y, WorldGen.orient_yaw_deg(yaw, o))
				check(got == want, "o %d yaw %s point %s: %s, orient_point gives %s" % [o, yaw, q, got, want])
	check(worst <= 1e-12, "heading and point maps agree to %s" % worst)
	check_eq(WorldGen.orient_point(3.0, 1.0, 0), PackedFloat64Array([3.0, 1.0]), "0 is the identity")
	check_eq(WorldGen.orient_point(3.0, 1.0, 1), PackedFloat64Array([-1.0, 3.0]), "1 turns (x, y) to (-y, x)")
	check_eq(WorldGen.orient_point(3.0, 1.0, 4), PackedFloat64Array([-3.0, 1.0]), "4 mirrors x")
	check_eq(WorldGen.orient_point(3.0, 1.0, 5), PackedFloat64Array([-1.0, -3.0]), "5 mirrors, then turns")
	check_eq(WorldGen.orient_yaw_deg(30.0, 6), -30.0 - 180.0, "6: negated, then two quarter turns")


# --- chunks (T1.9; core 6.5 and 12.2) ---

const DIGESTS := "res://tests/fixtures/world/chunk_digests.json"
const Yardstick := preload("res://tests/cost_yardstick.gd")


## Chunk keys in a square spiral out from (0, 0).
static func _spiral(count: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var at := Vector2i.ZERO
	var step := Vector2i(1, 0)
	var leg := 1
	var walked := 0
	var turns := 0
	while out.size() < count:
		out.append(at)
		at += step
		walked += 1
		if walked == leg:
			walked = 0
			step = Vector2i(-step.y, step.x)
			turns += 1
			if turns % 2 == 0:
				leg += 1
	return out


## The objects of a chunk with a centre, as [kind, dict].
static func _objects(c: WorldChunk) -> Array:
	var out := []
	for kind in ["shells", "zones", "sites", "anchors", "places"]:
		for item in c.get(kind):
			out.append([kind, item])
	return out


## G6: a fresh generator per chunk, one shared generator, and one cleared every 10 chunks give
## equal digests along a spiral, a straight line and a random walk of 200 chunks each.
func test_chunks_are_the_same_along_any_route() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6402
	var line: Array[Vector2i] = []
	var walk: Array[Vector2i] = []
	var at := Vector2i(5, -7)
	for i in 200:
		line.append(Vector2i(-100 + i, 3))
		walk.append(at)
		at += [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)][rng.randi_range(0, 3)]
	var shared := _gen(401)
	var differ := 0
	var objects := 0
	for route in [_spiral(200), line, walk]:
		var cleared := _gen(401)
		for i in route.size():
			var k: Vector2i = route[i]
			if i % 10 == 0:
				cleared.clear_memo()
			var a := _gen(401).chunk(1, k.x, k.y)
			var d := a.digest()
			objects += _objects(a).size()
			if d != shared.chunk(1, k.x, k.y).digest() or d != cleared.chunk(1, k.x, k.y).digest():
				differ += 1
				if differ <= 3:
					check(false, "chunk %s differs between generators" % k)
	check_eq(differ, 0, "chunks that depend on the route or the memo")
	check(objects > 600, "the routes hold objects (%d)" % objects)


func test_the_chunk_digest_golden_holds() -> void:
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIGESTS))
	check_eq(golden.world, WORLD, "the golden is of the fixture world")
	var gen := _gen(int(golden.seed))
	var homes := 0
	for e in golden.chunks:
		var k := Vector2i(int(e.key[0]), int(e.key[1]))
		check_eq(gen.chunk(int(golden.size), k.x, k.y).digest(), e.digest, "chunk %s (%s)" % [k, e.holds])
		if k.x >= -2 and k.x <= 1 and k.y >= -1 and k.y <= 0:
			homes += 1
	check_eq(homes, 8, "the eight home chunks x -2 to 1, y -1 to 0")


## Every shell, zone, site, anchor and place of 100 random chunks and the 16 home chunks lies in its
## chunk: floori(x / 32) == cx and the same in y, on the float64 value.
func test_a_chunk_holds_only_objects_whose_centres_lie_in_it() -> void:
	var gen := _shared_gen(401)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6403
	var keys: Array[Vector2i] = []
	for y in range(-2, 2):
		for x in range(-2, 2):
			keys.append(Vector2i(x, y))
	for i in 100:
		keys.append(Vector2i(rng.randi_range(-80, 80), rng.randi_range(-80, 80)))
	var outside := 0
	var seen := 0
	for k in keys:
		for o in _objects(gen.chunk(1, k.x, k.y)):
			seen += 1
			if floori(o[1].x / 32.0) != k.x or floori(o[1].y / 32.0) != k.y:
				outside += 1
				check(false, "%s %s at (%s, %s) is outside chunk %s" % [o[0], o[1].id, o[1].x, o[1].y, k])
	check_eq(outside, 0, "objects outside their chunk")
	check(seen > 300, "objects seen: %d" % seen)


## Nothing is lost or doubled between a tile's four chunks: each of its shells, zones and live sites
## appears exactly once, with its set-piece colliders and place on a rare tile; the home block's 16
## chunks hold every M1 rock, zone and site and every ring item once.
func test_a_tiles_four_chunks_hold_each_of_its_objects_once() -> void:
	var gen := _shared_gen(401)
	var content := _content()
	var tiles := []
	for i in 40:
		tiles.append(Vector2i(i * 3 - 60, 41 - i * 2))
	for b in range(-2, 3):
		tiles.append(gen.rare_of_block(0, b, 1 - b).tile)
	for t in tiles:
		var info := gen.tile_info(0, t.x, t.y)
		var data: Dictionary = content.tiles.tiles[info.id]
		var ids := {}
		var counts := {"shell": 0, "set_piece": 0, "zones": 0, "sites": 0, "places": 0}
		for dy in 2:
			for dx in 2:
				var c := gen.chunk(1, 2 * t.x + dx, 2 * t.y + dy)
				for o in _objects(c):
					check(not ids.has(o[1].id), "%s appears once" % o[1].id)
					ids[o[1].id] = true
					if o[0] == "shells":
						if o[1].kind != "landmark":
							counts[o[1].kind] += 1
					elif o[0] != "anchors":
						counts[o[0]] += 1
		var live: int = data.sites.filter(func(s: Dictionary) -> bool: return (s.sizes as Array).has(1)).size()
		var pieces := 0
		if not data.set_piece.is_empty():
			pieces = (content.kit.assets[data.set_piece.asset].colliders as Array).size()
		check_eq(counts, {"shell": data.shells.size(), "set_piece": pieces, "zones": data.zones.size(), "sites": live,
			"places": 1 if pieces > 0 else 0}, "tile %s (%s at orientation %d)" % [t, info.id, info.orientation])
	var home := {}
	for cy in range(-2, 2):
		for cx in range(-2, 2):
			for o in _objects(gen.chunk(1, cx, cy)):
				check(not home.has(o[1].id), "%s appears once in the home block" % o[1].id)
				home[o[1].id] = o[1]
	check_eq(home.size(), content.home.shells.size() + content.home.zones.size() + content.home.sites.size(),
		"every home item once")


## Each site's chunk list equals a brute-force test of every chunk square near its reach disc, and
## holds the site's own chunk (C-4 puts the home inside the disc).
func test_a_site_lists_every_chunk_its_reach_disc_touches() -> void:
	var gen := _shared_gen(4242)
	var checked := 0
	for k in _spiral(120):
		for s in gen.chunk(1, k.x, k.y).sites:
			var r: float = s.reach.radius
			var want: Array[Vector2i] = []
			for ky in range(floori((s.reach.y - r) / 32.0) - 1, floori((s.reach.y + r) / 32.0) + 2):
				for kx in range(floori((s.reach.x - r) / 32.0) - 1, floori((s.reach.x + r) / 32.0) + 2):
					var near := Vector2(clampf(s.reach.x, kx * 32.0, kx * 32.0 + 32.0), clampf(s.reach.y, ky * 32.0, ky * 32.0 + 32.0))
					if Vector2(s.reach.x, s.reach.y).distance_squared_to(near) < r * r:
						want.append(Vector2i(kx, ky))
			check_eq(s.chunks, want, "site %s" % s.id)
			check(s.chunks.has(k), "site %s lists its own chunk %s" % [s.id, k])
			check(s.chunks.size() <= 4, "site %s touches at most 4 chunks" % s.id)
			checked += 1
	check(checked > 20, "sites checked: %d" % checked)


## A site about 100 km out has its reach disc built in the tile's own frame (small numbers), then
## oriented and placed: equal to the identity-frame disc moved by hand within 1e-9 tm. A brain
## built at the absolute home would round it in float32 (printed).
func test_reach_discs_are_placed_from_the_tile_frame() -> void:
	var gen := _shared_gen(401)
	var species := _species_cache
	var found := false
	for i in 40:
		var t := Vector2i(1562 + i % 7 - 3, -1563 + i / 7 - 3)
		var info := gen.tile_info(0, t.x, t.y)
		var data: Dictionary = _content().tiles.tiles.get(info.id, {})
		if data.is_empty() or data.sites.is_empty():
			continue
		var site: Dictionary = data.sites[0]
		var zone := TileCatalog._zone(data, site.territory_zone)
		var local := {"species": site.species, "home": Vector2(site.home[0], site.home[1]), "heading": float(site.heading)}
		var territory := species.territory_from(local, {} if zone.is_empty() else
			{"center": Vector2(zone.center[0], zone.center[1]), "radius": float(zone.radius)})
		var disc := species.reach_disc_for(local, territory)
		var p := WorldGen.orient_point(disc.center.x, disc.center.y, info.orientation)
		var wx := 64.0 * t.x + 32.0 + p[0]
		var wy := 64.0 * t.y + 32.0 + p[1]
		var h := WorldGen.orient_point(site.home[0], site.home[1], info.orientation)
		var hx := 64.0 * t.x + 32.0 + h[0]
		var hy := 64.0 * t.y + 32.0 + h[1]
		var c := gen.chunk(1, floori(hx / 32.0), floori(hy / 32.0))
		for s in c.sites:
			if s.id == "t_0_%d_%d_%s" % [t.x, t.y, site.id]:
				found = true
				check(absf(s.reach.x - wx) <= 1e-9 and absf(s.reach.y - wy) <= 1e-9, "disc centre (%s, %s) against (%s, %s)" % [s.reach.x, s.reach.y, wx, wy])
				check_eq(s.reach.radius, float(disc.radius), "radius")
				var abs_territory := {}
				if not territory.is_empty():
					var tc := WorldGen.orient_point(territory.center.x, territory.center.y, info.orientation)
					abs_territory = {"center": Vector2(64.0 * t.x + 32.0 + tc[0], 64.0 * t.y + 32.0 + tc[1]), "radius": territory.radius}
				var naive := species.reach_disc_for({"species": site.species, "home": Vector2(hx, hy),
					"heading": WorldGen.orient_heading(float(site.heading), info.orientation)}, abs_territory)
				print("test-world-gen: at tile %s (%s) a brain built at the absolute home puts the disc %.4f tm off"
					% [t, site.species, Vector2(naive.center.x - wx, naive.center.y - wy).length()])
		if found:
			break
	check(found, "a site near tile (1562, -1563)")


## docs/s1/s1-content.md 17.10: a place carries the yaw and mirror its colliders were placed with,
## so drawing the piece mirrored in its own x when `mirror`, then turned by yaw_deg, at the place
## puts each record collider on its collider shell, at all eight orientations.
func test_places_carry_the_yaw_and_mirror_their_colliders_were_placed_with() -> void:
	var gen := _gen(401)
	var content := _content()
	var checked := 0
	for kind in TileCatalog.BAND0_RARE_KINDS:
		var t: Dictionary = content.tiles.rare_tile(0, kind)
		var record: Dictionary = content.kit.assets[t.set_piece.asset]
		for o in 8:
			var place := {}
			var pieces := {}
			for dy in 2:
				for dx in 2:
					var out := WorldChunk.new()
					out.key = Vector2i(14 + dx, 6 + dy)
					gen._emit_tile(out, t, {"orientation": o, "region": "rare"}, 1, 0, 1.0, 7, 3)
					for p in out.places:
						place = p
					for s in out.shells:
						if s.kind == "set_piece":
							pieces[s.id] = s
			check_eq(place.mirror, o >= 4, "%s o %d mirror" % [kind, o])
			check_eq(place.kind, kind, "kind")
			for k in (record.colliders as Array).size():
				var c: Dictionary = record.colliders[k]
				var cx: float = -c.center[0] if place.mirror else c.center[0]
				var q := TileCatalog.yaw_point(cx, c.center[1], place.yaw_deg)
				var s: Dictionary = pieces.get("s_0_7_3_r%d" % k, {})
				check(not s.is_empty() and absf(s.x - (place.x + q[0])) <= 1e-9 and absf(s.y - (place.y + q[1])) <= 1e-9,
					"%s o %d collider %d: %s, the drawn piece puts it at (%s, %s)" % [kind, o, k, s, place.x + q[0], place.y + q[1]])
				check(s.get("yaw_deg", NAN) == place.yaw_deg, "the collider shells carry the place's yaw")
				checked += 1
	check(checked >= 24, "colliders checked: %d" % checked)


## Each tile shell takes a kit shell that fits its slot, at scale radius / footprint, with one of
## its dressings' tints; the home block's M1 rocks keep their own asset, yaw and scale.
func test_shells_take_a_fitting_asset_a_dressing_and_their_scale() -> void:
	var gen := _shared_gen(4242)
	var kit := _content().kit
	var tried := 0
	for k in _spiral(150):
		for s in gen.chunk(1, k.x, k.y).shells:
			if s.kind != "shell" or s.id.begins_with("rock_"):
				continue
			var a: Dictionary = kit.assets.get(s.asset, {})
			check(kit.fitting(s.r, 0).has(s.asset), "%s: %s fits r %s" % [s.id, s.asset, s.r])
			check(is_equal_approx(s.scale, s.r / a.footprint_radius_m), "%s: scale %s" % [s.id, s.scale])
			check(a.dressings.map(func(d: Dictionary) -> String: return d.tint).has(s.tint), "%s: tint %s" % [s.id, s.tint])
			tried += 1
	check(tried > 200, "shells tried: %d" % tried)


## The home block at size 1 is the M1 pool: every rock with its id, centre, radius, asset, yaw and
## scale as the layout holds them, every zone, and every site with the reach disc
## SpeciesCatalog.reach_disc gives it in the pool; the ring's items carry the s_h_, z_h_ and t_h_ ids.
func test_the_home_block_emits_the_m1_pool_unchanged() -> void:
	var gen := _shared_gen(401)
	var layout := _content().layout
	var home := {}
	for cy in range(-2, 2):
		for cx in range(-2, 2):
			for o in _objects(gen.chunk(1, cx, cy)):
				home[o[1].id] = o[1]
	for r in layout.rocks:
		var s: Dictionary = home.get(r.id, {})
		check(not s.is_empty() and s.x == float(r.center.x) and s.y == float(r.center.y) and s.r == float(r.radius)
			and s.asset == r.asset and s.yaw_deg == float(r.yaw_deg) and s.scale == float(r.scale), "rock %s: %s" % [r.id, s])
	for z in layout.zones:
		var e: Dictionary = home.get(z.id, {})
		check(not e.is_empty() and e.x == float(z.center.x) and e.y == float(z.center.y) and e.radius == float(z.radius)
			and e.capacity == float(z.capacity) and e.region == "home", "zone %s: %s" % [z.id, e])
	for s in _species_cache.sites:
		var e: Dictionary = home.get(s.id, {})
		var disc := _species_cache.reach_disc(s, layout)
		check(not e.is_empty() and e.reach.x == float(disc.center.x) and e.reach.y == float(disc.center.y)
			and e.reach.radius == float(disc.radius), "site %s: %s against %s" % [s.id, e.get("reach"), disc])
	var ring := 0
	for id in home:
		if id.begins_with("s_h_") or id.begins_with("z_h_") or id.begins_with("t_h_"):
			ring += 1
	var content := _content()
	check_eq(ring, content.home.shells.filter(func(s: Dictionary) -> bool: return not s.fixed).size()
		+ content.home.zones.filter(func(z: Dictionary) -> bool: return not z.m1).size()
		+ content.home.sites.filter(func(s: Dictionary) -> bool: return not s.m1).size(), "ring items")


## generated_creatures off omits every tile site and keeps the home's M1 sites; a site not live at
## the size is omitted too.
func test_sites_follow_the_switch_and_their_sizes() -> void:
	var off := WorldContent.load_from(WORLD, PoolLayout.load_from(), _species_cache)
	off.config.switches.generated_creatures = false
	var gen := WorldGen.create(off, _species_cache, 401)
	var tile_sites := 0
	var m1 := 0
	for k in _spiral(100):
		for s in gen.chunk(1, k.x, k.y).sites:
			if s.id.begins_with("t_"):
				tile_sites += 1
			else:
				m1 += 1
	check_eq(tile_sites, 0, "no tile sites with generated creatures off")
	check_eq(m1, _species_cache.sites.size(), "the M1 sites stay")
	var later := WorldContent.load_from(WORLD, PoolLayout.load_from(), _species_cache)
	for id in later.tiles.tiles:
		for s in later.tiles.tiles[id].sites:
			var sizes: Array[int] = [2]
			s.sizes = sizes
	var gen2 := WorldGen.create(later, _species_cache, 401)
	var live := 0
	for k in _spiral(100):
		for s in gen2.chunk(1, k.x, k.y).sites:
			if s.id.begins_with("t_"):
				live += 1
	check_eq(live, 0, "sites of size 2 only are not live at size 1")


## G17: 500 cold chunks in spiral order from home. Each chunk is timed as the fastest of 3 runs, each
## on a new generator (so the chunk is cold in each), as the endless cost gates count a tick at its
## fastest of 3 runs, so a burst from another process cannot fail it; the yardstick runs after each.
func test_slow_cold_chunks_cost_at_most_150_us_median_and_300_us_max() -> void:
	var keys := _spiral(500)
	var best: Array[float] = []
	var ratio: Array[float] = []
	best.resize(keys.size())
	best.fill(INF)
	ratio.resize(keys.size())
	ratio.fill(INF)
	for run in 3:
		var gen := _gen(4242)
		for i in keys.size():
			var t0 := Time.get_ticks_usec()
			gen.chunk(1, keys[i].x, keys[i].y)
			var us := float(Time.get_ticks_usec() - t0)
			best[i] = minf(best[i], us)
			ratio[i] = minf(ratio[i], us / maxf(1.0, Yardstick.time_once()))
	var worst := 0
	for i in keys.size():
		if best[i] > best[worst]:
			worst = i
	var median := Yardstick.median(best)
	var median_ratio := Yardstick.median(ratio)
	var top := 0.0
	for r in ratio:
		top = maxf(top, r)
	print("test-world-gen: cold chunks median %.0f us (%.2f yardsticks), max %.0f us at %s (%.2f yardsticks max)"
		% [median, median_ratio, best[worst], keys[worst], top])
	check(median <= 150.0 and median_ratio <= 1.5, "median %.0f us, %.2f yardsticks" % [median, median_ratio])
	check(best[worst] <= 300.0 and top <= 3.0, "max %.0f us, %.2f yardsticks" % [best[worst], top])
