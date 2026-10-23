extends TestCase
## The placement kit (docs/s1/s1-interfaces.md sections 3.4 and 4.4): the smallest kit the rules
## accept passes, each rule refuses the mistake it is for, unknown and missing keys are refused with
## their JSON path (G24), and the lookups the generator uses (class, fitting shells, landmarks and
## rare pieces) answer from the data alone.
##
## The tests use tests/fixtures/world/kit_min.json: real GLBs, fixture records. The kit the world
## ships (art's, game/data/placement_kit.json) is checked by the same rules.

const KIT := "res://tests/fixtures/world/kit_min.json"
const RECORDS := "res://tests/fixtures/world/records/"
const VARIANTS := "res://tests/fixtures/world/records/variants/"


func _fixture() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(KIT))


## The index of the asset `id` in the fixture's list.
static func _index(data: Dictionary, id: String) -> int:
	for i in data.assets.size():
		if data.assets[i].id == id:
			return i
	return -1


## The fixture with `key` of asset `id` set to `value` (a null value erases the key).
func _with(id: String, key: String, value: Variant) -> Dictionary:
	var data := _fixture()
	var a: Dictionary = data.assets[_index(data, id)]
	if value == null:
		a.erase(key)
	else:
		a[key] = value
	return data


func _without(id: String) -> Dictionary:
	var data := _fixture()
	data.assets.remove_at(_index(data, id))
	return data


static func _dressings(scales: Array) -> Array:
	var out := []
	for i in scales.size():
		out.append({"id": "d%d" % i, "tint": "#E8E0D0", "growth": "", "scale": scales[i]})
	return out


func test_the_fixture_kit_has_no_problems() -> void:
	var kit := PlacementKit.load_from(KIT)
	check_eq(kit.validate(), PackedStringArray(), "the smallest kit the rules accept")
	check_eq(kit.assets.size(), 20, "7 pickable shells, 6 landmarks, 2 rare pieces, 2 markers and the 3 M1 rocks")
	check_eq(kit.classes, {"fp_s": [0.6, 0.9], "fp_m": [0.9, 1.2], "fp_l": [1.2, 1.5]}, "classes")
	check_eq(kit.landmark_groups, [2, 2, 1, 1] as Array[int], "landmark groups")
	check_eq(kit.anchor_radius_bu, 3.0, "anchor radius")
	check_eq(kit.collide_radius_bu, 2.0, "collide radius")
	var husk: Dictionary = kit.assets.rare_giant_husk
	check_eq(husk.colliders[0].center, PackedFloat64Array([0.0, 0.0]), "a collider centre is two floats")
	check_eq(husk.colliders[0].radius, 3.0, "and its radius")
	check_eq(kit.assets.landmark_arch.dressings[1], {"id": "algae", "tint": "#C8D8B0", "growth": "Growth_Algae", "scale": 0.95}, "a dressing")


## Art's kit on main (tools/blender/make_s1_kit.py, docs/s1/s1-build-plan.md section 1): the rules
## accept it and it holds exactly the S1 pieces plus S2's Lurker lair mouth marker (art PR #26), so
## a piece added, renamed or dropped shows here.
func test_the_shipped_kit_validates() -> void:
	var kit := PlacementKit.load_from()
	check_eq(kit.validate(), PackedStringArray(), "the kit the world ships")
	var ids := PackedStringArray(kit.assets.keys())
	ids.sort()
	check_eq(ids, PackedStringArray(["landmark_arch", "landmark_fan", "landmark_great_shell", "landmark_ring",
		"landmark_shed_husk", "landmark_spire", "marker_checkpoint_column", "marker_lair_mouth", "marker_origin_arrow",
		"rare_giant_husk", "rare_shell_cathedral", "rock_a", "rock_b", "rock_c", "shell_bell", "shell_diatom_disc",
		"shell_fluted_tower", "shell_girdle_drum", "shell_radiolarian_lens"]), "the 18 S1 pieces and the lair mouth")
	check_eq(kit.landmarks(0, 3), PackedStringArray(["landmark_shed_husk"]), "the shed husk is group 3's landmark")
	check_eq(kit.rare_asset(0, "giant_husk"), "rare_giant_husk", "and the fixed rare tile's piece is the giant husk")


func test_each_rule_has_a_failing_case() -> void:
	# [the data, the problem's start or fragment, how many problems]
	var husk_i := _index(_fixture(), "rare_giant_husk")
	var cases := [
		# Rule 1: ids, kinds and bands.
		[_with("shell_s_pill", "id", "Shell_s_pill"), "placement_kit.assets[0].id: 'Shell_s_pill' does not match", 1],
		[_with("shell_l_wide", "id", "shell_l_bell"), "placement_kit.assets[6].id: 'shell_l_bell' is repeated", 1],
		[_with("shell_l_wide", "band", 1), "placement_kit.assets[6].band: 1;", 1],
		[_with("shell_l_wide", "band", -1), "placement_kit.assets[6].band: -1;", 1],
		[_with("marker_origin_arrow", "band", 0), ".band: 0;", 1],
		# Rule 3: scale ranges.
		[_with("shell_l_tower", "scale", [0.4, 1.0]), ".scale: [0.4, 1.0] needs", 1],
		[_with("shell_l_tower", "scale", [0.8, 2.1]), ".scale: [0.8, 2.1] needs", 1],
		[_with("shell_l_tower", "scale", [0.6, 1.3]), ".scale: [0.6, 1.3] needs", 1],
		[_with("shell_l_tower", "scale", [1.0, 0.8]), ".scale: [1.0, 0.8] needs", 2],
		[_with("landmark_arch", "scale", [0.85, 1.1]), ".scale: a landmark's scale lies within", 1],
		[_with("rare_shell_cathedral", "scale", [1.0, 1.1]), ".scale: a rare's scale is [1, 1]", 1],
		[_with("marker_origin_arrow", "scale", [0.9, 0.9]), ".scale: a marker's scale is [1, 1]", 1],
		# Rule 4: a shell's footprint and the fit rule.
		[_with("shell_l_wide", "footprint_radius_m", 0.0), ".footprint_radius_m: must be above 0", 2],
		[_with("shell_l_wide", "footprint_class", "fp_xl"), ".footprint_class: 'fp_xl' is not one of", 1],
		[_with("shell_s_pill", "scale", [0.85, 1.2]), "placement_kit.assets[0]: footprint 0.75 at scale", 2],
		[_with("shell_l_wide", "scale", [1.0, 1.2]), ": footprint 1.2 at scale", 1],
		# Rule 5: landmarks.
		[_with("landmark_arch", "footprint_radius_m", 2.5), ".footprint_radius_m: 2.5 must equal landmark.collide_radius_bu", 2],
		[_with("landmark_arch", "group", 4), ".group: 4 is not in [0, 4)", 1],
		[_with("landmark_arch", "dressings", _dressings([1.0, 1.0])), ".dressings: a landmark has exactly 3 (2)", 1],
		[_with("landmark_arch", "dressings", _dressings([1.0, 1.0, 1.2])), ".dressings[2].scale: 1.2 is outside", 1],
		[_with("landmark_spire", "group", 3), "placement_kit.landmark.groups: band 0's landmarks per group are [2, 2, 0, 2]", 1],
		# Rule 6: rare pieces.
		[_with("rare_shell_cathedral", "rare_kind", "giant_husk"), ".rare_kind: 'giant_husk' is empty or repeated", 1],
		[_with("rare_giant_husk", "colliders", [{"center": [0.0, 0.0], "radius": 0.5}]), "placement_kit.assets[%d].colliders[0].radius: 0.5 is outside" % husk_i, 1],
		[_with("rare_giant_husk", "colliders", [{"center": [0.0, 0.0], "radius": 4.5}]), ".colliders[0].radius: 4.5 is outside", 1],
		[_with("rare_giant_husk", "colliders", []), ".colliders: a set piece needs at least one", 1],
		# Rule 7: yaw rules by kind.
		[_with("shell_s_lens", "yaw_rule", "steps_90"), ".yaw_rule: 'steps_90' is not one of", 1],
		[_with("landmark_arch", "yaw_rule", "slot"), ".yaw_rule: 'slot' is not one of", 1],
		[_with("rare_giant_husk", "yaw_rule", "free"), ".yaw_rule: 'free' is not one of", 1],
		[_with("marker_origin_arrow", "yaw_rule", "steps_90"), ".yaw_rule: 'steps_90' is not one of", 1],
		# Rule 8: dressings.
		[_with("shell_s_pill", "dressings", [{"id": "plain", "tint": "#FFFFFF", "growth": "", "scale": 1.0},
			{"id": "plain", "tint": "#FFFFFF", "growth": "", "scale": 1.0}]), ".dressings[1].id: 'plain' is empty or repeated", 1],
		[_with("shell_s_pill", "dressings", [{"id": "plain", "tint": "#ffffff", "growth": "", "scale": 1.0}]), ".dressings[0].tint: '#ffffff' does not match", 1],
		[_with("shell_s_pill", "dressings", [{"id": "plain", "tint": "#FFFFFF", "growth": "Algae", "scale": 1.0}]), ".dressings[0].growth: 'Algae' is neither", 1],
		[_with("shell_s_pill", "dressings", []), "placement_kit.assets[0].dressings: a shell needs at least one", 1],
		# Rule 9: the GLB and the record.
		[_with("shell_s_pill", "glb", "res://assets/export/no_such_shell.glb"), ".glb: 'res://assets/export/no_such_shell.glb' does not exist", 1],
		[_with("shell_s_pill", "record", RECORDS + "no_such_record.json"), ".record: '%sno_such_record.json' does not exist" % RECORDS, 1],
		[_with("shell_s_pill", "record", VARIANTS + "wrong_id.json"), ".record: '%swrong_id.json' disagrees: id 'shell_s_other'" % VARIANTS, 1],
		[_with("shell_s_pill", "record", VARIANTS + "wrong_radius.json"), "disagrees: footprint_radius_m 0.7", 1],
		[_with("shell_s_pill", "record", VARIANTS + "wrong_export.json"), "disagrees: export_path 'assets/export/shell_radiolarian_lens.glb'", 1],
		# Rule 10: placeholder and approval.
		[_with("shell_s_pill", "record", VARIANTS + "finished.json"), "placement_kit.assets[0].placeholder: true, but the record's review_state is 'production", 1],
		[_with("rock_a", "placeholder", true), ".placeholder: true, but the record's review_state is 'production", 1],
		[_with("shell_s_pill", "approved", true), "placement_kit.assets[0].approved: needs a finished piece", 1],
		# Rule 11: coverage and the markers.
		[_without("shell_s_lens"), "placement_kit.assets: 1 pickable band-0 shells cover all of fp_s", 1],
		[_with("shell_m_lens", "pickable", false), "placement_kit.assets: 1 pickable band-0 shells cover all of fp_m", 1],
		[_without("marker_origin_arrow"), "placement_kit.assets: the marker 'marker_origin_arrow' is missing", 1],
		# Rule 12: the M1 rocks.
		[_with("rock_a", "pickable", true), "placement_kit.assets: 'rock_a' must be a shell with pickable false", 1],
		[_with("rock_b", "scale", [0.8, 1.4]), "placement_kit.assets: 'rock_b' must be", 1],
		[_without("rock_c"), "placement_kit.assets: 'rock_c' must be", 1],
	]
	for c in cases:
		var problems := PlacementKit.from_dict(c[0]).validate()
		var found := false
		for p in problems:
			found = found or p.begins_with(c[1]) or p.contains(c[1])
		check(found and problems.size() == c[2], "one case gives %d problem(s), one containing '%s': %s" % [c[2], c[1], problems])


func test_the_classes_must_be_exactly_the_s1_classes() -> void:
	var cases := [
		{"fp_s": [0.6, 0.8], "fp_m": [0.9, 1.2], "fp_l": [1.2, 1.5]},
		{"fp_s": [0.6, 0.9], "fp_m": [0.9, 1.2]},
		{"fp_s": [0.6, 0.9], "fp_m": [0.9, 1.2], "fp_l": [1.2, 1.5], "fp_xl": [1.5, 2.0]},
	]
	for classes in cases:
		var data := _fixture()
		data.footprint_classes = classes
		var problems := PlacementKit.from_dict(data).validate()
		check(problems.size() == 1 and problems[0].begins_with("placement_kit.footprint_classes: must be exactly"),
			"%s is one problem; the fit and coverage rules wait for it: %s" % [classes, problems])


func test_an_approved_finished_piece_passes_rule_10() -> void:
	var data := _with("shell_s_pill", "record", VARIANTS + "approved.json")
	data.assets[0].placeholder = false
	data.assets[0].approved = true
	check_eq(PlacementKit.from_dict(data).validate(), PackedStringArray(), "a finished piece whose record is APPROVED")
	data = _with("shell_s_pill", "record", VARIANTS + "finished_proposed.json")
	data.assets[0].placeholder = false
	data.assets[0].approved = true
	check_eq(PlacementKit.from_dict(data).validate(), PackedStringArray(["placement_kit.assets[0].approved: needs a finished piece whose record status is APPROVED"]),
		"a finished piece the owner has not approved")
	data.assets[0].approved = false
	check_eq(PlacementKit.from_dict(data).validate(), PackedStringArray(), "a finished piece, not approved")


func test_unknown_and_missing_keys_are_refused_with_their_path() -> void:
	var data := _fixture()
	var husk_i := _index(data, "rare_giant_husk")
	data["colour"] = "blue"
	data.assets[0]["group"] = 1
	data.assets[husk_i].erase("rare_kind")
	data.assets[husk_i].colliders[0].erase("radius")
	data.assets[1].dressings[0]["shine"] = 0.5
	data.landmark.erase("groups")
	var kit := PlacementKit.from_dict(data)
	var expected := PackedStringArray(["placement_kit.colour: unknown key", "placement_kit.landmark.groups: missing",
		"placement_kit.assets[0].group: unknown key", "placement_kit.assets[1].dressings[0].shine: unknown key",
		"placement_kit.assets[%d].rare_kind: missing" % husk_i, "placement_kit.assets[%d].colliders[0].radius: missing" % husk_i])
	check_eq(kit.validate(), expected, "each named by its path, and the rules wait for a kit that reads")
	var wrong_kind := _with("marker_origin_arrow", "kind", "beacon")
	var problems := PlacementKit.from_dict(wrong_kind).validate()
	check(problems.size() == 1 and problems[0].ends_with(".kind: must be one of shell, landmark, rare, marker"), "an unknown kind: %s" % [problems])
	var types := _with("shell_s_pill", "pickable", "yes")
	types.assets[1]["band"] = 0.5
	check_eq(PlacementKit.from_dict(types).validate(), PackedStringArray(["placement_kit.assets[0].pickable: must be true or false",
		"placement_kit.assets[1].band: must be a whole number"]), "types")
	check_eq(PlacementKit.load_from("res://tests/fixtures/world/no_kit.json").validate(),
		PackedStringArray(["no_kit.json: missing or not readable JSON"]), "never null")


func test_class_of_follows_the_half_open_classes() -> void:
	var kit := PlacementKit.load_from(KIT)
	var cases := [[0.59, ""], [0.6, "fp_s"], [0.89, "fp_s"], [0.9, "fp_m"], [1.19, "fp_m"], [1.2, "fp_l"],
		[1.5, "fp_l"], [1.51, ""], [-1.0, ""]]
	for c in cases:
		check_eq(kit.class_of(c[0]), c[1], "radius %s" % c[0])


func test_fitting_offers_pickable_shells_only_sorted_by_id() -> void:
	var kit := PlacementKit.load_from(KIT)
	check_eq(kit.fitting(0.6, 0), PackedStringArray(["shell_s_lens", "shell_s_pill"]), "the smallest radius")
	check_eq(kit.fitting(1.0, 0), PackedStringArray(["shell_m_lens", "shell_m_pill"]), "the M1 rocks fit 1.0 but are never offered")
	check_eq(kit.fitting(1.5, 0), PackedStringArray(["shell_l_bell", "shell_l_tower", "shell_l_wide"]), "the largest radius")
	check_eq(kit.fitting(1.0, 1), PackedStringArray(), "band 1 has no shells")
	for i in 91:
		var r := 0.6 + i * 0.01
		var fit := kit.fitting(r, 0)
		var sorted := Array(fit)
		sorted.sort()
		check(fit.size() >= PlacementKit.MIN_PICKABLE_PER_CLASS and Array(fit) == sorted, "radius %s has two sorted choices: %s" % [r, fit])
		for id in fit:
			var a: Dictionary = kit.assets[id]
			var s: float = r / float(a.footprint_radius_m)
			check(a.pickable and s >= a.scale[0] - PlacementKit.FIT_EPSILON and s <= a.scale[1] + PlacementKit.FIT_EPSILON, "%s fits %s" % [id, r])


## The spine's own shell (fr 0.75, scale [0.8, 1.2]) is written on its class's edges, where float64
## division lands a hair outside the range; FIT_EPSILON lets the edge count, and nothing wider.
func test_the_spines_edge_example_covers_its_class() -> void:
	var a := {"footprint_radius_m": 0.75, "scale": [0.8, 1.2]}
	check(0.6 / 0.75 < 0.8, "the division lands below the range's end")
	check(PlacementKit._covers(a, 0.6) and PlacementKit._covers(a, 0.9), "but the edges count")
	check(not PlacementKit._covers(a, 0.6 - 1e-6) and not PlacementKit._covers(a, 0.9 + 1e-6), "a micro-bu beyond them does not")
	var kit := PlacementKit.load_from(KIT)
	check(kit.fitting(0.6, 0).has("shell_s_pill") and kit.fitting(0.9, 0).has("shell_s_pill"), "so the fixture's copy of it is offered at both")


func test_landmarks_and_rare_pieces_are_looked_up_by_group_and_kind() -> void:
	var kit := PlacementKit.load_from(KIT)
	check_eq(kit.landmarks(0, 0), PackedStringArray(["landmark_arch", "landmark_fan"]), "group 0")
	check_eq(kit.landmarks(0, 1), PackedStringArray(["landmark_great_shell", "landmark_ring"]), "group 1")
	check_eq(kit.landmarks(0, 3), PackedStringArray(["landmark_shed_husk"]), "group 3")
	check_eq(kit.landmarks(1, 0), PackedStringArray(), "band 1")
	check_eq(kit.rare_asset(0, "giant_husk"), "rare_giant_husk", "the fixed rare tile's piece")
	check_eq(kit.rare_asset(0, "shell_cathedral"), "rare_shell_cathedral", "the other rare kind")
	check_eq(kit.rare_asset(0, "kraken"), "", "a kind the kit lacks")
	check_eq(kit.rare_asset(1, "giant_husk"), "", "another band")
