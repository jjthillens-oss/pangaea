extends RefCounted
## The implicit field around a spine (PROPOSED, CREATURE_GEOMETRY_SPEC.md section 4). Each pair of neighbouring
## vertebrae makes a tapered capsule; each capsule gives the soft-object falloff (1 - d^2/R^2)^3 of the distance to
## its axis, with R = SUPPORT * radius. The skin is where the field equals ISO, which puts a lone capsule's surface at
## its radius. Within one chain the capsules are combined by max, not sum: a sum bulges about 15% at every vertebra
## (measured on paper: 2 f(d) = ISO at d = 1.15 r). Sum or smooth-union across chains comes with limbs.
## Pure rules: no scene or file access. skin/surface_nets.glsl repeats these formulas and must stay in step.

const SUPPORT := 1.6
const ISO := 0.22628403  # (1 - 1 / SUPPORT^2)^3

## Capsule k runs from a[k] to b[k]; it belongs to bones k and k + 1 (vertebra indices).
var a := PackedVector3Array()
var b := PackedVector3Array()
var ra := PackedFloat32Array()
var rb := PackedFloat32Array()


static func from_description(desc: RefCounted) -> RefCounted:
	var f = load("res://domain/body_field.gd").new()
	for i in desc.vertebrae.size() - 1:
		f.a.append(desc.position_m(i))
		f.b.append(desc.position_m(i + 1))
		f.ra.append(desc.radius_m(i))
		f.rb.append(desc.radius_m(i + 1))
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
	var best := 0.0
	for k in a.size():
		best = maxf(best, capsule(k, p).x)
	return best


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
