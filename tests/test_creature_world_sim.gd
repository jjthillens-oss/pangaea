extends TestCase
## The test field's simulation (game/systems/creature/creature_world_sim.gd): deterministic for a seed and the
## intents, eating, bites, death at the nest, evolve only at the nest, a legless body, and no NaN over a minute.

const Sim := preload("res://game/systems/creature/creature_world_sim.gd")
const Fixtures := preload("res://tests/creature_fixtures.gd")

var tuning := {}
var data := {}


func before_each() -> void:
	tuning = Sim.load_tuning()
	data = Sim.load_data()


func make(body_name := "s1_quadruped", seed_value := 7) -> CreatureWorldSim:
	return Sim.new(Fixtures.body(body_name).to_dict(), seed_value, tuning, data)


## A scripted drive: forward for 4 s, a left arc, a bite burst, a stop, then forward again.
static func intent_at(t: int) -> Dictionary:
	var move := Vector2(0.0, -1.0)
	if t >= 240 and t < 480:
		move = Vector2(-0.7, -0.7)
	elif t >= 600 and t < 700:
		move = Vector2.ZERO
	elif t >= 700:
		move = Vector2(1.0, 0.0)
	return {"move": move, "bite": t % 90 < 10, "evolve": t == 50 or t == 900}


func stream_hash(seed_value: int, ticks: int) -> String:
	var sim := make("s1_quadruped", seed_value)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for t in ticks:
		sim.tick(intent_at(t))
		ctx.update(JSON.stringify(sim.snapshot()).to_utf8_buffer())
	return ctx.finish().hex_encode()


func test_the_same_seed_and_intents_give_the_same_snapshot_stream() -> void:
	var a := stream_hash(7, 1200)
	var b := stream_hash(7, 1200)
	check_eq(a, b, "SHA-256 of 1200 snapshots, twice")
	check(stream_hash(8, 1200) != a, "another seed differs")


func test_setup_lays_out_the_field_from_the_tuning() -> void:
	var sim := make()
	check_eq(sim.fruit.size(), 40, "forty bushes")
	check_eq(sim.rivals.size(), 6, "six rivals")
	check_eq(sim.points, 150, "the start points")
	check(sim.at_nest(), "the player starts at the nest")
	check(sim.player()["has_legs"] and sim.player()["has_mouth"], "the quadruped walks and bites")
	check_eq(sim.ticks["fruit_regrow"], 1800, "regrow in whole ticks")
	check_eq(sim.ticks["bite_cooldown"], 48, "cooldown in whole ticks")
	for r in sim.rivals:
		check(r["planner"] != null, "%s (%s) walks" % [r["id"], r["starter"]])
		check(r["body"].validate(data["body_rules"]).is_empty(), "%s validates" % r["id"])
	var snap := sim.snapshot()
	check(snap["player"]["position"] is Array and snap["player"]["position"].size() == 3, "vectors are [x, y, z] arrays")
	check_eq(snap["rivals"][0]["id"], "r1", "rivals in id order")
	var ids := []
	for f in snap["fruit"]:
		ids.append(f["id"])
	check_eq(ids[0], "f1", "fruit in id order")


func test_walking_forward_moves_the_player_and_the_walls_hold() -> void:
	var sim := make()
	for t in 180:
		sim.tick({"move": Vector2(0.0, -1.0), "bite": false, "evolve": false})
	var p: Vector3 = sim.player()["position"]
	check(p.z < -2.0, "three seconds forward moves the player along -Z (%.2f m)" % p.z)
	check(absf(p.x) < 0.5, "and not sideways")
	check(not sim.at_nest(), "it left the nest")
	for t in 7200:
		sim.tick({"move": Vector2(0.0, -1.0), "bite": false, "evolve": false})
	p = sim.player()["position"]
	check(p.z >= -80.0 and p.z < -70.0, "two minutes on stops at the wall (%.2f m)" % p.z)
	var turned := make()
	for t in 180:
		turned.tick({"move": Vector2(1.0, 0.0), "bite": false, "evolve": false})
	var q: Vector3 = turned.player()["position"]
	check(q.x > 1.0 and absf(q.x) > absf(q.z), "wanting +X turns and walks that way (%s)" % q)


func test_eating_fruit_gives_points_and_the_bush_regrows() -> void:
	var sim := make()
	var bush: Dictionary = sim.fruit[0]
	sim._place(sim.me, bush["position"] + Vector3(0.0, 0.0, 0.6))
	var events: Array = sim.tick({"move": Vector2.ZERO, "bite": false, "evolve": false})
	var ate := events.filter(func(e): return e["kind"] == "ate" and e["who"] == "player")
	check_eq(ate.size(), 1, "one meal")
	if ate.size() == 1:
		check_eq(ate[0]["food"], "fruit", "fruit")
		check_eq(ate[0]["points"], 5, "worth the fruit points")
	check_eq(sim.points, 155, "points went up")
	check(not bush["ripe"], "the bush is bare")
	check_eq(int(bush["regrow_at"]), 1800, "and regrows after regrow_s")
	for t in 1800:
		sim.tick({"move": Vector2.ZERO, "bite": false, "evolve": false})
	check(bush["ripe"], "regrown")
	var mouthless := make("s1_tiny")
	if not mouthless.player()["has_mouth"]:
		var b2: Dictionary = mouthless.fruit[0]
		mouthless._place(mouthless.me, b2["position"])
		mouthless.tick({"move": Vector2.ZERO, "bite": false, "evolve": false})
		check_eq(mouthless.points, 152, "a body with no mouth eats fruit by touch at half points")


func test_a_bite_in_reach_hurts_and_cools_down() -> void:
	var sim := make()
	var rival: Dictionary = sim.rivals[0]
	var reach: float = sim.player()["bite_reach_m"]
	sim._place(sim.me, Vector3(20.0, 0.0, 20.0))
	sim.me["yaw"] = 0.0
	sim.me["planner"].yaw = 0.0
	sim._place(rival, Vector3(20.0, 0.0, 20.0 - reach - float(rival["stats"]["body_radius_m"]) * 0.5))
	var before: float = rival["health"]
	var events: Array = sim.tick({"move": Vector2.ZERO, "bite": true, "evolve": false})
	var bit := events.filter(func(e): return e["kind"] == "bit" and e["by"] == "player")
	var hit := events.filter(func(e): return e["kind"] == "hit" and e["target"] == rival["id"])
	check(bit.size() == 1 and hit.size() == 1, "a bite and its hit (%s)" % [events])
	check(before - rival["health"] >= sim.player()["bite_power"] - 0.1, "damage is the bite power (%.1f)" % (before - rival["health"]))
	var again: Array = sim.tick({"move": Vector2.ZERO, "bite": true, "evolve": false})
	check(again.filter(func(e): return e["kind"] == "bit" and e["by"] == "player").is_empty(), "no second bite inside the cooldown")
	sim._place(sim.me, Vector3(-20.0, 0.0, -20.0))
	for t in 60:
		sim.tick({"move": Vector2.ZERO, "bite": false, "evolve": false})
	var miss: Array = sim.tick({"move": Vector2.ZERO, "bite": true, "evolve": false})
	check(miss.filter(func(e): return e["kind"] == "bit").is_empty(), "nothing in reach, nothing bitten")


func test_biting_without_a_mouth_is_refused_once_per_press() -> void:
	var sim := make("s1_tiny")
	if sim.player()["has_mouth"]:
		check(true, "the tiny starter grew a mouth; nothing to refuse")
		return
	var first: Array = sim.tick({"move": Vector2.ZERO, "bite": true, "evolve": false})
	var refused := first.filter(func(e): return e["kind"] == "refused")
	check(refused.size() == 1 and refused[0]["reason"] == "No mouth to bite with", "the press is refused with the reason (%s)" % [first])
	var held: Array = sim.tick({"move": Vector2.ZERO, "bite": true, "evolve": false})
	check(held.filter(func(e): return e["kind"] == "refused").is_empty(), "holding the key says nothing more")
	sim.tick({"move": Vector2.ZERO, "bite": false, "evolve": false})
	var again: Array = sim.tick({"move": Vector2.ZERO, "bite": true, "evolve": false})
	check_eq(again.filter(func(e): return e["kind"] == "refused").size(), 1, "the next press is refused again")


func test_nothing_at_the_nest_can_be_bitten() -> void:
	var sim := make("s1_snake")
	check(not sim.player()["has_legs"] and sim.at_nest(), "a legless player at the nest")
	var rival: Dictionary = sim.rivals[0]
	rival["fullness"] = 0.0
	var reach := float(rival["stats"]["bite_reach_m"])
	var step := reach * 0.5 + float(sim.me["stats"]["body_radius_m"]) + float(rival["stats"]["body_radius_m"])
	sim._place(rival, Vector3(0.0, 0.0, step))
	rival["yaw"] = 0.0   # faces -Z, at the player
	if rival["planner"] != null:
		rival["planner"].yaw = 0.0
	var before: float = sim.me["health"]
	var bitten := 0
	for t in 120:
		for e in sim.tick({"move": Vector2.ZERO, "bite": false, "evolve": false}):
			if e["kind"] == "hit" and e["target"] == Sim.PLAYER_ID:
				bitten += 1
	check(bitten == 0 and sim.me["health"] >= before - 0.001, "a hungry rival next to the nest takes nothing (%d hits)" % bitten)
	# Away from the nest the same rival in the same place bites.
	var away := make("s1_snake")
	var r2: Dictionary = away.rivals[0]
	away._place(away.me, Vector3(30.0, 0.0, 0.0))
	away.me["cooldown"] = 0
	r2["fullness"] = 0.0
	away._place(r2, Vector3(30.0, 0.0, step))
	r2["yaw"] = 0.0
	if r2["planner"] != null:
		r2["planner"].yaw = 0.0
	r2["wants_bite"] = true
	var events := []
	away._bite(r2, away._alive_creatures(), events)
	check(events.filter(func(e): return e["kind"] == "hit" and e["target"] == Sim.PLAYER_ID).size() == 1,
			"the same bite lands away from the nest (%s)" % [events])


func test_death_sends_the_player_to_the_nest_with_the_points_loss() -> void:
	var sim := make()
	sim._place(sim.me, Vector3(30.0, 0.0, -10.0))
	sim.me["health"] = -1.0
	sim.me["last_hit_by"] = "r2"
	var events: Array = sim.tick({"move": Vector2.ZERO, "bite": false, "evolve": false})
	var died := events.filter(func(e): return e["kind"] == "died" and e["who"] == "player")
	check_eq(died.size(), 1, "a death event")
	if died.size() == 1:
		check_eq(died[0]["points_lost"], 30, "a fifth of 150")
		check_eq(died[0]["by"], "r2", "names the killer")
		var starter := String(sim.rivals[1]["starter"]).trim_prefix("s1_").replace("_", " ")
		check_eq(died[0]["cause"], "killed by a %s" % starter, "the cause reads as the rival's starter, not its id")
	check_eq(sim.points, 120, "points after the loss")
	check(sim.at_nest(), "back at the nest")
	check(is_equal_approx(sim.player()["health"], sim.player()["max_health"]), "full health")
	check_eq(sim.meat.size(), 1, "meat where it fell")
	if sim.meat.size() == 1:
		check((sim.meat[0]["position"] as Vector3).is_equal_approx(Vector3(30.0, 0.0, -10.0)), "at the death spot")
		check_eq(int(sim.meat[0]["decay_at"]), 3600, "decays after decay_s")
	check(sim.planner_of("player").position.is_equal_approx(Vector3.ZERO), "the planner was reset to the nest")


func test_evolve_only_at_the_nest_on_the_press() -> void:
	var sim := make()
	var at: Array = sim.tick({"move": Vector2.ZERO, "bite": false, "evolve": true})
	check(at.filter(func(e): return e["kind"] == "evolve").size() == 1, "at the nest: evolve")
	var held: Array = sim.tick({"move": Vector2.ZERO, "bite": false, "evolve": true})
	check(held.filter(func(e): return e["kind"] == "evolve").is_empty(), "holding the key does not repeat it")
	sim.tick({"move": Vector2.ZERO, "bite": false, "evolve": false})
	sim._place(sim.me, Vector3(30.0, 0.0, 0.0))
	var away: Array = sim.tick({"move": Vector2.ZERO, "bite": false, "evolve": true})
	var refused := away.filter(func(e): return e["kind"] == "refused")
	check(away.filter(func(e): return e["kind"] == "evolve").is_empty() and refused.size() == 1, "away from the nest: refused")
	if refused.size() == 1:
		check_eq(refused[0]["reason"], "Return to the nest to evolve", "with the reason")


func test_a_legless_body_stays_at_the_nest_but_can_evolve() -> void:
	var sim := make("s1_snake")
	check(not sim.player()["has_legs"], "no legs")
	check(sim.planner_of("player") == null, "no planner")
	for t in 120:
		sim.tick({"move": Vector2(0.0, -1.0), "bite": true, "evolve": false})
	check(sim.player()["position"].is_equal_approx(Vector3.ZERO) and sim.at_nest(), "it stays at the nest")
	var events: Array = sim.tick({"move": Vector2.ZERO, "bite": false, "evolve": true})
	check(events.filter(func(e): return e["kind"] == "evolve").size() == 1, "evolve works")


func test_rivals_stay_finite_and_inside_the_field_over_a_minute() -> void:
	var sim := make("s1_quadruped", 3)
	var modes := {}
	var events_seen := {}
	for t in 3600:
		for e in sim.tick(intent_at(t)):
			events_seen[e["kind"]] = true
		if t % 60 == 0:
			for r in sim.rivals:
				modes[r["mode"]] = true
	for r in sim.rivals:
		var p: Vector3 = r["position"]
		check(p.is_finite() and is_finite(float(r["yaw"])) and is_finite(float(r["health"])), "%s is finite" % r["id"])
		check(absf(p.x) <= 80.0 and absf(p.z) <= 80.0, "%s is inside the field (%s)" % [r["id"], p])
		if r["planner"] != null:
			check(r["planner"].is_finite_state(), "%s's planner is finite" % r["id"])
	check(modes.has("wander"), "rivals wander (%s)" % [modes.keys()])
	check(sim.player()["position"].is_finite(), "the player is finite")
	check(events_seen.has("ate"), "someone ate (%s)" % [events_seen.keys()])
