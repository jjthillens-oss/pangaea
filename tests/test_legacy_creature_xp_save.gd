extends TestCase
## Creature-stage saves accept a pre-deeds XP field, then write the current four-key creature.

const FIXTURE := "res://tests/fixtures/save_v3_creature.json"


class StubEditor:
	extends Node
	signal done_requested(body_dict: Dictionary, points_left: int)
	signal back_requested

	func setup(_body: RefCounted, _points: int) -> void:
		pass


var slot_path := "user://test_legacy_creature_xp_%d.json" % OS.get_process_id()
var stage: CreatureStage


func after_each() -> void:
	if stage != null:
		stage.free()
		stage = null
	for suffix in ["", PersistenceService.BACKUP_SUFFIX, PersistenceService.TEMP_SUFFIX]:
		var path: String = slot_path + String(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func test_old_xp_loads_and_creature_stage_save_discards_it() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	fixture["creature"]["xp"] = {"speed": 12, "strength": 3}
	var file := FileAccess.open(slot_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(fixture))
	file.close()
	var persistence := PersistenceService.new(PartCatalog.load_from())
	var old := persistence.load_from(slot_path)
	check(old.ok, "legacy XP save loads: %s" % [old.errors])
	if not old.ok:
		return
	check_eq(
		int(old.save.creature["xp"]["speed"]), 12, "old XP is read without losing the creature"
	)
	stage = CreatureStage.new()
	stage.make_editor = func() -> Node: return StubEditor.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(stage)
	stage.setup(slot_path, 99)
	check(
		stage.load_problems.is_empty(), "the stage opens the old save: %s" % [stage.load_problems]
	)
	check_eq(stage.state["points"], 42, "adaptation points survive the transition")
	check_eq(stage.save_now(), OK, "the stage saves in the current form")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(slot_path))
	check(not saved["creature"].has("xp"), "removed XP is absent from the next stage save")
	for key in ["name", "body", "generation", "history"]:
		check_eq(saved["creature"][key], fixture["creature"][key], "%s is retained" % key)
	check_eq(int(saved["adaptation_points"]), 42, "adaptation points remain the same")
	check(persistence.load_from(slot_path).ok, "the rewritten save still loads")
