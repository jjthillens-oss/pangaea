extends TestCase
## Deed rewards come from actual world interactions, once per qualifying action or sighting.

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


func _deeds(events: Array, deed: String) -> Array:
	return events.filter(func(e): return e["kind"] == "earned" and e["deed"] == deed)


func test_landed_bite_earns_points_but_cooldown_and_miss_do_not() -> void:
	var sim := _sim()
	var rival: Dictionary = sim.rivals[0]
	var reach: float = sim.player()["bite_reach_m"]
	sim._place(sim.me, Vector3(20.0, 0.0, 20.0))
	sim.me["yaw"] = 0.0
	sim.me["planner"].yaw = 0.0
	sim.me["stats"]["sight_m"] = 0.0
	sim._place(
		rival, Vector3(20.0, 0.0, 20.0 - reach - float(rival["stats"]["body_radius_m"]) * 0.5)
	)
	rival["health"] = 10000.0
	var before := sim.points
	var landed: Array = sim.tick(_intent(true))
	check_eq(
		landed.filter(func(e): return e["kind"] == "bit" and e["by"] == Sim.PLAYER_ID).size(),
		1,
		"bite lands"
	)
	var earned := _deeds(landed, "bit")
	check_eq(earned.size(), 1, "one bite reward")
	check_eq(
		sim.points,
		before + int(tuning["deeds"]["bite_points"]),
		"bite points enter the shared purse"
	)
	if earned.size() == 1:
		check_eq(
			earned[0]["points"], int(tuning["deeds"]["bite_points"]), "reward reports its points"
		)
	var cooling: Array = sim.tick(_intent(true))
	check(
		cooling.filter(func(e): return e["kind"] == "bit" and e["by"] == Sim.PLAYER_ID).is_empty(),
		"cooldown prevents another bite"
	)
	check(_deeds(cooling, "bit").is_empty(), "cooldown earns nothing")
	check_eq(sim.points, before + int(tuning["deeds"]["bite_points"]), "cooldown adds no points")
	sim.me["cooldown"] = 0
	sim._place(rival, Vector3(-30.0, 0.0, -30.0))
	var missed: Array = sim.tick(_intent(true))
	check(
		missed.filter(func(e): return e["kind"] == "bit" and e["by"] == Sim.PLAYER_ID).is_empty(),
		"bite misses out of reach"
	)
	check(_deeds(missed, "bit").is_empty(), "miss earns nothing")
	check_eq(sim.points, before + int(tuning["deeds"]["bite_points"]), "miss adds no points")


func test_a_survived_rival_hit_earns_points_without_changing_stats() -> void:
	var sim := _sim()
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
	var before := sim.points
	var events := []
	sim._bite(rival, sim._alive_creatures(), events)
	check_eq(
		events.filter(func(e): return e["kind"] == "hit" and e["target"] == Sim.PLAYER_ID).size(),
		1,
		"rival hits the player"
	)
	check(float(sim.me["health"]) > 0.0, "the player survives")
	var earned := _deeds(events, "survived")
	check_eq(earned.size(), 1, "one survived-hit reward")
	check_eq(
		sim.points, before + int(tuning["deeds"]["hit_points"]), "hit points enter the shared purse"
	)
	check_eq(
		float(sim.me["stats"]["max_health"]), old_max, "body-derived maximum health stays unchanged"
	)


func test_one_living_rival_only_grants_spotted_points_once() -> void:
	var sim := _sim()
	var rival: Dictionary = sim.rivals[0]
	sim._place(sim.me, Vector3(30.0, 0.0, 0.0))
	sim.me["stats"]["sight_m"] = 20.0
	sim._place(rival, Vector3(30.0, 0.0, -8.0))
	var before := sim.points
	var first: Array = sim.tick(_intent(false))
	check_eq(_deeds(first, "spotted").size(), 1, "first sighting earns a reward")
	var earned := int(tuning["deeds"]["spot_points"])
	check_eq(sim.points, before + earned, "spotted points enter the shared purse")
	var continued: Array = sim.tick(_intent(false))
	check(_deeds(continued, "spotted").is_empty(), "continued sight gives no duplicate reward")
	sim._place(rival, Vector3(-30.0, 0.0, -30.0))
	sim.tick(_intent(false))
	sim._place(rival, Vector3(30.0, 0.0, -8.0))
	var returned: Array = sim.tick(_intent(false))
	check(_deeds(returned, "spotted").is_empty(), "leaving and returning gives no second reward")
	check_eq(sim.points, before + earned, "the purse receives only the first sighting")
