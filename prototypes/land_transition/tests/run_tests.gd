extends SceneTree

const TransitionModel = preload("res://transition_model.gd")
const ShoreView = preload("res://shore.gd")
var failures := 0

func _initialize() -> void:
	test_shore_gate()
	test_stamina_and_rest()
	test_editor_and_lineage()
	test_editor_input_handoff()
	print("land_transition: %d failures" % failures)
	quit(1 if failures else 0)

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + description)

func test_shore_gate() -> void:
	var m := TransitionModel.new()
	check(not m.open_editor(), "editor cannot open in water")
	m.crawl(1.0, 3.0)
	check(m.stage == "aquatic", "crawling does not skip aquatic stage")
	check(not m.open_editor(), "shore approach alone does not open editor")
	m.support = 0.8
	m.crawl(1.0, 10.0)
	check(m.x < TransitionModel.EDITOR_X, "stamina bounds a long crawl")
	for i in range(5):
		m.rest(20.0)
		m.crawl(1.0, 2.0)
	check(m.shoreline_seen, "shoreline event is recorded")
	check(m.can_open_editor(), "viable body reaches editor gate")

func test_stamina_and_rest() -> void:
	var m := TransitionModel.new()
	m.x = TransitionModel.SHORE_X
	m.stamina = 0.0
	m.crawl(1.0, 2.0)
	check(is_equal_approx(m.x, TransitionModel.SHORE_X), "exhausted body cannot advance on land")
	m.rest(2.0)
	m.crawl(1.0, 1.0)
	check(m.x > TransitionModel.SHORE_X, "rest enables bounded crawl")
	check(m.stamina >= 0.0, "stamina never negative")

func test_editor_and_lineage() -> void:
	var m := TransitionModel.new()
	m.x = TransitionModel.EDITOR_X
	check(not m.open_editor(), "insufficient support blocks handoff")
	m.support = 0.6
	check(m.open_editor(), "qualified lineage opens editor")
	check(not m.choose_land_support(0.2), "editor rejects weak support")
	check(m.stage == "aquatic", "rejected edit keeps prior stage")
	check(m.choose_land_support(0.8), "editor commits viable support")
	check(m.stage == "terrestrial", "commit changes stage")
	check(
		m.lineage_id == "founding-lineage" and m.ancestral_feeding == "filter",
		"identity and feeding ancestry persist"
	)
	check(not m.editor_open, "editor closes after commit")

func test_editor_input_handoff() -> void:
	var view := ShoreView.new()
	root.add_child(view)
	view.model.x = TransitionModel.EDITOR_X
	view.model.support = 0.8
	view._unhandled_key_input(_press(KEY_ENTER))
	check(view.model.editor_open, "Enter opens the visible editor state")
	view._unhandled_key_input(_press(KEY_1))
	check(is_equal_approx(view.selected_support, 0.6), "first choice updates the editor preview")
	view._unhandled_key_input(_press(KEY_ENTER))
	check(view.model.stage == "terrestrial", "committing the selected support changes era")
	check(is_equal_approx(view.model.support, 0.6), "committed support is the selected option")
	view.queue_free()

func _press(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event
