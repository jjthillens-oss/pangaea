extends RefCounted
## Grid layout shared by the GDScript and compute-shader skin builders, so both sample the same points.

## Returns {origin: Vector3, cell: float, dims: Vector3i}. The grid covers the body's sphere box plus a margin, so
## the surface never touches the grid edge and the mesh closes. The blend swells the surface past the vertebra
## spheres where capsules overlap: with up to three overlapping, at most 1.09 r (BodyField), so the margin is
## 0.15 of the largest radius plus two cells.
static func layout(desc: RefCounted, divisions: int) -> Dictionary:
	var box: AABB = desc.bounds_m()
	var cell: float = box.get_longest_axis_size() / float(divisions)
	var r_max := 0.0
	for i in desc.vertebrae.size():
		r_max = maxf(r_max, desc.radius_m(i))
	var margin := 0.15 * r_max + 2.0 * cell
	var origin := box.position - Vector3.ONE * margin
	var size := box.size + Vector3.ONE * 2.0 * margin
	var dims := Vector3i(int(ceil(size.x / cell)) + 1, int(ceil(size.y / cell)) + 1, int(ceil(size.z / cell)) + 1)
	return {"origin": origin, "cell": cell, "dims": dims}
