extends RefCounted

const REQUIRED := ["schema_version", "build_id", "world_seed", "lineage_id", "era", "genome", "adaptation_points", "lineage_history", "discoveries", "relationships", "settlements", "world_changes", "player", "pending_transactions", "saved_at_unix"]
const ERAS := ["microscopic", "aquatic", "terrestrial", "social", "tribal", "civilization", "interstellar"]


static func load_save(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Cannot read save: " + path}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {"ok": false, "error": "Save must be a JSON object."}
	var data: Dictionary = parsed
	if data.get("schema_version") == 1:
		data = data.duplicate(true)
		data["schema_version"] = 2
		data["adaptation_points"] = 0
	elif data.get("schema_version") != 2:
		return {"ok": false, "error": "Unsupported save schema version."}
	for key in REQUIRED:
		if not data.has(key):
			return {"ok": false, "error": "Missing save field: " + key}
	for key in ["build_id", "lineage_id", "era"]:
		if not data[key] is String:
			return {"ok": false, "error": "Invalid save field: " + key}
	if not ERAS.has(data["era"]):
		return {"ok": false, "error": "Unknown era: " + data["era"]}
	if not _whole(data["world_seed"]) or data["world_seed"] < 0 or data["world_seed"] > 9007199254740992:
		return {"ok": false, "error": "World seed is outside the save range."}
	if not _whole(data["adaptation_points"]) or data["adaptation_points"] < 0:
		return {"ok": false, "error": "Invalid adaptation points."}
	if not _whole(data["saved_at_unix"]):
		return {"ok": false, "error": "Invalid save timestamp."}
	if not _valid_id(data["lineage_id"], "lineage_"):
		return {"ok": false, "error": "Invalid lineage id."}
	var genome = data["genome"]
	if not genome is Dictionary or not _valid_genome(genome, data["lineage_id"]):
		return {"ok": false, "error": "Invalid genome."}
	for key in ["lineage_history", "discoveries", "relationships", "settlements", "world_changes", "pending_transactions"]:
		if not data[key] is Array:
			return {"ok": false, "error": "Invalid save array: " + key}
	for event in data["lineage_history"]:
		if not event is Dictionary or not event.get("event") is String:
			return {"ok": false, "error": "Invalid lineage history event."}
	var player = data["player"]
	if not player is Dictionary or not player.get("position") is Array or player["position"].size() != 3:
		return {"ok": false, "error": "Player position must have three coordinates."}
	return {"ok": true, "error": "", "save": data}


static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value)) == float(value)


static func _valid_id(value: Variant, prefix: String) -> bool:
	if not value is String or not value.begins_with(prefix) or value.length() != prefix.length() + 16:
		return false
	for character in value.substr(prefix.length()):
		if not "0123456789abcdef".contains(character):
			return false
	return true


static func _valid_genome(genome: Dictionary, lineage_id: String) -> bool:
	if genome.get("schema_version") != 1 or genome.get("lineage_id") != lineage_id:
		return false
	if not _valid_id(genome.get("genome_id"), "genome_"):
		return false
	if not _whole(genome.get("generation")) or genome["generation"] < 1:
		return false
	if not genome.get("parts") is Array or not genome.get("appearance") is Dictionary:
		return false
	if not genome.get("parent_genome_id") is String:
		return false
	if not _whole(genome.get("next_part_number")):
		return false
	for part in genome["parts"]:
		if not part is Dictionary or not part.get("type") is String or not part.get("id") is String:
			return false
		if not (part.get("angle") is float or part.get("angle") is int):
			return false
		if not (part.get("scale") is float or part.get("scale") is int):
			return false
	return true


static func timeline(save: Dictionary) -> Dictionary:
	var indexed: Array = []
	var source: Array = save["lineage_history"]
	if source.is_empty():
		source = [{"event": "founded", "generation": 1, "genome_id": save["genome"]["genome_id"]}]
	for position in source.size():
		var event: Dictionary = source[position]
		indexed.append({"index": int(event.get("index", position)), "id": str(event.get("id", event.get("genome_id", ""))), "event": event})
	indexed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["index"] != b["index"]:
			return a["index"] < b["index"]
		return a["id"] < b["id"])
	var nodes: Array = []
	var band := 1
	for item in indexed:
		var event: Dictionary = item["event"]
		nodes.append({"index": item["index"], "id": item["id"], "generation": band, "kind": str(event.get("event", "event")), "detail": str(event.get("cause", event.get("part_type", "")))})
		if event.get("event") == "died":
			band += 1
	return {"nodes": nodes, "generations": band}


static func ascii(tree: Dictionary) -> String:
	var lines := PackedStringArray(["LINEAGE TIMELINE"])
	for node in tree["nodes"]:
		var detail: String = " (" + str(node["detail"]) + ")" if node["detail"] != "" else ""
		lines.append("G%d | #%d %s%s" % [node["generation"], node["index"], node["kind"], detail])
	return "\n".join(lines) + "\n"


static func svg(tree: Dictionary, save: Dictionary) -> String:
	var nodes: Array = tree["nodes"]
	var height := 80 + nodes.size() * 58
	var lines := PackedStringArray([
		'<svg xmlns="http://www.w3.org/2000/svg" width="720" height="%d" viewBox="0 0 720 %d">' % [height, height],
		'<rect width="720" height="%d" fill="#101b2a"/>' % height,
		'<text x="24" y="30" fill="#eff6ff" font-size="18">Lineage %s</text>' % _xml(save["lineage_id"]),
	])
	var previous_band := 0
	for position in nodes.size():
		var node: Dictionary = nodes[position]
		var y := 72 + position * 58
		if node["generation"] != previous_band:
			previous_band = node["generation"]
			lines.append('<rect x="8" y="%d" width="704" height="56" fill="#18334a"/>' % (y - 25))
			lines.append('<text x="24" y="%d" fill="#b5d9e8" font-size="12">Generation %d</text>' % [y - 8, previous_band])
		if position > 0:
			lines.append('<path d="M 105 %d L 105 %d" stroke="#8ad3cd" stroke-width="3"/>' % [y - 58, y])
		lines.append('<g class="event-node" data-index="%d" data-generation="%d">' % [node["index"], node["generation"]])
		lines.append('<circle cx="105" cy="%d" r="8" fill="#8ad3cd"/>' % y)
		lines.append('<text x="130" y="%d" fill="#ffffff" font-size="15">%s</text>' % [y + 5, _xml(node["kind"] + " " + node["detail"])])
		lines.append('</g>')
	lines.append(_silhouette(save["genome"]["parts"], nodes))
	lines.append('</svg>')
	return "\n".join(lines) + "\n"


static func _silhouette(parts: Array, nodes: Array) -> String:
	var lines := PackedStringArray()
	var seen: Dictionary = {}
	for position in nodes.size():
		var band: int = nodes[position]["generation"]
		if seen.has(band):
			continue
		seen[band] = true
		var y := 72 + position * 58
		lines.append('<g class="body-silhouette" data-generation="%d">' % band)
		lines.append('<circle cx="600" cy="%d" r="12" fill="#6a9d9a"/>' % y)
		for part_index in parts.size():
			var part: Dictionary = parts[part_index]
			var offset := 19 + part_index * 8
			lines.append('<rect x="%d" y="%d" width="12" height="4" rx="2" fill="#bed8bd" data-part="%s"/>' % [600 + offset, y - 2, _xml(str(part["type"]))])
		lines.append('</g>')
	return "\n".join(lines)


static func _xml(value: String) -> String:
	return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;").replace("'", "&apos;")
