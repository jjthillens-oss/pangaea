extends TestCase
## The growth tick (S2 T2.5; WorldStream.grow, s2-sim 3.7 as the build plan's BP-4 changes it) on
## FakeWorldGen at sizes 1 and 2: the world is re-expressed one size up round the cell's absolute
## point and the cell comes out of it safe, settled, full and sheltered (S2G9); the settle lands on
## the next size's pure point bit for bit, the point is INF exactly when no ring within the wedge is
## clear, and the prefetch never changes a result (S2G35); the size-2 world a growth makes is the one
## a direct arrival meets (S2G12, BP-8); the tick's events come in order with their frames (S2G33);
## and every conversion is exact (S2G34).

const FakeWorldGen := preload("res://tests/fakes/fake_world_gen.gd")
const Gates := preload("res://tests/test_endless_gates.gd")
const SwimBot := preload("res://game/dev/swim_bot.gd")
const FuzzInvariants := preload("res://tests/fuzz_invariants.gd")
## The fast seeds of S2G9, S2G12 and S2G35; their slow tests run SLOW_SEEDS seeds.
const SEEDS := [7, 11, 23, 4242, 90001]
const SLOW_SEEDS := 50
## Ticks a size-1 swim runs before the growth, so creatures are awake round the cell.
const SWIM_TICKS := 240
## am: how far out the two size-2 routes of S2G12 start (BP-8).
const ROUTE_AM := 200.0
## The prefetch comparison's ticks (the growth is tick 60).
const HASH_AT := [59, 60, 61, 75, 119]
## The quiet-tick prefetch case's swim.
const QUIET_TICKS := 240

var catalog: PartCatalog
var layout: PoolLayout


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()


## An endless sim on the fake generator with growth on (size 2 is the build top) and a site in
## every `period` x `period` chunks, its start events drained.
func _sim(seed_value: int, species: SpeciesCatalog = null, period := 2, at := PackedFloat64Array()) -> PoolSim:
	var sim := FakeWorldGen.endless_sim(seed_value, catalog, layout, species, null, at, period, true)
	sim.drain_events()
	return sim


## A size-1 sim that has swum SWIM_TICKS ticks among the size-2 species, a diagonal that depends on
## the seed.
func _swum(seed_value: int) -> PoolSim:
	var sim := _sim(seed_value, FakeWorldGen.s2_species())
	var dir := Vector2.from_angle(float(seed_value % 360) * PI / 180.0)
	for t in SWIM_TICKS:
		sim.step(SimIntent.new(dir * 0.6))
	sim.drain_events()
	return sim


## The next tick grows: the ring full and due, as the calm window leaves it.
static func _due(sim: PoolSim) -> void:
	var g := sim.growth
	g.meter = g.ring(sim.size())
	g.full_since = sim.tick
	g.due = true


static func _tick(sim: PoolSim, move := Vector2.ZERO) -> Array[Dictionary]:
	sim.step(SimIntent.new(move))
	return sim.drain_events()


static func _of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		if e.type == type:
			out.append(e)
	return out


static func _first(events: Array[Dictionary], type: String) -> Dictionary:
	var found := _of(events, type)
	return found[0] if not found.is_empty() else {}


## The next size's point round the cell, in the next size's frame (the spiral's own result).
static func _raw_point(sim: PoolSim) -> Vector2:
	return sim.world._next_point(sim.world.abs_of_local(sim.motion.position), sim.phenotype.radius)


## A size-2 shell of radius `r` centred `offset` (size-2 tm) from the cell's absolute point, through the
## fake's extra shells (before anything has generated that chunk at size 2).
static func _shell_at_next_size(sim: PoolSim, offset: Vector2, r: float) -> void:
	var a := sim.world.abs_of_local(sim.motion.position)
	var s1 := WorldConfig.tm_to_am(sim.size() + 1)
	_extra_shell(sim, a[0] + offset.x * s1, a[1] + offset.y * s1, r)
	sim.world._clear_next()


## A size-2 shell of radius `r` (size-2 tm) centred on the absolute point (x_am, y_am), through the
## fake's extra shells; the caches are left as they are.
static func _extra_shell(sim: PoolSim, x_am: float, y_am: float, r: float) -> void:
	var s1 := WorldConfig.tm_to_am(sim.size() + 1)
	var x := x_am / s1
	var y := y_am / s1
	var key := Vector3i(floori(x / sim.world.chunk_tm), floori(y / sim.world.chunk_tm), sim.size() + 1)
	var more: Array = sim.world.gen.extra_shells.get(key, [])
	more.append({"x": x, "y": y, "r": r})
	sim.world.gen.extra_shells[key] = more


# --- S2G9: the world one size up, the cell safe, settled, full and sheltered ---

func test_a_growth_re_expresses_the_world_one_size_up_round_the_cell() -> void:
	var sim := _swum(SEEDS[0])
	var w := sim.world
	var a := w.abs_of_local(sim.motion.position)
	var ap := w.abs_of_local(sim.motion.prev_position)
	var v := sim.motion.velocity
	var heading := sim.motion.heading
	var t0 := sim.tick
	w.grow(sim)
	check_eq(sim.size(), 2, "size 2")
	check_eq(sim.creatures.size, 2, "the creature field at size 2")
	check(w.origin_x_am == a[0] and w.origin_y_am == a[1], "the origin is the cell's absolute point exactly")
	check(sim.motion.prev_position == w.local_of_abs(ap[0], ap[1]), "the previous point from its absolute value")
	check(sim.motion.velocity == v / WorldConfig.GROWTH_FACTOR, "velocity / 1.6")
	check_eq(sim.motion.heading, heading, "the heading kept")
	check(sim.motion.position.length() <= float(sim.growth.cfg.wedge_tm) + 1e-6,
		"settled within %s new tm (%s)" % [sim.growth.cfg.wedge_tm, sim.motion.position])
	check(sim.actor.position == sim.motion.position, "the actor synced")
	var cp := w.abs_of_local(sim.motion.position)
	check_eq(Array(w.checkpoint_am), [cp[0], cp[1], heading, 2.0], "the checkpoint is the settled point at size 2")
	check_eq(sim.state.energy, sim.state.energy_capacity, "energy full")
	check_eq(sim.grace_until, t0 + CreatureBrain.ticks(sim.growth.cfg.shelter_s), "sheltered for shelter_s")
	check_eq(sim.growth.beat_until, t0 + CreatureBrain.ticks(sim.growth.cfg.beat_s), "the beat")
	check_eq(sim.growth.meter, 0.0, "the meter starts again")
	check(not sim.growth.due and sim.growth.full_since == -1 and sim.growth.calm_ticks == 0, "the window starts again")
	var keys := w.loaded_keys()
	check_eq(keys, w.view_set_keys(Vector2.ZERO), "the view set round the cell's point, at size 2")
	for key in keys:
		check_eq(w.chunk(key).size, 2, "chunk %s at size 2" % key)
	check(sim.creatures.creatures.is_empty(), "no creature of size 1 is left: they converted or left")
	for id in w.sites:
		check((w.sites[id].abs.sizes as Array).has(2), "site %s lives at size 2" % id)


func test_the_growth_tick_leaves_no_creature_that_can_attack_near_the_cell_or_in_view() -> void:
	_check_safe_after_growth(SEEDS)


func test_slow_the_growth_tick_leaves_no_creature_that_can_attack_near_the_cell_or_in_view_on_50_seeds() -> void:
	var seeds := []
	for i in SLOW_SEEDS:
		seeds.append(1000 + 37 * i)
	_check_safe_after_growth(seeds)


func _check_safe_after_growth(seeds: Array) -> void:
	var converted := 0
	var spawned := 0
	for seed_value: int in seeds:
		var sim := _swum(seed_value)
		converted += sim.creatures.awake().size()
		_due(sim)
		var ev := _tick(sim)
		check_eq(_of(ev, "grew").size(), 1, "seed %d: grew" % seed_value)
		spawned += _of(ev, "creature_spawned").size()
		var fair := sim.species.fairness
		var cam: Dictionary = layout.camera
		var cell := sim.motion.position
		for c in sim.creatures.awake():
			var margin := float(cam.look_ahead_max) + float(fair.spawn_view_margin_m) + c.phenotype.radius
			check(cell.distance_to(c.motion.position) >= float(fair.spawn_safe_m),
				"seed %d: %s is spawn_safe_m away" % [seed_value, c.id])
			check(not ViewFootprint.contains(cell, c.motion.position, cam, float(cam.zoom_max), float(fair.spawn_view_aspect), margin),
				"seed %d: %s is out of view" % [seed_value, c.id])
		check(sim.remnants.items.all(func(r: RemnantField.Remnant) -> bool: return r.brain == null),
			"seed %d: remnants have no brain to attack with" % seed_value)
	check(converted > 0, "creatures were awake to convert (%d)" % converted)
	check(spawned > 0, "size-2 creatures spawned in the growth tick (%d)" % spawned)


func test_step_one_grows_only_a_living_cell_below_the_top() -> void:
	var sim := _sim(SEEDS[1])
	sim.respawn_pending = false
	sim.dead = true
	_due(sim)
	sim.world.step(sim)
	check_eq(sim.size(), 1, "a dead cell does not grow")
	check(not sim.growth.due, "and the due is dropped")
	sim.dead = false
	check(sim.debug_set_size(2), "to the top")
	_due(sim)
	sim.world.step(sim)
	check_eq(sim.size(), 2, "the top does not grow")
	check(not sim.growth.due, "and the due is dropped")


# --- S2G35: the point, the wedge and the prefetch ---

func test_the_settle_lands_on_the_next_size_point_bit_for_bit() -> void:
	_check_point_equals_settle(SEEDS)


func test_slow_the_settle_lands_on_the_next_size_point_bit_for_bit_on_50_seeds() -> void:
	var seeds := []
	for i in SLOW_SEEDS:
		seeds.append(2000 + 53 * i)
	_check_point_equals_settle(seeds)


## For each seed: a size-2 shell 0.9 tm from the cell, in a direction of the seed's, so the settle must
## move it; the point taken before the tick is the grew event's settled_to exactly, and the
## checkpoint is its absolute value.
func _check_point_equals_settle(seeds: Array) -> void:
	var moved := 0
	for seed_value: int in seeds:
		var sim := _swum(seed_value)
		_shell_at_next_size(sim, Vector2.from_angle(float(seed_value % 628) / 100.0) * 0.9, 1.0)
		var a := sim.world.abs_of_local(sim.motion.position)
		var q := _raw_point(sim)
		check(q.is_finite(), "seed %d: not wedged" % seed_value)
		var current := sim.world.next_size_clear_point(sim)
		var s1 := WorldConfig.tm_to_am(2)
		check(current == sim.world.local_of_abs(a[0] + q.x * s1, a[1] + q.y * s1), "seed %d: the point in the current frame" % seed_value)
		_due(sim)
		var grew := _first(_tick(sim), "grew")
		check(grew.settled_to == q, "seed %d: settled %s == point %s bit for bit" % [seed_value, grew.get("settled_to"), q])
		check(float(grew.checkpoint_am[0]) == a[0] + float(q.x) * s1 and float(grew.checkpoint_am[1]) == a[1] + float(q.y) * s1,
			"seed %d: the checkpoint is the point's absolute value" % seed_value)
		if q != Vector2.ZERO:
			moved += 1
	check(moved * 2 >= seeds.size(), "the settle moved the cell on most seeds (%d of %d)" % [moved, seeds.size()])


func test_the_point_is_inf_exactly_when_no_ring_within_the_wedge_is_clear() -> void:
	var r := 0.5   # the cell's radius
	check_eq(_sim(SEEDS[2]).phenotype.radius, r, "the cell the numbers below assume")
	check_eq(_sim(SEEDS[2]).world.wedge_rings, 4, "ceil(wedge_tm / 0.5) rings (BP-4)")
	# A shell of radius 1.8 on the point blocks every point nearer than 2.3: the four rings (to 2 tm)
	# are shut and the fifth (2.5 tm) is open.
	var shut := _sim(SEEDS[2])
	_shell_at_next_size(shut, Vector2.ZERO, 1.8)
	check(_raw_point(shut) == Vector2.INF, "wedged: INF")
	check(shut.world.next_size_clear_point(shut) == Vector2.INF, "and INF in the current frame")
	check(PoolSim.clear_point_on(shut.world._next_arena, Vector2.ZERO, r, 5).is_finite(), "the fifth ring is clear")
	check_eq(shut.growth.blocker_of(shut), "wedged", "the blocker names it")
	# Radius 1.4 shuts everything nearer than 1.9: the fourth ring is the first clear one.
	var open := _sim(SEEDS[2])
	_shell_at_next_size(open, Vector2.ZERO, 1.4)
	var q := _raw_point(open)
	check(q.is_finite(), "not wedged: finite")
	check_near(q.length(), 2.0, 1e-5, "on the fourth ring")
	check_eq(open.growth.blocker_of(open), "", "no blocker")
	# Unwedged by moving: the point follows the cell's absolute point alone.
	var far := _sim(SEEDS[2])
	check(_raw_point(far) == Vector2.ZERO, "open water: the cell's own point")


func test_prefetch_on_and_off_give_equal_hashes_through_a_growth() -> void:
	_check_prefetch_on_off(SEEDS)


func test_slow_prefetch_on_and_off_give_equal_hashes_through_a_growth_on_50_seeds() -> void:
	var seeds := []
	for i in SLOW_SEEDS:
		seeds.append(3000 + 71 * i)
	_check_prefetch_on_off(seeds)


## Two runs of each seed, one with the next size's caches off: the meter held at 0.95 of the ring for
## 60 ticks (the prefetch runs), then a growth and 60 ticks more; the hashes are equal before the
## growth tick, after it, and at HASH_AT ticks after.
func _check_prefetch_on_off(seeds: Array) -> void:
	var hits := 0
	for seed_value: int in seeds:
		var on := _sim(seed_value, FakeWorldGen.s2_species())
		var off := _sim(seed_value, FakeWorldGen.s2_species())
		off.world.next_cache = false
		var dir := Vector2.from_angle(float(seed_value % 360) * PI / 180.0) * 0.6
		var parted := -1
		for t in 120:
			if t < 60:
				for sim: PoolSim in [on, off]:
					sim.growth.meter = 0.95 * sim.growth.ring(1)
			if t == 60:
				hits += on.world._next_chunks.size()
				check(off.world._next_chunks.is_empty(), "seed %d: nothing cached with the caches off" % seed_value)
				_due(on)
				_due(off)
			on.step(SimIntent.new(dir))
			off.step(SimIntent.new(dir))
			if HASH_AT.has(t) and parted < 0 and on.state_hash() != off.state_hash():
				parted = t
		check(parted < 0 and on.size() == 2, "seed %d: equal through the growth (parted at %d)" % [seed_value, parted])
	check(hits >= 9 * seeds.size(), "the prefetch had the chunks ready (%d)" % hits)


func test_the_prefetch_takes_the_nearest_missing_new_size_chunk_a_tick_while_the_ring_is_nearly_full() -> void:
	var sim := _sim(SEEDS[3])
	var w := sim.world
	var g := sim.growth
	var gen = w.gen
	check(g.prefetch_per_tick == 1 and g.prefetch_share == 0.9, "the world file's prefetch (BP-4)")
	g.meter = 0.89 * g.ring(1)
	w._prefetch(sim)
	check(w._next_chunks.is_empty(), "below the share: nothing")
	g.meter = 0.9 * g.ring(1)
	var a := w.abs_of_local(sim.motion.position)
	var s1 := WorldConfig.tm_to_am(2)
	var c := Vector2i(floori(a[0] / s1 / w.chunk_tm), floori(a[1] / s1 / w.chunk_tm))
	var order: Array[Vector2i] = []
	for i in 25:
		gen.built.clear()
		w._prefetch(sim)
		check_eq(gen.built.size(), 1, "one chunk a tick (%d)" % i)
		for key in gen.built:
			order.append(key)
	gen.built.clear()
	w._prefetch(sim)
	check(gen.built.is_empty(), "the 5 x 5 is full: nothing more")
	var want: Array[Vector2i] = []
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			want.append(Vector2i(c.x + dx, c.y + dy))
	var x := a[0] / s1
	var y := a[1] / s1
	want.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
		var dp := Vector2((p.x + 0.5) * w.chunk_tm - x, (p.y + 0.5) * w.chunk_tm - y).length_squared()
		var dq := Vector2((q.x + 0.5) * w.chunk_tm - x, (q.y + 0.5) * w.chunk_tm - y).length_squared()
		return dp < dq or (dp == dq and (p.y < q.y or (p.y == q.y and p.x < q.x))))
	check_eq(order, want, "nearest the cell first, ties by (y, x)")
	for key in w._next_chunks:
		check_eq(w._next_chunks[key].size, 2, "chunk %s at the next size" % key)
	# The window follows the cell: a chunk-width move drops the far column.
	sim.motion.position += Vector2(w.chunk_tm * WorldConfig.tm_to_am(2), 0.0)
	w._prefetch(sim)
	var c2 := Vector2i(c.x + 1, c.y)
	for key in w._next_chunks:
		check(absi(key.x - c2.x) <= 2 and absi(key.y - c2.y) <= 2, "%s inside the moved window" % key)
	check_eq(w._next_chunks.size(), 21, "the 20 kept and one new")
	# Below the share it forgets; so do a size change, a teleport and a respawn.
	g.meter = 0.5 * g.ring(1)
	w._prefetch(sim)
	check(w._next_chunks.is_empty() and w._next_arena == null, "below the share: forgotten")
	for how in ["set_size", "teleport", "respawn"]:
		g.meter = g.ring(1) * 0.95
		w._prefetch(sim)
		w.next_size_clear_point(sim)
		check(not w._next_chunks.is_empty() and w._next_arena != null, "%s: cached first" % how)
		match how:
			"set_size":
				w.set_size(1)
			"teleport":
				w.teleport(sim, w.origin_x_am + 500.0, w.origin_y_am)
				sim.motion.place(Vector2.ZERO, 0.0)
			"respawn":
				w._respawn(sim)
		check(w._next_chunks.is_empty() and w._next_arena == null, "%s forgets the caches" % how)


func test_a_cache_miss_generates_the_chunk_and_keeps_it() -> void:
	var sim := _sim(SEEDS[4])
	var w := sim.world
	var gen = w.gen
	gen.built.clear()
	var q := w.next_size_clear_point(sim)
	check(q.is_finite(), "a point")
	check_eq(gen.built.size(), 9, "the 3 x 3 generated once")
	check_eq(w._next_chunks.size(), 9, "and kept")
	gen.built.clear()
	for i in 3:
		check(w.next_size_clear_point(sim) == q, "the same point again")
	check(gen.built.is_empty(), "nothing generated again while the cell's new-size chunk is the same")
	var arena := w._next_arena
	sim.motion.position += Vector2(0.25, 0.0)
	w.next_size_clear_point(sim)
	check(is_same(arena, w._next_arena), "the arena kept, moved to the new point")


## BP-4's arena is kept, not rebuilt: on quiet ticks the 3 x 3 round the new-size chunk the cell
## heads for joins it one chunk a tick, so the crossing into that chunk adds none; with the cell
## still, a chunk in neither 3 x 3 leaves one a tick, and a crossing it did not head for adds the
## chunks it lacks. Every point equals the one from freshly generated chunks (a twin with the caches
## off), with a shell on the cell's point here and one and two chunks east, so the points are not the
## cell's own.
func test_the_next_arena_is_kept_across_new_size_chunks_and_gives_a_fresh_point() -> void:
	var on := _sim(SEEDS[1])
	var off := _sim(SEEDS[1])
	off.world.next_cache = false
	var w := on.world
	var east := Vector2(w.chunk_tm * WorldConfig.tm_to_am(2), 0.0)   # a new-size chunk, in size-1 tm
	var a := w.abs_of_local(on.motion.position)
	for sim: PoolSim in [on, off]:
		_extra_shell(sim, a[0], a[1], 1.4)
		_extra_shell(sim, a[0] + east.x, a[1], 1.4)
		_extra_shell(sim, a[0] + 2.0 * east.x, a[1], 1.4)
		sim.growth.meter = 0.95 * sim.growth.ring(1)
	for t in 25:
		w._prefetch(on)
	var q := w.next_size_clear_point(on)
	check(q == off.world.next_size_clear_point(off), "the point as from fresh chunks")
	check(q.distance_to(on.motion.position) > 1.0, "the shell moved it (%s)" % q)
	var arena := w._next_arena
	var key := w._next_key
	check_eq(w._next_held.size(), 9, "the 3 x 3")
	on.motion.velocity = east / WorldStream.NEXT_LEAD_S   # heading for the chunk east
	for t in 3:
		w._prefetch(on)
		check_eq(w._next_held.size(), 10 + t, "quiet tick %d: one chunk of the 3 x 3 ahead joined" % t)
	w._prefetch(on)
	w._prefetch(on, false)
	check_eq(w._next_held.size(), 12, "then none joins and none leaves")
	for sim: PoolSim in [on, off]:
		sim.motion.position += east
	var epoch := arena.epoch
	q = w.next_size_clear_point(on)
	check(is_same(arena, w._next_arena) and w._next_key == key + Vector2i(1, 0), "the same arena, round the new chunk")
	check_eq(arena.epoch, epoch + 1, "the crossing added no chunk, only moved the arena to A")
	check(q == off.world.next_size_clear_point(off), "the point as from fresh chunks after the crossing")
	check(q.distance_to(on.motion.position) > 1.0, "the shell there moved it (%s)" % q)
	on.motion.velocity = Vector2.ZERO
	for t in 5:
		w._prefetch(on)
	check_eq(w._next_held.size(), 12, "the prefetch's new column comes first")
	for t in 3:
		w._prefetch(on)
	check_eq(w._next_held.size(), 9, "then the column behind leaves, one a quiet tick")
	for k: Vector2i in w._next_held:
		check(absi(k.x - w._next_key.x) <= 1 and absi(k.y - w._next_key.y) <= 1, "%s in the 3 x 3" % k)
	check(w.next_size_clear_point(on) == q, "the point unchanged")
	for sim: PoolSim in [on, off]:
		sim.motion.position += east
	q = w.next_size_clear_point(on)
	check(is_same(arena, w._next_arena), "a crossing it did not head for keeps the arena too")
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			check(w._next_held.has(w._next_key + Vector2i(dx, dy)), "and adds the 3 x 3's chunk %s" % Vector2i(dx, dy))
	check(q == off.world.next_size_clear_point(off), "the point as from fresh chunks there")
	check(q.distance_to(on.motion.position) > 1.0, "the shell there moved it (%s)" % q)


## The prefetch generates only on a quiet tick, one that loaded no chunk and generated none ahead,
## so a size-2 generation never lands on a tick that already made a chunk.
func test_the_prefetch_waits_for_a_tick_that_loaded_and_generated_nothing() -> void:
	var sim := _sim(SEEDS[2])
	var w := sim.world
	sim.growth.meter = 0.95 * sim.growth.ring(1)
	w._prefetch(sim, false)
	check(w._next_chunks.is_empty(), "a busy tick generates nothing")
	w._prefetch(sim)
	check_eq(w._next_chunks.size(), 1, "a quiet one does")
	var dir := Vector2.from_angle(0.3)
	var waited := {"load": 0, "ahead": 0}
	var busy := 0
	for t in QUIET_TICKS:
		sim.growth.meter = 0.95 * sim.growth.ring(1)
		var loads := w._loads
		var ahead: Array = w._ahead.keys()
		var before: Array = w._next_chunks.keys()
		sim.step(SimIntent.new(dir))
		var fresh := 0
		for key in w._next_chunks:
			fresh += 0 if before.has(key) else 1
		var made := false   # a chunk generated ahead: a key in the keep that was not there
		for key in w._ahead:
			made = made or not ahead.has(key)
		if w._loads != loads or made:
			busy += 1
			check_eq(fresh, 0, "tick %d loaded or generated ahead: no prefetch" % t)
			if w._next_chunks.size() < 25:
				waited["load" if w._loads != loads else "ahead"] += 1
		else:
			check(fresh <= 1, "tick %d: at most one a quiet tick" % t)
	sim.drain_events()
	print("test-growth-tick: the prefetch waited on %d load ticks and %d look-ahead ticks of %d busy in %d" % [
		waited.load, waited.ahead, busy, QUIET_TICKS])
	check(waited.load > 0 and waited.ahead > 0, "the prefetch waited on load and look-ahead ticks (%s)" % waited)
	check_eq(w._next_chunks.size(), 25, "and filled the 5 x 5 on the quiet ones")


func test_the_growth_tick_takes_its_view_set_from_the_cache() -> void:
	var sim := _sim(SEEDS[0])
	var w := sim.world
	var gen = w.gen
	var g := sim.growth
	g.meter = 0.95 * g.ring(1)
	for t in 25:
		w._prefetch(sim)
	check_eq(w._next_chunks.size(), 25, "the 5 x 5 ready")
	gen.built.clear()
	_due(sim)
	var ev := _tick(sim)
	check_eq(_of(ev, "grew").size(), 1, "grew")
	var view := w.view_set_keys(Vector2.ZERO)
	for key in view:
		check(not gen.built.has(key), "view chunk %s came from the cache" % key)
	check(_of(ev, "chunk_loaded").size() > view.size(), "the beat loaded beyond the view set in the same tick")
	# The beat keeps taking from the cache; after it the cache is forgotten.
	while sim.tick < g.beat_until:
		_tick(sim)
	_tick(sim)
	check(w._next_chunks.is_empty(), "forgotten after the beat")


## The growth tick takes the next size's arena (BP-4) as its arena once it has given up its chunks
## outside the view set, so it must be the arena a growth with the caches off builds chunk by chunk:
## the same chunks, colliders, spans, near grids and origin, through the growth tick and its beat; and
## its epoch is past every epoch the old arena had (no RouteKeep picked on the old one is taken).
func test_the_growth_tick_takes_the_next_arena_as_the_arena_the_caches_off_build() -> void:
	for seed_value: int in SEEDS:
		var on := _sim(seed_value, FakeWorldGen.s2_species())
		var off := _sim(seed_value, FakeWorldGen.s2_species())
		off.world.next_cache = false
		var dir := Vector2.from_angle(float(seed_value % 360) * PI / 180.0) * 0.6
		for t in 60:
			for sim: PoolSim in [on, off]:
				sim.growth.meter = 0.95 * sim.growth.ring(1)
				sim.step(SimIntent.new(dir))
		for sim: PoolSim in [on, off]:
			sim.world.next_size_clear_point(sim)   # the calm window's wedge test, as the tick before a growth makes it
			_due(sim)
		var next: ChunkArena = on.world._next_arena
		var old := on.arena as ChunkArena
		check(next != null and next.chunk_keys().size() == 9, "seed %d: the next arena ready" % seed_value)
		# Three quiet ticks' chore while heading two new-size chunks out on the diagonal: the arena
		# takes three chunks beyond the 3 x 3, the far corner among them, which the view set lacks.
		var v := on.motion.velocity
		var s1 := WorldConfig.tm_to_am(2)
		on.motion.velocity = Vector2(2.0, 2.0) * on.world.chunk_tm * s1 / WorldStream.NEXT_LEAD_S
		for t in 3:
			on.world._prefetch(on)
		on.motion.velocity = v
		check_eq(next.chunk_keys().size(), 12, "seed %d: the chore added three" % seed_value)
		old.epoch += 1000000   # a long run's arena: its epoch far past the next arena's
		var epoch := old.epoch
		on.step(SimIntent.new(dir))
		off.step(SimIntent.new(dir))
		check(on.size() == 2 and off.size() == 2, "seed %d: both grew" % seed_value)
		check(is_same(on.arena, next), "seed %d: the growth tick took the next arena" % seed_value)
		check(on.arena.epoch > epoch, "seed %d: its epoch past the old arena's (%d, %d)" % [seed_value, on.arena.epoch, epoch])
		var parted := -1
		for t in 90:
			if parted < 0 and _arena_state(on.arena) != _arena_state(off.arena):
				parted = t
			on.step(SimIntent.new(dir))
			off.step(SimIntent.new(dir))
		check_eq(parted, -1, "seed %d: the arenas equal through the growth tick and the beat" % seed_value)
		check_eq(_arena_state(on.arena), _arena_state(off.arena), "seed %d: and after it" % seed_value)



## The growth tick and its beat load from the cache with their loads prepared on quiet ticks (each
## zone's plankton stream, seeded and unused, and each chunk_loaded payload but its positions): every
## event and every hash is the one the caches off give, from the growth tick through the beat.
func test_prepared_loads_give_the_events_and_hashes_of_fresh_ones() -> void:
	for seed_value: int in SEEDS:
		var on := _sim(seed_value, FakeWorldGen.s2_species())
		var off := _sim(seed_value, FakeWorldGen.s2_species())
		off.world.next_cache = false
		for t in 80:
			for sim: PoolSim in [on, off]:
				sim.growth.meter = 0.95 * sim.growth.ring(1)
				sim.step(SimIntent.new())
				sim.drain_events()
		check_eq(on.world._next_events.size(), 25, "seed %d: every cached chunk's load prepared" % seed_value)
		check(on.world._next_streams.size() > 0, "seed %d: with its zones' streams (%d)" % [seed_value, on.world._next_streams.size()])
		_due(on)
		_due(off)
		var parted := -1
		var loaded := 0
		for t in 90:
			on.step(SimIntent.new())
			off.step(SimIntent.new())
			var got := on.drain_events()
			loaded += _of(got, "chunk_loaded").size()
			if parted < 0 and (got != off.drain_events() or on.state_hash() != off.state_hash()):
				parted = t
		check(on.size() == 2 and loaded > 9, "seed %d: grew and loaded (%d)" % [seed_value, loaded])
		check_eq(parted, -1, "seed %d: the same events and hashes through the growth tick and the beat" % seed_value)


## The growth tick hands what it lets go of (the old chunks, the plankton list, the old arena) to
## quiet ticks after the beat to free, one a tick, instead of freeing it in its own tick; they free all
## of it.
func test_the_old_world_is_freed_on_quiet_ticks_after_the_beat() -> void:
	var sim := _sim(SEEDS[1])
	var w := sim.world
	var old := sim.arena
	var chunks := w.loaded_keys().size()
	_due(sim)
	_tick(sim)
	check(sim.size() == 2, "grew")
	check_eq(w._retired.size(), chunks + 2, "the old chunks, the plankton list and the arena held")
	check(w._retired.has(old), "the old arena among them")
	var held := w._retired.size()
	while sim.tick < sim.growth.beat_until:
		_tick(sim)
	check_eq(w._retired.size(), held, "none freed in the beat")
	for t in 300:
		_tick(sim)
	check(w._retired.is_empty(), "all freed after it (%d left)" % w._retired.size())


## The growth tick's unload (_unload_all: the zones' plankton in one pass, the zones in the region's
## order) leaves what unloading every chunk one at a time ("growth") leaves: the region, its streams,
## the food, the zone index and records, the sites, the queue, the counters and the events; only the
## arena is left to grow, which replaces it.
func test_the_growth_unload_leaves_what_unloading_each_chunk_leaves() -> void:
	for seed_value: int in SEEDS:
		var whole := _swum(seed_value)
		var each := _swum(seed_value)
		check(not whole.region.zones.is_empty() and not whole.plankton.items.is_empty() and not whole.world.sites.is_empty(),
			"seed %d: zones, food and sites to unload" % seed_value)
		whole.world._unload_all(whole)
		for key in each.world.loaded_keys():
			each.world._unload_chunk(each, key, "growth")
		check_eq(_unloaded_state(whole), _unloaded_state(each), "seed %d: the same world" % seed_value)
		check_eq(whole.drain_events(), each.drain_events(), "seed %d: the same events" % seed_value)


static func _unloaded_state(sim: PoolSim) -> Dictionary:
	var w := sim.world
	var pk := sim.plankton
	return {"zones": sim.region.zones, "streams": sim.region.streams.keys(), "niches": sim.region.niches,
		"items": pk.items, "active": pk.active_zones, "counts": pk._zone_counts, "latched": pk._empty_latched,
		"regrowing": pk._regrowing, "keys": w.loaded_keys(), "zone_abs": w._zone_abs, "zone_chunk": w._zone_chunk,
		"fill": w._fill, "trimmed": w._trimmed, "index": [w._zone_ids, w._zone_c, w._zone_r, w._zone_refs, w._zone_ax, w._zone_ay],
		"versions": [w._zones_version, w._zones_indexed, w._index_epoch, w._site_epoch], "sites": w.sites, "queue": sim.creatures.queue,
		"creatures": sim.creatures.creatures.map(func(c: CreatureField.Creature) -> String: return c.id), "roles": w.site_counts}

## An arena's state but its epoch (which only grows): its chunks in canonical order, the canonical
## arrays, each chunk's span, near grid and colliders as added, its origin and its switches.
static func _arena_state(arena: ChunkArena) -> Dictionary:
	var chunks := {}
	for key in arena.chunk_keys():
		chunks[str(key)] = [arena._range[key], arena._grids[key], arena._chunk_colliders[key]]
	return {"keys": arena.chunk_keys(), "x": arena._abs_x, "y": arena._abs_y, "centers": arena._centers,
		"radii": arena._radii, "rocks": arena.rocks, "chunks": chunks, "origin": [arena.origin_x, arena.origin_y],
		"grid": arena.rock_grid, "fallbacks": arena.settle_fallbacks}


## PlanktonField.drop_zones, the growth tick's one pass over the items, leaves what drop_zone a zone
## at a time leaves: the same items in the same order, the same counts, flags, packed copies and id
## index; for some zones (with a flagged zone, an empty one and an unknown id among them), every zone
## that shows items, and none.
func test_drop_zones_leaves_what_drop_zone_a_zone_at_a_time_leaves() -> void:
	var cases := ["some", "all", "none"]
	for which: String in cases:
		var one := _sim(SEEDS[4])
		var each := _sim(SEEDS[4])
		for t in 120:
			for sim: PoolSim in [one, each]:
				sim.step(SimIntent.new(Vector2.from_angle(0.4) * 0.6))
		var shown: Array = one.plankton._zone_counts.keys()
		shown.sort()
		check(shown.size() >= 2 and one.plankton.items.size() > 4, "%s: zones show items (%d)" % [which, shown.size()])
		var ids := {}
		if which == "all":
			for id in shown:
				ids[id] = true
		elif which == "some":
			for i in range(0, shown.size(), 2):
				ids[shown[i]] = true
			ids["no_such_zone"] = true
			for z in one.region.zones:
				if not shown.has(z.id):
					ids[z.id] = true   # a zone that shows none
					break
		for sim: PoolSim in [one, each]:
			sim.plankton._empty_latched[shown[0]] = true
			sim.plankton._regrowing[shown[0]] = true
			sim.plankton._regrowing[shown[1]] = true
		one.plankton.drop_zones(ids)
		for id in ids:
			each.plankton.drop_zone(id)
		check_eq(_plankton_state(one.plankton), _plankton_state(each.plankton), "%s: the same field" % which)
		var kept := 0 if which == "all" else one.plankton.items.size()
		check(kept > 0 or which == "all", "%s: items stay (%d)" % [which, kept])


static func _plankton_state(field: PlanktonField) -> Dictionary:
	return {"items": field.items, "counts": field._zone_counts, "latched": field._empty_latched,
		"regrowing": field._regrowing, "phase": field._phase, "omega": field._omega, "radii": field._radii,
		"ids": field._by_id.keys(), "next": field.next_number}


# --- the beat (D-80) and the fills (C-V15) ---

func test_the_beat_loads_two_chunks_a_tick_then_one() -> void:
	var sim := _sim(SEEDS[1])
	_due(sim)
	_tick(sim)
	var g := sim.growth
	var during := 0
	var most := 0
	while sim.tick < g.beat_until:
		var n := _of(_tick(sim), "chunk_loaded").size()
		during += n
		most = maxi(most, n)
	check_eq(most, int(g.cfg.beat_loads_per_tick), "at most beat_loads_per_tick a tick, reached")
	var after := 0
	for t in 60:
		after = maxi(after, _of(_tick(sim), "chunk_loaded").size())
	check(after <= int(sim.world.caps.loads_per_tick), "caps.loads_per_tick after the beat (%d)" % after)
	check(during > 0, "loads during the beat (%d)" % during)


func test_food_filled_by_the_growth_tick_is_born_on_it() -> void:
	var sim := _sim(SEEDS[2])
	_due(sim)
	var t0 := sim.tick
	_tick(sim)
	var n := 0
	for item in sim.plankton.items:
		check_eq(int(item.born_tick), t0, "%s born on the growth tick (C-V15)" % item.id)
		n += 1
	check(n > 0, "the zones filled at once (%d items)" % n)


# --- S2G12: the size-2 world is the one a direct arrival meets ---

## The stream's content state over `keys`: whether each is loaded, each chunk's digest, the arena's
## colliders there (sorted absolute tuples, hashed), the sites homed there (id, species, absolute home
## and posts) and the zones there (id, absolute centre, radius, capacity).
static func _content(sim: PoolSim, keys: Array[Vector2i]) -> Dictionary:
	var w := sim.world
	var arena := sim.arena as ChunkArena
	var digests := {}
	var tuples := []
	for key in keys:
		var ch := w.chunk(key)
		digests[str(key)] = ch.digest() if ch != null else "missing"
		for c: Dictionary in arena._chunk_colliders.get(key, []):
			tuples.append([float(c.x), float(c.y), float(c.r)])
	tuples.sort()
	var sites := []
	var ids := w.sites.keys()
	ids.sort()
	for id in ids:
		var rec: Dictionary = w.sites[id]
		if keys.has(rec.home_chunk):
			sites.append([id, rec.species, _plain(rec.abs_tm), _plain(rec.get("abs_posts", PackedFloat64Array()))])
	var zones := []
	for z in sim.region.zones:
		if keys.has(w._zone_chunk.get(z.id)):
			zones.append([z.id, Array(w._zone_abs[z.id]), z.radius, z.capacity])
	zones.sort()
	return {"digests": digests, "colliders": hash(JSON.stringify(tuples)), "sites": sites, "zones": zones}


## The values, a missing one (NaN: no territory) as null, so equal records compare equal.
static func _plain(values: PackedFloat64Array) -> Array:
	var out := []
	for v in values:
		out.append(null if is_nan(v) else v)
	return out


func test_a_growth_meets_the_world_a_direct_size_two_arrival_meets() -> void:
	for seed_value: int in SEEDS:
		_check_growth_equals_arrival(seed_value)


func test_slow_a_growth_meets_the_world_a_direct_size_two_arrival_meets_on_50_seeds() -> void:
	for i in SLOW_SEEDS:
		_check_growth_equals_arrival(4000 + 97 * i)


func _check_growth_equals_arrival(seed_value: int) -> void:
	var grown := _swum(seed_value)
	var a := grown.world.abs_of_local(grown.motion.position)
	grown.world.grow(grown)
	var p := grown.motion.position
	var direct := _sim(seed_value, FakeWorldGen.s2_species(), 2, a)
	check(direct.motion.position == Vector2.ZERO, "seed %d: the direct run starts on the point" % seed_value)
	check(direct.debug_set_size(2), "seed %d: debug_set_size(2)" % seed_value)
	var keys := grown.world.loaded_keys()
	check_eq(direct.world.loaded_keys(), keys, "seed %d: the same chunks held" % seed_value)
	check_eq(_content(direct, keys), _content(grown, keys), "seed %d: the same chunks, colliders, sites and zones" % seed_value)
	check(direct.motion.position == p, "seed %d: the same settled point" % seed_value)


## S2G12 on the shipped content (T3.5's size-2 sites): a hidden omnivore's growth after a swim from
## home meets the world a debug_set_size(2) arrival at its point meets, size-2 sites among it.
func test_on_the_shipped_content_a_growth_meets_the_world_a_direct_arrival_meets() -> void:
	var waits := Gates.s2_missing(["set_size", "size_two_content"])
	if not waits.is_empty():
		print("test-growth-tick: the shipped-content S2G12 waits on: %s" % "; ".join(waits))
		return
	var grown: PoolSim = Gates.make_sim("omnivore", SEEDS[0], true)
	grown.debug_set_hidden(true)
	for t in SWIM_TICKS:
		grown.step(SimIntent.new(Vector2.from_angle(0.4 + 0.004 * t) * 0.6))
	grown.drain_events()
	var a := grown.world.abs_of_local(grown.motion.position)
	grown.world.grow(grown)
	var direct: PoolSim = Gates.make_sim("omnivore", SEEDS[0], true)
	check(Gates.teleport(direct, a), "the direct run is placed on the point")
	check(direct.world.abs_of_local(direct.motion.position) == a, "exactly")
	check(direct.debug_set_size(2), "debug_set_size(2)")
	var keys := grown.world.loaded_keys()
	check_eq(direct.world.loaded_keys(), keys, "the same chunks held")
	var want := _content(grown, keys)
	check_eq(_content(direct, keys), want, "the same chunks, colliders, sites and zones")
	check(direct.motion.position == grown.motion.position, "the same settled point")
	var entering := Gates.species_entering_at(2)
	var met := 0
	for site: Array in want.sites:
		met += 1 if entering.has(str(site[1])) else 0
	check(met > 0, "size-2 sites among them (%d of %d)" % [met, want.sites.size()])


func test_two_size_two_routes_meet_the_world_a_growth_makes() -> void:
	_check_routes(SEEDS[0], null)


func test_slow_two_size_two_routes_meet_the_world_a_growth_makes_on_50_seeds() -> void:
	for i in SLOW_SEEDS:
		_check_routes(5000 + 89 * i, FakeWorldGen.s2_species())


## A growth at P against two size-2 swims to P (from P - (ROUTE_AM, 0) and P + (0, ROUTE_AM)): once each
## has held still 120 ticks at P, the 3 x 3 chunks round P hold the same content in all three.
func _check_routes(seed_value: int, species: SpeciesCatalog) -> void:
	var grown := _sim(seed_value, species)
	grown.world.grow(grown)
	var p := grown.world.abs_of_local(grown.motion.position)
	for t in 120:
		grown.step(SimIntent.new())
	var keys := _round(grown, p)
	var want := _content(grown, keys)
	for from in [Vector2(-ROUTE_AM, 0.0), Vector2(0.0, ROUTE_AM)]:
		var swim := _sim(seed_value, species, 2, PackedFloat64Array([p[0] + from.x, p[1] + from.y]))
		check(swim.debug_set_size(2), "seed %d: at size 2" % seed_value)
		var bot = SwimBot.toward(p)
		var t := 0
		while t < 6000 and swim.world.local_of_abs(p[0], p[1]).distance_to(swim.motion.position) > 1.0:
			SwimBot.overdrive(swim)
			swim.step(bot.next_intent(swim))
			t += 1
		check(t < 6000, "seed %d: the swim from %s arrived" % [seed_value, from])
		for i in 120:
			swim.step(SimIntent.new())
		check_eq(_content(swim, keys), want, "seed %d: the route from %s meets the same world" % [seed_value, from])


## The 3 x 3 chunk keys round absolute point `p` at the sim's size.
static func _round(sim: PoolSim, p: PackedFloat64Array) -> Array[Vector2i]:
	var c := sim.world.chunk_of_local(sim.world.local_of_abs(p[0], p[1]))
	var out: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			out.append(Vector2i(c.x + dx, c.y + dy))
	return out


# --- S2G33: the events, in order, with their frames ---

func test_growth_tick_events_come_in_order_with_their_frames() -> void:
	var sim := _sim(SEEDS[3], FakeWorldGen.ladder_species())
	var cell := sim.motion.position
	sim.debug_set_ai_frozen(true)
	check(sim.debug_spawn_creature("rammer", cell + Vector2(-7.0, 3.0), 0.0), "a rammer (prey at size 2)")
	check(sim.debug_spawn_creature("minnow", cell + Vector2(6.0, 0.0), 0.0), "a minnow (a morsel at size 2), converted after it")
	var sleeper := _sleeping_site_creature(sim)
	check(sleeper != null, "a sleeper")
	var near: Dictionary = sim.carrion.spawn(cell + Vector2(3.0, -4.0), "test", 20.0)
	var far: Dictionary = sim.carrion.spawn(cell + Vector2(60.0, 0.0), "test", 20.0)
	sim.drain_events()
	var before := {}
	for c in sim.creatures.creatures:
		before[c.id] = c.motion.position
	var far_at: Vector2 = far.position
	_due(sim)
	var ev := _tick(sim)
	var order := []
	for e in ev:
		var tag := str(e.type)
		if e.has("reason") and str(e.reason) == "growth":
			tag += "{growth}"
		if order.is_empty() or order[-1] != tag:
			order.append(tag)
	var at_grew := order.find("grew")
	check_eq(order.slice(0, at_grew + 1), ["growth_began", "creature_converted", "carrion_spawned", "creature_converted",
		"creature_removed{growth}", "carrion_expired{growth}", "chunk_unloaded{growth}", "chunk_loaded", "grew"],
		"the order (S2G33): began, conversions (a morsel's carrion first), sleepers, carrion, unloads, loads, grew")
	check_eq(_first(ev, "carrion_spawned").source, "morsel", "the carrion is the morsel")
	# Old frame before the origin moves; new frame after.
	for e in _of(ev, "creature_converted"):
		check(e.position == before[e.id], "creature_converted %s in the old frame" % e.id)
	var removed := {}
	for e in _of(ev, "creature_removed"):
		if e.id == sleeper.id:
			removed = e
	check(removed.get("reason") == "growth" and removed.position == before[sleeper.id], "the sleeper's removal in the old frame")
	var expired := _first(ev, "carrion_expired")
	check(expired.food_id == far.id and expired.position == far_at, "the far carrion's expiry in the old frame")
	check(sim.carrion.find(near.id).size() > 0, "the near carrion kept")
	var w := sim.world
	for e in _of(ev, "chunk_loaded"):
		var ch := w.chunk(e.key)
		if ch != null and not ch.shells.is_empty():
			var s: Dictionary = ch.shells[0]
			check(e.shells[0].position == w.local_of_tm(float(s.x), float(s.y)), "chunk_loaded %s in the new frame" % e.key)
	var grew := _first(ev, "grew")
	check(grew.center == Vector2.ZERO and grew.settled_from == Vector2.ZERO, "grew's centre is the new origin")
	check_eq(grew.morsels.size(), 1, "one morsel")
	check(grew.remnants.size() >= 1, "the rammer a remnant")
	check(_of(ev, "rebased").is_empty(), "no rebased (D-65)")


## A site creature of `sim`, put to sleep (it is far from the cell or not: the growth tick takes every
## sleeper).
func _sleeping_site_creature(sim: PoolSim) -> CreatureField.Creature:
	for t in 600:
		for c in sim.creatures.creatures:
			if not c.site_id.is_empty():
				if not c.asleep:
					sim.creatures.sleep(c, sim.tick)
				return c
		sim.step(SimIntent.new())
	return null


# --- S2G34: every conversion exact ---

func test_conversions_are_exact() -> void:
	var sim := _sim(SEEDS[4], FakeWorldGen.ladder_species(), 64)   # no site creature near
	var cell := sim.motion.position
	sim.debug_set_ai_frozen(true)
	check(sim.debug_spawn_creature("ambush_hunter", cell + Vector2(5.0, 2.0), 1.0), "an ambush hunter (a rival at size 2)")
	check(sim.debug_spawn_creature("minnow", cell + Vector2(-6.0, 0.0), 0.0), "a minnow")
	var hunter: CreatureField.Creature = null
	for c in sim.creatures.creatures:
		if c.species_id == "ambush_hunter":
			hunter = c
	hunter.state.health = hunter.phenotype.max_health * 0.5
	hunter.state.energy = 30.0
	hunter.motion.velocity = Vector2(0.8, -0.4)
	var scripted := sim.creatures.spawn_scripted("rammer", hunter.phenotype, cell + Vector2(0.0, 8.0), 0.0, sim.tick)
	var item: Dictionary = sim.carrion.spawn(cell + Vector2(2.0, 5.0), "kill", 18.0, -1, 0.27, 75.0)
	item.age = 12.5
	var was := item.duplicate()
	var r_minnow := float(sim.species.at_size("minnow", 2, catalog).phenotype.radius)
	sim.drain_events()
	_due(sim)
	var ev := _tick(sim)
	var f := WorldConfig.GROWTH_FACTOR
	# Carrion: id, age, lifetime and source kept; radius and energy / 1.6; points from the energy.
	var now := sim.carrion.find(was.id)
	check(not now.is_empty(), "the carrion kept its id")
	check_eq(now.source, was.source, "its source")
	check_eq(now.lifetime, was.lifetime, "its lifetime")
	check_near(float(now.age), float(was.age) + PoolSim.DT, 1e-9, "its age (and one tick on)")
	check_eq(now.radius, float(was.radius) / f, "radius / 1.6")
	check_eq(now.energy, float(was.energy) / f, "energy / 1.6")
	check_eq(now.points, floori(float(was.energy) / f / sim.carrion.energy * sim.carrion.points + 1e-6), "points from the energy")
	# The morsel: made once at the new size, never shrunk again (D-66).
	var conv := {}
	for e in _of(ev, "creature_converted"):
		conv[e.species] = e
	check_eq(conv.minnow.to, "morsel", "the minnow is a morsel")
	var morsel := sim.carrion.find(conv.minnow.food_id)
	var max_r := float(sim.growth.cfg.remnants.morsel_max_radius_tm)
	check_eq(morsel.radius, minf(r_minnow, max_r), "the morsel's radius, once")
	check_eq(morsel.energy, sim.carrion.energy * r_minnow / Relationships.PLAYER_RADIUS, "its energy from its new radius")
	check_eq(morsel.lifetime, float(sim.growth.cfg.remnants.morsel_rot_s), "it rots in morsel_rot_s")
	check_eq(conv.minnow.radius, r_minnow, "the event's radius is the new one")
	# The remnant: at_size(n + 1)'s body, health and velocity / 1.6.
	check_eq(conv.ambush_hunter.to, "remnant", "the hunter is a remnant")
	var rem := sim.remnants.find(hunter.id)
	check(rem != null, "the remnant keeps the id")
	var rec := sim.species.at_size("ambush_hunter", 2, catalog)
	check(is_same(rem.phenotype, rec.phenotype), "its body is at_size(2)'s")
	check_eq(rem.state.health, minf(hunter.state.health / f, rec.phenotype.max_health), "health / 1.6")
	check_eq(rem.state.energy, 30.0 / f, "energy / 1.6")
	check(rem.born_tick == sim.tick - 1, "born on the growth tick")
	# The scripted body is haze.
	check_eq(str(conv.get("rammer", {}).get("to", "")), "haze", "a scripted body is haze")
	check(sim.creatures.find(scripted.id) == null, "and gone")


func test_remnants_over_the_cap_turn_to_haze_nearest_kept() -> void:
	var sim := _sim(SEEDS[0], FakeWorldGen.ladder_species(), 64)
	sim.debug_set_ai_frozen(true)
	sim.remnants.cap = 2
	var cell := sim.motion.position
	var ids := []
	for i in 4:
		var p := cell + Vector2.from_angle(1.3 * i) * (8.0 + 3.0 * i)
		check(sim.debug_spawn_creature("rammer", p, 0.0), "rammer %d" % i)
	for c in sim.creatures.creatures:
		ids.append([cell.distance_to(c.motion.position), c.id])
	ids.sort()
	_due(sim)
	var ev := _tick(sim)
	var to := {}
	for e in _of(ev, "creature_converted"):
		to[e.id] = e.to
	check_eq([to[ids[0][1]], to[ids[1][1]], to[ids[2][1]], to[ids[3][1]]], ["remnant", "remnant", "haze", "haze"],
		"the nearest two kept (D-78)")
	check_eq(sim.world.counters.remnant_overflow, 1, "counted once")


# --- after the growth: a crack narrower than a body (BP-2 invariant 1 at size 2) ---

## A crack CRACK_GAP_SHARE x a body's width across, between two shells of CRACK_RADII (the share of
## that body's radius), CRACK_AHEAD tm east of where the body starts at size 2. The tiles keep every
## crack 1.5 tm wide at size 1 (#32), which is 0.94 tm at size 2: under the cell's 1.0.
const CRACK_GAP_SHARE := 0.9
const CRACK_RADII := [1.44, 1.06]
const CRACK_AHEAD := 3.0
const CRACK_LANE := 0.3                 ## tm: the lane runs this far off the crack's middle, toward the first shell
const CRACK_TICKS := 150
const CRACK_REMNANT_TICKS := 600        ## a remnant flees at its flee share of its speed
const CRACK_PUSH := 0.4                 ## tm: how far the cell presses into the body at the mouth


## Adds, at size 2, the crack for a body of radius `r` round the point CRACK_AHEAD tm (at size 2) east
## of the cell; the sim is at size 1 and the size-2 chunks there not yet made. Returns the crack's
## middle and its two shells as [x, y, r] in absolute size-2 tm.
static func _crack_at_size_two(sim: PoolSim, r: float) -> Array:
	var s2 := WorldConfig.tm_to_am(2)
	var a := sim.world.abs_of_local(sim.motion.position)
	var mid := Vector2(a[0] / s2 + CRACK_AHEAD, a[1] / s2)
	var r_n: float = CRACK_RADII[0] * r
	var r_s: float = CRACK_RADII[1] * r
	var half := CRACK_GAP_SHARE * r
	var shells := [[mid.x, mid.y + half + r_n, r_n], [mid.x, mid.y - half - r_s, r_s]]
	for s in shells:
		var key := Vector3i(floori(s[0] / sim.world.chunk_tm), floori(s[1] / sim.world.chunk_tm), 2)
		var more: Array = sim.world.gen.extra_shells.get(key, [])
		more.append({"x": s[0], "y": s[1], "r": s[2]})
		sim.world.gen.extra_shells[key] = more
	return [mid, shells]


## The deepest a body of radius `r` at `p` digs into either shell of the crack (size-2 tm, local).
static func _crack_dig(sim: PoolSim, crack: Array, p: Vector2, r: float) -> float:
	var s2 := WorldConfig.tm_to_am(2)
	var most := -INF
	for s in crack[1]:
		var c := sim.world.local_of_abs(s[0] * s2, s[1] * s2)
		most = maxf(most, s[2] + r - p.distance_to(c))
	return most


## The crack's middle, local.
static func _crack_mid(sim: PoolSim, crack: Array) -> Vector2:
	var s2 := WorldConfig.tm_to_am(2)
	return sim.world.local_of_abs(crack[0].x * s2, crack[0].y * s2)


## The cell swims east into a crack narrower than it at size 2, every tick: the arena's two settle
## passes, pushed from one shell into the other, would leave it inside one (in the growth fuzz, 33 mm
## into a reef shell at worst). A move that ends inside a rock is taken back, so it stops at the mouth
## touching both and never digs past FuzzInvariants' 1 mm.
func test_at_size_two_the_cell_stops_at_the_mouth_of_a_crack_narrower_than_it() -> void:
	var sim := _sim(SEEDS[0])
	var r := sim.phenotype.radius
	var crack := _crack_at_size_two(sim, r)
	check(sim.debug_set_size(2), "size 2")
	var mid := _crack_mid(sim, crack)
	var start := mid + Vector2(-CRACK_AHEAD, CRACK_LANE)
	check(sim.debug_teleport(start, 0.0), "the lane's start, heading east")
	check(sim.arena.is_clear(start, r), "open water there")
	var most := -INF
	for t in CRACK_TICKS:
		sim.step(SimIntent.new(Vector2.RIGHT))
		most = maxf(most, _crack_dig(sim, crack, sim.motion.position, r))
	check(most <= FuzzInvariants.ROCK_SLACK_M, "never more than 1 mm into a shell (%.4f m)" % most)
	check(most >= -0.02, "it reached the shells (%.4f m)" % most)
	check(sim.motion.position.x < mid.x, "held at the mouth, west of the crack's middle")
	check(sim.motion.position.x > start.x + 1.0, "after swimming in")
	# A body already inside (a load or a test may put one there) is not held there: it swims out.
	sim.motion.position = mid
	sim.motion.velocity = Vector2.ZERO
	var out_at := -1
	for t in CRACK_TICKS:
		sim.step(SimIntent.new(Vector2.LEFT))
		if _crack_dig(sim, crack, sim.motion.position, r) <= 0.0:
			out_at = t
			break
	check(out_at >= 0, "out of the crack, swimming west (after %d ticks)" % out_at)


## The same crack for the other bodies that move at size 2: an awake creature (tick step 4), a remnant
## (RemnantField.tick) and a body that contacts push in (tick step 5); each from size 1 is exactly S1's.
func test_at_size_two_creatures_remnants_and_pushed_bodies_stop_at_the_mouth_of_a_crack() -> void:
	var sim := _sim(SEEDS[0], FakeWorldGen.s2_species())
	var rec := sim.species.at_size("lurker", 2, catalog)
	var r: float = rec.phenotype.radius
	var crack := _crack_at_size_two(sim, r)
	check(sim.debug_set_size(2), "size 2")
	sim.debug_set_ai_frozen(true)
	var mid := _crack_mid(sim, crack)
	var start := mid + Vector2(-CRACK_AHEAD, CRACK_LANE * r / 0.5)
	# The cell well west, out of everything's way.
	check(sim.debug_teleport(mid + Vector2(-CRACK_AHEAD - 6.0, 0.0), 0.0), "the cell to the west")
	check(sim.debug_spawn_creature("lurker", start, 0.0), "a lurker at the lane's start")
	var c: CreatureField.Creature = null
	for each in sim.creatures.awake():
		if each.species_id == "lurker" and each.motion.position == start:
			c = each
	check(c != null, "and awake")
	if c == null:
		return
	var most := -INF
	for t in CRACK_TICKS:
		c.motion.velocity = Vector2(rec.phenotype.speed, 0.0)   # as its steering would, every tick
		sim._move_creatures()
		most = maxf(most, _crack_dig(sim, crack, c.motion.position, r))
	check(most <= FuzzInvariants.ROCK_SLACK_M, "a creature: never more than 1 mm into a shell (%.4f m)" % most)
	check(most >= -0.02 and c.motion.position.x < mid.x, "a creature: at the mouth (%.4f m)" % most)
	# A body pushed in: the cell presses into the creature at its mouth from behind.
	var mouth := c.motion.position
	var behind := mouth - Vector2(sim.phenotype.radius + r - CRACK_PUSH, 0.0)
	check(sim.debug_teleport(behind, 0.0), "the cell pressed into it from the west")
	sim.motion.velocity = Vector2.ZERO
	c.motion.velocity = Vector2.ZERO
	sim._contacts()
	var pushed := _crack_dig(sim, crack, c.motion.position, r)
	check(pushed <= FuzzInvariants.ROCK_SLACK_M, "a pushed creature: never more than 1 mm into a shell (%.4f m)" % pushed)
	check(sim.motion.position.distance_to(c.motion.position) < sim.phenotype.radius + r, "the two still overlap: the push was taken back")
	# A remnant fleeing the cell, east into the crack (remnants keep still under the freeze).
	sim.debug_set_ai_frozen(false)
	check(sim.debug_teleport(start + Vector2(-2.0, 0.0), 0.0), "the cell behind the lane")
	var rem := sim.remnants.add_from(c, rec, sim.tick)
	rem.motion.position = start
	rem.motion.velocity = Vector2.ZERO
	most = -INF
	for t in CRACK_REMNANT_TICKS:
		sim.remnants.tick(sim)
		if sim.remnants.find(rem.id) == null:
			break
		most = maxf(most, _crack_dig(sim, crack, rem.motion.position, r))
	check(sim.remnants.find(rem.id) != null, "the remnant stayed in view")
	check(most <= FuzzInvariants.ROCK_SLACK_M, "a remnant: never more than 1 mm into a shell (%.4f m)" % most)
	check(most >= -0.02 and rem.motion.position.x < mid.x, "a remnant: at the mouth (%.4f m)" % most)
