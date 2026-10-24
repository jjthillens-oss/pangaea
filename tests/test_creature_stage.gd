extends TestCase
## The creature stage root (game/scenes/creature/creature_stage.gd): the state flow between the editor and the world
## and its saves, driven with stub screens (plain Nodes with the contract's signals, injected through the stage's
## make_editor / make_world seam), so it runs without the editor and world scenes. The stage writes into the lineage
## save (schema v3, SaveGame.creature and adaptation_points); a slot that will not load is shown, never written over;
## a missing scene shows the notice and still exits. Files go to the per-process folder under
## user://test_saves.

const SaveFolder := preload("res://tests/save_folder.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")

## A stand-in for CreatureEditor: the contract's signals and setup(body, points).
class StubEditor extends Node:
	signal done_requested(body_dict: Dictionary, points_left: int)
	signal back_requested
	var body: RefCounted
	var points := -1
	var backs := 0
	func setup(p_body: RefCounted, p_points: int) -> void:
		body = p_body
		points = p_points
	func back() -> void:
		backs += 1
		back_requested.emit()

## The world HUD's title seam: set_title(name, generation).
class StubHud extends RefCounted:
	var title := ""
	func set_title(creature_name: String, generation: int) -> void:
		title = "%s · Generation %d" % [creature_name, generation]

## A stand-in for CreatureWorld: the contract's signals, setup(body_dict, seed, points), a sim with points and a
## hud with set_title.
class StubWorld extends Node:
	signal evolve_requested(points: int)
	signal died(cause: String)
	var body_dict := {}
	var world_seed := -1
	var points := -1
	var sim: RefCounted
	var hud := StubHud.new()
	func setup(p_body: Dictionary, p_seed: int, p_points: int) -> void:
		body_dict = p_body
		world_seed = p_seed
		points = p_points

class StubSim extends RefCounted:
	var points := 0

var path := ""
var exits := 0
var _nodes: Array[Node] = []


func before_each() -> void:
	SaveFolder.clear()
	path = SaveFolder.path("creature_stage.json")
	exits = 0


func after_each() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	SaveFolder.clear()


## A stage with stub screens (or none when `editor_scene` / `world_scene` is false), in the tree so children get
## _ready, set up on `path` with seed 99.
func _stage(editor_scene := true, world_scene := true, seed_value := 99) -> CreatureStage:
	var stage := CreatureStage.new()
	stage.make_editor = func() -> Node: return StubEditor.new() if editor_scene else null
	stage.make_world = func() -> Node: return StubWorld.new() if world_scene else null
	stage.exit_requested.connect(func(): exits += 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(stage)
	_nodes.append(stage)
	stage.setup(path, seed_value)
	return stage


## The lineage save in `path`, read the way Continue reads it.
func _loaded() -> Dictionary:
	return PersistenceService.new(PartCatalog.load_from()).load_from(path)


func _escape(stage: CreatureStage) -> void:
	stage.press_escape()


func test_a_fresh_stage_opens_the_editor_on_the_starter_body() -> void:
	var stage := _stage()
	check_eq(stage.mode(), "editor", "opens in the editor")
	check(stage.load_problems.is_empty(), "no file yet is not a problem: %s" % [stage.load_problems])
	check(stage.editor is StubEditor and stage.world == null, "the editor is the screen")
	var editor := stage.editor as StubEditor
	check_eq(editor.points, CreatureRules.start_points(), "with the start points")
	check_eq(BodyCodec.encode(editor.body), BodyCodec.encode(CreatureData.body("s1_quadruped")), "and the starter quadruped")
	check_eq(stage.state["world_seed"], 99, "the seed given")
	check(not FileAccess.file_exists(path), "nothing is written until something happens")


func test_done_saves_the_committed_body_and_enters_the_world() -> void:
	var stage := _stage()
	var body: RefCounted = CreatureData.body("s1_biped")
	(stage.editor as StubEditor).done_requested.emit(body.to_dict(), 120)
	check_eq(stage.mode(), "world", "the world is the screen")
	check(stage.world is StubWorld and stage.editor == null, "the editor is gone")
	var world := stage.world as StubWorld
	check_eq(world.points, 120, "the world gets the points left")
	check_eq(world.world_seed, 99, "and the seed")
	check_eq(BodyCodec.encode(BodyCodec.from_dict(world.body_dict)), BodyCodec.encode(body), "and the committed body")
	check_eq((world.hud as StubHud).title, "Newcomer · Generation 1", "the HUD's title names the creature and generation")
	check(stage.editor_scene() == null and stage.world_scene() == null, "the typed scenes are null for stubs")
	check_eq(stage.last_save, OK, "saved")
	var loaded := _loaded()
	check(loaded.ok, "the lineage save loads back: %s" % [loaded.errors])
	var save: SaveGame = loaded.save
	check_eq(int(JSON.parse_string(FileAccess.get_file_as_string(path))["schema_version"]), SaveGame.SCHEMA_VERSION,
			"at the current schema")
	check_eq(save.adaptation_points, 120, "with the points as adaptation points")
	check_eq(BodyCodec.encode(BodyCodec.from_dict(save.creature["body"])), BodyCodec.encode(body), "and the body")
	check_eq(save.world_seed, 99, "and the seed")
	check(not FileAccess.file_exists(path + PersistenceService.TEMP_SUFFIX), "no .tmp left")


func test_evolve_saves_the_points_and_reopens_the_editor() -> void:
	var stage := _stage()
	(stage.editor as StubEditor).done_requested.emit(CreatureData.body("s1_quadruped").to_dict(), 100)
	(stage.world as StubWorld).evolve_requested.emit(175)
	check_eq(stage.mode(), "editor", "back in the editor")
	check(stage.editor is StubEditor and stage.world == null, "the world is gone")
	check_eq((stage.editor as StubEditor).points, 175, "the editor gets the points earned")
	check_eq(stage.state["generation"], 2, "the generation advanced")
	(stage.editor as StubEditor).done_requested.emit(CreatureData.body("s1_quadruped").to_dict(), 175)
	check_eq(((stage.world as StubWorld).hud as StubHud).title, "Newcomer · Generation 2", "the next world's title says so")
	check_eq((stage.state["history"] as Array).size(), 1, "the generation before is in the history")
	check_eq(stage.state["history"][0]["generation"], 1, "as generation 1")
	var loaded := _loaded()
	check(loaded.ok, "the lineage save loads back: %s" % [loaded.errors])
	check_eq((loaded.save as SaveGame).adaptation_points, 175, "with the points")
	check_eq((loaded.save as SaveGame).creature["generation"], 2, "and the generation")
	check_eq(((loaded.save as SaveGame).creature["history"] as Array).size(), 1, "and the history")


func test_a_death_saves_what_the_sim_holds() -> void:
	var stage := _stage()
	(stage.editor as StubEditor).done_requested.emit(CreatureData.body("s1_quadruped").to_dict(), 100)
	var world := stage.world as StubWorld
	var sim := StubSim.new()
	sim.points = 80
	world.sim = sim
	world.died.emit("bitten")
	check_eq(stage.mode(), "world", "a death stays in the world")
	check_eq(stage.state["points"], 80, "the points after the death's loss")
	check_eq((_loaded().save as SaveGame).adaptation_points, 80, "saved")
	sim.points = 130
	_escape(stage)
	check_eq(stage.mode(), "editor", "Escape in the world goes back to the editor")
	check_eq((stage.editor as StubEditor).points, 130, "with the points the sim held")
	check_eq(exits, 0, "without leaving the stage")


func test_save_now_in_the_world_keeps_the_points_the_sim_holds() -> void:
	var stage := _stage()
	(stage.editor as StubEditor).done_requested.emit(CreatureData.body("s1_quadruped").to_dict(), 100)
	var sim := StubSim.new()
	sim.points = 160
	(stage.world as StubWorld).sim = sim
	check_eq(stage.save_now(), OK, "a quit's save_now() from the world")
	check_eq(stage.state["points"], 160, "takes the sim's points first")
	check_eq((_loaded().save as SaveGame).adaptation_points, 160, "and writes them")
	check_eq(stage.mode(), "world", "without leaving the world")


func test_back_saves_and_asks_main_for_the_title() -> void:
	var stage := _stage()
	_escape(stage)
	check_eq((stage.editor as StubEditor).backs, 1, "Escape in the editor asks the editor to go back")
	check_eq(exits, 1, "which leaves the stage")
	check(_loaded().ok, "saved on the way out")


func test_a_saved_stage_comes_back_as_it_was() -> void:
	var first := _stage()
	var body: RefCounted = CreatureData.body("s1_hexapod")
	(first.editor as StubEditor).done_requested.emit(body.to_dict(), 60)
	(first.world as StubWorld).evolve_requested.emit(90)
	var second := _stage(true, true, 5)
	check(second.load_problems.is_empty(), "the file read: %s" % [second.load_problems])
	check_eq(second.state["world_seed"], 99, "the saved seed, not the one given")
	check_eq(second.state["generation"], 2, "the saved generation")
	check_eq((second.editor as StubEditor).points, 90, "the saved points")
	check_eq(BodyCodec.encode((second.editor as StubEditor).body), BodyCodec.encode(body), "the saved body")


func test_a_slot_that_will_not_load_is_shown_and_never_written() -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var text := "{\"schema_version\": 3, \"adaptation_points\": \"lots\"}"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var stage := _stage()
	check_eq(stage.mode(), "problems", "the problems are the screen")
	check(not stage.load_problems.is_empty(), "the problems are kept")
	check(stage.editor == null and stage.world == null, "no editor or world")
	var label := stage.get_node_or_null("LoadProblems") as Label
	check(label != null and label.text.contains(stage.load_problems[0]), "the label says why")
	check_eq(stage.save_now(), ERR_UNCONFIGURED, "save_now() refuses")
	_escape(stage)
	check_eq(exits, 1, "Escape leaves the stage")
	check_eq(FileAccess.get_file_as_string(path), text, "the file is left as it is")
	check(not FileAccess.file_exists(path + PersistenceService.BACKUP_SUFFIX), "and nothing else is written")


func test_a_lineage_from_the_cell_stage_keeps_its_points_and_seed() -> void:
	var cell: SaveGame = Lineage.found(4242, "test", PartCatalog.load_from(), "grazer").save
	cell.adaptation_points = 37
	check_eq(PersistenceService.new(PartCatalog.load_from()).save_to(path, cell), OK, "a cell-stage save")
	var stage := _stage()
	check(stage.load_problems.is_empty(), "loads: %s" % [stage.load_problems])
	check_eq((stage.editor as StubEditor).points, 37, "the editor gets the lineage's points")
	check_eq(stage.state["world_seed"], 4242, "and its seed")
	check_eq(stage.state["generation"], 1, "the starter creature at generation 1")
	(stage.editor as StubEditor).done_requested.emit(CreatureData.body("s1_quadruped").to_dict(), 20)
	var save: SaveGame = _loaded().save
	check_eq(save.adaptation_points, 20, "the points spent in the editor")
	check_eq(save.lineage_id, cell.lineage_id, "the same lineage")
	check_eq(save.genome.to_dict(), cell.genome.to_dict(), "the cell's genome is kept")


func test_missing_scenes_show_a_notice_and_still_exit() -> void:
	var stage := _stage(false, false)
	check_eq(stage.mode(), "editor", "the editor was asked for")
	check(stage.editor == null and stage.world == null, "no screen")
	var label := stage.get_node_or_null("MissingScenes") as Label
	check(label != null and label.text == CreatureStage.MISSING_TEXT, "the notice names the problem")
	_escape(stage)
	check_eq(exits, 1, "Escape leaves the stage")
	var no_world := _stage(true, false)
	(no_world.editor as StubEditor).done_requested.emit(CreatureData.body("s1_quadruped").to_dict(), 50)
	check_eq(no_world.mode(), "world", "the world was asked for")
	check(no_world.get_node_or_null("MissingScenes") != null, "and reported missing")
	check(_loaded().ok, "the commit was saved first")
	no_world.back()
	check_eq(exits, 2, "back() leaves too")
