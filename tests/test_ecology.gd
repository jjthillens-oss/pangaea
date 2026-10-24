extends TestCase


func _region(seed_value: int = 7) -> EcologyRegion:
	var region := EcologyRegion.create(seed_value)
	region.add_zone("shallows", Vector2(5.0, 5.0), 4.0, 100.0, 0.2)
	return region


func test_taking_food_depletes_a_zone_and_never_goes_negative() -> void:
	var region := _region()
	check_near(region.take("shallows", 30.0), 30.0, 0.0001, "took 30")
	check_near(region.zone("shallows").amount, 70.0, 0.0001, "70 left")
	check_near(region.take("shallows", 500.0), 70.0, 0.0001, "only what is left")
	check_near(region.zone("shallows").amount, 0.0, 0.0001, "empty")
	check_near(region.take("nowhere", 5.0), 0.0, 0.0001, "unknown zone gives nothing")


func test_an_emptied_zone_regrows_to_capacity_and_no_further() -> void:
	var region := _region()
	region.take("shallows", 100.0)
	region.tick(1.0)
	var after_one: float = region.zone("shallows").amount
	check(after_one > 0.0, "regrows from empty")
	for i in 600:
		region.tick(0.5)
	check_near(region.zone("shallows").amount, 100.0, 0.001, "back to capacity")
	region.tick(10.0)
	check(region.zone("shallows").amount <= 100.0, "never above capacity")


func test_growth_is_fastest_at_half_capacity() -> void:
	var gains := {}
	for fill in [5.0, 50.0, 95.0]:
		var region := _region()
		region.take("shallows", 100.0 - fill)
		region.tick(0.1)
		gains[fill] = region.zone("shallows").amount - fill
	check(gains[50.0] > gains[5.0], "faster at half than nearly empty")
	check(gains[50.0] > gains[95.0], "faster at half than nearly full (not plain exponential growth)")


func test_zones_that_could_never_feed_are_refused() -> void:
	var region := _region()
	check(not region.add_zone("dead", Vector2.ZERO, 3.0, 0.0, 0.2), "zero capacity")
	check(not region.add_zone("frozen", Vector2.ZERO, 3.0, 50.0, 0.0), "no growth")
	check(not region.add_zone("dot", Vector2.ZERO, 0.0, 50.0, 0.2), "no area")
	check(not region.add_zone("shallows", Vector2.ZERO, 3.0, 50.0, 0.2), "repeated id")
	check(not region.add_zone("huge", Vector2.ZERO, 3.0, INF, 0.2), "infinite capacity")
	check(not region.add_zone("fast", Vector2.ZERO, 3.0, 50.0, INF), "infinite growth")
	check(not region.add_zone("wide", Vector2.ZERO, INF, 50.0, 0.2), "infinite area")
	check(not region.add_zone("lost", Vector2(NAN, 0.0), 3.0, 50.0, 0.2), "no real center")
	check_eq(region.zones.size(), 1, "nothing added")
	check_eq(region.take("shallows", NAN), 0.0, "NaN request takes nothing")
	check_eq(region.take("shallows", -5.0), 0.0, "negative request takes nothing")
	check_near(region.zone("shallows").amount, 100.0, 0.0001, "zone untouched")


func test_unknown_zone_spawn_point_uses_no_random_draw() -> void:
	var a := _region(11)
	var b := _region(11)
	check_eq(a.random_point_in("nowhere"), Vector2.INF, "unknown zone")
	check(a.random_point_in("shallows").is_equal_approx(b.random_point_in("shallows")), "sequence unchanged")


func test_same_seed_gives_same_spawn_points() -> void:
	var a := _region(42)
	var b := _region(42)
	var c := _region(43)
	var same := true
	var differs := false
	for i in 10:
		var pa := a.random_point_in("shallows")
		var pb := b.random_point_in("shallows")
		var pc := c.random_point_in("shallows")
		same = same and pa.is_equal_approx(pb)
		differs = differs or not pa.is_equal_approx(pc)
		check(pa.distance_to(Vector2(5.0, 5.0)) <= 4.0 + 0.0001, "inside the zone")
	check(same, "deterministic for a seed")
	check(differs, "a different seed gives different points")


func test_niches_cap_spawning_by_role() -> void:
	var region := _region()
	region.set_niche("grazer", 2)
	check(region.try_spawn("grazer"), "first")
	check(region.try_spawn("grazer"), "second")
	check(not region.try_spawn("grazer"), "niche full")
	check(not region.try_spawn("hunter"), "unknown role")
	region.on_creature_removed("grazer")
	check(region.try_spawn("grazer"), "a death frees a slot")
	region.set_niche("grazer", 3)
	check_eq(region.niches["grazer"].count, 2, "changing the cap keeps the count")
	region.on_creature_removed("grazer")
	region.on_creature_removed("grazer")
	region.on_creature_removed("grazer")
	check_eq(region.niches["grazer"].count, 0, "count never negative")


# --- the endless world's zone streams and removals (S1 T2.3) ---

func test_a_zone_stream_replaces_the_shared_rng_for_its_zone_only() -> void:
	var a := _region(5)
	a.add_zone("reef", Vector2(-20.0, 3.0), 3.0, 60.0, 0.1)
	var b := _region(5)
	b.add_zone("reef", Vector2(-20.0, 3.0), 3.0, 60.0, 0.1)
	var stream := RandomNumberGenerator.new()
	stream.seed = 99
	b.streams["reef"] = stream
	var twin := RandomNumberGenerator.new()
	twin.seed = 99
	# The streamed zone draws its own stream, two draws a point (angle, then distance share).
	var p := b.random_point_in("reef")
	var angle := twin.randf() * TAU
	var dist := sqrt(twin.randf()) * 3.0
	check_eq(p, Vector2(-20.0, 3.0) + Vector2.from_angle(angle) * dist, "the reef's point comes from its stream")
	check_eq(stream.state, twin.state, "two draws from the stream")
	# The shared rng was left alone, so the other zone's points match a region without streams.
	for i in 5:
		check_eq(b.random_point_in("shallows"), a.random_point_in("shallows"), "shallows point %d unchanged" % i)
	check_eq(b.rng.state, a.rng.state, "the shared rng drew only for the unstreamed zone")


func test_remove_zone_keeps_the_others_in_order() -> void:
	var region := _region()
	region.add_zone("a", Vector2(1.0, 0.0), 2.0, 40.0, 0.1)
	region.add_zone("b", Vector2(2.0, 0.0), 2.0, 40.0, 0.1)
	region.add_zone("c", Vector2(3.0, 0.0), 2.0, 40.0, 0.1)
	region.streams["b"] = RandomNumberGenerator.new()
	check(region.remove_zone("b"), "removed")
	check(not region.remove_zone("b"), "an unknown id is refused")
	var ids := []
	for z in region.zones:
		ids.append(z.id)
	check_eq(ids, ["shallows", "a", "c"], "the others keep their order")
	check(region.zone("b").is_empty(), "no lookup")
	check(not region.streams.has("b"), "its stream is gone")
	check_eq(region.random_point_in("b"), Vector2.INF, "no point")
	check(region.add_zone("b", Vector2(9.0, 0.0), 2.0, 40.0, 0.1), "the id can come back (a reload)")
	check_eq(region.zone("b").center, Vector2(9.0, 0.0), "as the new zone")


func test_zone_lookup_by_id_equals_the_linear_scan() -> void:
	var layout := PoolLayout.load_from()
	var region := layout.build_region(3)
	region.add_zone("extra", Vector2(30.0, 0.0), 2.0, 40.0, 0.1)
	region.remove_zone("z_s")
	for id in ["z_center", "z_n", "z_s", "extra", "nowhere"]:
		var scanned := {}
		for z in region.zones:
			if z.id == id:
				scanned = z
				break
		check(is_same(region.zone(id), scanned) or (scanned.is_empty() and region.zone(id).is_empty()),
			"%s: the same dictionary as the scan finds" % id)
	region.take("z_n", 10.0)
	check_near(float(region.zones[1].amount), float(region.zones[1].capacity) - 10.0, 1e-9, "a take through the index changes the listed zone")


# --- S3: the bloom (D-104, D-128; S3G15's ecology part) ---

const BLOOM_CYCLE := 5400


func test_a_bloom_meadow_regrows_at_one_and_a_half_then_half_by_its_slot() -> void:
	for slot in [0, 1]:
		var bloom := {"slot": slot, "offset_ticks": 300, "cycle_ticks": BLOOM_CYCLE}
		check_eq(EcologyRegion.bloom_multiplier(bloom, 0), 1.5 if slot == 0 else 0.5, "slot %d at tick 0" % slot)
		check_eq(EcologyRegion.bloom_multiplier(bloom, 2399), 1.5 if slot == 0 else 0.5, "slot %d just before the turn" % slot)
		check_eq(EcologyRegion.bloom_multiplier(bloom, 2400), 0.5 if slot == 0 else 1.5, "slot %d at the turn" % slot)
		var sum := 0.0
		for t in range(-BLOOM_CYCLE, BLOOM_CYCLE):
			sum += EcologyRegion.bloom_multiplier(bloom, t)
		check_eq(sum / float(2 * BLOOM_CYCLE), 1.0, "slot %d: the mean over whole cycles is exactly 1" % slot)
	check_eq(EcologyRegion.bloom_multiplier({}, 77), 1.0, "no bloom is 1")
	var a := {"slot": 0, "offset_ticks": 41, "cycle_ticks": BLOOM_CYCLE}
	var b := {"slot": 1, "offset_ticks": 41, "cycle_ticks": BLOOM_CYCLE}
	var together := 0
	for t in range(0, 3 * BLOOM_CYCLE, 13):
		together += 1 if EcologyRegion.bloom_multiplier(a, t) == EcologyRegion.bloom_multiplier(b, t) else 0
	check_eq(together, 0, "the two slots never bloom together")


func test_a_meadows_regrowth_is_scaled_and_a_plain_zones_is_bit_identical() -> void:
	var bloom := {"slot": 0, "offset_ticks": 0, "cycle_ticks": BLOOM_CYCLE}
	var region := EcologyRegion.create(5)
	check(region.add_zone("plain", Vector2.ZERO, 4.0, 40.0, 0.05), "a plain zone")
	check(region.add_zone("meadow_a", Vector2(10.0, 0.0), 4.0, 40.0, 0.05, bloom), "slot 0's meadow")
	check(region.add_zone("meadow_b", Vector2(20.0, 0.0), 4.0, 40.0, 0.05, {"slot": 1, "offset_ticks": 0, "cycle_ticks": BLOOM_CYCLE}), "slot 1's")
	var old := EcologyRegion.create(5)
	old.add_zone("plain", Vector2.ZERO, 4.0, 40.0, 0.05)
	check_eq(region.zone("meadow_a").bloom, bloom, "the zone keeps its bloom")
	check(not region.zone("plain").has("bloom"), "and a plain zone has none")
	for id in ["plain", "meadow_a", "meadow_b"]:
		region.take(id, 30.0)
	old.take("plain", 30.0)
	var start := 10.0
	for t in 60:
		region.tick(PoolSim.DT, t)
		old.tick(PoolSim.DT)
	check_eq(region.zone("plain").amount, old.zone("plain").amount, "the plain zone regrows to the bit as before")
	var grew_a: float = region.zone("meadow_a").amount - start
	var grew_b: float = region.zone("meadow_b").amount - start
	check(absf(grew_a / grew_b - 3.0) < 0.05, "the blooming meadow regrows about three times as fast (%.4f vs %.4f; logistic)" % [grew_a, grew_b])
	check(region.remove_zone("meadow_a"), "a meadow comes out")
	region.tick(PoolSim.DT, 60)
	check_eq(region.zones.map(func(z: Dictionary) -> String: return z.id), ["plain", "meadow_b"], "the others in order")
	var z := {"id": "prepared", "center": Vector2.INF, "radius": 3.0, "capacity": 10.0, "growth_rate": 0.05, "amount": 2.0,
		"bloom": bloom.duplicate()}
	check(region.add_zone_prepared(z, Vector2(30.0, 0.0)), "a prepared meadow goes in")
	region.tick(PoolSim.DT, 0)
	var expected := 2.0 + (0.05 * 2.0 * (1.0 - 2.0 / 10.0) + 10.0 * EcologyRegion.REGROW_FLOOR * 0.05) * 1.5 * PoolSim.DT
	check(absf(float(z.amount) - expected) < 1e-12, "and blooms (%.12f vs %.12f)" % [z.amount, expected])
	region.take_all_zones()
	region.tick(PoolSim.DT, 0)
	check_eq(region.zones.size(), 0, "taking every zone out empties the split lists too")
