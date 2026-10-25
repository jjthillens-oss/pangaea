extends Control
## The Aquatic stage's HUD (aquatic plan section 4, PROPOSED): small, like Spore's. Energy and health, the depth gauge
## with the body's rated depth, the zone, the nest's bearing, points and generation, one warning line for the hazard
## that matters now (text and shape as well as colour: the gauge stripes and the line says what to do), short toasts
## for events, and the lineage entry card on arrival. It reads the sim; it decides nothing.

const TOAST_S := 3.5
const CARD_S := 14.0
const WARN_COLOR := Color(1.0, 0.72, 0.25)
const DANGER_COLOR := Color(1.0, 0.38, 0.32)
const CALM_COLOR := Color(0.85, 0.97, 1.0)

var sim: AquaticSim
var energy_bar: ProgressBar
var health_bar: ProgressBar
var depth_label: Label
var depth_bar: ProgressBar
var rated_label: Label
var info_label: Label
var nest_label: Label
var warn_label: Label
var prompt_label: Label
var toast_label: Label
var help_label: Label
var card: PanelContainer
var card_label: Label

var _toasts: Array = []
var _card_left := 0.0


func setup(p_sim: AquaticSim) -> void:
	sim = p_sim
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := VBoxContainer.new()
	top.position = Vector2(36, 28)
	top.add_theme_constant_override("separation", 6)
	add_child(top)
	info_label = _label(top, 26)
	energy_bar = _bar(top, "Energy", Color(0.45, 0.9, 0.55))
	health_bar = _bar(top, "Health", Color(0.95, 0.45, 0.45))
	var gauge := VBoxContainer.new()
	add_child(gauge)
	_pin(gauge, 1.0, 0.0, -376.0, 28.0, 340.0)
	depth_label = _label(gauge, 30)
	depth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	depth_bar = ProgressBar.new()
	depth_bar.custom_minimum_size = Vector2(340, 18)
	depth_bar.show_percentage = false
	gauge.add_child(depth_bar)
	rated_label = _label(gauge, 20)
	rated_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nest_label = _label(gauge, 22)
	nest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	warn_label = _label(self, 34)
	_pin(warn_label, 0.5, 0.0, -700.0, 150.0, 1400.0)
	warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label = _label(self, 28)
	_pin(prompt_label, 0.5, 0.5, -600.0, 230.0, 1200.0)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label = _label(self, 26)
	_pin(toast_label, 0.5, 1.0, -700.0, -230.0, 1400.0)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label = _label(self, 19)
	_pin(help_label, 0.5, 1.0, -800.0, -56.0, 1600.0)
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.modulate = Color(1, 1, 1, 0.75)
	help_label.text = "W/S swim · A/D turn · Space rise · C dive · Shift burst · F bite · Q signal · E mate at the nest · Esc leave"
	card = PanelContainer.new()
	card.name = "EntryCard"
	add_child(card)
	_pin(card, 0.5, 0.5, -460.0, -300.0, 920.0)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.02, 0.1, 0.18, 0.88)
	card_style.set_corner_radius_all(18)
	card_style.set_content_margin_all(28)
	card_style.border_color = Color(0.5, 0.85, 1.0, 0.6)
	card_style.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", card_style)
	card_label = Label.new()
	card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_label.add_theme_font_size_override("font_size", 24)
	card.add_child(card_label)
	card.visible = false


## Places `c` with its top-left `x`, `y` from the anchor point (`ax`, `ay` of the screen), `width` wide.
static func _pin(c: Control, ax: float, ay: float, x: float, y: float, width: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = x
	c.offset_right = x + width
	c.offset_top = y
	c.offset_bottom = y
	c.grow_vertical = Control.GROW_DIRECTION_END


func _label(parent: Node, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.05, 0.12, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	parent.add_child(l)
	return l


func _bar(parent: Node, title: String, color: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := _label(row, 22)
	l.text = title
	l.custom_minimum_size = Vector2(110, 0)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(320, 22)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	return bar


## The lineage card on arrival: where this fish came from and what each cell trait became.
func show_entry_card(lineage: Dictionary) -> void:
	var lines := PackedStringArray()
	if bool(lineage.get("returning", false)):
		var saved: Dictionary = lineage.get("aquatic", {})
		lines.append("Your line swims again.")
		lines.append("Lineage %s, generation %d, %d points, %d places found." % [String(lineage.get("lineage_id", "")).right(6),
				int(lineage.get("generation", 1)), int(lineage.get("points", 0)), (saved.get("discovered", []) as Array).size()])
		lines.append("Back where you left the water. Any key to swim.")
		card_label.text = "\n".join(lines)
		card.visible = true
		_card_left = CARD_S
		return
	lines.append("Your lineage reaches the sea.")
	lines.append("Lineage %s, generation %d, %s." % [String(lineage.get("lineage_id", "")).right(6),
			int(lineage.get("generation", 1)), "from your saved cell" if lineage.get("source") == "save" else "a new line (no cell save found)"])
	for n in lineage.get("notes", []):
		lines.append("· " + String(n))
	var seen: PackedStringArray = lineage.get("species_seen", PackedStringArray())
	if not seen.is_empty():
		lines.append("The pool's %s are plankton-sized now: food drifting in the shallows." % ", ".join(seen.slice(0, 3)))
	if int(lineage.get("carried_points", 0)) > 0:
		lines.append("%d adaptation points carried over." % int(lineage.carried_points))
	lines.append("Eat, explore and make friends to earn points; mate with your kin at the nest to evolve. Any key to swim.")
	card_label.text = "\n".join(lines)
	card.visible = true
	_card_left = CARD_S


func hide_card() -> void:
	card.visible = false


func toast(text: String) -> void:
	_toasts.append([text, TOAST_S])
	if _toasts.size() > 3:
		_toasts.pop_front()


## One HUD frame from the sim.
func refresh(delta: float) -> void:
	var p: Dictionary = sim.player
	var s: Dictionary = p.stats
	energy_bar.max_value = float(s.energy_capacity)
	energy_bar.value = float(p.energy)
	health_bar.max_value = float(s.max_health)
	health_bar.value = maxf(0.0, float(p.health))
	var depth := -float(p.pos.y)
	var zone := sim.zone_at(p.pos)
	depth_label.text = "%s · %d m" % [zone.name, int(round(depth))]
	depth_bar.max_value = 110.0
	depth_bar.value = depth
	var w := sim.warnings()
	var pressure := float(w.pressure)
	rated_label.text = "Your body stands %d m" % int(s.rated_depth) if pressure <= 0.0 else \
			("▲ PRESSURE: rise above %d m ▲" % int(s.rated_depth))
	rated_label.modulate = CALM_COLOR if pressure <= 0.0 else (DANGER_COLOR if pressure >= 1.0 else WARN_COLOR)
	info_label.text = "Generation %d · %d points · %d meals" % [int(p.generation), sim.points, sim.meals]
	var to_nest: Vector3 = sim.nest_pos() - p.pos
	nest_label.text = "Nest %s %d m" % [_bearing(to_nest, float(p.heading)), int(Vector2(to_nest.x, to_nest.z).length())]
	var warn := ""
	var warn_color := WARN_COLOR
	match String(w.lancer):
		"investigate":
			warn = "Something is watching you: swim away or hide in an arch"
		"pursue":
			warn = "The lancer is chasing! Hide in an arch, or outswim it"
			warn_color = DANGER_COLOR
	if float(w.drifter) > 0.0:
		warn = "A huge shadow is passing: swim clear of its path"
		warn_color = DANGER_COLOR if float(w.drifter) >= 1.0 else WARN_COLOR
	if pressure > 0.0 and warn == "":
		warn = "The water presses on you: rise" if pressure < 1.0 else "The pressure is hurting you: rise now"
		warn_color = DANGER_COLOR if pressure >= 1.0 else WARN_COLOR
	warn_label.text = warn
	warn_label.modulate = warn_color
	var prompt := ""
	if p.pos.distance_to(sim.kin.pos) < float(sim.rules.world.mating.reach) + 2.0:
		prompt = "E: mate with your kin and evolve" if sim.can_mate() else \
				"Your kin waits. Eat until your energy is %d%% full to mate." % int(round(float(sim.rules.world.mating.energy_share) * 100.0))
	prompt_label.text = prompt
	var lines := PackedStringArray()
	for t in _toasts:
		t[1] = float(t[1]) - delta
		lines.append(String(t[0]))
	_toasts = _toasts.filter(func(t): return float(t[1]) > 0.0)
	toast_label.text = "\n".join(lines)
	if card.visible:
		_card_left -= delta
		if _card_left <= 0.0:
			card.visible = false


static func _bearing(to: Vector3, heading: float) -> String:
	var fwd := AquaticSim.forward_of(heading)
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() < 3.0:
		return "here"
	var angle := fwd.signed_angle_to(flat.normalized(), Vector3.UP)
	if absf(angle) < 0.5:
		return "ahead"
	if absf(angle) > 2.4:
		return "behind"
	return "◀ left" if angle > 0.0 else "right ▶"


## A player-facing line for a sim event, or "" for none.
static func event_text(e: Dictionary) -> String:
	match String(e.type):
		"found":
			return "Found: %s%s" % [e.name, (" (+%d points)" % int(e.points)) if int(e.get("points", 0)) > 0 else ""]
		"points":
			return "+%d point for your meals" % int(e.amount)
		"relation":
			return "The reef grazers are your friends now (+%d points)" % int(e.get("points", 0)) if e.standing == "friend" \
					else "The reef grazers will remember that bite"
		"signal_answered":
			if e.has("rapport"):
				return "The grazers answer your call (%d of %d)" % [int(e.rapport), int(e.needed)]
			return "The grazers answer" if e.get("standing") == "friend" else "The grazers keep away from you"
		"signal_too_fast":
			return "Wait for their answer before you call again"
		"signal_unheard":
			return "Nobody near enough to hear your call"
		"ally_warning":
			return "Your grazer friends flash a warning!"
		"lancer_gave_up":
			return "The lancer gives up" if e.why != "died" else ""
		"struck":
			return "Hit by the %s (−%d)" % [e.by, int(e.damage)]
		"stung":
			return "Your spines sting it back"
		"bite_weak":
			return "Your filter mouth cannot bite"
		"killed":
			return "You caught a fish" if e.species == "shoal" else ""
		"died":
			return "You died (%s). Back at the nest." % e.cause
		"shore":
			return "The shore. To go ashore your line needs limbs that can crawl; that comes in a later step."
		"mate_not_ready":
			return "Too hungry to mate: eat first"
		"generation":
			return "Generation %d swims" % int(e.generation)
	return ""
