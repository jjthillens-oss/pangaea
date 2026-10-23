extends RefCounted
## PROPOSED tuning for an isolated rival evolution experiment.

const MOUTHS := ["filter", "graze", "bite"]
const SPECIES := ["Drifters", "Grazers", "Runners", "Hunters"]
const SIZE_MIN := 1
const SIZE_MAX := 5
const SPEED_MIN := 1
const SPEED_MAX := 5
const SPIKES_MIN := 0
const SPIKES_MAX := 3


static func initial_species() -> Array[Dictionary]:
	return [
		{"id": 0, "name": "Drifters", "size": 2, "speed": 2, "mouth": 0, "spikes": 0},
		{"id": 1, "name": "Grazers", "size": 3, "speed": 2, "mouth": 1, "spikes": 0},
		{"id": 2, "name": "Runners", "size": 2, "speed": 4, "mouth": 1, "spikes": 1},
		{"id": 3, "name": "Hunters", "size": 4, "speed": 3, "mouth": 2, "spikes": 1},
	]


static func run(seed_value: int, generation_count: int = 20) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var species := initial_species()
	var history: Array = []
	var lines: PackedStringArray = []
	for generation in range(1, generation_count + 1):
		lines.append("Generation %d" % generation)
		var outcomes: Array[Dictionary] = []
		# Stable id order is the tie breaker for every aggregate and journal entry.
		for rival in species:
			var food: int = rng.randi_range(0, 3) + int(rival["mouth"] == 0)
			var pressure: int = rng.randi_range(0, 4)
			var defense: int = int(rival["speed"]) / 2 + int(rival["spikes"])
			var deaths: int = maxi(0, pressure - defense)
			outcomes.append({"id": rival["id"], "food": food, "deaths": deaths})
		for outcome in outcomes:
			var rival: Dictionary = species[int(outcome["id"])]
			var changes: PackedStringArray = []
			if int(outcome["deaths"]) >= 2:
				if int(rival["spikes"]) < SPIKES_MAX:
					rival["spikes"] += 1
					changes.append("grew spikes after heavy predation")
				elif int(rival["speed"]) < SPEED_MAX:
					rival["speed"] += 1
					changes.append("became faster after heavy predation")
			elif int(outcome["food"]) == 0:
				if int(rival["mouth"]) > 0:
					rival["mouth"] -= 1
					changes.append("shifted toward filtering after finding no food")
				elif int(rival["size"]) > SIZE_MIN:
					rival["size"] -= 1
					changes.append("became smaller after finding no food")
			elif int(outcome["food"]) >= 3:
				if int(rival["size"]) < SIZE_MAX:
					rival["size"] += 1
					changes.append("became larger after abundant feeding")
				elif int(rival["mouth"]) < MOUTHS.size() - 1:
					rival["mouth"] += 1
					changes.append("developed a stronger mouth after abundant feeding")
			if changes.is_empty():
				lines.append("  %s kept their traits (food %d, losses %d)." % [rival["name"], outcome["food"], outcome["deaths"]])
			else:
				for change in changes:
					lines.append("  %s %s (food %d, losses %d)." % [rival["name"], change, outcome["food"], outcome["deaths"]])
			history.append(rival.duplicate(true))
	return {"text": "\n".join(lines) + "\n", "history": history, "species": species}
