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
## Editor-ease (docs/proposals/editor-ease.md): one Undo takes back one action (a whole drag round the rim is
## one), and Undo, Redo and Back name the keys bound to them. The Symmetry toggle (PROPOSED, off by default and
## kept in memory only) adds, moves, sizes, upgrades and removes a part and its mirrored twin as one action. A drag
## round the rim snaps onto the middle line or opposite a part of its type, with a guide on the rim and a line
## under the dish that says what it snapped to. Hovering or focusing a palette tile opens the part card beside the
## palette: what the part is for, each stat it changes before → after (Phenotype.derive on a copy of the working
## body with the part where it would go), its count, price and where it goes. The stats panel marks each change
## ▲ better or ▼ worse with its signed size (shape and words, not colour alone), and hovering a stat's name
## explains it. The editor's panels use the game's theme (pangaea_theme.tres, the hud job's; used, not edited), so
## its text follows the text size setting like the other menus.

signal closed(committed: bool)

const PREVIEW_SCENE := preload("res://game/ui/cell_preview.tscn")
## The game's UI theme (owned by the hud job; only its type variations are used here). SettingsService scales its
## font sizes by the text size setting.
const GAME_THEME := preload("res://game/ui/theme/pangaea_theme.tres")
## A palette tile's padding: the theme's button styles with room for a square icon.
const TILE_PAD := 6.0
const UndoSteps := preload("res://game/ui/editor_ease/undo_steps.gd")
const ShortcutText := preload("res://game/ui/editor_ease/shortcut_text.gd")
const CellSymmetry := preload("res://game/ui/editor_ease/cell_symmetry.gd")
const CellEffects := preload("res://game/ui/editor_ease/cell_effects.gd")
const PartCard := preload("res://game/ui/editor_ease/part_card.gd")
const TooltipTheme := preload("res://game/ui/editor_ease/tooltip_theme.gd")
## The words on the editor's key line and its Undo and Redo tooltips; the keys come from the bindings.
const KEY_LINE := [[&"ui_undo", "undo"], [&"ui_redo", "redo"], [&"ui_cancel", "back"]]
const UNDO_TIP := "Undo the last change"
const REDO_TIP := "Redo the change you undid"
const NO_UNDO_TIP := "Nothing to undo"
const NO_REDO_TIP := "Nothing to redo"
## The line under the dish: how to move a part, and while dragging, what the drag snapped to (CellSymmetry.snap).
const RIM_HINT := "Drag a dot round the rim to move its part"
const DRAG_HINT := "Near the middle line, or opposite a part of the same kind, it snaps"
const SNAP_HINTS := {
	"centre": "Snapped to the middle line",
	"twin": "Snapped opposite the other %s",
	"pair_edge": "A mirrored pair keeps off the middle line",
	"taken": "Another part holds that spot, so it does not snap there",
}
const SYMMETRY_TIP := "When on, a part off the middle line comes with a mirrored twin, and the two move, change " \
		+ "and go together"
## The Symmetry toggle's text in each state (the state in words, not by colour alone: Bible 19).
const SYMMETRY_TEXT := {true: "Symmetry: on", false: "Symmetry: off"}
## What the editor says about a mirrored pair: the status line, a refusal, the selection line and Upgrade.
const PAIR_TEXT := {
	"no_room": "No room for its pair: %s",
	"has_pair": "It already has its pair",
	"selected": " · a mirrored pair",
	"upgrade": "Upgrade both · %d",
	"upgrade_tip": "Upgrades the part and its twin: 2 × %d points",
}
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
## What each stat means, on the part card when the pointer rests on its name in the stats panel. "%s" is the stat's
## cap from the catalog (PartCatalog.caps) where it has one.
const STAT_HELP := {
	"Speed": "Top swimming speed, in metres a second. Extra mass slows it. At most %s.",
	"Turning": "How fast it turns, in radians a second. At most %s.",
	"Health": "How much damage it takes before it dies.",
	"Eats": "What its mouths feed on: a filter mouth eats plants, a jaw eats meat.",
	"Bite": "Damage of each bite from a jaw.",
	"Ram": "Damage its spikes do when it rams into something.",
	"Defense": "Share of each hit its shell plates block, up to %s.",
	"Sight": "How far it notices food and danger, in metres. At most %s.",
	"Energy use": "Energy burned each second at rest; lower lasts longer between meals.",
	"Mass": "How heavy it is. Mass slows speed and acceleration, and makes moving cost more energy.",
}
## The stats panel's legend: the marks mean better and worse, whichever way the number goes.
const STAT_LEGEND := "▲ better   ▼ worse"
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
## The round stage in the middle: the body seen from above with the rim over it. Its smallest side: it grows,
## square, to fill the room the other rows leave (larger text leaves less).
const DISH_PX := 480.0
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
## Editor-ease symmetry (PROPOSED default off): parts off the middle line are added, moved, sized, upgraded and
## removed with their mirrored twin. Kept in memory only, never in the save or the settings.
var symmetry := false
var _gesture := false              ## true from begin_gesture() to end_gesture() (a drag round the rim)
var _gesture_twin := ""            ## the selected part's twin when the gesture began ("" for none), kept for its length

var _preview: CellPreview
var _rim: RimView
var _stats: GridContainer
var _stats_panel: PanelContainer
var _stat_cells: Array = []        ## per stat_lines() row: [name, before, after, change] Labels, built once
var _points: Label
var _status: Label
var _mate: Button
var _undo: Button
var _redo: Button
var _upgrade: Button
var _selected_label: Label
var _part_buttons: Array[Button] = []
var _palette: Control
var _card: PartCard                ## the palette's part card (editor-ease), shown beside the hovered tile
var _card_type := ""               ## the part the card shows; "" while it is hidden
var _quiet_focus := false          ## true while open() focuses the first tile, so the card waits for the player
var _warning: Label
var _test_pool: TestPool
var _steps := UndoSteps.new()      ## the session steps in each action, so one Undo takes back one action
var _keys: Label                   ## the key line: the bindings of undo, redo and back
var _keys_generation := -1         ## InputPrompts.generation the key line was written for
var _symmetry_button: Button
var _rim_hint: Label               ## under the dish: RIM_HINT, or what a drag snapped to


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
	_steps.reset()
	selected = ""
	_status.text = ""
	_refresh()
	if is_inside_tree() and not _part_buttons.is_empty():
		_quiet_focus = true
		_part_buttons[0].grab_focus()
		_quiet_focus = false


## Adds a part of `type_id` where it fits best (mouths at the front, propulsion at the back, the rest
## in the widest gap). Returns EditorSession's {"ok", "reason"}.
## With symmetry on, a part off the middle line comes with its mirrored twin, both one Undo step; when the twin does
## not fit, the part stays single and the status line says why.
func add(type_id: String) -> Dictionary:
	var angle := place_angle(type_id)
	var pair := symmetry and not CellSymmetry.is_central(angle)
	var opened := _open_group(pair)
	var result := session.add_part(type_id, angle)
	_steps.note(result.ok)
	var twin := {}
	if result.ok and pair:
		twin = session.mirror_part(str(session.working.parts[-1].id))
		_steps.note(twin.ok)
	_close_group(opened)
	_after(result)
	if result.ok:
		selected = str(result.part_id)
		if pair and not twin.ok:
			_status.text = PAIR_TEXT.no_room % twin.reason
		_refresh()
	return result


## Removes the selected part (and with symmetry on, its twin).
func remove_selected() -> Dictionary:
	var twin := selected_twin()
	var opened := _open_group(not twin.is_empty())
	var result := session.remove_part(selected)
	_steps.note(result.ok)
	if result.ok and not twin.is_empty():
		_steps.note(session.remove_part(str(twin.id)).ok)
	_close_group(opened)
	if result.ok:
		selected = ""
	_after(result)
	return result


## Adds a mirrored copy of the selected part. With symmetry on, a part that already has its twin is refused.
func mirror_selected() -> Dictionary:
	if not selected_twin().is_empty():
		var refused := {"ok": false, "reason": PAIR_TEXT.has_pair}
		_after(refused)
		return refused
	var result := session.mirror_part(selected)
	_steps.note(result.ok)
	_after(result)
	return result


func resize_selected(step: float) -> Dictionary:
	var part := _part(selected)
	if part.is_empty():
		return {"ok": false, "reason": "no part selected"}
	var twin := selected_twin()
	var new_scale := float(part.scale) + step
	var opened := _open_group(not twin.is_empty())
	var result := session.scale_part(selected, new_scale)
	_steps.note(result.ok)
	if result.ok and not twin.is_empty():
		_steps.note(session.scale_part(str(twin.id), new_scale).ok)
	_close_group(opened)
	_after(result)
	return result


## Raises the selected part a level (S4.5): stronger, a little heavier and dearer to run. With symmetry on, its twin
## too, at twice the price.
func upgrade_selected() -> Dictionary:
	var twin := selected_twin()
	var opened := _open_group(not twin.is_empty())
	var result := session.upgrade_part(selected)
	_steps.note(result.ok)
	if result.ok and not twin.is_empty():
		_steps.note(session.upgrade_part(str(twin.id)).ok)
	_close_group(opened)
	_after(result)
	return result


## Moves the selected part to `angle`. With symmetry on, its twin goes to the mirrored angle, and the pair keeps
## off the middle line (CellSymmetry.off_line).
func move_selected(angle: float) -> Dictionary:
	var twin := selected_twin()
	var target := wrapf(angle, -PI, PI)
	if not twin.is_empty():
		target = CellSymmetry.off_line(target, float(_part(selected).angle))
	var opened := _open_group(not twin.is_empty())
	var result := session.move_part(selected, target)
	_steps.note(result.ok)
	if result.ok and not twin.is_empty():
		_steps.note(session.move_part(str(twin.id), CellSymmetry.mirrored(target)).ok)
	_close_group(opened)
	_after(result)
	return result


## Turns symmetry on or off (in memory only). The toggle shows the state without acting on it again.
func set_symmetry(on: bool) -> void:
	symmetry = on
	if _symmetry_button != null:
		_symmetry_button.set_pressed_no_signal(on)
		_symmetry_button.text = SYMMETRY_TEXT[on]
	_refresh()


## The selected part's mirrored twin while symmetry is on (CellSymmetry.twin_of); {} otherwise. During a gesture it
## is the twin the part had when the gesture began: a drag that snaps a single part opposite another of its kind does
## not take that part along (they count as a pair from the release on).
func selected_twin() -> Dictionary:
	if not symmetry or session == null:
		return {}
	if _gesture:
		return {} if _gesture_twin == "" else _part(_gesture_twin)
	return CellSymmetry.twin_of(session.working.parts, _part(selected))


## Opens an Undo group for an action of several session steps, unless one is open already (a drag). Returns
## whether it opened one, for _close_group().
func _open_group(several: bool) -> bool:
	if not several or _steps.in_group():
		return false
	_steps.begin_group()
	return true


func _close_group(opened: bool) -> void:
	if opened:
		_steps.end_group()


## A gesture (a drag round the rim) starts: every op until end_gesture() is one Undo step.
func begin_gesture() -> void:
	var twin := selected_twin()
	_gesture_twin = "" if twin.is_empty() else str(twin.id)
	_gesture = true
	_steps.begin_group()
	_rim_hint.text = DRAG_HINT


func end_gesture() -> void:
	_gesture = false
	_gesture_twin = ""
	_steps.end_group()
	_rim_hint.text = RIM_HINT
	_rim_hint.modulate.a = 0.6


## A drag round the rim reached `angle`: moves the selected part there, snapped (CellSymmetry.snap; a part with its
## twin keeps off the middle line instead), and says on the hint line what it snapped to. move_selected() itself
## stays exact. Returns the snap {"angle", "kind", "of"}; kind "" for none.
func drag_to(angle: float) -> Dictionary:
	var part := _part(selected)
	if part.is_empty():
		return {"angle": angle, "kind": "", "of": ""}
	var twin := selected_twin()
	var keep := [] if twin.is_empty() else [str(twin.id)]
	var snap := CellSymmetry.snap(angle, session.working.parts, selected, keep, _rim.clear_angle())
	if not twin.is_empty():
		var kept := CellSymmetry.off_line(angle, float(part.angle))
		var moved := not is_equal_approx(kept, wrapf(angle, -PI, PI))
		snap = {"angle": kept, "kind": "pair_edge" if moved else "", "of": ""}
	move_selected(snap.angle)
	_rim_hint.modulate.a = 0.6 if str(snap.kind) == "" else 1.0   # a snap reads brighter; the words say which
	match str(snap.kind):
		"":
			_rim_hint.text = DRAG_HINT
		"twin":
			_rim_hint.text = SNAP_HINTS.twin % str(part.type).capitalize()
		_:
			_rim_hint.text = SNAP_HINTS[snap.kind]
	return snap


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


## Takes back the last action: one add, change or removal, or a whole drag round the rim.
func undo() -> void:
	_rim.stop_drag()   # an Undo in mid-drag ends the drag: the next move is not part of the undone one
	_steps.undo(session)
	_refresh()


func redo() -> void:
	_rim.stop_drag()
	_steps.redo(session)
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


## Where add() puts a part of `type_id`: free_angle(), or with symmetry on, a mouth at the front, a tail at the back
## when it is free, and anything else where both it and its twin have room: the middle of the widest gap on one
## side, with the parts of both sides folded onto it.
func place_angle(type_id: String) -> float:
	if not symmetry:
		return free_angle(type_id)
	match session.catalog.category_of(type_id):
		"mouth":
			return 0.0
		"propulsion":
			if _part_at(PI).is_empty():
				return PI
	var folded: Array[float] = [0.0, PI]
	for p in session.working.parts:
		folded.append(absf(wrapf(float(p.angle), -PI, PI)))
	folded.sort()
	var best_gap := -1.0
	var best := PI / 2.0
	for i in folded.size() - 1:
		if folded[i + 1] - folded[i] > best_gap:
			best_gap = folded[i + 1] - folded[i]
			best = (folded[i] + folded[i + 1]) / 2.0
	return best


## The before and after line of each stat: [label, before, after, better (true, false or null)].
func stat_lines() -> Array:
	var p := session.preview()
	return stat_rows(p.current, p.phenotype)


## Keeps room in the stats panel for the after and change columns while they are empty, so the panel (and the dish
## beside it) does not jump wider at the first change. Sized from the label font, so it follows the text size.
func _reserve_stat_columns() -> void:
	for spec: Array in [[2, "→ 0.00/s"], [3, "▼ +0.00"]]:
		var cell: Label = _stat_cells[0][spec[0]]
		var font := cell.get_theme_font(&"font")
		cell.custom_minimum_size.x = font.get_string_size(spec[1], HORIZONTAL_ALIGNMENT_LEFT, -1,
			cell.get_theme_font_size(&"font_size")).x


## A stats row's change column: ▲ for better or ▼ for worse, then the signed change of the shown numbers in the
## stat's format ("▲ +1.5", "▼ +0.15"); just the mark for the Eats line; "" when the row shows no change.
static func change_mark(line: Array) -> String:
	if line[1] == line[2]:
		return ""
	var mark: String = {true: "▲", false: "▼"}.get(line[3], "")
	for spec: Array in STATS:
		if spec[0] == line[0]:
			var number := "%+" + str(spec[3]).substr(1, str(spec[3]).find("f"))
			return ("%s %s" % [mark, number % (str(line[2]).to_float() - str(line[1]).to_float())]).strip_edges()
	return mark


## What a stat means, for its row's card: STAT_HELP with the catalog's cap filled in.
static func stat_help(label: String, catalog: PartCatalog) -> String:
	var text: String = STAT_HELP.get(label, "")
	if not text.contains("%s"):
		return text
	for spec: Array in STATS:
		if spec[0] == label and catalog.caps.has(spec[1]):
			var cap := float(catalog.caps[spec[1]])
			var shown := "%d%%" % roundi(cap * 100.0) if spec[1] == "defense" else str(spec[3]).get_slice("/", 0) % cap
			return text % shown
	return text.get_slice(" At most", 0).get_slice(", up to", 0)


## stat_lines() for any two bodies: the stats panel compares the parent with the working body, the part card the
## working body with the part added (CellEffects).
static func stat_rows(before: Phenotype, after: Phenotype) -> Array:
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
	if _card_type != "" and not _card_type.begins_with("stat:"):
		show_part_card(_card_type)   # the numbers follow the body
	_undo.disabled = not session.can_undo()
	_redo.disabled = not session.can_redo()
	_show_bindings()
	_show_selected()
	_reserve_stat_columns()
	var rows := stat_lines()
	for i in rows.size():
		var line: Array = rows[i]
		var cells: Array = _stat_cells[i]
		var changed: bool = line[1] != line[2]
		cells[0].text = line[0]
		cells[1].text = line[1]
		cells[2].text = "→ %s" % line[2] if changed else ""
		cells[3].text = change_mark(line)
		for cell: Label in [cells[2], cells[3]]:
			if changed and line[3] != null:
				cell.add_theme_color_override(&"font_color", BETTER if line[3] else WORSE)
			else:
				cell.remove_theme_color_override(&"font_color")


## Opens the part card for the tile of `type_id`, beside the palette at the tile's height: what adding it would do
## where add() would put it (with its twin when Symmetry is on).
func show_part_card(type_id: String) -> void:
	_card_type = type_id
	if session == null:
		return
	var angle := place_angle(type_id)
	var angles := [angle]
	if symmetry and not CellSymmetry.is_central(angle):
		angles.append(CellSymmetry.mirrored(angle))
	var card := CellEffects.card(session, type_id, angles, PART_ROLES.get(type_id, ""))
	_card.show_lines(card.title, card.lines)
	var tile := find_child("Add_" + type_id, true, false) as Control
	if tile != null and _palette != null:
		var tile_rect := tile.get_global_rect()
		var beside := Rect2(Vector2(_palette.get_global_rect().end.x, tile_rect.position.y),
				Vector2(0, tile_rect.size.y))
		_card.place_beside(beside, get_global_rect())


## Explains the stat named on `cell` on the card, to the left of the stats panel at the row's height.
func _show_stat_help(cell: Label) -> void:
	if session == null or cell.text.is_empty():
		return
	_card_type = "stat:" + cell.text
	_card.show_lines(cell.text, [[stat_help(cell.text, session.catalog), ""]])
	var panel := _stats_panel.get_global_rect()
	var at := Rect2(Vector2(panel.position.x, cell.get_global_rect().position.y), Vector2(panel.size.x, 0))
	_card.place_beside(at, get_global_rect())


## Closes the part card if it shows `type_id`.
func hide_part_card(type_id: String) -> void:
	if _card_type == type_id:
		_card_type = ""
		_card.hide()


## The part card (editor-ease), for tests and the shot script.
func part_card() -> Control:
	return _card


## The key line and the Undo and Redo tooltips, from the bindings of the device in use (Bible 19).
func _show_bindings() -> void:
	_keys_generation = InputPrompts.generation
	_keys.text = ShortcutText.hint_line(KEY_LINE)
	_undo.tooltip_text = ShortcutText.with_binding(UNDO_TIP, &"ui_undo") if not _undo.disabled else NO_UNDO_TIP
	_redo.tooltip_text = ShortcutText.with_binding(REDO_TIP, &"ui_redo") if not _redo.disabled else NO_REDO_TIP


func _process(_delta: float) -> void:
	if session != null and visible and InputPrompts.generation != _keys_generation:
		_show_bindings()   # the player switched between keys and a controller


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


## Names the selected part and its level, and prices its next level on the Upgrade button (with symmetry on and a
## twin, both parts' price: the pair upgrades together).
func _show_selected() -> void:
	var part := _part(selected)
	var catalog := session.catalog
	_upgrade.tooltip_text = ""
	if part.is_empty():
		_selected_label.text = "Pick a part on the rim"
		_upgrade.text = "Upgrade"
		_upgrade.disabled = true
		return
	var type_id := str(part.type)
	var level := Genome.level_of(part)
	var paired := not selected_twin().is_empty()
	_selected_label.text = "%s, level %d" % [type_id.capitalize(), level] if catalog.can_level(type_id) \
		else type_id.capitalize()
	if paired:
		_selected_label.text += PAIR_TEXT.selected
	if not catalog.can_level(type_id):
		_upgrade.text = "Upgrade"
		_upgrade.disabled = true
	elif level >= catalog.max_level:
		_upgrade.text = "Top level"
		_upgrade.disabled = true
	elif paired:
		var each := catalog.upgrade_cost(type_id, level)
		_upgrade.text = PAIR_TEXT.upgrade % (2 * each)
		_upgrade.tooltip_text = PAIR_TEXT.upgrade_tip % each
		_upgrade.disabled = false
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
	margin.theme = GAME_THEME   # the editor's panels only: the dim and the test dish keep their own look
	theme = TooltipTheme.get_theme()   # tooltips in glass, not Godot's default look (pangaea_theme has none)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.text = "Your next generation"
	title.theme_type_variation = &"LargeLabel"
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
	palette.add_child(palette_title)
	_part_buttons.clear()
	var catalog := PartCatalog.load_from()
	for group: Array in palette_groups(catalog):
		var heading := Label.new()
		heading.text = group[0]
		heading.theme_type_variation = &"CaptionLabel"
		palette.add_child(heading)
		var grid := GridContainer.new()
		grid.columns = TILE_COLUMNS
		palette.add_child(grid)
		for type_id: String in group[1]:
			grid.add_child(_part_tile(type_id, catalog))
	_palette = palette

	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(middle)
	var views := AspectRatioContainer.new()   # keeps the dish square, as large as the room allows
	views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	views.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(views)
	# One round stage, square and centred: the dish, the body on it seen from above, and the rim over the
	# body, so each part's dot sits on the part.
	var dish := Control.new()
	dish.custom_minimum_size = Vector2(DISH_PX, DISH_PX)
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
	_rim_hint = Label.new()
	_rim_hint.name = "RimHint"
	_rim_hint.text = RIM_HINT
	_rim_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rim_hint.theme_type_variation = &"SmallLabel"
	_rim_hint.modulate = Color(1, 1, 1, 0.6)
	middle.add_child(_rim_hint)
	_selected_label = Label.new()
	_selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selected_label.theme_type_variation = &"SmallLabel"
	middle.add_child(_selected_label)
	var tools := HFlowContainer.new()   # wraps onto a second line when large text leaves no room
	tools.alignment = FlowContainer.ALIGNMENT_CENTER
	tools.add_theme_constant_override(&"h_separation", 8)
	tools.add_theme_constant_override(&"v_separation", 8)
	middle.add_child(tools)
	_symmetry_button = Button.new()
	_symmetry_button.name = "Symmetry"
	_symmetry_button.theme_type_variation = &"DockButton"
	_symmetry_button.toggle_mode = true
	_symmetry_button.text = SYMMETRY_TEXT[false]   # the state in words, not by colour alone (Bible 19)
	_symmetry_button.tooltip_text = SYMMETRY_TIP
	_symmetry_button.toggled.connect(set_symmetry)
	tools.add_child(_symmetry_button)
	tools.add_child(VSeparator.new())
	for spec in [["Mirror", mirror_selected], ["Smaller", resize_selected.bind(-SCALE_STEP)],
			["Bigger", resize_selected.bind(SCALE_STEP)], ["Upgrade", upgrade_selected], ["Remove", remove_selected]]:
		var b := Button.new()
		b.name = spec[0]
		b.text = spec[0]
		b.theme_type_variation = &"DockButton"
		b.pressed.connect(spec[1])
		tools.add_child(b)
		if spec[0] == "Upgrade":
			_upgrade = b
	_status = Label.new()
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.theme_type_variation = &"SmallLabel"
	_status.add_theme_color_override(&"font_color", WORSE)
	middle.add_child(_status)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(260, 0)
	right.add_theme_constant_override(&"separation", 12)
	row.add_child(right)
	_stats_panel = PanelContainer.new()
	_stats_panel.name = "StatsPanel"
	_stats_panel.theme_type_variation = &"GlassPanel"
	right.add_child(_stats_panel)
	var stats_box := VBoxContainer.new()
	_stats_panel.add_child(stats_box)
	var stats_title := Label.new()
	stats_title.text = "Before → after"
	stats_title.uppercase = true
	stats_title.theme_type_variation = &"CaptionLabel"
	stats_box.add_child(stats_title)
	_stats = GridContainer.new()
	_stats.columns = 4
	_stats.add_theme_constant_override(&"h_separation", 14)
	stats_box.add_child(_stats)
	_stat_cells.clear()
	for i in STATS.size() + 1:   # the stats and the Eats line
		var cells := []
		for c in 4:
			var cell := Label.new()
			cell.theme_type_variation = &"SmallLabel"
			_stats.add_child(cell)
			cells.append(cell)
		var name_cell: Label = cells[0]
		name_cell.mouse_filter = Control.MOUSE_FILTER_STOP   # its name explains it on the card
		name_cell.mouse_entered.connect(_show_stat_help.bind(name_cell))
		name_cell.mouse_exited.connect(func() -> void: hide_part_card("stat:" + name_cell.text))
		_stat_cells.append(cells)
	var legend := Label.new()
	legend.name = "StatLegend"
	legend.text = STAT_LEGEND
	legend.theme_type_variation = &"CaptionLabel"
	stats_box.add_child(legend)
	_warning = Label.new()
	_warning.name = "ChaseWarning"
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.custom_minimum_size = Vector2(260, 0)
	_warning.theme_type_variation = &"SmallLabel"
	_warning.add_theme_color_override(&"font_color", WORSE)
	right.add_child(_warning)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override(&"separation", 12)
	column.add_child(bottom)
	_points = Label.new()
	_points.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_points.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_points.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # two lines rather than off the screen at large text
	bottom.add_child(_points)
	_keys = Label.new()
	_keys.name = "KeyLine"
	_keys.theme_type_variation = &"SmallLabel"
	_keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_keys)
	_button(bottom, "Test drive", test_drive).name = "TestDrive"
	_undo = _button(bottom, "Undo", undo)
	_redo = _button(bottom, "Redo", redo)
	_button(bottom, "Back", cancel)
	_mate = _button(bottom, "Mate", commit)
	_mate.theme_type_variation = &"PrimaryButton"   # the step that makes the next generation stands out
	_card = PartCard.new()
	add_child(_card)   # over the editor, under the test dish
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


## One palette tile: the part's icon over its name and cost. Hovering or focusing it opens the part card (in place of
## a plain tooltip, which would cover the tile's name).
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
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(state, _tile_style(state))
	b.pressed.connect(add.bind(type_id))
	b.mouse_entered.connect(show_part_card.bind(type_id))
	b.focus_entered.connect(func() -> void:
		if not _quiet_focus:
			show_part_card(type_id))
	b.mouse_exited.connect(hide_part_card.bind(type_id))
	b.focus_exited.connect(hide_part_card.bind(type_id))
	_part_buttons.append(b)
	return b


## The theme's button style for `state` with a tile's small padding, so the icon keeps the tile's width.
static func _tile_style(state: String) -> StyleBox:
	var style := GAME_THEME.get_stylebox(state, &"Button").duplicate() as StyleBox
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, TILE_PAD)
	return style


func _button(parent: Control, label: String, action: Callable) -> Button:
	var b := Button.new()
	b.name = label
	b.text = label
	b.theme_type_variation = &"DockButton"
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
	## The snapped spot's diamond, centre to corner: clear of the selected part's ring.
	const DIAMOND := 26.0
	var editor: CellEditor
	var _dragging := false
	var _snap := {}   ## the last drag_to() result while dragging, for the guide

	func center() -> Vector2:
		return size / 2.0

	func radius() -> float:
		return minf(size.x, size.y) * SHARE

	## The point on the rim at a part angle (0 the front, at the top; positive to the right).
	func at(angle: float) -> Vector2:
		return center() + Vector2(sin(angle), -cos(angle)) * radius()

	## The angle two dots of a part's usual size take on the rim, centre to centre: a snap target closer than this
	## to another part is taken (CellSymmetry.snap). CellSymmetry.CLEAR_RAD until the view has a size.
	func clear_angle() -> float:
		var r := radius()
		return CellSymmetry.CLEAR_RAD if r < 1.0 else maxf(2.0 * DOT / r, CellSymmetry.CLEAR_RAD / 2.0)

	func angle_of(p: Vector2) -> float:
		var d := p - center()
		return atan2(d.x, -d.y)

	func _draw() -> void:
		if editor == null or editor.session == null:
			return
		draw_arc(center(), radius(), 0.0, TAU, 64, Color(0.6, 0.9, 1.0, 0.8), 2.0, true)
		var snap_kind := str(_snap.get("kind", "")) if _dragging else ""
		if snap_kind == "centre":
			# Snapped onto the middle line: a bright solid line and a diamond at the spot (shape, not colour alone).
			draw_line(at(0.0) + Vector2(0, -24), at(PI) + Vector2(0, 24), Color(1, 1, 1, 0.9), 3.0, true)
			_diamond(at(float(_snap.angle)), DIAMOND, Color.WHITE)
		elif _dragging:
			# The middle line, faint, while a part is dragged: it snaps onto it.
			draw_line(at(0.0) + Vector2(0, -24), at(PI) + Vector2(0, 24), Color(0.8, 0.95, 1.0, 0.3), 1.5, true)
		elif editor.symmetry:
			# The mirror line, front to back, dashed: the parts on one side mirror the other's.
			draw_dashed_line(at(0.0) + Vector2(0, -24), at(PI) + Vector2(0, 24), Color(0.8, 0.95, 1.0, 0.5), 2.0, 10.0)
		if snap_kind == "twin":
			# Snapped opposite a part of its kind: a dashed ring on that part and a dashed chord across to it.
			var other := editor._part(str(_snap.of))
			if not other.is_empty():
				var o := at(float(other.angle))
				_dashed_ring(o, DOT * float(other.scale) + 7.0, Color.WHITE)
				draw_dashed_line(at(float(_snap.angle)), o, Color(1, 1, 1, 0.7), 2.0, 8.0)
				_diamond(at(float(_snap.angle)), DIAMOND, Color.WHITE)
		var twin := editor.selected_twin()
		for p in editor.session.working.parts:
			var q := at(float(p.angle))
			var r := DOT * float(p.scale)
			draw_circle(q, r, _color(editor.session.catalog.category_of(str(p.type))))
			if str(p.id) == editor.selected:
				draw_arc(q, r + 4.0, 0.0, TAU, 24, Color.WHITE, 2.0, true)
			elif not twin.is_empty() and str(p.id) == str(twin.id):
				_dashed_ring(q, r + 4.0, Color.WHITE)   # the selected part's twin: dashed, not by colour alone
			# One small pip outside the dot for each level above the first.
			var out := (q - center()).normalized()
			for i in Genome.level_of(p) - 1:
				draw_circle(q + out * (r + 9.0 + 7.0 * i), 2.5, Color.WHITE)

	## A diamond outline round `q`, `r` from its centre to each corner.
	func _diamond(q: Vector2, r: float, color: Color) -> void:
		var pts := PackedVector2Array([q + Vector2(0, -r), q + Vector2(r, 0), q + Vector2(0, r), q + Vector2(-r, 0),
				q + Vector2(0, -r)])
		draw_polyline(pts, color, 2.0, true)

	## A ring of short dashes round `q`.
	func _dashed_ring(q: Vector2, r: float, color: Color) -> void:
		for i in 8:
			var a := TAU * i / 8.0
			draw_arc(q, r, a, a + TAU / 16.0, 4, color, 2.0, true)

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
				stop_drag()   # a press with no release before it (focus lost mid-drag) closes that drag first
				editor.selected = _nearest(event.position)
				_dragging = editor.selected != ""
				if _dragging:
					editor.begin_gesture()   # the whole drag is one Undo step
				editor._refresh()
			else:
				stop_drag()
			accept_event()
		elif event is InputEventMouseMotion and _dragging:
			_snap = editor.drag_to(angle_of(event.position))   # snapped onto the middle line or opposite a twin
			queue_redraw()
			accept_event()

	## Ends a drag in progress, closing its Undo step.
	func stop_drag() -> void:
		if _dragging:
			_dragging = false
			_snap = {}
			editor.end_gesture()
			queue_redraw()

	## The part whose dot is nearest `p`, within reach; "" for none. On a tie (dots on top of each other) the selected
	## part keeps the pick, or else the one drawn last, on top.
	func _nearest(p: Vector2) -> String:
		var best := ""
		var best_d := DOT * 2.5
		for part in editor.session.working.parts:
			var d := p.distance_to(at(float(part.angle)))
			if d >= DOT * 2.5:
				continue
			var tie := absf(d - best_d) <= 0.5
			if (d < best_d and not tie) or (tie and (best == "" or best != editor.selected)):
				best_d = d
				best = str(part.id)
		return best
