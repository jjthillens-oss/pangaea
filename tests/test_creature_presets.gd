extends TestCase
## The preset creatures (game/data/creature/presets.json, from tools/make_creature_presets.py; PROPOSED designs from
## the owner's playtest of 2026-10-24): every one passes the body and part rules, builds a closed skin within the
## gameplay budget and stands on at least two legs the gait planner can walk.

const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const SkinCpu := preload("res://game/systems/creature/skin_cpu.gd")
const GaitBody := preload("res://game/domain/creature/gait_body.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const MeshChecks := preload("res://tests/creature_mesh_checks.gd")

var rules: Dictionary


func before_each() -> void:
	rules = CreatureData.rules()


func test_there_are_six_to_twelve_presets_each_with_a_title_and_blurb() -> void:
	var names := CreatureData.preset_names()
	check(names.size() >= 6 and names.size() <= 12, "6 to 12 presets (%d)" % names.size())
	for n in names:
		var p := CreatureData.preset(n)
		check(not String(p["title"]).strip_edges().is_empty() and not String(p["blurb"]).strip_edges().is_empty(),
				"%s has a title and a blurb" % n)
		check(Color.html_is_valid(String(p["body"].get("skin_color", ""))), "%s has a skin colour" % n)


func test_every_preset_passes_the_body_and_part_rules() -> void:
	var checker := CreatureRules.new()
	for n in CreatureData.preset_names():
		var problems := checker.body_problems(CreatureData.preset(n)["body"])
		check(problems.is_empty(), "%s is a valid body: %s" % [n, problems])


func test_every_preset_round_trips_through_the_codec() -> void:
	for n in CreatureData.preset_names():
		var desc: RefCounted = CreatureData.preset_body(n)
		check_eq(BodyCodec.encode(BodyCodec.decode(BodyCodec.encode(desc))), BodyCodec.encode(desc), "%s round-trips" % n)


func test_every_preset_skin_is_closed_within_the_gameplay_budget() -> void:
	for n in CreatureData.preset_names():
		var desc: RefCounted = CreatureData.preset_body(n)
		var skin := SkinCpu.build_within(desc, int(rules["gameplay_divisions"]), int(rules["gameplay_triangle_budget"]))
		check(MeshChecks.watertight(skin["indices"]) and MeshChecks.wrong_winding_fraction(skin) <= 0.001,
				"%s skin is closed and one piece (%d triangles)" % [n, skin["indices"].size() / 3])
		check(skin["indices"].size() / 3 <= int(rules["gameplay_triangle_budget"]), "%s is within the budget" % n)


func test_every_preset_walks_on_two_or_more_legs() -> void:
	for n in CreatureData.preset_names():
		var gait := GaitBody.from_description(CreatureData.preset_body(n))
		check((gait["legs"] as Array).size() >= 2, "%s has %d legs the planner walks on" % [n, (gait["legs"] as Array).size()])

