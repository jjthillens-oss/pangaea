extends RefCounted
## Mesh checks shared by the tests and the bench.


## Every edge is shared by exactly two triangles, in opposite directions, and the mesh is one connected piece.
static func watertight(indices: PackedInt32Array) -> bool:
	if indices.is_empty():
		return false
	var directed := {}
	for t in indices.size() / 3:
		for e in 3:
			var a := indices[3 * t + e]
			var b := indices[3 * t + (e + 1) % 3]
			var key := Vector2i(a, b)
			if directed.has(key):
				return false
			directed[key] = true
	for key in directed:
		if not directed.has(Vector2i(key.y, key.x)):
			return false
	return pieces(indices) == 1


## Number of connected pieces (union-find over triangle vertices).
static func pieces(indices: PackedInt32Array) -> int:
	var parent := {}
	for i in indices:
		parent[i] = i
	for t in indices.size() / 3:
		_union(parent, indices[3 * t], indices[3 * t + 1])
		_union(parent, indices[3 * t], indices[3 * t + 2])
	var roots := {}
	for i in parent:
		roots[_find(parent, i)] = true
	return roots.size()


static func mesh_hash(arrays: Dictionary) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(PackedVector3Array(arrays["vertices"]).to_byte_array())
	ctx.update(PackedVector3Array(arrays["normals"]).to_byte_array())
	ctx.update(PackedInt32Array(arrays["bones"]).to_byte_array())
	ctx.update(PackedFloat32Array(arrays["weights"]).to_byte_array())
	ctx.update(PackedInt32Array(arrays["indices"]).to_byte_array())
	return ctx.finish().hex_encode()


## Largest distance between matching vertices of two meshes with the same vertex order.
static func max_vertex_gap(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size():
		return INF
	var worst := 0.0
	for i in a.size():
		worst = maxf(worst, a[i].distance_to(b[i]))
	return worst


## Fraction of triangles whose winding faces away from the outward normals (should be 0 for Godot's clockwise
## front faces: (b - a) x (c - a) points inward).
static func wrong_winding_fraction(arrays: Dictionary) -> float:
	var v: PackedVector3Array = arrays["vertices"]
	var nrm: PackedVector3Array = arrays["normals"]
	var idx: PackedInt32Array = arrays["indices"]
	var wrong := 0
	for t in idx.size() / 3:
		var a := v[idx[3 * t]]
		var face := (v[idx[3 * t + 1]] - a).cross(v[idx[3 * t + 2]] - a)
		var outward := nrm[idx[3 * t]] + nrm[idx[3 * t + 1]] + nrm[idx[3 * t + 2]]
		if face.dot(outward) > 0.0:
			wrong += 1
	return float(wrong) / maxf(1.0, idx.size() / 3)


static func _find(parent: Dictionary, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


static func _union(parent: Dictionary, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[maxi(ra, rb)] = mini(ra, rb)
