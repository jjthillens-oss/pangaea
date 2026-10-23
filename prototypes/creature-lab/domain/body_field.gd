extends RefCounted
## The implicit field around a spine (PROPOSED, CREATURE_GEOMETRY_SPEC.md section 4). Each pair of neighbouring
## vertebrae makes a tapered capsule; each capsule gives the soft-object falloff (1 - d^2/R^2)^3 of the distance to
## its axis, with R = SUPPORT * radius. The skin is where the field equals ISO, which puts a lone capsule's surface at
## its radius. Within one chain the capsules are combined by a p-norm, F = (sum f^P)^(1/P) with P = 3: a plain sum
## (P = 1) bulges about 15% at every vertebra (2 f(d) = ISO at d = 1.15 r), and max (P = infinity) leaves creases
## where a bent spine's capsules meet. P = 3 bulges about 5% and rounds the creases. Grid builders store
## S = sum f^P and compare it with ISO_P = ISO^P, which is the same surface. Limbs are more chains of capsules in the
## same blend, so where a limb meets the trunk the p-norm also rounds the junction into a small fillet.
## Pure rules: no scene or file access. skin/surface_nets.glsl repeats these formulas and must stay in step.

const SUPPORT := 1.6
const ISO := 0.22628403  # (1 - 1 / SUPPORT^2)^3
const BLEND_P := 3.0
const ISO_P := 0.011586752  # ISO^BLEND_P
## Reduce opposing spine influence on vertices whose dominant capsule is a limb. This keeps the
## limb's cross-section from collapsing when its root swings far from the trunk.
const HIP_SPINE_BLEND := 0.02  # 90-degree quadruped hip retains 94.6% of rest radius.

## Capsule k runs from a[k] to b[k] and belongs to bones bone_a[k] and bone_b[k]. Spine capsules come first.
var a := PackedVector3Array()
var b := PackedVector3Array()
var ra := PackedFloat32Array()
var rb := PackedFloat32Array()
var bone_a := PackedInt32Array()
var bone_b := PackedInt32Array()
## Chain length before capsule k and the whole chain's length (for paint coordinates), its limb id (0 = spine) and,
## for a limb, the spine coordinate of the vertebra it starts on.
var start := PackedFloat32Array()
var chain_length := PackedFloat32Array()
var limb := PackedFloat32Array()
var attach_u := PackedFloat32Array()
## Spine length.
var total_length := 0.0


static func from_description(desc: RefCounted) -> RefCounted:
	var f = load("res://domain/body_field.gd").new()
	var n: int = desc.vertebrae.size()
	var spine_u := PackedFloat32Array([0.0])
	for i in n - 1:
		f._add(desc.position_m(i), desc.position_m(i + 1), desc.radius_m(i), desc.radius_m(i + 1), i, i + 1,
				f.total_length, 0.0, 0.0)
		f.total_length += desc.position_m(i).distance_to(desc.position_m(i + 1))
		spine_u.append(f.total_length)
	for k in f.chain_length.size():
		f.chain_length[k] = f.total_length
	var bone := n
	for c in desc.limb_chains():
		var pts: PackedVector3Array = c["points"]
		var rs: PackedFloat32Array = c["radii"]
		var u: float = spine_u[c["attach"]] / f.total_length if f.total_length > 0.0 else 0.0
		var first: int = f.a.size()
		var along := 0.0
		for k in pts.size() - 1:
			f._add(pts[k], pts[k + 1], rs[k], rs[k + 1], bone + k, bone + k + 1, along, float(c["limb_id"]), u)
			along += pts[k].distance_to(pts[k + 1])
		for k in range(first, f.a.size()):
			f.chain_length[k] = along
		bone += pts.size()
	return f


func _add(pa: Vector3, pb: Vector3, r0: float, r1: float, b0: int, b1: int, at: float, limb_id: float, u: float) -> void:
	a.append(pa)
	b.append(pb)
	ra.append(r0)
	rb.append(r1)
	bone_a.append(b0)
	bone_b.append(b1)
	start.append(at)
	chain_length.append(0.0)
	limb.append(limb_id)
	attach_u.append(u)


func capsule_count() -> int:
	return a.size()


## Falloff of capsule k at p, and the axis parameter t of the closest point (for weights).
func capsule(k: int, p: Vector3) -> Vector2:
	var ab := b[k] - a[k]
	var len2 := ab.length_squared()
	var t := clampf((p - a[k]).dot(ab) / len2, 0.0, 1.0) if len2 > 0.0 else 0.0
	var big_r := SUPPORT * lerpf(ra[k], rb[k], t)
	var x := (p - (a[k] + ab * t)).length_squared() / (big_r * big_r)
	if x >= 1.0:
		return Vector2(0.0, t)
	var u := 1.0 - x
	return Vector2(u * u * u, t)


func sample(p: Vector3) -> float:
	return pow(sample_p(p), 1.0 / BLEND_P)


## sum f^P, the value grid builders store.
func sample_p(p: Vector3) -> float:
	var s := 0.0
	for k in a.size():
		s += pow(capsule(k, p).x, BLEND_P)
	return s


## Outward surface normal at p (minus the field gradient), by central differences.
func normal(p: Vector3, h: float) -> Vector3:
	var g := Vector3(sample(p + Vector3(h, 0, 0)) - sample(p - Vector3(h, 0, 0)),
			sample(p + Vector3(0, h, 0)) - sample(p - Vector3(0, h, 0)),
			sample(p + Vector3(0, 0, h)) - sample(p - Vector3(0, 0, h)))
	return (-g).normalized() if g.length_squared() > 0.0 else Vector3.UP


## Box around everything the field can touch.
func support_bounds() -> AABB:
	var box := AABB(a[0], Vector3.ZERO)
	for k in a.size():
		var r := SUPPORT * maxf(ra[k], rb[k])
		box = box.merge(AABB(a[k] - Vector3.ONE * r, Vector3.ONE * 2.0 * r))
		box = box.merge(AABB(b[k] - Vector3.ONE * r, Vector3.ONE * 2.0 * r))
	return box


## Paint coordinates for the skin shader (Godot CUSTOM0, docs/art/creature_art_contract.md), from the capsule that
## contributes most at p: x = position along the spine (0 head, 1 tail; on a limb, that of its vertebra), y = angle
## around the capsule axis in turns (0 towards body up, 0.25 right, 0.5 down, 0.75 left; wraps at 0), z = limb id
## (0 = spine), w = position along the limb (0 at joint 0, 1 at the tip; 0 on the spine).
## skin/surface_nets.glsl repeats this.
func paint_coords(p: Vector3) -> Vector4:
	var best := dominant(p)
	var ab := b[best] - a[best]
	var len2 := ab.length_squared()
	var t := clampf((p - a[best]).dot(ab) / len2, 0.0, 1.0) if len2 > 0.0 else 0.0
	var along := (start[best] + t * sqrt(len2)) / chain_length[best] if chain_length[best] > 0.0 else 0.0
	var ring := ring_angle(p - (a[best] + ab * t), ab)
	if limb[best] == 0.0:
		return Vector4(along, ring, 0.0, 0.0)
	return Vector4(attach_u[best], ring, limb[best], along)


## The capsule that contributes most at p (the lowest index on a tie).
func dominant(p: Vector3) -> int:
	var best := 0
	var best_f := -1.0
	for k in a.size():
		var c := capsule(k, p)
		if c.x > best_f:
			best_f = c.x
			best = k
	return best


## Angle of `w` around the axis `axis` (head to tail), in turns: 0 towards body up, 0.25 towards body right.
static func ring_angle(w: Vector3, axis: Vector3) -> float:
	var tdir := axis.normalized() if axis.length_squared() > 0.0 else Vector3.BACK
	var ref := Vector3.UP if absf(tdir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var dorsal := (ref - tdir * ref.dot(tdir)).normalized()
	var right := dorsal.cross(tdir)
	return fposmod(atan2(w.dot(right), w.dot(dorsal)) / TAU, 1.0)


## Up to four (bone, weight) pairs at p, weights summing to 1, heaviest first; ties go to the lower bone index.
## A capsule gives its falloff to its two bones, split by t, so a bend between joints blends smoothly. A point whose
## dominant capsule is on a limb takes weights only from that limb and the spine, so a limb never drags on its
## neighbour (CREATURE_GEOMETRY_SPEC.md section 10, test 3).
func weights(p: Vector3, bone_count: int) -> Array:
	var w := PackedFloat32Array()
	w.resize(bone_count)
	var total := 0.0
	var own := limb[dominant(p)]
	for k in a.size():
		if limb[k] != 0.0 and limb[k] != own:
			continue
		var c := capsule(k, p)
		if c.x > 0.0:
			var influence: float = c.x * (HIP_SPINE_BLEND if own != 0.0 and limb[k] == 0.0 else 1.0)
			w[bone_a[k]] += influence * (1.0 - c.y)
			w[bone_b[k]] += influence * c.y
			total += influence
	if total <= 0.0:
		# Outside every support (rare, at the very tip): nearest capsule's bones.
		var best_k := 0
		var best_d := INF
		for k in a.size():
			if limb[k] != 0.0 and limb[k] != own:
				continue
			var d := Geometry3D.get_closest_point_to_segment(p, a[k], b[k]).distance_to(p)
			if d < best_d:
				best_d = d
				best_k = k
		w[bone_a[best_k]] = 1.0
	var bones := PackedInt32Array()
	var weights_out := PackedFloat32Array()
	for slot in 4:
		var best := -1
		for i in bone_count:
			if w[i] > 0.0 and (best < 0 or w[i] > w[best]):
				best = i
		if best < 0:
			bones.append(0)
			weights_out.append(0.0)
		else:
			bones.append(best)
			weights_out.append(w[best])
			w[best] = 0.0
	var sum := weights_out[0] + weights_out[1] + weights_out[2] + weights_out[3]
	for slot in 4:
		weights_out[slot] /= sum
	return [bones, weights_out]
