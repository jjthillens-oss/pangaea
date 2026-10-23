extends RefCounted
## Where a part sits (PROPOSED, workstreams/creature_editor.md section 3.4 option A-1): its anchor is stored relative
## to a host (the spine, a limb, or a limb's end), so after any body edit the part is found again on the skin.
## Pure rules: no scene or file access.
##
## For a spine or limb host: take the point at fraction u along the host's joint line, go out from it in the direction
## `ring` (thousandths of a turn: 0 up, 250 right, as the paint coordinates), and find the skin by bisection on the
## field. The part's up is the skin normal there, its forward the head direction laid onto the skin (art contract
## section 1.1: Godot +Y up, -Z forward). For a limb end: the point where the limb's axis leaves the tip, up along the
## axis; "ground" parts (feet) instead stand on the tip with up = body up and forward = body forward. Then the stored
## turn, tilt and roll, height and scale apply. A mirrored part's twin is the exact reflection across X = 0.

const BodyField := preload("res://domain/body_field.gd")

const BISECT_STEPS := 32
const MARCH_STEPS := 64

## The ankle top of a ground part above its sole, per metre of part scale (cpart_foot record: "the ankle top
## (z 0.09 m) meets the limb tip").
const GROUND_ANKLE_M := 0.09


## Returns [{part: id, twin: bool, transform: Transform3D (body space, with scale), bone: int}, ...]: one entry per
## part, two for a mirrored part. `orientations` maps a part type to its record's orientation ("normal", "ground",
## "forward_cone"); unknown types use "normal".
static func resolve_all(desc: RefCounted, field: RefCounted, orientations: Dictionary) -> Array:
	var out := []
	for p in desc.parts:
		var placed := resolve(desc, field, p, String(orientations.get(p["type"], "normal")))
		if placed.is_empty():
			continue
		out.append({"part": p["id"], "twin": false, "transform": placed["transform"], "bone": placed["bone"]})
		if p["mirror"]:
			out.append({"part": p["id"], "twin": true, "transform": mirrored(placed["transform"]),
					"bone": mirror_bone(desc, placed["bone"])})
	return out


## The reflection of a placement across the X = 0 plane (determinant -1: the twin is the part's mirror image, so a
## chiral part curls the other way).
static func mirrored(t: Transform3D) -> Transform3D:
	var m := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	return Transform3D(m * t.basis, Vector3(-t.origin.x, t.origin.y, t.origin.z))


## Body-space placement of one part: {transform, bone}, or {} when its host is missing.
static func resolve(desc: RefCounted, field: RefCounted, part: Dictionary, orientation := "normal") -> Dictionary:
	var host := String(part["host"])
	var line := PackedVector3Array()
	var radii := PackedFloat32Array()
	var bones := PackedInt32Array()
	var limb_chain := -1
	if host == "spine":
		for i in desc.vertebrae.size():
			line.append(desc.position_m(i))
			radii.append(desc.radius_m(i))
			bones.append(i)
	else:
		var limb_id := host.trim_suffix(":end")
		var bone: int = desc.vertebrae.size()
		var chains: Array = desc.limb_chains()
		for c in chains.size():
			var pts: PackedVector3Array = chains[c]["points"]
			if chains[c]["source"] == limb_id and limb_chain < 0:
				limb_chain = c
				line = pts
				radii = chains[c]["radii"]
				for k in pts.size():
					bones.append(bone + k)
			bone += pts.size()
		if limb_chain < 0:
			return {}
	var s := float(part["scale"]) / 1000.0
	var place: Transform3D
	var bone_out: int
	if host.ends_with(":end"):
		var n := line.size()
		var axis := (line[n - 1] - line[n - 2]).normalized()
		bone_out = bones[n - 1]
		if orientation == "ground":
			var tip := line[n - 1]
			place = Transform3D(Basis(), tip - Vector3(0.0, GROUND_ANKLE_M * s, 0.0))
		else:
			var p := _march(field, line[n - 1], axis, radii[n - 1])
			place = Transform3D(_frame(axis, Vector3.FORWARD), p)
	else:
		var at := _point_on_line(line, float(part["u"]) / 1000.0)
		var k: int = at["segment"]
		var tangent: Vector3 = at["tangent"]
		var dir := _ring_direction(tangent, float(part["ring"]) / 1000.0)
		# End caps (polar mode): at the spine's ends the part leans `elev` degrees from the axis towards `ring`.
		if host == "spine" and (int(part["u"]) == 0 or int(part["u"]) == 1000):
			var out_axis := -tangent if int(part["u"]) == 0 else tangent
			var e := deg_to_rad(float(part["elev"]))
			dir = (out_axis * cos(e) + dir * sin(e)).normalized()
		var r := lerpf(radii[k], radii[k + 1], at["t"])
		var p := _march(field, at["point"], dir, r)
		var up: Vector3 = field.normal(p, 0.05 * r)
		# Forward: towards the head along the spine; on a limb, the body's forward.
		var head := -tangent if host == "spine" else Vector3.FORWARD
		place = Transform3D(_frame(up, head), p)
		bone_out = bones[k] if at["t"] < 0.5 else bones[k + 1]
	var b := place.basis
	b = b * Basis(Vector3.UP, deg_to_rad(float(part["turn"]))) * Basis(Vector3.RIGHT, deg_to_rad(float(part["tilt"]))) \
			* Basis(Vector3.BACK, deg_to_rad(float(part["roll"])))
	var origin: Vector3 = place.origin + place.basis.y * float(part["height"]) * desc.scale_m()
	return {"transform": Transform3D(b.scaled_local(Vector3.ONE * s), origin), "bone": bone_out}


## Up = `up`; -Z as close to `forward` as the plane allows (falls back to body up or forward when they line up).
static func _frame(up: Vector3, forward: Vector3) -> Basis:
	var y := up.normalized()
	var f := forward - y * forward.dot(y)
	if f.length_squared() < 1e-8:
		f = Vector3.UP - y * y.y if absf(y.y) < 0.99 else Vector3.FORWARD - y * y.z
	var z := -f.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, x.cross(y))


## Point at arc fraction u along a joint line: {point, tangent (towards the line's end), segment, t}.
static func _point_on_line(line: PackedVector3Array, u: float) -> Dictionary:
	var total := 0.0
	for k in line.size() - 1:
		total += line[k].distance_to(line[k + 1])
	var want := clampf(u, 0.0, 1.0) * total
	for k in line.size() - 1:
		var len_k := line[k].distance_to(line[k + 1])
		if want <= len_k or k == line.size() - 2:
			var t := clampf(want / len_k, 0.0, 1.0) if len_k > 0.0 else 0.0
			return {"point": line[k].lerp(line[k + 1], t), "tangent": (line[k + 1] - line[k]).normalized(), "segment": k,
					"t": t}
		want -= len_k
	return {"point": line[0], "tangent": Vector3.BACK, "segment": 0, "t": 0.0}


## Direction at `ring` turns around `tangent`, with BodyField.ring_angle's frame (0 up, 0.25 right).
static func _ring_direction(tangent: Vector3, ring: float) -> Vector3:
	var ref := Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var dorsal := (ref - tangent * ref.dot(tangent)).normalized()
	var right := dorsal.cross(tangent)
	return dorsal * cos(TAU * ring) + right * sin(TAU * ring)


## Where the skin is along a ray from inside the body: march out to the first point outside, then bisect.
static func _march(field: RefCounted, from: Vector3, dir: Vector3, radius: float) -> Vector3:
	var step := 4.0 * BodyField.SUPPORT * radius / MARCH_STEPS
	var inside := 0.0
	var outside := -1.0
	for i in range(1, MARCH_STEPS + 1):
		if field.sample(from + dir * (step * i)) < BodyField.ISO:
			outside = step * i
			inside = step * (i - 1)
			break
	if outside < 0.0:
		return from + dir * radius
	for i in BISECT_STEPS:
		var mid := 0.5 * (inside + outside)
		if field.sample(from + dir * mid) < BodyField.ISO:
			outside = mid
		else:
			inside = mid
	return from + dir * (0.5 * (inside + outside))


## The bone of a mirrored part's twin: the same vertebra, or the matching joint of the limb's mirror copy, which
## limb_chains() lists right after the original (validate_parts refuses a twin on a limb without a mirror copy).
static func mirror_bone(desc: RefCounted, bone: int) -> int:
	var at: int = desc.vertebrae.size()
	if bone < at:
		return bone
	for c in desc.limb_chains():
		var count: int = (c["points"] as PackedVector3Array).size()
		if bone < at + count:
			return bone + count
		at += count
	return bone
