extends Control
## The Aquatic stage's fin and tail editor (aquatic plan section 6, PROPOSED), opened by mating at the nest. Spore's
## layout: the choices on the left (Tail, Fins, Body, Senses), the offspring turning on a plinth on the right, and
## the swim stats before and after with the points it costs. Every number comes from AquaticBody, the rules play
## uses, and the test swim (aquatic-r2: Spore's test drive, the Bible §12 test space) is AquaticSim.trial(), the
## same sim swum on fixed courses, so the preview cannot disagree with the water. Done commits the next generation;
## Cancel keeps the parent. The mouth and colour are inherited and stay (shown, not offered).

signal closed(committed: bool, body: Dictionary, cost: int)

const FishView := preload("res://game/scenes/aquatic/fish_view.gd")
const PLINTH := "res://assets/export/creature_editor_room.glb"
## The tail choices' names (aquatic-r2). No tail is simply "fast" or "nimble": the stats below the fish show each one's
## tradeoff, from the same rules the water uses.
const TAIL_NAMES := {"fluke": "Fluke", "ribbon": "Ribbon", "lunate": "Lunate", "paddle": "Paddle", "whip": "Whip"}
## What each tail trades (aquatic-r2, PROPOSED wording; the numbers behind it are in docs/stages/aquatic-plan.md
## section 4 and tests/test_aquatic_sim.gd checks the roles): the caption under the tail row and each button's tooltip.
const TAIL_ROLES := {
	"fluke": "Fluke, the all-rounder: good speed and a good dash at a middling cost, but it turns wide at full strength.",
	"ribbon": "Ribbon: strong even when small and nimble at speed, but costly to swim.",
	"lunate": "Lunate, the cruiser: the fastest at strength 2 and up and cheap to swim, but slow to dash and wide in the turn.",
	"paddle": "Paddle, the sprinter: the best dash and tight turns, but draggy and the costliest to swim.",
	"whip": "Whip, the thrifty one: the cheapest to swim and the tightest turn, but slow.",
}
## [stat key, name, unit, higher is better]
const STAT_ROWS := [
	["top_speed", "Top speed", "m/s", true],
	["burst_speed", "Burst", "m/s", true],
	["accel", "Pick-up", "m/s²", true],
	["turn_radius", "Turn at speed", "m radius", false],
	["trim", "Rise and dive", "m/s", true],
	["rated_depth", "Stands depth", "m", true],
	["sight", "Sight", "m", true],
	["max_health", "Health", "", true],
	["upkeep", "Upkeep", "/s", false],
	["thrust_cost", "Swim cost", "/s", false],
]
## The test swim's rows: [AquaticSim.trial() key, name, unit, higher is better, display factor].
const TRIAL_ROWS := [
	["dash_1s_m", "Dash, 1 s", "m", true, 1.0],
	["cruise_10s_m", "Cruise, 10 s", "m", true, 1.0],
	["turn_1s_rad", "Turn, 1 s", "°", true, 180.0 / PI],
	["energy_10s", "Energy, 10 s", "", false, 1.0],
]
const BETTER_COLOR := "#7dff9a"
const WORSE_COLOR := "#ff8a7a"
const PARENT_PATH_COLOR := Color(1.0, 1.0, 1.0, 0.5)
const CHILD_PATH_COLOR := Color(0.45, 0.92, 1.0)


## The test swim's turn course from above (AquaticSim.trial().path): the parent's and the offspring's, from the same
## start, with a dot each second, a tick where the hard turn begins and a scale bar.
class CourseView extends Control:
	var paths: Array = []   ## [[points ([x, z] metres), Color, width], ...]
	var turn_at := 30       ## the sample the turn starts at

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.05, 0.1, 0.55))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.5, 0.85, 1.0, 0.35), false, 1.0)
		var lo := Vector2.ZERO
		var hi := Vector2.ZERO
		for p in paths:
			for q in p[0]:
				lo = Vector2(minf(lo.x, float(q[0])), minf(lo.y, float(q[1])))
				hi = Vector2(maxf(hi.x, float(q[0])), maxf(hi.y, float(q[1])))
		var margin := 14.0
		var area := size - Vector2(0.0, 18.0)   # the scale bar's strip stays clear
		var span := (hi - lo).max(Vector2(4.0, 4.0))
		var k := minf((area.x - 2.0 * margin) / span.x, (area.y - 2.0 * margin) / span.y)
		var offset := (area - span * k) * 0.5 - lo * k
		for p in paths:
			var pts := PackedVector2Array()
			for q in p[0]:
				pts.append(offset + Vector2(float(q[0]), float(q[1])) * k)
			if pts.size() > 1:
				draw_polyline(pts, p[1], float(p[2]), true)
			for i in range(10, pts.size(), 10):
				draw_circle(pts[i], float(p[2]) * 0.9, p[1])
			if pts.size() > turn_at:
				var tangent := (pts[turn_at] - pts[turn_at - 1]).normalized()
				var side := Vector2(-tangent.y, tangent.x) * 7.0
				draw_line(pts[turn_at] - side, pts[turn_at] + side, p[1], 2.0)
			if not pts.is_empty():
				draw_circle(pts[pts.size() - 1], float(p[2]) + 2.5, p[1])
		draw_circle(offset, 4.0, Color.WHITE)
		var bar_m := 1.0
		for m in [20.0, 10.0, 5.0, 2.0]:
			if m * k <= size.x * 0.45:
				bar_m = m
				break
		var y := size.y - 8.0
		draw_line(Vector2(8.0, y), Vector2(8.0 + bar_m * k, y), Color(1, 1, 1, 0.8), 2.0)
		draw_string(get_theme_default_font(), Vector2(12.0 + bar_m * k, y + 5.0), "%d m" % int(bar_m),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.8))


var rules: Dictionary
var parent_body: Dictionary
var body: Dictionary
var points := 0
var cost := 0
var viewport: SubViewport
var rig_holder: Node3D
var rig: Node3D
var stats_label: RichTextLabel
var cost_label: Label
var done_button: Button
var problems_label: Label
var tail_caption: Label
var trial_label: RichTextLabel
var course_view: CourseView
## The test swims of the parent and of the body as it stands (AquaticSim.trial()), for the stats and the smokes.
var before_trial := {}
var after_trial := {}
var _value_labels := {}
## AquaticSim.trial() results by the body's JSON, so a click back to an earlier body swims nothing again.
var _trials := {}


## Opens on the parent's body with `p_points` to spend.
func open(p_rules: Dictionary, p_body: Dictionary, p_points: int) -> void:
	rules = p_rules
	parent_body = p_body.duplicate()
	body = p_body.duplicate()
	points = p_points
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var look := Theme.new()
	look.set_font_size("font_size", "Button", 22)
	theme = look
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.09, 0.16, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build_plinth()
	_build_panel()
	_refresh()


func _build_plinth() -> void:
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.position = Vector2(620, 40)
	holder.size = Vector2(1240, 600)
	add_child(holder)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.msaa_3d = Viewport.MSAA_4X
	holder.add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.32, 0.45)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.8, 0.9)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.32, 0.45)
	env.fog_density = 0.03
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	viewport.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(30.0), 0.0)
	sun.light_energy = 1.3
	viewport.add_child(sun)
	var packed := load(PLINTH) as PackedScene
	if packed != null:
		var pad := packed.instantiate() as Node3D
		pad.scale = Vector3(1.6, 1.0, 1.6)
		pad.position = Vector3(0.0, -0.01, 0.0)
		viewport.add_child(pad)
	rig_holder = Node3D.new()
	rig_holder.position = Vector3(0.0, 0.85, 0.0)
	viewport.add_child(rig_holder)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.35, 2.6)
	cam.fov = 40.0
	viewport.add_child(cam)
	cam.look_at(Vector3(0.0, 0.8, 0.0), Vector3.UP)


func _build_panel() -> void:
	var panel := VBoxContainer.new()
	panel.position = Vector2(48, 50)
	panel.custom_minimum_size = Vector2(540, 0)
	panel.add_theme_constant_override("separation", 10)
	add_child(panel)
	var title := Label.new()
	title.text = "Your offspring"
	title.add_theme_font_size_override("font_size", 40)
	panel.add_child(title)
	_section(panel, "Tail")
	_choice_row(panel, "tail", rules.body.tails, TAIL_NAMES, TAIL_ROLES)
	tail_caption = Label.new()
	tail_caption.name = "TailCaption"
	tail_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tail_caption.custom_minimum_size = Vector2(540, 0)
	tail_caption.add_theme_font_size_override("font_size", 19)
	tail_caption.modulate = Color(0.85, 0.95, 1.0, 0.85)
	panel.add_child(tail_caption)
	_step_row(panel, "tail_size", "Tail strength")
	_section(panel, "Fins")
	_step_row(panel, "fins", "Side fins")
	_step_row(panel, "dorsal", "Back fin and spines")
	_section(panel, "Body")
	_step_row(panel, "length", "Length")
	_step_row(panel, "girth", "Depth of body")
	_step_row(panel, "bladder", "Swim bladder")
	_section(panel, "Senses")
	_choice_row(panel, "sense", rules.body.senses, {"eyes": "Eyes", "barbels": "Barbels (dark water)", "lure": "Lure"})
	var mouth := Label.new()
	mouth.text = "Mouth (inherited): %s" % {"filter": "filter, eats plankton and algae", "jaw": "jaw, hunts fish",
			"both": "filter and jaw, eats both"}[String(body.mouth)]
	mouth.add_theme_font_size_override("font_size", 20)
	mouth.modulate = Color(1, 1, 1, 0.75)
	panel.add_child(mouth)
	stats_label = RichTextLabel.new()
	stats_label.name = "Stats"
	stats_label.bbcode_enabled = true
	stats_label.scroll_active = false
	stats_label.position = Vector2(640, 660)
	stats_label.size = Vector2(700, 280)
	stats_label.add_theme_font_size_override("normal_font_size", 20)
	stats_label.add_theme_font_size_override("bold_font_size", 22)
	add_child(stats_label)
	trial_label = RichTextLabel.new()
	trial_label.name = "TestSwim"
	trial_label.bbcode_enabled = true
	trial_label.scroll_active = false
	trial_label.position = Vector2(1360, 660)
	trial_label.size = Vector2(290, 280)
	trial_label.add_theme_font_size_override("normal_font_size", 20)
	trial_label.add_theme_font_size_override("bold_font_size", 22)
	add_child(trial_label)
	course_view = CourseView.new()
	course_view.name = "TestSwimCourse"
	course_view.position = Vector2(1660, 666)
	course_view.size = Vector2(200, 200)
	course_view.turn_at = roundi(3.0 * AquaticSim.TICK_HZ / AquaticSim.TRIAL_PATH_EVERY)
	add_child(course_view)
	var bottom := HBoxContainer.new()
	bottom.position = Vector2(48, 960)
	bottom.add_theme_constant_override("separation", 18)
	add_child(bottom)
	cost_label = Label.new()
	cost_label.add_theme_font_size_override("font_size", 26)
	cost_label.custom_minimum_size = Vector2(300, 0)
	bottom.add_child(cost_label)
	var reset := Button.new()
	reset.text = "Undo all"
	reset.pressed.connect(func(): body = parent_body.duplicate(); _refresh())
	bottom.add_child(reset)
	var cancel := Button.new()
	cancel.name = "Cancel"
	cancel.text = "Cancel"
	cancel.pressed.connect(cancel_edit)
	bottom.add_child(cancel)
	done_button = Button.new()
	done_button.name = "Done"
	done_button.text = "Done: swim as the next generation"
	done_button.pressed.connect(commit)
	bottom.add_child(done_button)
	problems_label = Label.new()
	problems_label.position = Vector2(48, 1010)
	problems_label.modulate = Color(1.0, 0.6, 0.5)
	add_child(problems_label)


func _section(panel: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 28)
	l.modulate = Color(0.6, 0.9, 1.0)
	panel.add_child(l)


func _choice_row(panel: Node, key: String, options: Array, names: Dictionary, tips := {}) -> void:
	var row := HBoxContainer.new()
	panel.add_child(row)
	for o in options:
		var b := Button.new()
		b.text = String(names.get(o, o))
		b.tooltip_text = String(tips.get(o, ""))
		b.toggle_mode = true
		b.name = "%s_%s" % [key, o]
		b.pressed.connect(func(): set_choice(key, String(o)))
		row.add_child(b)
	_value_labels[key] = row


func _step_row(panel: Node, key: String, text: String) -> void:
	var row := HBoxContainer.new()
	panel.add_child(row)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(260, 0)
	l.add_theme_font_size_override("font_size", 22)
	row.add_child(l)
	var minus := Button.new()
	minus.text = "  −  "
	minus.pressed.connect(func(): step(key, -1))
	row.add_child(minus)
	var value := Label.new()
	value.custom_minimum_size = Vector2(70, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 24)
	row.add_child(value)
	var plus := Button.new()
	plus.text = "  +  "
	plus.pressed.connect(func(): step(key, 1))
	row.add_child(plus)
	_value_labels[key] = value


## Moves a number by `delta` inside its range (the buttons; tests call it too).
func step(key: String, delta: int) -> void:
	var r: Array = rules.body.ranges[key]
	body[key] = clampi(int(body[key]) + delta, int(r[0]), int(r[1]))
	_refresh()


func set_choice(key: String, value: String) -> void:
	body[key] = value
	_refresh()


func _refresh() -> void:
	cost = AquaticBody.edit_cost(parent_body, body, rules.editor)
	for key in _value_labels:
		var v: Node = _value_labels[key]
		if v is Label:
			(v as Label).text = str(int(body[key]))
		else:
			for b in v.get_children():
				(b as Button).button_pressed = String(b.name) == "%s_%s" % [key, body[key]]
	tail_caption.text = String(TAIL_ROLES.get(String(body.tail), ""))
	var before := AquaticBody.stats(parent_body, rules.body)
	var after := AquaticBody.stats(body, rules.body)
	var half := ceili(STAT_ROWS.size() / 2.0)
	var text := "[b]Swim stats[/b]  [color=#ffffff99](parent → offspring)[/color]\n[table=4]"
	for i in half:
		for row in [STAT_ROWS[i], STAT_ROWS[i + half] if i + half < STAT_ROWS.size() else null]:
			if row == null:
				text += "[cell][/cell][cell][/cell]"
				continue
			text += "[cell]%s    [/cell][cell]%s      [/cell]" % [row[1],
					_before_after(float(before[row[0]]), float(after[row[0]]), bool(row[3]), String(row[2]), 1.0)]
	stats_label.text = text + "[/table]"
	before_trial = _trial(parent_body)
	after_trial = _trial(body)
	text = "[b]Test swim[/b]  [color=#ffffff99](the same water)[/color]\n[table=2]"
	for row in TRIAL_ROWS:
		text += "[cell]%s    [/cell][cell]%s[/cell]" % [row[1], _before_after(float(before_trial[row[0]]),
				float(after_trial[row[0]]), bool(row[3]), String(row[2]), float(row[4]))]
	trial_label.text = text + "[/table]\n[font_size=16][color=#ffffffaa]From still: 3 s ahead, then a hard right turn.\n" \
			+ "[color=#ffffff80]━[/color] parent  [color=#%s]━[/color] offspring[/color][/font_size]" % CHILD_PATH_COLOR.to_html(false)
	course_view.paths = [[before_trial.path, PARENT_PATH_COLOR, 2.0], [after_trial.path, CHILD_PATH_COLOR, 3.0]]
	course_view.queue_redraw()
	var affordable := cost <= points
	cost_label.text = "Cost %d of %d points" % [cost, points]
	cost_label.modulate = Color.WHITE if affordable else Color(1.0, 0.55, 0.5)
	var problems := AquaticBody.validate(body, rules.body)
	done_button.disabled = not affordable or not problems.is_empty()
	problems_label.text = "; ".join(problems) if not problems.is_empty() else ("" if affordable else "Not enough points: undo a change, or earn more by eating, exploring and making friends.")
	_rebuild_rig()


## "before → after unit", the after coloured by whether it is better or worse (white when the same).
static func _before_after(a: float, b: float, higher_is_better: bool, unit: String, factor: float) -> String:
	var digits := "%.0f" if unit == "°" else "%.1f"
	var shown_a := digits % (a * factor)
	var shown_b := digits % (b * factor)
	# Coloured only when the shown numbers differ, so "3.5 → 3.5" is never painted as a change.
	var colour := "white" if shown_a == shown_b else (BETTER_COLOR if (b > a) == higher_is_better else WORSE_COLOR)
	return ("%s → [color=%s]%s[/color]%s" % [shown_a, colour, shown_b, ("" if unit == "°" else " ") + unit]).strip_edges()


## The test swim of `b`, swum once per distinct body.
func _trial(b: Dictionary) -> Dictionary:
	var key := JSON.stringify(b, "", true)
	if not _trials.has(key):
		_trials[key] = AquaticSim.trial(rules, b)
	return _trials[key]


func _rebuild_rig() -> void:
	if rig != null:
		rig.queue_free()
	rig = FishView.make(body, FishView.PLAYER_SCALE_M, 40, FishView.color_of(float(body.hue)), 0)
	rig_holder.add_child(rig)


func _process(delta: float) -> void:
	if rig_holder != null:
		rig_holder.rotate_y(delta * 0.45)
	if rig != null:
		FishView.animate(rig, 1.5, delta)


func commit() -> void:
	if done_button.disabled:
		return
	closed.emit(true, body.duplicate(), cost)


func cancel_edit() -> void:
	closed.emit(false, parent_body.duplicate(), 0)
