extends SceneTree
## Release pack content probe (S1, build plan B-19). tools/check_release.sh runs it with
## --main-pack against the release pack, from an empty folder, so res:// is only what Pangaea.exe
## carries. It checks that the pack holds the endless sea's content: the band-0 tile folder lists
## exactly its TILE_COUNT tile files, the home block and the placement kit are there, the content
## loads with no problems, and every kit piece's GLB loads and instances. One PASS or FAIL line per
## check; exit code 0 when all pass.
##
## It lives in tools/ (ignored by Godot), so it is never imported or exported.

const TILE_COUNT := 20

var _checks := 0
var _failures := 0
var _finished := false


func _initialize() -> void:
	print("Release pack content probe")
	var config := WorldConfig.load_from(WorldConfig.DEFAULT_PATH)
	_check(config.load_problems.is_empty(), "the world file %s loads (%s)" % [WorldConfig.DEFAULT_PATH, config.load_problems])
	var paths: Dictionary = config.content
	var tiles_dir := str((paths.get("tiles", {}) as Dictionary).get("0", ""))
	var files := DirAccess.get_files_at(tiles_dir) if not tiles_dir.is_empty() else PackedStringArray()
	var json := Array(files).filter(func(f: String) -> bool: return f.get_extension() == "json")
	_check(files.size() == TILE_COUNT and json.size() == TILE_COUNT,
		"%s lists exactly the %d tile files (%d files, %d json)" % [tiles_dir, TILE_COUNT, files.size(), json.size()])
	for key: String in ["home", "kit"]:
		var path := str(paths.get(key, ""))
		_check(not path.is_empty() and FileAccess.file_exists(path), "the %s file %s is in the pack" % [key, path])
	var species := SpeciesCatalog.load_from()
	var content := WorldContent.load_from(WorldConfig.DEFAULT_PATH, PoolLayout.load_from(), species)
	var problems := content.problems(PartCatalog.load_from(), species)
	_check(problems.is_empty(), "the endless content loads with no problems (%s)" % "; ".join(problems))
	var broken := PackedStringArray()
	for id: String in content.kit.assets:
		var a: Dictionary = content.kit.assets[id]
		var path := str(a.get("glb", "res://assets/export/%s.glb" % id))
		var scene := load(path) as PackedScene
		var piece := scene.instantiate() if scene != null else null
		if piece == null:
			broken.append("%s (%s)" % [id, path])
		else:
			piece.free()
	_check(not content.kit.assets.is_empty() and broken.is_empty(),
		"every kit piece's GLB loads (%d pieces; broken: %s)" % [content.kit.assets.size(), broken])
	_finished = true
	print("\nRelease content probe: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


## Something quit before the probe finished (a quit with exit code 0 would hide it).
func _finalize() -> void:
	if not _finished:
		print("FAIL the game quit before the release content probe finished")
		quit(1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])
