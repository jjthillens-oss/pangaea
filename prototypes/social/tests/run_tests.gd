extends SceneTree

const SocialModel = preload("res://social_model.gd")
var failures := 0


func _initialize() -> void:
	test_seeded_determinism_and_tie_order()
	test_help_changes_later_response()
	test_broken_promise_outlasts_help()
	test_cooperation_requires_trust_and_conserves_food()
	test_contest_cost_and_failed_actions()
	print("social: %d failures" % failures)
	quit(1 if failures else 0)


func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + description)


func test_seeded_determinism_and_tie_order() -> void:
	var a := SocialModel.new(77)
	var b := SocialModel.new(77)
	for m in [a, b]:
		m.promise_help("ara")
		m.interact("ara", "share")
		m.interact("bren", "warn")
		m.break_promise("ara")
	check(a.snapshot() == b.snapshot(), "same seed and actions produce byte-identical state")
	check(a.snapshot() != SocialModel.new(78).snapshot(), "different seeds change dispositions or needs")
	for id in SocialModel.IDS:
		a.people[id].disposition = 1
		a.people[id].memory = []
	check(a.best_partner() == "ara", "equal trust selects smallest stable ID")


func test_help_changes_later_response() -> void:
	var m := SocialModel.new(1)
	m.people["ara"].disposition = 0
	m.people["ara"].food_need = 3
	var first: Dictionary = m.interact("ara", "greet")
	check(first.response == "watches cautiously", "initial neutral encounter is cautious")
	check(m.interact("ara", "share").ok, "first food help succeeds")
	check(m.interact("ara", "share").ok, "second food help succeeds")
	check(m.interact("ara", "greet").response == "welcomes", "two recent helps change later greeting")
	check(m.memory_count("ara", "help") == 2, "two named help encounters remain in memory")
	check(m.person("bren").memory.is_empty(), "memory is per individual")


func test_broken_promise_outlasts_help() -> void:
	var m := SocialModel.new(4)
	m.people["ara"].food_need = 3
	check(m.interact("ara", "share").ok, "help is recorded")
	check(m.promise_help("ara"), "promise can be made")
	check(m.break_promise("ara"), "broken promise is recorded")
	for i in range(2):
		m.interact("ara", "greet")
	check(m.memory_count("ara", "help") == 0, "kindness expires after three further encounters")
	check(m.memory_count("ara", "broken") == 1, "broken promise survives kindness")
	for i in range(4):
		m.interact("ara", "greet")
	check(m.memory_count("ara", "broken") == 0, "broken promise also eventually expires")


func test_cooperation_requires_trust_and_conserves_food() -> void:
	var m := SocialModel.new(3)
	m.people["ara"].disposition = 0
	m.people["ara"].food_need = 3
	var before := m.snapshot()
	check(not m.carry_together("ara").ok, "insufficient trust refuses route")
	check(m.snapshot() == before, "refused route spends nothing")
	m.interact("ara", "share")
	m.interact("ara", "share")
	var carried: Dictionary = m.carry_together("ara")
	check(carried.ok, "earned trust permits shared route")
	check(m.route_food == 2 and m.player_food == 2, "two gifts and one route food conserve food")
	check(m.player_stamina == 5 and m.shared_routes == 1 and m.insight == 1, "route has stamina cost and a milestone")
	check(m.adapt_clear_signal(), "route insight buys a clear signal")
	check(m.signal_bonus == 1 and m.insight == 0, "adaptation changes trust without creating insight")
	check(not m.adapt_clear_signal(), "adaptation cannot be purchased twice")


func test_contest_cost_and_failed_actions() -> void:
	var m := SocialModel.new(6)
	var food_before := m.player_food
	var first: Dictionary = m.interact("bren", "challenge")
	check(first.ok and first.response != "", "contest gives a readable result")
	check(m.player_stamina == 4 and m.contests == 1, "contest costs two stamina")
	check(m.player_food == food_before and m.memory_count("bren", "contest") == 1, "contest affects only target memory")
	m.player_stamina = 1
	var before := m.snapshot()
	check(not m.interact("bren", "challenge").ok, "tired contest is refused")
	check(m.snapshot() == before, "failed contest changes nothing")
	check(not m.interact("missing", "share").ok, "unknown individual is refused")
	check(not m.interact("bren", "unknown").ok, "unknown intention is refused")
