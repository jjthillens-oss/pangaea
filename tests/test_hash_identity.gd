extends TestCase
## S2G1, hash identity (S2 build plan BP-13 and BP-6; s2-sim T0.2): S2 changes neither pool mode
## nor, with growth off, the endless world at size 1.
##  - The M1 scenarios (tests/m1_scenarios.gd) hash as the E0 goldens (tests/fixtures/m1_goldens.json)
##    with the relationship rules of creatures_m1.json's "relationships" block (D-18) switched every
##    way the tiers name: every rule off at once (fast: seed 401, the three scenarios, 600 ticks);
##    each rule alone on and each alone off (slow: seed 401, 3,600 ticks); every rule off at seeds
##    402, 4242 and 77 (soak: 18,000 ticks). Every rule on is test_m1_goldens' own fast case, since
##    the shipped data has every rule on (T1.7). The block's numbers are the data's once the catalog
##    reads the block (T1.5), the spine's (4.2) before; only the switches change.
##  - With growth off, the endless world is S1's: test_endless_gates' IDENTITY_RUNS hash as
##    tests/fixtures/endless_s1_hashes.json, recorded on the e2 base (T0.1b). Fast: every run at 600
##    ticks and the overdriven racer, the run that covers the most ground, at 3,600 too (all three to
##    3,600 cost about 5 s, over T0's fast share). Slow: every run at every recorded tick, to 18,000.
##    Gates.make_sim sets the growth switch on every call.
##  - S3G34 (S3 build plan BP3-2): S2's endless world, growth on, at start sizes 1 and 2, hashes as
##    tests/fixtures/endless_s2_hashes.json, recorded on e3-base by T0.1 under the file's overrides
##    (test_endless_gates' IDENTITY_S2_RUNS). Fast: every run at 600 ticks. Slow: every recorded tick.
## Why it holds with the rules on: every M1 pair lies inside the block's shares, so each rule
## decides as M1 did. A fast case checks that pair by pair against the block's numbers. The M1
## scenarios alone cannot: their rammers and ambush hunters never come within sight of each other
## (on seeds 401, 402, 4242 and 77 over 18,000 ticks, a fear share of 1.19, s2-sim's S2G1 mutation
## under which the rammer, r 0.625, fears the ambush hunter, 0.75 >= 0.625 x 1.19, moves no hash).
## A slow control proves the switches reach the sim: the fear rule alone on at a share of 0.75,
## under which a rammer fears the cell (0.5 >= 0.625 x 0.75), must move both threat scenarios' hashes.

const Scenarios := preload("res://tests/m1_scenarios.gd")
const Gates := preload("res://tests/test_endless_gates.gd")

## The switches of the block's "rules" (spine 4.2), one per relationship rule 1 to 5.
const RULES: PackedStringArray = ["prey_share", "intruder_share", "fear", "no_engage_above", "outgrown_hazards"]
## Spine 4.2's block, used for its numbers until creatures_m1.json carries the block (T1.7).
const SPINE_BLOCK := {"rules": {"prey_share": true, "intruder_share": true, "fear": true, "no_engage_above": true,
	"outgrown_hazards": true}, "prey_share": 1.0, "intruder_max_radius_share": 1.2, "fear_radius_share": 1.25,
	"tolerance": 1e-6}
const FAST_SEED := 401
const FAST_TICKS: Array[int] = [600]
const SLOW_TICKS: Array[int] = [3600]
const SOAK_SEEDS: Array[int] = [402, 4242, 77]
const SOAK_TICKS: Array[int] = [18000]
const ENDLESS_FAST_TICKS := {"swim_hunter": [600], "swim_racer": [600, 3600], "circle_hunter": [600]}
const CONTROL_FEAR_SHARE := 0.75
const CONTROL_TICKS: Array[int] = [600]
const STARTING_BODIES: PackedStringArray = ["grazer", "hunter", "omnivore"]


## The data's relationships block (the spine's while the catalog has none), with each rule's switch
## taken from `on` (rule -> bool; a rule not named is off).
static func block_with(on: Dictionary) -> Dictionary:
	var block := data_block()
	var rules := {}
	for r in RULES:
		rules[r] = bool(on.get(r, false))
	block["rules"] = rules
	return block


## creatures_m1.json's relationships block as the catalog reads it, or SPINE_BLOCK before it does.
static func data_block() -> Dictionary:
	var species := SpeciesCatalog.load_from()
	if species.has_method("relationships_cfg"):
		var block: Dictionary = species.call("relationships_cfg")
		if not block.is_empty():
			return block.duplicate(true)
	return SPINE_BLOCK.duplicate(true)


## Every rule set to `value` except `but`, which gets the other value.
static func rules_all(value: bool, but := "") -> Dictionary:
	var out := {}
	for r in RULES:
		out[r] = value != (r == but)
	return out


func _check_m1(seeds: Array[int], ticks: Array[int], on: Dictionary, label: String) -> void:
	var goldens := Scenarios.load_goldens()
	check(not goldens.is_empty(), "the goldens file loads")
	var block := block_with(on)
	for scenario in Scenarios.SCENARIOS:
		for seed_value in seeds:
			var records := Scenarios.run(scenario, seed_value, ticks, block)
			check_eq(records.size(), ticks.size(), "%s: %s seed %d: a record per tick count" % [label, scenario, seed_value])
			for r in records:
				var why := Scenarios.difference(r, Scenarios.golden(goldens, scenario, seed_value, r.tick))
				check(why.is_empty(), "%s: %s" % [label, why])


## Runs every identity run to the tick counts `ticks` names for it (run name -> Array of ints).
func _check_endless(ticks: Dictionary) -> void:
	var waiting := Gates.missing(Gates.SIM)
	check(waiting.is_empty(), "an endless sim can be made (%s)" % "; ".join(waiting))
	check_eq(Gates.content_path(), Gates.REAL_WORLD, "the gates run on the real content, as the file was recorded")
	if not waiting.is_empty():
		return
	var file := Gates.identity_file()
	check(not file.is_empty(), "the identity file loads")
	var recorded := {}
	for r in file.get("runs", []):
		recorded[str(r.get("name", ""))] = r.get("hashes", {})
	for run in Gates.IDENTITY_RUNS:
		var at: Array[int] = []
		at.assign(ticks.get(run.name, []))
		check(not at.is_empty(), "%s is run" % run.name)
		var got := Gates.identity_run(run, at)
		var want: Dictionary = recorded.get(run.name, {})
		for n in at:
			check_eq(str(got.get(str(n), "")), str(want.get(str(n), "?")), "%s at %d ticks with growth off hashes as S1 (%s)" % [
				run.name, n, file.get("base_commit", "")])


## S3G34: runs every S3 identity run to the tick counts `at` and compares each with the file.
func _check_endless_s2(at: Array[int]) -> void:
	var waiting := Gates.missing(Gates.SIM)
	check(waiting.is_empty(), "an endless sim can be made (%s)" % "; ".join(waiting))
	check_eq(Gates.content_path(), Gates.REAL_WORLD, "the gates run on the real content, as the file was recorded")
	if not waiting.is_empty():
		return
	var file := Gates.identity_file(Gates.IDENTITY_S2_PATH)
	check(not file.is_empty(), "the S2 identity file loads")
	var recorded := {}
	for r in file.get("runs", []):
		recorded[str(r.get("name", ""))] = r.get("hashes", {})
	for run in Gates.IDENTITY_S2_RUNS:
		var got := Gates.identity_run_s2(run, at)
		var want: Dictionary = recorded.get(run.name, {})
		for n in at:
			check_eq(str(got.get(str(n), "")), str(want.get(str(n), "?")), "%s at %d ticks hashes as on e3-base (%s)" % [
				run.name, n, file.get("base_commit", "")])


# ---- Fast ----

func test_with_every_relationship_rule_off_the_m1_scenarios_hash_as_their_goldens() -> void:
	_check_m1([FAST_SEED], FAST_TICKS, rules_all(false), "every rule off")


func test_with_growth_off_the_endless_world_hashes_as_s1_at_600_and_3600_ticks() -> void:
	_check_endless(ENDLESS_FAST_TICKS)


func test_s2s_endless_world_at_sizes_1_and_2_hashes_as_on_e3_base_at_600_ticks() -> void:
	_check_endless_s2([600])


## BP-6: the gate content is shared, so make_sim sets the switch on every call, and the default is off.
## Once PoolSim carries growth (T2.1), it exists exactly when the switch is on (D-46).
func test_make_sim_sets_the_growth_switch_on_every_call() -> void:
	if not Gates.missing(Gates.SIM).is_empty():
		check(false, "an endless sim can be made: %s" % "; ".join(Gates.missing(Gates.SIM)))
		return
	var switches: Dictionary = Gates.data().content.config.switches
	var on: Variant = Gates.make_sim("hunter", FAST_SEED, true)
	check_eq(switches.get("growth"), true, "growth on")
	var off: Variant = Gates.make_sim("hunter", FAST_SEED)
	check_eq(switches.get("growth"), false, "the next call with the default turns it off again")
	if "growth" in off:
		check(off.get("growth") == null, "with growth off the sim has no Growth")
		check(on.get("growth") != null, "with growth on it has one")
	else:
		print("test-hash-identity: PoolSim has no growth yet (T2.1); only the switch is checked")


## Every M1 pair lies inside the shares of the block (s2-sim 0.8), which is why the M1 goldens hold
## with the rules on: no M1 creature fears another body (rule 3), an ambush brain preys on exactly
## the bodies M1's prey_max_radius_share gave it (rule 1), a territorial brain takes exactly M1's
## intruders (rule 2), and no M1 body is above a brain's engage share (rule 4). The bodies are the M1
## species (those with pool sites) and the three starting cells, at their M1 radii.
func test_every_m1_pair_lies_inside_the_relationship_shares() -> void:
	var species := SpeciesCatalog.load_from()
	var catalog := PartCatalog.load_from()
	var block := block_with(rules_all(true))
	var tol := float(block.tolerance)
	var radii := {}
	var m1 := PackedStringArray()
	for id in species.species_ids():
		if not species.sites_of(id).is_empty():
			m1.append(id)
			radii[id] = species.phenotype(id, catalog).radius
	for body in STARTING_BODIES:
		var g: Genome = Lineage.found(FAST_SEED, Scenarios.BUILD_ID, catalog, body).save.genome
		radii["the %s cell" % body] = Phenotype.derive(g, catalog).radius
	check(m1.has("ambush_hunter") and m1.has("rammer"), "the M1 species are there (%s)" % ", ".join(m1))
	for id in m1:
		var data: Dictionary = species.species[id]
		var own := float(radii[id])
		var behavior := species.behavior_of(id)
		for other in radii:
			if other == id:
				continue
			var r := float(radii[other])
			var pair := "%s (r %.4f) and %s (r %.4f)" % [id, own, other, r]
			check(not Relationships.fears(float(block.fear_radius_share), own, r, tol), "%s: no fear (rule 3)" % pair)
			if behavior == "ambush":
				var m1_prey := r <= own * float(data.get("prey_max_radius_share", InteractionResolver.BITE_SIZE_LIMIT))
				check_eq(Relationships.can_prey(float(block.prey_share), own, r, tol), m1_prey, "%s: prey as in M1 (rule 1)" % pair)
				check(not Relationships.above_engage(float(block.prey_share), own, r, tol), "%s: engages as in M1 (rule 4)" % pair)
			elif behavior == "territorial":
				var min_r := float(data.get("intruder_min_radius", 0.0))
				check_eq(Relationships.is_intruder(min_r, float(block.intruder_max_radius_share), own, r, tol), r >= min_r,
					"%s: intruder as in M1 (rule 2)" % pair)
				check(not Relationships.above_engage(float(block.intruder_max_radius_share), own, r, tol),
					"%s: engages as in M1 (rule 4)" % pair)
			else:
				check(false, "%s: an M1 behaviour the rules know (%s)" % [id, behavior])


func test_the_rule_tables_switch_one_rule_at_a_time() -> void:
	check_eq(rules_all(false).values().count(true), 0, "every rule off")
	for r in RULES:
		var alone_on := rules_all(false, r)
		var alone_off := rules_all(true, r)
		check(alone_on[r] and alone_on.values().count(true) == 1, "%s alone on" % r)
		check(not alone_off[r] and alone_off.values().count(false) == 1, "%s alone off" % r)
		check_eq(block_with(alone_on).rules, alone_on, "%s: the block carries the switches" % r)
	var block := block_with({})
	for key in ["prey_share", "intruder_max_radius_share", "fear_radius_share", "tolerance"]:
		check(block.has(key), "the block has %s" % key)


# ---- Slow ----

## The control: a switch the rules read reaches the sim. With the fear rule alone on at a share of
## 0.75, a rammer fears the cell, and both threat scenarios move off their goldens.
func test_slow_a_fear_share_of_0_75_moves_the_threat_scenarios_off_their_goldens() -> void:
	var goldens := Scenarios.load_goldens()
	var block := block_with(rules_all(false, "fear"))
	block["fear_radius_share"] = CONTROL_FEAR_SHARE
	var moved := PackedStringArray()
	for scenario in ["threats_forage", "threats_kiter"]:
		for r in Scenarios.run(scenario, FAST_SEED, CONTROL_TICKS, block):
			if not Scenarios.difference(r, Scenarios.golden(goldens, scenario, FAST_SEED, r.tick)).is_empty():
				moved.append("%s at %d" % [scenario, r.tick])
	print("test-hash-identity: fear share %.2f moves %s" % [CONTROL_FEAR_SHARE, ", ".join(moved) if not moved.is_empty() else "nothing"])
	check_eq(moved.size(), 2, "a fear share of %.2f changes both threat scenarios, so the switches reach the sim" % CONTROL_FEAR_SHARE)


func test_slow_each_relationship_rule_alone_on_and_alone_off_the_m1_scenarios_hash_as_their_goldens() -> void:
	for r in RULES:
		_check_m1([FAST_SEED], SLOW_TICKS, rules_all(false, r), "%s alone on" % r)
		_check_m1([FAST_SEED], SLOW_TICKS, rules_all(true, r), "%s alone off" % r)


func test_slow_with_growth_off_the_endless_world_hashes_as_s1_to_18000_ticks() -> void:
	var every := {}
	for run in Gates.IDENTITY_RUNS:
		every[run.name] = Gates.IDENTITY_TICKS
	_check_endless(every)


func test_slow_s2s_endless_world_at_sizes_1_and_2_hashes_as_on_e3_base_to_18000_ticks() -> void:
	_check_endless_s2(Gates.IDENTITY_TICKS)


# ---- Soak ----

func test_soak_with_every_relationship_rule_off_the_m1_scenarios_hash_as_their_goldens_at_three_seeds() -> void:
	_check_m1(SOAK_SEEDS, SOAK_TICKS, rules_all(false), "every rule off")
