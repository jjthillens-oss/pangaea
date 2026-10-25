extends SceneTree
## Owner frames of the shore at the build's top size (4): plays one new lineage on seed 4248 in the
## real game (main scene, HUD and all), raises the shore the way a paid ring at the top does, then
## moves the cell around it with the dev teleport and saves the frames the shore review looks at.
## The AI is frozen, the cell is hidden from it and holds still, so every run shows the same moments.
## Saves and settings go to user://shore_shots/, never the player's. Needs a real renderer (in the
## cloud: xvfb-run and gl_compatibility) and a fixed frame rate:
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --audio-driver Dummy \
##     --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 1920x1080 \
##     --fixed-fps 60 --script res://tools/godot/shore_shots.gd -- --out=/abs/dir
##
## Flags after --: --out=DIR (default user://shore_shots/out), --shots=a,b (only these, by name or
## by number prefix; every shot is still staged in SHOTS order), --home (raise the shore where the
## lineage starts, by the cradle, instead of out in the open sea at OPEN_SEA_AM).
## Prints one line per frame saved, the on-screen readings (CIE L*, from look_probe.gd's helpers)
## and a "notes" line saying where each shot was staged. Exits 1 if a shot could not be staged.

const LookProbe := preload("res://tools/godot/look_probe.gd")

const MAIN_SCENE := "res://game/scenes/main.tscn"
const DIR := "user://shore_shots"
const SLOT := DIR + "/slot.json"
const SETTINGS := DIR + "/settings.cfg"
const DEFAULT_OUT := DIR + "/out"
const BODY := "grazer"
const SEED := 4248
const SIZE := Vector2i(1920, 1080)
const TOP_SIZE := 4
const NORTH := -PI / 2.0
## Where the shore rises unless --home: open sea, away from the cradle (absolute am at size 1).
const OPEN_SEA_AM := Vector2(600.0, 600.0)
const START_FRAMES := 20
const SIZE_FRAMES := 30            ## after debug_set_size: the world re-expresses, the camera dollies back
const RISE_CAP_FRAMES := 240       ## the ring pays out on the next tick; the shore shows a frame later
const SETTLE_FRAMES := 45          ## after a move: the view set loads, the camera eases onto the cell
const ZOOM_FRAMES := 120           ## after a zoom change: the camera eases to its new distance
const OFFER_CAP_FRAMES := 120
## The sand behind the cell: this far north of the cell (tm, on the plane) and this box (px).
const BEHIND_TM := 1.8
const BOX_PX := 60
## Each shot in staging order. "at" is the offset from the shore point in tm at the top size
## (x east, y south); "zoom" sets the camera distance first (0 keeps the layout's 14).
##   risen   the frame right after the shore rose (no move)
##   move    a teleport to the shore point + at, facing north
##   offer   a move, then wait for the "Crawl onto land?" notice over the paused pool
##   stay    answer the notice "Stay in the water", then a move
const SHOTS: Array[Dictionary] = [
	{"name": "01_risen", "do": "risen", "what": "Right after the rise: the toast and the warm arrow, the shore 20 tm off screen"},
	{"name": "02_approach", "do": "move", "at": Vector2(0.0, 10.0), "what": "10 tm south of the shore point, approaching"},
	{"name": "03_reach_edge", "do": "move", "at": Vector2(0.0, 4.6), "what": "Just outside the 4 tm reach: no offer yet"},
	{"name": "04_offer", "do": "offer", "at": Vector2(0.0, 3.0), "what": "Inside the reach: the offer over the paused pool"},
	{"name": "05_on_shelf", "do": "stay", "at": Vector2(0.0, 0.0), "what": "Stay in the water, then on the shore point itself"},
	{"name": "06_east", "do": "move", "at": Vector2(6.0, 0.0), "what": "6 tm east: the landing's flank side-on"},
	{"name": "07_zoom10", "do": "move", "at": Vector2(0.0, 4.6), "zoom": 10.0, "what": "The reach edge at the closest zoom"},
	{"name": "08_zoom20", "do": "move", "at": Vector2(0.0, 4.6), "zoom": 20.0, "what": "The reach edge at the farthest zoom"},
]


## Swims nowhere: the cell holds still, its energy kept full so a long run never starves it.
class Still:
	extends RefCounted

	func next_intent(sim: PoolSim) -> SimIntent:
		sim.debug_set_energy(sim.state.energy_capacity)
		return SimIntent.new()


var main: Main
var out_dir := DEFAULT_OUT
var home := false
var _shore_am := PackedFloat64Array()
var _k := 1.0


func _initialize() -> void:
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--shots="):
			only = arg.trim_prefix("--shots=").split(",")
		elif arg == "--home":
			home = true
	if DisplayServer.get_name() == "headless":
		printerr("shore_shots needs a real renderer (xvfb-run, not --headless)")
		quit(2)
		return
	root.size = SIZE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	# Own settings, deleted first and never the player's: the growth trigger stays automatic.
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	SettingsService.set_shared(SettingsService.new(SETTINGS))
	for base in [SLOT, EraTransition.checkpoint_path(SLOT)]:
		for suffix in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(base + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(base + suffix))
	main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	main.flags.world = "endless"
	main.open_session(SLOT)
	main.intent_provider = Still.new()
	if not await _raise_shore():
		printerr("shore_shots: the shore did not rise")
		quit(1)
		return
	var notes: Array[String] = []
	var failed := 0
	for shot: Dictionary in SHOTS:
		if not await _stage(shot):
			printerr("could not stage ", shot.name)
			failed += 1
			continue
		if not _wanted(shot.name, only):
			continue
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		var path := out_dir.path_join("%s.png" % shot.name)
		img.save_png(path)
		print("saved ", ProjectSettings.globalize_path(path))
		var readings := _readings(img)
		if shot.name == "05_on_shelf":
			readings.merge(await _behind_cell())
		print("readings %s %s" % [shot.name, JSON.stringify(readings)])
		var sim := main.pool.sim
		var at := sim.absolute_position_am()
		notes.append("%s at (%.1f, %.1f) am, %.2f tm from the shore, zoom %.1f, light pulse %.2f, notice %s, message '%s', toast %s" % [
			shot.name, at[0], at[1], ShoreLink.distance_am(sim.save, at) / _k, main.pool.camera.distance,
			main.pool.shore.light_strength(), main.shore_notice != null, main.hud.message_text.text, main.hud.toast_texts()])
	print("notes ", JSON.stringify(notes))
	quit(1 if failed > 0 else 0)


## A new lineage, (unless --home) moved out to open sea, grown to the top size with its ring filled,
## played until the shore rose and shows. True when it did.
func _raise_shore() -> bool:
	var result := main.start_new(BODY, SEED)
	if not result.ok:
		return false
	var pool := main.pool
	var sim := pool.sim
	pool.pause_on_focus_loss = false
	sim.debug_set_ai_frozen(true)
	sim.debug_set_hidden(true)
	await _play(START_FRAMES)
	if not home and not sim.debug_teleport_abs(OPEN_SEA_AM.x, OPEN_SEA_AM.y, NORTH):
		return false
	await _play(SETTLE_FRAMES)
	if not sim.debug_set_size(TOP_SIZE):
		return false
	await _play(SIZE_FRAMES)
	if not sim.debug_fill_meter(1.0):
		return false
	for i in RISE_CAP_FRAMES:
		if pool.shore.visible:
			break
		await process_frame
	_shore_am = ShoreLink.point_am(sim.save)
	_k = WorldConfig.tm_to_am(TOP_SIZE)
	print("shore at (%.1f, %.1f) am, size %d, home %s" % [
		_shore_am[0] if _shore_am.size() == 2 else NAN, _shore_am[1] if _shore_am.size() == 2 else NAN,
		sim.size(), home])
	return pool.shore.visible and _shore_am.size() == 2


## Plays the shot's step and lets it settle. False when it could not be done.
func _stage(shot: Dictionary) -> bool:
	var pool := main.pool
	match str(shot.do):
		"risen":
			await _play(5)
			return pool.shore.visible
		"move":
			if not _move(shot.at):
				return false
			var zoom := float(shot.get("zoom", 0.0))
			if zoom > 0.0:
				pool.camera.distance = clampf(zoom, pool.camera.zoom_min, pool.camera.zoom_max)
				await _play(ZOOM_FRAMES)
			await _play(SETTLE_FRAMES)
		"offer":
			if not _move(shot.at):
				return false
			for i in OFFER_CAP_FRAMES:
				if main.shore_notice != null:
					break
				await process_frame
			await _play(SETTLE_FRAMES)
			return main.shore_notice != null and main.shore_notice.is_open()
		"stay":
			if main.shore_notice == null:
				return false
			main.shore_notice.choose("stay")
			await _play(5)
			if main.shore_notice != null or pool.paused or not _move(shot.at):
				return false
			await _play(SETTLE_FRAMES)
			return main.shore_notice == null
	return pool.shore.visible


## Teleports the cell to the shore point + `at` tm (x east, y south), facing north.
func _move(at: Vector2) -> bool:
	return main.pool.sim.debug_teleport_abs(_shore_am[0] + at.x * _k, _shore_am[1] + at.y * _k, NORTH)


## L* of the cell's inner disc, of the box BEHIND_TM north of it, of the reach's west point on the
## plane (clear of the cell in every shot) and of the fluid at the bottom edge; each {"L", "C", "h",
## "hex", "max_channel", "at"} as look_probe reads them, or {"off_screen"}.
func _readings(img: Image) -> Dictionary:
	var pool := main.pool
	var cam: Camera3D = pool.camera
	var cell := pool.cell_view.global_position
	var r_px := _radius_px(cam, cell, pool.sim.phenotype.radius)
	var c := cam.unproject_position(cell)
	var shore := pool.shore.global_position
	var out := {
		"cell_inner": _box_reading(img, c, 0.55 * r_px, true),
		"north_of_cell": _box_reading(img, cam.unproject_position(cell + Vector3(0.0, 0.0, -BEHIND_TM)), BOX_PX * 0.5),
		"reach_west": _box_reading(img, cam.unproject_position(shore + Vector3(-ShoreLink.REACH_TM, 0.0, 0.0)), 20.0),
		"fluid_bottom": _box_reading(img, Vector2(SIZE.x * 0.5, SIZE.y - 60.0), BOX_PX * 0.5),
	}
	return out


## The sand behind the cell with the cell hidden for a frame: the same box as north_of_cell, and
## the box where the cell itself was.
func _behind_cell() -> Dictionary:
	var pool := main.pool
	var cam: Camera3D = pool.camera
	var cell := pool.cell_view.global_position
	var at := cam.unproject_position(cell)
	pool.cell_view.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	pool.cell_view.visible = true
	img.save_png(out_dir.path_join("05_on_shelf_cell_hidden.png"))
	return {
		"under_cell_hidden": _box_reading(img, at, BOX_PX * 0.5),
		"north_of_cell_hidden": _box_reading(img, cam.unproject_position(cell + Vector3(0.0, 0.0, -BEHIND_TM)), BOX_PX * 0.5),
	}


## A square box of half-size `half` px (or, with `disc`, the disc of that radius) around `at`.
static func _box_reading(img: Image, at: Vector2, half: float, disc := false) -> Dictionary:
	var h := maxi(1, roundi(half))
	var rect := Rect2i(Vector2i(roundi(at.x) - h, roundi(at.y) - h), Vector2i(2 * h, 2 * h))
	var m := LookProbe.median_of(img, rect, 1, at if disc else Vector2.INF, half if disc else 0.0)
	if int(m.count) == 0:
		return {"off_screen": true, "at": [roundi(at.x), roundi(at.y)]}
	var reading := LookProbe.reading(m.color)
	return {"L": reading.L, "C": reading.C, "h": reading.h, "hex": reading.hex,
		"max_channel": m.max_channel, "at": [roundi(at.x), roundi(at.y)]}


## The on-screen radius (px) of a sphere of radius `r` at `p`.
static func _radius_px(cam: Camera3D, p: Vector3, r: float) -> float:
	var right := cam.global_transform.basis.x.normalized()
	return cam.unproject_position(p).distance_to(cam.unproject_position(p + right * r))


## Whether `name` is one of the --shots asked for (all when none were).
static func _wanted(name: String, only: PackedStringArray) -> bool:
	if only.is_empty():
		return true
	for o in only:
		if name == o or name.begins_with(o + "_"):
			return true
	return false


func _play(n: int) -> void:
	for i in n:
		await process_frame
