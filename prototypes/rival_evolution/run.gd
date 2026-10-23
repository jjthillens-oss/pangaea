extends SceneTree

const Simulation := preload("res://simulation.gd")

func _init() -> void:
	var seed_value := 1
	var generations := 20
	var species_count := 4
	var as_csv := false
	var as_summary := false
	for argument in OS.get_cmdline_user_args():
		if argument == "--csv":
			as_csv = true
		elif argument == "--summary":
			as_summary = true
		elif argument.begins_with("--seed="):
			var raw := argument.trim_prefix("--seed=")
			if not raw.is_valid_int():
				_bad("seed must be an integer")
				return
			seed_value = raw.to_int()
		elif argument.begins_with("--generations="):
			var raw := argument.trim_prefix("--generations=")
			if not raw.is_valid_int() or raw.to_int() < 1:
				_bad("generations must be a positive integer")
				return
			generations = raw.to_int()
		elif argument.begins_with("--species="):
			var raw := argument.trim_prefix("--species=")
			if not raw.is_valid_int() or raw.to_int() < 3 or raw.to_int() > 5:
				_bad("species must be 3, 4, or 5")
				return
			species_count = raw.to_int()
		else:
			_bad("unknown option: " + argument)
			return
	var result: Dictionary = Simulation.run(seed_value, generations, species_count)
	if as_summary:
		print(Simulation.summary(result["species"]).trim_suffix("\n"))
	elif as_csv:
		print(Simulation.csv(result["history"]).trim_suffix("\n"))
	else:
		print(result["text"].trim_suffix("\n"))
	quit(0)

func _bad(message: String) -> void:
	printerr(message)
	quit(2)

