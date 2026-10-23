extends RefCounted

# PROPOSED tuning. Biome ids are stable within this isolated prototype only.
const SEA := 0
const SHORE := 1
const GRASS := 2
const FOREST := 3
const ROCK := 4
const SNOW := 5
const BIOME_NAMES := ["sea", "shore", "grass", "forest", "rock", "snow"]

const HEIGHT_SEED := 0x13579B
const MOISTURE_SEED := 0x2468AC


static func generate(world_seed: int, cx: int, cz: int, size: int = 32) -> Dictionary:
	assert(size > 0)
	var stride := size + 1
	var heights := PackedFloat32Array()
	heights.resize(stride * stride)
	var lowest := INF
	var highest := -INF
	for z in range(stride):
		var world_z := cz * size + z
		for x in range(stride):
			var world_x := cx * size + x
			var height := _fractal(float(world_x) / 42.0, float(world_z) / 42.0, world_seed ^ HEIGHT_SEED, 4) * 10.0
			heights[z * stride + x] = height
			# Report extrema of the stored float32 samples, not transient float64 values.
			lowest = minf(lowest, heights[z * stride + x])
			highest = maxf(highest, heights[z * stride + x])
	var biomes := PackedByteArray()
	biomes.resize(size * size)
	for z in range(size):
		for x in range(size):
			var index := z * stride + x
			var elevation := (heights[index] + heights[index + 1] + heights[index + stride] + heights[index + stride + 1]) * 0.25
			var moisture := _fractal(float(cx * size + x) / 37.0, float(cz * size + z) / 37.0, world_seed ^ MOISTURE_SEED, 3)
			biomes[z * size + x] = _biome(elevation, moisture)
	return {
		"cx": cx, "cz": cz, "size": size, "heights": heights, "biomes": biomes,
		"min_height": lowest, "max_height": highest,
	}


static func _biome(height: float, moisture: float) -> int:
	if height < -2.5:
		return SEA
	if height < -0.7:
		return SHORE
	if height > 5.0:
		return SNOW
	if height > 3.0:
		return ROCK
	if moisture > 0.05:
		return FOREST
	return GRASS


static func _fractal(x: float, z: float, seed: int, octaves: int) -> float:
	var value := 0.0
	var weight := 1.0
	var total := 0.0
	for octave in range(octaves):
		value += _value_noise(x, z, seed + octave * 7919) * weight
		total += weight
		x *= 2.0
		z *= 2.0
		weight *= 0.5
	return value / total


static func _value_noise(x: float, z: float, seed: int) -> float:
	var x0 := floori(x)
	var z0 := floori(z)
	var fx := x - float(x0)
	var fz := z - float(z0)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var bottom := lerpf(_corner(x0, z0, seed), _corner(x0 + 1, z0, seed), fx)
	var top := lerpf(_corner(x0, z0 + 1, seed), _corner(x0 + 1, z0 + 1, seed), fx)
	return lerpf(bottom, top, fz)


static func _corner(x: int, z: int, seed: int) -> float:
	# Integer mixing, derived here for this prototype. No library or random stream.
	var bits := ((seed & 0x7FFFFFFF) + x * 374761393 + z * 668265263) & 0x7FFFFFFF
	bits = (bits ^ (bits >> 13)) & 0x7FFFFFFF
	bits = (bits * 1274126177) & 0x7FFFFFFF
	bits = (bits ^ (bits >> 16)) & 0x7FFFFFFF
	return float(bits) / 1073741823.5 - 1.0
