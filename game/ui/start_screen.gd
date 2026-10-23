class_name StartScreen
extends Control
## The title screen (M1 step 2; the UI pass added Save slots, Settings, the controller and the live
## world). Behind the menu is a TitleWorld: the deep-blue sea with the saved cell swimming in it,
## and a nameplate beside it names the slot, body, lineage tag, generation, points and save time.
## New lineage opens a picker of the three starting bodies with their real stats; the body picked
## swims in the world. Then Save slots, Settings and Quit. Buttons swell when focused and views
## slide in (MenuBounce). Everything works from the keyboard or a controller and the first button
## has focus; the hint at the bottom names the inputs of the device in use.
##
## It only asks: Main answers new_requested, continue_requested, slots_requested,
## settings_requested and quit_requested with the same methods the scene smoke calls. The slot summary comes from GameSession.peek_slot(), which
## never writes, and nothing here deletes a save.

signal new_requested(body: String)
signal continue_requested
signal quit_requested
signal slots_requested
signal settings_requested
## The creature stage preview (creature-stage plan): Main opens it with open_creature_stage().
signal creature_requested

const CARD_SCENE := preload("res://game/ui/body_card.tscn")
const REPLACE_TEXT := "This replaces your current lineage. The previous save is kept as a backup until your next save."
const BACKUP_TEXT := "Your last save could not be read; continuing from the backup."
const UNREADABLE_TEXT := "Your save could not be read, so Continue is off. Nothing was deleted."
const NO_SAVE_TEXT := "No saved lineage yet. Choose New lineage to found one."
## Where the camera slides on each view (TitleWorld.frame): the hero right of the menu, and on the
## picker up and further right, above its plate and clear of the cards.
const MAIN_FRAME := Vector2(-1.15, 0.0)
const PICKER_FRAME := Vector2(-2.1, -0.75)
const PICKER_ROAM := 0.45
## The body that swims behind the menu when the slot holds no lineage.
const IDLE_BODY := "grazer"

## GameSession.peek_slot() for the slot Main uses.
var peek := {}
var catalog: PartCatalog
var selected_body := "grazer"
## The numbered save slot shown (SaveSlots), or 0 for a --slot file that is none of them.
var slot_number := 0

var _group := ButtonGroup.new()
var _cards := {}       ## body -> BodyCard
var _genomes := {}     ## body -> Genome of the founded starting body
var _built := false
var _hint_generation := -1
var _covered := false
## The genome and phenotype of the saved lineage, or null when the slot holds none.
var _saved_genome: Genome
var _saved_phenotype: Phenotype

## The live sea behind the menus.
var world: TitleWorld
## The cell swimming in the world (it shows the saved lineage, or the body picked). The names are
## those of the previews they replace.
var continue_preview: PlayerCellView:
	get:
		return world.hero if world != null else null
var picker_preview: PlayerCellView:
	get:
		return world.hero if world != null else null

@onready var main_view: Control = %MainView
@onready var picker_view: Control = %PickerView
@onready var continue_button: Button = %ContinueButton
@onready var new_button: Button = %NewButton
@onready var quit_button: Button = %QuitButton
@onready var slots_button: Button = %SlotsButton
@onready var settings_button: Button = %SettingsButton
@onready var creature_button: Button = %CreatureButton
@onready var background: ColorRect = %Background
@onready var hint: Label = %Hint
@onready var _card_title: Label = %CardTitle
@onready var continue_card: Control = %ContinueCard
@onready var start_button: Button = %StartButton
@onready var back_button: Button = %BackButton
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
## `p_slot` is the numbered slot the summary is from (0: none, as for a --slot file).
func setup(p_peek: Dictionary, p_catalog: PartCatalog, p_slot: int = 0) -> void:
	peek = p_peek
	catalog = p_catalog
	slot_number = p_slot
	_built = false
	if is_node_ready():
		_build()


func _ready() -> void:
	world = TitleWorld.new()
	world.name = "World"
	add_child(world)
	move_child(world, 0)
	background.visible = false
	add_child(_make_shade())
	move_child(get_node("Shade"), 1)
	for b: Button in [continue_button, new_button, slots_button, settings_button, quit_button, creature_button]:
		MenuBounce.pill(b)
		MenuBounce.attach(b)
	for b: Button in [back_button, start_button]:
		MenuBounce.pill(b)
		MenuBounce.attach(b)
	continue_button.pressed.connect(func(): continue_requested.emit())
	new_button.pressed.connect(open_picker)
	quit_button.pressed.connect(func(): quit_requested.emit())
	slots_button.pressed.connect(func(): slots_requested.emit())
	settings_button.pressed.connect(func(): settings_requested.emit())
	creature_button.pressed.connect(func(): creature_requested.emit())
	resized.connect(fit_backdrop)
	fit_backdrop()
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
	var others: Array = []
	for body in BodyText.ORDER:
		if body != _hero_body():
			others.append(body)
	world.set_companions(others, catalog)
	show_main()
	if bool(peek.get("exists", false)) and not bool(peek.get("ok", false)):
		confirm.open("Your save could not be read", UNREADABLE_TEXT + " The files are still in the save folder.",
			[["ok", "OK", true]], "ok", "ok", "\n".join(peek.get("errors", PackedStringArray())))


## The motion of the world and the (fallback) backdrop follows "Reduce camera motion"; the
## backdrop's aspect follows the screen.
func fit_backdrop() -> void:
	if world != null:
		world.motion = 0.15 if SettingsService.shared().reduce_camera_motion() else 1.0
	var mat := background.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0) if size.y > 0.0 else 16.0 / 9.0)
	mat.set_shader_parameter("motion", 0.15 if SettingsService.shared().reduce_camera_motion() else 1.0)


## The hint at the bottom: the inputs of the device in use.
func hint_text() -> String:
	var move := "D-pad or left stick  Move" if InputPrompts.device == "pad" else "Arrows or mouse  Move"
	var rest := InputPrompts.hint_line([[&"ui_accept", "Select"], [&"ui_cancel", "Back"]])
	return move + ("   ·   " + rest if not rest.is_empty() else "")


func _process(_delta: float) -> void:
	if _hint_generation != InputPrompts.generation:
		_hint_generation = InputPrompts.generation
		hint.text = hint_text()
		fit_backdrop()
	_cover(_overlay_open())


## Puts focus back on the main view's first live button (after an overlay closes).
func focus_main() -> void:
	if main_view.visible and is_inside_tree():
		(new_button if continue_button.disabled else continue_button).grab_focus()


## The title view, with focus on Continue when it is available, else New lineage.
func show_main() -> void:
	var was_picking := picker_view.visible
	picker_view.visible = false
	main_view.visible = true
	_show_hero()
	world.frame = MAIN_FRAME
	world.roam = 1.0
	if is_inside_tree():
		(new_button if continue_button.disabled else continue_button).grab_focus()
	MenuBounce.arrive(main_view, _main_items(), Vector2(-MenuBounce.SLIDE_PX if was_picking else 0.0, 0.0))


## The body picker, with focus on the selected body's card.
func open_picker() -> void:
	main_view.visible = false
	picker_view.visible = true
	world.frame = PICKER_FRAME
	world.roam = PICKER_ROAM
	select(selected_body)
	var card: BodyCard = _cards.get(selected_body)
	if card != null and is_inside_tree():
		card.grab_focus()
	MenuBounce.arrive(picker_view, body_cards(), Vector2(MenuBounce.SLIDE_PX, 0.0))


## Selects a starting body: its card is marked and the body swims in the world.
func select(body: String) -> void:
	var card: BodyCard = _cards.get(body)
	if card == null:
		return
	var changed: bool = body != selected_body or world.hero_genome != _genomes[body]
	selected_body = body
	card.button_pressed = true
	_picked_name.text = BodyText.body_name(body)
	_picked_diet.text = BodyText.diet(card.phenotype)
	if changed:
		world.show_genome(_genomes[body], card.phenotype)


## Start on the picker: asks first when a save would be replaced. Cancel has focus, so a player
## pressing Enter through the screens does not replace the lineage by accident.
func request_start() -> void:
	if bool(peek.get("exists", false)):
		confirm.open("Start a new lineage?", REPLACE_TEXT, [["start", "Start new lineage", true], ["cancel", "Cancel"]],
			"cancel", "cancel")
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
		MenuBounce.attach(card, 1.03)
		card.focus_entered.connect(select.bind(body))
		card.pressed.connect(_on_card_pressed.bind(body))
		_cards[body] = card
		_genomes[body] = genome
	if not _cards.has(selected_body) and not _cards.is_empty():
		selected_body = _cards.keys()[0]


func _fill_continue_card() -> void:
	var ok := bool(peek.get("ok", false))
	_saved_genome = null
	_saved_phenotype = null
	continue_button.disabled = not ok
	continue_button.focus_mode = Control.FOCUS_ALL if ok else Control.FOCUS_NONE
	for label: Label in [_card_name, _card_tag, _card_progress, _card_saved]:
		label.visible = ok
	_card_note.visible = true
	_card_title.text = "Slot %d  ·  Your lineage" % slot_number if slot_number > 0 else "Your lineage"
	if ok:
		var summary: Dictionary = peek.summary
		_card_name.text = BodyText.body_name(summary.body)
		_card_tag.text = "Lineage %s" % summary.lineage_tag
		_card_progress.text = "Generation %d · %s" % [summary.generation, Hud.points_line(summary.adaptation_points)]
		_card_saved.text = "Saved %s" % local_time_text(summary.saved_at_unix)
		_saved_genome = summary.genome
		_saved_phenotype = Phenotype.derive(summary.genome, catalog)
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


## The body behind the title view: the saved lineage's, else IDLE_BODY.
func _hero_body() -> String:
	if _saved_genome != null:
		return Lineage.starting_body_of(_saved_genome, catalog)
	return IDLE_BODY


## The title view's hero: the saved lineage, else a starting body.
func _show_hero() -> void:
	if _saved_genome != null:
		if world.hero_genome != _saved_genome:
			world.show_genome(_saved_genome, _saved_phenotype)
	elif _genomes.has(IDLE_BODY) and world.hero_genome != _genomes[IDLE_BODY]:
		world.show_genome(_genomes[IDLE_BODY], _cards[IDLE_BODY].phenotype)


## The title view's parts that arrive one after another: the menu, then the preview button, then the card.
func _main_items() -> Array:
	var items: Array = []
	for box in ["Left/Buttons", "Left/Preview"]:
		for b in main_view.get_node(box).get_children():
			if b is Control and b.visible:
				items.append(b)
	items.append(continue_card)
	return items


## A soft navy wash over the left of the world, so the logo and menu read clearly over the sea.
func _make_shade() -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.01, 0.04, 0.11, 0.6))
	gradient.set_color(1, Color(0.01, 0.04, 0.11, 0.0))
	gradient.set_offset(1, 0.5)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 4
	var shade := TextureRect.new()
	shade.name = "Shade"
	shade.texture = texture
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return shade


## Whether the settings or the save slots are open over this screen.
func _overlay_open() -> bool:
	for child in get_children():
		if (child is SettingsMenu or child is SlotPicker) and (child as Control).visible:
			return true
	return false


## Under an overlay the title's menu and nameplate fade away, so only the sea and the cell show
## through the overlay's dim; they come back when it closes.
func _cover(covered: bool) -> void:
	if covered == _covered:
		return
	_covered = covered
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(main_view, "modulate:a", 0.0 if covered else 1.0, 0.2)
