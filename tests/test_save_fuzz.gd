extends TestCase
## Bounded, deterministic damaged-file cases through the real file loader.

const ROOT := "user://test_save_fuzz"
const MAX_CASES := 48
var folder := ROOT + "/%d" % OS.get_process_id()
var path := folder + "/slot.json"
var service: PersistenceService


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	service = PersistenceService.new(PartCatalog.load_from())
	_clear()


func after_each() -> void:
	_clear()


func _clear() -> void:
	for name in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder + "/" + name)


func _write(text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _valid_data() -> Dictionary:
	var save := SaveGame.new_run(12345, "fuzz-test")
	save.genome.add_part("mouth_jaw", 0.0)
	save.genome.add_part("flagellum", PI)
	return save.to_dict()


func _assert_rejected_unchanged(text: String, label: String) -> void:
	_write(text)
	var result := service.load_from(path)
	check(not result.ok, "%s is refused" % label)
	check(not result.errors.is_empty(), "%s gives an error" % label)
	check_eq(FileAccess.get_file_as_string(path), text, "%s preserves original" % label)


func test_corrupt_and_truncated_json_is_refused_with_a_message() -> void:
	var valid := JSON.stringify(_valid_data())
	var cases := ["", "{", "null", "[]", "true", "42", "{oops}", "{\"schema_version\":4"]
	for text in cases:
		_assert_rejected_unchanged(text, "corrupt %s" % text)
	var cuts := RandomNumberGenerator.new()
	cuts.seed = 38038
	for i in 24:
		var n := cuts.randi_range(1, valid.length() - 1)
		_assert_rejected_unchanged(valid.substr(0, n), "seeded truncation %d at %d" % [i, n])
	for length in [1, 2, 8, 32, 128, valid.length() / 2]:
		_assert_rejected_unchanged(valid.substr(0, length), "truncated at %d" % length)


func test_seeded_wrong_type_mutations_are_refused_without_touching_files() -> void:
	var fields := ["schema_version", "build_id", "world_seed", "lineage_id", "era", "genome",
		"adaptation_points", "creature", "lineage_history", "discoveries", "relationships",
		"settlements", "world_changes", "player", "pending_transactions", "growth",
		"checkpoint", "spawn", "gen_version", "saved_at_unix"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 38040
	for i in MAX_CASES:
		var data := _valid_data()
		var key: String = fields[rng.randi_range(0, fields.size() - 1)]
		data[key] = false
		_assert_rejected_unchanged(JSON.stringify(data), "wrong type %d %s" % [i, key])
	var fractional := _valid_data()
	fractional.schema_version = 3.5
	_assert_rejected_unchanged(JSON.stringify(fractional), "fractional version")


func test_old_and_future_versions_keep_originals() -> void:
	for fixture in ["save_v1.json", "save_v2_step2.json", "save_v3_creature.json", "save_v3_s2.json"]:
		var text := FileAccess.get_file_as_string("res://tests/fixtures/" + fixture)
		check(not text.is_empty(), "%s fixture available" % fixture)
		_write(text)
		var loaded := service.load_from(path)
		check(loaded.ok, "%s migrates: %s" % [fixture, loaded.errors])
		check_eq(FileAccess.get_file_as_string(path), text, "%s unchanged" % fixture)
	var data := _valid_data()
	data.schema_version = SaveGame.SCHEMA_VERSION + 1
	_assert_rejected_unchanged(JSON.stringify(data), "future version")
	data.schema_version = 1e40
	_assert_rejected_unchanged(JSON.stringify(data), "very large future version")


func test_oversized_primary_falls_back_to_backup_and_is_preserved() -> void:
	var save := SaveGame.from_dict(_valid_data())
	check_eq(service.save_to(path, save), OK, "writes valid primary")
	check_eq(service.save_to(path, save), OK, "writes valid backup")
	var oversized := "x".repeat(PersistenceService.MAX_SAVE_BYTES + 1)
	_write(oversized)
	var result := service.load_from(path)
	check(result.ok, "valid backup loads")
	check_eq(result.source, "backup", "backup source")
	check_has_error(result.errors, "too large")
	check_eq(FileAccess.open(path, FileAccess.READ).get_length(), oversized.length(), "oversized primary preserved")



func test_nested_wrong_types_are_refused_without_crashing_or_rewriting() -> void:
	var cases := [
		{"path": ["player", "position"], "value": [0.0, false, 0.0]},
		{"path": ["player", "energy"], "value": "full"},
		{"path": ["growth", "meter"], "value": "full"},
		{"path": ["growth", "size"], "value": 2.5},
		{"path": ["checkpoint", "heading"], "value": "north"},
		{"path": ["genome", "parts"], "value": "missing"},
		{"path": ["genome", "generation"], "value": []},
		{"path": ["discoveries"], "value": [false]},
		{"path": ["spawn"], "value": {"heading": false, "x_am": 0.0, "y_am": 9.0}},
	]
	for i in cases.size():
		var data := _valid_data()
		var keys: Array = cases[i].path
		if keys.size() == 1:
			data[keys[0]] = cases[i].value
		else:
			data[keys[0]][keys[1]] = cases[i].value
		_assert_rejected_unchanged(JSON.stringify(data), "nested wrong type %d" % i)


func test_slot_summary_reports_corrupt_primary_and_uses_backup_without_writing() -> void:
	var original_folder := SaveSlots.folder
	SaveSlots.folder = folder
	var slot := SaveSlots.path(1)
	var save := SaveGame.from_dict(_valid_data())
	check_eq(service.save_to(slot, save), OK, "slot writes")
	check_eq(service.save_to(slot, save), OK, "backup writes")
	var corrupt := "{not a save"
	var file := FileAccess.open(slot, FileAccess.WRITE)
	file.store_string(corrupt)
	file.close()
	var peek := SaveSlots.peek(1)
	check(peek.ok, "slot shows valid backup")
	check_eq(peek.source, "backup", "slot indicates recovery source")
	check(not peek.errors.is_empty(), "slot reports corrupt primary")
	check_eq(FileAccess.get_file_as_string(slot), corrupt, "peek preserves corrupt original")
	SaveSlots.folder = original_folder
