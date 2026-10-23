extends TestCase
## The growth meter (S2 T2.1 onward; game/systems/world/growth.gd): it exists only in the endless
## world with growth switched on (D-46, BP-20), the drain moves energy above the floor into the meter
## at its capped rate and never past the ring (S2G20), a full ring at the build top pays out at once
## (D-32), and the trigger comes only through the intent (S2G22).

const FakeWorldGen := preload("res://tests/fakes/fake_world_gen.gd")
const SEED := 5101
## The world snapshot keys S1 wrote (test_endless_sim's perturbation list and the counters), which a
## world with growth off must keep exactly (BP-6, BP-20).
const S1_WORLD_KEYS := ["cell_tile", "checkpoint_am", "chunks", "counters", "gen_version", "origin_am",
	"respawn_pending", "site_counts", "size", "sleeping", "slots", "zone_rngs"]
const S1_COUNTERS := ["awake_overflow", "chunk_waits", "evictions", "food_trimmed"]
## Spine 3.12's growth keys.
const GROWTH_KEYS := ["armed", "beat_until", "blocked", "blocker", "calm", "closing", "discoveries", "due",
	"energy_at_death", "full_since", "last_bite", "last_meal", "last_ram", "meter", "paid", "trigger"]
var catalog: PartCatalog
var layout: PoolLayout


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()


## An endless sim (fake generator, the shipped world file, no creatures) with growth on: size 2 is
## the build top.
func _growth_sim() -> PoolSim:
	var sim := FakeWorldGen.endless_sim(SEED, catalog, layout, null, null, PackedFloat64Array(), 4, true)
	sim.drain_events()
	return sim


static func _of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		if e.type == type:
			out.append(e)
	return out


func test_growth_exists_only_in_the_endless_world_with_its_switch_on() -> void:
	var off := FakeWorldGen.endless_sim(SEED, catalog, layout, null)
	check(off.growth == null, "growth off: no meter (D-46)")
	var world: Dictionary = off.snapshot().world
	var keys := world.keys()
	keys.sort()
	check_eq(keys, S1_WORLD_KEYS, "growth off: the world block is S1's, key for key (BP-20)")
	var counters: Array = world.counters.keys()
	counters.sort()
	check_eq(counters, S1_COUNTERS, "growth off: no remnant_overflow counter (BP-20)")
	check_eq(off.size(), 1, "size 1")
	var pool := PoolSim.create(Lineage.found(SEED, "test+dev", catalog, "omnivore").save, catalog, layout)
	check(pool.growth == null, "the pool has no meter")
	check_eq(pool.size(), 1, "the pool is size 1")
	check(not pool.snapshot().has("world"), "the pool snapshot is M1's")
	var on := _growth_sim()
	check_eq(on.world.max_size, 2, "the build top from the world file")
	var on_world: Dictionary = on.snapshot().world
	for key in ["growth", "carrion_radius", "carrion_lifetime"]:
		check(on_world.has(key), "growth on: world.%s" % key)
	check(on_world.counters.has("remnant_overflow"), "growth on: counters.remnant_overflow")
	var gkeys: Array = on_world.growth.keys()
	gkeys.sort()
	check_eq(gkeys, GROWTH_KEYS, "the growth block's keys (spine 3.12)")


func test_growth_reads_the_prefetch_keys() -> void:
	var cfg := WorldConfig.load_from().growth.duplicate(true)
	cfg.prefetch_share = 0.75
	cfg.prefetch_per_tick = 3
	var g := Growth.create(cfg, "press")
	check_eq(g.prefetch_share, 0.75, "prefetch_share")
	check_eq(g.prefetch_per_tick, 3, "prefetch_per_tick")
	check_eq(g.trigger, "press", "the trigger it was made with")


func test_the_ring_table_covers_sizes_one_to_nine() -> void:
	var cfg := WorldConfig.load_from().growth
	var g := Growth.create(cfg, "auto")
	for n in range(1, 10):
		check_eq(g.ring(n), float(cfg.rings[n - 1]), "size %d: rings[%d]" % [n, n - 1])
	check_eq(g.ring(10), 0.0, "no ring past the table")
	check_eq(g.ring(0), 0.0, "nor before it")
	var r := g.ring(1)
	g.meter = r - 1e-10
	check(g.is_full(1), "within 1e-9 of the ring is full")
	g.meter = r - 1e-6
	check(not g.is_full(1), "short of the ring")
	g.meter = 500.0
	check(not g.is_full(10), "never full without a ring")


func test_the_drain_moves_energy_above_the_floor_at_its_capped_rate() -> void:
	var sim := _growth_sim()
	var g := sim.growth
	var cap := sim.state.energy_capacity
	var floor_e := float(g.cfg.drain_floor_share) * cap
	var rate := g.ring(1) / float(g.cfg.drain_ring_seconds) * PoolSim.DT
	sim.state.energy = cap
	g._drain(sim)
	check_near(g.meter, rate, 1e-12, "one tick: ring / drain_ring_seconds")
	check_near(sim.state.energy, cap - rate, 1e-12, "taken from the energy")
	sim.state.energy = floor_e + rate * 0.25
	var before := g.meter
	g._drain(sim)
	check_near(g.meter - before, rate * 0.25, 1e-12, "only what lies above the floor")
	check_eq(sim.state.energy, floor_e, "down to the floor exactly")
	before = g.meter
	g._drain(sim)
	check_eq(g.meter, before, "nothing at the floor")
	sim.state.energy = floor_e - 1.0
	g._drain(sim)
	check_eq(g.meter, before, "nothing below it")
	check_eq(_of(sim.drain_events(), "meter_lump").size(), 0, "the drain is no lump")


func test_a_running_drain_never_takes_energy_below_the_floor() -> void:
	var sim := _growth_sim()
	var g := sim.growth
	var cap := sim.state.energy_capacity
	var floor_e := float(g.cfg.drain_floor_share) * cap
	var rate := g.ring(1) / float(g.cfg.drain_ring_seconds) * PoolSim.DT
	sim.debug_set_energy(floor_e + 60.0 * rate)
	var drained := 0
	var reached := false
	for t in 240:
		var before := g.meter
		sim.step(SimIntent.new())
		var gained := g.meter - before
		if gained > 0.0:
			drained += 1
			check(gained <= rate + 1e-12, "tick %d: at most the capped rate (%f)" % [t, gained])
			check(sim.state.energy >= floor_e - 1e-9, "tick %d: drained below the floor (%f < %f)" % [t, sim.state.energy, floor_e])
			reached = reached or sim.state.energy == floor_e
	check(drained > 10, "the drain ran (%d ticks)" % drained)
	check(reached, "it stopped at the floor exactly")
	check(g.meter > 0.0 and g.meter < g.ring(1), "part of the ring (%f)" % g.meter)


func test_the_meter_stops_at_the_ring_and_reports_it_full_once() -> void:
	var sim := _growth_sim()
	var g := sim.growth
	g.meter = g.ring(1) - 0.001
	sim.state.energy = sim.state.energy_capacity
	sim.step(SimIntent.new())
	var events := sim.drain_events()
	check_eq(g.meter, g.ring(1), "exactly the ring")
	check_eq(g.full_since, sim.tick - 1, "full since the tick it filled")
	var full := _of(events, "ring_full")
	check_eq(full.size(), 1, "ring_full once")
	if full.size() == 1:
		check_eq(full[0].size, 1, "at size 1")
		check_eq(full[0].ring, g.ring(1), "with its ring")
	var energy := sim.state.energy
	sim.step(SimIntent.new())
	check_eq(g.meter, g.ring(1), "still the ring")
	check_eq(_of(sim.drain_events(), "ring_full").size(), 0, "not reported again")
	check(sim.state.energy < energy, "a full ring drains nothing (only upkeep): %f" % sim.state.energy)
	check_near(energy - sim.state.energy, sim.phenotype.upkeep * PoolSim.DT, 1e-9, "upkeep alone")


func test_a_lump_reports_the_part_it_kept() -> void:
	var sim := _growth_sim()
	var g := sim.growth
	g.meter = g.ring(1) - 5.0
	g.add(sim, 12.0, "place", "giant_husk")
	var lumps := _of(sim.drain_events(), "meter_lump")
	check_eq(lumps.size(), 1, "one lump")
	if lumps.size() == 1:
		check_eq(lumps[0].amount, 5.0, "only the part up to the ring")
		check_eq(lumps[0].reason, "place", "its reason")
		check_eq(lumps[0].id, "giant_husk", "its id")
	check_eq(g.meter, g.ring(1), "capped at the ring")


func test_a_full_ring_at_the_build_top_pays_out_at_once() -> void:
	var sim := _growth_sim()
	var g := sim.growth
	sim.world.max_size = 1   # size 1 is the top
	sim.state.energy = sim.state.energy_capacity * 0.5
	var points := sim.save.adaptation_points
	g.add(sim, g.ring(1), "debug", "")
	var events := sim.drain_events()
	check_eq(sim.state.energy, sim.state.energy_capacity, "energy refilled")
	check_eq(sim.save.adaptation_points, points + int(g.cfg.top_payout_points), "the payout's points, through Lineage.earn")
	check_eq(g.meter, 0.0, "the meter starts again")
	check_eq(g.full_since, -1, "not full")
	var types := []
	for e in events:
		types.append(e.type)
	check_eq(types, ["meter_lump", "ring_full", "earned", "ring_paid"], "the payout's events in order")
	var earned := _of(events, "earned")
	if earned.size() == 1:
		check_eq(earned[0].points, 10, "10 points")
		check_eq(earned[0].reason, "ring", "for the ring")
	var paid := _of(events, "ring_paid")
	if paid.size() == 1:
		check_eq(paid[0].size, 1, "at the top size")
		check_eq(paid[0].points, 10, "the points")
		check_eq(paid[0].energy, sim.state.energy_capacity, "the energy")


func test_below_the_top_a_full_ring_does_not_pay_out() -> void:
	var sim := _growth_sim()
	var g := sim.growth
	sim.state.energy = sim.state.energy_capacity * 0.5
	var points := sim.save.adaptation_points
	g.add(sim, g.ring(1), "debug", "")
	check_eq(g.meter, g.ring(1), "full")
	check_eq(sim.save.adaptation_points, points, "no points")
	check_eq(_of(sim.drain_events(), "ring_paid").size(), 0, "no payout")


func test_the_trigger_comes_only_through_the_intent() -> void:
	var sim := _growth_sim()
	var g := sim.growth
	check_eq(g.trigger, "auto", "the world file's default")
	g.meter = g.ring(1)   # full, so an arm is kept (a press arms only a full ring)
	g.full_since = 0
	g.armed = true
	var press := SimIntent.new()
	press.trigger = "press"
	sim.step(press)
	check_eq(g.trigger, "press", "the intent's setting")
	check(not g.armed, "a change disarms")
	g.armed = true
	sim.step(SimIntent.new())
	check_eq(g.trigger, "press", "\"\" leaves it")
	check(g.armed, "and keeps the arm")
	var odd := SimIntent.new()
	odd.trigger = "sometimes"
	sim.step(odd)
	check_eq(g.trigger, "press", "an unknown setting is ignored")
	sim.step(press)
	check(g.armed, "the same setting again changes nothing")
	var back := SimIntent.new()
	back.trigger = "auto"
	sim.step(back)
	check_eq(g.trigger, "auto", "back to auto")
	check_eq(sim.snapshot().world.growth.trigger, "auto", "in the snapshot")


func test_the_meter_holds_while_the_cell_is_dead() -> void:
	var sim := _growth_sim()
	var g := sim.growth
	sim.state.energy = sim.state.energy_capacity
	sim.debug_hurt_player(sim.state.health)
	check(sim.dead, "dead")
	sim.state.energy = sim.state.energy_capacity
	for t in 30:
		sim.step(SimIntent.new())
	check_eq(g.meter, 0.0, "no drain while dead")
	sim.respawn_player()
	check(sim.respawn_pending, "waiting for its respawn")


func test_carrion_with_its_own_radius_or_lifetime_is_in_the_snapshot() -> void:
	var sim := _growth_sim()
	var item := sim.carrion.spawn(Vector2(3.0, 0.0), "kill")
	var world: Dictionary = sim.snapshot().world
	check(not world.carrion_radius.has(item.id), "a default item is left out")
	item.radius = 0.1875
	item.lifetime = sim.carrion.lifetime * 0.5
	world = sim.snapshot().world
	check_eq(world.carrion_radius.get(item.id), 0.1875, "its radius")
	check_eq(world.carrion_lifetime.get(item.id), sim.carrion.lifetime * 0.5, "its lifetime")


# --- T2.3: the calm window, the blockers, press and arm, the hints (S2G9, S2G22; BP-5, D-48, D-49, D-86) ---

## A growth sim with creatures (none near the start) and every brain frozen, so a test sets their
## states by hand; its showcase window cut to SHOWCASE_S so the auto tests run short.
const SHOWCASE_S := 2.0


func _calm_sim() -> PoolSim:
	var sim := FakeWorldGen.endless_sim(SEED, catalog, layout, SpeciesCatalog.load_from(), null, PackedFloat64Array(), 4, true)
	sim.debug_set_ai_frozen(true)
	sim.growth.cfg.showcase_s = SHOWCASE_S
	sim.drain_events()
	return sim


## Fills the ring now (the tick's full_since).
func _fill(sim: PoolSim) -> void:
	sim.growth.add(sim, sim.growth.ring(sim.size()) - sim.growth.meter, "debug", "")
	sim.drain_events()


## One tick with no movement, a G press when `grow`, and a trigger setting when one is given.
func _tick(sim: PoolSim, grow := false, trigger := "") -> Array[Dictionary]:
	var intent := SimIntent.new()
	intent.grow = grow
	intent.trigger = trigger
	sim.step(intent)
	return sim.drain_events()


## A dev rammer (frozen, at rest) `d` tm from the cell at `angle` (cell frame), or null.
func _rammer(sim: PoolSim, d: float, angle := 0.0) -> CreatureField.Creature:
	var p := sim.motion.position + Vector2.from_angle(angle) * d
	if not sim.debug_spawn_creature("rammer", p, angle + PI):
		return null
	var spawned := _of(sim.drain_events(), "debug")
	return sim.creatures.find(str(spawned[0].id)) if not spawned.is_empty() else null


func test_auto_counts_calm_ticks_after_the_showcase_and_sets_due_at_calm_ticks() -> void:
	var sim := _calm_sim()
	var g := sim.growth
	check_eq(g.blocker_of(sim), "", "a quiet start is calm")
	_fill(sim)
	var full_at := g.full_since
	var showcase := CreatureBrain.ticks(SHOWCASE_S)
	var need := int(g.cfg.calm_ticks)
	var first := -1
	var due_at := -1
	for t in showcase + need + 10:
		var at := sim.tick
		_tick(sim)
		if first < 0 and g.calm_ticks > 0:
			first = at
		if g.due:
			due_at = at
			break
	check_eq(first, full_at + showcase, "the first calm tick counts once the showcase is over")
	check_eq(due_at, full_at + showcase + need - 1, "due on the %dth counted tick" % need)
	check_eq(g.calm_ticks, need, "calm_ticks reached")
	check_eq(g.hint(), Growth.HINT_GROWING, "the HUD says Growing")


func test_press_counts_only_once_armed_and_a_press_on_an_unfilled_ring_does_nothing() -> void:
	var sim := _calm_sim()
	var g := sim.growth
	_tick(sim, true, "press")
	check(not g.armed, "a press before the ring is full does nothing")
	_fill(sim)
	check_eq(g.hint(), Growth.HINT_READY, "full and not armed: ready")
	for t in CreatureBrain.ticks(SHOWCASE_S) + 60:
		_tick(sim)
	check_eq(g.calm_ticks, 0, "press mode never counts unarmed, showcase or not")
	check(not g.due, "not due")
	var events := _tick(sim, true)
	check(g.armed, "G arms it")
	check(_of(events, "growth_waiting").is_empty(), "calm: no waiting notice")
	for t in int(g.cfg.calm_ticks) - 1:
		_tick(sim)
	check(g.due, "due after calm_ticks counted ticks from the press")


func test_each_blocker_in_priority_order() -> void:
	var sim := _calm_sim()
	var g := sim.growth
	check(sim.phenotype.bite_damage > 0.0, "the cell has a jaw (the chase cases need one)")
	var c := _rammer(sim, 6.0)
	check(c != null, "a rammer 6 tm off")
	if c == null:
		return
	check_eq(g.blocker_of(sim), "", "a rammer at rest 6 tm off is no blocker")
	var b := c.brain
	for phase in [CreatureBrain.TELL, CreatureBrain.STRIKE, CreatureBrain.GLIDE]:
		b.state = CreatureBrain.ATTACK
		b.phase = phase
		b.target = CreatureField.PLAYER_ID
		check_eq(g.blocker_of(sim), "hunted", "an attack %s aimed at the cell" % phase)
	b.phase = CreatureBrain.AIM
	check_eq(g.blocker_of(sim), "", "aiming is not yet hunting")
	b.phase = CreatureBrain.TELL
	b.target = "c_99"
	check_eq(g.blocker_of(sim), "", "a tell aimed at someone else")
	b.state = CreatureBrain.REST
	b.phase = ""
	b.target = ""
	sim.creatures.engaged_on_player.append(c.id)
	check_eq(g.blocker_of(sim), "hunted", "the token held on the cell")
	sim.creatures.engaged_on_player.clear()
	var touch := sim.phenotype.radius + c.phenotype.radius + PoolSim.TOUCH_MARGIN
	c.motion.position = sim.motion.position + Vector2(touch - 1e-3, 0.0)
	check_eq(g.blocker_of(sim), "hunted", "a touch")
	c.motion.position = sim.motion.position + Vector2(touch + 1e-3, 0.0)
	check_eq(g.blocker_of(sim), "", "just out of touch")
	# The cell's own bites, rams and meals, read from the tick's events; then the priority order.
	var quiet := int(g.cfg.quiet_ticks)
	sim.creatures.engaged_on_player.append(c.id)
	g.observe(sim, [{"type": "hit", "attacker": CreatureField.PLAYER_ID, "kind": "bite"},
		{"type": "ate", "kind": "plant"}])
	check_eq(g.blocker_of(sim), "hunted", "hunted comes first")
	sim.creatures.engaged_on_player.clear()
	check_eq(g.blocker_of(sim), "chasing", "a bite: chasing before eating")
	g.last_bite = sim.tick - quiet
	check_eq(g.blocker_of(sim), "eating", "quiet_ticks after the bite: eating")
	g.last_meal = sim.tick - quiet
	check_eq(g.blocker_of(sim), "", "quiet_ticks after the meal: calm")
	g.observe(sim, [{"type": "hit", "attacker": CreatureField.PLAYER_ID, "kind": "ram"}])
	check_eq(g.last_ram, sim.tick, "a ram is noted")
	check_eq(g.blocker_of(sim), "chasing", "a ram: chasing")
	g.last_ram = sim.tick - quiet + 1
	check_eq(g.blocker_of(sim), "chasing", "one tick short of quiet_ticks")
	g.last_ram = sim.tick - quiet
	g.observe(sim, [{"type": "hit", "attacker": c.id, "target": CreatureField.PLAYER_ID, "kind": "ram"}])
	check_eq(g.blocker_of(sim), "", "a creature's hit on the cell is not the cell chasing")


## The chase by the closing history: a fleeing creature the cell closes on by more than
## chase_close_tm over chase_window_ticks blocks; one held at its distance, one not fleeing, or one
## beyond chase_track_tm does not.
func test_closing_on_a_fleeing_creature_is_chasing() -> void:
	var sim := _calm_sim()
	var g := sim.growth
	var window := int(g.cfg.chase_window_ticks)
	var close := float(g.cfg.chase_close_tm)
	var cases := [
		# [name, start distance, closing per tick, state, blocks]
		["closing in while it flees", 8.0, (close + 0.2) / window, CreatureBrain.FLEE, true],
		["held at its distance", 8.0, 0.0, CreatureBrain.FLEE, false],
		["closing just short", 8.0, (close - 0.05) / window, CreatureBrain.FLEE, false],
		["closing in while it does not flee", 8.0, (close + 0.2) / window, CreatureBrain.WANDER, false],
		["closing in beyond the track", float(g.cfg.chase_track_tm) + 2.0 + close, (close + 0.2) / window, CreatureBrain.FLEE, false],
	]
	for row in cases:
		var s := _calm_sim()
		var gs := s.growth
		var c := _rammer(s, float(row[1]))
		if c == null:
			check(false, "%s: placed" % row[0])
			continue
		var dir := (c.motion.position - s.motion.position).normalized()
		var d := float(row[1])
		var hit := false
		for t in window + 5:
			c.brain.state = row[3]
			c.motion.position = s.motion.position + dir * d
			c.motion.velocity = Vector2.ZERO
			_tick(s)
			hit = hit or gs.blocker_of(s, false) == "chasing"
			d -= float(row[2])
		check_eq(hit, row[4], row[0])
		check(gs.closing.size() <= window + 1, "%s: at most chase_window_ticks + 1 entries" % row[0])
	# The history itself: oldest first, one entry a tick, the newest this tick.
	var last: Array = g.closing
	check(last.is_empty(), "no ticks yet, no history")
	for t in window + 10:
		_tick(sim)
	check_eq(g.closing.size(), window + 1, "a full window")
	check_eq(int(g.closing[-1][0]), sim.tick - 1, "the newest is the last tick")
	check_eq(int(g.closing[0][0]), sim.tick - 1 - window, "the oldest chase_window_ticks before it")


func test_a_broken_window_starts_again() -> void:
	var sim := _calm_sim()
	var g := sim.growth
	var c := _rammer(sim, 7.0, PI)
	_fill(sim)
	g.full_since -= CreatureBrain.ticks(SHOWCASE_S)   # the showcase is over
	for t in 50:
		_tick(sim)
	check_eq(g.calm_ticks, 50, "fifty calm ticks counted")
	sim.creatures.engaged_on_player.append(c.id)
	_tick(sim)
	check_eq(g.calm_ticks, 0, "one hunted tick breaks the window")
	sim.creatures.engaged_on_player.clear()
	for t in int(g.cfg.calm_ticks) - 1:
		_tick(sim)
		check(not g.due, "not due before a fresh calm_ticks (tick %d)" % t)
	_tick(sim)
	check(g.due, "due after a fresh calm_ticks")


func test_a_long_block_is_named_and_cleared_and_a_short_one_says_nothing() -> void:
	var sim := _calm_sim()
	var g := sim.growth
	var c := _rammer(sim, 7.0, PI)
	_fill(sim)
	var hint_at := CreatureBrain.ticks(g.cfg.blocked_hint_s)
	sim.creatures.engaged_on_player.append(c.id)
	var blocked: Array[Dictionary] = []
	for t in hint_at - 1:
		blocked.append_array(_of(_tick(sim), "growth_blocked"))
	check(blocked.is_empty(), "nothing named before blocked_hint_s")
	check_eq(g.hint(), "", "and no hint yet")
	sim.creatures.engaged_on_player.clear()
	check(_of(_tick(sim), "growth_unblocked").is_empty(), "a short block clears without a notice")
	sim.creatures.engaged_on_player.append(c.id)
	for t in hint_at:
		blocked.append_array(_of(_tick(sim), "growth_blocked"))
	check_eq(blocked, [{"type": "growth_blocked", "blocker": "hunted"}] as Array[Dictionary], "named once, at blocked_hint_s")
	check_eq(g.hint(), Growth.BLOCKER_HINTS.hunted, "the HUD names it")
	sim.creatures.engaged_on_player.clear()
	g.observe(sim, [{"type": "ate", "kind": "plant"}])   # a meal: the blocker changes
	blocked = _of(_tick(sim), "growth_blocked")
	check_eq(blocked, [{"type": "growth_blocked", "blocker": "eating"}] as Array[Dictionary], "named again when it changes")
	check_eq(g.hint(), Growth.BLOCKER_HINTS.eating, "the HUD follows")
	g.last_meal = -Growth.NEVER
	var events := _tick(sim)
	check_eq(_of(events, "growth_unblocked").size(), 1, "the first calm tick clears it")
	check_eq(g.blocker, "", "no blocker")


func test_a_press_in_danger_waits_and_says_so() -> void:
	var sim := _calm_sim()
	var g := sim.growth
	var c := _rammer(sim, 6.0)
	_tick(sim, false, "press")
	_fill(sim)
	c.brain.state = CreatureBrain.ATTACK
	c.brain.phase = CreatureBrain.TELL
	c.brain.target = CreatureField.PLAYER_ID
	var events := _tick(sim, true)
	check(g.armed, "the press arms it")
	check_eq(_of(events, "growth_waiting"), [{"type": "growth_waiting", "reason": "hunted"}] as Array[Dictionary], "and says why it waits")
	check_eq(g.hint(), Growth.HINT_NOT_WHILE_HUNTED, "at once")
	for t in int(g.cfg.calm_ticks) + 30:
		c.brain.state = CreatureBrain.ATTACK
		c.brain.phase = CreatureBrain.TELL
		_tick(sim)
	check(not g.due, "no growth during a tell")
	check_eq(g.calm_ticks, 0, "nothing counted")
	c.brain.state = CreatureBrain.REST
	c.brain.phase = ""
	c.brain.target = ""
	for t in int(g.cfg.calm_ticks):
		_tick(sim)
	check(g.due, "once calm, the armed press grows")


## D-49: in auto mode a creature that will flip at the next size, in view, starts the count before
## the showcase is over; one out of view does not.
func test_auto_counts_at_once_with_a_flipping_creature_in_view() -> void:
	var sim := _calm_sim()
	var g := sim.growth
	g.cfg.showcase_s = 1000.0
	var far := _rammer(sim, 40.0, -PI / 2.0)
	check(far != null, "a rammer out of view")
	_fill(sim)
	for t in 30:
		_tick(sim)
	check_eq(g.calm_ticks, 0, "no flip creature in view: the showcase holds")
	var role := str(sim.species.at_size("rammer", 2).ladder_role)
	check(role == "rival" or role == "prey", "an M1 rammer flips at size 2 (%s)" % role)
	var near := _rammer(sim, 8.0)
	check(near != null, "a rammer 8 tm off, in view")
	_tick(sim)
	check_eq(g.calm_ticks, 1, "it starts the count")
	near.motion.position = sim.motion.position + Vector2(0.0, -45.0)
	_tick(sim)
	check_eq(g.calm_ticks, 2, "a started count goes on")


## S2G35 (BP-4): a cell whose point is shut at the next size (a shell there over every ring within the
## wedge, though the water is open at size 1) is "wedged": the window never counts and the blocker is
## named once it has blocked for blocked_hint_s; once the cell is clear the window counts again and the
## cell grows once, onto open water.
func test_the_wedge_blocker_holds_a_shut_cell_and_lets_it_grow_once_clear() -> void:
	var sim := _growth_sim()
	var g := sim.growth
	g.cfg.showcase_s = SHOWCASE_S
	var w := sim.world
	var a := w.abs_of_local(sim.motion.position)
	var s1 := WorldConfig.tm_to_am(2)
	var x := a[0] / s1
	var y := a[1] / s1
	w.gen.extra_shells[Vector3i(floori(x / w.chunk_tm), floori(y / w.chunk_tm), 2)] = [{"x": x, "y": y, "r": 1.8}]
	w._clear_next()
	check(sim.arena.is_clear(sim.motion.position, sim.phenotype.radius), "open water at size 1")
	check(not w.next_size_clear_point(sim).is_finite(), "shut at size 2")
	_fill(sim)
	var blocked: Array[Dictionary] = []
	for t in CreatureBrain.ticks(SHOWCASE_S) + g._hint_ticks() + 30:
		blocked.append_array(_of(_tick(sim), "growth_blocked"))
	check_eq([g.blocker, g.calm_ticks, g.due, sim.size()], ["wedged", 0, false, 1], "held: wedged, no calm tick, not due")
	check_eq(blocked.size(), 1, "named once")
	if blocked.size() == 1:
		check_eq(blocked[0].blocker, "wedged", "as wedged")
	# 4 tm east at size 1 is 2.5 tm at size 2: past the shell's 1.8 and the cell's 0.5.
	check(sim.debug_teleport(sim.motion.position + Vector2(4.0, 0.0)), "4 tm east")
	var events: Array[Dictionary] = []
	var grew_at := -1
	for t in int(g.cfg.calm_ticks) + 5:
		var ev := _tick(sim)
		events.append_array(ev)
		if not _of(ev, "grew").is_empty():
			grew_at = t
			break
	check_eq(_of(events, "growth_unblocked").size(), 1, "unblocked")
	check_eq(_of(events, "grew").size(), 1, "it grows once")
	check_eq(grew_at, int(g.cfg.calm_ticks), "the tick after calm_ticks calm ticks")
	check_eq(sim.size(), 2, "at size 2")
	check_eq(sim.motion.position, Vector2.ZERO, "on its own point: the water there is open")


# --- T2.6: the ledger and lumps, the death cost, respawn energy, the dev commands, the save (S2G20,
# S2G32; D-35, D-71 to D-76) ---

## The meter_lump events among `events`, as [reason, amount, id].
static func _lumps_of(events: Array[Dictionary]) -> Array:
	var out := []
	for e in _of(events, "meter_lump"):
		out.append([e.reason, e.amount, e.id])
	return out


## A growth sim among the size-2 species (so kills have species).
func _species_sim() -> PoolSim:
	var sim := FakeWorldGen.endless_sim(SEED, catalog, layout, FakeWorldGen.s2_species(), null, PackedFloat64Array(), 4, true)
	sim.drain_events()
	return sim


## A Continue of `save` on the fake generator: growth as `growth` says, no creatures.
func _continue(save: SaveGame, growth := true) -> PoolSim:
	var content := FakeWorldGen.fixture_content()
	content.config.switches["growth"] = growth
	var sim := PoolSim._create_endless(save, catalog, layout, null, content, FakeWorldGen.new(content, null, save.world_seed))
	sim.drain_events()
	return sim


## D-71: every look at size 1 is new; at size 2 the algae ball is and carrion (size 1's meat) is not.
## A new look is written to the ledger once per size and, with lumps, pays food_look x the ring once.
func test_a_food_look_new_at_the_size_pays_once_and_is_written_to_the_ledger() -> void:
	var sim := _growth_sim()
	var g := sim.growth
	check_eq(float(g.cfg.lumps.food_look), 0.05, "food_look is 5 % of the ring")
	var plant := {"type": "ate", "kind": "plant"}
	var meat := {"type": "ate", "kind": "meat"}
	g.observe(sim, [plant, plant, meat])
	check_eq(_lumps_of(sim.drain_events()), [["food_look", 0.05 * 90.0, "plankton"], ["food_look", 0.05 * 90.0, "carrion"]],
		"size 1: plankton and carrion, once each")
	check_eq(g.discoveries, [{"type": "food", "id": "plankton", "size": 1}, {"type": "food", "id": "carrion", "size": 1}], "the ledger")
	check_eq(g.paid.food, ["carrion", "plankton"], "paid at size 1, sorted")
	check(sim.debug_set_size(2), "size 2")
	sim.drain_events()
	g.observe(sim, [plant, meat, plant])
	check_eq(_lumps_of(sim.drain_events()), [["food_look", 0.05 * 120.0, "algae_ball"]], "size 2: the algae ball alone")
	check_eq(g.discoveries.back(), {"type": "food", "id": "algae_ball", "size": 2}, "written at size 2")
	check_eq(g.paid.food, ["algae_ball"], "paid at size 2")
	check(sim.debug_set_size(1), "back to size 1")
	sim.drain_events()
	g.observe(sim, [plant, meat])
	check_eq(_lumps_of(sim.drain_events()), [], "size 1 again: its looks were paid (the ledger)")
	check_eq(g.discoveries.size(), 3, "and nothing is written twice")
	var content := FakeWorldGen.fixture_content()
	content.config.switches["lumps"] = false
	var off := FakeWorldGen.endless_sim(SEED, catalog, layout, null, content, PackedFloat64Array(), 4, true)
	off.drain_events()
	off.growth.observe(off, [plant])
	check_eq(_lumps_of(off.drain_events()), [], "lumps off: no lump")
	check_eq(off.growth.discoveries, [{"type": "food", "id": "plankton", "size": 1}], "but the ledger still")


## D-72: a kill by the cell of a species drawn at the size (q 1) pays threat_kill x the ring every
## time; any other kill pays kill_carcass_share x the summed energy of its carcass items still in the
## carrion field; a kill by anyone else pays nothing.
func test_a_kill_pays_threat_kill_at_q_one_and_a_carcass_share_otherwise() -> void:
	var sim := _species_sim()
	var g := sim.growth
	var me := CreatureField.PLAYER_ID
	g.observe(sim, [{"type": "creature_died", "id": "c_a", "species": "rammer", "by": me, "carcass": []},
		{"type": "creature_died", "id": "c_b", "species": "rammer", "by": me, "carcass": []},
		{"type": "creature_died", "id": "c_c", "species": "rammer", "by": "c_9", "carcass": []}])
	check_eq(_lumps_of(sim.drain_events()), [["threat_kill", 0.15 * 90.0, "c_a"], ["threat_kill", 0.15 * 90.0, "c_b"]],
		"size 1: a rammer (q 1) pays 15 % of the ring on every kill by the cell")
	check(sim.debug_set_size(2), "size 2")
	var a := sim.carrion.spawn(sim.motion.position + Vector2(3.0, 0.0), "carcass", 24.0)
	var b := sim.carrion.spawn(sim.motion.position + Vector2(-3.0, 0.0), "carcass", 10.0)
	sim.drain_events()
	g.observe(sim, [{"type": "creature_died", "id": "c_d", "species": "rammer", "by": me, "carcass": [a.id, b.id, "cr_gone"]},
		{"type": "creature_died", "id": "c_e", "species": "lurker", "by": me, "carcass": [a.id]}])
	check_eq(_lumps_of(sim.drain_events()), [["kill", 0.25 * 34.0, "c_d"], ["threat_kill", 0.15 * 120.0, "c_e"]],
		"size 2: a rammer (q 0.625) pays 25 % of its carcass; a Lurker (q 1) 15 % of the ring")
	var content := FakeWorldGen.fixture_content()
	content.config.switches["lumps"] = false
	var off := FakeWorldGen.endless_sim(SEED, catalog, layout, FakeWorldGen.s2_species(), content, PackedFloat64Array(), 4, true)
	off.drain_events()
	off.growth.observe(off, [{"type": "creature_died", "id": "c_a", "species": "rammer", "by": me, "carcass": []}])
	check_eq(_lumps_of(off.drain_events()), [], "lumps off: nothing")


## Step 10: a place within place_find_tm (10) and a landmark anchor within landmark_find_tm (6) of
## the cell are found once per size, in id order, each with discovered {kind, id, size, lump}; a place
## pays place x the ring, a landmark landmark_at_top x the ring at the build top only.
func test_a_place_and_a_landmark_near_the_cell_are_found_once_per_size() -> void:
	var sim := _growth_sim()
	var g := sim.growth
	var key := FakeWorldGen.PLACE_CHUNK
	var c := Vector2(32.0 * key.x + 16.0, 32.0 * key.y + 16.0)
	for n in [1, 2]:
		sim.world.gen.extra_anchors[Vector3i(key.x, key.y, n)] = [{"id": "a_f_arch", "x": c.x + 4.0, "y": c.y + 6.0,
			"model": "landmark_arch"}]
	(sim.world.gen.extra_anchors[Vector3i(key.x, key.y, 1)] as Array).append({"id": "a_f_arch2", "x": c.x + 1.0,
		"y": c.y + 9.0, "model": "landmark_arch"})   # a second arch: two of a kind in one tick
	check(sim.debug_teleport_abs(c.x + 30.0, c.y), "30 tm from the place")
	check_eq(_of(_tick(sim) + _tick(sim), "discovered"), [], "nothing found that far")
	check(sim.debug_teleport_abs(c.x - 9.0, c.y), "9 tm from the place, 14 from the arch")
	var events := _tick(sim)
	check_eq(_of(events, "discovered"), [{"type": "discovered", "kind": "place", "id": "giant_husk", "size": 1, "lump": true}],
		"the place")
	check_eq(_lumps_of(events), [["place", 0.1 * 90.0, "giant_husk"]], "pays 10 % of the ring")
	events = _tick(sim)
	check_eq(_of(events, "discovered") + _of(events, "meter_lump"), [], "once")
	check(sim.debug_teleport_abs(c.x - 1.0, c.y + 6.0), "5 tm from the arch, 3.6 from the second")
	events = _tick(sim)
	check_eq(_of(events, "discovered"), [{"type": "discovered", "kind": "landmark", "id": "landmark_arch", "size": 1, "lump": false}],
		"the landmark once though two arches are near, no lump below the top")
	check_eq(_lumps_of(events), [], "nothing paid")
	check_eq(g.discoveries, [{"type": "place", "id": "giant_husk", "size": 1}, {"type": "landmark", "id": "landmark_arch", "size": 1}],
		"the ledger")
	check(sim.debug_set_size(2), "size 2, the top")
	var k := WorldConfig.tm_to_am(2)
	check(sim.debug_teleport_abs((c.x - 1.0) * k, (c.y + 6.0) * k), "5 tm from the arch at size 2, 6.1 from the place")
	sim.drain_events()
	events = _tick(sim)
	check_eq(_of(events, "discovered"), [{"type": "discovered", "kind": "landmark", "id": "landmark_arch", "size": 2, "lump": true},
		{"type": "discovered", "kind": "place", "id": "giant_husk", "size": 2, "lump": true}], "both again at size 2, in id order")
	check_eq(_lumps_of(events), [["landmark", 0.1 * 120.0, "landmark_arch"], ["place", 0.1 * 120.0, "giant_husk"]],
		"the landmark pays at the top")
	check_eq(g.paid, {"place": ["giant_husk"], "landmark": ["landmark_arch"], "food": []}, "paid at size 2")


## on_death (D-35): the energy the cell died with is kept; from size 2 the death costs 25 % of the
## ring (never below 0, full no more); the window, the press and the closing history start again.
func test_a_death_costs_a_quarter_ring_from_size_two_and_none_at_size_one() -> void:
	var sim := _growth_sim()
	var g := sim.growth
	check_eq(float(g.cfg.death_meter_share), 0.25, "death_meter_share")
	check(sim.debug_fill_meter(0.5), "half full")
	g.calm_ticks = 5
	g.blocked_ticks = 7
	g.blocker = "eating"
	g.armed = true
	g.due = true
	g.closing.append([sim.tick, {}])
	sim.state.energy = 31.0
	sim._player_dies("starved", "", "", "test")
	check_eq(g.meter, 45.0, "size 1: the meter kept")
	check_eq(g.energy_at_death, 31.0, "the energy it died with")
	check_eq([g.calm_ticks, g.blocked_ticks, g.blocker, g.armed, g.due, g.closing], [0, 0, "", false, false, []], "the window cleared")
	var two := _growth_sim()
	two.world.max_size = 3   # a build whose top is 3, so size 2 has a window
	check(two.debug_set_size(2), "size 2")
	check(two.debug_fill_meter(1.0), "full")
	check(two.growth.full_since >= 0, "full")
	two._player_dies("killed", "c_1", "rammer", "")
	check_eq(two.growth.meter, 120.0 - 30.0, "size 2: 25 % of the ring (30) gone")
	check_eq(two.growth.full_since, -1, "no longer full")
	var low := _growth_sim()
	check(low.debug_set_size(2), "size 2, the top")
	check(low.debug_fill_meter(0.1), "12 in the meter")
	low._player_dies("starved", "", "", "test")
	check_eq(low.growth.meter, 0.0, "never below 0")


## D-35: the streak's share of the capacity, at most 20 over the energy the cell died with, and at
## size 1 (before the first growth) at least 80 %; the share alone with no death recorded.
func test_respawn_energy_is_the_share_capped_over_the_death_with_the_size_one_floor() -> void:
	var g := _growth_sim().growth
	check_eq([float(g.cfg.respawn_floor_share), float(g.cfg.respawn_cap_over_death)], [0.8, 20.0], "the data")
	check_eq(g.respawn_energy(100.0, 0.6, 1), 60.0, "no death recorded: the share")
	g.energy_at_death = 5.0
	check_eq(g.respawn_energy(100.0, 0.6, 1), 80.0, "size 1: the 80 % floor")
	check_eq(g.respawn_energy(100.0, 0.6, 2), 25.0, "size 2: 20 over the death")
	g.energy_at_death = 70.0
	check_eq(g.respawn_energy(100.0, 0.6, 2), 60.0, "the share caps it")
	check_eq(g.respawn_energy(100.0, 1.0, 1), 90.0, "size 1: 20 over the death above the floor")
	g.energy_at_death = 95.0
	check_eq(g.respawn_energy(100.0, 1.0, 2), 100.0, "never past the capacity")


## D-73: the respawn (step 0's _respawn_now) takes its energy from respawn_energy with growth on, and
## the streak's share alone with growth off (S1).
func test_a_respawn_takes_its_energy_from_respawn_energy() -> void:
	for growth in [true, false]:
		for n in ([1, 2] if growth else [1]):
			var sim := FakeWorldGen.endless_sim(SEED, catalog, layout, SpeciesCatalog.load_from(), null, PackedFloat64Array(), 4, growth)
			if n == 2:
				check(sim.debug_set_size(2), "size 2")
			sim.state.energy = 10.0
			sim._player_dies("starved", "", "", "test")
			sim.respawn_player()
			sim.drain_events()
			for t in 3:
				if sim.dead or sim.respawn_pending:
					sim.step(SimIntent.new())
			check(not sim.dead, "respawned (growth %s, size %d)" % [growth, n])
			var cap := sim.state.energy_capacity
			var share := RespawnRules.pick(sim.species.respawn_energy_share, sim.death_streak)
			var want := cap * share
			if growth:
				want = maxf(0.8 * cap, minf(share * cap, 30.0)) if n == 1 else minf(share * cap, 30.0)
			check_near(sim.state.energy, want, 0.05, "growth %s, size %d: energy %.2f" % [growth, n, sim.state.energy])


## The dev commands: fill_meter through Growth.add (debug event after the lump), force_growth makes the
## next tick grow even while hunted or wedged; both refuse with growth off, dead, or (force) at the top.
func test_the_dev_meter_commands_fill_and_force() -> void:
	var sim := _growth_sim()
	var g := sim.growth
	check(sim.debug_fill_meter(0.5), "half")
	var events := sim.drain_events()
	check_eq(g.meter, 45.0, "45 of 90")
	check_eq(_lumps_of(events), [["debug", 45.0, ""]], "through add")
	check_eq(events.back(), {"type": "debug", "command": "fill_meter", "share": 0.5}, "then the debug event")
	check(not sim.debug_fill_meter(1.5) and not sim.debug_fill_meter(-0.1), "a share outside 0 to 1 is refused")
	check(sim.debug_force_growth(), "forced")
	check_eq([g.meter, g.due], [90.0, true], "full and due")
	check_eq(sim.drain_events().back(), {"type": "debug", "command": "force_growth"}, "its event")
	check_eq(_of(_tick(sim), "grew").size(), 1, "the next tick grows")
	check_eq(sim.size(), 2, "size 2")
	check(not sim.debug_force_growth(), "not at the top")
	check(sim.debug_fill_meter(0.5), "fill still works at the top")
	sim._player_dies("starved", "", "", "test")
	check(not sim.debug_fill_meter(1.0) and not sim.debug_force_growth(), "not while dead")
	var off := FakeWorldGen.endless_sim(SEED, catalog, layout, null)
	check(not off.debug_fill_meter(1.0) and not off.debug_force_growth(), "not with growth off")
	# Wedged: a shell over every ring of the next size's point. Forced, it grows onto the nearest clear
	# point beyond the wedge (the settle is asserted only against a finite point).
	var shut := _growth_sim()
	var w := shut.world
	var a := w.abs_of_local(shut.motion.position)
	var x := a[0] / WorldConfig.tm_to_am(2)
	var y := a[1] / WorldConfig.tm_to_am(2)
	w.gen.extra_shells[Vector3i(floori(x / w.chunk_tm), floori(y / w.chunk_tm), 2)] = [{"x": x, "y": y, "r": 1.8}]
	w._clear_next()
	check(not w.next_size_clear_point(shut).is_finite(), "wedged")
	check(shut.debug_force_growth(), "forced while wedged")
	check_eq(_of(_tick(shut), "grew").size(), 1, "it grows")
	check(shut.arena.is_clear(shut.motion.position, shut.phenotype.radius), "clear")
	check(shut.motion.position.length() > 2.0 + 1e-3, "past the wedge (%s)" % shut.motion.position)


## The v3 fields (spine 4.6): write_growth_to_save writes the size and meter, the checkpoint, the
## ledger and the generator version; a Continue (D-74) comes back at that size with that meter,
## checkpoint and ledger, and never pays a find twice (S2G32).
func test_the_save_carries_the_size_meter_checkpoint_and_ledger_and_a_continue_restores_them() -> void:
	var sim := _growth_sim()
	var g := sim.growth
	var key := FakeWorldGen.PLACE_CHUNK
	var c := Vector2(32.0 * key.x + 16.0, 32.0 * key.y + 16.0)
	g.observe(sim, [{"type": "ate", "kind": "plant"}])
	check(sim.debug_teleport_abs(c.x - 9.0, c.y), "beside the place")
	_tick(sim)
	check_eq(g.discoveries, [{"type": "food", "id": "plankton", "size": 1}, {"type": "place", "id": "giant_husk", "size": 1}],
		"two finds at size 1")
	check(sim.debug_set_size(2), "size 2")
	check(sim.debug_fill_meter(0.25), "30 in the meter")
	sim.write_position_to_save()
	sim.write_growth_to_save()
	var cp := sim.world.checkpoint_am
	check_eq(sim.save.growth, {"size": 2, "meter": 30.0}, "growth")
	check_eq(sim.save.checkpoint, {"x_am": cp[0], "y_am": cp[1], "heading": cp[2], "size": 2}, "the checkpoint")
	check_eq(sim.save.discoveries, g.discoveries, "the ledger")
	check(not is_same(sim.save.discoveries, g.discoveries), "a copy")
	check_eq(sim.save.gen_version, sim.world.gen_version, "gen_version")
	check_eq(sim.save.validate(catalog), PackedStringArray(), "a valid v3 save")
	var back := _continue(sim.save)
	check_eq(back.size(), 2, "Continue at size 2")
	check_eq([back.growth.meter, back.growth.full_since], [30.0, -1], "the meter")
	check_eq(back.world.checkpoint_am, cp, "the checkpoint")
	check_eq(back.growth.discoveries, g.discoveries, "the ledger")
	check_eq(back.growth.paid, {"place": [], "landmark": [], "food": []}, "nothing paid at size 2 yet")
	var a := back.absolute_position_am()
	var b := sim.absolute_position_am()
	check(absf(a[0] - b[0]) < 1e-6 and absf(a[1] - b[1]) < 1e-6, "at its place")
	check(back.debug_set_size(1), "back at size 1")
	check_eq(back.growth.paid, {"place": ["giant_husk"], "landmark": [], "food": ["plankton"]}, "size 1's finds are paid")
	check(back.debug_teleport_abs(c.x - 9.0, c.y), "beside the place again")
	back.growth.observe(back, [{"type": "ate", "kind": "plant"}])
	var events := back.drain_events() + _tick(back)
	check_eq(_of(events, "discovered") + _of(events, "meter_lump"), [], "a Continue never pays twice")
	# D-74: the size clamped to the build's sizes, the meter to the ring (a full ring at the top pays
	# out on the first tick); with growth off, size 1 and no meter.
	sim.save.growth = {"size": 5, "meter": 999.0}
	var clamped := _continue(sim.save)
	check_eq([clamped.size(), clamped.growth.meter, clamped.growth.full_since, int(clamped.world.checkpoint_am[3])], [2, 120.0, 0, 2],
		"size 5 is 2 here; the meter the ring")
	check_eq(_of(_tick(clamped), "ring_paid").size(), 1, "full at the top: it pays out")
	check_eq(clamped.growth.meter, 0.0, "and starts again")
	var s1 := _continue(sim.save, false)
	check_eq([s1.size(), s1.growth, s1.world.checkpoint_am[3]], [1, null, 1.0], "growth off: size 1")
	var pool := PoolSim.create(Lineage.found(SEED, "test+dev", catalog, "omnivore").save, catalog, layout, null)
	pool.write_growth_to_save()
	check_eq([pool.save.growth, pool.save.checkpoint, pool.save.gen_version],
		[{"size": 1, "meter": 0.0}, {"x_am": 0.0, "y_am": 9.0, "heading": -1.5708, "size": 1}, 1], "the pool writes the defaults")
