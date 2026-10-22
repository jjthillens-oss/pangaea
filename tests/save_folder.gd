extends RefCounted
## Test helper (not a test file): the per-process folder under user://test_saves that tests write
## saves into, so two test runs at once cannot touch each other's files. It is the folder
## test_persistence.gd uses; folders left by killed runs are removed once their process is gone.
##
##     const SaveFolder := preload("res://tests/save_folder.gd")
##     var slot := SaveFolder.path("session_slot.json")

const ROOT := "user://test_saves"


static func dir() -> String:
	return ROOT + "/%d" % OS.get_process_id()


static func path(file: String) -> String:
	return dir() + "/" + file


## Empties and removes this process's folder.
static func clear() -> void:
	_remove(dir())


static func sweep_stale() -> void:
	# A fresh user folder (every CI run) has none yet; listing it would log an engine error.
	if not DirAccess.dir_exists_absolute(ROOT):
		return
	for sub in DirAccess.get_directories_at(ROOT):
		if sub.is_valid_int() and int(sub) != OS.get_process_id() and not OS.is_process_running(int(sub)):
			_remove(ROOT + "/" + sub)


static func _remove(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for f in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder + "/" + f)
	DirAccess.remove_absolute(folder)
