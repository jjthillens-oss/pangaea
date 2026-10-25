class_name Main
extends Node
## The game's root scene (M1 step 2). It owns the GameSession and the launch flags (RunFlags),
## shows one screen at a time (the start screen or the pool) and answers the menus. Quitting
## asks "Save first?" when there is unsaved progress, for the window's close button too.
##
## A death (M1 step 3) is resolved the moment the pool reports it: GameSession.resolve_death()
## takes the points and, with SAVE_ON_DEATH (owner decision OD1), saves the slot with the cell at
## its checkpoint. The notice then names what the death cost, the killer's tip and whether it was
## saved; a saved death leaves nothing to ask about on quit, a failed one gets its own warning.
## In debug builds it also adds the dev layer (debug panel, dev gizmos, dev keys) by loading
## game/dev by path; the release export leaves that folder out.
##
## Buttons and the scene smoke use the same methods: start_new(body), continue_run(),
## save_now(), save_and_quit_to_title(), resume(), continue_after_death(), quit_to_desktop().
## open_session(slot) switches save slots, and intent_provider (for example the dev ForageBot)
## swims instead of the player in the next run.
##
## Settings and slots (UI pass): the shared SettingsService is applied at launch (window, audio,
## bindings, text size) and picks the save slot unless --slot names one. open_settings() shows the
## settings screen over the title or the pause menu; open_slots() the save slots screen over the
## title, whose choose_slot(n) and delete_slot(n) do the work. Every input event tells
## InputPrompts which device is in use, so hints name the controller's buttons or the keys.
##
## Growth (S2): the pool reads the growth trigger and reduce camera motion from the same shared
## settings and follows their changes itself (V-15, V-16). Main keeps the player memory
## (UserSettings: hints followed, giant passes seen) on user://player_memory.cfg, apart from both
## the settings and the saves (C-V1); a run with --slot keeps its own beside that save.
##
## Creature stage preview (creature-stage plan, PROPOSED): open_creature_stage() puts the CreatureStage
## in place of the screen; the title's "Creature stage" button and --creature open it. It reads and
## writes the session's lineage slot (save schema v3 keeps the creature there; --slot applies) and
## comes back to the title through exit_requested.
##
## Aquatic stage slice (aquatic plan, PROPOSED): open_aquatic_stage() puts the AquaticStage in place of the screen; the
## title's "Aquatic stage" button and --aquatic open it. It reads the lineage slot and never writes it.

signal screen_changed(screen: Node)

const START_SCREEN_SCENE := preload("res://game/ui/start_screen.tscn")
const POOL_SCENE := preload("res://game/scenes/pool/pool.tscn")
const HUD_SCENE := preload("res://game/ui/hud.tscn")
const PAUSE_MENU_SCENE := preload("res://game/ui/pause_menu.tscn")
const NOTICE_SCENE := preload("res://game/ui/notice_dialog.tscn")
const CREATURE_STAGE_SCENE := preload("res://game/scenes/creature/creature_stage.tscn")
## Debug builds only. Loaded by path, never preloaded, so the release export can leave game/dev out.
const DEV_PANEL_PATH := "res://game/dev/debug_panel.tscn"
const DEV_GIZMOS_PATH := "res://game/dev/dev_gizmos.gd"
const DEV_KEYS_PATH := "res://game/dev/dev_keys.gd"
const DEV_PERF_TOUR_PATH := "res://game/dev/perf_tour.gd"
## The quit dialog's words when the cell's death could not be saved (GameSession.death_save_failed).
const DEATH_NOT_SAVED_TEXT := "Your cell's death could not be saved. Quit anyway?"

var flags: RunFlags
var session: GameSession
## Swims for the player in the next run when set (anything with next_intent(sim) -> SimIntent).
var intent_provider: Object
## The screen shown now: start_screen, pool or creature_stage.
var screen: Node
var start_screen: StartScreen
var pool: PoolScene
var creature_stage: CreatureStage
var aquatic_stage: AquaticStage
var hud: Hud
var pause_menu: PauseMenu
var cell_editor: CellEditor   ## S4.4: open while the cell chooses its next generation
var death_notice: NoticeDialog
## The result of the last start_new() or continue_run().
var last_run := {}
## Debug builds only; null in a release build.
var dev_layer: Node
var debug_panel: Node
## The player's settings (SettingsService.shared()).
var settings: SettingsService
## What this computer remembers about its player (S2): loaded at launch from player_memory_path().
var player_memory: UserSettings
## False while a tool must leave the player memory as it is (the perf tour always does).
var memory_writable := true
## The settings screen or the save slots screen while one is open, else null.
var settings_menu: SettingsMenu
var slot_picker: SlotPicker

var _paused_for_quit := false

@onready var quit_dialog: NoticeDialog = %QuitDialog
@onready var alert: NoticeDialog = %Alert


func _ready() -> void:
	get_tree().auto_accept_quit = false
	# The canvas expands to the window's aspect (project settings), but headless has no window (a
	# 64 x 64 root, which would expand to 1920 x 1920), so the smokes keep the 1920 x 1080 design canvas.
	if DisplayServer.get_name() == "headless":
		get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	flags = RunFlags.current()
	for problem in flags.problems:
		push_warning(problem)
	settings = SettingsService.shared()
	for problem in settings.load_problems:
		push_warning(problem)
	settings.apply_all()
	settings.changed.connect(_on_setting_changed)
	player_memory = UserSettings.load_from(player_memory_path())
	open_session(flags.slot if not flags.slot.is_empty() else settings.current_slot_path())
	quit_dialog.chosen.connect(_on_quit_choice)
	_add_dev_layer()
	if flags.perf_tour:
		_start_perf_tour()
	if flags.creature:
		open_creature_stage()
	elif flags.aquatic:
		open_aquatic_stage()
	if screen == null:
		show_start()


## The player memory's file: UserSettings.PATH, or player_memory.cfg beside the --slot save, so the
## smokes and tours, which name their own slot, never touch the player's.
func player_memory_path() -> String:
	if flags == null or flags.slot.is_empty():
		return UserSettings.PATH
	return flags.slot.get_base_dir().path_join("player_memory.cfg")


## Writes the player memory: ERR_SKIP, with nothing written, during the perf tour or while
## memory_writable is false.
func save_player_memory() -> Error:
	if player_memory == null or not memory_writable or (flags != null and flags.perf_tour):
		return ERR_SKIP
	return player_memory.save_to(player_memory_path())


## Uses another save slot ("" for the default) and shows its start screen if a screen is up. The
## world is the world file's (S1), endless unless --world=pool says otherwise.
func open_session(slot: String) -> void:
	session = GameSession.new(slot if not slot.is_empty() else GameSession.DEFAULT_SLOT, PoolLayout.DEFAULT_PATH,
		SpeciesCatalog.DEFAULT_PATH, WorldConfig.DEFAULT_PATH, flags.world if flags != null else "")
	if screen != null:
		show_start()


func show_start() -> void:
	_clear_screen()
	start_screen = START_SCREEN_SCENE.instantiate()
	add_child(start_screen)
	start_screen.setup(session.peek_slot(), session.catalog, SaveSlots.number_of(session.slot))
	# Deferred, so a screen is never swapped out from under the button that asked for it.
	start_screen.new_requested.connect(start_new, CONNECT_DEFERRED)
	start_screen.continue_requested.connect(continue_run, CONNECT_DEFERRED)
	start_screen.quit_requested.connect(quit_to_desktop, CONNECT_DEFERRED)
	start_screen.settings_requested.connect(open_settings, CONNECT_DEFERRED)
	start_screen.slots_requested.connect(open_slots, CONNECT_DEFERRED)
	start_screen.creature_requested.connect(open_creature_stage, CONNECT_DEFERRED)
	start_screen.aquatic_requested.connect(open_aquatic_stage, CONNECT_DEFERRED)
	_set_screen(start_screen)


## Opens the creature stage preview as the screen, on the session's lineage slot (save schema v3: the creature
## lives in the lineage save); a --seed names the seed of a lineage the stage founds. Its exit comes back to
## the title.
func open_creature_stage() -> CreatureStage:
	_clear_screen()
	creature_stage = CREATURE_STAGE_SCENE.instantiate()
	add_child(creature_stage)
	creature_stage.exit_requested.connect(show_start, CONNECT_DEFERRED)
	var seed_value := flags.seed_value if flags.seed_value >= 0 else randi()
	creature_stage.setup(session.slot, seed_value)
	_set_screen(creature_stage)
	return creature_stage


## Opens the Aquatic stage slice as the screen, on the session's lineage slot (read-only); a --seed names the seed of a
## lineage it founds in memory when the slot has none. Its exit comes back to the title.
func open_aquatic_stage() -> AquaticStage:
	_clear_screen()
	aquatic_stage = AquaticStage.new()
	aquatic_stage.name = "AquaticStage"
	add_child(aquatic_stage)
	aquatic_stage.exit_requested.connect(show_start, CONNECT_DEFERRED)
	aquatic_stage.setup(session.slot, flags.seed_value if flags.seed_value >= 0 else randi())
	_set_screen(aquatic_stage)
	return aquatic_stage


## Founds a lineage with a starting body and opens the pool. A seed below 0 uses --seed, else a
## random one. Returns GameSession.start_new's {"ok", "errors", "saved"}.
func start_new(body: String, seed_value: int = -1) -> Dictionary:
	var result := session.start_new(body, seed_value if seed_value >= 0 else flags.seed_value)
	last_run = result
	if not result.ok:
		_alert("Could not start a new lineage", result.errors)
		return result
	_open_pool()
	if not result.saved:
		hud.show_message("Not saved yet: %s" % "; ".join(result.errors))
	return result


## Loads the slot and opens the pool. Returns GameSession.continue_run's {"ok", "source", "errors"}.
func continue_run() -> Dictionary:
	var result := session.continue_run()
	last_run = result
	if not result.ok:
		_alert("Could not continue", result.errors)
		return result
	_open_pool()
	var text := Hud.rested_line(session.sim.state)
	if result.source == "backup":
		text = StartScreen.BACKUP_TEXT + "\n" + text
	hud.show_message(text)
	return result


## Pause menu: Save. Returns GameSession.save_now's {"ok", "error"}.
func save_now() -> Dictionary:
	var result := session.save_now()
	if pause_menu != null:
		pause_menu.show_status(save_status_text(result), result.ok)
	return result


## Pause menu: Save and quit to title. Stays in the menu, showing why, when the save fails.
func save_and_quit_to_title() -> Dictionary:
	var result := session.save_now()
	if result.ok:
		show_start()
	elif pause_menu != null:
		pause_menu.show_status(save_status_text(result), false)
	return result


## Pause menu: Resume (also Esc or P while it is open).
func resume() -> void:
	if pool == null:
		return
	pause_menu.close()
	pool.set_paused(false)
	get_viewport().gui_release_focus()


## S4.4: the cell touched its kin (the pool's mate_requested): the pool pauses under the cell editor.
func open_cell_editor() -> CellEditor:
	if pool == null:
		return null
	pool.release_input()
	pool.set_paused(true)
	hud.visible = false   # the editor is its own screen; the swim's panels would show through its dim
	cell_editor = CellEditor.new()
	cell_editor.name = "CellEditor"
	pool.ui.add_child(cell_editor)
	var chase := {}
	if session.sim.species != null:
		chase = session.sim.species.fastest_chase(session.sim.size(), session.sim.catalog)
		chase["name"] = str(session.sim.species.species.get(chase.species, {}).get("name", "hunter"))
	cell_editor.open(session.sim.save, session.sim.catalog, session.sim.state, chase)
	cell_editor.closed.connect(_on_cell_editor_closed, CONNECT_DEFERRED)
	return cell_editor


## The editor closed: with a new generation the cell takes its body and the run is saved; the kin
## goes either way and play resumes.
func _on_cell_editor_closed(committed: bool) -> void:
	if cell_editor != null:
		cell_editor.queue_free()
		cell_editor = null
	if pool == null:
		return
	hud.visible = true
	if committed:
		session.sim.apply_offspring()
		session.save_now()
		hud.show_message("Generation %d" % session.sim.save.genome.generation)
	pool.finish_mate(committed)
	pool.set_paused(false)


## Death notice: Continue. Puts the cell back at its checkpoint, sheltered (the death was applied
## when it happened). Returns the points the death took. The respawn message shows when the pool
## reports the respawn (_on_respawned): at once in the pool, and in the endless world at the sim's
## next step, which performs it (S1).
func continue_after_death() -> int:
	if pool == null or not session.sim.dead:
		return 0
	death_notice.close()
	pool.set_paused(false)
	return session.respawn_after_death()


## Pause menu and start screen: Quit. Asks "Save first?" when there is unsaved progress.
func quit_to_desktop() -> void:
	request_quit()


## Quits, or first asks when a run has unsaved progress (the window's close button comes here
## too): "Save first?", or a warning when the cell's death could not be saved (see quit_prompt).
## A saved death is not unsaved progress, so quitting at its notice asks nothing.
func request_quit() -> void:
	if creature_stage != null:
		creature_stage.save_now()
	if pool == null or not session.dirty:
		_quit()
		return
	if not pool.paused:
		pool.set_paused(true)
		_paused_for_quit = true
	var prompt := quit_prompt(session.sim.dead, session.death_save_failed())
	quit_dialog.open(prompt.title, prompt.body, prompt.choices, prompt.focus, "cancel")


## Full screen key: switches between a window and borderless full screen, and keeps the choice in
## the settings.
func toggle_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var windowed := str(settings.get_value("graphics/window_mode")) == "windowed"
	settings.set_value("graphics/window_mode", "borderless" if windowed else "windowed")
	settings.save_file()


## Shows the settings screen over the title or the pause menu (the pool stays paused under it).
func open_settings() -> SettingsMenu:
	if settings_menu != null:
		return settings_menu
	var host: Node = pool.ui if pool != null else screen
	if host == null:
		return null
	settings_menu = SettingsMenu.new()
	settings_menu.name = "SettingsMenu"
	host.add_child(settings_menu)
	settings_menu.closed.connect(_on_settings_closed, CONNECT_DEFERRED)
	settings_menu.open(settings)
	return settings_menu


## Shows the save slots screen over the title.
func open_slots() -> SlotPicker:
	if slot_picker != null or start_screen == null:
		return slot_picker
	slot_picker = SlotPicker.new()
	slot_picker.name = "SlotPicker"
	start_screen.add_child(slot_picker)
	slot_picker.slot_chosen.connect(choose_slot, CONNECT_DEFERRED)
	slot_picker.delete_requested.connect(delete_slot, CONNECT_DEFERRED)
	slot_picker.closed.connect(_on_slots_closed, CONNECT_DEFERRED)
	slot_picker.open(SaveSlots.peek_all(), SaveSlots.number_of(session.slot), session.catalog)
	return slot_picker


## Plays slot n from now on (remembered in the settings) and shows its title screen.
func choose_slot(n: int) -> void:
	settings.set_value("game/slot", n)
	settings.save_file()
	slot_picker = null
	open_session(SaveSlots.path(n))


## Deletes slot n's save (the slots screen already asked) and refreshes the slots and the title.
## Returns the error, OK when the files are gone.
func delete_slot(n: int) -> Error:
	var err := SaveSlots.delete(SaveSlots.path(n))
	# The title first (its rebuild grabs focus), then the slots screen, so focus ends on the slots
	# screen that is still open on top.
	if err == OK and start_screen != null and SaveSlots.number_of(session.slot) == n:
		start_screen.setup(session.peek_slot(), session.catalog, n)
	if slot_picker != null:
		slot_picker.show_slots(SaveSlots.peek_all(), SaveSlots.number_of(session.slot))
	if err != OK:
		_alert("Could not delete slot %d" % n, PackedStringArray([error_string(err)]))
	return err


## "Saved 14:02" (local time) or the save error.
static func save_status_text(result: Dictionary) -> String:
	if not result.ok:
		return str(result.error)
	var t := Time.get_time_dict_from_system()
	return "Saved %02d:%02d" % [t.hour, t.minute]


## The quit dialog for a run with unsaved progress: {"title", "body", "choices", "focus"}.
## Alive: "Save first?" with Save and quit. Dead with its death's save failed: a warning that
## quitting loses that death. Dead and not saved yet (the OD1 fallback, SAVE_ON_DEATH false):
## step 2's "Save first?", with no save while the cell is dead.
static func quit_prompt(dead: bool, death_save_failed: bool) -> Dictionary:
	if dead and death_save_failed:
		return {"title": "Death not saved", "body": DEATH_NOT_SAVED_TEXT,
			"choices": [["quit", "Quit"], ["cancel", "Cancel"]], "focus": "cancel"}
	var body := "You have progress since your last save."
	var choices := [["quit", "Quit without saving"], ["cancel", "Cancel"]]
	if dead:
		body += " Saving is off until you continue after your cell's death."
	else:
		choices.push_front(["save_quit", "Save and quit", true])
	return {"title": "Save first?", "body": body, "choices": choices, "focus": "cancel" if dead else "save_quit"}


## The death notice's title: how the cell died. A kill names its killer (the species'
## death_reason, such as "Caught by an ambush hunter").
static func death_title(cause: String, reason: String = "") -> String:
	if cause == "starved":
		return "Out of energy"
	if cause == "killed" and not reason.is_empty():
		return reason
	return "Your cell died"


## The death notice's body: what the death cost, already applied ("You lost ... (−3)", or that there
## was too little to lose: a quarter of fewer than 4 points rounds down to nothing), whether it
## was saved, then the tip on a line of its own. `saved` is GameSession.resolve_death's
## {"attempted", "ok", "error"}: "Saved.", "Could not save ...", or nothing when no save was tried
## (the OD1 fallback). A starving death without a tip gets GameSession.starved_tip(phenotype), which
## names only a food the body can eat, and no food without a phenotype.
static func death_text(cause: String, lost: int, tip: String = "", saved: Dictionary = {}, generation: int = 1,
		phenotype: Phenotype = null) -> String:
	var text := "The lineage continues from the start of generation %d. " % generation
	if lost > 0:
		text += "You lost a quarter of your unspent adaptation points (−%d)." % lost
	else:
		text += "You had too few unspent adaptation points to lose any."
	var save_line := death_save_line(saved)
	if not save_line.is_empty():
		text += " " + save_line
	if tip.is_empty() and cause == "starved":
		tip = GameSession.starved_tip(phenotype)
	if not tip.is_empty():
		text += "\n" + tip
	return text


## "Saved.", the save's error ("Could not save to …: …."), or "" when no save was tried.
static func death_save_line(saved: Dictionary) -> String:
	if not bool(saved.get("attempted", false)):
		return ""
	if bool(saved.get("ok", false)):
		return "Saved."
	var error := str(saved.get("error", ""))
	return error if error.begins_with("Could not save") else "Could not save: %s" % error


## The message after Continue: "Back at the generation start · sheltered for 5 s." (no shelter
## part when there is none, as in a pool without creatures).
static func respawn_text(shelter_s: int) -> String:
	if shelter_s <= 0:
		return "Back at the generation start."
	return "Back at the generation start · sheltered for %d s." % shelter_s


## "Seed 4242 · build 0.0.2-m1+abc1234" for the pause menu.
func footer_text() -> String:
	return "Seed %d · build %s" % [session.sim.save.world_seed, BuildInfo.build_id()]


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and settings != null:
		settings.set_window_focused(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and settings != null:
		settings.set_window_focused(true)


func _input(event: InputEvent) -> void:
	InputPrompts.note(event)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		get_viewport().set_input_as_handled()
		toggle_fullscreen()


func _open_pool() -> void:
	_clear_screen()
	pool = POOL_SCENE.instantiate()
	pool.player_memory = player_memory
	add_child(pool)
	pool.setup(session, intent_provider)
	var ui := pool.ui
	hud = HUD_SCENE.instantiate()
	ui.add_child(hud)
	ui.move_child(hud, 0)   # under the target ring and the starving arrow
	hud.bind_memory(player_memory, save_player_memory)
	hud.bind(pool)
	pause_menu = PAUSE_MENU_SCENE.instantiate()
	ui.add_child(pause_menu)
	death_notice = NOTICE_SCENE.instantiate()
	death_notice.name = "DeathNotice"
	ui.add_child(death_notice)
	pool.pause_requested.connect(_on_pause_requested)
	pool.died.connect(_on_died)
	pool.respawned.connect(_on_respawned)
	pool.giant_pass_started.connect(_on_giant_pass_started)
	pool.mate_requested.connect(open_cell_editor)
	pause_menu.resume_requested.connect(resume)
	pause_menu.save_requested.connect(save_now)
	pause_menu.save_and_quit_requested.connect(save_and_quit_to_title, CONNECT_DEFERRED)
	pause_menu.quit_requested.connect(quit_to_desktop, CONNECT_DEFERRED)
	pause_menu.settings_requested.connect(open_settings, CONNECT_DEFERRED)
	death_notice.chosen.connect(func(_choice: String): continue_after_death())
	_apply_pool_settings()
	_set_screen(pool)


func _clear_screen() -> void:
	quit_dialog.close()
	_paused_for_quit = false
	if screen != null:
		remove_child(screen)
		screen.queue_free()
	screen = null
	start_screen = null
	settings_menu = null
	slot_picker = null
	pool = null
	creature_stage = null
	aquatic_stage = null
	hud = null
	pause_menu = null
	death_notice = null
	cell_editor = null


func _set_screen(node: Node) -> void:
	screen = node
	screen_changed.emit(node)


func _on_pause_requested(reason: String) -> void:
	# An open notice stays in charge; the pool stays paused until it closes.
	if death_notice.is_open() or quit_dialog.is_open():
		return
	pause_menu.open(reason, footer_text(), not session.sim.dead)


## The pool reported the death: resolve it now (the points, and with SAVE_ON_DEATH the save), then
## show what it cost.
func _on_died(cause: String, reason: String = "") -> void:
	pause_menu.close()
	var d := session.resolve_death()
	var lost := int(d.get("lost", 0))
	var tip := str(d.get("tip", ""))
	var saved: Dictionary = d.get("saved", {})
	death_notice.open(death_title(cause, reason),
		death_text(cause, lost, tip, saved, session.sim.save.genome.generation, session.sim.phenotype),
		[["continue", "Continue", true]], "continue")


## The pool reported the respawn: "Back at the generation start · sheltered for 5 s.", in the frame
## the cell shows there.
func _on_respawned(grace_s: float, _teleport: bool) -> void:
	hud.show_message(respawn_text(ceili(grace_s)))


## The giants' first pass for this lineage has started (D-42): this computer remembers it at once, so
## a quit during the pass does not bring it back.
func _on_giant_pass_started() -> void:
	var lineage := session.sim.save.lineage_id if session != null and session.sim != null else ""
	if player_memory == null or lineage.is_empty() or player_memory.giant_pass_lineages.has(lineage):
		return
	player_memory.giant_pass_lineages.append(lineage)
	save_player_memory()


## The settings the running pool reads: pausing on focus loss, and the zoom speed and direction
## (a negative step zooms the other way).
func _apply_pool_settings() -> void:
	if pool == null:
		return
	pool.pause_on_focus_loss = settings.pause_on_focus_loss()
	var cam := pool.camera
	if not cam.has_meta("base_zoom_step"):
		cam.set_meta("base_zoom_step", cam.zoom_step)
	var direction := -1.0 if settings.get_value("controls/invert_zoom") else 1.0
	cam.zoom_step = float(cam.get_meta("base_zoom_step")) * float(settings.get_value("controls/zoom_speed")) * direction


func _on_setting_changed(id: String) -> void:
	if pool != null:
		_apply_pool_settings()
	if start_screen != null and id == "accessibility/reduce_camera_motion":
		start_screen.fit_backdrop()


func _on_settings_closed() -> void:
	if settings_menu != null:
		settings_menu.queue_free()
	settings_menu = null
	if pause_menu != null and pause_menu.is_open():
		pause_menu.settings_button.grab_focus()
	elif start_screen != null:
		start_screen.settings_button.grab_focus()


func _on_slots_closed() -> void:
	if slot_picker != null:
		slot_picker.queue_free()
	slot_picker = null
	if start_screen == null:
		return
	if start_screen.main_view.visible:
		start_screen.slots_button.grab_focus()
	else:
		# The title was left on another view under the overlay: back to its main view, focused.
		start_screen.show_main()


func _on_quit_choice(choice: String) -> void:
	match choice:
		"save_quit":
			var result := session.save_now()
			if result.ok:
				_quit()
			else:
				quit_dialog.open("Could not save", str(result.error),
					[["quit", "Quit without saving"], ["cancel", "Cancel"]], "cancel", "cancel")
		"quit":
			_quit()
		"cancel":
			if _paused_for_quit and pool != null:
				pool.set_paused(false)
			_paused_for_quit = false


func _alert(title: String, errors: PackedStringArray) -> void:
	alert.open(title, "Nothing was changed.", [["ok", "OK", true]], "ok", "ok", "\n".join(errors))


func _quit() -> void:
	# The settings screen writes its file when it closes; a quit from the window's close button (or
	# the pause menu's dialog) while it is open would otherwise drop every change made in it.
	if settings != null and settings.unsaved:
		var err := settings.save_file()
		if err != OK:
			push_warning("Settings could not be saved (%s)." % error_string(err))
	get_tree().quit()


## Debug builds only: the debug panel (F3), dev gizmos and the dev keys (F5 to F10).
func _add_dev_layer() -> void:
	if not OS.is_debug_build() or not ResourceLoader.exists(DEV_PANEL_PATH):
		return
	dev_layer = Node.new()
	dev_layer.name = "DevLayer"
	add_child(dev_layer)
	debug_panel = (load(DEV_PANEL_PATH) as PackedScene).instantiate()
	debug_panel.name = "DebugPanel"
	dev_layer.add_child(debug_panel)
	for path in [DEV_GIZMOS_PATH, DEV_KEYS_PATH]:
		var node: Node = (load(path) as GDScript).new()
		node.name = path.get_file().get_basename().to_pascal_case()
		dev_layer.add_child(node)
	for node in dev_layer.get_children():
		node.call("attach", self)


## --perf-tour: the dev build swims the forage bot for a while and writes a frame-time report.
func _start_perf_tour() -> void:
	if dev_layer == null:
		push_warning("--perf-tour needs a debug build (Pangaea-dev.exe); ignored.")
		return
	var tour: Node = (load(DEV_PERF_TOUR_PATH) as GDScript).new()
	tour.name = "PerfTour"
	dev_layer.add_child(tour)
	tour.call("attach", self)
