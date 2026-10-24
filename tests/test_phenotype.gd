extends TestCase

## The ambush hunter's parts (the hunter body) and the rammer's, as in the step 3 species plan.
const AMBUSH_PARTS := [["mouth_jaw", 0.0], ["flagellum", 2.8], ["flagellum", -2.8]]
const RAMMER_PARTS := [["mouth_filter", 0.0], ["spike", 0.3, 0.8], ["spike", -0.3, 0.8], ["spike", 1.9, 0.8],
	["spike", -1.9, 0.8], ["flagellum", 3.14159]]




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


# --- Body size (M1 step 3) ---

## Everything derive() produces, including the fields to_dict() leaves out.
func _full(p: Phenotype) -> String:
	var d := p.to_dict()
	d["radius"] = p.radius
	d["mouths"] = p.mouths
	d["spikes"] = p.spikes
	d["spike_stacking"] = p.spike_stacking
	d["move_cost"] = p.move_cost
	return JSON.stringify(d, "", true, true)


func test_size_one_is_exactly_the_unsized_rule_for_every_starting_body_and_single_part() -> void:
	var genomes := {}
	for body_name in catalog.starting_bodies:
		genomes[body_name] = Lineage.found(1, "test+dev", catalog, body_name).save.genome
	for type_id in catalog.parts:
		genomes["only " + type_id] = _body([[type_id, 0.4]])
	check(genomes.size() >= 11, "3 starting bodies and every part alone (%d genomes)" % genomes.size())
	for key in genomes:
		var unsized := Phenotype.derive(genomes[key], catalog)
		var sized := Phenotype.derive(genomes[key], catalog, 1.0)
		check_eq(_full(sized), _full(unsized), "%s at size 1" % key)
		check(_full(Phenotype.derive(genomes[key], catalog, 1.01)) != _full(unsized), "%s: size 1.01 differs, so the compare can fail" % key)


func test_the_starting_bodies_keep_their_step_2_stats() -> void:
	# Speed, acceleration, health, upkeep, sight, mass and radius, from the step 3 plan's body table.
	var expected := {
		"grazer": [2.906, 3.077, 30.0, 0.90, 9.0, 1.17, 0.5],
		"hunter": [3.262, 3.046, 30.0, 1.15, 6.0, 1.30, 0.5],
		"omnivore": [2.720, 2.880, 30.0, 0.95, 6.0, 1.25, 0.5],
	}
	for body_name in expected:
		var p := Phenotype.derive(Lineage.found(1, "test+dev", catalog, body_name).save.genome, catalog)
		var want: Array = expected[body_name]
		var got := [p.speed, p.acceleration, p.max_health, p.upkeep, p.sight, p.mass, p.radius]
		for i in want.size():
			check_near(got[i], want[i], 0.001, "%s stat %d" % [body_name, i])


func test_the_ambush_hunter_is_the_hunter_body_at_size_one_and_a_half() -> void:
	var p := Phenotype.derive(_body(AMBUSH_PARTS), catalog, 1.5)
	check_near(p.radius, 0.75, 1e-9, "radius")
	check_near(p.mass, 1.95, 1e-9, "mass")
	check_near(p.speed, 2.749, 0.001, "speed")
	check_near(p.acceleration, 2.277, 0.001, "acceleration")
	check_near(p.max_health, 45.0, 1e-9, "health")
	check_near(p.upkeep, 1.725, 1e-9, "upkeep")
	check_near(p.bite_damage, 12.0, 1e-9, "bite")
	check_near(p.turn_rate, 2.5, 1e-9, "turn rate is not scaled")
	check_near(p.sight, 6.0, 1e-9, "sight is not scaled")
	check_near(p.energy_capacity, 100.0, 1e-9, "energy capacity is not scaled")


func test_the_rammer_is_bigger_than_the_player_and_slower() -> void:
	var p := Phenotype.derive(_body(RAMMER_PARTS), catalog, 1.25)
	check_near(p.radius, 0.625, 1e-9, "radius")
	check_near(p.mass, 2.0375, 1e-9, "mass")
	check_near(p.speed, 1.840, 0.001, "speed")
	check_near(p.acceleration, 1.840, 0.001, "acceleration")
	check_near(p.max_health, 37.5, 1e-9, "health")
	check_near(p.upkeep, 1.2, 1e-9, "upkeep")
	check_eq(p.spikes.size(), 4, "four spikes")
	for spike in p.spikes:
		check_near(spike.damage, 6.0, 1e-9, "each spike: 6 x part scale 0.8 x size 1.25")


func test_spike_damage_scales_with_part_scale_times_body_size() -> void:
	for case in [[1.0, 1.0, 6.0], [0.8, 1.25, 6.0], [2.0, 1.5, 18.0], [0.5, 2.0, 6.0]]:
		var p := Phenotype.derive(_body([["mouth_filter", 0.0], ["spike", 0.0, case[0]]]), catalog, case[1])
		check_near(p.spikes[0].damage, case[2], 1e-9, "part scale %.2f at size %.2f" % [case[0], case[1]])
		check_near(p.ram_damage, case[2], 1e-9, "a single spike's ram damage")


func test_a_bigger_body_is_tougher_hungrier_and_slower() -> void:
	var genome := _body(AMBUSH_PARTS)
	var last := Phenotype.derive(genome, catalog, 1.0)
	for size in [1.25, 1.5, 2.0]:
		var p := Phenotype.derive(genome, catalog, size)
		check(p.max_health > last.max_health, "size %.2f: more health" % size)
		check(p.upkeep > last.upkeep, "size %.2f: more upkeep" % size)
		check(p.bite_damage > last.bite_damage, "size %.2f: a harder bite" % size)
		check(p.move_cost > last.move_cost, "size %.2f: moving costs more" % size)
		check(p.speed < last.speed, "size %.2f: slower" % size)
		check(p.acceleration < last.acceleration, "size %.2f: slower to speed up" % size)
		last = p


func test_body_size_is_clamped_to_its_range() -> void:
	var genome := _body(RAMMER_PARTS)
	check_eq(_full(Phenotype.derive(genome, catalog, 3.0)), _full(Phenotype.derive(genome, catalog, Phenotype.MAX_BODY_SIZE)), "above the range")
	check_eq(_full(Phenotype.derive(genome, catalog, 0.1)), _full(Phenotype.derive(genome, catalog, Phenotype.MIN_BODY_SIZE)), "below the range")
	check_eq(_full(Phenotype.derive(genome, catalog, NAN)), _full(Phenotype.derive(genome, catalog)), "not a number counts as size 1")
	check_eq(_full(Phenotype.derive(genome, catalog, INF)), _full(Phenotype.derive(genome, catalog)), "infinity counts as size 1")


# --- Scaled to another size (S2, plan B.6) ---

## Phenotype.scaled sorts every field: multiplied by q, or copied as it is. "spikes" is both: each
## spike's damage is multiplied and its type, angle and arc are copied. A new Phenotype field fails
## test_every_field_is_sorted_into_scaled_or_kept until it is added to one of these lists.
const SCALED_FIELDS: PackedStringArray = ["speed", "acceleration", "max_health", "energy_capacity", "upkeep",
	"move_cost", "sight", "mass", "radius", "bite_damage", "ram_damage"]
const KEPT_FIELDS: PackedStringArray = ["turn_rate", "defense", "spike_stacking", "diets", "mouths"]
## q at size 2 for a size-1 species, at size 3, and a size-2 species seen from size 1.
const LADDER_QS := [0.625, 0.390625, 1.6]


## The three starting bodies, the ambush hunter and the rammer.
func _ladder_bodies() -> Dictionary:
	var out := {}
	for body_name in catalog.starting_bodies:
		out[body_name] = Phenotype.derive(Lineage.found(1, "test+dev", catalog, body_name).save.genome, catalog)
	out["ambush hunter"] = Phenotype.derive(_body(AMBUSH_PARTS), catalog, 1.5)
	out["rammer"] = Phenotype.derive(_body(RAMMER_PARTS), catalog, 1.25)
	return out


func _fields(p: Phenotype) -> PackedStringArray:
	var out := PackedStringArray()
	for prop in p.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(prop.name)
	return out


func test_every_field_is_sorted_into_scaled_or_kept() -> void:
	var fields := _fields(Phenotype.new())
	var sorted := SCALED_FIELDS + KEPT_FIELDS + PackedStringArray(["spikes"])
	check(fields.size() >= 15, "the reflection finds the fields (%d)" % fields.size())
	for f in fields:
		check(f in sorted, "'%s' is sorted into scaled or kept" % f)
	for f in sorted:
		check(f in fields, "'%s' is a Phenotype field" % f)


func test_scaled_by_one_is_the_same_body_bit_for_bit() -> void:
	var bodies := _ladder_bodies()
	for key in bodies:
		var p: Phenotype = bodies[key]
		var same := p.scaled(1.0)
		for f in _fields(p):
			check_eq(same.get(f), p.get(f), "%s: %s" % [key, f])
		check_eq(_full(same), _full(p), "%s: every stat" % key)


func test_scaled_multiplies_each_size_stat_by_q_and_copies_the_rest() -> void:
	var bodies := _ladder_bodies()
	for q in LADDER_QS:
		for key in bodies:
			var p: Phenotype = bodies[key]
			var s := p.scaled(q)
			var where := "%s at q %.6f" % [key, q]
			for f in SCALED_FIELDS:
				check_eq(s.get(f), float(p.get(f)) * q, "%s: %s x q" % [where, f])
			for f in KEPT_FIELDS:
				check_eq(s.get(f), p.get(f), "%s: %s kept" % [where, f])
			check(s.radius != p.radius and s.speed != p.speed, where + ": the radius and speed did change")
			check_eq(s.spikes.size(), p.spikes.size(), where + ": every spike")
			for i in mini(s.spikes.size(), p.spikes.size()):
				check_eq(float(s.spikes[i].damage), float(p.spikes[i].damage) * q, "%s: spike %d damage x q" % [where, i])
				for k in ["type", "angle", "arc"]:
					check_eq(s.spikes[i][k], p.spikes[i][k], "%s: spike %d %s kept" % [where, i, k])
	check(not bodies.rammer.spikes.is_empty(), "the rammer has spikes to scale")


func test_a_scaled_copy_shares_nothing_with_its_body() -> void:
	var p := Phenotype.derive(_body(RAMMER_PARTS), catalog, 1.25)
	var before := _full(p)
	var s := p.scaled(0.625)
	s.mouths[0]["arc"] = 9.0
	s.spikes[0]["angle"] = 9.0
	s.diets.append("rock")
	check_eq(_full(p), before, "changing the copy's mouths, spikes and diets leaves the body as it was")


func test_a_scaled_down_body_is_slower_where_a_re_derived_one_would_be_faster() -> void:
	# The linear law keeps the ladder's fear rule honest: a re-derived small body sheds mass and speeds up.
	var genome := _body(AMBUSH_PARTS)
	var p := Phenotype.derive(genome, catalog, 1.5)
	var s := p.scaled(0.625)
	var rederived := Phenotype.derive(genome, catalog, 1.5 * 0.625)
	check_near(s.radius, rederived.radius, 1e-12, "the same radius either way (0.46875)")
	check(s.speed < p.speed, "scaled: slower (%.3f < %.3f)" % [s.speed, p.speed])
	check(rederived.speed > p.speed, "re-derived: faster (%.3f > %.3f)" % [rederived.speed, p.speed])
	check_near(s.turn_rate, p.turn_rate, 0.0, "the turn rate stays")
