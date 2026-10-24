extends Node2D

const TransitionModel = preload("res://transition_model.gd")
var model := TransitionModel.new()
var status := "A cell lineage reached the aquatic shore. Move right to crawl."
var selected_support := 0.8

func _process(delta: float) -> void:
	var direction := Input.get_axis("ui_left", "ui_right")
	model.crawl(direction, delta)
	if Input.is_action_pressed("ui_down"):
		model.rest(delta)
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ENTER:
		if model.editor_open:
			if model.choose_land_support(selected_support):
				status = "Land support selected. Same lineage enters Terrestrial play."
		elif model.open_editor():
			status = "Creature editor open: choose support, then commit."
		else:
			status = "Reach dry ground with enough support and stamina."
	elif model.editor_open and event.keycode == KEY_1:
		selected_support = 0.6
		status = "Creature editor: flexible support selected."
	elif model.editor_open and event.keycode == KEY_2:
		selected_support = 0.8
		status = "Creature editor: sturdy support selected."
	elif event.keycode == KEY_R:
		model = TransitionModel.new()
		selected_support = 0.8
		status = "A cell lineage reached the aquatic shore. Move right to crawl."

func _draw() -> void:
	draw_rect(Rect2(0, 170, 1000, 430), Color("315d78"))
	draw_rect(Rect2(TransitionModel.SHORE_X, 170, 700, 430), Color("987a51"))
	draw_line(
		Vector2(TransitionModel.SHORE_X, 170), Vector2(TransitionModel.SHORE_X, 600),
		Color.WHITE, 3
	)
	draw_circle(Vector2(model.x, 380), 25, Color("94d6b8"))
	draw_circle(Vector2(model.x + 9, 371), 5, Color("18383d"))
	var font := ThemeDB.fallback_font
	draw_string(
		font, Vector2(28, 55), "PROPOSED: Microscopic → Aquatic → Terrestrial",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24
	)
	draw_string(font, Vector2(28, 94), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 19)
	draw_string(
		font, Vector2(28, 128), "Arrows move · Down rests · Enter opens/commits editor · R resets",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17
	)
	var state_text := "Lineage: %s   Feeding: %s   Stage: %s   Stamina: %d" % [
		model.lineage_id, model.ancestral_feeding, model.stage, int(model.stamina)
	]
	draw_string(font, Vector2(28, 553), state_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
	if model.editor_open:
		draw_rect(Rect2(220, 170, 590, 290), Color("1f3439"))
		draw_rect(Rect2(230, 180, 570, 270), Color("39625b"), false, 3)
		_editor_line(font, "CREATURE EDITOR · shore support", 218, 23)
		_editor_line(font, "Same lineage and feeding ancestry continue.", 260, 18)
		_editor_line(font, "1 · Flexible support: 0.6 · easier turns", 308, 18)
		_editor_line(font, "2 · Sturdy support: 0.8 · longer crawl", 342, 18)
		var choice := "Selected support: %.1f · Enter commits" % selected_support
		_editor_line(font, choice, 399, 18)

func _editor_line(font: Font, content: String, y: float, size: int) -> void:
	draw_string(font, Vector2(250, y), content, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
