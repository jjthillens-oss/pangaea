extends TestCase
## The endless world's floating origin (S1 T2.4) on FakeWorldGen. A rebase moves the origin by whole
## chunks: every position the sim stores moves by exactly the offset (a reflection walk over the
## whole sim proves no Vector2 is missed), absolute places stay put within 2^-16 tm, and zones and
## colliders re-derive from their absolute values instead of accumulating shifts. A teleport to
## 100 km keeps every local position small and the arena exact (G10, G12).

const FakeWorldGen := preload("res://tests/fakes/fake_world_gen.gd")
const SEED := 4303
## Invariant 13: every local position stays under this (world_cell.json's origin.local_bound_tm).
const LOCAL_BOUND := 256.0
## The sim's fields that hold no local positions, so the walk skips them, with the reason.
const STATIC := {
	"catalog": "part data",
	"layout": "the pool's layout data, which the endless world does not place",
	"species": "creature data",
	"phenotype": "derived from the genome",
	"save": "the save, written on save in absolute values",
	"content": "absolute world data",
	"gen": "absolute world data",
	"_chunks": "WorldChunks: absolute float64 data",
	"_phenotypes": "creature data",
	"_senses": "creature data",
	"cfg": "brain tuning data",
	"camera": "camera tuning data",
}

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()


func _endless(with_species := true) -> PoolSim:
	return FakeWorldGen.endless_sim(SEED, catalog, layout, species if with_species else null)


## A sim with something in every place a position can live: the cell swimming, food of both kinds,
## and two debug creatures whose memories are all set (seen, lane, goal, progress, flee_from,
## territory) and which are moving.
func _busy_sim() -> PoolSim:
	var sim := _endless()
	for t in 120:
		sim.step(SimIntent.new(Vector2(1.0, 0.3)))
	sim.carrion.spawn(sim.motion.position + Vector2(4.0, 1.0), "test", 10.0)
	sim.carrion.spawn(sim.motion.position + Vector2(-6.0, 3.0), "test", 10.0)
	for i in 2:
		var c := sim.creatures.spawn_at("rammer" if i == 0 else "ambush_hunter", sim.motion.position + Vector2(10.0 + 4.0 * i, -8.0),
			0.3, "", sim.tick, true)
		check(c != null, "debug creature %d" % i)
		var mem := c.brain
		mem.seen["player"] = {"position": sim.motion.position, "velocity": sim.motion.velocity, "tick": sim.tick, "by": "sight",
			"species": "player", "radius": sim.phenotype.radius, "engageable": false}
		mem.lane = CreatureBrain.strike_lane(species.brain_config(c.species_id).attack, c.phenotype.radius, sim.phenotype.radius,
			c.motion.position, 0.3)
		mem.goal = c.motion.position + Vector2(3.0, 2.0)
		mem.progress = {"position": c.motion.position + Vector2(0.5, 0.5), "tick": sim.tick}
		mem.flee_from = sim.motion.position
		mem.territory_center = c.motion.position + Vector2(-1.0, 1.0)
		c.motion.velocity = Vector2(0.4, -0.2)
		c.motion.prev_position = c.motion.position - Vector2(0.01, 0.02)
	return sim


## Every Vector2 reachable from the sim's state, by path (PackedVector2Array entries included).
func _vectors(sim: PoolSim) -> Dictionary:
	var out := {}
	_walk(sim, "sim", out, {})
	return out


func _walk(v: Variant, path: String, out: Dictionary, seen: Dictionary) -> void:
	match typeof(v):
		TYPE_VECTOR2:
			out[path] = v
		TYPE_PACKED_VECTOR2_ARRAY:
			for i in v.size():
				out["%s[%d]" % [path, i]] = v[i]
		TYPE_DICTIONARY:
			for k in v:
				_walk(v[k], "%s.%s" % [path, k], out, seen)
		TYPE_ARRAY:
			for i in v.size():
				_walk(v[i], "%s[%d]" % [path, i], out, seen)
		TYPE_OBJECT:
			if v == null or not (v is RefCounted) or seen.has(v.get_instance_id()):
				return
			seen[v.get_instance_id()] = true
			for prop in v.get_property_list():
				if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not STATIC.has(prop.name):
					_walk(v.get(prop.name), "%s.%s" % [path, prop.name], out, seen)


## True when the path's value is named in RebaseShift.NOT_POSITIONS: by its own name, by its parent
## and name ("drive.move"), or by an "events" list anywhere above it.
static func _named(path: String) -> bool:
	var parts: Array = []
	for part in path.split("."):
		parts.append(part.get_slice("[", 0).lstrip("_"))
	if parts.has("events"):
		return true
	var last: String = parts[-1]
	return RebaseShift.NOT_POSITIONS.has(last) or RebaseShift.NOT_POSITIONS.has("%s.%s" % [parts[-2], last])


## float32 rounding of a shifted value: half an ulp of the result, and of the operands.
static func _shift_ok(before: Vector2, after: Vector2, by: Vector2) -> bool:
	if not before.is_finite():
		return after == before
	var want := before - by
	var tol := maxf(want.abs().x, want.abs().y) * 1.2e-7 + maxf(before.abs().x, before.abs().y) * 1.2e-7
	return absf(after.x - want.x) <= tol and absf(after.y - want.y) <= tol


func test_a_rebase_moves_every_stored_position_by_the_offset() -> void:
	var sim := _busy_sim()
	var before := _vectors(sim)
	var offset := Vector2(96.0, -64.0)
	check(sim.debug_rebase(Vector2i(3, -2)), "rebased")
	var after := _vectors(sim)
	var moved := 0
	var kept := 0
	var bad: Array = []
	var kinds := {}
	for path in before:
		# Events move from the fields' lists to the sim's as the rebase is emitted; they keep their
		# emitting tick's frame (spine 3.12), so they are not compared.
		if _named(path) and path.contains("events"):
			continue
		if not after.has(path):
			bad.append("%s vanished" % path)
			continue
		if _named(path):
			kept += 1
			if after[path] != before[path]:
				bad.append("%s is named but changed" % path)
			continue
		if _shift_ok(before[path], after[path], offset):
			moved += 1
			kinds[path.get_slice(".", path.get_slice_count(".") - 1).get_slice("[", 0)] = true
		else:
			bad.append("%s: %s -> %s" % [path, before[path], after[path]])
	check(bad.is_empty(), "every Vector2 moves by the offset or is named (%d bad: %s)" % [bad.size(), bad.slice(0, 6)])
	check(moved >= 40, "positions moved (%d)" % moved)
	check(kept > 0, "named values kept (%d)" % kept)
	# Each kind of position was there to be checked.
	for name in ["position", "prev_position", "anchor", "origin", "goal", "flee_from", "home", "territory_center", "center"]:
		check(kinds.has(name), "a %s was checked" % name)
	var paths := " ".join(PackedStringArray(before.keys()))
	for part in [".seen.player.position", ".lane.origin", ".progress.position", "arena._centers[", "region.zones["]:
		check(paths.contains(part), "the walk reached %s" % part)


func test_absolute_positions_hold_within_2_pow_minus_16_across_a_forced_rebase() -> void:
	var sim := _busy_sim()
	var o := PackedFloat64Array([sim.world.origin_x_am, sim.world.origin_y_am])
	var before := _vectors(sim)
	sim.debug_rebase(Vector2i(3, -2))
	var o2 := PackedFloat64Array([sim.world.origin_x_am, sim.world.origin_y_am])
	check_eq(o2, PackedFloat64Array([o[0] + 96.0, o[1] - 64.0]), "the origin moved by (96, -64) exactly")
	var after := _vectors(sim)
	var worst := 0.0
	var n := 0
	for path in before:
		if _named(path) or not before[path].is_finite():
			continue
		var b: Vector2 = before[path]
		var a: Vector2 = after[path]
		worst = maxf(worst, maxf(absf((o2[0] + float(a.x)) - (o[0] + float(b.x))), absf((o2[1] + float(a.y)) - (o[1] + float(b.y)))))
		n += 1
	check(n >= 40, "%d positions" % n)
	check(worst <= pow(2.0, -16.0), "every absolute place within 2^-16 tm (worst %s)" % worst)


func test_a_rebase_fires_beyond_96_tm_by_whole_chunks() -> void:
	var sim := _endless(false)
	sim.drain_events()
	var fired: Array = []
	var first_over := -1
	for t in 3000:
		var p := sim.motion.position
		if first_over < 0 and p.length() > 96.0:
			first_over = t
		sim.step(SimIntent.new(Vector2.RIGHT))
		for e in sim.drain_events():
			if e.type == "rebased":
				e["at"] = t
				e["from"] = p
				fired.append(e)
		if fired.size() == 1 and first_over >= 0:
			break
	check(first_over >= 0, "the cell got past 96 tm")
	check_eq(fired.size(), 1, "one rebase")
	if fired.size() == 1:
		var e: Dictionary = fired[0]
		check_eq(int(e.at), first_over, "on the first tick past 96 tm")
		var want := Vector2(roundf(e.from.x / 32.0) * 32.0, roundf(e.from.y / 32.0) * 32.0)
		check_eq(e.offset_tm, want, "by the nearest whole chunks")
		check(e.offset_tm == Vector2(96.0, 0.0) or e.offset_tm == Vector2(128.0, 0.0), "(96, 0) or (128, 0): %s" % e.offset_tm)
		check_eq(e.origin_am, [want.x, 9.0 + want.y], "origin_am after it")
		check(sim.motion.position.length() < 40.0, "the cell is near the origin again")


## 1,800 ticks of swimming with a forced rebase of up to two chunks either way every 60: the cell's
## absolute track stays continuous, every local position stays under 256 tm, and zones and colliders
## stay where their absolute values put them. (FuzzInvariants checks the full set, T2.8.)
func test_a_rebase_every_60_ticks_keeps_places_continuous_and_small() -> void:
	var sim := _endless()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var last := sim.absolute_position_am()
	var bad := 0
	var first := ""
	var rebases := 0
	for t in 1800:
		if t % 60 == 30:
			var by := Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
			sim.debug_rebase(by)
			rebases += 1
		var angle := t * 0.004
		sim.step(SimIntent.new(Vector2.from_angle(angle)))
		var a := sim.absolute_position_am()
		var step := Vector2(a[0] - last[0], a[1] - last[1]).length()
		last = a
		var problem := ""
		if step > sim.phenotype.speed / 60.0 * 1.5 + 1e-4:
			problem = "the cell jumped %.4f tm" % step
		var far := _farthest_local(sim)
		if far >= LOCAL_BOUND:
			problem = "a local position at %.1f tm" % far
		if not _derived_exactly(sim):
			problem = "a zone or collider off its absolute place"
		if not problem.is_empty():
			bad += 1
			if first.is_empty():
				first = "tick %d: %s" % [t, problem]
	check_eq(bad, 0, "continuous, small and exact (%s)" % first)
	check(rebases >= 29, "%d forced rebases" % rebases)


func test_a_teleport_to_100_km_keeps_locals_small_and_the_arena_exact() -> void:
	var sim := _endless()
	sim.drain_events()
	check(sim.debug_teleport_abs(100000.3, -100000.7), "teleported")
	check_eq(sim.world.origin_x_am, 100000.3, "origin x exactly")
	check_eq(sim.world.origin_y_am, -100000.7, "origin y exactly")
	check(sim.motion.position.length() < 20.0, "the cell near the new origin")
	var a := sim.absolute_position_am()
	check_near(a[0], 100000.3 + sim.motion.position.x, 1e-9, "its absolute place")
	var view := sim.world.view_set_keys(sim.motion.position)
	for key in view:
		check(sim.world.chunk(key) != null, "view-set chunk %s loaded at once" % key)
	for t in 600:
		sim.step(SimIntent.new(Vector2.from_angle(t * 0.01)))
	check(_farthest_local(sim) < LOCAL_BOUND, "every local under 256 tm (%.1f)" % _farthest_local(sim))
	check(_derived_exactly(sim), "zones and colliders exact out there")
	# 2,000 queries against a brute-force twin of the arena built at the same origin.
	var arena := sim.arena as ChunkArena
	var twin := ChunkArena.create_endless(32.0)
	twin.rock_grid = false
	twin.set_origin(arena.origin_x, arena.origin_y)
	for key in arena.chunk_keys():
		var colliders: Array[Dictionary] = []
		for s in sim.world.chunk(key).shells:
			colliders.append({"id": s.id, "x": float(s.x), "y": float(s.y), "r": float(s.r)})
		twin.add_chunk(key, colliders)
	check_eq(twin._centers, arena._centers, "the same local centres")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var differ := 0
	for i in 2000:
		var p := sim.motion.position + Vector2(rng.randf_range(-60.0, 60.0), rng.randf_range(-60.0, 60.0))
		var q := p + Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
		var r := rng.randf_range(0.2, 1.5)
		if arena.is_clear(p, r) != twin.is_clear(p, r):
			differ += 1
		if arena.segment_clear(p, q) != twin.segment_clear(p, q):
			differ += 1
		if arena.route_point(p, q, r) != twin.route_point(p, q, r):
			differ += 1
		if arena.rock_contact(p, r) != twin.rock_contact(p, r):
			differ += 1
	check_eq(differ, 0, "2,000 queries agree with the brute-force twin")


## A teleport's events: the old chunks unload, then rebased, then the new view set loads, then debug.
func test_a_teleport_unloads_then_rebases_then_loads() -> void:
	var sim := _endless()
	var c := sim.creatures.spawn_at("rammer", Vector2(6.0, -6.0), 0.0, "", sim.tick, true)
	sim.carrion.spawn(Vector2(2.0, 2.0), "test", 10.0)
	var old := sim.world.loaded_keys()
	sim.drain_events()
	check(sim.debug_teleport_abs(5000.0, 9.0), "teleported 5 km east")
	var types: Array = []
	for e in sim.drain_events():
		types.append(e.type)
	var r := types.find("rebased")
	check(r > 0, "a rebased")
	check_eq(types.count("chunk_unloaded"), old.size(), "every old chunk unloaded")
	check(types.slice(0, r).all(func(t: String) -> bool: return t == "chunk_unloaded" or t == "creature_removed"),
		"only unloads and removals before it: %s" % [types.slice(0, r)])
	var d := types.find("debug")
	check(d > r and d == types.size() - 1, "debug last")
	check(types.slice(r + 1, d).all(func(t: String) -> bool: return t == "chunk_loaded" or t == "tile_entered"),
		"only loads after it: %s" % [types.slice(r + 1, d)])
	check(sim.creatures.find(c.id) == null, "the creature left with its ground")
	check(sim.carrion.items.is_empty(), "the carrion too (C-10)")
	for id in sim.plankton.active_zones:
		check_eq(sim.plankton.count_in(id), sim.plankton.target_count(sim.region.zone(id)), "zone %s filled at once (C-9)" % id)


func test_no_event_is_pending_when_the_streaming_block_starts() -> void:
	var sim := _endless()
	check(sim.debug_spawn_creature("rammer", Vector2(8.0, -8.0), 0.0), "a creature about")
	var pending := 0
	for t in 600:
		var n := sim.plankton.events.size() + sim.carrion.events.size() + sim.creatures.events.size()
		for c in sim.creatures.creatures:
			if c.brain != null:
				n += c.brain.events.size()
		if n > 0:
			pending += 1
		sim.step(SimIntent.new(Vector2.from_angle(t * 0.02)))
	check_eq(pending, 0, "the field and brain event lists are empty before every step")


func test_prev_positions_shift_with_their_positions() -> void:
	var sim := _busy_sim()
	var gaps := {"cell": sim.motion.position - sim.motion.prev_position}
	for c in sim.creatures.creatures:
		gaps[c.id] = c.motion.position - c.motion.prev_position
	sim.debug_rebase(Vector2i(-2, 1))
	# Unchanged up to the float32 rounding of the two shifted values (an ulp is 7.6e-6 under 128 tm).
	check((sim.motion.position - sim.motion.prev_position - gaps.cell).length() < 1.6e-5, "the cell's step is unchanged")
	for c in sim.creatures.creatures:
		check((c.motion.position - c.motion.prev_position - gaps[c.id]).length() < 1.6e-5, "creature %s's step is unchanged" % c.id)
	check(gaps.cell.length() > 0.0, "the cell was moving")


func test_zones_and_colliders_are_re_derived_not_accumulated() -> void:
	var sim := _endless()
	# An origin with fractions, so local values are not whole numbers that any route keeps exact.
	check(sim.debug_teleport_abs(1000.3, -2000.7), "teleported")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var path: Array[Vector2i] = []
	for i in 50:
		path.append(Vector2i(rng.randi_range(-3, 3), rng.randi_range(-3, 3)))
	for by in path:
		sim.debug_rebase(by)
	path.reverse()
	for by in path:
		sim.debug_rebase(-by)
	# The origin itself adds in float64: back within a few of its ulps (4.5e-13 at 2 km).
	check_near(sim.world.origin_x_am, 1000.3, 1e-9, "back at the start x")
	check_near(sim.world.origin_y_am, -2000.7, 1e-9, "and y")
	check(_derived_exactly(sim), "every zone centre and collider equals a fresh derivation")
	# 1,000 km out and back: a shifted float32 would keep only 1/16 tm out there.
	sim.debug_rebase(Vector2i(31251, -31251))
	check(_derived_exactly(sim), "also 1,000 km out")
	sim.debug_rebase(Vector2i(-31251, 31251))
	check(_derived_exactly(sim), "and back")


func test_debug_commands_refuse_in_the_pool() -> void:
	var r := Lineage.found(SEED, "test+dev", catalog, "omnivore")
	r.save.player["position"] = PlaneSpace.to_save(layout.spawn)
	var sim := PoolSim.create(r.save, catalog, layout, species)
	var before := sim.motion.position
	check(not sim.debug_rebase(Vector2i(1, 0)), "no rebase in the pool")
	check(not sim.debug_teleport_abs(100.0, 9.0), "no absolute teleport in the pool")
	check_eq(sim.motion.position, before, "nothing moved")
	var e := _endless(false)
	check(not e.debug_teleport_abs(NAN, 9.0), "a place that is not finite is refused")
	check(not e.debug_teleport_abs(0.0, INF), "both axes")


## Every zone centre and every collider centre equals its absolute value minus the origin, computed
## now in float64 and cast.
func _derived_exactly(sim: PoolSim) -> bool:
	var w := sim.world
	for key in w.loaded_keys():
		for z in w.chunk(key).zones:
			var rz := sim.region.zone(z.id)
			if rz.is_empty() or rz.center != Vector2(float(z.x) - w.origin_x_am, float(z.y) - w.origin_y_am):
				return false
	var arena := sim.arena as ChunkArena
	var i := 0
	for key in arena.chunk_keys():
		for s in w.chunk(key).shells:
			if arena._centers[i] != Vector2(float(s.x) - w.origin_x_am, float(s.y) - w.origin_y_am):
				return false
			i += 1
	return i == arena._centers.size()


## The largest local coordinate among the positions invariant 13 lists.
func _farthest_local(sim: PoolSim) -> float:
	var far := 0.0
	var vs := _vectors(sim)
	for path in vs:
		if _named(path):
			continue
		var v: Vector2 = vs[path]
		if v.is_finite():
			far = maxf(far, v.length())
	return far
