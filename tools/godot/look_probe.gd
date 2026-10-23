extends SceneTree
## Look probe (micro-world plan C1, sections 5 and 6; the plan is docs/micro-world-plan.md in the
## project files). Stages fixed scenes in the real pool, saves their frames, measures CIELAB colours
## at named points and checks a look's acceptance gates. It measures what the player sees, in
## either renderer, so the micro-world look can be judged against today's, and Forward+ against
## Compatibility. It is not part of the test suite: run it at C4, C5 and C9 and whenever the look
## changes. Saves go to user://look_probe/, never the player's slot.
##
## Run it windowed, at 1920x1080 and a fixed frame rate (it refuses to run without --fixed-fps),
## from the repository root. In the cloud that means Xvfb; docs/TOOLCHAIN.md has the lavapipe setup.
##
##   Compatibility (about 2 minutes on 4 CPUs):
##     xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --audio-driver Dummy \
##       --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 1920x1080 \
##       --fixed-fps 60 --script res://tools/godot/look_probe.gd -- --out=/abs/probe_compat --look=baseline
##
##   Forward+ on lavapipe (about 10 minutes; --parity compares it with a Compatibility run):
##     VK_ICD_FILENAMES=/tmp/lvp/lvp_icd.json xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . \
##       --audio-driver Dummy --rendering-method forward_plus --rendering-driver vulkan \
##       --resolution 1920x1080 --fixed-fps 60 --script res://tools/godot/look_probe.gd -- \
##       --out=/abs/probe_fwd --look=baseline --parity=/abs/probe_compat
##
## Flags after --:
##   --out=DIR          the frames and look_probe.json (default user://look_probe/out)
##   --look=NAME        the gate set: micro (plan section 6, the default) or baseline (today's look)
##   --scenes=a,b       only these scenes (default every one, in SCENES order)
##   --parity=DIR       another renderer's run of the same scenes: adds the parity readings and gates
##   --zoom=M           the camera distance (default the layout's, 14 m)
## Exit code: 0 when every gate passes, 1 when one fails or a scene could not be staged, 2 when the
## probe cannot run (headless, no --fixed-fps, or the output folder cannot be made).
##
## Scenes. Each starts a new grazer lineage on seed 4242 with the cell holding still, plays to its
## moment with drawing off, then pauses the pool, stops time and centres the camera on the cell, so
## every frame of a scene shows the same moment:
##   lineup     both threats, plankton, three carrion pieces and the cell in the centre zone, AI frozen
##   tell       the ambush hunter at lair_se about 0.8 s into its 1.2 s tell on the cell
##   puff       the rammer of terr_n_a 0.65 s into its puff before a charge at the cell
##   rim_north  the cell 4 m from the north rim, facing it, AI frozen
##   rim_south  the cell 5 m from the south rim, facing it, AI frozen
##   starving   the starving (grey) cell at the spawn, AI frozen
##   hud        the starving cell (banner and food arrow) with a rammer near and the hurt vignette
##              at its peak, AI frozen
##
## Frames, in --out: <scene>.png is what the player sees; <scene>_fluid.png is the same moment with
## every body, food item, rock, world label and the 2D layer hidden, so it shows what lies behind
## them. tell and puff add <scene>_nolane.png (the lane hidden), <scene>_decor.png and
## <scene>_decor_nolane.png (a pale decor stand-in under the lane, with and without it); hud adds
## <scene>_vignette.png (the 3D frame and the vignette alone) and <scene>_world.png (no 2D layer).
## <scene>_points.png outlines every sampled region in yellow.
##
## Readings, in look_probe.json under scenes.<scene>.readings: a point is the per-channel median of
## its sRGB pixels as {"hex", "L", "a", "b", "C", "h"} (CIE76, D65; h in degrees) plus "max_channel"
## (0 to 255). Every scene has cell (the inner 55% of the cell's disc), cell_behind (the fluid frame
## there), fluid_near_cell (the fluid frame's centre third), cell_dL (|L* of cell - L* of
## fluid_near_cell|), fluid_threat_hue_gap (degrees of LAB hue between fluid_near_cell and the threat
## colour), fluid_top, fluid_bottom, fluid_corner_tl/tr/bl/br, fluid_corners_min_L, glow_dL
## (fluid_near_cell L* minus the corners' mean: the depth glow), creatures (each on-screen body
## against the fluid behind it) and render_info. lineup adds plankton and carrion (each on-screen item
## clear of bodies and HUD panels; hue span, highest channel, hue gap from the threat colour); tell
## and puff add lane (the outline's largest |dL*| against the same pixels without the lane, across
## the lane's edge at 30, 50 and 70% of its length on both sides, skipping places a body covers;
## over the fluid and over the decor stand-in); rim_north adds skirt (L* down the north wall from
## 1 m to 30 m deep, and its largest step between neighbouring samples); hud adds vignette (the four
## corners with the vignette alone), vignette_behind and vignette_dE. With --parity every scene adds
## parity: the median CIE76 between the two runs over the whole frame, the fluid frame and the cell.

const MAIN_SCENE := "res://game/scenes/main.tscn"
const SLOT := "user://look_probe/slot.json"
const DEFAULT_OUT := "user://look_probe/out"
const BODY := "grazer"
const SEED := 4242
const SCENES: Array[String] = ["lineup", "tell", "puff", "rim_north", "rim_south", "starving", "hud"]
const SIZE := Vector2i(1920, 1080)       ## the gates' thresholds were measured at this size
const START_FRAMES := 30                 ## frames of a new run before staging (the fade-in is 0.3 s)
const FIRST_SETTLE := 2                  ## frames drawn before a moment's first capture...
const SETTLE := 1                        ## ...and before each later capture of it
const TELL_WAIT_FRAMES := 3600
const TELL_FRAMES := 50                  ## into the ambush tell when it is shot (of 72)
const PUFF_FRAMES := 40                  ## into the rammer's puff when it is shot (of 72)
const CARRION_SETTLE_FRAMES := 45        ## new carrion sinks and grows in over 0.6 s
const STARVE_FRAMES := 45                ## the cell's starving tint fades in over 0.4 s
const CELL_CORE := 0.55                  ## share of the cell's radius sampled (clear of its membrane)
const BODY_CORE := 0.5                   ## the same for a creature
const FOOD_CORE := 0.6                   ## the same for a food item's hue (its whole disc for clipping)
const COVER_MARGIN := 1.3                ## a body covers this many of its radii on screen
const MAX_FOOD_ITEMS := 12
const FOOD_HEX := "CFE86A"               ## docs/art/ART_DIRECTION.md: food-only glow...
const THREAT_HEX := "D9466B"             ## ...and threat-only pink
## The decor stand-in under a lane: the palest decor the ambience contract allows (luminance ×
## alpha = 0.12, plan section 7), a camera-facing plane at the top of the midground band, fogged.
const DECOR_COLOR := Color(0.85, 0.92, 1.0)
const DECOR_ALPHA := 0.147
const DECOR_Y := -3.0
const LANE_FRACTIONS: Array[float] = [0.3, 0.5, 0.7]
const LANE_SCAN_IN_M := 0.45             ## the outline scan runs from this far inside the lane's edge...
const LANE_SCAN_OUT_M := 0.2             ## ...to this far outside it...
const LANE_SCAN_STEPS := 24              ## ...in this many steps
const LANE_POINTS_NEEDED := 3            ## plan section 6: "dL* ≥ 15 at 3 points"
const RIM_WALL_M := 38.75                ## the rim's skirt radius (plan section 3)
const SKIRT_TOP_Y := -1.0
const SKIRT_BOTTOM_Y := -30.0
const SKIRT_STEP_M := 0.5
const SKIRT_BOX_PX := 5
const PARITY_STRIDE := 4
const BOX_COLOR := Color(1.0, 0.95, 0.0)

## The acceptance gates by look. A gate reads the number at `path` in the readings ("lineup.cell.h")
## and passes when it lies in [min, max] (either end may be left out); a reading that is missing
## fails. A "parity" gate runs only with --parity, and a gate on a scene that did not run is skipped.
##   micro: plan section 6 (PROPOSED), plus the depth glow check of plan section 10, risk 1, and
##   section 3's 90 degrees of LAB hue between the fluid and the threat pink, read on screen.
##   baseline: today's look (m1-threats at ecb1eee) in both renderers, with margins (docs/DECISIONS.md,
##   "Microscopic world look"), so the probe itself can be checked on today's build. Its "fluid" is
##   the teal floor. It has no skirt or plankton clipping gate: there is no skirt yet (those samples
##   land on the floor's caustics), and the plankton's sunlit tops reach 255 in both renderers.
const GATES := {
	"micro": [
		{"id": "cell_hue", "path": "lineup.cell.h", "min": 30.0, "max": 50.0, "what": "coral cell hue (LAB h)"},
		{"id": "cell_contrast", "path": "lineup.cell_dL", "min": 15.0, "what": "cell against the fluid, centre third (|dL*|)"},
		{"id": "fluid_value", "path": "lineup.fluid_near_cell.L", "min": 26.0, "max": 36.0, "what": "fluid near the cell (L*)"},
		{"id": "fluid_hue", "path": "lineup.fluid_near_cell.h", "min": 268.0, "max": 288.0, "what": "fluid near the cell (h)"},
		{"id": "fluid_chroma", "path": "lineup.fluid_near_cell.C", "min": 25.0, "what": "fluid near the cell (C*)"},
		{"id": "fluid_threat_gap", "path": "lineup.fluid_threat_hue_gap", "min": 90.0, "what": "fluid near the cell, LAB hue away from the threat colour (degrees)"},
		{"id": "fluid_corners", "path": "lineup.fluid_corners_min_L", "min": 15.0, "what": "darkest fluid corner (L*)"},
		{"id": "depth_glow", "path": "lineup.glow_dL", "min": 5.0, "what": "centre field lighter than the corners (dL*)"},
		{"id": "lane_fluid_tell", "path": "tell.lane.over_fluid_min_dL", "min": 15.0, "what": "ambush lane outline over the fluid (|dL*|, 3 points)"},
		{"id": "lane_decor_tell", "path": "tell.lane.over_decor_min_dL", "min": 15.0, "what": "ambush lane outline over pale decor (|dL*|, 3 points)"},
		{"id": "lane_fluid_puff", "path": "puff.lane.over_fluid_min_dL", "min": 15.0, "what": "rammer lane outline over the fluid (|dL*|, 3 points)"},
		{"id": "lane_decor_puff", "path": "puff.lane.over_decor_min_dL", "min": 15.0, "what": "rammer lane outline over pale decor (|dL*|, 3 points)"},
		{"id": "plankton_hue_low", "path": "lineup.plankton.h_min", "min": 110.0, "what": "plankton hue, lowest item (h)"},
		{"id": "plankton_hue_high", "path": "lineup.plankton.h_max", "max": 145.0, "what": "plankton hue, highest item (h)"},
		{"id": "plankton_clip", "path": "lineup.plankton.max_channel", "max": 254.0, "what": "plankton never clips (highest channel)"},
		{"id": "carrion_hue", "path": "lineup.carrion.threat_hue_gap", "min": 15.0, "what": "carrion hue away from the threat colour (degrees)"},
		{"id": "vignette_hue", "path": "hud.vignette.h", "min": 15.0, "max": 45.0, "what": "hurt vignette outer band (h)"},
		{"id": "starving_contrast", "path": "starving.cell_dL", "min": 10.0, "what": "starving cell against the fluid (|dL*|)"},
		{"id": "skirt_edge", "path": "rim_north.skirt.max_step_dL", "max": 6.0, "what": "no hard lower edge on the rim wall (largest dL* step)"},
		{"id": "parity_fluid", "path": "lineup.parity.fluid_dE", "max": 2.0, "parity": true, "what": "renderer parity, fluid (median CIE76)"},
		{"id": "parity_cell", "path": "lineup.parity.cell_dE", "max": 2.0, "parity": true, "what": "renderer parity, cell (median CIE76)"},
	],
	# Today's readings, Compatibility | Forward+ (docs/TOOLCHAIN.md): each range holds both.
	"baseline": [
		{"id": "cell_hue", "path": "lineup.cell.h", "min": 30.0, "max": 50.0, "what": "coral cell hue (LAB h; 42.1 | 41.3)"},
		{"id": "cell_contrast", "path": "lineup.cell_dL", "max": 8.0, "what": "cell against the floor, centre third: it reads by hue, not value (|dL*|; 2.4 | 3.6)"},
		{"id": "fluid_value", "path": "lineup.fluid_near_cell.L", "min": 36.0, "max": 54.0, "what": "teal floor near the cell (L*; 42.4 | 47.5)"},
		{"id": "fluid_hue", "path": "lineup.fluid_near_cell.h", "min": 198.0, "max": 220.0, "what": "teal floor near the cell (h; 206.3 | 212.8)"},
		{"id": "fluid_chroma", "path": "lineup.fluid_near_cell.C", "min": 16.0, "max": 31.0, "what": "teal floor near the cell (C*; 22.6 | 24.3)"},
		{"id": "fluid_corners", "path": "lineup.fluid_corners_min_L", "min": 40.0, "max": 62.0, "what": "darkest floor corner (L*; 48.4 | 55.2)"},
		{"id": "depth_glow", "path": "lineup.glow_dL", "min": -14.0, "max": -3.0, "what": "centre darker than the corners, where the floor deepens (dL*; -7.7 | -9.2)"},
		{"id": "lane_fluid_tell", "path": "tell.lane.over_fluid_min_dL", "min": 1.0, "max": 12.0, "what": "ambush lane outline over the floor (|dL*|, 3 points; 8.0 | 3.0)"},
		{"id": "lane_decor_tell", "path": "tell.lane.over_decor_min_dL", "min": 1.0, "max": 12.0, "what": "ambush lane outline; the decor stand-in lies under the floor (|dL*|; 8.0 | 3.0)"},
		{"id": "lane_fluid_puff", "path": "puff.lane.over_fluid_min_dL", "min": 1.0, "max": 12.0, "what": "rammer lane outline over the floor (|dL*|, 3 points; 6.4 | 2.8)"},
		{"id": "lane_decor_puff", "path": "puff.lane.over_decor_min_dL", "min": 1.0, "max": 12.0, "what": "rammer lane outline; the decor stand-in lies under the floor (|dL*|; 6.4 | 2.8)"},
		{"id": "plankton_hue_low", "path": "lineup.plankton.h_min", "min": 100.0, "max": 125.0, "what": "plankton hue, lowest item (h; 108.6 | 117.8)"},
		{"id": "plankton_hue_high", "path": "lineup.plankton.h_max", "min": 129.0, "max": 145.0, "what": "plankton hue, highest item (h; 138.2 | 136.6)"},
		{"id": "carrion_hue", "path": "lineup.carrion.threat_hue_gap", "min": 10.0, "max": 27.0, "what": "carrion hue away from the threat colour (degrees; 18.6 | 15.1)"},
		{"id": "vignette_hue", "path": "hud.vignette.h", "min": 243.0, "max": 270.0, "what": "hurt vignette outer band, blue-grey over teal (h; 261.2 | 254.2)"},
		{"id": "starving_contrast", "path": "starving.cell_dL", "max": 10.0, "what": "starving cell against the floor (|dL*|; 5.8 | 3.7)"},
		{"id": "parity_fluid", "path": "lineup.parity.fluid_dE", "max": 10.0, "parity": true, "what": "renderer parity, floor (median CIE76; 6.7)"},
		{"id": "parity_cell", "path": "lineup.parity.cell_dE", "max": 10.0, "parity": true, "what": "renderer parity, cell (median CIE76; 7.0)"},
	],
}

## Swims nowhere: the cell holds still while a scene plays to its moment.
class Still:
	extends RefCounted

	func next_intent(_sim: PoolSim) -> SimIntent:
		return SimIntent.new()

var main: Main
var pool: PoolScene
var sim: PoolSim
var out_dir := ""
var look := "micro"
var parity_dir := ""
var zoom := 0.0
## Every sim event of the current run, in order.
var events: Array[Dictionary] = []
## scene -> {"frames": {variant: file}, "readings": {...}, "error": text}
var results := {}
## Regions sampled in the current scene, outlined in <scene>_points.png.
var _boxes: Array[Rect2i] = []
var _decor: MeshInstance3D


func _initialize() -> void:
	RenderingServer.render_loop_enabled = false
	var scenes: Array[String] = SCENES.duplicate()
	out_dir = DEFAULT_OUT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--look="):
			look = arg.trim_prefix("--look=")
		elif arg.begins_with("--scenes="):
			scenes.assign(Array(arg.trim_prefix("--scenes=").split(",")))
		elif arg.begins_with("--parity="):
			parity_dir = arg.trim_prefix("--parity=")
		elif arg.begins_with("--zoom="):
			zoom = float(arg.trim_prefix("--zoom="))
	var problem := _setup_problem(scenes)
	if problem.is_empty():
		root.size = SIZE
		# --fixed-fps leaves no trace in the arguments a script sees; it shows as an exact frame step.
		for i in 2:
			await process_frame
		if not is_equal_approx(root.get_process_delta_time(), 1.0 / Engine.physics_ticks_per_second):
			problem = "pass --fixed-fps %d, so every run plays the same frames" % Engine.physics_ticks_per_second
		elif root.size != SIZE:
			push_warning("The window is %s, not %s, where the gates were measured." % [root.size, SIZE])
	if not problem.is_empty():
		printerr("Look probe cannot run: %s" % problem)
		quit(2)
		return
	print("Look probe: %s gates, %s (%s), scenes %s" % [look, RenderingServer.get_current_rendering_method(),
		RenderingServer.get_video_adapter_name(), ", ".join(scenes)])
	for scene in scenes:
		results[scene] = {"frames": {}, "readings": {}, "error": ""}
		await _fresh_run()
		if not await _stage(scene):
			results[scene].error = "could not stage the scene"
			printerr("Look probe: could not stage %s" % scene)
			continue
		await _freeze()
		await _shoot(scene)
		_thaw()
	var gates := evaluate(GATES[look], _readings(), not parity_dir.is_empty())
	var failed := 0
	for g: Dictionary in gates:
		print("%s %-18s %s = %s  (%s)" % [g.status.to_upper(), g.id, g.path, str(g.value), g.what])
		if g.status == "fail":
			failed += 1
	var staged_all := results.values().all(func(r: Dictionary) -> bool: return r.error.is_empty())
	_write_report(gates, failed)
	print("Look probe: %d gates, %d failed. Report: %s" % [gates.size(), failed, ProjectSettings.globalize_path(out_dir.path_join("look_probe.json"))])
	quit(0 if failed == 0 and staged_all else 1)


## Why the probe cannot run here, or "".
func _setup_problem(scenes: Array[String]) -> String:
	if DisplayServer.get_name() == "headless":
		return "it needs a real renderer (run it under xvfb-run, not --headless)"
	if not GATES.has(look):
		return "--look must be one of %s" % ", ".join(GATES.keys())
	for scene in scenes:
		if not SCENES.has(scene):
			return "there is no scene %s (scenes: %s)" % [scene, ", ".join(SCENES)]
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir)) != OK:
		return "cannot make %s" % out_dir
	return ""


# --- Runs and moments ----------------------------------------------------------------------------

## A new grazer lineage on SEED in a fresh pool, the cell holding still and unsheltered,
## START_FRAMES in.
func _fresh_run() -> void:
	if main == null:
		main = (load(MAIN_SCENE) as PackedScene).instantiate()
		root.add_child(main)
		await process_frame
		main.open_session(SLOT)
	for path in [SLOT, SLOT + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.intent_provider = Still.new()
	events.clear()
	_decor = null
	main.start_new(BODY, SEED)
	pool = main.pool
	sim = pool.sim
	pool.pause_on_focus_loss = false
	pool.sim_event.connect(func(e: Dictionary): events.append(e))
	# No shelter: its rim would tint the cell and its chip show in the HUD.
	sim.grace_until = sim.tick
	await _play(START_FRAMES)


## Plays `n` frames without drawing them.
func _play(n: int) -> void:
	for i in n:
		await process_frame


## Plays until `id` starts a tell on the cell (at most `limit` frames). Returns the event or {}.
func _play_to_tell(id: String, limit: int) -> Dictionary:
	for i in limit:
		for e in events:
			if e.type == "creature_tell" and e.get("id") == id and e.get("target") == CreatureField.PLAYER_ID:
				return e
		await process_frame
	return {}


## Stops the moment: the pool pauses (its views show the current tick), time stands still, and the
## camera centres on the cell at the probe's zoom.
func _freeze() -> void:
	pool.set_paused(true)
	Engine.time_scale = 0.0
	await _play(1)
	if zoom > 0.0:
		pool.camera.distance = clampf(zoom, pool.camera.zoom_min, pool.camera.zoom_max)
	pool.camera.snap_to(pool.cell_view.position)


func _thaw() -> void:
	Engine.time_scale = 1.0
	RenderingServer.render_loop_enabled = false


## Draws the moment as it is now and returns the frame; `frames` are drawn, the last one kept.
func _capture(frames := SETTLE) -> Image:
	RenderingServer.render_loop_enabled = true
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	RenderingServer.render_loop_enabled = false
	img.convert(Image.FORMAT_RGB8)
	return img


func _save(scene: String, variant: String, img: Image) -> void:
	var file := scene + ("" if variant.is_empty() else "_" + variant) + ".png"
	var err := img.save_png(out_dir.path_join(file))
	if err != OK:
		printerr("Look probe could not save %s: %s" % [file, error_string(err)])
	results[scene].frames[variant if not variant.is_empty() else "full"] = file


## Shows or hides what lies in front of the fluid: the cell, creatures, food, rocks, world labels
## and the 2D layer (HUD, target ring, starving arrow).
func _show_gameplay(on: bool) -> void:
	for node: Node3D in [pool.cell_view, pool.creature_layer, pool.plankton_view, pool.carrion_view, pool.rocks, pool.feedback]:
		node.visible = on
	pool.ui.visible = on


## The full frame and the fluid frame of the moment, saved, plus the readings every scene has.
func _shoot_common(scene: String) -> Array[Image]:
	_boxes.clear()
	var full := await _capture(FIRST_SETTLE)
	var info := _render_info()
	_show_gameplay(false)
	var fluid := await _capture()
	_show_gameplay(true)
	_save(scene, "", full)
	_save(scene, "fluid", fluid)
	var r: Dictionary = results[scene].readings
	r.render_info = info
	r.merge(_common_readings(full, fluid))
	r.creatures = _creature_readings(full, fluid)
	if not parity_dir.is_empty():
		r.parity = _parity_readings(scene, full, fluid)
	return [full, fluid]


# --- Scenes: staging ---------------------------------------------------------------------------

## Plays the scene to its moment. Returns false when it cannot.
func _stage(scene: String) -> bool:
	match scene:
		"lineup":
			return await _stage_lineup()
		"tell":
			return await _stage_tell()
		"puff":
			return await _stage_puff()
		"rim_north":
			return await _stage_rim(Vector2(3.0, -35.0), -PI / 2.0)
		"rim_south":
			return await _stage_rim(Vector2(-3.0, 34.5), PI / 2.0)
		"starving":
			return await _stage_starving()
		"hud":
			return await _stage_hud()
	return false


## Dev creatures, since the sim keeps every site's creature on its leash.
func _stage_lineup() -> bool:
	sim.debug_set_ai_frozen(true)
	var center := Vector2(0.0, 1.5)
	if not sim.debug_spawn_creature("ambush_hunter", center + Vector2(-4.2, -1.0), -PI / 2.0):
		return false
	if not sim.debug_spawn_creature("rammer", center + Vector2(4.4, -2.2), -PI / 2.0):
		return false
	for i in 3:
		var p := center + Vector2(0.5, 3.4) + Vector2.from_angle(TAU * i / 3.0 + 0.4) * 0.9
		if sim.arena.is_clear(p, sim.carrion.item_radius):
			sim.carrion.spawn(p, "debug")
	if not sim.debug_teleport(center, -PI / 2.0):
		return false
	await _play(_whole_frames(CARRION_SETTLE_FRAMES))
	return true


func _stage_tell() -> bool:
	var hunter := _creature_at("lair_se")
	if hunter == null:
		return false
	sim.grace_until = sim.tick
	hunter.brain.ignore_all_until = sim.tick
	var front: Vector2 = hunter.motion.position + Vector2.from_angle(hunter.motion.heading) * 2.75
	if not sim.debug_teleport(front, hunter.motion.heading):
		return false
	if (await _play_to_tell(hunter.id, TELL_WAIT_FRAMES)).is_empty():
		return false
	await _play(TELL_FRAMES)
	return true


func _stage_puff() -> bool:
	var rammer := _creature_at("terr_n_a")
	if rammer == null or not rammer.brain.territory_center.is_finite():
		return false
	sim.grace_until = sim.tick
	rammer.brain.ignore_all_until = sim.tick
	if not sim.debug_teleport(rammer.brain.territory_center + Vector2(1.0, 4.5), -1.9):
		return false
	if (await _play_to_tell(rammer.id, TELL_WAIT_FRAMES)).is_empty():
		return false
	await _play(PUFF_FRAMES)
	return true


## The cell near the rim at `at`, facing it.
func _stage_rim(at: Vector2, heading: float) -> bool:
	sim.debug_set_ai_frozen(true)
	if not sim.debug_teleport(at, heading):
		return false
	await _play(20)
	return true


func _stage_starving() -> bool:
	sim.debug_set_ai_frozen(true)
	if not sim.debug_teleport(sim.layout.spawn, -PI / 2.0) or not sim.debug_set_energy(0.0):
		return false
	await _play(STARVE_FRAMES)
	return sim.state.is_starving()


func _stage_hud() -> bool:
	sim.debug_set_ai_frozen(true)
	var spot := Vector2(-4.0, 16.0)
	if not sim.debug_teleport(spot, -PI / 2.0) or not sim.debug_set_energy(0.0):
		return false
	sim.debug_spawn_creature("rammer", spot + Vector2(3.0, 3.5), -2.2)
	await _play(_whole_frames(STARVE_FRAMES))
	return sim.state.is_starving()


## At least `frames`, and enough for a creature spawned now to finish fading in (the species
## data's fade_in_s; one frame is one sim tick at --fixed-fps 60), so it is drawn opaque and whole.
func _whole_frames(frames: int) -> int:
	return maxi(frames, sim.species.fade_in_ticks + 1)


# --- Scenes: frames and readings ----------------------------------------------------------------

## Captures the frozen moment's frames and takes its readings.
func _shoot(scene: String) -> void:
	match scene:
		"tell", "puff":
			await _shoot_lane(scene)
		"hud":
			await _shoot_hud(scene)
		_:
			var frames := await _shoot_common(scene)
			var r: Dictionary = results[scene].readings
			if scene == "lineup":
				var panels := _hud_panels()
				r.plankton = _food_readings(frames[0], sim.plankton.items, pool.plankton_view.food_mesh(), panels)
				r.carrion = _food_readings(frames[0], sim.carrion.items, pool.carrion_view.food_mesh(), panels)
			elif scene == "rim_north":
				r.skirt = _skirt_readings(frames[1])
			_write_points(scene, frames[0])


## The vignette at its peak (Hud.VIGNETTE_PEAK) in the full frame; then the 3D frame with a copy of
## the vignette alone and with no 2D layer, for its outer band (the four corners) and what lies behind.
func _shoot_hud(scene: String) -> void:
	var vignette: ColorRect = main.hud.get("hurt_vignette")
	if vignette == null or not vignette.material is ShaderMaterial:
		results[scene].error = "the HUD has no hurt vignette to measure"
		return
	(vignette.material as ShaderMaterial).set_shader_parameter(&"strength", Hud.VIGNETTE_PEAK)
	vignette.visible = true
	var frames := await _shoot_common(scene)
	var layer := CanvasLayer.new()
	layer.layer = pool.ui.layer
	var copy := vignette.duplicate() as ColorRect
	layer.add_child(copy)
	copy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pool.add_child(layer)
	pool.ui.visible = false
	var alone := await _capture()
	layer.visible = false
	layer.queue_free()
	var world := await _capture()
	pool.ui.visible = true
	_save(scene, "vignette", alone)
	_save(scene, "world", world)
	var r: Dictionary = results[scene].readings
	var on := _corners_median(alone)
	var off := _corners_median(world)
	r.vignette = on
	r.vignette_behind = off
	r.vignette_dE = snappedf(delta_e(_color_of(on), _color_of(off)), 0.1)
	_write_points(scene, frames[0])


## A tell scene: the frames with and without the lane, over the fluid and over the decor stand-in.
func _shoot_lane(scene: String) -> void:
	var tell := _last_tell()
	var view: CreatureView = pool.creature_layer.view_of(str(tell.get("id", "")))
	if view == null or not view.lane_visible():
		results[scene].error = "the telling creature shows no lane"
		return
	var frames := await _shoot_common(scene)
	var lane: Dictionary = tell.lane
	view.hide_lane()
	var bare := await _capture()
	view.show_lane(lane)
	_add_decor(lane)
	var decor := await _capture()
	view.hide_lane()
	var decor_bare := await _capture()
	view.show_lane(lane)
	_save(scene, "nolane", bare)
	_save(scene, "decor", decor)
	_save(scene, "decor_nolane", decor_bare)
	results[scene].readings.lane = _lane_readings(lane, frames[0], bare, decor, decor_bare)
	_write_points(scene, frames[0])


# --- Measuring -----------------------------------------------------------------------------------

## cell, cell_behind, fluid_near_cell, cell_dL, fluid_threat_hue_gap, the fluid bands and corners,
## and glow_dL.
func _common_readings(full: Image, fluid: Image) -> Dictionary:
	var w := full.get_width()
	var h := full.get_height()
	var at := _px(pool.cell_view.global_position)
	var core := CELL_CORE * _px_radius(pool.cell_view.global_position, sim.phenotype.radius)
	var out := {}
	out.cell = _disc_point(full, at, core)
	out.cell_behind = _disc_point(fluid, at, core)
	out.fluid_near_cell = _box_point(fluid, Rect2i(w / 3, h / 3, w / 3, h / 3), 2)
	out.cell_dL = _dl(out.cell, out.fluid_near_cell)
	out.fluid_threat_hue_gap = snappedf(hue_gap(out.fluid_near_cell.h, hue(lab(Color(THREAT_HEX)))), 0.1)
	out.fluid_top = _box_point(fluid, Rect2i(int(w * 0.3125), 0, int(w * 0.4167), int(h * 0.111)), 2)
	out.fluid_bottom = _box_point(fluid, Rect2i(int(w * 0.3125), int(h * 0.889), int(w * 0.4167), int(h * 0.111)), 2)
	var cw := int(w * 0.078)
	var ch := int(h * 0.111)
	var corner_l: Array[float] = []
	for corner: Array in [["tl", 0, 0], ["tr", w - cw, 0], ["bl", 0, h - ch], ["br", w - cw, h - ch]]:
		var p := _box_point(fluid, Rect2i(corner[1], corner[2], cw, ch), 2)
		out["fluid_corner_" + corner[0]] = p
		corner_l.append(p.L)
	var mean_l := 0.0
	for l in corner_l:
		mean_l += l / corner_l.size()
	out.fluid_corners_min_L = corner_l.min()
	out.glow_dL = snappedf(out.fluid_near_cell.L - mean_l, 0.1)
	return out


## Each creature on screen: its body's core against the fluid behind it.
func _creature_readings(full: Image, fluid: Image) -> Array:
	var out := []
	if sim.creatures == null:
		return out
	for c in sim.creatures.creatures:
		var view := pool.creature_layer.view_of(c.id)
		if view == null or not _on_screen(view.global_position, full):
			continue
		var at := _px(view.global_position)
		var core := BODY_CORE * _px_radius(view.global_position, view.radius)
		var body := _disc_point(full, at, core)
		var behind := _disc_point(fluid, at, core)
		body.merge({"id": c.id, "species": c.species_id, "dL": _dl(body, behind),
			"dE": snappedf(delta_e(_color_of(body), _color_of(behind)), 0.1)})
		out.append(body)
	return out


## Food items on screen and clear of bodies and HUD panels, nearest the screen centre first: each
## one's core, the hue span, the highest channel over their whole discs and the hue gap from the
## threat colour. {"items", "count", "h_min", "h_max", "max_channel", "threat_hue_gap"}.
func _food_readings(full: Image, items: Array[Dictionary], mesh: Mesh, panels: Array[Rect2]) -> Dictionary:
	var size := mesh.get_aabb().size if mesh != null else Vector3.ONE * 0.4
	var radius_m := maxf(size.x, size.z) * 0.5
	var centre := Vector2(full.get_size()) * 0.5
	var found := []
	for item in items:
		var w := PlaneSpace.to_world(item.position)
		if not _on_screen(w, full):
			continue
		var at := _px(w)
		var r := _px_radius(w, radius_m)
		if _covered(at, r) or panels.any(func(p: Rect2) -> bool: return p.grow(r).has_point(at)):
			continue
		found.append({"at": at, "r": r, "d": at.distance_to(centre)})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	var out := {"items": [], "count": 0}
	var hues: Array[float] = []
	var top := 0
	var threat_h := hue(lab(Color(THREAT_HEX)))
	var gap := 360.0
	for f: Dictionary in found.slice(0, MAX_FOOD_ITEMS):
		var p := _disc_point(full, f.at, FOOD_CORE * f.r)
		var whole := median_of(full, _disc_rect(f.at, f.r), 1, f.at, f.r)
		p.max_channel = whole.max_channel
		out.items.append(p)
		hues.append(p.h)
		top = maxi(top, whole.max_channel)
		gap = minf(gap, hue_gap(p.h, threat_h))
	out.count = hues.size()
	if hues.is_empty():
		return out
	out.h_min = hues.min()
	out.h_max = hues.max()
	out.max_channel = top
	out.threat_hue_gap = snappedf(gap, 0.1)
	return out


## The lane's outline against the same pixels without it, over the fluid and over the decor
## stand-in: at each LANE_FRACTIONS place on both sides, the largest |dL*| across the edge. Places
## a body covers are left out; with fewer than LANE_POINTS_NEEDED left the minimum is not given.
func _lane_readings(lane: Dictionary, on: Image, off: Image, decor_on: Image, decor_off: Image) -> Dictionary:
	var heading := float(lane.heading)
	var dir := Vector2.from_angle(heading)
	var across := dir.orthogonal()
	var half := float(lane.half_width)
	var out := {"half_width_m": half, "length_m": float(lane.length), "over_fluid": [], "over_decor": []}
	for f in LANE_FRACTIONS:
		var mid: Vector2 = Vector2(lane.origin) + dir * float(lane.length) * f
		for side in [-1.0, 1.0]:
			var scan := PackedVector2Array()
			var covered := false
			for k in LANE_SCAN_STEPS:
				var d := lerpf(half - LANE_SCAN_IN_M, half + LANE_SCAN_OUT_M, k / float(LANE_SCAN_STEPS - 1))
				var px := _px(PlaneSpace.to_world(mid + across * side * d, CreatureView.LANE_Y))
				covered = covered or _covered(px, 0.0) or not Rect2(Vector2.ZERO, Vector2(on.get_size())).has_point(px)
				scan.append(px)
			for pair: Array in [["over_fluid", on, off], ["over_decor", decor_on, decor_off]]:
				var best := {"at": f, "side": side, "covered": covered, "dL": 0.0, "dE": 0.0}
				if not covered:
					for px in scan:
						var a := _color_of(median_of(pair[1], _disc_rect(px, 1.0)))
						var b := _color_of(median_of(pair[2], _disc_rect(px, 1.0)))
						var dl := absf(lab(a).x - lab(b).x)
						if dl > best.dL:
							best.dL = snappedf(dl, 0.1)
							best.dE = snappedf(delta_e(a, b), 0.1)
							best.px = [roundi(px.x), roundi(px.y)]
					_boxes.append(Rect2i(Vector2i(scan[0]), Vector2i.ONE).expand(Vector2i(scan[scan.size() - 1])).grow(2))
				out[pair[0]].append(best)
	for key in ["over_fluid", "over_decor"]:
		var measured: Array = out[key].filter(func(p: Dictionary) -> bool: return not p.covered)
		out[key + "_points"] = measured.size()
		if measured.size() >= LANE_POINTS_NEEDED:
			out[key + "_min_dL"] = measured.map(func(p: Dictionary) -> float: return p.dL).min()
	return out


## L* down the north wall below the cell, from SKIRT_TOP_Y to SKIRT_BOTTOM_Y, in the fluid frame:
## a hard lower edge on the rim's skirt shows as a step between neighbouring samples.
func _skirt_readings(fluid: Image) -> Dictionary:
	var x := pool.cell_view.global_position.x
	var z := -sqrt(RIM_WALL_M * RIM_WALL_M - x * x)
	var profile := []
	var step := 0.0
	var last := NAN
	var y := SKIRT_TOP_Y
	while y >= SKIRT_BOTTOM_Y - 1e-6:
		var px := _px(Vector3(x, y, z))
		if Rect2(Vector2.ZERO, Vector2(fluid.get_size())).has_point(px):
			var l := lab(_color_of(median_of(fluid, _disc_rect(px, SKIRT_BOX_PX * 0.5)))).x
			profile.append({"y": y, "L": snappedf(l, 0.1)})
			if not is_nan(last):
				step = maxf(step, absf(l - last))
			last = l
			_boxes.append(_disc_rect(px, SKIRT_BOX_PX * 0.5))
		y -= SKIRT_STEP_M
	return {"profile": profile, "max_step_dL": snappedf(step, 0.1)}


## The median CIE76 between this run and the --parity run of the scene: over the whole frame, the
## fluid frame and the cell. Missing when the other run has no such frames or another size.
func _parity_readings(scene: String, full: Image, fluid: Image) -> Dictionary:
	var paths := [parity_dir.path_join(scene + ".png"), parity_dir.path_join(scene + "_fluid.png")]
	if not paths.all(func(p: String) -> bool: return FileAccess.file_exists(p)):
		return {"error": "no %s frames in %s" % [scene, parity_dir]}
	var other := Image.load_from_file(paths[0])
	var other_fluid := Image.load_from_file(paths[1])
	if other == null or other_fluid == null or other.get_size() != full.get_size():
		return {"error": "no %s frames of the same size in %s" % [scene, parity_dir]}
	other.convert(Image.FORMAT_RGB8)
	other_fluid.convert(Image.FORMAT_RGB8)
	var whole := Rect2i(Vector2i.ZERO, full.get_size())
	var at := _px(pool.cell_view.global_position)
	var core := CELL_CORE * _px_radius(pool.cell_view.global_position, sim.phenotype.radius)
	var out := {
		"frame_dE": median_delta_e(full, other, whole, PARITY_STRIDE),
		"fluid_dE": median_delta_e(fluid, other_fluid, whole, PARITY_STRIDE),
		"cell_dE": median_delta_e(full, other, _disc_rect(at, core), 1, at, core),
	}
	for key: String in out.keys():
		if is_nan(out[key]):
			out.erase(key)
	return out


## The four corner boxes of a frame as one point.
func _corners_median(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var cw := int(w * 0.078)
	var ch := int(h * 0.111)
	var pixels := Image.create(cw * 2, ch * 2, false, Image.FORMAT_RGB8)
	for corner: Array in [[0, 0, 0, 0], [w - cw, 0, cw, 0], [0, h - ch, 0, ch], [w - cw, h - ch, cw, ch]]:
		pixels.blit_rect(img, Rect2i(corner[0], corner[1], cw, ch), Vector2i(corner[2], corner[3]))
		_boxes.append(Rect2i(corner[0], corner[1], cw, ch))
	var m := median_of(pixels, Rect2i(Vector2i.ZERO, pixels.get_size()), 2)
	var p := reading(m.color)
	p.max_channel = m.max_channel
	return p


func _render_info() -> Dictionary:
	var out := {}
	for kind: Array in [["visible", Viewport.RENDER_INFO_TYPE_VISIBLE], ["shadow", Viewport.RENDER_INFO_TYPE_SHADOW]]:
		out[kind[0]] = {
			"objects": root.get_render_info(kind[1], Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
			"primitives": root.get_render_info(kind[1], Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
			"draw_calls": root.get_render_info(kind[1], Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		}
	return out


func _box_point(img: Image, rect: Rect2i, stride := 1) -> Dictionary:
	_boxes.append(rect)
	var m := median_of(img, rect, stride)
	var p := reading(m.color)
	p.max_channel = m.max_channel
	return p


func _disc_point(img: Image, at: Vector2, radius: float) -> Dictionary:
	var rect := _disc_rect(at, radius)
	_boxes.append(rect)
	var m := median_of(img, rect, 1, at, maxf(radius, 0.5))
	var p := reading(m.color)
	p.max_channel = m.max_channel
	return p


func _px(world: Vector3) -> Vector2:
	return pool.camera.unproject_position(world)


## A world radius at `world` in screen pixels.
func _px_radius(world: Vector3, radius: float) -> float:
	return _px(world + pool.camera.global_basis.x * radius).distance_to(_px(world))


func _on_screen(world: Vector3, img: Image) -> bool:
	return not pool.camera.is_position_behind(world) and Rect2(Vector2.ZERO, Vector2(img.get_size())).grow(-20.0).has_point(_px(world))


## Whether a body (the cell or a creature, COVER_MARGIN of its radius) covers a disc on screen.
func _covered(at: Vector2, radius: float) -> bool:
	var cell := pool.cell_view.global_position
	if at.distance_to(_px(cell)) < COVER_MARGIN * _px_radius(cell, sim.phenotype.radius) + radius:
		return true
	for view in pool.creature_layer.views():
		if at.distance_to(_px(view.global_position)) < COVER_MARGIN * _px_radius(view.global_position, view.radius) + radius:
			return true
	return false


## Screen rects of the HUD's panels that are showing.
func _hud_panels() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for node in main.hud.find_children("*", "PanelContainer", true, false):
		if (node as Control).is_visible_in_tree():
			out.append((node as Control).get_global_rect())
	return out


## The pale decor stand-in, camera-facing, on the view ray through the lane's middle at DECOR_Y.
func _add_decor(lane: Dictionary) -> void:
	var mid: Vector2 = Vector2(lane.origin) + Vector2.from_angle(float(lane.heading)) * float(lane.length) * 0.5
	var eye := pool.camera.global_position
	var ray := (PlaneSpace.to_world(mid, CreatureView.LANE_Y) - eye).normalized()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(DECOR_COLOR, DECOR_ALPHA)
	mat.render_priority = -5
	var quad := QuadMesh.new()
	var reach := (DECOR_Y - eye.y) / ray.y
	quad.size = Vector2.ONE * float(lane.length) * 2.5 * reach / eye.distance_to(PlaneSpace.to_world(mid))
	_decor = MeshInstance3D.new()
	_decor.name = "ProbeDecor"
	_decor.mesh = quad
	_decor.material_override = mat
	_decor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pool.add_child(_decor)
	_decor.global_position = eye + ray * reach
	_decor.global_basis = pool.camera.global_basis


func _creature_at(site_id: String) -> CreatureField.Creature:
	for c in sim.creatures.creatures:
		if c.site_id == site_id:
			return c
	return null


## The last tell on the cell this run, or {}.
func _last_tell() -> Dictionary:
	for i in range(events.size() - 1, -1, -1):
		if events[i].type == "creature_tell" and events[i].get("target") == CreatureField.PLAYER_ID:
			return events[i]
	return {}


func _write_points(scene: String, full: Image) -> void:
	var img := full.duplicate() as Image
	var bounds := Rect2i(Vector2i.ZERO, img.get_size())
	for box in _boxes:
		var b := box.grow(1).intersection(bounds)
		for edge in [Rect2i(b.position, Vector2i(b.size.x, 1)), Rect2i(b.position + Vector2i(0, b.size.y - 1), Vector2i(b.size.x, 1)),
				Rect2i(b.position, Vector2i(1, b.size.y)), Rect2i(b.position + Vector2i(b.size.x - 1, 0), Vector2i(1, b.size.y))]:
			img.fill_rect(edge, BOX_COLOR)
	_save(scene, "points", img)


## The readings of every scene that ran; one that could not be staged has none, so its gates fail.
func _readings() -> Dictionary:
	var out := {}
	for scene: String in results:
		out[scene] = results[scene].readings
	return out


func _write_report(gates: Array[Dictionary], failed: int) -> void:
	var window := root.size
	var report := {
		"probe": "tools/godot/look_probe.gd",
		"look": look,
		"build": BuildInfo.build_id(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"resolution": [window.x, window.y],
		"body": BODY,
		"seed": SEED,
		"zoom": pool.camera.distance if pool != null else zoom,
		"parity_with": parity_dir,
		"gates": gates,
		"failed": failed,
		"scenes": results,
	}
	var file := FileAccess.open(out_dir.path_join("look_probe.json"), FileAccess.WRITE)
	if file == null:
		printerr("Look probe could not write its report: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(report, "\t", false))
	file.close()


func _dl(a: Dictionary, b: Dictionary) -> float:
	return snappedf(absf(float(a.L) - float(b.L)), 0.1)


static func _color_of(p: Dictionary) -> Color:
	return p.color if p.has("color") else Color(str(p.hex))


static func _disc_rect(at: Vector2, radius: float) -> Rect2i:
	var r := ceili(radius)
	return Rect2i(Vector2i(roundi(at.x) - r, roundi(at.y) - r), Vector2i(2 * r + 1, 2 * r + 1))


# --- Colour and gates (pure; tests/test_look_probe.gd checks them) -------------------------------

## CIELAB (D65) of an sRGB colour: Vector3(L*, a*, b*).
static func lab(c: Color) -> Vector3:
	var r := _linear(c.r)
	var g := _linear(c.g)
	var b := _linear(c.b)
	var x := _lab_f((0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047)
	var y := _lab_f(0.2126 * r + 0.7152 * g + 0.0722 * b)
	var z := _lab_f((0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883)
	return Vector3(116.0 * y - 16.0, 500.0 * (x - y), 200.0 * (y - z))


## The LAB hue in degrees, 0 to 360.
static func hue(v: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(v.z, v.y)), 360.0)


## The smaller angle between two hues, 0 to 180.
static func hue_gap(a: float, b: float) -> float:
	var d := fposmod(a - b, 360.0)
	return minf(d, 360.0 - d)


## CIE76 colour difference.
static func delta_e(a: Color, b: Color) -> float:
	return lab(a).distance_to(lab(b))


## A colour as a point: {"hex", "L", "a", "b", "C", "h"}, to 0.1.
static func reading(c: Color) -> Dictionary:
	var v := lab(c)
	return {
		"hex": "#" + c.to_html(false).to_upper(),
		"L": snappedf(v.x, 0.1), "a": snappedf(v.y, 0.1), "b": snappedf(v.z, 0.1),
		"C": snappedf(Vector2(v.y, v.z).length(), 0.1), "h": snappedf(hue(v), 0.1),
	}


## The per-channel median of the pixels in `rect` (every `stride`th one), only those within
## `radius` of `center` when a radius is given, and the highest channel among them (0 to 255):
## {"color", "max_channel", "count"}. count is 0 when no pixel lies in the image.
static func median_of(img: Image, rect: Rect2i, stride := 1, center := Vector2.INF, radius := 0.0) -> Dictionary:
	var area := rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var r := PackedFloat32Array()
	var g := PackedFloat32Array()
	var b := PackedFloat32Array()
	var top := 0.0
	for y in range(area.position.y, area.end.y, stride):
		for x in range(area.position.x, area.end.x, stride):
			if radius > 0.0 and Vector2(x, y).distance_to(center) > radius:
				continue
			var c := img.get_pixel(x, y)
			r.append(c.r)
			g.append(c.g)
			b.append(c.b)
			top = maxf(top, maxf(c.r, maxf(c.g, c.b)))
	if r.is_empty():
		return {"color": Color(), "max_channel": 0, "count": 0}
	r.sort()
	g.sort()
	b.sort()
	var m := r.size() / 2
	return {"color": Color(r[m], g[m], b[m]), "max_channel": roundi(top * 255.0), "count": r.size()}


## The median CIE76 between two frames' pixels in `rect` (as median_of picks them), to 0.1; NAN
## when no pixel lies in the frames.
static func median_delta_e(a: Image, b: Image, rect: Rect2i, stride := 1, center := Vector2.INF, radius := 0.0) -> float:
	var area := rect.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	var d := PackedFloat32Array()
	for y in range(area.position.y, area.end.y, stride):
		for x in range(area.position.x, area.end.x, stride):
			if radius > 0.0 and Vector2(x, y).distance_to(center) > radius:
				continue
			d.append(delta_e(a.get_pixel(x, y), b.get_pixel(x, y)))
	if d.is_empty():
		return NAN
	d.sort()
	return snappedf(d[d.size() / 2], 0.1)


## The value at a dotted path in nested dictionaries ("lineup.cell.h"), or null.
static func value_at(readings: Dictionary, path: String) -> Variant:
	var node: Variant = readings
	for key in path.split("."):
		if not node is Dictionary or not (node as Dictionary).has(key):
			return null
		node = node[key]
	return node


## Each gate's result: the gate's fields plus "value" and "status" (pass, fail or skip). A gate
## whose scene did not run, or a parity gate without parity readings, is skipped.
static func evaluate(gates: Array, readings: Dictionary, with_parity: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for gate: Dictionary in gates:
		var result := gate.duplicate()
		var value: Variant = value_at(readings, gate.path)
		result.value = value
		if not readings.has(gate.path.get_slice(".", 0)) or (gate.get("parity", false) and not with_parity):
			result.status = "skip"
		elif not (value is float or value is int) or is_nan(float(value)):
			result.status = "fail"
		else:
			var v := float(value)
			var ok := v >= float(gate.get("min", -INF)) and v <= float(gate.get("max", INF))
			result.status = "pass" if ok else "fail"
		out.append(result)
	return out


static func _linear(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


static func _lab_f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
