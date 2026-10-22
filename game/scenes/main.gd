class_name Main
extends Node
## The game's root scene (M1 step 2). It owns the GameSession and the launch flags (RunFlags),
## shows one screen at a time (the start screen or the pool) and answers the menus. Quitting
## asks "Save first?" when there is unsaved progress, for the window's close button too.
## In debug builds it also adds the dev layer (debug panel, dev gizmos, dev keys) by loading
## game/dev by path; the release export leaves that folder out.
##
## Buttons and the scene smoke use the same methods: start_new(body), continue_run(),
## save_now(), save_and_quit_to_title(), resume(), continue_after_death(), quit_to_desktop().
## open_session(slot) switches save slots, and intent_provider (for example the dev ForageBot)
## swims instead of the player in the next run.

signal screen_changed(screen: Node)

const START_SCREEN_SCENE := preload("res://game/ui/start_screen.tscn")
const POOL_SCENE := preload("res://game/scenes/pool/pool.tscn")
const HUD_SCENE := preload("res://game/ui/hud.tscn")
const PAUSE_MENU_SCENE := preload("res://game/ui/pause_menu.tscn")
const NOTICE_SCENE := preload("res://game/ui/notice_dialog.tscn")
## Debug builds only. Loaded by path, never preloaded, so the release export can leave game/dev out.
const DEV_PANEL_PATH := "res://game/dev/debug_panel.tscn"
const DEV_GIZMOS_PATH := "res://game/dev/dev_gizmos.gd"
const DEV_KEYS_PATH := "res://game/dev/dev_keys.gd"
const DEV_PERF_TOUR_PATH := "res://game/dev/perf_tour.gd"

var flags: RunFlags
var session: GameSession
## Swims for the player in the next run when set (anything with next_intent(sim) -> SimIntent).
var intent_provider: Object
## The screen shown now: start_screen or pool.
var screen: Node
var start_screen: StartScreen
var pool: PoolScene
var hud: Hud
var pause_menu: PauseMenu
var death_notice: NoticeDialog
## The result of the last start_new() or continue_run().
var last_run := {}
## Debug builds only; null in a release build.
var dev_layer: Node
var debug_panel: Node

var _paused_for_quit := false

@onready var quit_dialog: NoticeDialog = %QuitDialog
@onready var alert: NoticeDialog = %Alert


func _ready() -> void:
	get_tree().auto_accept_quit = false
	flags = RunFlags.current()
	for problem in flags.problems:
		push_warning(problem)
	open_session(flags.slot)
	quit_dialog.chosen.connect(_on_quit_choice)
	_add_dev_layer()
	if flags.perf_tour:
		_start_perf_tour()
	if screen == null:
		show_start()


## Uses another save slot ("" for the default) and shows its start screen if a screen is up.
func open_session(slot: String) -> void:
	session = GameSession.new(slot if not slot.is_empty() else GameSession.DEFAULT_SLOT)
	if screen != null:
		show_start()


func show_start() -> void:
	_clear_screen()
	start_screen = START_SCREEN_SCENE.instantiate()
	add_child(start_screen)
	start_screen.setup(session.peek_slot(), session.catalog)
	# Deferred, so a screen is never swapped out from under the button that asked for it.
	start_screen.new_requested.connect(start_new, CONNECT_DEFERRED)
	start_screen.continue_requested.connect(continue_run, CONNECT_DEFERRED)
	start_screen.quit_requested.connect(quit_to_desktop, CONNECT_DEFERRED)
	_set_screen(start_screen)


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


## Death notice: Continue. Applies the death rule and puts the cell back at the start. Returns
## the points lost.
func continue_after_death() -> int:
	if pool == null or not session.sim.dead:
		return 0
	death_notice.close()
	pool.set_paused(false)
	var lost := session.respawn_after_death()
	hud.show_message("Back at the start: %s lost." % Hud.points_line(lost))
	return lost


## Pause menu and start screen: Quit. Asks "Save first?" when there is unsaved progress.
func quit_to_desktop() -> void:
	request_quit()


## Quits, or first asks "Save first?" when a run has unsaved progress (the window's close
## button comes here too).
func request_quit() -> void:
	if pool == null or not session.dirty:
		_quit()
		return
	if not pool.paused:
		pool.set_paused(true)
		_paused_for_quit = true
	var body := "You have progress since your last save."
	var choices := [["quit", "Quit without saving"], ["cancel", "Cancel"]]
	if session.sim.dead:
		body += " Saving is off until you continue after your cell's death."
	else:
		choices.push_front(["save_quit", "Save and quit", true])
	quit_dialog.open("Save first?", body, choices, "cancel" if session.sim.dead else "save_quit", "cancel")


func toggle_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


## "Saved 14:02" (local time) or the save error.
static func save_status_text(result: Dictionary) -> String:
	if not result.ok:
		return str(result.error)
	var t := Time.get_time_dict_from_system()
	return "Saved %02d:%02d" % [t.hour, t.minute]


## The death notice's title. The body (`death_text`) already says how the cell died.
static func death_title(cause: String) -> String:
	return "Out of energy" if cause == "starved" else "Your cell died"


static func death_text(cause: String, lost: int) -> String:
	return "Your cell %s. The lineage continues. You lose a quarter of your unspent adaptation points (−%d)." \
		% ["starved" if cause == "starved" else "died", lost]


## "Seed 4242 · build 0.0.2-m1+abc1234" for the pause menu.
func footer_text() -> String:
	return "Seed %d · build %s" % [session.sim.save.world_seed, BuildInfo.build_id()]


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		get_viewport().set_input_as_handled()
		toggle_fullscreen()


func _open_pool() -> void:
	_clear_screen()
	pool = POOL_SCENE.instantiate()
	add_child(pool)
	pool.setup(session, intent_provider)
	var ui := pool.ui
	hud = HUD_SCENE.instantiate()
	ui.add_child(hud)
	ui.move_child(hud, 0)   # under the target ring and the starving arrow
	hud.bind(pool)
	pause_menu = PAUSE_MENU_SCENE.instantiate()
	ui.add_child(pause_menu)
	death_notice = NOTICE_SCENE.instantiate()
	death_notice.name = "DeathNotice"
	ui.add_child(death_notice)
	pool.pause_requested.connect(_on_pause_requested)
	pool.died.connect(_on_died)
	pause_menu.resume_requested.connect(resume)
	pause_menu.save_requested.connect(save_now)
	pause_menu.save_and_quit_requested.connect(save_and_quit_to_title, CONNECT_DEFERRED)
	pause_menu.quit_requested.connect(quit_to_desktop, CONNECT_DEFERRED)
	death_notice.chosen.connect(func(_choice: String): continue_after_death())
	_set_screen(pool)


func _clear_screen() -> void:
	quit_dialog.close()
	_paused_for_quit = false
	if screen != null:
		remove_child(screen)
		screen.queue_free()
	screen = null
	start_screen = null
	pool = null
	hud = null
	pause_menu = null
	death_notice = null


func _set_screen(node: Node) -> void:
	screen = node
	screen_changed.emit(node)


func _on_pause_requested(reason: String) -> void:
	# An open notice stays in charge; the pool stays paused until it closes.
	if death_notice.is_open() or quit_dialog.is_open():
		return
	pause_menu.open(reason, footer_text(), not session.sim.dead)


func _on_died(cause: String, _reason: String = "") -> void:
	pause_menu.close()
	var lost := Lineage.death_loss(session.sim.save.adaptation_points)
	death_notice.open(death_title(cause), death_text(cause, lost),
		[["continue", "Continue", true]], "continue")


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
	get_tree().quit()


## Debug builds only: the debug panel (F3), dev gizmos and the dev keys (F5 to F8).
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
