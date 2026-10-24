extends TestCase
## The golden M1 hashes (endless plan D.4; S1 gate G1): pool mode stays bit-identical while the
## endless world is built beside it. Every scenario of tests/m1_scenarios.gd, re-run here, must give
## the state hash and the SHA-256 of the snapshot string recorded in tests/fixtures/m1_goldens.json.
## Tiers: seed 401 at 600 and 3,600 ticks is fast; seeds 402, 4242 and 77 are slow (in
## tools/check.sh); every seed at 18,000 ticks is soak (tools/check_soak.sh). A failure here is a
## pool-mode change: fix the change, never the file.

const Scenarios := preload("res://tests/m1_scenarios.gd")
const Runner := preload("res://tests/run_tests.gd")

const FAST_SEED := 401
const SLOW_SEEDS: Array[int] = [402, 4242, 77]
const SHORT_TICKS: Array[int] = [600, 3600]
## CI's soak jobs (build plan B-14): soak-a runs these files, soak-b skips them.
const SOAK_JOBS := {"soak-a": "--only", "soak-b": "--skip"}
const SOAK_A_FILES := "test_endless_gates,test_endless_cost"


func _check_scenarios(seeds: Array[int], ticks: Array[int]) -> void:
	var goldens := Scenarios.load_goldens()
	check(not goldens.is_empty(), "the goldens file loads")
	for scenario in Scenarios.SCENARIOS:
		for seed_value in seeds:
			var records := Scenarios.run(scenario, seed_value, ticks)
			check_eq(records.size(), ticks.size(), "%s seed %d: a record per tick count" % [scenario, seed_value])
			for r in records:
				var why := Scenarios.difference(r, Scenarios.golden(goldens, scenario, seed_value, r.tick))
				check(why.is_empty(), why)


func test_the_goldens_file_covers_every_scenario_seed_and_tick() -> void:
	var goldens := Scenarios.load_goldens()
	check_eq(int(goldens.get("schema_version", 0)), Scenarios.SCHEMA_VERSION, "schema_version")
	check_eq(str(goldens.get("body", "")), Scenarios.BODY, "body")
	check(str(goldens.get("recorded_at", "")).length() >= 7, "names the commit it was recorded at")
	check(str(goldens.get("engine", "")).begins_with("4."), "names the engine")
	var hashes: Array = goldens.get("hashes", [])
	var n := Scenarios.SCENARIOS.size() * Scenarios.SEEDS.size() * Scenarios.TICKS.size()
	check_eq(hashes.size(), n, "one record per scenario, seed and tick")
	var hex := RegEx.create_from_string("^[0-9a-f]{64}$")
	var i := 0
	for scenario in Scenarios.SCENARIOS:
		for seed_value in Scenarios.SEEDS:
			for tick in Scenarios.TICKS:
				if i >= hashes.size():
					return
				var g: Dictionary = hashes[i]
				var where := "record %d" % i
				check_eq(str(g.get("scenario", "")), scenario, where + " scenario")
				check_eq(int(g.get("seed", -1)), seed_value, where + " seed")
				check_eq(int(g.get("tick", -1)), tick, where + " tick")
				var h: Variant = g.get("hash")
				check((h is float or h is int) and float(h) >= 0.0 and float(h) == floorf(float(h)), where + " hash is a whole number")
				check(hex.search(str(g.get("sha256", ""))) != null, where + " sha256 is 64 lowercase hex digits")
				i += 1


## The golden string is exactly state_hash's string (S1 spine contradiction 14), so the sha256 and
## the hash describe the same bytes.
func test_the_golden_string_is_the_state_hash_string() -> void:
	for scenario in Scenarios.SCENARIOS:
		var sim: PoolSim = Scenarios.make(scenario, FAST_SEED).sim
		var text := JSON.stringify(sim.snapshot(), "", true, true)
		check_eq(hash(text), sim.state_hash(), "%s: state_hash hashes the sorted, full-precision snapshot" % scenario)
		var r := Scenarios.record_of(scenario, FAST_SEED, sim)
		check_eq(r.sha256, text.sha256_text(), "%s: the record's sha256 is of that string" % scenario)


func test_a_changed_engine_hash_is_told_apart_from_a_changed_sim() -> void:
	var got := {"scenario": "pool", "seed": 401, "tick": 600, "hash": 5, "sha256": "a".repeat(64)}
	check_eq(Scenarios.difference(got, {"hash": 5.0, "sha256": "a".repeat(64)}), "", "equal records")
	var engine := Scenarios.difference(got, {"hash": 6.0, "sha256": "a".repeat(64)})
	check(engine.contains("engine hash changed") and engine.contains("record_goldens.gd"), "only the hash differs: " + engine)
	var sim := Scenarios.difference(got, {"hash": 5.0, "sha256": "b".repeat(64)})
	check(sim.contains("state differs"), "the string differs: " + sim)
	check(Scenarios.difference(got, {}).contains("no golden record"), "a missing record")


func test_the_pool_scenarios_match_the_goldens_at_seed_401() -> void:
	_check_scenarios([FAST_SEED], SHORT_TICKS)


func test_slow_the_pool_scenarios_match_the_goldens_at_seeds_402_4242_77() -> void:
	_check_scenarios(SLOW_SEEDS, SHORT_TICKS)


func test_soak_the_pool_scenarios_match_the_goldens_at_18000_ticks() -> void:
	_check_scenarios(Scenarios.SEEDS, Scenarios.TICKS)


## The soak tier the 18,000-tick goldens run in (S1 spine 3.1): never in a default run, only with
## --soak; tools/check_soak.sh passes --soak, and CI runs it in two parallel jobs (build plan B-14).
func test_the_soak_tier_runs_only_with_soak_and_ci_runs_it_in_two_jobs() -> void:
	var plain := Runner._flags(PackedStringArray([]))
	var soak := Runner._flags(PackedStringArray(["--soak", "--only=test_m1_goldens"]))
	var quick := Runner._flags(PackedStringArray(["--skip-slow"]))
	check(not plain.soak and soak.soak and soak.only == PackedStringArray(["test_m1_goldens"]), "--soak parses")
	check_eq(Runner.tier_of("test_soak_x", plain), "soak skipped", "a default run skips soak tests")
	check_eq(Runner.tier_of("test_soak_x", quick), "soak skipped", "so does --skip-slow")
	check_eq(Runner.tier_of("test_soak_x", soak), "run", "--soak runs them")
	check_eq(Runner.tier_of("test_x", soak), "soak skipped", "and only them")
	check_eq(Runner.tier_of("test_slow_x", soak), "soak skipped", "slow tests are not soak")
	check_eq(Runner.tier_of("test_slow_x", plain), "run", "a default run keeps slow tests")
	check_eq(Runner.tier_of("test_slow_x", quick), "slow skipped", "--skip-slow skips them")
	check_eq(Runner.tier_of("test_x", plain), "run", "plain tests run")
	check_eq(Runner.tier_of("helper", plain), "not a test", "other methods are not tests")
	var script := FileAccess.get_file_as_string("res://tools/check_soak.sh")
	check(script.contains("bounded 3600 \"$GODOT\" --headless --path . --script res://tests/run_tests.gd -- --soak \"$@\""),
		"check_soak.sh runs the soak tier under a 3600 s limit, passing its flags on")
	check(script.contains("bounded 600 \"$GODOT\" --headless --path . --import"), "after an import")
	check(script.contains("if [ $# -gt 0 ] && [ \"${1#--}\" = \"$1\" ]; then"), "a first argument that is a flag is not taken for the Godot path")
	var ci := FileAccess.get_file_as_string("res://.github/workflows/ci.yml")
	check(_ci_job(ci, "soak").is_empty(), "the one soak job is split in two")
	var lists := {}
	for job in SOAK_JOBS:
		var body := _ci_job(ci, job)
		check(not body.is_empty(), "CI has a job named %s" % job)
		check(body.contains("timeout-minutes: 75"), "%s: a 75-minute backstop" % job)
		check(not body.contains("needs:"), "%s: in parallel with test-and-export" % job)
		var flag: String = SOAK_JOBS[job]
		var at := body.find("run: tools/check_soak.sh %s=" % flag)
		check(at >= 0, "%s runs tools/check_soak.sh %s=" % [job, flag])
		if at >= 0:
			var line := body.substr(at).get_slice("\n", 0)
			lists[job] = line.trim_prefix("run: tools/check_soak.sh %s=" % flag).strip_edges()
	check_eq(str(lists.get("soak-a", "")), SOAK_A_FILES, "soak-a runs the endless gates and cost cases (B-14)")
	check_eq(str(lists.get("soak-b", "")), SOAK_A_FILES, "soak-b skips exactly the files soak-a runs")
	check(not FileAccess.get_file_as_string("res://tools/check.sh").contains("--soak"), "check.sh leaves the soak tier to its jobs")


## --skip=a,b (B-14) leaves those files out; a name in --only or --skip that matches no file fails the
## run; and soak-a's and soak-b's flags take every test file exactly once between them.
func test_skip_leaves_out_its_files_and_the_soak_jobs_split_every_file_once() -> void:
	var skip := Runner._flags(PackedStringArray(["--skip=test_a, test_b.gd", "--skip-slow"]))
	check_eq(skip.skip, PackedStringArray(["test_a", "test_b"]), "--skip parses, with or without .gd")
	check(skip.skip_slow and skip.only.is_empty(), "--skip-slow is not a --skip list")
	var plain := Runner._flags(PackedStringArray([]))
	check(plain.skip.is_empty() and Runner.file_selected("test_a", plain), "no flag: every file runs")
	check(not Runner.file_selected("test_a", skip) and not Runner.file_selected("test_b", skip), "a skipped file does not run")
	check(Runner.file_selected("test_c", skip), "the others do")
	var both := Runner._flags(PackedStringArray(["--only=test_a,test_c", "--skip=test_a"]))
	check(not Runner.file_selected("test_a", both), "a file in both lists is skipped")
	check(Runner.file_selected("test_c", both) and not Runner.file_selected("test_d", both), "--only still limits the run")
	var files := PackedStringArray(["test_a.gd", "test_c.gd"])
	check_eq(Runner.flag_problems(files, both), PackedStringArray(), "names that match files are fine")
	check_eq(Runner.flag_problems(files, skip), PackedStringArray(["--skip: there is no tests/test_b.gd"]), "a misspelt --skip name fails")
	var typo := Runner._flags(PackedStringArray(["--only=test_x"]))
	check_eq(Runner.flag_problems(files, typo), PackedStringArray(["--only: there is no tests/test_x.gd"]), "so does a misspelt --only name")
	var a := Runner._flags(PackedStringArray(["--soak", "--only=" + SOAK_A_FILES]))
	var b := Runner._flags(PackedStringArray(["--soak", "--skip=" + SOAK_A_FILES]))
	var all := DirAccess.get_files_at("res://tests")
	check_eq(Runner.flag_problems(all, a), PackedStringArray(), "every file soak-a names exists")
	var counted := 0
	for file in all:
		if file.begins_with("test_") and file.ends_with(".gd") and file != "test_case.gd":
			counted += 1
			var name := file.get_basename()
			check(Runner.file_selected(name, a) != Runner.file_selected(name, b), "%s runs in exactly one soak job" % name)
	check(counted > 10, "the split was checked over the test files (%d)" % counted)


## G20 (build plan B-13): the unit suite's limit in tools/check.sh is 1200 s and CI's test-and-export
## job times out after 40 minutes, holding the S1 fast (+48 s) and slow (+150 s) budgets.
func test_the_suite_limit_and_the_ci_timeout_hold_the_s1_budgets() -> void:
	var check_sh := FileAccess.get_file_as_string("res://tools/check.sh")
	check(check_sh.contains("\nbounded 1200 \"$GODOT\" --headless --path . --script res://tests/run_tests.gd\n"),
		"check.sh runs the unit suite under a 1200 s limit")
	check(not check_sh.contains("bounded 900 "), "and no longer under 900 s")
	var job := _ci_job(FileAccess.get_file_as_string("res://.github/workflows/ci.yml"), "test-and-export")
	check(job.contains("run: tools/check.sh"), "test-and-export runs tools/check.sh")
	check(job.contains("\n    timeout-minutes: 40\n"), "test-and-export times out after 40 minutes")


## The text of CI job `name` (from its key to the next job), or "".
static func _ci_job(ci: String, name: String) -> String:
	var start := ci.find("\n  %s:\n" % name)
	if start < 0:
		return ""
	var body := ci.substr(start + 1)
	var lines := body.split("\n")
	var out := PackedStringArray([lines[0]])
	for k in range(1, lines.size()):
		var line: String = lines[k]
		if line.length() > 2 and line.begins_with("  ") and line[2] != " ":
			break
		out.append(line)
	return "\n".join(out)
