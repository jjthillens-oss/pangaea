extends RefCounted
## Loads the spine and Stage 1 prototypes' data files. Not domain code: it reads files.

const BodyCodec := preload("res://domain/body_codec.gd")
const BodyDescription := preload("res://domain/body_description.gd")

const BODY_NAMES: Array[String] = ["bean", "worm", "fish", "snake", "tadpole", "arch", "large"]
## The Stage 1 test matrix (bodies with limbs), in data/stage1_bodies.json; names get a "s1_" prefix in body().
const STAGE1_NAMES: Array[String] = ["snake", "quadruped", "biped", "hexapod", "twelve_limbs", "giant_limb", "tiny",
		"max_vertebrae", "thin", "asymmetric"]


static func read_json(path: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(data is Dictionary, "could not read %s" % path)
	return data


static func rules() -> Dictionary:
	return read_json("res://data/body_rules.json")


static func body(body_name: String) -> RefCounted:
	if body_name.begins_with("s1_"):
		return BodyCodec.from_dict(read_json("res://data/stage1_bodies.json")["bodies"][body_name.substr(3)])
	return BodyCodec.from_dict(read_json("res://data/spine_bodies.json")["bodies"][body_name])


static func stage1_names() -> Array[String]:
	var out: Array[String] = []
	for n in STAGE1_NAMES:
		out.append("s1_" + n)
	return out
