extends SceneTree

const Names := preload("res://name_generator.gd")

func _init() -> void:
	var seed_value := 1
	var count := 1
	var traits: Dictionary = Names.DEFAULT_TRAITS.duplicate()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			var raw := argument.trim_prefix("--seed=")
			if not raw.is_valid_int():
				_bad("seed must be an integer")
				return
			seed_value = raw.to_int()
		elif argument.begins_with("--count="):
			var raw := argument.trim_prefix("--count=")
			if not raw.is_valid_int() or raw.to_int() < 1 or raw.to_int() > 10000:
				_bad("count must be from 1 to 10000")
				return
			count = raw.to_int()
		elif argument.begins_with("--traits="):
			for pair in argument.trim_prefix("--traits=").split(","):
				var parts := pair.split(":")
				if parts.size() != 2 or not traits.has(parts[0]):
					_bad("traits must be comma-separated key:value pairs")
					return
				if parts[0] == "limbs":
					if not parts[1].is_valid_int():
						_bad("limbs must be an integer")
						return
					traits[parts[0]] = parts[1].to_int()
				else:
					traits[parts[0]] = parts[1]
		else:
			_bad("unknown option: " + argument)
			return
	if not Names.valid_traits(traits):
		_bad("invalid traits: diet, habitat, size, or limbs")
		return
	for row in Names.generate_many(seed_value, traits, count):
		print("%s | %s | %s | %s" % [row.genus, row.common, row.lineage, row.short])
	quit(0)

func _bad(message: String) -> void:
	printerr(message)
	quit(2)
