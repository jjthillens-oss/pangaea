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
	check(b["speed_mps"] > a["speed_mps"], "and is faster (%.2f > %.2f m/s)" % [b["speed_mps"], a["speed_mps"]])
	check(is_equal_approx(b["speed_mps"] / a["speed_mps"], sqrt(2.0)), "top speed scales with the square root of leg length")
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
	check(one["has_mouth"] and is_equal_approx(one["bite_power"], 10.0), "one maw: base 5 + 5 (%.1f)" % one["bite_power"])
	bare.add_part("mandibles", {"host": "spine", "u": 1000, "ring": 500, "scale": 2000})
	var two := stats_of(bare)
	check(is_equal_approx(two["bite_power"], 20.0), "a second mouth at scale 2 adds 10 (%.1f)" % two["bite_power"])
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
