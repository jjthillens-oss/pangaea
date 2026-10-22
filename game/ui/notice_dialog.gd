class_name NoticeDialog
extends Control
## A modal message with a few choices (M1 step 2): the interim death notice, the "Save first?"
## prompt, the new-lineage confirmation and unreadable-save errors. It covers the screen, so
## clicks never reach the game behind it, keeps keyboard focus on its own buttons, and reports
## the player's choice by id. Esc (or the pause key) picks the cancel choice, if there is one.
##
##     dialog.open("Save first?", "You have unsaved progress.",
##         [["save", "Save and quit", true], ["quit", "Quit without saving"], ["cancel", "Cancel"]],
##         "save", "cancel")
##     var choice: String = await dialog.chosen

signal chosen(choice: String)

## Open dialogs, most recent last. Only the most recent one answers keys.
static var _open: Array[NoticeDialog] = []

## The choice Esc and the pause key pick; with none, those keys do nothing while it is open.
var cancel_choice := ""
var _return_focus: Control

@onready var _title: Label = %Title
@onready var _body: Label = %Body
@onready var _detail: Label = %Detail
@onready var _buttons: HBoxContainer = %Buttons


func _ready() -> void:
	visible = false


## Shows the dialog. Each choice is [id, text] or [id, text, true] for the main action, which is
## drawn as the primary button. `focus_choice` gets keyboard focus (default: the first).
## `detail` is smaller text under the body, such as a list of errors.
func open(title: String, body: String, choices: Array, focus_choice: String = "",
		p_cancel_choice: String = "", detail: String = "") -> void:
	_title.text = title
	_body.text = body
	_detail.text = detail
	_detail.visible = not detail.is_empty()
	cancel_choice = p_cancel_choice
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()
	var focus: Button = null
	for choice in choices:
		var button := Button.new()
		button.name = str(choice[0])
		button.text = str(choice[1])
		if choice.size() > 2 and choice[2]:
			button.theme_type_variation = &"PrimaryButton"
		button.pressed.connect(choose.bind(str(choice[0])))
		_buttons.add_child(button)
		if focus == null or str(choice[0]) == focus_choice:
			focus = button
	_trap_focus()
	if not visible:
		var owner_focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
		_return_focus = owner_focus if owner_focus != null and not is_ancestor_of(owner_focus) else null
	visible = true
	_open.erase(self)
	_open.append(self)
	if focus != null and is_inside_tree():
		focus.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	_open.erase(self)
	if _return_focus != null and is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree():
		_return_focus.grab_focus()
	_return_focus = null


func is_open() -> bool:
	return visible


## Closes the dialog and reports `choice`, exactly as pressing its button does.
func choose(choice: String) -> void:
	close()
	chosen.emit(choice)


## The ids of the current choices, in order.
func choice_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for button in _buttons.get_children():
		out.append(str(button.name))
	return out


func button_for(choice: String) -> Button:
	return _buttons.get_node_or_null(NodePath(choice)) as Button


func title_text() -> String:
	return _title.text


func body_text() -> String:
	return _body.text


func _exit_tree() -> void:
	_open.erase(self)


## Esc and the pause key belong to the most recent open dialog and never reach the game.
func _input(event: InputEvent) -> void:
	if not visible or _open.is_empty() or _open.back() != self:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if not cancel_choice.is_empty():
			choose(cancel_choice)


## Arrow keys and Tab move between this dialog's buttons only, wrapping at the ends.
func _trap_focus() -> void:
	var buttons := _buttons.get_children()
	for i in buttons.size():
		var button: Button = buttons[i]
		var prev: Button = buttons[(i - 1 + buttons.size()) % buttons.size()]
		var next: Button = buttons[(i + 1) % buttons.size()]
		button.focus_neighbor_left = button.get_path_to(prev)
		button.focus_neighbor_right = button.get_path_to(next)
		button.focus_previous = button.get_path_to(prev)
		button.focus_next = button.get_path_to(next)
		button.focus_neighbor_top = button.get_path_to(button)
		button.focus_neighbor_bottom = button.get_path_to(button)
