class_name CreatureEditorHud
extends Control
## The creature editor's panels (creature stage plan section 4, PROPOSED): the part palette on the left (one tool
## per part type in the art records with its cost, the limb tool, and a "no tool" state), the points and the stats
## on the right with the Undo / Redo / Delete / Insert / Mirror buttons, the Test drive toggle and Done and Back,
## eight skin colour swatches, a refusal line at the bottom and a hint line naming the keys. It only presents:
## every button emits a signal and CreatureEditor calls the same method the key would. The space between the
## panels lets the mouse through to the 3D view.

signal tool_chosen(type: String)
## "undo", "redo", "delete", "insert", "mirror", "done" or "back".
signal action(name: String)
signal test_drive_toggled(on: bool)
signal color_chosen(color: Color)
signal preset_chosen(preset_name: String)

const TOOL_BUTTON_FONT_PX := 22
## A part tool with its picture (set_tool_icon): name and price under the picture, three to a row.
const ICON_BUTTON_FONT_PX := 15
const ICON_COLUMNS := 3
const SWATCH_PX := 40
## The palette's category tabs, {id, title}, in order (the playthrough notes: parts grouped by kind in a grid on the
## left). "all" shows every tool.
const CATEGORIES := [
	{"id": "all", "title": "All"}, {"id": "mouths", "title": "Mouths"}, {"id": "senses", "title": "Senses"},
	{"id": "limbs", "title": "Limbs"}, {"id": "weapons", "title": "Weapons"}, {"id": "details", "title": "Details"},
]
## Part type -> category id; a type not listed (a part art adds later) goes to "details".
const PART_CATEGORY := {
	"beak": "mouths", "mandibles": "mouths", "maw": "mouths", "proboscis": "mouths",
	"eye": "senses", "compound_eye": "senses", "eye_stalk": "senses", "antenna": "senses", "barbels": "senses",
	"lure": "senses",
	"limb": "limbs", "foot": "limbs", "hoof": "limbs", "hand": "limbs", "claw": "limbs", "flipper": "limbs",
	"horn": "weapons", "tusk": "weapons", "tail_spikes": "weapons", "club_tail": "weapons", "quills": "weapons",
}

var _tool_buttons := {}   ## tool type -> Button
var _group := ButtonGroup.new()
var _swatches: Array[Button] = []
var _preset_title: Label
var _preset_menu: OptionButton
var _preset_sep: HSeparator
var _category := "all"
var _category_tabs: GridContainer
var _category_buttons := {}   ## category id -> Button

var tools_grid: GridContainer
var swatch_row: HBoxContainer
var points_text: Label
var cost_text: Label
var stats_text: Label
var refusal_panel: PanelContainer
var refusal_text: Label
var hint_text: Label
var title_text: Label
var test_drive_button: Button
var undo_button: Button
var redo_button: Button
var _wired := false


func _ready() -> void:
	wire()


## Finds the nodes and connects the buttons, once: from _ready(), or from the editor when the scene is driven before
## the tree is live (the test runner), where @onready has not run.
func wire() -> void:
	if _wired:
		return
	_wired = true
	tools_grid = %Tools
	swatch_row = %Swatches
	points_text = %PointsText
	cost_text = %CostText
	stats_text = %StatsText
	refusal_panel = %Refusal
	refusal_text = %RefusalText
	hint_text = %HintText
	title_text = %TitleText
	test_drive_button = %TestDrive
	undo_button = %Undo
	redo_button = %Redo
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_group.allow_unpress = true
	refusal_panel.visible = false
	for name in ["Undo", "Redo", "Delete", "Insert", "Mirror", "Done", "Back"]:
		var b: Button = get_node("%" + name)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): action.emit(name.to_lower()))
	test_drive_button.focus_mode = Control.FOCUS_NONE
	test_drive_button.toggled.connect(func(on: bool): test_drive_toggled.emit(on))


## Builds the palette: `tools` are the part types in order, `costs` the editor costs (CreatureData.editor_costs()),
## `colors` the skin swatches.
func setup(tools: Array, costs: Dictionary, colors: Array) -> void:
	for c in tools_grid.get_children():
		c.free()
	_tool_buttons.clear()
	_add_tool("", "Select", 0)
	_add_tool("limb", "Limb", 2 * 3 * int(costs.get("limb_joint", 0)))
	for type in tools:
		var price: int = int((costs.get("part", {}) as Dictionary).get(type, costs.get("part_default", 0)))
		_add_tool(type, String(type).capitalize(), price)
	_build_category_tabs()
	set_category(_category)
	for c in swatch_row.get_children():
		c.free()
	_swatches.clear()
	for color in colors:
		var b := Button.new()
		b.custom_minimum_size = Vector2(SWATCH_PX, SWATCH_PX)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.tooltip_text = color.to_html(false)
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(8)
		style.set_border_width_all(2)
		style.border_color = Color(0.3, 0.5, 0.82, 1)
		var chosen := style.duplicate() as StyleBoxFlat
		chosen.border_color = Color(1, 0.88, 0.6, 1)
		chosen.set_border_width_all(4)
		b.add_theme_stylebox_override("normal", style)
		b.add_theme_stylebox_override("hover", style)
		b.add_theme_stylebox_override("pressed", chosen)
		b.add_theme_stylebox_override("hover_pressed", chosen)
		b.pressed.connect(func(): color_chosen.emit(color))
		swatch_row.add_child(b)
		_swatches.append(b)


func _add_tool(type: String, label: String, price: int) -> void:
	var b := Button.new()
	b.text = label if price <= 0 else "%s  %d" % [label, price]
	b.set_meta("label", label)
	b.set_meta("price", price)
	b.toggle_mode = true
	b.button_group = _group
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = &"TabButton"
	b.add_theme_font_size_override("font_size", TOOL_BUTTON_FONT_PX)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func(): tool_chosen.emit(type))
	tools_grid.add_child(b)
	_tool_buttons[type] = b


## The category a tool belongs to: "" (Select) belongs to every one.
static func category_of(type: String) -> String:
	return "" if type == "" else String(PART_CATEGORY.get(type, "details"))


## Shows only `category`'s tools (and Select); "all" shows every tool.
func set_category(category: String) -> void:
	_category = category
	for t in _tool_buttons:
		(_tool_buttons[t] as Button).visible = category == "all" or t == "" or category_of(t) == category
	for id in _category_buttons:
		(_category_buttons[id] as Button).set_pressed_no_signal(id == category)


func category() -> String:
	return _category


## The tab row above the tools, built once; a tab with no tools in this palette is hidden.
func _build_category_tabs() -> void:
	if _category_tabs == null:
		_category_tabs = GridContainer.new()
		_category_tabs.name = "Categories"
		_category_tabs.columns = 3
		_category_tabs.add_theme_constant_override("h_separation", 6)
		_category_tabs.add_theme_constant_override("v_separation", 6)
		var group := ButtonGroup.new()
		for c in CATEGORIES:
			var b := Button.new()
			b.text = String(c["title"])
			b.toggle_mode = true
			b.button_group = group
			b.focus_mode = Control.FOCUS_NONE
			b.theme_type_variation = &"TabButton"
			b.add_theme_font_size_override("font_size", ICON_BUTTON_FONT_PX + 3)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var id := String(c["id"])
			b.pressed.connect(func(): set_category(id))
			_category_tabs.add_child(b)
			_category_buttons[id] = b
		var scroll := tools_grid.get_parent()
		scroll.get_parent().add_child(_category_tabs)
		scroll.get_parent().move_child(_category_tabs, scroll.get_index())
	for id in _category_buttons:
		var used: bool = id == "all"
		for t in _tool_buttons:
			used = used or (t != "" and category_of(t) == id)
		(_category_buttons[id] as Button).visible = used
	if not (_category_buttons[_category] as Button).visible:
		_category = "all"


## Shows which tool is in use ("" for none) without emitting tool_chosen; a tool outside the shown category switches
## the palette to that tool's category.
func set_tool(type: String) -> void:
	if type != "" and _category != "all" and category_of(type) != _category:
		set_category(category_of(type))
	for t in _tool_buttons:
		(_tool_buttons[t] as Button).set_pressed_no_signal(t == type)
	title_text.text = "Creature editor" if type == "" else "Creature editor   ·   %s tool" % (
			"limb" if type == "limb" else String(type).capitalize().to_lower())


func set_color(color: Color) -> void:
	for b in _swatches:
		b.set_pressed_no_signal(b.tooltip_text == color.to_html(false))


func set_points(points: int, cost: int, affordable: bool) -> void:
	points_text.text = "Points  %d" % points
	if cost == 0:
		cost_text.text = "No changes to pay for"
		cost_text.theme_type_variation = &"SmallLabel"
	elif affordable:
		cost_text.text = "Cost %d   →   %d left" % [cost, points - cost] if cost > 0 else "Refund %d   →   %d left" % [-cost, points - cost]
		cost_text.theme_type_variation = &"AccentLabel"
	else:
		cost_text.text = "Cost %d: %d more than you have" % [cost, cost - points]
		cost_text.theme_type_variation = &"WarnLabel"


func set_stats(lines: PackedStringArray) -> void:
	stats_text.text = "\n".join(lines)


func set_undo_redo(can_undo: bool, can_redo: bool) -> void:
	undo_button.disabled = not can_undo
	redo_button.disabled = not can_redo


## The refusal line: shown while `text` is not empty.
func set_refusal(text: String) -> void:
	refusal_panel.visible = text != ""
	refusal_text.text = text


func set_test_drive(on: bool) -> void:
	test_drive_button.set_pressed_no_signal(on)
	test_drive_button.text = "Stop test drive" if on else "Test drive"


func set_hint(text: String) -> void:
	hint_text.text = text


## The "Start from" menu at the top of the palette: a drop-down with one entry per preset creature ({name, title,
## blurb}; the blurb is the entry's tooltip), built once. Hidden until show_presets(true).
func setup_presets(entries: Array) -> void:
	var box: VBoxContainer = tools_grid.get_parent().get_parent()
	if _preset_menu == null:
		_preset_title = Label.new()
		_preset_title.name = "PresetsTitle"
		_preset_title.text = "Start from a preset"
		_preset_title.theme_type_variation = &"SmallLabel"
		_preset_menu = OptionButton.new()
		_preset_menu.name = "Presets"
		_preset_menu.focus_mode = Control.FOCUS_NONE
		_preset_menu.item_selected.connect(func(index: int):
			if index > 0:
				preset_chosen.emit(String(_preset_menu.get_item_metadata(index))))
		_preset_sep = HSeparator.new()
		_preset_sep.name = "PresetsSep"
		box.add_child(_preset_title)
		box.add_child(_preset_menu)
		box.add_child(_preset_sep)
		box.move_child(_preset_title, 0)
		box.move_child(_preset_menu, 1)
		box.move_child(_preset_sep, 2)
	_preset_menu.clear()
	_preset_menu.add_item("Choose a creature...")
	for e in entries:
		_preset_menu.add_item(String(e["title"]))
		var index := _preset_menu.item_count - 1
		_preset_menu.set_item_metadata(index, String(e["name"]))
		_preset_menu.set_item_tooltip(index, String(e["blurb"]))
	_preset_menu.select(0)
	show_presets(false)


## Shows `preset_name` as the menu's choice without emitting preset_chosen.
func set_preset(preset_name: String) -> void:
	if _preset_menu == null:
		return
	for index in _preset_menu.item_count:
		if _preset_menu.get_item_metadata(index) == preset_name:
			_preset_menu.select(index)
			return
	_preset_menu.select(0)


func preset_count() -> int:
	return 0 if _preset_menu == null else _preset_menu.item_count - 1


func show_presets(on: bool) -> void:
	for n in [_preset_title, _preset_menu, _preset_sep]:
		if n != null:
			n.visible = on



## Gives a part tool its picture (PartIcons): the picture on top, the name and price under it, and the palette goes
## to ICON_COLUMNS columns. Select and Limb keep their text.
func set_tool_icon(type: String, texture: Texture2D) -> void:
	var b: Button = _tool_buttons.get(type)
	if b == null:
		return
	b.icon = texture
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", ICON_BUTTON_FONT_PX)
	b.text = "%s %d" % [String(b.get_meta("label")), int(b.get_meta("price"))]
	b.clip_text = true
	b.tooltip_text = "%s, %d points" % [String(b.get_meta("label")), int(b.get_meta("price"))]
	tools_grid.columns = ICON_COLUMNS


func tool_icon(type: String) -> Texture2D:
	var b: Button = _tool_buttons.get(type)
	return b.icon if b != null else null
