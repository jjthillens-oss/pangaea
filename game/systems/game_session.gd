class_name GameSession
extends RefCounted
## One play session's save slot and running pool (M1 step 2, threats and checkpoints in step 3,
## the endless world in S1, growth in S2). Main owns it; it is not an autoload. New lineage,
## continue, save and the death flow all go through here, on save schema v3 (SaveGame): energy,
## health, heading, the world's food, the creatures, the death streak and the shelter are not
## saved, so Continue restarts them (D16).
##
## There is no timed autosave. Saving happens when the player asks (pause menu, save and quit,
## the quit dialog), once when a new lineage starts, so Continue always has a file, with
## SAVE_ON_DEATH when a death is resolved, and right after a tick in which the cell grew
## (after_events, which the scene calls with each tick's events; S2 D-75). A size that differs from
## the saved one is an unsaved change.
##
## The death flow (plan section 13): the sim reports died; resolve_death() applies the death to the
## lineage once (Lineage.apply_death with RespawnRules.death_cause) and, with save_on_death, writes
## the slot with the cell at its checkpoint; respawn_after_death() then brings the cell back there.
##
## The world (S1): with a world path the session reads WorldConfig, and the mode (the file's, or
## the world_mode argument, which is the --world flag) picks the endless world or the M1 pool.
## Without one it is the M1 pool, exactly as before, which is how every pool test runs. An endless
## save is a plain save whose position is absolute am in float64 (PlaneSpace.to_save_abs). In
## endless mode the sim respawns at its next step (respawn_pending), so between the request and
## that step the cell is still dead with its death already applied: resolve_death, a second
## respawn_after_death and save_now hold off, and the dirty test reads the death's own save.

const DEFAULT_SLOT := "user://saves/slot_1.json"   ## %APPDATA%\Pangaea\saves\slot_1.json on Windows
## Moving further than this since the last save counts as an unsaved change. In endless mode it is
## am at size 1, measured between absolute positions, so a rebase alone changes nothing.
const DIRTY_MOVE_M := 1.0
## The owner's choice for OD1 (plan section 24), the recommended option. true: resolving a death
## writes the slot at once, with the cell at its checkpoint, so quitting at the death notice cannot
## skip the death. false: step 2's rule; nothing is written until the player saves, and quitting
## without saving discards the death. Both paths are tested (test_checkpoints).
const SAVE_ON_DEATH := true
## The death notice's tips after starving, picked by starved_tip() from what the body eats (a
## kill's tip is its species' death_tip). A body that eats plankton is told where it regrows.
const STARVED_TIP := "Plankton regrows in the sunlit patches; slow down when energy runs low."
## A body that eats only carrion: since step 3, past the few world-start pieces (which may still lie
## in the pool), more comes only from kills (D1). Worded as the tests hunt (threats_sim #9 and #22,
## HuntBot): from behind a rammer, jaw first, biting until it dies (five bites in #9). It names no
## other prey, since an ambush hunter may be too big to bite.
const STARVED_TIP_MEAT := "More carrion comes only from kills: bite a rammer from behind, jaw first, and keep biting until it dies, then eat what it drops. Slow down when energy runs low."
## No body to go by, or one that eats nothing: no food named.
const STARVED_TIP_ANY := "Slow down when energy runs low."

var slot: String
var catalog: PartCatalog
var layout: PoolLayout
## The threats (creatures_m1.json); null for the step 2 pool with no creatures.
var species: SpeciesCatalog
var persistence: PersistenceService
var sim: PoolSim
## Where the running save came from: "new", "primary", "recovered" or "backup" ("" before a run starts).
var load_source := ""
## The last save attempt: {"ok", "error"} ({} before any).
var last_save := {}
## Tests set it to exercise both OD1 paths.
var save_on_death := SAVE_ON_DEATH
## The death being shown, once resolve_death() has applied it (see there); {} while the cell is
## alive or its death is not resolved yet.
var death := {}
## Points changed, the cell moved more than DIRTY_MOVE_M from where it was saved, or it died and
## that death is not saved.
var dirty: bool:
	get:
		return _is_dirty()

## The world content in endless mode; null in pool mode.
var world: WorldContent = null
## The world file with the mode applied, when a world path was given; null for a pool-only session.
## Its load problems (an unreadable file, a bad key, an unknown mode) stop a run in either mode.
var world_config: WorldConfig = null

var _saved_points := 0
var _saved_position := Vector2.ZERO
var _saved_history_size := 0
## Endless: absolute_position_am() at the last save or load. Pool mode uses _saved_position.
var _saved_abs := PackedFloat64Array([0.0, 0.0])
## The cell's size at the last save or load (S2): a growth or a size change since is unsaved.
var _saved_size := 1
var _saved_checkpoint := PackedFloat64Array()   ## endless: the world's checkpoint at the last save
## Whether the death handed to the pending respawn was saved: respawn_after_death clears `death`
## before the sim's next step performs the respawn, and the dirty test reads this meanwhile.
var _respawn_death_saved := false


## `species_path` "" runs the step 2 pool, with no creatures. `world_path` "" is the M1 pool; else
## the world file, with `world_mode` ("pool" or "endless", "" for the file's own) overriding its mode.
func _init(p_slot: String = DEFAULT_SLOT, layout_path: String = PoolLayout.DEFAULT_PATH,
		species_path: String = SpeciesCatalog.DEFAULT_PATH, world_path: String = "", world_mode: String = "") -> void:
	slot = p_slot
	catalog = PartCatalog.load_from()
	persistence = PersistenceService.new(catalog)
	layout = PoolLayout.load_from(layout_path)
	if not species_path.is_empty():
		species = SpeciesCatalog.load_from(species_path)
	if world_path.is_empty():
		return
	var from_file := WorldConfig.load_from(world_path)
	world_config = from_file.with_mode(world_mode if not world_mode.is_empty() else from_file.mode)
	if world_config.mode == "endless" and species != null and world_config.load_problems.is_empty():
		world = WorldContent.load_from(world_path, layout, species)
		world.config = world_config   # the flag's mode wins over the file's


## True when the session runs the endless world.
func is_endless() -> bool:
	return world != null


## The first eight hex digits of a lineage id in two groups, for showing to the player:
## "lineage_3f9a1c07b2e84d65" -> "3F9A-1C07".
static func lineage_tag(lineage_id: String) -> String:
	var body := lineage_id.trim_prefix("lineage_").to_upper()
	if body.length() < 8:
		return body
	return "%s-%s" % [body.substr(0, 4), body.substr(4, 4)]


## What the slot holds, without writing anything:
## {"exists", "ok", "source": "primary"|"recovered"|"backup"|"", "summary", "errors"}. The summary (when ok) is
## {"lineage_id", "lineage_tag", "body" ("" for an evolved body), "generation",
##  "adaptation_points", "saved_at_unix", "world_seed", "genome": Genome}.
func peek_slot() -> Dictionary:
	var exists := FileAccess.file_exists(slot) or FileAccess.file_exists(slot + PersistenceService.BACKUP_SUFFIX)
	var result := {"exists": exists, "ok": false, "source": "", "summary": {}, "errors": PackedStringArray()}
	if not exists:
		return result
	var loaded := persistence.load_from(slot)
	result.ok = loaded.ok
	result.source = loaded.source
	result.errors = loaded.errors
	if loaded.ok:
		var save: SaveGame = loaded.save
		result.summary = {
			"lineage_id": save.lineage_id,
			"lineage_tag": lineage_tag(save.lineage_id),
			"body": Lineage.starting_body_of(save.genome, catalog),
			"generation": save.genome.generation,
			"adaptation_points": save.adaptation_points,
			"saved_at_unix": save.saved_at_unix,
			"world_seed": save.world_seed,
			"genome": save.genome,
			"era": save.era,
		}
	return result


## Founds a lineage with a starting body, saves it to the slot and starts the pool.
## seed_value -1 picks a random non-negative seed. Returns {"ok", "errors", "saved"}: the run
## starts even when the first save fails (saved false, the reason in errors).
func start_new(body: String, seed_value: int = -1) -> Dictionary:
	var errors := _data_problems()
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "saved": false}
	if seed_value < 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		seed_value = rng.randi()
	var founded := Lineage.found(seed_value, BuildInfo.build_id(), catalog, body)
	if not founded.ok:
		return {"ok": false, "errors": founded.errors, "saved": false}
	var save: SaveGame = founded.save
	EraTransition.forget(slot)   # a checkpoint from the lineage this one replaces is not this one's to go back to
	if world != null:
		save.player["position"] = PlaneSpace.to_save_abs(world.home.spawn[0], world.home.spawn[1])
	else:
		save.player["position"] = PlaneSpace.to_save(layout.spawn)
	sim = PoolSim.create(save, catalog, layout, species, world)
	death = {}
	load_source = "new"
	var written := _write()
	var result_errors := PackedStringArray()
	if not written.ok:
		result_errors.append(written.error)
	return {"ok": true, "errors": result_errors, "saved": written.ok}


## Loads the slot (falling back to its backup) and starts the pool. Returns {"ok", "source", "errors"};
## errors explain a fallback to the backup even when ok.
func continue_run() -> Dictionary:
	var errors := _data_problems()
	if not errors.is_empty():
		return {"ok": false, "source": "", "errors": errors}
	var loaded := persistence.load_from(slot)
	if not loaded.ok:
		return {"ok": false, "source": "", "errors": loaded.errors}
	sim = PoolSim.create(loaded.save, catalog, layout, species, world)
	death = {}
	load_source = loaded.source
	_mark_saved()
	return {"ok": true, "source": loaded.source, "errors": loaded.errors}


## Writes the running save to the slot. Refused while the cell is dead (the death must be
## resolved first), except while an endless respawn is pending: the death is applied by then, and
## the save holds the checkpoint, as the death's own save did. Returns {"ok", "error"}.
func save_now() -> Dictionary:
	if sim == null:
		last_save = {"ok": false, "error": "There is no run to save."}
	elif sim.dead and not sim.respawn_pending:
		last_save = {"ok": false, "error": "Your cell is dead; continue before saving."}
	else:
		last_save = _write()
	return last_save


## Call with each tick's drained events (PoolSim.drain_events): a tick whose events hold "grew", or a
## landmark's "checkpoint_moved" (S3, D-132), is saved at once, so the growth or the new return point
## survives a quit or a crash (S2 D-75; plan E). Returns save_now()'s result when it saved, else {}.
##
## The cell-to-creature link (ShoreLink): the first ring paid at the build's top size raises the shore, and that
## tick is saved too, so the shore stands where it rose after a reload.
func after_events(events: Array) -> Dictionary:
	var raised := false
	for event in events:
		if not event is Dictionary:
			continue
		if event.get("type") == "grew" or event.get("type") == "checkpoint_moved":
			return save_now()
		if event.get("type") == "ring_paid" and raise_shore():
			raised = true
	return save_now() if raised else {}


## Raises the shore (ShoreLink.raise) RISE_AHEAD_TM up the screen from the cell, on the first clear point the
## rule C1 spiral finds there for twice the cell's radius, in the endless world at the build's top size. False when
## it has risen already, the lineage is ashore, or there is no world or no top.
func raise_shore() -> bool:
	if sim == null or sim.world == null or sim.growth == null or sim.dead:
		return false
	if not Growth.at_top(sim.size(), sim.world.max_size) or not ShoreLink.shore_of(sim.save).is_empty():
		return false
	var ahead := sim.motion.position + ShoreLink.RISE_DIRECTION * ShoreLink.RISE_AHEAD_TM
	var at := PoolSim.clear_point_on(sim.arena, ahead, sim.phenotype.radius * 2.0)
	var am := sim.world.abs_of_local(at)
	return ShoreLink.raise(sim.save, am[0], am[1], sim.size())


## Applies the cell's death to the lineage, once: Lineage.apply_death takes a quarter of the
## unspent points and records the cause ("starved" or "killed:<species>", D18). With save_on_death
## the slot is then written with the cell at its checkpoint (the usual temp, verify and backup
## path); when that fails the death still stands in memory and the session stays dirty. Calling it
## again returns the same result, and while an endless respawn is pending (the death it handed over
## was applied; `death` is already cleared) it returns {}. Returns {} while the cell is alive, else
## {"lost", "cause", "by_species", "reason" (the killer's death_reason, or ""), "tip" (the death
##  notice's tip, or ""), "saved": {"attempted", "ok", "error"}}.
func resolve_death() -> Dictionary:
	if sim == null or not sim.dead or sim.respawn_pending:
		return {}
	if not death.is_empty():
		return death
	var cause := RespawnRules.death_cause(sim.death)
	var lost := Lineage.apply_death(sim.save, cause)
	var saved := {"attempted": false, "ok": false, "error": ""}
	if save_on_death:
		last_save = _write()
		saved = {"attempted": true, "ok": last_save.ok, "error": last_save.error}
	var by_species := str(sim.death.get("by_species", ""))
	death = {"lost": lost, "cause": cause, "by_species": by_species, "reason": str(sim.death.get("reason", "")),
		"tip": _death_tip(cause, by_species), "saved": saved}
	return death


## True when the cell is dead and its death's save was tried and failed: the quit dialog warns that
## quitting loses it.
func death_save_failed() -> bool:
	return sim != null and sim.dead and not death.is_empty() and death.saved.attempted and not death.saved.ok


## Brings the dead cell back at its checkpoint (PoolSim.respawn_player), resolving the death first
## if that has not happened yet, so the death always counts once. Returns the points the death
## took (0, and nothing changed, when the cell is not dead or its endless respawn is pending: the
## sim performs it at its next step).
func respawn_after_death() -> int:
	if sim == null or not sim.dead or sim.respawn_pending:
		return 0
	var resolved := resolve_death()
	_respawn_death_saved = bool(resolved.saved.ok)
	sim.respawn_player()
	death = {}
	return int(resolved.lost)


## The tip after starving for body `p`, naming only a food it can eat: STARVED_TIP when it eats
## plankton, STARVED_TIP_MEAT when it eats only carrion, else (or for null) STARVED_TIP_ANY.
static func starved_tip(p: Phenotype) -> String:
	if p != null and p.can_eat("plant"):
		return STARVED_TIP
	if p != null and p.can_eat("meat"):
		return STARVED_TIP_MEAT
	return STARVED_TIP_ANY


## Why the run cannot start: the layout's problems, then the species data's, then the world file's
## (in either mode) and, in endless mode, the world content's.
func _data_problems() -> PackedStringArray:
	var errors := layout.validate()
	if errors.is_empty() and species != null:
		errors = species.validate(layout, catalog)
	if world_config != null:
		errors.append_array(world_config.load_problems)
		if world_config.mode == "endless" and species == null:
			errors.append("Endless mode needs the creature data; this session has none.")
		elif world != null:
			errors.append_array(world.problems(catalog, species))
	return errors


func _death_tip(cause: String, by_species: String) -> String:
	if cause == "starved":
		return starved_tip(sim.phenotype)
	if species != null and species.has_species(by_species):
		return str(species.species[by_species].get("death_tip", ""))
	return ""


## Writes the save with position_for_save() (the checkpoint while dead) and the v3 growth fields
## after it (the size, the meter, the world's checkpoint and the ledger; S2G19).
func _write() -> Dictionary:
	sim.write_position_to_save()
	sim.write_growth_to_save()
	var err := persistence.save_to(slot, sim.save)
	if err != OK:
		return {"ok": false, "error": "Could not save to %s: %s." % [slot, error_string(err)]}
	_mark_saved()
	return {"ok": true, "error": ""}


func _mark_saved() -> void:
	_saved_points = sim.save.adaptation_points
	_saved_position = sim.position_for_save()
	_saved_history_size = sim.save.lineage_history.size()
	_saved_size = _size()
	if sim.is_endless():
		_saved_abs = sim.absolute_position_am()
		_saved_checkpoint = sim.world.checkpoint_am.duplicate()


## The cell's size: the world's in endless mode, 1 in the pool.
func _size() -> int:
	return sim.size()


## A dead cell is dirty only while its death is not saved; after a saved death the checkpoint is
## where the save puts it, so neither the open notice nor the respawn there is an unsaved change.
## While an endless respawn is pending, the death's save is the one respawn_after_death recorded.
## Endless positions are compared as absolute am in float64, never as local Vector2s. A size other
## than the saved one is always a change, wherever the cell is.
func _is_dirty() -> bool:
	if sim == null:
		return false
	if sim.dead:
		var saved := _respawn_death_saved if sim.respawn_pending else bool(death.get("saved", {}).get("ok", false))
		if not saved:
			return true
	if sim.save.adaptation_points != _saved_points or sim.save.lineage_history.size() != _saved_history_size:
		return true
	if _size() != _saved_size:
		return true
	if sim.is_endless():
		if sim.world.checkpoint_am != _saved_checkpoint:
			return true   # a landmark moved the return point (S3G24c)
		var a := sim.absolute_position_am()
		var dx := a[0] - _saved_abs[0]
		var dy := a[1] - _saved_abs[1]
		return dx * dx + dy * dy > DIRTY_MOVE_M * DIRTY_MOVE_M
	return sim.position_for_save().distance_to(_saved_position) > DIRTY_MOVE_M
