class_name Hud
extends Control
## The pool's heads-up display (M1 step 2). It only reads the sim and the pool's signals; it
## never changes anything. Main mounts it under the pool's UI layer and calls bind(pool).
##
##   top left:     energy bar and text with a Fed / Hungry / Starving chip, the health bar (only
##                 while hurt or starving) and the lineage line
##   top right:    adaptation points with a "+N" flash, and meal and survival toasts
##   top center:   the starving banner (icon, words and a 1 Hz pulse), and one-off messages
##   bottom center: refusal hints, worded by RefusalHints
##   bottom left:  the controls, from the key bindings, until the first meal or for 30 s
##
## Labels refresh at 10 Hz and on every sim event; bars every frame. Every colour cue also has
## words or a shape. The whole HUD ignores the mouse, so clicks reach the swim input. The status
## panel has a fixed width and the top center wraps within CENTER_MAX_W, so the banner and
## messages never run under the side panels, whatever the body, lineage or message.

const LABEL_REFRESH_S := 0.1
const HUNGRY_SHARE := 0.25          ## below this share of capacity the chip says "Hungry"
const FLASH_S := 1.4
const TOAST_S := 2.6
const TOAST_FADE_S := 0.5
const TOAST_MAX := 4
const HINT_S := 2.8
const HINT_FADE_S := 0.4
const MESSAGE_S := 5.0
const CONTROLS_HINT_S := 30.0
const BANNER_PULSE_HZ := 1.0
## At the top of each pulse the banner's panel brightens this much and its icon grows this much;
## the words never fade.
const BANNER_PULSE_GLOW := Color(1.45, 1.25, 1.15)
const BANNER_PULSE_GROW := 0.18
const STARVING_TEXT := "Starving: you are slow and losing health.\nFind food."
## The widest the starving banner and a message may be, panel included: centered, this leaves a
## gap to the status panel (x 32..512 at the 1920 x 1080 base) and the points panel.
const CENTER_MAX_W := 840.0
## Step when narrowing a wrapped message so its lines come out about even.
const WRAP_STEP_PX := 8.0
## How a Label with AUTOWRAP_WORD_SMART breaks lines, with its default trim flags.
const WRAP_FLAGS := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE \
	| TextServer.BREAK_TRIM_START_EDGE_SPACES | TextServer.BREAK_TRIM_END_EDGE_SPACES
const CHIP_STYLES := {"Fed": &"ChipFed", "Hungry": &"ChipHungry", "Starving": &"ChipStarving"}
const ARROW_KEYS := {&"move_up": KEY_UP, &"move_left": KEY_LEFT, &"move_down": KEY_DOWN, &"move_right": KEY_RIGHT}

var pool: PoolScene

var _body := ""
var _refresh_t := 0.0
var _flash_points := 0
var _flash_t := 0.0
var _hint_t := 0.0
var _message_t := 0.0
var _controls_t := 0.0
var _banner_t := 0.0
var _toasts: Array[Dictionary] = []   ## {"node": Control, "age": float}

@onready var energy_text: Label = %EnergyText
@onready var state_chip: PanelContainer = %StateChip
@onready var state_text: Label = %StateText
@onready var energy_bar: ProgressBar = %EnergyBar
@onready var health_row: Control = %HealthRow
@onready var health_text: Label = %HealthText
@onready var health_bar: ProgressBar = %HealthBar
@onready var lineage_text: Label = %LineageText
@onready var points_text: Label = %PointsText
@onready var points_flash: Label = %PointsFlash
@onready var toast_list: VBoxContainer = %Toasts
@onready var starving_banner: PanelContainer = %StarvingBanner
@onready var banner_text: Label = %BannerText
@onready var _warning_icon: Control = %Warning
@onready var message: PanelContainer = %Message
@onready var message_text: Label = %MessageText
@onready var hint: PanelContainer = %Hint
@onready var hint_text: Label = %HintText
@onready var controls: PanelContainer = %Controls
@onready var controls_text: Label = %ControlsText
@onready var first_meal_text: Label = %FirstMealText


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for node in find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_text.text = STARVING_TEXT
	_fit_center(banner_text, starving_banner)
	_warning_icon.pivot_offset = _warning_icon.custom_minimum_size * 0.5
	starving_banner.visible = false
	message.visible = false
	hint.visible = false
	health_row.visible = false
	points_flash.modulate.a = 0.0


## Starts showing a running pool: reads its sim every frame and listens to its events.
func bind(p_pool: PoolScene) -> void:
	pool = p_pool
	pool.sim_event.connect(_on_sim_event)
	pool.refusal_hint.connect(func(text: String, _reason: String): show_hint(text))
	_body = Lineage.starting_body_of(pool.sim.save.genome, pool.sim.catalog)
	controls_text.text = "\n".join(controls_lines())
	first_meal_text.text = first_meal_line(pool.sim.phenotype)
	controls.visible = true
	_controls_t = 0.0
	refresh()


## Brings every label and bar up to date now (they otherwise refresh at 10 Hz).
func refresh() -> void:
	if pool == null or pool.sim == null:
		return
	var sim := pool.sim
	var state := sim.state
	_set_text(energy_text, energy_line(state))
	var chip := state_name(state)
	_set_text(state_text, chip)
	state_chip.theme_type_variation = CHIP_STYLES[chip]
	health_row.visible = state.health < state.max_health or state.is_starving()
	_set_text(health_text, health_line(state))
	_set_text(lineage_text, BodyText.lineage_line(_body, GameSession.lineage_tag(sim.save.lineage_id), sim.save.genome.generation))
	_set_text(points_text, points_line(sim.save.adaptation_points))
	starving_banner.visible = state.is_starving() and not sim.dead
	_update_bars()


## A short message at the top of the screen, such as "Your cell rested".
func show_message(text: String, seconds: float = MESSAGE_S) -> void:
	message.visible = true
	message_text.text = text
	_fit_center(message_text, message)
	message.modulate.a = 1.0
	_message_t = seconds


## A refusal hint at the bottom of the screen.
func show_hint(text: String) -> void:
	hint_text.text = text
	hint.visible = true
	hint.modulate.a = 1.0
	_hint_t = HINT_S


## The toasts on screen now, oldest first (for checks).
func toast_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for t in _toasts:
		out.append((t.node.get_child(0) as Label).text)
	return out


# Formatters. Tests and the scene smoke compare the labels against these.

## "Energy 62 / 100". Only a starving cell shows 0.
static func energy_line(state: ActorState) -> String:
	return "Energy %d / %d" % [_shown(state.energy), roundi(state.energy_capacity)]


static func health_line(state: ActorState) -> String:
	return "Health %d / %d" % [_shown(state.health), roundi(state.max_health)]


## "Fed", "Hungry" (below a quarter of capacity) or "Starving".
static func state_name(state: ActorState) -> String:
	if state.is_starving():
		return "Starving"
	if state.energy < state.energy_capacity * HUNGRY_SHARE:
		return "Hungry"
	return "Fed"


static func points_line(points: int) -> String:
	return "%d adaptation point%s" % [points, "" if points == 1 else "s"]


## "+8 energy · +1 point" for an "ate" event.
static func meal_toast(event: Dictionary) -> String:
	var text := "+%d energy" % roundi(float(event.get("absorbed", 0.0)))
	var points := int(event.get("points", 0))
	if points > 0:
		text += " · +%d point%s" % [points, "" if points == 1 else "s"]
	return text


## "+1 point · survived 30 s" for an "earned" survival event.
static func survival_toast(points: int, alive_s: float) -> String:
	return "+%d point%s · survived %d s" % [points, "" if points == 1 else "s", roundi(alive_s)]


## "Sheltered 5": the shelter chip's words, in whole seconds of shelter left.
static func grace_text(seconds: int) -> String:
	return "Sheltered %d" % seconds


## Whole seconds of shelter the living cell has left, rounded up; 0 when it is not sheltered (or
## the pool has no creatures, so no shelter).
static func shelter_seconds(sim: PoolSim) -> int:
	if sim == null or not sim.is_sheltered():
		return 0
	return ceili((sim.grace_until - sim.tick) / float(CreatureBrain.TICKS_PER_SECOND))


## What Continue restores: energy and health restart (they are not saved).
static func rested_line(state: ActorState) -> String:
	var health := "full" if state.health >= state.max_health else "%d%%" % roundi(100.0 * state.health / state.max_health)
	return "Your cell rested: Energy %d%%, Health %s" % [roundi(100.0 * state.energy / state.energy_capacity), health]


## The controls, named from the current key bindings.
static func controls_lines() -> PackedStringArray:
	var keys := PackedStringArray()
	var arrows := true
	for action: StringName in ARROW_KEYS:
		keys.append(KeyLabel.for_action(action))
		var has_arrow := false
		for event in InputMap.action_get_events(action):
			if event is InputEventKey and event.physical_keycode == ARROW_KEYS[action]:
				has_arrow = true
		arrows = arrows and has_arrow
	return PackedStringArray([
		"Swim: %s%s" % [" ".join(keys), " or arrow keys" if arrows else ""],
		"Swim to the cursor: hold %s" % " or ".join(KeyLabel.all_for_action(&"swim_to_cursor")),
		"Zoom: %s / %s" % [" or ".join(KeyLabel.all_for_action(&"zoom_in")), " or ".join(KeyLabel.all_for_action(&"zoom_out"))],
		"Pause: %s" % " or ".join(KeyLabel.all_for_action(&"pause")),
		"Full screen: %s" % " or ".join(KeyLabel.all_for_action(&"toggle_fullscreen")),
	])


## How this body eats, in words that do not lean on colour alone.
static func first_meal_line(p: Phenotype) -> String:
	var plants := p.can_eat("plant")
	var meat := p.can_eat("meat")
	if plants and meat:
		return "Eat by touching food with a mouth: drifting plankton with your filter mouth, still carrion with your jaw."
	if plants:
		return "Eat by touching drifting plankton (small green blobs) with your filter mouth."
	if meat:
		return "Eat by touching carrion (still brown chunks) with your jaw."
	return "This body has no mouth that can eat."


## The width a wrapping label needs for `text`: its own width when that is at most `max_w`, else
## the narrowest width that wraps into as few lines as `max_w` does with every break at a space,
## so a path is not split and the last line is more than one word when the words allow it.
static func wrap_width(text: String, font: Font, font_size: int, max_w: float) -> float:
	var para := TextParagraph.new()
	para.break_flags = WRAP_FLAGS
	para.add_string(text, font, font_size)
	var natural := para.get_size().x
	if natural < max_w:
		return minf(ceilf(natural) + 1.0, max_w)
	para.width = max_w
	var lines := para.get_line_count()
	var best := max_w
	var w := max_w - WRAP_STEP_PX
	while w > WRAP_STEP_PX:
		para.width = w
		if para.get_line_count() > lines:
			break
		if breaks_at_spaces(para, text):
			best = w
		w -= WRAP_STEP_PX
	return best


## True when every line of `para` (shaped from `text`) ends at a space or a line break.
static func breaks_at_spaces(para: TextParagraph, text: String) -> bool:
	for i in para.get_line_count() - 1:
		var end := para.get_line_range(i).y
		if not ((end > 0 and text[end - 1] in " \n") or (end < text.length() and text[end] in " \n")):
			return false
	return true


static func _shown(value: float) -> int:
	var shown := roundi(value)
	return 1 if shown == 0 and value > 0.0 else shown


func _process(delta: float) -> void:
	if pool == null or pool.sim == null:
		return
	_update_bars()
	if pool.paused:
		return
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = LABEL_REFRESH_S
		refresh()
	_controls_t += delta
	if controls.visible and _controls_t >= CONTROLS_HINT_S:
		controls.visible = false
	_banner_t = fmod(_banner_t + delta, 1.0 / BANNER_PULSE_HZ)
	var pulse := 0.5 - 0.5 * cos(_banner_t * BANNER_PULSE_HZ * TAU)
	starving_banner.self_modulate = Color.WHITE.lerp(BANNER_PULSE_GLOW, pulse)
	_warning_icon.scale = Vector2.ONE * (1.0 + BANNER_PULSE_GROW * pulse)
	_flash_t = maxf(_flash_t - delta, 0.0)
	points_flash.modulate.a = clampf(_flash_t / (FLASH_S * 0.4), 0.0, 1.0)
	if _flash_t <= 0.0:
		_flash_points = 0
	_hint_t = _fade(hint, _hint_t, delta, HINT_FADE_S)
	_message_t = _fade(message, _message_t, delta, HINT_FADE_S)
	_age_toasts(delta)


func _update_bars() -> void:
	var state := pool.sim.state
	energy_bar.max_value = state.energy_capacity
	energy_bar.value = state.energy
	health_bar.max_value = state.max_health
	health_bar.value = state.health


func _on_sim_event(event: Dictionary) -> void:
	match event.type:
		"ate":
			controls.visible = false
			_add_toast(meal_toast(event))
			_flash(int(event.get("points", 0)))
		"earned":
			_add_toast(survival_toast(int(event.points), pool.sim.alive_s))
			_flash(int(event.points))
		"respawned":
			hint.visible = false
	refresh()


func _flash(points: int) -> void:
	if points <= 0:
		return
	_flash_points += points
	_flash_t = FLASH_S
	points_flash.text = "+%d" % _flash_points


func _add_toast(text: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ToastPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var label := Label.new()
	label.text = text
	panel.add_child(label)
	toast_list.add_child(panel)
	_toasts.append({"node": panel, "age": 0.0})
	while _toasts.size() > TOAST_MAX:
		_toasts.pop_front().node.queue_free()


func _age_toasts(delta: float) -> void:
	for t in _toasts:
		t.age += delta
		t.node.modulate.a = clampf((TOAST_S - t.age) / TOAST_FADE_S, 0.0, 1.0)
	while not _toasts.is_empty() and _toasts[0].age >= TOAST_S:
		_toasts.pop_front().node.queue_free()


## Counts a timed panel down and fades it over its last `fade_s`; hides it at zero.
func _fade(panel: Control, t: float, delta: float, fade_s: float) -> float:
	if not panel.visible:
		return 0.0
	t -= delta
	panel.modulate.a = clampf(t / fade_s, 0.0, 1.0)
	if t <= 0.0:
		panel.visible = false
	return t


## Sizes a top-center label so its panel is at most CENTER_MAX_W wide; longer text wraps.
func _fit_center(label: Label, panel: Control) -> void:
	label.custom_minimum_size.x = 0.0
	var chrome := panel.get_combined_minimum_size().x - label.get_combined_minimum_size().x
	label.custom_minimum_size.x = wrap_width(label.text, label.get_theme_font(&"font"),
		label.get_theme_font_size(&"font_size"), CENTER_MAX_W - chrome)


func _set_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text
