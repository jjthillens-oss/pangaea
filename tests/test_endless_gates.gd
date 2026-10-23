extends TestCase
## The endless world's soak gates (S1 spine T0.6, core 12.5; G8, G13, G16, G17), and the harness
## they share with tests/test_endless_cost.gd and tests/test_swim_bot.gd.
##
## They run on the real content once T4.3's tiles are in game/data/tiles/b0, on T1's fixture world
## (tests/fixtures/world/world_min.json) before that, and wait while neither is there or while a T2
## surface they read has not landed (gaps()). Each waits on the level it needs (missing()): SIM, an
## endless sim at home (make_sim); WORLD, also the stream's read API, teleport, rebase and the
## creatures' endless fields; ALL, also FuzzInvariants (T2.8, the last T2 commit the gates read).
## The 10 km hash, which reads no invariant, needs SIM; the other gates ALL. Waiting is not a pass
## for ever:
## test_the_gates_wait_only_on_what_has_not_landed fails once a gap's marker file is in the tree
## while the harness still misses the surface, and with nothing missing it runs a short swim through
## the harness, so the gates are known to run before their tier does.
##
## Seeds and points were written here before any run. The straight swims and the 10 km hash run
## overdriven (S1 build plan B-12): RACER, the fastest legal body (3 flagella at scale 2: 4.41 tm/s),
## with SwimBot.overdrive before every step, which sets the 6 tm/s cap (PoolLayout.MAX_SPEED) the
## gates are written for and keeps the energy full; no legal body reaches it, and the fastest
## starting body, the hunter, makes 3.26. Each also keeps one run of RACER as it is. The other gates
## use the bodies of the M1 gates they extend (docs/DECISIONS.md, S1 build decisions). Every gate
## prints its numbers.
##  - Straight swims (G8, G17): eight directions x 36,000 ticks overdriven, then RACER east for as
##    long, each with FuzzInvariants clean on every tick (12, 13, 16 and the restated M1 ones),
##    awake_overflow and chunk_waits 0; food_trimmed and evictions printed. An overdriven swim must
##    average more than RACER's own top speed, or it was not overdriven.
##  - A circle of 3 tm round a chunk corner for 36,000 ticks: no chunk_loaded after the first 600.
##  - #32 from home (M1's 3 seeds x 2 bodies) and from 10 points (2 bodies each), M1's thresholds.
##  - #33: a greedy camper in z_center, z_s and 4 tile zones no live reach disc covers, M1's checks.
##  - Hunter viability: from home on M1's 6 seeds (5 must pass) and from 10 points (9 must pass).
##  - F9: a starving grazer dropped at 30 points eats before it dies, every time.
##  - G13: two overdriven runs of a 10 km straight swim (100,000 ticks) give the same hashes and
##    snapshot strings throughout, and so do two runs of RACER as it is (about 136,000 ticks): a hash
##    needs two runs, so G13's racer run is a pair. Its mutation is T2's zone stream left unseeded.
## A #32 or hunter run from a point arrives there as a player does (arrive()): it swims in, hidden,
## from 100 tm out, so the sites round the point spawn while it is still far off. Dropped onto the
## point by a teleport it found the sea round it empty, since no site spawns within spawn_safe_m of
## the cell or in its view. In the sea HuntBot roams to find prey and frees itself from cracks
## between shells (game/dev/hunt_bot.gd; docs/DECISIONS.md, the S1 integration gate harness).
## The cell is hidden from the creatures (debug_set_hidden) where a gate is about streaming, not
## about threats, and kept fed (debug_set_energy) on the long swims.

const SwimBot := preload("res://game/dev/swim_bot.gd")
const ForageBot := preload("res://game/dev/forage_bot.gd")
const EvadeBot := preload("res://game/dev/evade_bot.gd")
const HuntBot := preload("res://game/dev/hunt_bot.gd")

## The surfaces the gates read, and the file whose arrival says each has landed.
const POOL_SIM_PATH := "res://game/systems/pool_sim.gd"
const CREATURE_FIELD_PATH := "res://game/systems/creature_field.gd"
const CONTENT_FILE := "res://game/systems/world/world_content.gd"     ## T1.1
const STREAM_FILE := "res://game/systems/world/world_stream.gd"       ## T2.1
const REBASE_FILE := "res://game/domain/rebase_shift.gd"              ## T2.4
const FUZZ_PATH := "res://tests/fuzz_invariants.gd"                   ## T2.8, the last T2 commit the gates read
const FIXTURE_WORLD := "res://tests/fixtures/world/world_min.json"    ## T1.7
const REAL_WORLD := "res://game/data/world_cell.json"                 ## WorldConfig.DEFAULT_PATH
const REAL_TILES := "res://game/data/tiles/b0"                        ## T4.3

## The levels a test can wait on (missing()), each needing the ones before it.
const SIM := 0                         ## make_sim: an endless sim at home on the content
const WORLD := 1                       ## also the stream's read API, teleport, rebase, creature fields
const ALL := 2                         ## also FuzzInvariants

const BUILD_ID := "test+dev"
const HOME := Vector2(0.0, 9.0)        ## the spawn, in am: what a new endless game writes to the save
const HOME_BLOCK_TM := 64.0            ## the home block is [-64, 64) squared
const RACER := "racer"                 ## make_sim's name for the fastest legal body
const FEED_BELOW := 0.5                ## keep_fed tops the cell up below this share of its capacity
const DEATH_NOTICE_TICKS := 90         ## a player reading the death notice before Continue (as M1)
const POINTS_HALF_TM := 2000.0         ## random points lie in [-2 km, 2 km] squared round home
## Arrival (arrive()): a run from a point starts this far out on a bearing drawn from seed
## ARRIVE_BEARING_SEED + its run seed, beyond the load ring (56 tm) from every site in view of the
## point, and swims in until this near it or the limit (about twice the slowest body's swim).
const ARRIVE_FROM_TM := 100.0
const ARRIVE_BEARING_SEED := 3210
const ARRIVE_WITHIN_TM := 2.0
const ARRIVE_LIMIT_TICKS := 6000
const ARRIVE_NEAR_TM := 10.0           ## a run that ends its arrival farther off than this fails

## Straight swims: each swim's ticks, and the distance it must at least cover so its invariants
## were checked on a moving cell (4 chunks; it prints what it covered). Eight overdriven directions,
## from east every 45 degrees, then one RACER swim as it is, east.
const SWIM_SEED := 6101
const SWIM_TICKS := 36000
const SWIM_MIN_TM := 128.0
const SWIM_DIRECTIONS := 8
const SWIM_RACER_HEADING := 0.0
## The corner circle: candidate corners (abs tm), the first whose circle is clear of shells is used.
const CIRCLE_SEED := 6102
const CIRCLE_CORNERS: Array[Vector2] = [Vector2(256, 256), Vector2(-256, 256), Vector2(256, -256),
	Vector2(-256, -256), Vector2(512, 0), Vector2(0, 512), Vector2(-512, 0), Vector2(0, -512)]
const CIRCLE_R := 3.0
const CIRCLE_LEAD := 0.6               ## rad: it aims this far ahead round the circle
const CIRCLE_THROTTLE := 0.6
const CIRCLE_TICKS := 36000
const CIRCLE_SETTLE_TICKS := 600
const CIRCLE_HOLD_TM := 8.0            ## it must stay this near the corner, or it was not circling it
## #32 (M1's constants, docs/DECISIONS.md "M1 step 3 review fixes: pressure").
const PRESSURE_SEEDS: Array[int] = [501, 502, 503]
const PRESSURE_BODIES: PackedStringArray = ["grazer", "omnivore"]
const PRESSURE_TICKS := 300 * 60
const PRESSURE_POINTS_SEED := 3202
const PRESSURE_POINT_RUN_SEED := 511   ## point i runs with seed 511 + i
const PRESSURE_MIN_MEETINGS_PER_MIN := 1.0
const PRESSURE_MAX_DEATHS_PER_5_MIN := 0.5
## #33 (M1's constants): z_center and z_s, plus CAMP_TILE_ZONES zones found from probe points.
const CAMP_SEED := 331
const CAMP_HOME_ZONES: PackedStringArray = ["z_center", "z_s"]
const CAMP_TILE_ZONES := 4
const CAMP_PROBE_SEED := 3203
const CAMP_PROBES := 40
const CAMP_PROBE_SETTLE_TICKS := 120   ## the stream loads round a probe point before it is read
const CAMP_PROBE_TM := 24.0            ## a probe takes the nearest qualifying zone within this
const CAMP_LIMIT_TICKS := 420 * 60
const CAMP_MIN_IN_ZONE_SHARE := 0.9
## Hunter viability (M1's #30 constants), from home and from points.
const HUNTER_SEEDS: Array[int] = [201, 202, 203, 204, 205, 206]
const HUNTER_PASSES_NEEDED := 5
const HUNTER_POINTS_SEED := 3204
const HUNTER_POINT_RUN_SEED := 211     ## point i runs with seed 211 + i
const HUNTER_POINTS := 10
const HUNTER_POINT_PASSES_NEEDED := 9  ## 5 of 6 for 10 runs, rounded up
const HUNTER_TICKS := 240 * 60
const HUNTER_MAX_THREAT_DEATHS := 1
const HUNTER_MIN_MEAT := 3
## F9: a grazer with no energy, hidden, dropped at each point; it starves to death in 20 s.
const STARVE_SEED := 901
const STARVE_POINTS_SEED := 3209
const STARVE_POINTS := 30
const STARVE_LIMIT_TICKS := 25 * 60
## G13: two runs of a 10 km straight swim, compared every TEN_KM_RECORD_EVERY ticks and at the end.
const TEN_KM_SEED := 1013
const TEN_KM_TM := 10000.0
const TEN_KM_HEADING := 0.25           ## rad: east-south-east, across tile rows and columns
const TEN_KM_RECORD_EVERY := 18000
## The endless identity (S2 build plan BP-6 and 7.5): with growth off, endless size 1 is S1's.
## tools/godot/record_endless_hashes.gd ran these on the e2 base into IDENTITY_PATH, and
## tests/test_hash_identity.gd runs them again (S2G1). Re-recording needs a docs/DECISIONS.md line
## that names the S1 change forcing it.
const IDENTITY_PATH := "res://tests/fixtures/endless_s1_hashes.json"
const IDENTITY_DRIVERS: PackedStringArray = ["swim", "swim_overdriven", "circle"]
const IDENTITY_RUNS: Array[Dictionary] = [
	{"name": "swim_hunter", "body": "hunter", "seed": SWIM_SEED, "driver": "swim"},
	{"name": "swim_racer", "body": RACER, "seed": SWIM_SEED, "driver": "swim_overdriven"},
	{"name": "circle_hunter", "body": "hunter", "seed": CIRCLE_SEED, "driver": "circle"}]
const IDENTITY_TICKS: Array[int] = [600, 3600, 18000]

## S2's growth gates (test_threat_fuzz's size-2 runner, test_endless_fuzz's growth fuzz,
## test_growth_gates, test_endless_cost's size-2 cases) wait on the S2 seams they read (S2 build plan
## 5.2), each named in S2_NEEDS, as the S1 gates wait on gaps(): s2_missing(needs) names what has not
## landed, and a gap is allowed only while its marker file is not in the tree ("" for a data check
## with no file of its own).
const S2_NEEDS := {
	"set_size": {"what": "the growth tick and PoolSim.debug_set_size and debug_force_growth (T2.5, T2.6)", "marker": "res://tests/test_fuzz_invariants.gd"},
	"fuzz_growth": {"what": "FuzzInvariants through a growth and a set_size cut (T2.6b)", "marker": "res://tests/test_fuzz_invariants.gd"},
	"blocker": {"what": "Growth.blocker_of (T2.3)", "marker": "res://game/systems/world/remnant_field.gd"},
	"remnants": {"what": "PoolSim.remnants (T2.4)", "marker": "res://game/systems/world/remnant_field.gd"},
	"size_two_species": {"what": "species that enter at size 2 (T1.7)", "marker": "res://tests/fixtures/creatures_posts_test.json"},
	"size_two_content": {"what": "the real content's size-2 sites (T3.5)", "marker": ""},
}


# ---- The harness (static, shared) ----

static var _data := {}


## What the gates still wait on, as [{"what", "marker", "need"}]; empty when they can run. A gap is
## allowed only while its marker file is not in the tree. "need" is the level (SIM, WORLD, ALL) that
## waits on it.
static func gaps() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var classes := _global_classes()
	if not classes.has("WorldContent"):
		out.append({"what": "WorldContent (T1.1)", "marker": CONTENT_FILE, "need": SIM})
	var sim_script := load(POOL_SIM_PATH) as GDScript
	var lacking := _lacking(sim_script, {"create": 5, "is_endless": 0, "absolute_position_am": 0}, ["world", "respawn_pending"])
	if not lacking.is_empty():
		out.append({"what": "PoolSim %s (T2.1)" % ", ".join(lacking), "marker": STREAM_FILE, "need": SIM})
	lacking = _lacking(sim_script, {"debug_rebase": 1, "debug_teleport_abs": 2}, [])
	if not lacking.is_empty():
		out.append({"what": "PoolSim %s (T2.4)" % ", ".join(lacking), "marker": REBASE_FILE, "need": WORLD})
	if not classes.has("WorldStream"):
		out.append({"what": "WorldStream (T2.1)", "marker": STREAM_FILE, "need": SIM})
	else:
		lacking = _lacking(load(classes.WorldStream) as GDScript, {"loaded_keys": 0, "chunk": 1, "local_of_abs": 2,
			"abs_of_local": 1, "view_set_keys": 1, "sleeping_ids": 0}, ["counters", "size"])
		if not lacking.is_empty():
			out.append({"what": "WorldStream %s (T2.2 to T2.6)" % ", ".join(lacking), "marker": FUZZ_PATH, "need": WORLD})
	lacking = _lacking(load(CREATURE_FIELD_PATH) as GDScript, {"awake": 0}, [])
	lacking.append_array(_lacking(CreatureField.Creature, {}, ["asleep", "think_slot", "spawn_count"]))
	if not lacking.is_empty():
		out.append({"what": "CreatureField %s (T2.5, T2.6)" % ", ".join(lacking), "marker": FUZZ_PATH, "need": WORLD})
	if not FileAccess.file_exists(FUZZ_PATH):
		out.append({"what": "tests/fuzz_invariants.gd (T2.8)", "marker": FUZZ_PATH, "need": ALL})
	else:
		lacking = _lacking(load(FUZZ_PATH) as GDScript, {"before": 1, "after": 5, "report": 0}, ["bad", "counts"])
		if not lacking.is_empty():
			out.append({"what": "FuzzInvariants %s (T2.8)" % ", ".join(lacking), "marker": FUZZ_PATH, "need": ALL})
	if content_path().is_empty():
		out.append({"what": "world content: the fixture world (T1.7) or the real tiles (T4.3)", "marker": FIXTURE_WORLD, "need": SIM})
	return out


## What a test that needs `need` (SIM, WORLD or ALL) waits on, in words; empty when it can run.
static func missing(need := ALL) -> PackedStringArray:
	var out := PackedStringArray()
	for g in gaps():
		if int(g.need) <= need:
			out.append(g.what)
	return out


## The S2 seams of `needs` (S2_NEEDS keys) that have not landed, in words; empty when the gate can
## run. The S1 levels it rests on (ALL) come first.
static func s2_missing(needs: PackedStringArray) -> PackedStringArray:
	var out := missing(ALL)
	if not out.is_empty():
		return out
	for need in needs:
		if not s2_has(need):
			out.append(str(S2_NEEDS[need].what))
	return out


## Whether the S2 seam `need` (an S2_NEEDS key) is in the tree.
static func s2_has(need: String) -> bool:
	var sim_script := load(POOL_SIM_PATH) as GDScript
	match need:
		"set_size":
			return _lacking(sim_script, {"debug_set_size": 1, "debug_force_growth": 0}, []).is_empty()
		"fuzz_growth":
			var fuzz: Variant = new_fuzz()
			fuzz.start_run()
			return (fuzz.counts as Dictionary).has("growths") and (fuzz.counts as Dictionary).has("set_sizes")
		"blocker":
			return _lacking(load("res://game/systems/world/growth.gd") as GDScript, {"blocker_of": 1}, []).is_empty()
		"remnants":
			return _lacking(sim_script, {}, ["remnants"]).is_empty()
		"size_two_species":
			return not species_entering_at(2).is_empty()
		"size_two_content":
			if content_path() != REAL_WORLD or species_entering_at(2).is_empty():
				return false
			var entering := species_entering_at(2)
			var content: Variant = data().content
			var sites: Array = content.home.sites.duplicate()
			for id in content.tiles.tiles:
				sites.append_array(content.tiles.tiles[id].sites)
			for site in sites:
				if entering.has(str(site.species)):
					return true
			return false
	push_error("Gates.s2_has: no seam '%s'" % need)
	return false


## The ids of the species whose entry size is `n`, sorted.
static func species_entering_at(n: int) -> PackedStringArray:
	var species: SpeciesCatalog = data().species
	var out := PackedStringArray()
	for id in species.species_ids():
		if species.entry_size(id) == n:
			out.append(id)
	out.sort()
	return out


## The world file the gates run on: the real one once its tiles are there, else the fixture world,
## else "".
static func content_path() -> String:
	if FileAccess.file_exists(REAL_WORLD) and DirAccess.dir_exists_absolute(REAL_TILES):
		for f in DirAccess.get_files_at(REAL_TILES):
			if f.ends_with(".json"):
				return REAL_WORLD
	if FileAccess.file_exists(FIXTURE_WORLD):
		return FIXTURE_WORLD
	return ""


## The data every gate sim shares, loaded once: {"catalog", "layout", "species", "content"}.
static func data() -> Dictionary:
	if _data.is_empty():
		var catalog := PartCatalog.load_from()
		var layout := PoolLayout.load_from()
		var species := SpeciesCatalog.load_from()
		var content_class := load(str(_global_classes().WorldContent)) as GDScript
		var content: Variant = content_class.call("load_from", content_path(), layout, species)
		_data = {"catalog": catalog, "layout": layout, "species": species, "content": content}
	return _data


## A new lineage of `body` (or RACER) in the endless world at home, as a new endless game starts,
## with the world's growth switch set to `growth` (S2 build plan BP-6). The content is shared by
## every gate sim, so each call sets the switch; S1's gates take the default and run with growth
## off, where endless size 1 is S1's (S2G1). Read only after missing() is empty.
static func make_sim(body: String, seed_value: int, growth := false) -> Variant:
	var d := data()
	d.content.config.switches["growth"] = growth
	var r := Lineage.found(seed_value, BUILD_ID, d.catalog, "hunter" if body == RACER else body)
	if body == RACER:
		make_racer(r.save.genome, d.catalog)
	r.save.player["position"] = PlaneSpace.to_save(HOME)
	var sim: Variant = (load(POOL_SIM_PATH) as GDScript).callv("create", [r.save, d.catalog, d.layout, d.species, d.content])
	sim.drain_events()
	return sim


## Makes `g` the fastest legal body: a jaw, and the most flagella the catalog allows at its largest
## scale, spread over the rear.
static func make_racer(g: Genome, catalog: PartCatalog) -> void:
	g.parts.clear()
	g.add_part("mouth_jaw", 0.0, 1.0)
	for k in catalog.max_count_of("flagellum"):
		var side := 1.0 if k % 2 == 0 else -1.0
		g.add_part("flagellum", side * (PI - ceili(k / 2.0) * 0.6), catalog.max_scale)


## Moves the cell to an absolute point (am) as the debug teleport does, and drains its events.
static func teleport(sim: Variant, at: PackedFloat64Array) -> bool:
	var ok: bool = sim.debug_teleport_abs(at[0], at[1])
	sim.drain_events()
	return ok


## Brings a cell made by make_sim to the absolute point `at` (am) as a player arrives there: placed
## ARRIVE_FROM_TM out on a bearing drawn from `seed_value`, it swims in with a homing SwimBot, hidden
## from the creatures and kept fed, until within ARRIVE_WITHIN_TM of the point or ARRIVE_LIMIT_TICKS.
## The sites round the point load and spawn while the cell is still far off, as they do for a player.
## A teleport onto the point instead keeps every site within spawn_safe_m of the cell, or in its
## view, from spawning for as long as the cell stays near (CreatureField.blocker_from), so the runs
## from points used to start in a sea emptied round the cell. The cell then shows itself again with
## the energy it had before. Returns {"placed", "ticks", "left_tm", "bearing"}.
static func arrive(sim: Variant, at: PackedFloat64Array, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = ARRIVE_BEARING_SEED + seed_value
	var bearing := rng.randf() * TAU
	var out := {"placed": false, "ticks": 0, "left_tm": INF, "bearing": bearing}
	var energy: float = sim.state.energy
	var from := Vector2.from_angle(bearing) * ARRIVE_FROM_TM
	if not teleport(sim, PackedFloat64Array([at[0] + from.x, at[1] + from.y])):
		return out
	out.placed = true
	sim.debug_set_hidden(true)
	var bot = SwimBot.toward(at)
	while int(out.ticks) < ARRIVE_LIMIT_TICKS and abs_distance(sim.absolute_position_am(), at) > ARRIVE_WITHIN_TM:
		keep_fed(sim)
		tick(sim, bot.next_intent(sim))
		out.ticks += 1
	out.left_tm = abs_distance(sim.absolute_position_am(), at)
	sim.debug_set_hidden(false)
	sim.debug_set_energy(energy)
	sim.drain_events()
	return out


## Tops the cell's energy up to full when it is below FEED_BELOW of its capacity.
static func keep_fed(sim: Variant) -> void:
	if sim.state.energy < sim.state.energy_capacity * FEED_BELOW:
		sim.debug_set_energy(sim.state.energy_capacity)


## Before a step of a swim: overdriven, SwimBot.overdrive (6 tm/s, energy full; B-12); as it is,
## keep_fed.
static func drive(sim: Variant, overdriven: bool) -> void:
	if overdriven:
		SwimBot.overdrive(sim)
	else:
		keep_fed(sim)


## The corner circle's corner (abs tm): the first of CIRCLE_CORNERS whose CIRCLE_R circle is clear of
## colliders, with the cell teleported onto that circle; empty when none is.
static func circle_corner(sim: Variant) -> PackedFloat64Array:
	for c in CIRCLE_CORNERS:
		if not teleport(sim, PackedFloat64Array([c.x + CIRCLE_R, c.y])):
			continue
		var local: Vector2 = sim.world.local_of_abs(c.x, c.y)
		var clear := true
		for j in 16:
			clear = clear and sim.arena.is_clear(local + Vector2.from_angle(j * PI / 8.0) * CIRCLE_R, sim.phenotype.radius + 0.3)
		if clear:
			return PackedFloat64Array([c.x, c.y])
	return PackedFloat64Array()


## The intent that keeps the cell circling `corner` (abs tm): aimed CIRCLE_LEAD ahead round the circle.
static func circle_intent(sim: Variant, corner: PackedFloat64Array) -> SimIntent:
	var c: Vector2 = sim.world.local_of_abs(corner[0], corner[1])
	var to: Vector2 = c + Vector2.from_angle((sim.motion.position - c).angle() + CIRCLE_LEAD) * CIRCLE_R - sim.motion.position
	return SimIntent.new(to.normalized() * CIRCLE_THROTTLE if to.length() > 1e-6 else Vector2.ZERO)


## One endless identity run (S2 build plan 7.5) from make_sim, driven as the S1 gates drive theirs:
## "swim" and "swim_overdriven" as the straight swims (east, hidden, keep_fed or overdriven), "circle"
## as the corner circle. Returns {"<ticks>": "<state_hash() in decimal>"} after exactly each step
## count in `at` (ascending), or {} when a circle finds no clear corner.
static func identity_run(run: Dictionary, at: Array[int]) -> Dictionary:
	var sim: Variant = make_sim(str(run.body), int(run.seed))
	sim.debug_set_hidden(true)
	var driver := str(run.driver)
	assert(driver in IDENTITY_DRIVERS, "unknown identity driver %s" % driver)
	var corner := PackedFloat64Array()
	if driver == "circle":
		corner = circle_corner(sim)
		if corner.is_empty():
			return {}
	var bot = SwimBot.new(Vector2.from_angle(SWIM_RACER_HEADING))
	var out := {}
	var steps := 0
	for n in at:
		while steps < n:
			drive(sim, driver == "swim_overdriven")
			tick(sim, circle_intent(sim, corner) if driver == "circle" else bot.next_intent(sim))
			steps += 1
		out[str(n)] = str(sim.state_hash())
	return out


## The identity file as parsed, or {} when it is missing or not a JSON object.
static func identity_file(path: String = IDENTITY_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## A FuzzInvariants for the real species and layout.
static func new_fuzz() -> Variant:
	var d := data()
	return (load(FUZZ_PATH) as GDScript).new(d.species, d.layout)


## Steps `sim` once with `intent` and returns the tick's events; with `fuzz`, checks them.
static func tick(sim: Variant, intent: SimIntent, fuzz: Variant = null, where: String = "") -> Array[Dictionary]:
	var t: int = sim.tick
	var was: Dictionary = fuzz.before(sim) if fuzz != null else {}
	sim.step(intent)
	var events: Array[Dictionary] = sim.drain_events()
	if fuzz != null:
		fuzz.after(sim, events, t, where, was)
	return events


## Continues a dead cell at its checkpoint once the death notice has shown, as a player pressing
## Continue would. Call before each step; `dead` keeps {"since"}. Returns events the call made.
static func continue_after_death(sim: Variant, dead: Dictionary, fuzz: Variant = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not sim.dead:
		dead.since = -1
		return out
	if int(dead.get("since", -1)) < 0:
		dead.since = sim.tick
		return out
	if sim.tick - int(dead.since) < DEATH_NOTICE_TICKS or sim.respawn_pending:
		return out
	var t: int = sim.tick
	var was: Dictionary = fuzz.before(sim) if fuzz != null else {}
	sim.respawn_player()
	out = sim.drain_events()
	if fuzz != null and not out.is_empty():
		fuzz.after(sim, out, t, "respawn at %d" % t, was)
	dead.since = -1
	return out


## `n` points in [-half, half] squared (abs tm), from a seeded generator.
static func random_points(seed_value: int, n: int, half: float = POINTS_HALF_TM) -> Array[PackedFloat64Array]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array[PackedFloat64Array] = []
	for i in n:
		var x := rng.randf_range(-half, half)
		var y := rng.randf_range(-half, half)
		out.append(PackedFloat64Array([x, y]))
	return out


## The distance between two absolute points, in float64.
static func abs_distance(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]))


## The loaded zone whose absolute centre is `at` (within 1 cm), or {}.
static func zone_at(sim: Variant, at: PackedFloat64Array) -> Dictionary:
	for z in sim.region.zones:
		var c: PackedFloat64Array = sim.world.abs_of_local(z.center)
		if absf(c[0] - at[0]) < 0.01 and absf(c[1] - at[1]) < 0.01:
			return z
	return {}


## Whether a point (the cell's frame) lies inside any of `discs` ({"center", "radius"}).
static func covered(p: Vector2, discs: Array) -> bool:
	for disc in discs:
		if p.distance_to(disc.center) < float(disc.radius):
			return true
	return false


## Every global class name -> its script path.
static func _global_classes() -> Dictionary:
	var out := {}
	for c in ProjectSettings.get_global_class_list():
		out[str(c["class"])] = str(c.path)
	return out


## The names of `methods` (name -> least argument count) and `properties` that `script` lacks.
static func _lacking(script: GDScript, methods: Dictionary, properties: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var have := {}
	for m in script.get_script_method_list():
		have[str(m.name)] = maxi(int(have.get(str(m.name), 0)), (m.args as Array).size())
	for name in methods:
		if not have.has(name) or int(have[name]) < int(methods[name]):
			out.append("%s()" % name)
	var props := {}
	for p in script.get_script_property_list():
		props[str(p.name)] = true
	for name in properties:
		if not props.has(name):
			out.append(name)
	return out


# ---- Fast: the harness itself ----

func _waits(gate: String, need := ALL) -> bool:
	var what := missing(need)
	if what.is_empty():
		return false
	print("test-endless-gates: %s waits on: %s" % [gate, "; ".join(what)])
	return true


## A gap is allowed only while its dependency has not landed; with none, the content loads clean
## and a short swim runs through the harness with the invariants on.
func test_the_gates_wait_only_on_what_has_not_landed() -> void:
	var waiting := gaps()
	for g in waiting:
		check(not FileAccess.file_exists(g.marker), "%s is in the tree, so %s has landed, but the harness still misses it" % [
			g.marker, g.what])
	if not waiting.is_empty():
		print("test-endless-gates: the gates wait on: %s" % "; ".join(missing()))
		return
	var d := data()
	var problems: PackedStringArray = d.content.problems(d.catalog, d.species)
	check(problems.is_empty(), "the world content %s has no problems: %s" % [content_path(), problems])
	var sim: Variant = make_sim(RACER, SWIM_SEED)
	check(sim.is_endless(), "the sim is endless")
	sim.debug_set_hidden(true)
	var fuzz: Variant = new_fuzz()
	var start: PackedFloat64Array = sim.absolute_position_am()
	var bot = SwimBot.new(Vector2.RIGHT)
	for i in 120:
		tick(sim, bot.next_intent(sim), fuzz, "harness tick %d" % sim.tick)
	var end: PackedFloat64Array = sim.absolute_position_am()
	check(end[0] - start[0] > 3.0, "the cell swam east (%.2f tm)" % (end[0] - start[0]))
	check(not sim.world.loaded_keys().is_empty(), "chunks are loaded")
	check_eq(str(fuzz.report()), "", "the invariants hold on the harness swim")
	check_eq(int(sim.world.counters.awake_overflow) + int(sim.world.counters.chunk_waits), 0, "no overflow and no chunk waits")
	print("test-endless-gates: the harness ran on %s: %d chunks loaded, %.1f tm east in 120 ticks" % [
		content_path(), sim.world.loaded_keys().size(), end[0] - start[0]])


## S2's seams: each gap is allowed only while its marker file is not in the tree, and the waits
## name what they wait on.
func test_the_s2_gates_wait_only_on_what_has_not_landed() -> void:
	if _waits("the S2 seams check", ALL):
		return
	var waiting := PackedStringArray()
	for need in S2_NEEDS:
		var marker := str(S2_NEEDS[need].marker)
		if s2_has(need):
			continue
		waiting.append(str(S2_NEEDS[need].what))
		check(marker.is_empty() or not FileAccess.file_exists(marker), "%s is in the tree, so %s has landed, but the harness misses it" % [
			marker, S2_NEEDS[need].what])
	check_eq(s2_missing(PackedStringArray(S2_NEEDS.keys())), waiting, "s2_missing names every missing seam")
	print("test-endless-gates: the S2 gates wait on: %s" % ("nothing" if waiting.is_empty() else "; ".join(waiting)))


## The swim body is the fastest legal one: legal, faster than every starting body, and no part could
## be added or scaled up.
func test_the_racer_is_the_fastest_legal_body() -> void:
	var catalog := PartCatalog.load_from()
	var r := Lineage.found(SWIM_SEED, BUILD_ID, catalog, "hunter")
	var g: Genome = r.save.genome
	make_racer(g, catalog)
	check_eq(r.save.validate(catalog), PackedStringArray(), "the racer is a legal body")
	var speed := Phenotype.derive(g, catalog).speed
	for body in ["grazer", "hunter", "omnivore"]:
		var start := Lineage.found(SWIM_SEED, BUILD_ID, catalog, body)
		check(speed > Phenotype.derive(start.save.genome, catalog).speed, "the racer is faster than the %s" % body)
	var more := Lineage.found(SWIM_SEED, BUILD_ID, catalog, "hunter")
	make_racer(more.save.genome, catalog)
	more.save.genome.add_part("flagellum", 0.0, 1.0)
	check(not more.save.validate(catalog).is_empty(), "a fourth flagellum is not legal")
	for part in g.parts:
		check_eq(float(part.scale), catalog.max_scale if part.type == "flagellum" else 1.0, "%s at its scale" % part.type)
	check(speed < PoolLayout.MAX_SPEED, "no body reaches the cap (the gates print the speed they swim at)")
	print("test-endless-gates: the racer swims at %.3f tm/s (the cap is %.1f)" % [speed, PoolLayout.MAX_SPEED])


## Core Q3 (S1 build plan section 3): the endless #33 camper skips the guarded M1 zones, as M1's #33
## does (tests/test_threat_gates.gd): its home zones are M1's camp zones, and no M1 site's territory
## zone (z_n, z_nw, z_ne: the rammers') is among them.
func test_the_endless_camper_skips_the_guarded_m1_zones() -> void:
	var m1: PackedStringArray = (load("res://tests/test_threat_gates.gd") as GDScript).get_script_constant_map().CAMP_ZONES
	var ours := CAMP_HOME_ZONES.duplicate()
	var theirs := m1.duplicate()
	ours.sort()
	theirs.sort()
	check_eq(ours, theirs, "the endless camper's home zones are M1's #33 zones")
	var guarded := PackedStringArray()
	for s in SpeciesCatalog.load_from().sites:
		if not str(s.territory_zone).is_empty() and not guarded.has(str(s.territory_zone)):
			guarded.append(str(s.territory_zone))
	check(guarded.has("z_n") and guarded.has("z_nw"), "z_n and z_nw are guarded in M1 (%s)" % ", ".join(guarded))
	for id in guarded:
		check(not CAMP_HOME_ZONES.has(id), "%s is a territory, so the camper skips it" % id)


## The identity file (S2 build plan 7.5) holds every run of IDENTITY_RUNS, as named there, with a
## decimal hash at every tick count of IDENTITY_TICKS, recorded on the real content with growth off
## at a named commit.
func test_the_endless_identity_file_holds_every_run_at_every_tick() -> void:
	var file := identity_file()
	check(not file.is_empty(), "%s is there and is a JSON object" % IDENTITY_PATH)
	check_eq(str(file.get("content", "")), REAL_WORLD, "recorded on the real content")
	check_eq(file.get("growth"), false, "recorded with growth off")
	check(str(file.get("base_commit", "")).length() == 40, "the base commit is a full sha (%s)" % file.get("base_commit"))
	var runs: Array = file.get("runs", [])
	check_eq(runs.size(), IDENTITY_RUNS.size(), "one record per run")
	for i in mini(runs.size(), IDENTITY_RUNS.size()):
		var want: Dictionary = IDENTITY_RUNS[i]
		var got: Dictionary = runs[i]
		for key in want:
			var g: Variant = got.get(key)   # JSON numbers read back as floats
			var same: bool = typeof(g) == TYPE_FLOAT and float(g) == float(want[key]) if want[key] is int else str(g) == str(want[key])
			check(same, "run %d %s: %s (want %s)" % [i, key, g, want[key]])
		var hashes: Dictionary = got.get("hashes", {})
		check_eq(hashes.size(), IDENTITY_TICKS.size(), "%s: a hash per tick count" % want.name)
		for n in IDENTITY_TICKS:
			var h := str(hashes.get(str(n), ""))
			check(h.is_valid_int() and int(h) >= 0, "%s tick %d: a decimal hash (%s)" % [want.name, n, h])


func test_random_points_repeat_and_stay_in_their_square() -> void:
	var a := random_points(77, 50, 100.0)
	var b := random_points(77, 50, 100.0)
	check_eq(a.size(), 50, "count")
	for i in a.size():
		check(a[i] == b[i], "point %d repeats" % i)
		check(absf(a[i][0]) <= 100.0 and absf(a[i][1]) <= 100.0, "point %d in the square" % i)
	check(random_points(78, 1, 100.0)[0] != a[0], "another seed, other points")
	check_eq(abs_distance(PackedFloat64Array([1000000.0, 3.0]), PackedFloat64Array([1000003.0, 7.0])), 5.0, "abs distance")


# ---- Soak: the gates ----

## Eight directions x 10 minutes overdriven, then RACER east as it is (G8, G17).
func test_soak_straight_swims_in_eight_directions_keep_the_invariants_and_counters() -> void:
	if _waits("straight swims"):
		return
	var racer_top := 0.0
	for k in SWIM_DIRECTIONS + 1:
		var overdriven := k < SWIM_DIRECTIONS
		var dir := Vector2.from_angle(k * TAU / SWIM_DIRECTIONS if overdriven else SWIM_RACER_HEADING)
		var where := "direction %d" % k if overdriven else "racer"
		var sim: Variant = make_sim(RACER, SWIM_SEED)
		racer_top = float(sim.phenotype.speed)
		sim.debug_set_hidden(true)
		var fuzz: Variant = new_fuzz()
		var bot = SwimBot.new(dir)
		var start: PackedFloat64Array = sim.absolute_position_am()
		var t0 := Time.get_ticks_msec()
		for i in SWIM_TICKS:
			drive(sim, overdriven)
			tick(sim, bot.next_intent(sim), fuzz, "%s tick %d" % [where, sim.tick])
		var dist := abs_distance(start, sim.absolute_position_am())
		var speed := dist / (SWIM_TICKS / 60.0)
		var c: Dictionary = sim.world.counters
		var report: String = fuzz.report()
		print("test-endless-gates: %s (%.0f deg, %s): %.0f tm in %d s, %.2f tm/s; awake_overflow %d, chunk_waits %d, food_trimmed %d, evictions %d; %s; %.0f s" % [
			where, rad_to_deg(dir.angle()), "overdriven" if overdriven else "as it is", dist, SWIM_TICKS / 60, speed,
			int(c.awake_overflow), int(c.chunk_waits), int(c.food_trimmed), int(c.evictions), str(fuzz.counts),
			(Time.get_ticks_msec() - t0) / 1000.0])
		check_eq(report, "", "%s: every invariant held" % where)
		check_eq(int(c.awake_overflow), 0, "%s: awake_overflow" % where)
		check_eq(int(c.chunk_waits), 0, "%s: chunk_waits" % where)
		check(dist >= SWIM_MIN_TM, "%s: it swam %.0f tm (at least %.0f)" % [where, dist, SWIM_MIN_TM])
		if overdriven:
			check(speed > racer_top, "%s: it averaged %.2f tm/s, more than the racer's top speed %.2f, so it was overdriven" % [
				where, speed, racer_top])


func test_soak_circling_a_chunk_corner_does_not_churn_chunks() -> void:
	if _waits("corner circle"):
		return
	var sim: Variant = make_sim(RACER, CIRCLE_SEED)
	sim.debug_set_hidden(true)
	var corner := circle_corner(sim)
	check(not corner.is_empty(), "a chunk corner among the candidates has a clear %.0f tm circle" % CIRCLE_R)
	if corner.is_empty():
		return
	var counts := {"loads": 0, "unloads": 0, "late_loads": 0, "late_unloads": 0, "sleeps": 0, "wakes": 0}
	var farthest := 0.0
	for i in CIRCLE_TICKS:
		keep_fed(sim)
		var late := i >= CIRCLE_SETTLE_TICKS
		for e in tick(sim, circle_intent(sim, corner)):
			match str(e.type):
				"chunk_loaded":
					counts.loads += 1
					counts.late_loads += 1 if late else 0
				"chunk_unloaded":
					counts.unloads += 1
					counts.late_unloads += 1 if late else 0
				"creature_slept":
					counts.sleeps += 1
				"creature_woke":
					counts.wakes += 1
		if late:
			farthest = maxf(farthest, sim.motion.position.distance_to(sim.world.local_of_abs(corner[0], corner[1])))
	print("test-endless-gates: corner (%.0f, %.0f): %s; at most %.2f tm from the corner after the first %d ticks" % [
		corner[0], corner[1], counts, farthest, CIRCLE_SETTLE_TICKS])
	check(farthest <= CIRCLE_HOLD_TM, "it circled the corner (at most %.2f tm away)" % farthest)
	check_eq(int(counts.late_loads), 0, "no chunk loaded after the first %d ticks" % CIRCLE_SETTLE_TICKS)


## #32 from home and from 10 points: per body and start, at least one meeting a minute and one in
## every run; at most 0.5 deaths per 5 minutes over all runs; no starvation.
func test_soak_a_forager_meets_threats_and_one_that_dodges_is_not_worn_down() -> void:
	if _waits("#32"):
		return
	var points := random_points(PRESSURE_POINTS_SEED, 10)
	var deaths := 0
	var starved := 0
	var minutes := 0.0
	for body in PRESSURE_BODIES:
		for from_home in [true, false]:
			var starts: Array = range(points.size())
			if from_home:
				starts.assign(PRESSURE_SEEDS)
			var meetings := 0
			var met_in := 0
			for s: int in starts:
				var seed_value: int = s if from_home else PRESSURE_POINT_RUN_SEED + s
				var at: PackedFloat64Array = PackedFloat64Array() if from_home else points[s]
				var run := _pressure_run(body, seed_value, at)
				var met := int(run.notices) + int(run.tells)
				meetings += met
				met_in += 1 if met > 0 else 0
				deaths += int(run.killed)
				starved += int(run.starved)
				print("test-endless-gates: #32 %s %s seed %d: %d notices, %d tells, %d dodged, %d hits taken, %d killed, %d starved, %d meals%s" % [
					body, "home" if from_home else "point (%.0f, %.0f)" % [at[0], at[1]], seed_value, run.notices, run.tells,
					run.dodges, run.hits_taken, run.killed, run.starved, run.meals, "" if from_home else "; " + str(run.arrival)])
			var group_minutes := starts.size() * PRESSURE_TICKS / 3600.0
			minutes += group_minutes
			var where := "%s from %s" % [body, "home" if from_home else "points"]
			check(meetings / group_minutes >= PRESSURE_MIN_MEETINGS_PER_MIN, "%s: %.2f meetings a minute (need %.1f)" % [
				where, meetings / group_minutes, PRESSURE_MIN_MEETINGS_PER_MIN])
			check_eq(met_in, starts.size(), "%s: met a threat in every run" % where)
	var rate := deaths / minutes * 5.0
	print("test-endless-gates: #32: %d deaths in %.0f minutes, %.2f per 5 minutes; %d starved" % [deaths, minutes, rate, starved])
	check(rate <= PRESSURE_MAX_DEATHS_PER_5_MIN, "%.2f deaths per 5 minutes (at most %.1f)" % [rate, PRESSURE_MAX_DEATHS_PER_5_MIN])
	check_eq(starved, 0, "the forager never starved")


func _pressure_run(body: String, seed_value: int, at: PackedFloat64Array) -> Dictionary:
	var sim: Variant = make_sim(body, seed_value)
	var run := {"notices": 0, "tells": 0, "dodges": 0, "hits_taken": 0, "killed": 0, "starved": 0, "meals": 0,
		"arrival": ""}
	if not at.is_empty():
		run.arrival = _arrived(sim, at, seed_value, "%s seed %d" % [body, seed_value])
	var forager = ForageBot.new()
	var bot = EvadeBot.new()
	bot.base = forager.next_intent
	var events: Array[Dictionary] = []
	var dead := {"since": -1}
	for i in PRESSURE_TICKS:
		events.append_array(continue_after_death(sim, dead))
		events = tick(sim, bot.next_intent(sim, events))
		for e in events:
			match str(e.type):
				"creature_noticed", "creature_tell":
					if e.target == CreatureField.PLAYER_ID:
						run[("notices" if e.type == "creature_noticed" else "tells")] += 1
				"dodged":
					run.dodges += 1
				"hit":
					if e.target == CreatureField.PLAYER_ID:
						run.hits_taken += 1
				"died":
					run[("starved" if e.cause == "starved" else "killed")] += 1
				"ate":
					run.meals += 1
	return run


## arrive(), checked: the cell was placed and ended its arrival within ARRIVE_NEAR_TM of the point.
## Returns the arrival in words for the run's line.
func _arrived(sim: Variant, at: PackedFloat64Array, seed_value: int, who: String) -> String:
	var a := arrive(sim, at, seed_value)
	check(bool(a.placed), "%s: placed %.0f tm out from (%.0f, %.0f)" % [who, ARRIVE_FROM_TM, at[0], at[1]])
	check(float(a.left_tm) <= ARRIVE_NEAR_TM, "%s: arrived within %.0f tm of (%.0f, %.0f) (%.1f tm off)" % [
		who, ARRIVE_NEAR_TM, at[0], at[1], a.left_tm])
	return "arrived from %.0f deg in %.1f s, %.1f tm off" % [rad_to_deg(a.bearing), int(a.ticks) / 60.0, a.left_tm]


## #33: a greedy camper that starts full in an unguarded zone runs dry there (M1's checks).
func test_soak_a_greedy_camper_runs_dry_in_six_unguarded_zones() -> void:
	if _waits("#33"):
		return
	var zones: Array[PackedFloat64Array] = []
	var layout: PoolLayout = data().layout
	for id in CAMP_HOME_ZONES:
		var c: Vector2 = layout.zone(id).center   # the home block keeps the M1 zones where they were (abs = M1)
		zones.append(PackedFloat64Array([c.x, c.y]))
	zones.append_array(_unguarded_tile_zones(CAMP_TILE_ZONES))
	check_eq(zones.size(), CAMP_HOME_ZONES.size() + CAMP_TILE_ZONES, "six zones to camp in")
	for at in zones:
		for body in PRESSURE_BODIES:
			var run := _camp_run(body, at)
			var share := float(run.in_zone) / maxi(1, run.ticks)
			var where := "%s at (%.1f, %.1f) %s" % [run.zone, at[0], at[1], body]
			print("test-endless-gates: #33 %s: ran dry after %s, %d meals (full stock %d), %.0f%% in the zone, %d meetings, %d killed" % [
				where, "%.0f s" % (run.dry_at / 60.0) if run.dry_at >= 0 else "never in %d s" % (CAMP_LIMIT_TICKS / 60),
				run.meals, run.full_stock, 100.0 * share, run.meetings, run.killed])
			check(not str(run.zone).is_empty(), "%s: the zone is loaded" % where)
			check_eq(int(run.killed), 0, "%s: no threat killed the camper" % where)
			check(int(run.dry_at) >= 0, "%s: a camper that starts full runs dry within %d s" % [where, CAMP_LIMIT_TICKS / 60])
			check(share >= CAMP_MIN_IN_ZONE_SHARE, "%s: it camped (%.0f%% in the zone)" % [where, 100.0 * share])
			check(int(run.meals) >= int(run.full_stock), "%s: it ate more than the zone holds when full" % where)


## Tile zones (outside the home block) whose centres no live reach disc covers: from each probe
## point the nearest one within CAMP_PROBE_TM not found before, until `count`.
func _unguarded_tile_zones(count: int) -> Array[PackedFloat64Array]:
	var found: Array[PackedFloat64Array] = []
	var seen := {}
	var sim: Variant = make_sim("grazer", CAMP_SEED)
	sim.debug_set_hidden(true)
	for at in random_points(CAMP_PROBE_SEED, CAMP_PROBES):
		if found.size() >= count:
			break
		if not teleport(sim, at):
			continue
		for i in CAMP_PROBE_SETTLE_TICKS:
			keep_fed(sim)
			tick(sim, SimIntent.new())
		var here: Vector2 = sim.motion.position
		var reach: Array = HuntBot.live_site_discs(sim, "reach")
		var near: Array = []
		for z in sim.region.zones:
			if here.distance_to(z.center) <= CAMP_PROBE_TM:
				near.append(z)
		near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var da := here.distance_to(a.center)
			var db := here.distance_to(b.center)
			return da < db or (da == db and str(a.id) < str(b.id)))
		for z in near:
			var c: PackedFloat64Array = sim.world.abs_of_local(z.center)
			var r := float(z.radius)
			var in_home := absf(c[0]) < HOME_BLOCK_TM + r and absf(c[1]) < HOME_BLOCK_TM + r
			if in_home or seen.has(str(z.id)) or covered(z.center, reach):
				continue
			seen[str(z.id)] = true
			found.append(c)
			break
	return found


## A new `body` lineage placed full at the centre of the zone at `at`, eating only that zone's food
## (a greedy SwimBot camper) and dodging tells, until its energy first runs out or the limit.
func _camp_run(body: String, at: PackedFloat64Array) -> Dictionary:
	var sim: Variant = make_sim(body, CAMP_SEED)
	var run := {"zone": "", "ticks": 0, "dry_at": -1, "meals": 0, "in_zone": 0, "meetings": 0, "killed": 0, "full_stock": 0}
	if not teleport(sim, at):
		return run
	var z := zone_at(sim, at)
	if z.is_empty():
		return run
	run.zone = str(z.id)
	run.full_stock = sim.plankton.max_count(z)
	sim.debug_set_energy(sim.state.energy_capacity)
	sim.drain_events()
	var camper = SwimBot.camper(run.zone, true)
	var bot = EvadeBot.new()
	bot.base = camper.next_intent
	var events: Array[Dictionary] = []
	while int(run.ticks) < CAMP_LIMIT_TICKS and not sim.dead:
		events = tick(sim, bot.next_intent(sim, events))
		run.ticks += 1
		var now := sim.region.zone(run.zone) as Dictionary
		if not now.is_empty() and sim.motion.position.distance_to(now.center) <= float(now.radius):
			run.in_zone += 1
		for e in events:
			match str(e.type):
				"creature_noticed", "creature_tell":
					if e.target == CreatureField.PLAYER_ID:
						run.meetings += 1
				"died":
					run.killed += 1 if e.cause != "starved" else 0
				"ate":
					run.meals += 1
		if sim.state.energy <= 0.0:
			run.dry_at = sim.tick
			break
	return run


## Hunter viability (#30 restated): from home on M1's seeds and from 10 points.
func test_soak_a_hunter_lineage_lives_on_its_kills_from_home_and_ten_points() -> void:
	if _waits("hunter viability"):
		return
	var points := random_points(HUNTER_POINTS_SEED, HUNTER_POINTS)
	var home_passed := 0
	for seed_value in HUNTER_SEEDS:
		home_passed += 1 if _hunter_pass(seed_value, PackedFloat64Array()) else 0
	var point_passed := 0
	for i in points.size():
		point_passed += 1 if _hunter_pass(HUNTER_POINT_RUN_SEED + i, points[i]) else 0
	print("test-endless-gates: hunter viability: %d of %d seeds from home (need %d), %d of %d points (need %d)" % [
		home_passed, HUNTER_SEEDS.size(), HUNTER_PASSES_NEEDED, point_passed, points.size(), HUNTER_POINT_PASSES_NEEDED])
	check(home_passed >= HUNTER_PASSES_NEEDED, "from home: %d of %d seeds pass" % [home_passed, HUNTER_SEEDS.size()])
	check(point_passed >= HUNTER_POINT_PASSES_NEEDED, "from points: %d of %d pass" % [point_passed, points.size()])


func _hunter_pass(seed_value: int, at: PackedFloat64Array) -> bool:
	var sim: Variant = make_sim("hunter", seed_value)
	var arrival := ""
	if not at.is_empty():
		arrival = "; " + _arrived(sim, at, seed_value, "hunter seed %d" % seed_value)
	var bot = HuntBot.new()
	var run := {"starved": 0, "killed": 0, "meat": 0, "kills": 0}
	var events: Array[Dictionary] = []
	var dead := {"since": -1}
	for i in HUNTER_TICKS:
		events.append_array(continue_after_death(sim, dead))
		events = tick(sim, bot.next_intent(sim, events))
		for e in events:
			match str(e.type):
				"died":
					run[("starved" if e.cause == "starved" else "killed")] += 1
				"ate":
					run.meat += 1 if e.kind == "meat" else 0
				"creature_died":
					run.kills += 1 if e.by == CreatureField.PLAYER_ID else 0
	var ok: bool = run.starved == 0 and run.killed <= HUNTER_MAX_THREAT_DEATHS and run.meat >= HUNTER_MIN_MEAT
	print("test-endless-gates: hunter seed %d from %s: %s; %d kills, %d meat eaten, %d starved, %d killed%s" % [
		seed_value, "home" if at.is_empty() else "(%.0f, %.0f)" % [at[0], at[1]], "pass" if ok else "FAIL", run.kills,
		run.meat, run.starved, run.killed, arrival])
	return ok


## F9: every plant eater can always reach food. A grazer with no energy, hidden from the creatures,
## dropped at each point, must eat before it starves (20 s).
func test_soak_a_starving_grazer_reaches_food_from_thirty_points() -> void:
	if _waits("F9"):
		return
	var slowest := 0
	for at in random_points(STARVE_POINTS_SEED, STARVE_POINTS):
		var sim: Variant = make_sim("grazer", STARVE_SEED)
		sim.debug_set_hidden(true)
		check(teleport(sim, at), "placed at (%.0f, %.0f)" % [at[0], at[1]])
		sim.debug_set_energy(0.0)
		sim.drain_events()
		var bot = ForageBot.new()
		var ate_at := -1
		var died := false
		for i in STARVE_LIMIT_TICKS:
			for e in tick(sim, bot.next_intent(sim)):
				if e.type == "ate" and ate_at < 0:
					ate_at = i
				died = died or e.type == "died"
			if ate_at >= 0 or died:
				break
		slowest = maxi(slowest, ate_at)
		check(ate_at >= 0 and not died, "a starving grazer at (%.0f, %.0f) ate before it died (%s)" % [
			at[0], at[1], "died" if died else ("ate at %.1f s" % (ate_at / 60.0) if ate_at >= 0 else "never ate")])
	print("test-endless-gates: F9: %d starving grazers; the slowest ate after %.1f s" % [STARVE_POINTS, slowest / 60.0])


## G13: two runs of a 10 km straight swim are the same run, overdriven and with RACER as it is.
func test_soak_two_runs_of_a_ten_km_swim_give_the_same_hash() -> void:
	if _waits("10 km", SIM):
		return
	for overdriven in [true, false]:
		var label := "overdriven" if overdriven else "racer"
		var a := _ten_km_run(overdriven)
		var b := _ten_km_run(overdriven)
		check_eq(a.marks.size(), b.marks.size(), "%s: the same number of records" % label)
		var equal := 0
		for i in mini(a.marks.size(), b.marks.size()):
			var x: Dictionary = a.marks[i]
			var y: Dictionary = b.marks[i]
			var same: bool = x.hash == y.hash and x.sha256 == y.sha256
			equal += 1 if same else 0
			check(same, "%s tick %d: the two runs are the same (hash %d and %d)" % [label, x.tick, x.hash, y.hash])
		print("test-endless-gates: 10 km %s: %d ticks at %.2f tm/s, %.0f tm covered, %d of %d records equal; %.0f s a run" % [
			label, a.ticks, a.speed, a.distance, equal, a.marks.size(), a.seconds])
		check(float(a.distance) >= SWIM_MIN_TM, "%s: it swam (%.0f tm)" % [label, a.distance])


func _ten_km_run(overdriven: bool) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var sim: Variant = make_sim(RACER, TEN_KM_SEED)
	sim.debug_set_hidden(true)
	drive(sim, overdriven)
	var bot = SwimBot.new(Vector2.from_angle(TEN_KM_HEADING))
	var speed := float(sim.phenotype.speed)
	var ticks := ceili(TEN_KM_TM / speed * 60.0)
	var start: PackedFloat64Array = sim.absolute_position_am()
	var marks: Array[Dictionary] = []
	for i in ticks:
		drive(sim, overdriven)
		tick(sim, bot.next_intent(sim))
		if sim.tick % TEN_KM_RECORD_EVERY == 0 or i == ticks - 1:
			marks.append({"tick": sim.tick, "hash": sim.state_hash(),
				"sha256": JSON.stringify(sim.snapshot(), "", true, true).sha256_text()})
	return {"marks": marks, "ticks": ticks, "speed": speed, "distance": abs_distance(start, sim.absolute_position_am()),
		"seconds": (Time.get_ticks_msec() - t0) / 1000.0}
