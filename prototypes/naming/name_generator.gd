extends RefCounted

## PROPOSED original sound tables. Every draw uses the one RNG in generate_many().
const ONSETS := ["b", "d", "f", "g", "h", "k", "l", "m", "n", "p", "r", "s", "t", "v", "w", "z"]
const VOWELS := ["a", "e", "i", "o", "u", "ae", "ia", "ou"]
const CODAS := ["", "", "", "l", "m", "n", "r", "s", "t"]
const SEA_ONSETS := ["l", "m", "n", "r", "s", "v", "w"]
const SHORE_ONSETS := ["b", "d", "l", "m", "p", "r", "t"]
const LAND_ONSETS := ["d", "g", "k", "p", "r", "t", "z"]
const DIET_ENDINGS := {"herbivore": ["a", "ena", "ora"], "carnivore": ["ax", "ira", "or"], "omnivore": ["on", "ula", "ari"]}
const HABITAT_WORDS := {"sea": ["Tide", "Reef", "Current"], "shore": ["Dune", "Estuary", "Foam"], "land": ["Meadow", "Ridge", "Grove"]}
const DIET_WORDS := {"herbivore": ["Forager", "Grazer", "Browser"], "carnivore": ["Hunter", "Prowler", "Stalker"], "omnivore": ["Seeker", "Wanderer", "Gatherer"]}
const SIZE_WORDS := {"small": ["Little", "Fine", "Pip"], "medium": ["Broad", "Mottled", "Soft"], "large": ["Great", "Heavy", "Tall"]}
const LIMB_WORDS := {0: ["Drifter", "Ribbon"], 1: ["Skipper", "Hopper"], 2: ["Strider", "Darter"], 3: ["Pacer", "Creeper"], 4: ["Walker", "Climber"], 5: ["Crawler", "Scrambler"], 6: ["Scuttler", "Rambler"]}
const BLOCKED := ["fuck", "shit", "cunt", "bitch", "piss", "dick", "cock", "twat", "wank", "nigger", "faggot", "vagina", "penis"]
const DEFAULT_TRAITS := {"diet": "herbivore", "habitat": "sea", "size": "medium", "limbs": 2}

static func valid_traits(traits: Dictionary) -> bool:
	return DIET_ENDINGS.has(traits.get("diet")) and HABITAT_WORDS.has(traits.get("habitat")) \
		and SIZE_WORDS.has(traits.get("size")) and traits.get("limbs") is int \
		and int(traits["limbs"]) >= 0 and int(traits["limbs"]) <= 6

static func generate_many(seed_value: int, traits: Dictionary, count: int, generation: int = 1) -> Array[Dictionary]:
	if not valid_traits(traits) or count < 0 or generation < 1 or generation > 3999:
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result: Array[Dictionary] = []
	for _index in count:
		var genus := ""
		var epithet := ""
		for _attempt in 64:
			genus = _scientific_piece(rng, traits, true)
			epithet = _scientific_piece(rng, traits, false)
			if not is_blocked(genus + epithet):
				break
		if is_blocked(genus + epithet):
			genus = "Luma"
			epithet = "lumeria"
		var habitat: String = traits["habitat"]
		var diet: String = traits["diet"]
		var size: String = traits["size"]
		var limbs: int = traits["limbs"]
		var common := "%s %s %s %s" % [
			SIZE_WORDS[size][rng.randi_range(0, SIZE_WORDS[size].size() - 1)],
			HABITAT_WORDS[habitat][rng.randi_range(0, HABITAT_WORDS[habitat].size() - 1)],
			DIET_WORDS[diet][rng.randi_range(0, DIET_WORDS[diet].size() - 1)],
			LIMB_WORDS[limbs][rng.randi_range(0, LIMB_WORDS[limbs].size() - 1)]]
		result.append({"genus": genus, "common": common, "lineage": genus + " " + epithet,
			"short": genus + " " + roman(generation)})
	return result

static func _scientific_piece(rng: RandomNumberGenerator, traits: Dictionary, is_genus: bool) -> String:
	var onset_pool: Array = SEA_ONSETS if traits["habitat"] == "sea" else SHORE_ONSETS if traits["habitat"] == "shore" else LAND_ONSETS
	var text := ""
	var syllables := 2 + rng.randi_range(0, 1)
	for syllable in syllables:
		var onset: String = onset_pool[rng.randi_range(0, onset_pool.size() - 1)] if syllable == 0 else ONSETS[rng.randi_range(0, ONSETS.size() - 1)]
		var vowel: String = VOWELS[rng.randi_range(0, VOWELS.size() - 1)]
		var coda: String = CODAS[rng.randi_range(0, CODAS.size() - 1)]
		text += onset + vowel + coda
	if not is_genus:
		var endings: Array = DIET_ENDINGS[traits["diet"]]
		text += endings[rng.randi_range(0, endings.size() - 1)]
	else:
		text = text.capitalize().replace(" ", "")
	return text

static func is_blocked(text: String) -> bool:
	var lower := text.to_lower()
	for word in BLOCKED:
		if lower.contains(word):
			return true
	return false

static func roman(number: int) -> String:
	if number < 1 or number > 3999:
		return ""
	var remaining := number
	var result := ""
	var values := [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	var symbols := ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	for index in values.size():
		while remaining >= values[index]:
			result += symbols[index]
			remaining -= values[index]
	return result
