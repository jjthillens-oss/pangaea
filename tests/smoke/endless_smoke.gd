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
##       and the first step does not rebase. The column stands beside the checkpoint, the arrow points
##       home and the overlay reads the distance. A meal ghost in flight keeps its place across a
##       dev rebase (the scene tree steps its tween, which the unit runner cannot). Then the cell
##       dies: the respawn message waits for the respawn the next step performs (a teleport home,
##       300 tm out), and then the column stands beside home and the arrow hides.
##   -- --phase=fps --world=endless --seed=4245 --slot=... (--fps-out=FILE | --compare=FILE)
##       A new omnivore swims north-east; at sim tick FPS_TICK the provider records the sim's
##       state hash and the SHA-256 of its snapshot, and the pool pauses. --fps-out writes the
##       record; --compare fails unless both match the file (G13: the same sim at any frame rate).
##   -- --phase=grow --world=endless --slot=user://smoke/grow.json --seed=4246
##       S2 (docs/s2/s2-view.md 12.1; S2G31): a new omnivore, still and hidden, has its ring filled
##       at tick GROW_FILL_TICK and grows by the automatic trigger within GROW_CAP_TICKS. Then
##       GROW_AFTER_FRAMES more frames: one growth_began and one grew, size 2, the badge and (in
##       the frame at the chord, beat second 1.9) the message read "Size 2 · about 32 µm", the
##       dolly has handed the camera back, the beat is over and left nothing in BeatFx, the plants
##       are algae balls and the slot on disk holds size 2 (the autosave on grew). It saves and
##       writes user://smoke/grow_expect.json.
##   -- --phase=grow_continue --world=endless --slot=user://smoke/grow.json
##       A new process continues that slot at size 2: the same absolute place within 1e-6 am, the
##       same checkpoint, algae balls, the badge, the same near ghosts, and the camera at rest.
##   -- --phase=band_up --world=endless --slot=user://smoke/band_up.json --seed=4247
##       S3 (docs/s3/s3-view.md 16.2; S3G43): a new omnivore, still and hidden, is put at size 2 at
##       tick BAND_UP_SIZE_TICK and filled and forced at BAND_UP_FORCE_TICK: one grew from band 0 to
##       band 1, size 3, the badge, band 1's pieces only, nothing left under Handoff, the old band
##       drawn in at most 8 calls, the beat over, glass flakes and no place found yet. The debug
##       panel's Go to cradle shows the cradle, its caption at full alpha, the cradle's toast once
##       in the run and the beacon's top at size 3. A second fill and force: size 4, bead clusters,
##       the engulfer preview and size 4's near ghosts. It saves and writes BAND_UP_EXPECT_PATH.
##   -- --phase=band_up_continue --world=endless --slot=user://smoke/band_up.json
##       A new process continues that slot at size 4: the same place within 1e-6 am, bead
##       clusters, the old band ready and drawn in at most 8 calls (with instances when the first
##       run had any), the cradle shown, the preview line and the places line as saved.
##   -- --phase=shore --world=endless --slot=user://smoke/shore.json --seed=4248
##       The cell-to-creature link (ShoreLink, EraTransition), on a slot and checkpoint removed
##       first: a new omnivore, still and hidden, is put at the top size at tick SHORE_SIZE_TICK
##       and its ring filled at SHORE_FILL_TICK. The ring pays out and the shore rises: in the save
##       and in the slot on disk, shown with its arrow, and the HUD says so. A dev teleport onto it
##       opens "Crawl onto land?" over the paused pool. "Stay in the water" plays on with no offer
##       while the cell stays in reach; out past the reopen distance and back, it opens again.
##       "Crawl ashore" with no fade opens the creature stage under the arrival banner; the slot is
##       ashore with the same lineage and points, came_ashore last in its history and the cell's
##       hue as its skin, and the checkpoint holds the cell and the shore. It writes
##       SHORE_EXPECT_PATH.
##   -- --phase=shore_continue --world=endless --slot=user://smoke/shore.json
##       A new process: the title offers Back to the water and Continue opens the creature stage on
##       that lineage. Back at the title, Back to the water opens the sea from the checkpoint: the
##       same lineage, points and shore, the shore shown, the HUD saying so, and the save ashore
##       kept as the slot's backup. The cell is in the shore's reach and no offer greets it; out
##       where the shore rose and back onto it, the offer opens.
##
## Every phase plays on its own settings (SETTINGS_PATH, deleted first and never saved) and the
## player memory beside the slot; the S1 phases set the growth trigger to press and never press, so
## the cell never grows there. Saves stay under user://smoke/: the smoke stops before playing if
## --slot points anywhere else.

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
# S2's growth (s2-view 12.1).
const SETTINGS_PATH := "user://smoke/grow_settings.cfg"
const MEMORY_PATH := "user://smoke/player_memory.cfg"
const GROW_EXPECT_PATH := "user://smoke/grow_expect.json"
const GROW_FILL_TICK := 60
const GROW_CAP_TICKS := 2400        ## the showcase window (20 s) and the calm window (1.5 s): about 1,350
const GROW_AFTER_FRAMES := 360      ## 6 s: the beat, the dolly and the glitter are over
const GROW_SETTLE_FRAMES := 30      ## at most this many more for the beat's last frame
const BADGE_SIZE_2 := "Size 2 · about 32 µm"
const SIZE_2_LOOK := "algae_ball"
const CAMERA_TOLERANCE := 1e-3
# S3's band-up (s3-view 16.2).
const BAND_UP_EXPECT_PATH := "user://smoke/band_up_expect.json"
const BAND_UP_SIZE_TICK := 30
const BAND_UP_FORCE_TICK := 120
const BAND_UP_CAP_TICKS := 600      ## the forced growth comes on the tick after the force
const BAND_UP_FRAMES := 360
const CRADLE_FRAMES := 120
const OLD_BAND_MAX_CALLS := 8
const BEACON_TOP_3 := -4.965        ## HomeBeacon.TOP_BU / 1.6^2
const BEACON_TOLERANCE := 0.01
const SIZE_3_LOOK := "glass_flake"
const SIZE_4_LOOK := "bead_cluster"
const PREVIEW_AT_4 := "Coming in a later build: the engulfer"
const NEAR_AT_4: Array = ["engulfer", "lancer"]
# The cell-to-creature link (ShoreLink, EraTransition).
const SHORE_EXPECT_PATH := "user://smoke/shore_expect.json"
const SHORE_TOP := 4                ## the build's top size, where a paid ring raises the shore
const SHORE_SIZE_TICK := 30
const SHORE_FILL_TICK := 60
const SHORE_CAP_TICKS := 600        ## the ring pays out on the fill tick; a teleport comes on the next
const SHORE_OFFER_FRAMES := 120
const SHORE_STAY_FRAMES := 60
const SHORE_SETTLE_FRAMES := 4


## The intent provider: `bot` swims (null holds still), and the dev calls are keyed on sim.tick:
## hidden from the AI at its first tick, the energy refilled every REFILL_TICKS from then, (S2)
## the ring filled `fill_tick` ticks after the first and (the shore) the cell teleported to
## `teleport_am` at `teleport_tick`. At `record_tick` it calls `on_record` once, before that
## tick's step.
class Driver:
	var bot: RefCounted
	var first_tick := -1
	var record_tick := -1
	var on_record: Callable
	var fill_tick := -1                 ## S2: the ring is filled this many ticks after the first
	var size_tick := -1                 ## S3: debug_set_size(size_to) this many ticks after the first
	var size_to := 0
	var force_tick := -1                ## S3: fill and force this many ticks after the first
	var teleport_tick := -1             ## the shore: debug_teleport_abs to teleport_am, likewise
	var teleport_am := PackedFloat64Array()
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
		if t == fill_tick:
			sim.debug_fill_meter(1.0)
		if t == size_tick:
			sim.debug_set_size(size_to)
		if t == force_tick:
			sim.debug_fill_meter(1.0)
			sim.debug_force_growth()
		if t == teleport_tick and teleport_am.size() == 2:
			sim.debug_teleport_abs(teleport_am[0], teleport_am[1])
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
	_use_own_settings(phase)
	match phase:
		"endless_out":
			await _endless_out()
		"endless_continue":
			await _endless_continue()
		"fps":
			await _fps(fps_out, compare)
		"grow":
			await _grow()
		"grow_continue":
			await _grow_continue()
		"band_up":
			await _band_up()
		"band_up_continue":
			await _band_up_continue()
		"shore":
			await _shore()
		"shore_continue":
			await _shore_continue()
		_:
			_check(false, ("--phase is endless_out, endless_continue, fps, grow, grow_continue, band_up, "
				+ "band_up_continue, shore or shore_continue (got '%s')") % phase)
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
	_check(sim.growth == null or (sim.growth.trigger == "press" and int(_events.get("growth_began", 0)) == 0),
		"in press mode with no press the cell never grew (S2)")
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
	var column_at := PlaneSpace.to_world(WorldMarkers.column_point(w.local_of_abs(cp[0], cp[1])))
	_check(column != null and column.position.distance_to(column_at) <= COLUMN_TOLERANCE_M,
		"the column stands beside the checkpoint (%s, %s)" % [column.position if column != null else null, column_at])
	var arrow := pool.markers.arrow()
	var home := WorldMarkers.origin_arrow(PackedFloat64Array(want), PackedFloat64Array([ORIGIN_AM.x, ORIGIN_AM.y]))
	var yaw := PlaneSpace.yaw_for_heading((home.direction as Vector2).angle())
	_check(arrow != null and arrow.visible and absf(angle_difference(arrow.rotation.y, yaw)) <= ARROW_YAW_TOLERANCE,
		"the arrow shows, pointing home (yaw %.4f, want %.4f)" % [arrow.rotation.y if arrow != null else NAN, yaw])
	var label: Dictionary = main.hud.world_overlay.label if main.hud.world_overlay != null else {}
	var words := Hud.WorldOverlay.ARROW_TEXT % WorldMarkers.distance_text(Vector2(float(want[0]), float(want[1])).length())
	_check(str(label.get("text", "")) == words, "the overlay reads '%s' (%s)" % [words, label.get("text", "")])
	var panels := main.hud.panel_rects()
	var pip: Dictionary = main.hud.world_overlay.pip if main.hud.world_overlay != null else {}
	_check(not panels.is_empty() and (not main.hud.controls.visible or main.hud.controls.get_global_rect() in panels),
		"the HUD lists the panels showing (%d)" % panels.size())
	_check(pip.is_empty() or Hud.WorldOverlay._clear(pip, panels), "the pip and its words keep off them (%s)" % [pip.get("at")])
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
	var home_at := w.local_of_abs(cp[0], cp[1])
	column_at = PlaneSpace.to_world(WorldMarkers.column_point(home_at))
	_check(Vector2(cp[0], cp[1]) == HOME_AM and column != null and column.position.distance_to(column_at) <= COLUMN_TOLERANCE_M
		and home_at.length() < 1.0,
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


# grow (S2)

func _grow() -> void:
	_begin("grow")
	var flags := RunFlags.current()
	_remove_slot(flags.slot)
	DirAccess.remove_absolute(GROW_EXPECT_PATH)
	await _open_main()
	if not _slot_is_safe():
		return
	var driver := Driver.new()
	driver.fill_tick = GROW_FILL_TICK
	main.intent_provider = driver
	var started := main.start_new(BODY)
	var pool := main.pool
	_check(started.ok and pool != null and pool.is_endless() and pool.growth() != null,
		"a new %s lineage opens the growing sea (%s)" % [BODY, started])
	if pool == null or pool.growth() == null:
		return
	_check(main.settings.growth_trigger() == "auto", "the trigger is automatic (%s)" % main.settings.growth_trigger())
	_check(main.player_memory_path() == MEMORY_PATH and main.hud.idea_hints.memory == main.player_memory,
		"the HUD's idea hints use main's player memory, beside the slot (%s)" % main.player_memory_path())
	_watch(pool)
	var sim := pool.sim
	var ticks := await _ticks_until(sim, func() -> bool: return int(_events.get("grew", 0)) >= 1, GROW_CAP_TICKS)
	_check(int(_events.get("grew", 0)) >= 1 and sim.growth.trigger == "auto",
		"the cell grew %d ticks in by the automatic trigger (cap %d)" % [ticks, GROW_CAP_TICKS])
	_end()

	_begin("after the growth")
	var chord := {}
	for frame in GROW_AFTER_FRAMES:
		await process_frame
		if chord.is_empty() and pool.growth_beat.t() >= GrowthBeat.CHORD_S:
			chord = {"t": pool.growth_beat.t(), "shown": main.hud.message.visible, "text": str(main.hud.message_text.text)}
	var extra := await _frames_until(func() -> bool: return not pool.growth_beat.running(), GROW_SETTLE_FRAMES)
	_check(int(_events.get("growth_began", 0)) == 1 and int(_events.get("grew", 0)) == 1,
		"one growth_began and one grew (%d, %d)" % [int(_events.get("growth_began", 0)), int(_events.get("grew", 0))])
	_check(sim.size() == 2, "the sea is at size 2 (%d)" % sim.size())
	_check(main.hud.size_badge.text == BADGE_SIZE_2, "the badge reads '%s' (%s)" % [BADGE_SIZE_2, main.hud.size_badge.text])
	_check(not chord.is_empty() and chord.shown and chord.text == BADGE_SIZE_2,
		"in the frame at the chord the message reads '%s' (%s)" % [BADGE_SIZE_2, chord])
	var camera := pool.camera
	_check(absf(camera._shown_distance - camera.distance) < CAMERA_TOLERANCE,
		"the dolly handed the camera back (%.4f, %.4f)" % [camera._shown_distance, camera.distance])
	_check(not pool.growth_beat.active() and not pool.growth_beat.running() and pool.growth_beat.fx.get_child_count() == 0,
		"the beat is over and left nothing in BeatFx (%d more frames)" % extra)
	_check(pool.plankton_view.look == SIZE_2_LOOK, "the plants are %s (%s)" % [SIZE_2_LOOK, pool.plankton_view.look])
	var on_disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(flags.slot))
	var saved_size := int((on_disk as Dictionary).get("growth", {}).get("size", 0)) if on_disk is Dictionary else 0
	_check(saved_size == 2, "the slot on disk holds size 2, saved at the growth (%d)" % saved_size)
	_end()

	_begin("save")
	var saved := main.save_now()
	_check(saved.ok, "the run saves (%s)" % [saved])
	var expect := {
		"lineage_id": sim.save.lineage_id,
		"position_am": Array(sim.absolute_position_am()),
		"checkpoint_am": Array(sim.world.checkpoint_am),
		"size": sim.size(),
		"look": pool.plankton_view.look,
		"near": Array(pool.ghosts.near_species(pool.ghosts.shown_size())),
	}
	var file := FileAccess.open(GROW_EXPECT_PATH, FileAccess.WRITE)
	_check(file != null, "wrote %s" % GROW_EXPECT_PATH)
	if file != null:
		file.store_string(JSON.stringify(expect, "\t", true, true))
		file.close()
	_end()


func _grow_continue() -> void:
	_begin("grow continue")
	var expect: Variant = JSON.parse_string(FileAccess.get_file_as_string(GROW_EXPECT_PATH))
	_check(expect is Dictionary, "grow left %s" % GROW_EXPECT_PATH)
	if not expect is Dictionary:
		return
	await _open_main()
	if not _slot_is_safe():
		return
	main.intent_provider = Driver.new()
	var result := main.continue_run()
	var pool := main.pool
	_check(result.ok and str(main.last_run.get("source", "")) == "primary" and pool != null and pool.is_endless(),
		"Continue opens the sea from the primary save (%s)" % [result])
	if pool == null or not pool.is_endless():
		return
	var sim := pool.sim
	_check(sim.save.lineage_id == expect.lineage_id, "the lineage is the same (%s)" % sim.save.lineage_id)
	_check(sim.size() == int(expect.size) and sim.size() == 2, "at size 2 (%d)" % sim.size())
	var at := sim.absolute_position_am()
	var want: Array = expect.position_am
	_check(absf(at[0] - float(want[0])) <= POSITION_TOLERANCE_TM and absf(at[1] - float(want[1])) <= POSITION_TOLERANCE_TM,
		"the cell is back at its absolute place within 1e-6 am (%.9f, %.9f; saved %.9f, %.9f)" % [at[0], at[1], want[0], want[1]])
	_check(Array(sim.world.checkpoint_am) == expect.checkpoint_am, "the checkpoint is the same (%s)" % [sim.world.checkpoint_am])
	await _frames(2)
	_check(pool.plankton_view.look == SIZE_2_LOOK and pool.plankton_view.look == str(expect.look),
		"the plants are %s (%s)" % [SIZE_2_LOOK, pool.plankton_view.look])
	_check(main.hud.size_badge.text == BADGE_SIZE_2, "the badge reads '%s' (%s)" % [BADGE_SIZE_2, main.hud.size_badge.text])
	var shown := pool.ghosts.shown_size()
	_check(shown == 2 and Array(pool.ghosts.near_species(shown)) == expect.near,
		"the near ghosts are size 2's, as saved (size %d: %s)" % [shown, pool.ghosts.near_species(shown)])
	_check(pool.camera._shown_distance == pool.camera.distance, "the camera is at rest (%.4f, %.4f)" % [pool.camera._shown_distance, pool.camera.distance])
	_end()


# band_up (S3)

func _band_up() -> void:
	_begin("band up")
	var flags := RunFlags.current()
	_remove_slot(flags.slot)
	DirAccess.remove_absolute(BAND_UP_EXPECT_PATH)
	await _open_main()
	if not _slot_is_safe():
		return
	var driver := Driver.new()
	driver.size_tick = BAND_UP_SIZE_TICK
	driver.size_to = 2
	driver.force_tick = BAND_UP_FORCE_TICK
	main.intent_provider = driver
	var started := main.start_new(BODY)
	var pool := main.pool
	_check(started.ok and pool != null and pool.is_endless() and pool.growth() != null and pool.sim.world.max_size == 4,
		"a new %s lineage opens the growing sea, top size 4 (%s)" % [BODY, started])
	if pool == null or pool.growth() == null:
		return
	_watch(pool)
	var sim := pool.sim
	var hud := main.hud
	# The cradle's toasts shown in the run: each rise in the count on screen is a new one.
	var cradle_toasts := {"shown": 0, "on_screen": 0}
	var count_toasts := func() -> void:
		var now := hud.toast_texts().count(Hud.CRADLE_TOAST)
		cradle_toasts.shown += maxi(now - int(cradle_toasts.on_screen), 0)
		cradle_toasts.on_screen = now
	var ticks := await _ticks_until(sim, func() -> bool:
		count_toasts.call()
		return int(_events.get("grew", 0)) >= 1, BAND_UP_CAP_TICKS)
	_check(int(_events.get("grew", 0)) >= 1, "the cell grew %d ticks in (cap %d)" % [ticks, BAND_UP_CAP_TICKS])
	for frame in BAND_UP_FRAMES:
		await process_frame
		count_toasts.call()
	var extra := await _frames_until(func() -> bool: return not pool.growth_beat.running(), GROW_SETTLE_FRAMES)
	var grew := _log.filter(func(e: Dictionary) -> bool: return e.type == "grew")
	var bands := grew.map(func(e: Dictionary) -> Array: return [e.get("band_from"), e.get("band_to")])
	_check(grew.size() == 1 and int(grew[0].get("band_from", -1)) == 0 and int(grew[0].get("band_to", -1)) == 1,
		"one grew, band 0 to band 1 (%s)" % [bands])
	_check(sim.size() == 3, "the sea is at size 3 (%d)" % sim.size())
	var labels: PackedStringArray = sim.world.content.config.ladder.labels
	var badge := "Size 3 · " + labels[2]
	_check(hud.size_badge.text == badge, "the badge reads '%s' (%s)" % [badge, hud.size_badge.text])
	var stray := pool.landmarks.pieces().filter(func(p: Node3D) -> bool:
		return not (str(p.name).begins_with("a_1_") or str(p.name).begins_with("p_1_")))
	_check(stray.is_empty(), "every landmark piece is band 1's (%d others: %s)" % [stray.size(), stray.map(func(p: Node3D) -> String: return str(p.name))])
	var handoff := pool.old_band.get_node_or_null("Handoff")
	_check(handoff != null and handoff.get_child_count() == 0, "nothing is left under Handoff (%d)" % (handoff.get_child_count() if handoff != null else -1))
	var calls := pool.old_band.draw_calls()
	_check(calls >= 0 and calls <= OLD_BAND_MAX_CALLS, "the old band draws in %d calls (at most %d)" % [calls, OLD_BAND_MAX_CALLS])
	_check(not pool.growth_beat.active(), "the beat is over (%d more frames)" % extra)
	_check(pool.plankton_view.look == SIZE_3_LOOK, "the plants are %s (%s)" % [SIZE_3_LOOK, pool.plankton_view.look])
	var places: Vector2i = sim.growth.places_found(3)
	_check(hud.places_line.visible and hud.places_line.text == GrowthHud.places_text(0, places.y) and places.y == 10,
		"the places line reads '%s' (%s)" % [GrowthHud.places_text(0, 10), hud.places_line.text])
	_end()

	_begin("go to cradle")
	_check(main.debug_panel != null and main.debug_panel.run("go_to_cradle"), "the debug panel's Go to cradle applies")
	for frame in CRADLE_FRAMES:
		await process_frame
		count_toasts.call()
	var cradle := pool.cradle
	_check(cradle != null and cradle.visible, "the cradle shows")
	if cradle != null:
		_check(cradle.caption().text == "Your lineage began here" and is_equal_approx(cradle.caption().modulate.a, 1.0),
			"its caption reads 'Your lineage began here' at full alpha (%s, %.2f)" % [cradle.caption().text, cradle.caption().modulate.a])
	_check(int(cradle_toasts.shown) == 1, "the cradle's toast showed once in the run (%d)" % int(cradle_toasts.shown))
	var top := _box_in(pool.beacon, pool).end.y
	_check(absf(top - BEACON_TOP_3) <= BEACON_TOLERANCE, "the beacon's top is at %.3f (%.3f)" % [BEACON_TOP_3, top])
	_end()

	_begin("size 4")
	driver.force_tick = sim.tick - driver.first_tick + 1
	var before := int(_events.get("grew", 0))
	ticks = await _ticks_until(sim, func() -> bool: return int(_events.get("grew", 0)) > before, BAND_UP_CAP_TICKS)
	await _frames(BAND_UP_FRAMES)
	await _frames_until(func() -> bool: return not pool.growth_beat.running(), GROW_SETTLE_FRAMES)
	_check(sim.size() == 4, "the sea is at size 4 (%d, %d ticks)" % [sim.size(), ticks])
	_check(pool.plankton_view.look == SIZE_4_LOOK, "the plants are %s (%s)" % [SIZE_4_LOOK, pool.plankton_view.look])
	_check(hud.ladder_strip.preview_text() == PREVIEW_AT_4, "the strip reads '%s' (%s)" % [PREVIEW_AT_4, hud.ladder_strip.preview_text()])
	_check(Array(pool.ghosts.near_species(4)) == NEAR_AT_4, "size 4's near ghosts are %s (%s)" % [NEAR_AT_4, pool.ghosts.near_species(4)])
	_end()

	_begin("save")
	var saved := main.save_now()
	_check(saved.ok, "the run saves (%s)" % [saved])
	var found := sim.growth.places_found(4)
	var expect := {
		"position_am": Array(sim.absolute_position_am()),
		"checkpoint_am": Array(sim.world.checkpoint_am),
		"size": sim.size(),
		"places": [found.x, found.y],
		"old_band_instances": pool.old_band.instances().size(),
	}
	var file := FileAccess.open(BAND_UP_EXPECT_PATH, FileAccess.WRITE)
	_check(file != null, "wrote %s" % BAND_UP_EXPECT_PATH)
	if file != null:
		file.store_string(JSON.stringify(expect, "\t", true, true))
		file.close()
	_end()


func _band_up_continue() -> void:
	_begin("band up continue")
	var expect: Variant = JSON.parse_string(FileAccess.get_file_as_string(BAND_UP_EXPECT_PATH))
	_check(expect is Dictionary, "band_up left %s" % BAND_UP_EXPECT_PATH)
	if not expect is Dictionary:
		return
	await _open_main()
	if not _slot_is_safe():
		return
	main.intent_provider = Driver.new()
	var result := main.continue_run()
	var pool := main.pool
	_check(result.ok and pool != null and pool.is_endless(), "Continue opens the sea (%s)" % [result])
	if pool == null or not pool.is_endless():
		return
	var sim := pool.sim
	_check(sim.size() == 4 and int(expect.size) == 4, "at size 4 (%d)" % sim.size())
	var at := sim.absolute_position_am()
	var want: Array = expect.position_am
	_check(absf(at[0] - float(want[0])) <= POSITION_TOLERANCE_TM and absf(at[1] - float(want[1])) <= POSITION_TOLERANCE_TM,
		"the cell is back at its absolute place within 1e-6 am (%.9f, %.9f; saved %.9f, %.9f)" % [at[0], at[1], want[0], want[1]])
	await _frames(CRADLE_FRAMES)
	_check(pool.plankton_view.look == SIZE_4_LOOK, "the plants are %s (%s)" % [SIZE_4_LOOK, pool.plankton_view.look])
	var calls := pool.old_band.draw_calls()
	_check(pool.old_band.ready_to_draw() and calls <= OLD_BAND_MAX_CALLS,
		"the old band is ready and draws in %d calls (at most %d)" % [calls, OLD_BAND_MAX_CALLS])
	if int(expect.old_band_instances) > 0:
		_check(not pool.old_band.instances().is_empty(), "the old band has instances, as the first run did (%d)" % int(expect.old_band_instances))
	_check(pool.cradle != null and pool.cradle.visible, "the cradle shows")
	_check(main.hud.ladder_strip.preview_text() == PREVIEW_AT_4, "the strip reads '%s' (%s)" % [PREVIEW_AT_4, main.hud.ladder_strip.preview_text()])
	var places: Array = expect.places
	var line := GrowthHud.places_text(int(places[0]), int(places[1]))
	_check(main.hud.places_line.text == line, "the places line reads '%s' (%s)" % [line, main.hud.places_line.text])
	_end()


# shore (the cell-to-creature link)

func _shore() -> void:
	_begin("shore rises")
	var flags := RunFlags.current()
	_remove_slot(flags.slot)
	_remove_slot(EraTransition.checkpoint_path(flags.slot))
	DirAccess.remove_absolute(SHORE_EXPECT_PATH)
	await _open_main()
	if not _slot_is_safe():
		return
	var driver := Driver.new()
	driver.size_tick = SHORE_SIZE_TICK
	driver.size_to = SHORE_TOP
	driver.fill_tick = SHORE_FILL_TICK
	main.intent_provider = driver
	var started := main.start_new(BODY)
	var pool := main.pool
	_check(started.ok and pool != null and pool.growth() != null and pool.shore != null
		and pool.sim.world.max_size == SHORE_TOP,
		"a new %s lineage opens the growing sea, top size %d (%s)" % [BODY, SHORE_TOP, started])
	if pool == null or pool.growth() == null or pool.shore == null:
		return
	_watch(pool)
	var sim := pool.sim
	var persistence := main.session.persistence
	var ticks := await _ticks_until(sim, func() -> bool: return int(_events.get("ring_paid", 0)) >= 1,
		SHORE_CAP_TICKS)
	_check(int(_events.get("ring_paid", 0)) == 1 and sim.size() == SHORE_TOP,
		"the ring paid out at size %d, %d ticks in (cap %d)" % [sim.size(), ticks, SHORE_CAP_TICKS])
	await _frames_until(func() -> bool: return pool.shore.visible, SHORE_SETTLE_FRAMES)
	var shore := ShoreLink.shore_of(sim.save)
	var shore_am := ShoreLink.point_am(sim.save)
	_check(not shore.is_empty() and int(shore.get("size", 0)) == SHORE_TOP,
		"the shore rose in the save at size %d (%s)" % [SHORE_TOP, shore])
	var on_disk := persistence.load_from(flags.slot)
	_check(on_disk.ok and _same_place(ShoreLink.point_am(on_disk.save), shore_am),
		"the slot on disk holds the shore, saved as it rose (%s)" % [on_disk.errors])
	_check(pool.shore.visible, "the shore shows")
	var text := str(main.hud.message_text.text)
	_check(text == Main.SHORE_RISEN_TEXT, "the HUD says '%s' (%s)" % [Main.SHORE_RISEN_TEXT, text])
	_check(pool.shore_arrow.visible, "the arrow points to it, %.1f tm away" % _shore_tm(sim))
	_end()

	_begin("the offer")
	var from_am := sim.absolute_position_am()
	_teleport(driver, sim, shore_am)
	var frames := await _frames_until(func() -> bool: return main.shore_notice != null, SHORE_OFFER_FRAMES)
	var notice := main.shore_notice
	_check(notice != null and notice.is_open() and notice.title_text() == Main.SHORE_TITLE,
		"teleported onto the shore, '%s' opens (%d frames)" % [Main.SHORE_TITLE, frames])
	if notice == null:
		return
	_check(pool.paused and not pool.shore_arrow.visible, "the pool is paused and the arrow hides")
	notice.choose("stay")
	await _frames(SHORE_SETTLE_FRAMES)
	var tick := sim.tick
	frames = await _frames_until(func() -> bool: return main.shore_notice != null, SHORE_STAY_FRAMES)
	_check(not pool.paused and sim.tick > tick, "Stay in the water: the pool runs (%d ticks)" % (sim.tick - tick))
	_check(main.shore_notice == null and ShoreLink.in_reach(_shore_am(sim), sim.size()),
		"no offer opens in %d frames while the cell stays in reach (%.2f tm)" % [frames, _shore_tm(sim)])
	_teleport(driver, sim, from_am)
	ticks = await _ticks_until(sim, func() -> bool: return ShoreLink.out_of_reach(_shore_am(sim), sim.size()),
		SHORE_CAP_TICKS)
	await _frames(SHORE_SETTLE_FRAMES)
	_check(ShoreLink.out_of_reach(_shore_am(sim), sim.size()) and main.shore_notice == null
		and pool.shore_arrow.visible,
		"teleported out past the reopen distance (%.1f tm, %d ticks): no offer, and the arrow shows"
		% [_shore_tm(sim), ticks])
	_teleport(driver, sim, shore_am)
	frames = await _frames_until(func() -> bool: return main.shore_notice != null, SHORE_OFFER_FRAMES)
	notice = main.shore_notice
	_check(notice != null and notice.is_open() and pool.paused,
		"and back onto the shore, the offer opens again (%d frames)" % frames)
	_end()
	if notice == null:
		return

	_begin("ashore")
	var lineage := sim.save.lineage_id
	var points := sim.save.adaptation_points
	main.crawl_time_scale = 0.0
	notice.choose("ashore")
	await _frames(SHORE_SETTLE_FRAMES)
	var stage := main.creature_stage
	_check(stage != null and main.screen == stage and main.pool == null,
		"Crawl ashore with no fade: the creature stage is the screen (%s)" % [main.screen])
	var arrival: Label = stage.get_node_or_null("Arrival/Text") as Label if stage != null else null
	_check(stage != null and stage.get_node_or_null("Arrival") is CanvasLayer and arrival != null
		and arrival.text == Main.ARRIVAL_TEXT,
		"its Arrival layer reads '%s' (%s)" % [Main.ARRIVAL_TEXT, arrival.text if arrival != null else null])
	var ashore := persistence.load_from(flags.slot)
	var land: SaveGame = ashore.save if ashore.ok else null
	_check(land != null and land.era == ShoreLink.TO_ERA and land.lineage_id == lineage,
		"the slot loads on land, the same lineage (%s, %s)" % [land.era if land != null else ashore.errors, lineage])
	if land != null:
		var last: Variant = land.lineage_history.back() if not land.lineage_history.is_empty() else {}
		_check(last is Dictionary and str(last.get("event", "")) == ShoreLink.EVENT,
			"%s is last in the lineage's history (%s)" % [ShoreLink.EVENT, last])
		var body: Dictionary = land.creature.get("body", {})
		var skin := "#" + CreatureRules.cell_skin(float(land.genome.appearance.get("hue", 0.0))).to_html(false)
		_check(str(body.get(CreatureRules.SKIN_COLOR_KEY, "")) == skin,
			"its first creature has the cell's hue as its skin (%s, %s)" % [body.get(CreatureRules.SKIN_COLOR_KEY), skin])
		_check(land.adaptation_points == points, "the same adaptation points as in the water (%d, %d)"
			% [land.adaptation_points, points])
	var before := persistence.load_from(EraTransition.checkpoint_path(flags.slot))
	var water: SaveGame = before.save if before.ok else null
	_check(water != null and water.era == ShoreLink.FROM_ERA and water.lineage_id == lineage
		and _same_place(ShoreLink.point_am(water), shore_am),
		"the checkpoint holds the cell in the water, the same lineage and the shore (%s)"
		% [water.era if water != null else before.errors])
	var expect := {"lineage_id": lineage, "points": points, "shore_am": Array(shore_am)}
	var file := FileAccess.open(SHORE_EXPECT_PATH, FileAccess.WRITE)
	_check(file != null, "wrote %s" % SHORE_EXPECT_PATH)
	if file != null:
		file.store_string(JSON.stringify(expect, "\t", true, true))
		file.close()
	_end()


func _shore_continue() -> void:
	_begin("shore continue")
	var expect: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHORE_EXPECT_PATH))
	_check(expect is Dictionary, "shore left %s" % SHORE_EXPECT_PATH)
	if not expect is Dictionary:
		return
	await _open_main()
	if not _slot_is_safe():
		return
	var flags := RunFlags.current()
	_check(main.start_screen != null and main.screen == main.start_screen and main.start_screen.water_button.visible,
		"the title offers '%s'" % StartScreen.WATER_TEXT)
	var result := main.continue_run()
	var stage := main.creature_stage
	_check(result.ok and stage != null and main.screen == stage and main.pool == null,
		"Continue opens the creature stage, not the sea (%s)" % [result])
	_check(stage != null and stage.save != null and stage.save.lineage_id == str(expect.lineage_id)
		and int(stage.state.get("points", -1)) == int(expect.points),
		"on the lineage that came ashore, with its points (%d)" % int(expect.points))
	await _frames(2)
	_end()

	_begin("back to the water")
	main.show_start()
	await _frames(2)
	_check(main.start_screen != null and main.start_screen.water_button.visible, "back at the title, it is offered still")
	var driver := Driver.new()
	main.intent_provider = driver
	var confirm := main.start_screen.confirm
	main.start_screen.water_button.pressed.emit()
	_check(confirm.is_open() and confirm.cancel_choice == "cancel" and confirm.choice_ids().has("water"),
		"'%s' asks first, and Esc stays on land (%s)" % [StartScreen.WATER_TEXT, confirm.choice_ids()])
	confirm.choose("cancel")
	await _frames(2)
	_check(main.screen == main.start_screen and main.pool == null, "Stay on land keeps the title")
	main.start_screen.water_button.pressed.emit()
	confirm.choose("water")
	await _frames(2)
	var pool := main.pool
	_check(pool != null and pool.is_endless(), "Back to the water opens the sea (%s)" % [main.last_run])
	if pool == null or not pool.is_endless():
		return
	var sim := pool.sim
	_check(sim.save.era == ShoreLink.FROM_ERA and sim.save.lineage_id == str(expect.lineage_id)
		and sim.save.adaptation_points == int(expect.points),
		"the save is in the water, the same lineage and points (%s, %d)" % [sim.save.era, sim.save.adaptation_points])
	_check(_same_place(ShoreLink.point_am(sim.save), PackedFloat64Array(expect.shore_am)),
		"the shore is still where it rose (%s)" % [ShoreLink.shore_of(sim.save)])
	await _frames(2)
	_check(pool.shore != null and pool.shore.visible, "the shore shows")
	var text := str(main.hud.message_text.text)
	_check(text == Main.WATER_BACK_TEXT, "the HUD says '%s' (%s)" % [Main.WATER_BACK_TEXT, text])
	var bak := main.session.persistence.load_from(flags.slot + PersistenceService.BACKUP_SUFFIX)
	var land: SaveGame = bak.save if bak.ok else null
	_check(land != null and land.era == ShoreLink.TO_ERA and land.lineage_id == str(expect.lineage_id),
		"the slot's backup is the save on land (%s)" % [land.era if land != null else bak.errors])
	_end()

	_begin("at the shore")
	# The checkpoint holds the cell at the shore: no offer greets it until it has swum out and back.
	var frames := await _frames_until(func() -> bool: return main.shore_notice != null, SHORE_STAY_FRAMES)
	_check(main.shore_notice == null and not pool.paused and ShoreLink.in_reach(_shore_am(sim), sim.size()),
		"the cell is in the shore's reach (%.2f tm) and no offer greets it in %d frames" % [_shore_tm(sim), frames])
	_teleport(driver, sim, _below_shore(sim, ShoreLink.RISE_AHEAD_TM))
	var ticks := await _ticks_until(sim, func() -> bool: return ShoreLink.out_of_reach(_shore_am(sim), sim.size()),
		SHORE_CAP_TICKS)
	await _frames(SHORE_SETTLE_FRAMES)
	_teleport(driver, sim, ShoreLink.point_am(sim.save))
	frames = await _frames_until(func() -> bool: return main.shore_notice != null, SHORE_OFFER_FRAMES)
	_check(main.shore_notice != null and pool.paused,
		"out where the shore rose (%d ticks) and back onto it, the offer opens (%d frames)" % [ticks, frames])
	_end()


## The place `tm` tm (at the cell's size) back from the shore's centre the way it rose: where the cell was when it
## rose RISE_AHEAD_TM ahead.
static func _below_shore(sim: PoolSim, tm: float) -> PackedFloat64Array:
	var p := ShoreLink.point_am(sim.save)
	var am := tm * WorldConfig.tm_to_am(sim.size())
	return PackedFloat64Array([p[0] - ShoreLink.RISE_DIRECTION.x * am, p[1] - ShoreLink.RISE_DIRECTION.y * am])


## Has the driver teleport the cell to `am` (absolute) on the next tick.
static func _teleport(driver: Driver, sim: PoolSim, am: PackedFloat64Array) -> void:
	driver.teleport_am = am
	driver.teleport_tick = sim.tick - driver.first_tick + 1


## The cell's distance to the shore's centre in am, and in tm at its size.
static func _shore_am(sim: PoolSim) -> float:
	return ShoreLink.distance_am(sim.save, sim.absolute_position_am())


static func _shore_tm(sim: PoolSim) -> float:
	return _shore_am(sim) / WorldConfig.tm_to_am(sim.size())


## Whether two absolute places (am) are the same within POSITION_TOLERANCE_TM.
static func _same_place(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	return a.size() == 2 and b.size() == 2 and absf(a[0] - b[0]) <= POSITION_TOLERANCE_TM \
		and absf(a[1] - b[1]) <= POSITION_TOLERANCE_TM


# helpers

## A node's box in the pool's frame (its own transform up to the pool times its meshes' box).
static func _box_in(node: Node3D, pool: Node) -> AABB:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != pool and n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t * CradleView.aabb_under(node)


## Every phase plays on SETTINGS_PATH, deleted first and never saved; the S1 phases set the growth
## trigger to press and never press, so they play as S1 did. The growth, band-up and shore phases
## keep the automatic trigger.
func _use_own_settings(phase: String) -> void:
	DirAccess.make_dir_recursive_absolute(SMOKE_DIR)
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	var settings := SettingsService.new(SETTINGS_PATH)
	SettingsService.set_shared(settings)
	if not phase.begins_with("grow") and not phase.begins_with("band_up") and not phase.begins_with("shore"):
		settings.set_value("gameplay/growth_trigger", "press")


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
