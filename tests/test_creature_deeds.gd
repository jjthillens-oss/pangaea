extends TestCase
## Adaptation points earned by doing (tuning "deeds", owner pick 2026-10-24 after the Bible check): walking, landed
## bites, hits survived and rivals spotted add to the same points as eating, and leave the stats to the body.

const Sim := preload("res://game/systems/creature/creature_world_sim.gd")
const Fixtures := preload("res://tests/creature_fixtures.gd")

var tuning := {}


func before_each() -> void:
	tuning = Sim.load_tuning()


func _walk(sim, ticks: int) -> Array:
	var earned := []
	for t in ticks:
		for e in sim.tick({"move": Vector2(0.0, -1.0) if (t / 600) % 2 == 0 else Vector2(0.0, 1.0), "bite": false, "evolve": false}):
			if e["kind"] == "earned":
				earned.append(e)
	return earned


func test_walking_earns_points_and_leaves_the_stats_alone() -> void:
	var sim := Sim.new(Fixtures.body("s1_quadruped").to_dict(), 7, tuning, {})
	var stats_before: Dictionary = sim.player().duplicate()
	var earned := _walk(sim, 3600)
	var walked := earned.filter(func(e): return e["deed"] == "walked")
	check(not walked.is_empty(), "a minute of walking earns points")
	var total := 0
	for e in earned:
		total += int(e["points"])
	check(sim.points >= int(tuning["start_points"]) + total, "the points are in the purse (%d)" % sim.points)
	for k in ["speed_mps", "max_health", "bite_power", "sight_m"]:
		if stats_before.has(k):
			check_eq(sim.player()[k], stats_before[k], "%s is still the body's" % k)


func test_a_walk_earns_one_point_per_stretch() -> void:
	var sim := Sim.new(Fixtures.body("s1_quadruped").to_dict(), 7, tuning, {})
	var walked := _walk(sim, 3600).filter(func(e): return e["deed"] == "walked")
	var per := float(tuning["deeds"]["walk_m_per_point"])
	var points := 0
	for e in walked:
		points += int(e["points"])
	var top := float(sim.player()["speed_mps"]) * 60.0
	check(points <= int(ceil(top / per)), "no more than the distance allows (%d <= %.0f m / %.0f)" % [points, top, per])


func test_without_deed_tuning_nothing_is_earned() -> void:
	tuning.erase("deeds")
	var sim := Sim.new(Fixtures.body("s1_quadruped").to_dict(), 7, tuning, {})
	check(_walk(sim, 1200).is_empty(), "no deeds, no earned events")
