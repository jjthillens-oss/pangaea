extends TestCase
## The creature editor's Body size control (IB-30, PROPOSED): the session steps the body's reference_length_mm
## inside the tuning's "body_size" range with undo, the range spans the three size tiers with the expected stats
## ordering, the body validates at both ends, the HUD row shows the tier, and the tier's turn factor scales turning.

const Fixtures := preload("res://tests/creature_fixtures.gd")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const Sim := preload("res://game/systems/creature/creature_world_sim.gd")
const Session := preload("res://game/domain/creature/creature_editor_session.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const EDITOR_SCENE := preload("res://game/scenes/creature/creature_editor.tscn")

const BODY := "s1_quadruped"

var tuning := {}
var size_rules := {}
var editor: Node


func before_each() -> void:
	tuning = Sim.load_tuning()
	size_rules = tuning["body_size"]


func after_each() -> void:
	if editor != null:
		editor.free()
		editor = null


func _session() -> RefCounted:
	return Session.new(Fixtures.body(BODY), CreatureData.rules(), CreatureData.part_rules(), CreatureData.editor_costs(), 100)


func _stats(body: RefCounted) -> Dictionary:
	return CreatureStats.of(body, CreatureData.part_rules(), CreatureData.gait_table(), tuning)


func test_a_step_changes_the_reference_length_for_free_and_undo_restores_the_body() -> void:
	var s := _session()
	var before := BodyCodec.encode(s.working)
	var mm: int = s.body_size_mm()
	var r: Dictionary = s.step_body_size(1, size_rules)
	check(r["ok"], "bigger is accepted: %s" % r["reason"])
	check_eq(s.body_size_mm(), mm + int(size_rules["step_mm"]), "one step up")
	check_eq(int(r["length_mm"]), s.body_size_mm(), "the result carries the new length")
	check_eq(s.cost(), 0, "size is free")
	check(s.working.scale_m() > s.original.scale_m(), "the body's scale grows")
	check(s.undo(), "undo")
	check_eq(BodyCodec.encode(s.working), before, "undo restores the byte-identical body")
	check(s.redo(), "redo")
	check_eq(s.body_size_mm(), mm + int(size_rules["step_mm"]), "redo steps up again")
	check(s.step_body_size(-1, size_rules)["ok"] and s.step_body_size(-1, size_rules)["ok"], "two steps down")
	check_eq(s.body_size_mm(), mm - int(size_rules["step_mm"]), "one step under the start")


func test_the_size_clamps_at_both_ends_and_the_body_validates_there() -> void:
	var lo := int(size_rules["min_mm"])
	var hi := int(size_rules["max_mm"])
	for dir in [-1, 1]:
		var s := _session()
		var n := 0
		while s.step_body_size(dir, size_rules)["ok"] and n < 200:
			n += 1
		check(n > 0 and n < 200, "stepping %d stops (%d steps)" % [dir, n])
		check_eq(s.body_size_mm(), lo if dir < 0 else hi, "at the end of the range")
		var again: Dictionary = s.step_body_size(dir, size_rules)
		check(not again["ok"] and again["reason"] != "", "a step past the end is refused with a reason")
		check_eq(s.body_size_mm(), lo if dir < 0 else hi, "and changes nothing")
		check_eq(Array(s.errors_of(s.working)), [], "the body validates at %d mm" % s.body_size_mm())
		var done: Dictionary = s.commit()
		check(done["ok"], "and commits: %s" % str(done["errors"]))
		check_eq(int(done["points_left"]), 100, "for no points")
		check_eq(int(BodyCodec.from_dict(done["body"].to_dict()).reference_length_mm), s.body_size_mm(), "the size rides in the body")


func test_the_range_crosses_the_three_tiers_with_the_expected_ordering() -> void:
	var small_s := _session()
	check(small_s.set_body_size(int(size_rules["min_mm"]), int(size_rules["min_mm"]), int(size_rules["max_mm"]))["ok"], "to the smallest")
	var large_s := _session()
	check(large_s.set_body_size(int(size_rules["max_mm"]), int(size_rules["min_mm"]), int(size_rules["max_mm"]))["ok"], "to the largest")
	var small := _stats(small_s.working)
	var medium := _stats(_session().working)
	var large := _stats(large_s.working)
	check_eq([small["size_tier"], medium["size_tier"], large["size_tier"]], ["small", "medium", "large"], "the three tiers")
	check(large["bite_reach_m"] > medium["bite_reach_m"] and medium["bite_reach_m"] > small["bite_reach_m"], "reach grows with size")
	check(large["energy_use_factor"] > medium["energy_use_factor"] and medium["energy_use_factor"] > small["energy_use_factor"], "energy use grows with size")
	check(large["turn_factor"] < medium["turn_factor"] and medium["turn_factor"] < small["turn_factor"], "turning falls with size")
	check_eq(medium["turn_factor"], 1.0, "medium turning is exactly 1")


## The world multiplies the turn command by the stats' turn_factor (creature_world_sim.gd _drive): the same planner
## turns slower with the large tier's factor and exactly the same with medium's.
func test_the_turn_factor_scales_the_turn_rate() -> void:
	var large_factor := 0.0
	for t: Dictionary in tuning["size_tiers"]["tiers"]:
		if t["id"] == "large":
			large_factor = float(t["turn"])
	var yaws := []
	for factor in [1.0, large_factor]:
		var planner = Fixtures.planner("quad_short")
		for i in 120:
			planner.step(Sim.DT, 0.3, 1.0 * factor)
		yaws.append(absf(planner.yaw))
	check(yaws[0] > 0.0, "the planner turns (%.3f rad)" % yaws[0])
	check(yaws[1] < yaws[0], "a large body turns less in the same time (%.3f < %.3f rad)" % [yaws[1], yaws[0]])
	var src := FileAccess.get_file_as_string("res://game/systems/creature/creature_world_sim.gd")
	check(src.contains("command.y * float(c[\"stats\"].get(\"turn_factor\", 1.0))"), "the world's drive applies turn_factor")


func test_the_editor_row_steps_the_body_shows_the_tier_and_refits_the_camera() -> void:
	editor = EDITOR_SCENE.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(editor)
	editor.setup(CreatureData.body("quadruped"), 100)
	var shown: Dictionary = editor.hud.body_size_shown()
	check(String(shown["value"]).contains("Medium"), "the row shows the tier: %s" % shown["value"])
	var mm: int = editor.session.body_size_mm()
	var far: float = editor._frame_distance
	editor.hud.body_size_step.emit(1)
	check(editor.session.body_size_mm() > mm, "the Bigger button steps the body")
	editor._rebuild()
	check(editor._frame_distance > far, "the camera backs off for the bigger body")
	var n := 0
	while editor.step_body_size(1)["ok"] and n < 200:
		n += 1
	editor._rebuild()
	shown = editor.hud.body_size_shown()
	check_eq(editor.body_size_tier(), "large", "the largest body is large")
	check(String(shown["value"]).contains("Large") and String(shown["hint"]).begins_with("Large"), "the row says so: %s / %s" % [shown["value"], shown["hint"]])
	check(not shown["can_bigger"] and shown["can_smaller"], "Bigger greys at the end")
	check(editor.refusal_text != "", "the refused step shows its reason")
	editor.undo()
	editor._rebuild()
	check(editor.session.body_size_mm() < int(size_rules["max_mm"]), "undo steps back")


func test_parts_keep_their_proportion_when_the_body_changes_size() -> void:
	var s: RefCounted = Session.new(CreatureData.body("quadruped"), CreatureData.rules(), CreatureData.part_rules(),
			CreatureData.editor_costs(), 100)
	check(not s.working.parts.is_empty(), "the preset carries parts")
	var mm: int = s.body_size_mm()
	var before: Array = s.working.parts.map(func(p): return int(p["scale"]))
	check(s.set_body_size(mm * 2, 100, 8000)["ok"], "twice the size")
	for i in before.size():
		check_eq(int(s.working.parts[i]["scale"]), mini(before[i] * 2, int(CreatureData.rules()["part_scale_max"])),
				"part %d doubles with the body" % i)
	check_eq(s.cost(), 0, "size is still free with parts on the body")
	check(s.undo(), "undo")
	check_eq(s.working.parts.map(func(p): return int(p["scale"])), before, "undo restores every part's scale")
