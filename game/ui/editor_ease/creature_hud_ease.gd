extends Node
## Editor-ease in the creature editor (docs/proposals/editor-ease.md): the HUD's usability layer, built in code by
## this one node so creature_editor_hud.gd keeps only a few one-line hooks (attach, on_setup, on_tool, on_stats,
## on_undo_redo). It adds nothing to the palette's tool grid and never writes the editor's state: it only presents.
## Undo and Redo name the keys bound to ui_undo / ui_redo (Bible 19: inputs shown from the bindings); the editor's
## other keys are hardcoded today, so their buttons say what they do in plain words (GitHub issue B asks for input
## actions). No class_name: the HUD preloads it.

const ShortcutText := preload("res://game/ui/editor_ease/shortcut_text.gd")

const UNDO_WORDS := "Undo the last change"
const REDO_WORDS := "Redo the change you undid"
const NOTHING_TO_UNDO := "Nothing to undo"
const NOTHING_TO_REDO := "Nothing to redo"
## The dock's other buttons, in plain words (no key names: those keys are not bindings yet).
const DOCK_TIPS := {
	"Delete": "Take off the selected part, bone or limb joint",
	"Insert": "Add a bone after the selected bone (or at the tail), or a joint after the selected joint",
	"Mirror": "Give the selected part or limb a twin on the other side, or take its twin away",
	"TestDrive": "Watch the creature walk, trot, run and turn as it stands",
	"Done": "Keep this design and pay its cost",
	"Back": "Clear the tool or the selection first; then leave (unsaved edits ask once)",
}

var hud: Control
var _can_undo := false
var _can_redo := false
## InputPrompts.generation the Undo / Redo tooltips were written for.
var _keys_generation := -1


func _init() -> void:
	name = "EditorEase"


## Called once from the HUD's wire(), when its scene nodes are found.
func attach(owner_hud: Control) -> void:
	hud = owner_hud
	for button_name in DOCK_TIPS:
		var b := hud.get_node_or_null("%" + button_name) as Control
		if b != null:
			b.tooltip_text = DOCK_TIPS[button_name]
	_write_undo_tips()


## Called at the end of the HUD's setup() (a new visit): the palette's buttons were just made again.
func on_setup(_tools: Array, _costs: Dictionary, _roles: Dictionary) -> void:
	pass


## Called at the end of the HUD's set_tool(): `type` is the tool now in use ("" for none).
func on_tool(_type: String) -> void:
	pass


## Called at the end of the HUD's set_stats(), with the editor's stat lines.
func on_stats(_lines: PackedStringArray) -> void:
	pass


## Called at the end of the HUD's set_undo_redo().
func on_undo_redo(can_undo: bool, can_redo: bool) -> void:
	_can_undo = can_undo
	_can_redo = can_redo
	_write_undo_tips()


func _process(_delta: float) -> void:
	if hud != null and InputPrompts.generation != _keys_generation:
		_write_undo_tips()


## "Undo the last change (Ctrl+Z)" from the bindings for the device in use, or "Nothing to undo" while disabled.
func _write_undo_tips() -> void:
	_keys_generation = InputPrompts.generation
	if hud == null or hud.get("undo_button") == null:
		return
	hud.undo_button.tooltip_text = ShortcutText.with_binding(UNDO_WORDS, &"ui_undo") if _can_undo else NOTHING_TO_UNDO
	hud.redo_button.tooltip_text = ShortcutText.with_binding(REDO_WORDS, &"ui_redo") if _can_redo else NOTHING_TO_REDO
