extends TestCase
## The interaction resolver (PROPOSED, docs/stages/social-plan.md sections 4, 7 and 9): read and answer signals
## (Sing, Display, Share, Calm), where a refusal names what is missing and costs nothing and the answer depends on the
## choice, never on timing (Bible section 14: no rhythm minigame); orders that are acknowledged or refused with a
## reason; the explicit learning rule; names from a seeded stream.

const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const SLICE_PATH := "res://game/data/social/social_slice.json"
const RULES_PATH := "res://game/domain/social/social_rules.gd"
const CAST: Array[String] = ["strider", "boar", "monkey", "hopper", "prowler"]

var tuning := {}
var traits := {}


func before_each() -> void:
	tuning = SocialRules.with_ticks(JSON.parse_string(FileAccess.get_file_as_string(SLICE_PATH)))
	if traits.is_empty():
		var part_rules := CreatureData.part_rules()
		var gait_table := CreatureData.gait_table()
		var creature_tuning := CreatureData.read_json(CreatureData.DATA_DIR + "/creature_stage.json")
		for preset in CAST:
			var body := CreatureData.preset_body(preset)
			traits[preset] = SocialTraits.of(body, CreatureStats.of(body, part_rules, gait_table, creature_tuning),
					part_rules, tuning)


func _actor(preset: String, at: Vector2, carrying := 0, cooldown := 0) -> Dictionary:
	return {"position": at, "cooldown_t": cooldown, "carrying": carrying, "traits": traits[preset]}


## An individual of `preset` at the origin facing +Y (on the ground plane, +Z), calm, fed and neutral.
func _target(preset: String, extra := {}) -> Dictionary:
	var t := {"position": Vector2.ZERO, "heading": Vector2(0.0, 1.0), "traits": traits[preset], "hostile_left_t": 0,
			"group_hostile": false, "hunger": 0.1, "fear": 0.0, "disposition": "curious", "trust": 0.0, "busy": false}
	t.merge(extra, true)
	return t


func test_durations_become_whole_ticks_once() -> void:
	check_eq(SocialRules.to_ticks(1.0), 60, "a second is 60 ticks")
	check_eq(SocialRules.to_ticks(0.8), 48, "0.8 s")
	check_eq(SocialRules.to_ticks(0.001), 1, "a positive duration is at least one tick")
	check_eq(SocialRules.to_ticks(0.0), 0, "zero stays zero")
	check_eq(int(tuning["signals"]["cooldown_t"]), 60, "the signal cooldown")
	check_eq(int(tuning["hunter"]["investigate_t"]), 150, "the hunter's tell")
	check_eq(int(tuning["memory"]["kinds"]["bitten"]["life_t"]), 5400, "a nested memory lifetime")
	check(not (tuning["player"] as Dictionary).has("health_regen_per_t"), "a rate per second is not a duration")
	check_eq(int(tuning["tick_hz"]), 60, "the rate is recorded")


func test_a_signal_out_of_range_is_refused_with_the_distance_and_costs_nothing() -> void:
	var actor := _actor("strider", Vector2(0.0, 7.0), 1)
	var before := actor.duplicate(true)
	var song := SocialRules.check_signal("sing", actor, _target("strider"), tuning)
	check(not song["ok"], "7 m is too far for a plain song")
	check_eq(song["reason"], "Too far: come within 6 m", "the reason names the distance")
	check_near(float(song["range_m"]), 6.0, 0.0001, "the range")
	check_eq(actor, before, "a refusal spends no cooldown and no fruit")
	check(SocialRules.check_signal("sing", _actor("strider", Vector2(0.0, 5.9)), _target("strider"), tuning)["ok"],
			"within 6 m it can be sung")
	var share := SocialRules.check_signal("share", _actor("monkey", Vector2(0.0, 3.0), 1), _target("boar"), tuning)
	check_eq(share["reason"], "Too far: come within 2.5 m", "share's touch range")
	# The hopper's throat sac sings to the eared boar from 15 m (10 m times 1.5).
	var far := SocialRules.check_signal("sing", _actor("hopper", Vector2(0.0, 14.5)), _target("boar"), tuning)
	check(far["ok"], "a throat sac to ears reaches 14.5 m (range %.1f)" % far["range_m"])
	var cooling := SocialRules.check_signal("calm", _actor("hopper", Vector2(0.0, 1.0), 0, 10), _target("boar"), tuning)
	check_eq(cooling["reason"], "Wait a moment", "the cooldown")
	var hurt := SocialRules.check_signal("calm", _actor("hopper", Vector2(0.0, 1.0)), _target("boar", {"hostile_left_t": 2350}),
			tuning)
	check_eq(hurt["reason"], "It won't listen: you hurt it (40 s)", "hostility names the seconds left")


func test_a_target_facing_away_refuses_display_but_hears_a_song() -> void:
	var behind := Vector2(0.0, -4.0)
	var away := SocialRules.check_signal("display", _actor("strider", behind), _target("monkey"), tuning)
	check(not away["ok"], "a display behind its back is not seen")
	check_eq(away["reason"], "It can't see you: get in front of it", "and it says how to fix it")
	check(SocialRules.check_signal("sing", _actor("strider", behind), _target("monkey"), tuning)["ok"], "a song is heard")
	check(SocialRules.check_signal("calm", _actor("strider", Vector2(0.0, -2.5)), _target("monkey"), tuning)["ok"],
			"calm works by touch too")
	check(SocialRules.check_signal("display", _actor("strider", Vector2(0.0, 4.0)), _target("monkey"), tuning)["ok"],
			"in front of it the display is seen")
	check(SocialRules.check_signal("display", _actor("strider", Vector2(3.0, 1.5)), _target("monkey"), tuning)["ok"],
			"within the view cone off to one side")
	check(not SocialRules.check_signal("display", _actor("strider", Vector2(4.0, 0.0)), _target("monkey"), tuning)["ok"],
			"square to its side is outside the cone")


func test_share_needs_something_carried_and_says_so() -> void:
	var empty := SocialRules.check_signal("share", _actor("monkey", Vector2(0.0, 1.0)), _target("boar"), tuning)
	check_eq(empty["reason"], "Nothing to share: carry a fruit first", "nothing carried")
	check(SocialRules.check_signal("share", _actor("monkey", Vector2(0.0, 1.0), 1), _target("boar"), tuning)["ok"],
			"carrying a fruit it can share")
	var no_hands: Dictionary = (traits["monkey"] as Dictionary).duplicate()
	no_hands["can_carry"] = false
	var actor := {"position": Vector2(0.0, 1.0), "cooldown_t": 0, "carrying": 0, "traits": no_hands}
	check_eq(SocialRules.check_signal("share", actor, _target("boar"), tuning)["reason"],
			"Your body can't carry: it needs a mouth or a hand", "a body that cannot carry is told why")
	var gift := SocialRules.respond("share", _target("boar", {"hunger": 0.7}), 1.0, tuning)
	check_eq(gift["response"], "fits", "a hungry boar welcomes a gift")
	check(gift["gift_taken"], "and takes the fruit")
	check(not SocialRules.respond("share", _target("boar", {"busy": true}), 1.0, tuning)["gift_taken"],
			"a busy one leaves the fruit with you")


func test_the_fitting_signal_follows_what_the_individual_shows() -> void:
	var hungry_boar := _target("boar", {"hunger": 0.7, "disposition": "warm", "trust": 1.0})
	check_eq(SocialRules.fitting_signal(hungry_boar, tuning), "share", "hungry: a gift")
	check_eq(SocialRules.mood(hungry_boar, tuning), "hungry", "and its tag says hungry")
	var fed_boar := _target("boar", {"hunger": 0.2, "disposition": "warm", "trust": 4.5})
	check_eq(SocialRules.fitting_signal(fed_boar, tuning), "sing", "fed, with one display organ: a song")
	check_eq(SocialRules.mood(fed_boar, tuning), "warm", "its tag")
	var wary := _target("monkey", {"disposition": "wary", "trust": -1.0})
	check_eq(SocialRules.fitting_signal(wary, tuning), "calm", "wary: calm")
	check_eq(SocialRules.mood(wary, tuning), "wary", "its tag")
	var calmed := _target("monkey", {"disposition": "wary", "trust": 2.0})
	check_eq(SocialRules.fitting_signal(calmed, tuning), "sing", "calmed to trust 2: it listens to a song")
	var curious := _target("strider")
	check_eq(SocialRules.fitting_signal(curious, tuning), "display", "a crested strider answers a display")
	check_eq(SocialRules.mood(curious, tuning), "curious", "its tag")
	var scared := _target("strider", {"fear": 0.5})
	check_eq(SocialRules.fitting_signal(scared, tuning), "calm", "frightened: calm")
	check_eq(SocialRules.mood(scared, tuning), "scared", "its tag")
	check_eq(SocialRules.mood(_target("strider", {"hostile_left_t": 10}), tuning), "hostile", "hurt: hostile")
	# The fitting signal is welcomed; the others are not.
	for t in [hungry_boar, fed_boar, wary, calmed, curious, scared]:
		var fits := SocialRules.fitting_signal(t, tuning)
		for kind in SocialRules.SIGNALS:
			var r := SocialRules.respond(kind, t, float(t["trust"]), tuning)
			check_eq(r["response"] == "fits", kind == fits, "%s to %s: %s" % [kind, t["traits"]["role"], r["response"]])
	var welcome := SocialRules.respond("display", curious, 0.0, tuning, 2.09)
	check_eq(welcome["memory_kind"], "kind", "a fitting display leaves a kind memory")
	check_near(float(welcome["scale"]), 2.09, 0.0001, "scaled by the display's strength")
	check_eq(SocialRules.respond("sing", wary, -1.0, tuning)["response"], "startles", "a song startles the wary")
	check_eq(SocialRules.respond("share", _target("strider"), -1.0, tuning)["response"], "unsure",
			"an unfitting quiet signal below zero trust")
	check_eq(SocialRules.respond("sing", _target("strider", {"fear": 0.8}), 0.0, tuning)["response"], "busy",
			"too frightened to listen")


func test_the_response_depends_on_the_choice_not_on_when_it_was_pressed() -> void:
	var individuals := [_target("boar", {"hunger": 0.7, "disposition": "warm"}),
			_target("monkey", {"disposition": "wary", "trust": -1.0}), _target("strider"), _target("hopper")]
	for t in individuals:
		for kind in SocialRules.SIGNALS:
			var first := SocialRules.respond(kind, t, float(t["trust"]), tuning)
			for press in [0, 1, 7, 59, 60, 61, 600, 12345]:
				var timed: Dictionary = t.duplicate()
				timed.merge({"tick": press, "pressed_tick": press, "since_last_t": press % 37, "held_t": press % 5,
						"presses": press % 4, "sequence": ["sing", "calm"].slice(0, press % 3)}, true)
				check_eq(SocialRules.respond(kind, timed, float(t["trust"]), tuning), first,
						"%s to %s at press %d" % [kind, t["traits"]["role"], press])
				var at := {"position": Vector2(0.0, 2.0), "cooldown_t": 0, "carrying": 1, "traits": traits["strider"],
						"tick": press, "last_signal_tick": press - 61}
				check_eq(SocialRules.check_signal(kind, at, timed, tuning)["ok"],
						SocialRules.check_signal(kind, _actor("strider", Vector2(0.0, 2.0), 1), t, tuning)["ok"],
						"%s can be given whatever the timing" % kind)
	# The resolver's source reads no time: respond() and fitting_signal() mention no tick, clock or beat.
	var source := FileAccess.get_file_as_string(RULES_PATH)
	for fn in ["static func respond(", "static func fitting_signal(", "static func is_wary("]:
		var start := source.find(fn)
		check(start >= 0, "%s exists" % fn)
		var end := source.find("\nstatic func ", start + fn.length())
		var body := source.substr(start, end - start)
		var code := PackedStringArray()
		for line in body.split("\n"):
			if not line.strip_edges().begins_with("#"):
				code.append(line)
		var text := "\n".join(code).to_lower()
		for word in ["tick", "time", "beat", "rhythm", "tempo", "press", "sequence"]:
			check(not word in text, "%s reads no %s" % [fn, word])


func test_calm_is_eligible_for_every_body_so_no_body_is_locked_out() -> void:
	for preset in CAST:
		var r := SocialRules.check_signal("calm", _actor(preset, Vector2(0.0, -2.0)), _target("monkey"), tuning)
		check(r["ok"], "%s can calm from behind at 2 m (%s)" % [preset, r["reason"]])
	for t in [_target("monkey", {"disposition": "wary", "trust": -1.0}), _target("strider", {"fear": 0.5}),
			_target("boar", {"hunger": 0.9})]:
		check(SocialRules.respond("calm", t, float(t["trust"]), tuning)["response"] != "startles", "calm never startles")
	# A body that cannot give the fitting signal (a gift without carrying) still earns a friendly answer.
	var hungry := _target("boar", {"hunger": 0.7, "disposition": "warm", "trust": 1.0})
	var other := SocialRules.respond("sing", hungry, 1.0, tuning)
	check_eq(other["response"], "ok", "a song to a hungry boar: it listens")
	check(SocialMemory.event_weight(String(other["memory_kind"]), tuning) > 0.0, "a small friendly memory")


func test_every_order_is_acknowledged_or_refused_with_a_reason() -> void:
	var orders: Array = SocialRules.ORDERS.duplicate()
	orders.append(SocialRules.DISMISS)
	orders.append("dance_off")
	var companions := []
	for role in ["scout", "defender", "forager"]:
		for fear in [0.0, 0.6]:
			for hostile in [false, true]:
				for member in [true, false]:
					companions.append({"role": role, "fear": fear, "trust": 3.0, "hostile": hostile, "member": member,
							"home_name": "den"})
	var contexts := [{}, {"in_fight": true}, {"spot_hunter_m": 5.0}, {"in_fight": true, "spot_hunter_m": 30.0}]
	var acks := {}
	for order in orders:
		for c in companions:
			for ctx in contexts:
				var r := SocialRules.check_order(order, c, ctx, tuning)
				if r["ok"]:
					check(String(r["ack"]) != "", "%s acknowledged in words" % order)
					acks[order] = true
				else:
					check(String(r["reason"]) != "", "%s refused with a reason" % order)
	for order in orders:
		check_eq(acks.has(order), order != "dance_off", "%s can be acknowledged" % order)
	var hostile := SocialRules.check_order("follow", {"role": "scout", "hostile": true, "member": true}, {}, tuning)
	check_eq(hostile["reason"], "won't listen: you hurt it", "a hostile companion refuses")


func test_a_forager_refuses_to_assist_in_a_fight() -> void:
	var forager := {"role": "forager", "fear": 0.0, "trust": 7.0, "hostile": false, "member": true}
	var fight := SocialRules.check_order("assist", forager, {"in_fight": true}, tuning)
	check(not fight["ok"], "a forager will not fight")
	check(String(fight["reason"]).begins_with("no fighter"), "it says so: %s" % fight["reason"])
	check_eq(fight["mode"], "gather", "and gathers instead")
	var calm := SocialRules.check_order("assist", forager, {}, tuning)
	check(calm["ok"] and calm["mode"] == "gather", "without a fight it gathers food")
	check_eq(calm["ack"], "gathers food", "the acknowledgement")
	var defender := SocialRules.check_order("assist", {"role": "defender", "member": true}, {"in_fight": true}, tuning)
	check(defender["ok"] and defender["mode"] == "fight", "a defender fights beside you")
	check_eq(defender["ack"], "with you", "the acknowledgement")


func test_a_frightened_companion_refuses_to_investigate_near_the_hunter() -> void:
	var scared := {"role": "scout", "fear": 0.6, "trust": 3.0, "hostile": false, "member": true}
	var near := SocialRules.check_order("investigate", scared, {"spot_hunter_m": 10.0}, tuning)
	check(not near["ok"], "too scared to look near the hunter")
	check_eq(near["reason"], "too scared: the hunter is near", "the reason")
	check(SocialRules.check_order("investigate", scared, {"spot_hunter_m": 20.0}, tuning)["ok"], "far from it: it goes")
	check(SocialRules.check_order("investigate", scared, {}, tuning)["ok"], "the hunter unseen: it goes")
	var trusting := scared.duplicate()
	trusting["trust"] = 9.0
	check(SocialRules.check_order("investigate", trusting, {"spot_hunter_m": 10.0}, tuning)["ok"], "trust overcomes fear")
	var calm := scared.duplicate()
	calm["fear"] = 0.2
	check(SocialRules.check_order("investigate", calm, {"spot_hunter_m": 10.0}, tuning)["ok"], "a calm one goes")


func test_learning_passes_by_the_explicit_rule() -> void:
	var l: Dictionary = tuning["learning"]
	var at := int(l["inherit_at_uses"])
	var parent := {
		"grove": {"uses": at, "inherited": false, "idle": 0},
		"lair_path": {"uses": at - 1, "inherited": false, "idle": 0},
		"old_route": {"uses": 0, "inherited": true, "idle": 0},
		"kept_route": {"uses": 1, "inherited": true, "idle": 0},
	}
	var child := SocialRules.inherit_learning(parent, tuning)
	check_eq(child.keys(), ["grove", "kept_route"], "used enough or kept in use: inherited, in name order")
	check_eq(child["grove"], {"uses": 0, "inherited": true, "idle": 0}, "a fresh inherited route")
	check(not child.has("lair_path"), "used fewer than %d times: not passed on" % at)
	check(not child.has("old_route"), "an inherited route unused for a generation is forgotten")
	check_eq(SocialRules.inherit_learning(child, tuning).keys(), [], "the grandchild keeps none of them unused")
	check_eq(SocialRules.inherit_learning(parent, tuning), child, "the rule is deterministic")


func test_names_come_from_the_seeded_stream() -> void:
	var names: Dictionary = tuning["names"]
	var a := RandomNumberGenerator.new()
	a.seed = 4260
	var b := RandomNumberGenerator.new()
	b.seed = 4260
	var seen := {}
	for i in 20:
		var n := SocialRules.make_name(a, names["syllables"], names["parts"])
		check_eq(n, SocialRules.make_name(b, names["syllables"], names["parts"]), "the same seed, the same name")
		check(n.length() >= 4 and n[0] == n[0].to_upper(), "a capitalised name: %s" % n)
		seen[n] = true
	check(seen.size() > 10, "names vary (%d distinct of 20)" % seen.size())
