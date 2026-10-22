class_name BuildInfo
extends RefCounted
## Identifies the running build. tools/write_build_info.sh writes game/data/build_info.json
## before an export; without it the build reports itself as a local dev build.

const PATH := "res://game/data/build_info.json"


static func read() -> Dictionary:
	var info := {
		"version": str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		"commit": "dev",
		"built_at": "",
		"engine": Engine.get_version_info().string,
	}
	if FileAccess.file_exists(PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Dictionary:
			info.commit = str(data.get("commit", "dev"))
			info.built_at = str(data.get("built_at", ""))
	return info


static func build_id() -> String:
	var info := read()
	return "%s+%s" % [info.version, info.commit]
