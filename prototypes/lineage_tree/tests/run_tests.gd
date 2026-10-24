extends SceneTree

const TreeModel := preload("res://lineage_tree.gd")

var failures := 0


func _init() -> void:
	for fixture in ["fresh_v2.json", "three_generations_v2.json", "long_run_v2.json", "save_v1.json"]:
		var result: Dictionary = TreeModel.load_save("res://fixtures/" + fixture)
		_check(result["ok"], fixture + " loads")
		if result["ok"]:
			_check(TreeModel.ascii(TreeModel.timeline(result["save"])) == TreeModel.ascii(TreeModel.timeline(result["save"])), fixture + " deterministic ASCII")
			if fixture == "save_v1.json":
				_check(result["save"]["schema_version"] == 2 and result["save"]["adaptation_points"] == 0, "v1 migrated in memory")
	var three: Dictionary = TreeModel.load_save("res://fixtures/three_generations_v2.json")
	if three["ok"]:
		var tree: Dictionary = TreeModel.timeline(three["save"])
		_check(tree["generations"] == 3, "two deaths produce three generations")
		_check(tree["nodes"].size() == three["save"]["lineage_history"].size(), "one node per event")
		var image: String = TreeModel.svg(tree, three["save"])
		_check(image == TreeModel.svg(tree, three["save"]), "SVG bytes deterministic")
		_check(image.count('class="event-node"') == tree["nodes"].size(), "SVG node element count")
		var xml := XMLParser.new()
		var path := ProjectSettings.globalize_path("res://fixtures/three_generations.svg")
		_check(xml.open(path) == OK, "committed SVG opens as XML")
		var depth := 0
		var saw_root := false
		while xml.read() == OK:
			if xml.get_node_type() == XMLParser.NODE_ELEMENT:
				depth += 1
				if xml.get_node_name() == "svg":
					saw_root = true
				if xml.is_empty():
					depth -= 1
			elif xml.get_node_type() == XMLParser.NODE_ELEMENT_END:
				depth -= 1
		_check(saw_root and depth == 0, "committed SVG well-formed")
		_check(FileAccess.get_file_as_string(path) == image, "committed SVG matches renderer")
	var malformed := TreeModel.load_save("res://fixtures/malformed.json")
	_check(not malformed["ok"] and malformed["error"].contains("Missing save field"), "malformed save rejected clearly")
	var fresh: Dictionary = TreeModel.load_save("res://fixtures/fresh_v2.json")
	if fresh["ok"]:
		var no_history: Dictionary = fresh["save"].duplicate(true)
		no_history["lineage_history"] = []
		var single: Dictionary = TreeModel.timeline(no_history)
		_check(single["nodes"].size() == 1 and single["nodes"][0]["kind"] == "founded", "empty history gets founding node")
		var ties: Dictionary = fresh["save"].duplicate(true)
		ties["lineage_history"] = [
			{"index": 2, "id": "z", "event": "checkpoint"},
			{"index": 1, "id": "b", "event": "adapted"},
			{"index": 1, "id": "a", "event": "born"},
		]
		var sorted: Array = TreeModel.timeline(ties)["nodes"]
		_check(sorted[0]["id"] == "a" and sorted[1]["id"] == "b" and sorted[2]["id"] == "z", "index then id ordering")
	print("FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + label)
