class_name AquaticStage
extends Node
## The Aquatic stage's root (aquatic plan section 8, PROPOSED): Main hosts it as the screen, like the creature stage
## preview. It reads the lineage from the session's slot (read-only: saving the aquatic stage waits for the owner's
## OK on a save schema change, plan decision 2), builds the AquaticSim, steps it once per physics frame with the
## player's intent, and shows the world, the HUD and, after mating at the nest, the fin and tail editor. Escape (or
## the pad's Back) leaves for the title through exit_requested.
##
## Input: move_up / move_down swim forward and back, move_left / move_right turn, Space or the right trigger rises,
## C or the left trigger dives, Shift or pad A bursts, creature_bite (F, pad X) bites, creature_social (Q, pad B)
## signals, creature_evolve (E, pad Y) mates at the nest. `driver` (a Callable returning an AquaticSim.Intent)
## swims instead of the player for the smokes; while it is set the keyboard and pad are ignored.

signal exit_requested

const WorldScript := preload("res://game/scenes/aquatic/aquatic_world.gd")
const HudScript := preload("res://game/ui/aquatic_hud.gd")
const FinEditorScript := preload("res://game/ui/aquatic_editor.gd")

var rules: Dictionary
var lineage: Dictionary
var sim: AquaticSim
var world: Node3D
var hud: Control
var editor: Control
var ui: CanvasLayer
var driver: Callable
## Every sim event so far, for the smokes.
var event_log: Array = []

var _pressed := {}


func setup(slot_path: String, world_seed: int) -> void:
	rules = AquaticLineage.rules()
	lineage = AquaticLineage.read(slot_path, rules, world_seed)
	if not lineage.ok:
		push_warning("Aquatic stage: %s" % "; ".join(lineage.errors))
		lineage = {"ok": true, "source": "new", "generation": 1, "notes": [], "body": AquaticBody.DARTER.duplicate(),
				"world_seed": world_seed, "points": int(rules.editor.start_points)}
	for problem in lineage.get("errors", []):
		push_warning("Aquatic stage: %s A new line swims instead; the save is left as it is." % problem)
	sim = AquaticSim.new(rules, int(lineage.get("world_seed", world_seed)), lineage.body, lineage)
	world = WorldScript.new()
	world.name = "AquaticWorld"
	add_child(world)
	world.setup(sim)
	ui = CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	hud = HudScript.new()
	hud.name = "AquaticHud"
	ui.add_child(hud)
	hud.setup(sim)
	hud.show_entry_card(lineage)


func _physics_process(_delta: float) -> void:
	if sim == null or editor != null:
		return
	var intent: AquaticSim.Intent = driver.call() if driver.is_valid() else _read_input()
	sim.step(intent)
	for e in sim.take_events():
		event_log.append(e)
		var text: String = HudScript.event_text(e)
		if text != "":
			hud.toast(text)
		if e.type == "mate":
			open_editor()


func _process(delta: float) -> void:
	if sim == null:
		return
	if editor == null:
		world.sync(delta)
	hud.refresh(delta)


func _read_input() -> AquaticSim.Intent:
	var intent := AquaticSim.Intent.new()
	intent.thrust = Input.get_axis(&"move_down", &"move_up")
	if Input.is_physical_key_pressed(KEY_W):
		intent.thrust = 1.0
	elif Input.is_physical_key_pressed(KEY_S):
		intent.thrust = -1.0
	intent.turn = Input.get_axis(&"move_left", &"move_right")
	if Input.is_physical_key_pressed(KEY_A):
		intent.turn = -1.0
	elif Input.is_physical_key_pressed(KEY_D):
		intent.turn = 1.0
	var rise := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	if Input.is_physical_key_pressed(KEY_SPACE):
		rise = 1.0
	elif Input.is_physical_key_pressed(KEY_C) or Input.is_physical_key_pressed(KEY_CTRL):
		rise = -1.0
	intent.rise = rise if absf(rise) > 0.15 else 0.0
	intent.burst = Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	intent.bite = _edge("bite", Input.is_action_pressed(&"creature_bite"))
	intent.signal_call = _edge("signal", Input.is_action_pressed(&"creature_social") or Input.is_physical_key_pressed(KEY_Q))
	intent.interact = _edge("mate", Input.is_action_pressed(&"creature_evolve") or Input.is_physical_key_pressed(KEY_E))
	return intent


func _edge(key: String, down: bool) -> bool:
	var was: bool = _pressed.get(key, false)
	_pressed[key] = down
	return down and not was


func _unhandled_input(event: InputEvent) -> void:
	if hud != null and hud.card.visible and (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed():
		hud.hide_card()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_cancel") or (event is InputEventJoypadButton and event.is_pressed()
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_BACK):
		get_viewport().set_input_as_handled()
		if editor != null:
			editor.call("cancel_edit")
		else:
			exit_requested.emit()


## Mating at the nest: the editor opens over the paused world on the current body and points.
func open_editor() -> Control:
	if editor != null:
		return editor
	editor = FinEditorScript.new()
	editor.name = "AquaticEditor"
	ui.add_child(editor)
	editor.call("open", rules, sim.player.body, sim.points)
	editor.connect("closed", _on_editor_closed, CONNECT_DEFERRED)
	world.visible = false
	hud.visible = false
	return editor


func _on_editor_closed(committed: bool, body: Dictionary, cost: int) -> void:
	if committed:
		if sim.apply_offspring(body, cost):
			world.rebuild_player()
		else:
			push_warning("Aquatic stage: the editor's body was refused.")
	else:
		hud.toast("Your kin swims off; mate again when you are ready")
	for e in sim.take_events():
		event_log.append(e)
		var text: String = HudScript.event_text(e)
		if text != "":
			hud.toast(text)
	if editor != null:
		editor.queue_free()
		editor = null
	world.visible = true
	hud.visible = true
