class_name CreatureStore
extends RefCounted
## The creature stage's own save file (creature-stage plan section 3, PROPOSED): schema 1, kept apart from the
## lineage slot under user://creature_stage/slot_<n>.json. Folding the body into the lineage save is save schema
## v3 and waits for the owner (docs/DECISIONS.md).
##
## State: {"version", "name", "body" (body_codec's dictionary), "points", "world_seed", "generation", "history"}.
## Writing is atomic like PersistenceService: write <path>.tmp, read it back, then rename it into place; a failed
## write removes its .tmp. Loading never writes: a wrong version, a missing key, a wrong type or a body that breaks
## the body rules or part rules is refused with reasons, and the caller starts fresh (CreatureStage keeps the
## reasons in load_problems).

const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")

const SCHEMA_VERSION := 1
const FOLDER := "user://creature_stage"
const TEMP_SUFFIX := ".tmp"
## The save before the last one, kept as PersistenceService keeps its backup; load_from falls back to it.
const BACKUP_SUFFIX := ".bak"
const STARTER_BODY := "quadruped"
const DEFAULT_NAME := "Newcomer"
## The world tuning file (owned by the world track); start_points falls back to DEFAULT_START_POINTS without it.
const TUNING_PATH := "res://game/data/creature/creature_stage.json"
const DEFAULT_START_POINTS := 150
## Every key a state carries, with the type each must have.
const KEY_TYPES := {"version": TYPE_INT, "name": TYPE_STRING, "body": TYPE_DICTIONARY, "points": TYPE_INT,
		"world_seed": TYPE_INT, "generation": TYPE_INT, "history": TYPE_ARRAY}

## The body rules and part rules the loaded body is validated with (CreatureData's by default; tests may inject).
var rules: Dictionary
var part_rules: Dictionary


func _init(p_rules: Dictionary = {}, p_part_rules: Dictionary = {}) -> void:
	rules = p_rules if not p_rules.is_empty() else CreatureData.rules()
	part_rules = p_part_rules if not p_part_rules.is_empty() else CreatureData.part_rules()


## "user://creature_stage/slot_<n>.json".
static func default_path(slot: int) -> String:
	return FOLDER + "/slot_%d.json" % slot


## The tuning's start_points, or DEFAULT_START_POINTS when the tuning file is not there yet.
static func start_points() -> int:
	if not FileAccess.file_exists(TUNING_PATH):
		return DEFAULT_START_POINTS
	var data = JSON.parse_string(FileAccess.get_file_as_string(TUNING_PATH))
	if data is Dictionary and (data.get("start_points") is int or data.get("start_points") is float):
		return int(data["start_points"])
	return DEFAULT_START_POINTS


## A fresh state: the starter quadruped, the tuning's points, generation 1 and no history.
static func new_state(world_seed: int) -> Dictionary:
	return {"version": SCHEMA_VERSION, "name": DEFAULT_NAME, "body": CreatureData.body(STARTER_BODY).to_dict(),
			"points": start_points(), "world_seed": world_seed, "generation": 1, "history": []}


## Writes the state atomically. A state that would not load back is refused (ERR_INVALID_DATA) and nothing is
## written; a .tmp that could not be read back or moved into place is removed.
func save_to(path: String, state: Dictionary) -> Error:
	var errors := validate(state)
	if not errors.is_empty():
		push_error("Creature save refused: %s" % "; ".join(errors))
		return ERR_INVALID_DATA
	var text := JSON.stringify(state, "\t")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + TEMP_SUFFIX
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	var written := load_from(tmp)
	if not written.ok or int(written.state["points"]) != int(state["points"]) \
			or int(written.state["world_seed"]) != int(state["world_seed"]) \
			or BodyCodec.encode(BodyCodec.from_dict(written.state["body"])) != BodyCodec.encode(BodyCodec.from_dict(state["body"])):
		DirAccess.remove_absolute(tmp)
		return ERR_FILE_CORRUPT
	var backup := path + BACKUP_SUFFIX
	var backed_up := false
	if FileAccess.file_exists(path):
		# The current file becomes the backup first, so a failed move still leaves the player a save.
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)
		var err := DirAccess.rename_absolute(path, backup)
		if err != OK:
			DirAccess.remove_absolute(tmp)
			return err
		backed_up = true
	var moved := DirAccess.rename_absolute(tmp, path)
	if moved != OK:
		DirAccess.remove_absolute(tmp)
		if backed_up:
			DirAccess.rename_absolute(backup, path)
	return moved


## Returns {"ok": bool, "state": Dictionary (whole numbers as int), "errors": PackedStringArray}. When the file does
## not read, its .bak is tried (the result then carries "source": "backup"); the primary's reasons are kept either
## way. Never writes.
func load_from(path: String) -> Dictionary:
	var result := _read(path)
	if result.ok or not FileAccess.file_exists(path + BACKUP_SUFFIX) or path.ends_with(BACKUP_SUFFIX) \
			or path.ends_with(TEMP_SUFFIX):
		return result
	var backup := _read(path + BACKUP_SUFFIX)
	if backup.ok:
		backup["source"] = "backup"
		backup["errors"] = result.errors
		return backup
	return result


func _read(path: String) -> Dictionary:
	var result := {"ok": false, "state": {}, "errors": PackedStringArray()}
	var name := path.get_file()
	if not FileAccess.file_exists(path):
		result.errors.append("%s: file not found." % name)
		return result
	var json := JSON.new()
	var data = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	if not data is Dictionary:
		result.errors.append("%s: not a readable creature save." % name)
		return result
	var state := _normalise(data)
	for problem in validate(state):
		result.errors.append("%s: %s" % [name, problem])
	if not result.errors.is_empty():
		return result
	result.ok = true
	result.state = state
	return result


## Every problem with a state, as readable reasons: the version, the keys and their types, then the body against
## the body rules and the part rules. Empty means the state saves and loads.
func validate(state: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var version = state.get("version")
	if not version is int:
		out.append("missing schema version.")
	elif int(version) != SCHEMA_VERSION:
		out.append("schema %d is not this build's (%d)." % [int(version), SCHEMA_VERSION])
	for key in KEY_TYPES:
		if not state.has(key):
			out.append("missing %s." % key)
		elif typeof(state[key]) != KEY_TYPES[key]:
			out.append("%s is not %s." % [key, type_string(KEY_TYPES[key]).to_lower()])
	if not out.is_empty():
		return out
	if int(state["points"]) < 0:
		out.append("points is negative.")
	if int(state["generation"]) < 1:
		out.append("generation is below 1.")
	if String(state["name"]).strip_edges().is_empty():
		out.append("name is empty.")
	var body: RefCounted = BodyCodec.from_dict(state["body"])
	var body_errors: PackedStringArray = body.validate(rules)
	body_errors.append_array(body.validate_parts(rules, part_rules))
	for e in body_errors:
		out.append("body: %s" % e)
	return out


## JSON gives floats for every number; the whole ones the schema asks for become int, so validate() can tell a
## whole number from a fraction, and the state carries ints as new_state() does.
static func _normalise(data: Dictionary) -> Dictionary:
	var state := data.duplicate(true)
	for key in ["version", "points", "world_seed", "generation"]:
		var v = state.get(key)
		if v is float and is_finite(v) and v == floorf(v):
			state[key] = int(v)
	return state
