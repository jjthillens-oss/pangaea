extends RefCounted
## The implicit field around a spine (PROPOSED, CREATURE_GEOMETRY_SPEC.md section 4). Each pair of neighbouring
## vertebrae makes a tapered capsule; each capsule gives the soft-object falloff (1 - d^2/R^2)^3 of the distance to
## its axis, with R = SUPPORT * radius. The skin is where the field equals ISO, which puts a lone capsule's surface at
## its radius. Within one chain the capsules are combined by a p-norm, F = (sum f^P)^(1/P) with P = 3: a plain sum
## (P = 1) bulges about 15% at every vertebra (2 f(d) = ISO at d = 1.15 r), and max (P = infinity) leaves creases
## where a bent spine's capsules meet. P = 3 bulges about 5% and rounds the creases. Grid builders store
## S = sum f^P and compare it with ISO_P = ISO^P, which is the same surface. Sum or smooth-union across chains comes
## with limbs.
## Pure rules: no scene or file access. skin/surface_nets.glsl repeats these formulas and must stay in step.

const SUPPORT := 1.6
const ISO := 0.22628403  # (1 - 1 / SUPPORT^2)^3
const BLEND_P := 3.0
const ISO_P := 0.011586752  # ISO^BLEND_P

## Capsule k runs from a[k] to b[k]; it belongs to bones k and k + 1 (vertebra indices).
var a := PackedVector3Array()
var b := PackedVector3Array()
var ra := PackedFloat32Array()
var rb := PackedFloat32Array()
## Spine length before capsule k, and the whole spine length (for paint coordinates).
var start := PackedFloat32Array()
var total_length := 0.0


static func from_description(desc: RefCounted) -> RefCounted:
	var f = load("res://domain/body_field.gd").new()
	for i in desc.vertebrae.size() - 1:
		f.a.append(desc.position_m(i))
		f.b.append(desc.position_m(i + 1))
		f.ra.append(desc.radius_m(i))
		f.rb.append(desc.radius_m(i + 1))
		f.start.append(f.total_length)
		f.total_length += desc.position_m(i).distance_to(desc.position_m(i + 1))
	return f


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


## Paint coordinates for the skin shader (Godot CUSTOM0, CREATURE_GEOMETRY_SPEC.md section 8), from the capsule that
## contributes most at p: x = position along the spine (0 head, 1 tail), y = angle around it in turns (0 on the
## dorsal midline, 0.25 right, 0.5 belly, 0.75 left; wraps on the dorsal midline), z = limb id (0 = spine),
## w = distance along the limb (0 on the spine). skin/surface_nets.glsl repeats this.
func paint_coords(p: Vector3) -> Vector4:
	var best := 0
	var best_f := -1.0
	for k in a.size():
		var c := capsule(k, p)
		if c.x > best_f:
			best_f = c.x
			best = k
	var ab := b[best] - a[best]
	var len2 := ab.length_squared()
	var t := clampf((p - a[best]).dot(ab) / len2, 0.0, 1.0) if len2 > 0.0 else 0.0
	var u := (start[best] + t * sqrt(len2)) / total_length if total_length > 0.0 else 0.0
	return Vector4(u, ring_angle(p - (a[best] + ab * t), ab), 0.0, 0.0)


## Angle of `w` around the axis `axis` (head to tail), in turns: 0 towards body up, 0.25 towards body right.
static func ring_angle(w: Vector3, axis: Vector3) -> float:
	var tdir := axis.normalized() if axis.length_squared() > 0.0 else Vector3.BACK
	var ref := Vector3.UP if absf(tdir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var dorsal := (ref - tdir * ref.dot(tdir)).normalized()
	var right := dorsal.cross(tdir)
	return fposmod(atan2(w.dot(right), w.dot(dorsal)) / TAU, 1.0)


## Up to four (bone, weight) pairs at p, weights summing to 1, heaviest first; ties go to the lower bone index.
## A capsule gives its falloff to its two bones, split by t, so a bend between vertebrae blends smoothly.
func weights(p: Vector3, bone_count: int) -> Array:
	var w := PackedFloat32Array()
	w.resize(bone_count)
	var total := 0.0
	for k in a.size():
		var c := capsule(k, p)
		if c.x > 0.0:
			w[k] += c.x * (1.0 - c.y)
			w[k + 1] += c.x * c.y
			total += c.x
	if total <= 0.0:
		# Outside every support (rare, at the very tip): nearest capsule's bones.
		var best_k := 0
		var best_d := INF
		for k in a.size():
			var d := Geometry3D.get_closest_point_to_segment(p, a[k], b[k]).distance_to(p)
			if d < best_d:
				best_d = d
				best_k = k
		w[best_k] = 1.0
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
