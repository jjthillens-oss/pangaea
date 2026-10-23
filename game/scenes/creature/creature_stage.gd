class_name CreatureStage
extends Node
## The creature stage's root (creature-stage plan sections 3 to 5, PROPOSED): Main hosts it as the screen. It holds
## one child screen at a time, the editor (CreatureEditor) or the world (CreatureWorld), owns the stage's state and
## its save file (CreatureStore, under user://creature_stage/, never the lineage slot) and answers the screens:
##   editor.done_requested  -> the committed body and points go into the state, saved, then the world opens
##   editor.back_requested  -> saved, then exit_requested (Main shows the title)
##   world.evolve_requested -> the points go into the state, saved, then the editor opens
##   world.died             -> saved
## Escape in the world goes back to the editor; in the editor it asks the editor to go back (the title), unless the
## editor took the key itself; on the missing-scenes notice it exits.
##
## The editor and world scenes are loaded by path at play time (never preloaded), so this script runs without them:
## when a scene is missing, the stage says so in a Label, warns once and still exits. Tests inject plain Nodes with
## the screens' signals through make_editor / make_world (a Callable returning a Node, or null for "missing").

signal exit_requested

const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const EDITOR_SCENE_PATH := "res://game/scenes/creature/creature_editor.tscn"
const WORLD_SCENE_PATH := "res://game/scenes/creature/creature_world.tscn"
const MISSING_TEXT := "Creature stage scenes missing"

## The stage's state (CreatureStore.new_state's keys); saved by save_now().
var state: Dictionary = {}
## The file the state is saved to (CreatureStore.default_path of the slot).
var store_path := ""
var store: CreatureStore
## Why the store file could not be read (empty when it loaded or did not exist yet); the state is then fresh.
var load_problems: PackedStringArray = []
## The screen shown now: the editor, the world, or null (the missing-scenes notice).
var editor: Node
var world: Node
## The seam the tests use: each returns the screen's Node, or null when its scene is missing. The defaults load
## the scenes by path.
var make_editor: Callable = Callable(self, "_instantiate").bind(EDITOR_SCENE_PATH)
var make_world: Callable = Callable(self, "_instantiate").bind(WORLD_SCENE_PATH)
## The last save attempt's result (OK before any).
var last_save: Error = OK

var _mode := "editor"
var _screen: Node
var _missing_label: Label
var _warned := false


## Loads the state from `p_store_path`, or starts fresh with `world_seed` (keeping the load's reasons in
## load_problems), then opens the editor.
func setup(p_store_path: String, world_seed: int) -> void:
	store_path = p_store_path
	if store == null:
		store = CreatureStore.new()
	load_problems = PackedStringArray()
	var loaded := store.load_from(store_path)
	if loaded.ok:
		state = loaded.state
	else:
		state = CreatureStore.new_state(world_seed)
		if FileAccess.file_exists(store_path):
			load_problems = loaded.errors
			for problem in load_problems:
				push_warning("Creature stage: %s Starting fresh; the file is left as it is." % problem)
	open_editor()


## "editor" or "world": the screen asked for, whether or not its scene was there.
func mode() -> String:
	return _mode


## Shows the editor on the state's body and points.
func open_editor() -> void:
	_mode = "editor"
	_clear_screen()
	editor = make_editor.call()
	if editor == null:
		_show_missing()
		return
	_add_screen(editor)
	if editor.has_method("setup"):
		editor.call("setup", BodyCodec.from_dict(state["body"]), int(state["points"]))
	_connect(editor, "done_requested", _on_editor_done)
	_connect(editor, "back_requested", _on_editor_back)


## Shows the world on the state's body, seed and points.
func enter_world() -> void:
	_mode = "world"
	_clear_screen()
	world = make_world.call()
	if world == null:
		_show_missing()
		return
	_add_screen(world)
	if world.has_method("setup"):
		world.call("setup", state["body"], int(state["world_seed"]), int(state["points"]))
	_connect(world, "evolve_requested", _on_world_evolve)
	_connect(world, "died", _on_world_died)


## Writes the state to the store. A failure is warned about and kept in last_save; play goes on.
func save_now() -> Error:
	if store == null or store_path.is_empty():
		return ERR_UNCONFIGURED
	last_save = store.save_to(store_path, state)
	if last_save != OK:
		push_warning("Creature stage: could not save to %s (%s)." % [store_path, error_string(last_save)])
	return last_save


## Leaves the stage: saves, then asks Main for the title.
func back() -> void:
	save_now()
	exit_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	press_escape()


## Escape's method twin: in the world back to the editor; in the editor the editor's own back (the title); on the
## missing-scenes notice out of the stage.
func press_escape() -> void:
	if _mode == "world" and world != null:
		_leave_world()
	elif _mode == "editor" and editor != null:
		if editor.has_method("back"):
			editor.call("back")
		else:
			back()
	else:
		back()


func _on_editor_done(body_dict: Dictionary, points_left: int) -> void:
	state["body"] = body_dict.duplicate(true)
	state["points"] = points_left
	save_now()
	enter_world()


func _on_editor_back() -> void:
	back()


## The world asks for the editor: the points earned come along, the generation advances and the one before is
## kept in the history.
func _on_world_evolve(points: int) -> void:
	_take_points(points)
	state["history"].append({"generation": int(state["generation"]), "points": int(state["points"]),
			"body_sha256": BodyCodec.hash_text(BodyCodec.from_dict(state["body"]))})
	state["generation"] = int(state["generation"]) + 1
	save_now()
	open_editor()


## The world reports a death: the sim has already taken its share of the points; keep what is left.
func _on_world_died(_cause: String) -> void:
	_take_points(_world_points())
	save_now()


## Escape in the world: back to the editor with the points the sim holds now.
func _leave_world() -> void:
	_take_points(_world_points())
	save_now()
	open_editor()


func _take_points(points: int) -> void:
	if points >= 0:
		state["points"] = points


## The points the world's sim holds, or -1 when it has none to report (a stub, or no sim yet).
func _world_points() -> int:
	if world == null:
		return -1
	var sim = world.get("sim")
	if sim == null:
		return -1
	var points = sim.get("points")
	return int(points) if points is int or points is float else -1


func _instantiate(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	return scene.instantiate() if scene != null else null


func _add_screen(node: Node) -> void:
	_screen = node
	add_child(node)


func _clear_screen() -> void:
	if _screen != null:
		remove_child(_screen)
		_screen.queue_free()
	_screen = null
	editor = null
	world = null
	if _missing_label != null:
		_missing_label.queue_free()
		_missing_label = null


func _show_missing() -> void:
	if not _warned:
		push_warning("%s: %s or %s is not in this build; Escape leaves the stage." % [MISSING_TEXT, EDITOR_SCENE_PATH,
				WORLD_SCENE_PATH])
		_warned = true
	_missing_label = Label.new()
	_missing_label.name = "MissingScenes"
	_missing_label.text = MISSING_TEXT
	_missing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_missing_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_missing_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_missing_label)


static func _connect(node: Node, signal_name: String, target: Callable) -> void:
	if node.has_signal(signal_name):
		node.connect(signal_name, target)
	else:
		push_warning("Creature stage: the %s screen has no %s signal." % [node.name, signal_name])
