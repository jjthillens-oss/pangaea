extends Node2D

const TransitionModel = preload("res://transition_model.gd")
var model := TransitionModel.new()
var status := "A cell lineage reached the aquatic shore. Move right to crawl."

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
			if model.choose_land_support(0.8):
				status = "Land support selected. Same lineage enters Terrestrial play."
		elif model.open_editor():
			status = "Creature editor open: Enter commits a support adaptation."
		else:
			status = "Reach dry ground with enough support and stamina."
	elif event.keycode == KEY_R:
		model = TransitionModel.new()
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
