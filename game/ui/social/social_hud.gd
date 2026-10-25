class_name SocialHud
extends Control
## The Social stage preview's HUD (PROPOSED, docs/stages/social-plan.md section 11): small and Spore-like, on the
## Pangaea theme's glass variations (GlassPanel, PillPanel, DockButton, CaptionLabel and the labels; the theme itself
## is not edited). It reads a SocialSim and never changes it; the stage acts on its signals.
##   top left:      the goal card: "Befriend the band 1 / 3", then "Feed the nest 2 / 6", and the player's health
##   top right:     one card per companion ("Name · scout · following · trusting") with its Dismiss button
##   bottom centre: the caption (responses, acknowledgements and refusals, in words), the dock (Sing, Display, Share,
##                  Calm | Follow, Wait, Investigate, Retreat, Assist) and the hint line named from the bindings
##   centre:        the entry card, until play begins; the orders menu's panel over the dock while it is open
## Each dock button's enabled state and tooltip come from SocialSim.preview_signal() / preview_order(), the same check
## the action makes. The selected signal and the menu's order carry a "▸" mark, so nothing relies on colour alone.
## Only the buttons take the mouse; nothing takes keyboard or pad focus (the stage reads those itself), so the
## orbit drag and the wheel reach the world.

signal signal_pressed(kind: String)
signal order_pressed(order: String)
signal dismiss_pressed(id: String)

const THEME := preload("res://game/ui/theme/pangaea_theme.tres")
const REFRESH_S := 0.1
const CAPTION_S := 3.5
const CAPTION_FADE_S := 0.6
const CAPTION_LINES := 2
const MARK := "▸ "
const DONE := "✓ "
const SIGNAL_WORDS := {"sing": "Sing", "display": "Display", "share": "Share", "calm": "Calm"}
const ORDER_WORDS := {"follow": "Follow", "wait": "Wait", "investigate": "Investigate", "retreat": "Retreat",
		"assist": "Assist"}
const ENTRY_TITLE := "Preview · Social stage"
const ENTRY_TEXT := "Watch how each one behaves, then answer. Nothing here is saved."
const ENTRY_GO := "Press any key or button to begin"
const ROLE_WORDS := {"scout": "scout", "defender": "defender", "forager": "forager"}
## What a companion is doing, in words, from its order and state.
const DOING_WORDS := {"follow": "following", "wait": "waiting", "investigate": "looking", "retreat": "going home",
		"assist": "helping"}
const HUNTER_WORDS := {"investigate": "The hunter has noticed someone", "pursue": "The hunter gives chase!",
		"disengage": "The hunter breaks off", "rest": "The hunter goes back to its lair"}
const WHY_WORDS := {"time": "it tired", "nerve": "it lost its nerve", "nest": "the nest is too close",
		"group": "too many together", "lost": "it lost sight"}

var sim: SocialSim
var selected := "sing"
var menu_index := 0
var menu_shown := false
var goal_label: Label
var task_label: Label
var health_bar: ProgressBar
var band_box: VBoxContainer
var dock: PanelContainer
var signal_buttons := {}
var order_buttons := {}
var caption_box: VBoxContainer
var hint_label: Label
var card: PanelContainer
var card_name: Label
var card_note: Label
var menu_panel: PanelContainer
var menu_label: Label
var _band_cards := {}
var _captions: Array = []
var _refresh_left := 0.0
var _prompts_generation := -1


func _init() -> void:
	theme = THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_goal_card()
	_build_band_box()
	_build_bottom()
	_build_menu_panel()
	_build_card()


func bind(p_sim: SocialSim) -> void:
	sim = p_sim
	refresh_now()


# --- Building. ------------------------------------------------------------------------------------------------------

func _build_goal_card() -> void:
	var panel := _panel("GlassPanel", "GoalCard")
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(32, 28)
	panel.custom_minimum_size = Vector2(400, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	box.add_child(_label("Social preview", "CaptionLabel"))
	goal_label = _label("", "", 26)
	goal_label.name = "Goal"
	box.add_child(goal_label)
	task_label = _label("", "", 26)
	task_label.name = "Task"
	box.add_child(task_label)
	var health := HBoxContainer.new()
	health.add_theme_constant_override("separation", 10)
	box.add_child(health)
	health.add_child(_label("Health", "SmallLabel"))
	health_bar = ProgressBar.new()
	health_bar.name = "Health"
	health_bar.theme_type_variation = &"HealthBar"
	health_bar.show_percentage = false
	health_bar.custom_minimum_size = Vector2(220, 14)
	health_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	health_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health.add_child(health_bar)


func _build_band_box() -> void:
	band_box = VBoxContainer.new()
	band_box.name = "Band"
	band_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	band_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	band_box.position = Vector2(-32, 28)
	band_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	band_box.add_theme_constant_override("separation", 8)
	add_child(band_box)
	var title := _label("Your band", "CaptionLabel")
	title.name = "BandTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	band_box.add_child(title)


func _build_bottom() -> void:
	var bottom := VBoxContainer.new()
	bottom.name = "Bottom"
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position.y = -24
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 10)
	add_child(bottom)
	caption_box = VBoxContainer.new()
	caption_box.name = "Captions"
	caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	caption_box.add_theme_constant_override("separation", 6)
	bottom.add_child(caption_box)
	dock = _panel("PillPanel", "Dock")
	dock.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(dock)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	dock.add_child(row)
	row.add_child(_label("Friend", "CaptionLabel"))
	for kind in SocialRules.SIGNALS:
		var b := _dock_button(SIGNAL_WORDS[kind], "Signal_%s" % kind)
		b.toggle_mode = true
		b.pressed.connect(func(): signal_pressed.emit(kind))
		row.add_child(b)
		signal_buttons[kind] = b
	var gap := VSeparator.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.custom_minimum_size = Vector2(14, 0)
	row.add_child(gap)
	row.add_child(_label("Orders", "CaptionLabel"))
	for order in SocialRules.ORDERS:
		var b := _dock_button(ORDER_WORDS[order], "Order_%s" % order)
		b.pressed.connect(func(): order_pressed.emit(order))
		row.add_child(b)
		order_buttons[order] = b
	hint_label = _label("", "SmallLabel")
	hint_label.name = "Hint"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(hint_label)


func _build_menu_panel() -> void:
	menu_panel = _panel("GlassPanel", "OrdersMenu")
	menu_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	menu_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	menu_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	menu_panel.position.y = -250
	menu_panel.visible = false
	add_child(menu_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	menu_panel.add_child(box)
	var title := _label("Orders · the band is waiting for you", "CaptionLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	menu_label = _label("", "", 24)
	menu_label.name = "MenuText"
	menu_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(menu_label)


func _build_card() -> void:
	card = _panel("GlassPanel", "EntryCard")
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(760, 0)
	add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)
	var title := _label(ENTRY_TITLE, "LargeLabel")
	title.name = "Title"
	box.add_child(title)
	var text := _label(ENTRY_TEXT)
	text.name = "Text"
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	card_name = _label("", "AccentLabel")
	card_name.name = "Name"
	box.add_child(card_name)
	card_note = _label("", "SmallLabel")
	card_note.name = "Note"
	card_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(card_note)
	var go := _label(ENTRY_GO, "CaptionLabel")
	go.name = "Go"
	box.add_child(go)


static func _panel(variation: String, node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.theme_type_variation = StringName(variation)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


static func _label(text: String, variation: String = "", font_size: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	if not variation.is_empty():
		label.theme_type_variation = StringName(variation)
	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func _dock_button(text: String, node_name: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.theme_type_variation = &"DockButton"
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b


# --- The stage's calls. -------------------------------------------------------------------------------------------

func show_entry_card(creature_name: String, note: String) -> void:
	card_name.text = "You walk as %s" % creature_name if not creature_name.is_empty() else ""
	card_note.text = note
	card_note.visible = not note.is_empty()
	card.visible = true


func hide_card() -> void:
	card.visible = false


func card_visible() -> bool:
	return card.visible


func set_selected(kind: String) -> void:
	selected = kind
	refresh_now()


## Shows or hides the orders menu, with the order at `index` marked.
func set_menu(open: bool, index: int) -> void:
	menu_shown = open
	menu_index = index
	menu_panel.visible = open
	refresh_now()


## The tick's events: each one that has words goes to the caption.
func on_events(events: Array) -> void:
	var names := names_of(sim)
	for e in events:
		var text := event_text(e, names)
		if not text.is_empty():
			caption(text)


## Puts `text` on the caption line (the newest at the bottom, at most CAPTION_LINES).
func caption(text: String) -> void:
	for entry in _captions:
		if entry["label"].text == text:
			entry["left"] = CAPTION_S
			return
	var panel := _panel("PillPanel", "Caption")
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var label := _label(text, "", 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	caption_box.add_child(panel)
	_captions.append({"panel": panel, "label": label, "left": CAPTION_S})
	while _captions.size() > CAPTION_LINES:
		var old: Dictionary = _captions.pop_front()
		old["panel"].queue_free()


## The words on the caption line now, oldest first.
func caption_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for entry in _captions:
		out.append(entry["label"].text)
	return out


func refresh(delta: float) -> void:
	for entry in _captions.duplicate():
		entry["left"] = float(entry["left"]) - delta
		entry["panel"].modulate.a = clampf(float(entry["left"]) / CAPTION_FADE_S, 0.0, 1.0)
		if float(entry["left"]) <= 0.0:
			entry["panel"].queue_free()
			_captions.erase(entry)
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		refresh_now()
	elif _prompts_generation != InputPrompts.generation:
		_refresh_hint()


func refresh_now() -> void:
	_refresh_left = REFRESH_S
	_refresh_hint()
	if sim == null:
		return
	_refresh_goal()
	_refresh_band()
	_refresh_dock()


func _refresh_goal() -> void:
	var cap := int(sim.tuning["band"]["cap"])
	var members := sim.band().size()
	var task := sim.task_state()
	var befriended := members >= cap
	goal_label.text = (DONE if befriended else MARK) + "Befriend the band  %d / %d" % [mini(members, cap), cap]
	var fed := int(task["rounds_done"]) > 0
	var line := "Feed the nest  %d / %d" % [int(task["delivered"]), int(task["goal"])]
	if fed:
		line = DONE + "The nest is fed (%d)" % int(task["rounds_done"]) + ("  ·  next %d / %d" % [int(task["delivered"]),
				int(task["goal"])] if int(task["delivered"]) > 0 else "")
	elif befriended:
		line = MARK + line
	task_label.text = line
	task_label.modulate.a = 1.0 if befriended or fed or int(task["delivered"]) > 0 else 0.6
	var p := sim.player()
	health_bar.max_value = float(p["max_health"])
	health_bar.value = float(p["health"])


func _refresh_band() -> void:
	var seen := {}
	for id in sim.band():
		seen[id] = true
		var c := sim.individual(id)
		if not _band_cards.has(id):
			_band_cards[id] = _make_band_card(id)
		var entry: Dictionary = _band_cards[id]
		entry["label"].text = band_line(c)
	for id in _band_cards.keys():
		if not seen.has(id):
			_band_cards[id]["panel"].queue_free()
			_band_cards.erase(id)
	band_box.get_node("BandTitle").visible = not _band_cards.is_empty()


func _make_band_card(id: String) -> Dictionary:
	var panel := _panel("PillPanel", "Card_%s" % id)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var label := _label("", "", 22)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var b := _dock_button("Dismiss", "Dismiss")
	b.add_theme_font_size_override("font_size", 17)
	b.tooltip_text = "Let it go home, on good terms"
	b.pressed.connect(func(): dismiss_pressed.emit(id))
	row.add_child(b)
	band_box.add_child(panel)
	return {"panel": panel, "label": label, "dismiss": b}


## A companion's card line: "Name · scout · following · trusting".
static func band_line(c: Dictionary) -> String:
	return " · ".join([String(c["name"]), String(ROLE_WORDS.get(String(c["role"]), c["role"])), doing_word(c),
			String(c["trust_word"])])


static func doing_word(c: Dictionary) -> String:
	if int(c.get("carrying", 0)) > 0:
		return "carrying fruit"
	var order := String(c.get("order", ""))
	if DOING_WORDS.has(order):
		return DOING_WORDS[order]
	var state := String(c.get("state", ""))
	return {"forage": "foraging", "flee": "fleeing", "recover": "resting", "socialize": "listening"}.get(state, "with you")


func _refresh_dock() -> void:
	for kind in SocialRules.SIGNALS:
		var b: Button = signal_buttons[kind]
		var preview := sim.preview_signal(kind)
		b.disabled = not bool(preview["ok"])
		b.set_pressed_no_signal(kind == selected)
		b.text = (MARK if kind == selected else "") + String(SIGNAL_WORDS[kind])
		b.tooltip_text = signal_tooltip(kind, preview, names_of(sim))
		b.modulate.a = 0.45 if menu_shown else 1.0
	for i in SocialRules.ORDERS.size():
		var order: String = SocialRules.ORDERS[i]
		var b: Button = order_buttons[order]
		var preview := sim.preview_order(order)
		var marked := menu_shown and i == menu_index
		b.disabled = not bool(preview["ok"])
		b.text = (MARK if marked else "") + String(ORDER_WORDS[order])
		b.tooltip_text = order_tooltip(order, preview, names_of(sim))
	if menu_shown:
		var order: String = SocialRules.ORDERS[menu_index]
		menu_label.text = "%s%s:  %s" % [MARK, ORDER_WORDS[order], order_tooltip(order, sim.preview_order(order),
				names_of(sim))]


## A signal button's tooltip: who it goes to, or why it cannot be given now (the resolver's own words).
static func signal_tooltip(kind: String, preview: Dictionary, names: Dictionary) -> String:
	if not bool(preview["ok"]):
		return "%s: %s" % [SIGNAL_WORDS[kind], String(preview["reason"])]
	return "%s to %s" % [SIGNAL_WORDS[kind], String(names.get(String(preview["target"]), "them"))]


## An order button's tooltip: each member's answer (its acknowledgement or its refusal), or why no one can take it.
static func order_tooltip(order: String, preview: Dictionary, names: Dictionary) -> String:
	var answers: Array = preview.get("answers", [])
	if answers.is_empty():
		return String(preview["reason"])
	var parts := PackedStringArray()
	for a in answers:
		var who := String(names.get(String(a["who"]), a["who"]))
		parts.append("%s %s" % [who, String(a["words"])] if bool(a["ok"]) else "%s refuses: %s" % [who, String(a["reason"])])
	return "; ".join(parts)


func _refresh_hint() -> void:
	_prompts_generation = InputPrompts.generation
	var pairs := [[&"creature_social", "Friend: %s" % SIGNAL_WORDS.get(selected, "Sing")], [&"zoom_in", "Next signal"],
			[&"creature_bite", "Foe: bite"], [&"creature_evolve", "Orders"], [&"pause", "Leave"]]
	if menu_shown:
		pairs = [[&"ui_left", "Previous"], [&"ui_right", "Next"], [&"ui_accept", "Give the order"], [&"ui_cancel", "Close"]]
	var line := InputPrompts.hint_line(pairs)
	var move := move_name()
	if not move.is_empty() and not menu_shown:
		line = "%s  Move" % move + ("   ·   " + line if not line.is_empty() else "")
	hint_label.text = line


## The four move_* bindings of the device in use as one name ("WASD" or "Arrows" for the keys, "Left stick" for the
## pad); "" when none is bound.
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
	return "".join(names) if letters else " / ".join(names)


## id -> name for the individuals, the player ("You") and the hunter ("The hunter").
static func names_of(p_sim: SocialSim) -> Dictionary:
	var out := {SocialSim.PLAYER_ID: "You"}
	if p_sim == null:
		return out
	for c in p_sim.individuals():
		out[c["id"]] = c["name"]
	out[String(p_sim.hunter()["id"])] = "The hunter"
	return out


## An event in words for the caption ("" for one that needs none). `names`: names_of().
static func event_text(e: Dictionary, names: Dictionary = {}) -> String:
	var who := String(names.get(String(e.get("who", "")), e.get("name", e.get("who", ""))))
	match String(e.get("kind", "")):
		"refused":
			return "%s · %s" % [String(e.get("action", "")).capitalize(), String(e["reason"])]
		"response":
			return "%s %s" % [String(e.get("name", who)), String(e["words"])]
		"joined":
			return "%s joins your band" % String(e.get("name", who))
		"befriended":
			return "%s is your friend now; it stays where it lives" % String(e.get("name", who))
		"ack":
			return "%s %s" % [who, String(e["words"])]
		"order_refused":
			return "%s refuses: %s" % [who, String(e["reason"])]
		"arrived":
			return "%s is there" % who
		"found":
			return "%s found %s" % [who, String(e["what"])]
		"cannot":
			return "%s can't: %s" % [who, String(e["reason"])]
		"done":
			return "%s is done and comes back to you" % who
		"lost":
			return "%s lost you and goes home" % who
		"dismissed":
			return "%s goes home, on good terms" % String(e.get("name", who))
		"left":
			return "%s leaves your band: %s" % [String(e.get("name", who)), String(e.get("reason", ""))]
		"delivered":
			return "%s brings fruit to the nest" % who
		"learned":
			return "%s has learned the way to the grove" % who
		"task_done":
			return "The nest is fed: %d fruit" % int(e.get("count", 0))
		"hunter_state":
			var text := String(HUNTER_WORDS.get(String(e["state"]), ""))
			if String(e["state"]) == "disengage" and WHY_WORDS.has(String(e.get("why", ""))):
				text += ": " + String(WHY_WORDS[String(e["why"])])
			return text
		"warned":
			return "%s warns: hunter!" % String(e.get("name", who))
		"hit":
			var target := String(e.get("target", ""))
			if target == SocialSim.PLAYER_ID:
				return "The hunter strikes you"
			return "The hunter strikes at %s; it is frightened" % String(names.get(target, target))
		"drove_off":
			return "The hunter is driven off: %s" % String(WHY_WORDS.get(String(e.get("why", "")), "it gives up"))
		"bit":
			if String(e.get("by", "")) == SocialSim.PLAYER_ID:
				return "You bite %s" % String(names.get(String(e.get("target", "")), e.get("target", "")))
			return ""
		"hostile":
			return "%s won't trust you for %d s" % [String(e.get("name", who)), int(e.get("seconds", 0))]
		"bumped":
			return "You bump into %s; it knows it was an accident" % String(e.get("name", who))
		"fainted":
			return "You faint! Your band waits for you at the nest"
		"recovered":
			return "You come round at the nest"
	return ""
