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


# The notice the player sees, and the editor session with a placeholder part in the body (second slice) ---------------


func test_notice_text_for_one_three_and_five_missing_parts() -> void:
	check_eq(PartManifest.notice(PackedStringArray()), "", "no notice when nothing is missing")
	check_eq(PartManifest.notice(PackedStringArray(["mod_a"])),
			"This creature uses 1 part this version does not have (mod_a). It is kept in the save and left out for now.",
			"one missing part")
	check_eq(PartManifest.notice(PackedStringArray(["mod_a", "mod_b", "mod_c"])),
			"This creature uses 3 parts this version does not have (mod_a, mod_b, mod_c). They are kept in the save and left out for now.",
			"three missing parts are all named")
	check_eq(PartManifest.notice(PackedStringArray(["mod_a", "mod_b", "mod_c", "mod_d", "mod_e"])),
			"This creature uses 5 parts this version does not have (mod_a, mod_b, mod_c and 2 more). They are kept in the save and left out for now.",
			"five missing parts: three named, then the rest counted")
	var body: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))["creature"]["body"]
	var desc: RefCounted = BodyCodec.from_dict(body)
	check(PartManifest.notice_for(desc, CreatureData.part_rules()).contains("1 part this version does not have (%s)" % UNKNOWN),
			"the fixture body's notice names its missing type")
	check_eq(PartManifest.part_label({"type": UNKNOWN}, CreatureData.part_rules()), "Missing part: %s" % UNKNOWN,
			"a placeholder part is labelled as missing")
	check_eq(PartManifest.part_label({"type": "eye"}, {"eye": {}}), "eye", "a known part keeps its type as its label")


func test_editor_session_with_a_placeholder_part() -> void:
	var Session = load("res://game/domain/creature/creature_editor_session.gd")
	var body: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))["creature"]["body"]
	var part_rules := CreatureData.part_rules()
	var s = Session.new(BodyCodec.from_dict(body), CreatureData.rules(), part_rules, CreatureData.editor_costs(), 500)
	var pv: Dictionary = s.preview()
	check(pv["errors"].is_empty(), "the opened body has no errors: %s" % [pv["errors"]])
	check_eq(int(pv["cost"]), 0, "nothing to pay for on opening")
	check(int(pv["phenotype"]["parts"].get(UNKNOWN, 0)) >= 1, "the stats count the placeholder part")
	var before := int(s.working.parts.size())
	# Changing a placeholder is refused, with the reason, and nothing changes.
	for r in [s.scale_part(UNKNOWN_ID, 1100), s.move_part(UNKNOWN_ID, {"u": 100}), s.orient_part(UNKNOWN_ID, {"turn": 10})]:
		check(not r["ok"], "changing a placeholder part is refused")
		check_eq(String(r.get("reason", "")), String(Session.MISSING_PART_TEXT), "with the missing-part reason")
	check_eq(int(s.cost()), 0, "a refused change costs nothing")
	# Removing it is allowed, refunds, and can be undone.
	var removed: Dictionary = s.remove_part(UNKNOWN_ID)
	check(removed["ok"], "the placeholder part can be removed: %s" % [removed])
	check_eq(int(s.working.parts.size()), before - 1, "one part fewer")
	check(PartManifest.missing(s.working, part_rules).is_empty(), "nothing is missing after the removal")
	check(int(s.cost()) <= 0, "removing it is a refund or free")
	check(s.preview()["errors"].is_empty(), "the body without it is valid")
	check(s.undo(), "the removal can be undone")
	check_eq(PartManifest.placeholder_ids(s.working, part_rules), PackedStringArray([UNKNOWN_ID]), "the placeholder is back")
	check_eq(int(s.cost()), 0, "and the cost is back to nothing")
	check(s.redo(), "and redone")
	var done: Dictionary = s.commit()
	check(done["ok"], "Done works after the removal: %s" % [done.get("errors", [])])
	# Saving the cleaned body, and saving a body that still has the placeholder after an edit session, both work.
	_write(slot_path, FileAccess.get_file_as_string(FIXTURE))
	var loaded := service.load_from(slot_path)
	if not loaded.ok or not done["ok"]:
		check(loaded.ok, "the save loads: %s" % [loaded.errors])
		return
	loaded.save.creature["body"] = done["body"].to_dict()
	check_eq(service.save_to(slot_path, loaded.save), OK, "the cleaned creature saves")
	var again := service.load_from(slot_path)
	check(again.ok, "and loads: %s" % [again.errors])
	check(again.warnings.is_empty(), "with no warning left: %s" % [again.warnings])
	var kept = Session.new(BodyCodec.from_dict(body), CreatureData.rules(), part_rules, CreatureData.editor_costs(), 500)
	var kept_done: Dictionary = kept.commit()
	check(kept_done["ok"], "Done works with the placeholder still on the body: %s" % [kept_done.get("errors", [])])
	if kept_done["ok"]:
		loaded.save.creature["body"] = kept_done["body"].to_dict()
		check_eq(service.save_to(slot_path, loaded.save), OK, "a body that keeps its placeholder saves after the editor")
		check_eq(service.load_from(slot_path).warnings.size(), 1, "and still warns on the next load")
