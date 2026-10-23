extends SceneTree

const Names := preload("res://name_generator.gd")
var failures := 0

func _init() -> void:
	var base: Dictionary = Names.DEFAULT_TRAITS.duplicate()
	_check(Names.valid_traits(base), "default traits valid")
	_check(not Names.valid_traits({"diet": "none", "habitat": "sea", "size": "small", "limbs": 2}), "bad diet rejected")
	_check(not Names.valid_traits({"diet": "herbivore", "habitat": "sea", "size": "small", "limbs": 7}), "bad limb count rejected")
	var first := JSON.stringify(Names.generate_many(12, base, 100))
	_check(first == JSON.stringify(Names.generate_many(12, base, 100)), "same seed/traits byte-identical")
	_check(first != JSON.stringify(Names.generate_many(13, base, 100)), "seed changes names")
	var thousand := Names.generate_many(1, base, 1000)
	var unique := {}
	for row in thousand:
		unique[row.lineage] = true
		_check_word(row.genus, "genus")
		_check_word(row.lineage.replace(" ", ""), "lineage")
		_check(not Names.is_blocked(row.genus + row.common + row.lineage), "block list")
	_check(unique.size() >= 980, "at most 2 percent duplicate lineages (got %d)" % (1000 - unique.size()))
	var sample: Dictionary = thousand[0]
	_check(sample.lineage.begins_with(sample.genus + " "), "lineage begins with genus")
	_check(sample.short == sample.genus + " I", "generation I tag")
	_check(Names.roman(4) == "IV" and Names.roman(49) == "XLIX" and Names.roman(2026) == "MMXXVI", "generation roman tags")
	for habitat in ["sea", "shore", "land"]:
		for diet in ["herbivore", "carnivore", "omnivore"]:
			var traits := base.duplicate()
			traits.habitat = habitat
			traits.diet = diet
			var output := Names.generate_many(5, traits, 100)
			_check(output.size() == 100, "count %s %s" % [habitat, diet])
			for row in output:
				_check(not Names.is_blocked(row.genus + row.common + row.lineage), "block %s %s" % [habitat, diet])
	var sea := base.duplicate()
	sea.habitat = "sea"
	var land := base.duplicate()
	land.habitat = "land"
	var hunter := base.duplicate()
	hunter.diet = "carnivore"
	_check(Names.generate_many(1, sea, 1)[0].common != Names.generate_many(1, land, 1)[0].common, "habitat changes common name")
	_check(Names.generate_many(1, sea, 1)[0].common != Names.generate_many(1, hunter, 1)[0].common, "diet changes common name")
	print("FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)

func _check_word(word: String, label: String) -> void:
	var consonants := 0
	for letter in word.to_lower():
		if "aeiou".contains(letter):
			consonants = 0
		else:
			consonants += 1
			if consonants >= 3:
				_check(false, "%s has three consonants: %s" % [label, word])
				return

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
