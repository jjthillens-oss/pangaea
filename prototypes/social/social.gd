extends Node2D

const SocialModel = preload("res://social_model.gd")

var model := SocialModel.new(2026)
var selected := "ara"
var notice := "Choose a neighbor (1-3), then signal or share."


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var outcome := {}
	match event.keycode:
		KEY_1:
			selected = "ara"
		KEY_2:
			selected = "bren"
		KEY_3:
			selected = "cyra"
		KEY_G:
			outcome = model.interact(selected, "greet")
		KEY_S:
			outcome = model.interact(selected, "share")
		KEY_W:
			outcome = model.interact(selected, "warn")
		KEY_C:
			outcome = model.interact(selected, "challenge")
		KEY_P:
			notice = "Help promised" if model.promise_help(selected) else "Promise already made"
		KEY_X:
			notice = "Broken promise remembered" if model.break_promise(selected) else "No promise to break"
		KEY_F:
			outcome = model.carry_together(selected)
		KEY_A:
			notice = "Clearer signal adopted" if model.adapt_clear_signal() else "Complete a shared route first"
	if not outcome.is_empty():
		notice = str(outcome.response)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1000, 650), Color("243d4a"))
	draw_rect(Rect2(95, 210, 810, 275), Color("38544e"))
	draw_rect(Rect2(95, 360, 810, 55), Color("6b7556"))
	draw_circle(Vector2(505, 390), 42, Color("aa704f"))
	draw_circle(Vector2(505, 390), 21, Color("d6af75"))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(30, 44), "PROPOSED Social Stage | seed %d" % model.seed, HORIZONTAL_ALIGNMENT_LEFT, -1, 25)
	draw_string(font, Vector2(30, 78), notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	draw_string(font, Vector2(30, 112), "1-3 select | G greet | S share | W warn | C contest | P promise | X break", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string(font, Vector2(30, 140), "F carry together | A adapt signal", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	for index in SocialModel.IDS.size():
		var id: String = SocialModel.IDS[index]
		var p: Dictionary = model.person(id)
		var x := 220.0 + index * 280.0
		var chosen := id == selected
		draw_circle(Vector2(x, 290), 39, Color("d2b481") if chosen else Color("8db4ae"))
		draw_string(font, Vector2(x - 53, 350), "%s%s" % [id, " <" if chosen else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		draw_string(font, Vector2(x - 105, 445), "disposition %d | food need %d" % [p.disposition, p.food_need], HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
		draw_string(font, Vector2(x - 100, 470), "danger %d | trust %d" % [p.danger_need, model.trust(id)], HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	draw_string(font, Vector2(30, 550), "Food %d | Stamina %d | Route food %d | Insight %d" % [model.player_food, model.player_stamina, model.route_food, model.insight], HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	draw_string(font, Vector2(30, 580), "Shared routes %d | Contests %d | Best partner %s" % [model.shared_routes, model.contests, model.best_partner()], HORIZONTAL_ALIGNMENT_LEFT, -1, 18)

