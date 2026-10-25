extends TestCase
## Morsel sites at run time (S3 T2.4; docs/s3: s3-sim 3.7, D-98, D-129, BP3-3): on FakeWorldGen at
## size 4 each site chunk holds a morsel site "m_f_<cx>_<cy>" at its rammer site's home (D-145). A
## loaded site spawns its item on the pass (every MORSEL_PASS_TICKS) only in the food ring, out of
## the zoom-max view and spawn_safe_m from the cell (S3G17); the item is a "morsel_site" carrion with
## the site's species, radius and energy; eaten, dropped or rotted, the site is due again after its
## species' respawn time; an unload expires it ("unloaded"). The food total counts the claims, so at
## the food cap no item spawns (S3G17b), and the claims stay exact across unloads and size changes
## (BP3-3).

const FakeWorldGen := preload("res://tests/fakes/fake_world_gen.gd")
const B1_WORLD := "res://tests/fixtures/world/world_b1_min.json"
const SITE := "m_f_2_2"
const SITE_TM := Vector2(83.0, 80.0)      ## chunk (2, 2)'s centre + (ZONE_R - 2, 0), tm at size 4
const OUT_OF_VIEW := Vector2(83.0, 50.0)  ## 30 tm north of it: in the ring, out of view, past 20 tm

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog


func before_each() -> void:
	if species != null:
		return
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()


## An endless sim at size 4 with its cell at `at` (tm at size 4), a site per `period` x `period`
## chunks, the events drained.
func _sim(at: Vector2, period := 4, food_cap := -1) -> PoolSim:
	var content := FakeWorldGen.fixture_content(B1_WORLD)
	if food_cap >= 0:
		content.config.caps["food_items"] = food_cap
	var sim := FakeWorldGen.endless_sim(7, catalog, layout, species, content, PackedFloat64Array(), period, true)
	check(sim.debug_set_size(4), "size 4")
	_place(sim, at)
	return sim


func _place(sim: PoolSim, at: Vector2) -> void:
	var k := WorldConfig.tm_to_am(4)
	check(sim.debug_teleport_abs(at.x * k, at.y * k), "the cell at %s tm" % at)
	sim.motion.velocity = Vector2.ZERO
	sim.drain_events()


## Moves the cell to `at` (tm at size 4) inside the loaded world: no chunk unloads or loads with it.
func _move(sim: PoolSim, at: Vector2) -> void:
	check(sim.debug_teleport(sim.world.local_of_tm(at.x, at.y)), "the cell moved to %s tm" % at)
	sim.motion.velocity = Vector2.ZERO
	sim.drain_events()


## Steps `ticks` times with no intent; the events.
func _run(sim: PoolSim, ticks: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in ticks:
		sim.step(SimIntent.new())
		out.append_array(sim.drain_events())
	return out


static func _of(events: Array[Dictionary], type: String, source := "") -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool:
		return e.type == type and (source.is_empty() or e.get("source", "") == source))


## Steps until the site's item spawns (at most `most` ticks); the item, or {}.
func _spawned(sim: PoolSim, site := SITE, most := 61) -> Dictionary:
	for i in most:
		for e in _of(_run(sim, 1), "carrion_spawned", "morsel_site"):
			if e.site == site:
				return sim.carrion.find(e.food_id)
	return {}


func _in_view(sim: PoolSim, p: Vector2, r: float) -> bool:
	var w := sim.world
	var quad := ViewFootprint.corners(sim.motion.position, w.camera, float(w.camera.zoom_max), w.view_aspect)
	return not w._out_of_view(quad, WorldStream._box(quad), p, r)


## S3G17: a due site in the ring, out of view and 20 tm from the cell spawns its item on the pass:
## a morsel_site carrion with the site's species, radius and energy at its home; the entry holds it
## and the snapshot lists the entry.
func test_a_due_site_spawns_its_item_on_the_pass() -> void:
	var sim := _sim(OUT_OF_VIEW)
	var w := sim.world
	check(w.morsel_sites.has(SITE), "the loaded site has an entry")
	check_eq(w.morsel_sites[SITE].food_id, "", "with no item yet")
	var p := w.local_of_tm(SITE_TM.x, SITE_TM.y)
	check(not _in_view(sim, p, FakeWorldGen.MORSEL_R), "the home out of view")
	var item := _spawned(sim, SITE, WorldStream.MORSEL_PASS_TICKS + 1)
	check(not item.is_empty(), "the item spawned on the pass")
	if item.is_empty():
		return
	check_eq(posmod(sim.tick - 1, WorldStream.MORSEL_PASS_TICKS), 0, "on a pass tick")
	check_eq([item.source, item.species, item.site], ["morsel_site", "rammer", SITE], "its source and keys")
	check_eq([item.radius, item.energy], [FakeWorldGen.MORSEL_R, FakeWorldGen.MORSEL_ENERGY], "the site's radius and energy")
	check(Vector2(item.position).distance_to(p) < 1e-4, "at the site's home")
	check_eq(item.lifetime, 120.0, "rotting after morsel_rot_s")
	check_eq(w.morsel_sites[SITE].food_id, item.id, "the entry holds it")
	check_eq(w.morsel_claims(), 1, "one claim")
	var snap: Dictionary = sim.snapshot().world
	check_eq(snap.get("morsel_sites", {}).get(SITE, {}), {"food_id": item.id, "due_tick": w.morsel_sites[SITE].due_tick},
		"the snapshot lists the entry")
	check(_spawned(sim, SITE, WorldStream.MORSEL_PASS_TICKS * 2).is_empty(), "and no second item while it lives")


## S3G17's mutation guard: no item spawns while the home is in view, within 20 tm of the cell, or
## beyond the food ring.
func test_no_item_spawns_in_view_near_the_cell_or_beyond_the_ring() -> void:
	# The zoom-max view reaches 14 tm north of the cell, 28 tm to each side there, and 8 tm south.
	var places := {"in view": SITE_TM + Vector2(-22.0, 8.0), "near the cell": SITE_TM + Vector2(0.0, -15.0),
		"beyond the ring": SITE_TM + Vector2(0.0, -54.0)}
	for what in places:
		var sim := _sim(OUT_OF_VIEW)
		_move(sim, places[what])
		var w := sim.world
		var p := w.local_of_tm(SITE_TM.x, SITE_TM.y)
		check(w.morsel_sites.has(SITE), "%s: the site loaded" % what)
		if what == "in view":
			check(_in_view(sim, p, FakeWorldGen.MORSEL_R), "in view: the home is in view")
			check(p.distance_to(sim.motion.position) >= 20.0, "in view: 20 tm away")
		check(_spawned(sim, SITE, WorldStream.MORSEL_PASS_TICKS * 2 + 1).is_empty(), "%s: no item" % what)
		check_eq(w.morsel_claims(), 0, "%s: no claim" % what)


## S3G17: an eaten item, or one dropped beyond the ring, frees its site; the site is due again after
## its species' respawn time (rammer: 30 s +/- 6 s) and then spawns a new item. A rotted item does
## the same.
func test_a_gone_item_comes_back_after_the_respawn_time() -> void:
	for how in ["eaten", "dropped", "rotted"]:
		var sim := _sim(OUT_OF_VIEW)
		var w := sim.world
		var item := _spawned(sim)
		check(not item.is_empty(), "%s: an item" % how)
		if item.is_empty():
			continue
		match how:
			"eaten":
				check(sim.carrion.consume(item.id), "eaten")
			"dropped":
				_move(sim, SITE_TM + Vector2(0.0, -54.0))
				_run(sim, 1)
				check(sim.carrion.find(item.id).is_empty(), "dropped beyond the ring")
				_move(sim, OUT_OF_VIEW)
			"rotted":
				item.age = item.lifetime
		_run(sim, WorldStream.MORSEL_PASS_TICKS)
		var e: Dictionary = w.morsel_sites[SITE]
		check_eq([e.food_id, w.morsel_claims()], ["", 0], "%s: the pass frees the site" % how)
		var wait := int(e.due_tick) - (sim.tick - posmod(sim.tick, WorldStream.MORSEL_PASS_TICKS))
		check(wait >= 24 * 60 and wait <= 36 * 60, "%s: due after 30 s +/- 6 s (%d ticks)" % [how, wait])
		check(_spawned(sim, SITE, int(e.due_tick) - sim.tick - 1).is_empty(), "%s: nothing before it is due" % how)
		var again := _spawned(sim, SITE, WorldStream.MORSEL_PASS_TICKS + 2)
		check(not again.is_empty() and again.id != item.id, "%s: a new item once due" % how)


## S3G17 and BP3-3's first case: unloading the chunk expires the live item ("unloaded") and the
## entry leaves; unloading every chunk with a site leaves no claim and no entry.
func test_an_unload_expires_the_item_and_drops_the_entry() -> void:
	var sim := _sim(OUT_OF_VIEW)
	var w := sim.world
	var item := _spawned(sim)
	check(not item.is_empty(), "an item")
	var k := WorldConfig.tm_to_am(4)
	check(sim.debug_teleport_abs(SITE_TM.x * k, (SITE_TM.y - 400.0) * k), "far away")
	var gone := _of(sim.drain_events(), "carrion_expired").filter(func(e: Dictionary) -> bool: return e.food_id == item.get("id"))
	check_eq(gone.size(), 1, "the item expired")
	if gone.size() == 1:
		check_eq(gone[0].reason, "unloaded", "for the unload")
	check(not w.morsel_sites.has(SITE), "the entry left")
	_run(sim, 1)
	var loaded_sites := 0
	for key in w._chunks:
		loaded_sites += (w._chunks[key] as WorldChunk).morsel_sites.size()
	check_eq(w.morsel_claims(), w.morsel_sites.values().filter(func(e: Dictionary) -> bool: return e.food_id != "").size(),
		"the claims count the entries with an item")
	check(w.morsel_sites.size() == loaded_sites and not w.morsel_sites.has(SITE), "only loaded sites keep entries")


## S3G17b: the food total counts the live morsel items. With two sites in the ring and the cap one
## above the zones' items, the first item fills the cap: the second site never spawns, pass after pass.
func test_the_food_total_counts_the_morsel_items() -> void:
	var mid := Vector2(51.0, 80.0)   # sites m_f_1_1 (51, 48) and m_f_1_3 (51, 112): 32 tm north and south
	var sim := _sim(mid, 2, 0)
	var w := sim.world
	check(w.morsel_sites.has("m_f_1_1") and w.morsel_sites.has("m_f_1_3"), "two sites loaded")
	check(_spawned(sim, "m_f_1_1", WorldStream.MORSEL_PASS_TICKS * 2 + 1).is_empty(), "at cap 0 nothing spawns")
	check_eq(w.morsel_claims(), 0, "no claim")
	_run(sim, 1)
	var zones := w._food_total
	w.caps["food_items"] = zones + 1
	var spawned := 0
	for i in WorldStream.MORSEL_PASS_TICKS * 4:
		spawned += _of(_run(sim, 1), "carrion_spawned", "morsel_site").size()
	check_eq(spawned, 1, "one item fills the cap")
	check_eq(w.morsel_claims(), 1, "one claim")
	check_eq(w._food_total, zones + 1, "and the total counts it")


## BP3-3's second case: 4 to 1 leaves no claim, and the size-1 food total is a run's that only went
## to size 1 at the same place and tick.
func test_going_from_4_to_1_leaves_no_claim() -> void:
	var a := _sim(OUT_OF_VIEW)
	check(not _spawned(a).is_empty(), "an item at 4")
	var b := _sim(OUT_OF_VIEW, 4, 0)   # no morsel item ever spawns here
	_run(b, a.tick - b.tick)
	check_eq(a.tick, b.tick, "the same tick")
	var place := a.absolute_position_am()
	check_eq(b.absolute_position_am(), place, "and place")
	check(a.debug_set_size(1) and b.debug_set_size(1), "both to size 1")
	check_eq([a.world.morsel_claims(), a.world.morsel_sites.size()], [0, 0], "no claim, no entry")
	b.world.caps["food_items"] = a.world.caps.food_items
	_run(a, 1)
	_run(b, 1)
	check_eq(a.world._food_total, b.world._food_total, "the same food total")


## BP3-3's third case: 4 to 1 to 4 leaves the same entries and claims as one debug_set_size(4) at the
## same place and tick, then and after the next pass.
func test_going_4_to_1_to_4_matches_one_set_size() -> void:
	var a := _sim(OUT_OF_VIEW)
	check(not _spawned(a).is_empty(), "an item at 4")
	var content := FakeWorldGen.fixture_content(B1_WORLD)
	var b := FakeWorldGen.endless_sim(7, catalog, layout, species, content, PackedFloat64Array(), 4, true)
	var place := a.absolute_position_am()
	check(b.debug_teleport_abs(place[0], place[1]), "b at a's place")
	_run(b, a.tick - b.tick)
	check(a.debug_set_size(1) and a.debug_set_size(4), "a: 4 to 1 to 4")
	check(b.debug_set_size(4), "b: to 4")
	check_eq(a.absolute_position_am(), b.absolute_position_am(), "the same place")
	check_eq(a.tick, b.tick, "the same tick")
	check_eq(a.world.snapshot(a).get("morsel_sites"), b.world.snapshot(b).get("morsel_sites"), "the same entries")
	check_eq(a.world.morsel_claims(), b.world.morsel_claims(), "the same claims")
	_run(a, WorldStream.MORSEL_PASS_TICKS)
	_run(b, WorldStream.MORSEL_PASS_TICKS)
	var sa: Dictionary = a.world.snapshot(a).get("morsel_sites", {})
	var sb: Dictionary = b.world.snapshot(b).get("morsel_sites", {})
	check_eq(sa.keys(), sb.keys(), "the same entries after the pass")
	check_eq([a.world.morsel_claims(), b.world.morsel_claims()], [1, 1], "each spawned the item")
