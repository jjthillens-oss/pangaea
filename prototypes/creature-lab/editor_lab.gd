extends Node3D
## Editor Lab (PROPOSED): drag a Stage 1 body's vertebrae, joints and parts, with the skin rebuilt live. A thin shell
## over the scene-free editor core (domain/creature_editor_session.gd, domain/editor_picking.gd); the game's editor
## UI would host the same core. Command line (after --): --body=NAME (default s1_quadruped), --points=N,
## --divisions=N (skin grid), --sync (build the skin on the main thread), --demo (a scripted run of edits for a clip;
## quits when done).
##
## Mouse: left-drag a handle (orange vertebra, blue joint, green part) to move it; with a part tool chosen, left-click
## the skin to add one. Wheel over the selected vertebra or joint: thicker or thinner; elsewhere: zoom. Right-drag:
## orbit. A selected part shows a yellow ring: drag its handle round to turn the part. Keys: 1-5 part tools (eye, beak, fin, foot, horn), 6 or L limb tool (click the skin and drag the new limb's
## tip out), 0 no tool, Q/E turn and R/F tilt the selected part, Delete removes the selection, Insert adds a
## vertebra or joint after the selection, Ctrl+Z / Ctrl+Y undo and redo, Enter commits.
##
## A vertebra on the middle line stays on it while dragged, so a symmetric body stays symmetric. Dragging a mirror
## copy's joint or a part's twin moves the original, mirrored.

const Lab := preload("res://lab_spine.gd")
const SkinCpu := preload("res://skin/skin_cpu.gd")
const SpineRig := preload("res://rig/spine_rig.gd")
const BodyField := preload("res://domain/body_field.gd")
const AnchorResolver := preload("res://domain/anchor_resolver.gd")
const Session := preload("res://domain/creature_editor_session.gd")
const Picking := preload("res://domain/editor_picking.gd")
const BodyCodec := preload("res://domain/body_codec.gd")

const TOOLS := ["eye", "beak", "fin", "foot", "horn"]
const HANDLE_PICK_PX := 16.0
const COLORS := {"vertebra": Color(1.0, 0.6, 0.15), "joint": Color(0.3, 0.7, 1.0), "part": Color(0.4, 1.0, 0.5),
		"turn": Color(1.0, 0.9, 0.2)}
const BODY_COLOR := Color(0.36, 0.66, 0.86)

var body_name := "s1_quadruped"
var points := 100
var divisions := 0  # 0: the body's own preview grid (BodyDescription.preview_divisions)
var demo := false

var session: RefCounted
var part_rules := {}
var orientations := {}
var rig: Node3D
var handles: Array = []  # {kind, id, limb, copy, twin, world: Vector3}
var handle_root: Node3D
var camera: Camera3D
var hud: Label
var gpu: RefCounted
var tool := ""
var selected := {}
var dragging := false
var drag_plane := Plane()
var message := ""
var skin_ms := 0.0
var _dirty := true
## Skin builds on a worker thread (interactive runs; the demo builds in step).
var threaded := true
## --async: the demo also builds on the worker thread (a check of the threaded path).
var async_demo := false
var _worker: Thread
var _mutex := Mutex.new()
var _signal := Semaphore.new()
var _job := {}
var _built := {}
var _quit := false
var _building := false
var _orbit := Vector2(2.05, 0.3)
var _distance := 2.6
var _orbiting := false
var _focus := Vector3.ZERO
var _rig_offset := Vector3.ZERO
var _time := 0.0
var _demo_steps: Array = []
var _sphere: SphereMesh


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"body": body_name = kv[1]
			"points": points = int(kv[1])
			"divisions": divisions = int(kv[1])
			"demo": demo = true
			"sync": threaded = false
			"async": async_demo = true
	part_rules = Lab.part_rules()
	orientations = Lab.part_orientations(part_rules)
	session = Session.new(Lab.body(body_name), Lab.rules(), part_rules, Lab.editor_costs(), points)
	if demo:
		threaded = async_demo
	if threaded:
		# A local GPU device belongs to the thread that made it, so the worker makes and keeps its own.
		_worker = Thread.new()
		_worker.start(_work)
	else:
		gpu = _make_gpu()
	var box: AABB = session.working.bounds_m()
	_rig_offset = Vector3(0.0, -box.position.y + 0.01, 0.0)
	_focus = box.get_center() + _rig_offset
	_distance = 2.2 * box.get_longest_axis_size()
	_build_world()
	if demo:
		_demo_steps = _demo_script()


# Rebuild ---------------------------------------------------------------------------------------------------------


## Rebuilds the creature from the working body. Interactive runs build the skin on a worker thread, so a drag never
## waits on it: the handles follow the mouse at once and the skin catches up (an edit made while a build runs is built
## next). The demo builds in step, so every movie frame shows the edit it describes.
func _rebuild() -> void:
	_dirty = false
	var desc = session.working
	var placed := AnchorResolver.resolve_all(desc, BodyField.from_description(desc), orientations)
	_rebuild_handles(desc, placed)
	if not threaded:
		_present(_build_skin(desc.to_dict()))
		return
	# The newest body replaces any the worker has not started on.
	_mutex.lock()
	_job = desc.to_dict()
	_building = true
	_mutex.unlock()
	_signal.post()


static func _make_gpu() -> RefCounted:
	var g = load("res://skin/skin_gpu.gd").new()
	return g if g.is_available() else null


## The worker thread: builds the newest body it is given until told to quit; owns the GPU device.
func _work() -> void:
	gpu = _make_gpu()
	while true:
		_signal.wait()
		_mutex.lock()
		var job: Dictionary = _job
		_job = {}
		var quit := _quit
		_mutex.unlock()
		if quit:
			break
		if job.is_empty():
			continue
		var built := _build_skin(job)
		_mutex.lock()
		_built = built
		_mutex.unlock()
	if gpu:
		gpu.free_resources()
		gpu = null


func _build_skin(body: Dictionary) -> Dictionary:
	var desc = BodyCodec.from_dict(body)
	var t0 := Time.get_ticks_usec()
	var d: int = divisions if divisions > 0 else desc.preview_divisions(session.rules)
	var arrays: Dictionary = gpu.build(desc, d) if gpu else SkinCpu.build(desc, mini(d, 32))
	return {"desc": desc, "arrays": arrays, "ms": (Time.get_ticks_usec() - t0) / 1000.0}


func _present(built: Dictionary) -> void:
	var desc = built["desc"]
	skin_ms = built["ms"]
	if rig:
		rig.free()
	rig = SpineRig.new()
	add_child(rig)
	rig.position = _rig_offset
	rig.setup(desc, built["arrays"], BODY_COLOR)
	rig.add_parts(AnchorResolver.resolve_all(desc, BodyField.from_description(desc), orientations), orientations)
	rig.use_skin_shader({"color_base": BODY_COLOR, "pattern_seed": 3, "coat_pattern": 2, "detail_pattern": 1})


func _collect_skin() -> void:
	if not threaded:
		return
	_mutex.lock()
	var built := _built
	_built = {}
	if not built.is_empty():
		_building = not _job.is_empty()
	_mutex.unlock()
	if not built.is_empty():
		_present(built)


func _rebuild_handles(desc: RefCounted, placed: Array) -> void:
	handles.clear()
	for c in handle_root.get_children():
		c.free()
	var r: float = 0.018 * desc.bounds_m().get_longest_axis_size()
	for i in desc.vertebrae.size():
		_add_handle({"kind": "vertebra", "id": desc.vertebrae[i]["id"]}, desc.position_m(i), r)
	var chains: Array = desc.limb_chains()
	for c in chains.size():
		var copy: bool = c > 0 and chains[c - 1]["source"] == chains[c]["source"]
		var limb: Dictionary = desc.limbs[desc.limb_index(String(chains[c]["source"]))]
		var pts: PackedVector3Array = chains[c]["points"]
		for k in range(1, pts.size()):  # joint 0 rides on its vertebra
			_add_handle({"kind": "joint", "id": limb["joints"][k]["id"], "limb": limb["id"], "copy": copy}, pts[k], r)
	for e in placed:
		var t: Transform3D = e["transform"]
		_add_handle({"kind": "part", "id": e["part"], "twin": e["twin"]}, t.origin, 1.15 * r)
		# The selected part's turn ring: a circle around its up axis, with a handle on its side to drag round.
		if not e["twin"] and not selected.is_empty() and selected["kind"] in ["part", "turn"] and selected["id"] == e["part"]:
			var up := t.basis.y.normalized()
			var side := t.basis.x.normalized()
			var ring_r := 5.0 * r
			_add_ring(t.origin, up, side, ring_r)
			_add_handle({"kind": "turn", "id": e["part"], "origin": t.origin + _rig_offset, "up": up},
					t.origin + side * ring_r, r)


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


func _add_handle(h: Dictionary, body_pos: Vector3, r: float) -> void:
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
	mi.scale = Vector3.ONE * r * (1.6 if is_sel else 1.0)
	handle_root.add_child(mi)


static func _same(a: Dictionary, b: Dictionary) -> bool:
	return not b.is_empty() and a["kind"] == b["kind"] and a["id"] == b["id"] and a.get("copy", false) == b.get("copy", false) \
			and a.get("twin", false) == b.get("twin", false)


# Input (also driven by the demo) ----------------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if demo:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					press(mb.position)
				else:
					release()
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					wheel(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			_orbit += Vector2(-mm.relative.x, mm.relative.y) * 0.008
			_orbit.y = clampf(_orbit.y, -0.2, 1.4)
		elif dragging:
			drag_to(mm.position)
	elif event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if k.ctrl_pressed and k.keycode == KEY_Z:
			_report(session.undo(), "undo")
		elif k.ctrl_pressed and k.keycode == KEY_Y:
			_report(session.redo(), "redo")
		elif k.keycode >= KEY_1 and k.keycode <= KEY_5:
			tool = TOOLS[k.keycode - KEY_1]
		elif k.keycode == KEY_6 or k.keycode == KEY_L:
			tool = "limb"
		elif k.keycode == KEY_0:
			tool = ""
		elif k.keycode in [KEY_Q, KEY_E, KEY_R, KEY_F]:
			turn_selected(k.keycode)
		elif k.keycode == KEY_DELETE:
			remove_selected()
		elif k.keycode == KEY_INSERT:
			insert_after_selected()
		elif k.keycode == KEY_ENTER:
			commit()


## Left button down at a screen position: grab a handle, or add a part with the current tool.
func press(at: Vector2) -> void:
	var h := _handle_at(at)
	if not h.is_empty():
		selected = h
		dragging = true
		drag_plane = Plane(-camera.global_transform.basis.z, h["world"])
		session.begin_gesture()
		_dirty = true
		return
	selected = {}
	_dirty = true
	if tool == "":
		return
	var hit := _skin_hit(at)
	if not hit["hit"]:
		message = "missed the body"
		return
	if tool == "limb":
		_grow_limb(hit)
		return
	var a: Dictionary = Picking.anchor_for_part(session.working, part_rules[tool],
			Picking.anchor_at(session.working, hit["field"], hit["point"]))
	if a.has("reason"):
		message = a["reason"]
		return
	var r: Dictionary = session.add_part(tool, a)
	_result(r, "added %s" % tool)
	if r["ok"]:
		selected = {"kind": "part", "id": r["part_id"], "twin": false}


## Limb tool: a new limb grows from the click and its tip follows the mouse until release, all one undo step.
func _grow_limb(hit: Dictionary) -> void:
	var desc = session.working
	var limb: Dictionary = Picking.limb_at(desc, session.rules, hit["point"], hit["normal"])
	session.begin_gesture()
	var r: Dictionary = session.add_limb(limb["attach"], limb["joints"], limb["mirror"])
	_result(r, "grew a limb")
	if not r["ok"]:
		session.end_gesture()
		return
	var joints: Array = session.working.limbs[session.working.limb_index(r["limb_id"])]["joints"]
	var tip: Dictionary = joints[-1]
	var world: Vector3 = Vector3(float(tip["p"][0]), float(tip["p"][1]), float(tip["p"][2])) * desc.scale_m() + _rig_offset
	selected = {"kind": "joint", "id": tip["id"], "limb": r["limb_id"], "copy": false, "twin": false, "world": world}
	dragging = true
	drag_plane = Plane(-camera.global_transform.basis.z, world)


func drag_to(at: Vector2) -> void:
	if not dragging:
		return
	var desc = session.working
	if selected["kind"] == "turn":
		_drag_turn(at)
		return
	if selected["kind"] == "part":
		var hit := _skin_hit(at)
		if not hit["hit"]:
			return
		var p: Vector3 = hit["point"]
		if selected["twin"]:
			p.x = -p.x
		var part: Dictionary = desc.parts.filter(func(x): return x["id"] == selected["id"])[0]
		var a: Dictionary = Picking.anchor_for_part(desc, part_rules[part["type"]], Picking.anchor_at(desc, hit["field"], p))
		if a.has("reason"):
			message = a["reason"]
			return
		_result(session.move_part(selected["id"], a), "")
		return
	var origin := camera.project_ray_origin(at)
	var world = drag_plane.intersects_ray(origin, camera.project_ray_normal(at))
	if selected["kind"] == "vertebra":
		var v: Dictionary = desc.vertebrae[desc.vertebra_index(selected["id"])]
		if int(v["p"][0]) == 0:
			# Keep a middle-line vertebra on the middle line: drag in the X = 0 plane instead.
			world = Plane(Vector3.RIGHT, 0.0).intersects_ray(origin, camera.project_ray_normal(at))
		if world == null:
			return
		var q := _to_units(world)
		if int(v["p"][0]) == 0:
			q.x = 0
		_result(session.move_vertebra(selected["id"], q), "")
	else:
		if world == null:
			return
		var q := _to_units(world)
		if selected["copy"]:
			q.x = -q.x
		_result(session.move_joint(selected["limb"], selected["id"], q), "")


func release() -> void:
	if dragging:
		session.end_gesture()
	dragging = false


func wheel(direction: int) -> void:
	if selected.is_empty() or selected["kind"] == "part":
		_distance *= 0.9 if direction > 0 else 1.1
		return
	var desc = session.working
	var f := 1.1 if direction > 0 else 1.0 / 1.1
	if selected["kind"] == "vertebra":
		var v: Dictionary = desc.vertebrae[desc.vertebra_index(selected["id"])]
		_result(session.set_vertebra_radius(selected["id"], int(round(int(v["r"]) * f))), "")
	else:
		var limb: Dictionary = desc.limbs[desc.limb_index(selected["limb"])]
		for j in limb["joints"]:
			if j["id"] == selected["id"]:
				_result(session.set_joint_radius(selected["limb"], selected["id"], int(round(int(j["r"]) * f))), "")


## Dragging the turn ring's handle: the part turns by the angle the mouse sweeps around its up axis.
func _drag_turn(at: Vector2) -> void:
	var origin: Vector3 = selected["origin"]
	var up: Vector3 = selected["up"]
	var hit = Plane(up, origin).intersects_ray(camera.project_ray_origin(at), camera.project_ray_normal(at))
	if hit == null:
		return
	if not selected.has("from"):
		var part: Dictionary = session.working.parts.filter(func(x): return x["id"] == selected["id"])[0]
		selected["from"] = selected["world"] - origin
		selected["turn0"] = int(part["turn"])
	var v0: Vector3 = selected["from"]
	var v1: Vector3 = hit - origin
	var delta := rad_to_deg(atan2(up.dot(v0.cross(v1)), v0.dot(v1)))
	_result(session.orient_part(selected["id"], {"turn": int(round(selected["turn0"] + delta))}), "")


## Q/E turn the selected part 10 degrees left or right about its up axis, R/F tilt it.
func turn_selected(key: Key) -> void:
	if selected.is_empty() or selected["kind"] != "part":
		return
	var part: Dictionary = session.working.parts.filter(func(x): return x["id"] == selected["id"])[0]
	var step := 10 if key in [KEY_E, KEY_R] else -10
	var axis := "turn" if key in [KEY_Q, KEY_E] else "tilt"
	_result(session.orient_part(selected["id"], {axis: int(part[axis]) + step}), "%s %+d" % [axis, step])


func remove_selected() -> void:
	if selected.is_empty():
		return
	match selected["kind"]:
		"vertebra": _result(session.remove_vertebra(selected["id"]), "removed %s" % selected["id"])
		"joint": _result(session.remove_joint(selected["limb"], selected["id"]), "removed %s" % selected["id"])
		"part": _result(session.remove_part(selected["id"]), "removed %s" % selected["id"])
	selected = {}


func insert_after_selected() -> void:
	if selected.is_empty() or selected["kind"] == "part":
		_result(session.insert_vertebra(session.working.vertebrae.size()), "added a vertebra at the tail")
		return
	if selected["kind"] == "vertebra":
		_result(session.insert_vertebra(session.working.vertebra_index(selected["id"]) + 1), "added a vertebra")
	else:
		_result(session.insert_joint(selected["limb"], selected["id"]), "added a joint")


func commit() -> void:
	var c: Dictionary = session.commit()
	if c["ok"]:
		message = "committed: %d points left" % c["points_left"]
		session = Session.new(c["body"], session.rules, part_rules, session.costs, c["points_left"])
	else:
		message = "commit refused: %s" % c["errors"][0]
	_dirty = true


func _report(ok: bool, what: String) -> void:
	message = what if ok else "nothing to %s" % what
	_dirty = _dirty or ok


func _result(r: Dictionary, what: String) -> void:
	if r["ok"]:
		message = what if what != "" else message
		_dirty = true
	else:
		message = "refused: %s" % r["reason"]


func _handle_at(at: Vector2) -> Dictionary:
	var best := {}
	var best_d := HANDLE_PICK_PX
	for h in handles:
		if camera.is_position_behind(h["world"]):
			continue
		var d := camera.unproject_position(h["world"]).distance_to(at)
		if d < best_d:
			best_d = d
			best = h
	return best


## The skin under a screen position: {hit, point (body space), field}.
func _skin_hit(at: Vector2) -> Dictionary:
	var field = BodyField.from_description(session.working)
	var origin := camera.project_ray_origin(at) - _rig_offset
	var hit: Dictionary = Picking.ray_to_skin(field, origin, camera.project_ray_normal(at), 50.0)
	hit["field"] = field
	return hit


func _to_units(world: Vector3) -> Vector3i:
	var p: Vector3 = (world - _rig_offset) / session.working.scale_m()
	return Vector3i(int(round(p.x)), int(round(p.y)), int(round(p.z)))


# Frame -----------------------------------------------------------------------------------------------------------


func _process(delta: float) -> void:
	_time += delta
	if demo:
		_run_demo()
	if _dirty:
		_rebuild()
	_collect_skin()
	camera.position = _focus + _distance * Vector3(sin(_orbit.x) * cos(_orbit.y), sin(_orbit.y), cos(_orbit.x) * cos(_orbit.y))
	camera.look_at(_focus, Vector3.UP)
	var pv: Dictionary = session.preview()
	var now: Dictionary = pv["phenotype"]
	var was: Dictionary = pv["current"]
	var lines := PackedStringArray([
		"EDITOR LAB  %s   tool: %s   skin %s %.0f ms%s" % [body_name, tool if tool != "" else "none",
				"GPU" if gpu else "GDScript", skin_ms, "  (building)" if _building else ""],
		"cost %d of %d points%s" % [pv["cost"], points, "" if pv["affordable"] else "  (too many)"],
		"length %.2f m (was %.2f)   mass %.1f kg (was %.1f)   legs %d   bones %d   parts %d" % [now["length_m"],
				was["length_m"], now["mass_kg"], was["mass_kg"], now["legs"], now["bones"],
				(now["parts"] as Dictionary).values().reduce(func(a, b): return a + b, 0)],
		"selected: %s" % (("%s %s" % [selected["kind"], selected["id"]]) if not selected.is_empty() else "-"),
		message])
	hud.text = "\n".join(lines)


# Demo ------------------------------------------------------------------------------------------------------------


## [time, Callable] steps acting through the same screen-space calls as the mouse.
func _demo_script() -> Array:
	var steps := []
	# A drag from a handle by a body-space offset (metres), through screen positions like the mouse.
	var drag := func(t0: float, t1: float, find: Callable, offset: Vector3) -> void:
		var state := {}
		steps.append([t0, func():
			state["at"] = find.call()
			press(camera.unproject_position(state["at"]))])
		for i in range(1, 21):
			steps.append([lerpf(t0, t1, i / 20.0), func():
				drag_to(camera.unproject_position(state["at"] + offset * (i / 20.0)))])
		steps.append([t1 + 0.01, func(): release()])
	var vertebra := func(id: String) -> Callable:
		return func(): return handles.filter(func(h): return h["kind"] == "vertebra" and h["id"] == id)[0]["world"]
	var joint := func(id: String) -> Callable:
		return func(): return handles.filter(func(h): return h["kind"] == "joint" and h["id"] == id and not h["copy"])[0]["world"]
	var part := func(type: String) -> Callable:
		return func():
			var ids: Array = session.working.parts.filter(func(p): return p["type"] == type).map(func(p): return p["id"])
			return handles.filter(func(h): return h["kind"] == "part" and h["id"] == ids[-1] and not h["twin"])[0]["world"]
	steps.append([0.6, func(): message = "drag the head up"])
	drag.call(0.8, 2.0, vertebra.call("v_1"), Vector3(0, 0.1, -0.04))
	steps.append([2.4, func(): message = "drag a knee forward (the foot comes along)"])
	drag.call(2.6, 3.6, joint.call("j_2"), Vector3(0, 0, -0.12))
	steps.append([4.0, func():
		message = "thicken the chest"
		selected = handles.filter(func(h): return h["id"] == "v_4")[0]
		_dirty = true])
	for i in 3:
		steps.append([4.3 + 0.25 * i, func(): wheel(1)])
	steps.append([5.6, func():
		tool = "fin"
		message = "fin tool: click the back"])
	steps.append([6.0, func():
		var top: Vector3 = vertebra.call("v_5").call() + Vector3(0, 0.135, 0)
		press(camera.unproject_position(top))
		release()])
	steps.append([6.8, func():
		tool = ""
		message = "drag the fin along the back"])
	drag.call(7.0, 8.2, part.call("fin"), Vector3(0, 0, 0.3))
	steps.append([8.6, func():
		tool = "limb"
		message = "limb tool: drag a pair of arms out of the neck"])
	var arm := {}
	steps.append([9.0, func():
		var neck: Vector3 = vertebra.call("v_2").call()
		var r: float = session.working.radius_m(1)
		press(camera.unproject_position(neck + Vector3(0.9 * r, -0.2 * r, 0.0)))
		arm["at"] = selected.get("world", neck)])
	for i in range(1, 21):
		steps.append([9.0 + 0.06 * i, func(): drag_to(camera.unproject_position(arm["at"] + Vector3(0.05, -0.12, -0.18) * (i / 20.0)))])
	steps.append([10.3, func():
		release()
		tool = ""])
	steps.append([10.6, func():
		message = "turn a horn with its ring (its record allows 60 degrees)"
		selected = handles.filter(func(h): return h["kind"] == "part" and h["id"] == "p_3" and not h["twin"])[0]
		_dirty = true])
	var spin := {}
	steps.append([11.0, func():
		var ring: Dictionary = handles.filter(func(h): return h["kind"] == "turn")[0]
		spin["at"] = ring["world"]
		spin["origin"] = ring["origin"]
		spin["up"] = ring["up"]
		press(camera.unproject_position(ring["world"]))])
	for i in range(1, 25):
		steps.append([11.0 + 0.05 * i, func():
			var v: Vector3 = spin["at"] - spin["origin"]
			drag_to(camera.unproject_position(spin["origin"] + v.rotated(spin["up"], deg_to_rad(-4.0 * i))))])
	steps.append([12.3, func(): release()])
	steps.append([12.4, func(): message = "stretch the tail: past the limit is refused"])
	drag.call(12.6, 13.6, vertebra.call("v_9"), Vector3(0, 0.15, 1.2))
	steps.append([14.0, func(): _report(session.undo(), "undo")])
	steps.append([14.6, func(): _report(session.redo(), "redo")])
	steps.append([15.4, func(): commit()])
	steps.append([17.0, func(): get_tree().quit()])
	return steps


func _run_demo() -> void:
	_orbit.x = 2.05 + 0.15 * sin(0.25 * _time)
	while not _demo_steps.is_empty() and _demo_steps[0][0] <= _time:
		_demo_steps.pop_front()[1].call()
		if _dirty:
			_rebuild()


# World -----------------------------------------------------------------------------------------------------------


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.5, 0.78)
	sky_mat.sky_horizon_color = Color(0.72, 0.8, 0.88)
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.29, 0.27)
	mat.roughness = 0.95
	plane.material = mat
	ground.mesh = plane
	add_child(ground)
	camera = Camera3D.new()
	camera.fov = 40.0
	add_child(camera)
	handle_root = Node3D.new()
	add_child(handle_root)
	_sphere = SphereMesh.new()
	_sphere.radius = 1.0
	_sphere.height = 2.0
	_sphere.radial_segments = 12
	_sphere.rings = 6
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 17)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 5)
	layer.add_child(hud)


func _exit_tree() -> void:
	if _worker != null:
		_mutex.lock()
		_quit = true
		_mutex.unlock()
		_signal.post()
		_worker.wait_to_finish()
	elif gpu:
		gpu.free_resources()
	load("res://rig/part_library.gd").clear()
