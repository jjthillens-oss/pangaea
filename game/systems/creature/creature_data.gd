extends RefCounted
## Loads the creature stage's data files (game/data/creature/) and the part rules from the art team's records
## (assets/records/cpart_<type>.json). Not domain code: it reads files. Replaces the creature lab's lab_spine.gd and
## lab_data.gd; the lab's test-only bodies live under tests/fixtures/creature/.

const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const GaitTable := preload("res://game/domain/creature/gait_table.gd")

const DATA_DIR := "res://game/data/creature"
const RECORDS_DIR := "res://assets/records"
## The starter bodies (the lab's Stage 1 matrix), in data/creature/starter_bodies.json; names get a "s1_" prefix in
## body(), as in the lab, so a body name reads the same in both projects.
const STARTER_NAMES: Array[String] = ["snake", "quadruped", "biped", "hexapod", "twelve_limbs", "giant_limb", "tiny",
		"max_vertebrae", "thin", "asymmetric"]
const STARTER_PREFIX := "s1_"


static func read_json(path: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(data is Dictionary, "could not read %s" % path)
	return data


## Body limits (PROPOSED), for domain/creature/body_description.gd validate().
static func rules() -> Dictionary:
	return read_json(DATA_DIR + "/body_rules.json")


## Editor prices (PROPOSED), for domain/creature/creature_editor_session.gd.
static func editor_costs() -> Dictionary:
	return read_json(DATA_DIR + "/editor_costs.json")


## The gait bands in Froude units (PROPOSED), as a domain/creature/gait_table.gd instance.
static func gait_table() -> RefCounted:
	return GaitTable.from_dict(read_json(DATA_DIR + "/gait_table.json"))


## The starter body names, with their prefix: "s1_quadruped", ...
static func starter_bodies() -> Array[String]:
	var out: Array[String] = []
	for n in STARTER_NAMES:
		out.append(STARTER_PREFIX + n)
	return out


## A fresh description of a starter body, by its name with or without the prefix.
static func body(body_name: String) -> RefCounted:
	var key := body_name.trim_prefix(STARTER_PREFIX)
	var bodies: Dictionary = read_json(DATA_DIR + "/starter_bodies.json")["bodies"]
	assert(bodies.has(key), "no starter body %s" % body_name)
	return BodyCodec.from_dict(bodies[key])


## Part rules from the art team's records: type -> part_rules.
static func part_rules() -> Dictionary:
	var out := {}
	var files := DirAccess.get_files_at(RECORDS_DIR)
	files.sort()
	for file in files:
		if file.begins_with("cpart_") and file.ends_with(".json"):
			var record: Dictionary = read_json(RECORDS_DIR + "/" + file)
			if record.has("part_rules"):
				out[record["part_rules"]["type"]] = record["part_rules"]
	return out


## Part type -> orientation rule, for domain/creature/anchor_resolver.gd.
static func part_orientations(rules_by_type: Dictionary = {}) -> Dictionary:
	var source := rules_by_type if not rules_by_type.is_empty() else part_rules()
	var out := {}
	for type in source:
		out[type] = source[type]["orientation"]
	return out
