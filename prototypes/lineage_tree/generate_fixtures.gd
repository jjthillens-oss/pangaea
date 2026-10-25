extends SceneTree


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://fixtures"))
	var fresh := _base()
	_write("fresh_v2.json", fresh)
	var three := _base()
	three["genome"]["generation"] = 3
	three["lineage_history"] = [
		_event("founded", 1, 0),
		_event("adapted", 1, 1, "eye_spot"),
		_event("died", 1, 2, "starved"),
		_event("respawned", 2, 3),
		_event("checkpoint", 2, 4),
		_event("died", 2, 5, "killed:ambush_hunter"),
		_event("born", 3, 6),
		_event("part_added", 3, 7, "spike"),
	]
	_write("three_generations_v2.json", three)
	var long_run := _base()
	for index in 24:
		long_run["lineage_history"].append(_event("adapted", 1, index + 1, "part_%d" % (index + 3)))
	_write("long_run_v2.json", long_run)
	quit(0)


func _base() -> Dictionary:
	return {
		"schema_version": 2,
		"build_id": "lineage-fixture",
		"world_seed": 2026,
		"lineage_id": "lineage_3f9a1c07b2e84d65",
		"era": "microscopic",
		"genome": {
			"schema_version": 1,
			"genome_id": "genome_8d21e6a4f03b9c57",
			"lineage_id": "lineage_3f9a1c07b2e84d65",
			"parent_genome_id": "",
			"generation": 1,
			"appearance": {"hue": 0.45, "pattern": "plain"},
			"parts": [
				{"id": "part_1", "type": "mouth_jaw", "angle": 0.0, "scale": 1.0},
				{"id": "part_2", "type": "flagellum", "angle": 3.14159, "scale": 1.0},
			],
			"next_part_number": 3,
		},
		"adaptation_points": 0,
		"lineage_history": [_event("founded", 1, 0)],
		"discoveries": [],
		"relationships": [],
		"settlements": [],
		"world_changes": [],
		"player": {"position": [0.0, 0.0, 0.0]},
		"pending_transactions": [],
		"saved_at_unix": 0,
	}


func _event(kind: String, generation: int, index: int, detail: String = "") -> Dictionary:
	var event := {"event": kind, "generation": generation, "genome_id": "genome_8d21e6a4f03b9c57", "index": index, "id": "event_%03d" % index}
	if detail != "":
		event["cause" if kind == "died" else "part_type"] = detail
	return event


func _write(name: String, data: Dictionary) -> void:
	var path := ProjectSettings.globalize_path("res://fixtures/" + name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write fixture: " + path)
		quit(2)
		return
	file.store_string(JSON.stringify(data, "\t") + "\n")
