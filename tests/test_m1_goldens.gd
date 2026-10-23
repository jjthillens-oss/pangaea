extends TestCase
## The golden M1 hashes (endless plan D.4; S1 gate G1): pool mode stays bit-identical while the
## endless world is built beside it. Every scenario of tests/m1_scenarios.gd, re-run here, must give
## the state hash and the SHA-256 of the snapshot string recorded in tests/fixtures/m1_goldens.json.
## Tiers: seed 401 at 600 and 3,600 ticks is fast; seeds 402, 4242 and 77 are slow (in
## tools/check.sh); every seed at 18,000 ticks is soak (tools/check_soak.sh). A failure here is a
## pool-mode change: fix the change, never the file.

const Scenarios := preload("res://tests/m1_scenarios.gd")

const FAST_SEED := 401
const SLOW_SEEDS: Array[int] = [402, 4242, 77]
const SHORT_TICKS: Array[int] = [600, 3600]


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
