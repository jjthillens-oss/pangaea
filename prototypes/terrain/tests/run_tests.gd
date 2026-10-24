extends SceneTree

const TerrainChunk := preload("res://terrain_chunk.gd")
const TerrainMesh := preload("res://terrain_mesh.gd")

var failures := 0


func _init() -> void:
	var first: Dictionary = TerrainChunk.generate(1, 0, 0)
	var second: Dictionary = TerrainChunk.generate(1, 0, 0)
	check(first["heights"].to_byte_array() == second["heights"].to_byte_array()
		and first["thermal_heights"].to_byte_array() == second["thermal_heights"].to_byte_array()
		and first["biomes"] == second["biomes"] and first["rivers"] == second["rivers"]
		and first["river_flow"] == second["river_flow"], "same seed gives byte-identical arrays")
	var changed: Dictionary = TerrainChunk.generate(2, 0, 0)
	check(first["heights"] != changed["heights"], "different world seed changes heights")
	check(first["heights"] is PackedFloat32Array and first["heights"].size() == 1089
		and first["biomes"] is PackedByteArray and first["biomes"].size() == 1024,
		"32-cell chunk has 33x33 heights and 32x32 biome ids")
	var bounds := true
	var range_match := true
	var low := INF
	var high := -INF
	for height in first["heights"]:
		bounds = bounds and is_finite(height) and height >= -10.01 and height <= 10.01
		low = minf(low, height)
		high = maxf(high, height)
	range_match = low == first["min_height"] and high == first["max_height"]
	check(bounds and range_match, "finite height bounds and reported extrema")
	var original_roughness := 0.0
	var final_roughness := 0.0
	var raised_sites := 0
	var lowered_sites := 0
	for z in range(32):
		for x in range(32):
			var base: float = TerrainChunk._fractal(float(x) / 42.0, float(z) / 42.0,
				1 ^ TerrainChunk.HEIGHT_SEED, 4) * 10.0
			var base_right: float = TerrainChunk._fractal(float(x + 1) / 42.0, float(z) / 42.0,
				1 ^ TerrainChunk.HEIGHT_SEED, 4) * 10.0
			var base_down: float = TerrainChunk._fractal(float(x) / 42.0, float(z + 1) / 42.0,
				1 ^ TerrainChunk.HEIGHT_SEED, 4) * 10.0
			var i := z * 33 + x
			original_roughness += absf(base - base_right) + absf(base - base_down)
			final_roughness += absf(first["thermal_heights"][i] - first["thermal_heights"][i + 1])
			final_roughness += absf(first["thermal_heights"][i] - first["thermal_heights"][i + 33])
			if first["thermal_heights"][i] > base + 0.001:
				raised_sites += 1
			elif first["thermal_heights"][i] < base - 0.001:
				lowered_sites += 1
	print("thermal sites raised/lowered: %d/%d, roughness: %.3f -> %.3f" % [
		raised_sites, lowered_sites, original_roughness, final_roughness])
	check(raised_sites > 0 and lowered_sites > 0 and final_roughness < original_roughness,
		"thermal pass deposits and softens slopes")
	var chunks := {}
	for cz in range(-1, 2):
		for cx in range(-1, 2):
			chunks[Vector2i(cx, cz)] = TerrainChunk.generate(1, cx, cz)
	var seams := true
	var river_seams := true
	var border_river_count := 0
	for cz in range(-1, 2):
		for cx in range(-1, 2):
			var center: Dictionary = chunks[Vector2i(cx, cz)]
			if cx < 1:
				var east: Dictionary = chunks[Vector2i(cx + 1, cz)]
				for z in range(33):
					seams = seams and center["heights"][z * 33 + 32] == east["heights"][z * 33]
					river_seams = river_seams and center["rivers"][z * 33 + 32] == east["rivers"][z * 33]
					border_river_count += center["rivers"][z * 33 + 32]
			if cx > -1:
				var west: Dictionary = chunks[Vector2i(cx - 1, cz)]
				for z in range(33):
					seams = seams and center["heights"][z * 33] == west["heights"][z * 33 + 32]
					river_seams = river_seams and center["rivers"][z * 33] == west["rivers"][z * 33 + 32]
			if cz < 1:
				var south: Dictionary = chunks[Vector2i(cx, cz + 1)]
				for x in range(33):
					seams = seams and center["heights"][32 * 33 + x] == south["heights"][x]
					river_seams = river_seams and center["rivers"][32 * 33 + x] == south["rivers"][x]
					border_river_count += center["rivers"][32 * 33 + x]
			if cz > -1:
				var north: Dictionary = chunks[Vector2i(cx, cz - 1)]
				for x in range(33):
					seams = seams and center["heights"][x] == north["heights"][32 * 33 + x]
					river_seams = river_seams and center["rivers"][x] == north["rivers"][32 * 33 + x]
	check(seams, "all four shared-edge directions match in 3x3 block")
	check(river_seams and border_river_count > 0, "river channels continue across chunk borders")
	var river_cells := 0
	var downhill_rivers := true
	for cz in range(-1, 2):
		for cx in range(-1, 2):
			var chunk: Dictionary = chunks[Vector2i(cx, cz)]
			for z in range(33):
				for x in range(33):
					var i := z * 33 + x
					if chunk["rivers"][i] == 0:
						continue
					river_cells += 1
					var direction: int = chunk["river_flow"][i]
					if direction < 0:
						continue # A closed local basin is a proposed lake endpoint.
					var offset: Vector2i = TerrainChunk.OFFSETS[direction]
					var nx := x + offset.x
					var nz := z + offset.y
					var neighbor: Dictionary = chunk
					if nx < 0 and cx > -1:
						neighbor = chunks[Vector2i(cx - 1, cz)]
						nx += 32
					elif nx > 32 and cx < 1:
						neighbor = chunks[Vector2i(cx + 1, cz)]
						nx -= 32
					if nz < 0 and cz > -1:
						neighbor = chunks[Vector2i(cx, cz - 1)]
						nz += 32
					elif nz > 32 and cz < 1:
						neighbor = chunks[Vector2i(cx, cz + 1)]
						nz -= 32
					if nx >= 0 and nx <= 32 and nz >= 0 and nz <= 32:
						var next_index := nz * 33 + nx
						downhill_rivers = downhill_rivers and neighbor["heights"][next_index] < chunk["heights"][i]
						downhill_rivers = downhill_rivers and (neighbor["rivers"][next_index] != 0
						or neighbor["heights"][next_index] <= -2.5)
	check(river_cells > 0 and downhill_rivers, "river flow never rises and has lake endpoints")
	var biome_ids := {}
	for cz in range(-2, 3):
		for cx in range(-2, 3):
			var chunk: Dictionary = TerrainChunk.generate(1, cx, cz)
			for biome in chunk["biomes"]:
				biome_ids[biome] = true
	check(biome_ids.size() == 6, "seed 1 spans all six biomes in 5x5 block")
	var mesh := TerrainMesh.build(first)
	check(mesh.get_surface_count() == 1 and mesh.surface_get_array_len(0) == 1089
		and mesh.surface_get_array_index_len(0) == 6144,
		"mesh has 2048 triangles and all height vertices")
	var full_vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lod_ok := true
	for step in [2, 4]:
		var lod := TerrainMesh.build(first, step)
		var arrays := lod.surface_get_arrays(0)
		var lod_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var referenced := {}
		for index in arrays[Mesh.ARRAY_INDEX]:
			referenced[index] = true
		lod_ok = lod_ok and arrays[Mesh.ARRAY_INDEX].size() < mesh.surface_get_array_index_len(0)
		for edge in range(33):
			for index in [edge, 32 * 33 + edge, edge * 33, edge * 33 + 32]:
				lod_ok = lod_ok and referenced.has(index)
				lod_ok = lod_ok and lod_vertices[index].distance_to(full_vertices[index]) <= 0.000001
	check(lod_ok, "LOD steps 2 and 4 stitch every full-detail boundary vertex")
	var times := PackedFloat32Array()
	for i in range(4):
		var started := Time.get_ticks_usec()
		TerrainChunk.generate(1, i, -i)
		times.append(float(Time.get_ticks_usec() - started) / 1000.0)
	times.sort()
	print("32-cell generation ms, sorted: ", times)
	check(times[1] < 40.0 and times[2] < 40.0, "median 32-cell chunk with rivers under 40 ms")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		printerr("FAIL: ", label)
		failures += 1
