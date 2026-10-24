extends TestCase
## The seams and chunk purity, soak tier (docs/s1/s1-core.md 6.7 and 12.2, G4 and G6; CI's soak-b):
## every tile pair in every orientation across its seams, the home block's edges against every tile
## and orientation, and chunk purity over 5,000 chunks on each of four seeds. They run on T4's
## content once it exists (game/data/home_b0.json and game/data/tiles/b0) and on the fixture world
## before that. The checks themselves have their fast tests in tests/test_world_checks.gd.

const WorldChecks := preload("res://tests/world_checks.gd")
const REAL := "res://game/data/world_cell.json"
const FIXTURE := "res://tests/fixtures/world/world_min.json"
## T4's content; while any is missing the fixture world stands in.
const REAL_CONTENT: PackedStringArray = ["res://game/data/home_b0.json", "res://game/data/tiles/b0"]
const PURITY_SEEDS := [0, 1, 401, 4242]
const PURITY_CHUNKS := 5000
## The shared-route generator clears its memo this often; a fresh generator checks every FRESH_EVERY
## chunk.
const CLEAR_EVERY := 7
const FRESH_EVERY := 5

static var _content_cache: WorldContent = null
static var _species_cache: SpeciesCatalog = null
static var _parts_cache: PartCatalog = null


static func _world_path() -> String:
	for path in REAL_CONTENT:
		if not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path):
			return FIXTURE
	return REAL


## The real world when T4's content is in, else the fixture world; loaded once for the file.
static func _content() -> WorldContent:
	if _content_cache == null:
		_species_cache = SpeciesCatalog.load_from()
		_parts_cache = PartCatalog.load_from()
		_content_cache = WorldContent.load_from(_world_path(), PoolLayout.load_from(), _species_cache)
	return _content_cache


## The sizes this build runs.
static func _sizes(content: WorldContent) -> Array:
	return range(content.config.size_start, content.config.max_size_in_build + 1)


## Up to `limit` problems, one per line, for a failure message.
static func _head(problems: PackedStringArray, limit := 10) -> String:
	var shown := problems.slice(0, limit)
	var more := "" if problems.size() <= limit else "\n  ... and %d more" % (problems.size() - limit)
	return "\n  " + "\n  ".join(shown) + more


func test_soak_every_tile_pair_meets_rules_9_and_10_across_its_seams() -> void:
	var content := _content()
	check_eq(content.tiles.load_problems, PackedStringArray(), "the tiles load")
	var tiles := content.tiles.tiles.size()
	check(tiles >= 2, "a band of tiles (%d) from %s" % [tiles, _world_path()])
	for size in _sizes(content):
		var t0 := Time.get_ticks_msec()
		var problems := WorldChecks.tile_seam_problems(content, _species_cache, _parts_cache, size)
		print("test-seams: %s, size %d: %d tiles x 8 orientations, %d ordered pairs x 3 placements, %d problems, %d ms"
			% [_world_path().get_file(), size, tiles, tiles * tiles * 64, problems.size(), Time.get_ticks_msec() - t0])
		check(problems.is_empty(), "size %d: %d seam problems:%s" % [size, problems.size(), _head(problems)])


func test_soak_the_home_block_edges_meet_every_tile_and_orientation() -> void:
	var content := _content()
	check_eq(content.home.load_problems, PackedStringArray(), "the home block loads")
	for size in _sizes(content):
		var t0 := Time.get_ticks_msec()
		var problems := WorldChecks.home_seam_problems(content, _species_cache, _parts_cache, size)
		print("test-seams: %s, size %d: the home block's 8 edge slots x %d tiles x 8 orientations, %d problems, %d ms"
			% [_world_path().get_file(), size, content.tiles.tiles.size(), problems.size(), Time.get_ticks_msec() - t0])
		check(problems.is_empty(), "size %d: %d home edge problems:%s" % [size, problems.size(), _head(problems)])


## The route of PURITY_CHUNKS chunk keys for a seed: a random walk, a straight run far out, and
## jumps anywhere within a million chunks of the origin, in that order.
static func _route(seed_value: int) -> Array[Vector2i]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + seed_value
	var out: Array[Vector2i] = []
	var at := Vector2i(rng.randi_range(-40, 40), rng.randi_range(-40, 40))
	var walk := PURITY_CHUNKS * 2 / 5
	var run := PURITY_CHUNKS / 5
	for i in walk:
		out.append(at)
		at += [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)][rng.randi_range(0, 3)]
	var start := Vector2i(rng.randi_range(-50000, 50000), rng.randi_range(-50000, 50000))
	for i in run:
		out.append(start + Vector2i(i, -i / 2))
	while out.size() < PURITY_CHUNKS:
		out.append(Vector2i(rng.randi_range(-1000000, 1000000), rng.randi_range(-1000000, 1000000)))
	return out


## G6 at scale: on each seed, one generator walking the route forwards, one walking it backwards
## and clearing its memo every CLEAR_EVERY chunks, and a fresh generator for every FRESH_EVERY-th
## chunk all give each chunk the same digest.
func test_soak_chunk_purity_on_five_thousand_chunks_and_four_seeds() -> void:
	var content := _content()
	for size in _sizes(content):
		for seed_value in PURITY_SEEDS:
			var t0 := Time.get_ticks_msec()
			var route := _route(seed_value)
			var forward := WorldGen.create(content, _species_cache, seed_value)
			var backward := WorldGen.create(content, _species_cache, seed_value)
			var digests := PackedStringArray()
			var objects := 0
			for k in route:
				var c := forward.chunk(size, k.x, k.y)
				digests.append(c.digest())
				objects += c.shells.size() + c.zones.size() + c.sites.size() + c.anchors.size() + c.places.size()
			var differ := 0
			for j in route.size():
				var i := route.size() - 1 - j
				if j % CLEAR_EVERY == 0:
					backward.clear_memo()
				var k: Vector2i = route[i]
				var d := backward.chunk(size, k.x, k.y).digest()
				if i % FRESH_EVERY == 0 and d == digests[i]:
					d = WorldGen.create(content, _species_cache, seed_value).chunk(size, k.x, k.y).digest()
				if d != digests[i]:
					differ += 1
					if differ <= 3:
						check(false, "seed %d size %d: chunk %s differs between generators" % [seed_value, size, k])
			print("test-seams: chunk purity, seed %d size %d: %d chunks, %d objects, %d ms"
				% [seed_value, size, route.size(), objects, Time.get_ticks_msec() - t0])
			check_eq(differ, 0, "seed %d size %d: chunks that depend on the route or the memo" % [seed_value, size])
			check(objects > route.size(), "seed %d: the route holds objects (%d)" % [seed_value, objects])
