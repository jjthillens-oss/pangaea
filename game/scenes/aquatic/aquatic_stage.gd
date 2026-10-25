class_name AquaticStage
extends Node
## The Aquatic stage's root (aquatic plan section 8, PROPOSED): Main hosts it as the screen, like the creature stage
## preview. It reads the lineage from the session's slot, builds the AquaticSim (a lineage that swam before comes back
## as it was saved), steps it once per physics frame with the
## player's intent, and shows the world, the HUD and, after mating at the nest, the fin and tail editor. Escape (or
## the pad's Back) leaves for the title through exit_requested.
## Saving (schema v5, plan decision 2): the progress goes into the slot's aquatic block when a generation is born, a
## place is found, a relation changes, the fish dies, and on leaving or closing the window (AquaticLineage.write).
##
## Input: move_up / move_down swim forward and back, move_left / move_right turn, Space or the right trigger rises,
## C or the left trigger dives, Shift or pad A bursts, creature_bite (F, pad X) bites, creature_social (Q, pad B)
## signals, creature_evolve (E, pad Y) mates at the nest. `driver` (a Callable returning an AquaticSim.Intent)
## swims instead of the player for the smokes; while it is set the keyboard and pad are ignored.

signal exit_requested
## The player chose to crawl ashore at the shore (plan section 7); the progress is already saved. Main carries the
## lineage over to the creature stage (EraTransition) and opens it.
signal ashore_requested

const WorldScript := preload("res://game/scenes/aquatic/aquatic_world.gd")
const HudScript := preload("res://game/ui/aquatic_hud.gd")
const FinEditorScript := preload("res://game/ui/aquatic_editor.gd")
## The events after which the progress is saved at once.
const SAVE_ON := ["generation", "found", "relation", "died"]

var rules: Dictionary
var lineage: Dictionary
var sim: AquaticSim
var world: Node3D
var hud: Control
var editor: Control
## The "Crawl onto land?" card while it is open.
var shore_offer: Control
var ui: CanvasLayer
var driver: Callable
## Every sim event so far, for the smokes.
var event_log: Array = []
var slot := ""
## The result of the last write (OK, or why it was not written), for the smokes.
var last_save := ERR_UNCONFIGURED
var saves := 0

var _pressed := {}


func setup(slot_path: String, world_seed: int) -> void:
	slot = slot_path
	rules = AquaticLineage.rules()
	lineage = AquaticLineage.read(slot_path, rules, world_seed)
	if not lineage.ok:
		push_warning("Aquatic stage: %s" % "; ".join(lineage.errors))
		lineage = {"ok": true, "source": "new", "writable": false, "generation": 1, "notes": [],
				"body": AquaticBody.DARTER.duplicate(), "world_seed": world_seed, "points": int(rules.editor.start_points)}
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
	if bool(lineage.get("writable", false)) and not bool(lineage.get("returning", false)):
		save_progress()


## Writes the progress to the slot now (see the header). Returns OK or why not.
func save_progress() -> Error:
	if sim == null:
		return ERR_UNCONFIGURED
	last_save = AquaticLineage.write(slot, lineage, sim)
	if last_save == OK:
		saves += 1
	elif bool(lineage.get("writable", false)):
		push_warning("Aquatic stage: the progress was not saved (error %d)." % last_save)
	return last_save


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_progress()


func _physics_process(_delta: float) -> void:
	if sim == null or editor != null or shore_offer != null:
		return
	var intent: AquaticSim.Intent = driver.call() if driver.is_valid() else _read_input()
	sim.step(intent)
	var save_now := false
	for e in sim.take_events():
		event_log.append(e)
		var text: String = HudScript.event_text(e)
		if text != "":
			hud.toast(text)
		save_now = save_now or String(e.type) in SAVE_ON
		if e.type == "mate":
			open_editor()
		elif e.type == "shore" and bool(e.get("can_crawl", false)):
			open_shore_offer()
	if save_now:
		save_progress()


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
		if shore_offer != null:
			stay_in_the_sea()
		elif editor != null:
			editor.call("cancel_edit")
		else:
			save_progress()
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
	if committed:
		save_progress()
	if editor != null:
		editor.queue_free()
		editor = null
	world.visible = true
	hud.visible = true


## The shore with crawl-capable lobe fins (plan sections 7 and 7a): the choice, over the paused world. Crawling ashore
## saves and asks Main to carry the lineage onto land; staying records the choice in the lineage and swims on. The
## offer opens again the next time the fish swims into the shore.
func open_shore_offer() -> Control:
	if shore_offer != null:
		return shore_offer
	shore_offer = PanelContainer.new()
	shore_offer.name = "ShoreOffer"
	ui.add_child(shore_offer)
	HudScript._pin(shore_offer, 0.5, 0.5, -440.0, -170.0, 880.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.1, 0.18, 0.92)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(30)
	style.border_color = Color(0.95, 0.85, 0.55, 0.7)
	style.set_border_width_all(2)
	shore_offer.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	shore_offer.add_child(box)
	var title := Label.new()
	title.text = "Crawl onto land?"
	title.add_theme_font_size_override("font_size", 38)
	box.add_child(title)
	var text := Label.new()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 23)
	text.text = ("Your lobe fins can carry you out of the water. On land your line walks, and its fins become legs; "
			+ "the sea is kept as a checkpoint you can go back to. Or stay: the sea is a path of its own, and your line "
			+ "keeps evolving here.")
	box.add_child(text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	var crawl := Button.new()
	crawl.name = "Crawl"
	crawl.text = "Crawl onto land"
	crawl.pressed.connect(crawl_ashore)
	row.add_child(crawl)
	var stay := Button.new()
	stay.name = "Stay"
	stay.text = "Stay in the sea"
	stay.pressed.connect(stay_in_the_sea)
	row.add_child(stay)
	stay.call_deferred("grab_focus")
	return shore_offer


func _close_shore_offer() -> void:
	if shore_offer != null:
		ui.remove_child(shore_offer)
		shore_offer.queue_free()
		shore_offer = null


## Turns the shore down: the lineage is recorded as staying in the sea (AquaticLineage.STAYED_EVENT), and play goes on.
func stay_in_the_sea() -> void:
	_close_shore_offer()
	lineage["stayed"] = true
	save_progress()
	hud.toast("Your line stays in the sea")


## Saves, then hands the lineage to Main to carry onto land.
func crawl_ashore() -> void:
	_close_shore_offer()
	lineage["stayed"] = false
	save_progress()
	ashore_requested.emit()


## The arrival from the cell stage (Main, after the pool's edge opened to the sea): the entry card with `text` first.
func show_arrival(text: String) -> void:
	hud.show_entry_card(lineage)
	hud.card_label.text = text + "\n\n" + hud.card_label.text
