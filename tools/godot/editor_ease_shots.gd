extends SceneTree
## Screenshots of the creature and cell editors for the editor-ease review (docs/proposals/editor-ease.md): the
## same poses before and after the usability pass, so the two sets compare frame for frame. Every editor-ease API
## is looked up with has_method, so the script runs on a base without them (the BEFORE frames) and with them.
## Run under Xvfb (docs/TOOLCHAIN.md):
##   xvfb-run -a -s "-screen 0 1920x1080x24" GODOT --path . --audio-driver Dummy --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 1920x1080 --fixed-fps 60 --script res://tools/godot/editor_ease_shots.gd \
##     -- --out=DIR [--text-scale=130] [--only=creature|cell]
## Writes creature_idle, creature_hover_eye (the pointer resting on the Eye tool), creature_tool_eye (the Eye tool
## chosen), creature_edited (two vertebrae added and one undone, so Redo is live and the stats moved), and where
## the editor-ease node exists creature_stat_help (the pointer resting on the Sight row's name) and
## creature_undo_tip (the pointer resting on Undo), cell_idle,
## cell_hover_cilia (the pointer resting on the Cilia tile), cell_pair (an eye spot and its mirror),
## cell_undo_tip (the pointer resting on Undo after that edit) and cell_drag_snap (a part dragged round the rim,
## held near the front). Where the editor-ease APIs exist it also writes cell_stat_help (the pointer resting on a
## stat's name) and cell_pair_drag (a mirrored pair dragged towards the front with Symmetry on). Uses its own
## settings under user://editor_ease_shots/, never the player's.

const ROOT := "user://editor_ease_shots"
const CREATURE_EDITOR := "res://game/scenes/creature/creature_editor.tscn"
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
## Long enough for the tooltip delay (gui/timers/tooltip_delay_sec, 0.5 s) at the fixed 60 frames a second.
const HOVER_FRAMES := 60

var out_dir := "user://editor_ease_shots_out"
var text_scale := 100
var only := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--text-scale="):
			text_scale = arg.trim_prefix("--text-scale=").to_int()
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var service := SettingsService.new(ROOT.path_join("settings.cfg"))
	service.load_file()
	service.set_value("accessibility/text_scale", text_scale)
	SettingsService.set_shared(service)
	if only != "cell":
		await _creature()
	if only != "creature":
		await _cell()
	quit()


func _creature() -> void:
	var editor: Node = load(CREATURE_EDITOR).instantiate()
	editor.threaded = false
	root.add_child(editor)
	editor.setup(CreatureData.body("s1_quadruped"), 150)
	await _frames(40)
	await _shot("creature_idle")

	var hud: Node = editor.hud
	var eye: Button = hud.tool_button("eye") if hud.has_method("tool_button") else hud._tool_buttons.get("eye")
	hud.set_category(hud.category_of("eye", String(CreatureData.part_rules()["eye"].get("role", ""))))   # on screen
	await _frames(5)
	await _hover(eye)
	await _shot("creature_hover_eye")
	_hover_away()

	editor.choose_tool("eye")
	await _frames(10)
	await _shot("creature_tool_eye")
	editor.choose_tool("")
	hud.set_category("all")

	editor.insert_after_selected()
	editor.insert_after_selected()
	editor.undo()
	await _frames(30)
	await _shot("creature_edited")
	var ease: Node = hud.get("ease")
	if ease != null and ease.get("stats") != null:
		var label: Control = ease.stats.grid.get_child(0)
		for i in range(0, ease.stats.grid.get_child_count(), ease.stats.grid.columns):
			if (ease.stats.grid.get_child(i) as Label).text == "Sight":
				label = ease.stats.grid.get_child(i)
		await _hover(label)
		await _shot("creature_stat_help")
		_hover_away()
		await _frames(5)
		await _hover(hud.undo_button)
		await _shot("creature_undo_tip")
		_hover_away()
		await _frames(5)
	editor.queue_free()
	await _frames(5)


func _cell() -> void:
	RenderingServer.set_default_clear_color(Color(0.03, 0.08, 0.14))   # the pool's deep water, behind the dim
	var catalog := PartCatalog.load_from()
	var save: SaveGame = Lineage.found(7, "test+dev", catalog, "grazer").save
	save.adaptation_points = 200
	var state := ActorState.fresh(Phenotype.derive(save.genome, catalog))
	state.energy = state.energy_capacity
	var editor := CellEditor.new()
	root.add_child(editor)
	editor.open(save, catalog, state)
	await _frames(40)
	await _shot("cell_idle")

	await _hover(editor.find_child("Add_cilia", true, false) as Control)
	await _shot("cell_hover_cilia")
	_hover_away()

	if editor.has_method("set_symmetry"):
		editor.set_symmetry(true)
		editor.add("eye_spot")
	else:
		editor.add("eye_spot")
		editor.mirror_selected()
	await _frames(20)
	await _shot("cell_pair")

	await _hover(editor.find_child("Undo", true, false) as Control)
	await _shot("cell_undo_tip")
	_hover_away()

	# Drag the selected eye spot round the rim and hold it a little right of the front, alone (symmetry off), as in
	# the BEFORE frame.
	if editor.has_method("set_symmetry"):
		editor.set_symmetry(false)
	var rim: Control = editor.find_children("*", "Control", true, false).filter(
		func(c: Control) -> bool: return c is CellEditor.RimView)[0]
	var part: Dictionary = editor.session.working.parts[-1]
	var start: Vector2 = rim.at(float(part.angle))
	var to: Vector2 = rim.at(0.03)
	_mouse(rim, start, true)
	for i in 8:
		_motion(rim, start.lerp(to, (i + 1) / 8.0))
		await _frames(2)
	await _frames(10)
	await _shot("cell_drag_snap")
	_mouse(rim, to, false)

	var panel := editor.find_child("StatsPanel", true, false)
	if panel != null:
		var names := panel.find_children("*", "Label", true, false).filter(
			func(l: Label) -> bool: return l.text == "Energy use")
		await _hover(names[0])
		await _shot("cell_stat_help")
		_hover_away()

	if editor.has_method("set_symmetry"):
		editor.undo()   # the eye spot back off the middle line, beside its twin
		editor.set_symmetry(true)
		var eye: Dictionary = editor.session.working.parts[-1]
		var from: Vector2 = rim.at(float(eye.angle))
		_mouse(rim, from, true)
		for i in 8:
			_motion(rim, rim.at(lerp_angle(float(eye.angle), -0.03, (i + 1) / 8.0)))
			await _frames(2)
		await _frames(10)
		await _shot("cell_pair_drag")
		_mouse(rim, rim.at(-0.03), false)
	editor.queue_free()
	await _frames(5)


## Rests the pointer on `c` (a real motion event through the viewport, so the GUI hovers it and any tooltip
## opens), then waits past the tooltip delay. The event is in the viewport's own coordinates, so it lands on `c`
## at any window size (the 1920x1080 canvas is stretched to the window).
func _hover(c: Control) -> void:
	if c == null:
		push_warning("editor_ease_shots: nothing to hover")
		return
	var at := c.get_global_rect().get_center()
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.relative = Vector2(2, 0)
	Input.warp_mouse(root.get_final_transform() * at)
	root.push_input(e, true)
	await _frames(HOVER_FRAMES)


func _hover_away() -> void:
	var e := InputEventMouseMotion.new()
	e.position = Vector2(960, 1060)
	e.global_position = e.position
	e.relative = Vector2(2, 0)
	root.push_input(e, true)


## A left press or release at `local` in the rim view, fed to its _gui_input as the GUI would.
func _mouse(rim: Control, local: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = local
	rim._gui_input(e)


func _motion(rim: Control, local: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = local
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	rim._gui_input(e)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(shot_name + ".png")
	root.get_viewport().get_texture().get_image().save_png(path)
	print("editor_ease_shots: wrote ", path)
