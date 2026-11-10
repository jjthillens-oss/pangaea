extends TestCase
## Body size tiers (IB-30, PROPOSED; game/domain/creature/size_tiers.gd applied in creature_stats.gd): the same body
## at two scales gets the tier's multipliers on speed, bite reach and energy use; a body in the middle tier keeps
## its numbers exactly; the thresholds classify exactly.

const Fixtures := preload("res://tests/creature_fixtures.gd")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const Sim := preload("res://game/systems/creature/creature_world_sim.gd")
const SizeTiers := preload("res://game/domain/creature/size_tiers.gd")

const BODY := "s1_quadruped"

var part_rules := {}
var table: RefCounted
var tuning := {}
var tiers := {}


func before_each() -> void:
	part_rules = CreatureData.part_rules()
	table = CreatureData.gait_table()
	tuning = Sim.load_tuning()
	tiers = tuning["size_tiers"]


func _tier(id: String) -> Dictionary:
	for t: Dictionary in tiers["tiers"]:
		if t["id"] == id:
			return t
	return {}


## The same body at `length_mm`, with and without the tier rule.
func _stats_at(length_mm: int, with_tiers: bool) -> Dictionary:
	var body = Fixtures.body(BODY)
	body.reference_length_mm = length_mm
	var t := tuning.duplicate(true)
	if not with_tiers:
		t.erase("size_tiers")
	return CreatureStats.of(body, part_rules, table, t)


func test_the_tuning_has_a_small_a_neutral_and_a_large_tier() -> void:
	var small := _tier("small")
	var medium := _tier("medium")
	var large := _tier("large")
	check(not small.is_empty() and not medium.is_empty() and not large.is_empty(), "small, medium and large exist")
	for k in SizeTiers.FACTORS:
		check_eq(float(medium[k]), 1.0, "medium %s is exactly 1" % k)
	check(float(large["bite_reach"]) > 1.0 and float(small["bite_reach"]) < 1.0, "reach: large > 1 > small")
	check(float(large["energy_use"]) > 1.0 and float(small["energy_use"]) < 1.0, "energy use: large > 1 > small")
	check(float(large["turn"]) < 1.0 and float(small["turn"]) > 1.0, "turning: large < 1 < small")
	check(float(large["speed"]) < 1.0 and float(small["speed"]) >= 1.0, "speed: large < 1 <= small")


func test_classification_is_exact_at_the_thresholds() -> void:
	var m := int(_tier("medium")["min_mm"])
	var l := int(_tier("large")["min_mm"])
	check(m < l, "medium starts below large")
	check_eq(SizeTiers.of_length(m - 1, tiers)["id"], "small", "one millimetre under medium is small")
	check_eq(SizeTiers.of_length(m, tiers)["id"], "medium", "the medium threshold is medium")
	check_eq(SizeTiers.of_length(l - 1, tiers)["id"], "medium", "one millimetre under large is medium")
	check_eq(SizeTiers.of_length(l, tiers)["id"], "large", "the large threshold is large")
	check_eq(SizeTiers.of_length(100000, tiers)["id"], "large", "a giant is large")
	# The order of the list does not matter, and asking twice gives the same answer.
	var flipped := {"tiers": (tiers["tiers"] as Array).duplicate()}
	(flipped["tiers"] as Array).reverse()
	for mm in [1, m - 1, m, 1200, l - 1, l, 8000]:
		check_eq(SizeTiers.of_length(mm, flipped), SizeTiers.of_length(mm, tiers), "%d mm, list reversed" % mm)
		check_eq(SizeTiers.of_length(mm, tiers), SizeTiers.of_length(mm, tiers), "%d mm, asked twice" % mm)
	check_eq(SizeTiers.of_length(1200, {}), SizeTiers.NEUTRAL, "no tuning block is neutral")


func test_a_medium_body_keeps_its_numbers_exactly() -> void:
	var lengths: Array[int] = [int(Fixtures.body(BODY).reference_length_mm), int(_tier("medium")["min_mm"]),
			int(_tier("large")["min_mm"]) - 1]
	for mm in lengths:
		var with := _stats_at(mm, true)
		var without := _stats_at(mm, false)
		check_eq(with["size_tier"], "medium", "%d mm is medium" % mm)
		for k in without:
			if k in ["size_tier", "energy_use_factor", "turn_factor"]:
				continue
			check_eq(with[k], without[k], "%d mm: %s is unchanged" % [mm, k])
		check_eq(with["energy_use_factor"], 1.0, "%d mm: energy use x1" % mm)
		check_eq(with["turn_factor"], 1.0, "%d mm: turning x1" % mm)


func test_every_shipped_starter_and_preset_in_the_medium_band_is_unchanged() -> void:
	var seen := 0
	for n in Fixtures.starter_names():
		var body = Fixtures.body(n)
		if SizeTiers.of_body(body, tiers)["id"] != "medium":
			continue
		seen += 1
		var bare := tuning.duplicate(true)
		bare.erase("size_tiers")
		var with := CreatureStats.of(body, part_rules, table, tuning)
		var without := CreatureStats.of(body, part_rules, table, bare)
		check_eq(with["speed_mps"], without["speed_mps"], "%s: speed" % n)
		check_eq(with["bite_reach_m"], without["bite_reach_m"], "%s: reach" % n)
		check_eq(with["speed_factor"], without["speed_factor"], "%s: speed factor" % n)
	check(seen > 0, "some starters are medium (%d)" % seen)
	check_eq(SizeTiers.of_body(Fixtures.body(BODY), tiers)["id"], "medium", "the starter quadruped is medium")


## Same scenario, two sizes: the same body just under and at each threshold, so the geometry is all but the same
## and the tier is the difference.
func test_same_body_small_and_large_orders_speed_reach_and_energy() -> void:
	var m := int(_tier("medium")["min_mm"])
	var l := int(_tier("large")["min_mm"])
	var small := _stats_at(m - 1, true)
	var small_bare := _stats_at(m - 1, false)
	var large := _stats_at(l, true)
	var large_bare := _stats_at(l, false)
	check_eq(small["size_tier"], "small", "just under medium is small")
	check_eq(large["size_tier"], "large", "the large threshold is large")
	check(is_equal_approx(large["bite_reach_m"], large_bare["bite_reach_m"] * float(_tier("large")["bite_reach"])),
			"large reach is the body's reach times the tier's")
	check(is_equal_approx(small["bite_reach_m"], small_bare["bite_reach_m"] * float(_tier("small")["bite_reach"])),
			"small reach is the body's reach times the tier's")
	check(is_equal_approx(large["speed_mps"], large_bare["speed_mps"] * float(_tier("large")["speed"])),
			"large speed is the body's speed times the tier's")
	check(is_equal_approx(large["speed_factor"], large_bare["speed_factor"] * float(_tier("large")["speed"])),
			"and the speed factor the world's throttle reads carries it")
	check(is_equal_approx(small["speed_mps"], small_bare["speed_mps"] * float(_tier("small")["speed"])),
			"small speed is the body's speed times the tier's")
	check(large["bite_reach_m"] > large_bare["bite_reach_m"], "large reaches farther than its geometry alone")
	check(small["bite_reach_m"] < small_bare["bite_reach_m"], "small reaches less than its geometry alone")
	check(large["bite_reach_m"] > small["bite_reach_m"], "large out-reaches small (%.3f > %.3f m)"
			% [large["bite_reach_m"], small["bite_reach_m"]])
	check(large["speed_mps"] < large_bare["speed_mps"], "large is slower than its legs alone allow")
	check(large["energy_use_factor"] > 1.0 and 1.0 > small["energy_use_factor"], "energy use: large > medium > small")
	check(large["turn_factor"] < 1.0 and 1.0 < small["turn_factor"], "turning: large < medium < small")
	# One millimetre across the threshold changes the reach by the tier, not by the geometry.
	var under := _stats_at(l - 1, true)
	check(large["bite_reach_m"] / under["bite_reach_m"] > 1.1, "crossing into large is a step in reach")
	# The mass, health and bite power do not take a tier multiplier.
	check_eq(large["mass_kg"], large_bare["mass_kg"], "mass is the body's")
	check_eq(large["bite_power"], large_bare["bite_power"], "bite power is the body's")
