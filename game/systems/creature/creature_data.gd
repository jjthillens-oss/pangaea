extends RefCounted
## Loads the creature stage's data files (game/data/creature/), among them the part rules compiled from the art
## team's records (assets/records/cpart_<type>.json) into part_rules.json by tools/make_part_rules.py: the records
## folder is .gdignore'd, so a release pack never carries it. Not domain code: it reads files. Replaces the creature
## lab's lab_spine.gd and lab_data.gd; the lab's test-only bodies live under tests/fixtures/creature/.

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


## The preset creatures' names in their palette order (data/creature/presets.json, written by
## tools/make_creature_presets.py; PROPOSED designs from the owner's playtest of 2026-10-24).
static func preset_names() -> PackedStringArray:
	return PackedStringArray(read_json(DATA_DIR + "/presets.json")["order"])


## A preset creature: {title, blurb, body (the codec's dictionary, skin_color included)}.
static func preset(preset_name: String) -> Dictionary:
	var presets: Dictionary = read_json(DATA_DIR + "/presets.json")["presets"]
	assert(presets.has(preset_name), "no preset %s" % preset_name)
	return presets[preset_name]


## A preset creature's body as a description.
static func preset_body(preset_name: String) -> RefCounted:
	return BodyCodec.from_dict(preset(preset_name)["body"])


## Part rules, type -> part_rules, from data/creature/part_rules.json (the compiled records; the release pack
## carries this file and not the records). tests/test_assets.gd keeps it equal to part_rules_from_records().
static func part_rules() -> Dictionary:
	return read_json(DATA_DIR + "/part_rules.json")["rules"]


## The same rules read straight from the records (the project only, never a pack): what the data file must match.
static func part_rules_from_records() -> Dictionary:
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
