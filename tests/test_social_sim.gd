extends TestCase
## The Social stage slice's world (PROPOSED, docs/stages/social-plan.md sections 4 to 10): deterministic for a seed
## and the intents, stable individuals with names, roles and needs, befriending into the band and dismissing out of
## it, a wary loner that backs away from a loud signal and listens to Calm; orders that are acknowledged, reported
## and released; the group task with reservations; the hunter's bounded pursuit; leader loss; the far tier; the
## test-only record; and bumps that never start a war.

const SocialData := preload("res://game/systems/social/social_data.gd")
const PLAYER_PRESET := "raptor"
const SEED := 4260

static var _tuning := {}
static var _data := {}


func before_each() -> void:
	if _tuning.is_empty():
		_tuning = SocialData.tuning()
		_data = SocialData.creature_data()


func _sim(world_seed: int = SEED, preset: String = PLAYER_PRESET) -> SocialSim:
	return SocialSim.new(_data["presets"][preset], world_seed, _tuning, _data)


func _run(sim: SocialSim, ticks: int, intent: Dictionary = {}) -> Array:
	var events := []
	for i in ticks:
		events.append_array(sim.tick(intent))
	return events


static func _of_kind(events: Array, kind: String) -> Array:
	var out := []
	for e in events:
		if e["kind"] == kind:
			out.append(e)
	return out


static func _ground(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## Puts the player `dist` m in front of individual `id`, facing it.
static func _stand_before(sim: SocialSim, id: String, dist: float) -> void:
	var c: Dictionary = sim.individual(id)
	var at := _ground(c["position"]) + Vector2(-sin(c["yaw"]), -cos(c["yaw"])) * dist
	var to := _ground(c["position"]) - at
	sim.place(SocialSim.PLAYER_ID, at, atan2(-to.x, -to.y))


## A scripted intent stream: walking in a slow circle, every signal in turn, an order and a dismissal.
static func _scripted(t: int) -> Dictionary:
	var angle := float(t) * 0.01
	var intent := {"move": Vector2(cos(angle), sin(angle)) * (0.0 if t % 200 > 150 else 1.0)}
	if t % 90 == 45:
		intent["signal"] = SocialRules.SIGNALS[(t / 90) % SocialRules.SIGNALS.size()]
	if t == 300:
		intent["order"] = "follow"
	if t == 350:
		intent["order"] = "assist"
	if t == 400:
		intent["dismiss"] = "b1"
	if t > 500 and t < 520:
		intent["bite"] = true
	return intent


func test_the_same_seed_and_intents_give_the_same_world() -> void:
	var a := _sim()
	var b := _sim()
	var stream_a := []
	var stream_b := []
	for t in 600:
		stream_a.append_array(a.tick(_scripted(t)))
		stream_b.append_array(b.tick(_scripted(t)))
		if t % 100 == 99:
			check_eq(var_to_str(a.snapshot()), var_to_str(b.snapshot()), "the snapshots match at tick %d" % (t + 1))
	check_eq(var_to_str(stream_a), var_to_str(stream_b), "the event streams match")
	check_eq(int(a.snapshot()["tick"]), 600, "600 ticks ran")
	var start := _sim().snapshot()
	check(var_to_str(start["player"]["position"]) != var_to_str(a.snapshot()["player"]["position"]),
			"the player moved (the comparison is not vacuous)")
	var moved := 0
	for i in start["individuals"].size():
		if var_to_str(start["individuals"][i]["position"]) != var_to_str(a.snapshot()["individuals"][i]["position"]):
			moved += 1
	check(moved > 0, "individuals moved too (%d)" % moved)
	var pair: Array = a.snapshot()["player"]["position"]
	check(pair.size() == 2, "ground vectors are [x, z] pairs")


func test_different_seeds_name_and_place_individuals_differently() -> void:
	var a := _sim(1)
	var b := _sim(2)
	var names_a := []
	var names_b := []
	var same_spots := 0
	for i in a.individuals().size():
		var ia: Dictionary = a.individuals()[i]
		var ib: Dictionary = b.individuals()[i]
		names_a.append(ia["name"])
		names_b.append(ib["name"])
		if (ia["position"] as Vector3).is_equal_approx(ib["position"]):
			same_spots += 1
		check_eq(ia["id"], ib["id"], "the same ids")
		check_eq(ia["preset"], ib["preset"], "the same cast")
	check(names_a != names_b, "the names differ: %s / %s" % [names_a, names_b])
	check_eq(same_spots, 0, "no individual stands at the same spot")
	var spots_a := []
	var spots_b := []
	for bush in a.snapshot()["bushes"]:
		spots_a.append(bush["position"])
	for bush in b.snapshot()["bushes"]:
		spots_b.append(bush["position"])
	check(spots_a != spots_b, "the grove is laid out differently")


func test_individuals_have_stable_ids_names_roles_and_needs() -> void:
	var sim := _sim()
	var first := sim.individuals()
	var ids := []
	var names := {}
	for c in first:
		ids.append(c["id"])
		check(String(c["name"]).length() >= 2, "%s has a name (%s)" % [c["id"], c["name"]])
		names[c["name"]] = true
	check_eq(ids, ["b1", "b2", "b3", "l1"], "the cast in id order")
	check_eq(names.size(), 4, "every name is different")
	var roles := {}
	for c in first:
		roles[c["id"]] = c["role"]
	check_eq(roles, {"b1": "scout", "b2": "defender", "b3": "forager", "l1": "forager"},
			"roles come from anatomy (strider scout, boar defender, monkey and hopper foragers)")
	check_eq(first[1]["mood"], "hungry", "the boar starts hungry")
	check_eq(first[1]["fits"], "share", "and wants a gift")
	check_eq(first[2]["fits"], "calm", "the wary monkey wants Calm")
	check_eq(first[0]["fits"], "display", "the crested strider answers a display")
	_run(sim, 600)
	for i in first.size():
		var now: Dictionary = sim.individuals()[i]
		check_eq(now["id"], first[i]["id"], "the id stays")
		check_eq(now["name"], first[i]["name"], "the name stays")
		check_eq(now["role"], first[i]["role"], "the role stays")
		check(float(now["hunger"]) > float(first[i]["hunger"]) or float(now["hunger"]) >= 1.0
				or now["state"] == "forage", "%s gets hungrier over 10 s (%.3f -> %.3f)" % [now["id"], first[i]["hunger"], now["hunger"]])
	var boar_rise := float(sim.individuals()[1]["hunger"]) - float(first[1]["hunger"])
	var strider_rise := float(sim.individuals()[0]["hunger"]) - float(first[0]["hunger"])
	check_near(boar_rise / strider_rise, 1.25, 0.01, "the defender gets hungry 1.25 times faster")


func test_befriending_a_band_member_recruits_it_and_dismissing_releases_it() -> void:
	var sim := _sim()
	var cooldown := int(_tuning["signals"]["cooldown_t"])
	var events := []
	for attempt in 4:
		_stand_before(sim, "b1", 3.0)
		events.append_array(sim.tick({"signal": "display"}))
		if sim.band().has("b1"):
			break
		events.append_array(_run(sim, cooldown))
	var responses := _of_kind(events, "response")
	check(responses.size() >= 1, "the strider answered")
	for r in responses:
		check_eq(r["who"], "b1", "the strider the player faces answers")
		check_eq(r["response"], "fits", "a display fits the display-rich strider")
		check_eq(r["words"], "welcomes you", "in words")
	var joined := _of_kind(events, "joined")
	check_eq(joined.size(), 1, "it joined once")
	check_eq(Array(sim.band()), ["b1"], "the band holds it")
	var view := sim.individual("b1")
	check_eq(view["order"], "follow", "a new member follows")
	check(float(view["trust"]) >= float(_tuning["trust"]["join_at"]), "its trust reached the join mark")
	var trust_before := float(view["trust"])
	_run(sim, 120)
	check_eq(sim.individual("b1")["state"], "follow", "it follows the player")
	var out := sim.tick({"dismiss": "b1"})
	check_eq(_of_kind(out, "dismissed").size(), 1, "dismissed")
	var ack := _of_kind(out, "ack")
	check(ack.size() == 1 and ack[0]["words"] == "goes back to the den", "it says where it goes")
	check_eq(sim.band().size(), 0, "the band is empty")
	var after := sim.individual("b1")
	check_eq(after["order"], "", "no order is left")
	check(float(after["trust"]) > 0.0 and float(after["trust"]) < trust_before,
			"it keeps its memories, a mild 'parted' on top (%.2f -> %.2f)" % [trust_before, after["trust"]])
	_run(sim, 240)
	check(sim.individual("b1")["state"] != "follow", "it no longer follows")
	var again := sim.tick({"dismiss": "b1"})
	var refused := _of_kind(again, "order_refused")
	check(refused.size() == 1 and refused[0]["reason"] == "is not in your band", "a non-member cannot be dismissed")


func test_the_wary_loner_backs_away_from_a_loud_signal_and_listens_to_calm() -> void:
	var sim := _sim()
	var cooldown := int(_tuning["signals"]["cooldown_t"])
	# A refused signal costs nothing.
	_stand_before(sim, "l1", 6.0)
	var far := sim.tick({"signal": "calm"})
	var refused := _of_kind(far, "refused")
	check(refused.size() == 1 and refused[0]["reason"] == "Too far: come within 3 m", "Calm needs 3 m")
	check_eq(int(sim.player()["cooldown_t"]), 0, "a refusal spends no cooldown")
	check_eq(sim.individual("l1")["fits"], "calm", "the wary loner wants Calm")
	# A loud signal startles it.
	_stand_before(sim, "l1", 2.5)
	check_eq(sim.preview_signal("sing")["target"], "l1", "the loner is the target")
	var before := _ground(sim.individual("l1")["position"]).distance_to(_ground(sim.player()["position"]))
	var sung := sim.tick({"signal": "sing"})
	var r := _of_kind(sung, "response")
	check(r.size() == 1 and r[0]["response"] == "startles" and r[0]["words"] == "backs away", "Sing startles it")
	_run(sim, 60)
	var after := _ground(sim.individual("l1")["position"]).distance_to(_ground(sim.player()["position"]))
	check(after > before + 0.3, "it backs away (%.2f m -> %.2f m)" % [before, after])
	var view := sim.individual("l1")
	check(float(view["trust"]) < float(_tuning["trust"]["base"]["wary"]), "a startle is a bad memory")
	# Calm fits.
	_run(sim, cooldown)
	_stand_before(sim, "l1", 2.0)
	var calmed := sim.tick({"signal": "calm"})
	var c := _of_kind(calmed, "response")
	check(c.size() == 1 and c[0]["response"] == "fits" and c[0]["words"] == "welcomes you", "Calm fits the wary loner")
	check(float(sim.individual("l1")["trust"]) > float(view["trust"]) + 2.0, "and its trust rises")
	check_eq(sim.band().size(), 0, "a loner never joins the band")


## A world whose band already holds `ids` (through the test-only record, as a reload would).
func _with_band(ids: Array, world_seed: int = SEED) -> SocialSim:
	var rec := _sim(world_seed).to_record()
	for person in rec["individuals"]:
		if ids.has(person["id"]):
			person["member"] = true
			person["befriended"] = true
	return SocialSim.from_record(rec, _data["presets"][PLAYER_PRESET], _tuning, _data)


## No bush is reserved by two individuals, and every reservation is mirrored on its bush.
static func _reservations_ok(sim: SocialSim) -> String:
	var held := {}
	for c in sim.cast:
		var id := String(c["reserved"])
		if id == "":
			continue
		if held.has(id):
			return "%s and %s both hold %s" % [held[id], c["id"], id]
		held[id] = c["id"]
	for b in sim.bushes:
		var by := String(b["reserved_by"])
		if by != "" and held.get(b["id"], "") != by:
			return "%s says %s holds it" % [b["id"], by]
		if held.has(b["id"]) and by != held[b["id"]]:
			return "%s holds %s, the bush says '%s'" % [held[b["id"]], b["id"], by]
	return ""


func test_a_group_task_feeds_the_nest_and_no_bush_is_picked_twice() -> void:
	var sim := _with_band(["b1", "b2", "b3"])
	var regrow := int(_tuning["grove"]["regrow_t"])
	for id in sim.band():
		sim._individual_of(id)["hunger"] = 1.0
	var acks := _of_kind(sim.tick({"order": "assist"}), "ack")
	check_eq(acks.size(), 3, "each member acknowledges Assist")
	for a in acks:
		check_eq(a["words"], "gathers food", "without a fight everyone gathers")
	var last_pick := {}
	var delivered := 0
	var deliverers := {}
	var picked := 0
	var done_at := -1
	var bad := ""
	var events := []
	for t in 9000:
		var out := sim.tick({})
		events.append_array(out)
		for e in out:
			if e["kind"] == "picked":
				picked += 1
				if last_pick.has(e["bush"]) and sim.tick_count - int(last_pick[e["bush"]]) < regrow:
					bad = "%s was picked twice before it regrew" % e["bush"]
				last_pick[e["bush"]] = sim.tick_count
			elif e["kind"] == "delivered":
				delivered += int(e["count"])
				deliverers[e["who"]] = true
			elif e["kind"] == "task_done":
				done_at = sim.tick_count
		if bad == "":
			bad = _reservations_ok(sim)
		if done_at >= 0:
			break
	check_eq(bad, "", "reservations hold and no bush is picked twice")
	check(done_at > 0, "the task is done (%d fruit delivered in %d ticks)" % [delivered, sim.tick_count])
	check(delivered >= int(_tuning["task"]["fruit_goal"]), "six fruit reached the nest (%d)" % delivered)
	check(picked >= delivered, "every delivered fruit was picked first")
	check(deliverers.size() >= 2, "it was a group effort (%s)" % [deliverers.keys()])
	for id in deliverers:
		var kinds := []
		for e in sim.to_record()["individuals"]:
			if e["id"] == id:
				for m in e["memory"]:
					kinds.append(m["kind"])
		check(kinds.has("helped"), "%s remembers helping" % id)
	check_eq(sim.task_state()["rounds_done"], 1, "one round done")
	check_eq(sim.task_state()["delivered"], 0, "the next round starts empty")
	check_eq(_of_kind(events, "done").size(), 3, "every gatherer's Assist ends")
	for id in sim.band():
		check_eq(sim.individual(id)["order"], "follow", "%s follows again" % id)
		check_eq(int(sim.individual(id)["carrying"]), 0, "%s carries nothing into the next round" % id)
		check(float(sim.individual(id)["hunger"]) < float(_tuning["fit"]["hungry_at"]),
				"%s was fed by the fruit it helped bring (hunger %.2f)" % [id, sim.individual(id)["hunger"]])
		check(sim.individual(id)["mood"] != "hungry", "%s no longer reads hungry" % id)
	check(_of_kind(events, "ate").size() >= int(_tuning["task"]["fruit_goal"]), "the band ate the fruit")
	check(_of_kind(events, "learned").size() >= 1, "a carrier learned the grove route")
	_run(sim, regrow + 2)
	for id in last_pick:
		check(sim._bush(id)["ripe"], "%s regrew" % id)


func test_an_unreachable_investigate_is_acknowledged_then_reported_and_released() -> void:
	var sim := _with_band(["b1"])
	# Facing the east wall: the spot 12 m ahead lies outside the field.
	sim.place(SocialSim.PLAYER_ID, Vector2(36.0, 0.0), -PI / 2.0)
	sim.place("b1", Vector2(34.0, 2.0), -PI / 2.0)
	sim.tick({"order": "assist"})
	_run(sim, 12)
	var held := String(sim.individual("b1")["reserved"])
	check(held != "", "a gatherer reserves a bush first")
	var given := sim.tick({"order": "investigate"})
	var acks := _of_kind(given, "ack")
	check(acks.size() == 1 and acks[0]["words"] == "goes to look", "Investigate is acknowledged")
	check_eq(sim.individual("b1")["reserved"], "", "the new order released the old one's bush")
	check_eq(sim._bush(held)["reserved_by"], "", "and the bush is free")
	var events := []
	var limit := int(_tuning["orders"]["timeout_t"]) + 60
	for t in limit:
		events.append_array(sim.tick({}))
		if not _of_kind(events, "cannot").is_empty():
			break
	var cannot := _of_kind(events, "cannot")
	check_eq(cannot.size(), 1, "it reports that it cannot get there")
	if cannot.size() == 1:
		check_eq(cannot[0]["reason"], "can't reach that spot", "in words")
		check_eq(cannot[0]["order"], "investigate", "for the investigation")
	check_eq(_of_kind(events, "arrived").size(), 0, "it never claims to arrive")
	check_eq(sim.individual("b1")["order"], "follow", "then it comes back to follow")
	_run(sim, 240)
	var back := _ground(sim.individual("b1")["position"]).distance_to(_ground(sim.player()["position"]))
	check(back <= float(_tuning["band"]["follow_m"]) + 2.0, "and it is back beside the player (%.1f m)" % back)


func test_losing_the_leader_keeps_the_band_and_its_relationships() -> void:
	var sim := _with_band(["b1", "b2"])
	_run(sim, 150, {"move": Vector2(1.0, 0.0)})
	check(not sim.player()["at_nest"], "the player walked out of the nest")
	var before := sim.to_record()
	sim.me["health"] = 0.0
	var out := sim.tick({})
	var fainted := _of_kind(out, "fainted")
	check(fainted.size() == 1 and fainted[0]["band"] == ["b1", "b2"], "the player faints with its band")
	check_eq(Array(sim.band()), ["b1", "b2"], "the band keeps every member")
	for id in sim.band():
		check_eq(sim.individual(id)["order"], "retreat", "%s retreats to the nest" % id)
	var refused := _of_kind(sim.tick({"signal": "sing"}), "refused")
	check(refused.size() == 1 and refused[0]["reason"] == "You are out cold", "no signal while out cold")
	var events := []
	for t in int(_tuning["player"]["faint_t"]) + 2:
		events.append_array(sim.tick({}))
	check_eq(_of_kind(events, "recovered").size(), 1, "the player recovers")
	check(sim.player()["at_nest"], "at the nest")
	check(float(sim.player()["health"]) >= float(sim.player()["max_health"]) - 0.01, "at full health")
	var acks := _of_kind(events, "ack")
	check_eq(acks.size(), 2, "both members follow again")
	check_eq(Array(sim.band()), ["b1", "b2"], "the band is whole")
	var after := sim.to_record()
	for i in before["individuals"].size():
		check_eq(var_to_str(after["individuals"][i]["memory"]), var_to_str(before["individuals"][i]["memory"]),
				"%s remembers the same" % before["individuals"][i]["id"])
		check_eq(after["individuals"][i]["name"], before["individuals"][i]["name"], "and keeps its name")
	check_eq(var_to_str(after["reputation"]), var_to_str(before["reputation"]), "reputation is untouched")
	for id in sim.band():
		var d := _ground(sim.individual(id)["position"]).distance_to(Vector2.ZERO)
		check(d <= float(_tuning["nest"]["radius_m"]) + 3.0, "%s went to the nest (%.1f m from it)" % [id, d])


func test_far_individuals_change_tier_without_duplication_or_identity_loss() -> void:
	var sim := _with_band(["b1"])
	sim.place("b1", Vector2(-22.0, -16.0), 0.0)
	sim.place(SocialSim.PLAYER_ID, Vector2(30.0, 30.0), 0.0)
	var start := sim.individuals()
	var first := sim.tick({"order": "retreat"})
	var tiers := _of_kind(first, "tier")
	var far_ids := []
	for e in tiers:
		check_eq(e["tier"], "far", "%s goes far" % e["who"])
		far_ids.append(e["who"])
	far_ids.sort()
	check_eq(far_ids, ["b1", "b2", "b3", "h1", "l1"], "every actor 30 m away goes to the far tier, once")
	check_eq(_of_kind(first, "ack").size(), 1, "a far member still takes orders")
	var from_nest := _ground(sim.individual("b1")["position"]).length()
	var events := []
	events.append_array(_run(sim, 240))
	check_eq(_of_kind(events, "tier").size(), 0, "no tier flicker while it stays far")
	var now := sim.individual("b1")
	check_eq(now["tier"], "far", "b1 is far")
	check(_ground(now["position"]).length() < from_nest - 3.0,
			"a far actor still moves (%.1f -> %.1f m from the nest)" % [from_nest, _ground(now["position"]).length()])
	check((sim.planner_of("b1").position as Vector3).is_equal_approx(now["position"]), "its planner body follows")
	sim.place(SocialSim.PLAYER_ID, Vector2(0.0, 2.0), 0.0)
	var back := _of_kind(sim.tick({}), "tier")
	var near_b1 := false
	for e in back:
		check_eq(e["tier"], "near", "%s comes near" % e["who"])
		near_b1 = near_b1 or e["who"] == "b1"
	check(near_b1, "b1 is near again")
	var ids := {}
	for i in sim.individuals().size():
		var c: Dictionary = sim.individuals()[i]
		check(not ids.has(c["id"]), "%s appears once" % c["id"])
		ids[c["id"]] = true
		check_eq(c["name"], start[i]["name"], "%s keeps its name" % c["id"])
		check_eq(c["role"], start[i]["role"], "and its role")
	check_eq(ids.size(), 4, "nothing was duplicated or dropped")
	check_eq(Array(sim.band()), ["b1"], "b1 is still in the band")
	check_eq(sim.individual("b1")["order"], "retreat", "with its order")


func test_a_record_round_trip_keeps_identities_and_significant_relationships() -> void:
	var sim := _sim()
	var cooldown := int(_tuning["signals"]["cooldown_t"])
	for attempt in 4:
		_stand_before(sim, "b1", 3.0)
		sim.tick({"signal": "display"})
		if sim.band().has("b1"):
			break
		_run(sim, cooldown)
	check_eq(Array(sim.band()), ["b1"], "the strider joined")
	var reach := float(sim.me["stats"]["bite_reach_m"])
	var gap := float(sim.me["stats"]["body_radius_m"]) + float(sim._individual_of("l1")["stats"]["body_radius_m"]) + 0.02
	var bites := 0
	for i in 3:
		_stand_before(sim, "l1", minf(gap, reach * 0.9 + float(sim._individual_of("l1")["stats"]["body_radius_m"])))
		bites += _of_kind(sim.tick({"bite": true}), "bit").size()
		_run(sim, int(_tuning["bite"]["cooldown_t"]) + 1)
	check_eq(bites, 3, "three bites landed on the loner")
	check(int(sim.individual("l1")["hostile_left_t"]) > 0, "it is hostile")
	var rec := sim.to_record()
	check_eq(rec["record"], "social_slice_record_v0", "the test-only record kind (not the save)")
	var plain = JSON.parse_string(JSON.stringify(rec))
	check(plain is Dictionary, "the record is plain data")
	var back := SocialSim.from_record(plain, _data["presets"][PLAYER_PRESET], _tuning, _data)
	check(back != null, "it loads")
	check_eq(back.tick_count, sim.tick_count, "at the same tick")
	check_eq(Array(back.band()), ["b1"], "the band is the same")
	for i in sim.individuals().size():
		var a: Dictionary = sim.individuals()[i]
		var b: Dictionary = back.individuals()[i]
		for key in ["id", "name", "preset", "role", "member", "befriended", "hostile_left_t", "mood"]:
			check_eq(b[key], a[key], "%s keeps its %s" % [a["id"], key])
		check_near(float(b["trust"]), float(a["trust"]), 0.0001, "%s keeps its trust" % a["id"])
	check_near(float(back.reputation["loner"]), float(sim.reputation["loner"]), 0.0001, "the loner group's reputation")
	check_near(float(back.reputation["band"]), float(sim.reputation["band"]), 0.0001, "the band's reputation")
	_stand_before(back, "l1", 2.0)
	var refused := _of_kind(back.tick({"signal": "calm"}), "refused")
	check(refused.size() == 1 and String(refused[0]["reason"]).begins_with("It won't listen: you hurt it ("),
			"the hurt loner still won't listen after the reload")
	check(SocialSim.from_record({"record": "pangaea_save"}, _data["presets"][PLAYER_PRESET], _tuning, _data) == null,
			"another kind of record is not read")


func test_the_hunter_pursuit_ends_and_the_band_recovers() -> void:
	var sim := _with_band(["b2"])
	sim.place(SocialSim.PLAYER_ID, Vector2(17.0, -17.0), 0.0)
	sim.place("b2", Vector2(15.0, -14.0), 0.0)
	var states := []
	var events := []
	var nest_r := float(_tuning["nest"]["radius_m"])
	var inside := 0
	var rested := false
	# One whole cycle: until the hunter has rested and patrols again.
	for t in 3600:
		var out := sim.tick({})
		events.append_array(out)
		for e in out:
			if e["kind"] == "hunter_state":
				states.append(e["state"])
				rested = rested or (e["state"] == "patrol" and states.has("rest"))
		if _ground(sim.hunter()["position"]).length() < nest_r:
			inside += 1
		if rested:
			break
	check(rested, "the hunter went through a whole cycle: %s" % [states])
	check_eq(inside, 0, "the hunter never stands in the nest")
	var investigate := states.find("investigate")
	var pursue := states.find("pursue")
	check(investigate >= 0 and pursue > investigate, "a tell before the pursuit: %s" % [states])
	var disengage := states.find("disengage", maxi(pursue, 0))
	check(disengage > pursue, "the pursuit ends: %s" % [states])
	check(states.find("rest", maxi(disengage, 0)) > disengage, "then it rests: %s" % [states])
	check(_of_kind(events, "hit").size() >= 1, "it struck")
	check_eq(Array(sim.band()), ["b2"], "the band is whole")
	var b2 := sim.individual("b2")
	check(float(b2["fear"]) < float(_tuning["fit"]["frightened_at"]), "its fear faded (%.2f)" % b2["fear"])
	check_eq(b2["order"], "follow", "it follows again")
	var gap := _ground(b2["position"]).distance_to(_ground(sim.player()["position"]))
	check(gap <= float(_tuning["band"]["follow_m"]) + 2.0, "beside the player (%.1f m)" % gap)


func test_the_scout_warns_and_a_band_together_deters_the_hunter() -> void:
	var sim := _with_band(["b1", "b2", "b3"])
	sim.place(SocialSim.PLAYER_ID, Vector2(17.0, -17.0), 0.0)
	sim.place("b1", Vector2(15.5, -15.0), 0.0)
	sim.place("b2", Vector2(18.5, -15.0), 0.0)
	sim.place("b3", Vector2(17.0, -14.5), 0.0)
	var events := _run(sim, 900)
	var warned := _of_kind(events, "warned")
	check(warned.size() >= 1 and warned[0]["who"] == "b1", "the scout warns the band")
	var states := []
	for e in _of_kind(events, "hunter_state"):
		states.append(e["state"])
	check(states.has("investigate"), "the hunter watches: %s" % [states])
	check(not states.has("strike"), "it never strikes a band that stands together: %s" % [states])
	var drove := _of_kind(events, "drove_off")
	check(drove.size() >= 1 and drove[0]["why"] == "group", "the band drove it off together")
	for e in sim.to_record()["individuals"]:
		if sim.band().has(e["id"]):
			var kinds := []
			for m in e["memory"]:
				kinds.append(m["kind"])
			check(kinds.has("helped"), "%s remembers it" % e["id"])


func test_one_bump_never_turns_the_band_hostile() -> void:
	var sim := _with_band(["b2"])
	var r_sum := float(sim.me["stats"]["body_radius_m"]) + float(sim._individual_of("b2")["stats"]["body_radius_m"])
	sim.place(SocialSim.PLAYER_ID, Vector2(0.0, 2.0), 0.0)
	sim.place("b2", Vector2(0.0, 2.0 - r_sum - 0.05), 0.0)
	var trust_before := float(sim.individual("b2")["trust"])
	var rep_before := float(sim.reputation["band"])
	var events := _run(sim, 40, {"move": Vector2(0.0, -1.0)})
	var bumps := _of_kind(events, "bumped")
	check_eq(bumps.size(), 1, "walking into it is one bump, not one per tick")
	check_eq(_of_kind(events, "hostile").size() + _of_kind(events, "left").size(), 0, "nothing hostile")
	var after := sim.individual("b2")
	check(float(after["trust"]) >= trust_before - 0.6, "a bump is a mild memory (%.2f -> %.2f)" % [trust_before, after["trust"]])
	check_near(float(sim.reputation["band"]), rep_before, 0.0001, "a bump never moves the band's reputation")
	check(after["mood"] != "hostile", "it is not hostile")
	check_eq(sim.group_hostile_left("band"), 0, "nor is its group")
	check_eq(Array(sim.band()), ["b2"], "it stays in the band")
	var acks := _of_kind(sim.tick({"order": "wait"}), "ack")
	check_eq(acks.size(), 1, "and still takes orders")
	_run(sim, int(_tuning["memory"]["kinds"]["bumped"]["life_t"]))
	var bump_weight := 0.0
	var bump_entries := 0
	for e in sim.to_record()["individuals"]:
		if e["id"] == "b2":
			for m in e["memory"]:
				if m["kind"] == "bumped":
					bump_entries += 1
					bump_weight += SocialMemory.weight_at(m, sim.tick_count, _tuning)
	check(bump_entries <= 1, "one bump memory at most")
	check_near(bump_weight, 0.0, 0.000001, "the bump has faded to nothing")
	check(float(sim.individual("b2")["trust"]) >= trust_before - 0.1, "and its trust comes back (%.2f)" % sim.individual("b2")["trust"])


## A startle is the individual's memory alone: pressing the wrong signal at the wary monkey again and again never
## turns its group against the player (plan section 5: failures cost nothing).
func test_startles_never_turn_a_group_against_the_player() -> void:
	var sim := _sim()
	var cooldown := int(_tuning["signals"]["cooldown_t"])
	var startles := 0
	for i in 25:
		_stand_before(sim, "b3", 4.0)
		for e in _of_kind(sim.tick({"signal": "sing"}), "response"):
			if e["response"] == "startles":
				startles += 1
		_run(sim, cooldown)
	check(startles >= 20, "the wary monkey was startled %d times" % startles)
	check(float(sim.reputation["band"]) >= 0.0,
			"startles never lower the band's reputation (%.2f; the few Sings it listened to raise it)" % sim.reputation["band"])
	var kinds := []
	for e in sim.to_record()["individuals"]:
		if e["id"] == "b3":
			for m in e["memory"]:
				kinds.append(m["kind"])
	check(kinds.has("startled"), "the startles stay the monkey's own memory (%s)" % [kinds])
	check_eq(sim.group_hostile_left("band"), 0, "the band never refuses for startles")
	for id in ["b1", "b2", "b3"]:
		_stand_before(sim, id, 3.0)
		var p := sim.preview_signal("calm")
		check(bool(p["ok"]), "%s still listens to Calm (%s)" % [id, p.get("reason", "")])


## Bites are harm: enough of them turn the group against the player, for reputation.hostile_t and not for good. Then
## it listens again, its reputation lifted to reputation.truce and forgiven further with time (Bible section 8: no
## permanent war).
func test_bites_make_a_group_refuse_for_a_while_then_it_listens_again() -> void:
	var sim := _sim()
	var bite_cd := int(_tuning["bite"]["cooldown_t"])
	var r: Dictionary = _tuning["reputation"]
	var events := []
	var bites := 0
	while _of_kind(events, "group_hostile").is_empty() and bites < 30:
		_stand_before(sim, "b2", 0.6)
		var out := sim.tick({"bite": true})
		bites += _of_kind(out, "bit").size()
		events.append_array(out)
		events.append_array(_run(sim, bite_cd + 1))
	var turned := _of_kind(events, "group_hostile")
	check_eq(turned.size(), 1, "the band turned against the player once, after %d bites" % bites)
	check(bites >= 10, "and only after ten bites or more (%d)" % bites)
	check_eq(String(turned[0]["group"]), "band", "it was the band")
	check(sim.group_hostile_left("band") > 0, "the band refuses for a while")
	_stand_before(sim, "b1", 3.0)
	var refused := sim.preview_signal("calm")
	check(not bool(refused["ok"]) and String(refused["reason"]).begins_with("They won't listen: you hurt them ("),
			"even the unbitten strider refuses, with the time left: %s" % refused.get("reason", ""))
	check(sim.group_hostile_left("band") <= int(r["hostile_t"]), "for at most reputation.hostile_t")
	var later := _run(sim, sim.group_hostile_left("band") + 1)
	check_eq(_of_kind(later, "group_listens").size(), 1, "then the band listens again")
	check_eq(sim.group_hostile_left("band"), 0, "its hostility is over")
	check(float(sim.reputation["band"]) >= float(r["truce"]) - 0.0001,
			"its reputation is lifted to the truce (%.2f)" % sim.reputation["band"])
	_stand_before(sim, "b1", 3.0)
	check(bool(sim.preview_signal("calm")["ok"]), "the strider takes Calm again")
	var at_truce := float(sim.reputation["band"])
	_run(sim, 600)
	check(float(sim.reputation["band"]) > at_truce, "and a bad reputation keeps being forgiven (%.2f -> %.2f)"
			% [at_truce, sim.reputation["band"]])
	check(float(sim.reputation["band"]) <= 0.0, "back toward 0, never past it")


## Followers keep their own places beside the player (band.slots_m): level with it rather than in a line behind it
## (where the camera would put them under the HUD), and at least band.spacing_m apart once the band stops.
func test_followers_keep_their_places_beside_the_player_and_apart() -> void:
	var sim := _with_band(["b1", "b2", "b3"])
	var spacing := float(_tuning["band"]["spacing_m"])
	var worst_apart := INF
	var worst_behind := -INF
	# Away from the hunter's beat (north-east of the nest), so no one runs from it.
	for phase in [[Vector2(0.0, 1.0), 300], [Vector2.ZERO, 300], [Vector2(-1.0, 0.0), 240], [Vector2.ZERO, 300]]:
		_run(sim, int(phase[1]), {"move": phase[0]})
		if phase[0] != Vector2.ZERO:
			continue
		var me := _ground(sim.player()["position"])
		var forward := Vector2(-sin(float(sim.player()["yaw"])), -cos(float(sim.player()["yaw"])))
		var ids := Array(sim.band())
		for i in ids.size():
			var at := _ground(sim.individual(ids[i])["position"])
			check_eq(sim.individual(ids[i])["state"], "follow", "%s follows" % ids[i])
			worst_behind = maxf(worst_behind, -(at - me).dot(forward))
			for j in range(i + 1, ids.size()):
				worst_apart = minf(worst_apart, at.distance_to(_ground(sim.individual(ids[j])["position"])))
	check(worst_apart >= spacing, "stopped followers stand at least spacing_m apart (closest %.2f m)" % worst_apart)
	check(worst_behind <= 1.5, "and level with the player, not trailing behind it (furthest back %.2f m)" % worst_behind)


## Retreat sends each member to its own spot at the nest, so the band waits there side by side.
func test_a_retreating_band_waits_at_the_nest_side_by_side() -> void:
	var sim := _with_band(["b1", "b2", "b3"])
	_run(sim, 240, {"move": Vector2(1.0, 0.0)})
	var acks := _of_kind(sim.tick({"order": "retreat"}), "ack")
	check_eq(acks.size(), 3, "each member acknowledges Retreat")
	_run(sim, 900)
	var ids := Array(sim.band())
	var radius := float(_tuning["nest"]["radius_m"])
	for i in ids.size():
		var at := _ground(sim.individual(ids[i])["position"])
		check(at.length() <= radius, "%s waits in the nest (%.1f m from its centre)" % [ids[i], at.length()])
		for j in range(i + 1, ids.size()):
			var apart := at.distance_to(_ground(sim.individual(ids[j])["position"]))
			check(apart >= float(_tuning["band"]["spacing_m"]), "%s and %s stand apart (%.2f m)" % [ids[i], ids[j], apart])
