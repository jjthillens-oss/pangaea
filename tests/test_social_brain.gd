extends TestCase
## The Social stage's brains (PROPOSED, docs/stages/social-plan.md sections 7 and 8; Bible sections 8 and 13), from
## percepts only: every order is carried out, reported and ended (no frozen companion), a companion without a leader
## goes home and waits, and the hunter shows a tell before it pursues, always disengages and never enters the nest.

const SLICE_PATH := "res://game/data/social/social_slice.json"

var tuning := {}


func before_each() -> void:
	tuning = SocialRules.with_ticks(JSON.parse_string(FileAccess.get_file_as_string(SLICE_PATH)))


static func _seen(from: Vector2, to: Vector2) -> Dictionary:
	var d := to - from
	return {"dir": d.normalized() if d.length() > 0.0001 else Vector2(0.0, -1.0), "dist": d.length()}


func _companion(extra := {}) -> Dictionary:
	var p := {"role": "scout", "fear": 0.0, "hunger": 0.1, "carrying": 0, "heading": Vector2(0.0, -1.0),
			"bite_reach": 1.0, "noise": 0.0, "elapsed_t": 1, "disposition": "curious",
			"home": {"dir": Vector2(1.0, 0.0), "dist": 12.0, "radius": 5.0},
			"nest": {"dir": Vector2(-1.0, 0.0), "dist": 9.0, "radius": 6.0}}
	p.merge(extra, true)
	return p


func test_a_follower_keeps_within_follow_distance() -> void:
	var follow_m := float(tuning["band"]["follow_m"])
	var memory := CompanionBrain.fresh_memory(Vector2(0.0, -1.0))
	var far := CompanionBrain.decide(_companion({"order": {"name": "follow", "ticks_left": -1},
			"leader": {"dir": Vector2(1.0, 0.0), "dist": follow_m + 6.0}}), memory, tuning)
	check_eq(far["state"], "follow", "it follows")
	check(float(far["throttle"]) > 0.0, "and closes the gap")
	check(far["heading"].is_equal_approx(Vector2(1.0, 0.0)), "towards the leader")
	var close := CompanionBrain.decide(_companion({"order": {"name": "follow", "ticks_left": -1},
			"leader": {"dir": Vector2(1.0, 0.0), "dist": follow_m - 1.0}}), memory, tuning)
	check_near(float(close["throttle"]), 0.0, 0.0001, "within follow_m it stops")
	# Moving: a leader walking at 2 m/s, a follower that runs at 3 m/s; once caught up it stays within reach.
	var leader := Vector2.ZERO
	var me := Vector2(-12.0, 3.0)
	var worst := 0.0
	for tick in 1200:
		leader += Vector2(2.0, 0.0) / 60.0
		var out := CompanionBrain.decide(_companion({"order": {"name": "follow", "ticks_left": -1},
				"leader": _seen(me, leader)}), memory, tuning)
		me += (out["heading"] as Vector2) * 3.0 * float(out["throttle"]) / 60.0
		if tick > 600:
			worst = maxf(worst, me.distance_to(leader))
	check(worst <= follow_m + float(tuning["band"]["spacing_m"]) + 0.5, "stays within follow distance (%.2f m)" % worst)


## With a slot (its own place beside the leader) a follower walks to it and stands there, so two followers of one
## leader keep apart instead of meeting at the same point behind it.
func test_followers_keep_their_slots_beside_the_leader() -> void:
	var spacing := float(tuning["band"]["spacing_m"])
	var slots: Array = tuning["band"]["slots_m"]
	var leader := Vector2.ZERO
	var forward := Vector2(1.0, 0.0)
	var right := Vector2(-forward.y, forward.x)
	var bodies := [Vector2(-10.0, 4.0), Vector2(-9.0, -5.0)]
	var memories := [CompanionBrain.fresh_memory(Vector2(0.0, -1.0)), CompanionBrain.fresh_memory(Vector2(0.0, -1.0))]
	var worst_slot := 0.0
	var states := []
	for tick in 1500:
		if tick < 900:
			leader += forward * 2.0 / 60.0
		for k in 2:
			var off: Array = slots[k]
			var slot: Vector2 = leader + right * float(off[0]) + forward * float(off[1])
			var out := CompanionBrain.decide(_companion({"order": {"name": "follow", "ticks_left": -1},
					"leader": _seen(bodies[k], leader), "slot": _seen(bodies[k], slot)}), memories[k], tuning)
			bodies[k] += (out["heading"] as Vector2) * 3.0 * float(out["throttle"]) / 60.0
			if tick > 600 and tick < 900:
				worst_slot = maxf(worst_slot, (bodies[k] as Vector2).distance_to(slot))
			if tick == 1499:
				states.append(out["state"])
				check_near(float(out["throttle"]), 0.0, 0.0001, "follower %d stands still at its slot" % k)
				check((bodies[k] as Vector2).distance_to(slot) <= CompanionBrain.SLOT_M + 0.05, "follower %d is at its slot" % k)
	check(worst_slot <= spacing, "walking, each keeps near its slot (worst %.2f m)" % worst_slot)
	check_eq(states, ["follow", "follow"], "both follow")
	check((bodies[0] as Vector2).distance_to(bodies[1]) >= spacing, "and they stand apart (%.2f m)"
			% (bodies[0] as Vector2).distance_to(bodies[1]))


## "lost" is said for each separation, not once per order: after catching up, a second separation is reported too.
func test_a_follower_reports_each_time_it_loses_the_leader() -> void:
	var lost_m := float(tuning["band"]["lost_m"])
	var memory := CompanionBrain.fresh_memory(Vector2(0.0, -1.0))
	var reports := []
	for dist in [3.0, lost_m + 5.0, lost_m + 6.0, 20.0, 3.0, 2.5, lost_m + 4.0, lost_m + 8.0]:
		var out := CompanionBrain.decide(_companion({"order": {"name": "follow", "ticks_left": -1},
				"leader": {"dir": Vector2(1.0, 0.0), "dist": dist}}), memory, tuning)
		reports.append(String((out["report"] as Dictionary).get("kind", "")))
	check_eq(reports, ["", "lost", "", "", "", "", "lost", ""], "lost once per separation")


func test_wait_holds_until_another_order() -> void:
	var memory := CompanionBrain.fresh_memory(Vector2(0.0, -1.0))
	var wait := {"name": "wait", "target_dir": Vector2(0.0, 1.0), "target_dist": 0.2, "ticks_left": -1}
	for i in 300:
		var out := CompanionBrain.decide(_companion({"order": wait, "leader": {"dir": Vector2(1.0, 0.0), "dist": 25.0}}),
				memory, tuning)
		check_eq(out["state"], "wait", "it waits (decision %d)" % i)
		check_near(float(out["throttle"]), 0.0, 0.0001, "standing")
		if out["state"] != "wait":
			break
	# A threat makes it flee, then it comes back to its spot.
	var fled := CompanionBrain.decide(_companion({"order": wait, "fear": 0.9,
			"threat": {"dir": Vector2(0.0, 1.0), "dist": 4.0}}), memory, tuning)
	check_eq(fled["state"], "flee", "it runs from the hunter")
	var back := CompanionBrain.decide(_companion({"order": {"name": "wait", "target_dir": Vector2(0.0, 1.0),
			"target_dist": 6.0, "ticks_left": -1}}), memory, tuning)
	check_eq(back["state"], "wait", "then it goes back to wait")
	check(float(back["throttle"]) > 0.0 and back["heading"].is_equal_approx(Vector2(0.0, 1.0)), "to its spot")
	var next := CompanionBrain.decide(_companion({"order": {"name": "follow", "ticks_left": -1},
			"leader": {"dir": Vector2(1.0, 0.0), "dist": 25.0}}), memory, tuning)
	check_eq(next["state"], "follow", "another order ends the wait")


func test_investigate_goes_reports_and_returns() -> void:
	var memory := CompanionBrain.fresh_memory(Vector2(0.0, -1.0))
	var leader := {"dir": Vector2(-1.0, 0.0), "dist": 8.0}
	var reports := []
	var states := []
	for dist in [10.0, 8.0, 6.0, 4.0, 2.0, 1.0, 1.0, 1.0]:
		var order := {"name": "investigate", "target_dir": Vector2(0.0, -1.0), "target_dist": dist, "ticks_left": 600}
		var out := CompanionBrain.decide(_companion({"order": order, "leader": leader, "elapsed_t": 6}), memory, tuning)
		states.append(out["state"])
		if not (out["report"] as Dictionary).is_empty():
			reports.append(out["report"])
	check_eq(states.slice(0, 5), ["investigate", "investigate", "investigate", "investigate", "investigate"], "it goes")
	check_eq(reports, [{"kind": "arrived"}], "it reports arriving, once")
	check_eq(states.slice(5), ["return", "return", "return"], "then comes back to the leader")
	var near := CompanionBrain.decide(_companion({"order": {"name": "investigate", "target_dir": Vector2(0.0, -1.0),
			"target_dist": 1.0, "ticks_left": 500}, "leader": {"dir": Vector2(-1.0, 0.0), "dist": 2.0}}), memory, tuning)
	check_eq(near["state"], "follow", "back with the leader it follows")


func test_an_unreachable_investigation_times_out_and_reports_it() -> void:
	var stuck_t := int(tuning["orders"]["stuck_t"])
	var memory := CompanionBrain.fresh_memory(Vector2(0.0, -1.0))
	var leader := {"dir": Vector2(-1.0, 0.0), "dist": 8.0}
	var elapsed := 6
	var cannot := {}
	var decisions := 0
	while cannot.is_empty() and decisions < 1000:
		var order := {"name": "investigate", "target_dir": Vector2(0.0, -1.0), "target_dist": 9.0, "ticks_left": 1200}
		var out := CompanionBrain.decide(_companion({"order": order, "leader": leader, "elapsed_t": elapsed}), memory,
				tuning)
		decisions += 1
		if (out["report"] as Dictionary).get("kind", "") == "cannot":
			cannot = out["report"]
			check_eq(out["state"], "return", "and it comes back")
	check_eq(cannot.get("reason", ""), "can't reach that spot", "no progress: it reports it cannot reach the spot")
	check(decisions * elapsed >= stuck_t and decisions * elapsed <= stuck_t + 2 * elapsed,
			"after orders.stuck_t without progress (%d ticks)" % (decisions * elapsed))
	# Out of time while still making progress: the same report.
	var memory2 := CompanionBrain.fresh_memory(Vector2(0.0, -1.0))
	CompanionBrain.decide(_companion({"order": {"name": "investigate", "target_dir": Vector2(0.0, -1.0),
			"target_dist": 9.0, "ticks_left": 6}, "leader": leader}), memory2, tuning)
	var late := CompanionBrain.decide(_companion({"order": {"name": "investigate", "target_dir": Vector2(0.0, -1.0),
			"target_dist": 5.0, "ticks_left": 0}, "leader": leader}), memory2, tuning)
	check_eq(late["report"].get("kind", ""), "cannot", "the order's time ran out")


func test_retreat_runs_home_and_waits() -> void:
	var memory := CompanionBrain.fresh_memory(Vector2(0.0, -1.0))
	var run := CompanionBrain.decide(_companion({"order": {"name": "retreat", "target_dir": Vector2(-1.0, 0.0),
			"target_dist": 20.0, "ticks_left": -1}, "leader": {"dir": Vector2(1.0, 0.0), "dist": 3.0}}), memory, tuning)
	check_eq(run["state"], "retreat", "it runs for the nest")
	check(float(run["throttle"]) >= 1.0 and run["heading"].is_equal_approx(Vector2(-1.0, 0.0)), "at full speed")
	var reports := []
	for i in 5:
		var out := CompanionBrain.decide(_companion({"order": {"name": "retreat", "target_dir": Vector2(-1.0, 0.0),
				"target_dist": 0.5, "ticks_left": -1}}), memory, tuning)
		check_eq(out["state"], "wait", "and waits there")
		check_near(float(out["throttle"]), 0.0, 0.0001, "standing")
		if not (out["report"] as Dictionary).is_empty():
			reports.append(out["report"])
	check_eq(reports, [{"kind": "arrived"}], "it reports arriving, once")


func test_assist_attacks_the_foe_or_gathers_food_by_role() -> void:
	var fight := {"name": "assist", "mode": "fight", "ticks_left": 1200}
	var foe_near := {"dir": Vector2(0.0, 1.0), "dist": 0.8}
	var food := {"dir": Vector2(1.0, 0.0), "dist": 6.0, "reserved_ok": true}
	var memory := CompanionBrain.fresh_memory(Vector2(0.0, -1.0))
	var bite := CompanionBrain.decide(_companion({"role": "defender", "order": fight, "foe": foe_near, "food": food,
			"threat": foe_near, "fear": 0.9}), memory, tuning)
	check_eq(bite["state"], "assist", "a defender fights (it does not flee its foe)")
	check(bite["bite"], "and bites within reach")
	var chase := CompanionBrain.decide(_companion({"role": "defender", "order": fight,
			"foe": {"dir": Vector2(0.0, 1.0), "dist": 5.0}}), memory, tuning)
	check(not chase["bite"] and chase["heading"].is_equal_approx(Vector2(0.0, 1.0)), "out of reach it closes in")
	var forager := CompanionBrain.decide(_companion({"role": "forager", "order": fight, "foe": foe_near, "food": food}),
			CompanionBrain.fresh_memory(Vector2(0.0, -1.0)), tuning)
	check_eq(forager["state"], "forage", "a forager gathers instead")
	check(not forager["bite"] and forager["heading"].is_equal_approx(Vector2(1.0, 0.0)), "it heads for the bush")
	var carrying := CompanionBrain.decide(_companion({"role": "forager", "order": {"name": "assist", "mode": "gather",
			"ticks_left": 1200}, "carrying": 1, "food": food}), CompanionBrain.fresh_memory(Vector2(0.0, -1.0)), tuning)
	check(carrying["state"] == "forage" and carrying["heading"].is_equal_approx(Vector2(-1.0, 0.0)), "fruit to the nest")
	var taken := CompanionBrain.decide(_companion({"role": "scout", "order": {"name": "assist", "mode": "gather",
			"ticks_left": 1200}, "food": {"dir": Vector2(1.0, 0.0), "dist": 6.0, "reserved_ok": false},
			"leader": {"dir": Vector2(0.0, 1.0), "dist": 9.0}}), CompanionBrain.fresh_memory(Vector2(0.0, -1.0)), tuning)
	check_eq(taken["state"], "follow", "a bush another carrier reserved is left alone")
	var scared := CompanionBrain.decide(_companion({"role": "forager", "order": fight, "fear": 0.35,
			"threat": {"dir": Vector2(0.0, 1.0), "dist": 4.0}, "foe": foe_near}),
			CompanionBrain.fresh_memory(Vector2(0.0, -1.0)), tuning)
	check_eq(scared["state"], "flee", "a forager flees earlier than a fighter")
	# An assist that runs out of time ends: it says so once and comes back to the leader.
	var timed := CompanionBrain.fresh_memory(Vector2(0.0, -1.0))
	var leader := {"dir": Vector2(0.0, 1.0), "dist": 9.0}
	var over := {"name": "assist", "mode": "gather", "ticks_left": 0}
	var first := CompanionBrain.decide(_companion({"order": over, "food": food, "leader": leader}), timed, tuning)
	check_eq(first["report"], {"kind": "done"}, "the order's end is reported")
	check_eq(first["state"], "return", "and it comes back")
	var again := CompanionBrain.decide(_companion({"order": over, "food": food, "leader": leader}), timed, tuning)
	check(again["report"].is_empty(), "once")


func test_without_a_leader_a_companion_goes_home_and_waits() -> void:
	for order_name in ["follow", "assist", ""]:
		var memory := CompanionBrain.fresh_memory(Vector2(0.0, -1.0))
		var order := {} if order_name == "" else {"name": order_name, "mode": "fight", "ticks_left": -1}
		var going := CompanionBrain.decide(_companion({"order": order}), memory, tuning)
		check_eq(going["state"], "return", "%s without a leader: it goes home" % order_name)
		check(going["heading"].is_equal_approx(Vector2(1.0, 0.0)), "towards its home")
		var home := {"dir": Vector2(1.0, 0.0), "dist": 1.0, "radius": 5.0}
		var there := CompanionBrain.decide(_companion({"order": order, "home": home}), memory, tuning)
		var settled := ["wait", "idle"]
		check(settled.has(there["state"]), "%s: at home it waits (%s)" % [order_name, there["state"]])
		check(float(there["throttle"]) <= CompanionBrain.IDLE_WANDER + 0.0001, "and stays")
	# An investigation that ends while the leader has fainted comes home too.
	var memory := CompanionBrain.fresh_memory(Vector2(0.0, -1.0))
	var out := CompanionBrain.decide(_companion({"order": {"name": "investigate", "target_dir": Vector2(0.0, -1.0),
			"target_dist": 0.5, "ticks_left": 100}}), memory, tuning)
	check_eq(out["report"].get("kind", ""), "arrived", "it still reports")
	check_eq(out["state"], "return", "and goes home without a leader")


## A hunter, its prey and the nest on a line: the prey stands still, seen by the hunter, at `prey`.
func _hunter_percepts(hunter: Vector2, prey: Vector2, extra := {}) -> Dictionary:
	var nest_r := float(tuning["nest"]["radius_m"])
	var target := _seen(hunter, prey)
	target["group_near"] = 0
	target["in_nest"] = prey.length() < nest_r
	var p := {"target": target, "waypoint": _seen(hunter, Vector2(26.0, -24.0)), "nerve": 3, "heading": Vector2(0.0, -1.0),
			"lair": {"dir": Vector2(1.0, 0.0), "dist": 0.5, "radius": 4.0},
			"nest": {"dir": _seen(hunter, Vector2.ZERO)["dir"], "dist": hunter.length(), "radius": nest_r}}
	p.merge(extra, true)
	return p


func test_the_hunter_investigates_before_it_pursues_and_always_disengages() -> void:
	var h: Dictionary = tuning["hunter"]
	var memory := HunterBrain.fresh_memory(Vector2(0.0, -1.0))
	var hunter := Vector2(30.0, 0.0)
	var prey := Vector2(20.0, 0.0)
	var states := []
	var reports := []
	var cycle := int(h["investigate_t"]) + int(h["pursue_t"]) + int(h["disengage_t"]) + int(h["rest_t"])
	for tick in cycle + 10:
		var out := HunterBrain.decide(_hunter_percepts(hunter, prey), memory, tuning)
		states.append(out["state"])
		if not (out["report"] as Dictionary).is_empty():
			reports.append(out["report"]["kind"] + ("/" + String(out["report"]["why"]) if out["report"].has("why") else ""))
		if out["state"] == "investigate":
			check_near(float(out["throttle"]), 0.0, 0.0001, "the tell: it stops")
			check_near((out["heading"] as Vector2).dot(Vector2(-1.0, 0.0)), 0.0, 0.0001, "side-on")
		if reports.has("rested"):
			break
	check(states.size() <= cycle + 2, "one bounded cycle (%d ticks)" % states.size())
	var first_pursuit := states.find("pursue")
	check_eq(states.slice(0, int(h["investigate_t"])).filter(func(s): return s != "investigate").size(), 0,
			"it watches for investigate_t first")
	check_eq(first_pursuit, int(h["investigate_t"]), "then pursues")
	check(states.has("disengage"), "it disengages")
	check(states.find("disengage") <= first_pursuit + int(h["pursue_t"]) + 1, "after at most pursue_t")
	check_eq(reports, ["investigating", "pursuing", "disengaged/time", "rested"], "the whole cycle, reported")
	check_eq(states[states.size() - 1], "patrol", "and patrols again")
	# Every other end of a pursuit: nerve, the nest, a group standing together, losing sight.
	var ends := {"nerve": {"nerve": 0}, "nest": {"target": {"dir": Vector2(-1.0, 0.0), "dist": 9.0, "group_near": 0,
			"in_nest": true}}, "group": {"target": {"dir": Vector2(-1.0, 0.0), "dist": 3.0, "group_near": 3,
			"in_nest": false}}, "lost": {"target": {}}}
	for why in ends:
		var m := {"state": "pursue", "timer": 200, "cooldown": 0, "heading": Vector2(-1.0, 0.0)}
		var out := HunterBrain.decide(_hunter_percepts(hunter, prey, ends[why]), m, tuning)
		check_eq(out["state"], "disengage", "%s ends the pursuit" % why)
		check_eq(out["report"].get("why", ""), why, "and says why")
	# Strikes within reach, then waits for its cooldown.
	var m2 := {"state": "pursue", "timer": 200, "cooldown": 0, "heading": Vector2(-1.0, 0.0)}
	var strikes := 0
	for tick in int(h["strike_cooldown_t"]) + 1:
		var close := HunterBrain.decide(_hunter_percepts(Vector2(21.0, 0.0), prey), m2, tuning)
		strikes += 1 if close["strike"] else 0
	check_eq(strikes, 2, "one strike per cooldown")
	# A group standing together deters it at the end of its tell.
	var m3 := {"state": "investigate", "timer": 1, "cooldown": 0, "heading": Vector2(-1.0, 0.0)}
	var deterred := HunterBrain.decide(_hunter_percepts(hunter, prey, {"target": {"dir": Vector2(-1.0, 0.0), "dist": 10.0,
			"group_near": int(h["deterred_by_group"]), "in_nest": false}}), m3, tuning)
	check_eq(deterred["state"], "disengage", "deterred without a fight")


func test_the_hunter_never_enters_the_nest() -> void:
	var nest_r := float(tuning["nest"]["radius_m"])
	var speed := 5.0
	for start in [Vector2(20.0, 0.0), Vector2(0.0, -15.0), Vector2(-9.0, 9.0)]:
		var memory := HunterBrain.fresh_memory(Vector2(0.0, -1.0))
		var hunter: Vector2 = start
		var closest := INF
		for tick in 3600:
			# The prey circles just outside the nest, ducks inside it now and then, and stands across it.
			var angle := float(tick) / 120.0
			var prey := Vector2(cos(angle), sin(angle)) * (nest_r + 1.0)
			if (tick / 400) % 3 == 1:
				prey = Vector2(cos(angle), sin(angle)) * 2.0
			elif (tick / 400) % 3 == 2:
				prey = -hunter.normalized() * (nest_r + 2.0)
			var p := _hunter_percepts(hunter, prey, {"lair": _seen(hunter, Vector2(26.0, -24.0)), "nerve": 3})
			p["lair"]["radius"] = 4.0
			var out := HunterBrain.decide(p, memory, tuning)
			hunter += (out["heading"] as Vector2) * speed * float(out["throttle"]) / 60.0
			closest = minf(closest, hunter.length())
		check(closest >= nest_r, "from %s it never stepped inside the nest (closest %.2f m)" % [start, closest])
	# The heading filter on its own: never towards the centre at the edge.
	var nest := {"dir": Vector2(-1.0, 0.0), "dist": nest_r + 1.0, "radius": nest_r}
	var h := HunterBrain.keep_out_of_nest(Vector2(-1.0, 0.0), nest, float(tuning["hunter"]["nest_margin_m"]))
	check(h.dot(Vector2(-1.0, 0.0)) <= 0.0, "at the edge it turns away (%s)" % h)
	var slide := HunterBrain.keep_out_of_nest(Vector2(-1.0, 1.0).normalized(),
			{"dir": Vector2(-1.0, 0.0), "dist": nest_r + 2.5, "radius": nest_r}, float(tuning["hunter"]["nest_margin_m"]))
	check(slide.dot(Vector2(-1.0, 0.0)) <= 0.0001 and slide.y > 0.0, "near it, it slides round the edge (%s)" % slide)
