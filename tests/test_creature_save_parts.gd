extends TestCase
## Save v3 must name invalid creature parts and recover the last complete body.

const FIXTURE := "res://tests/fixtures/save_v3_creature.json"
const SUFFIXES := ["", PersistenceService.BACKUP_SUFFIX, PersistenceService.TEMP_SUFFIX]

var slot_path := "user://test_creature_save_parts_%d.json" % OS.get_process_id()
var service: PersistenceService


func before_each() -> void:
	service = PersistenceService.new(PartCatalog.load_from())
	_clear()


func after_each() -> void:
	_clear()


func _clear() -> void:
	for suffix in SUFFIXES:
		var path: String = slot_path + String(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()


func test_unknown_part_loads_complete_backup_with_a_clear_reason() -> void:
	var good := FileAccess.get_file_as_string(FIXTURE)
	_write(slot_path + PersistenceService.BACKUP_SUFFIX, good)
	var data: Dictionary = JSON.parse_string(good)
	var parts: Array = data["creature"]["body"]["parts"]
	parts[0]["type"] = "unrecognized_part"
	var damaged := JSON.stringify(data)
	_write(slot_path, damaged)
	var result := service.load_from(slot_path)
	check(result.ok, "the valid backup loads: %s" % [result.errors])
	check_eq(result.source, "backup", "the invalid primary is not accepted")
	check_has_error(result.errors, "unknown type unrecognized_part")
	check_eq(
		FileAccess.get_file_as_string(slot_path), damaged, "damaged file is left for diagnosis"
	)
	check_eq(
		FileAccess.get_file_as_string(slot_path + PersistenceService.BACKUP_SUFFIX),
		good,
		"backup is unchanged"
	)
	if result.ok:
		var recovered: Array = result.save.creature["body"]["parts"]
		check_eq(recovered.size(), parts.size(), "all backup parts are retained")
		check_eq(recovered[0]["type"], "eye", "the original part is restored")


func test_unknown_part_cannot_overwrite_a_good_save() -> void:
	var good := FileAccess.get_file_as_string(FIXTURE)
	_write(slot_path, good)
	var result := service.load_from(slot_path)
	check(result.ok, "the fixture loads: %s" % [result.errors])
	if not result.ok:
		return
	var save: SaveGame = result.save
	(save.creature["body"]["parts"] as Array)[0]["type"] = "unrecognized_part"
	check_eq(service.save_to(slot_path, save), ERR_INVALID_DATA, "the invalid part is refused")
	check_eq(FileAccess.get_file_as_string(slot_path), good, "the last good save remains intact")
	check(
		not FileAccess.file_exists(slot_path + PersistenceService.TEMP_SUFFIX),
		"no temp file remains"
	)
