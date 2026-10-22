extends TestCase
## Build plumbing (M1 step 2). The game launches into main.tscn and the M0 check scene still runs
## by path; there are no autoloads (they would also run under the test and smoke scripts); every
## action is bound by physical key, so the layout is the same on any keyboard; and the dev tools
## (debug panel, dev keys, forage bot) reach only the dev exe: the release export leaves game/dev
## out, nothing the release build runs refers to game/dev except Main's guarded loaders, nothing
## preloads a dev file, and no dev script (in game/dev or a subfolder) has a class_name. These
## checks read the text; tools/check_release.sh, run by check.sh and by CI after the export, starts
## the release pack itself.

const MAIN_SCENE := "res://game/scenes/main.tscn"
const BOOT_SCENE := "res://game/scenes/boot.tscn"
const PRESETS_PATH := "res://export_presets.cfg"
const EXPORT_SCRIPT := "res://tools/export_windows.sh"
const RELEASE_PRESET := "Windows Desktop"
const DEV_PRESET := "Windows Desktop Dev"
const DEV_DIR := "res://game/dev"
const GAME_DIR := "res://game"
## The one file outside game/dev that may name it: Main loads the dev layer by path in debug builds.
const DEV_LOADER := "res://game/scenes/main.gd"
## Main's functions that may use its dev paths, each with the guard its first line must hold.
const DEV_LOADER_GUARDS := {
	"_add_dev_layer": "if not OS.is_debug_build()",
	"_start_perf_tour": "if dev_layer == null",
}
const SCAN_EXTENSIONS := ["gd", "tscn", "tres", "json", "cfg"]
## Where a file in game/dev carries its uid, by extension.
const UID_PATTERNS := {
	"uid": "^(uid://[0-9a-z]+)",
	"tscn": "^\\[gd_scene[^\\]]*uid=\"(uid://[0-9a-z]+)\"",
	"tres": "^\\[gd_resource[^\\]]*uid=\"(uid://[0-9a-z]+)\"",
	"import": "(?m)^uid=\"(uid://[0-9a-z]+)\"",
}
const CHECK_SCRIPT := "res://tools/check.sh"
const CI_WORKFLOW := "res://.github/workflows/ci.yml"
const RELEASE_CHECK := "tools/check_release.sh"
## Default bindings (plan section 11), by physical key.
const KEY_ACTIONS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"pause": [KEY_ESCAPE, KEY_P],
	"toggle_fullscreen": [KEY_F11],
	"toggle_debug": [KEY_F3],
	"dev_fill": [KEY_F5],
	"dev_drain": [KEY_F6],
	"dev_empty_zone": [KEY_F7],
	"dev_spawn_carrion": [KEY_F8],
	"dev_spawn_threat": [KEY_F9],
	"dev_kill_nearest": [KEY_F10],
}
const MOUSE_ACTIONS := {
	"swim_to_cursor": MOUSE_BUTTON_LEFT,
	"zoom_in": MOUSE_BUTTON_WHEEL_UP,
	"zoom_out": MOUSE_BUTTON_WHEEL_DOWN,
}


## The game's own actions (the engine's built-in ui_* actions are left out).
func _project_actions() -> PackedStringArray:
	var out := PackedStringArray()
	for property in ProjectSettings.get_property_list():
		var name: String = property.name
		if name.begins_with("input/") and not name.begins_with("input/ui_"):
			out.append(name.trim_prefix("input/"))
	return out


func _events(action: String) -> Array:
	var setting: Variant = ProjectSettings.get_setting("input/" + action)
	return setting.get("events", []) if setting is Dictionary else []


## Every preset in export_presets.cfg by name: {"section", "values": {key: value}, "options": {key: value}}.
func _presets() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(PRESETS_PATH) != OK:
		return {}
	var out := {}
	for section in cfg.get_sections():
		if section.ends_with(".options"):
			continue
		var values := {}
		for key in cfg.get_section_keys(section):
			values[key] = cfg.get_value(section, key)
		var options := {}
		if cfg.has_section(section + ".options"):
			for key in cfg.get_section_keys(section + ".options"):
				options[key] = cfg.get_value(section + ".options", key)
		out[str(values.get("name", ""))] = {"section": section, "values": values, "options": options}
	return out


func _filters(preset: Dictionary, key: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part in str(preset.values.get(key, "")).split(",", false):
		out.append(part.strip_edges())
	return out


## Every file under dir, subfolders included, with one of the extensions.
func _files_under(dir: String, extensions: Array, out: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() in extensions:
			out.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		_files_under(dir.path_join(sub), extensions, out)


## The uid:// ids of the files in game/dev and its subfolders, from their .uid and .import files
## and scene and resource headers.
func _dev_uids() -> PackedStringArray:
	var files := PackedStringArray()
	_files_under(DEV_DIR, UID_PATTERNS.keys(), files)
	var out := PackedStringArray()
	for path in files:
		var re := RegEx.create_from_string(UID_PATTERNS[path.get_extension()])
		var found := re.search(FileAccess.get_file_as_string(path))
		if found != null:
			out.append(found.get_string(1))
	return out


## Whether text names a dev file: a game/dev path, a dev uid, or one of `constants` (whole words).
func _names_dev_file(text: String, uids: PackedStringArray, constants: PackedStringArray) -> bool:
	if text.contains("game/dev"):
		return true
	for uid in uids:
		if text.contains(uid):
			return true
	for constant in constants:
		if _mentions(text, constant):
			return true
	return false


func _mentions(text: String, word: String) -> bool:
	return RegEx.create_from_string("\\b%s\\b" % word).search(text) != null


## The constants a script declares that hold a dev file's path or uid, directly or through
## another such constant (`const A := "res://game/dev/x.gd"`, `const B := preload(A)`).
func _dev_constants(text: String, uids: PackedStringArray) -> PackedStringArray:
	var declarations := RegEx.create_from_string("(?m)^\\s*(?:static\\s+)?const\\s+(\\w+)[^=\\n]*=(.*)$").search_all(text)
	var out := PackedStringArray()
	var grew := true
	while grew:
		grew = false
		for declaration in declarations:
			var constant := declaration.get_string(1)
			if not constant in out and _names_dev_file(declaration.get_string(2), uids, out):
				out.append(constant)
				grew = true
	return out


## The argument of every preload() in a script.
func _preload_args(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for found in RegEx.create_from_string("\\bpreload\\s*\\(([^)]*)\\)").search_all(text):
		out.append(found.get_string(1).strip_edges())
	return out


## The code lines of a script as [function, line], where function is the top-level function the
## line is in ("" outside functions, inner classes included). Comment lines are left out.
func _lines_by_function(text: String) -> Array:
	var header := RegEx.create_from_string("^(?:static\\s+)?func\\s+(\\w+)")
	var out := []
	var function := ""
	for line in text.split("\n"):
		if line.strip_edges().is_empty() or line.strip_edges().begins_with("#"):
			continue
		if not (line.begins_with("\t") or line.begins_with(" ")):
			var found := header.search(line)
			function = found.get_string(1) if found != null else ""
		out.append([function, line])
	return out


func test_the_game_launches_into_main_and_the_m0_check_still_runs_by_path() -> void:
	var setting := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	var path := setting
	if setting.begins_with("uid://"):
		path = ResourceUID.get_id_path(ResourceUID.text_to_id(setting))
	check_eq(path, MAIN_SCENE, "main scene")
	check(ResourceLoader.exists(MAIN_SCENE), "main.tscn exists")
	check(ResourceLoader.exists(BOOT_SCENE), "boot.tscn is kept for tools/check.sh's M0 run")


func test_the_window_opens_at_1280_by_720_in_a_window() -> void:
	check_eq(int(ProjectSettings.get_setting("display/window/size/window_width_override")), 1280, "window width")
	check_eq(int(ProjectSettings.get_setting("display/window/size/window_height_override")), 720, "window height")
	check_eq(int(ProjectSettings.get_setting("display/window/size/mode")), DisplayServer.WINDOW_MODE_WINDOWED, "window mode")
	check_eq(int(ProjectSettings.get_setting("display/window/size/viewport_width")), 1920, "UI designed at 1920 wide")
	check_eq(int(ProjectSettings.get_setting("display/window/size/viewport_height")), 1080, "UI designed at 1080 high")


func test_there_are_no_autoloads() -> void:
	for property in ProjectSettings.get_property_list():
		check(not str(property.name).begins_with("autoload/"), "autoload %s" % property.name)
	check(not FileAccess.get_file_as_string("res://project.godot").contains("[autoload]"), "project.godot has no [autoload] section")


func test_every_action_is_bound_by_physical_key_or_mouse_button() -> void:
	var actions := _project_actions()
	for action in KEY_ACTIONS:
		check(action in actions, "%s exists" % action)
		var codes := []
		for event in _events(action):
			var key := event as InputEventKey
			check(key != null, "%s is bound to keys only" % action)
			if key == null:
				continue
			check(key.keycode == KEY_NONE and key.physical_keycode != KEY_NONE,
				"%s binds %s by physical key, not by layout" % [action, OS.get_keycode_string(key.physical_keycode)])
			codes.append(key.physical_keycode)
		check_eq(codes, KEY_ACTIONS[action], "%s keys" % action)
	for action in MOUSE_ACTIONS:
		check(action in actions, "%s exists" % action)
		var buttons := []
		for event in _events(action):
			var button := event as InputEventMouseButton
			check(button != null, "%s is bound to a mouse button" % action)
			if button != null:
				buttons.append(button.button_index)
		check_eq(buttons, [MOUSE_ACTIONS[action]], "%s button" % action)
	for action in actions:
		check(KEY_ACTIONS.has(action) or MOUSE_ACTIONS.has(action), "%s is one of the planned actions" % action)
		check(InputMap.has_action(action), "%s is in the input map" % action)


func test_space_and_the_right_mouse_button_stay_free_for_step_3() -> void:
	for action in _project_actions():
		for event in _events(action):
			if event is InputEventKey:
				check((event as InputEventKey).physical_keycode != KEY_SPACE, "%s uses Space" % action)
			elif event is InputEventMouseButton:
				check((event as InputEventMouseButton).button_index != MOUSE_BUTTON_RIGHT, "%s uses the right mouse button" % action)


func test_the_release_export_leaves_out_the_dev_tools_and_the_tests() -> void:
	var presets := _presets()
	check(presets.has(RELEASE_PRESET), "a '%s' preset" % RELEASE_PRESET)
	if not presets.has(RELEASE_PRESET):
		return
	var release: Dictionary = presets[RELEASE_PRESET]
	var excluded := _filters(release, "exclude_filter")
	check("game/dev/*" in excluded, "release excludes game/dev/* (%s)" % excluded)
	check("tests/*" in excluded, "release excludes tests/* (%s)" % excluded)
	check_eq(str(release.values.get("export_path", "")), "builds/windows/Pangaea.exe", "release export path")
	check_eq(str(release.values.get("platform", "")), "Windows Desktop", "release platform")


func test_the_dev_export_is_the_release_export_with_the_dev_tools() -> void:
	var presets := _presets()
	check(presets.has(RELEASE_PRESET) and presets.has(DEV_PRESET), "'%s' and '%s' presets" % [RELEASE_PRESET, DEV_PRESET])
	if not (presets.has(RELEASE_PRESET) and presets.has(DEV_PRESET)):
		return
	var release: Dictionary = presets[RELEASE_PRESET]
	var dev: Dictionary = presets[DEV_PRESET]
	var excluded := _filters(dev, "exclude_filter")
	check("tests/*" in excluded, "dev excludes tests/* (%s)" % excluded)
	check(not "game/dev/*" in excluded, "dev keeps game/dev (%s)" % excluded)
	check_eq(str(dev.values.get("export_path", "")), "builds/windows/Pangaea-dev.exe", "dev export path")
	for key in release.values:
		if not key in ["name", "export_path", "exclude_filter"]:
			check_eq(dev.values.get(key), release.values[key], "dev preset %s matches release" % key)
	check_eq(dev.options.keys().size(), release.options.keys().size(), "dev and release have the same options")
	for key in release.options:
		check_eq(dev.options.get(key), release.options[key], "dev option %s matches release" % key)
	var script := FileAccess.get_file_as_string(EXPORT_SCRIPT)
	check(script.contains("--export-release \"%s\" builds/windows/Pangaea.exe" % RELEASE_PRESET), "export_windows.sh exports the release exe")
	check(script.contains("--export-debug \"%s\" builds/windows/Pangaea-dev.exe" % DEV_PRESET), "export_windows.sh exports the dev exe as a debug build")


func test_only_mains_guarded_loader_refers_to_the_dev_tools() -> void:
	var files := PackedStringArray()
	_files_under(GAME_DIR, SCAN_EXTENSIONS, files)
	var uids := _dev_uids()
	check(uids.size() >= 5, "found the uids of the dev files (%d)" % uids.size())
	var main_paths := _dev_constants(FileAccess.get_file_as_string(DEV_LOADER), uids)
	check(main_paths.size() >= 4, "found Main's dev paths (%s)" % ", ".join(main_paths))
	var scanned := 0
	for path in files:
		if path.begins_with(DEV_DIR + "/"):
			continue
		scanned += 1
		var text := FileAccess.get_file_as_string(path)
		if path != DEV_LOADER:
			check(not text.contains("res://game/dev/"), "%s refers to res://game/dev/" % path)
			for constant in main_paths:
				check(not _mentions(text, constant), "%s uses Main.%s" % [path, constant])
		for uid in uids:
			check(not text.contains(uid), "%s refers to a dev file by %s" % [path, uid])
	check(scanned >= 40, "scanned the game files outside game/dev (%d)" % scanned)


func test_nothing_outside_the_dev_tools_preloads_a_dev_file() -> void:
	var files := PackedStringArray()
	_files_under(GAME_DIR, ["gd", "tscn"], files)
	var uids := _dev_uids()
	var main_paths := _dev_constants(FileAccess.get_file_as_string(DEV_LOADER), uids)
	var preloads := 0
	for path in files:
		if path.begins_with(DEV_DIR + "/"):
			continue
		var text := FileAccess.get_file_as_string(path)
		var constants := _dev_constants(text, uids)
		constants.append_array(main_paths)
		for arg in _preload_args(text):
			preloads += 1
			check(not _names_dev_file(arg, uids, constants),
				"%s preloads a dev file with preload(%s), so the release build cannot parse it" % [path, arg])
	check(preloads >= 10, "checked the game's preloads (%d)" % preloads)


func test_main_names_the_dev_tools_only_in_its_guarded_loaders() -> void:
	var loader := FileAccess.get_file_as_string(DEV_LOADER)
	var constants := _dev_constants(loader, _dev_uids())
	var declaration := RegEx.create_from_string("^const\\s+\\w+\\s*(:\\s*String\\s*)?:?=\\s*\"res://game/dev/[^\"]+\"$")
	var first_lines := {}
	var uses := 0
	for entry in _lines_by_function(loader):
		var function: String = entry[0]
		var line: String = entry[1]
		if function in DEV_LOADER_GUARDS and not first_lines.has(function) and line.begins_with("\t"):
			first_lines[function] = line.strip_edges()
		if not _names_dev_file(line, PackedStringArray(), constants):
			continue
		if function.is_empty():
			check(declaration.search(line.strip_edges()) != null,
				"Main names a dev file outside its guarded loaders, other than as a plain path: %s" % line.strip_edges())
		else:
			uses += 1
			check(function in DEV_LOADER_GUARDS, "Main.%s names a dev file: %s" % [function, line.strip_edges()])
	check(uses >= 3, "found Main's guarded loads (%d lines)" % uses)
	for function in DEV_LOADER_GUARDS:
		check(str(first_lines.get(function, "")).begins_with(DEV_LOADER_GUARDS[function]),
			"Main.%s starts with its guard '%s' (%s)" % [function, DEV_LOADER_GUARDS[function], first_lines.get(function, "missing")])


func test_no_script_in_game_dev_or_its_subfolders_declares_a_class_name() -> void:
	var scripts := PackedStringArray()
	_files_under(DEV_DIR, ["gd"], scripts)
	var re := RegEx.create_from_string("(?m)^\\s*class_name\\b")
	for path in scripts:
		check(re.search(FileAccess.get_file_as_string(path)) == null, "%s declares a class_name" % path)
	check(scripts.size() >= 5, "checked the dev scripts (%d)" % scripts.size())


func test_check_sh_and_ci_start_the_release_pack() -> void:
	check(FileAccess.get_file_as_string(CHECK_SCRIPT).contains(RELEASE_CHECK), "check.sh runs %s" % RELEASE_CHECK)
	var ci := FileAccess.get_file_as_string(CI_WORKFLOW)
	var export_at := ci.find("run: tools/export_windows.sh")
	var release_at := ci.find("run: " + RELEASE_CHECK, maxi(export_at, 0))
	check(export_at >= 0 and release_at > export_at, "CI runs %s after the export step" % RELEASE_CHECK)
	var line := ci.substr(release_at, ci.find("\n", release_at) - release_at) if release_at >= 0 else ""
	check(line.ends_with(" builds/windows/Pangaea.exe"), "CI checks the exported exe it uploads (%s)" % line)
