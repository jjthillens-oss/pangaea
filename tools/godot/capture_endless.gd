extends SceneTree
## Owner frames of the endless sea (S1): plays one new grazer lineage on seed 4242 in the real game
## (main scene, HUD and all), moves the cell through the sea with the dev teleport and saves the
## frames the S1 review looks at. The AI is frozen and the cell holds still, so every run shows the
## same moments. Saves go to user://capture_endless/, never the player's slot. Needs a real renderer
## (in the cloud: xvfb-run and gl_compatibility) and a fixed frame rate:
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --audio-driver Dummy \
##     --rendering-method gl_compatibility --rendering-driver opengl3 --resolution 1920x1080 \
##     --fixed-fps 60 --script res://tools/godot/capture_endless.gd -- --out=/abs/endless-s1
##
## Flags after --: --out=DIR (default user://capture_endless/out), --shots=a,b (only these, by name
## or by number prefix, in SHOTS order), --zoom=M (the camera distance; default the layout's).
## Prints one line per frame saved and a "notes" line: where each was staged, its tile and the
## region toasts showing.

const MAIN_SCENE := "res://game/scenes/main.tscn"
const SLOT := "user://capture_endless/slot.json"
const DEFAULT_OUT := "user://capture_endless/out"
const BODY := "grazer"
const SEED := 4242
const SIZE := Vector2i(1920, 1080)
const NORTH := -PI / 2.0
const SETTLE_FRAMES := 45        ## frames after a move: the view set loads, creatures fade in
## Every shot in the order it is staged (later ones build on earlier ones: the death notice is shot
## far out, the respawn after it). "at" is absolute tm (am at S1's size 1); "do" says what happens.
##   start      the new lineage's first moments at the spawn
##   move       a dev teleport to "at", facing "heading"
##   die        the cell is killed where it is; the death notice opens
##   respawn    Continue on the notice; played until the cell is back at the checkpoint
##   chunks     the debug panel's chunk gizmo on
const SHOTS: Array[Dictionary] = [
	{"name": "01_home_start_column_and_toast", "do": "start", "what": "A new lineage at the generation start: the light column beside the cell, the start tile's toast"},
	{"name": "01b_home_column_beside_the_cell", "do": "move", "at": Vector2(-4.0, 13.0), "heading": NORTH, "what": "A few metres from the spawn: the column stands beside the start, clear of the cell"},
	{"name": "02_region_toast_entering_tile_1_0", "do": "move", "at": Vector2(65.5, 20.0), "heading": 0.0, "what": "Into tile (1, 0) facing east: the region toast"},
	{"name": "03_landmark_great_shell", "do": "move", "at": Vector2(96.0, 64.0), "heading": NORTH, "what": "South of a great shell landmark"},
	{"name": "04_giant_husk_from_the_south", "do": "move", "at": Vector2(160.0, -26.1), "heading": NORTH, "what": "The giant husk side-on from the south, with its toast"},
	{"name": "05_shell_reef_knot", "do": "move", "at": Vector2(224.3, -40.8), "heading": NORTH, "what": "In a shell reef's knot of shells"},
	{"name": "06_shed_husk_landmark", "do": "move", "at": Vector2(-74.0, 146.0), "heading": NORTH, "what": "South of a shed husk landmark"},
	{"name": "07_arrow_home_and_column_pip_300m", "do": "move", "at": Vector2(300.0, 9.0), "heading": NORTH, "what": "300 m east: the arrow home with its distance, the column's pip at the screen edge"},
	{"name": "08_far_out_100km", "do": "move", "at": Vector2(100000.0, 9.0), "heading": NORTH, "what": "100 km east: the arrow reads 100 km and the sea goes on"},
	{"name": "09_far_death_notice", "do": "die", "what": "Killed 100 km out: the death notice"},
	{"name": "10_respawn_home_message", "do": "respawn", "what": "Continue: back at the generation start, sheltered, beside the column"},
	{"name": "11_chunk_gizmo_dev", "do": "chunks", "what": "The dev chunk gizmo at home (debug builds only)"},
]


## Swims nowhere: the cell holds still between moves.
class Still:
	extends RefCounted

	func next_intent(_sim: PoolSim) -> SimIntent:
		return SimIntent.new()


var main: Main
var out_dir := DEFAULT_OUT
var zoom := 0.0
var _toasts: Array[String] = []


func _initialize() -> void:
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--shots="):
			only = arg.trim_prefix("--shots=").split(",")
		elif arg.begins_with("--zoom="):
			zoom = float(arg.trim_prefix("--zoom="))
	if DisplayServer.get_name() == "headless":
		printerr("capture_endless needs a real renderer (xvfb-run, not --headless)")
		quit(2)
		return
	root.size = SIZE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	main.flags.world = "endless"
	for path in [SLOT, SLOT + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.open_session(SLOT)
	main.intent_provider = Still.new()
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
		var path := out_dir.path_join("%s.png" % shot.name)
		root.get_texture().get_image().save_png(path)
		var sim := main.pool.sim
		var at := sim.absolute_position_am()
		var tile := sim.world.tile_of_local(sim.motion.position) if sim.world != null else Vector2i.ZERO
		notes.append("%s at (%.1f, %.1f) tile %s toast %s" % [shot.name, at[0], at[1], tile, main.hud.toast_texts()])
		print("saved ", ProjectSettings.globalize_path(path))
	print("notes ", JSON.stringify(notes))
	quit(1 if failed > 0 else 0)


## Whether `name` is one of the --shots asked for (all when none were).
static func _wanted(name: String, only: PackedStringArray) -> bool:
	if only.is_empty():
		return true
	for o in only:
		if name == o or name.begins_with(o + "_"):
			return true
	return false


## Plays the shot's step and lets it settle. False when it could not be done.
func _stage(shot: Dictionary) -> bool:
	match str(shot.do):
		"start":
			var result := main.start_new(BODY, SEED)
			if not result.ok:
				return false
			main.pool.pause_on_focus_loss = false
			main.pool.sim.debug_set_ai_frozen(true)
			if zoom > 0.0:
				main.pool.camera.distance = clampf(zoom, main.pool.camera.zoom_min, main.pool.camera.zoom_max)
			await _play(SETTLE_FRAMES)
		"move":
			var at: Vector2 = shot.at
			if not main.pool.sim.debug_teleport_abs(at.x, at.y, float(shot.heading)):
				return false
			await _play(SETTLE_FRAMES)
		"die":
			var sim := main.pool.sim
			if not sim.debug_hurt_player(sim.state.max_health):
				return false
			await _play(SETTLE_FRAMES)
			return main.death_notice.is_open()
		"respawn":
			var heard := [false]
			main.pool.respawned.connect(func(_g: float, _t: bool) -> void: heard[0] = true, CONNECT_ONE_SHOT)
			main.continue_after_death()
			for i in 240:
				if heard[0]:
					break
				await process_frame
			await _play(20)
			return heard[0]
		"chunks":
			if main.debug_panel == null or not main.debug_panel.run("chunks"):
				return false
			await _play(5)
	return true


func _play(n: int) -> void:
	for i in n:
		await process_frame
