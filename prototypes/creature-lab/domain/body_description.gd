extends RefCounted
## Body description (PROPOSED, prototypes 0b and Stage 1): the only authority for a creature's body. Skeleton, skin
## and weights are derived from it. Positions and radii are integers in 1/1000 of `reference_length_mm`, so a body can
## grow by changing one number. Body axes: +X right, +Y up, -Z forward; vertebra 0 is the head end.
## Limbs (version 2) are joint chains that start on a vertebra; a mirrored limb also makes its copy across the X = 0
## plane, so a pair is one entry and stays symmetric while it is edited.
## Pure rules: no scene or file access.

const BODY_VERSION := 2

var body_version := BODY_VERSION
var plan := "spine"
var reference_length_mm := 1000
var generator := "skin-1"
## Each: {id: String, p: [x, y, z] ints, r: int}.
var vertebrae: Array = []
## Each: {id: String, attach: vertebra id, mirror: bool, joints: [{id: String, p: [x, y, z] ints, r: int}]}.
## Joint 0 is the shoulder or hip and sits on the attach vertebra; the last joint is the tip.
var limbs: Array = []
## Next id number per kind; ids are never reused.
var next_ids := {"v": 1, "l": 1, "j": 1}
## Top-level keys this version does not know, kept so a load never drops data.
var extra := {}
## Problems met while loading (wrong types, non-integers); the entries are kept.
var load_problems := PackedStringArray()


static func create() -> RefCounted:
	return load("res://domain/body_description.gd").new()


func add_vertebra(p: Vector3i, r: int, at := -1) -> String:
	var id := _next_id("v")
	var entry := {"id": id, "p": [p.x, p.y, p.z], "r": r}
	if at < 0 or at >= vertebrae.size():
		vertebrae.append(entry)
	else:
		vertebrae.insert(at, entry)
	return id


func remove_vertebra(index: int) -> void:
	vertebrae.remove_at(index)


## Adds a limb on vertebra `attach` with joints [[Vector3i, r], ...]; returns its id.
func add_limb(attach: String, joints: Array, mirror := true) -> String:
	var id := _next_id("l")
	var entry := {"id": id, "attach": attach, "mirror": mirror, "joints": []}
	for j in joints:
		var p: Vector3i = j[0]
		entry["joints"].append({"id": _next_id("j"), "p": [p.x, p.y, p.z], "r": int(j[1])})
	limbs.append(entry)
	return id


func vertebra_index(id: String) -> int:
	for i in vertebrae.size():
		if vertebrae[i]["id"] == id:
			return i
	return -1


## Limbs as the skin and skeleton see them: one chain per limb and one more per mirror copy, in order. Each is
## {limb_id: 1.., source: limb id, attach: vertebra index, points: PackedVector3Array (m), radii: PackedFloat32Array (m)}.
func limb_chains() -> Array:
	var out := []
	for limb in limbs:
		var points := PackedVector3Array()
		var radii := PackedFloat32Array()
		for j in limb["joints"]:
			points.append(Vector3(float(j["p"][0]), float(j["p"][1]), float(j["p"][2])) * scale_m())
			radii.append(float(j["r"]) * scale_m())
		var attach := vertebra_index(String(limb["attach"]))
		out.append({"limb_id": out.size() + 1, "source": limb["id"], "attach": attach, "points": points, "radii": radii})
		if limb["mirror"]:
			var mirrored := PackedVector3Array()
			for p in points:
				mirrored.append(Vector3(-p.x, p.y, p.z))
			out.append({"limb_id": out.size() + 1, "source": limb["id"], "attach": attach, "points": mirrored,
					"radii": radii})
	return out


## Bones: one per vertebra, then one per joint of each limb chain.
func bone_count() -> int:
	var n: int = vertebrae.size()
	for c in limb_chains():
		n += (c["points"] as PackedVector3Array).size()
	return n


func max_radius_m() -> float:
	var r := 0.0
	for i in vertebrae.size():
		r = maxf(r, radius_m(i))
	for limb in limbs:
		for j in limb["joints"]:
			r = maxf(r, float(j["r"]) * scale_m())
	return r


func _next_id(kind: String) -> String:
	var n := int(next_ids.get(kind, 1))
	next_ids[kind] = n + 1
	return "%s_%d" % [kind, n]


func scale_m() -> float:
	return reference_length_mm / 1000.0 / 1000.0


## Vertebra position in metres, body space.
func position_m(i: int) -> Vector3:
	var p: Array = vertebrae[i]["p"]
	return Vector3(float(p[0]), float(p[1]), float(p[2])) * scale_m()


func radius_m(i: int) -> float:
	return float(vertebrae[i]["r"]) * scale_m()


## Axis-aligned box around the body surface (each vertebra's sphere), in metres.
func bounds_m() -> AABB:
	var box := AABB(position_m(0), Vector3.ZERO)
	for i in vertebrae.size():
		var r := radius_m(i)
		box = box.merge(AABB(position_m(i) - Vector3.ONE * r, Vector3.ONE * 2.0 * r))
	for c in limb_chains():
		for k in (c["points"] as PackedVector3Array).size():
			var r: float = c["radii"][k]
			box = box.merge(AABB(c["points"][k] - Vector3.ONE * r, Vector3.ONE * 2.0 * r))
	return box


## Grid cell size for a quality level: the body's longest extent over `divisions`.
func cell_size_m(divisions: int) -> float:
	return bounds_m().get_longest_axis_size() / float(divisions)


func to_dict() -> Dictionary:
	var verts := []
	for v in vertebrae:
		verts.append({"id": v["id"], "p": (v["p"] as Array).duplicate(), "r": v["r"]})
	var d := {"body_version": body_version, "plan": plan, "reference_length_mm": reference_length_mm,
			"generator": generator, "vertebrae": verts, "limbs": limbs.duplicate(true), "next": next_ids.duplicate()}
	for k in extra:
		d[k] = extra[k]
	return d


## Every limit broken, as readable reasons. Empty means valid. `rules` is the body_rules table.
func validate(rules: Dictionary) -> PackedStringArray:
	var out := PackedStringArray(load_problems)
	var n := vertebrae.size()
	if body_version > BODY_VERSION:
		out.append("body_version %d is newer than this game knows (%d)" % [body_version, BODY_VERSION])
	if plan != "spine":
		out.append("plan \"%s\" is not supported (only \"spine\")" % plan)
	if reference_length_mm < int(rules["reference_length_mm_min"]) or reference_length_mm > int(rules["reference_length_mm_max"]):
		out.append("reference length %d mm is outside %d..%d" % [reference_length_mm,
				int(rules["reference_length_mm_min"]), int(rules["reference_length_mm_max"])])
	if n < int(rules["vertebra_count_min"]) or n > int(rules["vertebra_count_max"]):
		out.append("%d vertebrae; a spine needs %d..%d" % [n, int(rules["vertebra_count_min"]),
				int(rules["vertebra_count_max"])])
	var seen := {}
	var limit := int(rules["position_limit"])
	for i in n:
		var v: Dictionary = vertebrae[i]
		var id := String(v["id"])
		if seen.has(id):
			out.append("vertebra id %s is used twice" % id)
		seen[id] = true
		if not id.begins_with("v_") or not id.substr(2).is_valid_int() or int(id.substr(2)) >= int(next_ids["v"]):
			out.append("vertebra id %s is not below the next id counter v_%d" % [id, int(next_ids["v"])])
		for c in 3:
			if absi(int(v["p"][c])) > limit:
				out.append("vertebra %s is outside the body box (+-%d)" % [id, limit])
				break
		if int(v["r"]) < int(rules["radius_min"]) or int(v["r"]) > int(rules["radius_max"]):
			out.append("vertebra %s radius %d is outside %d..%d" % [id, int(v["r"]), int(rules["radius_min"]),
					int(rules["radius_max"])])
	if not out.is_empty() or n < 2:
		return out
	var cell := cell_size_m(int(rules["preview_divisions"]))
	for i in n:
		if radius_m(i) < float(rules["min_radius_preview_cells"]) * cell:
			out.append("vertebra %s is too thin for the skin grid (radius %.3f m, minimum %.3f m)"
					% [vertebrae[i]["id"], radius_m(i), float(rules["min_radius_preview_cells"]) * cell])
	for i in n - 1:
		var a := float(vertebrae[i]["r"])
		var b := float(vertebrae[i + 1]["r"])
		if maxf(a, b) > float(rules["neighbour_radius_ratio_max"]) * minf(a, b):
			out.append("vertebrae %s and %s differ in thickness by more than %.0f:1"
					% [vertebrae[i]["id"], vertebrae[i + 1]["id"], float(rules["neighbour_radius_ratio_max"])])
		if position_m(i).is_equal_approx(position_m(i + 1)):
			out.append("vertebrae %s and %s are at the same point" % [vertebrae[i]["id"], vertebrae[i + 1]["id"]])
	for i in range(1, n - 1):
		var d0 := position_m(i - 1) - position_m(i)
		var d1 := position_m(i + 1) - position_m(i)
		if d0.length() > 0.0 and d1.length() > 0.0 and rad_to_deg(d0.angle_to(d1)) < float(rules["fold_angle_min_deg"]):
			out.append("the spine folds back at %s (angle %.0f deg, minimum %.0f)"
					% [vertebrae[i]["id"], rad_to_deg(d0.angle_to(d1)), float(rules["fold_angle_min_deg"])])
	# The spine must not fold back onto itself: two segments that are close in space but far apart along the spine
	# would merge into one lump. "Far along the spine" means more than twice their combined radii of spine between.
	for i in n - 1:
		var along := 0.0
		for j in range(i + 2, n - 1):
			along += position_m(j - 1).distance_to(position_m(j))
			var reach := maxf(radius_m(i), radius_m(i + 1)) + maxf(radius_m(j), radius_m(j + 1))
			if along <= 2.0 * reach:
				continue
			var gap := _segment_distance(position_m(i), position_m(i + 1), position_m(j), position_m(j + 1))
			if gap < reach:
				out.append("the spine touches itself between %s and %s" % [vertebrae[i]["id"], vertebrae[j]["id"]])
	_validate_limbs(rules, cell, out)
	return out


func _validate_limbs(rules: Dictionary, cell: float, out: PackedStringArray) -> void:
	var limit := int(rules["position_limit"])
	if limbs.size() > int(rules["limb_count_max"]):
		out.append("%d limbs; at most %d" % [limbs.size(), int(rules["limb_count_max"])])
	if bone_count() > int(rules["bone_count_max"]):
		out.append("%d bones; at most %d" % [bone_count(), int(rules["bone_count_max"])])
	var seen := {}
	for limb in limbs:
		var id := String(limb["id"])
		for key in [id] + (limb["joints"] as Array).map(func(j): return String(j["id"])):
			if seen.has(key):
				out.append("id %s is used twice" % key)
			seen[key] = true
			var kind: String = key.get_slice("_", 0)
			if not key.get_slice("_", 1).is_valid_int() or int(key.get_slice("_", 1)) >= int(next_ids.get(kind, 1)):
				out.append("id %s is not below the next id counter" % key)
		var attach := vertebra_index(String(limb["attach"]))
		if attach < 0:
			out.append("limb %s attaches to %s, which is not a vertebra" % [id, String(limb["attach"])])
			continue
		var joints: Array = limb["joints"]
		if joints.size() < int(rules["limb_joints_min"]) or joints.size() > int(rules["limb_joints_max"]):
			out.append("limb %s has %d joints; a limb needs %d..%d" % [id, joints.size(), int(rules["limb_joints_min"]),
					int(rules["limb_joints_max"])])
			continue
		var pts: Array[Vector3] = []
		var rs: Array[float] = []
		var bad := false
		for j in joints:
			for c in 3:
				if absi(int(j["p"][c])) > limit:
					out.append("joint %s is outside the body box (+-%d)" % [j["id"], limit])
					bad = true
					break
			if int(j["r"]) < int(rules["radius_min"]) or int(j["r"]) > int(rules["radius_max"]):
				out.append("joint %s radius %d is outside %d..%d" % [j["id"], int(j["r"]), int(rules["radius_min"]),
						int(rules["radius_max"])])
				bad = true
			pts.append(Vector3(float(j["p"][0]), float(j["p"][1]), float(j["p"][2])) * scale_m())
			rs.append(float(j["r"]) * scale_m())
		if bad:
			continue
		if pts[0].distance_to(position_m(attach)) > radius_m(attach) + rs[0]:
			out.append("limb %s starts away from its vertebra %s (joint 0 must touch it)" % [id, String(limb["attach"])])
		for k in pts.size():
			if rs[k] < float(rules["min_radius_preview_cells"]) * cell:
				out.append("joint %s is too thin for the skin grid (radius %.3f m, minimum %.3f m)"
						% [joints[k]["id"], rs[k], float(rules["min_radius_preview_cells"]) * cell])
		for k in pts.size() - 1:
			if maxf(rs[k], rs[k + 1]) > float(rules["neighbour_radius_ratio_max"]) * minf(rs[k], rs[k + 1]):
				out.append("joints %s and %s differ in thickness by more than %.0f:1" % [joints[k]["id"],
						joints[k + 1]["id"], float(rules["neighbour_radius_ratio_max"])])
			if pts[k].is_equal_approx(pts[k + 1]):
				out.append("joints %s and %s are at the same point" % [joints[k]["id"], joints[k + 1]["id"]])
		for k in range(1, pts.size() - 1):
			var d0 := pts[k - 1] - pts[k]
			var d1 := pts[k + 1] - pts[k]
			if d0.length() > 0.0 and d1.length() > 0.0 and rad_to_deg(d0.angle_to(d1)) < float(rules["fold_angle_min_deg"]):
				out.append("limb %s folds back at %s (angle %.0f deg, minimum %.0f)" % [id, joints[k]["id"],
						rad_to_deg(d0.angle_to(d1)), float(rules["fold_angle_min_deg"])])
		# A mirrored pair joins only through the body: past joint 0, each joint stays at least its radius off the
		# middle plane on one side, so the two copies never touch.
		if limb["mirror"]:
			var side := signf(pts[0].x)
			if side == 0.0:
				out.append("mirrored limb %s starts on the middle plane; move it to one side" % id)
			else:
				for k in range(1, pts.size()):
					if pts[k].x * side < rs[k]:
						out.append("mirrored limb %s reaches its own copy at %s" % [id, joints[k]["id"]])
						break


static func _segment_distance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var pts := Geometry3D.get_closest_points_between_segments(p1, q1, p2, q2)
	return (pts[0] as Vector3).distance_to(pts[1])
