extends SceneTree

const Generator = preload("res://voice_generator.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := 1
	var out_path := ""
	var matrix := false
	var traits := {"mass_kg": 40.0, "neck_length_m": 0.3, "mouth": "jaw", "diet": "carnivore", "mood": "threat"}
	for arg in args:
		if arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
		elif arg == "--matrix":
			matrix = true
		elif arg.begins_with("--traits="):
			for pair in arg.trim_prefix("--traits=").split(",", false):
				var bits := pair.split(":", false, 1)
				if bits.size() != 2 or not traits.has(bits[0]):
					printerr("invalid trait pair: ", pair)
					quit(2)
					return
				traits[bits[0]] = float(bits[1]) if bits[0] in ["mass_kg", "neck_length_m"] else bits[1]
	if matrix:
		var folder := out_path if out_path != "" else ProjectSettings.globalize_path("res://../../builds/creature_voice")
		DirAccess.make_dir_recursive_absolute(folder)
		var count := 0
		for mass in [10.0, 80.0, 400.0]:
			for mouth in Generator.MOUTHS:
				for mood in Generator.MOODS:
					var cell_traits := traits.duplicate()
					cell_traits["mass_kg"] = mass
					cell_traits["mouth"] = mouth
					cell_traits["mood"] = mood
					var path := folder.path_join("%03dkg_%s_%s.wav" % [int(mass), mouth, mood])
					if not _write(path, Generator.render(cell_traits, seed_value + count)):
						quit(2)
						return
					count += 1
		print("MATRIX: %d synthesized WAV files in %s" % [count, folder])
		quit(0)
		return
	if out_path == "":
		printerr("--out=PATH is required unless --matrix is set")
		quit(2)
		return
	quit(0 if _write(out_path, Generator.render(traits, seed_value)) else 2)


func _write(path: String, result: Dictionary) -> bool:
	if result.has("error"):
		printerr(result["error"])
		return false
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	var folder := absolute.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		printerr("cannot create output directory: ", folder)
		return false
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		printerr("cannot write WAV: ", absolute)
		return false
	file.store_buffer(result["wav"])
	file.close()
	print("WAV: %s (%d bytes)" % [absolute, result["wav"].size()])
	return true
