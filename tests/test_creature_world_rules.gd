extends TestCase
## The test field's pure rules (game/domain/creature/creature_world_rules.gd) and the rival brain
## (creature_rival_brain.gd): steering, walls, bites, food, death, evolve, draws and decisions from percepts.

const Rules := preload("res://game/domain/creature/creature_world_rules.gd")
const Brain := preload("res://game/domain/creature/creature_rival_brain.gd")
const Fixtures := preload("res://tests/creature_fixtures.gd")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")

const RIVALS := {"flee_mass_ratio": 1.3, "hunt_mass_ratio": 0.7, "hungry_below": 0.5}


func test_seconds_become_whole_ticks() -> void:
	check_eq(Rules.to_ticks(0.8, 60), 48, "0.8 s")
	check_eq(Rules.to_ticks(30.0, 60), 1800, "30 s")
	check_eq(Rules.to_ticks(0.001, 60), 1, "never below one tick")


func test_steering_turns_towards_the_wanted_direction_and_walks_when_facing_it() -> void:
	var ahead := Rules.steer(0.0, Vector2(0.0, -1.0), 1.0)
	check(is_equal_approx(ahead.x, 1.0) and is_zero_approx(ahead.y), "facing -Z and wanting -Z: full throttle, no turn")
	var left := Rules.steer(0.0, Vector2(-1.0, 0.0), 1.0)
	check(left.y > 0.99, "wanting -X from yaw 0 turns left at the full rate")
	check(left.x < 0.01, "and does not walk sideways")
	var right := Rules.steer(0.0, Vector2(1.0, 0.0), 1.0)
	check(right.y < -0.99, "wanting +X turns right")
	var back := Rules.steer(0.0, Vector2(0.0, 1.0), 1.0)
	check(is_zero_approx(back.x), "wanting the opposite way: turn in place, no throttle")
	check(Rules.steer(0.0, Vector2.ZERO, 1.0) == Vector2.ZERO and Rules.steer(0.0, Vector2(0, -1), 0.0) == Vector2.ZERO, "no wish, no command")
	check(Rules.forward(0.0).is_equal_approx(Vector2(0.0, -1.0)) and Rules.forward(PI / 2).is_equal_approx(Vector2(-1.0, 0.0)), "forward")


func test_the_walls_keep_a_body_inside_the_field() -> void:
	var p := Rules.clamp_to_field(Vector3(100.0, 0.0, -95.0), 80.0, 1.0)
	check(p.is_equal_approx(Vector3(79.0, 0.0, -79.0)), "clamped to the half size minus the radius (%s)" % p)
	check(Rules.clamp_to_field(Vector3(3.0, 0.5, 4.0), 80.0, 1.0).is_equal_approx(Vector3(3.0, 0.5, 4.0)), "inside stays")


func test_a_bite_lands_in_reach_and_in_the_cone() -> void:
	check(Rules.bite_lands(Vector3.ZERO, 0.0, 0.5, Vector3(0.0, 0.0, -1.0), 0.6), "ahead within reach plus radius")
	check(not Rules.bite_lands(Vector3.ZERO, 0.0, 0.5, Vector3(0.0, 0.0, -2.0), 0.6), "ahead but too far")
	check(not Rules.bite_lands(Vector3.ZERO, 0.0, 0.5, Vector3(0.0, 0.0, 1.0), 0.6), "behind, in reach, is not bitten")
	check(Rules.bite_lands(Vector3.ZERO, 0.0, 0.5, Vector3(-0.5, 0.0, -0.8), 0.6), "45 degrees off is in the cone")
	check(Rules.touches(Vector3.ZERO, 0.4, Vector3(0.8, 0.0, 0.0), 0.5) and not Rules.touches(Vector3.ZERO, 0.4, Vector3(1.0, 0.0, 0.0), 0.5), "touch")


func test_food_points_and_the_death_toll() -> void:
	check_eq(Rules.fruit_points(5, true, 0.5), 5, "a mouth eats the whole fruit")
	check_eq(Rules.fruit_points(5, false, 0.5), 2, "no mouth: half, rounded down")
	check_eq(Rules.fruit_points(1, false, 0.5), 1, "but at least one")
	check_eq(Rules.points_after_death(150, 0.2), 120, "a death costs a fifth")
	check_eq(Rules.points_after_death(7, 0.2), 6, "rounded down")
	check(Rules.can_evolve(true)["ok"] and not Rules.can_evolve(false)["ok"], "evolve only at the nest")
	check_eq(Rules.can_evolve(false)["reason"], "Return to the nest to evolve", "the refusal names the nest")


func test_overlapping_bodies_are_pushed_apart_by_inverse_mass() -> void:
	var push: Array = Rules.separate(Vector3.ZERO, 1.0, 10.0, Vector3(1.0, 0.0, 0.0), 1.0, 30.0)
	check((push[0] as Vector3).is_equal_approx(Vector3(-0.75, 0.0, 0.0)), "the light body moves most (%s)" % push[0])
	check((push[1] as Vector3).is_equal_approx(Vector3(0.25, 0.0, 0.0)), "the heavy one least (%s)" % push[1])
	var none: Array = Rules.separate(Vector3.ZERO, 1.0, 10.0, Vector3(3.0, 0.0, 0.0), 1.0, 30.0)
	check(none[0] == Vector3.ZERO and none[1] == Vector3.ZERO, "no overlap, no push")


func test_scatter_keeps_out_of_the_nest_and_is_seeded() -> void:
	var a := RandomNumberGenerator.new()
	a.seed = 5
	var b := RandomNumberGenerator.new()
	b.seed = 5
	var pa: Array = Rules.scatter(a, 40, 80.0, 6.0, 2.0)
	var pb: Array = Rules.scatter(b, 40, 80.0, 6.0, 2.0)
	check_eq(pa.size(), 40, "forty spots")
	check(pa == pb, "the same seed gives the same spots")
	for p in pa:
		check(Vector2(p.x, p.z).length() >= 10.0 and absf(p.x) <= 78.0 and absf(p.z) <= 78.0, "spot %s is outside the nest and inside the walls" % p)


func test_rival_bodies_are_legged_starters_with_parts_that_validate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var starters := {}
	for n in CreatureData.STARTER_NAMES:
		starters[n] = CreatureData.read_json(CreatureData.DATA_DIR + "/starter_bodies.json")["bodies"][n]
	var names: Array = Rules.pick_rival_starters(starters, 6, rng)
	check_eq(names.size(), 6, "six rivals")
	check(not names.has("snake"), "the snake has no legs and is never a rival")
	var rules := CreatureData.rules()
	var part_rules := CreatureData.part_rules()
	var costs := CreatureData.editor_costs()
	var extra := 0
	for n in names:
		var starter = Fixtures.body("s1_" + n)
		var body = Rules.draw_rival_body(starter, rng, rules, part_rules, costs)
		check(body.validate(rules).is_empty() and body.validate_parts(rules, part_rules).is_empty(), "%s rival validates" % n)
		var added: int = body.parts.size() - starter.parts.size()
		check(added >= 0 and added <= Rules.RIVAL_PARTS_MAX, "%s wears 0..%d drawn parts (%d)" % [n, Rules.RIVAL_PARTS_MAX, added])
		extra += added
	check(extra > 0, "some rival wears a drawn part (%d in all)" % extra)


func percepts(extra: Dictionary) -> Dictionary:
	var base := {"food": {}, "creature": {}, "fullness": 1.0, "nest": {"dir": Vector2(0, -1), "dist": 10.0},
			"heading": Vector2(0, -1), "bite_reach": 0.4, "noise": 0.0}
	base.merge(extra, true)
	return base


func test_the_brain_flees_bigger_hunts_smaller_when_hungry_grazes_and_wanders() -> void:
	var memory := Brain.fresh_memory(Vector2(0, -1))
	var flee: Dictionary = Brain.decide(percepts({"creature": {"dir": Vector2(1, 0), "dist": 3.0, "mass_ratio": 2.0}}), memory, RIVALS)
	check(flee["mode"] == "flee" and (flee["heading"] as Vector2).is_equal_approx(Vector2(-1, 0)) and flee["throttle"] == 1.0, "flee a bigger creature, away from it")
	var hunt: Dictionary = Brain.decide(percepts({"creature": {"dir": Vector2(1, 0), "dist": 0.3, "mass_ratio": 0.5}, "fullness": 0.2}), memory, RIVALS)
	check(hunt["mode"] == "hunt" and hunt["bite"] and (hunt["heading"] as Vector2).is_equal_approx(Vector2(1, 0)), "hunt a smaller creature when hungry, biting in reach")
	var full: Dictionary = Brain.decide(percepts({"creature": {"dir": Vector2(1, 0), "dist": 0.3, "mass_ratio": 0.5}, "fullness": 0.9}), memory, RIVALS)
	check(full["mode"] == "wander", "a full creature leaves the small one alone")
	var toothless: Dictionary = Brain.decide(percepts({"creature": {"dir": Vector2(1, 0), "dist": 0.3, "mass_ratio": 0.5}, "fullness": 0.2, "bite_reach": 0.0}), memory, RIVALS)
	check(toothless["mode"] != "hunt", "no mouth, no hunt")
	var graze: Dictionary = Brain.decide(percepts({"food": {"dir": Vector2(0, 1), "dist": 5.0}, "fullness": 0.6}), memory, RIVALS)
	check(graze["mode"] == "graze" and (graze["heading"] as Vector2).is_equal_approx(Vector2(0, 1)), "graze towards food with room for it")
	var wander: Dictionary = Brain.decide(percepts({"noise": 1.0}), memory, RIVALS)
	check(wander["mode"] == "wander" and not wander["bite"], "nothing sensed: wander")
	check(absf((wander["heading"] as Vector2).angle_to(Vector2(0, -1))) > 0.0, "the wander heading drifts with the noise")
	check(memory["mode"] == "wander", "memory keeps the mode")
	var far: Dictionary = Brain.decide(percepts({"nest": {"dir": Vector2(1, 0), "dist": 70.0}}), memory, RIVALS)
	check((far["heading"] as Vector2).is_equal_approx(Vector2(1, 0)), "far from the nest a wanderer turns back")


func test_the_brain_is_deterministic_for_the_same_percepts() -> void:
	var a := Brain.fresh_memory(Vector2(1, 0))
	var b := Brain.fresh_memory(Vector2(1, 0))
	for i in 50:
		var p := percepts({"noise": sin(i * 0.7)})
		check(Brain.decide(p, a, RIVALS) == Brain.decide(p, b, RIVALS), "decision %d" % i)
	check(a == b, "memories agree")
