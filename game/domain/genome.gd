class_name Genome
extends RefCounted
## Inheritable body design: parts, placement and appearance. Plain data with validation;
## no scene, UI or file access (Bible sections 12 and 17). Stats come from Phenotype.derive().

const SCHEMA_VERSION := 1

var genome_id: String = ""
var lineage_id: String = ""
var parent_genome_id: String = ""
var generation: int = 1
var appearance: Dictionary = {"hue": 0.45, "pattern": "plain"}
## Each part: {"id": String, "type": String, "angle": float (radians, 0 = front), "scale": float}, plus
## "level": int 2..PartCatalog.max_level once upgraded (S4.5). A part without "level" is level 1, so
## genomes saved before levels load unchanged and level-1 parts are stored exactly as before.
var parts: Array[Dictionary] = []
var next_part_number: int = 1
## Type problems found by from_dict (not saved). validate() reports them.
var load_problems: Array = []


static func create(p_lineage_id: String) -> Genome:
	var genome := Genome.new()
	genome.genome_id = StableId.generate("genome")
	genome.lineage_id = p_lineage_id
	return genome


func add_part(type_id: String, angle: float, scale: float = 1.0, level: int = 1) -> String:
	var part_id := "part_%d" % next_part_number
	next_part_number += 1
	parts.append({"id": part_id, "type": type_id, "angle": angle, "scale": scale})
	if level > 1:
		parts[-1]["level"] = level
	return part_id


## A part's level: 1 when it has none (or it is not a whole number; validate() reports that).
static func level_of(part: Dictionary) -> int:
	var level = part.get("level", 1)
	return int(level) if (level is int or level is float) and is_finite(level) else 1


func remove_part(part_id: String) -> bool:
	for i in parts.size():
		if parts[i]["id"] == part_id:
			parts.remove_at(i)
			return true
	return false


func count_of(type_id: String) -> int:
	var n := 0
	for part in parts:
		if part["type"] == type_id:
			n += 1
	return n


## Returns human-readable problems. An empty array means the genome is valid.
func validate(catalog: PartCatalog) -> PackedStringArray:
	var errors := PackedStringArray(load_problems)
	if not StableId.is_valid(genome_id, "genome"):
		errors.append("Genome has an invalid id '%s'." % genome_id)
	if not StableId.is_valid(lineage_id, "lineage"):
		errors.append("Genome has an invalid lineage id '%s'." % lineage_id)
	if generation < 1:
		errors.append("Generation must be 1 or higher, got %d." % generation)
	if parts.size() > catalog.max_parts:
		errors.append("Too many parts: %d, the limit is %d." % [parts.size(), catalog.max_parts])
	var seen_ids := {}
	var counts := {}
	var categories := {}
	for part in parts:
		var raw_id = part.get("id")
		var part_id := str(raw_id)
		if not (raw_id is String) or part_id.is_empty() or seen_ids.has(part_id):
			errors.append("Part id '%s' is missing, repeated or not text." % part_id)
		seen_ids[part_id] = true
		if _part_number(part_id) >= next_part_number:
			errors.append("Part '%s' is not below the next part number %d; new parts would reuse its id." % [part_id, next_part_number])
		var raw_type = part.get("type")
		var type_id := str(raw_type) if raw_type is String else ""
		if not catalog.has_part(type_id):
			errors.append("Part '%s' has unknown type '%s'." % [part_id, type_id])
			continue
		counts[type_id] = counts.get(type_id, 0) + 1
		categories[catalog.category_of(type_id)] = true
		var angle = part.get("angle")
		if not (angle is float or angle is int) or not is_finite(angle) or absf(angle) > PI + 0.0001:
			errors.append("Part '%s' has an angle outside -PI..PI." % part_id)
		var scale = part.get("scale")
		if not (scale is float or scale is int) or not is_finite(scale) or scale < catalog.min_scale or scale > catalog.max_scale:
			errors.append("Part '%s' has a scale outside %.2f..%.2f." % [part_id, catalog.min_scale, catalog.max_scale])
		if part.has("level"):
			var level = part.get("level")
			var whole: bool = (level is int or level is float) and is_finite(level) and level == floorf(level)
			if not whole or level < 1 or level > catalog.max_level or (level > 1 and not catalog.can_level(type_id)):
				errors.append("Part '%s' has a level outside what its type allows." % part_id)
	for type_id in counts:
		if counts[type_id] > catalog.max_count_of(type_id):
			errors.append("Too many '%s': %d, the limit is %d." % [type_id, counts[type_id], catalog.max_count_of(type_id)])
	for category in catalog.required_categories:
		if not categories.has(category):
			errors.append("The body needs at least one '%s' part." % category)
	return errors


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"genome_id": genome_id,
		"lineage_id": lineage_id,
		"parent_genome_id": parent_genome_id,
		"generation": generation,
		"appearance": appearance.duplicate(true),
		"parts": parts.duplicate(true),
		"next_part_number": next_part_number,
	}


## Copies every field as stored. Unknown or invalid parts are kept so that validate()
## reports them; loading never silently drops body parts (Bible section 18). Fields of the wrong
## type are recorded in load_problems.
static func from_dict(data: Dictionary) -> Genome:
	var genome := Genome.new()
	var problems := genome.load_problems
	genome.genome_id = JsonValues.text(data, "genome_id", problems)
	genome.lineage_id = JsonValues.text(data, "lineage_id", problems)
	genome.parent_genome_id = JsonValues.text(data, "parent_genome_id", problems)
	genome.generation = JsonValues.whole(data, "generation", problems)
	genome.appearance = JsonValues.dict(data, "appearance", problems)
	for part in JsonValues.array(data, "parts", problems):
		if part is Dictionary:
			genome.parts.append(part)
		else:
			# Kept as an id-less part so validate() reports it too; never dropped.
			problems.append("A body part entry is not an object.")
			genome.parts.append({"id": "", "type": "", "raw": part})
	var highest := 0
	for part in genome.parts:
		highest = maxi(highest, _part_number(str(part.get("id"))))
	if data.has("next_part_number"):
		genome.next_part_number = JsonValues.whole(data, "next_part_number", problems)
	if not data.has("next_part_number") or genome.next_part_number <= 0:
		genome.next_part_number = highest + 1
	return genome


## The N of a "part_N" id, or 0 for any other id.
static func _part_number(part_id: String) -> int:
	if not part_id.begins_with("part_"):
		return 0
	var digits := part_id.trim_prefix("part_")
	return digits.to_int() if digits.is_valid_int() else 0
