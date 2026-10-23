class_name SettingsService
extends RefCounted
## Loads, saves and applies the player's settings (UI pass). The values live in GameSettings; this
## service owns the file (user://settings.cfg, kept apart from the saves, Bible 18) and puts the
## values into the engine: the window, frame rate and 3D resolution, the audio buses by name
## ("Master", "Music", "SFX", "Ambience"; a bus that does not exist yet is skipped), the input map
## (rebindings and the stick deadzone) and the theme's text size.
##
## One instance is shared (shared()): Main applies it at launch and the settings screen edits it.
## Other code only reads it, through the getters at the bottom, for example
##     SettingsService.shared().reduce_camera_motion()
## Writing is safe: a temporary file, then a rename, so an interrupted write keeps the old file.

signal changed(id: String)

const PATH := "user://settings.cfg"
const TEMP_SUFFIX := ".tmp"
## The bus each volume setting drives.
const BUSES := {"audio/master": "Master", "audio/music": "Music", "audio/sfx": "SFX", "audio/ambience": "Ambience"}
## The actions the player can rebind, in the order the controls screen lists them, with their names.
const REBINDABLE := [
	["move_up", "Swim up"], ["move_down", "Swim down"], ["move_left", "Swim left"], ["move_right", "Swim right"],
	["swim_to_cursor", "Swim to the cursor"], ["zoom_in", "Zoom in"], ["zoom_out", "Zoom out"],
	["grow", "Grow"], ["pause", "Pause"], ["toggle_fullscreen", "Full screen"],
]
## The movement actions the stick deadzone applies to.
const MOVE_ACTIONS := ["move_up", "move_down", "move_left", "move_right"]
## Controller inputs the menus need that the engine's ui_* actions lack: A to choose, B to go back
## (the engine binds the d-pad and the left stick for moving, but no buttons for these two).
const UI_PAD := {"ui_accept": "pad:0", "ui_cancel": "pad:1", "ui_up": "axis:1:-1", "ui_down": "axis:1:1",
	"ui_left": "axis:0:-1", "ui_right": "axis:0:1"}
## Text scale steps, in percent, multiply every font size in the theme but these (the title's
## 150 px logo type is already as large as reading needs).
const UNSCALED_TYPES := ["TitleLabel"]
const THEME_PATH := "res://game/ui/theme/pangaea_theme.tres"

static var _shared: SettingsService

var path := PATH
var settings := GameSettings.defaults()
## The last load's result: "file", "defaults" (no file yet) or "damaged" (unreadable, defaults used).
var load_source := ""
## What shared()'s first load found wrong (Main logs it as warnings).
var load_problems := PackedStringArray()
var _focus_muted := false
## Theme -> {[type, name]: base size} before any text scale.
var _base_sizes := {}


func _init(p_path: String = PATH) -> void:
	path = p_path


## The one instance the game uses, read from PATH on first use.
static func shared() -> SettingsService:
	if _shared == null:
		_shared = SettingsService.new()
		_shared.load_problems = _shared.load_file()
	return _shared


## Replaces the shared instance (tests point it at their own file; null makes the next shared() reload).
static func set_shared(service: SettingsService) -> void:
	_shared = service


## Reads the file. A missing file means defaults; a damaged one too, and the damaged file is left
## where it is until the next save replaces it. Returns the problems found (empty when all is well).
func load_file() -> PackedStringArray:
	if not FileAccess.file_exists(path):
		settings = GameSettings.defaults()
		load_source = "defaults"
		return PackedStringArray()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		settings = GameSettings.defaults()
		load_source = "damaged"
		return PackedStringArray(["%s could not be read; using default settings." % path.get_file()])
	var values := {}
	if cfg.has_section("values"):
		for id in cfg.get_section_keys("values"):
			values[id] = cfg.get_value("values", id)
	var binds := {}
	if cfg.has_section("bindings"):
		for action in cfg.get_section_keys("bindings"):
			binds[action] = cfg.get_value("bindings", action)
	settings = GameSettings.from_dict({"values": values, "bindings": binds})
	load_source = "file"
	return settings.problems


func save_file() -> Error:
	var cfg := ConfigFile.new()
	var data := settings.to_dict()
	cfg.set_value("meta", "schema", GameSettings.SCHEMA)
	for id in data.values:
		cfg.set_value("values", id, data.values[id])
	for action in data.bindings:
		cfg.set_value("bindings", action, data.bindings[action])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + TEMP_SUFFIX
	var err := cfg.save(tmp)
	if err != OK:
		DirAccess.remove_absolute(tmp)
		return err
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path)


func get_value(id: String) -> Variant:
	return settings.get_value(id)


## Changes one setting, applies it and reports it with `changed`. Returns false for a value the
## spec refuses (nothing changes then). It does not write the file; save_file() does.
func set_value(id: String, value: Variant) -> bool:
	var before = settings.get_value(id)
	if not settings.set_value(id, value):
		return false
	if settings.get_value(id) != before:
		apply_one(id)
		changed.emit(id)
	return true


## Puts every setting into the engine.
func apply_all() -> void:
	apply_graphics()
	apply_audio()
	apply_bindings()
	apply_text_scale()


func apply_one(id: String) -> void:
	var section := id.get_slice("/", 0)
	match section:
		"graphics":
			apply_graphics()
		"audio":
			apply_audio()
		"controls":
			apply_bindings()
		"accessibility":
			if id == "accessibility/text_scale":
				apply_text_scale()


func apply_graphics() -> void:
	Engine.max_fps = int(get_value("graphics/max_fps"))
	var root := _root_window()
	if root != null:
		root.scaling_3d_scale = float(get_value("graphics/render_scale"))
		root.msaa_3d = msaa_mode(str(get_value("graphics/msaa")))
	if DisplayServer.get_name() == "headless":
		return
	var vsync := DisplayServer.VSYNC_ENABLED if get_value("graphics/vsync") else DisplayServer.VSYNC_DISABLED
	if DisplayServer.window_get_vsync_mode() != vsync:
		DisplayServer.window_set_vsync_mode(vsync)
	var mode := window_mode(str(get_value("graphics/window_mode")))
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


func apply_audio() -> void:
	for id in BUSES:
		var bus := AudioServer.get_bus_index(BUSES[id])
		if bus < 0:
			continue
		var percent := int(get_value(id))
		AudioServer.set_bus_volume_db(bus, linear_to_db(percent / 100.0) if percent > 0 else -80.0)
		var muted: bool = percent == 0 or (_focus_muted and BUSES[id] == "Master")
		AudioServer.set_bus_mute(bus, muted)


## The window gained or lost focus: with "mute when unfocused" on, the master bus follows it.
func set_window_focused(focused: bool) -> void:
	_focus_muted = not focused and bool(get_value("audio/mute_unfocused"))
	apply_audio()


## Rebuilds the bindings of every rebindable action from the settings (or the project defaults) and
## sets the stick deadzone. The menus also take A, B and the left stick (UI_PAD).
func apply_bindings() -> void:
	for pair in REBINDABLE:
		var action: String = pair[0]
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		for code in codes_for(action):
			var event := InputCodes.to_event(code)
			if event != null:
				InputMap.action_add_event(action, event)
	var deadzone := float(get_value("controls/stick_deadzone"))
	for action in MOVE_ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_set_deadzone(action, deadzone)
	for action in UI_PAD:
		if not InputMap.has_action(action):
			continue
		var has := false
		for event in InputMap.action_get_events(action):
			if InputCodes.from_event(event) == UI_PAD[action]:
				has = true
		if not has:
			InputMap.action_add_event(action, InputCodes.to_event(UI_PAD[action]))


## The codes bound to an action now: the player's, or the project's defaults.
func codes_for(action: String) -> PackedStringArray:
	return settings.bindings_for(action, default_codes(action))


## The project's own bindings for an action (project.godot), whatever the player changed.
static func default_codes(action: String) -> PackedStringArray:
	var out := PackedStringArray()
	var setting: Variant = ProjectSettings.get_setting("input/" + action)
	if setting is Dictionary:
		for event in setting.get("events", []):
			var code := InputCodes.from_event(event)
			if not code.is_empty():
				out.append(code)
	return out


## Binds `code` to `action` in place of its first input of the same device ("keys" or "pad"), or
## adds it when the action has none. Another rebindable action holding the code gets the replaced
## input instead (a swap), so no input does two things. Applies at once; save_file() keeps it.
func rebind(action: String, code: String) -> void:
	var device := InputCodes.device_of(code)
	var codes := codes_for(action)
	var old := ""
	var at := -1
	for i in codes.size():
		if InputCodes.device_of(codes[i]) == device:
			old = codes[i]
			at = i
			break
	if old == code:
		return
	if at >= 0:
		codes[at] = code
	else:
		codes.append(code)
	for pair in REBINDABLE:
		var other: String = pair[0]
		if other == action:
			continue
		var theirs := codes_for(other)
		var i := theirs.find(code)
		if i < 0:
			continue
		if old.is_empty():
			theirs.remove_at(i)
		else:
			theirs[i] = old
		settings.bindings[other] = theirs
	settings.bindings[action] = codes
	apply_bindings()
	changed.emit("bindings/" + action)


## Puts every action back to the project's bindings.
func reset_bindings() -> void:
	settings.bindings.clear()
	apply_bindings()
	changed.emit("bindings")


## Puts every setting of one section ("graphics", "audio", ...) back to its default.
func reset_section(section: String) -> void:
	for id in GameSettings.SPEC:
		if id.begins_with(section + "/"):
			set_value(id, GameSettings.SPEC[id].default)


## The first input of a device bound to an action, as a code ("" when there is none).
func first_code(action: String, device: String) -> String:
	for code in codes_for(action):
		if InputCodes.device_of(code) == device:
			return code
	return ""


## Scales every font size in the game's theme by the text scale setting.
func apply_text_scale(theme: Theme = null) -> void:
	if theme == null:
		theme = load(THEME_PATH)
	if theme == null:
		return
	var key := theme.get_instance_id()
	if not _base_sizes.has(key):
		var base := {"default": theme.default_font_size}
		for type in theme.get_font_size_type_list():
			for name in theme.get_font_size_list(type):
				base[[type, name]] = theme.get_font_size(name, type)
		_base_sizes[key] = base
	var sizes: Dictionary = _base_sizes[key]
	var scale := int(get_value("accessibility/text_scale")) / 100.0
	theme.default_font_size = roundi(sizes.default * scale)
	for entry in sizes:
		if entry is Array:
			var keep: bool = entry[0] in UNSCALED_TYPES
			theme.set_font_size(entry[1], entry[0], sizes[entry] if keep else roundi(sizes[entry] * scale))


# --- Read API for other systems (S2 reads these) ---

func reduce_camera_motion() -> bool:
	return bool(get_value("accessibility/reduce_camera_motion"))


func reduce_flashing() -> bool:
	return bool(get_value("accessibility/reduce_flashing"))


## "auto": the cell grows by itself at a calm moment; "press": it waits for the grow action.
func growth_trigger() -> String:
	return str(get_value("gameplay/growth_trigger"))


func pause_on_focus_loss() -> bool:
	return bool(get_value("gameplay/pause_on_focus_loss"))


## The save slot the title screen uses (SaveSlots.path of the "game/slot" setting).
func current_slot_path() -> String:
	return SaveSlots.path(int(get_value("game/slot")))


static func window_mode(name: String) -> DisplayServer.WindowMode:
	match name:
		"borderless":
			return DisplayServer.WINDOW_MODE_FULLSCREEN
		"fullscreen":
			return DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	return DisplayServer.WINDOW_MODE_WINDOWED


static func msaa_mode(name: String) -> Viewport.MSAA:
	match name:
		"2x":
			return Viewport.MSAA_2X
		"4x":
			return Viewport.MSAA_4X
		"8x":
			return Viewport.MSAA_8X
	return Viewport.MSAA_DISABLED


static func _root_window() -> Window:
	var loop := Engine.get_main_loop()
	return (loop as SceneTree).root if loop is SceneTree else null
