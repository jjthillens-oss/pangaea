extends RefCounted
## PROPOSED offline creature-call synthesizer. No game code or recorded audio is used.

const RATE := 44100
const CEILING := 0.8912509 # -1 dBFS
const TAU := PI * 2.0
const MOODS := ["idle", "alert", "threat", "pain", "call"]
const MOUTHS := ["beak", "jaw", "proboscis", "none"]
const DIETS := ["herbivore", "carnivore", "omnivore"]


static func validate_traits(traits: Dictionary) -> String:
	if not traits.has_all(["mass_kg", "neck_length_m", "mouth", "diet", "mood"]):
		return "traits need mass_kg, neck_length_m, mouth, diet, mood"
	if not (traits["mass_kg"] is float or traits["mass_kg"] is int) or float(traits["mass_kg"]) < 1.0 or float(traits["mass_kg"]) > 10000.0:
		return "mass_kg must be 1..10000"
	if not (traits["neck_length_m"] is float or traits["neck_length_m"] is int) or float(traits["neck_length_m"]) < 0.0 or float(traits["neck_length_m"]) > 10.0:
		return "neck_length_m must be 0..10"
	if not MOUTHS.has(traits["mouth"]) or not DIETS.has(traits["diet"]) or not MOODS.has(traits["mood"]):
		return "unknown mouth, diet or mood"
	return ""


static func fundamental(mass_kg: float) -> float:
	return clampf(240.0 * pow(mass_kg / 10.0, -0.25), 65.0, 360.0)


static func pitch_factor(mood: String, position: float) -> float:
	match mood:
		"pain": return lerpf(1.35, 0.68, position)
		"threat": return 0.82 + 0.025 * sin(TAU * 18.0 * position)
		"alert": return lerpf(1.05, 1.25, position)
		"call": return 1.0 + 0.10 * sin(TAU * 3.0 * position)
		_: return 1.0


static func _duration(mood: String) -> float:
	match mood:
		"idle": return 0.35
		"alert": return 0.48
		"threat": return 0.75
		"pain": return 0.56
		_: return 0.93


static func render(traits: Dictionary, seed_value: int) -> Dictionary:
	var error := validate_traits(traits)
	if error != "":
		return {"error": error}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(round(_duration(traits["mood"]) * RATE))
	var samples := PackedFloat32Array()
	samples.resize(n)
	var f0 := fundamental(float(traits["mass_kg"]))
	var neck := float(traits["neck_length_m"])
	var diet_brightness: float = float({"herbivore": 0.92, "omnivore": 1.0, "carnivore": 1.08}[traits["diet"]])
	var formant_1 := 850.0 * diet_brightness / (1.0 + 0.45 * neck)
	var formant_2 := 1800.0 * diet_brightness / (1.0 + 0.45 * neck)
	var phase := 0.0
	var click_period := maxi(1, int(RATE / f0))
	var prior_noise := 0.0
	for i in n:
		var t := float(i) / float(n - 1)
		var pitch := f0 * pitch_factor(traits["mood"], t)
		phase += TAU * pitch / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		var voiced := 0.0
		for harmonic in range(1, 10):
			var hz := pitch * harmonic
			var weight := exp(-pow((hz - formant_1) / 440.0, 2.0)) + 0.55 * exp(-pow((hz - formant_2) / 600.0, 2.0))
			voiced += sin(phase * harmonic) * weight / float(harmonic)
		var source := 0.0
		match traits["mouth"]:
			"jaw": source = voiced + (0.02 if traits["diet"] == "herbivore" else 0.06) * noise
			"beak": source = 0.15 * voiced + (noise - prior_noise) * (1.0 if i % click_period < 14 else 0.08)
			"proboscis": source = 0.9 * voiced + 0.22 * sin(phase * 2.0) + 0.06 * noise
			"none": source = 0.08 * voiced + 0.3 * (noise + prior_noise)
		prior_noise = noise
		var shape := sin(PI * t)
		if traits["mood"] == "call":
			shape *= pow(absf(sin(PI * 3.0 * t)), 0.8)
		elif traits["mood"] == "threat":
			shape *= 0.65 + 0.35 * absf(sin(TAU * 17.0 * t))
		elif traits["mood"] == "pain":
			shape *= 1.0 - 0.35 * t
		samples[i] = source * shape
	# Mean removal, mandatory 5 ms fades, and one final peak normalization.
	var mean := 0.0
	for s in samples:
		mean += s
	mean /= n
	var fade := int(RATE * 0.005)
	var peak := 0.0
	for i in n:
		var edge := minf(1.0, minf(float(i) / fade, float(n - 1 - i) / fade))
		samples[i] = (samples[i] - mean) * edge
		peak = maxf(peak, absf(samples[i]))
	if peak > 0.0:
		for i in n:
			samples[i] *= (CEILING * 0.995) / peak
	return {"samples": samples, "wav": encode_wav(samples), "f0_start": f0 * pitch_factor(traits["mood"], 0.1), "f0_end": f0 * pitch_factor(traits["mood"], 0.9), "formants_hz": [formant_1, formant_2]}


static func _u16(bytes: PackedByteArray, value: int) -> void:
	bytes.append(value & 255)
	bytes.append((value >> 8) & 255)


static func _u32(bytes: PackedByteArray, value: int) -> void:
	for shift in [0, 8, 16, 24]:
		bytes.append((value >> shift) & 255)


static func encode_wav(samples: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.append_array("RIFF".to_ascii_buffer())
	_u32(bytes, 36 + samples.size() * 2)
	bytes.append_array("WAVEfmt ".to_ascii_buffer())
	_u32(bytes, 16)
	_u16(bytes, 1)
	_u16(bytes, 1)
	_u32(bytes, RATE)
	_u32(bytes, RATE * 2)
	_u16(bytes, 2)
	_u16(bytes, 16)
	bytes.append_array("data".to_ascii_buffer())
	_u32(bytes, samples.size() * 2)
	for sample in samples:
		_u16(bytes, clampi(int(round(sample * 32767.0)), -32768, 32767))
	return bytes
