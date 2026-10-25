extends PanelContainer
## Editor-ease (docs/proposals/editor-ease.md): a part's info card, the editors' own tooltip in the game theme's
## GlassPanel. It holds a caption title, plain lines, and before → after stat rows marked ▲ better or ▼ worse (a
## shape and a colour, not colour alone: Bible 19). It never takes the mouse, and it is placed beside what it
## describes, inside the screen. Shared by the cell and creature editors. No class_name; preload it.

const GAME_THEME := preload("res://game/ui/theme/pangaea_theme.tres")
const WIDTH := 380.0
## The space between the card and what it describes, and between the card and the screen's edge.
const GAP := 16.0
const BETTER := Color(0.55, 0.95, 0.6)
const WORSE := Color(1.0, 0.55, 0.5)
const MARKS := {true: "▲", false: "▼"}
## The card's least opacity: the theme's glass, made solid enough to read over the dish and the hint lines under it.
const OPACITY := 0.97

var _title: Label
var _box: VBoxContainer
var _anchor := Rect2()
var _bounds := Rect2()


func _init() -> void:
	name = "PartCard"
	theme = GAME_THEME   # its own, so it looks the same in either editor
	theme_type_variation = &"GlassPanel"
	var glass := GAME_THEME.get_stylebox(&"panel", &"GlassPanel").duplicate() as StyleBox
	if glass is StyleBoxFlat:
		glass.bg_color.a = maxf(glass.bg_color.a, OPACITY)
	add_theme_stylebox_override(&"panel", glass)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, 0)
	visible = false
	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_title = Label.new()
	_title.name = "Title"
	_title.theme_type_variation = &"CaptionLabel"
	_title.uppercase = true
	_box.add_child(_title)


## Shows `title` over `lines`. A line is [text, kind], kind "" (plain), "note" (a small caption), "better" or
## "worse" (marked and coloured); or ["stat", label, before, after, better (true, false or null)], shown in a grid
## as "label  before → after  ▲". Unchanged stats (before == after) are the caller's to leave out.
func show_lines(title: String, lines: Array) -> void:
	_title.text = title
	for child in _box.get_children():
		if child != _title:
			_box.remove_child(child)
			child.queue_free()
	var grid: GridContainer = null
	for line: Array in lines:
		if str(line[0]) == "stat":
			if grid == null:
				grid = GridContainer.new()
				grid.columns = 3
				grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
				grid.add_theme_constant_override(&"h_separation", 14)
				_box.add_child(grid)
			var better: Variant = line[4]
			var kind := "" if better == null else ("better" if better else "worse")
			grid.add_child(_label(str(line[1]), ""))
			grid.add_child(_label("%s → %s" % [line[2], line[3]], kind))
			grid.add_child(_label(MARKS.get(better, ""), kind))
		else:
			grid = null
			var label := _label(str(line[0]), str(line[1]))
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size = Vector2(WIDTH - 60.0, 0)
			if str(line[1]) == "better" or str(line[1]) == "worse":
				label.text = "%s %s" % [MARKS[str(line[1]) == "better"], label.text]
			_box.add_child(label)
	show()
	reset_size()


## Puts the card GAP right of `anchor` (a global rect), its top level with the anchor's top, inside `bounds` (a
## global rect, the screen): to the anchor's left when the right has no room, and moved up when it would run off
## the bottom. Placed again a frame later, once wrapped lines know their height.
func place_beside(anchor: Rect2, bounds: Rect2) -> void:
	_anchor = anchor
	_bounds = bounds
	_place()
	_place.call_deferred()


## Every line's text, the title first; a stat row reads "label before → after mark". For tests and the review.
func texts() -> PackedStringArray:
	var out := PackedStringArray([_title.text])
	for child in _box.get_children():
		if child is GridContainer:
			var cells := child.get_children()
			for i in range(0, cells.size(), 3):
				out.append("%s %s %s" % [cells[i].text, cells[i + 1].text, cells[i + 2].text])
		elif child != _title and child is Label:
			out.append(child.text)
	return out


func _place() -> void:
	if not is_inside_tree() or not visible:
		return
	reset_size()
	var x := _anchor.end.x + GAP
	if x + size.x > _bounds.end.x - GAP:
		x = _anchor.position.x - GAP - size.x
	var top := _bounds.position.y + GAP
	var y := clampf(_anchor.position.y, top, maxf(top, _bounds.end.y - GAP - size.y))
	global_position = Vector2(x, y)


func _label(text: String, kind: String) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.theme_type_variation = &"CaptionLabel" if kind == "note" else &"SmallLabel"
	if kind == "better" or kind == "worse":
		label.add_theme_color_override(&"font_color", BETTER if kind == "better" else WORSE)
	return label
