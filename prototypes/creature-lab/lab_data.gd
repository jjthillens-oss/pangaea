extends RefCounted
## Loads the Gait Lab data files and builds bodies. Not domain code: it reads files.

const GaitTable := preload("res://domain/gait_table.gd")
const BodyMechanics := preload("res://domain/body_mechanics.gd")
const GaitPlanner := preload("res://domain/gait_planner.gd")

const BODY_NAMES: Array[String] = ["quad_short", "quad_long", "hexapod"]


static func read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	assert(data is Dictionary, "could not read %s" % path)
	return data


static func table() -> RefCounted:
	return GaitTable.from_dict(read_json("res://data/gait_table.json"))


static func body(body_name: String, gait_table: RefCounted = null) -> RefCounted:
	var bodies: Dictionary = read_json("res://data/test_bodies.json")["bodies"]
	return BodyMechanics.create(body_name, bodies[body_name], gait_table if gait_table else table())


static func planner(body_name: String, start_position := Vector3.ZERO, start_yaw := 0.0) -> RefCounted:
	return GaitPlanner.create(body(body_name), start_position, start_yaw)
