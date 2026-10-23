extends TestCase
## CreatureField (M1 step 3): creatures appear only at their own sites, far from the player and out
## of view; deaths free the niche and requeue the site after its respawn time; kills drop carcasses
## clear of rocks; stuck creatures vanish only where nobody sees; debug spawns stay outside the
## niches; new creatures settle before noticing anything; and only one creature at a time may engage
## the player (the token).

const THREATS_FIXTURE := "res://tests/fixtures/pool_test_threats.json"
const TEST_SPECIES := "res://tests/fixtures/creatures_test.json"
const SEED := 77
## Real sites in data order, as populate() numbers them.
const SITE_ORDER := ["lair_se", "lair_sw", "lair_s", "terr_n_a", "terr_n_b", "terr_nw", "terr_ne"]
## 20.5 m west of lair_se, which the widest view still shows.
const BESIDE_LAIR_SE := Vector2(5.9, 12.6)
## 13.6 m north of lair_se, out of its view but under 20 m.
const NORTH_OF_LAIR_SE := Vector2(26.4, -1.0)

var parts: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog


func before_each() -> void:
	parts = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()


func _field(seed_value: int = SEED, p_species: SpeciesCatalog = null, p_layout: PoolLayout = null) -> CreatureField:
	var use := p_layout if p_layout != null else layout
	return CreatureField.create(p_species if p_species != null else species, parts, use, use.build_region(1), seed_value)


## The player in the senses' body format: a hunter-sized cell at rest.
func _player(at: Vector2) -> Dictionary:
	return {"id": "player", "species": SpeciesCatalog.PLAYER_SPECIES, "position": at, "velocity": Vector2.ZERO,
		"radius": PoolLayout.CELL_RADIUS, "alive": true, "concealed": false, "engageable": true, "bite": true, "spikes": 0}


func _of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _site_ids(field: CreatureField) -> Array:
	var out := []
	for c in field.creatures:
		out.append(c.site_id)
	return out


## Runs every creature's think (when due) and drive for ticks [from, to), bodies held still, and
## returns the events with the tick they came on. `each` is called after every tick.
func _run(field: CreatureField, arena: PoolArena, player_at: Vector2, from: int, to: int, each: Callable = Callable()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tick in range(from, to):
		var snapshot := field.bodies(_player(player_at))
		for c in field.creatures:
			if field.think_due(c, tick):
				field.think(c, snapshot, [], arena, tick)
			field.drive(c, arena, tick)
		for e in field.take_events():
			e["tick"] = tick
			out.append(e)
		if each.is_valid():
			each.call(tick)
	return out


func test_a_new_world_fills_every_site_in_data_order_and_both_niches() -> void:
	var field := _field()
	var arena := layout.build_arena()
	field.populate(arena, layout.spawn, 0)
	check_eq(field.creatures.size(), 7, "seven creatures")
	check_eq(_site_ids(field), SITE_ORDER, "one per site, in data order")
	for i in field.creatures.size():
		var c: CreatureField.Creature = field.creatures[i]
		var s := species.site(c.site_id)
		check_eq(c.id, "c_%d" % (i + 1), "%s id" % c.site_id)
		check_eq(c.motion.position, s.home, "%s at its home" % c.id)
		check_eq(c.motion.heading, float(s.heading), "%s facing its heading" % c.id)
		check_eq(c.species_id, s.species, "%s species" % c.id)
		check_near(c.state.energy / c.state.energy_capacity, float(species.species[c.species_id].start_energy_share), 1e-9,
			"%s starts at its species' energy share" % c.id)
		check_eq(c.brain.ignore_all_until, 180, "%s settles for 3 s" % c.id)
		check_eq(c.brain.rng.seed, SEED * CreatureField.BRAIN_SEED_STRIDE + c.number, "%s has its own brain seed" % c.id)
		check_eq(c.brain.state, "rest", "%s rests" % c.id)
	check_eq(field.region.niches, {"ambush": {"cap": 3, "count": 3}, "territorial": {"cap": 4, "count": 4}}, "both niches full")
	check(field.queue.is_empty(), "nothing waits")
	check_eq(_of(field.take_events(), "creature_spawned").size(), 7, "seven creature_spawned events")
	var rammer := field.find("c_6")
	check_eq(rammer.brain.territory_center, Vector2(-19.1, -11.0), "terr_nw's rammer guards z_nw")
	check_near(rammer.brain.territory_r, 8.0, 1e-9, "its zone plus the 2 m margin")
	check(field.find("c_8") == null, "no eighth creature")


func test_a_site_near_the_player_or_in_view_waits_for_the_first_retry_after_the_player_leaves() -> void:
	var field := _field()
	var arena := layout.build_arena()
	var lair: Dictionary = species.site("lair_se")
	field.populate(arena, lair.home, 0)
	check_eq(field.creatures.size(), 6, "the other six spawn")
	check(not _site_ids(field).has("lair_se"), "not the one the player is at")
	check_eq(field.queue, [{"site": "lair_se", "species": "ambush_hunter", "at_tick": 60}], "it waits 1 s")
	check_eq(field.spawn_blocker(lair, arena, lair.home), "near the player", "the 20 m rule")
	check_eq(field.spawn_blocker(lair, arena, NORTH_OF_LAIR_SE), "near the player", "13.6 m away, out of view, is still too near")
	check_eq(field.spawn_blocker(lair, arena, BESIDE_LAIR_SE), "in view", "20.5 m away but on screen at the widest zoom")
	check_eq(field.spawn_blocker(lair, arena, layout.spawn), "", "from the checkpoint it may spawn")
	var on_rock := {"id": "on_rock", "species": "ambush_hunter", "home": layout.rocks[16].center, "heading": 0.0}
	check_eq(field.spawn_blocker(on_rock, arena, layout.spawn), "not clear", "never on a rock (%s)" % layout.rocks[16].id)
	var squatter := field.spawn_at("rammer", lair.home + Vector2(1.5, 0.0), 0.0, "", 0, true)
	check_eq(field.spawn_blocker(lair, arena, layout.spawn), "occupied", "never onto another creature")
	field.remove(squatter, "test", 0, false)
	var player := [lair.home]
	var moves := {100: NORTH_OF_LAIR_SE, 150: BESIDE_LAIR_SE, 200: layout.spawn}
	var born := -1
	for tick in range(1, 400):
		if moves.has(tick):
			player[0] = moves[tick]
		field.tick_spawns(arena, player[0], tick)
		if born < 0 and _site_ids(field).has("lair_se"):
			born = tick
	check_eq(born, 240, "it spawns at the first retry (60, 120, 180 refused; 240 after the move at 200)")
	var c: CreatureField.Creature = field.creatures[-1]
	check_eq(c.site_id, "lair_se", "at lair_se")
	check_eq(c.motion.position, lair.home, "at its home")
	check_eq(c.born_tick, 240, "born then")
	check(field.queue.is_empty(), "nothing waits after")


func test_a_death_frees_the_niche_and_requeues_the_site_after_its_respawn_time() -> void:
	var delays := {"ambush_hunter": [], "rammer": []}
	for seed_value in range(1, 21):
		var field := _field(seed_value)
		var arena := layout.build_arena()
		field.populate(arena, layout.spawn, 0)
		var at := 1000
		for c in field.creatures.duplicate():
			field.remove(c, "killed", at, true)
		check(field.creatures.is_empty(), "seed %d: all removed" % seed_value)
		check_eq(field.region.niches.ambush.count, 0, "seed %d: the ambush niche is empty" % seed_value)
		check_eq(field.region.niches.territorial.count, 0, "seed %d: the territorial niche is empty" % seed_value)
		check_eq(field.queue.size(), 7, "seed %d: every site waits" % seed_value)
		for i in field.queue.size():
			var entry: Dictionary = field.queue[i]
			delays[entry.species].append(int(entry.at_tick) - at)
			if i > 0:
				var prev: Dictionary = field.queue[i - 1]
				check(prev.at_tick < entry.at_tick or (prev.at_tick == entry.at_tick and prev.site < entry.site),
					"seed %d: the queue is sorted by tick, then site" % seed_value)
		var removed := _of(field.take_events(), "creature_removed")
		check_eq(removed.size(), 7, "seed %d: seven creature_removed" % seed_value)
	for d in delays.ambush_hunter:
		check(d >= 50 * 60 and d <= 70 * 60, "an ambush hunter respawns 60 +/- 10 s later (%d ticks)" % d)
	for d in delays.rammer:
		check(d >= 24 * 60 and d <= 36 * 60, "a rammer respawns 30 +/- 6 s later (%d ticks)" % d)
	check(delays.rammer.min() < 28 * 60 and delays.rammer.max() > 32 * 60, "the jitter spreads them %s" % [[delays.rammer.min(), delays.rammer.max()]])

	var field := _field()
	var arena := layout.build_arena()
	field.populate(arena, layout.spawn, 0)
	var rammer := field.find("c_4")
	var neighbour := field.find("c_5")
	neighbour.brain.seen[rammer.id] = {"position": rammer.motion.position, "velocity": Vector2.ZERO, "tick": 5, "by": "sight",
		"species": "rammer", "radius": rammer.phenotype.radius, "engageable": true}
	field.remove(rammer, "killed", 10, true)
	check(not neighbour.brain.seen.has(rammer.id), "a brain that remembered it forgets it")
	var due: int = field.queue[0].at_tick
	field.tick_spawns(arena, layout.spawn, due - 1)
	check_eq(field.creatures.size(), 6, "not back before its time")
	field.tick_spawns(arena, layout.spawn, due)
	var back := field.find("c_8")
	check(back != null and back.site_id == "terr_n_a", "back at terr_n_a on time, as c_8")
	check_eq(field.region.niches.territorial.count, 4, "the niche is full again")


func test_a_carcass_lands_clear_of_rocks_even_beside_one() -> void:
	var fixture := PoolLayout.load_from(THREATS_FIXTURE)
	var test_species := SpeciesCatalog.load_from(TEST_SPECIES)
	var field := _field(SEED, test_species, fixture)
	var arena := fixture.build_arena()
	var carrion := CarrionField.create(fixture.carrion, 5)
	# A rammer pressed against wall_3 (center (0, 8), radius 1.25), facing it: the chunk ahead fits
	# neither 0.45 m nor 0.9 m out, so it lands at the body's center.
	var rammer := field.spawn_at("rammer", Vector2(0.0, 8.0 - 1.25 - 0.625 - 0.01), PI / 2.0)
	var points := field.carcass_points(rammer, arena, carrion.item_radius)
	check_eq(points.size(), 3, "a rammer leaves 3 chunks")
	check_eq(points[0], rammer.motion.position, "the chunk facing the rock falls back to the center")
	check_near(points[1].distance_to(rammer.motion.position), 0.45, 1e-5, "the others land 0.45 m out")
	var ids := field.drop_carcass(rammer, carrion, arena)
	check_eq(ids.size(), 3, "three carrion items")
	for item in carrion.items:
		check(arena.is_clear(item.position, item.radius), "%s is clear of rocks" % item.id)
		check_eq(item.source, "kill", "source")
		check_near(item.energy, 24.0, 1e-9, "24 energy")
		check_eq(item.points, 3, "3 points")
	var ambush := field.spawn_at("ambush_hunter", Vector2(-10.0, -10.0), 0.3)
	var four := field.carcass_points(ambush, arena, carrion.item_radius)
	check_eq(four.size(), 4, "an ambush hunter leaves 4 chunks")
	for i in four.size():
		var expected: Vector2 = ambush.motion.position + Vector2.from_angle(0.3 + i * TAU / 4.0) * 0.45
		check(four[i].distance_to(expected) < 1e-5, "chunk %d at its quarter turn, 0.45 m out" % i)
	var spawned := _of(carrion.events, "carrion_spawned")
	check_eq(spawned.size(), 3, "carrion_spawned for each chunk")


func test_a_stuck_creature_is_removed_and_requeued_only_where_the_player_cannot_see() -> void:
	var field := _field()
	var arena := layout.build_arena()
	field.populate(arena, layout.spawn, 0)
	field.take_events()
	var c := field.find("c_1")
	c.brain.stuck = true
	var margin: float = float(layout.camera.look_ahead_max) + float(species.fairness.spawn_view_margin_m) + c.phenotype.radius
	check(not ViewFootprint.contains(NORTH_OF_LAIR_SE, c.motion.position, layout.camera, float(layout.camera.zoom_max),
		float(species.fairness.spawn_view_aspect), margin), "13.6 m north of lair_se it is out of view")
	field.remove_stuck(NORTH_OF_LAIR_SE, 50)
	check(field.find("c_1") != null, "kept while the player is within 20 m, even out of view")
	field.remove_stuck(BESIDE_LAIR_SE, 51)
	check(field.find("c_1") != null, "kept while the player could see it")
	field.remove_stuck(layout.spawn, 52)
	check(field.find("c_1") == null, "removed once the player is far and it is out of view")
	var removed := _of(field.take_events(), "creature_removed")
	check_eq(removed.size(), 1, "one creature_removed")
	if removed.size() == 1:
		check_eq(removed[0].reason, "stuck", "reason stuck")
	check_eq(field.queue, [{"site": "lair_se", "species": "ambush_hunter", "at_tick": 112}], "its site waits 1 s")
	check_eq(field.region.niches.ambush.count, 2, "its niche slot is free meanwhile")
	field.tick_spawns(arena, layout.spawn, 112)
	var back := field.find("c_8")
	check(back != null and back.site_id == "lair_se" and not back.brain.stuck, "a fresh creature at lair_se")
	var lost := field.spawn_at("rammer", Vector2(0.0, -30.0), 0.0, "", 200, true)
	lost.brain.stuck = true
	field.remove_stuck(layout.spawn, 200)
	check(field.find(lost.id) == null, "a stuck debug creature is removed too")
	check(field.queue.is_empty(), "but never requeued")


func test_debug_spawns_bypass_the_niche_cap_are_not_counted_and_never_respawn() -> void:
	var field := _field()
	var arena := layout.build_arena()
	field.populate(arena, layout.spawn, 0)
	check(field.spawn_at("rammer", Vector2(0.0, 0.0), 0.0, "", 5) == null, "a counted spawn into a full niche is refused")
	var extra := field.spawn_at("rammer", Vector2(0.0, 0.0), 0.0, "", 5, true)
	check(extra != null and extra.debug, "a debug spawn is placed anyway")
	check_eq(field.region.niches.territorial.count, 4, "and not counted")
	field.remove(extra, "killed", 10, true)
	check_eq(field.region.niches.territorial.count, 4, "its death frees nothing")
	check(field.queue.is_empty(), "and queues nothing")
	check(field.spawn_at("kraken", Vector2.ZERO, 0.0, "", 5, true) == null, "an unknown species is refused")


func test_a_new_creature_notices_nothing_while_it_settles_then_notices_prey_in_view_all_along() -> void:
	var fixture := PoolLayout.load_from(THREATS_FIXTURE)
	var field := _field(SEED, SpeciesCatalog.load_from(TEST_SPECIES), fixture)
	var arena := fixture.build_arena()
	var c := field.spawn_at("ambush_hunter", Vector2(0.0, -10.0), 0.0)
	var events := _run(field, arena, Vector2(2.75, -10.0), 0, 240)
	var noticed := _of(events, "creature_noticed")
	check_eq(noticed.size(), 1, "it notices once")
	if noticed.size() == 1:
		check(noticed[0].tick >= 180 and noticed[0].tick < 186, "after the 180-tick settle, on its next think (tick %d)" % noticed[0].tick)
		check_eq(noticed[0].target, "player", "the player")
		check_eq(noticed[0].by, "sight", "by sight")
		check_eq(noticed[0].id, c.id, "tagged with the creature's id")


func test_only_one_creature_at_a_time_holds_the_token_on_the_player() -> void:
	var fixture := PoolLayout.load_from(THREATS_FIXTURE)
	var field := _field(SEED, SpeciesCatalog.load_from(TEST_SPECIES), fixture)
	var arena := fixture.build_arena()
	var player_at := Vector2(0.0, -14.0)
	var hunters: Array[CreatureField.Creature] = []
	for x in [-4.0, 4.0]:
		var at := Vector2(x, -18.0)
		var h := field.spawn_at("ambush_hunter", at, (player_at - at).angle())
		h.state.energy = h.state.energy_capacity * 0.3   # hungry: it wants to chase
		h.brain.ignore_all_until = 0
		hunters.append(h)
	var holders := []
	var most := [0]
	var other_engaged := [0]
	var other_states := {}
	var watch := func(_tick: int) -> void:
		most[0] = maxi(most[0], field.engaged_on_player.size())
		for id in field.engaged_on_player:
			if not holders.has(id):
				holders.append(id)
		if field.engaged_on_player.size() == 1:
			for h in hunters:
				if h.id == field.engaged_on_player[0]:
					continue
				if CreatureBrain.is_engaged_with(h.brain, "player"):
					other_engaged[0] += 1
				other_states["%s/%s" % [h.brain.state, h.brain.phase]] = true
	_run(field, arena, player_at, 0, 900, watch)
	check_eq(most[0], 1, "never more than one engaged with the player")
	check_eq(other_engaged[0], 0, "the other one never engaged while the token was taken")
	check(other_states.has("rest/watch"), "it watched instead (%s)" % [other_states.keys()])
	check_eq(holders.size(), 2, "the token passed from one to the other once the first gave up (%s)" % [holders])
	check(field.engaged_on_player.size() <= 1, "and the list ends within the limit")


func test_a_hunter_that_lost_sight_of_the_cell_while_another_took_the_token_does_not_chase_it() -> void:
	# F4 regression, in the running sim: two hungry hunters either side of the cell, which swims east
	# at 0.6. The west hunter last sees the cell while the token is free, the east one takes the token,
	# and the west one's notice ends with the cell just out of its sight. It decides on the token as it
	# is now, not as it was when it last saw the cell: no second creature enters a chase on the cell,
	# not even for the one think the token's backstop would undo.
	var fixture := PoolLayout.load_from(THREATS_FIXTURE)
	var r := Lineage.found(31, "test+dev", parts, "hunter")
	r.save.player["position"] = PlaneSpace.to_save(fixture.spawn)
	var sim := PoolSim.create(r.save, parts, fixture, SpeciesCatalog.load_from(TEST_SPECIES))
	sim.grace_until = sim.tick
	check(sim.debug_teleport(Vector2(1.0, -16.0), 0.0), "the cell placed between them")
	for at in [Vector2(-5.0, -16.0), Vector2(5.0, -16.0)]:
		var h := sim.creatures.spawn_at("ambush_hunter", at, 0.0 if at.x < 0.0 else PI, "", sim.tick, true)
		h.brain.ignore_all_until = 0
		h.brain.trace = true   # every state change is an event, so a chase undone in the same tick still shows
		h.state.energy = h.state.energy_capacity * 0.3   # hungry: each wants to chase
	sim.drain_events()
	var most := int(sim.species.fairness.max_engaged_on_player)
	var bad := ""
	var noticed := {}
	var chased := {}
	for i in 600:
		var t := sim.tick
		sim.step(SimIntent.new(Vector2.RIGHT * 0.6))
		var token := sim.creatures.engaged_on_player
		for e in sim.drain_events():
			if e.type == "creature_noticed" and e.target == CreatureField.PLAYER_ID:
				noticed[e.id] = true
			if e.type == "creature_state" and str(e.to).begins_with("chase/"):
				chased[e.id] = true
				if not token.has(e.id) and bad.is_empty():
					bad = "tick %d: %s went into %s without the token (%s)" % [t, e.id, e.to, token]
		for c in sim.creatures.creatures:
			if CreatureBrain.is_engaged_with(c.brain, CreatureField.PLAYER_ID) and not token.has(c.id) and bad.is_empty():
				bad = "tick %d: %s is engaged with the cell outside the token (%s)" % [t, c.id, token]
		if token.size() > most and bad.is_empty():
			bad = "tick %d: %d creatures hold the token (%s)" % [t, token.size(), token]
	check(bad.is_empty(), bad)
	check_eq(noticed.size(), 2, "both hunters noticed the cell (%s)" % [noticed.keys()])
	check(not chased.is_empty(), "one of them chased it (%s)" % [chased.keys()])


func test_the_token_never_grows_past_its_limit_and_a_brain_refused_it_stands_down() -> void:
	# The backstop behind the refreshed flag: a brain that enters a chase on the player while the
	# token is full (here forced from outside) is not added to the list; it drops the chase.
	var fixture := PoolLayout.load_from(THREATS_FIXTURE)
	var field := _field(SEED, SpeciesCatalog.load_from(TEST_SPECIES), fixture)
	var holder := field.spawn_at("rammer", Vector2(-6.0, -16.0), 0.0)
	var late := field.spawn_at("ambush_hunter", Vector2(6.0, -16.0), PI)
	for c in [holder, late]:
		c.brain.seen[CreatureField.PLAYER_ID] = {"position": Vector2(0.0, -16.0), "velocity": Vector2.ZERO, "tick": 10,
			"by": "sight", "species": SpeciesCatalog.PLAYER_SPECIES, "radius": PoolLayout.CELL_RADIUS, "engageable": true}
		CreatureBrain._notice(c.brain, CreatureField.PLAYER_ID, "sight", 10)
		CreatureBrain._chase(c.brain, field.self_view_of(c), CreatureBrain.PURSUE, 10, true)
		field.update_token(c, 10)
	check_eq(Array(field.engaged_on_player), [holder.id], "the first holds the token and the list stays at its limit")
	check(CreatureBrain.is_engaged_with(holder.brain, CreatureField.PLAYER_ID), "the holder chases on")
	check(not CreatureBrain.is_engaged_with(late.brain, CreatureField.PLAYER_ID), "the one refused stood down")
	check(not field.may_engage_player(late), "and may not engage")
	field.update_token(holder, 10)
	check_eq(Array(field.engaged_on_player), [holder.id], "updating the holder again changes nothing")


func test_the_same_seed_gives_the_same_field_and_its_snapshot_holds_no_vectors() -> void:
	var a := _field(SEED)
	var b := _field(SEED)
	var arena := layout.build_arena()
	var before := a.region.rng.state
	for field in [a, b]:
		field.populate(arena, layout.spawn, 0)
		for c in field.creatures.duplicate():
			if c.species_id == "rammer":
				field.remove(c, "killed", 30, true)
	check_eq(JSON.stringify(a.snapshot(), "", true, true), JSON.stringify(b.snapshot(), "", true, true), "same seed, same field")
	check_eq(a.region.rng.state, before, "the field never draws from the region's RNG")
	var other := _field(SEED + 1)
	other.populate(arena, layout.spawn, 0)
	for c in other.creatures.duplicate():
		if c.species_id == "rammer":
			other.remove(c, "killed", 30, true)
	check(JSON.stringify(other.snapshot()) != JSON.stringify(a.snapshot()), "another encounter seed gives other respawn times")
	check(_no_vectors(a.snapshot()), "every vector in the snapshot is a pair")
	check_eq(a.snapshot().creatures.size(), 3, "three ambush hunters left")


func _no_vectors(value: Variant) -> bool:
	if value is Vector2 or value is Vector3:
		return false
	if value is Dictionary:
		for k in value:
			if not _no_vectors(value[k]):
				return false
	if value is Array:
		for v in value:
			if not _no_vectors(v):
				return false
	return true


# --- the endless world's place lists (S1 T2.5): in the pool they reduce to M1's one place ---

func test_awake_is_the_creature_list_itself_in_pool_mode() -> void:
	var field := _field()
	field.populate(layout.build_arena(), layout.spawn, 0)
	check(not field.endless, "the pool field is not endless")
	check(is_same(field.awake(), field.creatures), "awake() is the very list (the pool tick runs over it unchanged)")
	var bodies := field.bodies(_player(layout.spawn))
	check_eq(bodies.size(), 8, "the player and all seven")
	var stray := field.spawn_at("rammer", Vector2(0.0, -30.0), 0.0, "", 5, true)
	check(field.awake().has(stray), "a new creature is awake in the pool at once")
	check_eq(field.creatures[-1], stray, "appended in the pool (numbers rise)")


func test_blocker_from_one_place_equals_the_m1_spawn_blocker() -> void:
	var field := _field()
	var arena := layout.build_arena()
	var squatter := field.spawn_at("rammer", species.site("lair_sw").home + Vector2(1.5, 0.0), 0.0, "", 0, true)
	var places: Array[Vector2] = [layout.spawn, BESIDE_LAIR_SE, NORTH_OF_LAIR_SE, Vector2(30.0, -30.0), Vector2(-25.0, 20.0)]
	var on_rock := {"id": "on_rock", "species": "ambush_hunter", "home": layout.rocks[16].center, "heading": 0.0}
	var sites: Array = species.sites.duplicate()
	sites.append(on_rock)
	var reasons := {}
	for s in sites:
		for p in places:
			var one: Array[Vector2] = [p]
			var m1 := field.spawn_blocker(s, arena, p)
			check_eq(field.blocker_from(s, arena, one), m1, "%s from %s" % [s.id, p])
			reasons[m1] = true
	for r in ["", "near the player", "in view", "not clear", "occupied"]:
		check(reasons.has(r), "the cases cover %s" % ("a free site" if r.is_empty() else "'%s'" % r))
	# Two places: the nearer rule wins from either, and "near" is checked before "in view".
	var lair: Dictionary = species.site("lair_se")
	var two: Array[Vector2] = [layout.spawn, NORTH_OF_LAIR_SE]
	check_eq(field.blocker_from(lair, arena, two), "near the player", "near from the second place")
	var both: Array[Vector2] = [BESIDE_LAIR_SE, NORTH_OF_LAIR_SE]
	check_eq(field.blocker_from(lair, arena, both), "near the player", "near before in view, whatever the place order")
	var seen: Array[Vector2] = [layout.spawn, BESIDE_LAIR_SE]
	check_eq(field.blocker_from(lair, arena, seen), "in view", "in view from the second place")
	field.remove(squatter, "test", 0, false)


func test_remove_stuck_at_one_place_equals_remove_stuck() -> void:
	for p in [NORTH_OF_LAIR_SE, BESIDE_LAIR_SE, layout.spawn]:
		var a := _field()
		var b := _field()
		var arena := layout.build_arena()
		a.populate(arena, layout.spawn, 0)
		b.populate(arena, layout.spawn, 0)
		for f in [a, b]:
			f.take_events()
			f.find("c_1").brain.stuck = true
			f.find("c_4").brain.stuck = true
		a.remove_stuck(p, 50)
		var one: Array[Vector2] = [p]
		b.remove_stuck_at(one, 50)
		check_eq(_site_ids(b), _site_ids(a), "the same creatures stay with the player at %s" % p)
		check_eq(b.queue, a.queue, "the same queue")
	# Two places: a stuck creature near or in view of either stays.
	var c := _field()
	c.populate(layout.build_arena(), layout.spawn, 0)
	c.find("c_1").brain.stuck = true
	var places: Array[Vector2] = [layout.spawn, BESIDE_LAIR_SE]
	c.remove_stuck_at(places, 60)
	check(c.find("c_1") != null, "kept: the second place sees it")
	var far: Array[Vector2] = [layout.spawn, Vector2(-30.0, -20.0)]
	c.remove_stuck_at(far, 61)
	check(c.find("c_1") == null, "removed when no place is near or sees it")
