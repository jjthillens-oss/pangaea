extends SceneTree

const Simulation := preload("res://simulation.gd")
var failures := 0

func _init() -> void:
	var catalog_path := ProjectSettings.globalize_path("res://").path_join("../../game/data/part_catalog.json").simplify_path()
	var species_path := ProjectSettings.globalize_path("res://").path_join("../../game/data/creatures_m1.json").simplify_path()
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
	var m1: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(species_path))
	var catalog_match := true
	for part in Simulation.PARTS:
		catalog_match = catalog_match and catalog["parts"].has(part)
		catalog_match = catalog_match and Simulation.PARTS[part][0] == catalog["parts"][part]["cost"]
		catalog_match = catalog_match and Simulation.PARTS[part][1] == catalog["parts"][part]["max_count"]
	var templates: Array[Dictionary] = Simulation.initial_species(5)
	var hunter_parts: Array = []
	for part in m1["species"]["ambush_hunter"]["parts"]:
		hunter_parts.append(part["type"])
	var rammer_parts: Array = []
	for part in m1["species"]["rammer"]["parts"]:
		rammer_parts.append(part["type"])
	check(catalog_match and Simulation.MAX_PARTS == catalog["limits"]["max_parts"]
		and Simulation.MIN_SCALE == catalog["limits"]["min_scale"]
		and Simulation.MAX_SCALE == catalog["limits"]["max_scale"]
		and templates[0]["parts"] == ["mouth_filter", "flagellum", "eye_spot"]
		and templates[1]["parts"] == hunter_parts
		and templates[4]["parts"] == rammer_parts,
		"visible templates and budgets match read-only game catalogs")
	var a: Dictionary = Simulation.run(17, 20, 5)
	var b: Dictionary = Simulation.run(17, 20, 5)
	check(a["text"] == b["text"] and Simulation.csv(a["history"]) == Simulation.csv(b["history"]),
		"same seed gives byte-identical journal and CSV")
	check(a["text"] != Simulation.run(18, 20, 5)["text"], "different seeds differ")
	var bounds := true
	var cooldown := true
	var causal := true
	var one_change := true
	var any_predation := false
	var any_shortfall := false
	var survival_count := 0
	var long_survival_count := 0
	var non_saturation_count := 0
	var refound_count := 0
	for seed_value in range(20):
		var result: Dictionary = Simulation.run(seed_value, 500, 5)
		var last_change := {}
		var last_trait := {}
		var last_delta := {}
		var max_streak := {}
		var non_saturated := true
		for rival in result["history"]:
			bounds = bounds and Simulation.valid_parts(rival)
			bounds = bounds and rival["population"] >= 0 and rival["population"] <= Simulation.POP_CAP
			bounds = bounds and rival["points"] >= 0 and rival["points"] <= 100
			var id: int = rival["id"]
			max_streak[id] = max_streak.get(id, 0) + 1 if rival["points"] == 100 else 0
			non_saturated = non_saturated and max_streak[id] <= 50
			any_predation = any_predation or rival["predation"] > 0
			any_shortfall = any_shortfall or rival["shortfall"] > 0
		for event in result["journal"]:
			var id: int = event["id"]
			causal = causal and event["text"].contains(" after ") and event["cause"] != ""
			if event["trait"] != "":
				if event["trait"] == "refound":
					refound_count += 1
				causal = causal and (event["cause"].contains("took") or event["cause"].contains("short") or event["cause"].contains("fewer") or event["cause"].contains("eating") or event["cause"].contains("survived"))
				if last_change.has(id) and event["generation"] - last_change[id] < Simulation.COOLDOWN:
					cooldown = false
				if last_trait.get(id, "") == event["trait"] and last_delta.get(id, 0) == -event["delta"] and event["generation"] - last_change.get(id, -100) < Simulation.COOLDOWN:
					cooldown = false
				last_change[id] = event["generation"]
				last_trait[id] = event["trait"]
				last_delta[id] = event["delta"]
		var first_twenty: Dictionary = Simulation.run(seed_value, 20, 5)
		var alive := true
		for rival in first_twenty["species"]:
			alive = alive and rival["population"] > 0
		if alive:
			survival_count += 1
		var alive_at_end := 0
		for rival in result["species"]:
			if rival["population"] > 0:
				alive_at_end += 1
		if alive_at_end >= 4:
			long_survival_count += 1
		if non_saturated:
			non_saturation_count += 1
		one_change = one_change and first_twenty["journal"].size() == 20 * 5
	check(bounds, "parts, scale, population and points bounded for 500 generations x 20 seeds")
	check(cooldown, "no change or reversal inside three-generation cooldown")
	check(causal and any_predation and any_shortfall, "every journal line has an observed cause; predation and scarcity occur")
	check(one_change, "at most one journaled change per species per generation")
	check(survival_count >= 18, "all species survive 20 generations in at least 18/20 seeds (%d)" % survival_count)
	check(long_survival_count >= 16, "at least four of five alive after 500 generations in at least 16/20 seeds (%d)" % long_survival_count)
	check(non_saturation_count >= 16, "no 100-point streak over 50 generations in at least 16/20 seeds (%d)" % non_saturation_count)
	print("OBSERVED  re-founding events over 500 generations x 20 seeds: %d" % refound_count)
	var base: Dictionary = Simulation.initial_species(5)[0]
	var spiky: Dictionary = base.duplicate(true)
	spiky["parts"].append("spike")
	var swift: Dictionary = base.duplicate(true)
	swift["parts"].append("flagellum")
	var fed_base: Dictionary = base.duplicate(true)
	fed_base["population"] = Simulation.POP_CAP
	swift["population"] = Simulation.POP_CAP
	check(Simulation.upkeep(spiky) > Simulation.upkeep(base) and Simulation.speed(spiky) < Simulation.speed(base)
		and Simulation.part_burden(swift) > Simulation.part_burden(fed_base) and Simulation.food_need(swift) > Simulation.food_need(fed_base),
		"spikes trade speed for defence and extra speed raises food need")
	var every_part_costs := true
	for part in Simulation.PARTS:
		var carrier: Dictionary = base.duplicate(true)
		var before: float = Simulation.part_burden(carrier)
		carrier["parts"].append(part)
		var first: float = Simulation.part_burden(carrier)
		every_part_costs = every_part_costs and first > before
		if Simulation.PARTS[part][1] > 1:
			carrier["parts"].append(part)
			var second: float = Simulation.part_burden(carrier)
			every_part_costs = every_part_costs and second - first > first - before
	check(every_part_costs, "every part has a rising recurring cost for additional copies")
	var choices := {}
	for generation in range(1, 4):
		var hunted: Dictionary = base.duplicate(true)
		hunted["points"] = 100
		var change: Dictionary = Simulation._adapt(hunted, {"predation": 2, "killer": "Hunters", "shortfall": 0, "food": 0, "need": 4}, generation)
		choices[change["trait"]] = true
	check(choices.size() >= 2, "predation offers more than one causal adaptation")
	var relatives: Array[Dictionary] = Simulation.initial_species(5)
	relatives[0]["population"] = 0
	var founding: Dictionary = Simulation._refound(relatives[0], relatives, 4)
	check(founding["trait"] == "refound" and relatives[0]["population"] == Simulation.REFOUND_POPULATION
		and Simulation.valid_parts(relatives[0]) and relatives[0]["parts"].size() < 3
		and founding["cause"].contains("survived"),
		"re-founding is bounded and names a surviving relative")
	var scarce: Dictionary = Simulation.run(1, 100, 5, 24)
	var observed_refound := false
	for event in scarce["journal"]:
		if event["trait"] == "refound":
			observed_refound = observed_refound or event["cause"].contains("survived")
	check(observed_refound, "scarcity run reaches the re-founding path and records its cause")
	var csv: String = Simulation.csv(a["history"])
	check(csv.split("\n").size() == 102 and csv.begins_with("generation,id,name,"), "CSV has header and 100 rows")
	var summary: String = Simulation.summary(Simulation.run(1, 500, 5)["species"])
	check(summary.begins_with("species | population | parts | points\n") and summary.split("\n").size() == 7
		and summary.contains("Rammers | "), "summary has one end-state row per species")
	check(Simulation.run(1, 20, 3)["journal"].size() == 60, "three-species mode runs")
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)

func check(ok: bool, description: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + description)
	if not ok:
		failures += 1

