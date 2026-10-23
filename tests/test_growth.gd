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
