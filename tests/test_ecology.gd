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
	var low := _region()
	low.take("shallows", 95.0)
	var mid := _region()
	mid.take("shallows", 50.0)
	low.tick(0.1)
	mid.tick(0.1)
	check(mid.zone("shallows").amount - 50.0 > low.zone("shallows").amount - 5.0, "logistic growth")


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
