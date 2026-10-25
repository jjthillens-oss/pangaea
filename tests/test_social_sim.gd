extends TestCase
## The Social stage slice's world (PROPOSED, docs/stages/social-plan.md sections 4 to 10): deterministic for a seed
## and the intents, stable individuals with names, roles and needs, befriending into the band and dismissing out of
## it, and a wary loner that backs away from a loud signal and listens to Calm.

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
	if t == 400:
		intent["dismiss"] = "b1"
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
