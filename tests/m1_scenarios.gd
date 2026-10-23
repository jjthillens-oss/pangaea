extends RefCounted
## Test helper (not a test file): the golden M1 scenarios (endless plan D.4; S1 spine T0.2). Each is
## the game's own start, a new omnivore lineage at the layout spawn, run by a dev bot for a fixed
## number of ticks:
##   pool:            the step 2 pool, no creatures, driven by ForageBot (as test_pool_sim's
##                    same-seed test drives it);
##   threats_forage:  the step 3 pool with its creatures, driven by ForageBot;
##   threats_kiter:   the same pool driven by KiterBot (seeded with the world seed), which circles
##                    the creatures so chases, tells, strikes and kills all play out.
## A golden record is {scenario, seed, tick, hash, sha256}: PoolSim.state_hash() (the engine's
## hash() of the snapshot string) and the SHA-256 of that same string,
## JSON.stringify(snapshot(), "", true, true) (pool_sim.gd state_hash). Two numbers per record,
## so an engine upgrade that changes hash() is told apart from a change in the sim.
##
## Pool mode stays bit-identical through S1: tests/test_m1_goldens.gd compares every scenario with
## tests/fixtures/m1_goldens.json, which tools/godot/record_goldens.gd wrote. The file is never
## re-recorded to make a change pass; a differing golden is a pool-mode change.
##
##     const Scenarios := preload("res://tests/m1_scenarios.gd")
##     var records := Scenarios.run("threats_kiter", 401, [600, 3600])

const ForageBot := preload("res://game/dev/forage_bot.gd")
const KiterBot := preload("res://game/dev/kiter_bot.gd")

const GOLDENS_PATH := "res://tests/fixtures/m1_goldens.json"
const SCHEMA_VERSION := 1
const SCENARIOS: PackedStringArray = ["pool", "threats_forage", "threats_kiter"]
const SEEDS: Array[int] = [401, 402, 4242, 77]
const TICKS: Array[int] = [600, 3600, 18000]
const BODY := "omnivore"
const BUILD_ID := "test+dev"
## The command that re-records the file (only when the engine's hash() changed and the sha256 did not).
const RECORD_COMMAND := "godot --headless --path . --script res://tools/godot/record_goldens.gd -- --out=res://tests/fixtures/m1_goldens.json --commit=<sha>"


## A new lineage at the layout spawn, as GameSession.start_new makes one: {"sim": PoolSim, "bot": Object}.
## With `relationships` (a creatures_m1.json "relationships" block, S2 D-18), every species' brain
## config is built from that block instead of the data's, as the catalog builds it, so a test can
## switch each relationship rule (S2G1, tests/test_hash_identity.gd). The step 2 pool has no species.
static func make(scenario: String, seed_value: int, relationships: Variant = null) -> Dictionary:
	assert(scenario in SCENARIOS, "unknown scenario %s" % scenario)
	var catalog := PartCatalog.load_from()
	var layout := PoolLayout.load_from()
	var r := Lineage.found(seed_value, BUILD_ID, catalog, BODY)
	var save: SaveGame = r.save
	save.player["position"] = PlaneSpace.to_save(layout.spawn)
	var species: SpeciesCatalog = null if scenario == "pool" else SpeciesCatalog.load_from()
	if species != null and relationships is Dictionary:
		for id in species.configs:
			species.configs[id] = CreatureBrain.config(id, species.species[id], species.ai, relationships)
	var sim := PoolSim.create(save, catalog, layout, species)
	var bot: Object = KiterBot.new(seed_value) if scenario == "threats_kiter" else ForageBot.new()
	return {"sim": sim, "bot": bot}


## The golden record of a sim as it stands.
static func record_of(scenario: String, seed_value: int, sim: PoolSim) -> Dictionary:
	return {"scenario": scenario, "seed": seed_value, "tick": sim.tick, "hash": sim.state_hash(),
		"sha256": JSON.stringify(sim.snapshot(), "", true, true).sha256_text()}


## Steps the scenario and returns a record after exactly each tick count in `at` (ascending).
## Events are drained every tick, as the game does; draining never changes the state.
## `relationships` as make().
static func run(scenario: String, seed_value: int, at: Array[int], relationships: Variant = null) -> Array[Dictionary]:
	var made := make(scenario, seed_value, relationships)
	var sim: PoolSim = made.sim
	var bot = made.bot
	var out: Array[Dictionary] = []
	var k := 0
	while k < at.size():
		sim.step(bot.next_intent(sim))
		sim.drain_events()
		if sim.tick == at[k]:
			out.append(record_of(scenario, seed_value, sim))
			k += 1
	return out


## The goldens file as parsed, or {} when it is missing or not a JSON object.
static func load_goldens(path: String = GOLDENS_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## The golden record for (scenario, seed, tick) in a parsed file, or {}.
static func golden(goldens: Dictionary, scenario: String, seed_value: int, tick: int) -> Dictionary:
	for g in goldens.get("hashes", []):
		if g is Dictionary and g.get("scenario") == scenario and int(g.get("seed", -1)) == seed_value and int(g.get("tick", -1)) == tick:
			return g
	return {}


## "" when `got` equals the golden record; else what differs. When only the engine hash differs,
## the message says so and names the re-record command.
static func difference(got: Dictionary, want: Dictionary) -> String:
	var where := "%s seed %d tick %d" % [got.scenario, got.seed, got.tick]
	if want.is_empty():
		return "%s: no golden record" % where
	var same_hash := int(want.get("hash", -1)) == int(got.hash)
	var same_sha := str(want.get("sha256", "")) == str(got.sha256)
	if same_hash and same_sha:
		return ""
	if same_sha:
		return "%s: engine hash changed; the sim string is unchanged (hash %d, golden %d). Re-record with %s" % [
			where, got.hash, int(want.hash), RECORD_COMMAND]
	return "%s: the pool-mode state differs from the golden (sha256 %s, golden %s; hash %d, golden %d)" % [
		where, str(got.sha256).left(12), str(want.get("sha256", "")).left(12), got.hash, int(want.get("hash", -1))]
