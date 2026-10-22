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
## Each part: {"id": String, "type": String, "angle": float (radians, 0 = front), "scale": float}
var parts: Array[Dictionary] = []
var next_part_number: int = 1


static func create(p_lineage_id: String) -> Genome:
	var genome := Genome.new()
	genome.genome_id = StableId.generate("genome")
	genome.lineage_id = p_lineage_id
	return genome


func add_part(type_id: String, angle: float, scale: float = 1.0) -> String:
	var part_id := "part_%d" % next_part_number
	next_part_number += 1
	parts.append({"id": part_id, "type": type_id, "angle": angle, "scale": scale})
	return part_id


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
	var errors := PackedStringArray()
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
		var part_id := str(part.get("id", ""))
		var type_id := str(part.get("type", ""))
		if part_id.is_empty() or seen_ids.has(part_id):
			errors.append("Part id '%s' is missing or repeated." % part_id)
		seen_ids[part_id] = true
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
## reports them; loading never silently drops body parts (Bible section 18).
static func from_dict(data: Dictionary) -> Genome:
	var genome := Genome.new()
	genome.genome_id = str(data.get("genome_id", ""))
	genome.lineage_id = str(data.get("lineage_id", ""))
	genome.parent_genome_id = str(data.get("parent_genome_id", ""))
	genome.generation = JsonValues.whole(data.get("generation"), 0)
	genome.appearance = JsonValues.dict(data.get("appearance"))
	for part in JsonValues.array(data.get("parts")):
		# A malformed entry is kept as an id-less part so validate() reports it; never dropped.
		genome.parts.append(part if part is Dictionary else {"id": "", "type": "", "raw": part})
	genome.next_part_number = JsonValues.whole(data.get("next_part_number"), genome.parts.size() + 1)
	return genome
