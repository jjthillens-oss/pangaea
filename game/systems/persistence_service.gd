class_name PersistenceService
extends RefCounted
## Versioned save files with safe writes, a last-known-good backup and migrations (Bible section 18).
##
## Writing: validate -> write <path>.tmp -> re-read and parse it -> move the current good save
## to <path>.bak -> move .tmp into place. An interrupted write leaves either the old save or the
## backup intact.
## Loading: never modifies files. If the primary file is unreadable, invalid or from a newer
## build, the backup is tried. Errors explain what went wrong.

const CURRENT_VERSION := SaveGame.SCHEMA_VERSION
const BACKUP_SUFFIX := ".bak"
const TEMP_SUFFIX := ".tmp"

## from_version (int) -> Callable(Dictionary) -> Dictionary returning the next version's data.
var migrations: Dictionary = {}
var catalog: PartCatalog


func _init(p_catalog: PartCatalog) -> void:
	catalog = p_catalog


func save_to(path: String, save: SaveGame) -> Error:
	var errors := save.validate(catalog)
	if not errors.is_empty():
		push_error("Save refused: %s" % "; ".join(errors))
		return ERR_INVALID_DATA
	save.saved_at_unix = int(Time.get_unix_time_from_system())
	var text := JSON.stringify(save.to_dict(), "\t")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())

	var tmp := path + TEMP_SUFFIX
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	if _parse(FileAccess.get_file_as_string(tmp)) == null:
		DirAccess.remove_absolute(tmp)
		return ERR_FILE_CORRUPT

	if FileAccess.file_exists(path):
		if _read_current_version(path).ok:
			# Current file is good: it becomes the last-known-good backup.
			var backup := path + BACKUP_SUFFIX
			if FileAccess.file_exists(backup):
				DirAccess.remove_absolute(backup)
			var err := DirAccess.rename_absolute(path, backup)
			if err != OK:
				return err
		else:
			# Keep the existing backup and set the unreadable file aside instead of discarding it.
			var corrupt := "%s.corrupt-%d" % [path, Time.get_unix_time_from_system()]
			var err := DirAccess.rename_absolute(path, corrupt)
			if err != OK:
				return err
	return DirAccess.rename_absolute(tmp, path)


## Returns {"ok": bool, "save": SaveGame or null, "source": "primary" | "backup" | "", "errors": PackedStringArray}
func load_from(path: String) -> Dictionary:
	var primary := _read_current_version(path)
	if primary.ok:
		primary.source = "primary"
		return primary
	var backup := _read_current_version(path + BACKUP_SUFFIX)
	if backup.ok:
		backup.source = "backup"
		backup.errors = primary.errors
		return backup
	var errors: PackedStringArray = primary.errors
	errors.append_array(backup.errors)
	return {"ok": false, "save": null, "source": "", "errors": errors}


func _read_current_version(path: String) -> Dictionary:
	var result := {"ok": false, "save": null, "source": "", "errors": PackedStringArray()}
	if not FileAccess.file_exists(path):
		result.errors.append("%s: file not found." % path.get_file())
		return result
	var data = _parse(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		result.errors.append("%s: not a readable save file." % path.get_file())
		return result
	var migrated := migrate(data)
	if not migrated.ok:
		result.errors.append("%s: %s" % [path.get_file(), migrated.error])
		return result
	var save := SaveGame.from_dict(migrated.data)
	var problems := save.validate(catalog)
	if not problems.is_empty():
		for problem in problems:
			result.errors.append("%s: %s" % [path.get_file(), problem])
		return result
	result.ok = true
	result.save = save
	return result


## Returns {"ok": bool, "data": Dictionary, "error": String}. Works on a copy; the input is untouched.
func migrate(data: Dictionary) -> Dictionary:
	var version = data.get("schema_version")
	if not (version is int or version is float):
		return {"ok": false, "data": {}, "error": "missing schema version."}
	var current: Dictionary = data.duplicate(true)
	var v := int(version)
	if v > CURRENT_VERSION:
		return {"ok": false, "data": {}, "error": "made by a newer build (schema %d, this build reads up to %d)." % [v, CURRENT_VERSION]}
	while v < CURRENT_VERSION:
		if not migrations.has(v):
			return {"ok": false, "data": {}, "error": "no migration from schema %d." % v}
		current = migrations[v].call(current)
		var next := int(current.get("schema_version", v))
		if next <= v:
			return {"ok": false, "data": {}, "error": "migration from schema %d did not advance the version." % v}
		v = next
	return {"ok": true, "data": current, "error": ""}


## Parses quietly; a damaged file is an expected case here, not an engine error.
static func _parse(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null
