extends RefCounted
## Canonical text for a body description (PROPOSED). Fixed key order, integers only, no whitespace, so
## encode -> decode -> encode gives the same bytes and the SHA-256 of the text identifies a body.
## Pure rules: no scene or file access.

const BodyDescription := preload("res://domain/body_description.gd")
const KNOWN_KEYS := ["body_version", "plan", "reference_length_mm", "generator", "vertebrae", "limbs", "next"]


static func encode(desc: RefCounted) -> String:
	var parts := PackedStringArray()
	parts.append("\"body_version\":%d" % desc.body_version)
	parts.append("\"plan\":%s" % JSON.stringify(desc.plan))
	parts.append("\"reference_length_mm\":%d" % desc.reference_length_mm)
	parts.append("\"generator\":%s" % JSON.stringify(desc.generator))
	var verts := PackedStringArray()
	for v in desc.vertebrae:
		verts.append("{\"id\":%s,\"p\":[%d,%d,%d],\"r\":%d}" % [JSON.stringify(String(v["id"])), int(v["p"][0]),
				int(v["p"][1]), int(v["p"][2]), int(v["r"])])
	parts.append("\"vertebrae\":[%s]" % ",".join(verts))
	var limbs := PackedStringArray()
	for limb in desc.limbs:
		var joints := PackedStringArray()
		for j in limb["joints"]:
			joints.append("{\"id\":%s,\"p\":[%d,%d,%d],\"r\":%d}" % [JSON.stringify(String(j["id"])), int(j["p"][0]),
					int(j["p"][1]), int(j["p"][2]), int(j["r"])])
		limbs.append("{\"id\":%s,\"attach\":%s,\"mirror\":%s,\"joints\":[%s]}" % [JSON.stringify(String(limb["id"])),
				JSON.stringify(String(limb["attach"])), "true" if limb["mirror"] else "false", ",".join(joints)])
	parts.append("\"limbs\":[%s]" % ",".join(limbs))
	var next_keys: Array = desc.next_ids.keys()
	next_keys.sort()
	var nexts := PackedStringArray()
	for k in next_keys:
		nexts.append("%s:%d" % [JSON.stringify(String(k)), int(desc.next_ids[k])])
	parts.append("\"next\":{%s}" % ",".join(nexts))
	var extra_keys: Array = desc.extra.keys()
	extra_keys.sort()
	for k in extra_keys:
		parts.append("%s:%s" % [JSON.stringify(String(k)), JSON.stringify(desc.extra[k], "", true, true)])
	return "{%s}" % ",".join(parts)


static func hash_text(desc: RefCounted) -> String:
	return encode(desc).sha256_text()


## Builds a description from parsed JSON. Never drops data: wrong types are reported in load_problems and kept as
## close as possible; unknown keys go to `extra`.
static func from_dict(d: Dictionary) -> RefCounted:
	var desc = BodyDescription.create()
	desc.body_version = _int(d.get("body_version", 1), "body_version", desc)
	desc.plan = String(d.get("plan", "spine"))
	desc.reference_length_mm = _int(d.get("reference_length_mm", 1000), "reference_length_mm", desc)
	desc.generator = String(d.get("generator", "skin-1"))
	var verts = d.get("vertebrae", [])
	if not verts is Array:
		desc.load_problems.append("vertebrae is not a list")
		desc.extra["vertebrae_unread"] = verts
		verts = []
	for v in verts:
		if not v is Dictionary:
			desc.load_problems.append("a vertebra is not an object: %s" % JSON.stringify(v))
			continue
		var p = v.get("p", [0, 0, 0])
		if not (p is Array and p.size() == 3):
			desc.load_problems.append("vertebra %s has no 3-number position" % String(v.get("id", "?")))
			p = [0, 0, 0]
		desc.vertebrae.append({"id": String(v.get("id", "")), "p": [_int(p[0], "p", desc), _int(p[1], "p", desc),
				_int(p[2], "p", desc)], "r": _int(v.get("r", 0), "r", desc)})
	var limbs = d.get("limbs", [])
	if not limbs is Array:
		desc.load_problems.append("limbs is not a list")
		desc.extra["limbs_unread"] = limbs
		limbs = []
	for limb in limbs:
		if not (limb is Dictionary and limb.get("joints", null) is Array):
			desc.load_problems.append("a limb is not an object with a joint list: %s" % JSON.stringify(limb))
			continue
		var joints := []
		for j in limb["joints"]:
			var p = j.get("p", [0, 0, 0]) if j is Dictionary else null
			if not (p is Array and p.size() == 3):
				desc.load_problems.append("a joint of limb %s has no 3-number position" % String(limb.get("id", "?")))
				continue
			joints.append({"id": String(j.get("id", "")), "p": [_int(p[0], "p", desc), _int(p[1], "p", desc),
					_int(p[2], "p", desc)], "r": _int(j.get("r", 0), "r", desc)})
		desc.limbs.append({"id": String(limb.get("id", "")), "attach": String(limb.get("attach", "")),
				"mirror": bool(limb.get("mirror", false)), "joints": joints})
	var nexts = d.get("next", {})
	desc.next_ids = {}
	if nexts is Dictionary:
		for k in nexts:
			desc.next_ids[String(k)] = _int(nexts[k], "next", desc)
	if not desc.next_ids.has("v"):
		desc.next_ids["v"] = desc.vertebrae.size() + 1
		desc.load_problems.append("next id counter was missing; set to v_%d" % desc.next_ids["v"])
	# Version 1 bodies have no limb or joint counters.
	for kind in ["l", "j"]:
		if not desc.next_ids.has(kind):
			desc.next_ids[kind] = 1 + (desc.limbs.size() if kind == "l" else desc.limbs.reduce(
					func(acc, l): return acc + (l["joints"] as Array).size(), 0))
	for k in d:
		if not KNOWN_KEYS.has(k):
			desc.extra[k] = d[k]
	return desc


static func decode(text: String) -> RefCounted:
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		var desc = BodyDescription.create()
		desc.load_problems.append("not a JSON object")
		desc.vertebrae = []
		return desc
	return from_dict(parsed)


## JSON numbers arrive as floats; body numbers must be whole.
static func _int(value, field: String, desc: RefCounted) -> int:
	if value is int:
		return value
	if value is float:
		if is_finite(value) and absf(value - roundf(value)) < 1e-9:
			return int(roundf(value))
		desc.load_problems.append("%s is not a whole number (%s); rounded" % [field, str(value)])
		return int(roundf(value)) if is_finite(value) else 0
	desc.load_problems.append("%s is not a number (%s)" % [field, str(value)])
	return 0
