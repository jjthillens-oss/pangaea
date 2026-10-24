class_name CreatureStage
extends Node
## The creature stage's root (creature-stage plan sections 3 to 5, PROPOSED): Main hosts it as the screen. It holds
## one child screen at a time, the editor (CreatureEditor) or the world (CreatureWorld), owns the stage's state and
## writes it into the lineage save (save schema v3, SaveGame.creature; its points are the save's adaptation_points;
## owner direction of 2026-10-24: follow the Bible, section 18) through PersistenceService, and answers the screens:
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

## The stage's working view of the save: {"name", "body", "points", "world_seed", "generation", "history"}.
## save_now() writes it back into `save` (points into adaptation_points, the rest into save.creature).
var state: Dictionary = {}
## The lineage slot the stage reads and writes (the session's slot).
var slot_path := ""
## The lineage save the state belongs to; null when the slot exists but would not load (nothing is then written).
var save: SaveGame
var persistence: PersistenceService
## Why the slot could not be loaded; when not empty the stage shows them and never writes over the file.
var load_problems: PackedStringArray = []
## The screen shown now: the editor, the world, or null (the missing-scenes notice). Nodes, since the tests inject
## stubs through make_editor / make_world; editor_scene() and world_scene() give the real scenes typed.
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


## Loads the lineage save in `p_slot_path` (its backup when the file is bad, as Continue does). A slot with no save
## founds a lineage here (Lineage.found with `world_seed` and the omnivore cell, the stage's start points); a lineage that has not met
## the creature stage gets the starter creature and keeps its points. A slot that exists but will not load is left
## untouched: the stage shows why and only lets the player leave. Then the editor opens.
func setup(p_slot_path: String, world_seed: int) -> void:
	slot_path = p_slot_path
	if persistence == null:
		persistence = PersistenceService.new(PartCatalog.load_from())
	load_problems = PackedStringArray()
	save = null
	var exists := FileAccess.file_exists(slot_path) or FileAccess.file_exists(slot_path + PersistenceService.BACKUP_SUFFIX) \
			or FileAccess.file_exists(slot_path + PersistenceService.TEMP_SUFFIX)
	if exists:
		var loaded := persistence.load_from(slot_path)
		if loaded.ok:
			save = loaded.save
		else:
			load_problems = loaded.errors
			for problem in load_problems:
				push_warning("Creature stage: %s The save is left as it is." % problem)
			_show_problems()
			return
	else:
		var founded := Lineage.found(world_seed, BuildInfo.build_id(), persistence.catalog, _starting_cell(persistence.catalog))
		if not founded.ok:
			load_problems = founded.errors
			for problem in load_problems:
				push_warning("Creature stage: could not found a lineage: %s" % problem)
			_show_problems()
			return
		save = founded.save
		save.adaptation_points = CreatureRules.start_points()
	if save.creature.is_empty():
		save.creature = CreatureRules.new_creature()
	state = {"name": String(save.creature["name"]), "body": (save.creature["body"] as Dictionary).duplicate(true),
			"points": save.adaptation_points, "world_seed": save.world_seed,
			"generation": int(save.creature["generation"]), "history": (save.creature["history"] as Array).duplicate(true)}
	open_editor()


## The cell a lineage founded in the creature stage starts from: the omnivore, else the first starting body.
static func _starting_cell(catalog: PartCatalog) -> String:
	if catalog.starting_bodies.has("omnivore"):
		return "omnivore"
	var names: Array = catalog.starting_bodies.keys()
	names.sort()
	return String(names[0]) if not names.is_empty() else ""


## "editor", "world" or "problems": the screen asked for, whether or not its scene was there.
func mode() -> String:
	return _mode


## The editor scene on screen, or null (the world is up, the scene is missing, or a test's stub stands in).
func editor_scene() -> CreatureEditor:
	return editor as CreatureEditor


## The world scene on screen, or null likewise.
func world_scene() -> CreatureWorld:
	return world as CreatureWorld


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
	# A creature's first design may start from a preset creature (owner playtest, 2026-10-24).
	if editor.has_method("offer_presets"):
		editor.call("offer_presets", int(state["generation"]) == 1 and (state["history"] as Array).is_empty())
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
	var hud = world.get("hud")
	if hud != null and hud.has_method("set_title"):
		hud.call("set_title", String(state["name"]), int(state["generation"]))
	_connect(world, "evolve_requested", _on_world_evolve)
	_connect(world, "died", _on_world_died)


## Writes the state to the store, with the points the world's sim holds when the world is up (so a quit from the
## world, Main.request_quit, keeps what was eaten). A failure is warned about and kept in last_save; play goes on.
func save_now() -> Error:
	if save == null or persistence == null or slot_path.is_empty():
		return ERR_UNCONFIGURED
	sync_from_world()
	save.adaptation_points = int(state["points"])
	save.creature = {"name": String(state["name"]), "body": (state["body"] as Dictionary).duplicate(true),
			"generation": int(state["generation"]), "history": (state["history"] as Array).duplicate(true)}
	last_save = persistence.save_to(slot_path, save)
	if last_save != OK:
		push_warning("Creature stage: could not save to %s (%s)." % [slot_path, error_string(last_save)])
	return last_save


## Copies the world's live points into the state while the world is up; nothing otherwise.
func sync_from_world() -> void:
	if _mode == "world" and world != null:
		_take_points(_world_points())


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


## The slot would not load: say why on screen; Escape (back) leaves without writing.
func _show_problems() -> void:
	_mode = "problems"
	_clear_screen()
	_missing_label = Label.new()
	_missing_label.name = "LoadProblems"
	_missing_label.text = "This save could not be opened, so the creature stage will not change it.\n%s\nEscape goes back." \
			% "\n".join(load_problems)
	_missing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_missing_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_missing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_missing_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_missing_label)


static func _connect(node: Node, signal_name: String, target: Callable) -> void:
	if node.has_signal(signal_name):
		node.connect(signal_name, target)
	else:
		push_warning("Creature stage: the %s screen has no %s signal." % [node.name, signal_name])
