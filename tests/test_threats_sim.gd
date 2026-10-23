extends TestCase
## M1 step 3 threats in the running PoolSim: creatures sense the cell only through their own senses
## (rocks hide it, sight has a range and a field of view, touch works behind them), remember it for
## a while and give up when it is gone; their state depends on nothing they did not sense (T5 and
## the decoy); the sim stays deterministic, hashes everything it keeps, and without creatures is
## exactly the step 2 pool. Most tests use the threats fixture (an open pool with a wall of rocks at
## y = 8) and the real species with no sites, so every creature is placed exactly.

const ForageBot := preload("res://game/dev/forage_bot.gd")
const EvadeBot := preload("res://game/dev/evade_bot.gd")
const HuntBot := preload("res://game/dev/hunt_bot.gd")
const Yardstick := preload("res://tests/cost_yardstick.gd")
const THREATS_FIXTURE := "res://tests/fixtures/pool_test_threats.json"
const TEST_SPECIES := "res://tests/fixtures/creatures_test.json"
const DT := PoolSim.DT
const PLAYER := "player"
## #28 (flake policy in docs/DECISIONS.md, M1 step 3 review fixes): the same 60 s are timed
## STEP_COST_RUNS times, the bot's run and replays of its intents, and the fastest run counts. Its
## average must stay under STEP_COST_LIMIT_US, about 2.5 times a quiet reading in the Linux container
## (about 550 us; CI's runners read 250 to 365), so moderate load from other processes does not fail
## it. Each step is also timed against the yardstick (tests/cost_yardstick.gd) run right after it,
## and the median run's step time over its yardstick time must stay under STEP_COST_YARDSTICKS: a
## tick reads 4.7 to 5.4 yardsticks at load 2 to 7 here and beside a busy loop or a cache-thrashing
## process (4.6 on CI), and a step that costs twice as much 9.5 to 10.2. Heavy load can still move
## the count, so only a pass on a quiet machine or on CI rules a regression out.
const STEP_COST_LIMIT_US := 1500.0
const STEP_COST_YARDSTICKS := 8.0
const STEP_COST_RUNS := 3
const STEP_COST_TICKS := 3600
const BODIES: PackedStringArray = ["grazer", "hunter", "omnivore"]
## Open water in the threats fixture, far from the wall, the zone and the soft wall: strikes start here.
const STRIKE_ORIGIN := Vector2(0.0, -16.0)
const LUNGE_DISTS := [2.5, 2.75, 3.0]   ## the lunge's start window (plan section 0)
const CHARGE_DISTS := [3.0, 4.0, 5.0]   ## the charge's start window
const GRAZE := 0.3                      ## throttle of a grazing cell
const CRUISE := 0.8                     ## throttle of a cruising cell
## Heading indices (k x 30 degrees, 0 facing away from the creature) that swim into the strike.
const HEAD_ON: Array[int] = [5, 6, 7]
## The turn F2 promises a dodge needs at most: out of the line on the side the cell faces, the
## perpendicular nearer its heading. The other side is not promised: a cell turns at 2.5 rad/s with
## no thrust until it heads within 90 degrees of where it wants to go (Locomotion.steer), so turning
## all the way round (150 to 180 degrees) takes longer than the tell.
const PROMISED_TURN_DEG := 90.0
## The side behind the cell, as measured every 5 degrees (DECISIONS, M1 step 3 review fixes: fair):
## outside the head-on sector (150 to 210 degrees) no dodge that turns less than this is hit...
const BEHIND_SAFE_UNDER_DEG := 120.0
## ...and inside it the lunge hits a fed cell from about 100 degrees of turn, under this.
const BEHIND_HEAD_ON_HIT_UNDER_DEG := 105.0
## Snapshot keys only a pool with creatures has (T14 compares everything else).
const CREATURE_KEYS: PackedStringArray = ["creatures", "creature_next", "creature_rng", "spawn_queue",
	"engaged_on_player", "niches", "grace_until", "death_streak"]
## What #25 perturbs, one sim each (_perturb).
const PERTURBATIONS: PackedStringArray = ["creature position.x by one float32 step", "creature velocity",
	"creature heading", "creature health", "creature energy", "a cooldown", "phase_tick", "target", "lock_heading",
	"a seen position", "an ignore entry", "landed_on", "the brain RNG", "the field RNG", "a queue at_tick",
	"engaged_on_player", "the AI frozen switch", "the hidden switch", "the cell's death", "the shelter's end",
	"the death streak"]

var catalog: PartCatalog
var fixture: PoolLayout
var layout: PoolLayout
var test_species: SpeciesCatalog
var species: SpeciesCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()
	fixture = PoolLayout.load_from(THREATS_FIXTURE)
	layout = PoolLayout.load_from()
	test_species = SpeciesCatalog.load_from(TEST_SPECIES)
	species = SpeciesCatalog.load_from()


## A new lineage with creatures (the fixture and the site-less species unless given), the cell at
## `at` facing `heading` (else at the layout spawn). Its start shelter is ended at once, so the
## creatures can sense it from the first tick (test_checkpoints covers the shelter). Starting events
## are dropped.
func _sim(body: String, seed_value: int, at := Vector2.INF, heading := 0.0, p_layout: PoolLayout = null,
		p_species: SpeciesCatalog = null) -> PoolSim:
	var use := p_layout if p_layout != null else fixture
	var r := Lineage.found(seed_value, "test+dev", catalog, body)
	r.save.player["position"] = PlaneSpace.to_save(use.spawn)
	var sim := PoolSim.create(r.save, catalog, use, p_species if p_species != null else test_species)
	sim.grace_until = sim.tick
	if at.is_finite():
		check(sim.debug_teleport(at, heading), "the cell placed at %s" % at)
	sim.drain_events()
	return sim


## The step 2 pool for the same lineage: no species at all.
func _plain_sim(body: String, seed_value: int, p_layout: PoolLayout) -> PoolSim:
	var r := Lineage.found(seed_value, "test+dev", catalog, body)
	r.save.player["position"] = PlaneSpace.to_save(p_layout.spawn)
	return PoolSim.create(r.save, catalog, p_layout)


## A creature placed at `at` facing `heading`, settled (it may notice from its first think), at
## `energy_share` of its capacity when given (below its hungry share it hunts or forages).
func _creature(sim: PoolSim, species_id: String, at: Vector2, heading: float, energy_share := -1.0) -> CreatureField.Creature:
	var c := sim.creatures.spawn_at(species_id, at, heading, "", sim.tick, true)
	check(c != null, "a %s placed at %s" % [species_id, at])
	c.brain.ignore_all_until = 0
	if energy_share >= 0.0:
		c.state.energy = c.state.energy_capacity * energy_share
	sim.drain_events()
	return c


## Steps `ticks` times (intent from `intent.call(sim)`, else none) and returns the events, each
## stamped with the tick it happened on. `each.call(sim, tick)` runs after every step; when it
## returns true the run stops early.
func _run(sim: PoolSim, ticks: int, intent := Callable(), each := Callable()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in ticks:
		var t := sim.tick
		var wanted: SimIntent = intent.call(sim) if intent.is_valid() else SimIntent.new()
		sim.step(wanted)
		for e in sim.drain_events():
			e["tick"] = t
			out.append(e)
		if each.is_valid() and each.call(sim, t) == true:
			break
	return out


func _of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _creature_json(sim: PoolSim) -> String:
	return JSON.stringify(sim.creatures.snapshot(), "", true, true)


# --- tells and fairness (plan threats_sim #1-8) ---

## One strike in the real sim with the probe's geometry (plan section 0): the creature at rest at
## STRIKE_ORIGIN facing +x, the cell `d` m in front heading `h` (0 faces away from it), still or
## swimming on at `throttle`, fed or starving; the tell starts now through the brain's begin_tell.
## `react` < 0: the cell never reacts; else EvadeBot with that reaction (its base: swim on), which
## dodges out of the line on the side with the shorter turn from the cell's heading, or with `far`
## on the other side. Runs until the strike is over. {"hit", "clearance" (INF without a strike
## tick), "tell_tick", "reacted_at", "turn" (degrees from the cell's heading to the dodge at the
## reaction; NAN without one), "events"}.
func _strike(species_id: String, body: String, d: float, h: float, throttle: float, starving: bool, react: int,
		far := false) -> Dictionary:
	var sim := _sim(body, 31, STRIKE_ORIGIN + Vector2(d, 0.0), h)
	if starving:
		sim.debug_set_energy(0.0)
	sim.motion.velocity = Vector2.from_angle(h) * sim.phenotype.speed * sim.state.speed_multiplier() * throttle
	var c := _creature(sim, species_id, STRIKE_ORIGIN, 0.0)
	_begin_tell(sim, c)
	var swim_on := SimIntent.new(Vector2.from_angle(h) * throttle)
	var bot = EvadeBot.new()
	bot.reaction_ticks = maxi(react, 0)
	bot.far_side = far
	bot.base = func(_s: PoolSim) -> SimIntent: return swim_on
	var tell_tick := sim.tick
	var out := {"hit": false, "clearance": INF, "tell_tick": tell_tick, "reacted_at": -1, "turn": NAN, "events": []}
	var pending: Array[Dictionary] = []
	var limit: int = c.brain.cfg.attack.tell_ticks + c.brain.cfg.attack.burst_ticks + c.brain.cfg.attack.glide_ticks + 4
	for i in limit:
		var t := sim.tick
		var intent: SimIntent = bot.next_intent(sim, pending) if react >= 0 else swim_on
		if react >= 0 and bot.reacted_at == t and is_nan(float(out.turn)):
			out.turn = rad_to_deg(absf(angle_difference(sim.motion.heading, intent.move.angle())))
		sim.step(intent)
		pending = sim.drain_events()
		for e in pending:
			e["tick"] = t
			out.events.append(e)
			if e.type == "hit" and e.attacker == c.id and e.target == PLAYER:
				out.hit = true
		if out.hit or c.brain.phase == CreatureBrain.RECOVER or sim.creatures.find(c.id) == null:
			break
		if CreatureBrain.is_striking(c.brain):
			out.clearance = minf(out.clearance, _clearance(c, sim))
	out.reacted_at = bot.reacted_at
	return out


## The creature's brain targets the cell (seen now, engageable) and starts its tell at once.
func _begin_tell(sim: PoolSim, c: CreatureField.Creature) -> void:
	c.brain.target = PLAYER
	c.brain.seen[PLAYER] = {"position": sim.motion.position, "velocity": sim.motion.velocity, "tick": sim.tick, "by": "sight",
		"species": SpeciesCatalog.PLAYER_SPECIES, "radius": sim.phenotype.radius, "engageable": true}
	c.brain.engaged_tick = sim.tick
	CreatureBrain.begin_tell(c.brain, sim.creatures.self_view_of(c), sim.tick)
	sim.creatures.update_token(c, sim.tick)


## How far the cell's center is from where the creature's strike would be allowed now: the nearest
## of its weapons' sectors (radius: both radii plus the reach; the weapon's arc). A ram needs closing
## speed, so while the bodies are not closing (a cell passing a rammer's flank spikes) no sector is
## allowed and the tick does not count (INF).
func _clearance(c: CreatureField.Creature, sim: PoolSim) -> float:
	var bite := str(c.brain.cfg.attack.kind) == "bite"
	var reach := c.phenotype.radius + sim.phenotype.radius + (InteractionResolver.BITE_REACH if bite else InteractionResolver.RAM_REACH)
	var weapons: Array[Dictionary] = []
	if bite:
		for m in c.phenotype.mouths:
			if m.type == "mouth_jaw":
				weapons.append(m)
	else:
		weapons.assign(c.phenotype.spikes)
		var line := sim.motion.position - c.motion.position
		if (c.motion.velocity - sim.motion.velocity).dot(line.normalized()) <= 0.0:
			return INF
	var d := c.motion.position.distance_to(sim.motion.position)
	var actor := InteractionResolver.Actor.new(c.id, c.motion.position, c.motion.heading, c.phenotype)
	var bearing := InteractionResolver.relative_angle(actor, sim.motion.position)
	var best := INF
	for w in weapons:
		best = minf(best, _sector_gap(d, absf(angle_difference(float(w.angle), bearing)), reach, float(w.arc) * 0.5))
	return best


## Distance from a point at distance d and off-axis angle th to the sector of radius r and half-angle a.
static func _sector_gap(d: float, th: float, r: float, a: float) -> float:
	if th <= a:
		return maxf(0.0, d - r)
	var off := th - a
	var along := d * cos(off)
	if along <= 0.0:
		return d
	if along <= r:
		return d * sin(off)
	return Vector2(along, d * sin(off)).distance_to(Vector2(r, 0.0))


## The S5 grid for one species (plan section 18 #2-3): EvadeBot at 24 ticks, distances `dists` x 12
## headings x still or grazing x fed or starving x 3 bodies, dodging on the side the cell faces (the
## shorter turn, at most 90 degrees). Returns {"body/base/fed" -> {"hits": [heading index...],
## "clear": min clearance, "clear_out": min clearance outside head-on, "max_turn": the dodge's
## largest turn in degrees}}, and checks the reaction came exactly 24 ticks after every tell.
func _grid(species_id: String, dists: Array) -> Dictionary:
	var cells := {}
	var late := 0
	for body in BODIES:
		for base in ["still", "graze"]:
			for starving in [false, true]:
				var cell := {"hits": [], "clear": INF, "clear_out": INF, "max_turn": 0.0, "runs": 0}
				for d in dists:
					for k in 12:
						var r := _strike(species_id, body, d, k * TAU / 12.0, 0.0 if base == "still" else GRAZE, starving, EvadeBot.REACTION_TICKS)
						cell.runs += 1
						if r.reacted_at != int(r.tell_tick) + EvadeBot.REACTION_TICKS:
							late += 1
						cell.max_turn = maxf(cell.max_turn, r.turn)
						if r.hit:
							cell.hits.append(k)
							continue
						cell.clear = minf(cell.clear, r.clearance)
						if not HEAD_ON.has(k):
							cell.clear_out = minf(cell.clear_out, r.clearance)
				cells["%s/%s/%s" % [body, base, "starving" if starving else "fed"]] = cell
	check_eq(late, 0, "%s: EvadeBot reacted exactly %d ticks after every tell" % [species_id, EvadeBot.REACTION_TICKS])
	return cells


func _cell_text(cells: Dictionary, key: String) -> String:
	var c: Dictionary = cells[key]
	return "%s: %d hits %s, clearance %.3f (outside head-on %.3f), turns up to %.0f deg over %d runs" \
		% [key, c.hits.size(), c.hits, c.clear, c.clear_out, c.max_turn, c.runs]


## The S5 strike (EvadeBot at 24 ticks) at every heading in `degs` (whole degrees, 0 faces away from
## the creature; a multiple of 30 gives exactly the grid's heading) x `dists` x still or grazing x
## fed or starving x 3 bodies, on the side the cell faces, or with `far` on the side behind it. One
## {"key": "body/base/fed", "deg", "turn", "hit"} per run; checks the reaction came exactly 24 ticks
## after every tell.
func _sweep(species_id: String, dists: Array, degs: Array, far: bool) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	var late := 0
	for body in BODIES:
		for base in ["still", "graze"]:
			for starving in [false, true]:
				var key := "%s/%s/%s" % [body, base, "starving" if starving else "fed"]
				for deg: int in degs:
					for d in dists:
						var r := _strike(species_id, body, d, float(deg) / 30.0 * TAU / 12.0, 0.0 if base == "still" else GRAZE,
							starving, EvadeBot.REACTION_TICKS, far)
						if r.reacted_at != int(r.tell_tick) + EvadeBot.REACTION_TICKS:
							late += 1
						runs.append({"key": key, "deg": deg, "turn": float(r.turn), "hit": bool(r.hit)})
	check_eq(late, 0, "%s: EvadeBot reacted exactly %d ticks after every tell" % [species_id, EvadeBot.REACTION_TICKS])
	return runs


## Whether heading `deg` (0 faces away from the creature) lies in the head-on sector, 150 to 210.
static func _is_head_on(deg: int) -> bool:
	return absi(deg - 180) <= 30


func test_the_threats_are_real_and_moving_prey_is_safe_without_any_reaction() -> void:
	# No reaction, every body fed: still prey is always hit, a perpendicular graze mostly, a
	# perpendicular cruise almost never (pinned together so tuning cannot slide to either extreme).
	for species_id in ["ambush_hunter", "rammer"]:
		var dists := LUNGE_DISTS if species_id == "ambush_hunter" else CHARGE_DISTS
		var graze_floor := 5 if species_id == "ambush_hunter" else 4
		for body in BODIES:
			var still_hits := 0
			var graze_hits := 0
			var cruise_hits := 0
			for d in dists:
				for k in 12:
					var r := _strike(species_id, body, d, k * TAU / 12.0, 0.0, false, -1)
					if r.hit:
						still_hits += 1
				for k in [3, 9]:
					if _strike(species_id, body, d, k * TAU / 12.0, GRAZE, false, -1).hit:
						graze_hits += 1
					if _strike(species_id, body, d, k * TAU / 12.0, CRUISE, false, -1).hit:
						cruise_hits += 1
			print("test-threats-no-reaction: %s vs %s: still %d/36, graze across %d/6, cruise across %d/6" % [species_id, body, still_hits, graze_hits, cruise_hits])
			check_eq(still_hits, 36, "%s hits a still %s every time" % [species_id, body])
			check(graze_hits >= graze_floor, "%s hits a %s grazing across its line %d/6 (at least %d)" % [species_id, body, graze_hits, graze_floor])
			check(cruise_hits <= 1, "%s hits a %s cruising across its line %d/6 (at most 1)" % [species_id, body, cruise_hits])


func test_a_lunge_is_dodged_by_swimming_out_of_its_line_on_the_side_the_cell_faces_0_4_s_after_the_tell_starts() -> void:
	# S5 lunge grid (plan section 18 #2): bounds from the probe in section 0. EvadeBot dodges on the
	# side the cell faces, a turn of at most 90 degrees (F2). The slow tests below add every 5 degrees
	# of the head-on sector and measure the side behind the cell.
	var cells := _grid("ambush_hunter", LUNGE_DISTS)
	for cell_key in cells:
		check(float(cells[cell_key].max_turn) <= PROMISED_TURN_DEG + 1e-3,
			"the dodge turns at most %d degrees: %s" % [PROMISED_TURN_DEG, _cell_text(cells, cell_key)])
	for body in BODIES:
		var key := "%s/still/fed" % body
		print("test-threats-s5-lunge: " + _cell_text(cells, key))
		check(cells[key].hits.is_empty() and cells[key].clear >= 0.15, _cell_text(cells, key))
		key = "%s/still/starving" % body
		print("test-threats-s5-lunge: " + _cell_text(cells, key))
		check(cells[key].hits.is_empty() and cells[key].clear_out >= 0.15, _cell_text(cells, key))
		key = "%s/graze/fed" % body
		print("test-threats-s5-lunge: " + _cell_text(cells, key))
		check(cells[key].hits.is_empty() and cells[key].clear_out >= 0.15, _cell_text(cells, key))
		key = "%s/graze/starving" % body
		print("test-threats-s5-lunge: " + _cell_text(cells, key))
		var head_on_only: bool = cells[key].hits.all(func(k: int) -> bool: return HEAD_ON.has(k))
		check(cells[key].hits.size() <= 1 and head_on_only and cells[key].clear_out >= 0.10, _cell_text(cells, key))


func test_a_charge_is_dodged_by_swimming_out_of_its_line_on_the_side_the_cell_faces_0_4_s_after_the_puff_starts() -> void:
	# S5 charge grid (plan section 18 #3), inside the rammer's territory, dodging on the side the
	# cell faces (F2).
	var cells := _grid("rammer", CHARGE_DISTS)
	for cell_key in cells:
		check(float(cells[cell_key].max_turn) <= PROMISED_TURN_DEG + 1e-3,
			"the dodge turns at most %d degrees: %s" % [PROMISED_TURN_DEG, _cell_text(cells, cell_key)])
	for body in BODIES:
		for base in ["still", "graze"]:
			var key := "%s/%s/fed" % [body, base]
			print("test-threats-s5-charge: " + _cell_text(cells, key))
			check(cells[key].hits.is_empty() and cells[key].clear >= 0.15, _cell_text(cells, key))
			key = "%s/%s/starving" % [body, base]
			print("test-threats-s5-charge: " + _cell_text(cells, key))
			check(cells[key].hits.is_empty() and cells[key].clear >= 0.05, _cell_text(cells, key))


func test_slow_a_dodge_on_the_side_the_cell_faces_holds_every_5_degrees_through_the_head_on_sector() -> void:
	# F2's promise where it is tightest: the S5 grids sample head-on at 150, 180 and 210 degrees
	# only; this runs every 5 degrees from 150 to 210 on the side the cell faces (a turn of 60 to 90
	# degrees). A fed cell is never hit; a starving one at most once per cell, the head-on budget.
	var degs := range(150, 215, 5)
	for species_id in ["ambush_hunter", "rammer"]:
		var runs := _sweep(species_id, LUNGE_DISTS if species_id == "ambush_hunter" else CHARGE_DISTS, degs, false)
		var hits := {}
		var max_turn := 0.0
		for r in runs:
			max_turn = maxf(max_turn, r.turn)
			if r.hit:
				hits[r.key] = hits.get(r.key, []) + ["heading %d deg, turn %.1f deg" % [r.deg, r.turn]]
		print("test-threats-s5-head-on: %s: %d runs, turns up to %.1f deg, hits %s" % [species_id, runs.size(), max_turn, hits])
		check(max_turn <= PROMISED_TURN_DEG + 1e-3, "%s: the dodge turns at most %d degrees (%.1f)" % [species_id, PROMISED_TURN_DEG, max_turn])
		for key: String in hits:
			check(key.ends_with("/starving") and hits[key].size() <= 1, "%s %s: only a starving cell is hit, at most once: %s"
				% [species_id, key, hits[key]])


func test_slow_a_dodge_on_the_side_behind_the_cell_is_hit_only_past_120_degrees_of_turn_outside_head_on() -> void:
	# The other side, which F2 does not promise and a player may still pick by where the lane lies
	# on screen: EvadeBot dodges to the perpendicular behind the cell, a turn of 90 to 180 degrees.
	# The S5 headings, plus every 5 degrees where that turn is under 120 degrees: facing away from
	# the creature (within 30 degrees of 0) and facing it (the head-on sector). This pins what
	# DECISIONS records (M1 step 3 review fixes: fair):
	#  - outside the head-on sector no dodge that turns less than BEHIND_SAFE_UNDER_DEG is hit;
	#  - inside it the lunge hits a fed cell from about 100 degrees of turn, so F2 promises only the
	#    side the cell faces (if this stops, the other side has become safer and F2 can say more);
	#  - a still cell that must turn all the way round is hit (if this stops, both sides work and
	#    F2, D6 and the tips can say so).
	var degs := []
	for deg in range(0, 360, 5):
		if deg % 30 == 0 or deg < 30 or deg > 330 or absi(deg - 180) < 30:
			degs.append(deg)
	for species_id in ["ambush_hunter", "rammer"]:
		var runs := _sweep(species_id, LUNGE_DISTS if species_id == "ambush_hunter" else CHARGE_DISTS, degs, true)
		var grid := {}         # the S5 headings: hits of 36 per cell, as recorded in DECISIONS
		var by_deg := {}       # hits per heading, all cells
		var cell_max := {}     # the largest turn per cell
		var hits := 0
		var away_band := 0     # runs outside head-on whose dodge turned more than 90 but less than BEHIND_SAFE_UNDER_DEG
		var head_on_band := 0  # the same inside the head-on sector
		var round_hits := 0    # hits on a still cell that had to turn 170 degrees or more
		var fed_head_on_min := INF
		var starving_head_on_min := INF
		var unpromised := []
		for r in runs:
			var key: String = r.key
			var deg: int = r.deg
			var turn: float = r.turn
			cell_max[key] = maxf(float(cell_max.get(key, 0.0)), turn)
			if deg % 30 == 0 and not grid.has(key):
				grid[key] = 0
			var banded := turn > 90.0 + 1e-3 and turn < BEHIND_SAFE_UNDER_DEG - 1e-3
			if banded and _is_head_on(deg):
				head_on_band += 1
			elif banded:
				away_band += 1
			if not r.hit:
				continue
			hits += 1
			by_deg[deg] = int(by_deg.get(deg, 0)) + 1
			if deg % 30 == 0:
				grid[key] += 1
			if turn >= 170.0 and key.contains("/still/"):
				round_hits += 1
			if _is_head_on(deg) and key.ends_with("/fed"):
				fed_head_on_min = minf(fed_head_on_min, turn)
			elif _is_head_on(deg):
				starving_head_on_min = minf(starving_head_on_min, turn)
			elif turn < BEHIND_SAFE_UNDER_DEG - 1e-3:
				unpromised.append("%s heading %d deg, turn %.1f deg" % [key, deg, turn])
		for key: String in cell_max:
			check(float(cell_max[key]) >= 150.0, "%s %s: the dodge went to the side behind the cell (turns up to %.0f deg)"
				% [species_id, key, cell_max[key]])
		var degs_hit := by_deg.keys()
		degs_hit.sort()
		print("test-threats-s5-far: %s: %d hits in %d runs; on the S5 headings, hits of 36 per cell %s" % [species_id, hits, runs.size(), grid])
		print("test-threats-s5-far: %s: hits by heading %s" % [species_id, degs_hit.map(func(k: int) -> String: return "%d:%d" % [k, by_deg[k]])])
		print("test-threats-s5-far: %s: %d runs outside head-on and %d inside turned 90-%d deg; head-on hits from %.1f deg fed, %.1f starving"
			% [species_id, away_band, head_on_band, BEHIND_SAFE_UNDER_DEG, fed_head_on_min, starving_head_on_min])
		check(unpromised.is_empty(), "%s: outside head-on no hit where the dodge turns less than %d degrees: %s"
			% [species_id, BEHIND_SAFE_UNDER_DEG, unpromised])
		check(away_band > 0 and head_on_band > 0, "%s: dodges turned 90-%d degrees both facing away (%d) and head-on (%d)"
			% [species_id, BEHIND_SAFE_UNDER_DEG, away_band, head_on_band])
		check(round_hits > 0, "%s: a still cell that turns all the way round is hit (%d times); if not, both sides work and F2, D6 and the tips can say so"
			% [species_id, round_hits])
		if species_id == "ambush_hunter":
			check(fed_head_on_min < BEHIND_HEAD_ON_HIT_UNDER_DEG, "head-on, the lunge hits a fed cell on the side behind from about 100 degrees of turn (%.1f); if not, F2 can promise more than the side the cell faces"
				% fed_head_on_min)


func test_the_brain_reaches_the_probed_strike_by_itself_and_a_dodge_on_the_side_the_cell_faces_still_works() -> void:
	# S5 natural path (plan #4): no whitebox. The creature notices the cell, pursues, aims and
	# tells by itself; the cell (fed, still or grazing at 4 headings) reacts with EvadeBot, out of
	# the line on the side it faces. A tell needs the creature at rest in its window, so a grazing
	# cell can slip away untold: an ambusher never tells on prey swimming straight away
	# (test_creature_brain), and a rammer lets an intruder leave its territory. Such a run must end
	# with the engagement over and no hit.
	for species_id in ["ambush_hunter", "rammer"]:
		var graze_tells := 0
		for body in BODIES:
			for base in ["still", "graze"]:
				var hits := 0
				var told := 0
				var unfinished := 0
				var unaimed := 0
				var clear := INF
				var clear_out := INF
				for k in [0, 3, 6, 9]:
					var r := _natural_strike(species_id, body, k * TAU / 12.0, 0.0 if base == "still" else GRAZE)
					if r.told:
						told += 1
						if not r.aimed:
							unaimed += 1
					elif r.engaged:
						unfinished += 1
					if r.hit:
						hits += 1
						continue
					clear = minf(clear, r.clearance)
					if not r.head_on:
						clear_out = minf(clear_out, r.clearance)
				var text := "%s vs %s %s: %d tells, %d hits, clearance %.3f (outside head-on %.3f)" % [species_id, body, base, told, hits, clear, clear_out]
				print("test-threats-natural: " + text)
				if base == "still":
					check_eq(told, 4, "every run on a still cell reached a tell: " + text)
				else:
					graze_tells += told
				check_eq(unfinished, 0, "a run without a tell ended its engagement: " + text)
				check_eq(unaimed, 0, "every tell came from aim with the creature nearly still: " + text)
				check_eq(hits, 0, "no hits: " + text)
				var floor_ok := clear >= 0.15 if base == "still" or species_id == "rammer" else clear_out >= 0.15
				check(floor_ok, "clearance as in the grid: " + text)
		check(graze_tells >= 6, "%s told on grazing cells in %d of 12 runs" % [species_id, graze_tells])


## One natural engagement: the creature at rest at STRIKE_ORIGIN facing +x (an ambush hunter
## hungry), the cell ahead of it heading `h`, swimming on at `throttle` with EvadeBot. Runs until the
## first strike is over (or 900 ticks). {"told", "hit", "clearance", "head_on" (the cell swam into
## the lane at the tell: heading within 30 degrees of straight at the creature), "aimed" (on the
## tick before the tell the brain was in aim and the creature at most tell_start_max_speed), "engaged"
## (still engaged with the cell at the end)}.
func _natural_strike(species_id: String, body: String, h: float, throttle: float) -> Dictionary:
	var ahead := 5.0 if species_id == "ambush_hunter" else 4.5
	var sim := _sim(body, 41, STRIKE_ORIGIN + Vector2(ahead, 0.0), h)
	sim.motion.velocity = Vector2.from_angle(h) * sim.phenotype.speed * throttle
	var c := _creature(sim, species_id, STRIKE_ORIGIN, 0.0, 0.4 if species_id == "ambush_hunter" else -1.0)
	var swim_on := SimIntent.new(Vector2.from_angle(h) * throttle)
	var bot = EvadeBot.new()
	bot.base = func(_s: PoolSim) -> SimIntent: return swim_on
	var out := {"told": false, "hit": false, "clearance": INF, "head_on": false, "aimed": false, "engaged": false}
	var struck := false
	var pending: Array[Dictionary] = []
	for i in 900:
		var was_aiming: bool = c.brain.phase == CreatureBrain.AIM
		var was_still: bool = c.motion.velocity.length() <= float(c.brain.cfg.tell_start_max_speed) + 1e-6
		sim.step(bot.next_intent(sim, pending))
		pending = sim.drain_events()
		for e in pending:
			if e.type == "creature_tell" and e.id == c.id and not out.told:
				out.told = true
				out.aimed = was_aiming and was_still
				out.head_on = absf(angle_difference(float(e.lane.heading), sim.motion.heading)) >= 5.0 * PI / 6.0 - 1e-6
			elif e.type == "creature_strike" and e.id == c.id:
				struck = true
			elif e.type == "hit" and e.attacker == c.id and e.target == PLAYER:
				out.hit = true
		if out.hit or (struck and not CreatureBrain.is_striking(c.brain)):
			break
		if CreatureBrain.is_striking(c.brain):
			out.clearance = minf(out.clearance, _clearance(c, sim))
	out.engaged = not out.told and CreatureBrain.is_engaged_with(c.brain, PLAYER)
	return out


func test_a_cell_swimming_straight_away_outpaces_a_pursuer_when_fed_and_is_never_hit_when_starving() -> void:
	# S6 escape (plan #5, F3): the creature starts 4 m behind the cell, already pursuing it.
	var slowest_fed: float = SpeciesCatalog._starting_bodies(catalog).slowest_fed
	for species_id in ["ambush_hunter", "rammer"]:
		for body in BODIES:
			for starving in [false, true]:
				var start := Vector2(-8.0, -16.0)
				var sim := _sim(body, 51, start, 0.0)
				if starving:
					sim.debug_set_energy(0.0)
				sim.motion.velocity = Vector2.RIGHT * sim.phenotype.speed * sim.state.speed_multiplier()
				var c := _creature(sim, species_id, start - Vector2(4.0, 0.0), 0.0, 0.4 if species_id == "ambush_hunter" else -1.0)
				_engage(sim, c)
				c.motion.velocity = Vector2.RIGHT * c.phenotype.speed * float(c.brain.cfg.speeds.pursue)
				var gaps: Array[float] = []
				var cell_speed: float = sim.phenotype.speed * sim.state.speed_multiplier()
				var attack: Dictionary = c.brain.cfg.attack
				var bound: int = c.brain.cfg.give_up_ticks + attack.tell_ticks + attack.burst_ticks + attack.glide_ticks + attack.recover_ticks
				var ended := -1   # the engagement is over: a give-up, or the attack ends without a reason to go on
				var hits := 0
				var shrunk := ""
				for t in bound + 1:
					sim.step(SimIntent.new(Vector2.RIGHT))
					gaps.append(c.motion.position.distance_to(sim.motion.position))
					for e in sim.drain_events():
						if e.type == "hit" and e.attacker == c.id:
							hits += 1
					if not CreatureBrain.is_engaged_with(c.brain, PLAYER):
						ended = t
						break
				var label := "%s behind a %s %s cell" % [species_id, "starving" if starving else "fed", body]
				check_eq(hits, 0, "%s: never hit" % label)
				if starving:
					check(ended >= 0, "%s: the creature let the cell go by tick %d (at %d)" % [label, bound, ended])
				else:
					for t in range(120, gaps.size()):
						if shrunk.is_empty() and gaps[t] < gaps[t - 60] - 0.05:
							shrunk = "tick %d: %.2f m -> %.2f m" % [t, gaps[t - 60], gaps[t]]
					check(shrunk.is_empty(), "%s: after the first second the gap never shrinks over a second (%s)" % [label, shrunk])
					# F3 measured in the sim: the pursuer is no faster than the escape rule's share of the
					# slowest fed starting body, so every second the gap opens by at least the cell's speed
					# minus that bound (less the same 0.05 m tolerance).
					var bound_speed: float = float(sim.species.fairness.max_pursue_share_of_slowest_fed) * slowest_fed
					var opens := INF
					for t in range(120, gaps.size()):
						opens = minf(opens, gaps[t] - gaps[t - 60])
					print("test-threats-escape: %s opens at least %.3f m/s (rule margin %.3f)" % [label, opens, cell_speed - bound_speed])
					check(opens >= cell_speed - bound_speed - 0.05,
						"%s: the gap opens by at least %.3f m every second (worst %.3f m)" % [label, cell_speed - bound_speed - 0.05, opens])
					check(gaps.size() >= 120, "%s: the chase lasted past the first two seconds (%d ticks)" % [label, gaps.size()])


## The creature's brain has just seen the cell and chases it, its give-up timer starting now
## (whitebox through the brain's own transitions).
func _engage(sim: PoolSim, c: CreatureField.Creature) -> void:
	c.brain.seen[PLAYER] = {"position": sim.motion.position, "velocity": sim.motion.velocity, "tick": sim.tick, "by": "sight",
		"species": SpeciesCatalog.PLAYER_SPECIES, "radius": sim.phenotype.radius, "engageable": true}
	CreatureBrain._notice(c.brain, PLAYER, "sight", sim.tick)
	CreatureBrain._chase(c.brain, sim.creatures.self_view_of(c), CreatureBrain.PURSUE, sim.tick, true)
	sim.creatures.update_token(c, sim.tick)
	sim.drain_events()


func test_every_strike_comes_exactly_1_2_s_after_its_tell_and_hits_only_inside_its_own_window() -> void:
	# Plan #6: long engagements against a cell that keeps edging toward the creature, so creatures
	# are in contact outside their strikes too.
	for species_id in ["ambush_hunter", "rammer"]:
		var sim := _sim("grazer", 61, STRIKE_ORIGIN + Vector2(4.0, 0.0), PI)
		var c := _creature(sim, species_id, STRIKE_ORIGIN, 0.0, 0.4 if species_id == "ambush_hunter" else -1.0)
		var attack: Dictionary = c.brain.cfg.attack
		var window: int = attack.burst_ticks + attack.glide_ticks
		var edge_in := func(s: PoolSim) -> SimIntent:
			var to := c.motion.position - s.motion.position
			return SimIntent.new(to.normalized() * 0.25 if to.length() > c.phenotype.radius + s.phenotype.radius + 0.1 else Vector2.ZERO)
		var tells: Array[int] = []
		var lanes: Array[Dictionary] = []     # each tell's lane, as the view draws it
		var strikes: Array[Dictionary] = []   # {"tick", "heading", "position", "hits", "hit_at"}
		var stray_hits: Array[int] = []
		var turned := ""
		var reach := c.phenotype.radius + sim.phenotype.radius + float(attack.reach)
		var touching := 0   # ticks in reach outside a strike: where a stray hit could land
		for t in 2400:
			sim.step(edge_in.call(sim))
			if not CreatureBrain.is_striking(c.brain) and c.motion.position.distance_to(sim.motion.position) <= reach:
				touching += 1
			for e in sim.drain_events():
				if e.get("id", "") == c.id and e.type == "creature_tell":
					tells.append(t)
					lanes.append(e.lane)
				elif e.get("id", "") == c.id and e.type == "creature_strike":
					strikes.append({"tick": t, "heading": float(e.heading), "position": Vector2(e.position), "hits": 0, "hit_at": []})
				elif e.type == "hit" and e.attacker == c.id:
					if not strikes.is_empty() and t >= int(strikes[-1].tick) and t < int(strikes[-1].tick) + window:
						strikes[-1].hits += 1
						strikes[-1].hit_at.append(Vector2(e.position))
					else:
						stray_hits.append(t)
			if CreatureBrain.is_striking(c.brain) and not strikes.is_empty() \
					and absf(angle_difference(c.motion.heading, float(strikes[-1].heading))) > 1e-6 and turned.is_empty():
				turned = "tick %d: %.4f vs %.4f" % [t, c.motion.heading, strikes[-1].heading]
			if sim.dead:
				break
		var landed: int = strikes.reduce(func(n: int, s: Dictionary) -> int: return n + int(s.hits), 0)
		print("test-threats-timings: %s: %d tells, %d strikes, %d hits in their windows, %d outside, %d ticks in reach outside strikes"
			% [species_id, tells.size(), strikes.size(), landed, stray_hits.size(), touching])
		check(strikes.size() >= 1 and landed >= 1, "%s: a strike (%d) and a hit (%d)" % [species_id, strikes.size(), landed])
		check(touching >= 30, "%s: in reach outside its strikes for %d ticks" % [species_id, touching])
		for i in strikes.size():
			check(i < tells.size() and int(strikes[i].tick) - tells[i] == int(attack.tell_ticks),
				"%s strike %d comes %d ticks after its tell" % [species_id, i, int(strikes[i].tick) - (tells[i] if i < tells.size() else 0)])
			check(int(strikes[i].hits) <= 1, "%s strike %d hit at most once (%d)" % [species_id, i, strikes[i].hits])
			if i >= lanes.size():
				continue
			# F1: the strike runs along the lane its tell showed, from its origin (the cell stops short of
			# touching, so nothing pushes the creature through its tell), and lands only inside it.
			var lane: Dictionary = lanes[i]
			check(absf(angle_difference(float(strikes[i].heading), float(lane.heading))) <= 1e-6,
				"%s strike %d runs along its tell's lane (%.4f vs %.4f)" % [species_id, i, strikes[i].heading, lane.heading])
			check(Vector2(strikes[i].position).distance_to(lane.origin) <= 1e-3, "%s strike %d starts at its lane's origin (%.4f m off)" % [
				species_id, i, Vector2(strikes[i].position).distance_to(lane.origin)])
			for at in strikes[i].hit_at:
				check(CreatureBrain.lane_contains(lane, at), "%s strike %d hit the cell at %s, inside its lane" % [species_id, i, at])
		check(stray_hits.is_empty(), "%s: no hit outside a strike's burst and glide (%s)" % [species_id, stray_hits])
		check(turned.is_empty(), "%s: the heading held over every strike (%s)" % [species_id, turned])


func test_a_rammer_cancels_its_puff_when_the_intruder_leaves_its_territory_and_goes_home() -> void:
	# Plan #7: the territory (8 m: a 6 m zone plus the margin) is centred 3 m behind the rammer; the
	# intruder starts 6.5 m from the centre, already swimming out at full speed.
	var center := STRIKE_ORIGIN
	var sim := _sim("hunter", 71, center + Vector2(6.5, 0.0), 0.0)
	sim.motion.velocity = Vector2.RIGHT * sim.phenotype.speed
	var c := _creature(sim, "rammer", center + Vector2(3.0, 0.0), 0.0)
	c.brain.territory_center = center
	_begin_tell(sim, c)
	var home := c.brain.home
	var events := _run(sim, 900, func(_s: PoolSim) -> SimIntent: return SimIntent.new(Vector2.RIGHT),
		func(_s: PoolSim, _t: int) -> bool: return c.brain.state == CreatureBrain.REST or c.brain.phase == CreatureBrain.PATROL)
	var cancelled := _of(events, "tell_cancelled")
	check_eq(cancelled.size(), 1, "the puff was cancelled")
	if cancelled.size() == 1:
		check_eq(cancelled[0].reason, "left_territory", "because the intruder left the territory")
		check(int(cancelled[0].tick) < int(c.brain.cfg.attack.tell_ticks), "during the puff (tick %d)" % cancelled[0].tick)
	check(_of(events, "creature_strike").is_empty(), "no strike")
	check(_of(events, "hit").is_empty(), "no hit")
	check(c.motion.position.distance_to(home) <= 1.0, "the rammer went home (%.2f m away)" % c.motion.position.distance_to(home))


func test_a_dodged_lunge_on_the_cell_reports_one_dodge_and_one_on_a_creature_reports_none() -> void:
	# Plan #8.
	var sim := _sim("grazer", 81, STRIKE_ORIGIN + Vector2(2.75, 0.0), PI / 2.0)
	var c := _creature(sim, "ambush_hunter", STRIKE_ORIGIN, 0.0)
	_begin_tell(sim, c)
	var bot = EvadeBot.new()
	var pending: Array[Dictionary] = []
	var events: Array[Dictionary] = []
	for i in 200:
		sim.step(bot.next_intent(sim, pending))
		pending = sim.drain_events()
		events.append_array(pending)
	var recovered := _of(events, "creature_recovered")
	check(not recovered.is_empty() and recovered[0].outcome == "missed", "the lunge missed")
	var dodged := _of(events, "dodged")
	check_eq(dodged.size(), 1, "one dodge")
	if dodged.size() == 1:
		check_eq([dodged[0].id, dodged[0].species], [c.id, "ambush_hunter"], "naming the creature and its species")
	check_eq(sim.stats.dodges, 1, "counted once")
	check(_of(events, "hit").is_empty(), "and no hit")

	# The same lunge at a scripted body that slips aside: a miss, but no dodge.
	var other := _sim("grazer", 81, Vector2(0.0, 20.0), 0.0)
	var h := _creature(other, "ambush_hunter", STRIKE_ORIGIN, 0.0)
	var decoy := other.creatures.spawn_scripted(SpeciesCatalog.PLAYER_SPECIES, other.phenotype, STRIKE_ORIGIN + Vector2(2.75, 0.0), PI / 2.0, other.tick)
	h.brain.target = decoy.id
	h.brain.seen[decoy.id] = {"position": decoy.motion.position, "velocity": Vector2.ZERO, "tick": other.tick, "by": "sight",
		"species": SpeciesCatalog.PLAYER_SPECIES, "radius": decoy.phenotype.radius, "engageable": true}
	CreatureBrain.begin_tell(h.brain, other.creatures.self_view_of(h), other.tick)
	other.drain_events()
	var on_decoy: Array[Dictionary] = []
	for t in 200:
		decoy.script_move = Vector2.DOWN if t >= EvadeBot.REACTION_TICKS else Vector2.ZERO
		other.step(SimIntent.new())
		on_decoy.append_array(other.drain_events())
	var missed := _of(on_decoy, "creature_recovered").filter(func(e: Dictionary) -> bool: return e.target == decoy.id)
	check(not missed.is_empty() and missed[0].outcome == "missed", "the lunge at the decoy missed")
	check(_of(on_decoy, "dodged").is_empty(), "no dodge for a creature target")


func test_the_evade_bot_stops_dodging_once_the_creature_telling_at_it_is_gone() -> void:
	# A guard on the dev driver: a creature killed in its tell never recovers, and the dodge still ends.
	var sim := _sim("grazer", 82, STRIKE_ORIGIN + Vector2(2.75, 0.0), PI / 2.0)
	var c := _creature(sim, "ambush_hunter", STRIKE_ORIGIN, 0.0)
	_begin_tell(sim, c)
	var bot = EvadeBot.new()
	var pending: Array[Dictionary] = []
	var dodging_at_kill := false
	for t in 60:
		if t == 40:
			dodging_at_kill = bot.is_dodging()
			check(sim.debug_kill_nearest_creature(), "the hunter killed in its tell")
			pending.append_array(sim.drain_events())
		sim.step(bot.next_intent(sim, pending))
		pending = sim.drain_events()
	check(dodging_at_kill, "the cell was dodging when the hunter died")
	check(not bot.is_dodging(), "and stopped once it was gone")


func test_the_forage_bot_minding_threats_passes_over_food_by_a_creature_steers_clear_and_dodges_a_tell() -> void:
	# ForageBot's avoid_threats (plan section 16), which the smoke phases use. Food: the nearer meat
	# lies 4 m from a rammer, the farther one 14 m.
	var sim := _sim("hunter", 83, STRIKE_ORIGIN - Vector2(10.0, 0.0), PI)
	var near: Dictionary = sim.carrion.spawn(STRIKE_ORIGIN - Vector2(6.0, 0.0), "debug")
	var far: Dictionary = sim.carrion.spawn(STRIKE_ORIGIN - Vector2(16.0, 0.0), "debug")
	_creature(sim, "rammer", STRIKE_ORIGIN - Vector2(2.0, 0.0), PI)
	var plain = ForageBot.new()
	plain.next_intent(sim)
	check_eq(plain.target_id(), near.id, "without avoid_threats it swims for the nearer meat")
	var wary = ForageBot.new()
	wary.avoid_threats = true
	wary.next_intent(sim)
	check_eq(wary.target_id(), far.id, "minding threats it passes over the meat beside the rammer")

	# Parked, with a creature 3 m east: pushed west, half the way from THREAT_AVOID_M times the gain.
	var calm := _sim("grazer", 84, STRIKE_ORIGIN, 0.0)
	_creature(calm, "rammer", STRIKE_ORIGIN + Vector2(3.0, 0.0), PI)
	var parked = ForageBot.new()
	parked.park_at = STRIKE_ORIGIN
	check_eq(parked.next_intent(calm).move, Vector2.ZERO, "parked and not minding threats it holds still")
	parked.avoid_threats = true
	var away: Vector2 = parked.next_intent(calm).move
	check(away.x < -0.99 and absf(away.y) < 1e-6, "minding threats it swims straight away west (%s)" % away)

	# A lunge at it: the EvadeBot reaction, 0.4 s after the tell, perpendicular to the lane; it misses.
	var lunge := _sim("grazer", 85, STRIKE_ORIGIN + Vector2(2.75, 0.0), PI / 2.0)
	var c := _creature(lunge, "ambush_hunter", STRIKE_ORIGIN, 0.0)
	_begin_tell(lunge, c)
	var tell_tick := lunge.tick
	var bot = ForageBot.new()
	bot.avoid_threats = true
	bot.park_at = lunge.motion.position
	var events: Array[Dictionary] = []
	var dodge := Vector2.ZERO
	for i in 200:
		var intent: SimIntent = bot.next_intent(lunge)
		if lunge.tick == tell_tick + EvadeBot.REACTION_TICKS:
			dodge = intent.move
		lunge.step(intent)
		events.append_array(lunge.drain_events())
	check(bot.evade != null and bot.evade.tells_seen == 1, "it saw the tell")
	check_eq(bot.evade.reacted_at if bot.evade != null else -1, tell_tick + EvadeBot.REACTION_TICKS, "and reacted 24 ticks after it")
	check(absf(dodge.dot(Vector2.RIGHT)) < 1e-3 and dodge.length() > 0.99, "perpendicular to the lane, at full throttle (%s)" % dodge)
	var recovered := _of(events, "creature_recovered")
	check(not recovered.is_empty() and recovered[0].outcome == "missed", "the lunge missed")
	check(_of(events, "hit").is_empty(), "and nothing hit the cell")


func test_the_forage_bot_minding_threats_feeds_a_grazer_in_the_real_pool_for_two_minutes_untouched() -> void:
	# The smoke phases' driver, in the real pool with every site filled: it eats and is never hit.
	var sim := _sim("grazer", 4242, Vector2.INF, 0.0, layout, species)
	check_eq(sim.creatures.creatures.size(), 7, "every site filled")
	var bot = ForageBot.new()
	bot.avoid_threats = true
	var events := _run(sim, 120 * 60, func(s: PoolSim) -> SimIntent: return bot.next_intent(s))
	var hits := _of(events, "hit").filter(func(e: Dictionary) -> bool: return e.target == PLAYER)
	var meals := _of(events, "ate").size()
	var noticed := _of(events, "creature_noticed").filter(func(e: Dictionary) -> bool: return e.target == PLAYER)
	print("test-threats-wary-forage: %d meals, %d notices, %d hits, dead %s" % [meals, noticed.size(), hits.size(), sim.dead])
	check(meals >= 10, "it ate (%d meals)" % meals)
	check(hits.is_empty(), "nothing hit it")
	check(not sim.dead, "and it lived")


# --- combat both ways (plan threats_sim #9-13) ---

func test_a_hunter_cell_kills_a_rammer_in_five_bites_and_its_carcass_feeds_the_cell_the_next_tick() -> void:
	# Plan #9: the cell comes up behind a resting rammer and keeps biting until it dies.
	var sim := _sim("hunter", 91, STRIKE_ORIGIN - Vector2(1.6, 0.0), 0.0)
	var r := _creature(sim, "rammer", STRIKE_ORIGIN, 0.0)
	r.brain.ignore_all_until = 1 << 40   # resting: it notices nothing until it is bitten
	var at_it := func(s: PoolSim) -> SimIntent: return SimIntent.new((r.motion.position - s.motion.position).normalized())
	var events := _run(sim, 1800, at_it, func(_s: PoolSim, _t: int) -> bool: return sim.creatures.find(r.id) == null)
	var bites := _of(events, "hit").filter(func(e: Dictionary) -> bool: return e.attacker == PLAYER and e.target == r.id)
	check_eq(bites.size(), 5, "five bites")
	check(bites.all(func(e: Dictionary) -> bool: return e.kind == "bite" and is_equal_approx(float(e.damage), 8.0)), "of 8 each")
	var died := _of(events, "creature_died")
	check_eq(died.size(), 1, "the rammer died")
	if died.size() != 1:
		return
	check_eq([died[0].id, died[0].cause, died[0].by], [r.id, "killed", PLAYER], "killed by the cell")
	check_eq(sim.stats.kills, 1, "a kill in the stats")
	var spawned := _of(events, "carrion_spawned")
	check_eq(spawned.map(func(e: Dictionary) -> String: return e.food_id), Array(died[0].carcass), "its carcass is the carrion that appeared")
	check_eq(spawned.size(), 3, "three chunks")
	check(spawned.all(func(e: Dictionary) -> bool: return e.source == "kill" and int(e.tick) == int(died[0].tick)), "from the kill, on its tick")
	# Edible on the next tick: the cell beside one chunk, facing it.
	var chunk := {}
	for item in sim.carrion.items:
		if item.id == died[0].carcass[0]:
			chunk = item
	check(not chunk.is_empty(), "the first chunk is in the carrion")
	if chunk.is_empty():
		return
	sim.debug_set_energy(sim.state.energy_capacity * 0.5)
	var side := Vector2.from_angle(0.7)
	check(sim.debug_teleport(chunk.position - side * (sim.phenotype.radius + float(chunk.radius) + 0.1), side.angle()), "the cell beside the chunk")
	var points := sim.save.adaptation_points
	sim.drain_events()
	sim.step(SimIntent.new())
	var ate := _of(sim.drain_events(), "ate")
	check_eq(ate.size(), 1, "it eats on the next tick")
	if ate.size() == 1:
		check_eq([ate[0].food_id, ate[0].kind, ate[0].points], [chunk.id, "meat", 3], "the chunk, meat, 3 points")
		check(is_equal_approx(float(ate[0].absorbed), 24.0), "24 energy (%.2f)" % ate[0].absorbed)
		check(sim.save.adaptation_points >= points + 3, "the points went through Lineage.earn (%d -> %d)" % [points, sim.save.adaptation_points])


func test_the_cell_fights_back_with_its_jaw_and_spikes_and_backing_away_is_no_ram() -> void:
	# Plan #10. A hunter cell's bite on an ambush hunter deals 8 and knocks it back 0.8 m/s.
	var sim := _sim("hunter", 101, STRIKE_ORIGIN + Vector2(0.75 + 0.5 + 0.2, 0.0), PI)
	var c := _creature(sim, "ambush_hunter", STRIKE_ORIGIN, 0.0)
	sim.debug_set_ai_frozen(true)
	sim.drain_events()
	sim.step(SimIntent.new())
	var hits := _of(sim.drain_events(), "hit")
	check_eq(hits.size(), 1, "one bite")
	if hits.size() == 1:
		check_eq([hits[0].attacker, hits[0].target, hits[0].kind], [PLAYER, c.id, "bite"], "the cell bit the hunter")
		check(is_equal_approx(float(hits[0].damage), 8.0) and is_equal_approx(float(hits[0].dealt), 8.0), "for 8")
		check(is_equal_approx(float(hits[0].target_health), 37.0), "45 -> 37")
		check(is_equal_approx(float(hits[0].knockback), float(species.combat.player_bite_knockback)), "knocked back")
		check(is_equal_approx(c.motion.velocity.length(), 0.8), "at 0.8 m/s (%.3f)" % c.motion.velocity.length())

	# A test genome with one front spike rams a frozen rammer: damage = spike x impact(closing speed).
	var ram := _spiked_sim(102, STRIKE_ORIGIN - Vector2(2.0, 0.0))
	var r := _creature(ram, "rammer", STRIKE_ORIGIN, PI)
	ram.debug_set_ai_frozen(true)
	ram.drain_events()
	var landed := {}
	var closing := 0.0
	for t in 120:
		ram.step(SimIntent.new(Vector2.RIGHT))
		var got := _of(ram.drain_events(), "hit")
		if not got.is_empty():
			landed = got[0]
			closing = ram.motion.velocity.dot((r.motion.position - ram.motion.position).normalized())
			break
	check(not landed.is_empty(), "the spiked cell rammed the rammer")
	if not landed.is_empty():
		var spike: Dictionary = ram.phenotype.spikes[0]
		var expected := float(spike.damage) * clampf(closing / ram.phenotype.speed, 0.25, 1.5)
		check_eq([landed.attacker, landed.target, landed.kind], [PLAYER, r.id, "ram"], "a ram")
		check(absf(float(landed.damage) - expected) < 1e-6, "%.4f damage = %.1f x impact at %.3f m/s closing (%.4f)" % [landed.damage, spike.damage, closing, expected])

	# Backing away from it, spike still pointing at it: refused, quietly, and nothing changes.
	var back := _spiked_sim(103, STRIKE_ORIGIN - Vector2(0.625 + 0.5 + 0.2, 0.0))
	var target := _creature(back, "rammer", STRIKE_ORIGIN, PI)
	back.debug_set_ai_frozen(true)
	back.motion.velocity = Vector2.LEFT * 1.0
	back.drain_events()
	var health := target.state.health
	back.step(SimIntent.new())
	var after := back.drain_events()
	check(_of(after, "hit").is_empty(), "no hit")
	check(_of(after, "attack_refused").is_empty(), "and no refusal reported (a quiet reason)")
	var rams := back.attack_log.filter(func(e: Dictionary) -> bool: return e.kind == "ram")
	check(not rams.is_empty() and rams[-1].reason == "not moving toward it" and not rams[-1].allowed, "the resolver refused it: %s" % [rams])
	check_eq(target.state.health, health, "the rammer is untouched")


## The cell with a test genome: one front spike and a flagellum, nothing else.
func _spiked_sim(seed_value: int, at: Vector2) -> PoolSim:
	var r := Lineage.found(seed_value, "test+dev", catalog, "grazer")
	var g := Genome.new()
	g.add_part("spike", 0.0, 1.0)
	g.add_part("flagellum", PI, 1.0)
	r.save.genome = g
	r.save.player["position"] = PlaneSpace.to_save(fixture.spawn)
	var sim := PoolSim.create(r.save, catalog, fixture, test_species)
	sim.grace_until = sim.tick   # no start shelter, as in _sim
	check(sim.debug_teleport(at, 0.0), "the spiked cell placed")
	sim.drain_events()
	return sim


func test_an_ambush_hunter_kills_a_rammer_that_strays_in_front_of_it_and_then_eats_the_carcass() -> void:
	# Plan #11: creature on creature, the cell far away.
	var sim := _sim("grazer", 111, Vector2(0.0, 20.0))
	var h := _creature(sim, "ambush_hunter", STRIKE_ORIGIN, 0.0, 0.4)
	var r := _creature(sim, "rammer", STRIKE_ORIGIN + Vector2(2.9, 0.0), PI / 2.0)
	r.brain.ignore_all_until = 1 << 40   # it rests on, noticing nothing
	r.state.energy = r.state.energy_capacity   # fed, so it does not swim off to forage
	r.state.health = 10.0                # one bite kills it
	var events := _run(sim, 2400, Callable(), func(s: PoolSim, _t: int) -> bool: return s.stats.creature_meals > 0)
	var died := _of(events, "creature_died")
	check_eq(died.size(), 1, "the rammer died")
	if died.size() != 1:
		return
	check_eq([died[0].id, died[0].cause, died[0].by], [r.id, "killed", h.id], "killed by the hunter")
	check_eq(died[0].carcass.size(), 3, "three chunks")
	var meals := _of(events, "creature_ate").filter(func(e: Dictionary) -> bool: return e.id == h.id)
	check(not meals.is_empty(), "the hungry hunter ate")
	if not meals.is_empty():
		check(Array(died[0].carcass).has(meals[0].food_id) and meals[0].kind == "meat", "a chunk of that carcass (%s)" % meals[0].food_id)


func test_a_cell_pressed_against_a_rock_is_never_pushed_into_it_or_past_6_m_s() -> void:
	# T10 (plan #12): a charge on a cell pressed to a lone rock, from 36 directions; also with the
	# knockback raised to 7 m/s, so the speed clamp has to act.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(THREATS_FIXTURE))
	data.rocks = [{"id": "lone", "asset": "rock_a", "center": [0.0, -16.0], "yaw_deg": 0, "scale": 1.25}]
	var one_rock := PoolLayout.from_dict(data)
	check(one_rock.load_problems.is_empty(), "the one-rock layout loads: %s" % [one_rock.load_problems])
	var rock: Dictionary = one_rock.build_arena().rocks[0]
	for knockback in [-1.0, 7.0]:
		var worst_dig := 0.0
		var fastest := 0.0
		var hits := 0
		for k in 36:
			var u := Vector2.from_angle(k * TAU / 36.0)
			var sim := _sim("grazer", 121, rock.center + u * (rock.radius + 0.5 + 0.02), (-u).angle(), one_rock)
			var c := _creature(sim, "rammer", sim.motion.position + u * 4.0, (-u).angle())
			if knockback > 0.0:
				c.brain.cfg = c.brain.cfg.duplicate(true)
				c.brain.cfg.attack.knockback = knockback
			_begin_tell(sim, c)
			for t in 200:
				sim.step(SimIntent.new(-u))
				for e in sim.drain_events():
					if e.type == "hit" and e.attacker == c.id:
						hits += 1
				for body in [[sim.motion, sim.phenotype.radius], [c.motion, c.phenotype.radius]]:
					var m: Locomotion.MotionState = body[0]
					worst_dig = maxf(worst_dig, float(rock.radius) + float(body[1]) - m.position.distance_to(rock.center))
					fastest = maxf(fastest, m.velocity.length())
		var label := "knockback %s" % ("as in the data" if knockback < 0.0 else "7 m/s")
		print("test-threats-t10: %s: %d rams landed, deepest %.5f m into the rock, fastest %.3f m/s" % [label, hits, worst_dig, fastest])
		check(hits >= 18, "%s: the charges landed (%d of 36)" % [label, hits])
		check(worst_dig <= 0.001, "%s: never more than 1 mm into the rock (%.5f)" % [label, worst_dig])
		check(fastest <= float(species.combat.max_speed_after_hit) + 1e-6, "%s: never faster than 6 m/s (%.3f)" % [label, fastest])


func test_a_mutual_kill_on_one_tick_kills_both_in_the_fixed_order_and_repeats_exactly() -> void:
	# T12 (plan #13): the cell and an ambush hunter at 1 health; the cell's jaw comes ready on the
	# very tick the lunge starts, so both attacks are allowed on that tick.
	var orders := []
	var hashes := []
	for run in 2:
		var sim := _sim("hunter", 131, STRIKE_ORIGIN + Vector2(0.75 + 0.5 + 0.2, 0.0), PI)
		var c := _creature(sim, "ambush_hunter", STRIKE_ORIGIN, 0.0)
		_begin_tell(sim, c)
		var strike_tick: int = sim.tick + int(c.brain.cfg.attack.tell_ticks)
		sim.actor.cooldowns["bite:" + c.id] = strike_tick * PoolSim.DT
		sim.state.health = 1.0
		c.state.health = 1.0
		var events := _run(sim, strike_tick - sim.tick + 5)
		var order := []
		for e in events:
			if e.type in ["hit", "died", "creature_died"]:
				order.append([e.type, int(e.tick) == strike_tick, e.get("attacker", e.get("by", "")), e.get("target", e.get("id", ""))])
		orders.append(order)
		hashes.append(sim.state_hash())
		if run == 0:
			check(sim.dead, "the cell died")
			check(sim.creatures.find(c.id) == null, "the hunter died")
			check_eq(sim.death.get("by_species", ""), "ambush_hunter", "killed by the hunter")
			check_eq(sim.death.get("reason", ""), str(species.species.ambush_hunter.death_reason), "with its death reason")
	var expected := [["hit", true, PLAYER, "c_1"], ["hit", true, "c_1", PLAYER], ["died", true, "c_1", ""], ["creature_died", true, PLAYER, "c_1"]]
	check_eq(orders[0], expected, "both hits, then the cell's death, then the hunter's, all on the strike tick")
	check_eq(orders[1], orders[0], "the second run did the same")
	check_eq(hashes[1], hashes[0], "and hashes the same")


func test_touching_a_creature_with_the_jaw_turned_away_reports_the_refusal_at_most_twice_a_second() -> void:
	# The cell has no attack key (OD3): touching is attacking, and a refusal it can act on is told.
	var sim := _sim("hunter", 141, STRIKE_ORIGIN + Vector2(0.625 + 0.5 + 0.2, 0.0), PI / 2.0)
	var r := _creature(sim, "rammer", STRIKE_ORIGIN, PI / 2.0)
	sim.debug_set_ai_frozen(true)
	sim.drain_events()
	var events := _run(sim, 61)
	var refused := _of(events, "attack_refused")
	check_eq(refused.map(func(e: Dictionary) -> int: return int(e.tick)), [0, 30, 60], "reported at once, then every 0.5 s")
	if not refused.is_empty():
		check_eq([refused[0].target, refused[0].kind, refused[0].reason], [r.id, "bite", "jaw is not facing it"], "the nearest creature, the jaw, why")
	check(_of(events, "hit").is_empty(), "no hit")
	var latest := sim.attack_log.slice(-2)
	check(sim.attack_log.size() == PoolSim.ATTACK_LOG_SIZE, "the attack log keeps the latest %d results" % PoolSim.ATTACK_LOG_SIZE)
	check_eq(latest.map(func(e: Dictionary) -> Array: return [e.kind, e.reason, e.tick]),
		[["bite", "jaw is not facing it", 60], ["ram", "needs a spike", 60]], "quiet reasons included")


func test_dev_commands_kill_the_nearest_creature_and_hurt_the_cell() -> void:
	var sim := _sim("grazer", 151, STRIKE_ORIGIN, 0.0)
	var near := _creature(sim, "rammer", STRIKE_ORIGIN + Vector2(4.0, 0.0), 0.0)
	_creature(sim, "ambush_hunter", STRIKE_ORIGIN + Vector2(-8.0, 0.0), 0.0)
	check(sim.debug_kill_nearest_creature(), "kill the nearest")
	var events := sim.drain_events()
	var died := _of(events, "creature_died")
	check_eq(died.size(), 1, "one creature died")
	if died.size() == 1:
		check_eq([died[0].id, died[0].cause, died[0].by], [near.id, "killed", "debug"], "the nearest, killed by the dev command")
		check_eq(died[0].carcass.size(), 3, "it left its carcass")
	check_eq(_of(events, "debug").size(), 1, "and said so")
	check_eq(sim.stats.kills, 0, "not the cell's kill")
	check(sim.debug_hurt_player(12.0), "hurt the cell")
	check(is_equal_approx(sim.state.health, sim.state.max_health - 12.0), "12 health taken")
	check(not sim.debug_hurt_player(NAN) and not sim.debug_hurt_player(-1.0), "a bad amount is refused")
	check(sim.debug_hurt_player(100.0), "hurt it to death")
	var gone := _of(sim.drain_events(), "died")
	check(sim.dead and gone.size() == 1 and gone[0].cause == "killed" and gone[0].by == "debug", "it died, killed by the dev command")
	check(not sim.debug_hurt_player(1.0), "a dead cell cannot be hurt")
	var plain := _plain_sim("grazer", 151, fixture)
	check(not plain.debug_kill_nearest_creature(), "without creatures there is nothing to kill")


# --- senses: it cannot see your coordinates (plan threats_sim #14-17) ---

func test_a_cell_behind_rocks_beyond_sight_or_behind_a_creature_outside_its_touch_is_never_noticed() -> void:
	# [what, creature at, facing, cell at, how it should be found ("" never)]
	var cases := [
		["behind the wall, within sight range", Vector2(0.0, 4.5), PI / 2.0, Vector2(0.0, 10.5), ""],
		["in the open at 6.6 m, past sight 6 + 0.5", Vector2(0.0, -5.0), PI / 2.0, Vector2(0.0, 1.6), ""],
		["in the open at 6.4 m", Vector2(0.0, -5.0), PI / 2.0, Vector2(0.0, 1.4), "sight"],
		["right behind it at 2.30 m, outside touch", Vector2(0.0, -5.0), PI / 2.0, Vector2(0.0, -7.3), ""],
		["right behind it at 2.20 m, inside touch", Vector2(0.0, -5.0), PI / 2.0, Vector2(0.0, -7.2), "near"],
	]
	for case in cases:
		var sim := _sim("grazer", 14, case[3], 0.0)
		var c := _creature(sim, "ambush_hunter", case[1], case[2])
		if case[0].begins_with("behind the wall"):
			var viewer := sim.creatures.viewer_of(c)
			check_eq(CreatureSenses.perceive(viewer, [sim.player_body()], null).size(), 1, "without rocks it would see it")
			check(CreatureSenses.perceive(viewer, [sim.player_body()], sim.arena).is_empty(), "the wall hides it")
		var noticed := _of(_run(sim, 600), "creature_noticed")
		if case[4].is_empty():
			check(noticed.is_empty(), "%s: never noticed in 600 ticks (%d notices)" % [case[0], noticed.size()])
		else:
			check(not noticed.is_empty(), "%s: noticed" % case[0])
			if not noticed.is_empty():
				check_eq(noticed[0].by, case[4], "%s: by %s" % [case[0], case[4]])
				check(int(noticed[0].tick) < 6, "%s: on its first think (tick %d)" % [case[0], noticed[0].tick])
				check_eq(noticed[0].target, PLAYER, "%s: the cell" % case[0])


func test_a_creature_that_loses_sight_of_the_cell_heads_for_where_it_last_saw_it_and_gives_up_lost() -> void:
	var sim := _sim("grazer", 15, Vector2(3.5, 6.0), 0.0)
	var c := _creature(sim, "ambush_hunter", Vector2(0.0, 4.5), PI / 2.0, 0.5)
	var chasing := func(_s: PoolSim, _t: int) -> bool: return c.brain.state == CreatureBrain.CHASE
	var before := _run(sim, 200, Callable(), chasing)
	check_eq(c.brain.state, CreatureBrain.CHASE, "a hungry hunter chases the cell it noticed")
	check_eq(_of(before, "creature_noticed").size(), 1, "after one notice")
	var last_seen: int = c.brain.seen[PLAYER].tick
	var seen_at: Vector2 = c.brain.seen[PLAYER].position
	var hide := Vector2(0.5, 10.0)
	check(sim.debug_teleport(hide), "the cell slips behind the wall")
	check(c.motion.position.distance_to(hide) <= c.phenotype.sight + sim.phenotype.radius, "still within sight range: only the rocks hide it")
	var start_gap := c.motion.position.distance_to(seen_at)
	var closest := [start_gap]
	var leaked := [0]
	var watch := func(s: PoolSim, _t: int) -> bool:
		if c.brain.seen.has(PLAYER) and Vector2(c.brain.seen[PLAYER].position).is_equal_approx(s.motion.position):
			leaked[0] += 1
		closest[0] = minf(closest[0], c.motion.position.distance_to(seen_at))
		return c.brain.state != CreatureBrain.CHASE
	var events := _run(sim, 400, Callable(), watch)
	var gave_up := _of(events, "creature_gave_up")
	check_eq(gave_up.size(), 1, "it gives up once")
	if gave_up.size() == 1:
		check_eq(gave_up[0].reason, "lost", "because it lost the cell")
		var memory: int = c.brain.cfg.memory_ticks
		var late := int(gave_up[0].tick) - last_seen
		check(late >= memory and late <= memory + 3, "%d ticks after the last percept (memory %d)" % [late, memory])
	check_eq(leaked[0], 0, "what it remembered was never the hidden cell's real position")
	check(closest[0] < start_gap - 0.5, "it swam toward where it last saw the cell (%.2f -> %.2f m)" % [start_gap, closest[0]])
	check(_of(events, "creature_noticed").is_empty(), "and never saw it again")


func test_a_creatures_life_is_the_same_wherever_an_unsensed_cell_is() -> void:
	# T5: one hungry ambush hunter foraging round its home; the cell parked 16 m north or south.
	var a := _sim("grazer", 16, Vector2(0.0, -16.0))
	var b := _sim("grazer", 16, Vector2(0.0, 16.0))
	var ca := _creature(a, "ambush_hunter", Vector2.ZERO, PI / 2.0, 0.4)
	_creature(b, "ambush_hunter", Vector2.ZERO, PI / 2.0, 0.4)
	var differing := 0
	var travelled := 0.0
	for i in 1800:
		var was := ca.motion.position
		a.step(SimIntent.new())
		b.step(SimIntent.new())
		travelled += was.distance_to(ca.motion.position)
		if _creature_json(a) != _creature_json(b):
			differing += 1
	check_eq(differing, 0, "the creature snapshots match on all 1800 ticks")
	check(travelled > 10.0, "the creature was busy (it swam %.1f m)" % travelled)
	check(_of(a.drain_events(), "creature_noticed").is_empty(), "it never sensed the cell")

	# The same with both cells within sight range but behind the wall, at different points.
	var hidden_a := _sim("grazer", 17, Vector2(-1.5, 10.5))
	var hidden_b := _sim("grazer", 17, Vector2(1.5, 10.5))
	var seen_c := _sim("grazer", 17, Vector2(3.0, 6.0))
	var h := _creature(hidden_a, "ambush_hunter", Vector2(0.0, 5.0), PI / 2.0)
	_creature(hidden_b, "ambush_hunter", Vector2(0.0, 5.0), PI / 2.0)
	_creature(seen_c, "ambush_hunter", Vector2(0.0, 5.0), PI / 2.0)
	check(h.motion.position.distance_to(hidden_a.motion.position) < h.phenotype.sight + 0.5, "the hidden cells are within sight range")
	differing = 0
	var control_differs := 0
	for i in 1800:
		for s in [hidden_a, hidden_b, seen_c]:
			s.step(SimIntent.new())
		if _creature_json(hidden_a) != _creature_json(hidden_b):
			differing += 1
		if _creature_json(hidden_a) != _creature_json(seen_c):
			control_differs += 1
	check_eq(differing, 0, "behind the wall, the snapshots match on all 1800 ticks")
	check(control_differs > 0, "control: a cell in clear view changes the creature (%d ticks differ)" % control_differs)


func test_a_scripted_decoy_where_the_cell_would_be_gets_the_same_drive_tick_by_tick() -> void:
	var at := Vector2(0.0, -7.25)
	var script := func(t: int) -> Vector2: return Vector2(0.3, 0.0) if t < 90 else Vector2.ZERO
	# Run A: the cell at P. Run B: the cell parked out of every sense, a decoy at P.
	var a := _sim("grazer", 18, at, 0.0)
	var b := _sim("grazer", 18, Vector2(0.0, 20.0), 0.0)
	var ha := _creature(a, "ambush_hunter", Vector2(0.0, -10.0), PI / 2.0, 0.5)
	var hb := _creature(b, "ambush_hunter", Vector2(0.0, -10.0), PI / 2.0, 0.5)
	var decoy := b.creatures.spawn_scripted(SpeciesCatalog.PLAYER_SPECIES, b.phenotype, at, 0.0, b.tick)
	b.drain_events()
	var compared := 0
	var told := false
	var mismatch := ""
	for t in 300:
		decoy.script_move = script.call(t)
		a.step(SimIntent.new(script.call(t)))
		b.step(SimIntent.new())
		var ea := a.drain_events()
		var eb := b.drain_events()
		if not _of(ea, "hit").is_empty() or not _of(eb, "hit").is_empty():
			break
		if ha.motion.position.distance_to(a.motion.position) < ha.phenotype.radius + a.phenotype.radius:
			break   # bodies in contact are pushed apart in a different pair order from here on
		compared += 1
		told = told or not _of(ea, "creature_tell").is_empty()
		var da: Dictionary = ha.drive.duplicate()
		var db: Dictionary = hb.drive.duplicate()
		var target_ok: bool = (da.target == PLAYER and db.target == decoy.id) or (da.target == "" and db.target == "")
		da.erase("target")
		db.erase("target")
		if mismatch.is_empty() and (da != db or not target_ok):
			mismatch = "tick %d: %s vs %s" % [t, ha.drive, hb.drive]
	check(mismatch.is_empty(), "the drives match: %s" % mismatch)
	check(compared >= 100, "compared %d ticks" % compared)
	check(told, "the comparison covered a tell")
	check_eq(b.creatures.snapshot().creatures[1].species, SpeciesCatalog.PLAYER_SPECIES, "the decoy carries the cell's species")


# --- the creatures' own lives ---

func test_a_hungry_rammer_grazes_plankton_in_its_territory_through_the_resolver() -> void:
	var sim := _sim("grazer", 21, Vector2(0.0, 25.0))
	var c := _creature(sim, "rammer", Vector2(0.0, 1.0), 0.0, 0.5)
	var energy_before := c.state.energy
	var events := _run(sim, 1800)
	var meals := _of(events, "creature_ate")
	check(meals.size() >= 3, "it ate (%d meals)" % meals.size())
	for e in meals:
		check_eq(e.id, c.id, "the rammer ate")
		check_eq(e.kind, "plant", "plankton")
		check(sim.plankton.items.all(func(item: Dictionary) -> bool: return item.id != e.food_id), "%s is gone" % e.food_id)
	check(c.state.energy > energy_before, "its energy rose (%.1f -> %.1f)" % [energy_before, c.state.energy])
	check_eq(sim.stats.creature_meals, meals.size(), "counted")
	check_eq(sim.stats.points_food, 0, "no food points for the lineage")
	check(_of(events, "ate").is_empty(), "the cell ate nothing")


func test_a_creature_that_starves_dies_without_a_carcass_and_frees_its_niche() -> void:
	var sim := _sim("grazer", 22, Vector2(0.0, 25.0))
	var c := sim.creatures.spawn_at("rammer", Vector2(10.0, -10.0), 0.0, "", 0)
	check_eq(sim.region.niches.territorial.count, 1, "a counted rammer")
	c.state.energy = 0.0
	c.state.health = 0.005   # starving costs it 1.5 x 0.25 / 60 health a tick
	var events := _run(sim, 2)
	var died := _of(events, "creature_died")
	check_eq(died.size(), 1, "it died")
	if died.size() == 1:
		check_eq(died[0].cause, "starved", "of starvation")
		check_eq(died[0].carcass, [], "no carcass")
		check_eq(died[0].species, "rammer", "a rammer")
	check(_of(events, "carrion_spawned").is_empty(), "no carrion")
	check(sim.creatures.find(c.id) == null, "gone from the pool")
	check_eq(sim.region.niches.territorial.count, 0, "its niche slot is free")
	check_eq(sim.stats.creature_deaths, 1, "counted")
	var removed := _of(events, "creature_removed")
	check(removed.size() == 1 and events.find(died[0]) < events.find(removed[0]), "creature_died comes before creature_removed")


func test_a_creature_stays_inside_its_leash_and_bodies_never_overlap_in_open_water() -> void:
	var sim := _sim("hunter", 23, Vector2(0.0, -14.0), PI / 2.0)
	var c := _creature(sim, "ambush_hunter", Vector2(0.0, -20.0), PI / 2.0, 0.3)
	var disc := CreatureBrain.leash_disc(c.brain)
	var worst_leash := [0.0]
	var worst_overlap := [0.0]
	var chased := [false]
	var away := func(s: PoolSim) -> SimIntent:
		# Swim south, away from its home, then hold still once well out.
		return SimIntent.new(Vector2(0.0, 1.0) if s.tick < 400 else Vector2.ZERO)
	var watch := func(s: PoolSim, _t: int) -> bool:
		chased[0] = chased[0] or c.brain.state == CreatureBrain.CHASE
		worst_leash[0] = maxf(worst_leash[0], c.motion.position.distance_to(disc.center) - float(disc.radius))
		var gap := c.motion.position.distance_to(s.motion.position) - c.phenotype.radius - s.phenotype.radius
		worst_overlap[0] = maxf(worst_overlap[0], -gap)
		return false
	_run(sim, 900, away, watch)
	check(chased[0], "it chased the cell")
	check(worst_leash[0] <= 1e-3, "never past its leash (worst %.4f m)" % worst_leash[0])
	check(worst_overlap[0] <= 1e-3, "the bodies never overlap at the end of a tick (worst %.4f m)" % worst_overlap[0])
	# Shoved outward at the leash's edge: a hunter cell inside the disc bites and pushes it straight
	# out for 2 s. The hard clamp keeps it on the disc however the hits and contacts push it.
	var shove := _sim("hunter", 23)
	var h := _creature(shove, "ambush_hunter", Vector2(0.0, -20.0), PI / 2.0, 1.0)
	var edge := CreatureBrain.leash_disc(h.brain)
	var out_dir := Vector2.DOWN
	h.motion.position = Vector2(edge.center) + out_dir * float(edge.radius)
	h.motion.heading = out_dir.angle()
	check(shove.debug_teleport(h.motion.position - out_dir * (h.phenotype.radius + shove.phenotype.radius + 0.2),
		out_dir.angle()), "the cell placed inside the disc behind it")
	shove.drain_events()
	var shoved := [0.0]
	var shove_watch := func(_s: PoolSim, _t: int) -> bool:
		shoved[0] = maxf(shoved[0], h.motion.position.distance_to(edge.center) - float(edge.radius))
		return false
	var events := _run(shove, 120, func(_s: PoolSim) -> SimIntent: return SimIntent.new(out_dir), shove_watch)
	var bites := _of(events, "hit").filter(func(e: Dictionary) -> bool: return e.attacker == PLAYER)
	check(not bites.is_empty(), "the cell bit it outward")
	check(shoved[0] <= 1e-3, "shoved outward it stays on its leash (worst %.4f m past)" % shoved[0])


# --- dev commands ---

func test_dev_commands_place_freeze_and_hide_and_refuse_what_does_not_fit() -> void:
	var sim := _sim("grazer", 31, Vector2(0.0, -10.0), PI / 2.0)
	check(not sim.debug_spawn_creature("kraken", Vector2.ZERO, 0.0), "an unknown species is refused")
	check(not sim.debug_spawn_creature("rammer", Vector2(0.0, 8.0), 0.0), "a rock is refused")
	check(sim.debug_spawn_threat_ahead("ambush_hunter"), "a threat ahead")
	var events := sim.drain_events()
	var c: CreatureField.Creature = sim.creatures.creatures[-1]
	check_near(c.motion.position.distance_to(sim.motion.position), PoolSim.DEBUG_THREAT_AHEAD_M, 1e-4, "6 m ahead")
	check_near(absf(angle_difference(c.motion.heading, (sim.motion.position - c.motion.position).angle())), 0.0, 1e-5, "facing the cell")
	check(c.debug, "a dev creature")
	check_eq(_of(events, "creature_spawned").size(), 1, "creature_spawned")
	check_eq(_of(events, "debug").size(), 1, "and a debug event")
	var plain := _plain_sim("grazer", 31, fixture)
	check(not plain.debug_spawn_threat_ahead("rammer"), "a pool without species has no creatures to place")
	check(not plain.debug_set_ai_frozen(true), "nor brains to freeze")

	c.brain.ignore_all_until = 0
	c.state.energy = c.state.energy_capacity * 0.4
	var engaged := func(_s: PoolSim, _t: int) -> bool: return CreatureBrain.is_engaged_with(c.brain, PLAYER)
	_run(sim, 120, Callable(), engaged)
	check(CreatureBrain.is_engaged_with(c.brain, PLAYER), "a hungry hunter engages the cell")
	check(sim.debug_set_hidden(true), "hide from AI")
	var hidden := _run(sim, 300)
	var gave_up := _of(hidden, "creature_gave_up")
	check(not gave_up.is_empty() and gave_up[0].reason == "target_gone", "it gives up on the hidden cell (target_gone)")
	check(_of(hidden, "creature_noticed").is_empty(), "and never notices it while hidden")
	check(sim.creatures.engaged_on_player.is_empty(), "the token is free")
	check(sim.debug_set_hidden(false), "unhide")

	check(sim.debug_set_ai_frozen(true), "freeze")
	c.motion.velocity = Vector2(1.0, 0.0)
	var phase := c.brain.phase_tick
	_run(sim, 120)
	check(c.motion.velocity.length() < 0.05, "a frozen creature coasts to a stop")
	check_eq(c.brain.phase_tick, phase, "and decides nothing")
	check_eq(c.drive.mode, CreatureBrain.MODE_STEER, "its drive is idle")
	check(sim.snapshot().dev_ai_frozen and not sim.snapshot().dev_hidden, "the switches are in the snapshot")


# --- give-up and recovery, the token, the economy (plan threats_sim #18-23) ---

func test_a_hunter_that_cannot_reach_a_cell_behind_the_wall_gives_up_and_lurks_again_within_20_s() -> void:
	# Plan #18: it saw the cell slip behind the wall's middle; the cell stays there.
	var sim := _sim("grazer", 181, Vector2(0.0, 10.5), 0.0)
	var c := _creature(sim, "ambush_hunter", Vector2(0.0, 4.0), PI / 2.0)
	_engage(sim, c)
	var lurking := func(_s: PoolSim, _t: int) -> bool: return c.brain.state == CreatureBrain.REST and c.brain.phase == CreatureBrain.LURK
	var events := _run(sim, 20 * 60, Callable(), lurking)
	var gave_up := _of(events, "creature_gave_up")
	check_eq(gave_up.size(), 1, "it gave up")
	if gave_up.size() == 1:
		check(gave_up[0].reason in ["unreachable", "lost"], "unreachable or lost (%s)" % gave_up[0].reason)
	check(lurking.call(sim, sim.tick), "back in rest/lurk within 20 s (%s/%s)" % [c.brain.state, c.brain.phase])
	check(c.motion.position.distance_to(c.brain.home) <= 1.0, "at home")
	check(_of(events, "creature_tell").is_empty(), "it never told on the hidden cell")


func test_a_chase_ends_on_its_timer_its_leash_or_the_territory_edge_and_the_target_is_then_ignored() -> void:
	# Plan #19. Timer: the cell circles the hunter's home 5 m out at full speed, which holds the
	# pursuer about 3.5 m off (just outside its 3 m window) until the 5 s timer runs out.
	var home := STRIKE_ORIGIN
	var sim := _sim("hunter", 191, home + Vector2(5.0, 0.0), PI / 2.0)
	var c := _creature(sim, "ambush_hunter", home, 0.0, 0.4)
	_engage(sim, c)
	var start := sim.tick
	var orbit := func(s: PoolSim) -> SimIntent:
		var rel := s.motion.position - home
		return SimIntent.new((Vector2(-rel.y, rel.x).normalized() + rel.normalized() * (5.0 - rel.length())).normalized())
	var events := _run(sim, 600, orbit, func(_s: PoolSim, _t: int) -> bool: return not CreatureBrain.is_engaged_with(c.brain, PLAYER))
	var gave_up := _of(events, "creature_gave_up")
	check_eq(gave_up.size(), 1, "timer: it gave up")
	check(_of(events, "creature_tell").is_empty(), "timer: never in its window long enough to tell")
	var g := -1
	if gave_up.size() == 1:
		check_eq(gave_up[0].reason, "timer", "timer: on its timer")
		g = int(gave_up[0].tick)
		check(g - start >= int(c.brain.cfg.give_up_ticks) and g - start <= int(c.brain.cfg.give_up_ticks) + 3, "timer: after %d ticks" % (g - start))
	# The cell keeps circling in view of the hunter, now back home: inside the refractory window it
	# is not noticed again; after it, it is.
	var refractory: int = c.brain.cfg.refractory_ticks
	var later := _run(sim, refractory + 120, orbit)
	var noticed := _of(later, "creature_noticed").filter(func(e: Dictionary) -> bool: return e.target == PLAYER)
	check(not noticed.is_empty() and int(noticed[0].tick) >= g + refractory, "timer: noticed again only after %d ticks (%s)" % [refractory, noticed.map(func(e: Dictionary) -> int: return int(e.tick) - g)])

	# Leash: the cell leads the hunter (displaced 3 m from home) straight out.
	var lead := _sim("hunter", 192, home + Vector2(7.0, 0.0), 0.0)
	var h := _creature(lead, "ambush_hunter", home, 0.0)
	h.motion.place(home + Vector2(3.0, 0.0), 0.0)
	_engage(lead, h)
	var out := _run(lead, 600, func(s: PoolSim) -> SimIntent: return SimIntent.new(Vector2.RIGHT * 0.75 if CreatureBrain.is_engaged_with(h.brain, PLAYER) else Vector2.ZERO),
		func(_s: PoolSim, _t: int) -> bool: return not CreatureBrain.is_engaged_with(h.brain, PLAYER))
	var leash := _of(out, "creature_gave_up")
	check(not leash.is_empty() and leash[0].reason == "leash", "leash: it gave up at its leash (%s)" % [leash.map(func(e: Dictionary) -> String: return e.reason)])
	var resting := func(_s: PoolSim, _t: int) -> bool: return h.brain.state == CreatureBrain.REST and h.motion.position.distance_to(h.brain.home) <= 1.0
	_run(lead, 15 * 60, Callable(), resting)
	check(resting.call(lead, lead.tick), "leash: home and resting within 15 s (%s/%s, %.2f m from home)" % [h.brain.state, h.brain.phase, h.motion.position.distance_to(h.brain.home)])

	# Territory: the rammer chases an intruder near the edge of its reach (territory 8 m plus leash
	# 3 m from the centre); the intruder swims out, a little faster than the rammer, still in sight.
	var leave := _sim("hunter", 193, home + Vector2(10.0, 0.0), 0.0)
	var out_speed := 0.62
	leave.motion.velocity = Vector2.RIGHT * leave.phenotype.speed * out_speed
	var r := _creature(leave, "rammer", home, 0.0)
	r.motion.place(home + Vector2(4.0, 0.0), 0.0)
	_engage(leave, r)
	var gone := _run(leave, 600, func(_s: PoolSim) -> SimIntent: return SimIntent.new(Vector2.RIGHT * out_speed),
		func(_s: PoolSim, _t: int) -> bool: return not CreatureBrain.is_engaged_with(r.brain, PLAYER))
	var left := _of(gone, "creature_gave_up")
	check(not left.is_empty() and left[0].reason == "left_territory", "territory: it gave up when the cell left (%s)" % [left.map(func(e: Dictionary) -> String: return e.reason)])


func test_a_rock_ring_closed_behind_a_hunter_gets_it_removed_as_stuck_and_it_respawns_at_its_site() -> void:
	# Plan #20: a ring of rocks round the hunter's home with one gap; the hunter is outside and the
	# gap is then closed. The cell is far away all along.
	var ring_home := Vector2(-15.0, -15.0)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(THREATS_FIXTURE))
	var rocks: Array = data.rocks.duplicate()
	for i in range(1, 10):
		var p := ring_home + Vector2.from_angle(i * TAU / 10.0) * 3.5
		rocks.append({"id": "ring_%d" % i, "asset": "rock_a", "center": [p.x, p.y], "yaw_deg": 0, "scale": 1.25})
	data.rocks = rocks
	var ring := PoolLayout.from_dict(data)
	check(ring.load_problems.is_empty(), "the ring layout loads: %s" % [ring.load_problems])
	test_species.sites.append({"id": "ring_lair", "species": "ambush_hunter", "home": ring_home, "heading": 0.0, "territory_zone": ""})
	var sim := _sim("grazer", 201, Vector2.INF, 0.0, ring)
	check_eq(sim.creatures.creatures.size(), 1, "the ring's hunter is there")
	var c: CreatureField.Creature = sim.creatures.creatures[0]
	check_eq(c.site_id, "ring_lair", "at its site")
	c.motion.place(ring_home + Vector2(6.0, 0.0), 0.0)
	CreatureBrain._enter(c.brain, CreatureBrain.WANDER, CreatureBrain.RETURN_HOME, sim.tick, c.motion.position)
	sim.arena.add_rock("plug", ring_home + Vector2(3.5, 0.0), 1.25)
	var start := sim.tick
	var timeout: int = c.brain.cfg.nav_timeout_ticks
	var events := _run(sim, 3 * timeout + 600, Callable(),
		func(s: PoolSim, _t: int) -> bool: return s.creatures.creatures.size() == 1 and s.creatures.creatures[0] != c)
	var removed := _of(events, "creature_removed")
	check(not removed.is_empty() and removed[0].reason == "stuck", "removed as stuck (%s)" % [removed])
	if removed.is_empty():
		return
	check(int(removed[0].tick) - start >= 3 * timeout, "after three navigation timeouts (%d ticks)" % (int(removed[0].tick) - start))
	var spawned := _of(events, "creature_spawned")
	check(not spawned.is_empty() and spawned[-1].site == "ring_lair" and int(spawned[-1].tick) > int(removed[0].tick), "then a new hunter at its site")
	if not spawned.is_empty():
		check(Vector2(spawned[-1].position).distance_to(ring_home) < 1e-6, "at its home")
	check(sim.motion.position.distance_to(ring_home) >= float(species.fairness.spawn_safe_m), "the cell was far away")


func test_only_one_creature_engages_the_cell_at_a_time_and_the_other_waits_until_its_timer() -> void:
	# T6 (plan #21): a hungry ambush hunter and a rammer, the cell inside both their reach. The
	# hunter notices first and keeps the token (its own timer lifted for the test); the cell dodges.
	var sim := _sim("grazer", 211, STRIKE_ORIGIN, 0.0)
	var h := _creature(sim, "ambush_hunter", STRIKE_ORIGIN - Vector2(4.0, 0.0), 0.0, 0.4)
	h.brain.cfg = h.brain.cfg.duplicate(true)
	h.brain.cfg.give_up_ticks = 1 << 30
	var r := _creature(sim, "rammer", STRIKE_ORIGIN + Vector2(4.0, 0.0), PI)
	r.brain.ignore_all_until = sim.tick + 20
	var bot = EvadeBot.new()
	bot.base = func(s: PoolSim) -> SimIntent:   # back to its spot between them after each dodge
		var to := STRIKE_ORIGIN - s.motion.position
		return SimIntent.new(to.limit_length(1.0) if to.length() > 0.3 else Vector2.ZERO)
	var pending: Array[Dictionary] = []
	var most := 0
	var rammer_engaged := 0
	var waited := 0
	var gave_up := {}
	var hunter_chased := false
	for t in 900:
		sim.step(bot.next_intent(sim, pending))
		pending = sim.drain_events()
		most = maxi(most, sim.creatures.engaged_on_player.size())
		hunter_chased = hunter_chased or CreatureBrain.is_engaged_with(h.brain, PLAYER)
		if CreatureBrain.is_engaged_with(r.brain, PLAYER):
			rammer_engaged += 1
		if r.brain.state == CreatureBrain.NOTICE and r.brain.target == PLAYER:
			waited += 1
		for e in pending:
			if e.type == "creature_gave_up" and e.id == r.id and gave_up.is_empty():
				gave_up = e
		if not gave_up.is_empty() or sim.dead:
			break
	check(hunter_chased, "the hunter engaged the cell")
	check_eq(most, 1, "never more than one creature engaged on the cell")
	check_eq(rammer_engaged, 0, "the rammer never chased or attacked it")
	check(not gave_up.is_empty() and gave_up.reason == "timer", "the rammer gave up on its timer (%s)" % [gave_up])
	check(waited >= int(r.brain.cfg.give_up_ticks) - int(r.brain.cfg.notice_ticks), "after waiting in notice (%d ticks)" % waited)


func test_a_starving_hunter_cell_kills_a_rammer_and_eats_before_it_starves() -> void:
	# Plan #22: HuntBot closes on the resting rammer from behind and keeps biting, dodges any charge
	# out of its line on the side the cell faces, then eats the carcass.
	var sim := _sim("hunter", 221, STRIKE_ORIGIN - Vector2(6.0, 0.0), 0.0)
	sim.debug_set_energy(0.0)
	var r := _creature(sim, "rammer", STRIKE_ORIGIN, 0.0)
	r.state.energy = r.state.energy_capacity
	var bot = HuntBot.new()
	var pending: Array[Dictionary] = []
	var killed := -1
	var ate := -1
	for t in 60 * 60:
		sim.step(bot.next_intent(sim, pending))
		pending = sim.drain_events()
		for e in pending:
			if e.type == "creature_died" and e.id == r.id and e.by == PLAYER:
				killed = t
			if e.type == "ate" and e.kind == "meat" and ate < 0:
				ate = t
		if sim.dead or (ate >= 0 and not sim.state.is_starving()):
			break
	print("test-threats-starving-hunter: killed at %.1f s, ate at %.1f s, dead %s, starving %s" % [killed / 60.0, ate / 60.0, sim.dead, sim.state.is_starving()])
	check(killed >= 0, "it killed the rammer")
	check(ate > killed, "then ate its meat")
	check(not sim.dead, "before it died")
	check(not sim.state.is_starving(), "and is no longer starving")


func test_every_fed_body_swims_past_the_lair_se_hunter_at_full_speed_and_is_never_hit() -> void:
	# Plan #23, real layout and species: a straight line through z_se's east side that passes
	# 2.75 m from lair_se, inside the hunter's window.
	var lair: Dictionary = species.site("lair_se")
	var lair_at: Vector2 = lair.home
	var x := lair_at.x - 2.75
	for body in BODIES:
		var sim := _sim(body, 231, Vector2.INF, 0.0, layout, species)
		var c: CreatureField.Creature = null
		for k in sim.creatures.creatures:
			if k.site_id == "lair_se":
				c = k
		check(c != null, "%s: the lair_se hunter is there" % body)
		if c == null:
			continue
		_run(sim, 200)   # it settles
		check(sim.debug_teleport(Vector2(x, lair_at.y - 12.0), PI / 2.0), "%s: at the start of the pass" % body)
		var events := _run(sim, 480, func(_s: PoolSim) -> SimIntent: return SimIntent.new(Vector2.DOWN))
		var noticed := _of(events, "creature_noticed").filter(func(e: Dictionary) -> bool: return e.id == c.id and e.target == PLAYER)
		var hits := _of(events, "hit").filter(func(e: Dictionary) -> bool: return e.target == PLAYER)
		print("test-threats-lair-pass: %s: noticed %d, tells %d, hits %d" % [body, noticed.size(), _of(events, "creature_tell").size(), hits.size()])
		check(not noticed.is_empty(), "%s: the hunter noticed the cell going by" % body)
		check(hits.is_empty(), "%s: never hit" % body)
		check(sim.motion.position.y > lair_at.y + 6.0, "%s: it got past (y %.1f)" % [body, sim.motion.position.y])


# --- determinism and coverage (plan threats_sim #24-28) ---

func test_two_runs_with_the_same_seed_and_intents_hash_the_same_and_another_seed_does_not() -> void:
	var runs := []
	for seed_value in [78, 78, 79]:
		var sim := _sim("hunter", seed_value, Vector2.INF, 0.0, layout, species)
		check(sim.debug_spawn_threat_ahead("ambush_hunter"), "a threat ahead")
		var c: CreatureField.Creature = sim.creatures.creatures[-1]
		c.brain.ignore_all_until = 0
		c.state.energy = c.state.energy_capacity * 0.4   # hungry: it chases
		sim.state.health = 10.0                          # and its first bites can kill the cell
		runs.append({"seed": seed_value, "sim": sim, "bot": ForageBot.new(), "hashes": [], "engaged": 0, "kills": 0})
	for t in 3600:
		for run in runs:
			var sim: PoolSim = run.sim
			if run.seed == 79 and t >= 600:
				continue   # seed 79 only has to differ by tick 600
			sim.step(run.bot.next_intent(sim))
			for e in sim.drain_events():
				if e.type == "died" or e.type == "creature_died":
					run.kills += 1
			if not sim.creatures.engaged_on_player.is_empty():
				run.engaged += 1
			if sim.tick % 60 == 0:
				run.hashes.append(sim.state_hash())
	check_eq(runs[0].hashes, runs[1].hashes, "seed 78 twice: the same hash every 60 ticks")
	check(runs[0].hashes.slice(0, 10) != runs[2].hashes.slice(0, 10), "seed 79 differs by tick 600")
	check(runs[0].engaged > 0, "the run included a chase on the cell (%d ticks engaged)" % runs[0].engaged)
	var stats: Dictionary = runs[0].sim.stats
	check(stats.hits_taken > 0 and runs[0].kills > 0, "and a kill: %d hits taken, %d deaths" % [stats.hits_taken, runs[0].kills])
	check_eq(runs[0].hashes.size(), 60, "sixty hashes")


## A sim with a creature in the middle of a tell on the cell and every kind of memory filled in.
func _rich_sim() -> PoolSim:
	var sim := _sim("hunter", 25, Vector2(0.0, -7.25), -PI / 2.0)
	var c := _creature(sim, "ambush_hunter", Vector2(0.0, -10.0), PI / 2.0, 0.5)
	_creature(sim, "rammer", Vector2(10.0, -10.0), 0.0)
	_run(sim, 200, Callable(), func(_s: PoolSim, _t: int) -> bool: return c.brain.phase == CreatureBrain.TELL)
	c.actor.cooldowns["bite:" + PLAYER] = 4.0
	c.brain.ignore["c_9"] = 500
	c.brain.landed_on["c_9"] = 3
	sim.creatures.queue.append({"site": "lair_x", "species": "ambush_hunter", "at_tick": 900})
	return sim


func test_the_state_hash_covers_every_creature_brain_field_and_rng_it_keeps() -> void:
	var base := _rich_sim()
	var c: CreatureField.Creature = base.creatures.creatures[0]
	check_eq(c.brain.phase, CreatureBrain.TELL, "the creature is telling")
	check(base.creatures.engaged_on_player.has(c.id), "and holds the token")
	check(c.brain.seen.has(PLAYER), "it remembers the cell")
	var h0 := base.state_hash()
	check_eq(_rich_sim().state_hash(), h0, "the same build hashes the same")
	for what in PERTURBATIONS:
		var sim := _rich_sim()
		_perturb(sim, what)
		check(sim.state_hash() != h0, "perturbing %s changes the hash" % what)
	check(_no_vectors(base.snapshot()), "every vector in the snapshot is a pair")


func _perturb(s: PoolSim, what: String) -> void:
	var c: CreatureField.Creature = s.creatures.creatures[0]
	match what:
		"creature position.x by one float32 step":
			# 1e-9 m is below float32 resolution away from 0; one step (2^-23 relative) is the smallest change.
			var x := c.motion.position.x
			c.motion.position.x = x + maxf(absf(x) * 1.2e-7, 1e-9)
			check(c.motion.position.x != x, "the position changed")
		"creature velocity":
			c.motion.velocity.y += 1e-3
		"creature heading":
			c.motion.heading += 1e-5
		"creature health":
			c.state.health -= 0.01
		"creature energy":
			c.state.energy -= 0.01
		"a cooldown":
			c.actor.cooldowns["bite:" + PLAYER] = 4.01
		"phase_tick":
			c.brain.phase_tick += 1
		"target":
			c.brain.target = "c_2"
		"lock_heading":
			c.brain.lock_heading += 1e-5
		"a seen position":
			c.brain.seen[PLAYER].position += Vector2(0.001, 0.0)
		"an ignore entry":
			c.brain.ignore["c_9"] = 501
		"landed_on":
			c.brain.landed_on["c_9"] = 4
		"the brain RNG":
			c.brain.rng.randf()
		"the field RNG":
			s.creatures.rng.randf()
		"a queue at_tick":
			s.creatures.queue[0].at_tick = 901
		"engaged_on_player":
			s.creatures.engaged_on_player.append("c_2")
		"the AI frozen switch":
			s.dev_ai_frozen = true
		"the hidden switch":
			s.dev_hidden = true
		"the cell's death":
			s.death = {"cause": "killed"}
		"the shelter's end":
			s.grace_until += 1
		"the death streak":
			s.death_streak += 1


func test_without_creatures_the_species_machinery_changes_nothing_in_the_step_2_pool() -> void:
	# T14: the step 2 run (ForageBot, seed 77) with no species and with species but no sites.
	var plain := _plain_sim("omnivore", 77, layout)
	var r := Lineage.found(77, "test+dev", catalog, "omnivore")
	r.save.player["position"] = PlaneSpace.to_save(layout.spawn)
	var empty := PoolSim.create(r.save, catalog, layout, test_species)
	check(empty.creatures != null and empty.creatures.creatures.is_empty(), "species, but no creatures")
	var bots := [ForageBot.new(), ForageBot.new()]
	var snap_diffs := 0
	var event_diffs := 0
	var first := ""
	var events := 0
	var shelter_ends := []
	for t in 3600:
		plain.step(bots[0].next_intent(plain))
		empty.step(bots[1].next_intent(empty))
		var ea := plain.drain_events()
		var eb: Array[Dictionary] = []
		# The start shelter is the one event only a pool with species has; it changes nothing else.
		for e in empty.drain_events():
			if e.type == "grace_ended":
				e["tick"] = t
				shelter_ends.append(e)
			else:
				eb.append(e)
		events += ea.size()
		if ea != eb:
			event_diffs += 1
		var sb := empty.snapshot()
		for k in CREATURE_KEYS:
			sb.erase(k)
		if plain.snapshot() != sb:   # a deep comparison of every key and value
			snap_diffs += 1
			if first.is_empty():
				first = "tick %d" % t
	check_eq(snap_diffs, 0, "the snapshots match minus the creature keys on every tick (first difference %s)" % first)
	check_eq(event_diffs, 0, "and so do the events, but for the start shelter's end")
	check_eq(shelter_ends, [{"type": "grace_ended", "reason": "timeout", "tick": test_species.start_grace_ticks - 1}],
		"which comes once, on its last tick")
	check(events >= 10 and plain.stats.plankton_eaten > 0, "the run did something (%d events)" % events)


func test_creatures_and_their_respawns_never_draw_from_the_region_rng() -> void:
	# T15: with and without species, the same seed; the creatures frozen, the lair_sw hunter (far from
	# the zones the cell forages in, so the 20 m rule never holds it back) killed and respawned.
	var plain := _plain_sim("grazer", 27, layout)
	var r := Lineage.found(27, "test+dev", catalog, "grazer")
	r.save.player["position"] = PlaneSpace.to_save(layout.spawn)
	var full := PoolSim.create(r.save, catalog, layout, species)
	check_eq(full.creatures.creatures.size(), 7, "seven creatures")
	check_eq(full.region.rng.state, plain.region.rng.state, "identical after create")
	full.debug_set_ai_frozen(true)
	var start_state := plain.region.rng.state
	var bots := [ForageBot.new(), ForageBot.new()]
	var hunter: CreatureField.Creature = full.creatures.find("c_2")
	check_eq(hunter.site_id, "lair_sw", "c_2 is lair_sw's hunter")
	var diffs := 0
	var respawned := -1
	for t in 4300:
		if t == 30:
			full.creatures.remove(hunter, "killed", full.tick, true)
		plain.step(bots[0].next_intent(plain))
		full.step(bots[1].next_intent(full))
		if respawned < 0 and not _of(full.drain_events(), "creature_spawned").is_empty():
			respawned = t
		if plain.region.rng.state != full.region.rng.state:
			diffs += 1
	check(respawned > 30, "lair_sw respawned (tick %d)" % respawned)
	check_eq(diffs, 0, "the region RNG matched on every tick")
	check(plain.region.rng.state != start_state, "the region RNG was in use (plankton regrowth)")


func test_a_tick_with_seven_creatures_costs_well_under_a_millisecond() -> void:
	# Plan #28 with the real data. The name gives the expected cost (about 550 us here, 250 to 365
	# on CI); the limits are STEP_COST_LIMIT_US and STEP_COST_YARDSTICKS. Only sim.step and the
	# yardstick are timed; the replays end in the bot's run's state hash, so all the runs timed the
	# same ticks. Each run's yardstick count is its step time over its yardstick time, and the
	# median counts.
	var intents: Array[Vector2] = []
	var averages: Array[float] = []
	var ratios: Array[float] = []
	var end_hash := 0
	var left := 0
	for run in STEP_COST_RUNS:
		var sim := _sim("omnivore", 91, Vector2.INF, 0.0, layout, species)
		check_eq(sim.creatures.creatures.size(), 7, "run %d: seven creatures" % run)
		var bot = ForageBot.new() if run == 0 else null
		var spent := 0
		var yard := 0
		for i in STEP_COST_TICKS:
			var intent: SimIntent
			if run == 0:
				intent = bot.next_intent(sim)
				intents.append(intent.move)
			else:
				intent = SimIntent.new(intents[i])
			var t0 := Time.get_ticks_usec()
			sim.step(intent)
			spent += Time.get_ticks_usec() - t0
			yard += Yardstick.time_once()
			sim.drain_events()
		averages.append(spent / float(STEP_COST_TICKS))
		ratios.append(spent / float(maxi(yard, 1)))
		if run == 0:
			end_hash = sim.state_hash()
			left = sim.creatures.creatures.size()
		else:
			check_eq(sim.state_hash(), end_hash, "replay %d ended in the bot's run's state, so it timed the same ticks" % run)
	var average: float = averages.min()
	var ratio := Yardstick.median(ratios)
	print("test-threats-step-cost: %.1f us per tick over %d ticks with %d creatures, the fastest of %d timed runs (%s); %.2f yardsticks, the median run (%s)" % [
		average, STEP_COST_TICKS, left, STEP_COST_RUNS, _joined(averages, "%.1f"), ratio, _joined(ratios, "%.2f")])
	check(average <= STEP_COST_LIMIT_US, "average %.1f us per tick (limit %.0f)" % [average, STEP_COST_LIMIT_US])
	check(ratio <= STEP_COST_YARDSTICKS, "a tick costs %.2f yardsticks in the median run (limit %.1f)" % [ratio, STEP_COST_YARDSTICKS])


static func _joined(values: Array[float], format: String) -> String:
	return ", ".join(values.map(func(v: float) -> String: return format % v))


func _no_vectors(value: Variant) -> bool:
	if value is Vector2 or value is Vector3:
		return false
	if value is Dictionary:
		for k in value:
			if not _no_vectors(value[k]):
				return false
	if value is Array:
		for v in value:
			if not _no_vectors(v):
				return false
	return true
