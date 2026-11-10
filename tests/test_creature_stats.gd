extends TestCase
## Anatomy to play numbers (game/domain/creature/creature_stats.gd): speed from leg length, bite from mouths, sight
## from eyes, mass from volume, and a body without legs or a mouth.

const Fixtures := preload("res://tests/creature_fixtures.gd")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const Sim := preload("res://game/systems/creature/creature_world_sim.gd")

var part_rules := {}
var table: RefCounted
var tuning := {}


func before_each() -> void:
	part_rules = CreatureData.part_rules()
	table = CreatureData.gait_table()
	tuning = Sim.load_tuning()


func stats_of(body: RefCounted) -> Dictionary:
	return CreatureStats.of(body, part_rules, table, tuning)


func test_speed_and_cadence_follow_leg_length() -> void:
	var short = Fixtures.body("s1_quadruped")
	var long = Fixtures.body("s1_quadruped")
	long.reference_length_mm = short.reference_length_mm * 2
	var a := stats_of(short)
	var b := stats_of(long)
	check(a["has_legs"] and b["has_legs"], "the quadruped has legs")
	check(b["leg_length_m"] > a["leg_length_m"], "a body twice as long has longer legs")
	var gait_ratio: float = (b["speed_mps"] / b["speed_factor"]) / (a["speed_mps"] / a["speed_factor"])
	check(is_equal_approx(gait_ratio, sqrt(2.0)), "the legs' top speed scales with the square root of leg length")
	check(b["cadence_hz"] < a["cadence_hz"], "and steps slower (%.2f < %.2f Hz)" % [b["cadence_hz"], a["cadence_hz"]])
	check(a["speed_mps"] > 0.5 and a["speed_mps"] < 20.0, "a playable speed (%.2f m/s)" % a["speed_mps"])


func test_bite_grows_with_mouths_and_their_scale() -> void:
	var body = Fixtures.body("s1_quadruped")
	var mouthless := stats_of(body)
	check(not mouthless["has_mouth"] or mouthless["bite_power"] > 0.0, "a mouth gives bite power")
	var bare = Fixtures.body("bean")
	var none := stats_of(bare)
	check(not none["has_mouth"] and none["bite_power"] == 0.0, "no mouth, no bite")
	bare.add_part("maw", {"host": "spine", "u": 0, "ring": 500, "scale": 1000})
	var one := stats_of(bare)
	var k: float = one["strength_factor"]
	check(one["has_mouth"] and is_equal_approx(one["bite_power"], 10.0 * k), "one maw: (base 5 + 5) x strength (%.1f)" % one["bite_power"])
	bare.add_part("mandibles", {"host": "spine", "u": 1000, "ring": 500, "scale": 2000})
	var two := stats_of(bare)
	check(is_equal_approx(two["bite_power"], 20.0 * k), "a second mouth at scale 2 adds 10 x strength (%.1f)" % two["bite_power"])
	check(two["bite_reach_m"] > none["bite_reach_m"], "a mouth reaches further than touch")
	check(two["mouths"] == 2, "two mouths counted")


func test_sight_comes_from_eyes_with_a_base_and_a_cap() -> void:
	var bare = Fixtures.body("bean")
	check(is_equal_approx(stats_of(bare)["sight_m"], 6.0), "no eyes: the base sight")
	bare.add_part("eye", {"host": "spine", "u": 100, "ring": 200, "mirror": true})
	check(is_equal_approx(stats_of(bare)["sight_m"], 12.0), "a mirrored eye pair adds 2 x 3 m")
	for i in 8:
		bare.add_part("eye", {"host": "spine", "u": 100 + 50 * i, "ring": 200, "mirror": true})
	check(is_equal_approx(stats_of(bare)["sight_m"], 24.0), "sight is capped at max_m")


func test_every_mouth_and_eye_role_part_counts() -> void:
	var mouths := CreatureStats.types_with_role(part_rules, "mouth")
	var eyes := CreatureStats.types_with_role(part_rules, "eye")
	for t in ["maw", "mandibles", "beak", "jaw", "bill", "proboscis"]:
		check(mouths.has(t), "%s has the mouth role" % t)
	for t in ["eye", "compound_eye", "eye_stalk", "eye_slit", "eye_round", "eye_cluster"]:
		check(eyes.has(t), "%s has the eye role" % t)
	for t in mouths:
		var bare = Fixtures.body("bean")
		bare.add_part(t, {"host": "spine", "u": 0, "ring": 500, "scale": 1000})
		var s := stats_of(bare)
		check(s["has_mouth"] and s["bite_power"] > 0.0, "a %s bites" % t)
	for t in eyes:
		var bare = Fixtures.body("bean")
		bare.add_part(t, {"host": "spine", "u": 100, "ring": 200})
		check(stats_of(bare)["eyes"] == 1, "a %s sees" % t)


func test_weapons_add_to_the_bite_with_a_cap() -> void:
	var bare = Fixtures.body("bean")
	bare.add_part("maw", {"host": "spine", "u": 0, "ring": 500, "scale": 1000})
	var plain := stats_of(bare)
	var k: float = plain["strength_factor"]
	bare.add_part("horn", {"host": "spine", "u": 100, "ring": 300, "scale": 1000})
	var horned := stats_of(bare)
	check(is_equal_approx(horned["bite_power"], plain["bite_power"] + 2.0 * k), "a horn adds 2 x strength (%.1f)" % horned["bite_power"])
	check(horned["weapons"] == 1, "one weapon counted")
	for i in 6:
		bare.add_part("spike", {"host": "spine", "u": 200 + 100 * i, "ring": 300, "scale": 1000})
	var spiky := stats_of(bare)
	check(is_equal_approx(spiky["bite_power"], plain["bite_power"] + 8.0 * k), "only four weapons count (%.1f)" % spiky["bite_power"])
	var mouthless = Fixtures.body("bean")
	mouthless.add_part("horn", {"host": "spine", "u": 100, "ring": 300, "scale": 1000})
	check(stats_of(mouthless)["bite_power"] == 0.0, "no mouth, no attack, horn or not")


func test_mass_and_health_come_from_volume() -> void:
	var small = Fixtures.body("bean")
	var big = Fixtures.body("bean")
	big.reference_length_mm = small.reference_length_mm * 2
	var a := stats_of(small)
	var b := stats_of(big)
	check(a["mass_kg"] > 0.0, "a body has mass (%.2f kg)" % a["mass_kg"])
	check(is_equal_approx(b["mass_kg"] / a["mass_kg"], 8.0), "twice the length is eight times the mass (%.3f)" % (b["mass_kg"] / a["mass_kg"]))
	check(is_equal_approx(a["max_health"], a["mass_kg"] * 2.0), "health is per_kg x mass")
	check(is_equal_approx(a["mass_kg"], CreatureStats.mass_kg(small, 900.0)), "mass at the tuning's density")


func test_a_legless_body_has_no_speed() -> void:
	var s := stats_of(Fixtures.body("s1_snake"))
	check(not s["has_legs"], "the snake has no legs")
	check(s["speed_mps"] == 0.0 and s["cadence_hz"] == 0.0 and s["leg_length_m"] == 0.0, "so no walking speed")
	check(s["max_health"] > 0.0 and s["sight_m"] >= 6.0, "but still health and sight")


func test_every_starter_body_gives_finite_stats() -> void:
	for n in Fixtures.starter_names():
		var s := stats_of(Fixtures.body(n))
		for key in ["mass_kg", "max_health", "bite_power", "bite_reach_m", "sight_m", "speed_mps", "cadence_hz", "leg_length_m"]:
			check(is_finite(float(s[key])) and float(s[key]) >= 0.0, "%s %s is finite and not negative" % [n, key])


## Owner direction, 2026-10-24: a bigger creature is slower, and size sets strength.
func test_heavy_bodies_lose_top_speed_and_gain_strength() -> void:
	var ref := float(tuning["size"]["ref_kg"])
	check_eq(CreatureStats.speed_factor(ref * 0.5, tuning), 1.0, "a light body runs at its legs' top speed")
	check_eq(CreatureStats.speed_factor(ref, tuning), 1.0, "up to the reference mass")
	var last := 1.0
	for m in [ref * 2.0, ref * 5.0, ref * 20.0]:
		var f := CreatureStats.speed_factor(m, tuning)
		check(f < last and f > 0.0, "%.0f kg runs at %.2f of its legs' top speed" % [m, f])
		last = f
	check(CreatureStats.strength_factor(200.0, tuning) > CreatureStats.strength_factor(20.0, tuning), "a heavier body bites harder")
	var sref := float(tuning["strength"]["ref_kg"])
	check(is_equal_approx(CreatureStats.strength_factor(sref * 8.0, tuning), pow(8.0, float(tuning["strength"]["mass_power"]))),
			"strength grows as mass to the 2/3")


func test_a_giant_is_slower_than_the_same_body_at_a_middle_size() -> void:
	var mid = Fixtures.body("s1_quadruped")
	var giant = Fixtures.body("s1_quadruped")
	giant.reference_length_mm = mid.reference_length_mm * 4
	var a := stats_of(mid)
	var b := stats_of(giant)
	check(b["mass_kg"] > 30.0 * a["mass_kg"], "the giant is far heavier (%.0f kg against %.0f)" % [b["mass_kg"], a["mass_kg"]])
	check(b["speed_mps"] < a["speed_mps"], "and slower (%.2f < %.2f m/s)" % [b["speed_mps"], a["speed_mps"]])
	check(b["bite_power"] >= a["bite_power"], "but bites at least as hard")


func test_swim_parts_kept_on_land_slow_the_run_and_trading_them_away_restores_it() -> void:
	var body = Fixtures.body("s1_quadruped")
	var plain := stats_of(body)
	check(body.parts.any(func(p): return p["type"] == "fin" and not p["mirror"]), "the starter has a lone back fin")
	check_eq(plain["land_factor"], 1.0, "a lone back fin does not drag")
	check_eq(plain["swim_parts"], 0, "and is not counted")
	body.add_part("fin", {"host": "spine", "u": 400, "ring": 250, "scale": 1000, "mirror": true})
	var finned := stats_of(body)
	var per: Dictionary = tuning["land_drag"]["per_part"]
	check(is_equal_approx(finned["land_factor"], 1.0 - 2.0 * float(per["fin"])), "a fin pair takes 2 x %.2f (%.3f)"
			% [float(per["fin"]), finned["land_factor"]])
	check_eq(finned["swim_parts"], 2, "a pair counts twice")
	check(is_equal_approx(finned["speed_mps"], plain["speed_mps"] * finned["land_factor"]), "and slows the run")
	check_eq(finned["mass_kg"], plain["mass_kg"], "the drag is not mass")
	body.add_part("tail_fluke", {"host": "spine", "u": 1000, "ring": 0, "scale": 2000})
	var fluked := stats_of(body)
	check(fluked["speed_mps"] < finned["speed_mps"], "a big fluke slows it more (%.2f < %.2f m/s)"
			% [fluked["speed_mps"], finned["speed_mps"]])
	for i in 20:
		body.add_part("fin", {"host": "spine", "u": 50 * i, "ring": 500, "scale": 3000, "mirror": true})
	check(is_equal_approx(stats_of(body)["land_factor"], float(tuning["land_drag"]["floor"])), "never below the floor")
	var bare := Fixtures.body("s1_quadruped")
	check_eq(stats_of(bare)["speed_mps"], plain["speed_mps"], "trading them away restores the speed")
