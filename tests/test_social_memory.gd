extends TestCase
## Memory and reputation (PROPOSED, docs/stages/social-plan.md section 5; Bible section 8): memories fade and drop
## out, at most cap are kept, one accident never makes an individual or a group hostile, repeated bites make one
## hostile for a while and never for life, and reputation moves at most step_cap per event.

const SLICE_PATH := "res://game/data/social/social_slice.json"

var tuning := {}


func before_each() -> void:
	tuning = SocialRules.with_ticks(JSON.parse_string(FileAccess.get_file_as_string(SLICE_PATH)))


func _life(kind: String) -> int:
	return int(tuning["memory"]["kinds"][kind]["life_t"])


func _weight(kind: String) -> float:
	return float(tuning["memory"]["kinds"][kind]["weight"])


func test_memories_fade_over_their_lifetime_and_drop_out() -> void:
	var life := _life("kind")
	check_eq(life, SocialRules.to_ticks(float(tuning["memory"]["kinds"]["kind"]["life_s"])), "life in whole ticks")
	var e := SocialMemory.entry("kind", 100)
	check_near(SocialMemory.weight_at(e, 100, tuning), _weight("kind"), 0.0001, "full weight when new")
	check_near(SocialMemory.weight_at(e, 100 + life / 2, tuning), _weight("kind") * 0.5, 0.001, "half way: half")
	check(SocialMemory.weight_at(e, 100 + life - 1, tuning) > 0.0, "still there just before its life ends")
	check_near(SocialMemory.weight_at(e, 100 + life, tuning), 0.0, 0.0001, "nothing once its life is over")
	var scaled := SocialMemory.entry("kind", 100, 2.0)
	check_near(SocialMemory.weight_at(scaled, 100, tuning), _weight("kind") * 2.0, 0.0001, "scale multiplies")
	var memory := SocialMemory.add([], "kind", 100, tuning)
	check_eq(SocialMemory.prune(memory, 100 + life - 1, tuning).size(), 1, "kept until its life ends")
	check_eq(SocialMemory.prune(memory, 100 + life, tuning).size(), 0, "dropped out after")
	check_eq(SocialMemory.add([], "no_such_kind", 0, tuning).size(), 0, "an unknown kind is not remembered")


func test_memory_keeps_at_most_cap_entries() -> void:
	var cap := int(tuning["memory"]["cap"])
	var memory := []
	var tick := 0
	for i in cap:
		memory = SocialMemory.add(memory, "listened", tick, tuning)
		tick += 60
	memory = SocialMemory.add(memory, "bitten", tick, tuning)
	tick += 60
	var before := memory.duplicate(true)
	for i in 5:
		memory = SocialMemory.add(memory, "kind", tick, tuning)
		tick += 60
	check_eq(memory.size(), cap, "never more than cap entries")
	check_eq(before.size(), cap, "add() leaves its input alone")
	check_eq(memory.filter(func(e): return e["kind"] == "bitten").size(), 1, "the strong bite is not forgotten first")
	check_eq(memory.filter(func(e): return e["kind"] == "kind").size(), 5, "the new kind memories are kept")
	var listened := memory.filter(func(e): return e["kind"] == "listened")
	check_eq(listened.size(), cap - 6, "the weakest (listened) go first")
	# Of equally weak entries the oldest goes first: the survivors are the newest listened ones.
	var ticks := listened.map(func(e): return int(e["tick"]))
	check_eq(ticks, [(cap - 2) * 60, (cap - 1) * 60], "the oldest listened entries were dropped")


func test_one_accidental_bump_never_makes_an_individual_or_the_band_hostile() -> void:
	var bases: Dictionary = tuning["trust"]["base"]
	for disposition in bases:
		var base := float(bases[disposition])
		var memory := SocialMemory.add([], "bumped", 1000, tuning)
		check_eq(SocialMemory.hostile_after(memory, 1000, tuning), 0, "%s: a bump is no reason for hostility" % disposition)
		var t := SocialMemory.trust(memory, 1000, base, 0.0, tuning)
		check_near(t, base + _weight("bumped"), 0.0001, "%s: a bump costs a little trust" % disposition)
		check_near(SocialMemory.trust(memory, 1000 + _life("bumped"), base, 0.0, tuning), base, 0.0001,
				"%s: and it is forgotten" % disposition)
	var rep := SocialMemory.reputation_after(0.0, SocialMemory.event_weight("bumped", tuning), tuning)
	check_near(rep, _weight("bumped") * float(tuning["reputation"]["rate"]), 0.0001, "a bump nudges reputation")
	check(not SocialMemory.group_hostile(rep, tuning), "the band is not hostile after a bump")
	# Even many bumps in a row never make an individual hostile (only bites count) nor, quickly, the band.
	var memory := []
	rep = 0.0
	for i in 10:
		memory = SocialMemory.add(memory, "bumped", 2000 + i * 180, tuning)
		rep = SocialMemory.reputation_after(rep, SocialMemory.event_weight("bumped", tuning), tuning)
	check_eq(SocialMemory.hostile_after(memory, 2000 + 9 * 180, tuning), 0, "bumps are never bites")
	check(not SocialMemory.group_hostile(rep, tuning), "ten bumps leave the band willing (%.3f)" % rep)


func test_repeated_bites_make_an_individual_hostile_for_a_while_not_forever() -> void:
	var h: Dictionary = tuning["hostile"]
	var window := int(h["window_t"])
	var lasts := int(h["lasts_t"])
	var bites := int(h["bites"])
	var memory := []
	var tick := 500
	for i in bites - 1:
		memory = SocialMemory.add(memory, "bitten", tick, tuning)
		check_eq(SocialMemory.hostile_after(memory, tick, tuning), 0, "bite %d alone is not enough" % (i + 1))
		tick += 600
	memory = SocialMemory.add(memory, "bitten", tick, tuning)
	var until := SocialMemory.hostile_after(memory, tick, tuning)
	check_eq(until, tick + lasts, "%d bites within the window: hostile for lasts_t" % bites)
	check(until < tick + 100000, "for a while, not for life")
	check_eq(SocialMemory.hostile_after(memory, tick + window, tuning), 0, "the window passes: no new hostility")
	# The same bites spread wider than the window never add up.
	var spread := []
	var t2 := 0
	for i in bites:
		spread = SocialMemory.add(spread, "bitten", t2, tuning)
		check_eq(SocialMemory.hostile_after(spread, t2, tuning), 0, "spread bite %d" % (i + 1))
		t2 += window / (bites - 1) + 1
	# Once the bites have faded, trust is back at its base.
	var base := float(tuning["trust"]["base"]["curious"])
	check(SocialMemory.trust(memory, tick, base, 0.0, tuning) < base, "bites cost trust")
	check_near(SocialMemory.trust(memory, tick + _life("bitten"), base, 0.0, tuning), base, 0.0001, "and fade")


func test_reputation_moves_at_most_step_cap_per_event() -> void:
	var r: Dictionary = tuning["reputation"]
	var cap := float(r["step_cap"])
	for kind in tuning["memory"]["kinds"]:
		for scale in [0.5, 1.0, 2.5]:
			var w := SocialMemory.event_weight(kind, tuning, scale)
			var after := SocialMemory.reputation_after(0.0, w, tuning)
			check(absf(after) <= cap + 0.0001, "%s x%.1f moves reputation %.3f" % [kind, scale, after])
	check_near(SocialMemory.reputation_after(float(r["max"]), 9.0, tuning), float(r["max"]), 0.0001, "kept within max")
	check_near(SocialMemory.reputation_after(float(r["min"]), -9.0, tuning), float(r["min"]), 0.0001, "kept within min")
	# The band refuses everything only after at least ten capped bad events.
	var rep := 0.0
	var events := 0
	while not SocialMemory.group_hostile(rep, tuning) and events < 100:
		rep = SocialMemory.reputation_after(rep, SocialMemory.event_weight("bitten", tuning), tuning)
		events += 1
	check(events >= 10, "hostile after %d bites, not sooner than ten" % events)
	# Reputation is half of trust (reputation.weight).
	check_near(SocialMemory.trust([], 0, 0.0, 4.0, tuning), 4.0 * float(r["weight"]), 0.0001, "reputation in trust")
	check_near(SocialMemory.trust([], 0, 0.0, 100.0, tuning), float(tuning["trust"]["max"]), 0.0001, "trust clamped")


func test_help_outlasts_a_bump() -> void:
	var memory := SocialMemory.add([], "helped", 0, tuning)
	memory = SocialMemory.add(memory, "bumped", 0, tuning)
	var later := _life("bumped") + 1
	var kept := SocialMemory.prune(memory, later, tuning)
	check_eq(kept.size(), 1, "the bump is gone")
	check_eq(String(kept[0]["kind"]), "helped", "the help remains")
	check(SocialMemory.feeling(memory, later, tuning) > 0.0, "the feeling is still good")
	check(SocialMemory.feeling(memory, 0, tuning) > 0.0, "even at the moment of the bump")
	check(_life("helped") > _life("bumped"), "help is remembered longer")
