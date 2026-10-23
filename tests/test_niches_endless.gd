extends TestCase
## The endless world's sites and niches (S1 T2.5) on FakeWorldGen, whose chunks (2 + 4i, 2 + 4j)
## each hold one rammer site (territorial, its reach disc inside the chunk). A loaded chunk's live
## sites enter the site table and queue at once; the niche caps are the table's sites per role,
## recomputed after every load and after the unloaded sites' creatures have left (G7); a site's
## creature is a hash of the world seed, the site and its spawn count, so it is the same along any
## route; a site whose reach comes near the checkpoint stays dormant.

const FakeWorldGen := preload("res://tests/fakes/fake_world_gen.gd")
const SEED := 4305

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()


func _endless(at := PackedFloat64Array()) -> PoolSim:
	return FakeWorldGen.endless_sim(SEED, catalog, layout, species, null, at)


## The caps the table implies, worked out here: per role of a species drawn at the world's size
## (entry_size at most the size: BP-10, so the real catalog's size-2 species add no role at size 1),
## the sites whose species fills it.
func _want_caps(sim: PoolSim) -> Dictionary:
	var out := {}
	for id in species.species_ids():
		if species.entry_size(id) <= sim.size():
			out[str(species.niche_of(id).role)] = 0
	for id in sim.world.sites:
		var role := str(species.niche_of(str(sim.world.sites[id].species)).role)
		out[role] = int(out[role]) + 1
	return out


func _caps(sim: PoolSim) -> Dictionary:
	var out := {}
	for role in sim.region.niches:
		out[role] = int(sim.region.niches[role].cap)
	return out


## Every live site of every loaded chunk (its sizes hold the world's size), from the generator.
func _loaded_sites(sim: PoolSim) -> Array:
	var out := []
	for key in sim.world.loaded_keys():
		for s in sim.world.chunk(key).sites:
			if (s.sizes as Array).has(sim.world.size):
				out.append(s.id)
	out.sort()
	return out


## On every tick of a long swim with twenty chunks or more loaded, the table holds exactly the
## loaded chunks' live sites, and each is filled or queued, never both.
func test_with_twenty_chunks_loaded_every_live_site_is_filled_or_queued() -> void:
	var sim := _endless()
	var seen := {}
	var bad := 0
	var first := ""
	var checked := 0
	for t in 6000:
		sim.step(SimIntent.new(Vector2.from_angle(0.6 + 0.0004 * t)))
		if sim.world.loaded_keys().size() < 20:
			continue
		checked += 1
		var table := sim.world.sites.keys()
		table.sort()
		var problem := ""
		if table != _loaded_sites(sim):
			problem = "table %s, loaded %s" % [table, _loaded_sites(sim)]
		for id in table:
			seen[id] = true
			var occupied := sim.creatures._occupant(id) != null
			var queued := sim.creatures.queue.any(func(e: Dictionary) -> bool: return e.site == id)
			if occupied == queued:
				problem = "site %s filled %s, queued %s" % [id, occupied, queued]
		if not problem.is_empty():
			bad += 1
			if first.is_empty():
				first = "tick %d: %s" % [t, problem]
	check_eq(bad, 0, "every tick (%s)" % first)
	check(checked > 3000, "%d ticks with twenty chunks loaded" % checked)
	check(seen.size() >= 3, "%d sites met" % seen.size())
	check(seen.keys().all(func(id: String) -> bool: return id.begins_with("t_f_")), "no size 2 site is live at size 1")


## At create the loaded sites that pass their checks spawn at once (M1's populate), and the start is
## not news: no creature_spawned is pending.
func test_create_populates_the_loaded_sites_that_pass_their_checks() -> void:
	var sim := _endless(PackedFloat64Array([40.0, 80.0]))
	var site := "t_f_2_2"
	check(sim.world.sites.has(site), "the site is in the table at create")
	var s: Dictionary = sim.world.sites[site]
	check_eq(sim.creatures.blocker_from(s, sim.arena, sim._player_places()), "occupied", "its checks pass but for its own creature")
	var c := sim.creatures._occupant(site)
	check(c != null, "its creature at tick 0")
	if c != null:
		check_eq(c.id, "c_1_%s_0" % site, "count 0")
		check_eq(c.born_tick, 0, "born at create")
	check(not sim.drain_events().any(func(e: Dictionary) -> bool: return e.type == "creature_spawned"), "no spawn event pending")


## G7: after every step of an out-and-back swim, including ticks that only unload, the caps are the
## loaded live sites per role.
func test_caps_equal_the_loaded_live_sites_per_role() -> void:
	var sim := _endless()
	var bad := 0
	var first := ""
	var unload_only := 0
	var nonzero := 0
	for t in 5000:
		sim.step(SimIntent.new(Vector2.from_angle(0.3) if t < 2500 else Vector2.from_angle(0.3 + PI)))
		var events := sim.drain_events()
		var loads := events.filter(func(e: Dictionary) -> bool: return e.type == "chunk_loaded").size()
		var unloads := events.filter(func(e: Dictionary) -> bool: return e.type == "chunk_unloaded").size()
		if unloads > 0 and loads == 0:
			unload_only += 1
		var want := _want_caps(sim)
		if _caps(sim) != want:
			bad += 1
			if first.is_empty():
				first = "tick %d: %s, want %s" % [t, _caps(sim), want]
		for role in want:
			if int(want[role]) > 0:
				nonzero += 1
	check_eq(bad, 0, "caps = the table's sites per role on every tick (%s)" % first)
	check(unload_only > 0, "ticks that only unloaded (%d)" % unload_only)
	check(nonzero > 0, "some caps above zero")


## G7: on a tick that only unloads (loads held off), an empty site's chunk leaves and the caps drop
## with it at once, not at the next load.
func test_a_tick_that_only_unloads_a_site_drops_its_cap_at_once() -> void:
	var sim := _endless()
	var site := "t_f_6_2"
	var c := _reach_site(sim, site, Vector2(150.0, 80.0), Vector2.RIGHT)
	check(c != null, "the site's creature")
	if c == null:
		return
	sim.creatures.remove(c, "test", sim.tick, false)
	var role := str(species.niche_of("rammer").role)
	var before := int(sim.region.niches[role].cap)
	sim.world.caps.loads_per_tick = 0
	check(sim.debug_teleport(sim.motion.position + Vector2(-110.0, 0.0)), "far west of it")
	sim.drain_events()
	sim.step(SimIntent.new())
	var events := sim.drain_events()
	check(events.any(func(e: Dictionary) -> bool: return e.type == "chunk_unloaded" and e.key == Vector2i(6, 2)), "its chunk unloaded")
	check(not events.any(func(e: Dictionary) -> bool: return e.type == "chunk_loaded"), "nothing loaded")
	check(not sim.world.sites.has(site), "the site left the table")
	check_eq(_caps(sim), _want_caps(sim), "the caps follow on the same tick")
	check_eq(int(sim.region.niches[role].cap), before - 1, "one fewer")


## Invariant 11: every niche's count is its live non-debug creatures, and within its cap, through
## loads, unloads, kills and respawns.
func test_invariant_11_holds_after_loads_unloads_and_kills() -> void:
	var sim := _endless()
	var debug_one := sim.debug_spawn_creature("rammer", Vector2(4.0, -12.0), 0.0)
	check(debug_one, "a debug creature, outside the niches")
	var bad := 0
	var first := ""
	var kills := 0
	for t in 4000:
		if t % 400 == 200:
			if sim.debug_kill_nearest_creature():
				kills += 1
		sim.step(SimIntent.new(Vector2.from_angle(t * 0.0015)))
		var live := {}
		for c in sim.creatures.creatures:
			if not c.debug and c.state.is_alive():
				live[c.role] = int(live.get(c.role, 0)) + 1
		for role in sim.region.niches:
			var n: Dictionary = sim.region.niches[role]
			if int(n.count) != int(live.get(role, 0)) or int(n.count) > int(n.cap):
				bad += 1
				if first.is_empty():
					first = "tick %d, %s: count %d, live %d, cap %d" % [t, role, n.count, live.get(role, 0), n.cap]
	check_eq(bad, 0, "count = live, within the cap (%s)" % first)
	check(kills >= 3, "%d kills" % kills)


## A site's creature does not depend on the route: reached from two directions (one with a detour
## past other sites first), its first creature has the same number, id, brain seed and respawn delay.
func test_a_sites_creature_is_the_same_along_two_routes() -> void:
	var site := "t_f_6_2"   # chunk (6, 2): zone at (208, 80), home (211, 80)
	var a := _endless()
	var ca := _reach_site(a, site, Vector2(150.0, 80.0), Vector2.RIGHT)
	var b := _endless()
	check(b.debug_teleport_abs(80.0, -60.0), "a detour")
	for t in 120:
		b.step(SimIntent.new())
	var cb := _reach_site(b, site, Vector2(208.0, 140.0), Vector2.UP)
	check(ca != null and cb != null, "both routes met the site's creature")
	if ca == null or cb == null:
		return
	check_eq(ca.id, "c_1_%s_0" % site, "id c_<size>_<site>_<count>")
	check_eq(cb.id, ca.id, "the same id")
	check_eq(cb.number, ca.number, "the same number")
	check_eq(ca.number, 1 + WorldHash.mix32(WorldHash.str32(site), 0) % (1 << 30), "the hashed number")
	check_eq(cb.brain.rng.seed, ca.brain.rng.seed, "the same brain seed")
	check_eq(ca.brain.rng.seed, WorldHash.hash_ints(PackedInt64Array([SEED, 1, WorldHash.str32(site), 0, WorldHash.str32("brain")])),
		"the hashed brain seed")
	check_eq(b.creatures.respawn_delay_for(cb), a.creatures.respawn_delay_for(ca), "the same respawn delay")
	var niche := species.niche_of("rammer")
	var u := WorldHash.unit(WorldHash.hash_ints(PackedInt64Array([SEED, 1, WorldHash.str32(site), 0, WorldHash.str32("respawn")])))
	check_eq(a.creatures.respawn_delay_for(ca), roundi((float(niche.respawn_s) + (2.0 * u - 1.0) * float(niche.respawn_jitter_s)) * 60.0),
		"the hashed delay")
	check(a.world.site_counts.get(site, 0) == 1 and b.world.site_counts.get(site, 0) == 1, "one spawn each")


## A killed site creature's site waits its hashed delay, then its next creature is count 1.
func test_a_killed_site_creature_respawns_after_its_hashed_delay_as_the_next_count() -> void:
	var sim := _endless()
	var site := "t_f_6_2"
	var c := _reach_site(sim, site, Vector2(150.0, 80.0), Vector2.RIGHT)
	check(c != null, "the site's creature")
	if c == null:
		return
	var delay := sim.creatures.respawn_delay_for(c)
	var at := sim.tick
	sim.creatures.remove(c, "killed", sim.tick, true)
	var entry: Array = sim.creatures.queue.filter(func(e: Dictionary) -> bool: return e.site == site)
	check_eq(entry.size(), 1, "requeued")
	if entry.size() == 1:
		check_eq(int(entry[0].at_tick), at + delay, "at its hashed delay")
	# Back off out of view so the respawn can happen, and wait for it.
	check(sim.debug_teleport(sim.motion.position + Vector2(-30.0, 0.0)), "out of view")
	var next: CreatureField.Creature = null
	for t in delay + 600:
		sim.step(SimIntent.new())
		next = sim.creatures._occupant(site)
		if next != null:
			break
	check(next != null, "it came back")
	if next != null:
		check_eq(next.id, "c_1_%s_1" % site, "as count 1")
		check(sim.tick - 1 >= at + delay, "not before its delay")
		check_eq(sim.world.site_counts[site], 2, "two spawns")


func test_a_site_spawn_count_rises_only_on_a_real_spawn() -> void:
	var sim := _endless()
	var site := "t_f_6_2"
	_reach_site(sim, site, Vector2(150.0, 80.0), Vector2.RIGHT)
	var s: Dictionary = sim.world.sites[site]
	var c := sim.creatures._occupant(site)
	sim.creatures.remove(c, "test", sim.tick, false)
	check_eq(sim.world.site_counts[site], 1, "one spawn so far")
	# The cell beside the home: "near the player", refused, the count unchanged.
	var places: Array[Vector2] = [s.home + Vector2(2.0, 0.0)]
	check_eq(sim.creatures.blocker_from(s, sim.arena, places), "near the player", "refused near the cell")
	check(not sim.creatures._try_site(s, sim.arena, places, sim.tick), "no spawn")
	check_eq(sim.world.site_counts[site], 1, "still one")
	# A full niche refuses too.
	var role := str(species.niche_of("rammer").role)
	sim.region.set_niche(role, int(sim.region.niches[role].count))
	check(sim.creatures.spawn_site(s, sim.tick) == null, "a full niche spawns nothing")
	check_eq(sim.world.site_counts[site], 1, "still one")
	sim.world.recompute_caps(sim)
	var far: Array[Vector2] = [s.home + Vector2(-60.0, 0.0)]
	check(sim.creatures._try_site(s, sim.arena, far, sim.tick), "with room and out of view it spawns")
	check_eq(sim.world.site_counts[site], 2, "two")


## G7: a spawn takes a niche slot, and a full niche spawns nothing.
func test_a_spawn_takes_a_niche_slot_and_a_full_niche_spawns_nothing() -> void:
	var sim := _endless()
	var site := "t_f_6_2"
	_reach_site(sim, site, Vector2(150.0, 80.0), Vector2.RIGHT)
	var s: Dictionary = sim.world.sites[site]
	var role := str(species.niche_of("rammer").role)
	var c := sim.creatures._occupant(site)
	var count := int(sim.region.niches[role].count)
	sim.creatures.remove(c, "test", sim.tick, false)
	check_eq(int(sim.region.niches[role].count), count - 1, "a removal frees a slot")
	check(sim.creatures.spawn_site(s, sim.tick) != null, "a spawn")
	check_eq(int(sim.region.niches[role].count), count, "takes it")
	sim.creatures.remove(sim.creatures._occupant(site), "test", sim.tick, false)
	sim.region.set_niche(role, count - 1)
	check(sim.creatures.spawn_site(s, sim.tick) == null, "at the cap nothing spawns")
	check_eq(int(sim.region.niches[role].count), count - 1, "and the count stays")


## Runtime rule 8: a site whose reach comes within respawn_clear_m of the checkpoint is dormant.
func test_a_moved_checkpoint_makes_a_nearby_site_dormant() -> void:
	var sim := _endless()
	var site := "t_f_6_2"
	_reach_site(sim, site, Vector2(150.0, 80.0), Vector2.RIGHT)
	var s: Dictionary = sim.world.sites[site]
	var far: Array[Vector2] = [s.home + Vector2(-60.0, 0.0)]
	check_eq(sim.creatures.blocker_from(s, sim.arena, far), "occupied", "its creature is home")
	sim.creatures.remove(sim.creatures._occupant(site), "test", sim.tick, false)
	check_eq(sim.creatures.blocker_from(s, sim.arena, far), "", "free")
	# The checkpoint 12 + 12 - r + 0.5 tm from the reach centre: still clear; 1 tm closer: dormant.
	var r: float = species.phenotype("rammer", catalog).radius
	var reach_abs: Dictionary = s.abs.reach
	var clear_d := float(reach_abs.radius) + r + float(species.fairness.respawn_clear_m)
	sim.world.checkpoint_am[0] = float(reach_abs.x) + clear_d + 0.01
	sim.world.checkpoint_am[1] = float(reach_abs.y)
	check_eq(sim.creatures.blocker_from(s, sim.arena, far), "", "just clear of it")
	sim.world.checkpoint_am[0] = float(reach_abs.x) + clear_d - 0.01
	check_eq(sim.creatures.blocker_from(s, sim.arena, far), "dormant", "just inside: dormant")
	check(not sim.creatures._try_site(s, sim.arena, far, sim.tick), "and it does not spawn")


## C-5 and D-12: a site whose creature would spawn asleep (its home at least the wake ring from
## every place) waits with "no room" while the sleepers are at their cap, and one that would spawn
## awake while the awake creatures are at theirs; with room each spawns, asleep or awake as its
## distance says, and a refusal leaves the spawn count alone.
func test_a_spawn_over_the_sleeper_or_awake_cap_waits_with_no_room() -> void:
	var sim := _endless()
	var site := "t_f_6_2"
	_reach_site(sim, site, Vector2(150.0, 80.0), Vector2.RIGHT)
	var s: Dictionary = sim.world.sites[site]
	sim.creatures.remove(sim.creatures._occupant(site), "test", sim.tick, false)
	var count: int = sim.world.site_counts[site]
	var sleepers := sim.creatures.creatures.size() - sim.creatures.awake().size()
	var awake := sim.creatures.awake().size()
	var far: Array[Vector2] = [s.home + Vector2(-60.0, 0.0)]
	var near: Array[Vector2] = [s.home + Vector2(0.0, 37.0)]   # inside the wake ring, out of view (> 35.7)
	check(sim.creatures.spawns_asleep(s, far), "60 tm out it would sleep")
	check(not sim.creatures.spawns_asleep(s, near), "37 tm out it would be awake")
	var both: Array[Vector2] = [far[0], near[0]]
	check(not sim.creatures.spawns_asleep(s, both), "awake when any place is inside the wake ring")
	sim.world.caps.sleepers = sleepers
	check_eq(sim.creatures.blocker_from(s, sim.arena, far), "no room", "the sleepers at their cap")
	check(not sim.creatures._try_site(s, sim.arena, far, sim.tick), "no spawn")
	check_eq(sim.world.site_counts[site], count, "the count unchanged")
	check_eq(sim.creatures.blocker_from(s, sim.arena, near), "", "an awake spawn is not limited by the sleepers")
	sim.world.caps.awake = awake
	check_eq(sim.creatures.blocker_from(s, sim.arena, near), "no room", "the awake ones at their cap")
	sim.world.caps.sleepers = sleepers + 1
	check_eq(sim.creatures.blocker_from(s, sim.arena, far), "", "a sleeper spawn is not limited by the awake")
	sim.drain_events()
	check(sim.creatures._try_site(s, sim.arena, far, sim.tick), "with room it spawns")
	var c := sim.creatures._occupant(site)
	check(c != null and c.asleep, "asleep")
	var spawned := sim.creatures.take_events().filter(func(e: Dictionary) -> bool: return e.type == "creature_spawned")
	check(spawned.size() == 1 and spawned[0].asleep == true, "its event says so")
	check_eq(c.think_slot, -1, "no think slot")
	check(not sim.creatures.awake().has(c), "not among the awake")
	sim.creatures.remove(c, "test", sim.tick, false)
	sim.world.caps.awake = awake + 1
	check(sim.creatures._try_site(s, sim.arena, near, sim.tick), "and awake")
	c = sim.creatures._occupant(site)
	check(c != null and not c.asleep and c.think_slot >= 0, "awake on a slot")


## B-9: after a teleport, every creature that spawns awake has its site's chunks loaded on its spawn
## tick, even those the view set did not hold.
func test_an_awake_spawn_has_its_site_chunks_loaded_on_its_spawn_tick() -> void:
	var sim := FakeWorldGen.endless_sim(SEED, catalog, layout, species, null, PackedFloat64Array(), 1)
	# Measured: from here two awake spawns' east chunks lie outside the view set.
	check(sim.debug_teleport_abs(5015.9, 9.0), "teleported")
	sim.drain_events()
	var awake_spawns := 0
	var missing_before := 0
	var bad := 0
	for t in 120:
		var loaded := sim.world.loaded_keys()
		sim.step(SimIntent.new())
		for e in sim.drain_events():
			if e.type != "creature_spawned" or e.debug or e.asleep:
				continue
			awake_spawns += 1
			var chunks: Array = sim.world.sites[e.site].chunks
			if chunks.any(func(k: Vector2i) -> bool: return not loaded.has(k)):
				missing_before += 1
			for key in chunks:
				if sim.world.chunk(key) == null:
					bad += 1
	check(awake_spawns >= 3, "%d awake spawns" % awake_spawns)
	check(missing_before >= 1, "%d of them had a site chunk missing when the tick began" % missing_before)
	check_eq(bad, 0, "every awake spawn's site chunks loaded")


## C-14: debug creatures take numbers from 2^30 up and keep "c_" + number ids, so they sort after
## every site creature and never meet a site creature's id.
func test_debug_creatures_sort_after_site_creatures_and_keep_c_ids() -> void:
	var sim := _endless()
	_reach_site(sim, "t_f_6_2", Vector2(150.0, 80.0), Vector2.RIGHT)
	check(sim.debug_spawn_creature("rammer", sim.motion.position + Vector2(8.0, 0.0), 0.0), "a debug creature")
	var debug_c := sim.creatures.creatures[-1]
	check(debug_c.debug, "last in the list")
	check(debug_c.number >= CreatureField.DEBUG_NUMBER_BASE, "numbered from 2^30 (%d)" % debug_c.number)
	check_eq(debug_c.id, "c_%d" % debug_c.number, "a c_ id")
	var site_n := 0
	for c in sim.creatures.creatures:
		if not c.debug:
			site_n += 1
			check(c.number <= CreatureField.SITE_NUMBERS, "site numbers within [1, 2^30]")
			check(c.id.begins_with("c_1_t_f_"), "site ids name the size and the site (%s)" % c.id)
	check(site_n >= 1, "site creatures (%d)" % site_n)
	var sorted := sim.creatures.creatures.duplicate()
	sorted.sort_custom(func(p: CreatureField.Creature, q: CreatureField.Creature) -> bool:
		return p.number < q.number or (p.number == q.number and p.id < q.id))
	check(sorted == sim.creatures.creatures, "the list stays sorted (number, id)")


## An awake site creature holds its site's reach chunks (as the generator lists them), not its
## leash disc's.
func test_an_awake_site_creature_holds_its_sites_chunks() -> void:
	var sim := _endless()
	var site := "t_f_6_2"
	var c := _reach_site(sim, site, Vector2(150.0, 80.0), Vector2.RIGHT)
	check(c != null and not c.asleep, "the site's creature, awake")
	if c == null:
		return
	sim.world.sites[site].chunks = [Vector2i(6, 2), Vector2i(9, 5)] as Array[Vector2i]
	var held := sim.world._held_keys(sim)
	check(held.has(Vector2i(9, 5)), "a listed chunk its leash disc does not reach is held")
	check(not sim.world.disc_keys(CreatureBrain.leash_disc(c.brain)).has(Vector2i(9, 5)), "(its leash disc is far from it)")


## A site's queue entry and record leave with its home chunk (its creature had died), and come back
## with it.
func test_an_unloaded_site_leaves_the_table_and_the_queue() -> void:
	var sim := _endless()
	var site := "t_f_6_2"
	var c := _reach_site(sim, site, Vector2(150.0, 80.0), Vector2.RIGHT)
	sim.creatures.remove(c, "killed", sim.tick, true)
	check(sim.creatures.queue.any(func(e: Dictionary) -> bool: return e.site == site), "queued")
	check(sim.debug_teleport(sim.motion.position + Vector2(-140.0, 0.0)), "far west")
	for t in 3:
		sim.step(SimIntent.new())
	check(sim.world.chunk(Vector2i(6, 2)) == null, "its chunk unloaded")
	check(not sim.world.sites.has(site), "the site left the table")
	check(not sim.creatures.queue.any(func(e: Dictionary) -> bool: return e.site == site), "and the queue")
	check_eq(sim.world.site_counts.get(site, 0), 1, "its count stays")
	check_eq(_caps(sim), _want_caps(sim), "the caps follow")


## Swims to `start` (absolute) by a debug teleport and on along `dir` until the site's creature exists
## and is awake; that creature, or null after 1,200 ticks.
func _reach_site(sim: PoolSim, site: String, start: Vector2, dir: Vector2) -> CreatureField.Creature:
	check(sim.debug_teleport(sim.world.local_of_abs(start.x, start.y)), "the cell at %s" % start)
	for t in 1200:
		var c := sim.creatures._occupant(site)
		if c != null and not c.asleep:
			return c
		sim.step(SimIntent.new(dir))
	return sim.creatures._occupant(site)


# --- S2 T2.2 (BP-10): the niches per size ---

## A site of its own, `species` homed at local `home` (in a loaded chunk), entered into the table at
## the world's size with the caps recomputed.
func _own_site(sim: PoolSim, id: String, p_species: String, home: Vector2) -> Dictionary:
	var a := sim.world.abs_of_local(home)
	var key := sim.world.chunk_of_local(home)
	check(sim.world.chunk(key) != null, "the home chunk of %s is loaded" % id)
	var s := {"id": id, "species": p_species, "x": a[0], "y": a[1], "heading": 0.0,
		"territory": {"x": a[0], "y": a[1], "radius": 3.0}, "reach": {"x": a[0], "y": a[1], "radius": 6.0},
		"chunks": [key] as Array[Vector2i], "sizes": [sim.world.size] as Array[int], "tile": Vector2i.ZERO}
	sim.world.sites[id] = sim.world._site_record(s, key)
	sim.world.recompute_caps(sim)
	return sim.world.sites[id]


## With the size-2 species in the catalog, a size-1 endless world is S1's: the same roles (a Lurker
## or elder rammer role at cap 0 would add keys to every size-1 snapshot) and the same state.
func test_at_size_1_the_size_2_species_add_no_role_and_change_nothing() -> void:
	var a := _endless()
	var b := FakeWorldGen.endless_sim(SEED, catalog, layout, FakeWorldGen.s2_species())
	for t in 900:
		a.step(SimIntent.new(Vector2.from_angle(0.3)))
		b.step(SimIntent.new(Vector2.from_angle(0.3)))
	check_eq(b.snapshot().niches, a.snapshot().niches, "the niches")
	check_eq(b.region.niches.keys(), a.region.niches.keys(), "the roles, in order")
	check(not b.region.niches.has("lurker") and not b.region.niches.has("elder_rammer"), "no size-2 role")
	check_eq(b.state_hash(), a.state_hash(), "the same state")


## At size 2 the size-2 species' roles join, the Lurker's cap is its live sites in the table, its
## creature takes the record at size 2, and a drop back to size 1 keeps the role at cap 0.
func test_at_size_2_the_lurker_cap_is_its_live_sites_and_a_drop_keeps_its_role_at_0() -> void:
	var s2 := FakeWorldGen.s2_species()
	var sim := FakeWorldGen.endless_sim(SEED, catalog, layout, s2)
	for t in 40:
		sim.step(SimIntent.new())
	sim.drain_events()
	var spot := sim._clear_point_near(sim.motion.position + Vector2(0.0, -9.0), 1.0)
	check(not sim.debug_spawn_creature("lurker", spot, 0.0), "no dev Lurker at size 1 (it has no record)")
	sim.world.size = 2
	sim.creatures.set_size(2)
	sim.world.recompute_caps(sim)
	check(sim.debug_spawn_creature("lurker", spot, 0.0), "a dev Lurker at size 2")
	check_eq(int(sim.region.niches.lurker.cap), 0, "the Lurker role joins at size 2, at 0 with no site")
	check_eq(int(sim.region.niches.elder_rammer.cap), 0, "and the elder rammer's")
	var at := sim.motion.position
	var ids := ["x_lurk_a", "x_lurk_b", "x_lurk_c"]
	for i in ids.size():
		_own_site(sim, ids[i], "lurker", at + Vector2(-20.0 + 6.0 * i, 12.0))
	var live := 0
	for id in sim.world.sites:
		if str(sim.world.sites[id].species) == "lurker" and s2.live_at("lurker", sim.world.size):
			live += 1
	check_eq(live, 3, "three live Lurker sites")
	check_eq(int(sim.region.niches.lurker.cap), live, "the Lurker cap is its live sites")
	var c := sim.creatures.spawn_site(sim.world.sites["x_lurk_a"], sim.tick, true)
	check(c != null, "a Lurker spawns at its site")
	if c != null:
		check_eq(c.phenotype.radius, s2.at_size("lurker", 2, catalog).phenotype.radius, "with its size-2 body")
	var r_site := _own_site(sim, "x_ram", "rammer", at + Vector2(20.0, 12.0))
	var r := sim.creatures.spawn_site(r_site, sim.tick, true)
	check(r != null and r.actor.reach_scale == 0.625, "a rammer at size 2 reaches at q 0.625")
	if r != null:
		check_eq(r.phenotype.radius, s2.at_size("rammer", 2, catalog).phenotype.radius, "with its scaled body")
	for id in ids:
		sim.world.sites.erase(id)
	sim.world.size = 1
	sim.creatures.set_size(1)
	sim.world.recompute_caps(sim)
	check(sim.region.niches.has("lurker"), "back at size 1 the Lurker role stays")
	check_eq(int(sim.region.niches.lurker.cap), 0, "at cap 0")


## Creatures come only from streamed sites in the endless world (BP-10): over a swim every
## creature_spawned names a site in the table on its tick, none is a debug spawn, and every creature
## in the field on every tick holds a site of the table.
func test_every_endless_spawn_comes_from_a_site_in_the_table() -> void:
	var sim := FakeWorldGen.endless_sim(SEED, catalog, layout, FakeWorldGen.s2_species(), null, PackedFloat64Array(), 2)
	var spawns := 0
	var met := {}
	var bad := []
	for t in 2400:
		sim.step(SimIntent.new(Vector2.from_angle(0.6)))
		for e in sim.drain_events():
			if e.type != "creature_spawned":
				continue
			spawns += 1
			if str(e.site).is_empty() or bool(e.debug) or not sim.world.sites.has(str(e.site)):
				bad.append("tick %d: %s" % [t, e])
		for c in sim.creatures.creatures:
			met[c.id] = true
			if c.debug or c.site_id.is_empty() or sim.creatures._occupant(c.site_id) != c:
				bad.append("tick %d: %s at site '%s'" % [t, c.id, c.site_id])
	check(bad.is_empty(), "every creature from a site (%s)" % [bad.slice(0, 3)])
	check(spawns >= 2, "%d spawns on the way" % spawns)
	check(met.size() >= 6, "%d creatures met" % met.size())
