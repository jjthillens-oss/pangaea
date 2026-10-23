extends RefCounted
## Two PROPOSED aquatic descriptions. The controller reads their geometry and parts, not these names.

const LabSpine := preload("res://lab_spine.gd")


static func names() -> Array[String]:
	return ["swim_tail", "swim_fins"]


static func body(body_name: String) -> RefCounted:
	if body_name == "swim_tail":
		var tail = LabSpine.body("fish")
		tail.add_part("tail_fluke", {"host": "spine", "u": 1000, "ring": 500, "elev": 0})
		tail.add_part("fin", {"host": "spine", "u": 400, "ring": 0})
		return tail
	if body_name == "swim_fins":
		var fins = LabSpine.body("tadpole")
		var attach: String = fins.vertebrae[2]["id"]
		var p: Vector3 = fins.position_m(2)
		var s: float = fins.scale_m()
		var base := Vector3i(roundi(p.x / s), roundi(p.y / s), roundi(p.z / s))
		var limb: String = fins.add_limb(attach, [[base + Vector3i(75, 0, 0), 45],
				[base + Vector3i(220, 0, 25), 30]], true)
		fins.add_part("flipper", {"host": limb + ":end", "u": 1000, "ring": 250, "mirror": true})
		return fins
	return null
