class_name PartCatalog
extends RefCounted
## Data-driven list of body parts and their tuning (game/data/part_catalog.json).
## Tuning lives in data, not scattered constants (Bible section 12).

const DEFAULT_PATH := "res://game/data/part_catalog.json"

var schema_version: int = 0
var max_parts: int = 0
var min_scale: float = 1.0
var max_scale: float = 1.0
var required_categories: PackedStringArray = []
## Share of a removed part's cost returned when an edit is committed.
var refund_rate: float = 1.0
## Each further copy of a part adds this share of the previous copy's effect.
var diminishing_factor: float = 1.0
var base_body: Dictionary = {}
var caps: Dictionary = {}
## name -> [{"type", "angle", "scale"}]: the bodies a new lineage can start with.
var starting_bodies: Dictionary = {}
## part type id -> {"category", "max_count", "cost", "editor", "effects": {stat: float}, "diet", "arc_deg"}
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
	catalog.refund_rate = float(data.get("refund_rate", 1.0))
	catalog.diminishing_factor = float(data.get("diminishing_factor", 1.0))
	catalog.base_body = Dictionary(data.get("base_body", {})).duplicate()
	catalog.caps = Dictionary(data.get("caps", {})).duplicate()
	var raw_bodies: Dictionary = data.get("starting_bodies", {})
	for body_name in raw_bodies:
		var body: Array[Dictionary] = []
		for part in raw_bodies[body_name]:
			body.append({"type": str(part.get("type", "")), "angle": float(part.get("angle", 0.0)), "scale": float(part.get("scale", 1.0))})
		catalog.starting_bodies[body_name] = body
	var raw_parts: Dictionary = data.get("parts", {})
	for type_id in raw_parts:
		var def: Dictionary = raw_parts[type_id]
		var effects := {}
		var raw_effects: Dictionary = def.get("effects", {})
		for stat in raw_effects:
			effects[stat] = float(raw_effects[stat])
		catalog.parts[type_id] = {
			"category": str(def.get("category", "")),
			"max_count": int(def.get("max_count", 0)),
			"cost": int(def.get("cost", 0)),
			"editor": bool(def.get("editor", false)),
			"effects": effects,
			"diet": str(def.get("diet", "")),
			"arc_deg": float(def.get("arc_deg", 0.0)),
		}
	return catalog


func has_part(type_id: String) -> bool:
	return parts.has(type_id)


func category_of(type_id: String) -> String:
	return parts[type_id]["category"] if parts.has(type_id) else ""


func max_count_of(type_id: String) -> int:
	return parts[type_id]["max_count"] if parts.has(type_id) else 0


func cost_of(type_id: String) -> int:
	return parts[type_id]["cost"] if parts.has(type_id) else 0


func in_editor(type_id: String) -> bool:
	return parts.has(type_id) and parts[type_id]["editor"]


func base(stat: String, fallback: float = 0.0) -> float:
	return float(base_body.get(stat, fallback))
