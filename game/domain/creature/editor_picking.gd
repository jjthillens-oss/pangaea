extends RefCounted
## Editor picking (PROPOSED): from a ray in body space to a point on the skin, and from a skin point to a part anchor
## (host, u, ring, elev) that domain/anchor_resolver.gd turns back into the same spot. This is the resolver run
## backwards: the capsule that contributes most at the point gives the host and the position along it, and the
## direction from its axis gives the ring, in BodyField.ring_angle's frame. Pure rules: no scene or file access.

const BodyField := preload("res://game/domain/creature/body_field.gd")

const BISECT_STEPS := 32
## March step along a ray, as a fraction of the thinnest capsule radius, so a ray cannot jump over a thin limb.
const MARCH_FRACTION := 0.25
## On a limb, a click this far along it (per mille) goes to the limb's end when the part may sit there.
const LIMB_END_FROM_U := 900
## A click this close (per mille of a turn) to the middle line snaps onto it, for parts allowed there.
const MIDDLE_SNAP := 25
## A press on the top of the back (the normal's up component at least TOP_PRESS_UP: within about 37 degrees of straight
## up, so a press on the upper flank still makes an arm) grows a limb up and out; a press
## at the end of the spine (the normal within END_PRESS_ALONG of the spine's own direction `along`, zero away from
## the ends) grows one on along it.
const TOP_PRESS_UP := 0.8
const END_PRESS_ALONG := 0.6
## A side press blends the normal with straight down, so a limb hangs like an arm: outward and down, tip below the
## attach point, the middle joint ARM_BEND of the limb's length forward.
const ARM_OUT := 0.6
const ARM_DOWN := 0.8
const ARM_BEND := 0.12


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
## middle-line rule (snaps a "required" part onto ring 0 or 500, and an "allowed" one when the click is within
## MIDDLE_SNAP of it), and gives a part off the middle line a twin.
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
		"allowed":
			if ring <= MIDDLE_SNAP or ring >= 1000 - MIDDLE_SNAP:
				a["ring"] = 0
			elif absi(ring - 500) <= MIDDLE_SNAP:
				a["ring"] = 500
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


## The scale (per mille) a new part gets on `desc`: in proportion to the body's size (the longest side of its
## bounds) against `reference_size_m`, the size at which parts were authored at 1000, rounded to 50 and kept in the
## body rules' part scale range. A big creature's new feet are big; the player can still resize them.
static func fit_scale(desc: RefCounted, reference_size_m: float, rules: Dictionary) -> int:
	if reference_size_m <= 0.0:
		return 1000
	var ratio: float = (desc.bounds_m() as AABB).get_longest_axis_size() / reference_size_m
	var s := int(round(ratio * 20.0)) * 50
	return clampi(s, int(rules.get("part_scale_min", 1000)), int(rules.get("part_scale_max", 1000)))


## A new limb grown from skin point `p` with outward normal `normal` (PROPOSED defaults): three joints on the vertebra
## nearest the click, 2.5 vertebra radii long and tapering. Joint 0 sits inside the vertebra's sphere, so it touches
## it. A press on the top of the back points up and out along the normal and a press past either end of the spine
## points on along it; a press on a side (or the belly) hangs the limb like an arm: outward and down, its tip below
## the attach point, with the middle joint a little forward for a bend (limb_direction). A click off the middle plane
## makes a mirrored pair. Returns {attach, joints: [[Vector3i, r], ...], mirror} for CreatureEditorSession.add_limb,
## or {reason}.
static func limb_at(desc: RefCounted, rules: Dictionary, p: Vector3, normal: Vector3) -> Dictionary:
	var s: float = desc.scale_m()
	var best := 0
	for i in desc.vertebrae.size():
		if desc.position_m(i).distance_to(p) < desc.position_m(best).distance_to(p):
			best = i
	var centre: Vector3 = desc.position_m(best)
	var rv: float = desc.radius_m(best)
	var out := (p - centre).normalized() if p.distance_to(centre) > 0.0 else normal
	var mirror := absf(p.x) > 0.25 * rv
	if not mirror and absf(p.x) > 0.0:
		p.x = 0.0
		out.x = 0.0
		normal.x = 0.0
	# Thick enough for the finest preview grid even after the limb lengthens the body a little.
	var min_r: float = 1.4 * float(rules["min_radius_preview_cells"]) * 1.15 * desc.bounds_m().get_longest_axis_size() \
			/ float(rules["preview_divisions_max"])
	var r0 := maxf(0.45 * rv, min_r)
	var start := centre + out.normalized() * 0.6 * rv
	var n: int = desc.vertebrae.size()
	var along := Vector3.ZERO
	if best == 0 and n > 1:
		along = (desc.position_m(0) - desc.position_m(1)).normalized()
	elif best == n - 1 and n > 1:
		along = (desc.position_m(n - 1) - desc.position_m(n - 2)).normalized()
	var pose := limb_direction(normal.normalized() if normal.length_squared() > 0.0 else out.normalized(), along)
	var dir: Vector3 = pose["dir"]
	var length := 2.5 * rv
	var joints := []
	for k in 3:
		var at := start + dir * length * k / 2.0
		if k == 1:
			at += (pose["bend"] as Vector3) * length
		var r := maxf(r0 * pow(0.85, k), min_r)
		joints.append([Vector3i(int(round(at.x / s)), int(round(at.y / s)), int(round(at.z / s))), int(ceil(r / s))])
	return {"attach": desc.vertebrae[best]["id"], "joints": joints, "mirror": mirror}


## The direction a new limb takes from a skin press with outward `normal` ({dir: unit Vector3, bend: the middle
## joint's offset per metre of limb}): straight along the normal on the top of the back and at the spine's ends,
## otherwise outward and down with a slight forward bend. `along` is the spine's outward direction at the pressed
## vertebra when it is an end, else zero.
static func limb_direction(normal: Vector3, along := Vector3.ZERO) -> Dictionary:
	if normal.y >= TOP_PRESS_UP or (along.length_squared() > 0.0 and normal.dot(along) >= END_PRESS_ALONG):
		return {"dir": normal, "bend": Vector3.ZERO}
	var dir := (normal * ARM_OUT + Vector3.DOWN * ARM_DOWN).normalized()
	return {"dir": dir, "bend": Vector3.FORWARD * ARM_BEND}
