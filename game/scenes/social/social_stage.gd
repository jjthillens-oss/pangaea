class_name SocialStage
extends Node
## The Social stage preview's root (PROPOSED, docs/stages/social-plan.md sections 11 and 14): Main hosts it as the
## screen, like the creature and Aquatic stages. setup() reads the player's creature from the lineage slot READ-ONLY
## (a legged land creature in the save; otherwise a starter body, with the reason kept in body_note), builds the
## SocialSim, the SocialWorld view and the HUD (SocialHud, SocialTags), and opens on the entry card. It steps the sim
## once per physics frame with the player's intent. It never writes the save or any other file: nothing here is
## saved, and leaving says so.
##
## Input (existing actions only): move_* walk, camera-relative; creature_social (R, pad B) is Friend: the selected
## signal at the target; zoom_in / zoom_out (wheel, RB / LB) choose the signal; creature_bite (F, pad X) is Foe;
## creature_evolve (E, pad Y) opens the orders menu (the sim pauses; ui_left / ui_right choose, ui_accept gives,
## ui_cancel or E again closes); pause (Esc, P, pad Menu) asks to leave. ui_cancel never leaves the stage, because
## pad B is also Sing. The dock's buttons, the band cards' Dismiss and the orders menu work with the mouse too.
## `driver` (a Callable returning a SocialSim intent) drives instead of the player for the smokes; while it is set
## the keyboard and pad are ignored.

signal exit_requested

const SocialData := preload("res://game/systems/social/social_data.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const NOTICE_SCENE := preload("res://game/ui/notice_dialog.tscn")

const LEAVE_TITLE := "Leave the Social preview?"
const LEAVE_TEXT := "Nothing here is saved."
const LEAVE_CHOICES := [["leave", "Back to title", true], ["stay", "Keep playing"]]
const NOTE_NO_SLOT := "No lineage saved yet, so a starter body walks here."
const NOTE_UNREADABLE := "Your save could not be read, so a starter body walks here. The save is left as it is."
const NOTE_NO_CREATURE := "Your lineage has no land creature yet, so a starter body walks here."
const NOTE_NO_LEGS := "Your creature needs legs to walk here, so a starter body walks instead."

var sim: SocialSim
var world: SocialWorld
var ui: CanvasLayer
var hud: SocialHud
var tags: SocialTags
var leave_dialog: NoticeDialog
var tuning: Dictionary
var data: Dictionary
## Drives the player instead of the keyboard and pad (smokes): returns {move: Vector2 (world ground direction),
## bite: bool}; one-tick presses still come from signal_now(), give_order() and dismiss().
var driver: Callable
## Every sim event so far, for the smokes and tests.
var event_log: Array = []
## "slot" (the lineage's creature) or "starter", and why a starter walks ("" from the slot).
var body_source := ""
var body_note := ""
var creature_name := ""
var slot := ""
var selected_signal := "sing"
var menu_index := 0
var _menu_open := false
var _pending := {}


## Builds the stage on `slot_path` (read only) with `world_seed` (a lineage from the slot brings its own).
func setup(slot_path: String, world_seed: int) -> void:
	slot = slot_path
	tuning = SocialData.tuning()
	data = SocialData.creature_data()
	var chosen := read_creature(slot_path, data)
	body_source = chosen["source"]
	body_note = chosen["note"]
	creature_name = chosen["name"]
	var seed_value := int(chosen["world_seed"]) if int(chosen["world_seed"]) >= 0 else world_seed
	sim = SocialSim.new(chosen["body"], seed_value, tuning, data)
	world = SocialWorld.new()
	world.name = "SocialWorld"
	add_child(world)
	world.setup(sim, data)
	ui = CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	tags = SocialTags.new()
	tags.name = "SocialTags"
	ui.add_child(tags)
	tags.bind(sim, world)
	hud = SocialHud.new()
	hud.name = "SocialHud"
	ui.add_child(hud)
	hud.bind(sim)
	hud.set_selected(selected_signal)
	hud.signal_pressed.connect(signal_now)
	hud.order_pressed.connect(give_order)
	hud.dismiss_pressed.connect(dismiss)
	hud.show_entry_card(creature_name, body_note)
	leave_dialog = NOTICE_SCENE.instantiate()
	leave_dialog.name = "LeaveDialog"
	ui.add_child(leave_dialog)
	leave_dialog.chosen.connect(_on_leave_choice)


## The player's creature from the lineage slot, read only: {body (codec dictionary), name, world_seed (-1: none),
## source ("slot" or "starter"), note (why a starter walks, "" from the slot)}. A slot that is missing or will not
## load, a lineage with no creature yet and a creature without legs all give the starter body (CreatureRules).
static func read_creature(slot_path: String, creature_data: Dictionary) -> Dictionary:
	var starter := CreatureRules.new_creature()
	var out := {"body": starter["body"], "name": String(starter["name"]), "world_seed": -1, "source": "starter",
			"note": NOTE_NO_SLOT}
	var exists := not slot_path.is_empty() and (FileAccess.file_exists(slot_path)
			or FileAccess.file_exists(slot_path + PersistenceService.BACKUP_SUFFIX)
			or FileAccess.file_exists(slot_path + PersistenceService.TEMP_SUFFIX))
	if not exists:
		return out
	var loaded := PersistenceService.new(PartCatalog.load_from()).load_from(slot_path)
	if not loaded.ok:
		out["note"] = NOTE_UNREADABLE
		return out
	var save: SaveGame = loaded.save
	var creature: Dictionary = save.creature
	if creature.is_empty() or not creature.get("body") is Dictionary:
		out["note"] = NOTE_NO_CREATURE
		return out
	var body: RefCounted = BodyCodec.from_dict(creature["body"])
	var stats: Dictionary = CreatureStats.of(body, creature_data["part_rules"], creature_data["gait_table"],
			creature_data["creature_tuning"])
	if not bool(stats["has_legs"]):
		out["note"] = NOTE_NO_LEGS
		return out
	return {"body": (creature["body"] as Dictionary).duplicate(true), "name": String(creature.get("name", out["name"])),
			"world_seed": int(save.world_seed), "source": "slot", "note": ""}


# --- Actions (the input, the HUD's buttons and the smokes all come here). -----------------------------------------

## Selects the signal R gives.
func choose_signal(kind: String) -> void:
	if not kind in SocialRules.SIGNALS:
		return
	selected_signal = kind
	if hud != null:
		hud.set_selected(kind)


## Gives `kind` (or the selected signal) to the target on the next tick. A refusal costs nothing.
func signal_now(kind: String = "") -> void:
	if not kind.is_empty():
		choose_signal(kind)
	_pending["signal"] = selected_signal


## Gives `order` to the whole band on the next tick (each member acknowledges or refuses), and closes the menu.
func give_order(order: String) -> void:
	if not order in SocialRules.ORDERS:
		return
	_pending["order"] = order
	close_menu()


## Dismisses `id` from the band on the next tick.
func dismiss(id: String) -> void:
	_pending["dismiss"] = id


func open_menu() -> void:
	_menu_open = true
	hud.set_menu(true, menu_index)


func close_menu() -> void:
	_menu_open = false
	if hud != null:
		hud.set_menu(false, menu_index)


func menu_open() -> bool:
	return _menu_open


## Starts play: hides the entry card.
func begin() -> void:
	hud.hide_card()


## Whether the sim holds still: the entry card, the orders menu or the leave question is up.
func held() -> bool:
	return _menu_open or hud.card_visible() or (leave_dialog != null and leave_dialog.is_open())


## Asks first: "Leave the Social preview? Nothing here is saved." Keep playing has focus.
func request_leave() -> void:
	close_menu()
	leave_dialog.open(LEAVE_TITLE, LEAVE_TEXT, LEAVE_CHOICES, "stay", "stay")


func leave() -> void:
	leave_dialog.close()
	exit_requested.emit()


func _on_leave_choice(choice: String) -> void:
	if choice == "leave":
		leave()


# --- The loop. -------------------------------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if sim == null or held():
		return
	var intent: Dictionary = driver.call() if driver.is_valid() else _read_input()
	intent.merge(_pending, true)
	_pending = {}
	var events := sim.tick(intent)
	event_log.append_array(events)
	hud.on_events(events)
	tags.on_events(events)


func _process(delta: float) -> void:
	if sim == null:
		return
	world.sync(delta)
	tags.refresh()
	hud.refresh(delta)


func _read_input() -> Dictionary:
	var keys := Input.get_vector(&"move_left", &"move_right", &"move_down", &"move_up")
	return {"move": world.camera_relative(keys), "bite": Input.is_action_pressed(&"creature_bite")}


func _unhandled_input(event: InputEvent) -> void:
	if hud == null or leave_dialog.is_open():
		return
	var press := (event is InputEventKey or event is InputEventJoypadButton or event is InputEventAction) \
			and event.is_pressed() and not event.is_echo()
	if hud.card_visible():
		if press:
			begin()
			_handled()
		return
	if _menu_open:
		if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"creature_evolve") \
				or event.is_action_pressed(&"pause"):
			close_menu()
		elif event.is_action_pressed(&"ui_left", true):
			_step_menu(-1)
		elif event.is_action_pressed(&"ui_right", true):
			_step_menu(1)
		elif event.is_action_pressed(&"ui_accept"):
			give_order(SocialRules.ORDERS[menu_index])
		else:
			return
		_handled()
		return
	if driver.is_valid():
		return
	if event.is_action_pressed(&"pause"):
		request_leave()
	elif event.is_action_pressed(&"creature_social"):
		signal_now()
	elif event.is_action_pressed(&"zoom_in"):
		_step_signal(1)
	elif event.is_action_pressed(&"zoom_out"):
		_step_signal(-1)
	elif event.is_action_pressed(&"creature_evolve"):
		open_menu()
	else:
		return
	_handled()


func _handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _step_signal(step: int) -> void:
	var i := SocialRules.SIGNALS.find(selected_signal)
	choose_signal(SocialRules.SIGNALS[posmod(i + step, SocialRules.SIGNALS.size())])


func _step_menu(step: int) -> void:
	menu_index = posmod(menu_index + step, SocialRules.ORDERS.size())
	hud.set_menu(true, menu_index)
