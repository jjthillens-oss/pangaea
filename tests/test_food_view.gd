extends TestCase
## The endless world's food view (S1 T2.3, the streaming block's step 6), on FakeWorldGen: one zone
## of radius 5 and capacity 40 (5 plankton items) per 2 x 2 chunks, at the chunk's centre. Only zones
## whose nearest point lies within 52 tm of the body show plankton; carrion beyond 52 tm goes for
## good; over caps.food_items the farthest zones wholly out of view are trimmed; a new world fills
## every food zone at once; each zone draws its plankton places from its own stream, so they do not
## depend on the route.

const FakeWorldGen := preload("res://tests/fakes/fake_world_gen.gd")
const SEED := 4302
const FOOD_RING := 52.0
## The zone the route tests visit: chunk (4, 0)'s, centred at abs (144, 16).
const ZONE := "z_f_4_0"
const ZONE_AT := Vector2(144.0, 16.0)

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()


func _endless(content: WorldContent = null) -> PoolSim:
	return FakeWorldGen.endless_sim(SEED, catalog, layout, null, content)


## The nearest point of every loaded zone within the ring from local `body`, by id.
func _food_zones(sim: PoolSim, body: Vector2) -> Dictionary:
	var out := {}
	for z in sim.region.zones:
		var d := body.distance_to(z.center) - float(z.radius)
		if d <= FOOD_RING:
			out[z.id] = d
	return out


func _counts(sim: PoolSim) -> Dictionary:
	var out := {}
	for item in sim.plankton.items:
		out[item.zone] = int(out.get(item.zone, 0)) + 1
	return out


func test_only_zones_within_52_tm_hold_plankton() -> void:
	var sim := _endless()
	var bad := 0
	var first := ""
	var seen_active := {}
	for t in 3000:
		var body := sim.motion.position
		sim.step(SimIntent.new(Vector2.RIGHT if t < 2000 else Vector2(-0.6, 0.8)))
		var want := _food_zones(sim, body)
		var active := sim.plankton.active_zones
		var problem := ""
		if active.keys().size() != want.size() or not want.keys().all(func(id: String) -> bool: return active.has(id)):
			problem = "active %s, want %s" % [active.keys(), want.keys()]
		for item in sim.plankton.items:
			if not active.has(item.zone):
				problem = "item %s of inactive zone %s" % [item.id, item.zone]
		if not problem.is_empty():
			bad += 1
			if first.is_empty():
				first = "tick %d: %s" % [t, problem]
		for id in active:
			seen_active[id] = true
	check_eq(bad, 0, "exactly the zones within 52 tm are active, and only they hold items (%s)" % first)
	check(seen_active.size() >= 4, "the swim met %d zones" % seen_active.size())


func test_a_zone_that_leaves_the_food_ring_drops_its_items_without_events() -> void:
	var sim := _endless()
	sim.drain_events()
	var left := 0
	for t in 2400:
		var before_items := {}
		for item in sim.plankton.items:
			before_items[item.id] = item.zone
		var before_active := sim.plankton.active_zones.duplicate()
		sim.step(SimIntent.new(Vector2.RIGHT))
		var events := sim.drain_events()
		for id in before_active:
			if sim.plankton.active_zones.has(id):
				continue
			left += 1
			check_eq(sim.plankton.count_in(id), 0, "zone %s shows nothing once it left" % id)
			check(not sim.plankton.is_regrowing(id), "and forgets its flags")
			for e in events:
				check(str(e.get("zone", "")) != id, "no %s event names zone %s" % [e.type, id])
				var food := str(e.get("food_id", e.get("food", "")))
				check(food.is_empty() or before_items.get(food, "") != id, "no %s event names its items" % e.type)
	check(left > 0, "zones left the ring (%d)" % left)


func test_a_zone_that_enters_the_food_ring_regrows_one_item_a_tick() -> void:
	var sim := _endless()
	var entered := 0
	var bad := 0
	var filled := 0
	for t in 2400:
		var before := _counts(sim)
		var before_active := sim.plankton.active_zones.duplicate()
		sim.step(SimIntent.new(Vector2.RIGHT))
		var after := _counts(sim)
		for id in after:
			if int(after[id]) - int(before.get(id, 0)) > 1:
				bad += 1
		for id in sim.plankton.active_zones:
			if not before_active.has(id):
				entered += 1
				check(int(after.get(id, 0)) <= 1, "zone %s shows at most one item on the tick it enters" % id)
		for id in after:
			if int(after[id]) == sim.plankton.target_count(sim.region.zone(id)) and int(before.get(id, 0)) < int(after[id]):
				filled += 1
	check_eq(bad, 0, "no zone gains more than one item a tick")
	check(entered > 0, "zones entered the ring (%d)" % entered)
	check(filled > 0, "and grew to their count (%d)" % filled)


## A stationary cell over the item cap: the trimmed zones are the farthest of those wholly out of
## view (zones in view stay), as few as fit the cap, worked out here independently.
func test_trimming_drops_the_farthest_out_of_view_zones_first_and_never_one_in_view() -> void:
	var sim := _endless()
	var cap := 7
	sim.world.caps.food_items = cap
	var quad_margin := float(layout.camera.look_ahead_max) + float(species.fairness.spawn_view_margin_m)
	var aspect := float(species.fairness.spawn_view_aspect)
	var checked := 0
	var in_view_kept := 0
	# (48, 30) has two food zones, both in view: neither may go, however far over the cap.
	for spot in [Vector2(0.0, 9.0), Vector2(40.0, 40.0), Vector2(70.0, -20.0), Vector2(100.0, 9.0), Vector2(32.0, -40.0),
			Vector2(-30.0, 30.0), Vector2(48.0, 30.0)]:
		check(sim.debug_teleport(sim.world.local_of_abs(spot.x, spot.y)), "the cell at %s" % spot)
		for t in 40:
			sim.step(SimIntent.new())
		var body := sim.motion.position
		var food := _food_zones(sim, body)
		var quad := ViewFootprint.corners(body, layout.camera, float(layout.camera.zoom_max), aspect)
		var total := 0
		for id in food:
			total += sim.plankton.target_count(sim.region.zone(id))
		var out: Array = []
		for id in food:
			var z := sim.region.zone(id)
			if ViewFootprint.distance_outside(quad, z.center) > quad_margin + float(z.radius):
				out.append(id)
		out.sort_custom(func(a: String, b: String) -> bool: return food[a] > food[b] or (food[a] == food[b] and a < b))
		var want := food.duplicate()
		for id in out:
			if total <= cap:
				break
			want.erase(id)
			total -= sim.plankton.target_count(sim.region.zone(id))
		var got := sim.plankton.active_zones.keys()
		got.sort()
		var want_keys := want.keys()
		want_keys.sort()
		check_eq(got, want_keys, "at %s the trimmed zones are the farthest out of view" % spot)
		var over := total > cap
		for id in food:
			if not out.has(id):
				check(sim.plankton.active_zones.has(id), "zone %s in view is never trimmed" % id)
				if over:
					in_view_kept += 1
		if want.size() < food.size():
			checked += 1
	check(checked >= 2, "trimming happened at %d spots" % checked)
	check(in_view_kept >= 2, "zones in view kept while still over the cap (%d)" % in_view_kept)
	check(sim.world.counters.food_trimmed > 0, "and was counted")


## C-11: food_trimmed counts the transitions into trimmed, not the ticks a zone stays trimmed.
func test_food_trimmed_counts_transitions_not_ticks() -> void:
	var sim := _endless()
	sim.world.caps.food_items = 5
	sim.step(SimIntent.new())
	var after_one := int(sim.world.counters.food_trimmed)
	check(after_one >= 1, "zones trimmed (%d)" % after_one)
	for t in 100:
		sim.step(SimIntent.new())
	check_eq(int(sim.world.counters.food_trimmed), after_one, "100 more trimmed ticks count nothing")
	sim.world.caps.food_items = 120
	sim.step(SimIntent.new())
	sim.world.caps.food_items = 5
	sim.step(SimIntent.new())
	check_eq(int(sim.world.counters.food_trimmed), 2 * after_one, "trimmed again after showing food: counted again")


## C-9: a new world shows every food zone full at once.
func test_create_fills_every_food_zone_at_once() -> void:
	var sim := _endless()
	var counts := _counts(sim)
	check(sim.plankton.active_zones.size() >= 2, "food zones at the start (%d)" % sim.plankton.active_zones.size())
	for id in sim.plankton.active_zones:
		var z := sim.region.zone(id)
		check(sim.plankton.target_count(z) > 0, "zone %s has stock" % id)
		check_eq(int(counts.get(id, 0)), sim.plankton.target_count(z), "zone %s full" % id)
	check(sim.drain_events().filter(func(e: Dictionary) -> bool: return e.type != "chunk_loaded").is_empty(),
		"and the start is not news: only the chunk loads are queued")


## D-11: a near respawn (no teleport) fills at once the food zones touching the new footprint plus
## the spawn margin; the other food zones regrow one item a tick, out of view. Every zone is emptied of
## items (its stock kept) while the cell is dead, so each zone's count after the respawn tick shows
## which way it filled.
func test_a_near_respawn_fills_only_the_zones_touching_the_new_footprint() -> void:
	var sim := _endless()
	for t in 30:
		sim.step(SimIntent.new(Vector2(0.6, 0.8)))
	check(sim.debug_hurt_player(1.0e9) and sim.dead, "the cell dies")
	for t in 30:
		sim.step(SimIntent.new())
	for z in sim.region.zones:
		sim.plankton.clear_zone(z.id)
	sim.respawn_player()
	sim.step(SimIntent.new())
	var events := sim.drain_events()
	var respawned := events.filter(func(e: Dictionary) -> bool: return e.type == "respawned")
	check(respawned.size() == 1 and respawned[0].teleport == false, "a near respawn (%s)" % [respawned])
	var counts := _counts(sim)
	var margin := float(layout.camera.look_ahead_max) + float(species.fairness.spawn_view_margin_m)
	var quad := ViewFootprint.corners(sim.motion.position, layout.camera, float(layout.camera.zoom_max),
		float(species.fairness.spawn_view_aspect))
	var touching := 0
	var other := 0
	for id in sim.plankton.active_zones:
		var z := sim.region.zone(id)
		var want := sim.plankton.target_count(z)
		check(want > 1, "zone %s has stock for more than one item" % id)
		if ViewFootprint.distance_outside(quad, z.center) <= margin + float(z.radius):
			touching += 1
			check_eq(int(counts.get(id, 0)), want, "zone %s touches the view: full at once" % id)
		else:
			other += 1
			check(int(counts.get(id, 0)) <= 1, "zone %s out of view regrows one item a tick (%d)" % [id, int(counts.get(id, 0))])
	check(touching >= 1, "zones touching the new view (%d)" % touching)
	check(other >= 1, "and food zones out of it (%d)" % other)


## The home block's starting carrion within the food ring is placed at create; the rest is not.
func test_create_places_the_home_carrion_within_the_food_ring() -> void:
	var c := FakeWorldGen.fixture_content()
	c.home.carrion_initial = [[1.5, 13.0], [-10.5, 4.5], [0.0, 70.0]]
	var sim := _endless(c)
	var places: Array = []
	for item in sim.carrion.items:
		places.append(item.position)
	check_eq(places, [Vector2(1.5, 4.0), Vector2(-10.5, -4.5)], "the two within 52 tm, in data order, local")
	check_eq(sim.carrion.next_number, 3, "the far one never took an id")
	check(sim.carrion.initial.is_empty(), "create-only data")


func test_carrion_beyond_52_tm_is_dropped_for_good() -> void:
	var sim := _endless()
	var item := sim.carrion.spawn(Vector2(0.0, 2.0), "test", 10.0)
	check(not item.is_empty(), "a carrion item at the origin")
	sim.drain_events()
	var gone_at := -1.0
	for t in 2400:
		var x := sim.motion.position.x
		sim.step(SimIntent.new(Vector2.RIGHT))
		if gone_at < 0.0 and sim.carrion.items.is_empty():
			gone_at = x
	check(gone_at > 0.0, "it went")
	check(Vector2(gone_at, 0.0).distance_to(Vector2(0.0, 2.0)) > FOOD_RING, "beyond 52 tm (at %.2f)" % gone_at)
	check(Vector2(gone_at, 0.0).distance_to(Vector2(0.0, 2.0)) < FOOD_RING + 0.2, "on the first tick past it")
	check(sim.drain_events().filter(func(e: Dictionary) -> bool: return e.type.begins_with("carrion")).is_empty(),
		"without an event")
	check(sim.debug_teleport(Vector2(0.0, 6.0)), "the cell back next to where it lay")
	for t in 60:
		sim.step(SimIntent.new())
	check(sim.carrion.items.is_empty(), "and the carrion did not come back")


## A zone's plankton places come from its own stream, so the zone shows the same first items whichever
## way the cell comes (route independence, S1 core 8.9).
func test_a_zones_first_anchors_are_the_same_along_two_routes() -> void:
	var west := _approach(_endless(), Vector2(84.0, 16.0), Vector2.RIGHT)
	# The northern route first visits the zones round (-112, 16), so other zones draw more plankton
	# before this one than on the western route.
	var north_sim := _endless()
	check(north_sim.debug_teleport(north_sim.world.local_of_abs(-100.0, 9.0)), "a detour west")
	for t in 40:
		north_sim.step(SimIntent.new())
	var north := _approach(north_sim, Vector2(144.0, -44.0), Vector2.DOWN)
	check_eq(west.size(), 5, "the zone filled from the west (capacity 40, 8 an item)")
	check(_same_places(north, west), "and the same anchors from the north: %s and %s" % [north, west])


## B-3: a zone whose disc crosses into a neighbour chunk, with a shell there exactly the 0.7 bu gap
## from the disc, draws the same 12 anchors whether or not that neighbour is loaded.
func test_a_zone_crossing_a_chunk_edge_draws_the_same_anchors_with_and_without_its_neighbour() -> void:
	var without := FakeWorldGen.endless_sim(SEED, catalog, layout, species, null, PackedFloat64Array([-39.0, 48.0]))
	var with := FakeWorldGen.endless_sim(SEED, catalog, layout, species, null, PackedFloat64Array([-60.0, 48.0]))
	var neighbour := FakeWorldGen.EDGE_CHUNK + Vector2i(-1, 0)
	check(without.world.chunk(FakeWorldGen.EDGE_CHUNK) != null and without.world.chunk(neighbour) == null,
		"one sim has the zone's chunk without its neighbour")
	check(with.world.chunk(neighbour) != null, "the other has both")
	var a := _anchors_abs(without, "z_edge")
	var b := _anchors_abs(with, "z_edge")
	check_eq(a.size(), 12, "12 anchors filled at once")
	check(_same_places(a, b), "the same anchors: %s and %s" % [a, b])
	# Not luck: every place an anchor can take (within radius - drift reach of the centre) is clear
	# of the neighbour's shell, so no draw is ever refused because of it.
	var z := with.region.zone("z_edge")
	var reach := float(z.radius) - with.plankton.drift_reach()
	var blocked := 0
	for i in 41:
		for j in 41:
			var p: Vector2 = z.center + Vector2(i - 20, j - 20) * (reach / 20.0)
			if p.distance_to(z.center) <= reach and not with.arena.is_clear(p, with.plankton.anchor_clearance()):
				blocked += 1
	check_eq(blocked, 0, "every possible anchor is clear with the neighbour loaded")


func _anchors_abs(sim: PoolSim, zone_id: String) -> Array:
	var out := []
	for item in sim.plankton.items:
		if item.zone == zone_id:
			var p := sim.world.abs_of_local(item.anchor)
			out.append(Vector2(p[0], p[1]))
	return out


## Unloaded and reloaded, a zone's stream starts over: its first anchors repeat.
func test_a_reloaded_zone_restarts_its_stream() -> void:
	var sim := _endless()
	var first := _approach(sim, Vector2(84.0, 16.0), Vector2.RIGHT)
	check(sim.debug_teleport(sim.world.local_of_abs(400.0, 16.0)), "far away")
	sim.step(SimIntent.new())
	check(sim.region.zone(ZONE).is_empty(), "the zone unloaded")
	var again := _approach(sim, Vector2(84.0, 16.0), Vector2.RIGHT)
	check(_same_places(again, first), "the same first anchors: %s and %s" % [again, first])
	check_eq(again.size(), 5, "all five")


func test_pool_mode_has_no_zone_streams_or_food_view() -> void:
	var r := Lineage.found(SEED, "test+dev", catalog, "omnivore")
	r.save.player["position"] = PlaneSpace.to_save(layout.spawn)
	var sim := PoolSim.create(r.save, catalog, layout, species)
	for t in 600:
		sim.step(SimIntent.new(Vector2.UP if t < 300 else Vector2.DOWN))
	check(sim.region.streams.is_empty(), "no streams: every zone draws the region's rng as in M1")
	check(not sim.plankton.endless and sim.plankton.active_zones.is_empty(), "no food view")
	for z in sim.region.zones:
		check(sim.plankton.count_in(z.id) <= sim.plankton.target_count(z), "zone %s shows its count" % z.id)


## The same absolute places, up to the float32 rounding of a local position in two frames (the
## routes may end with different origins; an ulp is 1.5e-5 tm under 256 tm).
static func _same_places(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if absf(a[i][0] - b[i][0]) > 3e-5 or absf(a[i][1] - b[i][1]) > 3e-5:
			return false
	return true


## Puts the cell at abs `start` and swims along `dir` until ZONE shows its full count; its items'
## anchors in spawn order.
func _approach(sim: PoolSim, start: Vector2, dir: Vector2) -> Array:
	check(sim.debug_teleport(sim.world.local_of_abs(start.x, start.y)), "the cell at %s" % start)
	sim.step(SimIntent.new())
	check(not sim.plankton.active_zones.has(ZONE), "the zone starts out of the food ring")
	for t in 600:
		var z := sim.region.zone(ZONE)
		if not z.is_empty() and sim.plankton.count_in(ZONE) >= sim.plankton.target_count(z) and sim.plankton.count_in(ZONE) > 0:
			break
		sim.step(SimIntent.new(dir))
	var out: Array = []
	for item in sim.plankton.items:
		if item.zone == ZONE:
			out.append(sim.world.abs_of_local(item.anchor))
	return out
