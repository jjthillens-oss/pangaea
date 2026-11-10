extends TestCase
## The landform layout rule (PROPOSED, IB-32): the same seed composes the same habitat, two seeds compose
## different ones, and every layout keeps its promises (each kind present, no overlap, inside the field, clear of
## the nest, sorted by id). The rule is not used by the game yet.

const LandformLayout := preload("res://game/domain/creature/landform_layout.gd")
const RULES_PATH := "res://game/data/creature/landform_rules.json"
const STAGE_PATH := "res://game/data/creature/creature_stage.json"
const SEEDS := 200

var rules: Dictionary


func before_each() -> void:
	rules = _read(RULES_PATH)


func _read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func test_the_shipped_rules_are_valid_and_match_the_creature_field() -> void:
	check_eq(LandformLayout.validate(rules), PackedStringArray())
	var stage := _read(STAGE_PATH)
	check_eq(float(rules.field_half_size_m), float(stage.field_half_size_m), "field size matches creature_stage.json")
	check(float(rules.nest_keep_out_m) >= float(stage.nest_radius_m), "the keep-out covers the nest")
	check_eq((rules.kinds as Dictionary).size(), 4, "river, canyon, island, plateau")
	for kind in ["river", "canyon", "island", "plateau"]:
		check(rules.kinds.has(kind), "kind %s" % kind)


func test_the_same_seed_composes_the_same_layout() -> void:
	for seed_value: int in [0, 1, 42, -7, 9000000000]:
		var a := LandformLayout.compose(seed_value, rules)
		var b := LandformLayout.compose(seed_value, rules)
		check(not a.is_empty(), "seed %d composes" % seed_value)
		check_eq(a, b, "seed %d twice" % seed_value)
		check_eq(LandformLayout.signature(a), LandformLayout.signature(b))


func test_two_seeds_side_by_side_differ() -> void:
	var a := LandformLayout.compose(11, rules)
	var b := LandformLayout.compose(12, rules)
	check(LandformLayout.signature(a) != LandformLayout.signature(b), "seeds 11 and 12 differ")
	var seen := {}
	for seed_value in SEEDS:
		seen[LandformLayout.signature(LandformLayout.compose(seed_value, rules))] = true
	check_eq(seen.size(), SEEDS, "every seed has its own layout")


func test_every_layout_keeps_its_promises() -> void:
	var sizes := {}
	for seed_value in SEEDS:
		var placed := LandformLayout.compose(seed_value, rules)
		check(placed.size() >= 4, "seed %d has at least four pieces" % seed_value)
		check_eq(LandformLayout.first_fault(placed, rules), "", "seed %d" % seed_value)
		sizes[placed.size()] = true
		for p: Dictionary in placed:
			var entry: Dictionary = rules.kinds[p.kind]
			check_eq(float(p.radius_m), float(entry.radius_m))
			check(is_zero_approx(fmod(float(p.turn_deg), float(entry.turn_step_deg))), "%s turn on its step" % p.id)
			check(p.pos is Array and p.pos.size() == 2, "pos is an [x, y] pair")
			check(String(p.id).begins_with(String(p.kind) + "_"), "id names its kind")
	check(sizes.size() > 1, "the piece count varies between seeds")


func test_first_fault_catches_broken_layouts() -> void:
	var placed := LandformLayout.compose(3, rules)
	var moved := placed.duplicate(true)
	moved[0].pos = [0.0, 0.0]
	check(LandformLayout.first_fault(moved, rules).contains("nest"), "a piece on the nest")
	moved = placed.duplicate(true)
	moved[1].pos = moved[0].pos.duplicate()
	check(LandformLayout.first_fault(moved, rules).contains("overlaps"), "two pieces on one spot")
	moved = placed.duplicate(true)
	moved[0].pos = [float(rules.field_half_size_m), 0.0]
	check(LandformLayout.first_fault(moved, rules).contains("field"), "a piece over the wall")
	moved = placed.duplicate(true)
	moved = moved.filter(func(p: Dictionary) -> bool: return p.kind != "river")
	check(LandformLayout.first_fault(moved, rules) != "", "a kind missing")


func test_bad_rules_are_reported() -> void:
	check(not LandformLayout.validate({}).is_empty(), "empty rules")
	check_eq(LandformLayout.compose(1, {}), [], "nothing composed from bad rules")
	var bad := rules.duplicate(true)
	bad.kinds.river.radius_m = 500
	check_has_error(LandformLayout.validate(bad), "does not fit inside the field")
	bad = rules.duplicate(true)
	bad.kinds.island.count = [0, 2]
	check_has_error(LandformLayout.validate(bad), "count needs 1 <= min <= max")
	bad = rules.duplicate(true)
	bad.kinds.canyon.turn_step_deg = 0
	check_has_error(LandformLayout.validate(bad), "turn_step_deg")
	bad = rules.duplicate(true)
	bad.nest_pos = [0]
	check_has_error(LandformLayout.validate(bad), "nest_pos")
	bad = rules.duplicate(true)
	bad.kinds = {}
	check_has_error(LandformLayout.validate(bad), "kinds")


func test_rules_with_no_room_compose_nothing() -> void:
	var tight := rules.duplicate(true)
	tight.field_half_size_m = 30
	check_eq(LandformLayout.validate(tight), PackedStringArray(), "valid, only too tight")
	check_eq(LandformLayout.compose(1, tight), [], "no layout rather than a broken one")
