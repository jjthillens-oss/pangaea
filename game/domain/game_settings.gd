class_name GameSettings
extends RefCounted
## The player's settings (UI pass): graphics, audio, controls, accessibility and gameplay. They are
## account settings, kept apart from run state (Bible 18): SettingsService writes them to
## user://settings.cfg, never into a save. This class only holds and checks values; it reads no
## files and touches no engine state.
##
## Every setting is "section/key" with a spec in SPEC: its kind ("bool", "int", "float" or
## "choice"), default and range or options. Values from a file are checked against the spec; a bad
## or missing one falls back to the default and is named in `problems`.
##
## Bindings are kept apart from SPEC: action -> PackedStringArray of input codes (InputCodes), only
## for the actions the player has changed. An action that is not here uses the project's defaults.

const SCHEMA := 1

const SPEC := {
	# Graphics
	"graphics/window_mode": {"kind": "choice", "default": "windowed", "options": ["windowed", "borderless", "fullscreen"]},
	"graphics/vsync": {"kind": "bool", "default": true},
	"graphics/max_fps": {"kind": "choice", "default": 0, "options": [0, 30, 60, 120, 144, 240]},
	"graphics/render_scale": {"kind": "float", "default": 1.0, "min": 0.5, "max": 1.0, "step": 0.05},
	"graphics/msaa": {"kind": "choice", "default": "2x", "options": ["off", "2x", "4x", "8x"]},
	# Audio: whole percents of each bus's full volume.
	"audio/master": {"kind": "int", "default": 80, "min": 0, "max": 100},
	"audio/music": {"kind": "int", "default": 70, "min": 0, "max": 100},
	"audio/sfx": {"kind": "int", "default": 80, "min": 0, "max": 100},
	"audio/ambience": {"kind": "int", "default": 70, "min": 0, "max": 100},
	"audio/mute_unfocused": {"kind": "bool", "default": false},
	# Controls
	"controls/zoom_speed": {"kind": "float", "default": 1.0, "min": 0.5, "max": 2.0, "step": 0.25},
	"controls/invert_zoom": {"kind": "bool", "default": false},
	"controls/stick_deadzone": {"kind": "float", "default": 0.2, "min": 0.05, "max": 0.5, "step": 0.05},
	# Accessibility (Bible 19)
	"accessibility/text_scale": {"kind": "choice", "default": 100, "options": [100, 115, 130]},
	"accessibility/reduce_camera_motion": {"kind": "bool", "default": false},
	"accessibility/reduce_flashing": {"kind": "bool", "default": false},
	# Gameplay
	"gameplay/growth_trigger": {"kind": "choice", "default": "auto", "options": ["auto", "press"]},
	"gameplay/pause_on_focus_loss": {"kind": "bool", "default": true},
	# Which save slot the title screen uses (1 to SLOT_COUNT).
	"game/slot": {"kind": "int", "default": 1, "min": 1, "max": 3},
}

var _values := {}
## action -> PackedStringArray of input codes, for the actions the player rebound.
var bindings := {}
## What was wrong in the data this was read from, in plain words (empty for defaults).
var problems := PackedStringArray()


func _init() -> void:
	for id in SPEC:
		_values[id] = SPEC[id].default


static func defaults() -> GameSettings:
	return GameSettings.new()


## Reads {"schema", "values": {"section/key": value}, "bindings": {action: [codes]}}. Unknown keys
## are ignored and bad values fall back to their defaults; both are named in `problems`.
static func from_dict(data: Dictionary) -> GameSettings:
	var out := GameSettings.new()
	var values = data.get("values", {})
	if not values is Dictionary:
		out.problems.append("settings values are not a table; using defaults.")
		values = {}
	for id in values:
		if not SPEC.has(id):
			out.problems.append("unknown setting '%s' ignored." % id)
			continue
		if not out.set_value(id, values[id]):
			out.problems.append("setting '%s' had a bad value (%s); using the default." % [id, str(values[id])])
	var binds = data.get("bindings", {})
	if binds is Dictionary:
		for action in binds:
			var codes := PackedStringArray()
			var list = binds[action]
			if not list is Array and not list is PackedStringArray:
				out.problems.append("bindings for '%s' are not a list; using the defaults." % action)
				continue
			var ok := true
			for code in list:
				if not InputCodes.is_valid(str(code)):
					ok = false
					break
				codes.append(str(code))
			if ok:
				out.bindings[str(action)] = codes
			else:
				out.problems.append("bindings for '%s' hold an unknown input; using the defaults." % action)
	return out


func to_dict() -> Dictionary:
	var binds := {}
	for action in bindings:
		binds[action] = Array(bindings[action])
	return {"schema": SCHEMA, "values": _values.duplicate(), "bindings": binds}


func get_value(id: String) -> Variant:
	return _values.get(id, SPEC[id].default if SPEC.has(id) else null)


## Sets a value if the spec allows it (numbers are clamped and snapped to the step). Returns false,
## changing nothing, for an unknown id or a value of the wrong kind or outside the options.
func set_value(id: String, value: Variant) -> bool:
	if not SPEC.has(id):
		return false
	var checked = check_value(id, value)
	if checked == null:
		return false
	_values[id] = checked
	return true


## The value the spec makes of `value`, or null when it does not fit.
static func check_value(id: String, value: Variant) -> Variant:
	var spec: Dictionary = SPEC[id]
	match spec.kind:
		"bool":
			return value if value is bool else null
		"int":
			if not (value is int or (value is float and is_equal_approx(value, roundf(value)))):
				return null
			return clampi(int(value), spec.min, spec.max)
		"float":
			if not (value is int or value is float):
				return null
			return clampf(snappedf(float(value), spec.step), spec.min, spec.max)
		"choice":
			for option in spec.options:
				if typeof(option) == TYPE_INT and (value is int or value is float) and is_equal_approx(float(value), float(option)):
					return option
				if typeof(option) == TYPE_STRING and value is String and value == option:
					return option
			return null
	return null


## The next or previous option of a choice setting, wrapping around (for left and right on a pad).
func cycle(id: String, direction: int) -> Variant:
	var options: Array = SPEC[id].options
	var i := options.find(get_value(id))
	var next = options[posmod(i + direction, options.size())]
	set_value(id, next)
	return next


## The codes bound to `action` when the player has rebound it, else `fallback` (the defaults).
func bindings_for(action: String, fallback: PackedStringArray) -> PackedStringArray:
	return bindings.get(action, fallback)
