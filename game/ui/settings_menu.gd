class_name SettingsMenu
extends Control
## The settings screen (UI pass), over the title screen or the pause menu. Five tabs: Graphics,
## Audio, Controls, Accessibility and Gameplay. Every row works with the mouse, the keyboard and
## a controller: up and down move between rows, left and right change a value, LB and RB (or Q and
## E) change tabs, and B or Esc goes back. Changes apply at once; closing writes the file.
##
## The Controls tab lists each action with its keyboard and controller input; pressing one waits
## for the next key, click or button (Esc cancels) and SettingsService.rebind() swaps it in.
##
## It only edits the shared SettingsService; whoever opened it listens to `closed`.

signal closed

const THEME := preload("res://game/ui/theme/pangaea_theme.tres")
const TABS := ["Graphics", "Audio", "Controls", "Accessibility", "Gameplay"]
## Each tab's rows: [setting id, label, words for the values (choices only; else {})].
const ROWS := {
	"Graphics": [
		["graphics/window_mode", "Display", {"windowed": "Window", "borderless": "Full screen (borderless)", "fullscreen": "Full screen (exclusive)"}],
		["graphics/vsync", "Vertical sync", {}],
		["graphics/max_fps", "Frame rate limit", {0: "No limit", 30: "30", 60: "60", 120: "120", 144: "144", 240: "240"}],
		["graphics/render_scale", "3D resolution", {}],
		["graphics/msaa", "Anti-aliasing", {"off": "Off", "2x": "MSAA 2x", "4x": "MSAA 4x", "8x": "MSAA 8x"}],
	],
	"Audio": [
		["audio/master", "Master volume", {}],
		["audio/music", "Music", {}],
		["audio/sfx", "Effects", {}],
		["audio/ambience", "Ambience", {}],
		["audio/mute_unfocused", "Mute when the window is in the background", {}],
	],
	"Controls": [
		["controls/zoom_speed", "Zoom speed", {}],
		["controls/invert_zoom", "Invert zoom", {}],
		["controls/stick_deadzone", "Stick deadzone", {}],
	],
	"Accessibility": [
		["accessibility/text_scale", "Text size", {100: "100%", 115: "115%", 130: "130%"}],
		["accessibility/reduce_camera_motion", "Reduce camera motion", {}],
		["accessibility/reduce_flashing", "Reduce flashing effects", {}],
	],
	"Gameplay": [
		["gameplay/growth_trigger", "Growing", {"auto": "Automatic, at a calm moment", "press": "When I press Grow"}],
		["gameplay/pause_on_focus_loss", "Pause when the window loses focus", {}],
	],
}
const NOTES := {
	"Accessibility": "Important cues never rely on colour or sound alone. Subtitles arrive with the first spoken lines.",
	"Controls": "Press an input to change it, then press the new key, click or button. Esc cancels.",
}
const WAIT_TEXT := "Press an input…"

var service: SettingsService
var tab := 0
## The action and device being rebound while waiting for an input ("" when not waiting).
var capture_action := ""
var capture_device := ""

var _tab_buttons: Array[Button] = []
var _rows_box: VBoxContainer
var _scroll: ScrollContainer
var _note: Label
var _hint: Label
var _back: Button
var _reset: Button
var _reset_binds: Button
var _bind_buttons := {}   ## [action, device] -> Button
var _value_labels := {}   ## id -> Label
var _controls := {}       ## id -> the focusable control of its row
var _hint_generation := -1


func _init() -> void:
	theme = THEME
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	_ensure_built()
	_dress()


## The playful touch (MenuBounce): pill buttons along the bottom, and every tab and button that
## is not a row's value swells when focused.
func _dress() -> void:
	for b: Button in [_reset_binds, _reset, _back]:
		MenuBounce.pill(b)
		MenuBounce.attach(b)
	for b in _tab_buttons:
		MenuBounce.attach(b, 1.04)


## Builds the screen once, on entering the tree or on the first open(), whichever comes first.
func _ensure_built() -> void:
	if _rows_box == null:
		_build()


## Shows the menu on a tab, editing `p_service` (default: the shared one).
func open(p_service: SettingsService = null, start_tab: int = 0) -> void:
	service = p_service if p_service != null else SettingsService.shared()
	_ensure_built()
	if not service.changed.is_connected(_on_changed):
		service.changed.connect(_on_changed)
	visible = true
	MenuBounce.arrive(self, [], Vector2.ZERO)   # fade only: a sliding dim would uncover an edge
	show_tab(start_tab)


## Writes the file and closes. The menu stays in the tree for the next open().
func close() -> void:
	if capture_action != "":
		_end_capture()
	if service != null:
		var err := service.save_file()
		if err != OK:
			push_warning("Settings could not be saved (%s)." % error_string(err))
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func show_tab(index: int) -> void:
	tab = posmod(index, TABS.size())
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == tab
	_fill_rows()
	_note.text = NOTES.get(TABS[tab], "")
	_note.visible = not _note.text.is_empty()
	_reset_binds.visible = TABS[tab] == "Controls"
	if is_inside_tree():
		var first := _first_focus()
		if first != null:
			first.grab_focus()


## The text a row shows for its value ("On", "75%", "Full screen (borderless)").
static func value_text(id: String, value: Variant, words: Dictionary = {}) -> String:
	if words.has(value):
		return words[value]
	var spec: Dictionary = GameSettings.SPEC[id]
	match spec.kind:
		"bool":
			return "On" if value else "Off"
		"int":
			return "%d%%" % value if id.begins_with("audio/") else str(value)
		"float":
			if id == "graphics/render_scale":
				return "%d%%" % roundi(value * 100.0)
			if id == "controls/zoom_speed":
				return "%.2fx" % value
			return "%.2f" % value
	return str(value)


## The controller or keyboard input shown on a binding button.
func binding_text(action: String, device: String) -> String:
	if capture_action == action and capture_device == device:
		return WAIT_TEXT
	var code := service.first_code(action, device)
	return InputPrompts.code_name(code) if not code.is_empty() else "—"


## Starts waiting for an input to bind to `action` on `device` ("keys" or "pad").
func begin_capture(action: String, device: String) -> void:
	capture_action = action
	capture_device = device
	_refresh_bindings()


## Binds a captured event, if it suits the device being rebound. Returns true when it was taken.
func capture(event: InputEvent) -> bool:
	if capture_action == "" or not event.is_pressed() or event.is_echo():
		return false
	var code := InputCodes.from_event(event)
	if code.is_empty() or InputCodes.device_of(code) != capture_device:
		return false
	if code.begins_with("mouse:") and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		return false
	var action := capture_action
	_end_capture()
	service.rebind(action, code)
	return true


func _end_capture() -> void:
	var button: Button = _bind_buttons.get([capture_action, capture_device])
	capture_action = ""
	capture_device = ""
	_refresh_bindings()
	if button != null and is_inside_tree():
		button.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if capture_action != "":
		get_viewport().set_input_as_handled()
		if event is InputEventKey and event.is_pressed() and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_end_capture()
		else:
			capture(event)
		return


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
	elif _is_tab_key(event, -1):
		get_viewport().set_input_as_handled()
		show_tab(tab - 1)
	elif _is_tab_key(event, 1):
		get_viewport().set_input_as_handled()
		show_tab(tab + 1)


func _process(_delta: float) -> void:
	if visible and _hint_generation != InputPrompts.generation:
		_hint_generation = InputPrompts.generation
		_update_hint()


static func _is_tab_key(event: InputEvent, direction: int) -> bool:
	if event is InputEventJoypadButton and event.is_pressed():
		var b := (event as InputEventJoypadButton).button_index
		return b == (JOY_BUTTON_LEFT_SHOULDER if direction < 0 else JOY_BUTTON_RIGHT_SHOULDER)
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		return (event as InputEventKey).physical_keycode == (KEY_Q if direction < 0 else KEY_E)
	return false


func _update_hint() -> void:
	if _hint == null:
		return
	if InputPrompts.device == "pad":
		_hint.text = "LB / RB  Tabs   ·   Left / Right  Change   ·   A  Select   ·   B  Back"
	else:
		_hint.text = "Q / E  Tabs   ·   Left / Right  Change   ·   Enter  Select   ·   Esc  Back"


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.004, 0.02, 0.06, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"DialogPanel"
	panel.custom_minimum_size = Vector2(1320, 860)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	var header := Label.new()
	header.text = "Settings"
	header.theme_type_variation = &"HeaderLabel"
	box.add_child(header)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	box.add_child(tabs)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var b := Button.new()
		b.name = "Tab" + TABS[i]
		b.text = TABS[i]
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = &"TabButton"
		b.focus_mode = Control.FOCUS_NONE   # tabs change with LB/RB, Q/E or a click
		b.pressed.connect(show_tab.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)

	box.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	box.add_child(_scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 10)
	_scroll.add_child(_rows_box)
	_note = Label.new()
	_note.theme_type_variation = &"SmallLabel"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_note)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	box.add_child(bottom)
	_hint = Label.new()
	_hint.theme_type_variation = &"SmallLabel"
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(_hint)
	_reset_binds = Button.new()
	_reset_binds.name = "ResetBindings"
	_reset_binds.text = "Reset inputs"
	_reset_binds.pressed.connect(func(): service.reset_bindings())
	bottom.add_child(_reset_binds)
	_reset = Button.new()
	_reset.name = "ResetTab"
	_reset.text = "Reset tab"
	_reset.pressed.connect(func(): service.reset_section(TABS[tab].to_lower()))
	bottom.add_child(_reset)
	_back = Button.new()
	_back.name = "Back"
	_back.text = "Back"
	_back.theme_type_variation = &"PrimaryButton"
	_back.custom_minimum_size = Vector2(200, 0)
	_back.pressed.connect(close)
	bottom.add_child(_back)
	_update_hint()


func _fill_rows() -> void:
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	_bind_buttons.clear()
	_value_labels.clear()
	_controls.clear()
	var tab_name: String = TABS[tab]
	for row in ROWS[tab_name]:
		_add_setting_row(row[0], row[1], row[2])
	if tab_name == "Controls":
		_add_binding_header()
		for pair in SettingsService.REBINDABLE:
			_add_binding_row(pair[0], pair[1])
	_link_focus()


func _add_setting_row(id: String, label_text: String, words: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.name = id.replace("/", "_")
	row.add_theme_constant_override("separation", 24)
	_rows_box.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spec: Dictionary = GameSettings.SPEC[id]
	var value = service.get_value(id)
	var control: Control
	match spec.kind:
		"bool":
			var toggle := CheckButton.new()
			toggle.button_pressed = value
			toggle.text = value_text(id, value)
			toggle.custom_minimum_size = Vector2(440, 0)
			toggle.toggled.connect(func(on: bool): service.set_value(id, on))
			control = toggle
		"int", "float":
			var slider := HSlider.new()
			slider.min_value = spec.min
			slider.max_value = spec.max
			slider.step = spec.get("step", 1)
			slider.value = value
			slider.custom_minimum_size = Vector2(320, 40)
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			slider.value_changed.connect(func(v: float): service.set_value(id, v if spec.kind == "float" else int(v)))
			row.add_child(slider)
			var shown := Label.new()
			shown.custom_minimum_size = Vector2(100, 0)
			shown.text = value_text(id, value)
			shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_value_labels[id] = shown
			row.add_child(shown)
			control = slider
		"choice":
			var cycle := ChoiceButton.new()
			cycle.setup(id, words, service)
			cycle.custom_minimum_size = Vector2(440, 0)
			control = cycle
	control.name = "Value"
	if control.get_parent() == null:
		row.add_child(control)
	_controls[id] = control


func _add_binding_header() -> void:
	_rows_box.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_rows_box.add_child(row)
	for text in ["Action", "Keyboard and mouse", "Controller"]:
		var label := Label.new()
		label.text = text
		label.theme_type_variation = &"AccentLabel"
		label.custom_minimum_size = Vector2(300, 0)
		if text == "Action":
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)


func _add_binding_row(action: String, label_text: String) -> void:
	var row := HBoxContainer.new()
	row.name = "Bind_" + action
	row.add_theme_constant_override("separation", 24)
	_rows_box.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	for device in ["keys", "pad"]:
		var b := Button.new()
		b.name = "Keys" if device == "keys" else "Pad"
		b.custom_minimum_size = Vector2(300, 0)
		b.pressed.connect(begin_capture.bind(action, device))
		row.add_child(b)
		_bind_buttons[[action, device]] = b
	_refresh_bindings()


func _refresh_bindings() -> void:
	for key in _bind_buttons:
		var b: Button = _bind_buttons[key]
		b.text = binding_text(key[0], key[1])
		b.theme_type_variation = &"PrimaryButton" if b.text == WAIT_TEXT else &""


## Rows lead down to the bottom buttons and the bottom buttons lead back up.
func _link_focus() -> void:
	var first := _first_focus()
	if first == null:
		return
	for b in [_reset_binds, _reset, _back]:
		b.focus_neighbor_top = b.get_path_to(_last_focus())
	_last_focus().focus_neighbor_bottom = _last_focus().get_path_to(_back)
	first.focus_neighbor_top = first.get_path_to(_back)


func _first_focus() -> Control:
	if not _controls.is_empty():
		var id: String = ROWS[TABS[tab]][0][0]
		return _controls[id]
	return _back


func _last_focus() -> Control:
	if TABS[tab] == "Controls" and not _bind_buttons.is_empty():
		var last: String = SettingsService.REBINDABLE[-1][0]
		return _bind_buttons[[last, "keys"]]
	var rows: Array = ROWS[TABS[tab]]
	return _controls[rows[-1][0]]


func _on_changed(id: String) -> void:
	if not visible:
		return
	if id.begins_with("bindings"):
		_refresh_bindings()
		return
	if not GameSettings.SPEC.has(id) or not _controls.has(id):
		if id.begins_with(TABS[tab].to_lower()):
			_fill_rows()
		return
	var value = service.get_value(id)
	var control: Control = _controls[id]
	if control is CheckButton:
		control.set_pressed_no_signal(value)
		control.text = value_text(id, value)
	elif control is HSlider:
		control.set_value_no_signal(value)
		_value_labels[id].text = value_text(id, value)
	elif control is ChoiceButton:
		control.refresh()


## A button that shows a choice setting's value between arrows; left and right (or a click) change it.
class ChoiceButton extends Button:
	var id := ""
	var words := {}
	var service: SettingsService

	func setup(p_id: String, p_words: Dictionary, p_service: SettingsService) -> void:
		id = p_id
		words = p_words
		service = p_service
		alignment = HORIZONTAL_ALIGNMENT_CENTER
		refresh()
		pressed.connect(step.bind(1))

	func refresh() -> void:
		text = "‹  %s  ›" % SettingsMenu.value_text(id, service.get_value(id), words)

	func step(direction: int) -> void:
		var options: Array = GameSettings.SPEC[id].options
		var i := options.find(service.get_value(id))
		service.set_value(id, options[posmod(i + direction, options.size())])
		refresh()

	func _gui_input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_left"):
			accept_event()
			step(-1)
		elif event.is_action_pressed("ui_right"):
			accept_event()
			step(1)
