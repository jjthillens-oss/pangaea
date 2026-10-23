class_name SaveMigrations
extends RefCounted
## Every approved save schema step, oldest first. Each takes the previous version's data and
## returns the next version's. Covered by tests/test_persistence.gd with real fixtures. A step never
## changes once it ships: it holds its own values, not the current defaults.


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


## v3 (S2, plan E): exact, because every v2 run is at size 1 and the home block sits at the origin.
## Size 1 with an empty meter; the checkpoint at the home spawn (0, 9) facing -1.5708, in absolute
## am; the first generator; no spawn of its own (the checkpoint); a fresh energy and health. The
## discoveries (always [] in v2) and player.position (absolute am since S1) stay as they are. A
## player that is not an object is left as it is, so the load reports it instead of hiding it.
static func v2_to_v3(data: Dictionary) -> Dictionary:
	data["growth"] = {"size": 1, "meter": 0.0}
	data["checkpoint"] = {"x_am": 0.0, "y_am": 9.0, "heading": -1.5708, "size": 1}
	data["spawn"] = null
	data["gen_version"] = 1
	var player = data.get("player")
	if player is Dictionary:
		player["energy"] = null
		player["health"] = null
	data["schema_version"] = 3
	return data
