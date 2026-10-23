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
