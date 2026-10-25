extends TestCase
## World part pickups (domain/creature/part_unlocks.gd, PROPOSED): a lineage starts with the starter parts, finds the
## others as pickups in the creature world, and each find is a "found_part" event in the save's lineage history (no
## schema change). The sim lays the pickups out from their own seeded stream, the stage records finds and preset
## parts, and the editor refuses a locked tool.

const PartUnlocks := preload("res://game/domain/creature/part_unlocks.gd")
const Sim := preload("res://game/systems/creature/creature_world_sim.gd")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const Fixtures := preload("res://tests/creature_fixtures.gd")
const SaveFolder := preload("res://tests/save_folder.gd")
const EditorScene := preload("res://game/scenes/creature/creature_editor.tscn")

## A stand-in for CreatureWorld that reports finds: the stage's world contract plus part_found and locked_parts.
class StubWorld extends Node:
	signal evolve_requested(points: int)
	signal died(cause: String)
	signal part_found(type: String)
	var locked_parts: Array = []
	var seen_locked: Array = []
	func setup(_body: Dictionary, _seed: int, _points: int) -> void:
		seen_locked = locked_parts.duplicate()

## A stand-in for CreatureEditor that keeps what set_locked_parts gave it.
class StubEditor extends Node:
	signal done_requested(body_dict: Dictionary, points_left: int)
	signal back_requested
	var locked: Array = []
	func setup(_body: RefCounted, _points: int) -> void:
		pass
	func set_locked_parts(types: Array) -> void:
		locked = types.duplicate()

var tuning := {}
var data := {}
var path := ""
var _nodes: Array[Node] = []


func before_each() -> void:
	tuning = Sim.load_tuning()
	data = Sim.load_data()
	SaveFolder.clear()
	path = SaveFolder.path("creature_unlocks.json")


func after_each() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	SaveFolder.clear()


func all_types() -> Array:
	var out: Array = CreatureData.part_rules().keys()
	out.sort()
	return out


func starters() -> Array:
	return tuning["pickups"]["starter_parts"]


func sim_with(locked: Array, seed_value := 7) -> CreatureWorldSim:
	var d := data.duplicate()
	d["locked_parts"] = locked
	return Sim.new(Fixtures.body("s1_quadruped").to_dict(), seed_value, tuning, d)


func test_the_starter_parts_are_real_part_types_and_leave_most_to_find() -> void:
	var types := all_types()
	for t in starters():
		check(types.has(t), "starter %s is a part type" % t)
	check(starters().size() >= 10 and types.size() - starters().size() >= 20,
			"%d starters, %d to find" % [starters().size(), types.size() - starters().size()])


func test_finds_and_the_body_unlock_and_everything_else_stays_locked() -> void:
	var history := [{"event": "founded", "generation": 1},
			PartUnlocks.event("wing_dragon", 1), PartUnlocks.event("mane", 2), {"event": "found_part", "part": 7}]
	check_eq(PartUnlocks.found(history), ["mane", "wing_dragon"], "finds in sorted order; a bad entry is skipped")
	var body := {"parts": [{"type": "tusk"}, {"type": "tusk"}, {"type": "jaw"}]}
	var locked := PartUnlocks.locked(["beak", "jaw", "mane", "tusk", "wing_dragon", "quills"], ["beak"], history, body)
	check_eq(locked, ["quills"], "starters, finds and the body's parts are open")
	check_eq(PartUnlocks.commit_events({"parts": [{"type": "quills"}, {"type": "beak"}]}, locked, 3),
			[PartUnlocks.event("quills", 3, PartUnlocks.SOURCE_PRESET)], "a committed locked part is a preset find")


func test_the_draw_takes_each_locked_type_once_and_depends_only_on_the_seed() -> void:
	var a := RandomNumberGenerator.new()
	a.seed = 5
	var b := RandomNumberGenerator.new()
	b.seed = 5
	var locked := ["c", "a", "b", "d", "e"]
	var first := PartUnlocks.draw(locked, 4, a)
	check_eq(first, PartUnlocks.draw(["e", "d", "c", "b", "a"], 4, b), "same seed, same draw, whatever the order")
	var seen := {}
	for t in first:
		check(not seen.has(t) and locked.has(t), "%s drawn once" % t)
		seen[t] = true
	check_eq(PartUnlocks.draw(["x"], 4, a), ["x"], "never more than there are")


func test_no_locked_parts_means_no_pickups_and_the_field_is_unchanged() -> void:
	var plain := Sim.new(Fixtures.body("s1_quadruped").to_dict(), 7, tuning, data)
	check(plain.pickups.is_empty() and not plain.snapshot().has("pickups"), "no pickups without locked parts")
	var locked := PartUnlocks.locked(all_types(), starters(), [], {})
	var with := sim_with(locked)
	check_eq(with.pickups.size(), int(tuning["pickups"]["count"]), "count pickups")
	var a := plain.snapshot()
	var b := with.snapshot()
	b.erase("pickups")
	check_eq(JSON.stringify(a), JSON.stringify(b), "the fruit, rivals and player are drawn as before")
	for k in with.pickups:
		check(locked.has(k["part"]), "%s is a locked part" % k["part"])
		check(Vector2(k["position"].x, k["position"].z).length() > float(tuning["pickups"]["min_nest_distance_m"]),
				"%s lies out of the nest" % k["id"])
	check_eq(JSON.stringify(sim_with(locked).snapshot()), JSON.stringify(with.snapshot()), "deterministic")


func test_walking_onto_a_pickup_finds_it_once_and_earns_its_points() -> void:
	var sim := sim_with(PartUnlocks.locked(all_types(), starters(), [], {}))
	var k: Dictionary = sim.pickups[0]
	var before := sim.points
	sim._place(sim.me, k["position"])
	var events := sim.tick({"move": Vector2.ZERO})
	var found := events.filter(func(e): return e["kind"] == "found_part")
	check_eq(found.size(), 1, "one find")
	check_eq(String(found[0]["part"]), String(k["part"]), "the pickup's part")
	check(k["taken"], "the pickup is taken")
	check_eq(sim.points - before, int(tuning["pickups"]["points"]), "its points")
	var again := sim.tick({"move": Vector2.ZERO}).filter(func(e): return e["kind"] == "found_part")
	check(again.is_empty(), "a taken pickup is not found again")


func _stage() -> CreatureStage:
	var stage := CreatureStage.new()
	stage.make_editor = func() -> Node: return StubEditor.new()
	stage.make_world = func() -> Node: return StubWorld.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(stage)
	_nodes.append(stage)
	stage.setup(path, 99)
	return stage


func test_the_stage_locks_unfound_parts_and_records_a_find_in_the_lineage_history() -> void:
	var stage := _stage()
	var locked := stage.locked_parts()
	check(not locked.is_empty() and not locked.has("jaw") and locked.has("wing_dragon"), "wing locked, jaw open")
	check_eq((stage.editor as StubEditor).locked, locked, "the editor is told")
	stage.enter_world()
	check_eq((stage.world as StubWorld).seen_locked, locked, "the world gets them before setup")
	(stage.world as StubWorld).part_found.emit("wing_dragon")
	check(not stage.locked_parts().has("wing_dragon"), "the wing is found")
	var loaded := PersistenceService.new(PartCatalog.load_from()).load_from(path)
	check(loaded.ok, "the save loads: %s" % [loaded.errors])
	check(PartUnlocks.found(loaded.save.lineage_history).has("wing_dragon"), "and keeps the find")


func test_committing_a_body_with_locked_parts_records_them_as_found() -> void:
	var stage := _stage()
	var body: Dictionary = CreatureData.preset("dragon")["body"]
	check(stage.locked_parts().has("wing_dragon"), "locked before")
	(stage.editor as StubEditor).done_requested.emit(body, 10)
	check(not stage.locked_parts().has("wing_dragon"), "found once committed")
	var events := (stage.save.lineage_history as Array).filter(func(e): return e.get("event") == PartUnlocks.EVENT)
	check(not events.is_empty() and events.all(func(e): return e["source"] == PartUnlocks.SOURCE_PRESET),
			"recorded as preset finds")


func test_the_editor_greys_and_refuses_a_locked_tool_but_not_a_part_on_the_body() -> void:
	var editor: CreatureEditor = EditorScene.instantiate()
	editor.threaded = false
	(Engine.get_main_loop() as SceneTree).root.add_child(editor)
	_nodes.append(editor)
	editor.setup(CreatureData.preset_body("dragon"), 50)
	editor.set_locked_parts(["wing_dragon", "mane"])
	check(not editor.locked.has("wing_dragon"), "the dragon's own wing stays usable")
	check(editor.locked.has("mane") and editor.hud.is_locked("mane"), "the mane is locked and greyed")
	var grid: GridContainer = editor.hud.tools_grid
	check(grid.get_children().find(editor.hud._tool_buttons["mane"]) > grid.get_children().find(editor.hud._tool_buttons["tusk"]),
			"a locked tool sits after the open ones")
	editor.choose_tool("mane")
	check_eq(editor.tool, "", "a locked tool is refused")
	check(editor.refusal_text.contains("world"), "with a reason: %s" % editor.refusal_text)
	editor.choose_tool("wing_dragon")
	check_eq(editor.tool, "wing_dragon", "the wing tool works")
