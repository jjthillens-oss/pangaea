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


## The thresholds are the region noise's measured third quantiles (core 0.2), so before the drift
## rule each region holds a third of the tiles (measured worst 0.026 off at this size).
func test_region_shares_are_a_third_each_before_the_drift_rule() -> void:
	var shares := _shares(_gen(401), 320, true)
	print("test-world-gen: raw shares at seed 401 over 320 x 320 tiles: %s" % [shares])
	for r in shares:
		check_near(shares[r], 1.0 / 3.0, 0.05, "%s share" % r)


## And on three more seeds, the final shares the coordinate rule keeps.
func test_slow_region_shares_are_a_third_each_on_four_seeds() -> void:
	for s in [0, 1, 401, 4242]:
		var shares := _shares(_gen(s), 320, true)
		print("test-world-gen: raw shares at seed %d: %s" % [s, shares])
		for r in shares:
			check_near(shares[r], 1.0 / 3.0, 0.05, "seed %d %s share" % [s, r])
		if s != 401:
			_check_final_shares(s)


static var _region_grids := {}


## Final regions of the ordinary rule over [-64, 64)^2 tiles, row-major, per seed.
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


## The coordinate rule (B-11) keeps drift near 14.8% (two thirds of the raw third), and every final
## region keeps at least 10% of the tiles. Over 320 x 320 tiles the reference measures 14.8% to 15.8%
## on eight seeds; a 128-tile square swings from 11% to 20%, too few lattice cells to judge.
func test_the_drift_share_after_the_rule_is_as_measured() -> void:
	_check_final_shares(401)


func _check_final_shares(seed_value: int) -> void:
	var shares := _shares(_gen(seed_value), 320, false)
	print("test-world-gen: final shares at seed %d over 320 x 320 tiles: %s" % [seed_value, shares])
	check(shares.drift >= 0.12 and shares.drift <= 0.18, "seed %d: drift share %.4f in [0.12, 0.18]" % [seed_value, shares.drift])
	for r in shares:
		check(shares[r] >= 0.10, "seed %d: %s keeps %.4f of the tiles, at least 0.10" % [seed_value, r, shares[r]])


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
## S2 (S2G12): the same fixture world at size 2, recorded with size 1 unchanged.
const DIGESTS_S2 := "res://tests/fixtures/world/chunk_digests_s2.json"
const Yardstick := preload("res://tests/cost_yardstick.gd")
const WorldChecks := preload("res://tests/world_checks.gd")


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


## The size-1 golden is S1's, untouched by S2's generator (BP-7: one-post sites carry no posts key);
## the size-2 golden pins sunk shells, dropped and thinned zones, k and scale x s (S2G12).
func test_the_chunk_digest_golden_holds() -> void:
	for path in [DIGESTS, DIGESTS_S2]:
		var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		check_eq(golden.world, WORLD, "the golden is of the fixture world")
		check_eq(int(golden.size), 1 if path == DIGESTS else 2, "its size")
		var gen := _gen(int(golden.seed))
		var homes := 0
		for e in golden.chunks:
			var k := Vector2i(int(e.key[0]), int(e.key[1]))
			check_eq(gen.chunk(int(golden.size), k.x, k.y).digest(), e.digest, "size %d chunk %s (%s)" % [golden.size, k, e.holds])
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
	for kind in PackedStringArray(TileCatalog.RARE_KINDS_BY_BAND[0]):
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
	var cost := _cold_chunk_costs(1)
	check(cost.median <= 150.0 and cost.median_ratio <= 1.5, "median %.0f us, %.2f yardsticks" % [cost.median, cost.median_ratio])
	check(cost.max <= 300.0 and cost.top <= 3.0, "max %.0f us, %.2f yardsticks" % [cost.max, cost.top])


## S2G37: G17 at size 2, where a chunk is part of up to four 40-tm tiles and each is emitted whole.
func test_slow_size_two_chunks_cost_at_most_300_us_median_and_600_us_max() -> void:
	var cost := _cold_chunk_costs(2)
	check(cost.median <= 300.0 and cost.median_ratio <= 3.5, "median %.0f us, %.2f yardsticks" % [cost.median, cost.median_ratio])
	check(cost.max <= 600.0 and cost.top <= 7.0, "max %.0f us, %.2f yardsticks" % [cost.max, cost.top])


## S3G20 (BP3-6): band 1's chunks on the shipped content at the size-4 top, measured in the same run
## as band 0's, the four sizes interleaved chunk by chunk so a slower stretch of the machine falls on
## all of them alike. The absolute rows are G17's at size 3 and S2G37's at size 4; they block, since
## both were green on e3-base (main's CI). The relative rows always block: size 3 against size 1 and
## size 4 against size 2, median and p90 at most 1.10 x, max at most 1.25 x (a single chunk, about
## +-9% between runs).
func test_slow_band_1_chunks_cost_as_band_0s() -> void:
	var catalog := SpeciesCatalog.load_from()
	var top := WorldContent.load_from(WorldChecks.shipped_world_at(4), PoolLayout.load_from(), catalog)
	var cost := _cold_chunk_costs_at([1, 3, 2, 4], func() -> WorldGen: return WorldGen.create(top, catalog, 4242))
	var limits := {3: [150.0, 1.5, 300.0, 3.0], 4: [300.0, 3.5, 600.0, 7.0]}
	for n in [3, 4]:
		var c: Dictionary = cost[n]
		var l: Array = limits[n]
		check(c.median <= l[0] and c.median_ratio <= l[1], "size %d: median %.0f us, %.2f yardsticks" % [n, c.median, c.median_ratio])
		check(c.max <= l[2] and c.top <= l[3], "size %d: max %.0f us, %.2f yardsticks" % [n, c.max, c.top])
		var base: Dictionary = cost[n - 2]
		for row in [["median", 1.10], ["p90", 1.10], ["max", 1.25]]:
			var ratio := float(c[row[0]]) / maxf(1.0, float(base[row[0]]))
			check(ratio <= row[1], "size %d against %d: %s %.0f us / %.0f us = %.2f x (at most %.2f)"
				% [n, n - 2, row[0], c[row[0]], base[row[0]], ratio, row[1]])


## G17's measure at size n: 500 chunks in spiral order, each its fastest of 3 runs on a new generator
## (the fixture world's) and its fastest ratio to the yardstick timed after it.
## {median, p90, median_ratio, max, top}.
func _cold_chunk_costs(n: int) -> Dictionary:
	return _cold_chunk_costs_at([n], func() -> WorldGen: return _gen(4242))[n]


## G17's measure at each of `sizes` in one pass: each run makes a new generator per size (`make`)
## and times each chunk at every size in turn before the next chunk. size -> {median, p90,
## median_ratio, max, top}.
func _cold_chunk_costs_at(sizes: Array, make: Callable) -> Dictionary:
	var keys := _spiral(500)
	var best := {}
	var ratio := {}
	for n in sizes:
		var b: Array[float] = []
		b.resize(keys.size())
		b.fill(INF)
		best[n] = b
		var r: Array[float] = []
		r.resize(keys.size())
		r.fill(INF)
		ratio[n] = r
	for run in 3:
		var gens := {}
		for n in sizes:
			gens[n] = make.call()
		for i in keys.size():
			for n in sizes:
				var t0 := Time.get_ticks_usec()
				(gens[n] as WorldGen).chunk(n, keys[i].x, keys[i].y)
				var us := float(Time.get_ticks_usec() - t0)
				best[n][i] = minf(best[n][i], us)
				ratio[n][i] = minf(ratio[n][i], us / maxf(1.0, Yardstick.time_once()))
	var out := {}
	for n in sizes:
		var b: Array[float] = best[n]
		var worst := 0
		for i in keys.size():
			if b[i] > b[worst]:
				worst = i
		var sorted := b.duplicate()
		sorted.sort()
		var p90: float = sorted[int(0.9 * (sorted.size() - 1))]
		var top := 0.0
		for r in ratio[n]:
			top = maxf(top, r)
		out[n] = {"median": Yardstick.median(b), "p90": p90, "median_ratio": Yardstick.median(ratio[n]), "max": b[worst], "top": top}
		print("test-world-gen: size %d cold chunks median %.0f us (%.2f yardsticks), p90 %.0f us, max %.0f us at %s (%.2f yardsticks max)"
			% [n, out[n].median, out[n].median_ratio, p90, b[worst], keys[worst], top])
	return out


# --- size 2 (S2 T3.3; docs/s2/s2-sim.md 3.10, build plan BP-7, BP-16) ---

## The objects of tile t (tile coordinates) at size n, by id: those of the chunks the tile covers whose
## id names the tile (s_0_tx_ty_*, z_0_tx_ty_*, t_0_tx_ty_*, p_0_tx_ty).
static func _tile_objects(gen: WorldGen, n: int, t: Vector2i) -> Dictionary:
	var tile_tm := 64.0 * WorldConfig.bu_to_tm(n)
	var tag := "0_%d_%d" % [t.x, t.y]
	var out := {}
	for ky in range(floori(t.y * tile_tm / 32.0), ceili((t.y + 1) * tile_tm / 32.0)):
		for kx in range(floori(t.x * tile_tm / 32.0), ceili((t.x + 1) * tile_tm / 32.0)):
			for o in _objects(gen.chunk(n, kx, ky)):
				var parts: PackedStringArray = str(o[1].id).split("_")
				if parts.size() >= 4 and "%s_%s_%s" % [parts[1], parts[2], parts[3]] == tag:
					out[o[1].id] = o[1]
	return out


## S2G12's pure function at size 2: a fresh generator per chunk, one shared and one cleared every 10
## chunks give equal digests along a spiral and a line.
func test_size_2_chunks_are_the_same_along_any_route() -> void:
	var line: Array[Vector2i] = []
	for i in 100:
		line.append(Vector2i(-50 + i, -4))
	var shared := _gen(401)
	var cleared := _gen(401)
	var differ := 0
	var objects := 0
	for route in [_spiral(100), line]:
		for i in route.size():
			var k: Vector2i = route[i]
			if i % 10 == 0:
				cleared.clear_memo()
			var a := _gen(401).chunk(2, k.x, k.y)
			objects += _objects(a).size()
			if a.digest() != shared.chunk(2, k.x, k.y).digest() or a.digest() != cleared.chunk(2, k.x, k.y).digest():
				differ += 1
	check_eq(differ, 0, "size-2 chunks that depend on the route or the memo")
	check(objects > 300, "the routes hold objects (%d)" % objects)


## S2G7 at the band's second size: a "sink" shell is not generated, a "drop" zone neither, a "thin"
## zone holds capacity x 0.4 (D-60) and a "keep" one its own; everything else is the size-1 object
## at 0.625 of its place and radius, with the same asset, yaw and tint, and its scale x 0.625 (BP-16).
func test_the_second_size_sinks_drops_and_thins() -> void:
	var gen := _shared_gen(401)
	var content := _content()
	var counts := {"sink": 0, "drop": 0, "thin": 0, "keep": 0}
	for i in 24:
		var t := Vector2i(i * 3 - 30, 17 - i * 2)
		var info := gen.tile_info(0, t.x, t.y)
		var data: Dictionary = content.tiles.tiles.get(info.id, {})
		if data.is_empty():
			continue
		var one := _tile_objects(gen, 1, t)
		var two := _tile_objects(gen, 2, t)
		var prefix := "0_%d_%d_" % [t.x, t.y]
		for sh in data.shells:
			var a: Dictionary = one.get("s_" + prefix + sh.id, {})
			var b: Dictionary = two.get("s_" + prefix + sh.id, {})
			check(not a.is_empty(), "%s shell %s at size 1" % [info.id, sh.id])
			if sh.at_second_size == "sink":
				counts.sink += 1
				check(b.is_empty(), "%s shell %s sinks at size 2" % [info.id, sh.id])
				continue
			check(not b.is_empty() and b.x == a.x * 0.625 and b.y == a.y * 0.625 and b.r == a.r * 0.625
				and b.scale == a.scale * 0.625 and b.asset == a.asset and b.yaw_deg == a.yaw_deg and b.tint == a.tint,
				"%s shell %s: %s against %s" % [info.id, sh.id, b, a])
		for z in data.zones:
			var a: Dictionary = one.get("z_" + prefix + z.id, {})
			var b: Dictionary = two.get("z_" + prefix + z.id, {})
			counts[z.at_second_size] += 1
			if z.at_second_size == "drop":
				check(b.is_empty(), "%s zone %s is dropped at size 2" % [info.id, z.id])
				continue
			var capacity: float = float(z.capacity) * (0.4 if z.at_second_size == "thin" else 1.0)
			check(not b.is_empty() and b.capacity == capacity and a.capacity == float(z.capacity) and b.radius == a.radius * 0.625
				and b.x == a.x * 0.625 and b.growth_rate == a.growth_rate, "%s zone %s (%s): %s against %s" % [info.id, z.id, z.at_second_size, b, a])
	check(counts.sink > 5 and counts.drop > 1 and counts.thin > 5 and counts.keep > 5, "every kind met: %s" % counts)
	# The home block's ring: its thin zones too; the M1 zones keep.
	var home := {}
	for cy in range(-2, 2):
		for cx in range(-2, 2):
			for o in _objects(gen.chunk(2, cx, cy)):
				home[o[1].id] = o[1]
	var thin := 0
	for z in content.home.zones:
		var e: Dictionary = home.get(z.id if z.m1 else "z_h_%s" % z.id, {})
		var want: float = float(z.capacity) * (0.4 if z.at_second_size == "thin" else 1.0)
		thin += 1 if z.at_second_size == "thin" else 0
		check(not e.is_empty() and e.capacity == want, "home zone %s (%s): %s" % [z.id, z.at_second_size, e])
	check(thin > 0, "the fixture ring has thin zones")


## The home block's ring at size 2: a "sink" ring shell and a "drop" ring zone are not generated, the
## rest are (the fixture ring keeps every shell, so one of each is changed on a fresh content).
func test_the_home_ring_sinks_and_drops_at_size_2() -> void:
	var content := WorldContent.load_from(WORLD, PoolLayout.load_from(), _species_cache)
	var ring: Array = content.home.shells.filter(func(e: Dictionary) -> bool: return not e.fixed)
	var zones: Array = content.home.zones.filter(func(e: Dictionary) -> bool: return not e.m1 and e.at_second_size == "keep")
	ring[0].at_second_size = "sink"
	zones[0].at_second_size = "drop"
	var gen := WorldGen.create(content, _species_cache, 401)
	var at := {1: {}, 2: {}}
	for n in [1, 2]:
		for cy in range(-3, 3):
			for cx in range(-3, 3):
				for o in _objects(gen.chunk(n, cx, cy)):
					at[n][o[1].id] = o[1]
	for e in ring:
		var id: String = "s_h_" + e.id
		check(at[1].has(id) and at[2].has(id) != (e.at_second_size == "sink"), "ring shell %s (%s)" % [id, e.at_second_size])
	for e in content.home.zones:
		var id: String = e.id if e.m1 else "z_h_" + e.id
		check(at[1].has(id) and at[2].has(id) != (e.at_second_size == "drop"), "home zone %s (%s)" % [id, e.at_second_size])


## An M1 site at size 2 is its size-1 record at 0.625: k is 1 for an entry-size-1 species in band 0,
## so its bu discs are the same and only the placing scales. One-post sites carry no posts key.
func test_m1_sites_at_size_2_scale_their_discs_by_s() -> void:
	var gen := _shared_gen(401)
	var checked := 0
	for i in 30:
		var t := Vector2i(i * 5 - 70, 9 - i)
		var one := _tile_objects(gen, 1, t)
		var two := _tile_objects(gen, 2, t)
		for id in one:
			if not str(id).begins_with("t_"):
				continue
			var a: Dictionary = one[id]
			var b: Dictionary = two.get(id, {})
			if not (a.sizes as Array).has(2):
				check(b.is_empty(), "%s is not live at size 2" % id)
				continue
			check(not b.is_empty() and b.x == a.x * 0.625 and b.reach.radius == a.reach.radius * 0.625
				and b.reach.x == a.reach.x * 0.625 and b.heading == a.heading, "%s: %s against %s" % [id, b, a])
			check(not b.has("posts") and not a.has("posts"), "%s has no posts" % id)
			if not a.territory.is_empty():
				check(b.territory.radius == a.territory.radius * 0.625, "%s territory" % id)
			checked += 1
	check(checked > 10, "sites checked: %d" % checked)


## BP-16: a mesh's scale is x s wherever its radius is: shells (radius / footprint, so r / footprint at
## either size), set pieces (s), landmarks (the dressing's scale x s) and the home block's M1 rocks
## (the layout's scale x s).
func test_every_scale_is_times_s_at_size_2() -> void:
	var gen := _shared_gen(401)
	var kit := _content().kit
	var kinds := {}
	var keys: Array[Vector2i] = [Vector2i(1, 1), Vector2i(3, -1), Vector2i(0, -8)]
	for cy in range(-2, 2):
		for cx in range(-2, 2):
			keys.append(Vector2i(cx, cy))
	var rocks := {}
	for r in _content().layout.rocks:
		rocks[r.id] = float(r.scale)
	for k in keys:
		for s in gen.chunk(2, k.x, k.y).shells:
			kinds[s.kind] = true
			match s.kind:
				"set_piece":
					check_eq(s.scale, 0.625, "%s: a set piece at s" % s.id)
				"landmark":
					# The same landmark at size 1, in the chunk its size-1 place lies in.
					var at := Vector2i(floori(s.x / 0.625 / 32.0), floori(s.y / 0.625 / 32.0))
					var one: Array = gen.chunk(1, at.x, at.y).shells.filter(func(e: Dictionary) -> bool: return e.id == s.id)
					check(one.size() == 1 and s.scale == float(one[0].scale) * 0.625 and s.tint == one[0].tint,
						"%s: a landmark's scale %s is its dressing's %s x 0.625" % [s.id, s.scale, one])
				"shell":
					if rocks.has(s.id):
						check_eq(s.scale, rocks[s.id] * 0.625, "M1 rock %s" % s.id)
					else:
						check(is_equal_approx(s.scale, s.r / float(kit.assets[s.asset].footprint_radius_m)), "%s: scale %s, r %s" % [s.id, s.scale, s.r])
	check_eq(kinds.size(), 3, "shells, set pieces and a landmark met: %s" % [kinds.keys()])
	# A slot no kit shell fits gets no asset and scale 1 at size 1, so 0.625 at size 2.
	var bare := WorldContent.load_from(WORLD, PoolLayout.load_from(), _species_cache)
	for id in bare.kit.assets:
		bare.kit.assets[id].pickable = false
	var unfit := WorldGen.create(bare, _species_cache, 401)
	var met := {1: 0, 2: 0}
	for n in [1, 2]:
		for k in keys:
			for s in unfit.chunk(n, k.x, k.y).shells:
				if s.kind == "shell" and not rocks.has(s.id):
					check(s.asset == "" and s.scale == (1.0 if n == 1 else 0.625), "size %d unfit %s: scale %s" % [n, s.id, s.scale])
					met[n] += 1
	check(met[1] > 5 and met[2] > 5, "unfit shells met: %s" % met)



## D-38, D-82 on the chunk side: a two-post site's record carries `posts`, its first post the site
## itself (place, heading, territory) and its second the site's post_b placed and oriented like its
## home, with post_b's zone as its territory; its reach is the union of the two posts' reach discs at
## k 1.6 (an entry-size-2 species in band 0) and lists every chunk the union touches. One-post sites
## carry no posts, and a size-2 site is not generated at size 1. The fixture world with the two
## two-post fixture tiles added (tests/fixtures/world/tiles_s2).
func test_two_post_sites_carry_both_posts_and_reach_over_their_union() -> void:
	var species := WorldChecks.s2_species()
	var content := WorldContent.load_from(WORLD, PoolLayout.load_from(), species)
	for id in ["reef_posts", "sunlit_posts"]:
		var path := "res://tests/fixtures/world/tiles_s2/b0/%s.json" % id
		content.tiles.add_tile(JSON.parse_string(FileAccess.get_file_as_string(path)), 0, id)
	check_eq(content.tiles.load_problems, PackedStringArray(), "the fixture tiles load")
	var gen := WorldGen.create(content, species, 401)
	var k := 1.6
	var met := {"lk": 0, "er": 0}
	var orientations := {}
	for ty in range(-12, 12):
		for tx in range(-12, 12):
			var info := gen.tile_info(0, tx, ty)
			if not info.id in ["reef_posts", "sunlit_posts"]:
				continue
			var t: Dictionary = content.tiles.tile(info.id)
			var o: int = info.orientation
			orientations[o] = true
			var cx := 32.0 * (2 * tx + 1)
			var cy := 32.0 * (2 * ty + 1)
			var two := _tile_objects(gen, 2, Vector2i(tx, ty))
			var one := _tile_objects(gen, 1, Vector2i(tx, ty))
			var prefix := "0_%d_%d_" % [tx, ty]
			for site in t.sites:
				var id: String = "t_" + prefix + site.id
				var r: Dictionary = two.get(id, {})
				check(r.is_empty() != (site.sizes as Array).has(2), "%s at size 2 as its sizes %s say" % [id, site.sizes])
				if r.is_empty():
					check(one.has(id) and not one[id].has("posts"), "%s at size 1, with no posts" % id)
					continue
				if site.post_b.is_empty():
					check(not r.has("posts") and not one.get(id, {}).has("posts"), "%s: a one-post site has no posts" % id)
					continue
				met[site.id] += 1
				check(not one.has(id), "%s: a size-2 site is not generated at size 1" % id)
				var posts: Array = r.get("posts", [])
				check_eq(posts.size(), 2, "%s: two posts" % id)
				if posts.size() != 2:
					continue
				check_eq(posts[0], {"x": r.x, "y": r.y, "heading": r.heading, "territory": r.territory}, "%s: post a is the site" % id)
				var p := WorldGen.orient_point(site.post_b.home[0], site.post_b.home[1], o)
				check(posts[1].x == (cx + p[0]) * 0.625 and posts[1].y == (cy + p[1]) * 0.625
					and posts[1].heading == WorldGen.orient_heading(float(site.post_b.heading), o), "%s post b: %s" % [id, posts[1]])
				# Each post's territory is its zone's chunk record.
				for i in 2:
					var zone_id: String = [site.get("territory_zone", ""), site.post_b.get("territory_zone", "")][i]
					var want := {}
					if not zone_id.is_empty():
						var z: Dictionary = two.get("z_" + prefix + zone_id, {"x": NAN, "y": NAN, "radius": NAN})
						want = {"x": z.x, "y": z.y, "radius": z.radius}
					check_eq(posts[i].territory, want, "%s post %d territory" % [id, i])
				# The reach: the union of the posts' reach discs at k, in tm.
				var discs := []
				var discs_k1 := []
				for i in 2:
					var post: Dictionary = posts[i]
					var at := {"species": site.species, "home": Vector2(post.x, post.y) / 0.625, "heading": post.heading}
					var terr := {}
					if not post.territory.is_empty():
						terr = {"center": Vector2(post.territory.x, post.territory.y) / 0.625, "radius": post.territory.radius / 0.625}
					discs.append(species.reach_disc_for(at, terr, k))
					discs_k1.append(species.reach_disc_for(at, terr, 1.0))
				var union := CreatureBrain.union_disc(discs[0], discs[1])
				check(is_equal_approx(r.reach.radius, union.radius * 0.625) and is_equal_approx(r.reach.radius / 0.625, union.radius)
					and absf(r.reach.x - union.center.x * 0.625) < 1e-6 and absf(r.reach.y - union.center.y * 0.625) < 1e-6,
					"%s reach %s is the union %s x 0.625" % [id, r.reach, union])
				var union_k1 := CreatureBrain.union_disc(discs_k1[0], discs_k1[1])
				check(float(r.reach.radius) > float(union_k1.radius) * 0.625 + 0.5, "%s: k 1.6 widens the reach (%s at k 1)" % [id, union_k1])
				check_eq(r.chunks, WorldGen.disc_chunks(r.reach.x, r.reach.y, r.reach.radius, 32.0), "%s: the union's chunks" % id)
	check(met.lk >= 3 and met.er >= 3 and orientations.size() >= 4, "two-post sites met %s in orientations %s" % [met, orientations.keys()])


# --- S3 (T3.5; docs/s3: spine 5.5 and 5.6, s3-sim 3.11): band 1 ---

const WORLD_B1 := "res://tests/fixtures/world/world_b1_min.json"
const B1_REGIONS: PackedStringArray = ["veil_garden", "warden_flat", "glass_reef"]
const BLOOM_CYCLE_TICKS := 5400

static var _b1_cache: WorldContent = null


## world_b1_min.json (band 0 as world_min.json, band 1's fixture tiles and the cradle) with the
## shipped kit, which holds both bands (T3.2; the fixture kit is band 0's only).
static func _b1_content() -> WorldContent:
	if _b1_cache == null:
		_content()
		_b1_cache = WorldContent.load_from(WORLD_B1, PoolLayout.load_from(), _species_cache)
		_b1_cache.kit = PlacementKit.load_from()
	return _b1_cache


static func _b1_gen(seed_value: int) -> WorldGen:
	return WorldGen.create(_b1_content(), _species_cache, seed_value)


## Every chunk of [x0, x1) x [y0, y1) at size n, merged: {shells, zones, sites, morsel_sites, anchors,
## places} by id.
static func _area(gen: WorldGen, n: int, x0: int, x1: int, y0: int, y1: int) -> Dictionary:
	var out := {"shells": {}, "zones": {}, "sites": {}, "morsel_sites": {}, "anchors": {}, "places": {}}
	for cy in range(y0, y1):
		for cx in range(x0, x1):
			var c := gen.chunk(n, cx, cy)
			for kind in out:
				for item in c.get(kind):
					out[kind][item.id] = item
	return out


func test_band_1_has_its_own_regions_and_fixed_rare() -> void:
	var gen := _b1_gen(401)
	var counts := {}
	for ty in range(-24, 24):
		for tx in range(-24, 24):
			var info := gen.tile_info(1, tx, ty)
			counts[info.region] = int(counts.get(info.region, 0)) + 1
			if info.region == "rare":
				check(TileCatalog.RARE_KINDS_BY_BAND[1].has(info.rare), "a band-1 rare kind at %s (%s)" % [Vector2i(tx, ty), info.rare])
	for region in counts:
		check(B1_REGIONS.has(region) or region in ["home", "rare"], "band 1's regions only (%s)" % region)
	for region in B1_REGIONS:
		var share := float(counts.get(region, 0)) / (48.0 * 48.0)
		check(share > 0.2 and share < 0.45, "%s holds about a third (%.3f): band 1 has no drift rule" % [region, share])
	var fixed := gen.tile_info(1, 2, -1)
	check_eq([fixed.region, fixed.rare, fixed.orientation], ["rare", "sunbeam_well", 0], "band 1's fixed rare (arrangement.bands)")
	check_eq(gen.tile_info(0, 2, -1).rare, _gen(401).tile_info(0, 2, -1).rare, "band 0's is the file's own")
	for ty in range(-6, 6):
		for tx in range(-6, 6):
			check_eq(gen.tile_info(0, tx, ty), _gen(401).tile_info(0, tx, ty), "band 0 unchanged at %s" % Vector2i(tx, ty))


## S3G39: band-1 chunks at sizes 3 and 4 are the same from a fresh generator, a shared one, one cleared
## every 10 chunks and one that first walked the route at sizes 1 and 2 (a band-up).
func test_band_1_chunks_are_the_same_along_any_route() -> void:
	var line: Array[Vector2i] = []
	for i in 80:
		line.append(Vector2i(-40 + i, 5))
	for n in [3, 4]:
		var shared := _b1_gen(401)
		var cleared := _b1_gen(401)
		var differ := 0
		var objects := 0
		for route in [_spiral(80), line]:
			var walked := _b1_gen(401)
			for i in route.size():
				var k: Vector2i = route[i]
				if i % 10 == 0:
					cleared.clear_memo()
				walked.chunk(1, k.x, k.y)
				walked.chunk(2, k.x, k.y)
				var a := _b1_gen(401).chunk(n, k.x, k.y)
				objects += _objects(a).size() + a.morsel_sites.size()
				var d := a.digest()
				if d != shared.chunk(n, k.x, k.y).digest() or d != cleared.chunk(n, k.x, k.y).digest() \
						or d != walked.chunk(n, k.x, k.y).digest():
					differ += 1
		check_eq(differ, 0, "size-%d chunks that depend on the route, the memo or the sizes before" % n)
		check(objects > 300, "size %d: the routes hold objects (%d)" % [n, objects])


## D-97: a site is placed by its ladder role at the size; a morsel site is food with the species'
## radius (at most morsel_max_radius_tm) and carcass.energy x r / 0.5 (X3-23), none at size 3.
func test_sites_are_placed_by_their_role() -> void:
	var gen := _b1_gen(401)
	var tol := _species_cache.share_tolerance()
	for n in [3, 4]:
		var area := _area(gen, n, -12, 12, -12, 12)
		check(area.sites.size() > 20, "size %d places creature sites (%d)" % [n, area.sites.size()])
		for id in area.sites:
			var sp: String = area.sites[id].species
			var role := Relationships.ladder_role(_species_cache.entry_size(sp), n, _species_cache.radius_at(sp, n), tol)
			check(role in ["threat", "rival", "prey"], "site %s (%s) is a creature at %d (%s)" % [id, sp, n, role])
		if n == 3:
			check_eq(area.morsel_sites.size(), 0, "no morsel site at size 3 (D-135)")
			continue
		check(area.morsel_sites.size() > 5, "size 4 places morsel sites (%d)" % area.morsel_sites.size())
		for id in area.morsel_sites:
			var m: Dictionary = area.morsel_sites[id]
			var r := _species_cache.radius_at(m.species, 4)
			check(str(id).begins_with("m_1_") or str(id).begins_with("m_c_"), "a placed morsel id (%s)" % id)
			check_eq(Relationships.ladder_role(_species_cache.entry_size(m.species), 4, r, tol), "morsel", "%s is a morsel" % id)
			check_eq(m.radius, minf(r, 0.225), "%s radius" % id)
			check_eq(m.energy, float(_species_cache.species[m.species].carcass.energy) * r / Relationships.PLAYER_RADIUS, "%s energy" % id)
			check(str(m.key).ends_with("/" + str(id).get_slice("_", str(id).get_slice_count("_") - 1)), "%s key names its site (%s)" % [id, m.key])
	var c := gen.chunk(4, 0, 0)
	var with_morsels: WorldChunk = null
	for cy in range(-12, 12):
		for cx in range(-12, 12):
			var k := gen.chunk(4, cx, cy)
			if with_morsels == null and not k.morsel_sites.is_empty():
				with_morsels = k
	check(with_morsels != null and with_morsels.to_dict().has("morsel_sites"), "a chunk with morsel sites lists them")
	check(not gen.chunk(3, 5, 5).to_dict().has("morsel_sites"), "a chunk without keeps its S2 shape")
	check(c != null, "")


## D-104, D-128, S3G15b (gen part): an elder Warden's placed site and its two meadows share one bloom
## phase (slot 0 its territory zone, slot 1 its second post's), hashed from the placed id, so two
## placements of one tile bloom out of step; nothing blooms at size 3.
func test_an_elder_wardens_site_and_meadows_share_one_bloom_phase() -> void:
	var gen := _b1_gen(401)
	var at_3 := _area(gen, 3, -8, 8, -8, 8)
	check(at_3.zones.values().all(func(z: Dictionary) -> bool: return not z.has("bloom")), "no bloom at size 3")
	var area := _area(gen, 4, -16, 16, -16, 16)
	var phases := {}       # placed site id -> offset
	var by_tile := {}      # tile id -> [offsets of its placements]
	for id in area.sites:
		var site: Dictionary = area.sites[id]
		check_eq(site.has("bloom"), site.species == "elder_warden", "%s has a bloom phase exactly when it is an elder Warden" % id)
		if site.has("bloom"):
			check_eq(site.bloom.cycle_ticks, BLOOM_CYCLE_TICKS, "a 90 s cycle")
			check(site.bloom.offset_ticks >= 0 and site.bloom.offset_ticks < BLOOM_CYCLE_TICKS, "the offset within the cycle")
			phases[id] = site.bloom.offset_ticks
	check(phases.size() > 4, "elder Wardens placed (%d)" % phases.size())
	var slots := {}
	for id in area.zones:
		var z: Dictionary = area.zones[id]
		if not z.has("bloom"):
			continue
		var prefix := "t_c_" if str(id).begins_with("z_c_") else "t_1_%d_%d_" % [z.tile.x, z.tile.y]
		var owners := phases.keys().filter(func(sid: String) -> bool:
			return sid.begins_with(prefix) and phases[sid] == z.bloom.offset_ticks)
		check_eq(owners.size(), 1, "meadow %s has its elder Warden's phase (%s)" % [id, z.bloom])
		if owners.size() == 1:
			if not slots.has(owners[0]):
				slots[owners[0]] = []
			slots[owners[0]].append(z.bloom.slot)
	var two := 0
	for sid in slots:
		var got: Array = slots[sid]
		got.sort()
		if got == [0, 1]:
			two += 1
		var tile_id := _tile_id_of(gen, sid)
		if not tile_id.is_empty():
			if not by_tile.has(tile_id):
				by_tile[tile_id] = []
			by_tile[tile_id].append(phases[sid])
	check(two > 4, "elder Wardens with both meadows in view bloom slots 0 and 1 (%d)" % two)
	var out_of_step := 0
	for tile_id in by_tile:
		var offsets: Array = by_tile[tile_id]
		if offsets.size() > 1 and offsets.min() != offsets.max():
			out_of_step += 1
	check(out_of_step > 0, "two placements of one tile bloom out of step (%s)" % [by_tile])


## The tile id a placed tile site id ("t_1_<tx>_<ty>_<site>") was placed from, or "" for the cradle's.
static func _tile_id_of(gen: WorldGen, site_id: String) -> String:
	var parts := site_id.split("_")
	if parts[1] != "1":
		return ""
	return gen.tile_info(1, int(parts[2]), int(parts[3])).id


## D-94, D-138: at band 1 the home tiles hold the cradle, not the band-0 home block: its shells,
## zones and sites by role, ids "s_c_", "z_c_", "t_c_" and "m_c_", region home, tile its quadrant; sunk
## shells and dropped zones gone at size 4.
func test_the_cradle_takes_the_home_tiles_at_band_1() -> void:
	var gen := _b1_gen(401)
	var cradle := _b1_content().cradle_of(1)
	check(cradle != null and cradle.load_problems.is_empty(), "the cradle is loaded")
	for n in [3, 4]:
		var area := _area(gen, n, -3, 3, -3, 3)
		var second: bool = n == 4
		var shells: Array = area.shells.keys().filter(func(id: String) -> bool: return id.begins_with("s_c_"))
		var want_shells: Array = cradle.shells.filter(func(s: Dictionary) -> bool: return not (second and s.at_second_size == "sink"))
		check_eq(shells.size(), want_shells.size(), "size %d: the cradle's shells" % n)
		var zones: Array = area.zones.keys().filter(func(id: String) -> bool: return id.begins_with("z_c_"))
		var want_zones: Array = cradle.zones.filter(func(z: Dictionary) -> bool: return not (second and z.at_second_size == "drop"))
		check_eq(zones.size(), want_zones.size(), "size %d: the cradle's zones" % n)
		for id in zones:
			var z: Dictionary = area.zones[id]
			check_eq(z.region, "home", "%s is home" % id)
			var src: Dictionary = _item_of(cradle.zones, id.trim_prefix("z_c_"))
			check_eq(z.tile, CradleBlock.quadrant_of(src.center[0], src.center[1]), "%s in its quadrant" % id)
			check_eq([z.x, z.y], [src.center[0] * WorldConfig.bu_to_tm(n), src.center[1] * WorldConfig.bu_to_tm(n)], "%s at its place x s" % id)
		var placed: Array = area.sites.keys().filter(func(id: String) -> bool: return id.begins_with("t_c_"))
		var morsels: Array = area.morsel_sites.keys().filter(func(id: String) -> bool: return id.begins_with("m_c_"))
		var creatures := 0
		var food := 0
		for s in cradle.sites:
			if not (s.sizes as Array).has(n):
				continue
			var role := TileCatalog.site_role(_species_cache, s, n)
			creatures += 1 if role in ["threat", "rival", "prey"] else 0
			food += 1 if role == "morsel" else 0
		check_eq([placed.size(), morsels.size()], [creatures, food], "size %d: its creature and morsel sites" % n)
		check(not area.shells.keys().any(func(id: String) -> bool: return id.begins_with("s_h_")), "no band-0 ring shell")
		check(not area.zones.values().any(func(z: Dictionary) -> bool: return not str(z.id).begins_with("z_c_") and z.region == "home"),
			"no band-0 home zone")


static func _item_of(list: Array, id: String) -> Dictionary:
	for item in list:
		if item.id == id:
			return item
	return {}


## S3G29 (helper part), V3-21: landmark_piece and rare_piece are where the band's chunks put the anchor
## and the place, at both sizes of the band (1e-9 tm), with the same id, model, dressing, yaw, scale
## (x s), kind, yaw and mirror; band 0 on world_min, band 1 on world_b1_min.
func test_the_old_band_pieces_are_where_the_chunks_put_them() -> void:
	for b in [0, 1]:
		var gen := _gen(401) if b == 0 else _b1_gen(401)
		var anchors := 0
		var places := 0
		for n in [2 * b + 1, 2 * b + 2]:
			var s := WorldConfig.bu_to_tm(n)
			for ly in range(-4, 4):
				for lx in range(-4, 4):
					var piece := gen.landmark_piece(b, lx, ly)
					if piece.is_empty():
						check(gen.landmark_of_cell(b, lx, ly).is_empty(), "a cell with a landmark has a piece")
						continue
					var c := gen.chunk(n, floori(piece.x_bu * s / 32.0), floori(piece.y_bu * s / 32.0))
					var found := c.anchors.filter(func(a: Dictionary) -> bool: return a.id == piece.id)
					check_eq(found.size(), 1, "band %d size %d: anchor %s in its chunk" % [b, n, piece.id])
					if found.size() != 1:
						continue
					var a: Dictionary = found[0]
					check(absf(a.x - piece.x_bu * s) <= 1e-9 and absf(a.y - piece.y_bu * s) <= 1e-9, "%s at x s" % piece.id)
					check_eq([a.model, a.dressing, a.tile], [piece.model, piece.dressing, piece.tile], "%s model" % piece.id)
					var lm := c.shells.filter(func(sh: Dictionary) -> bool: return sh.kind == "landmark" and sh.x == a.x and sh.y == a.y)
					check_eq([lm[0].yaw_deg, lm[0].scale, lm[0].r], [piece.yaw_deg, piece.scale * s, piece.collide_r_bu * s], "%s yaw, scale and collider" % piece.id)
					anchors += 1
			for by in range(-2, 2):
				for bx in range(-2, 2):
					var piece := gen.rare_piece(b, bx, by)
					check(not piece.is_empty(), "band %d block %s has a rare place" % [b, Vector2i(bx, by)])
					if piece.is_empty():
						continue
					var c := gen.chunk(n, floori(piece.x_bu * s / 32.0), floori(piece.y_bu * s / 32.0))
					var found := c.places.filter(func(p: Dictionary) -> bool: return p.id == piece.id)
					check_eq(found.size(), 1, "band %d size %d: place %s in its chunk" % [b, n, piece.id])
					if found.size() != 1:
						continue
					var p: Dictionary = found[0]
					check(absf(p.x - piece.x_bu * s) <= 1e-9 and absf(p.y - piece.y_bu * s) <= 1e-9, "%s at x s" % piece.id)
					check_eq([p.kind, p.yaw_deg, p.mirror, p.tile], [piece.kind, piece.yaw_deg, piece.mirror, piece.tile], "%s" % piece.id)
					places += 1
		check(anchors > 20 and places == 32, "band %d: anchors %d, places %d" % [b, anchors, places])


## C3V-8: old_pool_pieces is the shipped home block as its size-1 chunks draw it: the 18 M1 rocks and
## the 8 ring shells, with their assets, yaws and scales.
func test_old_pool_pieces_are_the_home_blocks_shells() -> void:
	var content := WorldContent.load_from(WorldConfig.DEFAULT_PATH, PoolLayout.load_from(), _species_cache)
	var gen := WorldGen.create(content, _species_cache, 401)
	var pieces := gen.old_pool_pieces()
	var rocks := pieces.filter(func(p: Dictionary) -> bool: return not str(p.id).begins_with("s_h_"))
	check_eq([rocks.size(), pieces.size() - rocks.size()], [18, 8], "18 rocks and 8 ring shells")
	var drawn := {}
	for cy in range(-2, 2):
		for cx in range(-2, 2):
			for sh in gen.chunk(1, cx, cy).shells:
				drawn[sh.id] = sh
	for p in pieces:
		check(drawn.has(p.id), "%s is drawn at size 1" % p.id)
		if not drawn.has(p.id):
			continue
		var d: Dictionary = drawn[p.id]
		check_eq([p.x_bu, p.y_bu, p.r_bu, p.asset, p.yaw_deg, p.scale], [d.x, d.y, d.r, d.asset, d.yaw_deg, d.scale], "%s as drawn" % p.id)


func test_the_touching_helpers_list_cells_and_blocks() -> void:
	check_eq(WorldGen.landmark_cells_touching(Rect2(10.0, 10.0, 20.0, 20.0), 2, 64.0), [Vector2i(0, 0)] as Array[Vector2i], "inside one cell")
	check_eq(WorldGen.landmark_cells_touching(Rect2(-10.0, 120.0, 20.0, 20.0), 2, 64.0),
		[Vector2i(-1, 0), Vector2i(0, 0), Vector2i(-1, 1), Vector2i(0, 1)] as Array[Vector2i], "across both lines, sorted by (y, x)")
	check_eq(WorldGen.rare_blocks_touching(Rect2(-10.0, -10.0, 20.0, 20.0), 6, -3, 64.0), [Vector2i(0, 0)] as Array[Vector2i], "block (0, 0) from tile -3")
	check_eq(WorldGen.rare_blocks_touching(Rect2(-250.0, 0.0, 10.0, 10.0), 6, -3, 64.0), [Vector2i(-1, 0)] as Array[Vector2i], "west of tile -3")
	check_eq(WorldGen.rare_blocks_touching(Rect2(-200.0, 0.0, 10.0, 10.0), 6, -3, 64.0), [Vector2i(-1, 0), Vector2i(0, 0)] as Array[Vector2i],
		"across tile -3's west edge (-192 bu)")


## BP3-8: reach_max_threat(n) is the largest reach plus body over the band's sites live at n whose
## species is the cell's size there: at 4, an elder Warden's union disc and body (the plan's 14.55 tm
## is D-147's widest spacing; the fixture's posts give 13.31).
func test_reach_max_threat_is_the_widest_live_threat() -> void:
	var content := _b1_content()
	var at_4 := content.reach_max_threat(4, _species_cache)
	check(at_4 > 12.5 and at_4 < 14.6, "size 4: an elder Warden's union and body, at most 14.55 tm (%.3f)" % at_4)
	var at_3 := content.reach_max_threat(3, _species_cache)
	check(at_3 > 7.5, "size 3: a veil or a Warden (%.3f)" % at_3)
	check(_content().reach_max_threat(1, _species_cache) > 0.0, "size 1 on band 0")
