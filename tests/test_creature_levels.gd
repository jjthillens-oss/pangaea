extends TestCase
## Stat levels earned by doing (game/domain/creature/creature_levels.gd, PROPOSED): the level curve, the multipliers,
## applying them to the body's stats, and the world sim earning speed by walking and senses by spotting rivals.

const Sim := preload("res://game/systems/creature/creature_world_sim.gd")
const Fixtures := preload("res://tests/creature_fixtures.gd")

var tuning := {}
var levels := {}


func before_each() -> void:
	tuning = Sim.load_tuning()
	levels = tuning["levels"]


func test_each_level_needs_more_experience_up_to_the_cap() -> void:
	check_eq(CreatureLevels.level_of(0, levels), 0, "no experience, level 0")
	var top := int(levels["max_level"])
	var last := 0
	for n in range(1, top + 1):
		var need := CreatureLevels.xp_for_level(n, levels)
		check(need > last, "level %d needs more than level %d (%d)" % [n, n - 1, need])
		check_eq(CreatureLevels.level_of(need - 1, levels), n - 1, "one short of level %d" % n)
		check_eq(CreatureLevels.level_of(need, levels), n, "exactly level %d" % n)
		last = need
	check_eq(CreatureLevels.level_of(1000000, levels), top, "never past the cap")
	check(is_equal_approx(CreatureLevels.multiplier(top, levels), 1.0 + float(levels["per_level"]) * top), "the top multiplier")


func test_levels_scale_their_own_stat_only() -> void:
	var stats := {"speed_mps": 4.0, "speed_factor": 0.8, "bite_power": 10.0, "max_health": 100.0, "sight_m": 9.0}
	var xp := {"strength": CreatureLevels.xp_for_level(2, levels)}
	var out := CreatureLevels.apply(stats, xp, tuning)
	var m := CreatureLevels.multiplier(2, levels)
	check(is_equal_approx(out["bite_power"], 10.0 * m), "strength scales the bite")
	check_eq(out["speed_mps"], 4.0, "and leaves the speed")
	check_eq(out["max_health"], 100.0, "and the health")
	check_eq(stats["bite_power"], 10.0, "the input is untouched")
	var sighted := CreatureLevels.apply(stats, {"senses": 1000000}, tuning)
	check(sighted["sight_m"] <= float(tuning["sight"]["max_m"]), "senses stay within the sight cap")


func test_a_saved_experience_is_checked() -> void:
	check(CreatureLevels.problems({"speed": 12, "senses": 0}).is_empty(), "good experience passes")
	check(not CreatureLevels.problems({"speed": -1}).is_empty(), "negative is refused")
	check(not CreatureLevels.problems({"flight": 3}).is_empty(), "an unknown stat is refused")
	check(not CreatureLevels.problems([1, 2]).is_empty(), "a list is refused")


func test_walking_earns_speed_and_a_level_raises_the_stat() -> void:
	var sim := Sim.new(Fixtures.body("s1_quadruped").to_dict(), 7, tuning, {})
	var base := float(sim.player()["speed_mps"])
	var ups := []
	for t in 3600:
		for e in sim.tick({"move": Vector2(0.0, -1.0) if (t / 600) % 2 == 0 else Vector2(0.0, 1.0), "bite": false, "evolve": false}):
			if e["kind"] == "level_up":
				ups.append(e)
	check(int(sim.xp.get("speed", 0)) > 0, "a minute of walking earns speed experience (%d)" % int(sim.xp.get("speed", 0)))
	var speed_ups := ups.filter(func(e): return e["stat"] == "speed")
	check(not speed_ups.is_empty(), "and at least one speed level")
	check(float(sim.player()["speed_mps"]) > base, "which raises the top speed (%.2f > %.2f)" % [sim.player()["speed_mps"], base])


func test_saved_experience_sets_the_levels_and_full_health() -> void:
	var sim := Sim.new(Fixtures.body("s1_quadruped").to_dict(), 7, tuning, {})
	var base := float(sim.player()["max_health"])
	sim.set_xp({"toughness": CreatureLevels.xp_for_level(3, levels)})
	check_eq(int(sim.levels()["toughness"]), 3, "level 3 toughness")
	check(is_equal_approx(float(sim.player()["max_health"]), base * CreatureLevels.multiplier(3, levels)), "the health grew")
	check(is_equal_approx(float(sim.player()["health"]), float(sim.player()["max_health"])), "and starts full")
