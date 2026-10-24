extends TestCase
## XP comes from actual world events, once per qualifying action or sighting.

const Sim := preload("res://game/systems/creature/creature_world_sim.gd")
const Fixtures := preload("res://tests/creature_fixtures.gd")

var tuning := {}


func before_each() -> void:
	tuning = Sim.load_tuning()
	tuning["rivals"]["count"] = 1
	tuning["fruit"]["count"] = 0


func _sim() -> CreatureWorldSim:
	return Sim.new(Fixtures.body("s1_quadruped").to_dict(), 7, tuning, {})


func _intent(bite: bool) -> Dictionary:
	return {"move": Vector2.ZERO, "bite": bite, "evolve": false}


func test_strength_xp_requires_a_landed_bite_not_cooldown_or_a_miss() -> void:
	var sim := _sim()
	var rival: Dictionary = sim.rivals[0]
	var reach: float = sim.player()["bite_reach_m"]
	sim._place(sim.me, Vector3(20.0, 0.0, 20.0))
	sim.me["yaw"] = 0.0
	sim.me["planner"].yaw = 0.0
	sim._place(
		rival, Vector3(20.0, 0.0, 20.0 - reach - float(rival["stats"]["body_radius_m"]) * 0.5)
	)
	rival["health"] = 10000.0
	var landed: Array = sim.tick(_intent(true))
	check_eq(
		landed.filter(func(e): return e["kind"] == "bit" and e["by"] == Sim.PLAYER_ID).size(),
		1,
		"bite lands"
	)
	var earned := int(tuning["levels"]["bite_xp"])
	check_eq(int(sim.xp.get("strength", 0)), earned, "landed bite earns strength XP")
	var cooling: Array = sim.tick(_intent(true))
	check(
		cooling.filter(func(e): return e["kind"] == "bit" and e["by"] == Sim.PLAYER_ID).is_empty(),
		"cooldown prevents another bite"
	)
	check_eq(int(sim.xp.get("strength", 0)), earned, "cooldown earns no strength XP")
	sim.me["cooldown"] = 0
	sim._place(rival, Vector3(-30.0, 0.0, -30.0))
	var missed: Array = sim.tick(_intent(true))
	check(
		missed.filter(func(e): return e["kind"] == "bit" and e["by"] == Sim.PLAYER_ID).is_empty(),
		"bite misses out of reach"
	)
	check_eq(int(sim.xp.get("strength", 0)), earned, "miss earns no strength XP")


func test_incoming_hit_levels_toughness_without_refilling_health() -> void:
	var sim := _sim()
	var gain := int(tuning["levels"]["hit_xp"])
	var need := CreatureLevels.xp_for_level(1, tuning["levels"])
	sim.set_xp({"toughness": need - gain})
	sim._place(sim.me, Vector3(30.0, 0.0, 0.0))
	var rival: Dictionary = sim.rivals[0]
	sim._place(rival, Vector3(30.0, 0.0, 2.0))
	rival["yaw"] = 0.0
	rival["cooldown"] = 0
	rival["stats"]["has_mouth"] = true
	rival["stats"]["bite_reach_m"] = 3.0
	rival["stats"]["bite_power"] = 2.0
	var old_max: float = sim.me["stats"]["max_health"]
	sim.me["health"] = old_max * 0.6
	var events := []
	sim._bite(rival, sim._alive_creatures(), events)
	var hits := events.filter(func(e): return e["kind"] == "hit" and e["target"] == Sim.PLAYER_ID)
	check_eq(hits.size(), 1, "rival bite hits the player")
	check_eq(int(sim.xp.get("toughness", 0)), need, "the hit reaches level-one toughness")
	check_eq(int(sim.levels()["toughness"]), 1, "toughness level rises")
	check_eq(
		events.filter(func(e): return e["kind"] == "level_up" and e["stat"] == "toughness").size(),
		1,
		"one level-up notice"
	)
	var new_max: float = sim.me["stats"]["max_health"]
	check(new_max > old_max, "toughness increases maximum health")
	if hits.size() == 1:
		var share := (old_max * 0.6 - float(hits[0]["damage"])) / old_max
		check_near(
			float(sim.me["health"]) / new_max,
			share,
			0.0001,
			"level-up preserves health share after damage"
		)


func test_one_living_rival_only_grants_senses_xp_once() -> void:
	var sim := _sim()
	var rival: Dictionary = sim.rivals[0]
	sim._place(sim.me, Vector3(30.0, 0.0, 0.0))
	sim.me["stats"]["sight_m"] = 20.0
	sim._place(rival, Vector3(30.0, 0.0, -8.0))
	sim.tick(_intent(false))
	var earned := int(tuning["levels"]["spot_xp"])
	check_eq(int(sim.xp.get("senses", 0)), earned, "first sighting earns senses XP")
	sim.tick(_intent(false))
	check_eq(int(sim.xp.get("senses", 0)), earned, "continued sight gives no duplicate XP")
	sim._place(rival, Vector3(-30.0, 0.0, -30.0))
	sim.tick(_intent(false))
	sim._place(rival, Vector3(30.0, 0.0, -8.0))
	sim.tick(_intent(false))
	check_eq(int(sim.xp.get("senses", 0)), earned, "leaving and returning does not award XP again")
