class_name SocialTags
extends Control
## The Social stage preview's tags (PROPOSED, docs/stages/social-plan.md section 11): a small panel over each
## individual and the hunter, projected from the world with the camera, reading "Name · role · mood" (the mood is
## the word the player reads the individual by: hungry, wary, scared, curious, warm, at ease or hostile) and, under
## it, the trust word and the latest answer to a signal for a few seconds. The individual the player's signals go to
## carries a "▸" mark. Words carry everything, so nothing relies on colour alone. Tags ignore the mouse.

const THEME := preload("res://game/ui/theme/pangaea_theme.tres")
const MARK := "▸ "
const RESPONSE_S := 3.0
## Tags are drawn only within this distance of the camera (m).
const SHOW_M := 34.0

var sim: SocialSim
var world: SocialWorld
## id -> {panel, top, bottom}
var tags := {}
var _responses := {}
var _last_ms := 0


func _init() -> void:
	theme = THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func bind(p_sim: SocialSim, p_world: SocialWorld) -> void:
	sim = p_sim
	world = p_world
	for c in sim.individuals():
		tags[c["id"]] = _make_tag(String(c["id"]))
	tags[String(sim.hunter()["id"])] = _make_tag(String(sim.hunter()["id"]))
	_last_ms = Time.get_ticks_msec()


func _make_tag(id: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.name = "Tag_%s" % id
	panel.theme_type_variation = &"ToastPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	var top := Label.new()
	top.add_theme_font_size_override("font_size", 20)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(top)
	var bottom := Label.new()
	bottom.theme_type_variation = &"SmallLabel"
	bottom.add_theme_font_size_override("font_size", 17)
	bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(bottom)
	add_child(panel)
	return {"panel": panel, "top": top, "bottom": bottom}


## Keeps the latest answer to a signal per individual.
func on_events(events: Array) -> void:
	for e in events:
		if String(e.get("kind", "")) == "response":
			_responses[String(e["who"])] = {"words": String(e["words"]), "left": RESPONSE_S}


## The words on `id`'s tag now: [top line, bottom line].
func tag_lines(id: String) -> PackedStringArray:
	if sim == null:
		return PackedStringArray(["", ""])
	if id == String(sim.hunter()["id"]):
		var h := sim.hunter()
		return PackedStringArray(["Hunter · %s" % String(h["preset"]), hunter_word(String(h["state"]))])
	var c := sim.individual(id)
	if c.is_empty():
		return PackedStringArray(["", ""])
	var top := "%s · %s · %s" % [String(c["name"]), String(c["role"]), String(c["mood"])]
	if id == sim.target_id():
		top = MARK + top
	var bottom := String(c["trust_word"])
	if bool(c["member"]):
		bottom = "in your band · " + bottom
	elif bool(c["befriended"]):
		bottom = "your friend · " + bottom
	if _responses.has(id):
		bottom += " · " + String(_responses[id]["words"])
	return PackedStringArray([top, bottom])


static func hunter_word(state: String) -> String:
	return {"patrol": "patrolling", "investigate": "watching", "pursue": "chasing", "strike": "striking",
			"disengage": "breaking off", "rest": "resting"}.get(state, state)


func refresh() -> void:
	if sim == null or world == null or world.camera == null:
		return
	var now := Time.get_ticks_msec()
	var delta := float(now - _last_ms) / 1000.0
	_last_ms = now
	for id in _responses.keys():
		_responses[id]["left"] = float(_responses[id]["left"]) - delta
		if float(_responses[id]["left"]) <= 0.0:
			_responses.erase(id)
	var camera := world.camera
	for id in tags:
		var tag: Dictionary = tags[id]
		var panel: PanelContainer = tag["panel"]
		var at := world.tag_point(id)
		var shown := camera.is_inside_tree() and not camera.is_position_behind(at) \
				and camera.global_position.distance_to(at) <= SHOW_M
		panel.visible = shown
		if not shown:
			continue
		var lines := tag_lines(id)
		tag["top"].text = lines[0]
		tag["bottom"].text = lines[1]
		# unproject_position gives the canvas's own coordinates (the stretch's design size), which this full-rect
		# Control under an untransformed CanvasLayer shares.
		var screen := camera.unproject_position(at)
		panel.reset_size()
		panel.position = screen - Vector2(panel.size.x * 0.5, panel.size.y)
