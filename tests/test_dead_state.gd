extends TestCase
## The dead state and the respawn (S1 T2.7, spine 3.11 step 0, D-10, D-11, G9), on the real WorldGen
## with the fixture world. Each case starts at home, dies by debug_hurt_player, steps through a
## notice of NOTICE ticks, calls respawn_player and steps AFTER more:
##
##   near  swims 40 tm south of home: the checkpoint's view set is still loaded, so the cell comes
##         back there without a teleport;
##   150   debug_teleport_abs(150, 9) first: the respawn teleports home behind the camera cut;
##   5 km  debug_teleport_abs(5000, 9) first: the same, 5 km out.
##
## Each case runs once per suite and is checked tick by tick with FuzzInvariants (1 to 13 and 16)
## from the dev teleport, or the end of the swim, to the end: the respawn tick (and a dev teleport's)
## is the camera cut. Plankton appearing in view is watched through the notice and the WATCHED_AFTER
## ticks after the respawn.

const FakeWorldGen := preload("res://tests/fakes/fake_world_gen.gd")
const FuzzInvariants := preload("res://tests/fuzz_invariants.gd")
const SEED := 4309
const NOTICE := 120
const AFTER := 120
const WATCHED_AFTER := 60              ## ticks after the respawn tick that nothing may appear in view
const SOUTH := 40.0                    ## tm: the near case's swim
const SETTLE := 60                     ## ticks after a dev teleport, before the death
## The chunk the near case keeps by hysteresis: 58.5 tm from the body, inside the 72 tm unload ring.
const HELD_CHUNK := Vector2i(1, -1)

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog
var _runs := {}   ## case -> its record, run once per suite


func before_each() -> void:
	if catalog == null:
		catalog = PartCatalog.load_from()
		layout = PoolLayout.load_from()
		species = SpeciesCatalog.load_from()


func test_a_near_death_respawns_at_the_checkpoint_without_a_teleport() -> void:
	var r := _run("near")
	check_eq(r.respawned.get("teleport"), false, "respawned.teleport")
	check_eq(r.respawn_types.count("rebased"), 0, "no rebased on the respawn tick")
	var types: PackedStringArray = r.respawn_types
	var at := types.find("respawned")
	check(at >= 0 and types.slice(0, at).count("chunk_unloaded") + types.slice(0, at).count("chunk_loaded") == 0,
		"no chunk event before respawned (%s)" % types)
	check(types.count("chunk_loaded") <= int(r.loads_per_tick), "only step 4's loads (%d)" % types.count("chunk_loaded"))
	check(r.held_at_death, "chunk %s loaded when the cell died" % HELD_CHUNK)
	check(r.held_through, "and still loaded at the respawn (hysteresis)")
	check(r.cell_after.distance_to(r.cp_after) < 0.01, "the cell back at its checkpoint (%s, %s)" % [r.cell_after, r.cp_after])
	check_eq(r.origin_after, r.origin_before, "the origin did not move")
	check(r.body_at_death.distance_to(r.cp_at_death) >= SOUTH - 0.5, "the body died %.1f tm from the checkpoint" % r.body_at_death.distance_to(r.cp_at_death))


func test_a_death_150_tm_out_teleports_home_behind_the_cut() -> void:
	var r := _run("150")
	check_eq(r.respawned.get("teleport"), true, "respawned.teleport")
	var types: PackedStringArray = r.respawn_types
	var rebased := types.find("rebased")
	check(rebased >= 0, "a rebased on the respawn tick")
	check(types.count("chunk_unloaded") > 0, "chunks unloaded (%d)" % types.count("chunk_unloaded"))
	check(types.rfind("chunk_unloaded", rebased) == types.rfind("chunk_unloaded"), "every chunk_unloaded precedes the rebased")
	check(types.find("chunk_loaded") > rebased, "the view set loads after it")
	check(types.find("respawned") > types.rfind("chunk_loaded", types.find("respawned")), "then the cell comes back")
	check_eq(r.origin_after, r.cp_am, "the origin is the checkpoint exactly")
	check(r.cell_after.length() < 2.0, "the cell at the clear point by the origin (%s)" % r.cell_after)
	check(r.food_zones >= 2, "food zones round home (%d)" % r.food_zones)
	check_eq(r.unfilled, [], "every food zone full at once (C-9)")


func test_a_death_5_km_out_teleports_home_and_keeps_locals_under_256() -> void:
	var r := _run("5km")
	check_eq(r.respawned.get("teleport"), true, "respawned.teleport")
	check_eq(r.origin_after, r.cp_am, "the origin is the checkpoint exactly")
	check(not r.fuzz.bad.has(13), "invariant 13 on every tick: %s" % r.fuzz.report())
	check(r.max_local < FuzzInvariants.LOCAL_BOUND, "the cell under 256 tm on every tick (%.1f)" % r.max_local)


## Rule C2 in both paths. Near: a home rammer moved within 12 tm of the checkpoint goes home. A
## teleport removes every creature first, and the new view set's sites spawn out of view.
func test_creatures_within_12_tm_of_the_checkpoint_are_sent_home() -> void:
	var clear := float(species.fairness.respawn_clear_m)
	for name in ["near", "150", "5km"]:
		var r := _run(name)
		check_eq(r.too_close, [], "%s: nothing within %.0f tm of the cell after the respawn tick" % [name, clear])
	var near := _run("near")
	check(not near.moved_id.is_empty(), "near: a creature put by the checkpoint")
	check(near.respawned.relocated.has(near.moved_id), "near: %s sent home (%s)" % [near.moved_id, near.respawned.relocated])
	check(near.moved_from_home < 0.5, "near: %s at its home after the tick (%.3f tm)" % [near.moved_id, near.moved_from_home])


## G9: while the cell is dead, the checkpoint is a place, so a sleeper near it wakes. In the near case
## the home rammers sleep while the cell is 71 tm from them and 31 tm from the checkpoint.
func test_no_sleeper_lies_within_40_tm_of_the_checkpoint_from_the_second_dead_tick() -> void:
	for name in ["near", "150", "5km"]:
		var r := _run(name)
		check_eq(r.dead_sleeper_bad, 0, "%s: no sleeper within 40 tm or in view of the checkpoint (%s)" % [name, r.dead_sleeper_first])
		check_eq(r.dead_unload_bad, 0, "%s: no chunk unloads while dead but one a creature let go (%s)" % [name, r.dead_unload_first])
	var near := _run("near")
	check(near.slept_by_checkpoint.size() >= 2, "near: sleepers by the checkpoint when the cell died (%s)" % [near.slept_by_checkpoint])
	for id in near.slept_by_checkpoint:
		check(near.woke_while_dead.has(id), "near: %s woke while the cell was dead" % id)


func test_nothing_appears_or_vanishes_in_the_footprint_during_the_notice_and_60_ticks_after() -> void:
	for name in ["near", "150", "5km"]:
		var r := _run(name)
		var fz: FuzzInvariants = r.fuzz
		check_eq(fz.report(), "", "%s: every invariant on every tick" % name)
		check(int(fz.counts.checked) > 0, "%s: things measured (%s)" % [name, fz.counts])
		check_eq(int(fz.counts.cuts), 1 if name == "near" else 2, "%s: the cuts are the respawn and a dev teleport" % name)
		check(r.view_zones >= 1, "%s: food zones in the new view (%d)" % [name, r.view_zones])
		check_eq(r.view_unfilled, [], "%s: each full from the cut on (D-11)" % name)
		check_eq(r.food_appeared, 0, "%s: no plankton appears in view (%s)" % [name, r.food_first])
	var near := _run("near")
	# A site in view of the checkpoint, queued when the cell died, stays shut while it is dead: the
	# checkpoint is a place too (G8: blocker_from measured from the body alone spawns it there).
	check(not str(near.cp_site).is_empty(), "near: a site queued in view of the checkpoint")
	check_eq(near.get("cp_site_blocker", ""), "in view", "near: and still shut at the end of the notice")
	check_eq(near.get("cp_site_spawned", -1), 0, "near: it never spawned while the cell was dead")
	check(int(near.fuzz.counts.wakes) >= 2, "near: wakes measured (%s)" % near.fuzz.counts)
	check(int(near.fuzz.counts.loads) >= 1, "near: loads measured (%s)" % near.fuzz.counts)


## C-8: dead, and with the respawn pending, the absolute position is the checkpoint's exactly.
func test_the_checkpoint_absolute_position_is_exact_while_dead() -> void:
	for name in ["near", "150", "5km"]:
		var r := _run(name)
		check(r.abs_checked >= NOTICE, "%s: %d dead ticks checked" % [name, r.abs_checked])
		check_eq(r.abs_bad, 0, "%s: absolute_position_am() == checkpoint_am while dead (%s)" % [name, r.abs_first])
		check(r.pending_abs_ok, "%s: and while the respawn is pending" % name)


## C-10: the teleport drops every carrion item before the origin moves.
func test_a_teleport_drops_all_carrion() -> void:
	for name in ["150", "5km"]:
		var r := _run(name)
		check(r.carrion_before.size() >= 1, "%s: carrion by the body before the respawn (%d)" % [name, r.carrion_before.size()])
		for id in r.carrion_before:
			check(not r.carrion_after.has(id), "%s: carrion %s gone" % [name, id])


# --- the runs ---

func _run(name: String) -> Dictionary:
	if not _runs.has(name):
		_runs[name] = _death(name)
	return _runs[name]


## One case: home, then out (a swim or a dev teleport), the death, the notice, the respawn, AFTER
## ticks, every tick checked by FuzzInvariants. Returns what the tests read.
func _death(name: String) -> Dictionary:
	var sim := FakeWorldGen.real_sim(SEED, catalog, layout, species)
	var w := sim.world
	var r := {"cp_am": PackedFloat64Array([w.checkpoint_am[0], w.checkpoint_am[1]]), "max_local": 0.0, "food_appeared": 0,
		"food_first": ""}
	var fuzz := FuzzInvariants.new(species, layout)
	sim.drain_events()
	var was := fuzz.before(sim)
	match name:
		"near":
			var guard := 0
			while sim.motion.position.y < SOUTH and guard < 3000:   # unchecked: the swim is the endless fuzz's
				sim.step(SimIntent.new(Vector2(0.0, 1.0)))
				guard += 1
			sim.drain_events()
		"150":
			sim.debug_teleport_abs(150.0, 9.0)
		"5km":
			sim.debug_teleport_abs(5000.0, 9.0)
	for i in SETTLE:
		# A dev teleport's events reach the first settle tick's check, as its cut.
		_tick(sim, Vector2.ZERO, fuzz, "%s settle tick %d" % [name, i], r, was if i == 0 and name != "near" else {})
	if name != "near":
		for i in 3:
			sim.debug_spawn_carrion_ahead()
			sim.motion.heading += 2.0
		sim.drain_events()
	r["origin_before"] = PackedFloat64Array([w.origin_x_am, w.origin_y_am])
	r["held_at_death"] = w.chunk(HELD_CHUNK) != null
	r["body_at_death"] = sim.motion.position
	r["cp_at_death"] = w.checkpoint_local()
	var wake := float(w.rings.wake)
	var slept: Array[String] = []
	for c in sim.creatures.creatures:
		if c.asleep and c.motion.position.distance_to(w.checkpoint_local()) < wake:
			slept.append(c.id)
	r["slept_by_checkpoint"] = slept
	check(sim.debug_hurt_player(1.0e9), "%s: the cell is hurt" % name)
	check(sim.dead, "%s: and dies" % name)
	if name == "near":
		r["cp_site"] = _queue_site_in_view_of_the_checkpoint(sim)
	sim.drain_events()
	var woke := {}
	var dead_sleeper := [0, ""]
	var dead_unload := [0, ""]
	var abs_bad := [0, ""]
	var abs_checked := 0
	var held_through := true
	for i in NOTICE:
		var held := w._held_keys(sim)
		var where := "%s notice tick %d" % [name, i]
		var events := _tick(sim, Vector2.ZERO, fuzz, where, r, {}, true)
		held_through = held_through and w.chunk(HELD_CHUNK) != null
		for e in events:
			if e.type == "creature_woke":
				woke[e.id] = true
			if e.type == "chunk_unloaded" and i >= 1 and not held.has(e.key):
				dead_unload[0] += 1
				if dead_unload[1].is_empty():
					dead_unload[1] = "%s: %s was not held" % [where, e.key]
		var cp := w.checkpoint_local()
		for c in sim.creatures.creatures:
			if c.asleep and i >= 1 and (c.motion.position.distance_to(cp) < wake or _in_view(cp, c.motion.position, c.phenotype.radius)):
				dead_sleeper[0] += 1
				if dead_sleeper[1].is_empty():
					dead_sleeper[1] = "%s: %s %.1f tm from the checkpoint" % [where, c.id, c.motion.position.distance_to(cp)]
		abs_checked += 1
		if sim.absolute_position_am() != r.cp_am:
			abs_bad[0] += 1
			if abs_bad[1].is_empty():
				abs_bad[1] = "%s: %s" % [where, sim.absolute_position_am()]
	r["woke_while_dead"] = woke
	if name == "near" and not str(r.cp_site).is_empty():
		var site: Dictionary = w.sites[r.cp_site]
		r["cp_site_blocker"] = sim.creatures.blocker_from(site, sim.arena, sim._player_places())
		r["cp_site_spawned"] = int(w.site_counts.get(r.cp_site, 0))
	# Near: an awake rammer put by the checkpoint, a creature the cell would find at its door.
	r["moved_id"] = ""
	if name == "near":
		var cp := w.checkpoint_local()
		for c in sim.creatures.creatures:
			if c.asleep or c.brain == null or c.species_id != "rammer":
				continue
			for at: Vector2 in [cp + Vector2(0.0, -8.0), cp + Vector2(8.0, 0.0), cp + Vector2(-8.0, 0.0)]:
				if sim.arena.is_clear(at, c.phenotype.radius):
					c.motion.place(at, c.motion.heading)
					c.actor.position = at
					r.moved_id = c.id
					r["moved_home"] = c.brain.home
					break
			if not r.moved_id.is_empty():
				break
	var carrion_before := {}
	for item in sim.carrion.items:
		carrion_before[item.id] = true
	r["carrion_before"] = carrion_before
	sim.respawn_player()
	check(sim.respawn_pending, "%s: the respawn waits for the next step" % name)
	r["pending_abs_ok"] = sim.dead and sim.absolute_position_am() == r.cp_am
	# The respawn tick: the camera cut.
	var events := _tick(sim, Vector2.ZERO, fuzz, "%s respawn tick" % name, r)
	var types := PackedStringArray()
	r["respawned"] = {}
	for e in events:
		types.append(e.type)
		if e.type == "respawned":
			r.respawned = e
	r["respawn_types"] = types
	r["origin_after"] = PackedFloat64Array([w.origin_x_am, w.origin_y_am])
	r["cell_after"] = sim.motion.position
	r["cp_after"] = w.checkpoint_local()
	r["loads_per_tick"] = int(w.caps.loads_per_tick)
	r["held_through"] = held_through and w.chunk(HELD_CHUNK) != null
	var too_close: Array[String] = []
	for c in sim.creatures.creatures:
		if c.motion.position.distance_to(sim.motion.position) - c.phenotype.radius < float(species.fairness.respawn_clear_m):
			too_close.append(c.id)
	r["too_close"] = too_close
	r["moved_from_home"] = INF
	if not r.moved_id.is_empty():
		var moved := sim.creatures.find(r.moved_id)
		if moved != null:
			r.moved_from_home = moved.motion.position.distance_to(r.moved_home)
	var carrion_after := {}
	for item in sim.carrion.items:
		carrion_after[item.id] = true
	r["carrion_after"] = carrion_after
	var unfilled: Array[String] = []
	for id in sim.plankton.active_zones:
		if sim.plankton.count_in(id) != sim.plankton.target_count(sim.region.zone(id)):
			unfilled.append(id)
	r["food_zones"] = sim.plankton.active_zones.size()
	r["unfilled"] = unfilled
	# D-11: every zone in the new view shows its plankton from the cut on.
	var view_unfilled: Array[String] = []
	var touching := 0
	for z in sim.region.zones:
		if _in_view(sim.motion.position, z.center, float(z.radius)):
			touching += 1
			if sim.plankton.count_in(z.id) < sim.plankton.target_count(z):
				view_unfilled.append(z.id)
	r["view_zones"] = touching
	r["view_unfilled"] = view_unfilled
	for i in AFTER:
		_tick(sim, Vector2.ZERO, fuzz, "%s tick %d after the respawn" % [name, i + 1], r, {}, i < WATCHED_AFTER)
	r["fuzz"] = fuzz
	r["dead_sleeper_bad"] = dead_sleeper[0]
	r["dead_sleeper_first"] = dead_sleeper[1]
	r["dead_unload_bad"] = dead_unload[0]
	r["dead_unload_first"] = dead_unload[1]
	r["abs_bad"] = abs_bad[0]
	r["abs_first"] = abs_bad[1]
	r["abs_checked"] = abs_checked
	var c: Dictionary = fuzz.counts
	print("test-dead-state: %s: teleport %s, relocated %s, %d woke while dead; checked %d, %d spawns, %d sleeps, %d wakes, %d loads, %d unloads, %d cuts" % [
		name, r.respawned.get("teleport"), r.respawned.get("relocated"), woke.size(), c.checked, c.spawns, c.sleeps, c.wakes,
		c.loads, c.unloads, c.cuts])
	return r


## A rammer site of the test's own, homed in view of the checkpoint (over 20 tm from it, its reach
## clear of rule 8's ring) on a loaded chunk, entered into the site table and queued now. Returns
## its id, "" when no such clear home was found.
func _queue_site_in_view_of_the_checkpoint(sim: PoolSim) -> String:
	var w := sim.world
	var cp := w.checkpoint_local()
	for at: Vector2 in [cp + Vector2(-20.0, -10.0), cp + Vector2(20.0, -10.0), cp + Vector2(-22.0, -6.0), cp + Vector2(22.0, -6.0)]:
		var key := w.chunk_of_local(at)
		if w.chunk(key) == null or not sim.arena.is_clear(at, 1.5) or not _in_view(cp, at, 0.6) or at.distance_to(cp) < 21.0:
			continue
		var a := w.abs_of_local(at)
		var x_tm := a[0] / w._tm_to_am
		var y_tm := a[1] / w._tm_to_am
		var s := {"id": "x_cp", "species": "rammer", "x": x_tm, "y": y_tm, "heading": 0.0,
			"territory": {"x": x_tm, "y": y_tm, "radius": 3.0}, "reach": {"x": x_tm, "y": y_tm, "radius": 6.0},
			"chunks": [key] as Array[Vector2i], "sizes": [1] as Array[int], "tile": Vector2i.ZERO}
		w.sites["x_cp"] = w._site_record(s, key)
		w.recompute_caps(sim)
		sim.creatures._enqueue("x_cp", "rammer", sim.tick)
		return "x_cp"
	return ""


## One step with `move`, checked by `fuzz` (`was`, when given, is what it took before something done
## between the steps). Returns the step's events.
## With `watch`, a plankton item that appears in view (a zone regrowing where the player looks)
## counts in r.food_appeared.
func _tick(sim: PoolSim, move: Vector2, fuzz: FuzzInvariants, where: String, r: Dictionary, was := {}, watch := false) -> Array[Dictionary]:
	if was.is_empty():
		was = fuzz.before(sim)
	var t := sim.tick
	sim.step(SimIntent.new(move))
	var events := sim.drain_events()
	fuzz.after(sim, events, t, where, was)
	r.max_local = maxf(float(r.max_local), sim.motion.position.length())
	if watch:
		for item in sim.plankton.items:
			if not was.plankton.has(item.id) and _in_view(sim.motion.position, item.position, sim.plankton.item_radius):
				r.food_appeared += 1
				if str(r.food_first).is_empty():
					r.food_first = "%s: %s of zone %s" % [where, item.id, item.zone]
	return events


## Whether a body at `p` of radius `r` is in the widest view of `place` grown by the spawn margin.
func _in_view(place: Vector2, p: Vector2, r: float) -> bool:
	var margin := float(layout.camera.look_ahead_max) + float(species.fairness.spawn_view_margin_m) + r
	return ViewFootprint.contains(place, p, layout.camera, float(layout.camera.zoom_max), float(species.fairness.spawn_view_aspect), margin)
