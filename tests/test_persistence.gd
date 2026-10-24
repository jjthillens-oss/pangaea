extends TestCase

## Per-process folder so two test runs at once cannot touch each other's files. Folders left by
## runs that were killed are removed once their process is gone.
const ROOT := "user://test_saves"
var DIR := ROOT + "/%d" % OS.get_process_id()
var PATH := DIR + "/slot.json"
var _swept := false

var catalog: PartCatalog
var service: PersistenceService


func before_each() -> void:
	catalog = PartCatalog.load_from()
	service = PersistenceService.new(catalog)
	if not _swept:
		_sweep_stale_runs()
		_swept = true
	_clear()
	DirAccess.make_dir_recursive_absolute(DIR)


func after_each() -> void:
	_clear()


func _sweep_stale_runs() -> void:
	for sub in DirAccess.get_directories_at(ROOT):
		if sub.is_valid_int() and int(sub) != OS.get_process_id() and not OS.is_process_running(int(sub)):
			var path := ROOT + "/" + sub
			for f in DirAccess.get_files_at(path):
				DirAccess.remove_absolute(path + "/" + f)
			DirAccess.remove_absolute(path)


func _clear() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + f)
	DirAccess.remove_absolute(DIR)


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


func test_a_verified_temp_file_left_by_an_interrupted_move_is_the_save_that_loads() -> void:
	# save_to moves the primary to .bak and then .tmp into place; a crash between the two leaves
	# the older save as .bak and the newest as .tmp.
	var save := _new_save()
	service.save_to(PATH, save)
	save.adaptation_points = 15
	service.save_to(PATH, save)
	var newest := FileAccess.get_file_as_string(PATH)
	DirAccess.remove_absolute(PATH + ".bak")
	DirAccess.rename_absolute(PATH, PATH + ".bak")
	_write_raw(PATH + ".tmp", newest)
	var result := service.load_from(PATH)
	check(result.ok, "loads")
	check_eq(result.source, "recovered", "from the temp file, not the older backup")
	check_eq(result.errors.size(), 0, "nothing was unreadable")
	if result.ok:
		check_eq(result.save.adaptation_points, 15, "the newest points")
	check(FileAccess.file_exists(PATH + ".tmp") and not FileAccess.file_exists(PATH), "loading moved nothing")
	# The next save takes the empty place; the recovered state is not lost.
	result.save.adaptation_points = 20
	check_eq(service.save_to(PATH, result.save), OK, "next save writes")
	check(not FileAccess.file_exists(PATH + ".tmp"), "no temp file after it")
	check_eq(service.load_from(PATH).source, "primary", "primary again")
	_write_raw(PATH + ".tmp", "{ half a save")
	DirAccess.remove_absolute(PATH)
	check_eq(service.load_from(PATH).source, "backup", "a damaged temp file is ignored for the backup")


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


func test_m0_save_migrates_to_the_current_schema_with_no_adaptation_points() -> void:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/save_v1.json")
	check(not text.is_empty(), "fixture readable")
	_write_raw(PATH, text)
	var result := service.load_from(PATH)
	check(result.ok, "v1 loads: %s" % [result.errors])
	if not result.ok:
		return
	var loaded: SaveGame = result.save
	check_eq(loaded.adaptation_points, 0, "starts with no points")
	check_eq(loaded.lineage_id, "lineage_3f9a1c07b2e84d65", "lineage kept")
	check_eq(loaded.genome.parts.size(), 2, "body kept")
	check_eq(FileAccess.get_file_as_string(PATH), text, "file not rewritten on load")
	check_eq(service.save_to(PATH, loaded), OK, "re-saves")
	check_eq(int(JSON.parse_string(FileAccess.get_file_as_string(PATH))["schema_version"]), SaveGame.SCHEMA_VERSION, "written at the current schema")
	check(service.load_from(PATH).save.creature.is_empty(), "with no creature yet")


func test_negative_adaptation_points_are_refused() -> void:
	var data := _new_save().to_dict()
	data["adaptation_points"] = -5
	_write_raw(PATH, JSON.stringify(data))
	var result := service.load_from(PATH)
	check(not result.ok, "refused")
	check_has_error(result.errors, "must not be negative")


func test_adaptation_points_round_trip() -> void:
	var save := _new_save()
	save.adaptation_points = 37
	service.save_to(PATH, save)
	var result := service.load_from(PATH)
	check(result.ok, "loads")
	if result.ok:
		check_eq(result.save.adaptation_points, 37, "points kept")


func test_wrong_types_in_a_save_fail_cleanly_and_fall_back_to_the_backup() -> void:
	var save := _new_save()
	save.adaptation_points = 12
	service.save_to(PATH, save)
	service.save_to(PATH, save)
	var data := save.to_dict()
	data["adaptation_points"] = null
	data["lineage_history"] = "oops"
	data["player"] = 7
	data["genome"]["parts"] = null
	_write_raw(PATH, JSON.stringify(data))
	var result := service.load_from(PATH)
	check(result.ok, "backup loads: %s" % [result.errors])
	check_eq(result.source, "backup", "from the backup")
	check_has_error(result.errors, "'adaptation_points' must be a whole number")
	check_has_error(result.errors, "'lineage_history' must be a list")
	check_has_error(result.errors, "'parts' must be a list")
	if result.ok:
		check_eq(result.save.adaptation_points, 12, "backup points")


func test_wrong_typed_lists_do_not_load_as_empty_and_the_backup_survives_the_next_save() -> void:
	var save := _new_save()
	service.save_to(PATH, save)
	service.save_to(PATH, save)
	var backup_text := FileAccess.get_file_as_string(PATH + ".bak")
	var data := save.to_dict()
	data["discoveries"] = {"id": "food_red_chunk", "generation": 1}
	data["genome"]["appearance"] = "red"
	data["genome"]["parts"][1]["id"] = 2
	_write_raw(PATH, JSON.stringify(data))
	var result := service.load_from(PATH)
	check_eq(result.source, "backup", "damaged primary is not accepted")
	check_has_error(result.errors, "'discoveries' must be a list")
	check_has_error(result.errors, "'appearance' must be an object")
	check_has_error(result.errors, "not text")
	if result.ok:
		check_eq(result.save.discoveries.size(), 1, "discoveries come back from the backup")
		check_eq(service.save_to(PATH, result.save), OK, "re-save")
		check_eq(FileAccess.get_file_as_string(PATH + ".bak"), backup_text, "the good backup was not replaced by the damaged file")


func test_a_world_seed_a_save_file_cannot_hold_exactly_is_refused() -> void:
	var save := _new_save()
	service.save_to(PATH, save)
	var before := FileAccess.get_file_as_string(PATH)
	# 2^53 + 1 would be read back as 2^53: Continue would run a different world.
	save.world_seed = 9007199254740993
	check_has_error(save.validate(catalog), "World seed")
	check_eq(service.save_to(PATH, save), ERR_INVALID_DATA, "refused")
	check_eq(FileAccess.get_file_as_string(PATH), before, "previous save intact")
	save.world_seed = 9007199254740992
	check_eq(service.save_to(PATH, save), OK, "2^53 is held exactly")


func test_a_save_that_would_not_load_back_is_refused_rather_than_reported_as_written() -> void:
	var save := _new_save()
	service.save_to(PATH, save)
	var before := FileAccess.get_file_as_string(PATH)
	# Valid in memory, but the file rounds the next part number (2^53 + 1) down onto the newest
	# part's number, which then fails to load. Any number the file cannot hold exactly would do.
	save.genome.next_part_number = 9007199254740992
	save.genome.add_part("cilia", 1.0)
	check(save.validate(catalog).is_empty(), "valid in memory: %s" % [save.validate(catalog)])
	check(service.save_to(PATH, save) != OK, "refused")
	check_eq(FileAccess.get_file_as_string(PATH), before, "previous save intact")
	check(not FileAccess.file_exists(PATH + ".tmp"), "no temp file left")


func test_a_save_that_cannot_be_moved_into_place_leaves_no_temp_file() -> void:
	# The slot path is a folder, so the final rename fails.
	var folder := DIR + "/folder.json"
	DirAccess.make_dir_recursive_absolute(folder)
	check(service.save_to(folder, _new_save()) != OK, "refused")
	check(not FileAccess.file_exists(folder + ".tmp"), "no temp file left")
	DirAccess.remove_absolute(folder)


## Save schema v3 (Bible section 18): the creature stage's creature lives in the lineage save.
const V3_FIXTURE := "res://tests/fixtures/save_v3_creature.json"


func test_a_v2_save_migrates_to_v3_with_no_creature() -> void:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/save_v2_step2.json")
	_write_raw(PATH, text)
	var result := service.load_from(PATH)
	check(result.ok, "v2 loads: %s" % [result.errors])
	if not result.ok:
		return
	var loaded: SaveGame = result.save
	check(loaded.creature.is_empty(), "with no creature")
	check_eq(loaded.adaptation_points, 16, "the points kept")
	check_eq(loaded.genome.parts.size(), 3, "the body kept")
	check_eq(FileAccess.get_file_as_string(PATH), text, "file not rewritten on load")
	check_eq(service.save_to(PATH, loaded), OK, "re-saves")
	var written: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	check_eq(int(written["schema_version"]), 3, "written as v3")
	check_eq(written["creature"], {}, "with an empty creature")


func test_the_v3_fixture_loads_and_round_trips_the_creature() -> void:
	var text := FileAccess.get_file_as_string(V3_FIXTURE)
	check(not text.is_empty(), "fixture readable")
	_write_raw(PATH, text)
	var result := service.load_from(PATH)
	check(result.ok, "v3 loads: %s" % [result.errors])
	if not result.ok:
		return
	var loaded: SaveGame = result.save
	check_eq(loaded.creature["name"], "Fixture", "the name")
	check_eq(loaded.creature["generation"], 3, "the generation, an int")
	check(loaded.creature["generation"] is int, "not a float")
	check_eq((loaded.creature["history"] as Array).size(), 2, "the history")
	check_eq(loaded.adaptation_points, 42, "the points")
	var body_before := JSON.stringify(JSON.parse_string(text)["creature"]["body"], "", true)
	check_eq(service.save_to(PATH, loaded), OK, "re-saves")
	var again: SaveGame = service.load_from(PATH).save
	check_eq(JSON.stringify(again.creature["body"], "", true), body_before, "the body survives a round trip unchanged")
	check_eq(again.creature["history"], loaded.creature["history"], "and the history")


func test_a_creature_with_a_bad_body_is_refused_and_the_backup_loads() -> void:
	_write_raw(PATH + PersistenceService.BACKUP_SUFFIX, FileAccess.get_file_as_string(V3_FIXTURE))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(V3_FIXTURE))
	(data["creature"]["body"] as Dictionary).erase("vertebrae")
	_write_raw(PATH, JSON.stringify(data))
	var primary := service._read_current_version(PATH)
	check(not primary.ok, "the primary is refused")
	var result := service.load_from(PATH)
	check(result.ok, "the backup loads: %s" % [result.errors])
	if result.ok:
		check_eq(result.save.creature["name"], "Fixture", "with its creature")


func test_a_creature_with_wrong_types_is_refused() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(V3_FIXTURE))
	data["creature"]["generation"] = 0
	data["creature"]["name"] = "  "
	_write_raw(PATH, JSON.stringify(data))
	var result := service.load_from(PATH)
	check(not result.ok, "refused")
	check(result.errors.size() >= 1, "with reasons: %s" % [result.errors])


func test_a_creature_with_a_bad_body_is_not_written() -> void:
	var save := _new_save()
	save.creature = CreatureRules.new_creature()
	check_eq(service.save_to(PATH, save), OK, "a good creature saves")
	var before := FileAccess.get_file_as_string(PATH)
	(save.creature["body"] as Dictionary).erase("vertebrae")
	check_eq(service.save_to(PATH, save), ERR_INVALID_DATA, "a bad body is refused")
	check_eq(FileAccess.get_file_as_string(PATH), before, "previous save intact")
