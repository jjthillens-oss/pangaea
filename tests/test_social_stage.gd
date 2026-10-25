extends TestCase
## The Social stage preview's entry and presentation (PROPOSED, docs/stages/social-plan.md sections 11, 12 and 14):
## --social and the title's "Social stage" button under Preview open it; the player's creature comes from the
## lineage slot, which is only ever read (a missing, unreadable or legless one gives the starter body); the dock's
## enabled states and tooltips are the resolver's own previews; the hint names the bound inputs; every event the HUD
## shows has words. The test_slow_ methods build the real stage (generated skins): its input follows the plan (the
## orders menu holds the sim, ui_cancel never leaves, pause asks first), and a slot's bytes and folder are unchanged
## after a session. Main itself needs a running tree (this runner adds nodes before the first frame, so they are not
## in the tree yet), so Main opening and leaving the stage is left to the social smoke; here Main's hooks are checked
## in its source. Files go under user://smoke/test_social/ only.

const SocialData := preload("res://game/systems/social/social_data.gd")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const START_SCREEN_SCENE := "res://game/ui/start_screen.tscn"
const DIR := "user://smoke/test_social"
const SLOT_PRESET := "raptor"
const SEED := 4261

static var _tuning := {}
static var _data := {}
var _nodes: Array[Node] = []


func before_each() -> void:
	if _tuning.is_empty():
		_tuning = SocialData.tuning()
		_data = SocialData.creature_data()
	_clear_dir()
	DirAccess.make_dir_recursive_absolute(DIR)


func after_each() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			if node.is_inside_tree():
				node.get_parent().remove_child(node)
			node.free()
	_nodes.clear()
	_clear_dir()


static func _clear_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
	DirAccess.remove_absolute(DIR)


static func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## A lineage save at `path` whose creature is the `preset` body (or `body` when given), written the way the game
## writes it.
static func _write_slot(path: String, preset: String = SLOT_PRESET, body: Dictionary = {}) -> Error:
	var catalog := PartCatalog.load_from()
	var founded := Lineage.found(SEED, BuildInfo.build_id(), catalog, "omnivore")
	var save: SaveGame = founded["save"]
	var creature := CreatureRules.new_creature()
	creature["name"] = "Testwalker"
	creature["body"] = body if not body.is_empty() else (CreatureData.preset(preset)["body"] as Dictionary).duplicate(true)
	save.creature = creature
	return PersistenceService.new(catalog).save_to(path, save)


static func _listing() -> PackedStringArray:
	var files := DirAccess.get_files_at(DIR)
	files.sort()
	return files


func _sim() -> SocialSim:
	return SocialSim.new(_data["presets"][SLOT_PRESET], SEED, _tuning, _data)


## Readies `node` and everything under it, children first as the engine does: the test runner adds nodes to the
## root before the tree's first frame, so their _ready (and @onready) would not run yet.
static func _ready_all(node: Node) -> void:
	for child in node.get_children():
		_ready_all(child)
	node.notification(Node.NOTIFICATION_READY)


static func _press(action: StringName) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	return e


# --- Entry. --------------------------------------------------------------------------------------------------------

func test_run_flags_read_social() -> void:
	var on := RunFlags.from_args(PackedStringArray(["--social", "--seed=7"]))
	check(on.social, "--social opens the Social stage preview")
	check_eq(on.seed_value, 7)
	check(not "--social" in on.other, "--social is not left for other tools")
	check(on.problems.is_empty(), "no problems: %s" % ", ".join(on.problems))
	var off := RunFlags.from_args(PackedStringArray(["--creature"]))
	check(not off.social and off.creature, "--creature alone does not open the Social stage")


func test_the_title_offers_the_social_stage_under_preview() -> void:
	var screen: StartScreen = (load(START_SCREEN_SCENE) as PackedScene).instantiate()
	_nodes.append(screen)
	_root().add_child(screen)
	_ready_all(screen)
	var button := screen.find_child("SocialButton", true, false) as Button
	check(button != null, "the title has a SocialButton")
	if button == null:
		return
	check_eq(button.get_parent().name, &"Preview", "it sits in the Preview list")
	check_eq(button.text, "Social stage")
	check_eq(button.theme_type_variation, &"TitleMenuButton", "shown like the Creature stage button")
	check(button.visible, "shown in every build")
	var preview := button.get_parent()
	check_eq(preview.get_child(preview.get_child_count() - 1), button, "last in the Preview list")
	check(preview.find_child("CreatureButton", false, false) != null, "the Creature stage button stays")
	check(screen.find_child("Buttons", true, false).find_child("SocialButton", false, false) == null,
			"the main Buttons list is unchanged")
	var asked := [0]
	screen.social_requested.connect(func(): asked[0] += 1)
	button.pressed.emit()
	check_eq(asked[0], 1, "pressing it asks Main for the Social stage")


func test_main_has_the_social_hooks() -> void:
	var source := (load("res://game/scenes/main.gd") as GDScript).source_code
	check(source.contains("func open_social_stage() -> SocialStage:"), "Main opens the stage")
	check(source.contains("start_screen.social_requested.connect(open_social_stage, CONNECT_DEFERRED)"),
			"the title's button reaches it")
	check(source.contains("elif flags.social:\n\t\topen_social_stage()"), "--social reaches it")
	check(source.contains("\tsocial_stage = null\n"), "clearing the screen forgets it")


# --- The slot is only read. -----------------------------------------------------------------------------------------

func test_the_creature_comes_from_the_slot_and_the_slot_is_only_read() -> void:
	var path := DIR.path_join("lineage.json")
	check_eq(_write_slot(path), OK, "the test slot is written")
	var before := FileAccess.get_sha256(path)
	var listing := _listing()
	var chosen := SocialStage.read_creature(path, _data)
	check_eq(chosen["source"], "slot")
	check_eq(chosen["name"], "Testwalker")
	check_eq(chosen["note"], "")
	check_eq(int(chosen["world_seed"]), SEED, "the lineage's own world seed")
	check_eq(JSON.stringify(chosen["body"], "", true), JSON.stringify(CreatureData.preset(SLOT_PRESET)["body"], "", true),
			"the saved body, as saved")
	check_eq(FileAccess.get_sha256(path), before, "the slot's bytes are unchanged")
	check_eq(_listing(), listing, "no temp or backup file appears")


func test_a_missing_unreadable_or_legless_slot_gives_the_starter() -> void:
	var starter: Dictionary = CreatureRules.new_creature()["body"]
	var missing := SocialStage.read_creature(DIR.path_join("none.json"), _data)
	check_eq(missing["source"], "starter")
	check_eq(missing["note"], SocialStage.NOTE_NO_SLOT)
	check_eq(JSON.stringify(missing["body"], "", true), JSON.stringify(starter, "", true))
	check(not FileAccess.file_exists(DIR.path_join("none.json")), "a missing slot is not created")
	var bad := DIR.path_join("bad.json")
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("{ not a save")
	f.close()
	var bad_sha := FileAccess.get_sha256(bad)
	var unreadable := SocialStage.read_creature(bad, _data)
	check_eq(unreadable["source"], "starter")
	check_eq(unreadable["note"], SocialStage.NOTE_UNREADABLE)
	check_eq(FileAccess.get_sha256(bad), bad_sha, "an unreadable slot is left as it is")
	# A body with no limbs at all (only its spine): it cannot walk the field.
	var legless: Dictionary = (CreatureData.preset(SLOT_PRESET)["body"] as Dictionary).duplicate(true)
	legless["limbs"] = []
	legless["parts"] = []
	var path := DIR.path_join("legless.json")
	check_eq(_write_slot(path, SLOT_PRESET, legless), OK)
	var no_legs := SocialStage.read_creature(path, _data)
	check_eq(no_legs["source"], "starter")
	check_eq(no_legs["note"], SocialStage.NOTE_NO_LEGS)
	check(_listing() == PackedStringArray(["bad.json", "legless.json"]), "only the test's own files: %s" % [_listing()])


# --- The HUD. ----------------------------------------------------------------------------------------------------------

func test_the_dock_previews_match_the_rules() -> void:
	var sim := _sim()
	var hud := SocialHud.new()
	_nodes.append(hud)
	hud.bind(sim)
	# Far from everyone at the start, then in front of the curious strider.
	for step in 2:
		if step == 1:
			var c: Dictionary = sim.individual("b1")
			var at := Vector2(c["position"].x, c["position"].z) + Vector2(-sin(c["yaw"]), -cos(c["yaw"])) * 4.0
			var to := Vector2(c["position"].x, c["position"].z) - at
			sim.place(SocialSim.PLAYER_ID, at, atan2(-to.x, -to.y))
			sim.tick({})
		hud.refresh_now()
		var names := SocialHud.names_of(sim)
		for kind in SocialRules.SIGNALS:
			var preview := sim.preview_signal(kind)
			var b: Button = hud.signal_buttons[kind]
			check_eq(b.disabled, not bool(preview["ok"]), "%s enabled as the resolver says (step %d)" % [kind, step])
			check_eq(b.tooltip_text, SocialHud.signal_tooltip(kind, preview, names))
			if not bool(preview["ok"]):
				check(b.tooltip_text.contains(String(preview["reason"])), "%s's tooltip gives the reason" % kind)
		for order in SocialRules.ORDERS:
			var preview := sim.preview_order(order)
			var b: Button = hud.order_buttons[order]
			check_eq(b.disabled, not bool(preview["ok"]), "%s enabled as the resolver says" % order)
			check_eq(b.tooltip_text, SocialHud.order_tooltip(order, preview, names))
	check_eq(sim.target_id(), "b1", "the strider is the target")
	check(not hud.signal_buttons["display"].disabled, "Display reaches the strider at 4 m")
	check(hud.signal_buttons["share"].disabled, "Share needs a fruit in hand")
	check(hud.order_buttons["follow"].disabled, "no band yet, so no orders")
	check_eq(hud.order_buttons["follow"].tooltip_text, "No one in your band yet")


func test_the_selected_signal_and_menu_order_are_marked_in_words() -> void:
	var hud := SocialHud.new()
	_nodes.append(hud)
	hud.bind(_sim())
	hud.set_selected("calm")
	check(hud.signal_buttons["calm"].text.begins_with(SocialHud.MARK), "the selected signal carries the mark")
	check(hud.signal_buttons["calm"].button_pressed, "and shows pressed")
	check(not hud.signal_buttons["sing"].text.begins_with(SocialHud.MARK), "only the selected one")
	hud.set_menu(true, 2)
	check(hud.menu_panel.visible, "the orders menu shows")
	check(hud.order_buttons["investigate"].text.begins_with(SocialHud.MARK), "the menu's order carries the mark")
	check(hud.menu_label.text.contains("Investigate"), hud.menu_label.text)
	hud.set_menu(false, 2)
	check(not hud.menu_panel.visible, "the menu closes")
	check(not hud.order_buttons["investigate"].text.begins_with(SocialHud.MARK), "the mark goes with it")


func test_the_hint_names_the_bindings() -> void:
	var was := InputPrompts.device
	InputPrompts.device = "keys"
	var hud := SocialHud.new()
	_nodes.append(hud)
	hud.bind(_sim())
	hud.refresh_now()
	var line := hud.hint_label.text
	for action: StringName in [&"creature_social", &"creature_bite", &"creature_evolve", &"pause"]:
		var names := InputPrompts.names_for(action, "keys")
		check(not names.is_empty() and line.contains(names[0]), "the hint names %s's key (%s): %s" % [action, names, line])
	check(line.contains("WASD") or line.contains("Move"), "the hint names the move keys: %s" % line)
	check(line.contains("Friend: Sing") and line.contains("Foe: bite") and line.contains("Orders"), line)
	InputPrompts.device = "pad"
	hud.refresh_now()
	var pad := hud.hint_label.text
	for action: StringName in [&"creature_social", &"creature_bite", &"creature_evolve"]:
		var names := InputPrompts.names_for(action, "pad")
		check(not names.is_empty() and pad.contains(names[0]), "the pad hint names %s (%s): %s" % [action, names, pad])
	InputPrompts.device = was


## The individual the player faces carries the two answers on its own tag, with their bindings (plan section 2:
## friend or foe before any interaction); no other tag does.
func test_the_target_tag_offers_friend_and_foe() -> void:
	var was := InputPrompts.device
	InputPrompts.device = "keys"
	var sim := _sim()
	var c: Dictionary = sim.individual("b1")
	var at := Vector2(c["position"].x, c["position"].z) + Vector2(-sin(c["yaw"]), -cos(c["yaw"])) * 4.0
	var to := Vector2(c["position"].x, c["position"].z) - at
	sim.place(SocialSim.PLAYER_ID, at, atan2(-to.x, -to.y))
	sim.tick({})
	var tags := SocialTags.new()
	_nodes.append(tags)
	tags.sim = sim
	check_eq(sim.target_id(), "b1", "the strider is the target")
	var line := tags.answer_line("b1")
	var friend := InputPrompts.names_for(&"creature_social", "keys")
	var foe := InputPrompts.names_for(&"creature_bite", "keys")
	check(line.contains("Friend") and line.contains("Foe"), "the target's tag offers both answers: %s" % line)
	check(not friend.is_empty() and line.contains(friend[0]) and not foe.is_empty() and line.contains(foe[0]),
			"with their keys (%s, %s): %s" % [friend, foe, line])
	check_eq(tags.answer_line("b2"), "", "another individual's tag does not")
	check_eq(tags.answer_line(String(sim.hunter()["id"])), "", "nor does the hunter's")
	InputPrompts.device = was


func test_every_shown_event_has_words() -> void:
	var names := {"b1": "Ama", "player": "You", "h1": "The hunter"}
	var events := [{"kind": "refused", "action": "sing", "who": "b1", "reason": "Too far: come within 6 m"},
			{"kind": "response", "who": "b1", "name": "Ama", "signal": "sing", "response": "fits", "words": "welcomes you", "trust": 3.0},
			{"kind": "joined", "who": "b1", "name": "Ama"}, {"kind": "befriended", "who": "b1", "name": "Ama"},
			{"kind": "ack", "who": "b1", "order": "follow", "words": "follows you"},
			{"kind": "order_refused", "who": "b1", "order": "assist", "reason": "no fighter, I'll gather"},
			{"kind": "arrived", "who": "b1", "order": "investigate"}, {"kind": "found", "who": "b1", "what": "fruit"},
			{"kind": "cannot", "who": "b1", "order": "investigate", "reason": "can't reach that spot"},
			{"kind": "done", "who": "b1", "order": "assist"}, {"kind": "lost", "who": "b1"},
			{"kind": "dismissed", "who": "b1", "name": "Ama"}, {"kind": "left", "who": "b1", "name": "Ama", "reason": "you hurt it"},
			{"kind": "delivered", "who": "b1", "count": 1, "total": 2}, {"kind": "learned", "who": "b1", "route": "grove"},
			{"kind": "task_done", "round": 1, "count": 6}, {"kind": "hunter_state", "state": "pursue", "why": ""},
			{"kind": "hunter_state", "state": "disengage", "why": "nest"}, {"kind": "warned", "who": "b1", "name": "Ama"},
			{"kind": "hit", "target": "player", "by": "h1", "damage": 5.0}, {"kind": "hit", "target": "b1", "by": "h1", "damage": 0.0},
			{"kind": "drove_off", "why": "group"}, {"kind": "bit", "by": "player", "target": "b1"},
			{"kind": "hostile", "who": "b1", "name": "Ama", "seconds": 40}, {"kind": "bumped", "who": "b1", "name": "Ama"},
			{"kind": "fainted", "band": ["b1"]}, {"kind": "recovered"},
			{"kind": "group_hostile", "group": "band", "seconds": 120}, {"kind": "group_listens", "group": "band"}]
	for e in events:
		var text := SocialHud.event_text(e, names)
		check(not text.is_empty(), "%s has words" % e["kind"])
		check(not text.contains("b1"), "%s names the individual, not its id: %s" % [e["kind"], text])
	check_eq(SocialHud.event_text(events[0], names), "Sing · Too far: come within 6 m", "a refusal gives its reason")
	check_eq(SocialHud.event_text(events[1], names), "Ama welcomes you")
	check_eq(SocialHud.event_text(events[5], names), "Ama refuses: no fighter, I'll gather")
	for quiet in [{"kind": "tier", "who": "b1", "tier": "far"}, {"kind": "picked", "who": "b1", "bush": "g1"},
			{"kind": "hunter_state", "state": "strike", "why": ""}, {"kind": "hunter_state", "state": "patrol", "why": ""}]:
		check_eq(SocialHud.event_text(quiet, names), "", "%s stays off the caption" % quiet["kind"])


## A round's end comes in the same tick as every gatherer's "done": the key line stays on the caption, and a whole
## band's answers to one order fit.
func test_key_lines_stay_on_the_caption() -> void:
	var sim := _sim()
	var hud := SocialHud.new()
	_nodes.append(hud)
	hud.bind(sim)
	var names := SocialHud.names_of(sim)
	hud.on_events([{"kind": "task_done", "round": 1, "count": 6}, {"kind": "done", "who": "b1", "order": "assist"},
			{"kind": "done", "who": "b2", "order": "assist"}, {"kind": "done", "who": "b3", "order": "assist"}])
	var shown := hud.caption_texts()
	check_eq(shown.size(), SocialHud.CAPTION_LINES, "the caption is full: %s" % [shown])
	check(shown.has("The nest is fed: 6 fruit"), "the round's end is still shown: %s" % [shown])
	check_eq(shown[shown.size() - 1], "The nest is fed: 6 fruit", "as the newest line")
	var acks := []
	for id in ["b1", "b2", "b3"]:
		acks.append({"kind": "ack", "who": id, "order": "follow", "words": "follows you"})
	hud.on_events(acks)
	shown = hud.caption_texts()
	for id in ["b1", "b2", "b3"]:
		check(shown.has("%s follows you" % names[id]), "%s's answer is shown: %s" % [names[id], shown])


# --- The real stage (generated skins). -------------------------------------------------------------------------------

func _stage(path: String) -> SocialStage:
	var stage := SocialStage.new()
	_nodes.append(stage)
	_root().add_child(stage)
	stage.setup(path, SEED)
	_ready_all(stage.leave_dialog)
	return stage


func test_slow_the_stage_follows_the_plan_controls() -> void:
	var stage := _stage(DIR.path_join("none.json"))
	check_eq(stage.body_source, "starter")
	check(stage.hud.card_visible(), "it opens on the entry card")
	check(stage.held(), "the sim holds still under the entry card")
	var card_text := (stage.hud.card.find_child("Text", true, false) as Label).text
	check(card_text.contains("Nothing here is saved."), card_text)
	stage._physics_process(1.0 / 60.0)
	check_eq(stage.sim.tick_count, 0, "no tick under the card")
	var exits := [0]
	stage.exit_requested.connect(func(): exits[0] += 1)
	stage._unhandled_input(_press(&"creature_social"))
	check(not stage.hud.card_visible(), "any press begins")
	stage._physics_process(1.0 / 60.0)
	check_eq(stage.sim.tick_count, 1)
	stage._unhandled_input(_press(&"ui_cancel"))
	check_eq(exits[0], 0, "ui_cancel never leaves (pad B is Sing)")
	check(not stage.leave_dialog.is_open(), "and does not ask to leave")
	stage._unhandled_input(_press(&"zoom_in"))
	check_eq(stage.selected_signal, "display", "zoom_in picks the next signal")
	stage._unhandled_input(_press(&"zoom_out"))
	stage._unhandled_input(_press(&"zoom_out"))
	check_eq(stage.selected_signal, "calm", "zoom_out goes back round")
	stage._unhandled_input(_press(&"creature_evolve"))
	check(stage.menu_open(), "E opens the orders menu")
	stage._physics_process(1.0 / 60.0)
	check_eq(stage.sim.tick_count, 1, "the sim holds still in the menu")
	stage._unhandled_input(_press(&"ui_right"))
	stage._unhandled_input(_press(&"ui_right"))
	check_eq(stage.menu_index, 2)
	stage._unhandled_input(_press(&"ui_accept"))
	check(not stage.menu_open(), "giving an order closes the menu")
	var before := stage.event_log.size()
	stage._physics_process(1.0 / 60.0)
	var refused := stage.event_log.slice(before).filter(func(e): return e["kind"] == "refused")
	check(refused.size() == 1 and refused[0]["reason"] == "No one in your band yet",
			"Investigate with no band is refused in words: %s" % [stage.event_log.slice(before)])
	check(stage.hud.caption_texts().size() > 0, "the refusal reaches the caption")
	stage._unhandled_input(_press(&"creature_evolve"))
	stage._unhandled_input(_press(&"ui_cancel"))
	check(not stage.menu_open() and exits[0] == 0, "ui_cancel closes the menu and stays")
	stage._unhandled_input(_press(&"pause"))
	check(stage.leave_dialog.is_open(), "pause asks first")
	check_eq(stage.leave_dialog.title_text(), SocialStage.LEAVE_TITLE)
	check_eq(stage.leave_dialog.body_text(), SocialStage.LEAVE_TEXT)
	check(stage.held(), "the sim holds still while it asks")
	stage.leave_dialog.choose("stay")
	check(not stage.leave_dialog.is_open() and exits[0] == 0, "Keep playing stays")
	stage._unhandled_input(_press(&"pause"))
	stage.leave_dialog.choose("leave")
	check_eq(exits[0], 1, "Back to title leaves")


func test_slow_the_stage_never_writes_the_slot() -> void:
	var path := DIR.path_join("lineage.json")
	check_eq(_write_slot(path), OK)
	var sha := FileAccess.get_sha256(path)
	var listing := _listing()
	var stage := _stage(path)
	check_eq(stage.body_source, "slot")
	check_eq(stage.creature_name, "Testwalker")
	check_eq(stage.sim.world_seed, SEED, "the lineage's world seed")
	stage.begin()
	stage.driver = func() -> Dictionary: return {"move": Vector2(0.0, -1.0), "bite": false}
	for i in 240:
		if i % 60 == 30:
			stage.signal_now(SocialRules.SIGNALS[(i / 60) % SocialRules.SIGNALS.size()])
		stage._physics_process(1.0 / 60.0)
	check_eq(stage.sim.tick_count, 240)
	stage.dismiss("b1")
	stage.give_order("follow")
	stage._physics_process(1.0 / 60.0)
	stage.leave()
	check_eq(FileAccess.get_sha256(path), sha, "the slot's bytes are unchanged")
	check_eq(_listing(), listing, "no temp, backup or other file appears")

