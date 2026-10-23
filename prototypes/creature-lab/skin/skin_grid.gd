extends RefCounted
## Grid layout shared by the GDScript and compute-shader skin builders, so both sample the same points.

## Returns {origin: Vector3, cell: float, dims: Vector3i}. The grid covers the body's surface box plus two cells on
## every side, so the surface never touches the grid edge and the mesh closes.
static func layout(desc: RefCounted, divisions: int) -> Dictionary:
	var box: AABB = desc.bounds_m()
	var cell: float = box.get_longest_axis_size() / float(divisions)
	var origin := box.position - Vector3.ONE * 2.0 * cell
	var size := box.size + Vector3.ONE * 4.0 * cell
	var dims := Vector3i(int(ceil(size.x / cell)) + 1, int(ceil(size.y / cell)) + 1, int(ceil(size.z / cell)) + 1)
	return {"origin": origin, "cell": cell, "dims": dims}
