class_name StartScreen
extends Control
## The title screen (M1 step 2). Continue (with a card naming the saved body, lineage tag,
## generation, points and save time over a preview of the saved cell), New lineage (a picker of
## the three starting bodies with their real stats and a shared preview), and Quit. Everything
## works from the keyboard and the first button has focus.
##
## It only asks: Main answers new_requested, continue_requested and quit_requested with the same
## methods the scene smoke calls. The slot summary comes from GameSession.peek_slot(), which
## never writes, and nothing here deletes a save.

signal new_requested(body: String)
signal continue_requested
signal quit_requested

const CARD_SCENE := preload("res://game/ui/body_card.tscn")
const REPLACE_TEXT := "This replaces your current lineage. The previous save is kept as a backup until your next save."
const BACKUP_TEXT := "Your last save could not be read; continuing from the backup."
const UNREADABLE_TEXT := "Your save could not be read, so Continue is off. Nothing was deleted."
const NO_SAVE_TEXT := "No saved lineage yet. Choose New lineage to found one."

## GameSession.peek_slot() for the slot Main uses.
var peek := {}
var catalog: PartCatalog
var selected_body := "grazer"

var _group := ButtonGroup.new()
var _cards := {}       ## body -> BodyCard
var _genomes := {}     ## body -> Genome of the founded starting body
var _built := false

@onready var main_view: Control = %MainView
@onready var picker_view: Control = %PickerView
@onready var continue_button: Button = %ContinueButton
@onready var new_button: Button = %NewButton
@onready var quit_button: Button = %QuitButton
@onready var continue_card: Control = %ContinueCard
@onready var continue_preview: CellPreview = %ContinuePreview
@onready var start_button: Button = %StartButton
@onready var back_button: Button = %BackButton
@onready var picker_preview: CellPreview = %PickerPreview
@onready var confirm: NoticeDialog = %Confirm
@onready var _card_name: Label = %CardName
@onready var _card_tag: Label = %CardTag
@onready var _card_progress: Label = %CardProgress
@onready var _card_saved: Label = %CardSaved
@onready var _card_note: Label = %CardNote
@onready var _cards_box: HBoxContainer = %Cards
@onready var _picked_name: Label = %PickedName
@onready var _picked_diet: Label = %PickedDiet
@onready var _build_label: Label = %BuildLabel


## Shows the slot summary and the starting bodies. Call it before or after the screen enters the tree.
func setup(p_peek: Dictionary, p_catalog: PartCatalog) -> void:
	peek = p_peek
	catalog = p_catalog
	_built = false
	if is_node_ready():
		_build()


func _ready() -> void:
	continue_button.pressed.connect(func(): continue_requested.emit())
	new_button.pressed.connect(open_picker)
	quit_button.pressed.connect(func(): quit_requested.emit())
	start_button.pressed.connect(request_start)
	back_button.pressed.connect(show_main)
	confirm.chosen.connect(_on_confirm)
	_build_label.text = "Build %s" % BuildInfo.build_id()
	if catalog != null and not _built:
		_build()


func _build() -> void:
	_built = true
	_build_cards()
	_fill_continue_card()
	show_main()
	if bool(peek.get("exists", false)) and not bool(peek.get("ok", false)):
		confirm.open("Your save could not be read", UNREADABLE_TEXT + " The files are still in the save folder.",
			[["ok", "OK", true]], "ok", "ok", "\n".join(peek.get("errors", PackedStringArray())))


## The title view, with focus on Continue when it is available, else New lineage.
func show_main() -> void:
	picker_view.visible = false
	main_view.visible = true
	if is_inside_tree():
		(new_button if continue_button.disabled else continue_button).grab_focus()


## The body picker, with focus on the selected body's card.
func open_picker() -> void:
	main_view.visible = false
	picker_view.visible = true
	select(selected_body)
	var card: BodyCard = _cards.get(selected_body)
	if card != null and is_inside_tree():
		card.grab_focus()


## Selects a starting body: its card is marked and the shared preview shows it.
func select(body: String) -> void:
	var card: BodyCard = _cards.get(body)
	if card == null:
		return
	selected_body = body
	card.button_pressed = true
	_picked_name.text = BodyText.body_name(body)
	_picked_diet.text = BodyText.diet(card.phenotype)
	picker_preview.show_genome(_genomes[body], card.phenotype)


## Start on the picker: asks first when a save would be replaced.
func request_start() -> void:
	if bool(peek.get("exists", false)):
		confirm.open("Start a new lineage?", REPLACE_TEXT, [["start", "Start new lineage", true], ["cancel", "Cancel"]],
			"start", "cancel")
	else:
		new_requested.emit(selected_body)


## The body cards, in BodyText.ORDER.
func body_cards() -> Array[BodyCard]:
	var out: Array[BodyCard] = []
	for body in BodyText.ORDER:
		if _cards.has(body):
			out.append(_cards[body])
	return out


func card_for(body: String) -> BodyCard:
	return _cards.get(body)


## The Continue card's visible lines, top to bottom (for checks).
func continue_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for label: Label in [_card_name, _card_tag, _card_progress, _card_saved, _card_note]:
		if label.visible and not label.text.is_empty():
			out.append(label.text)
	return out


## A local date and time, "2026-10-22 14:02", for a Unix time.
static func local_time_text(unix_time: int) -> String:
	var bias_min := int(Time.get_time_zone_from_system().get("bias", 0))
	var d := Time.get_datetime_dict_from_unix_time(unix_time + bias_min * 60)
	return "%04d-%02d-%02d %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute]


func _build_cards() -> void:
	for child in _cards_box.get_children():
		_cards_box.remove_child(child)
		child.queue_free()
	_cards.clear()
	_genomes.clear()
	for body in BodyText.ORDER:
		var founded := Lineage.found(0, BuildInfo.build_id(), catalog, body)
		if not founded.ok:
			continue
		var genome: Genome = founded.save.genome
		var card: BodyCard = CARD_SCENE.instantiate()
		card.button_group = _group
		_cards_box.add_child(card)
		card.setup(body, Phenotype.derive(genome, catalog))
		card.focus_entered.connect(select.bind(body))
		card.pressed.connect(_on_card_pressed.bind(body))
		_cards[body] = card
		_genomes[body] = genome
	if not _cards.has(selected_body) and not _cards.is_empty():
		selected_body = _cards.keys()[0]


func _fill_continue_card() -> void:
	var ok := bool(peek.get("ok", false))
	continue_button.disabled = not ok
	continue_button.focus_mode = Control.FOCUS_ALL if ok else Control.FOCUS_NONE
	continue_preview.visible = ok
	for label: Label in [_card_name, _card_tag, _card_progress, _card_saved]:
		label.visible = ok
	_card_note.visible = true
	if ok:
		var summary: Dictionary = peek.summary
		_card_name.text = BodyText.body_name(summary.body)
		_card_tag.text = "Lineage %s" % summary.lineage_tag
		_card_progress.text = "Generation %d · %s" % [summary.generation, Hud.points_line(summary.adaptation_points)]
		_card_saved.text = "Saved %s" % local_time_text(summary.saved_at_unix)
		continue_preview.show_genome(summary.genome, Phenotype.derive(summary.genome, catalog))
		_card_note.text = BACKUP_TEXT if peek.get("source", "") == "backup" else ""
		_card_note.visible = not _card_note.text.is_empty()
	elif bool(peek.get("exists", false)):
		_card_note.text = UNREADABLE_TEXT
	else:
		_card_note.text = NO_SAVE_TEXT
	_card_note.theme_type_variation = &"SmallLabel" if _card_note.text == NO_SAVE_TEXT else &"WarnLabel"


func _on_card_pressed(body: String) -> void:
	select(body)
	start_button.grab_focus()


func _on_confirm(choice: String) -> void:
	if choice == "start":
		new_requested.emit(selected_body)


func _unhandled_input(event: InputEvent) -> void:
	if picker_view.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		show_main()
