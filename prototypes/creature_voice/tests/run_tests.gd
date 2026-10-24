extends SceneTree

const Generator = preload("res://voice_generator.gd")
var failures := 0


func _init() -> void:
	var traits := {"mass_kg": 40.0, "neck_length_m": 0.3, "mouth": "jaw", "diet": "carnivore", "mood": "threat"}
	var a: Dictionary = Generator.render(traits, 31)
	_check(not a.has("error"), "valid traits render")
	if a.has("error"):
		print("FAILURES: %d" % failures)
		quit(1)
		return
	_check(a["wav"] == Generator.render(traits, 31)["wav"], "same seed gives byte-identical WAV")
	_check(a["wav"] != Generator.render(traits, 32)["wav"], "seed changes output")
	var different_diet := traits.duplicate()
	different_diet["diet"] = "herbivore"
	_check(a["wav"] != Generator.render(different_diet, 31)["wav"], "diet changes timbre")
	_check(_header_ok(a["wav"], a["samples"].size()), "WAV is 44.1 kHz mono 16-bit PCM")
	var peak := 0.0
	var sum := 0.0
	var finite := true
	for sample in a["samples"]:
		finite = finite and is_finite(sample)
		peak = maxf(peak, absf(sample))
		sum += sample
	_check(finite, "all samples finite")
	_check(peak <= Generator.CEILING + 0.00001, "peak <= -1 dBFS")
	_check(absf(sum / a["samples"].size()) < 0.001, "DC offset below 0.001")
	_check(a["samples"][0] == 0.0 and a["samples"][-1] == 0.0, "five millisecond fades reach zero")
	_check(a["samples"].size() >= int(0.2 * Generator.RATE) and a["samples"].size() <= int(1.5 * Generator.RATE), "duration bounds")
	_check(Generator.render({"mass_kg": -2.0}, 1).has("error"), "invalid traits rejected")
	var light := traits.duplicate()
	light["mass_kg"] = 10.0
	light["mood"] = "idle"
	var heavy := light.duplicate()
	heavy["mass_kg"] = 400.0
	var light_samples: PackedFloat32Array = Generator.render(light, 9)["samples"]
	var heavy_samples: PackedFloat32Array = Generator.render(heavy, 9)["samples"]
	var light_hz := _pitch_hz(light_samples, int(0.15 * Generator.RATE))
	var heavy_hz := _pitch_hz(heavy_samples, int(0.15 * Generator.RATE))
	print("MASS FUNDAMENTALS: %.1f Hz / %.1f Hz" % [light_hz, heavy_hz])
	_check(light_hz > heavy_hz * 1.25, "10 kg fundamental measured higher than 400 kg")
	var centroids := []
	for mouth in Generator.MOUTHS:
		var variant := traits.duplicate()
		variant["mouth"] = mouth
		variant["mood"] = "idle"
		centroids.append(_centroid(Generator.render(variant, 9)["samples"]))
	print("MOUTH CENTROIDS: ", centroids)
	var distinct_centroids := true
	for i in centroids.size():
		for j in range(i + 1, centroids.size()):
			distinct_centroids = distinct_centroids and absf(centroids[i] - centroids[j]) > 100.0
	_check(distinct_centroids, "every mouth pair changes measured spectral centroid")
	var pain := traits.duplicate()
	pain["mood"] = "pain"
	var pain_samples: PackedFloat32Array = Generator.render(pain, 9)["samples"]
	var pain_start := _pitch_hz(pain_samples, int(0.14 * Generator.RATE))
	var pain_end := _pitch_hz(pain_samples, int(0.40 * Generator.RATE))
	print("PAIN FUNDAMENTAL: %.1f -> %.1f Hz" % [pain_start, pain_end])
	_check(pain_start > pain_end * 1.15, "pain ends lower in measured pitch")
	for mood in Generator.MOODS:
		var mood_traits := traits.duplicate()
		mood_traits["mood"] = mood
		var result: Dictionary = Generator.render(mood_traits, 3)
		_check(not result.has("error") and result["wav"].size() >= 44 + int(0.2 * Generator.RATE) * 2, "mood %s renders within duration" % mood)
	print("FAILURES: %d" % failures)
	quit(1 if failures else 0)


func _header_ok(wav: PackedByteArray, n: int) -> bool:
	return wav.size() == 44 + n * 2 and wav.slice(0, 4).get_string_from_ascii() == "RIFF" and wav.slice(8, 12).get_string_from_ascii() == "WAVE" and wav.decode_u16(20) == 1 and wav.decode_u16(22) == 1 and wav.decode_u32(24) == 44100 and wav.decode_u16(34) == 16


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)


func _pitch_hz(samples: PackedFloat32Array, center: int) -> float:
	var best := -INF
	var best_lag := 0
	var start := center - 700
	for lag in range(95, 750):
		var correlation := 0.0
		var left_power := 0.0
		var right_power := 0.0
		for i in range(0, 1200, 2):
			var left := samples[start + i]
			var right := samples[start + i + lag]
			correlation += left * right
			left_power += left * left
			right_power += right * right
		# Prefer the first strong periodicity over a multiple-period peak.
		var score := correlation / sqrt(maxf(0.000001, left_power * right_power)) - 0.0002 * lag
		if score > best:
			best = score
			best_lag = lag
	return float(Generator.RATE) / best_lag if best_lag > 0 else 0.0


func _centroid(samples: PackedFloat32Array) -> float:
	var size := 512
	var start := samples.size() / 2 - size / 2
	var sum_hz := 0.0
	var sum_magnitude := 0.0
	for bin in range(1, size / 2):
		var real := 0.0
		var imag := 0.0
		for i in size:
			var window := 0.5 - 0.5 * cos(TAU * i / float(size - 1))
			var angle := TAU * bin * i / float(size)
			real += samples[start + i] * window * cos(angle)
			imag -= samples[start + i] * window * sin(angle)
		var magnitude := sqrt(real * real + imag * imag)
		sum_hz += magnitude * bin * Generator.RATE / float(size)
		sum_magnitude += magnitude
	return sum_hz / maxf(0.00001, sum_magnitude)
