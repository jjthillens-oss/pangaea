extends Control
## The creature stage's world HUD (PROPOSED, creature-stage-plan.md section 5). It only reads the world scene; it
## never changes anything. CreatureWorld mounts it under its UI layer and calls bind(world).
##
##   top left:      the creature's name and generation, the health bar and text, and the hunger bar under it
##                  (hidden when the stage has no hunger tuning; issue #206)
##   top right:     points, with a "+N" flash after a meal
##   top center:    one notice line at a time: "Return to the nest to evolve", the death notice, "This creature
##                  needs legs to walk" (which stays while it is true)
##   bottom center: the controls, named from the bindings for the device in use (InputPrompts), on the same dark
##                  pill as the cards so they read over the field
## Labels refresh at 10 Hz; the bar every frame. The HUD ignores the mouse, so the orbit drag reaches the camera.

const LABEL_REFRESH_S := 0.1
const DISPLAY_ACTIONS := {"sing": &"creature_social", "dance": &"creature_dance", "charm": &"creature_charm",
		"pose": &"creature_pose"}
const FLASH_S := 1.4
const NOTICE_S := 3.0

var world: Node3D
var _refresh_t := 0.0
var _flash_t := 0.0
var _notice_t := 0.0
var _sticky_notice := ""
var _prompts_generation := -1

var _name_text: Label
var _health_text: Label
var _health_bar: ProgressBar
var _hunger_text: Label
var _hunger_bar: ProgressBar
var _social_text: Label
var _stance_text: Label
var _stance := "friend"
const STANCE_FRIEND_COLOR := Color(0.55, 0.9, 0.55)
const STANCE_FOE_COLOR := Color(0.96, 0.5, 0.45)
var _points_text: Label
var _points_flash: Label
var _notice_panel: PanelContainer
var _notice_text: Label
var _hint_text: Label


func _ready() -> void:
	_resolve()


## Finds the labels once (not @onready: a headless test binds the HUD before the tree's first frame readies it).
func _resolve() -> void:
	if _name_text != null:
		return
	_name_text = %NameText
	_health_text = %HealthText
	_health_bar = %HealthBar
	_hunger_text = %HungerText
	_hunger_bar = %HungerBar
	_social_text = %SocialText
	_stance_text = %StanceText
	_show_stance()
	_points_text = %PointsText
	_points_flash = %PointsFlash
	_notice_panel = %NoticePanel
	_notice_text = %NoticeText
	_hint_text = %HintText
	_points_flash.visible = false
	_notice_panel.visible = false
	_refresh_hints()


func bind(p_world: Node3D) -> void:
	_resolve()
	world = p_world
	_refresh_t = 0.0
	refresh()
	_refresh_hints()   # the bite entry depends on the body


## The friend-or-foe stance the world is in ("friend" or "foe"): the stance line and the control hints follow it.
func set_stance(stance: String) -> void:
	_resolve()
	_stance = stance
	_show_stance()
	_refresh_hints()
	refresh()


func _show_stance() -> void:
	var keys := InputPrompts.names_for(&"creature_stance")
	var key := "  [%s to switch]" % String(keys[0]) if not keys.is_empty() else ""
	var friend := _stance == "friend"
	_stance_text.text = ("Stance: FRIEND" if friend else "Stance: FOE") + key
	_stance_text.add_theme_color_override(&"font_color", STANCE_FRIEND_COLOR if friend else STANCE_FOE_COLOR)


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
	_hunger_bar.value = float(p.get("fullness", 1.0))
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


func refresh() -> void:
	if world == null or world.sim == null:
		return
	var p: Dictionary = world.sim.player()
	_health_text.text = "Health %d / %d" % [int(ceil(float(p["health"]))), int(ceil(float(p["max_health"])))]
	_points_text.text = "Points %d" % int(world.sim.points)
	var hungry := bool(p.get("hungry", false))
	_hunger_text.visible = hungry
	_hunger_bar.visible = hungry
	_hunger_text.text = hunger_label(float(p.get("fullness", 1.0)))
	var t: Dictionary = world.sim.social_target() if world.sim.has_method("social_target") else {}
	if _stance != "friend":
		t = {}
	_social_text.visible = not t.is_empty()
	if not t.is_empty():
		_social_text.text = social_label(t)


## The friend path's prompt for the creature in front of the player: what it wants and the key for it.
static func social_label(t: Dictionary) -> String:
	if bool(t.get("hostile", false)):
		return "%s won't listen: you bit it" % the(String(t["name"]))
	var wants := String(t["wants"])
	var action: StringName = DISPLAY_ACTIONS.get(wants, &"creature_social")
	var keys := InputPrompts.names_for(action)
	var key := String(keys[0]) if not keys.is_empty() else ""
	return "%s wants you to %s%s   (%d / %d)" % [the(String(t["name"])), wants.to_upper(),
			"  [%s]" % key if not key.is_empty() else "", int(t["friendship"]), int(t["needed"])]


## "a hexapod" as "The hexapod": a sentence start for the creature in front of the player.
static func the(creature_name: String) -> String:
	return "The " + creature_name.trim_prefix("a ")


## The hunger line over the bar, in words a player reads at a glance (PROPOSED thresholds).
static func hunger_label(fullness: float) -> String:
	if fullness <= 0.0:
		return "Starving! Eat fruit or meat"
	if fullness < 0.25:
		return "Hunger: very hungry"
	if fullness < 0.6:
		return "Hunger: hungry"
	return "Hunger: full"


func _refresh_hints() -> void:
	_prompts_generation = InputPrompts.generation
	var pairs := []
	if _stance == "friend":
		pairs = [[&"creature_social", "Sing"], [&"creature_dance", "Dance"], [&"creature_charm", "Charm"], [&"creature_pose", "Pose"]]
	elif world == null or world.sim == null or bool(world.sim.player()["has_mouth"]):
		pairs = [[&"creature_bite", "Bite"]]   # with no mouth there is nothing to bite with
	pairs.append_array([[&"creature_evolve", "Evolve at the nest"], [&"ui_cancel", "Back to the editor"]])
	var line := InputPrompts.hint_line(pairs)
	var move := move_name()
	if not move.is_empty():
		line = "%s  Move" % move + ("   ·   " + line if not line.is_empty() else "")
	var orbit := "Right stick  Orbit" if InputPrompts.device == "pad" else "Middle drag  Orbit"
	_hint_text.text = line + "   ·   " + orbit if not line.is_empty() else orbit


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
