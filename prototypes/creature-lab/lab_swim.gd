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
		_add_fin_pair(tail, 3)
		return tail
	if body_name == "swim_fins":
		var fins = LabSpine.body("tadpole")
		_add_fin_pair(fins, 2)
		return fins
	return null


static func _add_fin_pair(desc: RefCounted, vertebra: int) -> void:
	var attach: String = desc.vertebrae[vertebra]["id"]
	var p: Vector3 = desc.position_m(vertebra)
	var s: float = desc.scale_m()
	var base := Vector3i(roundi(p.x / s), roundi(p.y / s), roundi(p.z / s))
	var limb: String = desc.add_limb(attach, [[base + Vector3i(75, 0, 0), 45],
			[base + Vector3i(220, 0, 25), 30]], true)
	desc.add_part("flipper", {"host": limb + ":end", "u": 1000, "ring": 250, "mirror": true})
