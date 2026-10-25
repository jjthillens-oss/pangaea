class_name CreatureEditorHud
extends Control
## The creature editor's panels (creature stage plan section 4, PROPOSED): the part palette on the left (one tool
## per part type in the art records with its cost, the limb tool, and a "no tool" state), the points and the stats
## on the right with the Undo / Redo / Delete / Insert / Mirror buttons, the Test drive toggle and Done and Back,
## eight skin colour swatches, the four skin covering toggles (Smooth, Fur, Scales, Wet), the head shape sliders
## (snout, skull width and height, jaw, brow; built in code by setup_head_shape, under the stats), a refusal line at
## the bottom and a hint line naming the keys. It only presents:
## every button emits a signal and CreatureEditor calls the same method the key would. The space between the
## panels lets the mouse through to the 3D view.

signal tool_chosen(type: String)
## "undo", "redo", "delete", "insert", "mirror", "done" or "back".
signal action(name: String)
signal test_drive_toggled(on: bool)
signal color_chosen(color: Color)
## A covering button: an index into the covering names setup() was given (creature_look.gd COVERINGS).
signal covering_chosen(covering: int)
signal preset_chosen(preset_name: String)
## The "Random creature" button beside the presets.
signal random_requested
## A head shape slider moved: `key` is a HeadShape field, `value` per mille.
signal head_shape_changed(key: String, value: int)
## A head shape slider drag began (true) or ended (false), so the editor makes the drag one undo step.
signal head_shape_drag(started: bool)
## Editor-ease: the Symmetry toggle (on: new parts and limbs off the middle line come as mirrored pairs). The toggle
## shows only when something is connected to this at setup() (GitHub issue A asks the editor to connect it).
signal symmetry_toggled(on: bool)

const TOOL_BUTTON_FONT_PX := 22
## A part tool with its picture (set_tool_icon): name and price under the picture, three to a row.
const ICON_BUTTON_FONT_PX := 15
const ICON_COLUMNS := 3
## A locked tool (a part not found yet) is drawn this faded.
const LOCKED_TOOL_MODULATE := Color(1, 1, 1, 0.35)
const SWATCH_PX := 40
## The head shape sliders, in order: {key (HeadShape field), title, kind ("scale": shown as 1.40x, "amount": 0..100%)}.
const HEAD_SLIDERS := [
	{"key": "snout", "title": "Snout", "kind": "scale"}, {"key": "width", "title": "Skull width", "kind": "scale"},
	{"key": "height", "title": "Skull height", "kind": "scale"}, {"key": "jaw", "title": "Jaw", "kind": "amount"},
	{"key": "brow", "title": "Brow ridge", "kind": "amount"},
]
## One slider step, per mille.
const HEAD_STEP := 50
const HEAD_FONT_PX := 17
## The palette's category tabs, {id, title}, in order (the playthrough notes: parts grouped by kind in a grid on the
## left). "all" shows every tool.
const CATEGORIES := [
	{"id": "all", "title": "All"}, {"id": "mouths", "title": "Mouths"}, {"id": "senses", "title": "Senses"},
	{"id": "limbs", "title": "Limbs"}, {"id": "weapons", "title": "Weapons"}, {"id": "details", "title": "Details"},
]
## Part role (part_rules "role", from each cpart_ record) -> category id. A detail part goes by PART_CATEGORY.
const ROLE_CATEGORY := {
	"mouth": "mouths", "eye": "senses", "hand": "limbs", "foot": "limbs", "weapon": "weapons",
}
## Part type -> category id for the tools a role does not place: the limb tool and the detail parts that sense.
## Anything else (a detail, or a part without a role) goes to "details".
const PART_CATEGORY := {
	"limb": "limbs", "antenna": "senses", "barbels": "senses", "lure": "senses",
}

var _tool_buttons := {}   ## tool type -> Button
var _roles := {}   ## part type -> part role
var _group := ButtonGroup.new()
var _swatches: Array[Button] = []
var _coverings: Array[Button] = []
var _preset_title: Label
var _preset_menu: OptionButton
var _preset_sep: HSeparator
var _category := "all"
var _category_tabs: GridContainer
var _category_buttons := {}   ## category id -> Button
var _random_button: Button
var _head_box: VBoxContainer
var _head_sliders := {}   ## head field -> HSlider
var _head_values := {}   ## head field -> Label

var tools_grid: GridContainer
var swatch_row: HBoxContainer
## The covering toggles, built by setup() under its own caption after the swatches.
var covering_row: HBoxContainer
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
## Editor-ease (game/ui/editor_ease/creature_hud_ease.gd): the tooltips, stats panel, part card and placement hint,
## built in code by one child node; the hooks below only forward to it.
const EditorEase := preload("res://game/ui/editor_ease/creature_hud_ease.gd")
var ease: Node


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
	ease = EditorEase.new()
	add_child(ease)
	ease.attach(self)


## Builds the palette: `tools` are the part types in order, `costs` the editor costs (CreatureData.editor_costs()),
## `colors` the skin swatches, `roles` part type -> part role (for the category tabs), `coverings` the covering
## button labels in the shader's order.
func setup(tools: Array, costs: Dictionary, colors: Array, roles: Dictionary = {},
		coverings: Array = ["Smooth", "Fur", "Scales", "Wet"]) -> void:
	_roles = roles
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
	_build_coverings(coverings)
	if ease:
		ease.on_setup(tools, costs, roles)


## The "SKIN COVERING" caption and its row of toggles, placed after the swatches once and refilled on each setup.
func _build_coverings(names: Array) -> void:
	if covering_row == null:
		var box := swatch_row.get_parent()
		var title := Label.new()
		title.name = "CoveringTitle"
		title.theme_type_variation = &"CaptionLabel"
		title.text = "SKIN COVERING"
		covering_row = HBoxContainer.new()
		covering_row.name = "Coverings"
		covering_row.add_theme_constant_override("separation", 6)
		box.add_child(title)
		box.add_child(covering_row)
		box.move_child(title, swatch_row.get_index() + 1)
		box.move_child(covering_row, swatch_row.get_index() + 2)
	for c in covering_row.get_children():
		c.free()
	_coverings.clear()
	var group := ButtonGroup.new()
	for i in names.size():
		var b := Button.new()
		b.text = String(names[i])
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): covering_chosen.emit(i))
		covering_row.add_child(b)
		_coverings.append(b)
	set_covering(0)


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
	b.set_meta("order", _tool_buttons.size())
	tools_grid.add_child(b)
	_tool_buttons[type] = b


## The category a tool belongs to, from its part `role` or else PART_CATEGORY: "" (Select) belongs to every one.
static func category_of(type: String, role: String = "") -> String:
	if type == "":
		return ""
	return String(ROLE_CATEGORY.get(role, PART_CATEGORY.get(type, "details")))


func _category_for(type: String) -> String:
	return category_of(type, String(_roles.get(type, "")))


## Shows only `category`'s tools (and Select); "all" shows every tool.
func set_category(category: String) -> void:
	_category = category
	for t in _tool_buttons:
		(_tool_buttons[t] as Button).visible = category == "all" or t == "" or _category_for(t) == category
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
			used = used or (t != "" and _category_for(t) == id)
		(_category_buttons[id] as Button).visible = used
	if not (_category_buttons[_category] as Button).visible:
		_category = "all"


## Shows which tool is in use ("" for none) without emitting tool_chosen; a tool outside the shown category switches
## the palette to that tool's category.
func set_tool(type: String) -> void:
	if type != "" and _category != "all" and _category_for(type) != _category:
		set_category(_category_for(type))
	for t in _tool_buttons:
		(_tool_buttons[t] as Button).set_pressed_no_signal(t == type)
	title_text.text = "Creature editor" if type == "" else "Creature editor   ·   %s tool" % (
			"limb" if type == "limb" else String(type).capitalize().to_lower())
	if ease:
		ease.on_tool(type)


func set_color(color: Color) -> void:
	for b in _swatches:
		b.set_pressed_no_signal(b.tooltip_text == color.to_html(false))


## Shows covering `index` as the pressed toggle without emitting covering_chosen.
func set_covering(index: int) -> void:
	for i in _coverings.size():
		_coverings[i].set_pressed_no_signal(i == index)


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
	if ease:
		ease.on_stats(lines)


func set_undo_redo(can_undo: bool, can_redo: bool) -> void:
	undo_button.disabled = not can_undo
	redo_button.disabled = not can_redo
	if ease:
		ease.on_undo_redo(can_undo, can_redo)


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
		_random_button = Button.new()
		_random_button.name = "Random"
		_random_button.text = "Random creature"
		_random_button.focus_mode = Control.FOCUS_NONE
		_random_button.tooltip_text = "A surprise creature to start from"
		_random_button.pressed.connect(func(): random_requested.emit())
		_preset_sep = HSeparator.new()
		_preset_sep.name = "PresetsSep"
		box.add_child(_preset_title)
		box.add_child(_preset_menu)
		box.add_child(_random_button)
		box.add_child(_preset_sep)
		box.move_child(_preset_title, 0)
		box.move_child(_preset_menu, 1)
		box.move_child(_random_button, 2)
		box.move_child(_preset_sep, 3)
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
	for n in [_preset_title, _preset_menu, _random_button, _preset_sep]:
		if n != null:
			n.visible = on



## Gives a part tool its picture (PartIcons): the picture on top, the name and price under it, and the palette goes
## to ICON_COLUMNS columns. Select and Limb keep their text.
## Greys out and disables the tools of the part types in `types` (a set: type -> true), the parts the lineage has not
## found in the world yet, and moves them after the open ones; every other tool is enabled, in palette order.
func set_locked(types: Dictionary) -> void:
	var buttons: Array = []
	for t in _tool_buttons:
		var b: Button = _tool_buttons[t]
		var is_locked := types.has(t)
		b.set_meta("locked", is_locked)
		b.disabled = is_locked
		b.modulate = LOCKED_TOOL_MODULATE if is_locked else Color.WHITE
		b.tooltip_text = _tooltip_of(b)
		buttons.append(b)
	buttons.sort_custom(func(a: Button, b: Button) -> bool:
		var la := int(bool(a.get_meta("locked")))
		var lb := int(bool(b.get_meta("locked")))
		return la < lb if la != lb else int(a.get_meta("order")) < int(b.get_meta("order")))
	for i in buttons.size():
		tools_grid.move_child(buttons[i], i)


## Whether a part type's tool is locked (set_locked).
func is_locked(type: String) -> bool:
	var b: Button = _tool_buttons.get(type)
	return b != null and bool(b.get_meta("locked", false))


static func _tooltip_of(b: Button) -> String:
	if bool(b.get_meta("locked", false)):
		return "%s: find it in the world to use it" % String(b.get_meta("label"))
	return "%s, %d points" % [String(b.get_meta("label")), int(b.get_meta("price"))]


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
	b.tooltip_text = _tooltip_of(b)
	tools_grid.columns = ICON_COLUMNS


func tool_icon(type: String) -> Texture2D:
	var b: Button = _tool_buttons.get(type)
	return b.icon if b != null else null


## The palette button of a tool ("" Select, "limb", or a part type), or null.
func tool_button(type: String) -> Button:
	return _tool_buttons.get(type)


## Shows the symmetry state on its toggle without emitting symmetry_toggled.
func set_symmetry(on: bool) -> void:
	if ease:
		ease.show_symmetry(on)


## The head shape sliders under the stats, built once: `ranges` is key -> [min, max] per mille (the body rules'
## head_shape table). Each slider emits head_shape_changed; a drag also brackets itself with head_shape_drag.
func setup_head_shape(ranges: Dictionary) -> void:
	if _head_box == null:
		var box: VBoxContainer = stats_text.get_parent()
		_head_box = VBoxContainer.new()
		_head_box.name = "HeadShape"
		_head_box.add_theme_constant_override("separation", 2)
		var title := Label.new()
		title.text = "HEAD SHAPE"
		title.theme_type_variation = &"CaptionLabel"
		_head_box.add_child(title)
		for spec in HEAD_SLIDERS:
			var key := String(spec["key"])
			var row := HBoxContainer.new()
			row.name = "Head_" + key
			var name_label := Label.new()
			name_label.text = String(spec["title"])
			name_label.custom_minimum_size = Vector2(130, 0)
			name_label.add_theme_font_size_override("font_size", HEAD_FONT_PX)
			var slider := HSlider.new()
			slider.name = "Slider"
			slider.step = HEAD_STEP
			slider.focus_mode = Control.FOCUS_NONE
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			slider.tooltip_text = String(spec["title"])
			var value_label := Label.new()
			value_label.custom_minimum_size = Vector2(62, 0)
			value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			value_label.add_theme_font_size_override("font_size", HEAD_FONT_PX)
			slider.value_changed.connect(func(v: float):
				value_label.text = head_value_text(key, int(v))
				head_shape_changed.emit(key, int(v)))
			slider.drag_started.connect(func(): head_shape_drag.emit(true))
			slider.drag_ended.connect(func(_changed: bool): head_shape_drag.emit(false))
			row.add_child(name_label)
			row.add_child(slider)
			row.add_child(value_label)
			_head_box.add_child(row)
			_head_sliders[key] = slider
			_head_values[key] = value_label
		var sep := HSeparator.new()
		sep.name = "HeadSep"
		box.add_child(sep)
		box.add_child(_head_box)
		var at := stats_text.get_index() + 1
		box.move_child(sep, at)
		box.move_child(_head_box, at + 1)
	for key in _head_sliders:
		var r: Array = ranges.get(key, [0, 1000])
		var slider: HSlider = _head_sliders[key]
		slider.set_block_signals(true)
		slider.min_value = float(r[0])
		slider.max_value = float(r[1])
		slider.set_block_signals(false)


## Shows the head dials (key -> per mille) on the sliders without emitting head_shape_changed.
func set_head_shape(shape: Dictionary) -> void:
	for key in _head_sliders:
		if not shape.has(key):
			continue
		var slider: HSlider = _head_sliders[key]
		slider.set_value_no_signal(float(shape[key]))
		(_head_values[key] as Label).text = head_value_text(key, int(shape[key]))


## The slider for a head field (null before setup_head_shape).
func head_slider(key: String) -> HSlider:
	return _head_sliders.get(key)


## "1.40x" for a scale dial, "40%" for an amount (jaw, brow).
static func head_value_text(key: String, value: int) -> String:
	for spec in HEAD_SLIDERS:
		if spec["key"] == key and spec["kind"] == "amount":
			return "%d%%" % roundi(value / 10.0)
	return "%.2fx" % (value / 1000.0)
