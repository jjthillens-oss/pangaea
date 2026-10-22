class_name PartCatalog
extends RefCounted
## Data-driven list of body parts a genome may use (game/data/part_catalog.json).
## Tuning lives in data, not scattered constants (Bible section 12).

const DEFAULT_PATH := "res://game/data/part_catalog.json"

var schema_version: int = 0
var max_parts: int = 0
var min_scale: float = 1.0
var max_scale: float = 1.0
var required_categories: PackedStringArray = []
## part type id -> {"category": String, "max_count": int}
var parts: Dictionary = {}


static func load_from(path: String = DEFAULT_PATH) -> PartCatalog:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("PartCatalog: cannot read %s" % path)
		return null
	return from_dict(JSON.parse_string(text))


static func from_dict(data: Variant) -> PartCatalog:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var catalog := PartCatalog.new()
	catalog.schema_version = int(data.get("schema_version", 0))
	var limits: Dictionary = data.get("limits", {})
	catalog.max_parts = int(limits.get("max_parts", 0))
	catalog.min_scale = float(limits.get("min_scale", 1.0))
	catalog.max_scale = float(limits.get("max_scale", 1.0))
	catalog.required_categories = PackedStringArray(data.get("required_categories", []))
	var raw_parts: Dictionary = data.get("parts", {})
	for type_id in raw_parts:
		var def: Dictionary = raw_parts[type_id]
		catalog.parts[type_id] = {
			"category": str(def.get("category", "")),
			"max_count": int(def.get("max_count", 0)),
		}
	return catalog


func has_part(type_id: String) -> bool:
	return parts.has(type_id)


func category_of(type_id: String) -> String:
	return parts[type_id]["category"] if parts.has(type_id) else ""


func max_count_of(type_id: String) -> int:
	return parts[type_id]["max_count"] if parts.has(type_id) else 0
