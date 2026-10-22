extends TestCase
## Die several times in a row and always return to a fair checkpoint (M1 step 3, plan section 13,
## rules C1-C7): the respawn puts the cell there with the streak's shelter and energy, sends home
## every creature near it and makes every brain forget the cell; sheltered, nothing senses or hits
## it. Saves go to a per-process folder under user://test_saves.

const SaveFolder := preload("res://tests/save_folder.gd")
const ForageBot := preload("res://game/dev/forage_bot.gd")
const SessionTests := preload("res://tests/test_game_session.gd")
const THREATS_FIXTURE := "res://tests/fixtures/pool_test_threats.json"
const TEST_SPECIES := "res://tests/fixtures/creatures_test.json"
## A slot written by the step 2 build (a3fe55b): an omnivore in generation 1 that ate, starved once
## and was saved mid-run near the pool's center.
const STEP2_SAVE := "res://tests/fixtures/save_v2_step2.json"
const PLAYER := "player"
## m in front of a lair's hunter: the middle of the lunge's start window (2.5-3.0 m).
const IN_FRONT_M := 2.75
## A death the test causes must come within this; the streak window is 90 s.
const DEATH_LIMIT_TICKS := 80 * 60
## Open water 4 m south of the spawn, away from every food item and creature: a cell starves here.
const STARVE_SPOT := Vector2(0.0, 13.0)
const STARTING_POINTS := 40

var slot := ""
var _swept := false


func before_each() -> void:
	if not _swept:
		SaveFolder.sweep_stale()
		_swept = true
	SaveFolder.clear()
	slot = SaveFolder.path("checkpoint_slot.json")


func after_each() -> void:
	SaveFolder.clear()


func _files() -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(SaveFolder.dir()):
		var path := SaveFolder.path(f)
		out[f] = [FileAccess.get_modified_time(path), FileAccess.get_file_as_string(path)]
	return out


## Steps `sim` with `bot` until `done.call()` holds or `limit` ticks pass; returns the events, each
## stamped with the tick it happened on.
func _play(sim: PoolSim, bot, limit: int, done := Callable()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in limit:
		if done.is_valid() and done.call():
			break
		var t := sim.tick
		sim.step(bot.next_intent(sim))
		for e in sim.drain_events():
			e["tick"] = t
			out.append(e)
	return out


## The events on the cell during its shelter: hits on it and creatures noticing it.
func _sheltered_threats(events: Array[Dictionary], until: int) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool:
		return int(e.tick) < until and ((e.type == "hit" and e.target == PLAYER)
			or (e.type == "creature_noticed" and e.target == PLAYER)))


## The save on disk, read the way Continue reads it.
func _on_disk(session: GameSession) -> SaveGame:
	var loaded := PersistenceService.new(session.catalog).load_from(session.slot)
	check(loaded.ok, "the slot loads: %s" % [loaded.errors])
	return loaded.save if loaded.ok else null


## The site's creature (null when it is not spawned).
func _at_site(sim: PoolSim, site_id: String) -> CreatureField.Creature:
	for c in sim.creatures.creatures:
		if c.site_id == site_id:
			return c
	return null


## The smallest gap between a non-debug creature's body and the checkpoint.
func _nearest_creature_m(sim: PoolSim) -> float:
	var at: Vector2 = sim.checkpoint().position
	var best := INF
	for c in sim.creatures.creatures:
		if not c.debug:
			best = minf(best, c.motion.position.distance_to(at) - c.phenotype.radius)
	return best


func test_creatures_near_the_checkpoint_are_sent_home_and_forget_the_cell_at_the_respawn() -> void:
	# Plan test_checkpoints #7 (C2, C3), in the open fixture: two dev creatures whose homes are far
	# out have come within 12 m of the checkpoint and seen the cell; a third stays beyond 12 m.
	var catalog := PartCatalog.load_from()
	var fixture := PoolLayout.load_from(THREATS_FIXTURE)
	var r := Lineage.found(4646, "test+dev", catalog, "hunter")
	r.save.player["position"] = PlaneSpace.to_save(fixture.spawn)
	var sim := PoolSim.create(r.save, catalog, fixture, SpeciesCatalog.load_from(TEST_SPECIES))
	sim.grace_until = sim.tick
	var cp: Vector2 = sim.checkpoint().position
	# [species, home, where it has come to], relative to the checkpoint: two in sight of it, one 14 m off.
	var placed := [["ambush_hunter", Vector2(12.0, 0.0), Vector2(5.0, 0.0)], ["rammer", Vector2(-14.0, 0.0), Vector2(-5.0, 1.0)],
		["ambush_hunter", Vector2(0.0, -20.0), Vector2(0.0, -14.0)]]
	var made: Array[CreatureField.Creature] = []
	for p in placed:
		var home: Vector2 = cp + p[1]
		check(sim.debug_spawn_creature(p[0], home, (cp - home).angle()), "a dev %s placed" % p[0])
		var c: CreatureField.Creature = sim.creatures.creatures[-1]
		c.brain.ignore_all_until = 0
		c.motion.place(cp + p[2], (cp - (cp + p[2])).angle())
		made.append(c)
	var bot = ForageBot.new()
	bot.park_at = cp
	_play(sim, bot, 30)
	for c in made.slice(0, 2):
		check(c.brain.seen.has(PLAYER), "%s has seen the cell" % c.id)
		check(c.motion.position.distance_to(cp) < 12.0, "%s is within 12 m of the checkpoint" % c.id)
	var far := made[2].motion.position
	check(far.distance_to(cp) > 12.0, "%s is not" % made[2].id)
	check(sim.debug_hurt_player(sim.state.max_health), "the cell dies")
	sim.drain_events()
	sim.respawn_player()
	var respawned := sim.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "respawned")
	check(respawned.size() == 1 and respawned[0].relocated == [made[0].id, made[1].id],
		"respawned names the two sent home, by id: %s" % [respawned])
	for c in made.slice(0, 2):
		check_eq(c.motion.position, c.brain.home, "%s is at its home" % c.id)
		check_eq(c.motion.heading, c.brain.home_heading, "facing its home heading")
		check_eq(c.motion.velocity, Vector2.ZERO, "at rest")
		check(not c.brain.seen.has(PLAYER) and c.brain.target != PLAYER and not c.brain.landed_on.has(PLAYER),
			"%s has no memory of the cell" % c.id)
		check(c.brain.state == CreatureBrain.REST, "and rests (%s)" % c.brain.state)
	check_eq(made[2].motion.position, far, "the one beyond 12 m stays where it was")
	check(not made[2].brain.seen.has(PLAYER), "but forgets the cell too")


func test_a_sheltered_cell_is_never_sensed_or_struck_and_its_own_bite_ends_the_shelter() -> void:
	# Rule C5 face to face: a hunter cell sheltered in front of an ambush hunter, which is even
	# forced into a lunge at it; then the cell bites the hunter from behind.
	var catalog := PartCatalog.load_from()
	var fixture := PoolLayout.load_from(THREATS_FIXTURE)
	var r := Lineage.found(4747, "test+dev", catalog, "hunter")
	r.save.player["position"] = PlaneSpace.to_save(fixture.spawn)
	var sim := PoolSim.create(r.save, catalog, fixture, SpeciesCatalog.load_from(TEST_SPECIES))
	check(sim.is_sheltered() and sim.grace_until == 300, "a new lineage starts with 5 s of shelter")
	var home := Vector2(0.0, -16.0)
	check(sim.debug_spawn_creature("ambush_hunter", home, 0.0), "an ambush hunter facing +x")
	var c: CreatureField.Creature = sim.creatures.creatures[-1]
	c.brain.ignore_all_until = 0
	check(sim.debug_teleport(home + Vector2(IN_FRONT_M, 0.0), 0.0), "the cell in its window")
	var bot = ForageBot.new()
	bot.park_at = sim.motion.position
	var events := _play(sim, bot, 120)
	check(not c.brain.seen.has(PLAYER) and c.brain.state == CreatureBrain.REST, "the hunter senses nothing for 2 s")
	# Whitebox: a lunge at the concealed cell, as if the brain had seen it.
	c.brain.seen[PLAYER] = {"position": sim.motion.position, "velocity": Vector2.ZERO, "tick": sim.tick, "by": "sight",
		"species": "lineage", "radius": sim.phenotype.radius, "engageable": true}
	c.brain.target = PLAYER
	CreatureBrain.begin_tell(c.brain, sim.creatures.self_view_of(c), sim.tick)
	var strike_ticks: int = c.brain.cfg.attack.tell_ticks + c.brain.cfg.attack.burst_ticks + c.brain.cfg.attack.glide_ticks
	events.append_array(_play(sim, bot, strike_ticks + 2))
	check(events.any(func(e: Dictionary) -> bool: return e.type == "creature_strike" and e.target == PLAYER), "the lunge was struck")
	check(sim.is_sheltered(), "still sheltered (%d ticks in)" % sim.tick)
	var threats := _sheltered_threats(events, sim.grace_until)
	check(threats.is_empty(), "no notice of and no hit on the sheltered cell: %s" % [threats])
	check(not events.any(func(e: Dictionary) -> bool: return e.type == "dodged"), "and no dodge: hiding is not dodging")
	check_eq(sim.state.health, sim.state.max_health, "unhurt")
	# Kept sheltered, out of its reach, until the hunter is idle again; then the cell bites it from
	# behind: the shelter ends at once and the hunter turns on it.
	sim.grace_until = sim.tick + 1200
	check(sim.debug_teleport(home + Vector2(0.0, -6.0)), "the cell out of reach")
	bot.park_at = sim.motion.position
	_play(sim, bot, 600, func() -> bool: return c.brain.state == CreatureBrain.REST or c.brain.state == CreatureBrain.WANDER)
	check(sim.is_sheltered(), "the cell is still sheltered")
	check(c.brain.state == CreatureBrain.REST or c.brain.state == CreatureBrain.WANDER, "the hunter is idle again (%s)" % c.brain.state)
	check(not c.brain.seen.has(PLAYER), "and has nothing of the cell in mind")
	var behind := c.motion.position - Vector2.from_angle(c.motion.heading) * (c.phenotype.radius + sim.phenotype.radius + 0.1)
	check(sim.debug_teleport(behind, c.motion.heading), "the cell behind the hunter, jaw on its tail")
	bot.park_at = behind
	var bite := _play(sim, bot, 30, func() -> bool: return not sim.is_sheltered())
	check(not sim.is_sheltered(), "the bite ended the shelter")
	var ended := bite.filter(func(e: Dictionary) -> bool: return e.type == "grace_ended")
	var hits := bite.filter(func(e: Dictionary) -> bool: return e.type == "hit" and e.attacker == PLAYER)
	check(ended.size() == 1 and ended[0].reason == "attacked" and hits.size() == 1 and int(hits[0].tick) == int(ended[0].tick),
		"grace_ended {attacked} on the tick of the cell's hit: %s" % [ended])
	_play(sim, bot, 2)
	check(c.brain.target == PLAYER and c.brain.seen.has(PLAYER), "the hunter turns on its attacker")


func test_the_cell_respawns_at_the_nearest_clear_point_when_the_checkpoint_is_blocked() -> void:
	# Rule C1's fallback, never needed by the real layout: the checkpoint moved onto a rock's edge.
	var catalog := PartCatalog.load_from()
	var layout := PoolLayout.load_from()
	var r := Lineage.found(4848, "test+dev", catalog, "grazer")
	r.save.player["position"] = PlaneSpace.to_save(layout.spawn)
	var sim := PoolSim.create(r.save, catalog, layout, SpeciesCatalog.load_from())
	check(sim.arena.is_clear(sim.checkpoint().position, sim.phenotype.radius), "the real checkpoint is clear")
	var rock: Dictionary = sim.arena.rocks[1]   # rock_02, beside the spawn
	layout.spawn = rock.center + Vector2(0.0, -float(rock.radius) - 0.2)
	check(not sim.arena.is_clear(layout.spawn, sim.phenotype.radius), "the moved checkpoint is not clear")
	check(sim.debug_hurt_player(sim.state.max_health), "the cell dies")
	sim.respawn_player()
	var at := sim.motion.position
	check(sim.arena.is_clear(at, sim.phenotype.radius), "it respawns clear of the rock: %s" % at)
	var d := at.distance_to(layout.spawn)
	check(d > 0.0 and d <= PoolSim.CLEAR_SPIRAL_STEP_M * 2.0 + 1e-6, "within two 0.5 m rings of the checkpoint (%.2f m)" % d)


