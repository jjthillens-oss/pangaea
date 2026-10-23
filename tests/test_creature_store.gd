extends TestCase
## The creature stage's own save file (game/systems/creature/creature_store.gd): a fresh state, the default path,
## a round trip, the atomic write (no .tmp left, a bad state writes nothing) and the refusals a load explains.
## Files go to the per-process folder under user://test_saves, never the player's.

const SaveFolder := preload("res://tests/save_folder.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")

var store: CreatureStore
var path := ""


func before_each() -> void:
	SaveFolder.clear()
	store = CreatureStore.new()
	path = SaveFolder.path("creature_slot.json")


func after_each() -> void:
	SaveFolder.clear()


func test_default_path_is_the_stage_folder_not_the_lineage_slot() -> void:
	check_eq(CreatureStore.default_path(1), "user://creature_stage/slot_1.json", "slot 1")
	check_eq(CreatureStore.default_path(3), "user://creature_stage/slot_3.json", "slot 3")
	check(not CreatureStore.default_path(1).begins_with(SaveSlots.folder), "never under the lineage slots")


func test_new_state_is_the_starter_quadruped_with_the_start_points() -> void:
	var state := CreatureStore.new_state(4242)
	check_eq(state["version"], CreatureStore.SCHEMA_VERSION, "version")
	check_eq(state["name"], "Newcomer", "name")
	check_eq(state["world_seed"], 4242, "seed")
	check_eq(state["generation"], 1, "generation")
	check_eq(state["history"], [], "no history")
	check_eq(state["points"], CreatureStore.start_points(), "the tuning's start points")
	check(state["points"] is int and state["points"] > 0, "points are a whole positive number")
	var body := BodyCodec.from_dict(state["body"])
	check_eq(BodyCodec.encode(body), BodyCodec.encode(CreatureStore.CreatureData.body("s1_quadruped")), "the starter quadruped")
	check(store.validate(state).is_empty(), "a fresh state is valid: %s" % [store.validate(state)])


func test_round_trip_keeps_body_points_and_seed() -> void:
	var state := CreatureStore.new_state(77)
	state["points"] = 120
	state["generation"] = 3
	state["history"].append({"generation": 2, "points": 95})
	check_eq(store.save_to(path, state), OK, "saved")
	var loaded := store.load_from(path)
	check(loaded.ok, "loads back: %s" % [loaded.errors])
	check_eq(loaded.state["points"], 120, "points")
	check_eq(loaded.state["world_seed"], 77, "seed")
	check_eq(loaded.state["generation"], 3, "generation")
	check_eq(loaded.state["name"], "Newcomer", "name")
	check_eq((loaded.state["history"] as Array).size(), 1, "history")
	check(loaded.state["points"] is int and loaded.state["world_seed"] is int, "whole numbers come back as int")
	check_eq(BodyCodec.encode(BodyCodec.from_dict(loaded.state["body"])), BodyCodec.encode(BodyCodec.from_dict(state["body"])),
			"the same body, byte for byte")


func test_write_is_atomic_and_leaves_no_temp_file() -> void:
	var state := CreatureStore.new_state(1)
	check_eq(store.save_to(path, state), OK, "first save")
	check(not FileAccess.file_exists(path + CreatureStore.TEMP_SUFFIX), "no .tmp after a save")
	state["points"] = 99
	check_eq(store.save_to(path, state), OK, "a second save replaces the file")
	check(not FileAccess.file_exists(path + CreatureStore.TEMP_SUFFIX), "still no .tmp")
	check_eq(store.load_from(path).state["points"], 99, "the second save is the one on disk")
	var bad := state.duplicate(true)
	bad["points"] = -5
	check_eq(store.save_to(path, bad), ERR_INVALID_DATA, "a bad state is refused")
	check(not FileAccess.file_exists(path + CreatureStore.TEMP_SUFFIX), "and writes no .tmp")
	check_eq(store.load_from(path).state["points"], 99, "the good file is untouched")


func test_refusals_explain_themselves() -> void:
	var missing := store.load_from(path)
	check(not missing.ok and missing.state.is_empty(), "no file: not ok")
	check_has_error(missing.errors, "file not found")

	_write(path, "{not json")
	var garbage := store.load_from(path)
	check(not garbage.ok, "garbage: not ok")
	check_has_error(garbage.errors, "not a readable creature save")

	var wrong_version := CreatureStore.new_state(1)
	wrong_version["version"] = 2
	_write(path, JSON.stringify(wrong_version))
	check_has_error(store.load_from(path).errors, "schema 2 is not this build's (1)")

	var no_version := CreatureStore.new_state(1)
	no_version.erase("version")
	_write(path, JSON.stringify(no_version))
	check_has_error(store.load_from(path).errors, "missing schema version")

	var no_body := CreatureStore.new_state(1)
	no_body.erase("body")
	no_body.erase("history")
	_write(path, JSON.stringify(no_body))
	var errors: PackedStringArray = store.load_from(path).errors
	check_has_error(errors, "missing body")
	check_has_error(errors, "missing history")

	var fraction := CreatureStore.new_state(1)
	fraction["points"] = 12.5
	_write(path, JSON.stringify(fraction))
	check_has_error(store.load_from(path).errors, "points is not int")

	var text_points := CreatureStore.new_state(1)
	text_points["points"] = "lots"
	_write(path, JSON.stringify(text_points))
	check_has_error(store.load_from(path).errors, "points is not int")

	var bad_body := CreatureStore.new_state(1)
	bad_body["body"]["vertebrae"] = bad_body["body"]["vertebrae"].slice(0, 1)
	_write(path, JSON.stringify(bad_body))
	check_has_error(store.load_from(path).errors, "body: 1 vertebrae; a spine needs")

	var bad_part := CreatureStore.new_state(1)
	bad_part["body"]["parts"].append({"id": "p_x", "type": "no_such_part", "host": "spine", "u": 500, "ring": 250,
			"elev": 0, "height": 0, "turn": 0, "tilt": 0, "roll": 0, "scale": 1000, "handles": [], "mirror": false})
	_write(path, JSON.stringify(bad_part))
	check_has_error(store.load_from(path).errors, "unknown type no_such_part")
	for r in [missing, garbage]:
		check(r.state.is_empty(), "a refused load gives no state")


func _write(p: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()
