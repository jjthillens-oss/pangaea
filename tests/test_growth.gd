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
