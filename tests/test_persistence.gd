extends TestCase

const DIR := "user://test_saves"
const PATH := DIR + "/slot.json"

var catalog: PartCatalog
var service: PersistenceService


func before_each() -> void:
	catalog = PartCatalog.load_from()
	service = PersistenceService.new(catalog)
	_clear()
	DirAccess.make_dir_recursive_absolute(DIR)


func after_each() -> void:
	_clear()


func _clear() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + f)


func _new_save() -> SaveGame:
	var save := SaveGame.new_run(12345, "test+dev")
	save.genome.add_part("mouth_jaw", 0.0)
	save.genome.add_part("flagellum", PI)
	save.discoveries.append({"id": "food_red_chunk", "generation": 1})
	return save


func _write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_round_trip_keeps_lineage_genome_and_discoveries() -> void:
	var save := _new_save()
	check_eq(service.save_to(PATH, save), OK, "save")
	var result := service.load_from(PATH)
	check(result.ok, "load ok: %s" % [result.errors])
	if not result.ok:
		return
	var loaded: SaveGame = result.save
	check_eq(result.source, "primary", "source")
	check_eq(loaded.lineage_id, save.lineage_id, "lineage id")
	check_eq(loaded.world_seed, 12345, "seed")
	check_eq(JSON.stringify(loaded.genome.to_dict()), JSON.stringify(save.genome.to_dict()), "genome")
	check_eq(loaded.discoveries.size(), 1, "discoveries")
	check_eq(loaded.lineage_history[0]["event"], "founded", "history")


func test_write_leaves_no_temp_file_and_keeps_backup_of_previous_save() -> void:
	var save := _new_save()
	service.save_to(PATH, save)
	save.genome.add_part("spike", 0.4)
	service.save_to(PATH, save)
	check(not FileAccess.file_exists(PATH + ".tmp"), "temp file removed")
	check(FileAccess.file_exists(PATH + ".bak"), "backup exists")
	var backup := service.load_from(PATH + ".bak")
	check(backup.ok, "backup loads")
	if backup.ok:
		check_eq(backup.save.genome.parts.size(), 2, "backup holds the previous save")


func test_corrupt_primary_falls_back_to_backup_without_touching_files() -> void:
	var save := _new_save()
	service.save_to(PATH, save)
	service.save_to(PATH, save)
	_write_raw(PATH, "{ this is not json")
	var result := service.load_from(PATH)
	check(result.ok, "falls back")
	check_eq(result.source, "backup", "source")
	check(result.errors.size() > 0, "explains why the primary failed")
	check_eq(FileAccess.get_file_as_string(PATH), "{ this is not json", "corrupt original preserved")


func test_saving_over_corrupt_primary_sets_it_aside_and_keeps_backup() -> void:
	var save := _new_save()
	service.save_to(PATH, save)
	service.save_to(PATH, save)
	var backup_before := FileAccess.get_file_as_string(PATH + ".bak")
	_write_raw(PATH, "garbage")
	check_eq(service.save_to(PATH, save), OK, "save")
	check_eq(FileAccess.get_file_as_string(PATH + ".bak"), backup_before, "good backup kept")
	var set_aside := false
	for f in DirAccess.get_files_at(DIR):
		if f.begins_with("slot.json.corrupt-"):
			set_aside = FileAccess.get_file_as_string(DIR + "/" + f) == "garbage"
	check(set_aside, "corrupt file preserved beside the save")


func test_save_from_newer_build_is_refused_and_untouched() -> void:
	var data := _new_save().to_dict()
	data["schema_version"] = PersistenceService.CURRENT_VERSION + 1
	var text := JSON.stringify(data)
	_write_raw(PATH, text)
	var result := service.load_from(PATH)
	check(not result.ok, "refused")
	check_has_error(result.errors, "newer build")
	check_eq(FileAccess.get_file_as_string(PATH), text, "file untouched")


func test_migration_runs_in_memory_only() -> void:
	# A hypothetical schema 0 that stored the genome under "body".
	var current := _new_save().to_dict()
	var old := current.duplicate(true)
	old["schema_version"] = 0
	old["body"] = old["genome"]
	old.erase("genome")
	var text := JSON.stringify(old)
	_write_raw(PATH, text)
	service.migrations[0] = func(d: Dictionary) -> Dictionary:
		d["genome"] = d["body"]
		d.erase("body")
		d["schema_version"] = 1
		return d
	var result := service.load_from(PATH)
	check(result.ok, "migrated load: %s" % [result.errors])
	if result.ok:
		check_eq(result.save.genome.parts.size(), 2, "genome carried over")
	check_eq(FileAccess.get_file_as_string(PATH), text, "original file not rewritten on load")


func test_missing_migration_is_an_explained_failure() -> void:
	var data := _new_save().to_dict()
	data["schema_version"] = 0
	_write_raw(PATH, JSON.stringify(data))
	var result := service.load_from(PATH)
	check(not result.ok, "refused")
	check_has_error(result.errors, "no migration from schema 0")


func test_save_with_invalid_body_fails_to_load_instead_of_dropping_parts() -> void:
	var data := _new_save().to_dict()
	data["genome"]["parts"].append({"id": "part_7", "type": "unknown_organ", "angle": 0.0, "scale": 1.0})
	_write_raw(PATH, JSON.stringify(data))
	var result := service.load_from(PATH)
	check(not result.ok, "refused")
	check_has_error(result.errors, "unknown_organ")


func test_invalid_save_is_not_written_and_existing_file_survives() -> void:
	var save := _new_save()
	service.save_to(PATH, save)
	var before := FileAccess.get_file_as_string(PATH)
	save.genome.parts.clear()
	check_eq(service.save_to(PATH, save), ERR_INVALID_DATA, "refused")
	check_eq(FileAccess.get_file_as_string(PATH), before, "previous save intact")
