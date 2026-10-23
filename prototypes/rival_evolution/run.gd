extends SceneTree

const Simulation := preload("res://simulation.gd")


func _init() -> void:
	var seed_value := 1
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			var raw := argument.trim_prefix("--seed=")
			if not raw.is_valid_int():
				printerr("Seed must be an integer: ", raw)
				quit(2)
				return
			seed_value = raw.to_int()
	print(Simulation.run(seed_value, 20)["text"].trim_suffix("\n"))
	quit(0)
