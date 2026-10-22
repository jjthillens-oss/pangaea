class_name PauseMenu
extends Control
## The pause menu (M1 step 2): Resume, Save, Save and quit to title, Quit to desktop, the
## controls and a seed and build footer. It only asks; Main does the work and reports back with
## show_status(). The pool is already paused (and has let go of held input) when this opens.
## Esc or P resumes. Saving is off while the cell is dead.

signal resume_requested
signal save_requested
signal save_and_quit_requested
signal quit_requested

@onready var resume_button: Button = %Resume
@onready var save_button: Button = %Save
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
	_controls.text = "\n".join(Hud.controls_lines())


## Shows the menu. reason: "key" or "focus" (the window lost focus). footer: "Seed N · build X".
func open(reason: String, footer: String, can_save: bool) -> void:
	_reason.visible = reason == "focus"
	_reason.text = "Paused because the window lost focus."
	_status.text = ""
	_status.visible = false
	save_button.disabled = not can_save
	save_quit_button.disabled = not can_save
	_footer.text = footer
	visible = true
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
