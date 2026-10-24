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
