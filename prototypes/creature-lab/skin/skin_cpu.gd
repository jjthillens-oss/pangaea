extends RefCounted
## Skin builder in GDScript (the baseline): naive Surface Nets (Gibson 1998) over the body field, normals from the
## field gradient, four bone weights per vertex from capsule contributions. Returns plain arrays and timings; it
## creates no nodes. Triangles wind clockwise seen from outside, Godot's front face.

const BodyField := preload("res://domain/body_field.gd")
const SkinGrid := preload("res://skin/skin_grid.gd")

## The 12 cell edges as pairs of corner numbers; corner c is at offset (c & 1, (c >> 1) & 1, (c >> 2) & 1).
const EDGES := [0, 1, 2, 3, 4, 5, 6, 7, 0, 2, 1, 3, 4, 6, 5, 7, 0, 4, 1, 5, 2, 6, 3, 7]


## Returns {vertices, normals, bones, weights, indices, dims, cell, ms: {field, nets, normals_weights, total}}.
static func build(desc: RefCounted, divisions: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var field = BodyField.from_description(desc)
	var grid := SkinGrid.layout(desc, divisions)
	var origin: Vector3 = grid["origin"]
	var cell: float = grid["cell"]
	var dims: Vector3i = grid["dims"]
	var nx := dims.x
	var nxy := dims.x * dims.y
	var n := nxy * dims.z
	var values := PackedFloat32Array()
	values.resize(n)

	# 1. Field: each capsule writes the points inside its support box (max of falloffs).
	for k in field.capsule_count():
		var a: Vector3 = field.a[k]
		var ab: Vector3 = field.b[k] - a
		var len2 := ab.length_squared()
		var ra: float = field.ra[k]
		var rb: float = field.rb[k]
		var reach := BodyField.SUPPORT * maxf(ra, rb)
		var lo := (Vector3(minf(a.x, a.x + ab.x), minf(a.y, a.y + ab.y), minf(a.z, a.z + ab.z)) - Vector3.ONE * reach - origin) / cell
		var hi := (Vector3(maxf(a.x, a.x + ab.x), maxf(a.y, a.y + ab.y), maxf(a.z, a.z + ab.z)) + Vector3.ONE * reach - origin) / cell
		var x0 := maxi(0, int(floor(lo.x)))
		var y0 := maxi(0, int(floor(lo.y)))
		var z0 := maxi(0, int(floor(lo.z)))
		var x1 := mini(dims.x - 1, int(ceil(hi.x)))
		var y1 := mini(dims.y - 1, int(ceil(hi.y)))
		var z1 := mini(dims.z - 1, int(ceil(hi.z)))
		for z in range(z0, z1 + 1):
			for y in range(y0, y1 + 1):
				var row := z * nxy + y * nx
				for x in range(x0, x1 + 1):
					var p := origin + Vector3(x, y, z) * cell
					var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0) if len2 > 0.0 else 0.0
					var big_r := BodyField.SUPPORT * lerpf(ra, rb, t)
					var q := (p - (a + ab * t)).length_squared() / (big_r * big_r)
					if q < 1.0:
						var u := 1.0 - q
						var f := u * u * u
						if f > values[row + x]:
							values[row + x] = f
	var t1 := Time.get_ticks_usec()

	# 2. One vertex per cell the surface crosses, at the mean of its edge crossings.
	var corner_offsets := PackedInt32Array([0, 1, nx, nx + 1, nxy, nxy + 1, nxy + nx, nxy + nx + 1])
	var corner_pos := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0),
			Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1)])
	var cell_vertex := PackedInt32Array()
	cell_vertex.resize(n)
	cell_vertex.fill(-1)
	var vertices := PackedVector3Array()
	var iso := BodyField.ISO
	var corner_vals := PackedFloat32Array()
	corner_vals.resize(8)
	for z in dims.z - 1:
		for y in dims.y - 1:
			var row := z * nxy + y * nx
			for x in dims.x - 1:
				var base := row + x
				var mask := 0
				for c in 8:
					var v := values[base + corner_offsets[c]] - iso
					corner_vals[c] = v
					if v > 0.0:
						mask |= 1 << c
				if mask == 0 or mask == 255:
					continue
				var sum := Vector3.ZERO
				var count := 0
				for e in 12:
					var c0: int = EDGES[2 * e]
					var c1: int = EDGES[2 * e + 1]
					var v0 := corner_vals[c0]
					var v1 := corner_vals[c1]
					if (v0 > 0.0) != (v1 > 0.0):
						sum += corner_pos[c0].lerp(corner_pos[c1], v0 / (v0 - v1))
						count += 1
				cell_vertex[base] = vertices.size()
				vertices.append(origin + (Vector3(x, y, z) + sum / count) * cell)

	# 3. A quad for every grid edge the surface crosses, joining the four cells around it.
	var indices := PackedInt32Array()
	for z in range(1, dims.z - 1):
		for y in range(1, dims.y - 1):
			var row := z * nxy + y * nx
			for x in range(1, dims.x - 1):
				var i := row + x
				var inside := values[i] > iso
				if inside != (values[i + 1] > iso):
					_quad(indices, cell_vertex, i - nx - nxy, i - nxy, i, i - nx, inside)
				if inside != (values[i + nx] > iso):
					_quad(indices, cell_vertex, i - 1 - nxy, i - 1, i, i - nxy, inside)
				if inside != (values[i + nxy] > iso):
					_quad(indices, cell_vertex, i - 1 - nx, i - nx, i, i - 1, inside)
	var t2 := Time.get_ticks_usec()

	# 4. Normals from the field gradient; bone weights from capsule contributions.
	var normals := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var bone_count: int = desc.vertebrae.size()
	for p in vertices:
		normals.append(field.normal(p, 0.25 * cell))
		var bw: Array = field.weights(p, bone_count)
		bones.append_array(bw[0])
		weights.append_array(bw[1])
	var t3 := Time.get_ticks_usec()
	return {"vertices": vertices, "normals": normals, "bones": bones, "weights": weights, "indices": indices,
			"dims": dims, "cell": cell,
			"ms": {"field": (t1 - t0) / 1000.0, "nets": (t2 - t1) / 1000.0, "normals_weights": (t3 - t2) / 1000.0,
				"total": (t3 - t0) / 1000.0}}


## Two triangles for the quad q0..q3, which runs counter-clockwise about the edge's +axis. When the edge starts
## inside, the outward side is +axis, so the order is reversed to wind clockwise seen from outside.
static func _quad(out: PackedInt32Array, cell_vertex: PackedInt32Array, q0: int, q1: int, q2: int, q3: int,
		starts_inside: bool) -> void:
	var v0 := cell_vertex[q0]
	var v1 := cell_vertex[q1]
	var v2 := cell_vertex[q2]
	var v3 := cell_vertex[q3]
	if starts_inside:
		out.append_array([v0, v2, v1, v0, v3, v2])
	else:
		out.append_array([v0, v1, v2, v0, v2, v3])
