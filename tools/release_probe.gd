extends SceneTree
## Release pack probe (M1 step 2). tools/check_release.sh runs it with --main-pack against the
## release pack, from an empty folder, so res:// is only what Pangaea.exe carries. It starts the
## main scene the way the exe does and checks that the start screen is up, that Main added no dev
## layer, that --perf-tour (passed by check_release.sh) is ignored, that the creature stage opens
## with its part tools (the compiled part rules must be in the pack), saves and enters the world, and that
## the pack holds nothing from game/dev or tests. It prints one PASS or FAIL line per check; exit
## code 0 when all pass. check_release.sh passes --slot so the stage's save (the lineage slot) stays
## under user://smoke/.
##
## It lives in tools/ (ignored by Godot), so it is never imported or exported, and reads Main
## only through get(), so it still reports if main.gd fails to parse.

const FRAMES := 30
const LEFT_OUT := ["res://game/dev", "res://tests"]

var _checks := 0
var _failures := 0
var _finished := false


func _initialize() -> void:
	print("Release pack probe")
	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	var scene: PackedScene = null
	if not main_scene.is_empty():
		scene = load(main_scene) as PackedScene
	_check(scene != null, "the main scene %s loads" % main_scene)
	if scene != null:
		var main := scene.instantiate()
		root.add_child(main)
		for i in FRAMES:
			await process_frame
		var screen: Object = main.get("screen")
		_check(screen != null and screen == main.get("start_screen"), "Main opens on the start screen (%s)" % screen)
		_check(main.get("dev_layer") == null and main.get("debug_panel") == null and main.find_child("DevLayer", true, false) == null,
			"Main added no dev layer or debug panel")
		_check(main.find_child("PerfTour", true, false) == null, "--perf-tour is ignored")
		await _probe_creature_stage(main)
		var script := main.get_script() as Script
		var constants := script.get_script_constant_map() if script != null else {}
		for constant: String in constants:
			var value: Variant = constants[constant]
			if value is String and (value as String).begins_with("res://game/dev/"):
				_check(not ResourceLoader.exists(value), "Main.%s (%s) is not in the pack" % [constant, value])
	for dir: String in LEFT_OUT:
		_check(not DirAccess.dir_exists_absolute(dir), "%s is not in the pack" % dir)
	_finished = true
	print("\nRelease probe: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


## The creature stage from the title: the editor with a tool per part record, a save that writes, and Done into
## the world with its rivals. Read through get()/call() like Main, so a missing method is a FAIL, not a crash.
func _probe_creature_stage(main: Node) -> void:
	if not main.has_method("open_creature_stage"):
		_check(false, "Main has open_creature_stage")
		return
	var stage: Node = main.call("open_creature_stage")
	for i in FRAMES:
		await process_frame
	_check(stage != null and main.get("screen") == stage, "the creature stage is the screen")
	if stage == null:
		return
	var editor: Node = stage.get("editor")
	var tools: Array = editor.get("tools") if editor != null else []
	_check(editor != null and not tools.is_empty(), "the editor has its part tools (%d: part_rules.json is in the pack)" % tools.size())
	_check(stage.call("save_now") == OK, "the stage saves (%s)" % error_string(stage.get("last_save")))
	if editor != null and editor.has_method("finish"):
		var done: Dictionary = editor.call("finish")
		for i in FRAMES:
			await process_frame
		var world: Node = stage.get("world")
		var sim: Object = world.get("sim") if world != null else null
		var rivals: Array = sim.get("rivals") if sim != null else []
		_check(bool(done["ok"]) and stage.call("mode") == "world" and sim != null and not rivals.is_empty(),
				"Done enters the world with its rivals (%s, %d rivals)" % [done.get("reason", ""), rivals.size()])
	if stage.has_method("back"):
		stage.call("back")
		for i in FRAMES:
			await process_frame
	_check(main.get("screen") == main.get("start_screen"), "the stage's Back returns to the start screen")


## Something quit before the probe finished (a quit with exit code 0 would hide it).
func _finalize() -> void:
	if not _finished:
		print("FAIL the game quit before the release probe finished")
		quit(1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])
