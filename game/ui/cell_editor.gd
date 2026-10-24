class_name CellEditor
extends Control
## S4.4, the cell editor (docs/s4/s4-plan.md; Bible sections 5 and 24): opened by a mate (the pool's
## mate_requested), a bounded editor over EditorSession for the next generation. The palette, its
## tiles grouped by category with each part's model as the icon, adds a part where it fits; the rim
## picks a part and drags it round the body; the selected part can be mirrored, resized, upgraded
## (S4.5 part levels) or removed; undo and redo step through the edits. The 3D preview draws the
## working body as the pool will, and the stat lines show each number before and after; Test drive
## swims it round a small empty dish (TestPool, IB-03) and comes back unchanged. Mate commits
## through Lineage.reproduce (the save's genome becomes the child, its points pay the cost); Back
## leaves the body as it was. Either way `closed` reports whether a new generation was born.
##
## It only edits a working copy: the save changes only in commit(), and only when Lineage accepts.

signal closed(committed: bool)

const PREVIEW_SCENE := preload("res://game/ui/cell_preview.tscn")
## [label, Phenotype field, higher is better, format]
const STATS := [
	["Speed", "speed", true, "%.1f"],
	["Turning", "turn_rate", true, "%.1f"],
	["Health", "max_health", true, "%.0f"],
	["Bite", "bite_damage", true, "%.0f"],
	["Ram", "ram_damage", true, "%.0f"],
	["Defense", "defense", true, "%.2f"],
	["Sight", "sight", true, "%.1f"],
	["Energy use", "upkeep", false, "%.2f/s"],
	["Mass", "mass", false, "%.2f"],
]
## What each part is for, on its palette button.
const PART_ROLES := {
	"mouth_filter": "eats plants", "mouth_jaw": "eats meat, bites", "flagellum": "swims faster",
	"cilia": "turns and starts faster", "spike": "rams harder", "eye_spot": "sees farther",
	"shell_plate": "tougher", "toxin_gland": "poisons",
}
## The palette's groups, in order: [catalog category, heading].
const CATEGORIES := [["mouth", "Mouths"], ["propulsion", "Movement"], ["defense", "Defense"], ["sense", "Senses"]]
## A tile's short name where the group heading already says the rest.
const TILE_NAMES := {"mouth_filter": "Filter", "mouth_jaw": "Jaw"}
const PALETTE_PX := 300.0
const TILE_PX := 92.0
const TILE_COLUMNS := 3
const SCALE_STEP := 0.25
## The round stage in the middle: the body seen from above with the rim over it.
const DISH_PX := 780.0
## The body's half length as a share of the rim's radius: the rim's dots ring the body, and a
## long upgraded tail still fits on the dish.
const BODY_ON_RIM := 0.58
## The foods a mouth's diet means, on the Eats line (Bible section 5 previews feeding).
const DIET_NAMES := {"plant": "plants", "meat": "meat"}
const BETTER := Color(0.55, 0.95, 0.6)
const WORSE := Color(1.0, 0.55, 0.5)

var session: EditorSession
var save: SaveGame
var state: ActorState
var selected := ""                 ## the selected part's id, "" for none
var chase := {}                    ## {"speed", "name"}: the fastest hunter here; {} for none

var _preview: CellPreview
var _rim: RimView
var _stats: GridContainer
var _points: Label
var _status: Label
var _mate: Button
var _undo: Button
var _redo: Button
var _upgrade: Button
var _selected_label: Label
var _part_buttons: Array[Button] = []
var _part_info: Label
var _warning: Label
var _test_pool: TestPool


func _init() -> void:
	# Anchored here, out of the tree: inside it, set_anchors_preset keeps the offsets of a zero size.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _ready() -> void:
	_refresh()


## Opens on `p_save`'s genome with its points; `p_state` is the cell's (Lineage checks its energy).
## `chase` is the fastest chase where the cell lives (SpeciesCatalog.fastest_chase, with the
## species' "name" added); the editor warns when the new body is no faster. {} for none.
func open(p_save: SaveGame, catalog: PartCatalog, p_state: ActorState, p_chase: Dictionary = {}) -> void:
	save = p_save
	state = p_state
	chase = p_chase
	session = EditorSession.new(save.genome, catalog, save.adaptation_points)
	selected = ""
	_status.text = ""
	_refresh()
	if is_inside_tree() and not _part_buttons.is_empty():
		_part_buttons[0].grab_focus()


## Adds a part of `type_id` where it fits best (mouths at the front, propulsion at the back, the rest
## in the widest gap). Returns EditorSession's {"ok", "reason"}.
func add(type_id: String) -> Dictionary:
	var result := session.add_part(type_id, free_angle(type_id))
	_after(result)
	if result.ok:
		selected = str(session.working.parts[-1].id)
		_refresh()
	return result


func remove_selected() -> Dictionary:
	var result := session.remove_part(selected)
	if result.ok:
		selected = ""
	_after(result)
	return result


func mirror_selected() -> Dictionary:
	var result := session.mirror_part(selected)
	_after(result)
	return result


func resize_selected(step: float) -> Dictionary:
	var part := _part(selected)
	if part.is_empty():
		return {"ok": false, "reason": "no part selected"}
	var result := session.scale_part(selected, float(part.scale) + step)
	_after(result)
	return result


## Raises the selected part a level (S4.5): stronger, a little heavier and dearer to run.
func upgrade_selected() -> Dictionary:
	var result := session.upgrade_part(selected)
	_after(result)
	return result


func move_selected(angle: float) -> Dictionary:
	var result := session.move_part(selected, wrapf(angle, -PI, PI))
	_after(result)
	return result


## Mate: commits the working body through Lineage. Returns its {"ok", "errors"}.
func commit() -> Dictionary:
	var result := Lineage.reproduce(save, session, state)
	if result.ok:
		closed.emit(true)
	else:
		_status.text = "\n".join(result.errors)
	return result


func cancel() -> void:
	closed.emit(false)


func undo() -> void:
	session.undo()
	_refresh()


func redo() -> void:
	session.redo()
	_refresh()


## The angle a new part of `type_id` goes at: 0 (the front) for a mouth, PI for propulsion, else
## the middle of the widest gap between the parts on the rim.
func free_angle(type_id: String) -> float:
	match session.catalog.category_of(type_id):
		"mouth":
			return 0.0
		"propulsion":
			if _part_at(PI).is_empty():
				return PI
	var angles: Array[float] = []
	for p in session.working.parts:
		angles.append(wrapf(float(p.angle), 0.0, TAU))
	if angles.is_empty():
		return PI / 2.0
	angles.sort()
	var best_gap := -1.0
	var best := PI / 2.0
	for i in angles.size():
		var a: float = angles[i]
		var b: float = angles[(i + 1) % angles.size()] + (TAU if i == angles.size() - 1 else 0.0)
		if b - a > best_gap:
			best_gap = b - a
			best = wrapf((a + b) / 2.0, -PI, PI)
	return best


## The before and after line of each stat: [label, before, after, better (true, false or null)].
func stat_lines() -> Array:
	var p := session.preview()
	var before: Phenotype = p.current
	var after: Phenotype = p.phenotype
	var out := []
	for s in STATS:
		var a := float(before.get(s[1]))
		var b := float(after.get(s[1]))
		var better: Variant = null
		if not is_equal_approx(a, b):
			better = (b > a) == bool(s[2])
		out.append([s[0], s[3] % a, s[3] % b, better])
	out.insert(3, ["Eats", eats_text(before.diets), eats_text(after.diets), _diet_better(before.diets, after.diets)])
	return out


## What a body can eat, for the Eats line: "plants and meat", "nothing" for no mouth.
static func eats_text(diets: PackedStringArray) -> String:
	var names := []
	for diet in ["plant", "meat"]:
		if diets.has(diet):
			names.append(DIET_NAMES[diet])
	for diet in diets:
		if not DIET_NAMES.has(diet):
			names.append(diet)
	return " and ".join(names) if not names.is_empty() else "nothing"


## true when the edit only adds foods, false when it only takes some away, null when it is the
## same or trades one for another.
static func _diet_better(before: PackedStringArray, after: PackedStringArray) -> Variant:
	var gained := Array(after).filter(func(d: String) -> bool: return not before.has(d))
	var lost := Array(before).filter(func(d: String) -> bool: return not after.has(d))
	if gained.is_empty() == lost.is_empty():
		return null
	return lost.is_empty()


func _after(result: Dictionary) -> void:
	_status.text = "" if result.ok else str(result.get("reason", ""))
	_refresh()


func _part(part_id: String) -> Dictionary:
	for p in session.working.parts:
		if str(p.id) == part_id:
			return p
	return {}


func _part_at(angle: float) -> Dictionary:
	for p in session.working.parts:
		if absf(angle_difference(float(p.angle), angle)) < 0.05:
			return p
	return {}


func _refresh() -> void:
	if session == null:
		return
	var p := session.preview()
	if _preview.is_node_ready():
		# The 3D preview builds once it is in the tree (_ready refreshes again).
		_preview.show_genome(session.working, p.phenotype)
	_rim.queue_redraw()
	var c: int = p.cost
	_points.text = "%d points · this body costs %d" % [session.available_points, c] if c >= 0 \
		else "%d points · refund %d" % [session.available_points, -c]
	var errors: PackedStringArray = p.errors
	_mate.disabled = not (p.affordable and errors.is_empty())
	_mate.tooltip_text = "" if not _mate.disabled else ("Not enough points" if errors.is_empty() else errors[0])
	_warning.text = chase_warning(p.phenotype.speed)
	_undo.disabled = not session.can_undo()
	_redo.disabled = not session.can_redo()
	_show_selected()
	for child in _stats.get_children():
		_stats.remove_child(child)
		child.queue_free()
	for line in stat_lines():
		var name_label := Label.new()
		name_label.text = line[0]
		_stats.add_child(name_label)
		var value := Label.new()
		value.text = line[1] if line[1] == line[2] else "%s → %s" % [line[1], line[2]]
		if line[3] != null:
			value.add_theme_color_override(&"font_color", BETTER if line[3] else WORSE)
		_stats.add_child(value)


## Swims the working body round the test dish (IB-03); Back returns here with nothing changed.
func test_drive() -> void:
	if session == null:
		return
	_test_pool.start(session.working, session.preview().phenotype)


func _on_test_pool_left() -> void:
	if is_inside_tree():
		_mate.grab_focus()


## The rule 3 warning (S4.6): a body no faster than the fastest chase here can be caught. The editor
## allows it (heavy and slow is a fair trade), but says so. "" when the body outswims every hunter.
func chase_warning(speed: float) -> String:
	var hunter := float(chase.get("speed", 0.0))
	if hunter <= 0.0 or speed > hunter:
		return ""
	return "The %s can catch this body: it chases at %.1f, this body swims %.1f." % [
		str(chase.get("name", "hunter")), hunter, speed]


## Names the selected part and its level, and prices its next level on the Upgrade button.
func _show_selected() -> void:
	var part := _part(selected)
	var catalog := session.catalog
	if part.is_empty():
		_selected_label.text = "Pick a part on the rim"
		_upgrade.text = "Upgrade"
		_upgrade.disabled = true
		return
	var type_id := str(part.type)
	var level := Genome.level_of(part)
	_selected_label.text = "%s, level %d" % [type_id.capitalize(), level] if catalog.can_level(type_id) \
		else type_id.capitalize()
	if not catalog.can_level(type_id):
		_upgrade.text = "Upgrade"
		_upgrade.disabled = true
	elif level >= catalog.max_level:
		_upgrade.text = "Top level"
		_upgrade.disabled = true
	else:
		_upgrade.text = "Upgrade · %d" % catalog.upgrade_cost(type_id, level)
		_upgrade.disabled = false


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.09, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.text = "Your next generation"
	title.add_theme_font_size_override(&"font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override(&"separation", 24)
	column.add_child(row)

	var palette := VBoxContainer.new()
	palette.custom_minimum_size = Vector2(PALETTE_PX, 0)
	palette.add_theme_constant_override(&"separation", 6)
	row.add_child(palette)
	var palette_title := Label.new()
	palette_title.text = "Add a part"
	palette_title.add_theme_font_size_override(&"font_size", 20)
	palette.add_child(palette_title)
	_part_buttons.clear()
	var catalog := PartCatalog.load_from()
	for group: Array in palette_groups(catalog):
		var heading := Label.new()
		heading.text = group[0]
		heading.modulate = Color(1, 1, 1, 0.6)
		palette.add_child(heading)
		var grid := GridContainer.new()
		grid.columns = TILE_COLUMNS
		palette.add_child(grid)
		for type_id: String in group[1]:
			grid.add_child(_part_tile(type_id, catalog))
	_part_info = Label.new()
	_part_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_part_info.custom_minimum_size = Vector2(PALETTE_PX, 48)
	palette.add_child(_part_info)

	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(middle)
	var views := HBoxContainer.new()
	views.alignment = BoxContainer.ALIGNMENT_CENTER
	views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(views)
	# One round stage, square at its own size and centred: the dish, the body on it seen from above,
	# and the rim over the body, so each part's dot sits on the part.
	var dish := Control.new()
	dish.custom_minimum_size = Vector2(DISH_PX, DISH_PX)
	dish.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	views.add_child(dish)
	var stage := DishView.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dish.add_child(stage)
	_preview = PREVIEW_SCENE.instantiate()
	_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview.view_from_above(PartPlacement.RZ / (BODY_ON_RIM * RimView.SHARE))
	dish.add_child(_preview)
	_rim = RimView.new()
	_rim.editor = self
	_rim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dish.add_child(_rim)
	_selected_label = Label.new()
	_selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(_selected_label)
	var tools := HBoxContainer.new()
	tools.alignment = BoxContainer.ALIGNMENT_CENTER
	middle.add_child(tools)
	for spec in [["Mirror", mirror_selected], ["Smaller", resize_selected.bind(-SCALE_STEP)],
			["Bigger", resize_selected.bind(SCALE_STEP)], ["Upgrade", upgrade_selected], ["Remove", remove_selected]]:
		var b := Button.new()
		b.name = spec[0]
		b.text = spec[0]
		b.pressed.connect(spec[1])
		tools.add_child(b)
		if spec[0] == "Upgrade":
			_upgrade = b
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override(&"font_color", WORSE)
	middle.add_child(_status)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(260, 0)
	row.add_child(right)
	var stats_title := Label.new()
	stats_title.text = "Before → after"
	right.add_child(stats_title)
	_stats = GridContainer.new()
	_stats.columns = 2
	_stats.add_theme_constant_override(&"h_separation", 16)
	right.add_child(_stats)
	_warning = Label.new()
	_warning.name = "ChaseWarning"
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.custom_minimum_size = Vector2(260, 0)
	_warning.add_theme_color_override(&"font_color", WORSE)
	right.add_child(_warning)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override(&"separation", 12)
	column.add_child(bottom)
	_points = Label.new()
	_points.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_points)
	_button(bottom, "Test drive", test_drive).name = "TestDrive"
	_undo = _button(bottom, "Undo", undo)
	_redo = _button(bottom, "Redo", redo)
	_button(bottom, "Back", cancel)
	_mate = _button(bottom, "Mate", commit)
	_test_pool = TestPool.new()
	_test_pool.left.connect(_on_test_pool_left)
	add_child(_test_pool)   # last, so it covers the editor while it is shown


## The palette's groups, Spore's way: [heading, [part type ids]] by category in CATEGORIES order,
## each group's parts by cost then name. Only parts the editor offers.
static func palette_groups(catalog: PartCatalog) -> Array:
	var out := []
	for spec: Array in CATEGORIES:
		var ids: Array = catalog.parts.keys().filter(
			func(t: String) -> bool: return catalog.in_editor(t) and catalog.category_of(t) == spec[0])
		ids.sort_custom(func(a: String, b: String) -> bool:
			return [catalog.cost_of(a), a] < [catalog.cost_of(b), b])
		if not ids.is_empty():
			out.append([spec[1], ids])
	return out


## One palette tile: the part's icon over its name and cost. Hovering or focusing it names what
## the part does under the grid.
func _part_tile(type_id: String, catalog: PartCatalog) -> Button:
	var icon := PartIcon.new(type_id)
	add_child(icon)   # a viewport draws only in the tree; it is not a Control, so it takes no room
	var b := Button.new()
	b.name = "Add_" + type_id
	b.text = "%s\n%d" % [TILE_NAMES.get(type_id, type_id.capitalize()), catalog.cost_of(type_id)]
	b.icon = icon.get_texture()
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.custom_minimum_size = Vector2(TILE_PX, TILE_PX + 40)
	b.clip_text = true   # every tile the same width, however long the name
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_size_override(&"font_size", 15)
	b.tooltip_text = PART_ROLES.get(type_id, "")
	b.pressed.connect(add.bind(type_id))
	var info := "%s · %d points: %s" % [type_id.capitalize(), catalog.cost_of(type_id), PART_ROLES.get(type_id, "")]
	b.mouse_entered.connect(func() -> void: _part_info.text = info)
	b.focus_entered.connect(func() -> void: _part_info.text = info)
	_part_buttons.append(b)
	return b


func _button(parent: Control, label: String, action: Callable) -> Button:
	var b := Button.new()
	b.name = label
	b.text = label
	b.custom_minimum_size = Vector2(110, 0)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _test_pool.visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel()
	elif event.is_action_pressed(&"ui_redo"):
		get_viewport().set_input_as_handled()
		redo()
	elif event.is_action_pressed(&"ui_undo"):
		get_viewport().set_input_as_handled()
		undo()


## The round stage under the body.
class DishView:
	extends Control

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.48
		draw_circle(size / 2.0, r, Color(0.06, 0.16, 0.28, 0.92))
		draw_arc(size / 2.0, r, 0.0, TAU, 96, Color(0.45, 0.75, 0.9, 0.45), 3.0, true)


## The rim over the body seen from above, front up: each part a dot on the rim, the selected one
## ringed. A click picks the nearest part; dragging it moves it round the rim.
class RimView:
	extends Control

	const DOT := 11.0
	## The rim's radius as a share of the view's smaller side.
	const SHARE := 0.34
	var editor: CellEditor
	var _dragging := false

	func center() -> Vector2:
		return size / 2.0

	func radius() -> float:
		return minf(size.x, size.y) * SHARE

	## The point on the rim at a part angle (0 the front, at the top; positive to the right).
	func at(angle: float) -> Vector2:
		return center() + Vector2(sin(angle), -cos(angle)) * radius()

	func angle_of(p: Vector2) -> float:
		var d := p - center()
		return atan2(d.x, -d.y)

	func _draw() -> void:
		if editor == null or editor.session == null:
			return
		draw_arc(center(), radius(), 0.0, TAU, 64, Color(0.6, 0.9, 1.0, 0.8), 2.0, true)
		for p in editor.session.working.parts:
			var q := at(float(p.angle))
			var r := DOT * float(p.scale)
			draw_circle(q, r, _color(editor.session.catalog.category_of(str(p.type))))
			if str(p.id) == editor.selected:
				draw_arc(q, r + 4.0, 0.0, TAU, 24, Color.WHITE, 2.0, true)
			# One small pip outside the dot for each level above the first.
			var out := (q - center()).normalized()
			for i in Genome.level_of(p) - 1:
				draw_circle(q + out * (r + 9.0 + 7.0 * i), 2.5, Color.WHITE)

	func _color(category: String) -> Color:
		match category:
			"mouth":
				return Color(1.0, 0.8, 0.35)
			"propulsion":
				return Color(0.5, 0.85, 1.0)
			"defense":
				return Color(1.0, 0.5, 0.5)
			"sense":
				return Color(0.8, 0.6, 1.0)
		return Color.WHITE

	func _gui_input(event: InputEvent) -> void:
		if editor == null or editor.session == null:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				editor.selected = _nearest(event.position)
				_dragging = editor.selected != ""
				editor._refresh()
			else:
				_dragging = false
			accept_event()
		elif event is InputEventMouseMotion and _dragging:
			editor.move_selected(angle_of(event.position))
			accept_event()

	func _nearest(p: Vector2) -> String:
		var best := ""
		var best_d := DOT * 2.5
		for part in editor.session.working.parts:
			var d := p.distance_to(at(float(part.angle)))
			if d < best_d:
				best_d = d
				best = str(part.id)
		return best
