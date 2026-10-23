extends SceneTree

const TerrainChunk := preload("res://terrain_chunk.gd")
const TerrainMesh := preload("res://terrain_mesh.gd")

var failures := 0


func _init() -> void:
	var first: Dictionary = TerrainChunk.generate(1, 0, 0)
	var second: Dictionary = TerrainChunk.generate(1, 0, 0)
	check(first["heights"].to_byte_array() == second["heights"].to_byte_array()
		and first["biomes"] == second["biomes"], "same seed gives byte-identical arrays")
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
	var chunks := {}
	for cz in range(-1, 2):
		for cx in range(-1, 2):
			chunks[Vector2i(cx, cz)] = TerrainChunk.generate(1, cx, cz)
	var seams := true
	for cz in range(-1, 2):
		for cx in range(-1, 2):
			var center: Dictionary = chunks[Vector2i(cx, cz)]
			if cx < 1:
				var east: Dictionary = chunks[Vector2i(cx + 1, cz)]
				for z in range(33):
					seams = seams and center["heights"][z * 33 + 32] == east["heights"][z * 33]
			if cz < 1:
				var south: Dictionary = chunks[Vector2i(cx, cz + 1)]
				for x in range(33):
					seams = seams and center["heights"][32 * 33 + x] == south["heights"][x]
	check(seams, "all east/west and north/south shared edges match in 3x3 block")
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
	var times := PackedFloat32Array()
	for i in range(4):
		var started := Time.get_ticks_usec()
		TerrainChunk.generate(1, i, -i)
		times.append(float(Time.get_ticks_usec() - started) / 1000.0)
	times.sort()
	print("32-cell generation ms, sorted: ", times)
	check(times[1] < 20.0 and times[2] < 20.0, "median 32-cell chunk under 20 ms")
	print("FAILURES: ", failures)
	quit(1 if failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		printerr("FAIL: ", label)
		failures += 1
