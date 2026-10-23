extends TestCase
## The endless world's generator (S1, docs/s1/s1-interfaces.md section 3.6): chunks are plain data
## with a stable digest, and the same inputs always give the same chunk.


func _content() -> WorldContent:
	return WorldContent.load_from(WorldConfig.DEFAULT_PATH, PoolLayout.load_from(), SpeciesCatalog.load_from())


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
	var gen := WorldGen.create(content, SpeciesCatalog.load_from(), 4242)
	check_eq(gen.world_seed, 4242, "seed")
	check_eq(gen.gen_version, content.config.gen_version, "gen_version from the world file")
	var c := gen.chunk(1, -3, 5)
	check_eq(c.key, Vector2i(-3, 5), "key")
	check_eq(c.size, 1, "size")
	check_eq(c.digest(), gen.chunk(1, -3, 5).digest(), "the same chunk twice")
