extends RefCounted


static func build(chunk: Dictionary) -> ArrayMesh:
	var size: int = chunk["size"]
	var stride := size + 1
	var heights: PackedFloat32Array = chunk["heights"]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.resize(stride * stride)
	normals.resize(stride * stride)
	uvs.resize(stride * stride)
	indices.resize(size * size * 6)
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
	for z in range(size):
		for x in range(size):
			var i := z * size * 6 + x * 6
			var a := z * stride + x
			indices[i] = a
			indices[i + 1] = a + stride
			indices[i + 2] = a + 1
			indices[i + 3] = a + 1
			indices[i + 4] = a + stride
			indices[i + 5] = a + stride + 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
