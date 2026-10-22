extends TestCase
## Save, quit and continue bring back the same lineage, body, points and place, using the
## existing v2 save schema; a death is applied once (test_checkpoints covers the death flow in
## full). Saves go to a per-process folder under user://test_saves.

const SaveFolder := preload("res://tests/save_folder.gd")
const ForageBot := preload("res://game/dev/forage_bot.gd")
## The v2 save's top-level keys. A field added without a schema version and migration fails here.
const V2_KEYS := ["adaptation_points", "build_id", "discoveries", "era", "genome", "lineage_history",
	"lineage_id", "pending_transactions", "player", "relationships", "saved_at_unix", "schema_version",
	"settlements", "world_changes", "world_seed"]

var slot := ""
var _swept := false


func before_each() -> void:
	if not _swept:
		SaveFolder.sweep_stale()
		_swept = true
	SaveFolder.clear()
	slot = SaveFolder.path("session_slot.json")


func after_each() -> void:
	SaveFolder.clear()


func _play(session: GameSession, ticks: int) -> void:
	var bot = ForageBot.new()
	for i in ticks:
		session.sim.step(bot.next_intent(session.sim))


func _files() -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(SaveFolder.dir()):
		var path := SaveFolder.path(f)
		out[f] = [FileAccess.get_modified_time(path), FileAccess.get_file_as_string(path)]
	return out


func test_continue_brings_back_the_same_lineage_body_points_and_place() -> void:
	var session := GameSession.new(slot)
	var started := session.start_new("omnivore", 5150)
	check(started.ok and started.saved, "started and saved: %s" % [started.errors])
	if not started.ok:
		return
	_play(session, 600)
	var before: SaveGame = session.sim.save
	check(before.adaptation_points > 0, "the bot ate something in 10 s")
	var saved := session.save_now()
	check(saved.ok, "saved: %s" % saved.error)
	var position := session.sim.motion.position
	# The slot holds this save and the backup holds the start, so a re-save would change both.
	var files := _files()

	var again := GameSession.new(slot)
	var r := again.continue_run()
	check(r.ok, "continued: %s" % [r.errors])
	check_eq(_files(), files, "continuing rewrote nothing: file list, times and contents")
	if not r.ok:
		return
	check_eq(r.source, "primary", "from the primary file")
	var loaded: SaveGame = again.sim.save
	check_eq(loaded.lineage_id, before.lineage_id, "lineage id")
	check_eq(JSON.stringify(loaded.genome.to_dict()), JSON.stringify(before.genome.to_dict()), "genome")
	check_eq(Lineage.starting_body_of(loaded.genome, again.catalog), "omnivore", "still the omnivore")
	check_eq(loaded.adaptation_points, before.adaptation_points, "points")
	check_eq(loaded.world_seed, 5150, "seed")
	# Through JSON whole numbers come back as floats, so compare both sides as saved.
	var saved_history := JSON.stringify(JSON.parse_string(JSON.stringify(before.lineage_history)))
	check_eq(JSON.stringify(loaded.lineage_history), saved_history, "history")
	check(again.sim.motion.position.distance_to(position) < 1e-3, "place: %s vs %s" % [again.sim.motion.position, position])
	check_near(again.sim.state.energy, again.sim.state.energy_capacity * 0.6, 1e-9, "a rested cell (energy is not saved)")
	check(not again.dirty, "nothing unsaved right after continuing")


func test_a_saved_file_has_exactly_the_v2_keys() -> void:
	var session := GameSession.new(slot)
	session.start_new("grazer", 1)
	_play(session, 120)
	session.save_now()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(slot))
	var keys := data.keys()
	keys.sort()
	check_eq(keys, V2_KEYS, "top-level keys")
	check_eq(int(data.schema_version), 2, "schema version")
	check_eq(data.player.keys(), ["position"], "the player holds only a position")
	check_eq(data.player.position.size(), 3, "three numbers")


func test_a_corrupt_save_continues_from_the_backup_and_peek_says_so() -> void:
	var session := GameSession.new(slot)
	session.start_new("hunter", 2)
	_play(session, 300)
	session.save_now()
	var lineage := session.sim.save.lineage_id
	var f := FileAccess.open(slot, FileAccess.WRITE)
	f.store_string("{ not a save")
	f.close()
	var files := _files()
	var again := GameSession.new(slot)
	var peek := again.peek_slot()
	check(peek.exists and peek.ok, "peek finds a usable save")
	check_eq(peek.source, "backup", "peek reports the backup")
	check(not peek.errors.is_empty(), "and why the primary failed")
	var r := again.continue_run()
	check(r.ok, "continued")
	check_eq(r.source, "backup", "from the backup")
	check_eq(_files(), files, "the damaged file stays as it was until the player saves")
	if r.ok:
		check_eq(again.sim.save.lineage_id, lineage, "the same lineage")
		check_eq(again.load_source, "backup", "load source kept for the debug panel")


func test_peek_describes_the_slot_without_writing() -> void:
	var empty := GameSession.new(slot)
	var nothing := empty.peek_slot()
	check(not nothing.exists and not nothing.ok, "no save yet")
	check(not DirAccess.dir_exists_absolute(SaveFolder.dir()), "peek created nothing")

	var session := GameSession.new(slot)
	session.start_new("grazer", 3)
	_play(session, 300)
	session.save_now()
	var files := _files()
	var peek := GameSession.new(slot).peek_slot()
	check_eq(_files(), files, "file list, times and contents unchanged")
	check(peek.ok, "readable")
	check_eq(peek.source, "primary", "primary")
	var summary: Dictionary = peek.summary
	check_eq(summary.lineage_id, session.sim.save.lineage_id, "lineage")
	check_eq(summary.lineage_tag, GameSession.lineage_tag(session.sim.save.lineage_id), "tag")
	check_eq(summary.body, "grazer", "body")
	check_eq(summary.generation, 1, "generation")
	check_eq(summary.adaptation_points, session.sim.save.adaptation_points, "points")
	check(summary.saved_at_unix > 0, "saved time")
	check(summary.genome is Genome, "genome for the preview")


func test_a_new_lineage_over_a_save_keeps_the_old_one_as_the_backup() -> void:
	var first := GameSession.new(slot)
	first.start_new("grazer", 4)
	var old_lineage := first.sim.save.lineage_id
	var second := GameSession.new(slot)
	var started := second.start_new("hunter", 5)
	check(started.ok and started.saved, "started")
	var backup := PersistenceService.new(second.catalog).load_from(slot + ".bak")
	check(backup.ok, "the backup loads")
	if backup.ok:
		check_eq(backup.save.lineage_id, old_lineage, "it is the old lineage")
	var primary := PersistenceService.new(second.catalog).load_from(slot)
	check_eq(primary.save.lineage_id, second.sim.save.lineage_id, "the slot holds the new one")
	check(old_lineage != second.sim.save.lineage_id, "two different lineages")


func test_a_saved_position_inside_a_rock_continues_from_the_spawn() -> void:
	var session := GameSession.new(slot)
	session.start_new("grazer", 6)
	session.sim.save.player["position"] = PlaneSpace.to_save(Vector2(12.0, 0.3))
	PersistenceService.new(session.catalog).save_to(slot, session.sim.save)
	var again := GameSession.new(slot)
	check(again.continue_run().ok, "continued")
	check(again.sim.motion.position.is_equal_approx(again.layout.spawn), "back at the spawn: %s" % again.sim.motion.position)
	check(again.sim.arena.is_clear(again.sim.motion.position, again.sim.phenotype.radius), "in open water")


func test_a_cell_saved_while_pressed_against_a_rock_continues_in_place() -> void:
	# Pushing out of a rock leaves the cell within float32 rounding of its surface. rock_09 is one
	# where that lands a micrometre inside from some sides, which once sent Continue to the spawn.
	var session := GameSession.new(slot)
	session.start_new("grazer", 9)
	var sim := session.sim
	var rock := {}
	for r in sim.arena.rocks:
		if r.id == "rock_09":
			rock = r
	check(not rock.is_empty(), "the layout has rock_09")
	if rock.is_empty():
		return
	var touching: float = rock.radius + sim.phenotype.radius
	var pressed := 0
	for k in 16:
		var out := Vector2.from_angle(k * TAU / 16.0)
		if not sim.debug_teleport(rock.center + out * (touching + 0.05), (-out).angle()):
			continue
		for i in 30:
			sim.step(SimIntent.new(-out))
		var saved_at := sim.motion.position
		if absf(saved_at.distance_to(rock.center) - touching) > 1e-3:
			continue
		pressed += 1
		check(session.save_now().ok, "saved")
		var again := GameSession.new(slot)
		if not again.continue_run().ok:
			check(false, "continued after saving at %s" % saved_at)
			continue
		var back := again.sim.motion.position
		check(back.distance_to(saved_at) < 1e-3, "pressed from %d deg: saved at %s, continued at %s"
			% [k * 360 / 16, saved_at, back])
	check(pressed >= 12, "the cell was pressed against the rock from %d of 16 sides" % pressed)


func test_unsaved_changes_are_tracked() -> void:
	var session := GameSession.new(slot)
	check(not session.dirty, "no run, nothing unsaved")
	session.start_new("omnivore", 7)
	check(not session.dirty, "the start was saved")
	session.sim.debug_teleport(session.sim.motion.position + Vector2(0.5, 0.0))
	check(not session.dirty, "moving half a meter is not worth a prompt")
	session.sim.debug_teleport(session.sim.motion.position + Vector2(1.0, 0.0))
	check(session.dirty, "moving over a meter is")
	session.save_now()
	check(not session.dirty, "saved")
	Lineage.earn(session.sim.save, 1)
	check(session.dirty, "points changed")


func test_a_death_is_resolved_once_and_the_respawn_after_it_takes_nothing_more() -> void:
	# Plan section 13: resolve_death() applies the death (and saves it, OD1); respawn_after_death()
	# only brings the cell back. A step 2 caller that only respawns still pays once (test_pool_sim).
	var session := GameSession.new(slot)
	check(session.start_new("grazer", 8).ok, "started")
	var sim := session.sim
	Lineage.earn(sim.save, 20)
	check_eq(session.resolve_death(), {}, "nothing to resolve while alive")
	check_eq(session.respawn_after_death(), 0, "nor to respawn")
	sim.debug_set_energy(0.0)
	for i in 25 * 60:
		sim.step(SimIntent.new())
		if sim.dead:
			break
	check(sim.dead, "starved")
	var resolved := session.resolve_death()
	check_eq(resolved.cause, "starved", "the history cause")
	check_eq(resolved.lost, 5, "a quarter of 20")
	check_eq(resolved.reason, "", "no killer's reason")
	check_eq(resolved.tip, GameSession.STARVED_TIP, "the starving tip")
	check(resolved.saved.attempted and resolved.saved.ok, "saved at once")
	check_eq(session.resolve_death(), resolved, "resolving again changes nothing")
	check_eq(sim.save.adaptation_points, 15, "applied once")
	check_eq(session.respawn_after_death(), 5, "the respawn reports the loss")
	check_eq(sim.save.adaptation_points, 15, "and takes nothing more")
	var deaths := sim.save.lineage_history.filter(func(e: Dictionary) -> bool: return e.event == "died")
	check_eq(deaths.size(), 1, "one death in the history")
	check(not sim.dead and session.death.is_empty(), "alive, with no death pending")
	check_eq(session.respawn_after_death(), 0, "a second respawn does nothing")


func test_a_starving_death_tip_names_only_food_the_body_can_eat() -> void:
	# A hunter's jaw eats only carrion, which since step 3 comes only from kills (D1): its starving
	# tip must say so, not send it to plankton it cannot eat. Each starting body starves for real.
	for body in BodyText.ORDER:
		var session := GameSession.new(slot)
		check(session.start_new(body, 12).ok, "%s started" % body)
		var sim := session.sim
		sim.debug_set_energy(0.0)
		for i in 25 * 60:
			sim.step(SimIntent.new())
			if sim.dead:
				break
		check(sim.dead, "the %s starved" % body)
		if not sim.dead:
			continue
		var tip := str(session.resolve_death().tip)
		check_eq(tip, GameSession.starved_tip(sim.phenotype), "the %s gets its body's starving tip" % body)
		check(sim.phenotype.can_eat("plant") or not tip.to_lower().contains("plankton"),
			"the %s cannot eat plankton and is not sent to it: %s" % [body, tip])
		check(sim.phenotype.can_eat("meat") or not tip.to_lower().contains("carrion"),
			"the %s cannot eat carrion and is not sent to it: %s" % [body, tip])
		if body == "hunter":
			check(tip.contains("carrion") or tip.contains("Carrion"), "the hunter's tip names its food: %s" % tip)
			check(tip.contains("kills"), "and where it comes from: %s" % tip)
		session.respawn_after_death()


func test_a_session_runs_the_threats_by_default_and_the_step_2_pool_without_species_data() -> void:
	var session := GameSession.new(slot)
	check(session.species != null and session.start_new("grazer", 10).ok, "started with the species data")
	check(session.sim.creatures != null and session.sim.creatures.creatures.size() == 7, "seven creatures")
	check(session.sim.is_sheltered(), "the new lineage starts sheltered")
	var plain := GameSession.new(slot, PoolLayout.DEFAULT_PATH, "")
	check(plain.species == null and plain.continue_run().ok, "continued without species data")
	check(plain.sim.creatures == null and not plain.sim.is_sheltered(), "the step 2 pool: no creatures, no shelter")


func test_unusable_species_data_stops_a_new_lineage_and_a_continue() -> void:
	check(GameSession.new(slot).start_new("grazer", 11).ok, "a save to continue")
	var broken := GameSession.new(slot, PoolLayout.DEFAULT_PATH, "res://tests/fixtures/no_such_species.json")
	var r := broken.start_new("grazer", 11)
	check(not r.ok and broken.sim == null, "no new lineage")
	check_has_error(r.errors, "missing or not readable")
	var c := broken.continue_run()
	check(not c.ok and broken.sim == null, "no continue")
	check_has_error(c.errors, "missing or not readable")


func test_starting_needs_a_known_body_and_picks_a_seed_when_none_is_given() -> void:
	var session := GameSession.new(slot)
	var r := session.start_new("kraken", 1)
	check(not r.ok, "refused")
	check_has_error(r.errors, "Unknown starting body")
	check(session.sim == null, "no run")
	check(not FileAccess.file_exists(slot), "nothing written")
	check_eq(session.save_now().error, "There is no run to save.", "nothing to save")
	var random := session.start_new("grazer")
	check(random.ok, "started with a random seed")
	check(session.sim.save.world_seed >= 0, "a non-negative seed")


func test_lineage_tags_are_two_groups_of_four_hex_digits() -> void:
	check_eq(GameSession.lineage_tag("lineage_3f9a1c07b2e84d65"), "3F9A-1C07", "tag")
