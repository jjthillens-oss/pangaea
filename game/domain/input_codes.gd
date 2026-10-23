class_name InputCodes
extends RefCounted
## Inputs as short text codes, for the settings file and the rebinding screen (UI pass):
##   "key:87"          a keyboard key by physical position (W on QWERTY)
##   "mouse:1"         a mouse button (MouseButton)
##   "pad:0"           a controller button (JoyButton)
##   "axis:1:-1"       a controller stick or trigger pushed one way (JoyAxis, then -1 or 1)
## Keys are kept by physical position, as the project's bindings are, so a layout change keeps
## them in place. Controller names follow the common layout (A at the bottom, B on the right).

const KINDS := ["key", "mouse", "pad", "axis"]

const PAD_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Menu",
	JOY_BUTTON_LEFT_STICK: "Left stick press", JOY_BUTTON_RIGHT_STICK: "Right stick press",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}
const AXIS_NAMES := {
	"0:-1": "Left stick left", "0:1": "Left stick right", "1:-1": "Left stick up", "1:1": "Left stick down",
	"2:-1": "Right stick left", "2:1": "Right stick right", "3:-1": "Right stick up", "3:1": "Right stick down",
	"4:1": "LT", "5:1": "RT",
}


static func is_valid(code: String) -> bool:
	return to_event(code) != null


## The code for an event, or "" for an event no binding can hold (a typed key without a physical
## position, a stick at rest, a touch).
static func from_event(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		return "key:%d" % key.physical_keycode if key.physical_keycode != KEY_NONE else ""
	if event is InputEventMouseButton:
		return "mouse:%d" % (event as InputEventMouseButton).button_index
	if event is InputEventJoypadButton:
		return "pad:%d" % (event as InputEventJoypadButton).button_index
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) < 0.5:
			return ""
		return "axis:%d:%d" % [motion.axis, 1 if motion.axis_value > 0 else -1]
	return ""


## The event a code stands for, or null for a malformed code.
static func to_event(code: String) -> InputEvent:
	var parts := code.split(":")
	if parts.size() < 2 or not parts[0] in KINDS:
		return null
	for i in range(1, parts.size()):
		if not parts[i].is_valid_int():
			return null
	var n := parts[1].to_int()
	match parts[0]:
		"key":
			if parts.size() != 2 or n <= 0:
				return null
			var key := InputEventKey.new()
			key.physical_keycode = n as Key
			return key
		"mouse":
			if parts.size() != 2 or n < 1 or n > 9:
				return null
			var mouse := InputEventMouseButton.new()
			mouse.button_index = n as MouseButton
			return mouse
		"pad":
			if parts.size() != 2 or n < 0 or n >= JOY_BUTTON_SDL_MAX:
				return null
			var pad := InputEventJoypadButton.new()
			pad.button_index = n as JoyButton
			return pad
		"axis":
			if parts.size() != 3 or n < 0 or n >= JOY_AXIS_SDL_MAX or not parts[2] in ["-1", "1"]:
				return null
			var motion := InputEventJoypadMotion.new()
			motion.axis = n as JoyAxis
			motion.axis_value = float(parts[2].to_int())
			return motion
	return null


## "keys" for keyboard and mouse codes, "pad" for controller ones.
static func device_of(code: String) -> String:
	return "pad" if code.begins_with("pad:") or code.begins_with("axis:") else "keys"


## A controller code's name ("A", "LB", "Left stick up"); "" for keyboard and mouse codes, which
## KeyLabel names from the player's layout.
static func pad_name(code: String) -> String:
	var parts := code.split(":")
	if parts[0] == "pad" and parts.size() == 2:
		return PAD_NAMES.get(parts[1].to_int(), "Button %s" % parts[1])
	if parts[0] == "axis" and parts.size() == 3:
		return AXIS_NAMES.get("%s:%s" % [parts[1], parts[2]], "Axis %s%s" % [parts[1], "+" if parts[2] == "1" else "-"])
	return ""
