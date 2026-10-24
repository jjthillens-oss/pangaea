class_name PauseMenu
extends Control
## The pause menu (M1 step 2): Resume, Save, Settings (UI pass), Save and quit to title, Quit to
## desktop, the controls and a seed and build footer. It only asks; Main does the work and reports back with
## show_status(). The pool is already paused (and has let go of held input) when this opens.
## Esc or P resumes. Saving is off while the cell is dead.

signal resume_requested
signal save_requested
signal save_and_quit_requested
signal quit_requested
signal settings_requested

@onready var resume_button: Button = %Resume
@onready var save_button: Button = %Save
@onready var settings_button: Button = %Settings
@onready var save_quit_button: Button = %SaveQuit
@onready var quit_button: Button = %Quit
@onready var _reason: Label = %Reason
@onready var _status: Label = %Status
@onready var _controls: Label = %ControlsText
@onready var _footer: Label = %Footer


func _ready() -> void:
	visible = false
	resume_button.pressed.connect(func(): resume_requested.emit())
	save_button.pressed.connect(func(): save_requested.emit())
	save_quit_button.pressed.connect(func(): save_and_quit_requested.emit())
	quit_button.pressed.connect(func(): quit_requested.emit())
	settings_button.pressed.connect(func(): settings_requested.emit())
	_controls.text = "\n".join(Hud.controls_lines())
	for b: Button in [resume_button, save_button, settings_button, save_quit_button, quit_button]:
		MenuBounce.pill(b)
		MenuBounce.attach(b)


## The controls as a controller plays them, from its bindings (UI pass).
static func pad_controls_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for row in [[TranslationServer.translate("UI_SWIM_6CAE1A"), [&"move_up", &"move_down", &"move_left", &"move_right"]], [TranslationServer.translate("UI_ZOOM_IN_4FC05F"), [&"zoom_in"]],
			[TranslationServer.translate("UI_ZOOM_OUT_A4AE4B"), [&"zoom_out"]], [TranslationServer.translate("UI_GROW_7E2299"), [&"grow"]], [TranslationServer.translate("UI_PAUSE_781961"), [&"pause"]]]:
		var names := PackedStringArray()
		for action: StringName in row[1]:
			for n in InputPrompts.names_for(action, "pad"):
				var short := n.trim_suffix(" up").trim_suffix(" down").trim_suffix(" left").trim_suffix(" right")
				if not short in names:
					names.append(short)
		if not names.is_empty():
			out.append("%s: %s" % [row[0], " or ".join(names)])
	return out


## Shows the menu. reason: "key" or "focus" (the window lost focus). footer: "Seed N · build X".
func open(reason: String, footer: String, can_save: bool) -> void:
	_reason.visible = reason == "focus"
	_reason.text = tr("UI_PAUSED_BECAUSE_THE_WINDOW_LOST_FOCUS_9A86AA")
	_status.text = ""
	_status.visible = false
	save_button.disabled = not can_save
	save_quit_button.disabled = not can_save
	_footer.text = footer
	_controls.text = "\n".join(pad_controls_lines() if InputPrompts.device == "pad" else Hud.controls_lines())
	visible = true
	MenuBounce.arrive(self, [], Vector2.ZERO)   # fade only: a sliding dim would uncover an edge
	if is_inside_tree():
		resume_button.grab_focus()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


## A save result or other short news, such as "Saved 14:02" or the save error.
func show_status(text: String, ok: bool) -> void:
	_status.text = text
	_status.theme_type_variation = &"AccentLabel" if ok else &"WarnLabel"
	_status.visible = true


func status_text() -> String:
	return _status.text if _status.visible else ""


func footer_text() -> String:
	return _footer.text


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		resume_requested.emit()
