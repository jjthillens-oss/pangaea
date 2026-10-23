extends TestCase
## The sim's cost shortcuts (S1 perf, G17) give exactly what the plain code gives: each test pins one
## shortcut against the work it replaces, on inputs that reach its edge cases.

const ForageBot := preload("res://game/dev/forage_bot.gd")
const SwimBot := preload("res://game/dev/swim_bot.gd")
const Gates := preload("res://tests/test_endless_gates.gd")
const COST := "res://tests/test_endless_cost.gd"
const FAKE_GEN := "res://tests/fakes/fake_world_gen.gd"
const FIXTURE_WORLD := "res://tests/fixtures/world/world_min.json"
const BUILD_ID := "test+dev"
const HOME := Vector2(0.0, 9.0)
const DEATH_NOTICE_TICKS := 90

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()


## An omnivore at home on the fixture world, with its starting events drained.
func _forager(seed_value: int) -> PoolSim:
	var r := Lineage.found(seed_value, BUILD_ID, catalog, "omnivore")
	r.save.player["position"] = PlaneSpace.to_save(HOME)
	var sim := PoolSim.create(r.save, catalog, layout, species, WorldContent.load_from(FIXTURE_WORLD, layout, species))
	sim.drain_events()
	return sim


## The endless queue's binary search puts every entry where the pool's scan does: before the first
## entry that is not less by (at_tick, site), ties and repeats included.
func test_the_endless_queue_insert_matches_the_scan() -> void:
	var fast := CreatureField.new()
	fast.endless = true
	var scan := CreatureField.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var sites := ["a", "b", "b2", "c_1", "c_10", "c_2", "z"]
	for i in 400:
		var site: String = sites[rng.randi_range(0, sites.size() - 1)]
		var at := rng.randi_range(0, 12)
		var species_id := "s%d" % i   # tells repeats of (at_tick, site) apart
		fast._enqueue(site, species_id, at)
		scan._enqueue(site, species_id, at)
		if fast.queue != scan.queue:
			check_eq(fast.queue, scan.queue, "insert %d (%s at %d)" % [i, site, at])
			return
		if i % 50 == 49:
			var taken := rng.randi_range(0, 10)   # the due front
			fast.queue = fast.queue.slice(taken)
			scan.queue = scan.queue.slice(taken)
	check_eq(fast.queue.size(), scan.queue.size(), "both queues hold the same entries")


## A tick's spawn retries, queued together, land where one insert at a time puts them: batches in
## site order (as the due entries come out) and out of order, with repeats, next to entries of their
## own tick and others.
func test_queued_retries_match_one_insert_at_a_time() -> void:
	var fast := CreatureField.new()
	fast.endless = true
	var scan := CreatureField.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1848
	var sites := ["a", "b", "b2", "c_1", "c_10", "c_2", "z"]
	var made := 0
	var in_order := 0
	for batch in 300:
		var at := rng.randi_range(0, 12)
		var picks: Array[Dictionary] = []
		for k in rng.randi_range(1, 6):
			made += 1   # each record's species tells repeats of (at_tick, site) apart
			picks.append({"id": sites[rng.randi_range(0, sites.size() - 1)], "species": "s%d" % made})
		if rng.randf() < 0.6:
			picks.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
				return str(x.id) < str(y.id) or (x.id == y.id and str(x.species) < str(y.species)))
			in_order += 1
		if rng.randf() < 0.3:
			var one := {"id": sites[rng.randi_range(0, sites.size() - 1)], "species": "solo%d" % batch}
			fast._enqueue(one.id, one.species, at)
			scan._enqueue(one.id, one.species, at)
		fast._enqueue_retries(picks, at)
		for s in picks:
			scan._enqueue(s.id, s.species, at)
		if fast.queue != scan.queue:
			check_eq(fast.queue, scan.queue, "batch %d at %d" % [batch, at])
			return
		if batch % 40 == 39:
			var taken := rng.randi_range(0, 30)   # the due front
			fast.queue = fast.queue.slice(taken)
			scan.queue = scan.queue.slice(taken)
	check(in_order > 100 and in_order < 250, "both kinds of batch (%d in order)" % in_order)
	check_eq(fast.queue.size(), scan.queue.size(), "both queues hold the same entries")


## tick_spawns_at turns every due site away without the spawn check while the sleepers and the awake
## are both at their caps: on the saturated world (the cost case's DenseGen, swum through
## overdriven), _caps_full() is exactly that, and then every free site's _try_site says no.
func test_full_caps_turn_every_site_away() -> void:
	var cost: GDScript = load(COST)
	var content: Variant = (load(FAKE_GEN) as GDScript).call("fixture_content")
	var r := Lineage.found(2802, Gates.BUILD_ID, catalog, "hunter")
	Gates.make_racer(r.save.genome, catalog)
	r.save.player["position"] = PlaneSpace.to_save_abs(0.0, 16.0)
	var sim := PoolSim._create_endless(r.save, catalog, layout, species, content, cost.DenseGen.new(content, species, 2802))
	sim.debug_set_hidden(true)
	sim.drain_events()
	var f := sim.creatures
	var bot = SwimBot.new(Vector2.RIGHT)
	var wrong := 0
	var both := 0
	var one := 0
	var refused := 0
	for t in 1500:
		SwimBot.overdrive(sim)
		sim.step(bot.next_intent(sim))
		sim.drain_events()
		var sleepers_full := f.creatures.size() - f.awake().size() >= int(sim.world.caps.sleepers)
		var awake_full := f.awake().size() >= int(sim.world.caps.awake)
		if f._caps_full() != (sleepers_full and awake_full):
			wrong += 1
		if sleepers_full != awake_full:
			one += 1
		if f._caps_full() and t % 25 == 0:
			both += 1
			for id in sim.world.sites:
				var s: Dictionary = sim.world.sites[id]
				if f._occupant(s.id) != null:
					continue
				if f._try_site(s, sim.arena, sim._player_places(), sim.tick):
					wrong += 1   # it spawned
				else:
					refused += 1
	check_eq(wrong, 0, "ticks where _caps_full() differs from both caps, or a full world took a creature")
	check(both > 10, "the caps were both full (%d checks)" % both)
	check(one > 0, "and only one of them at times (%d ticks)" % one)
	check(refused > 100, "free sites were turned away (%d)" % refused)


## take_events reads only the awake brains unless a sleeper may hold events: after every step no brain,
## asleep or awake, still holds one. An omnivore swims east overdriven, leaving the creatures it
## passed asleep (some in a chase), comes back and forages, eating, chased, dying and respawning, with
## the hide switch flipped now and then (every brain forgets the cell).
func test_no_brain_keeps_events_past_a_step() -> void:
	var sim := _forager(5101)
	var east = SwimBot.new(Vector2.RIGHT)
	var west = SwimBot.new(Vector2.LEFT)
	var forage = ForageBot.new()
	var dead_since := -1
	var counts := {"creature_slept": 0, "creature_woke": 0, "creature_removed": 0, "respawned": 0}
	var left := 0
	for t in 3000:
		if t % 300 == 150:
			sim.debug_set_hidden(not sim.dev_hidden)
		if sim.dead:
			if dead_since < 0:
				dead_since = sim.tick
			elif sim.tick - dead_since >= DEATH_NOTICE_TICKS and not sim.respawn_pending:
				sim.respawn_player()
				dead_since = -1
		var bot = east if t < 900 else (west if t < 1800 else forage)
		if t < 1800:
			SwimBot.overdrive(sim)
		sim.step(bot.next_intent(sim))
		for e in sim.drain_events():
			if counts.has(e.type):
				counts[e.type] += 1
		for c in sim.creatures.creatures:
			if c.brain != null and not c.brain.events.is_empty():
				left += 1
	check_eq(left, 0, "brain events left after a step")
	for type in ["creature_slept", "creature_woke", "creature_removed"]:
		check(int(counts[type]) > 0, "some %s (%s)" % [type, counts])


## The hooks every brain gets reach sleepers too, and what a sleeper's brain says then comes out with
## the next events: debug creatures (which the stream never wakes) put to sleep engaged, then hiding
## the cell, a removal, the cell's death and its respawn at the checkpoint.
func test_a_sleepers_events_from_a_hook_come_out_at_once() -> void:
	var sim := _forager(5102)
	check(sim.debug_spawn_creature("ambush_hunter", Vector2(30.0, -30.0), 0.0), "a hunter")
	check(sim.debug_spawn_creature("rammer", Vector2(-30.0, -30.0), 0.0), "a rammer")
	var field := sim.creatures
	var a: CreatureField.Creature = field.creatures[field.creatures.size() - 2]
	var b: CreatureField.Creature = field.creatures[field.creatures.size() - 1]
	CreatureBrain._notice(a.brain, CreatureField.PLAYER_ID, "sight", sim.tick)
	CreatureBrain._notice(b.brain, a.id, "sight", sim.tick)
	field.sleep(b, sim.tick)   # first: a sleeping creature is forgotten by every awake brain
	field.sleep(a, sim.tick)
	sim.drain_events()
	sim.step(SimIntent.new())
	sim.drain_events()
	check(a.asleep and b.asleep, "both still asleep")
	sim.debug_set_hidden(true)
	check_eq(_gave_up(sim.drain_events()), [[a.id, CreatureField.PLAYER_ID]], "hidden: the sleeping hunter gives up the cell")
	sim.debug_set_hidden(false)
	field.remove(a, "killed", sim.tick, false)
	check_eq(_gave_up(sim.drain_events()), [[b.id, a.id]], "removed: the sleeping rammer gives up the hunter")
	CreatureBrain._notice(b.brain, CreatureField.PLAYER_ID, "sight", sim.tick)
	sim.drain_events()
	check(sim.debug_hurt_player(1e9), "the cell dies")
	check_eq(_gave_up(sim.drain_events()), [[b.id, CreatureField.PLAYER_ID]], "death: the sleeping rammer gives up the cell")
	# A sleeper in a tell at the cell: forgetting the cell at the respawn cancels it.
	b.brain.target = CreatureField.PLAYER_ID
	b.brain.state = CreatureBrain.ATTACK
	b.brain.phase = CreatureBrain.TELL
	sim.respawn_player()
	sim.step(SimIntent.new())
	check_eq(_cancelled(sim.drain_events()), [b.id], "respawn: the sleeper's tell is cancelled")
	check(b.asleep and b.brain.events.is_empty(), "it sleeps on, its brain holding nothing")


static func _gave_up(events: Array[Dictionary]) -> Array:
	var out := []
	for e in events:
		if e.type == "creature_gave_up":
			out.append([e.id, e.target])
	return out


static func _cancelled(events: Array[Dictionary]) -> Array:
	var out := []
	for e in events:
		if e.type == "creature_recovered" and e.outcome == "cancelled":
			out.append(e.id)
	return out


## A body that leaves (removed, or put to sleep) is forgotten by each brain as on_target_gone forgets
## it, also by one that remembers it only as the attacker that hurt it while it notices the cell
## (CreatureField._forget_in's shortcut): the hurt goes with the attacker, and what it notices stays.
func test_a_brain_forgets_an_attacker_that_leaves_while_it_notices_the_cell() -> void:
	var sim := _forager(5103)
	var field := sim.creatures
	for leave in ["removed", "asleep"]:
		check(sim.debug_spawn_creature("ambush_hunter", Vector2(30.0, -30.0), 0.0), "%s: a hunter" % leave)
		check(sim.debug_spawn_creature("rammer", Vector2(-30.0, -30.0), 0.0), "%s: a rammer" % leave)
		var a: CreatureField.Creature = field.creatures[field.creatures.size() - 2]
		var b: CreatureField.Creature = field.creatures[field.creatures.size() - 1]
		CreatureBrain._notice(b.brain, CreatureField.PLAYER_ID, "sight", sim.tick)
		b.brain.attacker = a.id
		b.brain.pain = true
		if leave == "removed":
			field.remove(a, "killed", sim.tick, false)
		else:
			field.sleep(a, sim.tick)
		check_eq([b.brain.attacker, b.brain.pain], ["", false], "%s: the rammer forgets the hunter that hurt it" % leave)
		check_eq(b.brain.target, CreatureField.PLAYER_ID, "%s: and still notices the cell" % leave)
		sim.drain_events()


## CreatureField.remove_all leaves the field as remove on each creature in turn would: twins on the
## saturated world take the same creatures away, one with remove_all and one one by one, while nothing
## refers to them (the one pass), while a brain left has one of them as its target, while a brain not
## engaged sits in the token list, and while one chases the cell without the token (one by one in the
## last three). The events, the lists, the token and every brain left must be the same.
func test_remove_all_leaves_the_field_as_removing_each_in_turn() -> void:
	var sims: Array[PoolSim] = []
	for i in 2:
		var cost: GDScript = load(COST)
		var content: Variant = (load(FAKE_GEN) as GDScript).call("fixture_content")
		var r := Lineage.found(2802, Gates.BUILD_ID, catalog, "hunter")
		Gates.make_racer(r.save.genome, catalog)
		r.save.player["position"] = PlaneSpace.to_save_abs(0.0, 16.0)
		var sim := PoolSim._create_endless(r.save, catalog, layout, species, content, cost.DenseGen.new(content, species, 2802))
		sim.debug_set_hidden(true)
		sim.drain_events()
		sims.append(sim)
	var a := sims[0]
	var b := sims[1]
	var bot = SwimBot.new(Vector2.RIGHT)
	var forgot := 0   # memories of the gone that the brains left dropped
	for round in ["quiet", "target", "token", "chase"]:
		for t in 150:
			SwimBot.overdrive(a)
			SwimBot.overdrive(b)
			var intent = bot.next_intent(a)
			a.step(intent)
			b.step(intent)
			a.drain_events()
			b.drain_events()
		var fa := a.creatures
		var fb := b.creatures
		var ids: Array[String] = []
		var n := 0
		for c in fa.creatures:
			if not c.site_id.is_empty() and c.brain != null:
				n += 1
				if n % 3 == 0 and ids.size() < 6:
					ids.append(c.id)
		var stay := ""
		for c in fa.creatures:
			if c.brain != null and not ids.has(c.id) and stay.is_empty():
				stay = c.id
		for f: CreatureField in [fa, fb]:
			var s := f.find(stay)
			match round:
				"target":
					s.brain.target = ids[0]
				"token":
					f.engaged_on_player.append(s.id)
				"chase":
					s.brain.target = CreatureField.PLAYER_ID
					s.brain.state = CreatureBrain.CHASE
		for c in fa.creatures:
			for id in ids:
				forgot += 1 if c.brain != null and not ids.has(c.id) and c.brain.seen.has(id) else 0
		var list_a: Array[CreatureField.Creature] = []
		var list_b: Array[CreatureField.Creature] = []
		for id in ids:
			list_a.append(fa.find(id))
			list_b.append(fb.find(id))
		fa.remove_all(list_a, "unloaded", a.tick)
		for c in list_b:
			fb.remove(c, "unloaded", b.tick, false)
		check_eq(var_to_str(fa.events), var_to_str(fb.events), "%s: the same events" % round)
		check_eq(_field_state(fa), _field_state(fb), "%s: the same lists, token and brains" % round)
		check_eq(a.state_hash(), b.state_hash(), "%s: the same hash" % round)
		fa.events.clear()
		fb.events.clear()
	check(forgot >= 3, "brains left remembered the gone ones (%d)" % forgot)


## The field's lists, token and site index, and every brain's script variables (an RNG as its seed
## and state), by creature id.
static func _field_state(f: CreatureField) -> String:
	var brains := {}
	for c in f.creatures:
		var mem := {}
		if c.brain != null:
			for p in c.brain.get_property_list():
				if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
					var v: Variant = c.brain.get(p.name)
					mem[p.name] = [v.seed, v.state] if v is RandomNumberGenerator else v
		brains[c.id] = mem
	return var_to_str([f.creatures.map(func(c): return c.id), f.awake().map(func(c): return c.id), f.engaged_on_player,
		f._by_site.keys(), brains])


## PlanktonField keeps each zone's item count, its packed copies of the items' drift phases and
## rates and radii, and its id index as items come and go, so count_in and the tick's counts are what
## a count over the items gives, the drift reads each item's own values, packed_radii() what reading
## the items gives and find() what a scan finds: random meals, takes (the newest item goes), clears,
## drops, fills and active-zone changes, in the pool and in the endless world.
func test_plankton_zone_counts_follow_every_change() -> void:
	for endless in [false, true]:
		var region := layout.build_region(21)
		var arena := layout.build_arena()
		var field := PlanktonField.create(layout.plankton)
		var ids: Array = region.zones.map(func(z: Dictionary) -> String: return z.id)
		field.endless = endless
		if endless:
			field.active_zones = {ids[0]: true, ids[1]: true, ids[2]: true}
		field.fill(region, arena, 0, 0.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		var wrong := 0
		var unpacked := 0
		var unindexed := 0
		var gone: Array[String] = []
		for t in 1500:
			var roll := rng.randf()
			var zone_id: String = ids[rng.randi_range(0, ids.size() - 1)]
			if roll < 0.05 and not field.items.is_empty():
				var item: Dictionary = field.items[rng.randi_range(0, field.items.size() - 1)]
				region.take(item.zone, float(item.energy))
				field.consume(item.id)
				gone.append(item.id)
			elif roll < 0.10:
				region.take(zone_id, rng.randf_range(0.0, 40.0))
			elif roll < 0.11:
				field.clear_zone(zone_id)
			elif roll < 0.12:
				field.drop_zone(zone_id)
			elif roll < 0.13:
				field.fill_zone(region.zone(zone_id), region, arena, t, t * PoolSim.DT)
			elif roll < 0.14:
				field.item_radius = rng.randf_range(0.1, 0.3)   # new items differ, so a misplaced radius shows
			elif roll < 0.16 and endless:
				if field.active_zones.has(zone_id):
					field.drop_zone(zone_id)
					field.active_zones.erase(zone_id)
				else:
					field.active_zones[zone_id] = true
			region.tick(PoolSim.DT)
			field.tick(region, arena, t, t * PoolSim.DT)
			var counts := {}
			for item in field.items:
				counts[item.zone] = int(counts.get(item.zone, 0)) + 1
			for id in ids + ["no_such_zone"]:
				if field.count_in(id) != int(counts.get(id, 0)):
					wrong += 1
			if field._radii.size() != field.items.size():
				unpacked += 1   # packed_radii() would rebuild it: the bookkeeping missed a change
			var radii := field.packed_radii()
			for i in field.items.size():
				if field._phase[i] != field.items[i].phase or field._omega[i] != field.items[i].omega:
					unpacked += 1
				if radii[i] != field.items[i].radius:
					unpacked += 1
			if field._by_id.size() != field.items.size():
				unindexed += 1   # find() would rebuild it: the bookkeeping missed a change
			for item in field.items:
				if not is_same(field.find(item.id), item):
					unindexed += 1
			for id in gone:
				if not field.find(id).is_empty():
					unindexed += 1
		check_eq(wrong, 0, "endless %s: counts that differ from the items" % endless)
		check_eq(field._phase.size(), field.items.size(), "endless %s: one drift entry per item" % endless)
		check_eq(field._radii.size(), field.items.size(), "endless %s: one radius per item" % endless)
		check_eq(unpacked, 0, "endless %s: drift entries that differ from their item's" % endless)
		check_eq(unindexed, 0, "endless %s: id index entries that differ from the items" % endless)
		check(gone.size() > 20, "endless %s: items were eaten (%d)" % [endless, gone.size()])
		check(field.next_number > 40, "endless %s: items came and went (%d)" % [endless, field.next_number])


## A plankton list changed from outside the field (items appended or taken out directly) is taken in
## again by the next tick before any zone's count is read: the counts, packed copies and id index
## then follow the list, and the zones grow and shrink to their targets from the true counts.
func test_plankton_takes_in_a_list_changed_from_outside() -> void:
	var region := layout.build_region(22)
	var arena := layout.build_arena()
	var field := PlanktonField.create(layout.plankton)
	field.fill(region, arena, 0, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var wrong := 0
	var over := 0
	for t in range(1, 400):
		if t % 20 == 0 and field.items.size() > 2:
			if rng.randf() < 0.5:
				field.items.remove_at(rng.randi_range(0, field.items.size() - 1))
			else:
				var copy: Dictionary = field.items[rng.randi_range(0, field.items.size() - 1)].duplicate()
				copy.id = "pk_extra_%d" % t
				field.items.append(copy)
		region.tick(PoolSim.DT)
		field.tick(region, arena, t, t * PoolSim.DT)
		var counts := {}
		for item in field.items:
			counts[item.zone] = int(counts.get(item.zone, 0)) + 1
		for z in region.zones:
			if field.count_in(z.id) != int(counts.get(z.id, 0)):
				wrong += 1
			if int(counts.get(z.id, 0)) > field.target_count(z):
				over += 1
		if field._phase.size() != field.items.size() or field._by_id.size() != field.items.size():
			wrong += 1
	check_eq(wrong, 0, "ticks where the counts or packed copies differ from the list")
	check_eq(over, 0, "zones left above their target after a tick")


## perceive_food over the packed positions and radii finds the same food in the same order as over
## the dictionaries: random viewers among random items of both kinds, with items on the range edge
## (either side by a float32 step), on the field-of-view edge, at equal distances and on the viewer.
func test_packed_food_sense_matches_the_dictionary_one() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var differ := 0
	var found := 0
	for round in 300:
		# Every other round on whole numbers, where an item straight along an axis lies exactly at
		# sight + radius.
		var exact := round % 2 == 0
		var from := Vector2(rng.randi_range(-40, 40), rng.randi_range(-40, 40)) if exact \
			else Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-40.0, 40.0))
		var heading := rng.randf_range(-PI, PI)
		var viewer := {"id": "c_1", "species": "s", "position": from, "heading": heading, "radius": 0.5,
			"sight": float(rng.randi_range(3, 9)) if exact else rng.randf_range(3.0, 9.0),
			"fov": deg_to_rad(rng.randf_range(90.0, 300.0)), "near": 1.0}
		var items: Array = []
		for i in rng.randi_range(0, 60):
			var kind := "plant" if rng.randf() < 0.7 else "meat"
			var r := (0.25 if kind == "plant" else 0.5) if exact else (0.18 if kind == "plant" else 0.3)
			var p := from + Vector2.from_angle(rng.randf_range(-PI, PI)) * rng.randf_range(0.0, 14.0)
			match rng.randi_range(0, 5):
				0:   # on the range edge (straight along an axis), or a float32 step either side of it
					var edge := float(viewer.sight) + r
					if exact:
						p = from + [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN][rng.randi_range(0, 3)] * edge
					else:
						p = from + Vector2.from_angle(rng.randf_range(-PI, PI)) * edge * (1.0 + rng.randi_range(-1, 1) * 1.2e-7)
				1:   # on the field of view's edge
					p = from + Vector2.from_angle(heading + float(viewer.fov) / 2.0 * (1.0 if rng.randf() < 0.5 else -1.0)) * 2.0
				2:   # as far as an earlier item
					if not items.is_empty():
						var other: Dictionary = items[rng.randi_range(0, items.size() - 1)]
						p = from + (Vector2(other.position) - from).rotated(rng.randf_range(-0.5, 0.5))
				3:
					p = from
			items.append({"id": ("pk_%d" if kind == "plant" else "cr_%d") % i, "kind": kind, "position": p, "radius": r})
		var at := PackedVector2Array()
		var radii := PackedFloat64Array()
		for item in items:
			at.append(item.position)
			radii.append(item.radius)
		for kinds in [PackedStringArray(["plant"]), PackedStringArray(["meat"]), PackedStringArray(["plant", "meat"]), PackedStringArray()]:
			var want := CreatureSenses.perceive_food(viewer, items, kinds)
			var got := CreatureSenses.perceive_food_packed(viewer, items, at, radii, kinds)
			found += want.size()
			if var_to_str(got) != var_to_str(want):
				differ += 1
	check_eq(differ, 0, "rounds where the packed sense differs")
	check(found > 1000, "food was found (%d)" % found)


## CreatureBrain.next_deadline with its states reordered (the usual ones first) and its fields read
## once gives what the plain version below gives, for random memories in every state and phase.
func test_next_deadline_matches_the_plain_version() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var phases := ["", CreatureBrain.LURK, CreatureBrain.WATCH, CreatureBrain.PATROL, CreatureBrain.RETURN_HOME,
		CreatureBrain.SEEK, CreatureBrain.EAT, CreatureBrain.WAIT, CreatureBrain.PURSUE, CreatureBrain.AIM,
		CreatureBrain.TELL, CreatureBrain.STRIKE, CreatureBrain.GLIDE, CreatureBrain.RECOVER]
	var states := [CreatureBrain.REST, CreatureBrain.WANDER, CreatureBrain.FORAGE, CreatureBrain.NOTICE,
		CreatureBrain.CHASE, CreatureBrain.ATTACK, CreatureBrain.FLEE]
	var differ := 0
	for id in ["rammer", "ambush_hunter"]:
		var cfg := species.brain_config(id)
		for i in 2000:
			var mem := CreatureBrain.create(str(cfg.behavior), cfg.duplicate(true), Vector2.ZERO, 0.0, {}, i, 0)
			mem.cfg.forage_timeout_ticks = [0, 300][rng.randi_range(0, 1)]
			mem.state = states[rng.randi_range(0, states.size() - 1)]
			mem.phase = phases[rng.randi_range(0, phases.size() - 1)]
			mem.phase_tick = rng.randi_range(0, 500)
			mem.state_tick = rng.randi_range(0, 500)
			mem.goal_tick = rng.randi_range(0, 500)
			mem.rest_until = rng.randi_range(0, 900)
			mem.recover_ticks = rng.randi_range(0, 60)
			mem.engaged_tick = rng.randi_range(0, 500)
			mem.goal = Vector2(1.0, 2.0) if rng.randf() < 0.5 else Vector2.INF
			mem.target = "t" if rng.randf() < 0.7 else ""
			if rng.randf() < 0.5:
				mem.seen["t"] = {"tick": rng.randi_range(0, 500)}
			if rng.randf() < 0.5:
				mem.progress = {"position": Vector2.ZERO, "tick": rng.randi_range(0, 500)}
			if CreatureBrain.next_deadline(mem) != _plain_next_deadline(mem):
				differ += 1
	check_eq(differ, 0, "memories whose deadline differs")


## next_deadline as it was before it was reordered.
static func _plain_next_deadline(mem: CreatureBrain.Memory) -> int:
	var due := CreatureBrain.NEVER
	match mem.state:
		CreatureBrain.NOTICE:
			if mem.phase != CreatureBrain.WAIT:
				due = mem.phase_tick + int(mem.cfg.notice_ticks)
			due = mini(due, _plain_give_up_deadline(mem))
		CreatureBrain.CHASE:
			due = _plain_give_up_deadline(mem)
			if mem.phase == CreatureBrain.PURSUE and not mem.progress.is_empty():
				due = mini(due, int(mem.progress.tick) + int(mem.cfg.unreachable_ticks))
		CreatureBrain.ATTACK:
			if mem.phase == CreatureBrain.RECOVER:
				due = mem.phase_tick + mem.recover_ticks
		CreatureBrain.FLEE:
			due = mem.state_tick + int(mem.cfg.flee_ticks)
		CreatureBrain.REST:
			if mem.phase == CreatureBrain.WATCH and mem.seen.has(mem.target):
				due = int(mem.seen[mem.target].tick) + int(mem.cfg.memory_ticks)
			elif mem.behavior == CreatureBrain.TERRITORIAL:
				due = mem.rest_until
		CreatureBrain.WANDER, CreatureBrain.FORAGE:
			if mem.phase == CreatureBrain.RETURN_HOME:
				due = mem.phase_tick + int(mem.cfg.nav_timeout_ticks)
			elif mem.goal.is_finite() and mem.phase != CreatureBrain.EAT:
				due = mem.goal_tick + int(mem.cfg.nav_timeout_ticks)
			if mem.phase == CreatureBrain.SEEK and int(mem.cfg.forage_timeout_ticks) > 0:
				due = mini(due, mem.phase_tick + int(mem.cfg.forage_timeout_ticks))
			if not mem.progress.is_empty() and mem.phase != CreatureBrain.EAT:
				due = mini(due, int(mem.progress.tick) + int(mem.cfg.unreachable_ticks))
	return due


static func _plain_give_up_deadline(mem: CreatureBrain.Memory) -> int:
	var due := mem.engaged_tick + int(mem.cfg.give_up_ticks)
	if mem.seen.has(mem.target):
		due = mini(due, int(mem.seen[mem.target].tick) + int(mem.cfg.memory_ticks))
	return due


## perceive_bodies over a Bodies snapshot gives what perceive gives over the same bodies as
## dictionaries, for random viewers among bodies on the range edges, dead, concealed, the viewer
## itself and bodies as far as another.
func test_packed_body_sense_matches_the_dictionary_one() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var differ := 0
	var found := 0
	for round in 400:
		var exact := round % 2 == 0
		var from := Vector2(rng.randi_range(-40, 40), rng.randi_range(-40, 40)) if exact \
			else Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-40.0, 40.0))
		var heading := rng.randf_range(-PI, PI)
		var viewer := {"id": "c_1", "species": "s", "position": from, "heading": heading, "radius": 0.5,
			"sight": float(rng.randi_range(3, 9)) if exact else rng.randf_range(3.0, 9.0),
			"fov": deg_to_rad(rng.randf_range(90.0, 300.0)), "near": float(rng.randi_range(0, 2))}
		var bodies: Array[Dictionary] = []
		for i in rng.randi_range(0, 24):
			var r := float(rng.randi_range(1, 4)) / 4.0 if exact else rng.randf_range(0.2, 1.2)
			var p := from + Vector2.from_angle(rng.randf_range(-PI, PI)) * rng.randf_range(0.0, 14.0)
			match rng.randi_range(0, 6):
				0:   # on the sight edge, or a float32 step either side of it
					var edge := float(viewer.sight) + r
					if exact:
						p = from + [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN][rng.randi_range(0, 3)] * edge
					else:
						p = from + Vector2.from_angle(rng.randf_range(-PI, PI)) * edge * (1.0 + rng.randi_range(-1, 1) * 1.2e-7)
				1:   # on the near edge
					var edge := float(viewer.radius) + r + float(viewer.near)
					p = from + [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN][rng.randi_range(0, 3)] * edge
				2:   # on the field of view's edge
					p = from + Vector2.from_angle(heading + float(viewer.fov) / 2.0 * (1.0 if rng.randf() < 0.5 else -1.0)) * 2.0
				3:   # as far as an earlier body
					if not bodies.is_empty():
						var other: Dictionary = bodies[rng.randi_range(0, bodies.size() - 1)]
						p = from + (Vector2(other.position) - from).rotated(rng.randf_range(-0.5, 0.5))
				4:
					p = from
			var id := "c_1" if rng.randf() < 0.05 else ("player" if i == 0 else "c_%d" % (i + 2))
			bodies.append({"id": id, "species": "sp%d" % rng.randi_range(0, 2), "position": p,
				"velocity": Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0)), "radius": r,
				"alive": rng.randf() < 0.9, "concealed": rng.randf() < 0.1, "engageable": rng.randf() < 0.8,
				"bite": rng.randf() < 0.5, "spikes": rng.randi_range(0, 3)})
		var snap := CreatureSenses.Bodies.new()
		for body in bodies:
			snap.info.append(body)
			snap.at.append(body.position)
			snap.velocity.append(body.velocity)
			snap.radius.append(body.radius)
			snap.alive.append(1 if bool(body.alive) else 0)
		var want := CreatureSenses.perceive(viewer, bodies, null)
		var got := CreatureSenses.perceive_bodies(viewer, snap, null)
		found += want.size()
		if var_to_str(got) != var_to_str(want):
			differ += 1
	check_eq(differ, 0, "rounds where the packed sense differs")
	check(found > 500, "bodies were sensed (%d)" % found)


## CreatureField.body_snapshot holds what bodies() gives, column by column, and every awake creature
## perceives the same through either with the arena's line of sight: on the saturated world swum
## through overdriven (creatures spawn, sleep, wake and go), then with the hunter seen.
func test_the_body_snapshot_holds_what_bodies_gives() -> void:
	var cost: GDScript = load(COST)
	var content: Variant = (load(FAKE_GEN) as GDScript).call("fixture_content")
	var r := Lineage.found(2802, Gates.BUILD_ID, catalog, "hunter")
	Gates.make_racer(r.save.genome, catalog)
	r.save.player["position"] = PlaneSpace.to_save_abs(0.0, 16.0)
	var sim := PoolSim._create_endless(r.save, catalog, layout, species, content, cost.DenseGen.new(content, species, 2802))
	sim.debug_set_hidden(true)
	sim.drain_events()
	var f := sim.creatures
	var bot = SwimBot.new(Vector2.RIGHT)
	var wrong := 0
	var differ := 0
	var sensed := 0
	for t in 1500:
		if t == 900:
			sim.debug_set_hidden(false)
		SwimBot.overdrive(sim)
		sim.step(bot.next_intent(sim))
		sim.drain_events()
		if t % 5 != 0:
			continue
		var player := sim.player_body()
		var list := f.bodies(player)
		var snap := f.body_snapshot(player)
		if snap.info.size() != list.size() or snap.at.size() != list.size() or snap.velocity.size() != list.size() \
				or snap.radius.size() != list.size() or snap.alive.size() != list.size():
			wrong += 1
			continue
		for i in list.size():
			var body := list[i]
			var info := snap.info[i]
			for key in ["id", "species", "concealed", "engageable", "bite", "spikes"]:
				if info[key] != body[key]:
					wrong += 1
			if snap.at[i] != body.position or snap.velocity[i] != body.velocity or snap.radius[i] != body.radius \
					or snap.alive[i] != (1 if bool(body.alive) else 0):
				wrong += 1
		for c in f.awake():
			var viewer := f.viewer_of(c)
			var want := CreatureSenses.perceive(viewer, list, sim.arena)
			sensed += want.size()
			if var_to_str(CreatureSenses.perceive_bodies(viewer, snap, sim.arena)) != var_to_str(want):
				differ += 1
	check_eq(wrong, 0, "snapshot values that differ from bodies()")
	check_eq(differ, 0, "creatures that perceive differently through the snapshot")
	check(sensed > 200, "bodies were sensed (%d)" % sensed)


## take_events skips its scan while no brain has emitted since the last one, and a creature that woke
## holding events (given while it slept, after the scan that skipped it) still has them taken by the
## next take_events, as the plain scan of the awake list takes them.
func test_a_woken_creatures_held_events_come_out_next() -> void:
	var sim := _forager(5103)
	check(sim.debug_spawn_creature("rammer", Vector2(-30.0, -30.0), 0.0), "a rammer")
	var field := sim.creatures
	var b: CreatureField.Creature = field.creatures[field.creatures.size() - 1]
	field.sleep(b, sim.tick)
	sim.step(SimIntent.new())
	sim.drain_events()
	check(b.asleep and b.brain.events.is_empty(), "asleep, its brain holding nothing")
	CreatureBrain._notice(b.brain, CreatureField.PLAYER_ID, "sight", sim.tick)   # no hook: no full scan
	field.take_events()
	check_eq(b.brain.events.size(), 1, "a sleeper's event waits while the awake are scanned")
	check(field.take_events().is_empty(), "nothing emitted since: nothing taken")
	field.wake(b, sim.tick)
	var noticed := []
	for e in field.take_events():
		if e.type == "creature_noticed":
			noticed.append(e.id)
	check_eq(noticed, [b.id], "woken: its held event comes out with the next events")
	check(b.brain.events.is_empty(), "its brain holds nothing")


## The usual drive written out in PoolSim._creatures_act, a forager's seek from the body's own values
## (CreatureBrain.seek_from), gives what drive gives with the self view: every awake forager seeking
## its goal on the saturated world swum through overdriven.
func test_the_view_free_seek_matches_drive() -> void:
	var cost: GDScript = load(COST)
	var content: Variant = (load(FAKE_GEN) as GDScript).call("fixture_content")
	var r := Lineage.found(2802, Gates.BUILD_ID, catalog, "hunter")
	Gates.make_racer(r.save.genome, catalog)
	r.save.player["position"] = PlaneSpace.to_save_abs(0.0, 16.0)
	var sim := PoolSim._create_endless(r.save, catalog, layout, species, content, cost.DenseGen.new(content, species, 2802))
	sim.debug_set_hidden(true)
	sim.drain_events()
	var f := sim.creatures
	var bot = SwimBot.new(Vector2.RIGHT)
	var differ := 0
	var seeking := 0
	for t in 900:
		SwimBot.overdrive(sim)
		sim.step(bot.next_intent(sim))
		sim.drain_events()
		for c in f.awake():
			var b := c.brain
			if b == null or b.state != CreatureBrain.FORAGE or b.phase == CreatureBrain.EAT or not b.goal.is_finite():
				continue
			seeking += 1
			var p := c.phenotype
			var want := CreatureBrain.drive(b, f.self_view_of(c), sim.tick, sim.arena)
			var got := CreatureBrain.seek_from(b, c.motion.position, p.radius, p.speed, p.acceleration, b.goal,
				float(b.cfg.speeds.forage), sim.arena, true)
			if var_to_str(got) != var_to_str(want):
				differ += 1
	check_eq(differ, 0, "foragers whose view-free seek differs from drive")
	check(seeking > 2000, "foragers seeking (%d)" % seeking)


## A forager's seek routes past the colliders kept for it (ChunkArena.route_point_kept): on the
## saturated world, through two rebases and a teleport, a twin whose creatures drop their keeps
## before every step drives every creature the same on every tick, to the same hash. Keeps hold
## through a rebase (the stream's own and the debug ones): a forager seeking before and after a step
## that rebased keeps its pick (one picked again has a new key).
func test_a_forager_seeks_the_same_with_its_route_kept_or_picked_every_tick() -> void:
	var sims: Array[PoolSim] = []
	for i in 2:
		var cost: GDScript = load(COST)
		var content: Variant = (load(FAKE_GEN) as GDScript).call("fixture_content")
		var r := Lineage.found(2802, Gates.BUILD_ID, catalog, "hunter")
		Gates.make_racer(r.save.genome, catalog)
		r.save.player["position"] = PlaneSpace.to_save_abs(0.0, 16.0)
		var sim := PoolSim._create_endless(r.save, catalog, layout, species, content, cost.DenseGen.new(content, species, 2802))
		sim.debug_set_hidden(true)
		sim.drain_events()
		sims.append(sim)
	var a := sims[0]
	var b := sims[1]
	var bot = SwimBot.new(Vector2.RIGHT)
	var held := 0
	var held_rebased := 0   # foragers seeking on both sides of a step that rebased, with their keeps held
	var keys := {}
	for t in 1500:
		var seeking := {}
		for c in a.creatures.awake():
			if c.route_keep != null and _seeking(c):
				seeking[c] = c.route_keep.key
		if t == 400 or t == 800:
			a.debug_rebase(Vector2i(-1, 1))
			b.debug_rebase(Vector2i(-1, 1))
		elif t == 1100:
			a.debug_teleport(a.motion.position + Vector2(-20.0, 8.0))
			b.debug_teleport(b.motion.position + Vector2(-20.0, 8.0))
		for c in b.creatures.creatures:
			c.route_keep = null
		SwimBot.overdrive(a)
		SwimBot.overdrive(b)
		var intent = bot.next_intent(a)
		a.step(intent)
		b.step(intent)
		var drives_a := []
		var drives_b := []
		var events: Array = a.drain_events()
		for e in events:
			if e.type == "rebased":
				for c in seeking:
					held_rebased += 1 if _seeking(c) and c.route_keep.key == seeking[c] else 0
				break
		for c in a.creatures.awake():
			drives_a.append(c.drive)
			if c.route_keep != null:
				if keys.get(c.id) == c.route_keep.key:
					held += 1
				keys[c.id] = c.route_keep.key
		for c in b.creatures.awake():
			drives_b.append(c.drive)
		if var_to_str(drives_a) != var_to_str(drives_b) or var_to_str(events) != var_to_str(b.drain_events()):
			check(false, "tick %d: the twins' drives or events differ" % t)
			return
		if t % 60 == 59 and a.state_hash() != b.state_hash():
			check(false, "tick %d: the hashes differ" % t)
			return
	check_eq(a.state_hash(), b.state_hash(), "the same end")
	check(held > 5000, "keeps held from tick to tick (%d)" % held)
	check(held_rebased >= 5, "keeps held through rebases (%d)" % held_rebased)
	print("test-perf-sim-caches: kept routes held %d times from tick to tick, %d through a rebase" % [held, held_rebased])


## Whether the creature's drive seeks its goal along a kept route (PoolSim's usual drive for a forager).
static func _seeking(c: CreatureField.Creature) -> bool:
	var b := c.brain
	return b != null and b.state == CreatureBrain.FORAGE and b.phase != CreatureBrain.EAT and b.goal.is_finite()


## The tick's leash clamp (CreatureBrain.leash_disc written out in PoolSim._contacts) is the brain's
## leash disc: with the brains frozen, a hunter and a rammer put 0.5 tm inside their discs stay there,
## and put 1 tm past them come back to the edge.
func test_the_ticks_leash_clamp_is_the_brains_leash_disc() -> void:
	var sim := _forager(5104)
	check(sim.debug_set_ai_frozen(true), "the brains are frozen")
	check(sim.debug_spawn_creature("ambush_hunter", Vector2(30.0, -30.0), 0.0), "a hunter")
	check(sim.debug_spawn_creature("rammer", Vector2(-30.0, -30.0), 0.0), "a rammer")
	var field := sim.creatures
	for c in [field.creatures[field.creatures.size() - 2], field.creatures[field.creatures.size() - 1]]:
		var disc := CreatureBrain.leash_disc(c.brain)
		var center: Vector2 = disc.center
		var radius: float = disc.radius
		var dir := Vector2.ZERO
		for k in 8:
			var d := Vector2.from_angle(k * PI / 4.0)
			if sim.arena.is_clear(center + d * (radius - 0.5), c.phenotype.radius) \
					and sim.arena.is_clear(center + d * (radius + 1.0), c.phenotype.radius):
				dir = d
				break
		check(dir != Vector2.ZERO, "%s: clear water at its leash's edge" % c.species_id)
		for out in [-0.5, 1.0]:
			c.motion.position = center + dir * (radius + out)
			c.motion.velocity = Vector2.ZERO
			sim.step(SimIntent.new())
			check(absf(c.motion.position.distance_to(center) - minf(radius + out, radius)) < 1e-3,
				"%s put %.1f tm off its leash's edge ends %.3f tm from the centre (leash %.3f)" % [
					c.species_id, out, c.motion.position.distance_to(center), radius])
