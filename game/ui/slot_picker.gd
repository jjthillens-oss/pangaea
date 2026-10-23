class_name SlotPicker
extends Control
## The save slots screen (UI pass): SaveSlots.COUNT cards side by side, each naming the lineage it
## holds (body, tag, generation, points, when it was saved, over a preview of the cell) or saying it
## is empty or unreadable. "Play this slot" makes it the one the title screen continues or founds
## in; "Delete" asks first (Cancel has focus) and then asks Main to delete it.
##
## It only asks: Main answers slot_chosen and delete_requested and calls show_slots() again with
## fresh summaries. Left and right move between cards, B or Esc goes back.

signal slot_chosen(n: int)
signal delete_requested(n: int)
signal closed

const THEME := preload("res://game/ui/theme/pangaea_theme.tres")
const PREVIEW_SCENE := preload("res://game/ui/cell_preview.tscn")
const DELETE_TEXT := "Delete the lineage in slot %d? Its save and its backup are removed. This cannot be undone."

var catalog: PartCatalog
## The slot in use (0 when the game runs a --slot file that is none of them).
var current := 1
var peeks: Array[Dictionary] = []

var _cards_box: HBoxContainer
var _play_buttons: Array[Button] = []
var _delete_buttons: Array[Button] = []
var _back: Button
var _confirm: NoticeDialog
var _pending_delete := 0


func _init() -> void:
	theme = THEME
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _ready() -> void:
	_ensure_built()
	_dress()


## The playful touch (MenuBounce): buttons that swell when focused.
func _dress() -> void:
	for b: Button in _delete_buttons + [_back]:
		MenuBounce.pill(b)
	# Play changes its look (primary or not) with the slot in use, so it keeps the theme's shape.
	for b: Button in _play_buttons + _delete_buttons + [_back]:
		MenuBounce.attach(b)


## Builds the screen once, on entering the tree or on the first open(), whichever comes first.
func _ensure_built() -> void:
	if _cards_box == null:
		_build()


## Shows the slots: `p_peeks` is SaveSlots.peek_all(); `p_current` the slot in use.
func open(p_peeks: Array[Dictionary], p_current: int, p_catalog: PartCatalog) -> void:
	catalog = p_catalog
	_ensure_built()
	visible = true
	MenuBounce.arrive(self, [], Vector2.ZERO)   # fade only: a sliding dim would uncover an edge
	show_slots(p_peeks, p_current)


func show_slots(p_peeks: Array[Dictionary], p_current: int) -> void:
	peeks = p_peeks
	current = p_current
	_fill()
	if is_inside_tree() and visible:
		first_focus().grab_focus()


## The first slot that can be picked (the one in use cannot), else Back.
func first_focus() -> Button:
	for b in _play_buttons:
		if not b.disabled:
			return b
	return _back


func close() -> void:
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


## Asks before deleting slot n; the answer comes back through the confirm dialog.
func request_delete(n: int) -> void:
	_pending_delete = n
	_confirm.open("Delete this lineage?", DELETE_TEXT % n, [["delete", "Delete"], ["cancel", "Cancel"]], "cancel", "cancel")


## The words on slot n's card, top to bottom (for checks).
func card_lines(n: int) -> PackedStringArray:
	var out := PackedStringArray()
	var card := _cards_box.get_child(n - 1)
	for label in card.find_children("*", "Label", true, false):
		if label.visible and not label.text.is_empty():
			out.append(label.text)
	return out


func play_button(n: int) -> Button:
	return _play_buttons[n - 1]


func delete_button(n: int) -> Button:
	return _delete_buttons[n - 1]


## The facts a slot's card shows: "Empty", an unreadable note, or the lineage's lines.
static func slot_lines(peek: Dictionary) -> PackedStringArray:
	if not bool(peek.get("exists", false)):
		return PackedStringArray(["Empty", "Found a new lineage here."])
	if not bool(peek.get("ok", false)):
		return PackedStringArray(["Unreadable", "This save could not be read. Nothing was deleted."])
	var s: Dictionary = peek.summary
	var lines := PackedStringArray([
		BodyText.body_name(s.body),
		"Lineage %s" % s.lineage_tag,
		"Generation %d · %s" % [s.generation, Hud.points_line(s.adaptation_points)],
		"Saved %s" % StartScreen.local_time_text(s.saved_at_unix),
	])
	if peek.get("source", "") == "backup":
		lines.append("From the backup")
	return lines


func _unhandled_input(event: InputEvent) -> void:
	if visible and not _confirm.is_open() and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		close()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.004, 0.02, 0.06, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 28)
	center.add_child(box)
	var header := Label.new()
	header.text = "Save slots"
	header.theme_type_variation = &"HeaderLabel"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(header)
	_cards_box = HBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 28)
	_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_cards_box)
	for n in range(1, SaveSlots.COUNT + 1):
		_cards_box.add_child(_make_card(n))
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(bottom)
	_back = Button.new()
	_back.name = "Back"
	_back.text = "Back"
	_back.custom_minimum_size = Vector2(260, 0)
	_back.pressed.connect(close)
	bottom.add_child(_back)
	_confirm = (load("res://game/ui/notice_dialog.tscn") as PackedScene).instantiate()
	_confirm.name = "ConfirmDelete"
	add_child(_confirm)
	_confirm.chosen.connect(_on_confirm)


func _make_card(n: int) -> Control:
	var card := PanelContainer.new()
	card.name = "Slot%d" % n
	card.theme_type_variation = &"CardPanel"
	card.custom_minimum_size = Vector2(560, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"AccentLabel"
	box.add_child(title)
	var preview: CellPreview = PREVIEW_SCENE.instantiate()
	preview.name = "Preview"
	preview.custom_minimum_size = Vector2(260, 260)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(preview)
	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.custom_minimum_size = Vector2(260, 260)
	box.add_child(spacer)
	var facts := VBoxContainer.new()
	facts.name = "Facts"
	facts.custom_minimum_size = Vector2(0, 160)
	box.add_child(facts)
	var play := Button.new()
	play.name = "Play"
	play.pressed.connect(func(): slot_chosen.emit(n))
	box.add_child(play)
	var delete := Button.new()
	delete.name = "Delete"
	delete.text = "Delete"
	delete.pressed.connect(request_delete.bind(n))
	box.add_child(delete)
	_play_buttons.append(play)
	_delete_buttons.append(delete)
	return card


func _fill() -> void:
	for i in _cards_box.get_child_count():
		var n := i + 1
		var card := _cards_box.get_child(i)
		var peek: Dictionary = peeks[i] if i < peeks.size() else {}
		var title: Label = card.find_child("Title", true, false)
		title.text = "Slot %d%s" % [n, "  ·  in use" if n == current else ""]
		var preview: CellPreview = card.find_child("Preview", true, false)
		var spacer: Control = card.find_child("Spacer", true, false)
		var ok := bool(peek.get("ok", false))
		preview.visible = ok and catalog != null
		spacer.visible = not preview.visible
		if preview.visible:
			var genome: Genome = peek.summary.genome
			preview.show_genome(genome, Phenotype.derive(genome, catalog))
		var facts: VBoxContainer = card.find_child("Facts", true, false)
		for child in facts.get_children():
			facts.remove_child(child)
			child.queue_free()
		var lines := slot_lines(peek)
		for j in lines.size():
			var label := Label.new()
			label.text = lines[j]
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size = Vector2(490, 0)
			if j == 0:
				label.theme_type_variation = &"HeaderLabel"
			elif lines[j] == "From the backup" or lines[0] == "Unreadable":
				label.theme_type_variation = &"WarnLabel"
			elif j >= 3 or lines[0] == "Empty":
				label.theme_type_variation = &"SmallLabel"
			facts.add_child(label)
		var play := _play_buttons[i]
		play.text = "Play this slot" if n != current else "Playing this slot"
		play.theme_type_variation = &"PrimaryButton" if n != current else &""
		play.disabled = n == current
		play.focus_mode = Control.FOCUS_NONE if play.disabled else Control.FOCUS_ALL
		var delete := _delete_buttons[i]
		delete.disabled = not bool(peek.get("exists", false))
		delete.focus_mode = Control.FOCUS_NONE if delete.disabled else Control.FOCUS_ALL


func _on_confirm(choice: String) -> void:
	var n := _pending_delete
	_pending_delete = 0
	if choice == "delete" and n > 0:
		delete_requested.emit(n)
	elif n > 0 and is_inside_tree():
		_delete_buttons[n - 1].grab_focus()
