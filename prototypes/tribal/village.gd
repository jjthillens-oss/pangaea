extends Node2D

const VillageModel = preload("res://village_model.gd")
var model := VillageModel.new()
var notice := "Assign scout to food (1) or forager to material (2)."

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			notice = "Scout reserves food site" if model.assign("scout", "food") else "Food site unavailable"
		KEY_2:
			notice = "Forager reserves material site" if model.assign("forager", "material") else "Material site unavailable"
		KEY_G:
			var success := model.gather("scout") or model.gather("forager")
			notice = "Gather completed" if success else "Assign a reachable site first"
		KEY_B:
			notice = "Shelter built" if model.build_shelter() else "Shelter needs two materials"
		KEY_T:
			notice = "Neighbor traded one food for one material" if model.trade_food() else "Trade needs material and rival food"
		KEY_W:
			model.warn_neighbor()
			notice = "Neighbor warned; relationship worsened"
		KEY_C:
			model.cancel("scout")
			model.cancel("forager")
			notice = "Assignments canceled; reservations released"
		KEY_R:
			model.regenerate()
			notice = "Resource sites regenerated within capacity"
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1000, 620), Color("364b3e"))
	draw_circle(Vector2(260, 340), 105, Color("71926b"))
	draw_circle(Vector2(740, 340), 95, Color("aa795f"))
	draw_rect(Rect2(185, 303, 100, 74), Color("c8ad75") if model.shelter_built else Color("4e6a51"))
	draw_circle(Vector2(460, 270), 33, Color("84b266"))
	draw_circle(Vector2(465, 450), 33, Color("b6aa78"))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(24, 50), "PROPOSED tribal village · %s" % model.lineage_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 25)
	draw_string(font, Vector2(24, 86), notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 19)
	draw_string(font, Vector2(24, 120), "1/2 assign · G gather · B build · T trade · W warn · C cancel · R regrow", HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
	draw_string(font, Vector2(130, 510), "Village: food %d, material %d" % [model.food, model.materials], HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
	draw_string(font, Vector2(625, 510), "Rival: food %d, relation %d" % [model.rival_food, model.rival_relation], HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
	draw_string(font, Vector2(340, 560), "Sites: food %d, material %d · Reservations: %s" % [model.food_site, model.material_site, str(model.reserved_sites)], HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
