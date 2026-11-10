extends TestCase
## IB-31 "Graceful sharing" (PROPOSED), first slice: a save whose creature has a part of a type this build does not
## have loads with that part kept as a placeholder and a warning, never a refusal. Other part problems still fail.

const FIXTURE := "res://tests/fixtures/save_v3_creature_unknown_part.json"
const UNKNOWN := "mod_crystal_horn"
const UNKNOWN_ID := "p_3"
const SUFFIXES := ["", PersistenceService.BACKUP_SUFFIX, PersistenceService.TEMP_SUFFIX]
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const PartManifest := preload("res://game/domain/creature/part_manifest.gd")

var slot_path := "user://test_graceful_sharing_%d.json" % OS.get_process_id()
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


func _fixture_parts() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))["creature"]["body"]["parts"]


func test_unknown_part_loads_with_a_placeholder_and_a_warning() -> void:
	_write(slot_path, FileAccess.get_file_as_string(FIXTURE))
	var result := service.load_from(slot_path)
	check(result.ok, "the save loads: %s" % [result.errors])
	check_eq(result.source, "primary", "no fallback to a backup")
	check(result.errors.is_empty(), "no errors: %s" % [result.errors])
	check_eq(result.warnings.size(), 1, "one warning: %s" % [result.warnings])
	check_has_error(result.warnings, "part %s needs the missing part type %s" % [UNKNOWN_ID, UNKNOWN])
	if not result.ok:
		return
	var body: Dictionary = result.save.creature["body"]
	check_eq(service.creature_rules.missing_parts(body), PackedStringArray([UNKNOWN]), "the missing type is listed")
	var desc: RefCounted = BodyCodec.from_dict(body)
	check_eq(PartManifest.placeholder_ids(desc, CreatureData.part_rules()), PackedStringArray([UNKNOWN_ID]),
			"only the unknown part is a placeholder")


func test_known_parts_are_unaffected() -> void:
	_write(slot_path, FileAccess.get_file_as_string(FIXTURE))
	var result := service.load_from(slot_path)
	if not result.ok:
		check(false, "the save loads: %s" % [result.errors])
		return
	var loaded: Array = result.save.creature["body"]["parts"]
	var written := _fixture_parts()
	check_eq(loaded.size(), written.size(), "every part is kept")
	var part_rules := CreatureData.part_rules()
	for i in mini(loaded.size(), written.size()):
		check_eq(String(loaded[i]["type"]), String(written[i]["type"]), "part %d keeps its type" % i)
		if String(written[i]["id"]) != UNKNOWN_ID:
			check(not PartManifest.is_placeholder(loaded[i], part_rules), "part %s is not a placeholder" % written[i]["id"])


func test_round_trip_keeps_the_unknown_part() -> void:
	_write(slot_path, FileAccess.get_file_as_string(FIXTURE))
	var first := service.load_from(slot_path)
	if not first.ok:
		check(false, "the save loads: %s" % [first.errors])
		return
	check_eq(service.save_to(slot_path, first.save), OK, "a body with a placeholder part saves")
	var second := service.load_from(slot_path)
	check(second.ok, "it loads again: %s" % [second.errors])
	if not second.ok:
		return
	var written: Dictionary = _fixture_parts()[2]
	var kept: Dictionary = (second.save.creature["body"]["parts"] as Array)[2]
	check_eq(String(kept["id"]), UNKNOWN_ID, "the part keeps its id")
	check_eq(String(kept["type"]), UNKNOWN, "the part keeps its type id")
	check_eq(String(kept["host"]), String(written["host"]), "the part keeps its host")
	check_eq(bool(kept["mirror"]), bool(written["mirror"]), "the part keeps its twin")
	for key in ["u", "ring", "elev", "height", "turn", "tilt", "roll", "scale"]:
		check_eq(int(kept[key]), int(written[key]), "the part keeps its anchor field %s" % key)
	check_eq(second.warnings.size(), 1, "the warning is raised again; it is derived, not saved")
	check(not FileAccess.get_file_as_string(slot_path).contains("placeholder"), "no placeholder flag is written to the save")


func test_an_invalid_known_part_still_fails() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	data["creature"]["body"]["parts"][0]["scale"] = 99999
	_write(slot_path, JSON.stringify(data))
	var result := service.load_from(slot_path)
	check(not result.ok, "a known part scaled past its limit is refused")
	check_has_error(result.errors, "part p_1 scale 99999 is outside")


func test_a_part_with_no_type_or_a_bad_anchor_still_fails() -> void:
	var rules := CreatureRules.new()
	var body: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))["creature"]["body"]
	check(rules.body_problems(body).is_empty(), "the fixture body has no problems: %s" % [rules.body_problems(body)])
	var untyped: Dictionary = body.duplicate(true)
	untyped["parts"][2]["type"] = ""
	check_has_error(rules.body_problems(untyped), "part %s has no type" % UNKNOWN_ID)
	var off: Dictionary = body.duplicate(true)
	off["parts"][2]["u"] = 5000
	check_has_error(rules.body_problems(off), "part %s anchor is out of range" % UNKNOWN_ID)


func test_part_manifest_lists_needed_and_missing() -> void:
	var desc: RefCounted = BodyCodec.from_dict({"parts": [
		{"id": "p_1", "type": "eye"}, {"id": "p_2", "type": "zz_gone"}, {"id": "p_3", "type": "eye"},
		{"id": "p_4", "type": "aa_gone"}], "next": {"v": 1}})
	var known := {"eye": {}}
	check_eq(PartManifest.needed(desc), PackedStringArray(["aa_gone", "eye", "zz_gone"]), "needed types, once each, sorted")
	check_eq(PartManifest.missing(desc, known), PackedStringArray(["aa_gone", "zz_gone"]), "missing types, sorted")
	check_eq(PartManifest.placeholder_ids(desc, known), PackedStringArray(["p_2", "p_4"]), "placeholder parts in body order")
	check_eq(PartManifest.warnings(desc, known).size(), 2, "one warning for each placeholder part")
	check(PartManifest.missing(desc, {"eye": {}, "aa_gone": {}, "zz_gone": {}}).is_empty(), "nothing missing when all are known")
