extends VBoxContainer
## Editor-ease (docs/proposals/editor-ease.md): the creature editor's stats as a table, one stat a row: its name,
## its value now, and its change since the visit began, "▲ +0.4 m/s" (better), "▼ -3" (worse) or "+0.12 m" (a
## plain change: a longer body is a choice, not an upgrade). Better and worse are a shape and a colour, never colour
## alone (Bible 19). The body's counts (legs, limbs, parts, bones) share two lines, "4 legs · 4 limbs" and
## "10 parts · 26 bones (+1)", so the panel still fits at the largest text size. Under them a legend and the selection. Every
## label takes its size from the game theme, so the table follows the text-size setting. No class_name: preload it.

const StatsRows := preload("res://game/ui/editor_ease/stats_rows.gd")

## The pointer came to rest on a stat's name (`key` as StatsRows names it, COUNTS_KEY for the counts line or
## CHANGE_KEY for the CHANGE header), or left it.
signal stat_entered(key: String, label: Control)
signal stat_exited(key: String)

const TITLE := "STATS"
const CHANGE_TITLE := "CHANGE"
const LEGEND := "▲ better   ▼ worse"
const SELECTED := "Selected: %s"
const NOTHING_SELECTED := "nothing"
## The stats shown on the counts line instead of a row each, in order.
const COUNT_KEYS := ["legs", "limbs", "parts", "bones"]
const COUNTS_KEY := "counts"
## The CHANGE header's key for stat_entered: the card says what the column counts from.
const CHANGE_KEY := "change"
const VALUE_COLOR := Color(0.924, 0.941, 0.97)
const NAME_COLOR := Color(0.78, 0.83, 0.9)
const BETTER := Color(0.55, 0.95, 0.6)
const WORSE := Color(1.0, 0.6, 0.52)
const PLAIN := Color(0.78, 0.83, 0.9)
## Widest change text the column keeps room for, so the table does not jump wider at the first change.
const CHANGE_SAMPLE := "▼ -00.0 m/s"

var grid: GridContainer
var counts_label: Label
var legend: Label
var selected_label: Label
## Per table row: [name, value, change] labels, rebuilt only when the stat names change.
var _cells: Array = []
var _keys := PackedStringArray()
var _change_title: Label
## The last rows shown, by key, for row().
var _rows := {}


func _init() -> void:
	name = "EaseStats"
	add_theme_constant_override(&"separation", 4)
	grid = GridContainer.new()
	grid.name = "Rows"
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 14)
	grid.add_theme_constant_override(&"v_separation", 1)
	add_child(grid)
	counts_label = _label("", VALUE_COLOR)
	counts_label.name = "Counts"
	counts_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	counts_label.mouse_filter = Control.MOUSE_FILTER_PASS
	counts_label.mouse_entered.connect(func(): stat_entered.emit(COUNTS_KEY, counts_label))
	counts_label.mouse_exited.connect(func(): stat_exited.emit(COUNTS_KEY))
	add_child(counts_label)
	legend = _label(LEGEND, PLAIN)
	legend.name = "Legend"
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(legend)
	selected_label = _label("", NAME_COLOR)
	selected_label.name = "Selected"
	selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(selected_label)


## Shows compared rows (StatsRows.compare) and the selection's words ("" or "-" for nothing).
func show_rows(rows: Array, selected: String) -> void:
	var table: Array = []
	var counts := PackedStringArray()
	_rows.clear()
	for row: Dictionary in rows:
		_rows[String(row["key"])] = row
		if COUNT_KEYS.has(row["key"]):
			var change := String(row.get("change", ""))
			counts.append("%s %s%s" % [row["text"], String(row["name"]).to_lower(), "" if change.is_empty() else " (%s)" % change])
		else:
			table.append(row)
	var keys := PackedStringArray()
	for row: Dictionary in table:
		keys.append(String(row["key"]) + "|" + String(row["name"]))
	if keys != _keys:
		_rebuild(table.size())
		_keys = keys
	for i in table.size():
		var row: Dictionary = table[i]
		var cells: Array = _cells[i]
		(cells[0] as Label).text = String(row["name"])
		(cells[1] as Label).text = String(row.get("text", ""))
		var change := cells[2] as Label
		change.text = String(row.get("change", ""))
		var b: Variant = StatsRows.better(row)
		change.add_theme_color_override(&"font_color", PLAIN if b == null else (BETTER if b else WORSE))
	var pairs := PackedStringArray()
	for i in range(0, counts.size(), 2):
		pairs.append(" · ".join(counts.slice(i, i + 2)))
	counts_label.text = "\n".join(pairs)
	counts_label.visible = not counts.is_empty()
	selected_label.text = SELECTED % (NOTHING_SELECTED if selected.is_empty() or selected == "-" else selected)
	_reserve_space()


## Each table row's "name value change" text, then the counts line when there is one; for tests and the review.
func row_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for cells: Array in _cells:
		out.append(("%s %s %s" % [cells[0].text, cells[1].text, cells[2].text]).strip_edges())
	if counts_label.visible:
		out.append(counts_label.text)
	return out


## The stat `key` ("length", "speed", "legs"...) as shown: {name, value, change}, or {} when there is none.
func row(key: String) -> Dictionary:
	if not _rows.has(key):
		return {}
	var r: Dictionary = _rows[key]
	return {"name": String(r["name"]), "value": String(r.get("text", "")), "change": String(r.get("change", ""))}


func _rebuild(count: int) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	_cells.clear()
	# The header row: the title over the names, CHANGE over the change column.
	var title := _label(TITLE, NAME_COLOR)
	title.remove_theme_color_override(&"font_color")
	_change_title = _label(CHANGE_TITLE, NAME_COLOR)
	_change_title.remove_theme_color_override(&"font_color")
	_change_title.mouse_filter = Control.MOUSE_FILTER_PASS
	var header := _change_title
	header.mouse_entered.connect(func(): stat_entered.emit(CHANGE_KEY, header))
	header.mouse_exited.connect(func(): stat_exited.emit(CHANGE_KEY))
	for c in [title, _label("", NAME_COLOR), _change_title]:
		grid.add_child(c)
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


## Keeps room for the widest change and for two lines of counts, so the panel does not jump at the first change.
func _reserve_space() -> void:
	if _change_title == null:
		return
	var font := _change_title.get_theme_font(&"font")
	if font != null:
		var px := _change_title.get_theme_font_size(&"font_size")
		_change_title.custom_minimum_size.x = font.get_string_size(CHANGE_SAMPLE, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		counts_label.custom_minimum_size.y = 2.0 * font.get_height(px)   # two lines even while one wraps


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"CaptionLabel"
	label.add_theme_color_override(&"font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
