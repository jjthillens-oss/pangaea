extends TestCase
## The friend path (PROPOSED; owner direction 2026-10-24: keep Spore's befriending by song and dance): singing at a
## rival up close adds the singer's charm to its friendship; at friend_at it joins the pack, follows the player and
## helps fight; a bitten rival will not listen; display organs add charm with a cap.

const Sim := preload("res://game/systems/creature/creature_world_sim.gd")
const Brain := preload("res://game/domain/creature/creature_rival_brain.gd")
const Fixtures := preload("res://tests/creature_fixtures.gd")

var tuning := {}


func before_each() -> void:
	tuning = Sim.load_tuning()


## A sim with the player away from the nest (where nothing can be bitten) and rival r1 parked right in front of it,
## within bite reach; everything else far away.
func _face_to_face() -> Sim:
	var sim := Sim.new(Fixtures.body("s1_quadruped").to_dict(), 7, tuning, {})
	sim._place(sim.me, Vector3(30.0, 0.0, 0.0))
	var ahead: Vector2 = Sim.Rules.forward(sim.me["yaw"])
	var spot: Vector3 = sim.me["position"] + Vector3(ahead.x, 0.0, ahead.y) * _gap(sim)
	for r in sim.rivals:
		var far := Vector3(60.0, 0.0, 60.0)
		sim._place(r, far)
	sim._place(sim.rivals[0], spot)
	sim.rivals[0]["fullness"] = 1.0
	return sim


func _gap(sim: Sim) -> float:
	return float(sim.me["stats"]["body_radius_m"]) + float(sim.rivals[0]["stats"]["body_radius_m"]) * 0.5


func _sing_once(sim: Sim) -> Array:
	var events: Array = sim.tick({"move": Vector2.ZERO, "bite": false, "evolve": false, "social": true})
	for t in int(ceil(float(tuning["social"]["cooldown_s"]) * 60.0)):
		events.append_array(sim.tick({"move": Vector2.ZERO, "bite": false, "evolve": false, "social": false}))
		var r: Dictionary = sim.rivals[0]
		var ahead: Vector2 = Sim.Rules.forward(sim.me["yaw"])
		sim._place(r, sim.me["position"] + Vector3(ahead.x, 0.0, ahead.y) * _gap(sim))
	return events


func test_singing_befriends_a_rival_and_pays_points() -> void:
	var sim := _face_to_face()
	var before: int = sim.points
	var all := []
	for i in 12:
		all.append_array(_sing_once(sim))
		if sim.rivals[0]["ally"]:
			break
	var charmed := all.filter(func(e): return e["kind"] == "charmed")
	check(charmed.size() >= 2, "it takes a few songs (%d)" % charmed.size())
	check(sim.rivals[0]["ally"], "the rival joined the pack")
	check(not all.filter(func(e): return e["kind"] == "befriended").is_empty(), "a befriended event")
	check(sim.points >= before + int(tuning["social"]["befriend_points"]), "worth points (%d -> %d)" % [before, sim.points])
	check_eq(sim.allies(), [sim.rivals[0]["id"]], "allies() lists it")


func test_nobody_close_is_refused_once() -> void:
	var sim := Sim.new(Fixtures.body("s1_quadruped").to_dict(), 7, tuning, {})
	for r in sim.rivals:
		sim._place(r, Vector3(60.0, 0.0, 60.0))
	var refused := 0
	for t in 30:
		for e in sim.tick({"move": Vector2.ZERO, "bite": false, "evolve": false, "social": true}):
			if e["kind"] == "refused":
				refused += 1
	check_eq(refused, 1, "one notice while the button is held")


func test_a_bitten_rival_will_not_listen_and_an_ally_bitten_leaves() -> void:
	var sim := _face_to_face()
	sim.rivals[0]["ally"] = true
	sim.rivals[0]["friendship"] = float(tuning["social"]["friend_at"])
	sim.rivals[0]["hostile"] = false
	# The player's bite skips its allies.
	sim.tick({"move": Vector2.ZERO, "bite": true, "evolve": false})
	check(sim.rivals[0]["ally"], "the player's bite does not land on an ally")
	sim.rivals[0]["ally"] = false
	sim.rivals[0]["friendship"] = 2.0
	sim.me["cooldown"] = 0
	var events: Array = sim.tick({"move": Vector2.ZERO, "bite": false, "evolve": false})
	events = sim.tick({"move": Vector2.ZERO, "bite": true, "evolve": false})
	check(sim.rivals[0]["hostile"], "a bitten rival turns hostile")
	check_eq(float(sim.rivals[0]["friendship"]), 0.0, "and forgets the songs")
	var after := _sing_once(sim)
	check(not after.filter(func(e): return e["kind"] == "snubbed").is_empty(), "so it snubs the next song")


func test_an_ally_follows_and_helps_fight() -> void:
	var t: Dictionary = tuning["rivals"].duplicate()
	t["follow_m"] = 5.0
	var memory := Brain.fresh_memory(Vector2(0.0, -1.0))
	var far := Brain.decide({"leader": {"dir": Vector2(1.0, 0.0), "dist": 20.0}, "bite_reach": 1.0}, memory, t)
	check_eq(far["mode"], "follow", "a distant leader is followed")
	check_eq(far["heading"], Vector2(1.0, 0.0), "towards it")
	var fight := Brain.decide({"leader": {"dir": Vector2(1.0, 0.0), "dist": 2.0}, "foe": {"dir": Vector2(0.0, 1.0), "dist": 0.5},
			"bite_reach": 1.0}, memory, t)
	check_eq(fight["mode"], "assist", "the leader's foe is attacked")
	check(fight["bite"], "and bitten in reach")
	var near := Brain.decide({"leader": {"dir": Vector2(1.0, 0.0), "dist": 2.0}, "fullness": 1.0}, memory, t)
	check(near["mode"] != "follow" and near["mode"] != "assist", "close by, it lives its own life (%s)" % near["mode"])


func test_display_organs_add_charm_up_to_a_cap() -> void:
	var data := Sim.load_data()
	var body = Fixtures.body("s1_quadruped")
	var plain := CreatureStats.of(body, data["part_rules"], data["gait_table"], tuning)
	var displays := CreatureStats.count_parts(body, CreatureStats.types_with_role(data["part_rules"], CreatureStats.DISPLAY_ROLE), data["part_rules"])
	var social: Dictionary = tuning["social"]
	check(is_equal_approx(float(plain["charm"]), float(social["base_charm"]) + float(social["per_display_part"])
			* mini(displays, int(social["display_cap"]))), "charm = base + per display organ, capped")
	check(float(social["base_charm"]) + float(social["per_display_part"]) * int(social["display_cap"])
			< float(social["friend_at"]), "no body befriends in one song")
