class_name CreatureEditor
extends Node3D
## The in-game creature editor (creature stage plan section 4, PROPOSED): a Spore-style room over the scene-free
## editor core (game/domain/creature/creature_editor_session.gd, editor_picking.gd), ported from the creature lab's
## editor_lab.gd. The body's vertebrae, joints and parts carry handles to drag; a part tool adds a part where the
## skin is clicked; the limb tool grows a limb from the click and its tip follows the drag; the skin is rebuilt live
## on a worker thread (the GPU builder when the renderer has compute, else the GDScript one) while the handles follow
## the mouse at once. "Test drive" walks the working body on the gait planner's legs in place of the editor view.
##
## Mouse: left-drag a handle (orange vertebra, blue joint, green part; a selected part shows a yellow turn ring whose
## handle turns it); with a tool chosen, left-click the skin to add a part or grow a limb. Wheel over the selected
## vertebra or joint thickens or thins it, over the selected part grows or shrinks it, elsewhere zooms. Right-drag,
## middle-drag or the right stick orbits (owner playtest, 2026-10-24). Keys: 1-9, Tab,
## [ and ] pick a part tool, L the limb tool, 0 no tool, Q/E turn and R/F tilt the selected part, Delete removes the
## selection, Insert adds a vertebra or joint after it, M toggles its mirror, + and - grow and shrink it (a part's
## scale, a vertebra's or joint's thickness), Ctrl+Z / Ctrl+Y undo and redo, T
## toggles the test drive, Enter is Done. Escape (and the HUD's Back, and the pad's B through CreatureStage) is
## progressive: it clears the tool and the selection first; with edits since the last Done it asks once (UNSAVED_TEXT,
## for REFUSAL_S) and leaves on the next press; otherwise it leaves. Space stays unused; the right mouse button
## only orbits here (no input action uses it, tests/test_project_settings.gd).
##
## Every input path has a method twin (choose_tool, click_skin, drag, select, undo, redo, remove_selected,
## insert_after_selected, mirror_selected, thicken, resize_selected, set_head_shape, orbit, zoom, test_drive, finish, back), so the smoke and the scene tests drive
## it without input events. The UI buttons call the same methods. `refusal_text` holds the last refused op's reason
## for REFUSAL_S seconds.
##
## The skin colour comes from a swatch; it rides in the body dictionary as "skin_color" ("#rrggbb") beside the three
## skin-pattern ints (creature_look.gd), fields the codec keeps as unknown keys (tests/test_creature_body.gd), so the
## world and the store carry them without a schema change. The HUD's head shape sliders (snout, skull width and
## height, jaw, brow) set the body's "head_shape" block the same way (domain/creature/head_shape.gd); a slider drag is
## one undo step, and the dials cost nothing and change no stat (mass leaves the head shape out).

const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const SkinCpu := preload("res://game/systems/creature/skin_cpu.gd")
const SpineRig := preload("res://game/scenes/creature/spine_rig.gd")
const WalkerRig := preload("res://game/scenes/creature/walker_rig.gd")
const Look := preload("res://game/scenes/creature/creature_look.gd")
const BodyField := preload("res://game/domain/creature/body_field.gd")
const AnchorResolver := preload("res://game/domain/creature/anchor_resolver.gd")
const Session := preload("res://game/domain/creature/creature_editor_session.gd")
const Picking := preload("res://game/domain/creature/editor_picking.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const GaitBody := preload("res://game/domain/creature/gait_body.gd")
const BodyMechanics := preload("res://game/domain/creature/body_mechanics.gd")
const GaitPlanner := preload("res://game/domain/creature/gait_planner.gd")
const SkinWorker := preload("res://game/scenes/creature/creature_editor_skin_worker.gd")
const PartIcons := preload("res://game/scenes/creature/part_icons.gd")
const WorldRules := preload("res://game/domain/creature/creature_world_rules.gd")
## The STATS track's anatomy-to-play numbers (CreatureStats, pure); shown when its file is present.
const STATS_PATH := "res://game/domain/creature/creature_stats.gd"
const STAGE_TUNING_PATH := "res://game/data/creature/creature_stage.json"

const HANDLE_PICK_PX := 16.0
## Handles keep one size on screen whatever the zoom: this radius in pixels (at the project's 1080 rows, scaled with
## the viewport), unselected part handles at HANDLE_PART_SCALE of it and the selection at HANDLE_SELECTED_SCALE.
const HANDLE_SCREEN_PX := 9.0
const HANDLE_PART_SCALE := 0.6
const HANDLE_SELECTED_SCALE := 1.5
const REFUSAL_S := 2.0
const ORBIT_MOUSE_RATE := 0.008
const ORBIT_STICK_RATE := 2.2
const STICK_DEADZONE := 0.2
const ZOOM_STEP := 1.1
## One + / - or wheel step on a part's scale (10%), clamped to the body rules' part scale range.
const PART_SCALE_STEP := 1.1
## The camera's distance range, as multiples of the body's framing distance: close enough to inspect a part, far
## enough to see a big creature whole.
## New parts are sized to the body (Picking.fit_scale): at scale 1000 on a body this one's size, larger on a bigger
## body, so a giant's feet are not a mouse's.
const REFERENCE_BODY := "s1_quadruped"
const ZOOM_MIN := 0.25
const ZOOM_MAX := 4.0
## The camera's pitch range (rad): never under the floor disc, even zoomed far out.
const PITCH_MIN := 0.05
const PITCH_MAX := 1.4
## Back with edits since the last Done asks once; Done on a body without legs asks once.
const UNSAVED_TEXT := "Unsaved edits: press Esc or Back again to leave without them"
const NO_LEGS_TEXT := "No legs to walk on; press Done again to go anyway"
const COLORS := {"vertebra": Color(1.0, 0.6, 0.15), "joint": Color(0.3, 0.7, 1.0), "part": Color(0.4, 1.0, 0.5),
		"turn": Color(1.0, 0.9, 0.2)}
const SKIN_COLOR_KEY := "skin_color"
## The eight skin swatches (PROPOSED): the lab's blue first.
const SKIN_COLORS: Array[Color] = [Color("#5ca8dc"), Color("#4fc08a"), Color("#d9a441"), Color("#d2604e"),
		Color("#a86fd6"), Color("#e6e1c8"), Color("#5f6b7a"), Color("#2e4a6b")]
## The test drive's looping program: [until_s, throttle, turn] (a walk, a trot, a run and a turn, then again).
const DRIVE_PROGRAM := [[2.5, 0.3, 0.0], [5.0, 0.6, 0.0], [7.0, 1.0, 0.0], [8.5, 0.6, 0.7], [10.0, 0.0, 0.0]]
const HINT := "Drag a handle   ·   click the skin with a tool   ·   right-drag turns the view   ·   wheel zooms, or over the selection resizes it\n" \
		+ "1-9 / Tab tools   ·   L limb   ·   0 none   ·   + - resize   ·   Q E R F turn and tilt   ·   Del   ·   Ins   ·   M mirror   ·   Ctrl+Z / Ctrl+Y   ·   T test drive   ·   Enter done   ·   Esc clears the tool, again leaves"

signal done_requested(body_dict: Dictionary, points_left: int)
signal back_requested

var session: RefCounted
var rules := {}
var part_rules := {}
var costs := {}
var orientations := {}
## Part tools: every part type in the art records, by name.
var tools: Array = []
var tool := ""
var selected := {}
var dragging := false
var drag_plane := Plane()
var handles: Array = []   ## {kind, id, limb, copy, twin, world: Vector3}
var _handle_meshes: Array = []   ## {mesh: MeshInstance3D, scale: float}, resized to the camera each frame
var skin_color: Color = SKIN_COLORS[0]
## The skin-shader pattern (pattern_seed, coat_pattern, detail_pattern), from the body or Look.DEFAULT_PATTERN.
var skin_pattern: Dictionary = Look.DEFAULT_PATTERN.duplicate()
## The last refused op's reason, for REFUSAL_S seconds.
var refusal_text := ""
var rig: Node3D
var walker: Node3D
var skin_ms := 0.0
## Builds the skin on a worker thread with its own GPU device; off, it builds in step on the main thread.
var threaded := true
var divisions := 0   ## 0: the body's own preview grid

var _dirty := false
var _refusal_t := 0.0
var _worker: RefCounted
var _orbit := Vector2(2.05, 0.3)
var _distance := 2.6
## The distance the body was framed at (frame_body), the zoom range's yardstick; 0 before the first framing.
var _frame_distance := 0.0
## The longest side of REFERENCE_BODY's bounds (m), measured once.
var _reference_size_m := 0.0
## Whether the "Start from" presets are offered (offer_presets), and the preset the design started from since the
## last Done ("" for none; Back asks before leaving it).
var presets_offered := false
## The palette's part pictures (part_icons.gd), rendered after setup.
var _icons: Node
var preset := ""
var _orbiting := false
var _focus := Vector3.ZERO
var _rig_offset := Vector3.ZERO
var _drive_t := 0.0
var _sphere: SphereMesh
var _stats_script: GDScript
var _readied := false
var _stage_tuning := {}

var camera: Camera3D
var handle_root: Node3D
var rig_root: Node3D
var floor_disc: Node3D          # the floor pad (assets/export/creature_editor_room.glb), unit radius, scaled to the body
var hud: CreatureEditorHud


func _ready() -> void:
	_wire()


## Finds the nodes and wires the HUD, once: from _ready(), or from setup() when the scene is driven before the tree
## is live (the test runner), where @onready has not run.
func _wire() -> void:
	if _readied:
		return
	_readied = true
	camera = $Camera
	handle_root = $HandleRoot
	rig_root = $RigRoot
	floor_disc = $Floor
	hud = $UI/Hud
	hud.wire()
	_sphere = SphereMesh.new()
	_sphere.radius = 1.0
	_sphere.height = 2.0
	_sphere.radial_segments = 12
	_sphere.rings = 6
	hud.tool_chosen.connect(choose_tool)
	hud.action.connect(_on_hud_action)
	hud.test_drive_toggled.connect(func(on: bool): test_drive(on))
	hud.color_chosen.connect(set_skin_color)
	hud.preset_chosen.connect(start_from_preset)
	hud.random_requested.connect(func(): start_random())
	hud.head_shape_changed.connect(func(key: String, value: int): set_head_shape(key, value))
	hud.head_shape_drag.connect(func(started: bool):
		if started:
			session.begin_gesture()
		else:
			session.end_gesture())
	hud.set_hint(HINT)
	if ResourceLoader.exists(STATS_PATH):
		_stats_script = load(STATS_PATH)
		if ResourceLoader.exists(STAGE_TUNING_PATH):
			_stage_tuning = CreatureData.read_json(STAGE_TUNING_PATH)


## Opens a body with `points` to spend. The data files and part rules are read here (a service's job, not a scene's
## rule), once per visit.
func setup(body: RefCounted, points: int) -> void:
	_wire()
	rules = CreatureData.rules()
	part_rules = CreatureData.part_rules()
	costs = CreatureData.editor_costs()
	orientations = CreatureData.part_orientations(part_rules)
	tools = part_rules.keys()
	tools.sort()
	session = Session.new(body, rules, part_rules, costs, points)
	if _reference_size_m <= 0.0:
		_reference_size_m = (CreatureData.body(REFERENCE_BODY).bounds_m() as AABB).get_longest_axis_size()
	var stored := String(body.extra.get(SKIN_COLOR_KEY, ""))
	skin_color = Color.html(stored) if Color.html_is_valid(stored) else SKIN_COLORS[0]
	skin_pattern = Look.pattern_of(body.extra)
	selected = {}
	tool = ""
	preset = ""
	if _worker == null:
		_worker = SkinWorker.new(rules, divisions)
		if threaded:
			_worker.start()
	var roles := {}
	for type in part_rules:
		roles[type] = String(part_rules[type].get("role", ""))
	hud.setup(tools, costs, SKIN_COLORS, roles)
	hud.setup_head_shape(session.head_shape_ranges())
	if _icons == null:
		_icons = PartIcons.new()
		_icons.name = "PartIcons"
		add_child(_icons)
		_icons.icon_ready.connect(hud.set_tool_icon)
	_icons.render(tools)
	hud.set_tool(tool)
	hud.set_color(skin_color)
	_frame_body()
	_rebuild()


func working_body() -> RefCounted:
	return session.working


## The points still available to this visit.
func points() -> int:
	return session.available_points


# Rebuild ---------------------------------------------------------------------------------------------------------


## Frames the camera on the working body and sizes the floor disc to it.
func _frame_body() -> void:
	var box: AABB = session.working.bounds_m()
	_rig_offset = Vector3(0.0, -box.position.y + 0.01, 0.0)
	_focus = box.get_center() + _rig_offset
	_distance = 2.2 * box.get_longest_axis_size()
	_frame_distance = _distance
	var disc := maxf(1.2, 1.4 * box.get_longest_axis_size())
	floor_disc.scale = Vector3(disc, 1.0, disc)
	_update_camera()


## Rebuilds the handles now and posts the skin to the worker (the handles follow the mouse at once, the skin catches
## up; an edit made while a build runs is built next). Without a worker the skin is built in step.
func _rebuild() -> void:
	_dirty = false
	var desc = session.working
	_store_look(desc.extra)
	var placed := AnchorResolver.resolve_all(desc, BodyField.from_description(desc), orientations)
	_rebuild_handles(desc, placed)
	_refresh_hud()
	if threaded:
		_worker.post(desc.to_dict())
	else:
		_present(_worker.build_now(desc.to_dict()))


func _present(built: Dictionary) -> void:
	var desc = built["desc"]
	skin_ms = built["ms"]
	if rig:
		rig.free()
	rig = SpineRig.new()
	rig.name = "Body"
	rig_root.add_child(rig)
	rig.position = _rig_offset
	rig.setup(desc, built["arrays"], skin_color)
	rig.add_parts(AnchorResolver.resolve_all(desc, BodyField.from_description(desc), orientations), orientations)
	rig.use_skin_shader(_shader_params())
	rig.visible = walker == null


func _shader_params() -> Dictionary:
	return Look.shader_params(skin_color, skin_pattern)


## The swatch and the pattern into a body's extra keys, as the world reads them (creature_look.gd).
func _store_look(extra: Dictionary) -> void:
	extra[SKIN_COLOR_KEY] = skin_color.to_html(false)
	Look.store_pattern(extra, skin_pattern)


func _collect_skin() -> void:
	if not threaded or _worker == null:
		return
	var built: Dictionary = _worker.collect()
	if not built.is_empty():
		_present(built)


func _rebuild_handles(desc: RefCounted, placed: Array) -> void:
	handles.clear()
	_handle_meshes.clear()
	for c in handle_root.get_children():
		c.free()
	var r: float = 0.018 * desc.bounds_m().get_longest_axis_size()   # the turn ring's unit; the spheres size to the screen
	for i in desc.vertebrae.size():
		_add_handle({"kind": "vertebra", "id": desc.vertebrae[i]["id"]}, desc.position_m(i), 1.0)
	var chains: Array = desc.limb_chains()
	for c in chains.size():
		var copy: bool = c > 0 and chains[c - 1]["source"] == chains[c]["source"]
		var limb: Dictionary = desc.limbs[desc.limb_index(String(chains[c]["source"]))]
		var pts: PackedVector3Array = chains[c]["points"]
		for k in range(1, pts.size()):  # joint 0 rides on its vertebra
			_add_handle({"kind": "joint", "id": limb["joints"][k]["id"], "limb": limb["id"], "copy": copy}, pts[k], 1.0)
	for e in placed:
		var t: Transform3D = e["transform"]
		_add_handle({"kind": "part", "id": e["part"], "twin": e["twin"]}, t.origin, HANDLE_PART_SCALE)
		# The selected part's turn ring: a circle around its up axis, with a handle on its side to drag round.
		if not e["twin"] and not selected.is_empty() and selected["kind"] in ["part", "turn"] and selected["id"] == e["part"]:
			var up := t.basis.y.normalized()
			var side := t.basis.x.normalized()
			var ring_r := 5.0 * r
			_add_ring(t.origin, up, side, ring_r)
			_add_handle({"kind": "turn", "id": e["part"], "origin": t.origin + _rig_offset, "up": up},
					t.origin + side * ring_r, 1.0)
	handle_root.visible = walker == null
	_scale_handles()


func _add_ring(centre: Vector3, up: Vector3, side: Vector3, radius: float) -> void:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.albedo_color = COLORS["turn"]
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	var other := up.cross(side)
	for k in 49:
		var a := TAU * k / 48.0
		im.surface_add_vertex(centre + _rig_offset + (side * cos(a) + other * sin(a)) * radius)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	handle_root.add_child(mi)


## A handle sphere at `body_pos`, drawn at `scale` times HANDLE_SCREEN_PX (the selection larger).
func _add_handle(h: Dictionary, body_pos: Vector3, scale: float) -> void:
	h["world"] = body_pos + _rig_offset
	handles.append(h)
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 1
	var col: Color = COLORS[h["kind"]]
	var is_sel := _same(h, selected)
	mat.albedo_color = col.lightened(0.6) if is_sel else col
	mi.material_override = mat
	mi.position = h["world"]
	_handle_meshes.append({"mesh": mi, "scale": HANDLE_SELECTED_SCALE if is_sel else scale})
	handle_root.add_child(mi)


## Sizes every handle sphere to its screen size at the camera's current distance (perspective: a sphere of radius
## r at distance d covers r / (d * tan(fov / 2)) of the half-height).
func _scale_handles() -> void:
	if _handle_meshes.is_empty():
		return
	var eye := _camera_xform().origin
	var per_px := 2.0 * tan(deg_to_rad(camera.fov) * 0.5) / maxf(_screen_size().y, 1.0)
	for e in _handle_meshes:
		var mi: MeshInstance3D = e["mesh"]
		var r := HANDLE_SCREEN_PX * float(e["scale"]) * per_px * maxf(mi.position.distance_to(eye), 0.05)
		mi.scale = Vector3.ONE * r


static func _same(a: Dictionary, b: Dictionary) -> bool:
	return not b.is_empty() and a["kind"] == b["kind"] and a["id"] == b["id"] and a.get("copy", false) == b.get("copy", false) \
			and a.get("twin", false) == b.get("twin", false)


# Input -----------------------------------------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if session == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					press(mb.position)
				else:
					release()
				_mark_handled()
			MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed
				_mark_handled()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					wheel(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1, mb.position)
					_mark_handled()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			orbit(Vector2(-mm.relative.x, mm.relative.y) * ORBIT_MOUSE_RATE)
		elif dragging:
			drag_to(mm.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		if _key(event as InputEventKey):
			_mark_handled()


## Marks the event handled when the editor is in a live viewport (tests also feed _unhandled_input directly).
func _mark_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


## The keys, as the lab bound them. Returns true when the key did something.
func _key(k: InputEventKey) -> bool:
	if k.ctrl_pressed and k.keycode == KEY_Z:
		if k.shift_pressed:
			redo()
		else:
			undo()
	elif k.ctrl_pressed and k.keycode == KEY_Y:
		redo()
	elif k.keycode >= KEY_1 and k.keycode <= KEY_9 and k.keycode - KEY_1 < tools.size():
		choose_tool(tools[k.keycode - KEY_1])
	elif k.keycode == KEY_TAB or k.keycode == KEY_BRACKETRIGHT or k.keycode == KEY_BRACKETLEFT:
		var step := -1 if k.keycode == KEY_BRACKETLEFT or k.shift_pressed else 1
		choose_tool(tools[posmod(tools.find(tool) + step, tools.size())] if tools.has(tool) else tools[0])
	elif k.keycode == KEY_L:
		choose_tool("limb")
	elif k.keycode == KEY_0:
		choose_tool("")
	elif k.keycode in [KEY_Q, KEY_E, KEY_R, KEY_F]:
		turn_selected(k.keycode)
	elif k.keycode == KEY_DELETE:
		remove_selected()
	elif k.keycode == KEY_INSERT:
		insert_after_selected()
	elif k.keycode == KEY_M:
		mirror_selected()
	elif k.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
		resize_selected(1)
	elif k.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
		resize_selected(-1)
	elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		finish()
	elif k.keycode == KEY_ESCAPE:
		back()
	elif k.keycode == KEY_T:
		test_drive(walker == null)
	else:
		return false
	return true


func _on_hud_action(name: String) -> void:
	match name:
		"undo": undo()
		"redo": redo()
		"delete": remove_selected()
		"insert": insert_after_selected()
		"mirror": mirror_selected()
		"done": finish()
		"back": back()


# Method twins ----------------------------------------------------------------------------------------------------


## A part type from the art records, "limb", or "" for no tool. An unknown type is ignored.
func choose_tool(type: String) -> void:
	if type != "" and type != "limb" and not tools.has(type):
		_refuse("no %s tool" % type)
		return
	tool = type
	hud.set_tool(tool)


## A left click on the skin: with a part tool, adds the part at the clicked anchor; with the limb tool, grows a limb
## (its tip stays where it was grown; use drag() to pull it out); with no tool, selects the handle under the click or
## clears the selection. Returns {ok, reason}.
func click_skin(screen_pos: Vector2) -> Dictionary:
	var r := press(screen_pos)
	release()
	return r


## A left drag: press at `from_screen`, move in `steps` moves to `to_screen`, release. One undo step. Returns the
## last op's {ok, reason} (the press's when nothing was dragged).
func drag(from_screen: Vector2, to_screen: Vector2, steps: int = 6) -> Dictionary:
	var r := press(from_screen)
	if dragging:
		for i in range(1, maxi(1, steps) + 1):
			var moved := drag_to(from_screen.lerp(to_screen, float(i) / maxi(1, steps)))
			if not moved.is_empty():
				r = moved
	release()
	return r


## Selects a handle by kind ("vertebra", "joint" or "part") and id (the original, not a copy or twin).
func select(kind: String, id: String) -> bool:
	for h in handles:
		if h["kind"] == kind and h["id"] == id and not h.get("copy", false) and not h.get("twin", false):
			selected = h
			_mark_dirty()
			return true
	return false


func undo() -> bool:
	var ok: bool = session.undo()
	if ok:
		selected = {}
		_mark_dirty()
	return ok


func redo() -> bool:
	var ok: bool = session.redo()
	if ok:
		selected = {}
		_mark_dirty()
	return ok


func remove_selected() -> Dictionary:
	if selected.is_empty():
		return _refuse("nothing selected")
	var r := {}
	match selected["kind"]:
		"vertebra": r = session.remove_vertebra(selected["id"])
		"joint": r = session.remove_joint(selected["limb"], selected["id"])
		"part", "turn": r = session.remove_part(selected["id"])
	if r["ok"]:
		selected = {}
	return _result(r)


## Adds a vertebra after the selected one, a joint after the selected joint, or a vertebra at the tail otherwise.
func insert_after_selected() -> Dictionary:
	if selected.is_empty() or selected["kind"] in ["part", "turn"]:
		return _result(session.insert_vertebra(session.working.vertebrae.size()))
	if selected["kind"] == "vertebra":
		return _result(session.insert_vertebra(session.working.vertebra_index(selected["id"]) + 1))
	return _result(session.insert_joint(selected["limb"], selected["id"]))


## Toggles the mirror of the selected limb (by one of its joints) or part.
func mirror_selected() -> Dictionary:
	if selected.is_empty():
		return _refuse("nothing selected")
	var desc = session.working
	match selected["kind"]:
		"joint":
			var limb: Dictionary = desc.limbs[desc.limb_index(selected["limb"])]
			return _result(session.set_limb_mirror(selected["limb"], not bool(limb["mirror"])))
		"part", "turn":
			var part: Dictionary = desc.parts.filter(func(x): return x["id"] == selected["id"])[0]
			return _result(session.set_part_mirror(selected["id"], not bool(part["mirror"])))
	return _refuse("a vertebra has no mirror")


## Thickens (delta > 0) or thins the selected vertebra or joint by 10% per step.
func thicken(delta: int) -> Dictionary:
	if selected.is_empty() or selected["kind"] in ["part", "turn"]:
		return _refuse("select a vertebra or joint to thicken")
	var desc = session.working
	var f := pow(ZOOM_STEP, delta)
	if selected["kind"] == "vertebra":
		var v: Dictionary = desc.vertebrae[desc.vertebra_index(selected["id"])]
		return _result(session.set_vertebra_radius(selected["id"], int(round(int(v["r"]) * f))))
	var limb: Dictionary = desc.limbs[desc.limb_index(selected["limb"])]
	for j in limb["joints"]:
		if j["id"] == selected["id"]:
			return _result(session.set_joint_radius(selected["limb"], selected["id"], int(round(int(j["r"]) * f))))
	return _refuse("no joint %s" % selected["id"])


## The test drive: the body as it stands walks, trots, runs and turns on the gait planner's legs in place of the
## editor view. A body with no legs is refused with the reason.
func test_drive(on: bool) -> Dictionary:
	if not on:
		if walker:
			walker.free()
			walker = null
		if rig:
			rig.visible = true
		handle_root.visible = true
		hud.set_test_drive(false)
		return {"ok": true, "reason": ""}
	if walker:
		return {"ok": true, "reason": ""}
	var desc = session.working
	var info: Dictionary = GaitBody.from_description(desc) if not desc.limbs.is_empty() else {"legs": []}
	if info["legs"].is_empty():
		hud.set_test_drive(false)
		return _refuse("no legs to walk on (a leg needs a knee and must reach the ground)")
	var mech = BodyMechanics.create("edited", info["body"], CreatureData.gait_table())
	walker = WalkerRig.new()
	walker.name = "Walker"
	rig_root.add_child(walker)
	walker.setup(desc, SkinCpu.build(desc, desc.preview_divisions(rules)),
			GaitPlanner.create(mech, Vector3.ZERO, 0.0), info, skin_color,
			AnchorResolver.resolve_all(desc, BodyField.from_description(desc), orientations), orientations)
	walker.body.use_skin_shader(_shader_params())
	if rig:
		rig.visible = false
	handle_root.visible = false
	_drive_t = 0.0
	hud.set_test_drive(true)
	return {"ok": true, "reason": "", "legs": info["legs"].size()}


## Commits: validates, charges the points and emits done_requested with the body dictionary and the points left.
## Returns {ok, reason, points_left}; a refused commit changes nothing. A body without legs cannot walk the world,
## so the first Done on one asks (NO_LEGS_TEXT); the next within REFUSAL_S goes anyway (E at the nest still evolves).
func finish() -> Dictionary:
	if int(session.preview()["phenotype"]["legs"]) == 0 and refusal_text != NO_LEGS_TEXT:
		_refuse(NO_LEGS_TEXT)
		return {"ok": false, "reason": NO_LEGS_TEXT, "points_left": session.available_points}
	var c: Dictionary = session.commit()
	if not c["ok"]:
		var reason: String = c["errors"][0] if not (c["errors"] as PackedStringArray).is_empty() else "cannot commit"
		_refuse(reason)
		return {"ok": false, "reason": reason, "points_left": c["points_left"]}
	var body: RefCounted = c["body"]
	_store_look(body.extra)
	var dict: Dictionary = body.to_dict()
	session = Session.new(body, rules, part_rules, costs, c["points_left"])
	selected = {}
	_mark_dirty()
	preset = ""
	done_requested.emit(dict, c["points_left"])
	return {"ok": true, "reason": "", "points_left": c["points_left"]}


## Back, progressive (Escape, the HUD's Back button and CreatureStage.press_escape all come here): a tool or a
## selection is cleared first; edits since the last Done ask once (UNSAVED_TEXT) and the next press within REFUSAL_S
## leaves; otherwise back_requested is emitted at once. Returns what happened: "cleared", "asked" or "left".
func back() -> String:
	if tool != "" or not selected.is_empty():
		choose_tool("")
		selected = {}
		_mark_dirty()
		return "cleared"
	if (not session._undo.is_empty() or preset != "") and refusal_text != UNSAVED_TEXT:
		_refuse(UNSAVED_TEXT)
		return "asked"
	back_requested.emit()
	return "left"


## Offers the preset creatures (CreatureStage does for a creature's first design, generation 1): the palette shows a
## "Start from" row and start_from_preset() is allowed.
func offer_presets(on: bool) -> void:
	presets_offered = on
	if on and hud.preset_count() == 0:
		var entries := []
		for n in CreatureData.preset_names():
			var p := CreatureData.preset(n)
			entries.append({"name": n, "title": String(p["title"]), "blurb": String(p["blurb"])})
		hud.setup_presets(entries)
	hud.show_presets(on)


## Starts the design over from a preset creature (owner playtest, 2026-10-24): its body and skin colour replace the
## working body at no cost, the points stay as they were, and undo starts afresh. Only while presets are offered.
func start_from_preset(preset_name: String) -> Dictionary:
	if not presets_offered:
		return _refuse("presets are for a new creature's first design")
	if not CreatureData.preset_names().has(preset_name):
		return _refuse("no preset %s" % preset_name)
	var body: RefCounted = CreatureData.preset_body(preset_name)
	var stored := String(body.extra.get(SKIN_COLOR_KEY, ""))
	_start_from(body, Color.html(stored) if Color.html_is_valid(stored) else SKIN_COLORS[0], Look.pattern_of(body.extra))
	preset = preset_name
	hud.set_preset(preset_name)
	return {"ok": true, "reason": ""}


## A random first design (owner ask, 2026-10-24: "a random button that will generate a random type of creature"):
## a preset drawn from `seed_value` (the clock when negative), dressed with extra parts the way the world's rivals
## are (CreatureWorldRules.draw_rival_body, so every result passes the rules), in a random swatch colour and coat.
## Like the presets, only on a new creature's first design. Returns {ok, reason, base}.
func start_random(seed_value: int = -1) -> Dictionary:
	if not presets_offered:
		return _refuse("a random creature is for a new creature's first design")
	var names: Array = CreatureData.preset_names()
	if names.is_empty():
		return _refuse("no presets to start from")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value >= 0 else Time.get_ticks_usec()
	var base := String(names[rng.randi_range(0, names.size() - 1)])
	var body: RefCounted = WorldRules.draw_rival_body(CreatureData.preset_body(base), rng, rules, part_rules, costs)
	var pattern := {}
	for key in Look.PATTERN_KEYS:
		pattern[key] = rng.randi_range(int(Look.PATTERN_RANGE[key][0]), int(Look.PATTERN_RANGE[key][1]))
	_start_from(body, SKIN_COLORS[rng.randi_range(0, SKIN_COLORS.size() - 1)], pattern)
	preset = base
	hud.set_preset("")
	return {"ok": true, "reason": "", "base": base}


## Starts a fresh session on `body` (keeping the points), in `color` and `pattern`.
func _start_from(body: RefCounted, color: Color, pattern: Dictionary) -> void:
	if walker != null:
		test_drive(false)
	session = Session.new(body, rules, part_rules, costs, session.available_points)
	skin_color = color
	skin_pattern = pattern
	_store_look(session.working.extra)
	hud.set_color(skin_color)
	selected = {}
	choose_tool("")
	_frame_body()
	_mark_dirty()
	_rebuild()


## The skin colour, from a swatch; the working body carries it as "skin_color".
func set_skin_color(color: Color) -> void:
	skin_color = color
	_store_look(session.working.extra)
	hud.set_color(color)
	if rig:
		rig.use_skin_shader(_shader_params())
	if walker:
		walker.body.use_skin_shader(_shader_params())


## One head shape dial (HeadShape field: snout, width, height, jaw, brow) to `value` per mille; a value outside the
## body rules is refused and the slider goes back.
func set_head_shape(key: String, value: int) -> Dictionary:
	var r: Dictionary = _result(session.set_head_shape(key, value))
	if not r["ok"]:
		hud.set_head_shape(session.head_shape())
	return r


## The screen position of a point in body space (the description's metres), for driving by the method twins.
func screen_of(body_point: Vector3) -> Vector2:
	return _unproject(body_point + _rig_offset)


## The screen position of a handle, or Vector2(-1, -1) when there is none.
func handle_screen(kind: String, id: String) -> Vector2:
	for h in handles:
		if h["kind"] == kind and h["id"] == id and not h.get("copy", false) and not h.get("twin", false):
			return _unproject(h["world"])
	return Vector2(-1, -1)


# Mouse paths (the twins above are built from these) -------------------------------------------------------------


## Left button down at a screen position: grab a handle, or add a part or grow a limb with the current tool.
func press(at: Vector2) -> Dictionary:
	var h := _handle_at(at)
	if not h.is_empty():
		selected = h
		dragging = true
		drag_plane = Plane(-_camera_xform().basis.z, h["world"])
		session.begin_gesture()
		_mark_dirty()
		return {"ok": true, "reason": "", "selected": h}
	selected = {}
	_mark_dirty()
	if tool == "":
		return {"ok": false, "reason": "no tool chosen"}
	var hit := _skin_hit(at)
	if not hit["hit"]:
		return _refuse("missed the body")
	if tool == "limb":
		return _grow_limb(hit)
	var a: Dictionary = Picking.anchor_for_part(session.working, part_rules[tool],
			Picking.anchor_at(session.working, hit["field"], hit["point"]))
	if a.has("reason"):
		return _refuse(a["reason"])
	a["scale"] = Picking.fit_scale(session.working, _reference_size_m, rules)
	var r: Dictionary = session.add_part(tool, a)
	if r["ok"]:
		selected = {"kind": "part", "id": r["part_id"], "twin": false}
	return _result(r)


## Limb tool: a new limb grows from the click and its tip follows the mouse until release, all one undo step.
func _grow_limb(hit: Dictionary) -> Dictionary:
	var desc = session.working
	var limb: Dictionary = Picking.limb_at(desc, rules, hit["point"], hit["normal"])
	if limb.has("reason"):
		return _refuse(limb["reason"])
	session.begin_gesture()
	var r: Dictionary = session.add_limb(limb["attach"], limb["joints"], limb["mirror"])
	if not r["ok"]:
		session.end_gesture()
		return _result(r)
	var joints: Array = session.working.limbs[session.working.limb_index(r["limb_id"])]["joints"]
	var tip: Dictionary = joints[-1]
	var world: Vector3 = Vector3(float(tip["p"][0]), float(tip["p"][1]), float(tip["p"][2])) * desc.scale_m() + _rig_offset
	selected = {"kind": "joint", "id": tip["id"], "limb": r["limb_id"], "copy": false, "twin": false, "world": world}
	dragging = true
	drag_plane = Plane(-_camera_xform().basis.z, world)
	return _result(r)


## The mouse moved to `at` with the button down: moves the selection. Returns the op's result, or {} when nothing
## was attempted.
func drag_to(at: Vector2) -> Dictionary:
	if not dragging:
		return {}
	var desc = session.working
	if selected["kind"] == "turn":
		return _drag_turn(at)
	if selected["kind"] == "part":
		var hit := _skin_hit(at)
		if not hit["hit"]:
			return {}
		var p: Vector3 = hit["point"]
		if selected["twin"]:
			p.x = -p.x
		var part: Dictionary = desc.parts.filter(func(x): return x["id"] == selected["id"])[0]
		var a: Dictionary = Picking.anchor_for_part(desc, part_rules[part["type"]], Picking.anchor_at(desc, hit["field"], p))
		if a.has("reason"):
			return _refuse(a["reason"])
		return _result(session.move_part(selected["id"], a))
	var ray := _ray(at)
	var origin: Vector3 = ray["origin"]
	var world = drag_plane.intersects_ray(origin, ray["normal"])
	if selected["kind"] == "vertebra":
		var v: Dictionary = desc.vertebrae[desc.vertebra_index(selected["id"])]
		if int(v["p"][0]) == 0:
			# Keep a middle-line vertebra on the middle line: drag in the X = 0 plane instead.
			world = Plane(Vector3.RIGHT, 0.0).intersects_ray(origin, ray["normal"])
		if world == null:
			return {}
		var q := _to_units(world)
		if int(v["p"][0]) == 0:
			q.x = 0
		return _result(session.move_vertebra(selected["id"], q))
	if world == null:
		return {}
	var q := _to_units(world)
	if selected["copy"]:
		q.x = -q.x
	return _result(session.move_joint(selected["limb"], selected["id"], q))


func release() -> void:
	if dragging:
		session.end_gesture()
	dragging = false
	_mark_dirty()


## The wheel at a screen position: over the selection's handle it resizes it (resize_selected: a vertebra or joint
## thickens or thins, a part grows or shrinks; a paid, undoable edit); anywhere else it zooms. Without a position it
## zooms.
func wheel(direction: int, at := Vector2(-INF, -INF)) -> void:
	var under := _handle_at(at) if at.is_finite() else {}
	var over_selection: bool = not under.is_empty() and _same(under, selected)
	if not over_selection:
		zoom(direction)
		return
	resize_selected(direction)


## Zooms in (direction > 0) or out one step, within ZOOM_MIN..ZOOM_MAX of the body's framing distance.
func zoom(direction: int) -> void:
	_distance *= 1.0 / ZOOM_STEP if direction > 0 else ZOOM_STEP
	if _frame_distance > 0.0:
		_distance = clampf(_distance, _frame_distance * ZOOM_MIN, _frame_distance * ZOOM_MAX)
	_update_camera()


## Grows (delta > 0) or shrinks the selection one step: a part's scale by PART_SCALE_STEP within the body rules'
## range (so feet and hooves can follow a big body), a vertebra's or joint's thickness as thicken() does.
func resize_selected(delta: int) -> Dictionary:
	if selected.is_empty():
		return _refuse("select something to resize")
	if not selected["kind"] in ["part", "turn"]:
		return thicken(delta)
	var desc = session.working
	var found: Array = desc.parts.filter(func(x): return x["id"] == selected["id"])
	if found.is_empty():
		return _refuse("no part %s" % selected["id"])
	var now := int(found[0]["scale"])
	var lo := int(session.rules.get("part_scale_min", 0))
	var hi := int(session.rules.get("part_scale_max", 1000000))
	var want := clampi(int(round(now * pow(PART_SCALE_STEP, delta))), lo, hi)
	if want == now:
		return _refuse("the part is already as %s as it goes" % ("big" if delta > 0 else "small"))
	return _result(session.scale_part(selected["id"], want))


## Orbits the camera by (yaw, pitch) radians.
func orbit(by: Vector2) -> void:
	_orbit += by
	_orbit.y = clampf(_orbit.y, PITCH_MIN, PITCH_MAX)
	_update_camera()


## Dragging the turn ring's handle: the part turns by the angle the mouse sweeps around its up axis.
func _drag_turn(at: Vector2) -> Dictionary:
	var origin: Vector3 = selected["origin"]
	var up: Vector3 = selected["up"]
	var ray := _ray(at)
	var hit = Plane(up, origin).intersects_ray(ray["origin"], ray["normal"])
	if hit == null:
		return {}
	if not selected.has("from"):
		var part: Dictionary = session.working.parts.filter(func(x): return x["id"] == selected["id"])[0]
		selected["from"] = selected["world"] - origin
		selected["turn0"] = int(part["turn"])
	var v0: Vector3 = selected["from"]
	var v1: Vector3 = hit - origin
	var delta := rad_to_deg(atan2(up.dot(v0.cross(v1)), v0.dot(v1)))
	return _result(session.orient_part(selected["id"], {"turn": int(round(selected["turn0"] + delta))}))


## Q/E turn the selected part 10 degrees left or right about its up axis, R/F tilt it.
func turn_selected(key: Key) -> Dictionary:
	if selected.is_empty() or not selected["kind"] in ["part", "turn"]:
		return _refuse("select a part to turn")
	var part: Dictionary = session.working.parts.filter(func(x): return x["id"] == selected["id"])[0]
	var step := 10 if key in [KEY_E, KEY_R] else -10
	var axis := "turn" if key in [KEY_Q, KEY_E] else "tilt"
	return _result(session.orient_part(selected["id"], {axis: int(part[axis]) + step}))


# Results ---------------------------------------------------------------------------------------------------------


## Notes an op's result: a success rebuilds, a refusal shows its reason.
func _result(r: Dictionary) -> Dictionary:
	if r["ok"]:
		_mark_dirty()
	else:
		_refuse(String(r["reason"]))
	return r


func _refuse(reason: String) -> Dictionary:
	refusal_text = reason
	_refusal_t = 0.0
	hud.set_refusal(refusal_text)
	return {"ok": false, "reason": reason}


## Rebuilds at once when the gesture is not a drag in progress (a drag rebuilds the handles each move anyway; the
## skin coalesces on the worker).
func _mark_dirty() -> void:
	_dirty = true
	_rebuild()


func _handle_at(at: Vector2) -> Dictionary:
	if walker:
		return {}
	var best := {}
	var best_d := HANDLE_PICK_PX
	for h in handles:
		var px := _unproject(h["world"])
		if is_nan(px.x):
			continue
		var d := px.distance_to(at)
		if d < best_d:
			best_d = d
			best = h
	return best


## The skin under a screen position: {hit, point (body space), normal, field}.
func _skin_hit(at: Vector2) -> Dictionary:
	var field = BodyField.from_description(session.working)
	var ray := _ray(at)
	var origin: Vector3 = ray["origin"] - _rig_offset
	var hit: Dictionary = Picking.ray_to_skin(field, origin, ray["normal"], 50.0)
	hit["field"] = field
	return hit


## The camera's world transform (its local one outside a live tree, where the editor sits at the origin).
func _camera_xform() -> Transform3D:
	return camera.global_transform if camera.is_inside_tree() else camera.transform


## The screen in pixels: the live viewport, or the project's window when the scene is driven outside the tree (the
## test runner has no live viewport).
func _screen_size() -> Vector2:
	if is_inside_tree():
		return get_viewport().get_visible_rect().size
	return Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920)),
			float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080)))


## Camera3D.unproject_position from the camera's own fov (keep height) and transform, so it also works outside the
## tree. A point behind the camera comes back as NaN.
func _unproject(world: Vector3) -> Vector2:
	var size := _screen_size()
	var view := _camera_xform().affine_inverse() * world
	if view.z >= 0.0:
		return Vector2(NAN, NAN)
	var clip := Projection.create_perspective(camera.fov, size.aspect(), camera.near, camera.far) * Vector4(view.x, view.y, view.z, 1.0)
	var ndc := Vector2(clip.x, clip.y) / clip.w
	return Vector2((ndc.x + 1.0) * 0.5 * size.x, (1.0 - ndc.y) * 0.5 * size.y)


## The ray through a screen position: {origin, normal} in world space (Camera3D.project_ray_* outside the tree).
func _ray(at: Vector2) -> Dictionary:
	var size := _screen_size()
	var ndc := Vector2(at.x / size.x * 2.0 - 1.0, 1.0 - at.y / size.y * 2.0)
	var inv := Projection.create_perspective(camera.fov, size.aspect(), camera.near, camera.far).inverse()
	var near := inv * Vector4(ndc.x, ndc.y, -1.0, 1.0)
	var view := Vector3(near.x, near.y, near.z) / near.w
	var xform := _camera_xform()
	var normal := (xform.basis * view).normalized()
	return {"origin": xform.origin + xform.basis * view, "normal": normal}


func _to_units(world: Vector3) -> Vector3i:
	var p: Vector3 = (world - _rig_offset) / session.working.scale_m()
	return Vector3i(int(round(p.x)), int(round(p.y)), int(round(p.z)))


# Frame -----------------------------------------------------------------------------------------------------------


func _process(delta: float) -> void:
	if session == null:
		return
	if refusal_text != "":
		_refusal_t += delta
		if _refusal_t >= REFUSAL_S:
			refusal_text = ""
			hud.set_refusal("")
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() > STICK_DEADZONE:
		orbit(Vector2(-stick.x, stick.y) * ORBIT_STICK_RATE * delta)
	if _dirty:
		_rebuild()
	_collect_skin()
	if walker:
		_drive_t += delta
		var input := _drive_input(fmod(_drive_t, float(DRIVE_PROGRAM[-1][0])))
		walker.planner.step(delta, input.x, input.y)
		if walker.is_inside_tree():
			walker.sync(delta)
	_update_camera()


## (throttle, turn) of the looping test drive at time t.
static func _drive_input(t: float) -> Vector2:
	for leg in DRIVE_PROGRAM:
		if t < float(leg[0]):
			return Vector2(float(leg[1]), float(leg[2]))
	return Vector2.ZERO


func _update_camera() -> void:
	var focus := _focus
	if walker:
		focus = walker.planner.position + Vector3(0.0, _focus.y, 0.0)
		floor_disc.position = Vector3(focus.x, floor_disc.position.y, focus.z)   # the floor keeps up with the walk
	var at := focus + _distance * Vector3(sin(_orbit.x) * cos(_orbit.y), sin(_orbit.y), cos(_orbit.x) * cos(_orbit.y))
	camera.transform = Transform3D(Basis.looking_at(focus - at, Vector3.UP), at)
	_scale_handles()


func _refresh_hud() -> void:
	var pv: Dictionary = session.preview()
	var now: Dictionary = pv["phenotype"]
	var parts_count: int = (now["parts"] as Dictionary).values().reduce(func(a, b): return a + b, 0)
	hud.set_points(session.available_points, pv["cost"], pv["affordable"])
	var lines := PackedStringArray([
		"Length  %.2f m" % now["length_m"],
		"Mass  %.1f kg" % now["mass_kg"],
		"Legs  %d   ·   limbs  %d" % [now["legs"], now["limbs"]],
		"Parts  %d   ·   bones  %d" % [parts_count, now["bones"]],
	])
	if _stats_script != null and not _stage_tuning.is_empty():
		var s: Dictionary = _stats_script.of(session.working, part_rules, CreatureData.gait_table(), _stage_tuning)
		lines.append("Speed  %.1f m/s   ·   health  %d" % [float(s.get("speed_mps", 0.0)), int(s.get("max_health", 0))])
		lines.append("Bite  %d   ·   sight  %.0f m" % [int(s.get("bite_power", 0)), float(s.get("sight_m", 0.0))])
	lines.append("Selected  %s" % (("%s %s" % [selected["kind"], selected["id"]]) if not selected.is_empty() else "-"))
	hud.set_stats(lines)
	hud.set_undo_redo(not session._undo.is_empty(), not session._redo.is_empty())
	hud.set_head_shape(session.head_shape())


func _exit_tree() -> void:
	_stop_worker()


func _notification(what: int) -> void:
	# Freed outside a live tree (the test runner): the worker holds a call on this node until it is joined.
	if what == NOTIFICATION_PREDELETE:
		_stop_worker()


## Joins the skin worker (it frees its GPU device).
func _stop_worker() -> void:
	if _worker != null:
		_worker.stop()
		_worker = null
