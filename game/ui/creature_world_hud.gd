extends Control
## The creature stage's world HUD (PROPOSED, creature-stage-plan.md section 5). It only reads the world scene; it
## never changes anything. CreatureWorld mounts it under its UI layer and calls bind(world).
##
##   top left:      the creature's name and generation, the health bar and text
##   top right:     points, with a "+N" flash after a meal
##   top center:    one notice line at a time: "Return to the nest to evolve", the death notice, "This creature
##                  needs legs to walk" (which stays while it is true)
##   bottom center: the controls, named from the bindings for the device in use (InputPrompts)
## Labels refresh at 10 Hz; the bar every frame. The HUD ignores the mouse, so the orbit drag reaches the camera.

const LABEL_REFRESH_S := 0.1
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


func refresh() -> void:
	if world == null or world.sim == null:
		return
	var p: Dictionary = world.sim.player()
	_health_text.text = "Health %d / %d" % [int(ceil(float(p["health"]))), int(ceil(float(p["max_health"])))]
	_points_text.text = "Points %d" % int(world.sim.points)


func _refresh_hints() -> void:
	_prompts_generation = InputPrompts.generation
	var pairs := [[&"move_up", "Move"], [&"creature_bite", "Bite"], [&"creature_evolve", "Evolve at the nest"]]
	var line := InputPrompts.hint_line(pairs)
	var orbit := "Right stick  Orbit" if InputPrompts.device == "pad" else "Middle drag  Orbit"
	_hint_text.text = line + "   ·   " + orbit if not line.is_empty() else orbit
