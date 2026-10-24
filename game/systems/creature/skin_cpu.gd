extends RefCounted
## Skin builder in GDScript (the baseline): naive Surface Nets (Gibson 1998) over the body field, normals from the
## field gradient, four bone weights per vertex from capsule contributions. Returns plain arrays and timings; it
## creates no nodes. Triangles wind clockwise seen from outside, Godot's front face.

const BodyField := preload("res://game/domain/creature/body_field.gd")
const SkinGrid := preload("res://game/systems/creature/skin_grid.gd")

## The 12 cell edges as pairs of corner numbers; corner c is at offset (c & 1, (c >> 1) & 1, (c >> 2) & 1).
const EDGES := [0, 1, 2, 3, 4, 5, 6, 7, 0, 2, 1, 3, 4, 6, 5, 7, 0, 4, 1, 5, 2, 6, 3, 7]
## Topology-fix passes; must match FIX_PASSES in surface_nets.glsl.
const FIX_PASSES := 6
## A fixed corner is set to ISO_P * FLIP_SCALE: just inside, so the surface passes through that grid point.
const FLIP_SCALE := 1.0001

static var _split: Array = []


## Returns {vertices, normals, bones, weights, custom0 (4 floats per vertex, BodyField.paint_coords), indices, dims, cell, ms: {field, nets, normals_weights, total}}.
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

	# 1. Field: each capsule adds f^3 to the points inside its support box (BodyField's p-norm blend).
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
						values[row + x] += f * f * f  # f^BLEND_P with BLEND_P = 3
	var t1 := Time.get_ticks_usec()

	var corner_offsets := PackedInt32Array([0, 1, nx, nx + 1, nxy, nxy + 1, nxy + nx, nxy + nx + 1])
	var iso := BodyField.ISO_P

	# 1b. Topology fix. Naive Surface Nets puts one vertex in each crossed cell, so a cell whose inside corners (or
	# outside corners) form two separate groups makes a non-manifold mesh. Such cells are joined: their strongest
	# outside corner is moved just inside. Each pass decides from the state at its start (the GPU does the same in
	# parallel), and passes repeat until nothing changes or FIX_PASSES is reached.
	var candidates := PackedInt32Array()
	for z in dims.z - 1:
		for y in dims.y - 1:
			var row := z * nxy + y * nx
			for x in dims.x - 1:
				var m := _mask(values, row + x, corner_offsets, iso)
				if m != 0 and m != 255:
					candidates.append(row + x)
	var fixes := 0
	var passes_used := 0
	for pass_i in FIX_PASSES:
		var flips := {}
		for base in candidates:
			var m := _mask(values, base, corner_offsets, iso)
			if not _split_table()[m]:
				continue
			var best := -1
			for c in 8:
				if (m >> c) & 1 == 0 and (best < 0 or values[base + corner_offsets[c]] > values[base + corner_offsets[best]]):
					best = c
			flips[base + corner_offsets[best]] = true
		if flips.is_empty():
			break
		passes_used += 1
		candidates = PackedInt32Array()
		var touched := {}
		for pnt in flips:
			values[pnt] = maxf(values[pnt], iso * FLIP_SCALE)
			fixes += 1
			for c in 8:
				var cb: int = pnt - corner_offsets[c]
				if cb >= 0 and not touched.has(cb):
					touched[cb] = true
					var cx := cb % nx
					var cy := (cb / nx) % dims.y
					var cz := cb / nxy
					if cx < dims.x - 1 and cy < dims.y - 1 and cz < dims.z - 1:
						candidates.append(cb)
		candidates.sort()

	# 2. One vertex per cell the surface crosses, at the mean of its edge crossings.
	var corner_pos := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0),
			Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1)])
	var cell_vertex := PackedInt32Array()
	cell_vertex.resize(n)
	cell_vertex.fill(-1)
	var vertices := PackedVector3Array()
	var corner_vals := PackedFloat32Array()
	corner_vals.resize(8)
	for z in dims.z - 1:
		for y in dims.y - 1:
			var row := z * nxy + y * nx
			for x in dims.x - 1:
				var base := row + x
				var mask := 0
				for c in 8:
					var sv := values[base + corner_offsets[c]]
					if sv > iso:
						mask |= 1 << c
				if mask == 0 or mask == 255:
					continue
				# Crossings are interpolated on the blended field F = S^(1/3), which is close to linear across a cell;
				# S itself is not, and would misplace vertices.
				for c in 8:
					corner_vals[c] = pow(values[base + corner_offsets[c]], 1.0 / 3.0) - BodyField.ISO
				var sum := Vector3.ZERO
				var count := 0
				for e in 12:
					var c0: int = EDGES[2 * e]
					var c1: int = EDGES[2 * e + 1]
					var v0 := corner_vals[c0]
					var v1 := corner_vals[c1]
					if (mask >> c0 & 1) != (mask >> c1 & 1):
						sum += corner_pos[c0].lerp(corner_pos[c1], clampf(v0 / (v0 - v1), 0.0, 1.0))
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
	var custom0 := PackedFloat32Array()
	var bone_count: int = desc.bone_count()
	for p in vertices:
		normals.append(field.normal(p, 0.25 * cell))
		var bw: Array = field.weights(p, bone_count)
		bones.append_array(bw[0])
		weights.append_array(bw[1])
		var pc: Vector4 = field.paint_coords(p)
		custom0.append_array([pc.x, pc.y, pc.z, pc.w])
	var t3 := Time.get_ticks_usec()
	return {"vertices": vertices, "normals": normals, "bones": bones, "weights": weights, "custom0": custom0,
			"indices": indices,
			"dims": dims, "cell": cell, "topology_fixes": fixes, "fix_passes_used": passes_used,
			"ms": {"field": (t1 - t0) / 1000.0, "nets": (t2 - t1) / 1000.0, "normals_weights": (t3 - t2) / 1000.0,
				"total": (t3 - t0) / 1000.0}}


## The gameplay skin: built at `divisions` and, if that is over `triangle_budget` triangles (round, bulky bodies have
## more surface per grid cell), rebuilt on a coarser grid. Triangles grow with divisions squared, so one estimate
## nearly always lands; a second step down is the fallback. Adds "divisions" to the result.
static func build_within(desc: RefCounted, divisions: int, triangle_budget: int) -> Dictionary:
	var d := divisions
	var out := build(desc, d)
	for attempt in 3:
		var tris: int = out["indices"].size() / 3
		if tris <= triangle_budget:
			break
		d = mini(d - 2, int(floor(d * sqrt(float(triangle_budget) / tris) * 0.97)))
		out = build(desc, d)
	out["divisions"] = d
	return out


static func _mask(values: PackedFloat32Array, base: int, corner_offsets: PackedInt32Array, iso: float) -> int:
	var m := 0
	for c in 8:
		if values[base + corner_offsets[c]] > iso:
			m |= 1 << c
	return m


## For each of the 256 corner masks: true if the inside corners or the outside corners form more than one group
## along cube edges (the cell would hold two surface pieces).
static func _split_table() -> Array:
	if _split.is_empty():
		for m in 256:
			_split.append(_groups(m, true) > 1 or _groups(m, false) > 1)
	return _split


static func _groups(m: int, inside: bool) -> int:
	var parent := [0, 1, 2, 3, 4, 5, 6, 7]
	for e in 12:
		var a: int = EDGES[2 * e]
		var b: int = EDGES[2 * e + 1]
		if bool((m >> a) & 1) == inside and bool((m >> b) & 1) == inside:
			var ra := a
			while parent[ra] != ra:
				ra = parent[ra]
			var rb := b
			while parent[rb] != rb:
				rb = parent[rb]
			parent[maxi(ra, rb)] = mini(ra, rb)
	var roots := {}
	for c in 8:
		if bool((m >> c) & 1) == inside:
			var r := c
			while parent[r] != r:
				r = parent[r]
			roots[r] = true
	return roots.size()


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
