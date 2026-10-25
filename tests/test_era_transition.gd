extends TestCase
## The cell-to-creature crossing as a save transaction (game/systems/era_transition.gd), on real files through
## PersistenceService: cross() is refused without a shore and once ashore, writing nothing; it keeps the cell at the
## shore as the checkpoint (<slot>.pre-terrestrial) and writes the lineage ashore with everything it carries; a
## failed write at any of its three steps leaves the save in memory as it was and the slot, once written, in the water.
## restore() writes the checkpoint back as the slot (the ashore save becomes the slot's .bak), refusing another
## lineage's checkpoint and a missing one; forget(), SaveSlots.delete and a new lineage on the slot remove the
## checkpoint's files. peek_slot's summary names the era. Files go to the per-process folder under
## user://test_saves.

const SaveFolder := preload("res://tests/save_folder.gd")

## Where the test lineage's shore rose (absolute am) and the size it rose at.
const SHORE_X := 120.5
const SHORE_Y := -64.25
const SHORE_SIZE := 4
## The test lineage's hue, points and seed.
const HUE := 0.62
const POINTS := 37
const SEED := 5151

var slot := ""
var catalog: PartCatalog
var persistence: PersistenceService
var _swept := false


func before_each() -> void:
	if not _swept:
		SaveFolder.sweep_stale()
		_swept = true
	_clear()
	slot = SaveFolder.path("era_slot.json")
	catalog = PartCatalog.load_from()
	persistence = PersistenceService.new(catalog)


func after_each() -> void:
	_clear()


## Empties the test folder, after the folder a test made at the checkpoint's path (SaveFolder.clear removes files).
func _clear() -> void:
	var cp := EraTransition.checkpoint_path(SaveFolder.path("era_slot.json"))
	if DirAccess.dir_exists_absolute(cp):
		DirAccess.remove_absolute(cp)
	SaveFolder.clear()


## A founded omnivore lineage in the water with points, a discovery and the cell's hue; its shore risen when
## `shore` (ShoreLink.raise). Nothing is written.
func _lineage(shore := true, seed_value := SEED) -> SaveGame:
	var founded := Lineage.found(seed_value, "test+dev", catalog, "omnivore")
	check(founded.ok, "a lineage is founded: %s" % [founded.errors])
	var save: SaveGame = founded.save
	save.adaptation_points = POINTS
	save.discoveries.append({"type": "place", "id": "giant_husk", "size": 1})
	save.genome.appearance["hue"] = HUE
	if shore:
		check(ShoreLink.raise(save, SHORE_X, SHORE_Y, SHORE_SIZE), "the shore rose")
	return save


## The files in the test folder, sorted ([] when there is no folder).
static func _files() -> Array:
	if not DirAccess.dir_exists_absolute(SaveFolder.dir()):
		return []
	var out := Array(DirAccess.get_files_at(SaveFolder.dir()))
	out.sort()
	return out


## The save without its write time, as the file holds it (through JSON every number reads back as a float, so both
## sides go through it): the same lineage state compares equal in memory and on disk, however often it is written.
static func _state(save: SaveGame) -> String:
	var d := save.to_dict()
	d.erase("saved_at_unix")
	return JSON.stringify(JSON.parse_string(JSON.stringify(d, "", true, true)), "", true, true)


## How many came_ashore events the lineage's history holds.
static func _came_ashore(save: SaveGame) -> int:
	return save.lineage_history.filter(func(e: Dictionary) -> bool: return e.event == ShoreLink.EVENT).size()


## `path` loaded as Continue loads it; a failed check (and null) when it does not load.
func _load(path: String, what: String) -> SaveGame:
	var loaded := persistence.load_from(path)
	check(loaded.ok, "%s loads: %s" % [what, loaded.errors])
	return loaded.save if loaded.ok else null


func test_crossing_is_refused_without_a_shore_or_once_ashore_and_writes_nothing() -> void:
	var save := _lineage(false)
	var state := _state(save)
	var r := EraTransition.cross(save, slot, persistence, CreatureRules.from_cell(save.genome))
	check(not r.ok, "no shore, no crossing")
	check_has_error(r.errors, "No shore has risen")
	check_eq(r.checkpoint, "", "no checkpoint")
	check_eq(_state(save), state, "the save in memory as it was")
	check_eq(_files(), [], "nothing written")
	check(not EraTransition.has_checkpoint(slot), "no checkpoint on disk")

	var ashore := _lineage()
	ashore.era = ShoreLink.TO_ERA
	state = _state(ashore)
	r = EraTransition.cross(ashore, slot, persistence, CreatureRules.from_cell(ashore.genome))
	check(not r.ok, "a lineage ashore cannot cross again")
	check_has_error(r.errors, "already ashore (era 'terrestrial')")
	check_eq(r.checkpoint, "", "no checkpoint")
	check_eq(_state(ashore), state, "the save in memory as it was")
	check_eq(_files(), [], "nothing written")


func test_crossing_keeps_the_cell_at_the_shore_as_the_checkpoint() -> void:
	var save := _lineage()
	var lineage := save.lineage_id
	var genome := JSON.stringify(save.genome.to_dict())
	var history := save.lineage_history.size()
	var r := EraTransition.cross(save, slot, persistence, CreatureRules.from_cell(save.genome))
	check(r.ok, "crossed: %s" % [r.errors])
	check(r.errors.is_empty(), "no errors")
	check_eq(EraTransition.checkpoint_path(slot), slot + ".pre-terrestrial", "the checkpoint beside the slot")
	check_eq(r.checkpoint, EraTransition.checkpoint_path(slot), "the result names it")
	check(EraTransition.has_checkpoint(slot), "it is there")
	var loaded := persistence.load_from(EraTransition.checkpoint_path(slot))
	check(loaded.ok, "the checkpoint loads: %s" % [loaded.errors])
	if not loaded.ok:
		return
	check_eq(loaded.source, "primary", "from its own file")
	var cp: SaveGame = loaded.save
	check_eq(cp.era, "microscopic", "in the water")
	check_eq(cp.lineage_id, lineage, "the same lineage")
	check_eq(cp.genome.genome_id, save.genome.genome_id, "the same genome id")
	check_eq(JSON.stringify(cp.genome.to_dict()), genome, "the same genome")
	check_eq(cp.adaptation_points, POINTS, "the points")
	check_eq(cp.discoveries, [{"type": "place", "id": "giant_husk", "size": 1}], "the discoveries")
	check_eq(ShoreLink.point_am(cp), PackedFloat64Array([SHORE_X, SHORE_Y]), "the shore")
	check_eq(int(ShoreLink.shore_of(cp).get("size", 0)), SHORE_SIZE, "risen at size 4")
	check_eq(cp.creature, {}, "no creature yet")
	check_eq(cp.lineage_history.size(), history, "no came_ashore in its history")
	check(not FileAccess.file_exists(EraTransition.checkpoint_path(slot) + PersistenceService.TEMP_SUFFIX), "no .tmp")


func test_crossing_writes_the_lineage_ashore_with_everything_it_carries() -> void:
	var save := _lineage()
	var lineage := save.lineage_id
	var genome := JSON.stringify(save.genome.to_dict())
	var history := save.lineage_history.size()
	var creature := CreatureRules.from_cell(save.genome)
	var r := EraTransition.cross(save, slot, persistence, creature)
	check(r.ok, "crossed: %s" % [r.errors])
	check_eq(save.era, "terrestrial", "ashore in memory")
	var ashore := _load(slot, "the slot")
	if ashore == null:
		return
	check_eq(_state(ashore), _state(save), "the slot holds the save in memory")
	check_eq(ashore.era, "terrestrial", "ashore")
	check_eq(ashore.lineage_history.size(), history + 1, "one lineage event added")
	check_eq(ashore.lineage_history[-1].event, "came_ashore", "came_ashore last")
	check_eq(ashore.lineage_history[-1].genome_id, save.genome.genome_id, "with the genome id")
	check_eq(int(ashore.lineage_history[-1].generation), save.genome.generation, "and generation")
	check_eq(ashore.lineage_history[0].event, "founded", "the history before it kept")
	check_eq(ashore.creature.name, CreatureRules.DEFAULT_NAME, "the first creature")
	check_eq(int(ashore.creature.generation), 1, "generation 1")
	var skin := "#" + CreatureRules.cell_skin(HUE).to_html(false)
	check_eq(ashore.creature.body.get("skin_color"), skin, "in the cell's hue")
	check_eq(ashore.lineage_id, lineage, "the same lineage")
	check_eq(JSON.stringify(ashore.genome.to_dict()), genome, "the same genome")
	check_eq(ashore.adaptation_points, POINTS, "the points carried over")
	check_eq(ashore.world_seed, SEED, "the world seed")
	check_eq(ashore.discoveries, [{"type": "place", "id": "giant_husk", "size": 1}], "the discoveries")
	check_eq(ShoreLink.point_am(ashore), PackedFloat64Array([SHORE_X, SHORE_Y]), "the shore stays in the world")
	# Step 1's write, the cell at the shore, is the slot's backup now.
	var before := _load(slot + PersistenceService.BACKUP_SUFFIX, "the slot's backup")
	if before != null:
		check_eq(before.era, "microscopic", "the backup is the cell at the shore")
		check_eq(before.lineage_id, lineage, "of the same lineage")
	check_eq(_files(), ["era_slot.json", "era_slot.json.bak", "era_slot.json.pre-terrestrial"], "three files, no .tmp")


func test_a_failed_final_write_leaves_the_cell_in_the_water() -> void:
	var save := _lineage()
	var state := _state(save)
	# A creature the save's checks refuse (a blank name): step 3's write is refused (PersistenceService logs it).
	var bad := CreatureRules.from_cell(save.genome)
	bad["name"] = ""
	var r := EraTransition.cross(save, slot, persistence, bad)
	check(not r.ok, "refused")
	check_has_error(r.errors, "Could not save the lineage ashore")
	check_eq(r.checkpoint, EraTransition.checkpoint_path(slot), "the checkpoint was written before it")
	check_eq(_state(save), state, "the save in memory undone")
	check_eq(save.era, "microscopic", "in the water")
	check_eq(save.creature, {}, "no creature")
	check(ShoreLink.in_water(save) and not ShoreLink.shore_of(save).is_empty(), "with its shore")
	var on_disk := _load(slot, "the slot")
	if on_disk != null:
		check_eq(on_disk.era, "microscopic", "the slot loads in the water")
		check_eq(ShoreLink.point_am(on_disk), PackedFloat64Array([SHORE_X, SHORE_Y]), "with the shore")
		check_eq(on_disk.creature, {}, "and no creature")
		check_eq(_state(on_disk), state, "step 1's save")
	check_eq(_files(), ["era_slot.json", "era_slot.json.pre-terrestrial"], "no .tmp left")
	# The save in memory crosses on a retry, with one came_ashore.
	r = EraTransition.cross(save, slot, persistence, CreatureRules.from_cell(save.genome))
	check(r.ok, "the retry crosses: %s" % [r.errors])
	check_eq(_came_ashore(save), 1, "one came_ashore")


func test_a_failed_first_or_checkpoint_write_changes_nothing_in_memory() -> void:
	# Step 1: the slot's folder is a file, so the slot cannot be written.
	var save := _lineage()
	var state := _state(save)
	DirAccess.make_dir_recursive_absolute(SaveFolder.dir())
	var blocker := SaveFolder.path("blocked")
	var f := FileAccess.open(blocker, FileAccess.WRITE)
	f.store_string("not a folder")
	f.close()
	var blocked := blocker + "/slot.json"
	var r := EraTransition.cross(save, blocked, persistence, CreatureRules.from_cell(save.genome))
	check(not r.ok, "refused")
	check_has_error(r.errors, "Could not save before going ashore")
	check_eq(r.checkpoint, "", "no checkpoint")
	check_eq(_state(save), state, "the save in memory as it was")
	check(not EraTransition.has_checkpoint(blocked), "no checkpoint written")
	# Step 2: a folder stands where the checkpoint goes, so it cannot be moved into place.
	DirAccess.make_dir_recursive_absolute(EraTransition.checkpoint_path(slot))
	r = EraTransition.cross(save, slot, persistence, CreatureRules.from_cell(save.genome))
	check(not r.ok, "refused")
	check_has_error(r.errors, "Could not keep the checkpoint")
	check_eq(r.checkpoint, "", "no checkpoint")
	check_eq(_state(save), state, "the save in memory as it was")
	var on_disk := _load(slot, "the slot")
	if on_disk != null:
		check_eq(_state(on_disk), state, "the slot holds step 1's save, in the water")
	var cp_tmp := EraTransition.checkpoint_path(slot) + PersistenceService.TEMP_SUFFIX
	check(not FileAccess.file_exists(cp_tmp), "no checkpoint .tmp left")


func test_restore_brings_the_cell_back_and_keeps_the_ashore_save_as_the_backup() -> void:
	var save := _lineage()
	var r := EraTransition.cross(save, slot, persistence, CreatureRules.from_cell(save.genome))
	check(r.ok, "crossed: %s" % [r.errors])
	var ashore_text := FileAccess.get_file_as_string(slot)
	var cp := _load(EraTransition.checkpoint_path(slot), "the checkpoint")
	var back := EraTransition.restore(slot, persistence, save.lineage_id)
	check(back.ok, "restored: %s" % [back.errors])
	check(back.save is SaveGame, "the save it wrote")
	if not back.ok or cp == null:
		return
	var water: SaveGame = back.save
	check_eq(water.era, "microscopic", "in the water")
	check_eq(_state(water), _state(cp), "the checkpoint's save")
	var slot_save := _load(slot, "the slot")
	if slot_save != null:
		check_eq(_state(slot_save), _state(cp), "the slot holds the checkpoint")
		check_eq(slot_save.creature, {}, "no creature")
		check_eq(_came_ashore(slot_save), 0, "no came_ashore in its history")
		check_eq(ShoreLink.point_am(slot_save), PackedFloat64Array([SHORE_X, SHORE_Y]), "the shore where it rose")
	var backup := FileAccess.get_file_as_string(slot + PersistenceService.BACKUP_SUFFIX)
	check_eq(backup, ashore_text, "the ashore save is the slot's backup")
	check(EraTransition.has_checkpoint(slot), "the checkpoint stays")
	var still := _load(EraTransition.checkpoint_path(slot), "the checkpoint after the restore")
	if still != null:
		check_eq(_state(still), _state(cp), "unchanged")
	# Back in the water, the lineage can cross again.
	r = EraTransition.cross(water, slot, persistence, CreatureRules.from_cell(water.genome))
	check(r.ok, "crosses again: %s" % [r.errors])
	var again := _load(slot, "the slot after the second crossing")
	if again != null:
		check_eq(again.era, "terrestrial", "ashore again")
		check_eq(_came_ashore(again), 1, "with one came_ashore: the first went back with the restore")


func test_restore_refuses_another_lineage_s_checkpoint_and_a_missing_one() -> void:
	var none := EraTransition.restore(slot, persistence, "")
	check(not none.ok and none.save == null, "no checkpoint, no restore")
	check_has_error(none.errors, "no checkpoint")
	check_eq(_files(), [], "nothing written")
	var save := _lineage()
	check(EraTransition.cross(save, slot, persistence, CreatureRules.from_cell(save.genome)).ok, "crossed")
	var files := _files()
	var text := FileAccess.get_file_as_string(slot)
	var other := _lineage(true, SEED + 1)
	check(other.lineage_id != save.lineage_id, "two lineages")
	var refused := EraTransition.restore(slot, persistence, other.lineage_id)
	check(not refused.ok and refused.save == null, "another lineage's checkpoint is refused")
	check_has_error(refused.errors, "belongs to another lineage (%s)" % save.lineage_id)
	check_eq(FileAccess.get_file_as_string(slot), text, "the slot as it was")
	check_eq(_files(), files, "no file added")
	# An unreadable checkpoint (and no backup of it) is refused with the reasons.
	var cp_path := EraTransition.checkpoint_path(slot)
	var f := FileAccess.open(cp_path, FileAccess.WRITE)
	f.store_string("{ not a save")
	f.close()
	var damaged := EraTransition.restore(slot, persistence, save.lineage_id)
	check(not damaged.ok, "a damaged checkpoint is refused")
	check_has_error(damaged.errors, "not a readable save file")
	check_eq(FileAccess.get_file_as_string(slot), text, "the slot as it was")
	# "" skips the lineage check (a slot that will not load can still go back); a checkpoint's backup serves. The
	# first write sets the damaged file aside, the second keeps the first as the checkpoint's backup.
	check_eq(persistence.save_to(cp_path, other), OK, "a checkpoint of the other lineage")
	check_eq(persistence.save_to(cp_path, other), OK, "and again, so it has a backup")
	DirAccess.remove_absolute(cp_path)
	check(EraTransition.has_checkpoint(slot), "its backup alone counts as the checkpoint")
	var any := EraTransition.restore(slot, persistence, "")
	check(any.ok, "restored without the check: %s" % [any.errors])
	if any.ok:
		check_eq(any.save.lineage_id, other.lineage_id, "from the checkpoint's backup")


func test_forget_and_deleting_the_slot_remove_the_checkpoint() -> void:
	var save := _lineage()
	check(EraTransition.cross(save, slot, persistence, CreatureRules.from_cell(save.genome)).ok, "crossed")
	var cp := EraTransition.checkpoint_path(slot)
	# The checkpoint with a backup and a temporary file, as a second crossing and an interrupted write leave them.
	check_eq(persistence.save_to(cp, _load(cp, "the checkpoint")), OK, "the checkpoint written again")
	var f := FileAccess.open(cp + PersistenceService.TEMP_SUFFIX, FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	check(FileAccess.file_exists(cp + PersistenceService.BACKUP_SUFFIX), "a checkpoint backup")
	EraTransition.forget(slot)
	check(not EraTransition.has_checkpoint(slot), "forgotten")
	check_eq(_files(), ["era_slot.json", "era_slot.json.bak"], "the slot and its backup stay")
	EraTransition.forget(slot)
	check_eq(_files(), ["era_slot.json", "era_slot.json.bak"], "forgetting nothing changes nothing")
	# SaveSlots.delete removes the slot's files and the checkpoint's.
	var water := _load(slot + PersistenceService.BACKUP_SUFFIX, "the cell at the shore")
	check(EraTransition.cross(water, slot, persistence, CreatureRules.from_cell(water.genome)).ok, "crossed again")
	check_eq(persistence.save_to(cp, _load(cp, "the new checkpoint")), OK, "a checkpoint backup")
	f = FileAccess.open(cp + PersistenceService.TEMP_SUFFIX, FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	check_eq(_files().size(), 5, "slot, backup, checkpoint, its backup and .tmp: %s" % [_files()])
	check_eq(SaveSlots.delete(slot), OK, "deleted")
	check_eq(_files(), [], "every file gone")
	check(not EraTransition.has_checkpoint(slot), "no checkpoint")


func test_a_new_lineage_on_the_slot_forgets_the_old_one_s_checkpoint() -> void:
	var save := _lineage()
	check(EraTransition.cross(save, slot, persistence, CreatureRules.from_cell(save.genome)).ok, "crossed")
	check(EraTransition.has_checkpoint(slot), "a checkpoint")
	var session := GameSession.new(slot)
	var started := session.start_new("grazer", 3)
	check(started.ok and started.saved, "a new lineage: %s" % [started.errors])
	check(not EraTransition.has_checkpoint(slot), "the old lineage's checkpoint is gone")
	check_eq(_files(), ["era_slot.json", "era_slot.json.bak"], "the new lineage and the old as its backup")


func test_peek_names_the_slot_s_era() -> void:
	var save := _lineage()
	check_eq(persistence.save_to(slot, save), OK, "the cell at the shore saved")
	var peek := GameSession.new(slot).peek_slot()
	check(peek.ok, "readable: %s" % [peek.errors])
	check_eq(peek.summary.get("era"), "microscopic", "in the water")
	check(EraTransition.cross(save, slot, persistence, CreatureRules.from_cell(save.genome)).ok, "crossed")
	peek = GameSession.new(slot).peek_slot()
	check(peek.ok, "readable: %s" % [peek.errors])
	check_eq(peek.summary.get("era"), "terrestrial", "ashore")
	check_eq(peek.summary.get("lineage_id"), save.lineage_id, "the same lineage")
	check_eq(peek.summary.get("adaptation_points"), POINTS, "with its points")
