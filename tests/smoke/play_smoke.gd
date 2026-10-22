extends SceneTree
## Two-process scene smoke (M1 step 2). tools/check.sh runs it twice with --fixed-fps 60, so each
## frame is exactly one sim tick and 2400 frames are 40 s of sim time. It drives the real main
## scene through the methods, buttons and keys a player uses, with the dev ForageBot swimming
## instead of the player, and prints one PASS or FAIL line per check and a TIME line per step.
## Buttons are clicked with the mouse through the viewport, and only when a player could click
## them: on screen, enabled and not covered. Exit code 0 when every check passes, 1 otherwise.
##
##   -- --phase=found --slot=user://smoke/slot_1.json --seed=4242
##       Clears user://smoke/ and opens the start screen. A grazer lineage eats, starves and
##       recovers, dies and continues, pauses and resumes, then saves and quits to the title.
##       Hunter and omnivore lineages on their own slots eat too. Then the grazer continues and
##       swims, and the window's close button saves and quits through "Save first?", which ends
##       the process; expect.json records what Continue must bring back.
##   -- --phase=continue --slot=user://smoke/slot_1.json
##       A new process: Continue must bring back the lineage, body, parts, points and place in
##       user://smoke/expect.json, and the run must play.
##
## Nodes are awaited into the tree before use. Saves stay under user://smoke/: the smoke stops
## before playing if --slot points anywhere else.

const MAIN_SCENE := "res://game/scenes/main.tscn"
const ForageBot := preload("res://game/dev/forage_bot.gd")
const SMOKE_DIR := "user://smoke"
const EXPECT_PATH := "user://smoke/expect.json"
const MEAL_TICKS := 2400            ## each body must eat within 40 s of sim time
const RECOVER_TICKS := 1200         ## a starving cell dies after 20 s, so it must eat sooner
const DEATH_TICKS := 1500
const VIEW_SIZE := Vector2(1920, 1080)
const CENTRAL_SHARE := 0.4          ## the cell stays inside the central 40% of the view
const PITCH_DEG := 55.0
const HUD_LAG_FRAMES := 8           ## HUD labels refresh at 10 Hz (6 frames), plus slack
const RUN_FRAMES := 10              ## frames watched to see the sim stand still or run
const FADE_SLACK_FRAMES := 2        ## the pool's fade-in may still show this long after FADE_IN_S
## A deliberate stall: the debug panel must show it at its wall-clock length, not the ~150 ms
## the engine's delta caps it at (here, under --fixed-fps, delta is always one tick).
const STALL_MS := 400
const BAR_STEP := 0.01              ## the HUD bars round their value to this step
## Points before the death, so the death rule's quarter of them takes at least 1.
const POINTS_BEFORE_DEATH := 4
const POSITION_TOLERANCE_M := 1e-3
const ANGLE_TOLERANCE := 1e-6
## Half of the last shown digit of each body card stat: speed, turning, upkeep, sight, max energy.
const STAT_ROUNDING: PackedFloat64Array = [0.05, 0.5, 0.005, 0.5, 0.5]


## Calls back after every other node's _process each frame (the highest process_priority), so
## it sees what the views drew in that frame.
class FrameProbe extends Node:
	var on_frame: Callable

	func _init(callback: Callable) -> void:
		on_frame = callback
		process_priority = 1000

	func _process(_delta: float) -> void:
		on_frame.call()


var main: Main
var _failures := 0
var _checks := 0
var _finished := false
## The next quit is the game's own (Save and quit in "Save first?"), so _finalize reports.
var _quit_expected := false
var _step_name := ""
var _step_msec := 0
var _numbers := RegEx.create_from_string("-?\\d+(\\.\\d+)?")
## Sim events seen in the current run, by type, and the meals among them.
var _events := {}
var _meals: Array[Dictionary] = []
var _event_points := 0
var _hud_meal_mismatches := PackedStringArray()
## What the probe saw in the current run, frame by frame.
var _view := {}


func _initialize() -> void:
	var phase := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):
			phase = arg.trim_prefix("--phase=")
	print("Scene smoke, phase '%s', build %s" % [phase, BuildInfo.build_id()])
	root.add_child(FrameProbe.new(_probe_frame))
	match phase:
		"found":
			await _found()
		"continue":
			await _continue()
		_:
			_check(false, "--phase is found or continue (got '%s')" % phase)
	_finished = true
	_report()


## The game quit: as the found phase expects after "Save first?", or before the smoke finished
## (a quit with exit code 0 would hide that).
func _finalize() -> void:
	if _finished:
		return
	_finished = true
	if _quit_expected:
		_check(true, "Save and quit closes the game")
		_report()
		return
	print("FAIL the game quit before the smoke finished (step '%s')" % _step_name)
	quit(1)


func _report() -> void:
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


# Found phase

func _found() -> void:
	_begin("start screen")
	_clear_dir(SMOKE_DIR)
	await _open_main()
	if not _slot_is_safe():
		return
	var start := main.start_screen
	_check(start != null and main.screen == start, "the main scene opens on the start screen")
	if start == null:
		return
	_check(start.continue_button.disabled, "Continue is off while the slot has no save")
	_check(_focus() == start.new_button, "New lineage has the keyboard focus")
	_check_body_cards(start)
	_end()

	_begin("grazer eats")
	if not _click(start.new_button, "New lineage"):
		start.open_picker()
	await _frames(1)
	_check(_shown(start.picker_view) and _focus() == start.card_for("grazer"), "the picker opens with the grazer card focused")
	start.select("grazer")
	main.intent_provider = ForageBot.new()
	if not _click(start.start_button, "the picker's Start"):
		start.request_start()
	await _frames(2)
	var started: bool = await _check_run_started("grazer")
	if not started:
		return
	var pool := main.pool
	var sim := pool.sim
	_check(sim.save.world_seed == main.flags.seed_value or main.flags.seed_value < 0, "the lineage uses the --seed world seed (%d)" % sim.save.world_seed)
	var ticks := await _ticks_until(sim, func(): return _meals.size() >= 2 and sim.save.adaptation_points >= 2, MEAL_TICKS)
	_check(_meals.size() >= 2 and sim.save.adaptation_points >= 2,
		"the grazer ate %d times and has %d points after %.1f s" % [_meals.size(), sim.save.adaptation_points, ticks * PoolSim.DT])
	_check(_meals.all(func(m: Dictionary): return m.kind == "plant"), "the grazer ate only plankton")
	_check(sim.save.adaptation_points == _event_points, "every point came with an ate or earned event the HUD shows (%d)" % _event_points)
	_check(_hud_meal_mismatches.is_empty(), "at each meal the HUD energy text equals the sim energy %s" % _hud_meal_mismatches)
	await _check_hud_now(sim)
	_check_cell_view(pool)
	_check_camera(pool)
	_check_view_record("the grazer run")
	await _check_debug_panel(sim)
	_end()

	_begin("starve and recover")
	await _starve_and_recover(pool)
	_end()

	_begin("death notice")
	await _die_and_continue(pool)
	_check_view_record("the grazer run, starving, death and respawn included")
	_end()

	_begin("save and quit to title")
	var expect := await _save_and_quit_to_title(pool)
	_end()
	if expect.is_empty():
		return

	_begin("hunter and omnivore eat")
	for body in ["hunter", "omnivore"]:
		await _brief_run(body)
	_check_slot_kept(expect)
	_end()

	# Last, because Save and quit in "Save first?" ends the process.
	_begin("close the window and save")
	await _continue_and_close_window(expect)


## Every body card shows the stats Phenotype.derive gives its starting genome.
func _check_body_cards(start: StartScreen) -> void:
	var cards := start.body_cards()
	var bodies := PackedStringArray()
	for card in cards:
		bodies.append(card.body)
	_check(bodies == BodyText.ORDER, "the picker has the three starting bodies in order %s" % bodies)
	var catalog := main.session.catalog
	for card in cards:
		var founded := Lineage.found(0, BuildInfo.build_id(), catalog, card.body)
		var p := Phenotype.derive(founded.save.genome, catalog)
		var formatted := PackedStringArray()
		for row in BodyText.stat_rows(p):
			formatted.append(row[1])
		var shown := card.stat_values()
		_check(shown == formatted, "the %s card shows the formatted derived stats %s" % [card.body, shown])
		var derived := [p.speed, rad_to_deg(p.turn_rate), p.upkeep, p.sight, p.energy_capacity]
		var close := shown.size() == derived.size()
		for i in mini(shown.size(), derived.size()):
			close = close and absf(_first_number(shown[i]) - derived[i]) <= STAT_ROUNDING[i] + 1e-6
		_check(close, "the %s card's numbers round the phenotype's %s" % [card.body, derived])
		_check(card.diet_text() == BodyText.diet(p), "the %s card says '%s'" % [card.body, card.diet_text()])


## The pool and HUD are up for a new lineage of `body`, played by the forage bot.
func _check_run_started(body: String) -> bool:
	var ok := main.pool != null and main.hud != null and main.screen == main.pool and bool(main.last_run.get("ok", false))
	_check(ok, "a new %s lineage opens the pool with its HUD %s" % [body, main.last_run.get("errors", [])])
	if not ok:
		return false
	var sim := main.pool.sim
	_check(Lineage.starting_body_of(sim.save.genome, sim.catalog) == body, "the pool runs the %s body" % body)
	_check(bool(main.last_run.get("saved", false)) and FileAccess.file_exists(main.session.slot), "founding saved the slot %s" % main.session.slot)
	_check(main.pool.intent_provider == main.intent_provider, "the forage bot swims for the player")
	_watch(main.pool)
	await _frames(1)
	return true


## The HUD labels are on screen and name the sim's energy and points once they have refreshed.
func _check_hud_now(sim: PoolSim) -> void:
	await _frames(HUD_LAG_FRAMES)
	var hud := main.hud
	var energy_ok := absf(_first_number(hud.energy_text.text) - sim.state.energy) <= 1.0
	_check(_shown(hud.energy_text) and energy_ok and hud.energy_text.text.ends_with("/ %d" % roundi(sim.state.energy_capacity)),
		"the HUD shows '%s' for sim energy %.2f / %.0f" % [hud.energy_text.text, sim.state.energy, sim.state.energy_capacity])
	_check(_shown(hud.points_text) and hud.points_text.text == Hud.points_line(sim.save.adaptation_points)
		and int(_first_number(hud.points_text.text)) == sim.save.adaptation_points, "the HUD shows '%s'" % hud.points_text.text)


## The cell view drawn at fraction 1 sits exactly on the sim's position and faces its heading.
func _check_cell_view(pool: PoolScene) -> void:
	var motion := pool.sim.motion
	pool.cell_view.show_motion(motion, 1.0)
	var at := pool.cell_view.global_position
	var want := PlaneSpace.to_world(motion.position)
	_check(at.distance_to(want) <= POSITION_TOLERANCE_M, "the cell view is within 1 mm of the sim position (%.6f m)" % at.distance_to(want))
	var facing := -pool.cell_view.global_transform.basis.z.normalized()
	var heading := PlaneSpace.to_world(Vector2.from_angle(motion.heading))
	_check(facing.distance_to(heading) <= 1e-3, "the cell view faces the sim heading")


func _check_camera(pool: PoolScene) -> void:
	var forward := -pool.camera.global_transform.basis.z.normalized()
	var pitch := rad_to_deg(asin(-forward.y))
	_check(absf(pitch - PITCH_DEG) <= 0.5, "the camera looks down at %.2f degrees" % pitch)
	_check(absf(forward.x) <= 1e-4 and forward.z < 0.0, "the camera faces north and does not turn")


## What the frame probe saw over a run: the cell on screen and the food views in step.
func _check_view_record(run: String) -> void:
	var limit := CENTRAL_SHARE * 0.5
	_check(_view.frames > 0 and _view.rect == VIEW_SIZE, "%s was drawn in a %s view for %d frames" % [run, _view.rect, _view.frames])
	_check(_view.worst_offset <= limit and _view.behind == 0,
		"the cell stayed in the central 40%% of the view in %s (worst %.3f of the screen from the centre)" % [run, _view.worst_offset])
	_check(_view.food_mismatch == 0 and _view.plankton_drawn > 0,
		"the food views drew the sim's plankton and carrion counts every frame of %s (%d misses; last %d plankton, %d carrion)"
		% [run, _view.food_mismatch, _view.plankton_drawn, _view.carrion_drawn])
	_check(_view.food_misplaced == 0,
		"the food views drew every plankton and carrion item at its sim position every frame of %s (%d misses)" % [run, _view.food_misplaced])
	_check(_view.fade_late == 0,
		"the pool's fade-in cleared after %.1f s in %s (shown %d frames late)" % [PoolScene.FADE_IN_S, run, _view.fade_late])
	_check(_view.bar_worst <= BAR_STEP + 1e-6, "the energy bar showed the sim energy every frame of %s (worst %.3f off)" % [run, _view.bar_worst])
	_check(_view.hud_worst_lag <= HUD_LAG_FRAMES, "the HUD energy text never lagged the sim by more than %d frames in %s (%d)" % [HUD_LAG_FRAMES, run, _view.hud_worst_lag])


## F3 opens the debug panel, which names the genome and the world seed, and shows a stalled
## frame as its longest.
func _check_debug_panel(sim: PoolSim) -> void:
	var panel: CanvasLayer = main.debug_panel
	_check(panel != null and main.dev_layer != null, "the debug build has the dev layer and debug panel")
	if panel == null:
		return
	await _press(&"toggle_debug")
	_check(panel.visible, "F3 shows the debug panel")
	panel.call("refresh")
	var identity := (panel.get_node("%Identity") as Label).text
	_check(identity.contains("Genome %s" % sim.save.genome.genome_id) and identity.contains("World seed %d" % sim.save.world_seed),
		"the debug panel names genome %s and world seed %d" % [sim.save.genome.genome_id, sim.save.world_seed])
	OS.delay_msec(STALL_MS)
	await _frames(2)
	panel.call("refresh")
	var longest: float = panel.get("fields").get("longest_frame_ms", 0.0)
	_check(longest >= STALL_MS * 0.95 and longest < STALL_MS * 2.0,
		"the debug panel shows a %d ms stall as its longest frame (%.1f ms)" % [STALL_MS, longest])
	await _press(&"toggle_debug")
	_check(not panel.visible, "F3 hides it again")


## Back at the spawn, away from food, F6 drains the cell: the starving banner, health bar and
## food arrow show; the bot swims to food, eats, and they go away.
func _starve_and_recover(pool: PoolScene) -> void:
	var sim := pool.sim
	var hud := main.hud
	_check(main.debug_panel.call("run", "teleport") and sim.motion.position.distance_to(sim.layout.spawn) <= POSITION_TOLERANCE_M,
		"the debug panel's Teleport puts the cell at the spawn")
	await _press(&"dev_drain")
	if sim.state.energy > 0.0 and not sim.state.is_starving():
		_check(false, "F6 drains the cell's energy (%.1f left)" % sim.state.energy)
		sim.debug_set_energy(0.0)
	else:
		_check(true, "F6 drains the cell's energy")
	await _ticks_until(sim, func(): return sim.state.is_starving(), 10)
	await _frames(1)
	_check(sim.state.is_starving() and sim.state.speed_multiplier() <= 0.5, "the cell starves at half speed")
	_check(_shown(hud.starving_banner) and _shown(hud.banner_text) and hud.banner_text.text == Hud.STARVING_TEXT, "the starving banner shows")
	_check(_shown(hud.state_text) and hud.state_text.text == "Starving" and _shown(hud.health_row), "the HUD says Starving and shows health")
	_check(_shown(pool.starving_arrow), "the arrow points to food")
	var meals_before := _meals.size()
	var ticks := await _ticks_until(sim, func(): return not sim.state.is_starving() or sim.dead, RECOVER_TICKS)
	_check(not sim.dead and not sim.state.is_starving() and _meals.size() > meals_before,
		"the bot found food and stopped starving after %.1f s" % (ticks * PoolSim.DT))
	await _frames(2)
	_check(not hud.starving_banner.visible and not pool.starving_arrow.visible, "the banner and the arrow are gone")
	_check(hud.state_text.text != "Starving", "the HUD no longer says Starving (%s)" % hud.state_text.text)


## A drained cell parked away from food dies; the notice names the points the death takes and
## keeps the pause key, the window's close button offers no save while the cell is dead, and
## the notice's Continue puts the cell back at the start and play goes on.
func _die_and_continue(pool: PoolScene) -> void:
	var sim := pool.sim
	var bot := main.intent_provider as ForageBot
	# A quarter of fewer than 4 points rounds down to nothing, so eat a little more first.
	var ticks := await _ticks_until(sim, func(): return sim.save.adaptation_points >= POINTS_BEFORE_DEATH, MEAL_TICKS)
	_check(sim.save.adaptation_points >= POINTS_BEFORE_DEATH and not sim.dead,
		"the grazer kept eating to %d points in %.1f s" % [sim.save.adaptation_points, ticks * PoolSim.DT])
	_check(sim.debug_teleport(sim.layout.spawn, sim.layout.spawn_heading), "the cell goes back to the spawn, away from food")
	bot.park_at = sim.layout.spawn
	sim.debug_set_energy(0.0)
	var deaths_before := int(_events.get("died", 0))
	ticks = await _ticks_until(sim, func(): return sim.dead, DEATH_TICKS)
	await _frames(2)
	_check(sim.dead and int(_events.get("died", 0)) == deaths_before + 1, "the starving cell died once, after %.1f s" % (ticks * PoolSim.DT))
	var notice := main.death_notice
	var points := sim.save.adaptation_points
	var loss := Lineage.death_loss(points)
	_check(_shown(notice) and notice.body_text().contains("(−%d)" % loss), "the death notice names the loss: %s" % notice.body_text())
	await _press(&"pause")
	_check(not main.pause_menu.is_open() and _shown(notice), "the pause key leaves the death notice in charge")
	var button := notice.button_for("continue")
	_check(button != null and _focus() == button, "the notice's Continue has the keyboard focus")
	var dialog := main.quit_dialog
	root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await _frames(1)
	_check(_shown(dialog) and dialog.choice_ids() == PackedStringArray(["quit", "cancel"]) and _focus() == dialog.button_for("cancel"),
		"the window's close button asks 'Save first?' with no save choice while the cell is dead (%s)" % dialog.choice_ids())
	if not _click(dialog.button_for("cancel"), "the dialog's Cancel"):
		dialog.choose("cancel")
	await _frames(1)
	_check(not dialog.is_open() and _shown(notice) and button != null and _focus() == button, "Cancel goes back to the death notice")
	if not _click(button, "the notice's Continue"):
		main.continue_after_death()
	await _frames(2)
	_check(not sim.dead and not notice.is_open(), "Continue brings the cell back")
	_check(loss >= 1 and sim.save.adaptation_points == points - loss and str(sim.save.lineage_history.back().get("event", "")) == "died",
		"the lineage lost %d of %d points and its history records the death" % [loss, points])
	_check(sim.motion.position.distance_to(sim.layout.spawn) <= POSITION_TOLERANCE_M and sim.state.health == sim.state.max_health,
		"the cell is back at the start with full health")
	bot.park_at = Vector2.INF
	await _check_running(pool, "play goes on after the death", 30)


## The pause key opens the pause menu and the sim stands still; the pause key and Resume each
## close it and the sim runs again. Quit asks first because of the unsaved progress; Save and
## quit to title saves and shows the title with Continue. Returns what expect.json records ({} on
## failure).
func _save_and_quit_to_title(pool: PoolScene) -> Dictionary:
	var sim := pool.sim
	await _press(&"pause")
	var menu := main.pause_menu
	_check(_shown(menu) and pool.paused, "the pause key opens the pause menu and pauses the pool")
	_check(_focus() == menu.resume_button, "Resume has the keyboard focus")
	var still := await _ticks_in(sim, RUN_FRAMES)
	_check(still == 0, "the sim stands still under the pause menu (%d ticks in %d frames)" % [still, RUN_FRAMES])
	await _press(&"pause")
	await _check_running(pool, "the pause key closes the pause menu and the sim runs again")
	await _press(&"pause")
	if not _click(menu.resume_button, "Resume"):
		main.resume()
	await _check_running(pool, "Resume closes the pause menu and the sim runs again")
	await _press(&"pause")
	_check(_shown(menu) and pool.paused and _focus() == menu.resume_button, "the pause key opens the pause menu again, with Resume focused")
	_check(menu.footer_text() == "Seed %d · build %s" % [sim.save.world_seed, BuildInfo.build_id()], "the footer reads '%s'" % menu.footer_text())
	_check(not menu.save_button.disabled and not menu.save_quit_button.disabled, "a living cell can save from the pause menu")
	if main.session.dirty:
		if not _click(menu.quit_button, "Quit to desktop"):
			main.quit_to_desktop()
		await _frames(2)
		var dialog := main.quit_dialog
		var choices := dialog.choice_ids()
		_check(_shown(dialog) and choices == PackedStringArray(["save_quit", "quit", "cancel"]),
			"Quit to desktop asks 'Save first?' with %s" % choices)
		if not _click(dialog.button_for("cancel"), "the dialog's Cancel"):
			dialog.choose("cancel")
		await _frames(1)
		_check(not dialog.is_open() and _shown(menu) and pool.paused, "Cancel returns to the pause menu")
	else:
		_check(false, "the run has unsaved progress before Save and quit")
	if not _click(menu.save_quit_button, "Save and quit to title"):
		main.save_and_quit_to_title()
	await _frames(2)
	var start := main.start_screen
	_check(start != null and main.screen == start and main.pool == null, "Save and quit to title shows the title")
	_check(main.session.last_save.get("ok", false) and not main.session.dirty, "the save succeeded")
	if start == null or not main.session.last_save.get("ok", false):
		return {}
	var save := sim.save
	var position := PlaneSpace.from_save(save.player.position)
	_check(position.distance_to(sim.motion.position) <= POSITION_TOLERANCE_M, "the save holds the cell's position")
	_check(not start.continue_button.disabled and _focus() == start.continue_button, "Continue is on and has the keyboard focus")
	var expect := _expect_from(sim)
	var wrote := _write_expect(expect)
	_check(wrote, "wrote %s" % EXPECT_PATH)
	return expect if wrote else {}


## What Continue must bring back after the grazer's run was saved: the run as it is now, not
## what its save holds, so a save that wrote nothing fails the continue phase.
func _expect_from(sim: PoolSim) -> Dictionary:
	var save := sim.save
	var parts := []
	for part in save.genome.parts:
		parts.append({"type": str(part.get("type", "")), "angle": float(part.get("angle", 0.0))})
	var position := sim.motion.position
	return {
		"lineage_id": save.lineage_id,
		"lineage_tag": GameSession.lineage_tag(save.lineage_id),
		"genome_id": save.genome.genome_id,
		"body": "grazer",
		"generation": save.genome.generation,
		"parts": parts,
		"points": save.adaptation_points,
		"position": [position.x, position.y],
		"world_seed": save.world_seed,
	}


func _write_expect(expect: Dictionary) -> bool:
	var file := FileAccess.open(EXPECT_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(expect, "\t", true, true))
	file.close()
	return true


## A new lineage of `body` on its own slot eats something it can eat within 40 s.
func _brief_run(body: String) -> void:
	main.open_session("%s/%s.json" % [SMOKE_DIR, body])
	await _frames(1)
	main.intent_provider = ForageBot.new()
	main.start_new(body)
	await _frames(1)
	var started: bool = await _check_run_started(body)
	if not started:
		return
	var sim := main.pool.sim
	var ticks := await _ticks_until(sim, func(): return not _meals.is_empty(), MEAL_TICKS)
	var kinds := PackedStringArray()
	for meal in _meals:
		kinds.append(meal.kind)
	_check(not _meals.is_empty() and _meals.all(func(m: Dictionary): return sim.phenotype.can_eat(m.kind)),
		"the %s ate %s after %.1f s" % [body, kinds, ticks * PoolSim.DT])
	_check(sim.save.adaptation_points == _event_points and sim.save.adaptation_points > 0, "the %s earned %d points" % [body, sim.save.adaptation_points])
	_check_view_record("the %s run" % body)
	main.show_start()
	await _frames(1)


## The grazer's slot still holds the grazer lineage after the other bodies' runs.
func _check_slot_kept(expect: Dictionary) -> void:
	var slot := RunFlags.current().slot
	var peek := GameSession.new(slot).peek_slot()
	_check(peek.ok and peek.summary.lineage_id == expect.lineage_id and peek.summary.body == "grazer",
		"the other runs left %s alone" % slot)


## Continue on the title brings back what Save and quit to title wrote. The grazer swims away
## from that place (unsaved progress), then the window's close button asks "Save first?". Its Save
## and quit writes the slot and quits the game at the end of that frame, so the slot is checked in
## the same frame and expect.json records it for the continue phase.
func _continue_and_close_window(expect: Dictionary) -> void:
	main.open_session(RunFlags.current().slot)
	await _frames(1)
	main.intent_provider = ForageBot.new()
	if not _click(main.start_screen.continue_button, "Continue"):
		main.continue_run()
	await _frames(2)
	var pool := main.pool
	_check(pool != null and main.last_run.get("source", "") == "primary", "Continue opens the grazer's slot %s" % main.last_run)
	if pool == null:
		_end()
		return
	var sim := pool.sim
	var saved := Vector2(expect.position[0], expect.position[1])
	# The bot has already swum a tick, so the place is read from the loaded save.
	_check(sim.save.lineage_id == expect.lineage_id and sim.save.adaptation_points == int(expect.points)
		and PlaneSpace.from_save(sim.save.player.position).distance_to(saved) <= POSITION_TOLERANCE_M,
		"Continue loads the lineage, points and place that Save and quit to title wrote")
	var away := func(): return sim.motion.position.distance_to(saved) > GameSession.DIRTY_MOVE_M
	var ticks := await _ticks_until(sim, away, MEAL_TICKS)
	_check(away.call() and main.session.dirty, "the grazer swam away from its saved place in %.1f s" % (ticks * PoolSim.DT))
	var dialog := main.quit_dialog
	root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await _frames(1)
	_check(_shown(dialog) and pool.paused and dialog.choice_ids() == PackedStringArray(["save_quit", "quit", "cancel"])
		and _focus() == dialog.button_for("save_quit"),
		"the window's close button pauses and asks 'Save first?' with Save and quit focused (%s)" % dialog.choice_ids())
	_quit_expected = true
	if not _click(dialog.button_for("save_quit"), "the dialog's Save and quit"):
		_quit_expected = false
		_end()
		return
	var session := main.session
	_check(session.last_save.get("ok", false) and not session.dirty, "Save and quit saved the run %s" % session.last_save)
	var loaded := session.persistence.load_from(session.slot)
	var position := PlaneSpace.from_save(loaded.save.player.position) if loaded.ok else Vector2.INF
	_check(loaded.ok and loaded.save.lineage_id == expect.lineage_id and loaded.save.adaptation_points == sim.save.adaptation_points
		and position.distance_to(sim.motion.position) <= POSITION_TOLERANCE_M,
		"the slot holds the run's %d points and new place (%.2f m from the last save)" % [sim.save.adaptation_points, position.distance_to(saved)])
	_check(_write_expect(_expect_from(sim)), "wrote %s again" % EXPECT_PATH)
	_end()
	# The game quits at the end of this frame and _finalize reports; still running means it did not.
	await _frames(2)
	_quit_expected = false
	_check(false, "Save and quit closes the game")


# Continue phase

func _continue() -> void:
	_begin("continue card")
	var expect: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECT_PATH))
	_check(expect is Dictionary, "the found phase left %s" % EXPECT_PATH)
	if not expect is Dictionary:
		return
	await _open_main()
	if not _slot_is_safe():
		return
	var start := main.start_screen
	_check(start != null and not start.continue_button.disabled, "Continue is on")
	if start == null:
		return
	_check(_focus() == start.continue_button, "Continue has the keyboard focus")
	var lines := start.continue_lines()
	_check(lines.size() >= 3 and lines[0] == BodyText.body_name(expect.body) and lines[1].contains(expect.lineage_tag),
		"the Continue card names the body and lineage tag %s" % lines)
	_check(lines.size() >= 3 and lines[2] == "Generation %d · %s" % [int(expect.generation), Hud.points_line(int(expect.points))],
		"the Continue card shows the generation and points")
	_check(_parts_match(start.continue_preview.part_nodes(), expect.parts), "the Continue card's preview has the saved parts")
	_end()

	_begin("continue run")
	if not _click(start.continue_button, "Continue"):
		main.continue_run()
	await _frames(2)
	var pool := main.pool
	_check(pool != null and main.screen == pool and main.last_run.get("ok", false) and main.last_run.get("source", "") == "primary",
		"Continue opens the pool from the primary save %s" % main.last_run)
	if pool == null:
		return
	_watch(pool)
	await _frames(1)
	var sim := pool.sim
	_check(sim.save.lineage_id == expect.lineage_id, "the lineage is the same (%s)" % sim.save.lineage_id)
	_check(sim.save.genome.genome_id == expect.genome_id, "the genome is the same (%s)" % sim.save.genome.genome_id)
	_check(Lineage.starting_body_of(sim.save.genome, sim.catalog) == expect.body, "the body is the %s" % expect.body)
	_check(_parts_match(pool.cell_view.part_nodes(), expect.parts), "the PlayerCell has the saved parts at the saved angles")
	_check(sim.save.adaptation_points == int(expect.points), "the points are the same (%d)" % sim.save.adaptation_points)
	main.hud.refresh()
	_check(main.hud.points_text.text == Hud.points_line(int(expect.points)), "the HUD shows '%s'" % main.hud.points_text.text)
	var saved := Vector2(expect.position[0], expect.position[1])
	_check(sim.motion.position.distance_to(saved) <= POSITION_TOLERANCE_M,
		"the cell is where it was saved (%.6f m away)" % sim.motion.position.distance_to(saved))
	_check_cell_view(pool)
	_check(_shown(main.hud.message) and main.hud.message_text.text.begins_with("Your cell rested"),
		"the HUD says the cell rested: %s" % main.hud.message_text.text)
	await _check_running(pool, "the continued run plays", 60)
	_check_view_record("the continued run")
	await _press(&"pause")
	_check(_shown(main.pause_menu) and pool.paused, "the pause key reaches the continued run and opens the pause menu")
	_end()


## Part nodes (PlayerCell or CellPreview) match the expected [{type, angle}] in order.
func _parts_match(nodes: Array[Node], parts: Array) -> bool:
	if nodes.size() != parts.size() or parts.is_empty():
		return false
	for i in parts.size():
		var node := nodes[i]
		if str(node.get_meta("part_type", "")) != str(parts[i].type):
			return false
		if absf(float(node.get_meta("part_angle", INF)) - float(parts[i].angle)) > ANGLE_TOLERANCE:
			return false
	return true


# Helpers

func _open_main() -> void:
	main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(2)


## Refuses to play unless the session uses a slot under user://smoke/.
func _slot_is_safe() -> bool:
	var safe := main.session.slot.begins_with(SMOKE_DIR + "/")
	_check(safe, "the smoke plays on a slot under %s/ (%s)" % [SMOKE_DIR, main.session.slot])
	return safe


## Starts listening to a pool's events and clears what the last run recorded.
func _watch(pool: PoolScene) -> void:
	_events.clear()
	_meals.clear()
	_event_points = 0
	_hud_meal_mismatches.clear()
	_view = {"frames": 0, "rect": Vector2.ZERO, "worst_offset": 0.0, "behind": 0, "food_mismatch": 0,
		"plankton_drawn": 0, "carrion_drawn": 0, "food_misplaced": 0, "fade_late": 0,
		"hud_lag": 0, "hud_worst_lag": 0, "bar_worst": 0.0}
	pool.sim_event.connect(_on_sim_event)


## Runs after the HUD's own handler, so the HUD has already refreshed for this event.
func _on_sim_event(event: Dictionary) -> void:
	_events[event.type] = int(_events.get(event.type, 0)) + 1
	match event.type:
		"ate":
			_meals.append(event)
			_event_points += int(event.points)
			var sim := main.pool.sim
			if main.hud.energy_text.text != Hud.energy_line(sim.state) \
					or absf(_first_number(main.hud.energy_text.text) - sim.state.energy) > 0.5 + 1e-6:
				_hud_meal_mismatches.append("'%s' at %.2f" % [main.hud.energy_text.text, sim.state.energy])
		"earned":
			_event_points += int(event.points)


## Every frame of a run, after the views have drawn it.
func _probe_frame() -> void:
	if main == null or main.pool == null or main.pool.sim == null or _view.is_empty():
		return
	var pool := main.pool
	var sim := pool.sim
	_view.frames += 1
	var rect := pool.camera.get_viewport().get_visible_rect()
	_view.rect = rect.size
	var at := pool.cell_view.global_position
	if pool.camera.is_position_behind(at):
		_view.behind += 1
	var offset := ((pool.camera.unproject_position(at) - rect.position) / rect.size - Vector2(0.5, 0.5)).abs()
	_view.worst_offset = maxf(_view.worst_offset, maxf(offset.x, offset.y))
	_view.plankton_drawn = pool.plankton_view.shown_count()
	_view.carrion_drawn = pool.carrion_view.shown_count()
	if _view.plankton_drawn != sim.plankton.items.size() or _view.carrion_drawn != sim.carrion.items.size():
		_view.food_mismatch += 1
	if not _food_placed(pool.plankton_view, sim.plankton.items) or not _food_placed(pool.carrion_view, sim.carrion.items):
		_view.food_misplaced += 1
	# _view.frames starts a frame or more after the pool's fade-in starts.
	if _view.frames > ceili(PoolScene.FADE_IN_S / PoolSim.DT) + FADE_SLACK_FRAMES and _shown(pool.get_node("%Fade") as CanvasItem):
		_view.fade_late += 1
	var stale := not pool.paused and absf(_first_number(main.hud.energy_text.text) - sim.state.energy) > 1.0
	_view.hud_lag = _view.hud_lag + 1 if stale else 0
	_view.hud_worst_lag = maxi(_view.hud_worst_lag, _view.hud_lag)
	_view.bar_worst = maxf(_view.bar_worst, absf(main.hud.energy_bar.value - sim.state.energy))


## Every one of `items` sits at its sim position (x and z) in the view's instance buffer, which is
## what the renderer draws. MultiMesh.get_instance_transform() reads identity under --headless,
## but the buffer reads back as written.
func _food_placed(view: FoodView, items: Array[Dictionary]) -> bool:
	if items.is_empty():
		return true
	var buffer := view.multimesh.buffer
	for i in items.size():
		var want := PlaneSpace.to_world(items[i].position)
		var o: int = i * FoodView.FLOATS_PER_INSTANCE
		if o + 11 >= buffer.size() or absf(buffer[o + 3] - want.x) > POSITION_TOLERANCE_M \
				or absf(buffer[o + 11] - want.z) > POSITION_TOLERANCE_M:
			return false
	return true


## Waits for `done` or `max_ticks` sim ticks, whichever comes first. Returns the ticks waited.
func _ticks_until(sim: PoolSim, done: Callable, max_ticks: int) -> int:
	var from := sim.tick
	var frames := 0
	while not done.call() and sim.tick - from < max_ticks and frames < max_ticks * 2:
		await process_frame
		frames += 1
	return sim.tick - from


func _frames(count: int) -> void:
	for i in count:
		await process_frame


## The sim ticks run in `count` frames.
func _ticks_in(sim: PoolSim, count: int) -> int:
	var from := sim.tick
	await _frames(count)
	return sim.tick - from


## The pause menu is closed, the pool is not paused and every frame runs one sim tick.
func _check_running(pool: PoolScene, what: String, count: int = RUN_FRAMES) -> void:
	var ticks := await _ticks_in(pool.sim, count)
	_check(not main.pause_menu.is_open() and not pool.paused and ticks == count, "%s (%d ticks in %d frames)" % [what, ticks, count])


## Clicks `button` with the mouse at its centre, through the viewport's GUI input, as a player does.
## It must be on screen, enabled and able to take keyboard focus, and the click must reach it, so a
## control drawn over it fails the check. Returns whether the button was pressed; when the player
## could not press it, nothing is clicked.
func _click(button: BaseButton, what: String) -> bool:
	var at := button.get_global_rect().get_center() if button != null else Vector2.INF
	var why := ""
	if button == null:
		why = "missing"
	elif not _shown(button):
		why = "hidden"
	elif button.disabled:
		why = "disabled"
	elif button.focus_mode != Control.FOCUS_ALL:
		why = "takes no keyboard focus"
	elif button.mouse_filter != Control.MOUSE_FILTER_STOP or not root.get_visible_rect().has_point(at):
		why = "takes no clicks"
	var pressed := [false]
	if why.is_empty():
		var note := func(): pressed[0] = true
		button.pressed.connect(note)
		for down in [true, false]:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = down
			click.position = at
			click.global_position = at
			root.push_input(click, true)
		button.pressed.disconnect(note)
		why = "" if pressed[0] else "covered"
	_check(pressed[0], "a click presses %s%s" % [what, "" if why.is_empty() else " (%s)" % why])
	return pressed[0]


## On screen: visible up the tree (CanvasLayers included) and not faded out by its own or any
## ancestor's modulate.
func _shown(item: CanvasItem) -> bool:
	if item == null or not item.is_visible_in_tree() or item.self_modulate.a <= 0.01:
		return false
	var node: Node = item
	while node is CanvasItem:
		if (node as CanvasItem).modulate.a <= 0.01:
			return false
		node = node.get_parent()
	return true


## A key press and release of `action`, as the player's keyboard sends it.
func _press(action: StringName) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(1)
	var up := InputEventAction.new()
	up.action = action
	Input.parse_input_event(up)
	await _frames(2)


func _focus() -> Control:
	return root.gui_get_focus_owner()


func _first_number(text: String) -> float:
	var found := _numbers.search(text)
	return found.get_string().to_float() if found != null else NAN


func _clear_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_clear_dir(path.path_join(sub))
		dir.remove(sub)
	for file in dir.get_files():
		dir.remove(file)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])


func _begin(step: String) -> void:
	_step_name = step
	_step_msec = Time.get_ticks_msec()


func _end() -> void:
	print("TIME %s: %d ms" % [_step_name, Time.get_ticks_msec() - _step_msec])
