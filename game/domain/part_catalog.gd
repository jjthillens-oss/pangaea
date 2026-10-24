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
## Part levels (S4.5, PROPOSED): 1..max_level. Index 0 is level 1, which is always the part as
## catalogued (shares 1.0, no upgrade cost), so a catalog without "part_levels" has level 1 only.
var max_level: int = 1
var level_effect_share := PackedFloat64Array([1.0])
var level_cost_share := PackedFloat64Array([1.0])
var level_upgrade_cost_share := PackedFloat64Array([0.0])
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
	var levels: Dictionary = data.get("part_levels", {})
	if not levels.is_empty():
		catalog.max_level = int(levels.get("max", 1))
		catalog.level_effect_share = PackedFloat64Array(levels.get("effect_share", [1.0]))
		catalog.level_cost_share = PackedFloat64Array(levels.get("cost_share", [1.0]))
		catalog.level_upgrade_cost_share = PackedFloat64Array(levels.get("upgrade_cost_share", [0.0]))
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


## Whether `type_id` can be upgraded at all: the catalog has levels and the part has a benefit
## (an effect other than mass and upkeep), so a level would change something.
func can_level(type_id: String) -> bool:
	if max_level <= 1 or not parts.has(type_id):
		return false
	for stat in parts[type_id]["effects"]:
		if stat != "mass" and stat != "upkeep":
			return true
	return false


## The share of a part's benefits at `level` (clamped to 1..max_level).
func effect_share(level: int) -> float:
	return level_effect_share[_level_index(level, level_effect_share)]


## The share of a part's mass and upkeep at `level`.
func cost_share(level: int) -> float:
	return level_cost_share[_level_index(level, level_cost_share)]


## Points to raise a `type_id` part from `from_level` to the next level.
func upgrade_cost(type_id: String, from_level: int) -> int:
	return roundi(cost_of(type_id) * level_upgrade_cost_share[_level_index(from_level + 1, level_upgrade_cost_share)])


## Everything a `type_id` part at `level` has cost: the part and each upgrade.
func value_of(type_id: String, level: int) -> int:
	var total := cost_of(type_id)
	for l in range(1, clampi(level, 1, max_level)):
		total += upgrade_cost(type_id, l)
	return total


func _level_index(level: int, shares: PackedFloat64Array) -> int:
	return clampi(level, 1, mini(max_level, shares.size())) - 1
