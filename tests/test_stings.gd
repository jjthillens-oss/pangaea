extends TestCase
## S3's stings in the running PoolSim (s3-sim 3.3 and 3.4; D-101, D-119, D-125 to D-127; gates
## S3G12, S3G12b, S3G12c): a veil's threads sting the cell they touch, once per the cell's cooldown
## however many veils touch it, never at q < 1, never while a creature holds the token, within 120
## ticks of a strike hit or in shelter; after a sting no creature takes the token for 120 ticks; a
## lethal sting kills that tick with the veil's death text; the knockback pushes the cell off the
## threads. The veil is placed at q = 1 in pool mode through the test seam (use_entry_record) in the
## threats fixture's open water, with every brain frozen so nothing moves but what a test moves.

const THREATS_FIXTURE := "res://tests/fixtures/pool_test_threats.json"
const AT := Vector2(0.0, -16.0)     ## open water in the threats fixture
const FakeWorldGen := preload("res://tests/fakes/fake_world_gen.gd")
const B1_WORLD := "res://tests/fixtures/world/world_b1_min.json"   ## sizes to 4 (S3G34b)

var catalog: PartCatalog
var fixture: PoolLayout
var species: SpeciesCatalog


func before_each() -> void:
	if species != null:
		return
	catalog = PartCatalog.load_from()
	fixture = PoolLayout.load_from(THREATS_FIXTURE)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpeciesCatalog.DEFAULT_PATH))
	data.sites = []
	species = SpeciesCatalog.from_dict(data)


## A grazer lineage in the threats fixture with the real species and no sites, its shelter over and
## every brain frozen.
func _sim(seed_value := 41) -> PoolSim:
	var r := Lineage.found(seed_value, "test+dev", catalog, "grazer")
	r.save.player["position"] = PlaneSpace.to_save(fixture.spawn)
	var sim := PoolSim.create(r.save, catalog, fixture, species)
	sim.grace_until = sim.tick
	sim.debug_set_ai_frozen(true)
	sim.drain_events()
	return sim


## A veil at q = 1 (D-127) at `at` facing `heading`.
func _veil(sim: PoolSim, at := AT, heading := 0.0) -> CreatureField.Creature:
	sim.creatures.use_entry_record("veil")
	check(sim.debug_spawn_creature("veil", at, heading), "a veil at %s" % at)
	var c: CreatureField.Creature = sim.creatures.creatures.back()
	sim.drain_events()
	return c


func _capsule(c: CreatureField.Creature) -> Dictionary:
	return CreatureBrain.thread_capsule(c.brain, c.motion.position, c.motion.heading, c.phenotype.radius)


## Puts the cell, still, `gap` m clear of the threads (negative: overlapping them) beside the point at
## share `u` of the way along them, on their left; returns the outward normal there.
func _beside(sim: PoolSim, c: CreatureField.Creature, u: float, gap: float) -> Vector2:
	var cap := _capsule(c)
	var n: Vector2 = (Vector2(cap.b) - Vector2(cap.a)).normalized().orthogonal()
	var at: Vector2 = Vector2(cap.a).lerp(cap.b, u) + n * (float(cap.r) + sim.phenotype.radius + gap)
	check(sim.debug_teleport(at, n.angle()), "the cell placed beside the threads at %s" % at)
	sim.motion.velocity = Vector2.ZERO
	sim.drain_events()
	return n


## Steps `ticks` times with no intent; the events, each stamped with its tick.
func _run(sim: PoolSim, ticks: int, hold := Vector2.INF) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in ticks:
		var t := sim.tick
		sim.step(SimIntent.new())
		for e in sim.drain_events():
			e["tick"] = t
			out.append(e)
		if hold.is_finite():
			sim.motion.position = hold
			sim.motion.velocity = Vector2.ZERO
	return out


func _stings(events: Array[Dictionary]) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "hit" and e.kind == "sting")


func test_the_threads_sting_the_cell_they_touch_and_not_one_a_hair_away() -> void:
	var sim := _sim()
	var veil := _veil(sim)
	check_eq(float(sim.creatures.record_of("veil").q), 1.0, "the veil at q = 1")
	_beside(sim, veil, 0.5, -0.02)
	var before := sim.state.health
	var t := sim.tick
	var stings := _stings(_run(sim, 1))
	check_eq(stings.size(), 1, "touching: one sting")
	if stings.size() == 1:
		var s: Dictionary = stings[0]
		check_eq([s.attacker, s.target, s.damage], [veil.id, CreatureField.PLAYER_ID, 5.0], "the veil stings the cell for its damage")
		check_eq(sim.state.health, before - float(s.dealt), "and takes what it deals")
		check_eq(float(s.knockback), 1.5, "the threads' knockback")
	check_eq(sim.last_sting_tick, t, "the sting tick")
	check_eq(sim.creatures.token_closed_until, t + PoolSim.STING_STRIKE_GAP_TICKS, "the token closes for the gap")
	check_eq(sim.stats.hits_taken, 1, "counted as a hit taken")
	var clear := _sim()
	_beside(clear, _veil(clear), 0.5, 0.02)
	check(_stings(_run(clear, 1)).is_empty(), "0.02 m clear: none")
	var tip := _sim()
	var v := _veil(tip)
	var cap := _capsule(v)
	var back: Vector2 = (Vector2(cap.b) - Vector2(cap.a)).normalized()
	check(tip.debug_teleport(Vector2(cap.b) + back * (float(cap.r) + tip.phenotype.radius - 0.02), 0.0), "beyond the tip")
	tip.motion.velocity = Vector2.ZERO
	check_eq(_stings(_run(tip, 1)).size(), 1, "the round tip stings too")


func test_the_cooldown_is_the_cells_however_many_veils_touch_it() -> void:
	var sim := _sim()
	var a := _veil(sim, AT, 0.0)
	_beside(sim, a, 0.9, -0.05)
	var hold := sim.motion.position
	# The second veil faces -y with the cell on the middle of its threads, which trail toward +y.
	var b := _veil(sim, hold - Vector2(0.0, a.phenotype.radius + 1.2), -PI / 2.0)
	check(sim.motion.position.distance_to(Geometry2D.get_closest_point_to_segment(hold, _capsule(b).a, _capsule(b).b))
		<= float(_capsule(b).r) + sim.phenotype.radius, "both veils' threads touch the cell")
	var stings := _stings(_run(sim, 200, hold))
	var ticks := stings.map(func(e: Dictionary) -> int: return e.tick)
	check_eq(stings.size(), 3, "three stings in 200 ticks (%s)" % [ticks])
	if stings.size() == 3:
		check_eq([ticks[1] - ticks[0], ticks[2] - ticks[1]], [75, 75], "one per cooldown, 75 ticks apart")
	check(stings.all(func(e: Dictionary) -> bool: return e.attacker == a.id), "the first veil in order stings each time")


func test_a_veil_below_its_entry_size_never_stings() -> void:
	var sim := _sim()
	sim.creatures.set_size(4)
	check(sim.debug_spawn_creature("veil", AT, 0.0), "a veil drawn at size 4")
	var veil: CreatureField.Creature = sim.creatures.creatures.back()
	check(float(sim.creatures.record_of("veil").q) < 1.0, "at q < 1")
	_beside(sim, veil, 0.5, -0.05)
	check(_stings(_run(sim, 120, sim.motion.position)).is_empty(), "its threads do nothing (thread_damage 0)")


func test_no_sting_while_the_token_is_held_soon_after_a_strike_hit_or_in_shelter() -> void:
	var held := _sim()
	_beside(held, _veil(held), 0.5, -0.05)
	held.creatures.engaged_on_player.append("c_99")
	check(_stings(_run(held, 5, held.motion.position)).is_empty(), "none while a creature holds the token")
	held.creatures.engaged_on_player.clear()
	check_eq(_stings(_run(held, 1)).size(), 1, "one once it is free")
	var struck := _sim()
	_beside(struck, _veil(struck), 0.5, -0.05)
	struck.last_strike_hit_tick = struck.tick - PoolSim.STING_STRIKE_GAP_TICKS + 1
	check(_stings(_run(struck, 1, struck.motion.position)).is_empty(), "none 119 ticks after a strike hit")
	check_eq(_stings(_run(struck, 1)).size(), 1, "one at 120")
	var sheltered := _sim()
	_beside(sheltered, _veil(sheltered), 0.5, -0.05)
	sheltered.grace_until = sheltered.tick + 600
	check(sheltered.is_sheltered(), "sheltered")
	check(_stings(_run(sheltered, 5, sheltered.motion.position)).is_empty(), "none in shelter")
	var hidden := _sim()
	_beside(hidden, _veil(hidden), 0.5, -0.05)
	hidden.dev_hidden = true
	check(_stings(_run(hidden, 5, hidden.motion.position)).is_empty(), "none while hidden from the AI")


func test_no_creature_takes_the_token_for_120_ticks_after_a_sting() -> void:
	var sim := _sim()
	var veil := _veil(sim)
	_beside(sim, veil, 0.5, -0.02)
	var t := sim.tick
	check_eq(_stings(_run(sim, 1)).size(), 1, "stung")
	# Out of the threads' way, a hungry ambush hunter 2.7 m ahead of the cell, facing it, settled.
	check(sim.debug_teleport(AT + Vector2(0.0, 10.0), 0.0), "the cell moved off")
	sim.motion.velocity = Vector2.ZERO
	check(sim.debug_spawn_creature("ambush_hunter", sim.motion.position + Vector2(2.7, 0.0), PI), "a hunter")
	var hunter: CreatureField.Creature = sim.creatures.creatures.back()
	hunter.brain.ignore_all_until = 0
	hunter.state.energy = hunter.state.energy_capacity * 0.3
	veil.brain.ignore_all_until = 0
	sim.debug_set_ai_frozen(false)
	var engaged_at := -1
	var early := false
	for i in 240:
		_run(sim, 1, sim.motion.position)
		if not sim.creatures.engaged_on_player.is_empty() and engaged_at < 0:
			engaged_at = sim.tick - 1
		if sim.tick - 1 < t + PoolSim.STING_STRIKE_GAP_TICKS and not sim.creatures.engaged_on_player.is_empty():
			early = true
		if sim.tick - 1 < t + PoolSim.STING_STRIKE_GAP_TICKS and hunter.brain.seen.has(CreatureField.PLAYER_ID):
			check(not bool(hunter.brain.seen[CreatureField.PLAYER_ID].engageable), "not engageable at %d" % (sim.tick - 1))
	check(not early, "no creature took the token within 120 ticks of the sting")
	check(engaged_at >= t + PoolSim.STING_STRIKE_GAP_TICKS, "the hunter engages once it opens (tick %d, sting %d)" % [engaged_at, t])


## S3G12b: a lethal sting kills on the same tick with the veil's death text.
func test_a_lethal_sting_kills_that_tick_with_the_veils_death_text() -> void:
	var sim := _sim()
	var veil := _veil(sim)
	_beside(sim, veil, 0.5, -0.02)
	sim.state.health = 2.0
	var events := _run(sim, 1)
	check(sim.dead, "dead")
	var died := events.filter(func(e: Dictionary) -> bool: return e.type == "died")
	check_eq(died.size(), 1, "one death")
	if died.size() == 1:
		check_eq([died[0].tick, died[0].by, died[0].by_species, died[0].reason], [_stings(events)[0].tick, veil.id, "veil",
			"Stung by a stinger veil"], "on the sting's tick, by the veil, with its text")


## S3G12c: the knockback pushes from the nearest point of the threads, so a cell beside their middle
## goes sideways, not away from the veil's body.
func test_the_knockback_pushes_the_cell_off_the_threads_sideways() -> void:
	var sim := _sim()
	var veil := _veil(sim)
	var n := _beside(sim, veil, 0.5, -0.02)
	_run(sim, 1)
	var v := sim.motion.velocity
	check(v.length() > 0.5, "pushed (%.2f m/s)" % v.length())
	check(v.normalized().dot(n) > 0.99, "straight off the threads (%s against %s)" % [v.normalized(), n])
	var from_body := (sim.motion.position - veil.motion.position).normalized()
	check(v.normalized().dot(from_body) < 0.9, "not along the line from the veil's body")


## S3G12e (BP3-4): a token holder that lets go inside its think on tick t leaves the token free when
## the stings run later that tick, so the veil stings on tick t and the sting records engaged == [].
## A rammer takes the token over the cell in its territory; the cell then sits in a veil's threads
## beyond that territory and its leash, and the rammer, put where it sees the cell and made to think,
## gives the chase up (left_territory). Every sting of the run carries engaged == [] (invariant 15 (c)
## as BP3-4 restates it; the whole invariant joins this run with T0.2).
func test_a_sting_on_the_tick_the_holder_gives_up_records_no_holder() -> void:
	var sim := _sim()
	var veil := _veil(sim)
	var away := AT + Vector2(0.0, 16.0)
	check(sim.debug_teleport(away, 0.0), "the cell away from the veil")
	sim.motion.velocity = Vector2.ZERO
	check(sim.debug_spawn_creature("rammer", away + Vector2(2.5, 0.0), PI), "a rammer beside the cell")
	var rammer: CreatureField.Creature = sim.creatures.creatures.back()
	rammer.brain.ignore_all_until = 0
	veil.brain.ignore_all_until = 0
	sim.debug_set_ai_frozen(false)
	sim.drain_events()
	var held := false
	var run: Array[Dictionary] = []
	for i in 600:
		run.append_array(_run(sim, 1, away))
		if sim.creatures.engaged_on_player.has(rammer.id):
			held = true
			break
	check(held, "the rammer took the token")
	check_eq(sim.last_strike_hit_tick, -CreatureBrain.NEVER, "and has not hit the cell")
	if not held:
		return
	# The cell overlaps the threads' tail. The rammer stands 3 m out from it, turned so the cell sits
	# 125 degrees off its heading (inside its 270-degree view) and the veil's body behind it, out of
	# view and beyond touch: it sees the cell and not the veil, so it gives up and does not flee.
	var n := _beside(sim, veil, 1.0, -0.05)
	var b := rammer.brain
	check(sim.motion.position.distance_to(b.territory_center) > b.territory_r + float(b.cfg.leash_m),
		"the cell beyond the rammer's territory and leash")
	var at := sim.motion.position + n * 3.0
	rammer.motion.position = at
	rammer.motion.prev_position = at
	rammer.motion.velocity = Vector2.ZERO
	rammer.motion.heading = (sim.motion.position - at).angle() - deg_to_rad(125.0)
	var eye := {"position": at, "heading": rammer.motion.heading}
	check(absf(CreatureSenses.bearing(eye, veil.motion.position)) > deg_to_rad(140.0), "the veil behind the rammer")
	check(at.distance_to(veil.motion.position) > rammer.phenotype.radius + veil.phenotype.radius + 1.0,
		"and beyond its touch")
	b.wake = true
	var events := _run(sim, 1)
	run.append_array(events)
	var gave_up := events.filter(func(e: Dictionary) -> bool: return e.type == "creature_gave_up" and e.id == rammer.id)
	var stings := _stings(events)
	check_eq(gave_up.size(), 1, "the rammer gave up this tick (%s)" % [events.map(func(e: Dictionary) -> String: return e.type)])
	check_eq(stings.size(), 1, "and the veil stung the same tick")
	if stings.size() == 1:
		check_eq(stings[0].engaged, [], "with no holder at the sting")
	check(sim.creatures.engaged_on_player.is_empty(), "the token is free")
	check(_stings(run).all(func(e: Dictionary) -> bool: return e.engaged == []), "no sting of the run had a holder")


## S3G34b (BP3-2): at a size where no hazard can be live the sting rule's ticks stay out of the
## snapshot, however many strikes hit the cell (S2's hashes hold); a debug size change is a cut that
## starts them again; at size 3 a strike hit puts its tick in.
func test_the_sting_rule_ticks_join_the_snapshot_only_where_a_veil_can_live() -> void:
	var content := FakeWorldGen.fixture_content(B1_WORLD)
	var sim := FakeWorldGen.endless_sim(7, catalog, PoolLayout.load_from(), SpeciesCatalog.load_from(), content,
		PackedFloat64Array(), 4, true)
	check(sim.debug_set_size(2), "size 2")
	check(not sim.creatures.hazard_live, "no hazard is live at size 2")
	check(sim.debug_spawn_threat_ahead("elder_rammer"), "an elder rammer ahead")
	var hits := _strike_hits(sim, "lurker", 3, 6000)
	check(hits.size() >= 3, "at least 3 strike hits at size 2 (%d)" % hits.size())
	check(sim.last_strike_hit_tick != -CreatureBrain.NEVER, "the field holds the last one")
	for keys in hits:
		check_eq(keys, [false, false, false], "none of the keys in a size-2 snapshot")
	sim.creatures.token_closed_until = sim.tick + 50
	check(not sim.snapshot().has("token_closed_until"), "nor a closed token")
	check(sim.debug_set_size(3), "size 3")
	check(sim.creatures.hazard_live, "veils are live at size 3")
	check_eq([sim.last_strike_hit_tick, sim.last_sting_tick, sim.creatures.token_closed_until], [-CreatureBrain.NEVER,
		-CreatureBrain.NEVER, 0], "the cut starts the sting rule again")
	hits = _strike_hits(sim, "warden", 1, 6000)
	check_eq(hits.size(), 1, "a strike hit at size 3")
	if hits.size() == 1:
		check(hits[0][0], "puts last_strike_hit_tick in the snapshot")


## Steps `sim` still, the cell kept at full health, a dev `ahead` placed in front of it every 600
## ticks and every awake creature then made hungry and attentive, until `want` strike hits land on the
## cell or `most` ticks pass. Per hit: whether the snapshot then
## has last_strike_hit_tick, last_sting_tick and token_closed_until.
func _strike_hits(sim: PoolSim, ahead: String, want: int, most: int) -> Array:
	var out := []
	for i in most:
		if i % 600 == 0:
			sim.debug_spawn_threat_ahead(ahead)
			for c in sim.creatures.awake():
				c.brain.ignore_all_until = 0
				c.state.energy = c.state.energy_capacity * 0.3
		sim.step(SimIntent.new())
		sim.state.health = sim.state.max_health
		for e in sim.drain_events():
			if e.type == "hit" and e.target == CreatureField.PLAYER_ID and e.kind != "sting":
				var snap := sim.snapshot()
				out.append([snap.has("last_strike_hit_tick"), snap.has("last_sting_tick"), snap.has("token_closed_until")])
		if out.size() >= want:
			break
	return out
