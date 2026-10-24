extends RefCounted


static func build(chunk: Dictionary, step: int = 1) -> ArrayMesh:
	var size: int = chunk["size"]
	assert(step == 1 or step == 2 or step == 4)
	var stride := size + 1
	var heights: PackedFloat32Array = chunk["heights"]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.resize(stride * stride)
	normals.resize(stride * stride)
	uvs.resize(stride * stride)
	for z in range(stride):
		for x in range(stride):
			var i := z * stride + x
			vertices[i] = Vector3(float(x), heights[i], float(z))
			uvs[i] = Vector2(float(x) / size, float(z) / size)
			var left: float = heights[z * stride + maxi(0, x - 1)]
			var right: float = heights[z * stride + mini(size, x + 1)]
			var back: float = heights[maxi(0, z - 1) * stride + x]
			var front: float = heights[mini(size, z + 1) * stride + x]
			normals[i] = Vector3(left - right, 2.0, back - front).normalized()
	# Each coarse cell is a convex x/z polygon. Cells on the outer boundary
	# retain every height sample along that edge, stitching a full-detail neighbour.
	for z0 in range(0, size, step):
		var z1 := mini(size, z0 + step)
		for x0 in range(0, size, step):
			var x1 := mini(size, x0 + step)
			var polygon: Array[int] = []
			if z0 == 0:
				for x in range(x0, x1 + 1):
					polygon.append(z0 * stride + x)
			else:
				polygon.append(z0 * stride + x0)
				polygon.append(z0 * stride + x1)
			if x1 == size:
				for z in range(z0 + 1, z1 + 1):
					polygon.append(z * stride + x1)
			else:
				polygon.append(z1 * stride + x1)
			if z1 == size:
				for x in range(x1 - 1, x0 - 1, -1):
					polygon.append(z1 * stride + x)
			else:
				polygon.append(z1 * stride + x0)
			if x0 == 0:
				for z in range(z1 - 1, z0, -1):
					polygon.append(z * stride + x0)
			for i in range(1, polygon.size() - 1):
				indices.append(polygon[0])
				indices.append(polygon[i + 1])
				indices.append(polygon[i])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
