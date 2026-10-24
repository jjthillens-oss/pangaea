extends TestCase
## Die several times in a row and always return to a fair checkpoint (M1 step 3, plan section 13,
## rules C1-C7): every death is applied to the lineage once and, with SAVE_ON_DEATH (OD1), saved at
## once with the cell at its checkpoint; the respawn puts the cell there with the streak's shelter
## and energy, sends home every creature near it, makes every brain forget the cell and its killer
## ignore it; the lineage is never erased. Saves go to a per-process folder under user://test_saves.

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
## S3G26 (S3 T0.7; D-107, D-132, BP3-8): the checkpoint rules at landmark checkpoints at size 4.
const Gates := preload("res://tests/test_endless_gates.gd")
const LANDMARK_CHECKPOINTS := 50
const LANDMARK_SEED := 2626
const LANDMARK_CHUNKS := 16            ## the anchors of the chunks this far round home, nearest first
const LANDMARK_NEAR_TM := 3.0          ## the cell by an anchor (landmark_find_tm is 6)
const LANDMARK_WAIT_TICKS := 240       ## a calm, still cell by an anchor: moved or refused by then
const LANDMARK_BLOCKED_AFTER := 5      ## the anchor tried after this many moves gets a blocker
const LANDMARK_CROWD_TM := 8.0         ## C2: a creature put this far from the checkpoint while dead
const LANDMARK_EDGE_EVERY := 10        ## C1's fallback: every 10th checkpoint is blocked at the respawn
const LANDMARK_SETTLE_TICKS := 30      ## creatures act before the death
const NOTICE_TICKS := 120

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


func test_dying_five_times_in_a_row_always_returns_the_cell_to_a_fair_checkpoint() -> void:
	# Plan test_checkpoints #1, with the real data: three lair hunters, a rammer and starving, each
	# death within 90 s of the last respawn, so the streak grows 1 to 5.
	var session := GameSession.new(slot)
	check(session.start_new("grazer", 9090).ok, "started")
	var sim := session.sim
	check_eq(sim.creatures.creatures.size(), 7, "every site is filled")
	Lineage.earn(sim.save, STARTING_POINTS)
	check(session.save_now().ok, "saved with %d points" % STARTING_POINTS)
	var lineage := sim.save.lineage_id
	var genome := JSON.stringify(sim.save.genome.to_dict())
	var history_size := sim.save.lineage_history.size()
	var checkpoint: Vector2 = sim.checkpoint().position
	var bot = ForageBot.new()
	# Out of the start shelter first, at the checkpoint.
	bot.park_at = checkpoint
	_play(sim, bot, sim.grace_until - sim.tick)
	check(not sim.is_sheltered(), "the start shelter is over")

	var deaths := [
		{"at": "lair_se", "cause": "killed:ambush_hunter", "grace_s": 5.0, "energy": 0.6},
		{"at": "lair_sw", "cause": "killed:ambush_hunter", "grace_s": 8.0, "energy": 0.8},
		{"at": "lair_s", "cause": "killed:ambush_hunter", "grace_s": 10.0, "energy": 1.0},
		{"at": "z_n", "cause": "killed:rammer", "grace_s": 10.0, "energy": 1.0},
		{"at": "starve", "cause": "starved", "grace_s": 10.0, "energy": 1.0},
	]
	var respawned_at := 0
	for k in deaths.size():
		var plan: Dictionary = deaths[k]
		var killer: CreatureField.Creature = null
		var spot := checkpoint
		match str(plan.at):
			"z_n":
				spot = sim.region.zone("z_n").center
			"starve":
				sim.debug_set_energy(0.0)
			_:
				killer = _at_site(sim, plan.at)
				check(killer != null, "%s has its hunter" % plan.at)
				if killer == null:
					return
				spot = killer.brain.home + Vector2.from_angle(killer.brain.home_heading) * IN_FRONT_M
				check(sim.debug_teleport(spot, killer.brain.home_heading), "the cell 2.75 m in front of %s's hunter" % plan.at)
		if str(plan.at) == "z_n":
			check(sim.debug_teleport(spot, 0.0), "the cell in the middle of z_n")
		bot.park_at = spot
		_play(sim, bot, DEATH_LIMIT_TICKS, func() -> bool: return sim.dead)
		check(sim.dead, "death %d (%s) came within 80 s" % [k + 1, plan.at])
		if not sim.dead:
			return
		check(sim.tick - respawned_at < sim.species.streak_window_ticks or k == 0,
			"death %d came within the 90 s streak window (%.1f s)" % [k + 1, (sim.tick - respawned_at) * PoolSim.DT])
		if killer != null:
			check_eq(sim.death.by, killer.id, "death %d: the lair's hunter killed it" % (k + 1))
		var points := sim.save.adaptation_points
		var resolved := session.resolve_death()
		check_eq(resolved.cause, plan.cause, "death %d's cause" % (k + 1))
		var by := str(resolved.by_species)
		var reason := str(sim.species.species[by].death_reason) if killer != null or plan.at == "z_n" else ""
		var tip := str(sim.species.species[by].death_tip) if not reason.is_empty() else GameSession.STARVED_TIP
		check_eq(resolved.reason, reason, "death %d's reason for the notice" % (k + 1))
		check_eq(resolved.tip, tip, "death %d's tip" % (k + 1))
		check_eq(resolved.lost, floori(points * Lineage.DEATH_POINT_LOSS), "death %d loses a quarter, rounded down" % (k + 1))
		check(resolved.saved.attempted and resolved.saved.ok, "death %d saved at once: %s" % [k + 1, resolved.saved.error])
		check_eq(sim.save.adaptation_points, points - int(resolved.lost), "death %d is applied before the respawn" % (k + 1))
		# C7: the slot already holds the death, with the cell at the checkpoint.
		var disk := _on_disk(session)
		if disk != null:
			check_eq(disk.adaptation_points, sim.save.adaptation_points, "death %d: the slot has the reduced points" % (k + 1))
			check_eq(str(disk.lineage_history.back().get("cause", "")), plan.cause, "death %d: the slot has the death" % (k + 1))
			check(PlaneSpace.from_save(disk.player.position).distance_to(checkpoint) < 1e-4,
				"death %d: the slot has the cell at the checkpoint" % (k + 1))
		check(not session.dirty, "death %d: nothing unsaved while the notice is open" % (k + 1))

		check_eq(session.respawn_after_death(), int(resolved.lost), "the respawn reports the same loss")
		respawned_at = sim.tick
		var events := sim.drain_events()
		var respawned := events.filter(func(e: Dictionary) -> bool: return e.type == "respawned")
		check_eq(respawned.size(), 1, "respawn %d reported once" % (k + 1))
		if respawned.size() == 1:
			check_eq(respawned[0].grace_s, plan.grace_s, "respawn %d: the event's shelter" % (k + 1))
			check_eq(respawned[0].streak, k + 1, "respawn %d: the streak" % (k + 1))
			check_eq(respawned[0].relocated, [], "respawn %d: no creature had to be sent home" % (k + 1))
		# C1, C4, C5
		check_eq(sim.motion.position, checkpoint, "respawn %d: at the checkpoint" % (k + 1))
		check_eq(sim.motion.heading, float(sim.checkpoint().heading), "respawn %d: facing the start heading" % (k + 1))
		check_eq(sim.grace_until - sim.tick, roundi(float(plan.grace_s) * 60.0), "respawn %d: sheltered %.0f s" % [k + 1, plan.grace_s])
		check_near(sim.state.energy, sim.state.energy_capacity * float(plan.energy), 1e-6, "respawn %d: energy share" % (k + 1))
		check_eq(sim.state.health, sim.state.max_health, "respawn %d: full health" % (k + 1))
		check(sim.actor.cooldowns.is_empty(), "respawn %d: no cooldowns" % (k + 1))
		check(sim.is_sheltered() and sim.is_concealed(), "respawn %d: sheltered and concealed" % (k + 1))
		# C2
		check(_nearest_creature_m(sim) >= 12.0, "respawn %d: no creature within 12 m (%.2f m)" % [k + 1, _nearest_creature_m(sim)])
		# C3: no brain remembers the cell or holds the token.
		for c in sim.creatures.creatures:
			check(not c.brain.seen.has(PLAYER) and c.brain.target != PLAYER, "respawn %d: %s forgot the cell" % [k + 1, c.id])
		check(sim.creatures.engaged_on_player.is_empty(), "respawn %d: the token is free" % (k + 1))
		# C5: through the shelter, at the checkpoint, nothing notices or hits it.
		var until := sim.grace_until
		bot.park_at = checkpoint
		var during := _play(sim, bot, until - sim.tick + 1)
		var threats := _sheltered_threats(during, until)
		check(threats.is_empty(), "respawn %d: no hit on or notice of the sheltered cell: %s" % [k + 1, threats])
		var ended := during.filter(func(e: Dictionary) -> bool: return e.type == "grace_ended")
		check(ended.size() == 1 and ended[0].reason == "timeout" and int(ended[0].tick) == until - 1,
			"respawn %d: the shelter ended on its last tick (%s)" % [k + 1, ended])
		check(not sim.is_sheltered() and not sim.is_concealed(), "respawn %d: then the cell is exposed again" % (k + 1))

	# C6: the lineage is intact, with exactly five new deaths.
	check_eq(sim.save.lineage_id, lineage, "the same lineage")
	check_eq(JSON.stringify(sim.save.genome.to_dict()), genome, "the same genome")
	check_eq(sim.save.genome.generation, 1, "still generation 1")
	var causes := []
	for entry in sim.save.lineage_history.slice(history_size):
		check_eq(entry.event, "died", "only deaths were added")
		causes.append(entry.cause)
	check_eq(causes, ["killed:ambush_hunter", "killed:ambush_hunter", "killed:ambush_hunter", "killed:rammer", "starved"],
		"five deaths, each with its cause")
	var points := sim.save.adaptation_points
	check(points < STARTING_POINTS / 2, "five quarters of the points are gone (%d -> %d)" % [STARTING_POINTS, points])
	# C7: the last death's save continues from the primary file, at the checkpoint, sheltered.
	var again := GameSession.new(slot)
	var r := again.continue_run()
	check(r.ok and r.source == "primary", "continued from the primary file: %s" % [r])
	if r.ok:
		check_eq(again.sim.motion.position, checkpoint, "at the checkpoint")
		check_eq(again.sim.save.adaptation_points, points, "with the points")
		check(again.sim.is_sheltered(), "sheltered")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(slot))
	var keys := data.keys()
	keys.sort()
	check_eq(keys, SessionTests.SAVE_KEYS, "the save has exactly the 20 v4 keys")


func test_quitting_at_the_death_notice_does_not_skip_the_death_unless_save_on_death_is_off() -> void:
	# Plan test_checkpoints #2, both OD1 options: die, resolve, drop the session (quit at the notice),
	# continue in a new session.
	for on in [true, false]:
		SaveFolder.clear()
		var session := GameSession.new(slot)
		session.save_on_death = on
		check(session.start_new("grazer", 4141).ok, "started")
		var sim := session.sim
		Lineage.earn(sim.save, 12)
		check(sim.debug_teleport(STARVE_SPOT), "the cell away from food")
		check(session.save_now().ok, "saved there with 12 points")
		var history_size := sim.save.lineage_history.size()
		sim.debug_set_energy(0.0)
		var bot = ForageBot.new()
		bot.park_at = STARVE_SPOT
		_play(sim, bot, DEATH_LIMIT_TICKS, func() -> bool: return sim.dead)
		check(sim.dead, "starved")
		var resolved := session.resolve_death()
		check_eq(resolved.saved.attempted, on, "save on death %s: the death save was tried or not" % on)
		check_eq(session.resolve_death(), resolved, "resolving again changes nothing")
		check_eq(sim.save.adaptation_points, 9, "the death is applied in memory either way")
		var files := _files()
		var again := GameSession.new(slot)
		var r := again.continue_run()
		check(r.ok and r.source == "primary", "continued: %s" % [r])
		check_eq(_files(), files, "continuing rewrote nothing: file list, times and contents")
		if not r.ok:
			continue
		var save := again.sim.save
		if on:
			check_eq(save.adaptation_points, 9, "the points are reduced by the death")
			check_eq(save.lineage_history.size(), history_size + 1, "the death is in the history")
			check_eq(str(save.lineage_history.back().get("cause", "")), "starved", "with its cause")
			check_eq(again.sim.motion.position, again.sim.checkpoint().position, "the cell is at the checkpoint")
			check_eq(again.sim.grace_until - again.sim.tick, 300, "with 5 s of shelter")
		else:
			check_eq(save.adaptation_points, 12, "save on death off: the pre-death points, as in step 2")
			check_eq(save.lineage_history.size(), history_size, "and no death")
			check(again.sim.motion.position.distance_to(STARVE_SPOT) < 1e-3, "at the place of the last save")


func test_a_death_save_that_fails_keeps_the_death_in_memory_and_says_so() -> void:
	# Plan test_checkpoints #3: a file sits where the slot's folder should be.
	var blocker := SaveFolder.path("blocked")
	DirAccess.make_dir_recursive_absolute(SaveFolder.dir())
	var f := FileAccess.open(blocker, FileAccess.WRITE)
	f.store_string("not a folder")
	f.close()
	var session := GameSession.new(blocker + "/slot.json")
	var started := session.start_new("grazer", 4242)
	check(started.ok and not started.saved, "the run starts, unsaved")
	var sim := session.sim
	Lineage.earn(sim.save, 8)
	check(sim.debug_teleport(STARVE_SPOT), "the cell away from food")
	sim.debug_set_energy(0.0)
	var bot = ForageBot.new()
	bot.park_at = STARVE_SPOT
	_play(sim, bot, DEATH_LIMIT_TICKS, func() -> bool: return sim.dead)
	check(sim.dead, "starved")
	check(not session.death_save_failed(), "no failure before the death is resolved")
	var resolved := session.resolve_death()
	check(resolved.saved.attempted and not resolved.saved.ok, "the death save failed")
	check(str(resolved.saved.error).begins_with("Could not save"), "with the reason: %s" % resolved.saved.error)
	check_eq(sim.save.adaptation_points, 6, "the death is applied in memory")
	check_eq(str(sim.save.lineage_history.back().get("cause", "")), "starved", "and recorded")
	check(session.dirty, "the session is dirty")
	check(session.death_save_failed(), "the quit dialog can tell the death was not saved")
	check(not FileAccess.file_exists(blocker + "/slot.json"), "nothing was written")
	check_eq(session.respawn_after_death(), 2, "the respawn still works")
	check(not sim.dead and sim.motion.position == sim.checkpoint().position, "back at the checkpoint")
	check(not session.death_save_failed(), "the failure belonged to that death")
	check(session.dirty, "still dirty after the respawn")


func test_a_saved_death_is_not_an_unsaved_change_and_an_unsaved_one_is() -> void:
	# Plan test_checkpoints #4. The cell dies away from the checkpoint, so its body is more than
	# DIRTY_MOVE_M from where the save puts it.
	for on in [true, false]:
		SaveFolder.clear()
		var session := GameSession.new(slot)
		session.save_on_death = on
		check(session.start_new("grazer", 4343).ok, "started")
		var sim := session.sim
		Lineage.earn(sim.save, 4)
		check(sim.debug_teleport(STARVE_SPOT), "the cell away from food")
		check(session.save_now().ok and not session.dirty, "saved there")
		sim.debug_set_energy(0.0)
		var bot = ForageBot.new()
		bot.park_at = STARVE_SPOT
		_play(sim, bot, DEATH_LIMIT_TICKS, func() -> bool: return sim.dead)
		check(sim.dead and sim.motion.position.distance_to(sim.checkpoint().position) > GameSession.DIRTY_MOVE_M,
			"died away from the checkpoint")
		check(session.dirty, "save on death %s: an unresolved death is an unsaved change" % on)
		session.resolve_death()
		check_eq(session.dirty, not on, "save on death %s: dirty while the notice is open" % on)
		session.respawn_after_death()
		check_eq(session.dirty, not on, "save on death %s: dirty after the respawn at the checkpoint" % on)
		check(sim.debug_teleport(sim.checkpoint().position + Vector2(1.5, 0.0)), "moved on")
		check(session.dirty, "moving over a meter from the checkpoint is a change")


func test_a_life_of_ninety_seconds_resets_the_death_streak_and_its_shelter() -> void:
	# Plan test_checkpoints #5, plus the boundary: a death 89 s after the respawn grows the streak.
	var session := GameSession.new(slot)
	check(session.start_new("grazer", 4444).ok, "started")
	var sim := session.sim
	var bot = ForageBot.new()
	bot.park_at = sim.checkpoint().position
	var lives := [{"live_s": 10, "streak": 1, "grace": 300}, {"live_s": 89, "streak": 2, "grace": 480},
		{"live_s": 91, "streak": 1, "grace": 300}]
	for life in lives:
		sim.debug_set_energy(sim.state.energy_capacity)   # it lives on its stores, never starving
		_play(sim, bot, int(life.live_s) * 60)
		check(sim.debug_hurt_player(sim.state.max_health), "killed after %d s" % life.live_s)
		session.respawn_after_death()
		check_eq(sim.death_streak, int(life.streak), "after a life of %d s the streak is %d" % [life.live_s, life.streak])
		check_eq(sim.grace_until - sim.tick, int(life.grace), "and the shelter %.0f s" % (int(life.grace) / 60.0))
		sim.drain_events()


func test_the_killer_ignores_the_cell_for_thirty_seconds_after_the_respawn_and_then_notices_it() -> void:
	# Plan test_checkpoints #6: back in front of the lair that killed it, as soon as the shelter ends.
	var session := GameSession.new(slot)
	check(session.start_new("grazer", 4545).ok, "started")
	var sim := session.sim
	sim.grace_until = sim.tick
	var hunter := _at_site(sim, "lair_se")
	check(hunter != null, "lair_se has its hunter")
	if hunter == null:
		return
	var spot: Vector2 = hunter.brain.home + Vector2.from_angle(hunter.brain.home_heading) * IN_FRONT_M
	check(sim.debug_teleport(spot, hunter.brain.home_heading), "in front of it")
	var bot = ForageBot.new()
	bot.park_at = spot
	var before := _play(sim, bot, DEATH_LIMIT_TICKS, func() -> bool: return sim.dead)
	check(sim.dead and sim.death.by == hunter.id, "killed by lair_se's hunter")
	check(before.any(func(e: Dictionary) -> bool: return e.type == "creature_noticed" and e.id == hunter.id), "which had noticed it")
	# C3 names only the killer: every other brain's ignore entry for the cell (-1 for none) is as it was.
	var others := {}
	for c in sim.creatures.creatures:
		if c.brain != null and c != hunter:
			others[c.id] = int(c.brain.ignore.get(PLAYER, -1))
	check(others.size() >= 2, "other creatures in the pool (%d)" % others.size())
	session.respawn_after_death()
	var respawn_tick := sim.tick
	var ignore_until := respawn_tick + sim.species.killer_ignore_ticks
	check_eq(int(hunter.brain.ignore.get(PLAYER, -1)), ignore_until, "the killer ignores the cell for 30 s")
	for c in sim.creatures.creatures:
		if others.has(c.id):
			check_eq(int(c.brain.ignore.get(PLAYER, -1)), int(others[c.id]), "%s, not the killer, gains no ignore on the cell" % c.id)
	_play(sim, bot, sim.grace_until - sim.tick)
	check(sim.debug_teleport(spot, hunter.brain.home_heading), "back in front of the lair when the shelter ends")
	var noticed := []
	var events := _play(sim, bot, ignore_until + 120 - sim.tick, func() -> bool: return not noticed.is_empty())
	for e in events:
		if e.type == "creature_noticed" and e.id == hunter.id and e.target == PLAYER:
			noticed.append(int(e.tick))
	check(not noticed.is_empty(), "it notices the cell once the 30 s are over")
	if not noticed.is_empty():
		check(noticed[0] >= ignore_until, "not before (noticed %.2f s after the respawn)" % ((noticed[0] - respawn_tick) * PoolSim.DT))
		check(noticed[0] <= ignore_until + 6, "but on its first think after (%d ticks late)" % (noticed[0] - ignore_until))
	check(not sim.dead, "the cell was alive in front of it all along")


func test_creatures_near_the_checkpoint_are_sent_home_and_forget_the_cell_at_the_respawn() -> void:
	# Plan test_checkpoints #7 (C2, C3), in the open fixture: two dev creatures whose homes are far
	# out have come within 12 m of the checkpoint and seen the cell; a third stays beyond 12 m, and
	# a fourth is just inside 12 m when the cell dies (the radius's edge, not only the middle).
	var catalog := PartCatalog.load_from()
	var fixture := PoolLayout.load_from(THREATS_FIXTURE)
	var r := Lineage.found(4646, "test+dev", catalog, "hunter")
	r.save.player["position"] = PlaneSpace.to_save(fixture.spawn)
	var sim := PoolSim.create(r.save, catalog, fixture, SpeciesCatalog.load_from(TEST_SPECIES))
	sim.grace_until = sim.tick
	var cp: Vector2 = sim.checkpoint().position
	# [species, home, where it has come to], relative to the checkpoint: two in sight of it, one 14 m
	# off, and one whose home is 20 m off (moved to 11.5 m below, after the warm-up, so it cannot
	# drift back toward its home first).
	var placed := [["ambush_hunter", Vector2(12.0, 0.0), Vector2(5.0, 0.0)], ["rammer", Vector2(-14.0, 0.0), Vector2(-5.0, 1.0)],
		["ambush_hunter", Vector2(0.0, -20.0), Vector2(0.0, -14.0)], ["ambush_hunter", Vector2(-20.0, 0.0), Vector2(-20.0, 0.0)]]
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
	var edge := made[3]
	edge.motion.place(cp + Vector2(-11.5, 0.0), 0.0)
	check(edge.brain.home.distance_to(cp) > 12.0, "%s's home is beyond 12 m" % edge.id)
	check(sim.debug_hurt_player(sim.state.max_health), "the cell dies")
	sim.drain_events()
	# Each brain's ignore entry for the cell (-1 for none) once the death is over (a chase on the
	# cell ends in a give-up and its own short ignore), for C3 after the respawn.
	var ignored := {}
	for c in made:
		ignored[c.id] = int(c.brain.ignore.get(PLAYER, -1))
	sim.respawn_player()
	var respawned := sim.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "respawned")
	var near: Array[CreatureField.Creature] = [made[0], made[1], edge]
	var near_ids := near.map(func(c: CreatureField.Creature) -> String: return c.id)
	near_ids.sort()
	check(respawned.size() == 1 and respawned[0].relocated == near_ids,
		"respawned names the three sent home, 11.5 m out included, by id: %s" % [respawned])
	for c in near:
		check_eq(c.motion.position, c.brain.home, "%s is at its home" % c.id)
		check_eq(c.motion.heading, c.brain.home_heading, "facing its home heading")
		check_eq(c.motion.velocity, Vector2.ZERO, "at rest")
		check(not c.brain.seen.has(PLAYER) and c.brain.target != PLAYER and not c.brain.landed_on.has(PLAYER),
			"%s has no memory of the cell" % c.id)
		check(c.brain.state == CreatureBrain.REST, "and rests (%s)" % c.brain.state)
	check_eq(made[2].motion.position, far, "the one beyond 12 m stays where it was")
	check(not made[2].brain.seen.has(PLAYER), "but forgets the cell too")
	# C3: a dev kill has no killer, so the respawn gives no brain an ignore on the cell.
	for c in made:
		check_eq(int(c.brain.ignore.get(PLAYER, -1)), int(ignored[c.id]), "%s's ignore on the cell is as it was" % c.id)


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


func test_a_step_2_save_continues_sheltered_with_creatures_and_is_not_rewritten() -> void:
	# Plan test_checkpoints #8: the slot the step 2 build wrote, copied to a temp slot.
	DirAccess.make_dir_recursive_absolute(SaveFolder.dir())
	var bytes := FileAccess.get_file_as_bytes(STEP2_SAVE)
	check(bytes.size() > 0, "the fixture is readable")
	var out := FileAccess.open(slot, FileAccess.WRITE)
	out.store_buffer(bytes)
	out.close()
	var files := _files()
	var session := GameSession.new(slot)
	var r := session.continue_run()
	check(r.ok and r.source == "primary", "continued: %s" % [r])
	check_eq(_files(), files, "the file's bytes and time are unchanged by the load")
	check_eq(FileAccess.get_file_as_bytes(slot), bytes, "byte for byte")
	if not r.ok:
		return
	var sim := session.sim
	check_eq(sim.save.adaptation_points, 16, "its points")
	check_eq(sim.save.lineage_history.size(), 2, "its history: founded, died")
	check(sim.motion.position.distance_to(Vector2(-1.300788, 3.253892)) < 1e-3, "at its mid-run place: %s" % sim.motion.position)
	check(sim.creatures != null and sim.creatures.creatures.size() + sim.creatures.queue.size() == 7,
		"every site has its creature or waits for it")
	check(sim.creatures.creatures.size() > 0, "creatures are present (%d)" % sim.creatures.creatures.size())
	check(sim.is_sheltered() and sim.grace_until - sim.tick == 300, "the cell starts sheltered for 5 s")
	check(not session.dirty, "nothing unsaved")


## S3G26 (S3 T0.7; D-107, D-132, BP3-8; endless-cell-plan F7): the 10 tests' checkpoint rules at
## LANDMARK_CHECKPOINTS landmark checkpoints at size 4, on the shipped world with its top at 4. The
## cell is put by each anchor round home in turn (nearest first, the creatures still) until the
## landmark pass moves the checkpoint there; it then dies with the creatures acting. Each checkpoint:
## a clear point within the bounded spiral of its anchor at size 4 (#9's rule); the respawn there,
## facing its heading, with full health, no cooldowns, its streak's shelter and energy, sheltered and
## concealed (#1, #5); an awake creature put LANDMARK_CROWD_TM from it while the cell was dead is sent
## home, and no q == 1 creature is within respawn_clear_m (#7; a landmark checkpoint counts only q 1,
## as fuzz invariant 3); every brain forgets the cell, the token is free and, a dev kill having no
## killer, no brain gains an ignore (#6, #7); through the shelter nothing notices, strikes or stings
## the cell, and the shelter ends on its last tick (#1, #8); every LANDMARK_EDGE_EVERY-th checkpoint
## gets a collider whose edge is 0.2 tm off it at the respawn, and the cell comes back clear within
## two rings of it (#10). One anchor, tried after LANDMARK_BLOCKED_AFTER moves, sits under a collider
## of ChunkArena.MAX_COLLIDER_R (the spiral's reach): it is refused ("no_clear_point") and the
## checkpoint stays (BP3-8; the mutation is the unbounded spiral). The save-side tests (#2 to #4, #8's
## step-2 file) do not depend on where the checkpoint is: S3G33 continues a size-4 save.
func test_soak_at_fifty_landmark_checkpoints_at_size_4_every_respawn_is_fair() -> void:
	var sim: PoolSim = Gates.make_sim_at("omnivore", LANDMARK_SEED, 4)
	check(sim != null, "the size-4 sim")
	if sim == null:
		return
	var w := sim.world
	check_eq([sim.size(), w.max_size], [4, 4], "at size 4, the top")
	check(bool(w.content.config.switches.get("landmark_return", false)), "the landmark return is on")
	var reach := float(w.content.config.growth.discovery.landmark_find_tm)
	var spiral := WorldStream.LANDMARK_SPIRAL_RINGS * PoolSim.CLEAR_SPIRAL_STEP_M
	var clear_m := float(sim.species.fairness.respawn_clear_m)
	var anchors := _landmark_anchors(sim)
	var refused := {}
	var moved := 0
	var blocked := ""
	var crowded := 0
	var edged := 0
	var streak := sim.death_streak
	for a in anchors:
		if moved >= LANDMARK_CHECKPOINTS:
			break
		var block := blocked.is_empty() and moved == LANDMARK_BLOCKED_AFTER
		var at := "anchor %s" % a.id
		var before := w.checkpoint_am.duplicate()
		var got := _to_landmark(sim, a, block)
		if block:
			blocked = str(a.id)
			check_eq(got.reason, "no_clear_point", "%s under a collider of %.0f tm: refused (%s)" % [at, ChunkArena.MAX_COLLIDER_R, got])
			check_eq(w.checkpoint_am, before, "%s: the checkpoint stays" % at)
			_unblock(sim, got.get("key", Vector2i.ZERO), got.get("kept", []))
			continue
		if not got.moved:
			refused[got.reason] = int(refused.get(got.reason, 0)) + 1
			continue
		moved += 1
		at = "checkpoint %d (%s)" % [moved, a.id]
		var cp := w.checkpoint_local()
		var heading := float(w.checkpoint_am[2])
		check_eq(int(w.checkpoint_am[3]), 4, "%s: at size 4" % at)
		check(sim.arena.is_clear(cp, sim.phenotype.radius), "%s: a clear point" % at)
		var off := cp.distance_to(w.local_of_tm(float(a.x), float(a.y)))
		check(off <= spiral + 1e-4, "%s: within the spiral of its anchor (%.2f tm)" % [at, off])
		# The death, with the creatures acting.
		sim.debug_set_ai_frozen(false)
		_hold(sim, LANDMARK_SETTLE_TICKS)
		if sim.dead:
			check(false, "%s: the cell died before the test killed it (%s)" % [at, sim.death])
			return
		var alive := sim._alive_ticks
		check(sim.debug_hurt_player(1.0e9) and sim.dead, "%s: the cell dies" % at)
		var ignored := {}
		for c in sim.creatures.creatures:
			if c.brain != null:
				ignored[c.id] = int(c.brain.ignore.get(PLAYER, -1))
		_hold(sim, NOTICE_TICKS)
		var crowd := _crowd_the_checkpoint(sim, cp)
		var edge := {}
		if moved % LANDMARK_EDGE_EVERY == 0:
			edge = _edge_the_checkpoint(sim, cp, w.local_of_tm(float(a.x), float(a.y)))
			check(not edge.is_empty() and not sim.arena.is_clear(cp, sim.phenotype.radius), "%s: blocked for the respawn" % at)
		var next_streak := streak + 1 if alive < sim.species.streak_window_ticks else 1
		var energy := sim.growth.respawn_energy(sim.state.energy_capacity,
			RespawnRules.pick(sim.species.respawn_energy_share, next_streak), 4)
		sim.respawn_player()
		var t := sim.tick
		var events := _hold(sim, 1)
		var respawned := events.filter(func(e: Dictionary) -> bool: return e.type == "respawned")
		check_eq(respawned.size(), 1, "%s: one respawned" % at)
		if respawned.size() != 1:
			return
		var r: Dictionary = respawned[0]
		streak = sim.death_streak
		check_eq(int(r.streak), next_streak, "%s: the streak after a life of %.1f s" % [at, alive * PoolSim.DT])
		check_eq(r.get("teleport"), false, "%s: back without a teleport" % at)
		var grace := roundi(float(r.grace_s) * CreatureBrain.TICKS_PER_SECOND)
		check_eq(grace, int(RespawnRules.pick(sim.species.grace_ticks, streak)), "%s: the streak's shelter" % at)
		check_eq(sim.grace_until, t + grace, "%s: sheltered from the respawn" % at)
		check_eq(sim.state.health, sim.state.max_health, "%s: full health" % at)
		check_near(float(r.energy), energy, 1e-9, "%s: the streak's energy, capped over the death's (D-35)" % at)
		check(sim.state.energy > 0.0 and sim.state.energy <= float(r.energy), "%s: and the cell has it, less a tick" % at)
		check(sim.actor.cooldowns.is_empty(), "%s: no cooldowns" % at)
		check(sim.is_sheltered() and sim.is_concealed(), "%s: sheltered and concealed" % at)
		if edge.is_empty():
			check(sim.motion.position.distance_to(cp) < 0.01, "%s: at the checkpoint (%.3f tm off)" % [at, sim.motion.position.distance_to(cp)])
			check_eq(sim.motion.heading, heading, "%s: facing its heading" % at)
		else:
			edged += 1
			var d := sim.motion.position.distance_to(cp)
			check(sim.arena.is_clear(sim.motion.position, sim.phenotype.radius), "%s: back clear of the collider" % at)
			check(d > 0.0 and d <= PoolSim.CLEAR_SPIRAL_STEP_M * 2.0 + 1e-4, "%s: within two rings of it (%.2f tm)" % [at, d])
			_unblock(sim, edge.key, edge.kept)
		if not crowd.is_empty():
			crowded += 1
			check(Array(r.relocated).has(crowd.id), "%s: %s, %.0f tm off, sent home (%s)" % [at, crowd.id, LANDMARK_CROWD_TM, r.relocated])
		for c in sim.creatures.creatures:
			if c.debug or sim.species.q_of(c.species_id, 4) != 1.0:
				continue
			var gap := c.motion.position.distance_to(sim.motion.position) - c.phenotype.radius
			check(gap >= clear_m, "%s: %s (q 1) is %.2f tm off (at least %.0f)" % [at, c.id, gap, clear_m])
		for c in sim.creatures.creatures:
			if c.brain == null:
				continue
			check(not c.brain.seen.has(PLAYER) and c.brain.target != PLAYER, "%s: %s forgot the cell" % [at, c.id])
			if ignored.has(c.id):
				check_eq(int(c.brain.ignore.get(PLAYER, -1)), int(ignored[c.id]), "%s: %s gains no ignore" % [at, c.id])
		check(sim.creatures.engaged_on_player.is_empty(), "%s: the token is free" % at)
		var until := sim.grace_until
		var during := _hold(sim, until - sim.tick + 1)
		var threats := during.filter(func(e: Dictionary) -> bool:
			return int(e.tick) < until and ((e.type == "hit" and e.target == PLAYER)
				or (e.type == "creature_noticed" and e.target == PLAYER)))
		check(threats.is_empty(), "%s: nothing notices, strikes or stings the sheltered cell: %s" % [at, threats])
		var ended := during.filter(func(e: Dictionary) -> bool: return e.type == "grace_ended")
		check(ended.size() == 1 and ended[0].reason == "timeout" and int(ended[0].tick) == until - 1,
			"%s: the shelter ended on its last tick (%s)" % [at, ended])
		if sim.dead:
			check(false, "%s: the cell died in the shelter (%s)" % [at, sim.death])
			return
	print("test-checkpoints: S3G26 %d landmark checkpoints of %d anchors at size 4; refused %s; blocked %s; %d crowded, %d edged; streak %d" % [
		moved, anchors.size(), refused, blocked, crowded, edged, streak])
	check_eq(moved, LANDMARK_CHECKPOINTS, "%d landmark checkpoints" % LANDMARK_CHECKPOINTS)
	check(not blocked.is_empty(), "a blocked anchor was tried")
	check(crowded >= LANDMARK_CHECKPOINTS / 2, "a creature crowded at least half the checkpoints (%d)" % crowded)
	check_eq(edged, LANDMARK_CHECKPOINTS / LANDMARK_EDGE_EVERY, "the edge cases")


## The anchors of the chunks within LANDMARK_CHUNKS of home at size 4, nearest home first.
func _landmark_anchors(sim: PoolSim) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cy in range(-LANDMARK_CHUNKS, LANDMARK_CHUNKS + 1):
		for cx in range(-LANDMARK_CHUNKS, LANDMARK_CHUNKS + 1):
			for a in sim.world.gen.chunk(4, cx, cy).anchors:
				out.append(a)
	out.sort_custom(func(p: Dictionary, q: Dictionary) -> bool:
		var dp := Vector2(p.x, p.y).length()
		var dq := Vector2(q.x, q.y).length()
		return dp < dq or (dp == dq and str(p.id) < str(q.id)))
	return out


## Puts the cell, fed and still, by anchor `a` with every brain frozen and holds it there until the
## landmark pass moves the checkpoint to `a` or LANDMARK_WAIT_TICKS pass. `block` covers the anchor
## first with a collider of ChunkArena.MAX_COLLIDER_R (the cell just outside it, within reach).
## {moved, reason (the candidate's refusal), key and kept (the blocked chunk and its colliders)}.
func _to_landmark(sim: PoolSim, a: Dictionary, block: bool) -> Dictionary:
	var w := sim.world
	var k := WorldConfig.tm_to_am(4)
	var near := LANDMARK_NEAR_TM if not block else ChunkArena.MAX_COLLIDER_R + sim.phenotype.radius + 0.5
	var p := Vector2(float(a.x), float(a.y)) + Vector2(near, 0.0)
	sim.debug_set_ai_frozen(true)
	sim.debug_teleport_abs(p.x * k, p.y * k, PI)
	sim.debug_set_energy(sim.state.energy_capacity)
	var out := {"moved": false, "reason": ""}
	if block:
		var key := w.chunk_of_local(w.local_of_tm(float(a.x), float(a.y)))
		out["key"] = key
		out["kept"] = _block(sim, key, Vector2(float(a.x), float(a.y)), ChunkArena.MAX_COLLIDER_R)
		w._landmark_points.erase(a.id)
	for i in LANDMARK_WAIT_TICKS:
		for e in _hold(sim, 1):
			if e.type == "checkpoint_moved" and e.reason == "landmark":
				out.moved = str(e.anchor) == str(a.id)
				out.reason = "" if out.moved else "another anchor (%s)" % e.anchor
				return out
		if i >= LANDMARK_SETTLE_TICKS and not block and w.landmark_candidate(sim, a).reason in ["reach", "no_clear_point"]:
			break   # a lasting refusal: the next anchor
	var cand := w.landmark_candidate(sim, a)
	out.reason = cand.reason if not cand.ok else "out of reach"
	return out


## Adds a collider of radius `r` at `center` (abs tm) to loaded chunk `key`; its colliders before.
func _block(sim: PoolSim, key: Vector2i, center: Vector2, r: float) -> Array:
	var arena := sim.arena as ChunkArena
	check(arena.has_chunk(key), "chunk %s is loaded" % key)
	var kept: Array = arena._chunk_colliders.get(key, []).duplicate(true)
	var more: Array[Dictionary] = []
	for c in kept:
		more.append(c)
	more.append({"id": "s3g26_block", "x": center.x, "y": center.y, "r": r})
	arena.remove_chunk(key)
	arena.add_chunk(key, more)
	return kept


## Puts chunk `key`'s colliders back as `kept`.
func _unblock(sim: PoolSim, key: Vector2i, kept: Array) -> void:
	var arena := sim.arena as ChunkArena
	if not arena.has_chunk(key):
		return
	var back: Array[Dictionary] = []
	for c in kept:
		back.append(c)
	arena.remove_chunk(key)
	arena.add_chunk(key, back)


## #10's case: a collider of 2 tm whose edge is 0.2 tm off the checkpoint, on the side of its anchor
## `anchor_at` (the landmark's collider is there already, so the open water stays open).
func _edge_the_checkpoint(sim: PoolSim, cp: Vector2, anchor_at: Vector2) -> Dictionary:
	var w := sim.world
	var r := 2.0
	var toward := (anchor_at - cp).normalized()
	for dir: Vector2 in [toward, toward.orthogonal(), -toward.orthogonal()]:
		var at := cp + dir * (r + 0.2)
		var a := w.abs_of_local(at)
		var k := WorldConfig.tm_to_am(4)
		var key := w.chunk_of_local(at)
		if not (sim.arena as ChunkArena).has_chunk(key):
			continue
		return {"key": key, "kept": _block(sim, key, Vector2(a[0] / k, a[1] / k), r)}
	return {}


## #7's case: the nearest awake creature with a brain (not a veil) put LANDMARK_CROWD_TM from the
## checkpoint at a clear point, while the cell is dead. {id} or {} for none.
func _crowd_the_checkpoint(sim: PoolSim, cp: Vector2) -> Dictionary:
	var best: CreatureField.Creature = null
	for c in sim.creatures.creatures:
		if c.asleep or c.debug or c.brain == null or c.brain.behavior == CreatureBrain.HAZARD:
			continue
		if best == null or c.motion.position.distance_to(cp) < best.motion.position.distance_to(cp):
			best = c
	if best == null:
		return {}
	for i in 8:
		var at := cp + Vector2.from_angle(TAU * i / 8.0) * LANDMARK_CROWD_TM
		if sim.arena.is_clear(at, best.phenotype.radius):
			best.motion.place(at, best.motion.heading)
			best.actor.position = at
			return {"id": best.id}
	return {}


## Steps the still cell `ticks` times; the events, each stamped with its tick.
func _hold(sim: PoolSim, ticks: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in ticks:
		var t := sim.tick
		sim.step(SimIntent.new())
		if not sim.dead and not sim.respawn_pending:
			sim.motion.velocity = Vector2.ZERO
		for e in sim.drain_events():
			e["tick"] = t
			out.append(e)
	return out
