extends RefCounted
## Turns a body description into the gait body the planner uses (PROPOSED): which limbs are legs, where their hips
## are, their two-bone lengths and which way their knees bend. Pure rules: no scene or file access.
##
## A limb is a leg when it has a knee (3 or more joints), its tip hangs below its first joint by more than a quarter of
## the limb's length, and the tip reaches down to within a quarter of its length of the lowest tip (so a biped's
## hanging arms are not legs). Two-joint stubs need a one-bone solver, which is not built. The IK treats a leg
## as two bones: hip (joint 0) to knee (joint 1), and knee to the tip as one rigid piece, so a toe or extra joint keeps
## its rest shape. The gait origin is the centre of the hips; `centre` is that point in description space.


## Returns {body: Dictionary in data/test_bodies.json form, centre: Vector3, legs: Array of limb_chains() indices}.
## body["legs"] is empty when the creature has no legs.
static func from_description(desc: RefCounted) -> Dictionary:
	var chains: Array = desc.limb_chains()
	var lowest := INF
	for c in chains:
		var pts: PackedVector3Array = c["points"]
		lowest = minf(lowest, pts[pts.size() - 1].y)
	var legs := []
	for c in chains.size():
		var pts: PackedVector3Array = chains[c]["points"]
		var length := 0.0
		for k in pts.size() - 1:
			length += pts[k].distance_to(pts[k + 1])
		var tip_y := pts[pts.size() - 1].y
		if pts.size() >= 3 and pts[0].y - tip_y > 0.25 * length and tip_y - lowest < 0.25 * length:
			legs.append(c)
	var centre := Vector3.ZERO
	for c in legs:
		centre += (chains[c]["points"] as PackedVector3Array)[0]
	if not legs.is_empty():
		centre /= legs.size()
	var body_legs := []
	for c in legs:
		var pts: PackedVector3Array = chains[c]["points"]
		var hip := pts[0] - centre
		var knee := pts[1]
		var tip := pts[pts.size() - 1]
		body_legs.append({
			"side": "L" if pts[0].x < 0.0 else "R",
			"hip": [hip.x, hip.y, hip.z],
			"upper": pts[0].distance_to(knee),
			"lower": knee.distance_to(tip),
			"knee": knee_direction(pts[0], knee, tip),
		})
	var box: AABB = desc.bounds_m()
	return {"body": {"body_length": box.size.z, "body_width": box.size.x, "legs": body_legs}, "centre": centre,
			"legs": legs}


## Which way a knee bends at rest, in the planner's words: "out" when it sits further out to the side than forward or
## back of the hip-tip line, else "forward" (towards -Z) or "back".
static func knee_direction(hip: Vector3, knee: Vector3, tip: Vector3) -> String:
	var axis := (tip - hip).normalized()
	var off := (knee - hip) - axis * (knee - hip).dot(axis)
	if absf(off.x) > absf(off.z) and off.x * signf(hip.x) > 0.0:
		return "out"
	return "forward" if off.z < 0.0 else "back"
