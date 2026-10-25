extends TestCase
## Anatomy to social traits (PROPOSED, docs/stages/social-plan.md sections 4 and 6): display organs raise display
## strength with diminishing returns, a throat sac carries a song further and ears hear further, roles follow the
## body, and part types or roles the tuning does not name count for nothing.

const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const SLICE_PATH := "res://game/data/social/social_slice.json"

var tuning := {}
var part_rules := {}
var gait_table: RefCounted
var creature_tuning := {}


func before_each() -> void:
	tuning = JSON.parse_string(FileAccess.get_file_as_string(SLICE_PATH))
	part_rules = CreatureData.part_rules()
	gait_table = CreatureData.gait_table()
	creature_tuning = CreatureData.read_json(CreatureData.DATA_DIR + "/creature_stage.json")


func _stats(body: RefCounted) -> Dictionary:
	return CreatureStats.of(body, part_rules, gait_table, creature_tuning)


func _traits(preset: String) -> Dictionary:
	var body := CreatureData.preset_body(preset)
	return SocialTraits.of(body, _stats(body), part_rules, tuning)


func test_display_organs_raise_display_strength_with_diminishing_returns() -> void:
	var display: Dictionary = tuning["signals"]["display"]
	var cap := int(display["display_cap"])
	var last := SocialTraits.display_strength_of(0, display)
	check_near(last, 1.0, 0.0001, "no display organ: strength 1")
	var last_step := INF
	for n in range(1, cap + 1):
		var s := SocialTraits.display_strength_of(n, display)
		var step := s - last
		check(step > 0.0, "organ %d adds strength (%.3f)" % [n, step])
		check(step < last_step, "organ %d adds less than the one before (%.3f vs %.3f)" % [n, step, last_step])
		last_step = step
		last = s
	check_near(SocialTraits.display_strength_of(cap + 3, display), last, 0.0001, "organs past the cap add nothing")
	# The crested strider wears four display organs (crest, two wings, tail fluke); the hopper none.
	var strider := _traits("strider")
	check(int(strider["display_count"]) >= 2, "the strider is display-rich (%d organs)" % strider["display_count"])
	check_near(float(strider["display_strength"]),
			SocialTraits.display_strength_of(int(strider["display_count"]), display), 0.0001, "strider strength")
	check(float(strider["display_strength"]) > float(_traits("hopper")["display_strength"]),
			"a crested body displays more strongly than a plain one")


func test_a_throat_sac_carries_a_song_further_and_ears_hear_further() -> void:
	var sing: Dictionary = tuning["signals"]["sing"]
	var hopper := _traits("hopper")
	var strider := _traits("strider")
	check_eq(int(hopper["voice_organs"]), 1, "the hopper's throat sac is its voice organ")
	check_near(float(hopper["voice_m"]), float(sing["range_m"]) + float(sing["voice_bonus_m"]), 0.0001, "hopper song")
	check_near(float(strider["voice_m"]), float(sing["range_m"]), 0.0001, "a body without a voice organ")
	check(float(hopper["voice_m"]) > float(strider["voice_m"]), "the throat sac carries the song further")
	for eared in ["boar", "monkey"]:
		var t := _traits(eared)
		check(int(t["hearing_organs"]) > 0, "%s wears ears" % eared)
		check_near(float(t["hearing_mult"]), float(sing["hearing_mult"]), 0.0001, "%s hears further" % eared)
	check_near(float(strider["hearing_mult"]), 1.0, 0.0001, "no ears: plain hearing")
	check_eq(int(_traits("boar")["display_count"]), 1, "the boar's ears are hearing organs, only its mane displays")


func test_roles_follow_anatomy() -> void:
	var expected := {"strider": "scout", "boar": "defender", "monkey": "forager", "hopper": "forager"}
	for preset in expected:
		var t := _traits(preset)
		check_eq(t["role"], expected[preset], "%s role (scores %s)" % [preset, t["role_scores"]])
	# Hands carry two fruit, a mouth alone one.
	check_eq(int(_traits("monkey")["carry_count"]), int(tuning["carry"]["with_hand"]), "monkey carries with its hands")
	check_eq(int(_traits("strider")["carry_count"]), int(tuning["carry"]["with_mouth"]), "strider carries in its beak")
	# Ties go to the fixed order forager, scout, defender.
	check_eq(SocialTraits.role_of({"scout": 1.0, "defender": 1.0, "forager": 1.0}), "forager", "a three-way tie")
	check_eq(SocialTraits.role_of({"scout": 2.0, "defender": 2.0, "forager": 1.0}), "scout", "scout before defender")


func test_two_body_plans_suit_different_signals() -> void:
	var rich_at := int(tuning["fit"]["display_rich_at"])
	var strider := _traits("strider")
	var hopper := _traits("hopper")
	check(int(strider["display_count"]) >= rich_at, "the strider has the organs for Display")
	check(int(hopper["display_count"]) < rich_at, "the hopper does not")
	check(float(hopper["voice_m"]) > float(strider["voice_m"]), "but the hopper sings from further away")
	check(float(strider["display_strength"]) > float(hopper["display_strength"]), "and the strider displays stronger")


func test_unknown_part_types_and_roles_count_for_nothing() -> void:
	var body := CreatureData.preset_body("hopper")
	var stats := _stats(body)
	var plain := SocialTraits.of(body, stats, part_rules, tuning)
	# A part type the rules do not list, and a listed type with a role the social rules do not use.
	var rules := part_rules.duplicate(true)
	rules["glow_spot"] = {"role": "aura"}
	body.parts.append({"type": "mystery_organ", "mirror": true, "scale": 1000})
	body.parts.append({"type": "glow_spot", "mirror": true, "scale": 1000})
	var extended := SocialTraits.of(body, stats, rules, tuning)
	for key in ["voice_m", "hearing_mult", "display_strength", "display_count", "carry_count", "hands", "role"]:
		check_eq(extended[key], plain[key], "%s unchanged by unknown parts" % key)
	# A voice-organ type that is not a detail-role part is no voice organ.
	var rerolled := part_rules.duplicate(true)
	rerolled["throat_sac"] = (rerolled["throat_sac"] as Dictionary).duplicate()
	rerolled["throat_sac"]["role"] = "weapon"
	var no_voice := SocialTraits.of(CreatureData.preset_body("hopper"), stats, rerolled, tuning)
	check_eq(int(no_voice["voice_organs"]), 0, "a re-roled throat sac is not a voice organ")
	check_near(float(no_voice["voice_m"]), float(tuning["signals"]["sing"]["range_m"]), 0.0001, "plain song range")
