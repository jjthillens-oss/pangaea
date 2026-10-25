extends SceneTree
## Review frames for the more-parts job (docs/art/creature_parts_more.md), taken in the real creature editor
## (game/scenes/creature/creature_editor.tscn) so every part is seen as the game places, rigs and lights it.
## Run under Xvfb (docs/TOOLCHAIN.md):
##   xvfb-run -a -s "-screen 0 1920x1080x24" GODOT --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 1920x1080 --fixed-fps 60 \
##     --script res://tools/godot/more_parts_shots.gd -- --out=DIR --mode=palette|creatures [--set=before|after] \
##     [--presets=a,b,c] [--showcase=PATH]
##
## --mode=palette opens the quadruped starter body with 150 points, waits until PartIcons has drawn every tool's icon
##   and saves one frame per palette tab: <set>_palette_<tab>.png.
## --mode=creatures opens each preset (CreatureData.preset_body) and saves, with the HUD and the edit handles hidden:
##   <set>_<name>_game.png    the world camera's distance (clamp(2.4 x body length, 2.6, 12) m, creature_world.gd),
##                            pitch (16 degrees) and fov (50), from behind and to the side, as the player sees it
##                            in the world;
##   <set>_<name>_front.png   the same distance and pitch from the front three-quarter (mouths and eyes);
##   <set>_<name>_close.png   0.45 x that distance, front three-quarter, on the head;
##   <set>_<name>_side.png    a level side profile of the head at 0.3 x that distance (which way mouths and eyes
##                            point).
## --showcase=PATH (res:// or absolute) reads a JSON list of {name, preset, parts: [part dict, ...], swap: {old type:
##   new type}}: the preset's parts, with swapped types (their handles reset to rest), plus these, so a new part is
##   seen on a real body. It changes the bodies in memory only, never presets.json. Without it the bodies are the
##   unmodified presets.
## --cone-fix-preview (review only) turns the forward_cone parts (mouths and eyes) on the rig the way the proposed
##   frame fix would, to check they read right once it lands; use a distinct --set name for those frames.

const EDITOR_SCENE := "res://game/scenes/creature/creature_editor.tscn"
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const BodyField := preload("res://game/domain/creature/body_field.gd")
const AnchorResolver := preload("res://game/domain/creature/anchor_resolver.gd")
## The before set: presets that already wear beaks, jaws, maws, eyes, manes, crests, tails and webbed feet.
const DEFAULT_PRESETS := ["tortoise", "longneck", "boar", "strider", "prowler", "stalker", "angler", "raptor",
	"monkey"]
const POINTS := 150
## The world camera (game/scenes/creature/creature_world.gd CAMERA_*).
const DISTANCE_PER_BODY_M := 2.4
const DISTANCE_MIN_M := 2.6
const DISTANCE_MAX_M := 12.0
const PITCH_DEG := 16.0
const FOV_DEG := 50.0
const CLOSE_SHARE := 0.45
const SIDE_SHARE := 0.3

var out_dir := "user://more_parts_shots"
var mode := "palette"
var set_name := "before"
var presets: Array = DEFAULT_PRESETS.duplicate()
var showcase_path := ""
var cone_fix_preview := false
var editor: Node


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--set="):
			set_name = arg.trim_prefix("--set=")
		elif arg.begins_with("--presets="):
			presets = Array(arg.trim_prefix("--presets=").split(",", false))
		elif arg.begins_with("--showcase="):
			showcase_path = arg.trim_prefix("--showcase=")
		elif arg == "--cone-fix-preview":
			cone_fix_preview = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	editor = (load(EDITOR_SCENE) as PackedScene).instantiate()
	editor.threaded = false   # the skin is built in step, so a frame never shows a half-built body
	root.add_child(editor)
	await _frames(2)
	if mode == "palette":
		await _palette()
	else:
		await _creatures()
	quit()


func _palette() -> void:
	editor.setup(CreatureData.body("quadruped"), POINTS)
	await _frames(2 * editor.tools.size() + 60)
	var scroll: ScrollContainer = editor.hud.get_node("Palette/Box/ToolsScroll")
	for c in CreatureEditorHud.CATEGORIES:
		editor.hud.set_category(String(c["id"]))
		scroll.scroll_vertical = 0
		await _frames(4)
		await _shot("%s_palette_%s" % [set_name, c["id"]])
		# Page down a tab that scrolls (a page is the visible height less one row), so every icon is seen once.
		var bar := scroll.get_v_scroll_bar()
		var page := int(scroll.size.y * 0.75)
		var n := 1
		while bar.max_value - bar.page > 1.0 and scroll.scroll_vertical < int(bar.max_value - bar.page) and n < 12:
			var before := scroll.scroll_vertical
			scroll.scroll_vertical += page
			await _frames(4)
			if scroll.scroll_vertical == before:
				break
			await _shot("%s_palette_%s_%d" % [set_name, c["id"], n])
			n += 1
	print("palette tools: ", editor.tools.size())


func _creatures() -> void:
	(editor.get_node("UI") as CanvasLayer).visible = false
	editor.camera.fov = FOV_DEG   # the world camera's (creature_world.tscn), not the editor's 40
	for entry in _bodies():
		var body: RefCounted = CreatureData.preset_body(String(entry["preset"]))
		var swap: Dictionary = entry.get("swap", {})
		for p in body.parts:
			if swap.has(p["type"]):
				p["type"] = swap[p["type"]]
				p["handles"] = []     # the new type's handles rest at 0
		for p in entry.get("parts", []):
			body.parts.append((p as Dictionary).duplicate(true))
		editor.setup(body, POINTS)
		editor.handle_root.visible = false
		if cone_fix_preview:
			_preview_cone_fix()
		await _frames(6)
		var desc: RefCounted = editor.working_body()
		var length: float = (desc.bounds_m() as AABB).get_longest_axis_size()
		var distance := clampf(DISTANCE_PER_BODY_M * length, DISTANCE_MIN_M, DISTANCE_MAX_M)
		var centre: Vector3 = editor._focus
		var head: Vector3 = _head(desc) + editor._rig_offset
		var pitch := deg_to_rad(PITCH_DEG)
		var shot_name := "%s_%s" % [set_name, entry["name"]]
		await _view(centre, distance, 0.75, pitch, shot_name + "_game")       # behind (+Z) and to the side
		await _view(centre, distance, 2.3, pitch, shot_name + "_front")       # front (-Z) three-quarter
		await _view(head, CLOSE_SHARE * distance, 2.3, 0.25, shot_name + "_close")
		await _view(head, SIDE_SHARE * distance, PI / 2.0, 0.03, shot_name + "_side")
		print("creature ", entry["name"], " length ", snappedf(length, 0.01), " parts ", desc.parts.size())


## Review only (--cone-fix-preview; game code is not changed): turns every forward_cone part on the editor's rig so
## its authored outward axis (local +Y, Blender +Z) points along the look direction (the cone frame's -Z) and its
## authored upper side (local -Z, Blender +Y) faces body up (+Y). That is a half turn about (0, 1, -1), which also
## mirrors x, harmless for these centreline parts. It previews the frame fix proposed in the orientation issue.
func _preview_cone_fix() -> void:
	var fix := Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, -1.0, 0.0))
	var types := {}
	for part in editor.working_body().parts:
		types[part["id"]] = part["type"]
	for p in editor.rig.part_nodes:
		if editor.orientations.get(types.get(p["entry"]["part"], ""), "") == "forward_cone":
			var node: Node3D = p["node"]
			node.transform.basis = node.transform.basis * fix


## The bodies to show: the showcase file's entries, or else the presets as they are.
func _bodies() -> Array:
	if showcase_path != "":
		var text := FileAccess.get_file_as_string(showcase_path)
		var parsed = JSON.parse_string(text)
		if parsed is Array:
			return parsed
		push_error("more_parts_shots: %s is not a JSON list" % showcase_path)
		return []
	var out := []
	for p in presets:
		out.append({"name": p, "preset": p, "parts": []})
	return out


## Body-space centre of the head: the mean placement of the mouth and eye parts, or else the first vertebra.
func _head(desc: RefCounted) -> Vector3:
	var roles := {}
	for type in editor.part_rules:
		roles[type] = String(editor.part_rules[type].get("role", ""))
	var by_id := {}
	for p in desc.parts:
		by_id[p["id"]] = String(p["type"])
	var sum := Vector3.ZERO
	var n := 0
	for placed in AnchorResolver.resolve_all(desc, BodyField.from_description(desc), editor.orientations):
		if roles.get(by_id.get(placed["part"], ""), "") in ["mouth", "eye"]:
			sum += (placed["transform"] as Transform3D).origin
			n += 1
	return sum / n if n > 0 else desc.position_m(0)


## The editor camera's orbit about `focus`: yaw 0 looks from +Z (behind), PI/2 from +X (the right side), PI from -Z
## (the front). The editor re-aims its camera every frame from _focus, _distance and _orbit (creature_editor.gd
## _update_camera), so the view is set through them.
func _view(focus: Vector3, distance: float, yaw: float, pitch: float, shot_name: String) -> void:
	editor._focus = focus
	editor._distance = distance
	editor._orbit = Vector2(yaw, pitch)
	await _frames(4)
	await _shot(shot_name)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("shot ", shot_name)
