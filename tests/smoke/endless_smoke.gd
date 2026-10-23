extends SceneTree
## The endless sea's scene smoke (S1, docs/s1/s1-content.md section 8; G19, G13, G9, G10). It
## instantiates the real main scene, which reads --world, --slot and --seed (RunFlags), and drives
## main.start_new, main.continue_run and main.continue_after_death directly: the start screen is
## smoked by play_smoke.gd's found phase. Every dev call comes from the intent provider (Driver),
## keyed on sim.tick and never on frames: hidden from the AI at its first tick and the energy
## refilled every REFILL_TICKS. It prints one PASS or FAIL line per check and a TIME line per step,
## and exits 1 on any failure.
##
##   -- --phase=endless_out --world=endless --slot=user://smoke/endless.json --seed=4244
##       A new omnivore swims east (SwimBot) until it is OUT_TM from where the lineage began, at
##       most SWIM_CAP_TICKS, then on until its absolute x is off the float32 grid (at most
##       SETTLE_TICKS more), so a save that truncates to float32 always shows (G19). The swim
##       rebased, unloaded a chunk and entered a tile, with no awake overflow, no chunk wait and no
##       attack on the cell. It saves and writes user://smoke/endless_expect.json.
##   -- --phase=endless_continue --world=endless --slot=user://smoke/endless.json
##       A new process continues that slot: the cell is back at its absolute place within 1e-6 tm,
##       the same view set is loaded with the same anchors and first shells, under the same tile,
##       and the first step does not rebase. The column stands at the checkpoint, the arrow points
##       home and the overlay reads the distance. A meal ghost in flight keeps its place across a
##       dev rebase (the scene tree steps its tween, which the unit runner cannot). Then the cell
##       dies: the respawn message waits for the respawn the next step performs (a teleport home,
##       300 tm out), and then the column stands at home and the arrow hides.
##   -- --phase=fps --world=endless --seed=4245 --slot=... (--fps-out=FILE | --compare=FILE)
##       A new omnivore swims north-east; at sim tick FPS_TICK the provider records the sim's
##       state hash and the SHA-256 of its snapshot, and the pool pauses. --fps-out writes the
##       record; --compare fails unless both match the file (G13: the same sim at any frame rate).
##
## Saves stay under user://smoke/: the smoke stops before playing if --slot points anywhere else.

const MAIN_SCENE := "res://game/scenes/main.tscn"
const SWIM_BOT_PATH := "res://game/dev/swim_bot.gd"
const SMOKE_DIR := "user://smoke"
const EXPECT_PATH := "user://smoke/endless_expect.json"
const BODY := "omnivore"
const OUT_TM := 300.0
const SWIM_CAP_TICKS := 9000        ## the omnivore (2.72 tm/s) needs about 6,600 (build plan B-17)
const SETTLE_TICKS := 60            ## CT 17.14's float32 settle
const REFILL_TICKS := 1800
const HOME_AM := Vector2(0.0, 9.0)  ## the generation start (build plan 17.12)
const ORIGIN_AM := Vector2.ZERO     ## where the arrow points (build plan Q9)
const POSITION_TOLERANCE_TM := 1e-6
const COLUMN_TOLERANCE_M := 1e-4
const ARROW_YAW_TOLERANCE := deg_to_rad(1.0)
const OVERLAY_FRAMES := 4
const DEATH_FRAMES := 120
const RESPAWN_TICKS := 240
## The meal ghost (PlayerCellView.GHOST_S, 0.35 s) flies 1.1 tm toward the cell; the dev rebase
## comes this many frames into the flight, and no frame may move it more than GHOST_STEP_M against
## the cell (a ghost left behind by the rebase jumps by the rebase step, 32 tm).
const GHOST_FROM := Vector2(1.0, 0.5)
const GHOST_REBASE_FRAME := 8
const GHOST_FRAMES := 18
const GHOST_STEP_M := 0.5
const REBASE_BY := Vector2i(1, 0)
const FPS_TICK := 1200
const FPS_FRAMES := 6000            ## 1,200 ticks take 2,880 frames at 144 fps


## The intent provider: `bot` swims (null holds still), and the dev calls are keyed on sim.tick:
## hidden from the AI at its first tick, the energy refilled every REFILL_TICKS from then. At
## `record_tick` it calls `on_record` once, before that tick's step.
class Driver:
	var bot: RefCounted
	var first_tick := -1
	var record_tick := -1
	var on_record: Callable
	var _next_refill := 0

	func _init(p_bot: RefCounted = null) -> void:
		bot = p_bot

	func next_intent(sim: PoolSim) -> SimIntent:
		if first_tick < 0:
			first_tick = sim.tick
			sim.debug_set_hidden(true)
		var t := sim.tick - first_tick
		if t >= _next_refill:
			sim.debug_set_energy(sim.state.energy_capacity)
			_next_refill = (floori(float(t) / REFILL_TICKS) + 1) * REFILL_TICKS
		if sim.tick == record_tick and on_record.is_valid():
			on_record.call(sim)
			on_record = Callable()
		if bot == null or sim.dead:
			return SimIntent.new()
		return bot.next_intent(sim)


var main: Main
var _failures := 0
var _checks := 0
var _finished := false
var _step_name := ""
var _step_msec := 0
## Sim events of the current run, by type, and every one in order.
var _events := {}
var _log: Array[Dictionary] = []
## What the HUD said in the frame the respawn was routed: {"text", "grace_s", "teleport"}.
var _respawn_seen := {}
var _record := {}


func _initialize() -> void:
	var phase := ""
	var fps_out := ""
	var compare := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):
			phase = arg.trim_prefix("--phase=")
		elif arg.begins_with("--fps-out="):
			fps_out = arg.trim_prefix("--fps-out=")
		elif arg.begins_with("--compare="):
			compare = arg.trim_prefix("--compare=")
	print("Endless smoke, phase '%s', build %s" % [phase, BuildInfo.build_id()])
	match phase:
		"endless_out":
			await _endless_out()
		"endless_continue":
			await _endless_continue()
		"fps":
			await _fps(fps_out, compare)
		_:
			_check(false, "--phase is endless_out, endless_continue or fps (got '%s')" % phase)
	_finished = true
	_report()


## The game quit before the smoke finished: a quit with exit code 0 would hide that.
func _finalize() -> void:
	if _finished:
		return
	_finished = true
	print("FAIL the game quit before the smoke finished (step '%s')" % _step_name)
	quit(1)


func _report() -> void:
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


# endless_out

func _endless_out() -> void:
	_begin("swim out")
	var flags := RunFlags.current()
	_remove_slot(flags.slot)
	DirAccess.remove_absolute(EXPECT_PATH)
	await _open_main()
	if not _slot_is_safe():
		return
	main.intent_provider = Driver.new(load(SWIM_BOT_PATH).new(Vector2.RIGHT))
	var started := main.start_new(BODY)
	var pool := main.pool
	_check(started.ok and pool != null and pool.is_endless(), "a new %s lineage opens the endless sea (%s)" % [BODY, started])
	if pool == null or not pool.is_endless():
		return
	_watch(pool)
	var sim := pool.sim
	var w := sim.world
	var origin_before := Vector2(w.origin_x_am, w.origin_y_am)
	var ticks := await _ticks_until(sim, func() -> bool: return _from_home(sim) >= OUT_TM, SWIM_CAP_TICKS)
	_check(_from_home(sim) >= OUT_TM, "the cell swam %.1f tm east in %d ticks (cap %d)" % [_from_home(sim), ticks, SWIM_CAP_TICKS])
	var settle := await _ticks_until(sim, func() -> bool: return _off_float32_grid(sim.absolute_position_am()[0]), SETTLE_TICKS)
	_check(_off_float32_grid(sim.absolute_position_am()[0]),
		"then %d ticks more put x off the float32 grid (%.9f)" % [settle, sim.absolute_position_am()[0]])
	var origin_after := Vector2(w.origin_x_am, w.origin_y_am)
	_check(int(_events.get("rebased", 0)) >= 1 and origin_after != origin_before,
		"the world rebased %d times (origin %s to %s)" % [int(_events.get("rebased", 0)), origin_before, origin_after])
	_check(int(_events.get("chunk_unloaded", 0)) >= 1, "chunks unloaded behind the cell (%d)" % int(_events.get("chunk_unloaded", 0)))
	_check(int(_events.get("tile_entered", 0)) >= 1, "the cell entered new tiles (%d)" % int(_events.get("tile_entered", 0)))
	_check(int(w.counters.awake_overflow) == 0 and int(w.counters.chunk_waits) == 0,
		"no awake overflow and no chunk wait (%s)" % [w.counters])
	var attacks := _log.filter(func(e: Dictionary) -> bool:
		return (e.type == "hit" or e.type == "creature_tell" or e.type == "creature_noticed") and e.get("target") == CreatureField.PLAYER_ID)
	_check(attacks.is_empty() and not sim.dead, "nothing noticed, told at or hit the hidden cell (%d)" % attacks.size())
	_end()

	_begin("save")
	var saved := main.save_now()
	_check(saved.ok, "the run saves (%s)" % [saved])
	var expect := _expect_from(sim)
	var file := FileAccess.open(EXPECT_PATH, FileAccess.WRITE)
	_check(file != null, "wrote %s" % EXPECT_PATH)
	if file != null:
		file.store_string(JSON.stringify(expect, "\t", true, true))
		file.close()
	_end()


## What Continue must bring back: the absolute place right after the save, the origin, the tile,
## the view set and, from the generator (pure), each view-set chunk's anchors and first shell.
func _expect_from(sim: PoolSim) -> Dictionary:
	var w := sim.world
	var view_set := []
	var anchors := []
	var first_shells := []
	for key in w.view_set_keys(sim.motion.position):
		view_set.append([key.x, key.y])
		var chunk := w.gen.chunk(w.size, key.x, key.y)
		for a in chunk.anchors:
			anchors.append(str(a.id))
		if not chunk.shells.is_empty():
			first_shells.append(str(chunk.shells[0].id))
	anchors.sort()
	first_shells.sort()
	var tile := w.tile_of_local(sim.motion.position)
	return {
		"lineage_id": sim.save.lineage_id,
		"position_am": Array(sim.absolute_position_am()),
		"origin_am": [w.origin_x_am, w.origin_y_am],
		"tile": [tile.x, tile.y],
		"view_set": view_set,
		"anchors": anchors,
		"first_shells": first_shells,
		"checkpoint_am": Array(w.checkpoint_am),
	}


# endless_continue

func _endless_continue() -> void:
	_begin("continue")
	var expect: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECT_PATH))
	_check(expect is Dictionary, "endless_out left %s" % EXPECT_PATH)
	if not expect is Dictionary:
		return
	await _open_main()
	if not _slot_is_safe():
		return
	main.intent_provider = Driver.new()
	var result := main.continue_run()
	var pool := main.pool
	_check(result.ok and str(result.get("source", "")) == "primary" and pool != null and pool.is_endless(),
		"Continue opens the endless sea from the primary save (%s)" % [result])
	if pool == null or not pool.is_endless():
		return
	_watch(pool)
	var sim := pool.sim
	var w := sim.world
	_check(sim.save.lineage_id == expect.lineage_id, "the lineage is the same (%s)" % sim.save.lineage_id)
	var at := sim.absolute_position_am()
	var want: Array = expect.position_am
	_check(absf(at[0] - float(want[0])) <= POSITION_TOLERANCE_TM and absf(at[1] - float(want[1])) <= POSITION_TOLERANCE_TM,
		"the cell is back at its absolute place within 1e-6 tm (%.9f, %.9f; saved %.9f, %.9f)" % [at[0], at[1], want[0], want[1]])
	var view_set := []
	for key in w.view_set_keys(sim.motion.position):
		view_set.append([key.x, key.y])
	_check(view_set == _int_pairs(expect.view_set), "the view set is the same (%d chunks)" % view_set.size())
	var anchors := []
	var first_shells := []
	var missing := []
	for key in w.view_set_keys(sim.motion.position):
		var chunk := w.chunk(key)
		if chunk == null:
			missing.append(key)
			continue
		for a in chunk.anchors:
			anchors.append(str(a.id))
		if not chunk.shells.is_empty():
			first_shells.append(str(chunk.shells[0].id))
	anchors.sort()
	first_shells.sort()
	_check(missing.is_empty(), "every view-set chunk is loaded at once (missing %s)" % [missing])
	_check(anchors == expect.anchors and first_shells == expect.first_shells,
		"with the same anchors (%d) and first shells (%d)" % [anchors.size(), first_shells.size()])
	var tile := w.tile_of_local(sim.motion.position)
	_check([[tile.x, tile.y]] == _int_pairs([expect.tile]), "under the same tile %s" % tile)
	await _frames(2)
	_check(int(_events.get("rebased", 0)) == 0 and sim.tick >= 1, "the first step does not rebase (%d)" % int(_events.get("rebased", 0)))
	_end()

	_begin("markers")
	await _frames(OVERLAY_FRAMES)
	var cp := w.checkpoint_am
	var column := pool.markers.column()
	var column_at := PlaneSpace.to_world(w.local_of_abs(cp[0], cp[1]))
	_check(column != null and column.position.distance_to(column_at) <= COLUMN_TOLERANCE_M,
		"the column stands at the checkpoint (%s, %s)" % [column.position if column != null else null, column_at])
	var arrow := pool.markers.arrow()
	var home := WorldMarkers.origin_arrow(PackedFloat64Array(want), PackedFloat64Array([ORIGIN_AM.x, ORIGIN_AM.y]))
	var yaw := PlaneSpace.yaw_for_heading((home.direction as Vector2).angle())
	_check(arrow != null and arrow.visible and absf(angle_difference(arrow.rotation.y, yaw)) <= ARROW_YAW_TOLERANCE,
		"the arrow shows, pointing home (yaw %.4f, want %.4f)" % [arrow.rotation.y if arrow != null else NAN, yaw])
	var label: Dictionary = main.hud.world_overlay.label if main.hud.world_overlay != null else {}
	var words := Hud.WorldOverlay.ARROW_TEXT % WorldMarkers.distance_text(Vector2(float(want[0]), float(want[1])).length())
	_check(str(label.get("text", "")) == words, "the overlay reads '%s' (%s)" % [words, label.get("text", "")])
	_end()

	_begin("ghost across a rebase")
	await _check_ghost_across_rebase(pool)
	_end()

	_begin("die and respawn")
	_check(sim.debug_hurt_player(sim.state.max_health), "the cell is hurt to death")
	var frames := await _frames_until(func() -> bool: return main.death_notice.is_open(), DEATH_FRAMES)
	_check(main.death_notice.is_open(), "the death notice shows (%d frames)" % frames)
	main.continue_after_death()
	var text := str(main.hud.message_text.text)
	_check(not main.hud.message.visible or not text.begins_with("Back at the generation start"),
		"the HUD has no respawn message while the cell is still dead ('%s')" % text)
	var ticks := await _ticks_until(sim, func() -> bool: return not _respawn_seen.is_empty(), RESPAWN_TICKS)
	_check(not _respawn_seen.is_empty(), "the next step respawns the cell (%d ticks)" % ticks)
	if not _respawn_seen.is_empty():
		_check(_respawn_seen.text == Main.respawn_text(ceili(float(_respawn_seen.grace_s))),
			"in the frame it is routed the HUD says '%s'" % _respawn_seen.text)
		_check(bool(_respawn_seen.teleport), "and the world moved home (teleport: %s)" % _respawn_seen.teleport)
	await _frames(2)
	cp = w.checkpoint_am
	column_at = PlaneSpace.to_world(w.local_of_abs(cp[0], cp[1]))
	_check(Vector2(cp[0], cp[1]) == HOME_AM and column != null and column.position.distance_to(column_at) <= COLUMN_TOLERANCE_M
		and Vector2(column_at.x, column_at.z).length() < 1.0,
		"the column stands at home, by the cell (%s)" % [column.position if column != null else null])
	_check(arrow != null and not arrow.visible, "and the arrow hides within 40 tm of the origin")
	_end()


## A meal ghost in flight toward the still cell keeps its place against the cell across a dev
## rebase: WorldFx shifts it with everything else. The tween steps only in the tree.
func _check_ghost_across_rebase(pool: PoolScene) -> void:
	var sim := pool.sim
	var view := pool.cell_view
	var at := sim.motion.position
	var before := pool.world_fx.get_children()
	view._ghost(pool.plankton_view.food_mesh(), PlaneSpace.to_world(at + GHOST_FROM), PlaneSpace.to_world(at))
	var ghost: Node3D = null
	for child in pool.world_fx.get_children():
		if not before.has(child) and child is MeshInstance3D:
			ghost = child
	_check(ghost != null, "the ghost flies in WorldFx")
	if ghost == null:
		return
	var origin := Vector2(sim.world.origin_x_am, sim.world.origin_y_am)
	var last := ghost.global_position - view.global_position
	var worst := 0.0
	var seen := 0
	for frame in GHOST_FRAMES:
		if frame == GHOST_REBASE_FRAME:
			_check(sim.debug_rebase(REBASE_BY), "a dev rebase mid-flight")
		await process_frame
		if not is_instance_valid(ghost):
			break
		seen += 1
		var now := ghost.global_position - view.global_position
		worst = maxf(worst, now.distance_to(last))
		last = now
	_check(Vector2(sim.world.origin_x_am, sim.world.origin_y_am) != origin, "the origin moved")
	_check(seen > GHOST_REBASE_FRAME and worst <= GHOST_STEP_M,
		"the ghost kept its place against the cell across the rebase (%d frames, largest step %.3f m)" % [seen, worst])


# fps

func _fps(fps_out: String, compare: String) -> void:
	_begin("fps")
	var flags := RunFlags.current()
	_check(fps_out.is_empty() != compare.is_empty(), "the fps phase takes --fps-out or --compare")
	_remove_slot(flags.slot)
	if not fps_out.is_empty():
		DirAccess.remove_absolute(fps_out)
	await _open_main()
	if not _slot_is_safe():
		return
	var driver := Driver.new(load(SWIM_BOT_PATH).new(Vector2(1.0, -1.0).normalized()))
	driver.record_tick = FPS_TICK
	driver.on_record = _on_fps_record
	main.intent_provider = driver
	var started := main.start_new(BODY)
	var pool := main.pool
	_check(started.ok and pool != null and pool.is_endless(), "a new %s lineage opens the endless sea" % BODY)
	if pool == null or not pool.is_endless():
		return
	_watch(pool)
	var frames := await _frames_until(func() -> bool: return not _record.is_empty(), FPS_FRAMES)
	_check(not _record.is_empty(), "the sim reached tick %d in %d frames" % [FPS_TICK, frames])
	if _record.is_empty():
		return
	print("RECORD %s" % JSON.stringify(_record))
	if not fps_out.is_empty():
		var file := FileAccess.open(fps_out, FileAccess.WRITE)
		_check(file != null, "wrote %s" % fps_out)
		if file != null:
			file.store_string(JSON.stringify(_record, "\t", true, true))
			file.close()
	else:
		var other: Variant = JSON.parse_string(FileAccess.get_file_as_string(compare))
		_check(other is Dictionary, "read %s" % compare)
		if other is Dictionary:
			_check(int(other.get("tick", -1)) == FPS_TICK and str(other.get("hash", "")) == _record.hash
				and str(other.get("sha256", "")) == _record.sha256,
				"tick %d's state hash and snapshot are the same as at the other frame rate (%s, %s)" % [FPS_TICK, _record.hash, other.get("hash", "")])
	_end()


## At FPS_TICK, before that tick's step: the sim's state hash, its snapshot's SHA-256 and the world
## events so far. The pool pauses after this frame.
func _on_fps_record(sim: PoolSim) -> void:
	_record = {"tick": sim.tick, "hash": str(sim.state_hash()),
		"sha256": JSON.stringify(sim.snapshot(), "", true, true).sha256_text(),
		"rebases": int(_events.get("rebased", 0)), "chunk_loads": int(_events.get("chunk_loaded", 0))}
	main.pool.set_paused.call_deferred(true)


# helpers

func _open_main() -> void:
	main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(2)


## Refuses to play unless the session uses a slot under user://smoke/.
func _slot_is_safe() -> bool:
	var safe := main.session.slot.begins_with(SMOKE_DIR + "/")
	_check(safe, "the smoke plays on a slot under %s/ (%s)" % [SMOKE_DIR, main.session.slot])
	return safe


## Removes this phase's own slot files (never another phase's), when the slot is under SMOKE_DIR.
func _remove_slot(slot: String) -> void:
	if not slot.begins_with(SMOKE_DIR + "/"):
		return
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(slot + suffix):
			DirAccess.remove_absolute(slot + suffix)


## JSON's numbers back as int pairs: [[x, y], ...].
static func _int_pairs(pairs: Array) -> Array:
	var out := []
	for p: Array in pairs:
		out.append([int(p[0]), int(p[1])])
	return out


## Starts listening to a pool's events.
func _watch(pool: PoolScene) -> void:
	_events.clear()
	_log.clear()
	_respawn_seen = {}
	pool.sim_event.connect(_on_sim_event)


## Runs after the pool's own handlers (and so after main's respawn message) for each event.
func _on_sim_event(event: Dictionary) -> void:
	_events[event.type] = int(_events.get(event.type, 0)) + 1
	_log.append(event)
	if event.type == "respawned" and _respawn_seen.is_empty():
		_respawn_seen = {"text": str(main.hud.message_text.text), "grace_s": float(event.get("grace_s", 0.0)),
			"teleport": event.get("teleport", false)}


## The cell's absolute distance from the generation start, tm.
func _from_home(sim: PoolSim) -> float:
	var at := sim.absolute_position_am()
	return Vector2(at[0] - HOME_AM.x, at[1] - HOME_AM.y).length()


## Whether float64 `x` is not a float32 value (a float32 truncation would move it).
static func _off_float32_grid(x: float) -> bool:
	return Vector2(x, 0.0).x != x


## Waits for `done` or `max_ticks` sim ticks, whichever comes first. Returns the ticks waited.
func _ticks_until(sim: PoolSim, done: Callable, max_ticks: int) -> int:
	var from := sim.tick
	var frames := 0
	while not done.call() and sim.tick - from < max_ticks and frames < max_ticks * 4:
		await process_frame
		frames += 1
	return sim.tick - from


func _frames(count: int) -> void:
	for i in count:
		await process_frame


## Waits until `done` returns true, for at most `max_frames` frames. Returns the frames waited.
func _frames_until(done: Callable, max_frames: int) -> int:
	var frames := 0
	while not done.call() and frames < max_frames:
		await process_frame
		frames += 1
	return frames


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
