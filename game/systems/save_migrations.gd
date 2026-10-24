class_name SaveMigrations
extends RefCounted
## Every approved save schema step, oldest first. Each takes the previous version's data and
## returns the next version's. Covered by tests/test_persistence.gd with real fixtures.


static func all() -> Dictionary:
	return {
		1: v1_to_v2,
		2: v2_to_v3,
	}


## v2 (M1): adds unspent adaptation points. Runs saved before M1 start with none.
static func v1_to_v2(data: Dictionary) -> Dictionary:
	data["adaptation_points"] = 0
	data["schema_version"] = 2
	return data


## v3 (the creature stage, owner direction of 2026-10-24: follow the Bible, section 18): the creature
## stage's creature lives in the lineage save. A run saved before has not entered the stage: {}.
static func v2_to_v3(data: Dictionary) -> Dictionary:
	data["creature"] = {}
	data["schema_version"] = 3
	return data
