extends SceneTree

const TerrainChunk := preload("res://terrain_chunk.gd")


func _init() -> void:
	var seed_value := 1
	var radius := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--radius="):
			radius = int(arg.trim_prefix("--radius="))
	if radius < 0 or radius > 16:
		printerr("radius must be 0..16")
		quit(1)
		return
	var chunks := {}
	var histogram := PackedInt32Array()
	histogram.resize(TerrainChunk.BIOME_NAMES.size())
	for cz in range(-radius, radius + 1):
		for cx in range(-radius, radius + 1):
			var started := Time.get_ticks_usec()
			var chunk: Dictionary = TerrainChunk.generate(seed_value, cx, cz)
			var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
			print("chunk (%d,%d): %.3f ms, height %.3f..%.3f" % [cx, cz, elapsed_ms, chunk["min_height"], chunk["max_height"]])
			chunks[Vector2i(cx, cz)] = chunk
			for biome in chunk["biomes"]:
				histogram[biome] += 1
	print("biomes:")
	for i in range(histogram.size()):
		print("  %s: %d" % [TerrainChunk.BIOME_NAMES[i], histogram[i]])
	var output := ProjectSettings.globalize_path("res://../../builds/terrain/preview_%d.ppm" % seed_value).simplify_path()
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("cannot write preview: ", output)
		quit(1)
		return
	var width := (radius * 2 + 1) * 32
	file.store_line("P3")
	file.store_line("%d %d" % [width, width])
	file.store_line("255")
	for row in range(width):
		var cz := floori(float(row) / 32.0) - radius
		var local_z := row % 32
		var values := PackedStringArray()
		for column in range(width):
			var cx := floori(float(column) / 32.0) - radius
			var local_x := column % 32
			var chunk: Dictionary = chunks[Vector2i(cx, cz)]
			var height: float = chunk["heights"][local_z * 33 + local_x]
			var gray := clampi(roundi((height + 10.0) * 12.75), 0, 255)
			values.append("%d %d %d" % [gray, gray, gray])
		file.store_line(" ".join(values))
	file.close()
	print("preview: ", output)
	quit()
