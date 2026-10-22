extends TestCase

var catalog: PartCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()


func _body(parts: Array) -> Genome:
	var genome := Genome.create(StableId.generate("lineage"))
	for p in parts:
		genome.add_part(p[0], p[1], p[2] if p.size() > 2 else 1.0)
	return genome


func _derive(parts: Array) -> Phenotype:
	return Phenotype.derive(_body(parts), catalog)


func test_mouth_only_body_uses_base_stats_slowed_by_mouth_mass() -> void:
	var p := _derive([["mouth_filter", 0.0]])
	check_near(p.mass, 1.05, 0.0001, "mass")
	check_near(p.speed, 2.0 / 1.05, 0.0001, "speed")
	check_near(p.upkeep, 0.55, 0.0001, "upkeep")
	check_near(p.sight, 6.0, 0.0001, "sight")
	check_near(p.max_health, 30.0, 0.0001, "health")
	check(p.can_eat("plant"), "filter mouth eats plants")
	check(not p.can_eat("meat"), "filter mouth cannot eat meat")


func test_second_flagellum_is_faster_but_costs_full_upkeep() -> void:
	var one := _derive([["mouth_filter", 0.0], ["flagellum", PI]])
	var two := _derive([["mouth_filter", 0.0], ["flagellum", PI], ["flagellum", 2.6]])
	check_near(one.speed, (2.0 + 1.4) / 1.15, 0.0001, "one flagellum")
	check_near(two.speed, (2.0 + 1.4 + 1.4 * 0.6) / 1.25, 0.0001, "second adds 60% of the first")
	check(two.speed > one.speed, "two is faster")
	check_near(two.upkeep - one.upkeep, 0.25, 0.0001, "second flagellum pays full upkeep")


func test_benefits_diminish_with_each_copy() -> void:
	var p := _derive([["mouth_filter", 0.0], ["eye_spot", 0.5], ["eye_spot", -0.5], ["eye_spot", 1.0]])
	check_near(p.sight, 6.0 + 3.0 + 1.8 + 1.08, 0.0001, "3 + 1.8 + 1.08")


func test_extra_mass_slows_the_same_propulsion() -> void:
	var light := _derive([["mouth_jaw", 0.0], ["flagellum", PI]])
	var heavy := _derive([["mouth_jaw", 0.0], ["flagellum", PI], ["spike", 0.3], ["spike", -0.3]])
	check(heavy.speed < light.speed, "spikes add mass and slow the body")
	check(heavy.acceleration < light.acceleration, "and its acceleration")
	check(heavy.move_cost > light.move_cost, "moving a heavier body costs more")


func test_scale_multiplies_the_benefit_and_the_cost() -> void:
	var small := _derive([["mouth_filter", 0.0], ["eye_spot", 0.5, 0.5]])
	var big := _derive([["mouth_filter", 0.0], ["eye_spot", 0.5, 2.0]])
	check_near(small.sight, 6.0 + 1.5, 0.0001, "half size")
	check_near(big.sight, 6.0 + 6.0, 0.0001, "double size")
	check_near(small.upkeep, 0.55 + 0.05, 0.0001, "half size, half upkeep")
	check_near(big.upkeep, 0.55 + 0.2, 0.0001, "double size, double upkeep")
	check_near(big.mass - small.mass, 0.02 * 1.5, 0.0001, "mass scales too")
	var spike := _derive([["mouth_filter", 0.0], ["spike", 0.0, 2.0]])
	check_near(spike.spikes[0].damage, 12.0, 0.0001, "spike damage scales with size")


func test_every_part_carries_a_cost() -> void:
	for type_id in catalog.parts:
		var effects: Dictionary = catalog.parts[type_id]["effects"]
		check(effects.get("upkeep", 0.0) > 0.0, "%s has upkeep" % type_id)
		check(effects.get("mass", 0.0) > 0.0, "%s has mass" % type_id)
		check(catalog.cost_of(type_id) > 0, "%s costs points" % type_id)


func test_part_order_does_not_change_stats() -> void:
	var a := _derive([["mouth_filter", 0.0], ["eye_spot", 0.5, 2.0], ["eye_spot", -0.5, 0.5], ["spike", 0.0, 0.5], ["spike", PI, 1.5]])
	var b := _derive([["spike", PI, 1.5], ["eye_spot", -0.5, 0.5], ["spike", 0.0, 0.5], ["eye_spot", 0.5, 2.0], ["mouth_filter", 0.0]])
	check_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()), "same parts, same stats")
	check_near(a.sight, 6.0 + 6.0 + 1.5 * 0.6, 0.0001, "largest copy counts in full")


func test_stats_are_capped() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PartCatalog.DEFAULT_PATH))
	data["caps"]["sight"] = 8.0
	data["caps"]["speed"] = 2.5
	var capped := PartCatalog.from_dict(data)
	var genome := _body([["mouth_filter", 0.0], ["eye_spot", 0.5], ["flagellum", PI], ["flagellum", 2.6]])
	var p := Phenotype.derive(genome, capped)
	check_near(p.sight, 8.0, 0.0001, "sight capped")
	check_near(p.speed, 2.5, 0.0001, "speed capped")


func test_directional_parts_keep_their_angles() -> void:
	var p := _derive([["mouth_jaw", 0.2], ["spike", 0.0], ["spike", PI]])
	check_eq(p.mouths.size(), 1, "one mouth")
	check_near(p.mouths[0].angle, 0.2, 0.0001, "mouth angle")
	check_near(p.mouths[0].arc, deg_to_rad(60.0), 0.0001, "jaw arc")
	check_eq(p.spikes.size(), 2, "two spikes")
	check_near(p.spikes[1].angle, PI, 0.0001, "rear spike angle")
	check_near(p.bite_damage, 8.0, 0.0001, "bite")
	check_near(p.ram_damage, 6.0 + 3.6, 0.0001, "both spikes together, with diminishing returns")
	check_near(p.spikes[0].damage, 6.0, 0.0001, "each spike keeps its own full damage")
	check_near(p.spike_stacking, 0.6, 0.0001, "stacking share for spikes hitting together")


func test_omnivore_with_two_mouths_eats_both() -> void:
	var p := _derive([["mouth_filter", 0.0], ["mouth_jaw", 0.4]])
	check(p.can_eat("plant") and p.can_eat("meat"), "both diets")
	check_eq(p.mouths.size(), 2, "two mouths")


func test_unknown_parts_add_nothing() -> void:
	var genome := _body([["mouth_filter", 0.0]])
	var before := Phenotype.derive(genome, catalog).to_dict()
	genome.parts.append({"id": "part_99", "type": "unknown_organ", "angle": 0.0, "scale": 1.0})
	check_eq(JSON.stringify(Phenotype.derive(genome, catalog).to_dict()), JSON.stringify(before), "same stats")
	check_has_error(genome.validate(catalog), "unknown_organ")
