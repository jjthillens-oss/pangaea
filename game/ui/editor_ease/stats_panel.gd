extends VBoxContainer
## Editor-ease (docs/proposals/editor-ease.md): the creature editor's stats as a table, one stat a row: its name,
## its value now, and its change since the visit began, "▲ +0.4 m/s" (better), "▼ -3" (worse) or "+0.12 m" (a
## plain change: a longer body is a choice, not an upgrade). Better and worse are a shape and a colour, never colour
## alone (Bible 19). Under the table a legend and the selection. Every label takes its size from the game theme, so
## the table follows the text-size setting. No class_name: preload it.

const StatsRows := preload("res://game/ui/editor_ease/stats_rows.gd")

## The pointer came to rest on a stat's name (`key` as StatsRows names it), or left it.
signal stat_entered(key: String, label: Control)
signal stat_exited(key: String)

const TITLE := "STATS"
const LEGEND := "▲ better   ▼ worse   since you came in"
const SELECTED := "Selected: %s"
const NOTHING_SELECTED := "nothing"
const VALUE_COLOR := Color(0.924, 0.941, 0.97)
const NAME_COLOR := Color(0.78, 0.83, 0.9)
const BETTER := Color(0.55, 0.95, 0.6)
const WORSE := Color(1.0, 0.6, 0.52)
const PLAIN := Color(0.78, 0.83, 0.9)
## Widest change text the column keeps room for, so the table does not jump wider at the first change.
const CHANGE_SAMPLE := "▼ -00.0 m/s"

var grid: GridContainer
var legend: Label
var selected_label: Label
## Per row: [name, value, change] labels, rebuilt only when the stat names change.
var _cells: Array = []
var _keys := PackedStringArray()


func _init() -> void:
	name = "EaseStats"
	add_theme_constant_override(&"separation", 4)
	var title := _label(TITLE, NAME_COLOR)
	title.name = "Title"
	title.remove_theme_color_override(&"font_color")
	add_child(title)
	grid = GridContainer.new()
	grid.name = "Rows"
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 14)
	grid.add_theme_constant_override(&"v_separation", 1)
	add_child(grid)
	legend = _label(LEGEND, PLAIN)
	legend.name = "Legend"
	add_child(legend)
	selected_label = _label("", NAME_COLOR)
	selected_label.name = "Selected"
	selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(selected_label)


## Shows compared rows (StatsRows.compare) and the selection's words ("" or "-" for nothing).
func show_rows(rows: Array, selected: String) -> void:
	var keys := PackedStringArray()
	for row: Dictionary in rows:
		keys.append(String(row["key"]) + "|" + String(row["name"]))
	if keys != _keys:
		_rebuild(rows.size())
		_keys = keys
	for i in rows.size():
		var row: Dictionary = rows[i]
		var cells: Array = _cells[i]
		(cells[0] as Label).text = String(row["name"])
		(cells[1] as Label).text = String(row.get("text", ""))
		var change := cells[2] as Label
		change.text = String(row.get("change", ""))
		var b: Variant = StatsRows.better(row)
		change.add_theme_color_override(&"font_color", PLAIN if b == null else (BETTER if b else WORSE))
	selected_label.text = SELECTED % (NOTHING_SELECTED if selected.is_empty() or selected == "-" else selected)
	_reserve_change_column()


## Each row's "name value change" text, for tests and the review.
func row_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for cells: Array in _cells:
		out.append(("%s %s %s" % [cells[0].text, cells[1].text, cells[2].text]).strip_edges())
	return out


## The row whose stat is `key` ("length", "speed"...): {name, value, change} texts, or {} when there is none.
func row(key: String) -> Dictionary:
	for i in _keys.size():
		if _keys[i].begins_with(key + "|"):
			var cells: Array = _cells[i]
			return {"name": cells[0].text, "value": cells[1].text, "change": cells[2].text}
	return {}


func _rebuild(count: int) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	_cells.clear()
	for i in count:
		var cells := [_label("", NAME_COLOR), _label("", VALUE_COLOR), _label("", PLAIN)]
		(cells[1] as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var name_label := cells[0] as Label
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		name_label.mouse_entered.connect(func(): stat_entered.emit(_key_at(i), name_label))
		name_label.mouse_exited.connect(func(): stat_exited.emit(_key_at(i)))
		for c in cells:
			grid.add_child(c)
		_cells.append(cells)


func _key_at(i: int) -> String:
	return _keys[i].get_slice("|", 0) if i < _keys.size() else ""


func _reserve_change_column() -> void:
	if _cells.is_empty():
		return
	var cell: Label = _cells[0][2]
	var font := cell.get_theme_font(&"font")
	if font != null:
		cell.custom_minimum_size.x = font.get_string_size(CHANGE_SAMPLE, HORIZONTAL_ALIGNMENT_LEFT, -1,
				cell.get_theme_font_size(&"font_size")).x


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"CaptionLabel"
	label.add_theme_color_override(&"font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
