extends RefCounted
## Loads the spine prototype's data files. Not domain code: it reads files.

const BodyCodec := preload("res://domain/body_codec.gd")
const BodyDescription := preload("res://domain/body_description.gd")

const BODY_NAMES: Array[String] = ["bean", "worm", "fish", "snake", "tadpole", "arch", "large"]


static func read_json(path: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(data is Dictionary, "could not read %s" % path)
	return data


static func rules() -> Dictionary:
	return read_json("res://data/body_rules.json")


static func body(body_name: String) -> RefCounted:
	return BodyCodec.from_dict(read_json("res://data/spine_bodies.json")["bodies"][body_name])
