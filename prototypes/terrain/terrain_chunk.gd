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
const FLOW_RADIUS := 6
const FLOW_THRESHOLD := 10
const RIVER_DEPTH := 0.14
const THERMAL_TALUS := 0.12
const THERMAL_RATE := 0.08
const OFFSETS := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]


static func generate(world_seed: int, cx: int, cz: int, size: int = 32) -> Dictionary:
	assert(size > 0)
	var stride := size + 1
	# The halo contains every possible origin of a six-step upstream path and
	# the one-cell footprint of the thermal pass. Every lookup uses world coordinates.
	var pad := FLOW_RADIUS + 3
	var span := stride + 2 * pad
	var base := PackedFloat32Array()
	var eroded := PackedFloat32Array()
	var downhill := PackedInt32Array()
	var accumulation := PackedInt32Array()
	base.resize(span * span)
	eroded.resize(span * span)
	downhill.resize(span * span)
	accumulation.resize(span * span)
	for pz in range(span):
		for px in range(span):
			var wx := cx * size + px - pad
			var wz := cz * size + pz - pad
			base[pz * span + px] = _fractal(float(wx) / 42.0, float(wz) / 42.0,
				world_seed ^ HEIGHT_SEED, 4) * 10.0
	for pz in range(1, span - 1):
		for px in range(1, span - 1):
			var i := pz * span + px
			var value := base[i]
			var delta := 0.0
			for neighbor in range(4):
				var offset: Vector2i = OFFSETS[neighbor]
				var other: float = base[(pz + offset.y) * span + px + offset.x]
				var difference: float = other - value
				if absf(difference) > THERMAL_TALUS:
					delta += signf(difference) * (absf(difference) - THERMAL_TALUS) * THERMAL_RATE
			eroded[i] = clampf(value + delta, -10.0, 10.0)
	for i in range(downhill.size()):
		downhill[i] = -1
		accumulation[i] = 1
	for pz in range(2, span - 2):
		for px in range(2, span - 2):
			var i := pz * span + px
			var lowest_neighbor: float = eroded[i]
			for direction in range(OFFSETS.size()):
				var offset: Vector2i = OFFSETS[direction]
				var next: int = (pz + offset.y) * span + px + offset.x
				if eroded[next] < lowest_neighbor - 0.000001:
					lowest_neighbor = eroded[next]
					downhill[i] = next
	# A bounded upstream footprint makes accumulation local and chunk-order independent.
	for pz in range(pad - FLOW_RADIUS, pad + size + FLOW_RADIUS + 1):
		for px in range(pad - FLOW_RADIUS, pad + size + FLOW_RADIUS + 1):
			var cursor := pz * span + px
			for step in range(FLOW_RADIUS):
				cursor = downhill[cursor]
				if cursor < 0:
					break
				accumulation[cursor] += 1
	var heights := PackedFloat32Array()
	var thermal_heights := PackedFloat32Array()
	var rivers := PackedByteArray()
	var river_flow := PackedInt32Array()
	heights.resize(stride * stride)
	thermal_heights.resize(stride * stride)
	rivers.resize(stride * stride)
	river_flow.resize(stride * stride)
	var lowest := INF
	var highest := -INF
	for z in range(stride):
		for x in range(stride):
			var i := (z + pad) * span + x + pad
			var output := z * stride + x
			thermal_heights[output] = eroded[i]
			rivers[output] = int(eroded[i] > -2.5 and accumulation[i] >= FLOW_THRESHOLD)
			heights[output] = _carved_height(i, eroded, accumulation)
			river_flow[output] = -1
			if rivers[output] != 0:
				var best: float = heights[output]
				for direction in range(OFFSETS.size()):
					var offset: Vector2i = OFFSETS[direction]
					var next := i + offset.y * span + offset.x
					var next_is_channel: bool = eroded[next] <= -2.5 or (
						eroded[next] > -2.5 and accumulation[next] >= FLOW_THRESHOLD)
					if not next_is_channel:
						continue
					var next_height := _carved_height(next, eroded, accumulation)
					if next_height < best - 0.000001:
						best = next_height
						river_flow[output] = direction
			# Report extrema of the stored float32 samples, not transient float64 values.
			lowest = minf(lowest, heights[output])
			highest = maxf(highest, heights[output])
	var biomes := PackedByteArray()
	biomes.resize(size * size)
	for z in range(size):
		for x in range(size):
			var index := z * stride + x
			var elevation := (heights[index] + heights[index + 1] + heights[index + stride] + heights[index + stride + 1]) * 0.25
			var moisture := _fractal(float(cx * size + x) / 37.0, float(cz * size + z) / 37.0, world_seed ^ MOISTURE_SEED, 3)
			biomes[z * size + x] = _biome(elevation, moisture)
	return {
		"cx": cx, "cz": cz, "size": size, "heights": heights,
		"thermal_heights": thermal_heights, "biomes": biomes,
		"rivers": rivers, "river_flow": river_flow,
		"min_height": lowest, "max_height": highest,
	}


static func _carved_height(index: int, eroded: PackedFloat32Array,
		accumulation: PackedInt32Array) -> float:
	var height: float = eroded[index]
	if height > -2.5 and accumulation[index] >= FLOW_THRESHOLD:
		return height - RIVER_DEPTH
	return height


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
	# Integer mixing uses a common public-domain hash. No library or random stream.
	var bits := ((seed & 0x7FFFFFFF) + x * 374761393 + z * 668265263) & 0x7FFFFFFF
	bits = (bits ^ (bits >> 13)) & 0x7FFFFFFF
	bits = (bits * 1274126177) & 0x7FFFFFFF
	bits = (bits ^ (bits >> 16)) & 0x7FFFFFFF
	return float(bits) / 1073741823.5 - 1.0
