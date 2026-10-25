class_name Hud
extends Control
## The pool's heads-up display (M1 step 2). It only reads the sim and the pool's signals; it
## never changes anything. Main mounts it under the pool's UI layer and calls bind(pool).
##
##   top left:     a compact glass card (HudGlass, 420 px wide), vitals first: the energy text with a
##                 Fed / Hungry / Starving chip over a slim energy bar, the health text and slim bar
##                 (whenever health is below full, or while starving), the "Sheltered 5" chip with a
##                 ring icon while the cell is sheltered (M1 step 3); then the growth block (below)
##                 and the lineage line in caption type
##   top right:    adaptation points with a "+N" flash in a small glass pill (HudPill), and the
##                 meal, survival and region toasts as pills under it
##   top center:   the starving banner (HudBanner, the one solid warm red panel: a warning icon, words
##                 and a 1 Hz pulse), and one-off messages in a pill
##   bottom center: refusal hints in an amber-worded pill (HudPill), worded by RefusalHints, above
##                 the band the bottom edge arrows use (ThreatIndicators.band_px, about 108 px), so an
##                 arrow never covers a hint
##   bottom left:  the controls in a glass card under a "CONTROLS" caption, from the key bindings,
##                 for 30 s, or until the first meal once they have been up for 12 s
##
##   screen edges: the hurt vignette, one dark red pulse per hit on the cell (at most one per
##                 VIGNETTE_MIN_GAP_S), and the off-screen threat arrows (ThreatIndicators)
##
##   growth (S2):  in the card under the vitals, the meter ring with the size in it and the size badge
##                 ("Size 1 · about 20 µm"), and under them Growth.hint() as it is, its "(G)" naming
##                 the grow key bound now (BP-19). GrowthHud works out what they show; all three are
##                 hidden in the M1 pool, which has no growth (D-46). A ring paid out at the top gets
##                 its own toast, never the survival one (C-V8)
##   bottom right: the ladder strip (LadderStrip) in a glass card: the species near and to come, each
##                 tinted by what it is to the cell, and what the next growth changes; hidden in the pool
##   bottom center: above the refusal hints, one idea at a time (IdeaHints) in the same pill, its
##                 followed ideas kept in main's player memory (bind_memory)
##
##   endless sea (S1): a toast naming each region or rare tile the cell enters, at most once per
##                 REGION_TOAST_REPEAT_S for each, the start tile's at once; and the WorldOverlay,
##                 made in code: a cream pip at the screen edge toward the column at the generation
##                 start while it is off screen, and the distance home beside the arrow's tip;
##                 the pip and its words slide along the edge clear of the panels showing
##
## Labels refresh at 10 Hz and on every sim event; bars every frame. Every colour cue also has
## words or a shape. The whole HUD ignores the mouse, so clicks reach the swim input. The status
## card has a fixed width and the top center wraps within CENTER_MAX_W, so the banner and
## messages never run under the side panels, whatever the body, lineage or message. The look is
## the title menu's glass (game/ui/theme/pangaea_theme.tres: HudGlass cards, HudPill pills, slim
## bars, the HudBanner warning). Every text size comes from the theme, which the text size setting
## scales; the few set in code (the ring's digit, the strip's captions, the overlay's words) scale
## with the same setting.

const KIN_TOAST := "A cell like you is here. Swim into it to mate."
const MATE_TOAST := "You mated."
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
## The first meal hides the controls, but never before they have been up this long: at the spawn
## the first plankton is about 2 s away, too soon to read five lines.
const CONTROLS_MIN_S := 12.0
const BANNER_PULSE_HZ := 1.0
## At the top of each pulse the banner's panel brightens this much and its icon grows this much;
## the words never fade.
const BANNER_PULSE_GLOW := Color(1.45, 1.25, 1.15)
const BANNER_PULSE_GROW := 0.18
const STARVING_TEXT := "Starving: you are slow and losing health.\nFind food."
## The widest the starving banner and a message may be, panel included: centered, this leaves a
## gap to the status card (x 32..452 at the 1920 x 1080 base) and the points panel.
const CENTER_MAX_W := 840.0
## Step when narrowing a wrapped message so its lines come out about even.
const WRAP_STEP_PX := 8.0
## How a Label with AUTOWRAP_WORD_SMART breaks lines, with its default trim flags.
const WRAP_FLAGS := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE \
	| TextServer.BREAK_TRIM_START_EDGE_SPACES | TextServer.BREAK_TRIM_END_EDGE_SPACES
## The hurt vignette: each hit on the cell sets it to VIGNETTE_PEAK at the screen's edges and it
## fades to nothing over VIGNETTE_FALL_S; a hit sooner than VIGNETTE_MIN_GAP_S after the last
## pulse adds none. No full-screen flash and no camera shake (comfort).
const VIGNETTE_PEAK := 0.35
const VIGNETTE_FALL_S := 0.4
const VIGNETTE_MIN_GAP_S := 0.5
const CHIP_STYLES := {"Fed": &"ChipFed", "Hungry": &"ChipHungry", "Starving": &"ChipStarving"}
const ARROW_KEYS := {&"move_up": KEY_UP, &"move_left": KEY_LEFT, &"move_down": KEY_DOWN, &"move_right": KEY_RIGHT}
## A region's (or rare tile's) toast shows again only after this long, so a swim along a boundary
## does not repeat it (C-15). The window is per region.
const REGION_TOAST_REPEAT_S := 30.0
const REGION_NAMES := {"home": "Home waters", "sunlit": "Sunlit shallows", "reef": "Shell reef",
		"drift": "Open drift", "giant_husk": "The giant husk", "shell_cathedral": "The shell cathedral",
		# S3 (D-116): band 1's regions and rare places.
		"veil_garden": "Veil gardens", "warden_flat": "Warden flats", "glass_reef": "Glass reef",
		"sunbeam_well": "Sunbeam well", "fallen_lattice": "Fallen lattice", "sponge_grove": "Sponge grove",
		"shed_shell": "Shed shell"}
## Home from band 1 (D-116, V3-15): the cradle's name, toasted once a session.
const CRADLE_TOAST := "Your lineage began here"
## The idea hints read the pool's context this often (s2-view 7.5).
const IDEA_CONTEXT_S := 0.25
## The grow warning sound plays when the ring starts growing, at most once per this long (sim s).
const GROW_WARN_GAP_S := 3.0
## The growth line's look while the ring waits or grows: cream on a keyline outline.
const GROWTH_LINE_CREAM := Color("#F4EAD2")
const GROWTH_LINE_OUTLINE := 4

var pool: PoolScene

var _body := ""
var _refresh_t := 0.0
var _flash_points := 0
var _flash_t := 0.0
var _hint_t := 0.0
var _message_t := 0.0
var _controls_t := 0.0
## When the controls hide: CONTROLS_HINT_S, or sooner after the first meal (hide_controls()).
var _controls_until := CONTROLS_HINT_S
var _banner_t := 0.0
var _toasts: Array[Dictionary] = []   ## {"node": Control, "age": float}
var _vignette_t := INF                ## seconds since the last vignette pulse
var _region_shown := {}               ## region or rare kind -> sim time its toast last showed
var _cradle_toasted := false          ## the cradle's toast has shown since bind (V3-15)
var _held_region: Array = []          ## [region, rare] entered during a beat before its chord
var _growth_state := "none"           ## GrowthHud state shown last frame
var _grow_warn_at := -INF             ## sim time the grow warning last played
## The endless sea's marker overlay; null in the pool.
var world_overlay: WorldOverlay
## What idea shows in %IdeaHint (S2); a fresh one for each pool bound.
var idea_hints := IdeaHints.new()
var _memory: UserSettings
var _save_memory := Callable()
var _idea_t := 0.0
var _idea_ctx := {}

@onready var energy_text: Label = %EnergyText
@onready var state_chip: PanelContainer = %StateChip
@onready var state_text: Label = %StateText
@onready var energy_bar: ProgressBar = %EnergyBar
@onready var growth_row: Control = %GrowthRow
@onready var meter_ring: MeterRing = %MeterRing
@onready var size_badge: Label = %SizeBadge
@onready var growth_line: Label = %GrowthLine
@onready var places_line: Label = %PlacesLine
@onready var shelter_chip: PanelContainer = %ShelterChip
@onready var shelter_text: Label = %ShelterText
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
@onready var hurt_vignette: ColorRect = %HurtVignette
@onready var threat_indicators: ThreatIndicators = %ThreatIndicators
@onready var idea_hint: PanelContainer = %IdeaHint
@onready var idea_hint_text: Label = %IdeaHintText
@onready var ladder_strip: LadderStrip = %LadderStrip


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
	idea_hint.visible = false
	health_row.visible = false
	shelter_chip.visible = false
	points_flash.modulate.a = 0.0
	_set_vignette(0.0)


## Starts showing a running pool: reads its sim every frame and listens to its events.
func bind(p_pool: PoolScene) -> void:
	pool = p_pool
	pool.sim_event.connect(_on_sim_event)
	pool.refusal_hint.connect(func(text: String, _reason: String): show_hint(text))
	pool.growth_chord.connect(on_growth_chord)
	_body = Lineage.starting_body_of(pool.sim.save.genome, pool.sim.catalog)
	controls_text.text = "\n".join(controls_lines())
	first_meal_text.text = first_meal_line(pool.sim.phenotype)
	controls.visible = true
	_controls_t = 0.0
	_controls_until = CONTROLS_HINT_S
	_vignette_t = INF
	_set_vignette(0.0)
	threat_indicators.bind(pool)
	_region_shown.clear()
	_cradle_toasted = false
	_held_region = []
	_growth_state = "none"
	_grow_warn_at = -INF
	idea_hints = IdeaHints.new()
	idea_hints.bind_memory(_memory, _save_memory)
	_idea_t = 0.0
	_idea_ctx = {}
	idea_hint.visible = false
	update_growth()
	ladder_strip.bind(pool)
	if world_overlay != null:
		remove_child(world_overlay)
		world_overlay.queue_free()
		world_overlay = null
	if pool.is_endless():
		world_overlay = WorldOverlay.new(pool)
		add_child(world_overlay)
		move_child(world_overlay, 0)   # under the panels and the threat arrows
		var start := start_tile_info(pool.sim)
		_on_region(str(start.get("region", "")), str(start.get("rare", "")))
	refresh()


## The idea hints remember what the player followed in `memory` (main's player memory), calling
## `save` as each is added; none leaves them for the run.
func bind_memory(memory: UserSettings, save: Callable) -> void:
	_memory = memory
	_save_memory = save
	idea_hints.bind_memory(memory, save)


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
	health_row.visible = shows_health(state)
	var shelter := shelter_seconds(sim)
	shelter_chip.visible = shelter > 0
	_set_text(shelter_text, grace_text(shelter))
	_set_text(health_text, health_line(state))
	_set_text(lineage_text, BodyText.lineage_line(_body, GameSession.lineage_tag(sim.save.lineage_id), sim.save.genome.generation))
	_set_text(points_text, points_line(sim.save.adaptation_points))
	var growth := pool.growth()
	places_line.visible = growth != null
	if growth != null:
		var places: Vector2i = growth.places_found(pool.shown_size())
		set_places(places.x, places.y)
	starving_banner.visible = state.is_starving() and not sim.dead
	_update_bars()


## A short message at the top of the screen, such as "Your cell rested".
func show_message(text: String, seconds: float = MESSAGE_S) -> void:
	message.visible = true
	message_text.text = text
	_fit_center(message_text, message)
	message.modulate.a = 1.0
	_message_t = seconds


## The growth beat's chord (S2, 1.9 s in): the new size's message ("Size 2 · about 32 µm"); the
## badge and the ring follow pool.shown_size(), which turns to the new size at the same moment.
## Then the region entered during the beat (V3-15); at a band-up with none, the tile the cell is in
## under its new band's name, since a cell that keeps its tile coordinates (home's, at the origin)
## gets no tile_entered and would never hear that home is now the cradle.
func on_growth_chord(size: int) -> void:
	show_message(GrowthHud.badge_text(size, pool.session.world.config.ladder.get("labels", [])))
	update_growth()
	ladder_strip.refresh()
	refresh()
	if not _held_region.is_empty():
		var held := _held_region
		_held_region = []
		_on_region(held[0], held[1])
	elif pool.is_endless() and WorldConfig.band_of(size) > WorldConfig.band_of(size - 1):
		var here := start_tile_info(pool.sim)
		_on_region(str(here.get("region", "")), str(here.get("rare", "")))


## The places line (S3, D-133): "Places found at this size: 3 of 10".
func set_places(found: int, total: int) -> void:
	_set_text(places_line, GrowthHud.places_text(found, total))


## A refusal hint at the bottom of the screen.
func show_hint(text: String) -> void:
	hint_text.text = text
	hint.visible = true
	hint.modulate.a = 1.0
	_hint_t = HINT_S


## The hurt vignette's strength now, for checks: its alpha where the edge band is full (the
## shader's outer band lifts the corners a little more).
func vignette_alpha() -> float:
	return float((hurt_vignette.material as ShaderMaterial).get_shader_parameter(&"strength"))


## The screen rects of the panels showing now (status, points, toasts, banner, message, hint and
## controls): the world overlay keeps its pip and words off them.
func panel_rects() -> Array[Rect2]:
	var panels: Array = [get_node("Frame/Status"), get_node("Frame/Right/Points"), starving_banner, message, hint, controls,
		idea_hint, ladder_strip.get_node("Panel")]
	panels.append_array(toast_list.get_children())
	var out: Array[Rect2] = []
	for panel: Control in panels:
		if panel.is_visible_in_tree() and panel.modulate.a > 0.0 and panel.size != Vector2.ZERO:
			out.append(panel.get_global_rect())
	return out


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


## The health bar shows whenever health is below full, so every hit shows, or while starving.
static func shows_health(state: ActorState) -> bool:
	return state.health < state.max_health or state.is_starving()


## The hurt vignette's strength `age_s` seconds after its pulse began: VIGNETTE_PEAK at once,
## falling to 0 at VIGNETTE_FALL_S.
static func vignette_strength(age_s: float) -> float:
	if age_s < 0.0 or age_s >= VIGNETTE_FALL_S:
		return 0.0
	return VIGNETTE_PEAK * (1.0 - age_s / VIGNETTE_FALL_S)


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


## "+10 points · new place" for an "earned" event a find paid (`reason` "place" or "landmark").
static func find_toast(points: int, reason: String) -> String:
	return "+%d point%s · new %s" % [points, "" if points == 1 else "s", reason]


## The toast for entering a tile: its rare kind's name when `rare` is not "", else its region's;
## "" for a name the HUD does not know. Home from band `band` 1 is the cradle (V3-15).
static func region_toast(region: String, rare: String, band := 0) -> String:
	if rare == "" and region == WorldGen.HOME and band >= 1:
		return CRADLE_TOAST
	return str(REGION_NAMES.get(rare if rare != "" else region, ""))


## The tile the endless cell is in now: WorldGen.tile_info's {id, region, rare, ...}.
static func start_tile_info(sim: PoolSim) -> Dictionary:
	var w := sim.world
	var t := w.tile_of_local(sim.motion.position)
	return w.gen.tile_info(WorldConfig.band_of(w.size), t.x, t.y)


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


## The first meal: the controls go once they have been readable for CONTROLS_MIN_S.
func hide_controls() -> void:
	_controls_until = minf(_controls_until, maxf(_controls_t, CONTROLS_MIN_S))
	if _controls_t >= _controls_until:
		controls.visible = false


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


## How this body eats, in words that do not lean on colour alone. A body that eats only carrion is
## also told that, past the world-start pieces it may see now, more comes only from kills (D1); its
## starving tip says how to make one.
static func first_meal_line(p: Phenotype) -> String:
	var plants := p.can_eat("plant")
	var meat := p.can_eat("meat")
	if plants and meat:
		return "Eat by touching food with a mouth: drifting plankton with your filter mouth, still carrion with your jaw."
	if plants:
		return "Eat by touching drifting plankton (small green blobs) with your filter mouth."
	if meat:
		return "Eat by touching carrion (still brown chunks) with your jaw; more comes only from kills."
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
	update_growth()
	if pool.paused:
		return
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = LABEL_REFRESH_S
		refresh()
	_controls_t += delta
	if controls.visible and _controls_t >= _controls_until:
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
	_update_idea(delta)
	_message_t = _fade(message, _message_t, delta, HINT_FADE_S)
	_age_toasts(delta)
	if _vignette_t < maxf(VIGNETTE_FALL_S, VIGNETTE_MIN_GAP_S):
		_vignette_t += delta
		_set_vignette(vignette_strength(_vignette_t))


## The growth row and line, from the pool's Growth (S2; every frame, and at bind): hidden with no
## growth. The ring shows the shown size's meter, the badge that size, the line Growth.hint() with
## the bound grow key; the grow warning sounds when the ring starts growing.
func update_growth() -> void:
	var growth := pool.growth()
	growth_row.visible = growth != null
	if growth == null:
		growth_line.visible = false
		_growth_state = "none"
		return
	var config := pool.session.world.config
	var n := pool.shown_size()
	var state := GrowthHud.state_of(growth, n, pool.max_size())
	# Until the growth beat's chord the scene shows the old size, its ring still full (V-7).
	var share := 1.0 if n < pool.sim_size() else GrowthHud.share_of(growth, n)
	meter_ring.reduce_flashing = SettingsService.shared().reduce_flashing()
	meter_ring.show_ring(share, n, state)
	_set_text(size_badge, GrowthHud.badge_text(n, config.ladder.get("labels", [])))
	var hint: String = GrowthHud.hint_of(growth)
	if hint.contains("(G)"):
		hint = GrowthHud.with_grow_key(hint, grow_key_name())
	_set_text(growth_line, hint)
	growth_line.visible = hint != ""
	if state != _growth_state:
		_style_growth_line(state)
		var now := pool.sim.now()
		if state == "growing" and now - _grow_warn_at >= GROW_WARN_GAP_S:
			_grow_warn_at = now
			pool.audio.play("grow_warn")
		_growth_state = state


## The name of the input bound to grow for the device in use ("G", or a button), "" for none.
static func grow_key_name() -> String:
	var code := SettingsService.shared().first_code("grow", InputPrompts.device)
	return InputPrompts.code_name(code) if code != "" else ""


func _style_growth_line(state: String) -> void:
	if state in ["growing", "blocked", "ready"]:
		growth_line.add_theme_color_override(&"font_color", GROWTH_LINE_CREAM)
		growth_line.add_theme_color_override(&"font_outline_color", UiPalette.KEYLINE)
		growth_line.add_theme_constant_override(&"outline_size", GROWTH_LINE_OUTLINE)
	else:
		growth_line.remove_theme_color_override(&"font_color")
		growth_line.remove_theme_color_override(&"font_outline_color")
		growth_line.remove_theme_constant_override(&"outline_size")


func _update_bars() -> void:
	var state := pool.sim.state
	energy_bar.max_value = state.energy_capacity
	energy_bar.value = state.energy
	health_bar.max_value = state.max_health
	health_bar.value = state.health


## Every IDEA_CONTEXT_S the idea hints read the pool's context; the one they show sits in %IdeaHint.
## None where the sea does not grow: the M1 pool, and the sea with growth off, keep their HUD.
func _update_idea(delta: float) -> void:
	if pool.growth() == null:
		idea_hint.visible = false
		return
	_idea_t -= delta
	if _idea_t <= 0.0 or _idea_ctx.is_empty():
		_idea_t = IDEA_CONTEXT_S
		_idea_ctx = pool.hint_context()
		idea_hints.observe(_idea_ctx)
	var id := idea_hints.step(pool.sim.now())
	idea_hint.visible = id != ""
	if id != "":
		_set_text(idea_hint_text, IdeaHints.text_of(id))


func _on_sim_event(event: Dictionary) -> void:
	if pool.growth() != null:
		# A meal's ring share is the one after it: the context is read afresh for it.
		idea_hints.on_event(event, pool.hint_facts(event), pool.hint_context() if event.type == "ate" else _idea_ctx)
	match event.type:
		"ate":
			hide_controls()
			_add_toast(meal_toast(event))
			_flash(int(event.get("points", 0)))
		"earned":
			# A ring paid out at the top has its own toast (ring_paid); the points only flash (C-V8).
			match str(event.get("reason", "")):
				"ring":
					pass
				"place", "landmark":
					_add_toast(find_toast(int(event.points), str(event.reason)))
				_:
					_add_toast(survival_toast(int(event.points), pool.sim.alive_s))
			_flash(int(event.points))
		"kin_arrived":
			_add_toast(KIN_TOAST)
		"mate":
			_add_toast(MATE_TOAST)
		"ring_paid":
			_add_toast(GrowthHud.ring_paid_text(int(event.points)))
			meter_ring.sweep()
			pool.audio.play("growth_ring")
		"ring_full":
			pool.audio.play("growth_ring")
		"growth_waiting":
			pool.audio.play("refuse")   # the line itself is Growth.hint(), say "Not while something is hunting you"
		"meter_lump", "discovered":
			meter_ring.flash()
		"respawned":
			hint.visible = false
		"tile_entered":
			_on_region(str(event.get("region", "")), str(event.get("rare", "")))
		"hit":
			if event.get("target") == CreatureField.PLAYER_ID and _vignette_t >= VIGNETTE_MIN_GAP_S:
				_vignette_t = 0.0
				_set_vignette(vignette_strength(0.0))
	refresh()


## Toasts the region (or rare tile) the cell is in, unless its toast showed less than
## REGION_TOAST_REPEAT_S ago; the cradle's only once a session. During a growth beat before its chord
## the last region entered is held and toasted at the chord (V3-15: the band-up's tick changes
## every tile, so it would toast on frame 0).
func _on_region(region: String, rare: String) -> void:
	var beat := pool.growth_beat
	if beat != null and beat.active() and beat.t() < GrowthBeat.CHORD_S:
		_held_region = [region, rare]
		return
	var text := region_toast(region, rare, WorldConfig.band_of(pool.sim_size()) if pool.is_endless() else 0)
	if text == "":
		return
	if text == CRADLE_TOAST:
		if not _cradle_toasted:
			_cradle_toasted = true
			_add_toast(text)
		return
	var key := rare if rare != "" else region
	var now := pool.sim.now()
	if float(_region_shown.get(key, -INF)) + REGION_TOAST_REPEAT_S <= now:
		_region_shown[key] = now
		_add_toast(text)


func _flash(points: int) -> void:
	if points <= 0:
		return
	_flash_points += points
	_flash_t = FLASH_S
	points_flash.text = "+%d" % _flash_points


func _add_toast(text: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HudPill"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var label := Label.new()
	label.theme_type_variation = &"HudValueLabel"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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


## "Reduce flashing effects" (settings, Bible 19) keeps the pulse but at this share of its strength.
const REDUCED_FLASH_SCALE := 0.4


func _set_vignette(strength: float) -> void:
	if strength > 0.0 and SettingsService.shared().reduce_flashing():
		strength *= REDUCED_FLASH_SCALE
	(hurt_vignette.material as ShaderMaterial).set_shader_parameter(&"strength", strength)
	hurt_vignette.visible = strength > 0.0


func _set_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text


## The endless sea's marker overlay (S1, docs/s1/s1-content.md 6.11), made in code so hud.tscn is
## untouched. While the column at the generation start is off screen, a cream pip sits at the
## screen edge toward it (where an edge arrow would, ThreatIndicators.edge_point), labelled
## "Generation start"; while the arrow home shows, "Where you began · 1.4 km" sits beside its tip.
## Both are shapes and words, never colour alone. Where the pip or its words would cover a panel
## (the controls, when the column is to the west), the pip slides along the edge band to the
## nearest point clear of every panel showing, so it still sits on the column's side.
class WorldOverlay extends Control:
	const PIP_RADIUS_PX := 10.0
	const PIP_OUTLINE_PX := 3.0
	const PIP_TEXT := "Generation start"
	const ARROW_TEXT := "Where you began · %s"
	## The words' size at 100% text; font_size() scales it with the text size setting (Bible 19).
	const FONT_SIZE := 18
	const TEXT_GAP_PX := 8.0
	const TEXT_PAD_PX := 8.0              ## text stays this far inside the screen
	const OUTLINE := Color(UiPalette.KEYLINE, 0.85)
	const PANEL_GAP_PX := 6.0             ## the pip and its words keep this far off the panels
	const SLIDE_STEP_PX := 4.0            ## how finely the pip slides along the edge band

	var pool: PoolScene
	## {"at": Vector2, "text": Rect2 (where its words go)} while the pip is drawn, else empty (for
	## checks).
	var pip := {}
	## {"at": Vector2 (the arrow tip's screen point), "side": Vector2 (the way the arrow points on
	## screen, where the words go), "text": String} while the label is drawn, else empty.
	var label := {}

	func _init(p_pool: PoolScene) -> void:
		pool = p_pool
		name = "WorldOverlay"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _process(_delta: float) -> void:
		if pool != null and not pool.paused:
			refresh()

	## Works out the pip and the label on the screen `rect` (by default the viewport's), projecting
	## pool points with `project`: a Callable(Vector3) -> {"at": Vector2, "behind": bool} (by
	## default the pool camera's own projection). The pip keeps off the screen rects in `avoid` (by
	## default the HUD's panels showing now, Hud.panel_rects).
	func refresh(rect := Rect2(), project := Callable(), avoid: Variant = null) -> void:
		pip = {}
		label = {}
		var markers: WorldMarkers = pool.markers if pool != null else null
		if markers == null or not markers.visible or markers.column() == null or pool.camera == null:
			queue_redraw()
			return
		if not rect.has_area():
			rect = get_viewport_rect()
		if not project.is_valid():
			var camera: Camera3D = pool.camera
			project = func(at: Vector3) -> Dictionary:
				return {"at": camera.unproject_position(at), "behind": camera.is_position_behind(at)}
		var column: Dictionary = project.call(markers.column().position)
		if column.behind or not rect.has_point(column.at):
			if avoid == null:
				avoid = (get_parent() as Hud).panel_rects() if get_parent() is Hud else []
			var at := ThreatIndicators.edge_point(rect, column.at, column.behind, ThreatIndicators.MARGIN_PX)
			pip = place_pip(rect, at, avoid)
		if markers.arrow() != null and markers.arrow().visible:
			var tip: Dictionary = project.call(markers.arrow_tip())
			var back: Dictionary = project.call(markers.arrow().position)
			if not tip.behind and (tip.at as Vector2).is_finite():
				var side := ((tip.at as Vector2) - (back.at as Vector2)).normalized()
				label = {"at": tip.at, "side": side if side.is_finite() and side != Vector2.ZERO else Vector2.RIGHT,
					"text": ARROW_TEXT % WorldMarkers.distance_text(markers.arrow_state().distance_am)}
		queue_redraw()

	## The pip at `at` on the edge band of `rect` with its words; where either would come within
	## PANEL_GAP_PX of a rect in `avoid`, slid along the band (both ways, the nearer first) to the
	## nearest point where neither does. Where no point is clear it stays at `at`.
	func place_pip(rect: Rect2, at: Vector2, avoid: Array) -> Dictionary:
		var font := get_theme_default_font()
		var placed := _pip_at(font, rect, at)
		var band := rect.grow(-ThreatIndicators.MARGIN_PX)
		var around := 2.0 * (band.size.x + band.size.y)
		if _clear(placed, avoid) or around <= 0.0:
			return placed
		var from := _along(band, at)
		for i in range(1, ceili(around * 0.5 / SLIDE_STEP_PX) + 1):
			for way in [1.0, -1.0]:
				var moved := _pip_at(font, rect, _band_point(band, from + way * i * SLIDE_STEP_PX))
				if _clear(moved, avoid):
					return moved
		return placed

	## The pip at `at` and its words, which sit on its inner side, toward the screen centre.
	func _pip_at(font: Font, rect: Rect2, at: Vector2) -> Dictionary:
		var inward := (rect.get_center() - at).normalized()
		return {"at": at, "text": _text_rect(font, rect, at + inward * (PIP_RADIUS_PX + TEXT_GAP_PX), PIP_TEXT, inward)}

	static func _clear(placed: Dictionary, avoid: Array) -> bool:
		var reach := PIP_RADIUS_PX + PIP_OUTLINE_PX
		var disc := Rect2(placed.at - Vector2(reach, reach), Vector2(reach, reach) * 2.0)
		for r: Rect2 in avoid:
			var kept := r.grow(PANEL_GAP_PX)
			if kept.intersects(disc) or kept.intersects(placed.text):
				return false
		return true

	## How far round the edge of `band` the point `p` (on it) is, clockwise from its top left.
	static func _along(band: Rect2, p: Vector2) -> float:
		var w := band.size.x
		var h := band.size.y
		var q := p.clamp(band.position, band.end) - band.position
		var to := [q.y, w - q.x, h - q.y, q.x]   # top, right, bottom, left
		match to.find(to.min()):
			0:
				return q.x
			1:
				return w + q.y
			2:
				return w + h + (w - q.x)
		return 2.0 * w + h + (h - q.y)

	## The point `s` round the edge of `band`, clockwise from its top left (any s; it wraps).
	static func _band_point(band: Rect2, s: float) -> Vector2:
		var w := band.size.x
		var h := band.size.y
		s = fposmod(s, 2.0 * (w + h))
		if s < w:
			return band.position + Vector2(s, 0.0)
		if s < w + h:
			return band.position + Vector2(w, s - w)
		if s < 2.0 * w + h:
			return band.position + Vector2(w - (s - w - h), h)
		return band.position + Vector2(0.0, h - (s - 2.0 * w - h))

	func _draw() -> void:
		var font := get_theme_default_font()
		var rect := get_viewport_rect() if is_inside_tree() else get_rect()
		if not pip.is_empty():
			var at: Vector2 = pip.at
			draw_circle(at, PIP_RADIUS_PX + PIP_OUTLINE_PX, OUTLINE)
			draw_circle(at, PIP_RADIUS_PX, WorldMarkers.MARKER_COLOR)
			_text(font, (pip.text as Rect2).position, PIP_TEXT)
		if not label.is_empty():
			_text(font, _text_rect(font, rect, label.at, label.text, label.side).position, label.text)

	## Where `text` goes beside `anchor` on its `side`, kept inside `rect`.
	## The words' font size now: FONT_SIZE at the text size setting.
	static func font_size() -> int:
		return roundi(FONT_SIZE * int(SettingsService.shared().get_value("accessibility/text_scale")) / 100.0)

	func _text_rect(font: Font, rect: Rect2, anchor: Vector2, text: String, side: Vector2) -> Rect2:
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size())
		var top_left := anchor + Vector2(TEXT_GAP_PX if side.x >= 0.0 else -TEXT_GAP_PX - size.x, -size.y * 0.5)
		if absf(side.y) > absf(side.x):
			top_left = anchor + Vector2(-size.x * 0.5, 0.0 if side.y > 0.0 else -size.y)
		var inner := rect.grow(-TEXT_PAD_PX)
		return Rect2(top_left.clamp(inner.position, (inner.end - size).max(inner.position)), size)

	## Draws `text` outlined with its top left at `top_left`.
	func _text(font: Font, top_left: Vector2, text: String) -> void:
		var px := font_size()
		var baseline := top_left + Vector2(0.0, font.get_ascent(px))
		draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 6, OUTLINE)
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, WorldMarkers.MARKER_COLOR)
