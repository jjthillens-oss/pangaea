extends Control
## The creature stage's world HUD (PROPOSED, creature-stage-plan.md section 5; the glass look is the hud job's,
## docs/evidence/credit-hud/README.md). It only reads the world scene; it never changes anything. CreatureWorld mounts
## it under its UI layer and calls bind(world).
##
##   top left:      a small glass card: the creature's name and generation, the points with a "+N" flash after a
##                  meal, and the goal line ("Goal: evolve at the nest", or the evolve key once at the nest)
##   top center:    one notice pill at a time: "Return to the nest to evolve", the death notice, "This creature
##                  needs legs to walk" (which stays while it is true)
##   bottom center: the dock, a glass bar with the health text and a slim bar, and the ability chips (Bite, Sing,
##                  Evolve, each named by its bound key). The chips only show state: Evolve lights while the
##                  creature stands at the nest and Bite dims while it recharges. They never act; the keys do.
##                  Above the dock, the controls line, named from the bindings for the device in use (InputPrompts),
##                  for KEYS_HINT_S after the world opens and again after the device or a binding changes; then
##                  only the dock stays, its chips still naming the ability keys (PROPOSED).
## Labels and chips refresh at 10 Hz; the bar every frame. The HUD and every control in it ignore the mouse, so the
## orbit drag reaches the camera.

const LABEL_REFRESH_S := 0.1
const FLASH_S := 1.4
const NOTICE_S := 3.0
## How long the controls line stays up, and how long it takes to fade at the end.
const KEYS_HINT_S := 15.0
const KEYS_FADE_S := 0.5

var world: Node3D
var _refresh_t := 0.0
var _flash_t := 0.0
var _notice_t := 0.0
var _sticky_notice := ""
var _prompts_generation := -1
var _keys_t := 0.0

var _name_text: Label
var _health_text: Label
var _health_bar: ProgressBar
var _points_text: Label
var _points_flash: Label
var _notice_panel: PanelContainer
var _notice_text: Label
var _hint_text: Label
var _hint_panel: PanelContainer
var _goal_text: Label
var _abilities: HBoxContainer
## The display-only ability chips by action, rebuilt with the hint line.
var _chips := {}


func _ready() -> void:
	_resolve()


## Finds the labels once (not @onready: a headless test binds the HUD before the tree's first frame readies it).
func _resolve() -> void:
	if _name_text != null:
		return
	_name_text = %NameText
	_health_text = %HealthText
	_health_bar = %HealthBar
	_points_text = %PointsText
	_points_flash = %PointsFlash
	_notice_panel = %NoticePanel
	_notice_text = %NoticeText
	_hint_text = %HintText
	_hint_panel = %HintPanel
	_goal_text = %GoalText
	_abilities = %Abilities
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for control: Control in find_children("*", "Control", true, false):
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_points_flash.visible = false
	_notice_panel.visible = false
	_refresh_hints()


func bind(p_world: Node3D) -> void:
	_resolve()
	world = p_world
	_refresh_t = 0.0
	refresh()
	_refresh_hints()   # the bite entry depends on the body


func set_title(creature_name: String, generation: int) -> void:
	_resolve()
	_name_text.text = "%s · Generation %d" % [creature_name, generation]


## A notice for NOTICE_S seconds; with `sticky` it stays until clear_notice().
func show_notice(text: String, sticky := false) -> void:
	_resolve()
	if sticky:
		_sticky_notice = text
	_notice_text.text = text
	_notice_panel.visible = true
	_notice_t = NOTICE_S


func clear_notice() -> void:
	_sticky_notice = ""
	_notice_t = 0.0
	_notice_panel.visible = false


func flash_points(amount: int) -> void:
	_resolve()
	_points_flash.text = "%+d" % amount
	_points_flash.visible = true
	_flash_t = FLASH_S


func notice_text() -> String:
	_resolve()
	return _notice_text.text if _notice_panel.visible else ""


func _process(delta: float) -> void:
	if world == null or world.sim == null or _name_text == null:
		return
	var p: Dictionary = world.sim.player()
	_health_bar.max_value = maxf(1.0, float(p["max_health"]))
	_health_bar.value = float(p["health"])
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = LABEL_REFRESH_S
		refresh()
	if _flash_t > 0.0:
		_flash_t -= delta
		_points_flash.modulate.a = clampf(_flash_t / 0.4, 0.0, 1.0)
		if _flash_t <= 0.0:
			_points_flash.visible = false
	if _notice_t > 0.0:
		_notice_t -= delta
		if _notice_t <= 0.0:
			if _sticky_notice.is_empty():
				_notice_panel.visible = false
			else:
				_notice_text.text = _sticky_notice
	if _prompts_generation != InputPrompts.generation:
		_refresh_hints()
	if _keys_t > 0.0:
		_keys_t -= delta
		_hint_panel.modulate.a = clampf(_keys_t / KEYS_FADE_S, 0.0, 1.0)
		_hint_panel.visible = _keys_t > 0.0


func refresh() -> void:
	if world == null or world.sim == null:
		return
	var p: Dictionary = world.sim.player()
	_health_text.text = "Health %d / %d" % [int(ceil(float(p["health"]))), int(ceil(float(p["max_health"])))]
	_points_text.text = "Points %d" % int(world.sim.points)
	var at_nest := bool(p["at_nest"])
	var evolve_key := InputPrompts.names_for(&"creature_evolve")
	if at_nest and not evolve_key.is_empty():
		_goal_text.text = "At the nest: %s to evolve" % evolve_key[0]
	else:
		_goal_text.text = "Goal: evolve at the nest"
	var evolve: Button = _chips.get(&"creature_evolve")
	if evolve != null:
		evolve.set_pressed_no_signal(at_nest)
	var bite: Button = _chips.get(&"creature_bite")
	if bite != null:
		bite.disabled = int(p["cooldown"]) > 0


func _refresh_hints() -> void:
	_prompts_generation = InputPrompts.generation
	var pairs := [[&"creature_bite", "Bite"], [&"creature_social", "Sing"], [&"creature_evolve", "Evolve at the nest"], [&"ui_cancel", "Back to the editor"]]
	if world != null and world.sim != null and not bool(world.sim.player()["has_mouth"]):
		pairs.remove_at(0)   # nothing to bite with
	var line := InputPrompts.hint_line(pairs)
	var move := move_name()
	if not move.is_empty():
		line = "%s  Move" % move + ("   ·   " + line if not line.is_empty() else "")
	var orbit := "Right stick  Orbit" if InputPrompts.device == "pad" else "Middle drag  Orbit"
	_hint_text.text = line + "   ·   " + orbit if not line.is_empty() else orbit
	_keys_t = KEYS_HINT_S
	_hint_panel.visible = true
	_hint_panel.modulate.a = 1.0
	_build_chips(pairs)
	refresh()


## The dock's ability chips: one per action of the hint's pairs but the way out, named by its first binding
## ("F  Bite"). They are display only: no focus, no mouse, never pressed by the player.
func _build_chips(pairs: Array) -> void:
	for chip: Node in _abilities.get_children():
		_abilities.remove_child(chip)
		chip.queue_free()
	_chips.clear()
	for pair: Array in pairs:
		if pair[0] == &"ui_cancel":
			continue
		var names := InputPrompts.names_for(pair[0])
		if names.is_empty():
			continue
		var chip := Button.new()
		chip.name = String(pair[1]).get_slice(" ", 0)
		chip.theme_type_variation = &"HudChip"
		chip.text = "%s  %s" % [names[0], String(pair[1]).get_slice(" ", 0)]
		chip.toggle_mode = true
		chip.focus_mode = Control.FOCUS_NONE
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_abilities.add_child(chip)
		_chips[pair[0]] = chip


## The four move_* bindings of the device in use as one name ("WASD" or "Arrows" for the keys, "Left stick" for
## the pad), the direction suffixes trimmed as PauseMenu.pad_controls_lines() trims them; "" when none is bound.
static func move_name() -> String:
	var names := PackedStringArray()
	var letters := true
	for action: StringName in [&"move_up", &"move_left", &"move_down", &"move_right"]:
		var found := InputPrompts.names_for(action)
		if found.is_empty():
			continue
		var short := found[0].trim_suffix(" up").trim_suffix(" down").trim_suffix(" left").trim_suffix(" right")
		letters = letters and short.length() == 1
		if not short in names:
			names.append(short)
	if names.is_empty():
		return ""
	return "".join(names) if letters and names.size() == 4 else " / ".join(names)
