extends Node
## Editor-ease in the creature editor (docs/proposals/editor-ease.md): the HUD's usability layer, built in code by
## this one node so creature_editor_hud.gd keeps only a few one-line hooks (attach, on_setup, on_tool, on_stats,
## on_undo_redo, show_symmetry). It adds nothing to the palette's tool grid and never writes the editor's state: it
## only presents, reading the body being edited (hud.owner.working_body()) where a card needs it, guarded so the HUD
## also works alone.
## - Undo and Redo name the keys bound to ui_undo / ui_redo (Bible 19: inputs shown from the bindings); the editor's
##   other keys are hardcoded today, so their buttons say what they do in plain words (GitHub issue #207 asks the
##   editor for input actions).
## - A stats table with each stat's change since the visit began, marked ▲ better / ▼ worse (shape and colour).
## - A part card on hover with what the part does by the world's own stats rule (Bible 12, 14), in place of the
##   default tooltip, and a stat's meaning on the card when the pointer rests on its name.
## - A placement line for the chosen tool (where it goes, when it snaps to the middle line, when it comes as a pair).
## - A Symmetry toggle that shows only once the editor listens to it (GitHub issue #204); while it shows, the
##   placement line and the card follow it.
## No class_name: the HUD preloads it.

const ShortcutText := preload("res://game/ui/editor_ease/shortcut_text.gd")
const StatsRows := preload("res://game/ui/editor_ease/stats_rows.gd")
const StatsPanel := preload("res://game/ui/editor_ease/stats_panel.gd")
const PartCard := preload("res://game/ui/editor_ease/part_card.gd")
const Effects := preload("res://game/ui/editor_ease/creature_effects.gd")
const PlacementHint := preload("res://game/ui/editor_ease/placement_hint.gd")
const TooltipTheme := preload("res://game/ui/editor_ease/tooltip_theme.gd")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")

## The placement line's widest: it wraps rather than run under the palette and the stats panels beside it, and
## narrows further when larger text widens those panels.
const SNAP_HINT_WIDTH := 660.0
## The space kept between the placement line and the panels beside it, and under the title pill.
const SNAP_HINT_GAP := 16.0
## The body a card measures against when the HUD runs without an editor (the editor's own REFERENCE_BODY).
const REFERENCE_BODY := "s1_quadruped"
const UNDO_WORDS := "Undo the last change"
const REDO_WORDS := "Redo the change you undid"
const NOTHING_TO_UNDO := "Nothing to undo"
const NOTHING_TO_REDO := "Nothing to redo"
## The dock's other buttons, in plain words (no key names: those keys are not bindings yet).
const DOCK_TIPS := {
	"Delete": "Take off the selected part, bone or limb joint",
	"Insert": "Add a bone after the selected bone (or at the tail), or a joint after the selected joint",
	"Mirror": "Give the selected part or limb a twin on the other side, or take its twin away",
	"TestDrive": "Watch the creature walk, trot, run and turn as it stands",
	"Done": "Keep this design and pay its cost",
	"Back": "Clear the tool or the selection first; then leave (unsaved edits ask once)",
}
const SYMMETRY_TEXT := {true: "Symmetry: on", false: "Symmetry: off"}
const SYMMETRY_TIP := {
	true: "New parts and limbs off the middle line come as mirrored pairs",
	false: "New parts and limbs come one at a time",
}
## What each stat means, on the card when the pointer rests on its name; %s are filled from the stage tuning.
const STAT_HELP := {
	"length": "Nose to tail. A longer body is a choice, not an upgrade.",
	"mass": "From the body's volume. Heavier bodies bite harder; very heavy ones run slower.",
	"legs": "Limbs that reach the ground. A creature needs legs to walk.",
	"limbs": "Every leg and arm; a mirrored limb counts twice.",
	"parts": "Parts worn; a mirrored pair counts twice.",
	"bones": "Vertebrae and limb joints.",
	"change": "How each stat moved since you came into the editor (or started from a preset): ▲ better, ▼ worse, a bare sign for a change that is neither.",
	"counts": "Legs reach the ground (a creature needs them to walk). Limbs are every leg and arm, parts every part worn, a mirrored one counting twice. Bones are the vertebrae and limb joints.",
	"speed": "Top running speed, from the legs' length; very heavy bodies run slower.",
	"health": "From the body's mass: %s per kg.",
	"bite": "Damage per bite: each mouth, plus your largest weapons, times strength (heavier bodies bite harder). No mouth, no bite.",
	"sight": "How far it sees: %s m, plus %s m per eye, %s m at most.",
}

## The card's title for a help key that is not one stat.
const HELP_TITLES := {"counts": "Legs, limbs, parts, bones", "change": "Change"}

var hud: Control
## The stats table, in the Stats panel just before the editor's own stat text (which it hides once the lines parse).
var stats: VBoxContainer
## The part card, a child of the HUD drawn over the 3D view.
var card: PanelContainer
## The placement line above the dock, and its label.
var snap_hint: Control
var snap_label: Label
## The Symmetry toggle in the dock, after Mirror; hidden until the editor connects symmetry_toggled.
var symmetry_button: Button
## The rows the changes are measured from: the first stats after a new visit or a new editor session.
var _baseline: Array = []
var _baseline_pending := true
var _baseline_session := 0
var _can_undo := false
var _can_redo := false
## InputPrompts.generation the Undo / Redo tooltips were written for.
var _keys_generation := -1
## Read once, on the first setup: part_rules, tuning (creature_stage.json), gait, body_rules, ref_size_m.
var _data := {}
var _costs := {}
var _reference: RefCounted
var _tool := ""
var _driving := false
## The tool (or "stat:<key>") the card shows, or "" when it is hidden.
var _shown := ""


func _init() -> void:
	name = "EditorEase"


## Called once from the HUD's wire(), when its scene nodes are found.
func attach(owner_hud: Control) -> void:
	hud = owner_hud
	for panel in ["Palette", "Stats", "Bottom"]:
		TooltipTheme.apply(hud.get_node_or_null(panel) as Control)   # tooltips in glass, not Godot's default look
	for button_name in DOCK_TIPS:
		var b := hud.get_node_or_null("%" + button_name) as Control
		if b != null:
			b.tooltip_text = DOCK_TIPS[button_name]
	_write_undo_tips()
	stats = StatsPanel.new()
	var box: Node = hud.stats_text.get_parent()
	box.add_child(stats)
	box.move_child(stats, hud.stats_text.get_index())
	stats.stat_entered.connect(_on_stat_entered)
	stats.stat_exited.connect(_on_stat_exited)
	card = PartCard.new()
	card.z_index = 10
	hud.add_child(card)
	_build_snap_hint()
	_build_symmetry()


## Called at the end of the HUD's setup() (a new visit): the palette's buttons were just made again.
func on_setup(tools: Array, costs: Dictionary, _roles: Dictionary) -> void:
	_baseline_pending = true
	_costs = costs
	if _data.is_empty():
		_load_data()
	var types: Array = ["", "limb"]
	types.append_array(tools)
	for type in types:
		var b: Button = hud.tool_button(String(type))
		if b != null:
			b.mouse_entered.connect(_on_tool_entered.bind(String(type)))
			b.mouse_exited.connect(_on_tool_exited.bind(String(type)))
	hide_card()
	symmetry_button.visible = hud.has_signal("symmetry_toggled") and not hud.symmetry_toggled.get_connections().is_empty()


## Called at the end of the HUD's set_tool(): `type` is the tool now in use ("" for none).
func on_tool(type: String) -> void:
	_tool = type
	_refresh_hint()


## Called at the end of the HUD's set_stats(), with the editor's stat lines. The first lines after a new visit, or
## after the editor starts a new session (a preset, a random creature, Done), are the baseline the changes count from.
func on_stats(lines: PackedStringArray) -> void:
	var parsed := StatsRows.parse(lines)
	var session_id := _session_id()
	if _baseline_pending or session_id != _baseline_session:
		_baseline = parsed["rows"]
		_baseline_pending = false
		_baseline_session = session_id
	stats.show_rows(StatsRows.compare(parsed["rows"], _baseline), selection_words(String(parsed["selected"])))
	var any := false
	for row: Dictionary in parsed["rows"]:
		any = any or not row.get("raw", false)
	stats.visible = any
	hud.stats_text.visible = not any
	if _shown != "" and not _shown.begins_with("stat:"):
		show_card(_shown)   # the body changed under an open card


## Called at the end of the HUD's set_undo_redo().
func on_undo_redo(can_undo: bool, can_redo: bool) -> void:
	_can_undo = can_undo
	_can_redo = can_redo
	_write_undo_tips()


## Called from the HUD's set_symmetry(): shows the state without emitting.
func show_symmetry(on: bool) -> void:
	symmetry_button.set_pressed_no_signal(on)
	_write_symmetry(on)
	_refresh_hint()


## Whether a new part or limb off the middle line comes as a mirrored pair: what the Symmetry toggle shows while the
## editor listens to it, and always true otherwise (the editor mirrors today).
func mirrored() -> bool:
	return not symmetry_button.visible or symmetry_button.button_pressed


## The card for a tool ("" Select, "limb" or a part type): {title, lines}, the same the hover shows.
func card_for(type: String) -> Dictionary:
	if type == "":
		return Effects.select_card()
	var where := hint_for(type)
	if type == "limb":
		var limb: Button = hud.tool_button("limb")
		return Effects.limb_card(int(limb.get_meta("price", 0)) if limb != null else 0, where, mirrored())
	var rules: Dictionary = _data.get("part_rules", {})
	if not rules.has(type):
		return {"title": type.capitalize(), "lines": [[Effects.ROLE_UNKNOWN, ""]]}
	var body := working_body()
	if body == null:
		body = _reference_body()
	var fx := Effects.effects(body, type, rules, _data["gait"], _data["tuning"], _data["body_rules"], _data["ref_size_m"])
	var tuning: Dictionary = _data["tuning"]
	var info := {
		"price": int((_costs.get("part", {}) as Dictionary).get(type, _costs.get("part_default", 0))),
		"refund_rate": float(_costs.get("refund_rate", 0.0)),
		"locked": hud.has_method("is_locked") and bool(hud.call("is_locked", type)),
		"parts": body.parts.size(),
		"part_count_max": int(_data["body_rules"].get("part_count_max", 1 << 30)),
		"sight_max_m": float(tuning.get("sight", {}).get("max_m", 0.0)),
	}
	if tuning.has("social"):
		info["display_cap"] = int(tuning["social"]["display_cap"])
	if tuning.has("weapon"):
		info["weapon_cap"] = int(tuning["weapon"]["cap"])
	info.merge(_points())
	return Effects.card(type, rules[type], fx, info, where, mirrored())


## Shows the card for `type` beside the palette, level with its button.
func show_card(type: String) -> void:
	var c := card_for(type)
	card.show_lines(String(c["title"]), c["lines"])
	_shown = type
	var b: Button = hud.tool_button(type)
	var palette := hud.get_node_or_null("Palette") as Control
	if b == null or palette == null:
		return
	var at := b.get_global_rect()
	card.place_beside(Rect2(Vector2(palette.get_global_rect().end.x, at.position.y), Vector2(0, at.size.y)), _bounds())


func hide_card() -> void:
	card.hide()
	_shown = ""


## The placement line for a tool: "" for no tool, the limb tool's, or "<Part>: <hint>" from the part's rule.
func hint_for(type: String) -> String:
	if type == "":
		return ""
	if type == "limb":
		return PlacementHint.limb_tool(mirrored())
	var rules: Dictionary = _data.get("part_rules", {})
	return PlacementHint.creature(rules[type], mirrored()) if rules.has(type) else ""


## The selection in words from the editor's "part p3" / "vertebra v2" / "joint j4": "eye (a pair)",
## "vertebra 3 of 9 from the head", "limb joint". The editor's own words when the body cannot be read.
func selection_words(text: String) -> String:
	var kind := text.get_slice(" ", 0)
	var id := text.get_slice(" ", 1) if text.contains(" ") else ""
	var body := working_body()
	if body == null or id.is_empty():
		return text
	match kind:
		"part", "turn":
			for p in body.parts:
				if String(p["id"]) == id:
					var type := String(p["type"]).capitalize().to_lower()
					return type + " (a pair)" if bool(p["mirror"]) else type
		"vertebra":
			var i: int = body.vertebra_index(id)
			if i >= 0:
				return "vertebra %d of %d from the head" % [i + 1, body.vertebrae.size()]
		"joint":
			return "limb joint"
	return text


## The body being edited, read only: the editor's working body when the HUD sits in a live editor, else null.
func working_body() -> RefCounted:
	var editor: Node = hud.owner if hud != null else null
	if editor != null and editor.has_method("working_body") and editor.get("session") != null:
		return editor.working_body()
	return null


## What a stat means, with the stage's own numbers.
func stat_help(key: String) -> String:
	var t: Dictionary = _data.get("tuning", {})
	var text := String(STAT_HELP.get(key, ""))
	match key:
		"health":
			return text % _num(t.get("health", {}).get("per_kg", "?"))
		"sight":
			var s: Dictionary = t.get("sight", {})
			return text % [_num(s.get("base_m", "?")), _num(s.get("per_eye_m", "?")), _num(s.get("max_m", "?"))]
	return text


func _process(_delta: float) -> void:
	if hud == null:
		return
	if InputPrompts.generation != _keys_generation:
		_write_undo_tips()
	var driving: bool = hud.test_drive_button != null and hud.test_drive_button.button_pressed
	if driving != _driving:
		_driving = driving
		_refresh_hint()


## "Undo the last change (Ctrl+Z)" from the bindings for the device in use, or "Nothing to undo" while disabled.
func _write_undo_tips() -> void:
	_keys_generation = InputPrompts.generation
	if hud == null or hud.get("undo_button") == null:
		return
	hud.undo_button.tooltip_text = ShortcutText.with_binding(UNDO_WORDS, &"ui_undo") if _can_undo else NOTHING_TO_UNDO
	hud.redo_button.tooltip_text = ShortcutText.with_binding(REDO_WORDS, &"ui_redo") if _can_redo else NOTHING_TO_REDO


func _on_tool_entered(type: String) -> void:
	var b: Button = hud.tool_button(type)
	if b != null:
		b.tooltip_text = ""   # the card replaces the engine's tooltip, which would cover the tool's name
	show_card(type)


func _on_tool_exited(type: String) -> void:
	if _shown == type:
		hide_card()


func _on_stat_entered(key: String, label: Control) -> void:
	var help := stat_help(key)
	if help.is_empty():
		return
	card.show_lines(String(HELP_TITLES.get(key, key.capitalize())), [[help, ""]])
	_shown = "stat:" + key
	card.place_beside(label.get_global_rect(), _bounds())


func _on_stat_exited(key: String) -> void:
	if _shown == "stat:" + key:
		hide_card()


## The placement line: a pill under the title pill, over the sky and the creature's back, hidden for no tool and
## during the test drive. Above the dock it wrapped over the creature's feet at large text, hiding the limb tips a
## foot or hand tool is clicked on (the full words, "it can also sit on another part" included, are on the card).
func _build_snap_hint() -> void:
	snap_hint = CenterContainer.new()
	snap_hint.name = "SnapHint"
	snap_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	snap_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var pill := PanelContainer.new()
	pill.theme_type_variation = &"PillPanel"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The theme's pill is 62% opaque: over the creature its text was hard to read, so it is as opaque as the card.
	var glass := PartCard.GAME_THEME.get_stylebox(&"panel", &"PillPanel").duplicate() as StyleBox
	if glass is StyleBoxFlat:
		glass.bg_color.a = maxf(glass.bg_color.a, PartCard.OPACITY)
	pill.add_theme_stylebox_override(&"panel", glass)
	snap_label = Label.new()
	snap_label.name = "Text"
	snap_label.theme_type_variation = &"CaptionLabel"
	snap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	snap_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	snap_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	snap_label.custom_minimum_size = Vector2(SNAP_HINT_WIDTH, 0)
	pill.add_child(snap_label)
	snap_hint.add_child(pill)
	snap_hint.visible = false
	hud.add_child(snap_hint)
	var title := hud.get_node_or_null("TitleCenter") as Control
	if title != null:
		hud.move_child(snap_hint, title.get_index() + 1)
		title.item_rect_changed.connect(_place_snap_hint)
	_place_snap_hint()


## Puts the placement line just under the title pill.
func _place_snap_hint() -> void:
	var title := hud.get_node_or_null("TitleCenter/TitlePill") as Control
	if title == null or snap_hint == null:
		return
	var below := title.get_parent_control().position.y + title.position.y + title.size.y
	snap_hint.offset_top = below + SNAP_HINT_GAP / 2.0
	snap_hint.offset_bottom = snap_hint.offset_top


## The pill's words: the tool's placement hint without the "it can also sit on another part" sentence (the card
## keeps it), so the line stays short at large text.
func pill_text(type: String) -> String:
	var text := hint_for(type).trim_suffix(". " + PlacementHint.ON_PARTS)
	return "" if text.is_empty() else "%s  ·  %s" % [type.capitalize(), text]


func _refresh_hint() -> void:
	var text := pill_text(_tool)
	snap_label.text = text
	snap_label.custom_minimum_size.x = _snap_width()
	snap_hint.visible = not text.is_empty() and not _driving
	_place_snap_hint()


## The placement line's width: centred on the HUD, clear of the palette on the left and the stats on the right.
func _snap_width() -> float:
	var palette := hud.get_node_or_null("Palette") as Control
	var side := hud.get_node_or_null("Stats") as Control
	var middle := hud.get_global_rect().get_center().x
	if palette == null or side == null or palette.size.x <= 0.0 or side.size.x <= 0.0:
		return SNAP_HINT_WIDTH
	var room := minf(middle - palette.get_global_rect().end.x, side.get_global_rect().position.x - middle) - SNAP_HINT_GAP
	return clampf(2.0 * room - 48.0, 240.0, SNAP_HINT_WIDTH)   # 48: the pill's own padding


func _build_symmetry() -> void:
	symmetry_button = Button.new()
	symmetry_button.name = "Symmetry"
	symmetry_button.toggle_mode = true
	symmetry_button.focus_mode = Control.FOCUS_NONE
	symmetry_button.theme_type_variation = &"DockButton"
	symmetry_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	symmetry_button.visible = false
	symmetry_button.toggled.connect(func(on: bool):
		_write_symmetry(on)
		_refresh_hint()
		hud.symmetry_toggled.emit(on))
	_write_symmetry(false)
	var mirror := hud.get_node_or_null("%Mirror") as Control
	if mirror != null:
		mirror.get_parent().add_child(symmetry_button)
		mirror.get_parent().move_child(symmetry_button, mirror.get_index() + 1)


func _write_symmetry(on: bool) -> void:
	symmetry_button.text = SYMMETRY_TEXT[on]
	symmetry_button.tooltip_text = SYMMETRY_TIP[on]


func _load_data() -> void:
	_data = {
		"part_rules": CreatureData.part_rules(),
		"tuning": CreatureData.read_json(CreatureData.DATA_DIR + "/creature_stage.json"),
		"gait": CreatureData.gait_table(),
		"body_rules": CreatureData.rules(),
	}
	_data["ref_size_m"] = (_reference_body().bounds_m() as AABB).get_longest_axis_size()


func _reference_body() -> RefCounted:
	if _reference == null:
		_reference = CreatureData.body(REFERENCE_BODY)
	return _reference


## The points to spend and this visit's cost so far, from the editor's session; {} without one.
func _points() -> Dictionary:
	var editor: Node = hud.owner if hud != null else null
	var session: Variant = editor.get("session") if editor != null else null
	if session is Object and (session as Object).has_method("cost") and (session as Object).get("available_points") != null:
		return {"points": int(session.available_points), "cost": int(session.cost())}
	return {}


## The editor session's object id (0 without one), so a new session (preset, random, Done) resets the baseline.
func _session_id() -> int:
	var editor: Node = hud.owner if hud != null else null
	var session: Variant = editor.get("session") if editor != null else null
	return (session as Object).get_instance_id() if session is Object else 0


## The screen, for keeping the card on it; the HUD's own rect, or the viewport's when the HUD has no size yet.
func _bounds() -> Rect2:
	var r := hud.get_global_rect()
	if r.size.x > 0.0 or not hud.is_inside_tree():
		return r
	return hud.get_viewport().get_visible_rect()


static func _num(v: Variant) -> String:
	return ("%.1f" % v).trim_suffix(".0") if v is float else str(v)
