extends Control
## The Aquatic stage's fin and tail editor (aquatic plan section 6, PROPOSED), opened by mating at the nest. Spore's
## layout: the choices on the left (Tail, Fins, Body, Senses), the offspring turning on a plinth on the right, and
## the swim stats before and after with the points it costs. Every number comes from AquaticBody, the rules play
## uses, so the preview cannot disagree with the water. Done commits the next generation; Cancel keeps the parent.
## The mouth and colour are inherited and stay (shown, not offered).

signal closed(committed: bool, body: Dictionary, cost: int)

const FishView := preload("res://game/scenes/aquatic/fish_view.gd")
const PLINTH := "res://assets/export/creature_editor_room.glb"
## The tail choices' names (aquatic-r2). No tail is simply "fast" or "nimble": the stats below the fish show each one's
## tradeoff, from the same rules the water uses.
const TAIL_NAMES := {"fluke": "Fluke", "ribbon": "Ribbon", "lunate": "Lunate", "paddle": "Paddle", "whip": "Whip"}
const STAT_ROWS := [
	["top_speed", "Top speed", "m/s", true],
	["burst_speed", "Burst", "m/s", true],
	["turn_radius", "Turn at speed", "m radius", false],
	["trim", "Rise and dive", "m/s", true],
	["rated_depth", "Stands depth", "m", true],
	["sight", "Sight", "m", true],
	["max_health", "Health", "", true],
	["upkeep", "Upkeep", "/s", false],
]

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
var _value_labels := {}


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
	holder.position = Vector2(620, 60)
	holder.size = Vector2(1240, 760)
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
	_choice_row(panel, "tail", rules.body.tails, TAIL_NAMES)
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
	stats_label.bbcode_enabled = true
	stats_label.fit_content = true
	stats_label.position = Vector2(660, 830)
	stats_label.size = Vector2(1200, 180)
	stats_label.add_theme_font_size_override("normal_font_size", 21)
	add_child(stats_label)
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


func _choice_row(panel: Node, key: String, options: Array, names: Dictionary) -> void:
	var row := HBoxContainer.new()
	panel.add_child(row)
	for o in options:
		var b := Button.new()
		b.text = String(names.get(o, o))
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
	var before := AquaticBody.stats(parent_body, rules.body)
	var after := AquaticBody.stats(body, rules.body)
	var lines := PackedStringArray()
	for row in STAT_ROWS:
		var a := float(before[row[0]])
		var b := float(after[row[0]])
		var better: bool = (b > a) == bool(row[3])
		var colour := "white" if is_equal_approx(a, b) else ("#7dff9a" if better else "#ff8a7a")
		lines.append("%s: %.1f → [color=%s]%.1f[/color] %s" % [row[1], a, colour, b, row[2]])
	stats_label.text = "    ".join(lines.slice(0, 4)) + "\n" + "    ".join(lines.slice(4))
	var affordable := cost <= points
	cost_label.text = "Cost %d of %d points" % [cost, points]
	cost_label.modulate = Color.WHITE if affordable else Color(1.0, 0.55, 0.5)
	var problems := AquaticBody.validate(body, rules.body)
	done_button.disabled = not affordable or not problems.is_empty()
	problems_label.text = "; ".join(problems) if not problems.is_empty() else ("" if affordable else "Not enough points: undo a change, or earn more by eating, exploring and making friends.")
	_rebuild_rig()


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
