extends TestCase
## The balance lab (game/dev/balance_lab.gd, tools/balance_lab.sh): every bot runs for every starting
## body, a run repeats exactly for its seed, and the summary and its flags add up. The lab's numbers
## are information, not gates; the step 3 gates stay in test_threat_gates.

const BalanceLab := preload("res://game/dev/balance_lab.gd")
const LabMain := preload("res://tests/balance/balance_lab_main.gd")

const SHORT_TICKS := 10 * 60
const REPEAT_TICKS := 40 * 60

var lab


func before_each() -> void:
	lab = BalanceLab.new()


func test_every_bot_runs_for_every_body() -> void:
	check_eq(lab.bodies(), PackedStringArray(["grazer", "hunter", "omnivore"]), "the three starting bodies")
	for body in lab.bodies():
		for bot in BalanceLab.BOTS:
			var r: Dictionary = lab.run(body, bot, 7, SHORT_TICKS)
			check(r.ok, "%s %s runs" % [body, bot])
			if not r.ok:
				continue
			check_eq(int(r.alive_ticks) + int(r.dead_ticks), SHORT_TICKS, "%s %s: every tick is alive or dead" % [body, bot])
			check_eq(int(r.deaths), int(r.starved) + int(r.killed), "%s %s: deaths are starved or killed" % [body, bot])


func test_an_unknown_body_or_bot_is_refused() -> void:
	check(not lab.run("whale", "forage", 7, SHORT_TICKS).ok, "unknown body")
	check(not lab.run("grazer", "teleport", 7, SHORT_TICKS).ok, "unknown bot")


func test_a_run_repeats_exactly_for_its_seed() -> void:
	var a: Dictionary = lab.run("grazer", "evade", 501, REPEAT_TICKS)
	var b: Dictionary = BalanceLab.new().run("grazer", "evade", 501, REPEAT_TICKS)
	check_eq(a.state_hash, b.state_hash, "same end state")
	check_eq(JSON.stringify(a), JSON.stringify(b), "same counts")
	check(int(a.meals) > 0, "the forager ate (%d meals)" % a.meals)
	var c: Dictionary = lab.run("grazer", "evade", 502, REPEAT_TICKS)
	check(c.state_hash != a.state_hash, "another seed is another run")


func test_the_summary_adds_up_and_flags_starvation() -> void:
	var runs := [
		_run("grazer", "wary", 1, {"deaths": 1, "starved": 1, "meals": 30, "tells": 4, "dodges": 3, "first_death_tick": 9000}),
		_run("grazer", "wary", 2, {"deaths": 2, "killed": 2, "killed_by": {"rammer": 2}, "meals": 50, "first_death_tick": 3600}),
		_run("grazer", "forage", 1, {"meals": 60, "notices": 10}),
		_run("hunter", "forage", 1, {"meals": 60, "notices": 10}),
		{"ok": false},
	]
	var rows: Array[Dictionary] = BalanceLab.summarize(runs)
	check_eq(rows.size(), 3, "one row per body and bot")
	check_eq([rows[0].body, rows[0].bot, rows[1].bot, rows[2].body], ["grazer", "forage", "wary", "hunter"],
		"sorted by body, then in BOTS order")
	var wary: Dictionary = rows[1]
	check_eq(wary.runs, 2, "two runs")
	check_eq(wary.deaths, 3, "three deaths")
	check_eq(wary.killed_by, {"rammer": 2}, "killed by a rammer twice")
	check_eq(wary.survived_runs, 0, "neither survived")
	check_near(wary.deaths_per_5_min, 1.5, 1e-6, "3 deaths in 10 minutes")
	check_near(wary.meetings_per_min, 0.4, 1e-6, "4 tells in 10 minutes")
	check_near(wary.median_first_death_s, 150.0, 1e-6, "the later of two first deaths")
	var flags := BalanceLab.flags(wary)
	check(flags.size() >= 2, "starves and is worn down: %s" % ", ".join(flags))
	check(BalanceLab.flags(rows[0]).is_empty(), "a fed careless forager raises nothing")


func test_seed_ranges_and_lists_parse() -> void:
	check_eq(LabMain._seeds("1001-1003,7"), [1001, 1002, 1003, 7], "a range and a single seed")


## A 300 s run with the counts given, the rest zero.
func _run(body: String, bot: String, seed_value: int, counts: Dictionary) -> Dictionary:
	var r: Dictionary = lab._new_run(body, bot, seed_value, 300 * 60)
	r.alive_ticks = 300 * 60
	r.first_death_tick = 300 * 60
	r.merge(counts, true)
	return r
