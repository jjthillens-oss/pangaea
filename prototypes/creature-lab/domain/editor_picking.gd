extends RefCounted
## Editor picking (PROPOSED): from a ray in body space to a point on the skin, and from a skin point to a part anchor
## (host, u, ring, elev) that domain/anchor_resolver.gd turns back into the same spot. This is the resolver run
## backwards: the capsule that contributes most at the point gives the host and the position along it, and the
## direction from its axis gives the ring, in BodyField.ring_angle's frame. Pure rules: no scene or file access.

const BodyField := preload("res://domain/body_field.gd")

const BISECT_STEPS := 32
## March step along a ray, as a fraction of the thinnest capsule radius, so a ray cannot jump over a thin limb.
const MARCH_FRACTION := 0.25
## On a limb, a click this far along it (per mille) goes to the limb's end when the part may sit there.
const LIMB_END_FROM_U := 900


## First point where the ray enters the skin: {hit: bool, point: Vector3, normal: Vector3}.
static func ray_to_skin(field: RefCounted, origin: Vector3, dir: Vector3, max_distance := 100.0) -> Dictionary:
	var d := dir.normalized()
	var box: AABB = field.support_bounds()
	var far := origin + d * max_distance
	var start := origin
	if not box.has_point(origin):
		var entry = box.intersects_segment(origin, far)
		if entry == null:
			return {"hit": false}
		start = entry
	var min_r := INF
	for k in field.capsule_count():
		min_r = minf(min_r, minf(field.ra[k], field.rb[k]))
	var step := MARCH_FRACTION * min_r
	var span := minf(max_distance - origin.distance_to(start), box.get_longest_axis_size() * 1.8)
	var outside := 0.0
	var inside := -1.0
	var t := 0.0
	while t <= span:
		if field.sample(start + d * t) >= BodyField.ISO:
			inside = t
			break
		outside = t
		t += step
	if inside < 0.0:
		return {"hit": false}
	for i in BISECT_STEPS:
		var mid := 0.5 * (inside + outside)
		if field.sample(start + d * mid) >= BodyField.ISO:
			inside = mid
		else:
			outside = mid
	var p := start + d * (0.5 * (inside + outside))
	return {"hit": true, "point": p, "normal": field.normal(p, 0.05 * min_r)}


## The anchor at skin point `p`: {host: "spine" | limb id, u, ring, elev (ints), on_copy: bool (the point is on a
## mirrored limb's copy; the anchor is given on the original, so a mirrored part's twin lands at p)}.
## The chain (spine or limb) is the one whose capsule contributes most at p; the spot on it is the closest point on
## the chain's joint line, as the resolver measures u along that line. Past an end of the line (the spine's ends, a
## limb's tip) the anchor is an end cap: u 0 or 1000, leaning `elev` degrees from the axis.
static func anchor_at(desc: RefCounted, field: RefCounted, p: Vector3) -> Dictionary:
	var on_limb := _chain_anchor(desc, field, p, int(field.limb[field.dominant(p)]))
	# Behind a limb's first joint is the fillet into the trunk, which the limb's line cannot reach: use the spine.
	if on_limb.get("before_start", false):
		return _chain_anchor(desc, field, p, 0)
	return on_limb


static func _chain_anchor(desc: RefCounted, field: RefCounted, p: Vector3, limb_id: int) -> Dictionary:
	var first := -1
	var last := -1
	var best := -1
	var best_d := INF
	var best_raw := 0.0
	for k in field.capsule_count():
		if int(field.limb[k]) != limb_id:
			continue
		if first < 0:
			first = k
		last = k
		var ab: Vector3 = field.b[k] - field.a[k]
		var len2 := ab.length_squared()
		var raw: float = (p - field.a[k]).dot(ab) / len2 if len2 > 0.0 else 0.0
		var d: float = p.distance_to(field.a[k] + ab * clampf(raw, 0.0, 1.0))
		if d < best_d - 1e-9:
			best_d = d
			best = k
			best_raw = raw
	var a: Vector3 = field.a[best]
	var ab: Vector3 = field.b[best] - a
	var t := clampf(best_raw, 0.0, 1.0)
	var u: float = (field.start[best] + t * ab.length()) / field.chain_length[best] if field.chain_length[best] > 0.0 else 0.0
	var axis := ab
	# On the outside of a bend the closest point is the joint itself: measure the ring around the bend's mean
	# direction, as the resolver does there.
	if best_raw > 1.0 and best != last:
		axis = ab.normalized() + (field.b[best + 1] - field.a[best + 1]).normalized()
	elif best_raw < 0.0 and best != first:
		axis = ab.normalized() + (field.b[best - 1] - field.a[best - 1]).normalized()
	var ring := BodyField.ring_angle(p - (a + ab * t), axis)
	var elev := 0
	if limb_id != 0 and best == first and best_raw < 0.0:
		return {"before_start": true}
	# The spine has caps at both ends; a limb at its tip only (its start is inside the trunk).
	var head_cap := limb_id == 0 and best == first and best_raw < 0.0
	var tail_cap := best == last and best_raw > 1.0
	if head_cap or tail_cap:
		var end := a if head_cap else a + ab
		var out_axis := -ab.normalized() if head_cap else ab.normalized()
		elev = clampi(int(round(rad_to_deg(out_axis.angle_to(p - end)))), 0, 90)
		u = 0.0 if head_cap else 1.0
		ring = BodyField.ring_angle(p - end, ab) if elev > 0 else 0.0
	var ring_i := int(round(ring * 1000.0)) % 1000
	if limb_id == 0:
		return {"host": "spine", "u": int(round(u * 1000.0)), "ring": ring_i, "elev": elev, "on_copy": false}
	var chains: Array = desc.limb_chains()
	var chain: Dictionary = chains[limb_id - 1]
	var on_copy: bool = limb_id >= 2 and chains[limb_id - 2]["source"] == chain["source"]
	if on_copy:
		# Mirroring across X = 0 turns the ring the other way.
		ring_i = (1000 - ring_i) % 1000
	return {"host": String(chain["source"]), "u": int(round(u * 1000.0)), "ring": ring_i, "elev": elev,
			"on_copy": on_copy}


## The anchor a part of this kind gets at a picked spot, or {reason} when it cannot go there. `rule` is the part's
## record part_rules. Applies the part's hosts (a limb click near the tip goes to the limb's end when allowed), its
## middle-line rule (snaps a "required" part onto ring 0 or 500), and gives a part off the middle line a twin.
static func anchor_for_part(desc: RefCounted, rule: Dictionary, picked: Dictionary) -> Dictionary:
	var hosts: Array = rule["hosts"]
	var a := {"host": picked["host"], "u": picked["u"], "ring": picked["ring"], "elev": picked["elev"]}
	if picked["host"] == "spine":
		if not hosts.has("spine"):
			return {"reason": "%s parts go on a limb" % rule["type"]}
	else:
		var limb: Dictionary = desc.limbs[desc.limb_index(String(picked["host"]))]
		var end_ok := hosts.has("limb_end")
		if end_ok and (int(picked["u"]) >= LIMB_END_FROM_U or not hosts.has("limb")):
			a["host"] = String(picked["host"]) + ":end"
		elif not hosts.has("limb"):
			return {"reason": "%s parts go on the body" % rule["type"]}
		a["mirror"] = bool(limb["mirror"])
		return a
	var ring := int(a["ring"])
	var cap := int(a["u"]) == 0 or int(a["u"]) == 1000
	match String(rule["centerline"]):
		"required":
			a["ring"] = 0 if ring < 250 or ring >= 750 else 500
			if cap:
				a["elev"] = 0
		"forbidden":
			if ring == 0 or ring == 500:
				a["ring"] = ring + 1
			if cap and int(a["elev"]) == 0:
				a["elev"] = 1
	var middle: bool = int(a["ring"]) == 0 or int(a["ring"]) == 500 or (cap and int(a["elev"]) == 0)
	a["mirror"] = not middle
	return a
