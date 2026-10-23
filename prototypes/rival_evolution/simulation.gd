extends RefCounted
## PROPOSED isolated rules, based on game/data/part_catalog.json and creatures_m1.json.
const PARTS := {"mouth_filter": [10, 1], "mouth_jaw": [15, 1], "flagellum": [15, 3], "cilia": [10, 3], "spike": [15, 4], "eye_spot": [10, 3]}
const MAX_PARTS := 8
const MIN_SCALE := 0.5
const MAX_SCALE := 2.0
const COOLDOWN := 3
const POP_CAP := 24
const FOOD_CAP := 36
const FOOD_REGROW := 24
const TEMPLATES := [
	["Grazers", "grazer", 1.0, ["mouth_filter", "flagellum", "eye_spot"]],
	["Hunters", "hunter", 1.4, ["mouth_jaw", "flagellum", "flagellum"]],
	["Runners", "grazer", 0.8, ["mouth_filter", "flagellum", "flagellum"]],
	["Shoalers", "grazer", 0.7, ["mouth_filter", "cilia", "eye_spot"]],
	["Rammers", "grazer", 1.2, ["mouth_filter", "spike", "spike", "spike", "spike", "flagellum"]],
]

static func initial_species(species_count: int = 4) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in species_count:
		var t: Array = TEMPLATES[id]
		result.append({"id": id, "name": t[0], "role": t[1], "scale": t[2], "parts": t[3].duplicate(),
			"population": 18, "points": 25, "last_change": -COOLDOWN})
	return result

static func count_part(rival: Dictionary, part: String) -> int:
	return rival["parts"].count(part)

static func speed(rival: Dictionary) -> float:
	var value := 2.0
	for i in count_part(rival, "flagellum"):
		value += 1.4 * pow(0.6, i)
	return minf(value, 6.0)

static func mouth(rival: Dictionary) -> String:
	if count_part(rival, "mouth_filter") > 0 and count_part(rival, "mouth_jaw") > 0:
		return "both"
	return "jaw" if count_part(rival, "mouth_jaw") > 0 else "filter"

static func valid_parts(rival: Dictionary) -> bool:
	if rival["parts"].size() > MAX_PARTS or count_part(rival, "mouth_filter") + count_part(rival, "mouth_jaw") < 1:
		return false
	for part in rival["parts"]:
		if not PARTS.has(part) or count_part(rival, part) > PARTS[part][1]:
			return false
	return rival["scale"] >= MIN_SCALE and rival["scale"] <= MAX_SCALE

static func _add_part(rival: Dictionary, part: String) -> bool:
	if rival["parts"].size() >= MAX_PARTS or count_part(rival, part) >= PARTS[part][1] or rival["points"] < PARTS[part][0]:
		return false
	rival["points"] -= PARTS[part][0]
	rival["parts"].append(part)
	return true

static func _scale(rival: Dictionary, delta: float) -> bool:
	var next: float = snappedf(clampf(rival["scale"] + delta, MIN_SCALE, MAX_SCALE), 0.1)
	if is_equal_approx(next, rival["scale"]) or rival["points"] < 10:
		return false
	rival["points"] -= 10
	rival["scale"] = next
	return true

static func _adapt(rival: Dictionary, outcome: Dictionary, generation: int) -> Dictionary:
	var change := {"trait": "", "cause": "", "description": "", "delta": 0}
	if generation - rival["last_change"] < COOLDOWN:
		return change
	if outcome["predation"] >= 2:
		var cause: String = "%s took %d of them" % [outcome["killer"], outcome["predation"]]
		if _add_part(rival, "spike"):
			change = {"trait": "spike", "cause": cause, "description": "grew a spike", "delta": 1}
		elif _add_part(rival, "flagellum"):
			change = {"trait": "speed", "cause": cause, "description": "grew a flagellum", "delta": 1}
	elif outcome["shortfall"] >= 2:
		var cause: String = "prey supplied %d fewer food units than needed" % outcome["shortfall"] if rival["role"] == "hunter" and count_part(rival, "mouth_filter") == 0 else "shared food ran short by %d" % outcome["shortfall"]
		if _add_part(rival, "mouth_filter"):
			change = {"trait": "mouth", "cause": cause, "description": "grew a filter mouth", "delta": 1}
		elif _add_part(rival, "cilia"):
			change = {"trait": "forage", "cause": cause, "description": "grew cilia to forage", "delta": 1}
		elif _scale(rival, -0.1):
			change = {"trait": "size", "cause": cause, "description": "became smaller", "delta": -1}
	elif outcome["food"] >= outcome["need"] and outcome["food"] > 0:
		var cause: String = "eating %d food units" % outcome["food"]
		if _scale(rival, 0.1):
			change = {"trait": "size", "cause": cause, "description": "became larger", "delta": 1}
	if change["trait"] != "":
		rival["last_change"] = generation
	return change

static func run(seed_value: int, generation_count: int = 20, species_count: int = 4) -> Dictionary:
	assert(species_count >= 3 and species_count <= 5)
	assert(generation_count >= 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var species := initial_species(species_count)
	var food_pool := FOOD_CAP
	var history: Array[Dictionary] = []
	var journal: Array[Dictionary] = []
	var lines: PackedStringArray = []
	for generation in range(1, generation_count + 1):
		food_pool = mini(FOOD_CAP, food_pool + FOOD_REGROW)
		lines.append("Generation %d (shared food %d)" % [generation, food_pool])
		var outcomes: Array[Dictionary] = []
		for rival in species:
			outcomes.append({"id": rival["id"], "food": 0, "need": ceili(rival["population"] * rival["scale"] / 4.0),
				"predation": 0, "killer": "", "shortfall": 0})
		var grazers: Array[Dictionary] = []
		for rival in species:
			if (rival["role"] == "grazer" or count_part(rival, "mouth_filter") > 0) and rival["population"] > 0:
				grazers.append(rival)
		grazers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var x: float = speed(a) + count_part(a, "eye_spot") + count_part(a, "cilia")
			var y: float = speed(b) + count_part(b, "eye_spot") + count_part(b, "cilia")
			return a["id"] < b["id"] if is_equal_approx(x, y) else x > y)
		for rival in grazers:
			var o: Dictionary = outcomes[rival["id"]]
			var capacity: int = 2 + 4 * count_part(rival, "mouth_filter") + floori(speed(rival))
			o["food"] = mini(food_pool, mini(o["need"], capacity))
			food_pool -= o["food"]
		for hunter in species:
			if hunter["role"] != "hunter" or hunter["population"] <= 0:
				continue
			var prey: Array[Dictionary] = []
			for rival in species:
				if rival["id"] != hunter["id"] and rival["population"] > 0 and (rival["scale"] < hunter["scale"] or speed(rival) < speed(hunter)):
					prey.append(rival)
			prey.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var x: float = hunter["scale"] - a["scale"] + speed(hunter) - speed(a) - count_part(a, "spike")
				var y: float = hunter["scale"] - b["scale"] + speed(hunter) - speed(b) - count_part(b, "spike")
				return a["id"] < b["id"] if is_equal_approx(x, y) else x > y)
			if prey.is_empty():
				continue
			var target: Dictionary = prey[0]
			var attack: float = speed(hunter) + hunter["scale"] * 1.5 + rng.randf_range(-1.0, 1.0)
			var defense: float = speed(target) + target["scale"] * 1.5 + count_part(target, "spike") * 1.2
			var kills: int = mini(target["population"], clampi(ceili(attack - defense), 0, 3))
			outcomes[target["id"]]["predation"] += kills
			outcomes[target["id"]]["killer"] = hunter["name"]
			outcomes[hunter["id"]]["food"] += kills * 2
		for o in outcomes:
			var rival: Dictionary = species[o["id"]]
			o["shortfall"] = maxi(0, o["need"] - o["food"])
			var hunger_deaths: int = ceili(o["shortfall"] / 3.0)
			rival["population"] = clampi(rival["population"] - o["predation"] - hunger_deaths, 0, POP_CAP)
			if o["food"] >= o["need"] and rival["population"] > 0:
				rival["population"] = mini(POP_CAP, rival["population"] + 3)
			elif o["food"] > 0 and rival["population"] > 0:
				rival["population"] = mini(POP_CAP, rival["population"] + 1)
			rival["points"] = mini(100, rival["points"] + 3 + mini(3, o["food"]))
			var change: Dictionary = _adapt(rival, o, generation)
			var cause: String = change["cause"]
			var description: String = change["description"]
			if cause == "":
				cause = "taking %d food units, losing %d to predators, and lacking %d food units" % [o["food"], o["predation"], o["shortfall"]]
				description = "kept their parts"
			var line: String = "%s %s after %s (population %d)." % [rival["name"], description, cause, rival["population"]]
			lines.append("  " + line)
			journal.append({"generation": generation, "id": rival["id"], "text": line,
				"cause": cause, "trait": change["trait"], "delta": change["delta"]})
			var record: Dictionary = rival.duplicate(true)
			record["generation"] = generation
			record["food"] = o["food"]
			record["predation"] = o["predation"]
			record["shortfall"] = o["shortfall"]
			history.append(record)
	return {"text": "\n".join(lines) + "\n", "history": history, "species": species, "journal": journal}

static func csv(history: Array[Dictionary]) -> String:
	var rows: PackedStringArray = ["generation,id,name,population,food,predation,shortfall,scale,speed,mouth,spikes,points,parts"]
	for rival in history:
		rows.append("%d,%d,%s,%d,%d,%d,%d,%.1f,%.2f,%s,%d,%d,%s" % [
			rival["generation"], rival["id"], rival["name"], rival["population"], rival["food"],
			rival["predation"], rival["shortfall"], rival["scale"], speed(rival), mouth(rival),
			count_part(rival, "spike"), rival["points"], "|".join(rival["parts"])])
	return "\n".join(rows) + "\n"


