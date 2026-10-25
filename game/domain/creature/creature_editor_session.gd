extends RefCounted
## One visit to the creature editor (PROPOSED). Same contract as the cell stage's EditorSession
## (game/domain/editor_session.gd), so one editor shell can host both: edits apply to a working copy of the body
## description; every op returns {ok, reason} and a refused op changes nothing; snapshot undo and redo; preview() gives
## the stats before and after and the cost; commit() validates, checks the cost and only then returns the new body.
##
## An op is refused when it would add a validation problem the body did not already have (body rules and part rules),
## so a drag stops at the last valid shape. A drag is one gesture: begin_gesture() ... end_gesture() makes all the
## moves in between one undo step.
##
## Cost (PROPOSED numbers, data/editor_costs.json): what this session adds minus refund_rate x what it removes, per
## vertebra, limb joint and part. A mirrored limb's joints and a mirrored part's twin count twice. Moving, resizing,
## turning and the head shape dials are free. Lineage (ids, generation) belongs to the caller, as the body description has none.
## Pure rules: no scene, file access or randomness.

const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const BodyField := preload("res://game/domain/creature/body_field.gd")
const GaitBody := preload("res://game/domain/creature/gait_body.gd")
const HeadShape := preload("res://game/domain/creature/head_shape.gd")

## Water, for a mass estimate from the capsule volumes.
const DENSITY_KG_M3 := 1000.0

var rules: Dictionary
var part_rules: Dictionary
var costs: Dictionary
var original: RefCounted
var working: RefCounted
var available_points := 0
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _in_gesture := false
var _gesture_marked := false


## `body_rules` is data/body_rules.json, `p_part_rules` type -> the art record's part_rules, `p_costs`
## data/editor_costs.json.
func _init(body: RefCounted, body_rules: Dictionary, p_part_rules: Dictionary, p_costs: Dictionary, points: int) -> void:
	rules = body_rules
	part_rules = p_part_rules
	costs = p_costs
	original = body
	working = BodyCodec.from_dict(body.to_dict())
	available_points = points


static func _ok(extra: Dictionary = {}) -> Dictionary:
	var r := {"ok": true, "reason": ""}
	r.merge(extra)
	return r


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


func errors_of(desc: RefCounted) -> PackedStringArray:
	var out: PackedStringArray = desc.validate(rules)
	out.append_array(desc.validate_parts(rules, part_rules))
	return out


## Applies `change` (a Callable taking the working body) and keeps it only if it adds no new problem.
func _apply(change: Callable, extra: Dictionary = {}) -> Dictionary:
	var before: Dictionary = working.to_dict()
	var known := errors_of(working)
	var result = change.call(working)
	if result is String and result != "":
		working = BodyCodec.from_dict(before)
		return _no(result)
	for e in errors_of(working):
		if not known.has(e):
			working = BodyCodec.from_dict(before)
			return _no(e)
	if not _in_gesture or not _gesture_marked:
		_undo.append(before)
		_redo.clear()
		_gesture_marked = _in_gesture
	if result is Dictionary:
		extra.merge(result)
	return _ok(extra)


## Everything until end_gesture() is one undo step (a drag).
func begin_gesture() -> void:
	_in_gesture = true
	_gesture_marked = false


func end_gesture() -> void:
	_in_gesture = false
	_gesture_marked = false


# Spine -----------------------------------------------------------------------------------------------------------


func _vertebra(desc: RefCounted, id: String) -> Dictionary:
	var i: int = desc.vertebra_index(id)
	return desc.vertebrae[i] if i >= 0 else {}


## Moves a vertebra; the limbs on it move with it, so their shoulders stay on the spine.
func move_vertebra(id: String, p: Vector3i) -> Dictionary:
	return _apply(func(d):
		var v := _vertebra(d, id)
		if v.is_empty():
			return "no such vertebra"
		var delta := p - _vec(v["p"])
		v["p"] = [p.x, p.y, p.z]
		for limb in d.limbs:
			if limb["attach"] == id:
				for j in limb["joints"]:
					j["p"] = _arr(_vec(j["p"]) + delta)
		return "")


func set_vertebra_radius(id: String, r: int) -> Dictionary:
	return _apply(func(d):
		var v := _vertebra(d, id)
		if v.is_empty():
			return "no such vertebra"
		v["r"] = r
		return "")


## Inserts a vertebra at index `at` (0..count): between two vertebrae it goes halfway, with their mean radius; at an
## end it extends the spine by the end segment's length.
func insert_vertebra(at: int) -> Dictionary:
	return _apply(func(d):
		var n: int = d.vertebrae.size()
		if at < 0 or at > n or n < 2:
			return "bad position"
		var p: Vector3i
		var r: int
		if at == 0:
			p = 2 * _vec(d.vertebrae[0]["p"]) - _vec(d.vertebrae[1]["p"])
			r = int(d.vertebrae[0]["r"])
		elif at == n:
			p = 2 * _vec(d.vertebrae[n - 1]["p"]) - _vec(d.vertebrae[n - 2]["p"])
			r = int(d.vertebrae[n - 1]["r"])
		else:
			p = (_vec(d.vertebrae[at - 1]["p"]) + _vec(d.vertebrae[at]["p"])) / 2
			r = (int(d.vertebrae[at - 1]["r"]) + int(d.vertebrae[at]["r"])) / 2
		return {"vertebra_id": d.add_vertebra(p, r, at)})


## Removes a vertebra, with the limbs on it and the parts on those limbs (listed in the result).
func remove_vertebra(id: String) -> Dictionary:
	return _apply(func(d):
		var i: int = d.vertebra_index(id)
		if i < 0:
			return "no such vertebra"
		var removed := {"limbs": [], "parts": []}
		for limb in d.limbs.duplicate():
			if limb["attach"] == id:
				removed["parts"].append_array(_remove_limb(d, String(limb["id"])))
				removed["limbs"].append(limb["id"])
		d.remove_vertebra(i)
		return {"removed": removed})


# Limbs -----------------------------------------------------------------------------------------------------------


## Adds a limb on vertebra `attach` with joints [[Vector3i, r], ...].
func add_limb(attach: String, joints: Array, mirror := true) -> Dictionary:
	return _apply(func(d):
		if d.vertebra_index(attach) < 0:
			return "no such vertebra"
		return {"limb_id": d.add_limb(attach, joints, mirror)})


## Removes a limb and the parts on it (listed in the result).
func remove_limb(limb_id: String) -> Dictionary:
	return _apply(func(d):
		if d.limb_index(limb_id) < 0:
			return "no such limb"
		return {"removed": {"limbs": [limb_id], "parts": _remove_limb(d, limb_id)}})


static func _remove_limb(d: RefCounted, limb_id: String) -> Array:
	var gone := []
	for p in d.parts.duplicate():
		if String(p["host"]).trim_suffix(":end") == limb_id:
			gone.append(p["id"])
			d.parts.erase(p)
	d.limbs.remove_at(d.limb_index(limb_id))
	return gone


## Moves a joint to `p`; with `carry`, the joints after it move by the same amount, so the rest of the limb keeps its
## shape (dragging a knee brings the foot along).
func move_joint(limb_id: String, joint_id: String, p: Vector3i, carry := true) -> Dictionary:
	return _apply(func(d):
		var k := _joint_index(d, limb_id, joint_id)
		if k < 0:
			return "no such joint"
		var joints: Array = d.limbs[d.limb_index(limb_id)]["joints"]
		var delta := p - _vec(joints[k]["p"])
		for i in range(k, joints.size() if carry else k + 1):
			joints[i]["p"] = _arr(_vec(joints[i]["p"]) + delta)
		return "")


func set_joint_radius(limb_id: String, joint_id: String, r: int) -> Dictionary:
	return _apply(func(d):
		var k := _joint_index(d, limb_id, joint_id)
		if k < 0:
			return "no such joint"
		d.limbs[d.limb_index(limb_id)]["joints"][k]["r"] = r
		return "")


## Adds a joint after joint `after_id`: halfway to the next one, or beyond the tip by the last segment's length.
func insert_joint(limb_id: String, after_id: String) -> Dictionary:
	return _apply(func(d):
		var k := _joint_index(d, limb_id, after_id)
		if k < 0:
			return "no such joint"
		var joints: Array = d.limbs[d.limb_index(limb_id)]["joints"]
		var p: Vector3i
		var r: int
		if k == joints.size() - 1:
			p = 2 * _vec(joints[k]["p"]) - _vec(joints[k - 1]["p"])
			r = int(joints[k]["r"])
		else:
			p = (_vec(joints[k]["p"]) + _vec(joints[k + 1]["p"])) / 2
			r = (int(joints[k]["r"]) + int(joints[k + 1]["r"])) / 2
		var id: String = d._next_id("j")
		joints.insert(k + 1, {"id": id, "p": _arr(p), "r": r})
		return {"joint_id": id})


func remove_joint(limb_id: String, joint_id: String) -> Dictionary:
	return _apply(func(d):
		var k := _joint_index(d, limb_id, joint_id)
		if k < 0:
			return "no such joint"
		if k == 0:
			return "the first joint holds the limb on; remove the limb instead"
		d.limbs[d.limb_index(limb_id)]["joints"].remove_at(k)
		return "")


func set_limb_mirror(limb_id: String, mirror: bool) -> Dictionary:
	return _apply(func(d):
		var i: int = d.limb_index(limb_id)
		if i < 0:
			return "no such limb"
		d.limbs[i]["mirror"] = mirror
		return "")


static func _joint_index(d: RefCounted, limb_id: String, joint_id: String) -> int:
	var i: int = d.limb_index(limb_id)
	if i < 0:
		return -1
	var joints: Array = d.limbs[i]["joints"]
	for k in joints.size():
		if joints[k]["id"] == joint_id:
			return k
	return -1


# Parts -----------------------------------------------------------------------------------------------------------


func _part(d: RefCounted, id: String) -> Dictionary:
	for p in d.parts:
		if p["id"] == id:
			return p
	return {}


## Adds a part at `anchor` (any of host, u, ring, elev, height, turn, tilt, roll, scale, handles, mirror; see
## domain/editor_picking.gd for an anchor from a click). Handles start at the record's defaults.
func add_part(type: String, anchor: Dictionary) -> Dictionary:
	return _apply(func(d):
		if not part_rules.has(type):
			return "%s is not a known part" % type
		var a := anchor.duplicate()
		if not a.has("handles"):
			a["handles"] = (part_rules[type].get("handles", []) as Array).map(func(h): return int(h["default_permille"]))
		return {"part_id": d.add_part(type, a)})


func remove_part(part_id: String) -> Dictionary:
	return _apply(func(d):
		var p := _part(d, part_id)
		if p.is_empty():
			return "no such part"
		d.parts.erase(p)
		return "")


## Moves a part to a new anchor: host, u, ring and elev (the keys given).
func move_part(part_id: String, anchor: Dictionary) -> Dictionary:
	return _set_part(part_id, anchor, ["host", "u", "ring", "elev", "mirror"])


## Turn, tilt, roll (degrees) and height off the skin.
func orient_part(part_id: String, values: Dictionary) -> Dictionary:
	return _set_part(part_id, values, ["turn", "tilt", "roll", "height"])


func scale_part(part_id: String, scale: int) -> Dictionary:
	return _set_part(part_id, {"scale": scale}, ["scale"])


func set_part_handles(part_id: String, handles: Array) -> Dictionary:
	return _set_part(part_id, {"handles": handles}, ["handles"])


func set_part_mirror(part_id: String, mirror: bool) -> Dictionary:
	return _set_part(part_id, {"mirror": mirror}, ["mirror"])


func _set_part(part_id: String, values: Dictionary, allowed: Array) -> Dictionary:
	return _apply(func(d):
		var p := _part(d, part_id)
		if p.is_empty():
			return "no such part"
		for k in values:
			if not allowed.has(k):
				return "%s cannot be set here" % k
			match k:
				"host":
					p[k] = String(values[k])
				"mirror":
					p[k] = bool(values[k])
				"handles":
					if (values[k] as Array).size() != (p["handles"] as Array).size():
						return "wrong number of handles"
					p[k] = (values[k] as Array).map(func(h): return int(h))
				_:
					p[k] = int(values[k])
		return "")


# Head shape ------------------------------------------------------------------------------------------------------


## The working body's head dials (HeadShape.FIELDS -> per mille).
func head_shape() -> Dictionary:
	return HeadShape.of(working.extra)


## key -> [min, max] per mille, from the body rules.
func head_shape_ranges() -> Dictionary:
	return HeadShape.ranges(rules)


## Sets one head dial (snout, width, height, jaw or brow) to `value` per mille. Outside the body rules' range it is
## refused; a drag of a slider is one gesture, so one undo step.
func set_head_shape(key: String, value: int) -> Dictionary:
	return _apply(func(d):
		if not HeadShape.FIELDS.has(key):
			return "%s is not a head dial" % key
		var shape: Dictionary = HeadShape.of(d.extra)
		shape[key] = value
		HeadShape.store(d.extra, shape)
		return "")


# Undo, cost, preview, commit ---------------------------------------------------------------------------------------


func undo() -> bool:
	if _undo.is_empty():
		return false
	_redo.append(working.to_dict())
	working = BodyCodec.from_dict(_undo.pop_back())
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.append(working.to_dict())
	working = BodyCodec.from_dict(_redo.pop_back())
	return true


## id -> [price, count] for everything that costs points.
func _priced(d: RefCounted) -> Dictionary:
	var out := {}
	for v in d.vertebrae:
		out[v["id"]] = [int(costs["vertebra"]), 1]
	for limb in d.limbs:
		for j in limb["joints"]:
			out[j["id"]] = [int(costs["limb_joint"]), 2 if limb["mirror"] else 1]
	for p in d.parts:
		var price := int((costs["part"] as Dictionary).get(p["type"], costs["part_default"]))
		out[p["id"]] = [price, 2 if p["mirror"] else 1]
	return out


func cost() -> int:
	var before := _priced(original)
	var after := _priced(working)
	var added := 0
	var removed := 0
	for id in after:
		var had: int = before[id][1] if before.has(id) else 0
		added += after[id][0] * maxi(0, after[id][1] - had)
	for id in before:
		var has: int = after[id][1] if after.has(id) else 0
		removed += before[id][0] * maxi(0, before[id][1] - has)
	return added - floori(removed * float(costs["refund_rate"]))


## Summary numbers for the editor's before/after panel (PROPOSED; the creature stage's real stats come later).
static func stats(d: RefCounted) -> Dictionary:
	var field = BodyField.from_description(d)
	var volume: float = field.body_volume_m3()
	var legs: Array = GaitBody.from_description(d)["legs"] if not d.limbs.is_empty() else []
	var by_type := {}
	for p in d.parts:
		by_type[p["type"]] = int(by_type.get(p["type"], 0)) + (2 if p["mirror"] else 1)
	return {"length_m": field.total_length, "mass_kg": volume * DENSITY_KG_M3, "bones": d.bone_count(),
			"limbs": d.limb_chains().size(), "legs": legs.size(), "parts": by_type,
			"description_bytes": BodyCodec.encode(d).length()}


## What committing now would produce, without committing.
func preview() -> Dictionary:
	var c := cost()
	return {"phenotype": stats(working), "current": stats(original), "cost": c, "affordable": c <= available_points,
			"errors": errors_of(working)}


## Returns {ok, errors, body (a new description), points_left}. On failure nothing changes.
func commit() -> Dictionary:
	var errors := errors_of(working)
	var c := cost()
	if c > available_points:
		errors.append("Needs %d points, you have %d." % [c, available_points])
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "body": null, "points_left": available_points}
	return {"ok": true, "errors": PackedStringArray(), "body": BodyCodec.from_dict(working.to_dict()),
			"points_left": available_points - c}


static func _vec(a: Array) -> Vector3i:
	return Vector3i(int(a[0]), int(a[1]), int(a[2]))


static func _arr(v: Vector3i) -> Array:
	return [v.x, v.y, v.z]
