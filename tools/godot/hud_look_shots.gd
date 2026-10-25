extends SceneTree
## Look-review screenshots of the in-game HUDs (hud job): the cell HUD in the endless sea and in the M1 pool, and
## the creature world HUD. Run under Xvfb (docs/TOOLCHAIN.md):
##   xvfb-run -a -s "-screen 0 1920x1080x24" GODOT --path . --audio-driver Dummy --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 1920x1080 --fixed-fps 60 --script res://tools/godot/hud_look_shots.gd \
##     -- --out=DIR [--text-scale=100|115|130] [--only=cell,pool,creature]
## Each frame is saved as DIR/<name>_<text scale>.png. Uses its own slots and settings under user://shots/hud,
## never the player's, and wipes them when done.
##
##   cell_start     endless sea, grazer, seed 4242, 60 frames in: status card, ring, points, controls, toasts
##   cell_busy      two meal toasts, the refusal hint, the health row (health set to 60% for the shot), paused
##   cell_starving  energy 0: the starving banner, the Starving chip, the health bar and the rested message
##   cell_sunlit    fed again and moved to the sunlit tile nearest the origin: the HUD over the brightest water
##   pool_start     the M1 pool, hunter: no growth row or ladder strip
##   editor_tooltip  the creature editor, the mouse held over a button with a tooltip: the glass TooltipPanel and
##                   TooltipLabel (no before frame)
##   creature_world  the creature stage's world, 90 frames after enter_world: the controls line is still up
##   creature_death  at the nest, the longest notice (the death notice, set by hand: "Back at the nest") with the
##                   Evolve chip lit (no before frame)
##   creature_notice walked off the nest and pressed evolve: the sim's own refusal notice, and a "+5" points flash
##                   (set by hand)
##   creature_away   still off the nest, bit at the air (the Bite chip recharging), the notice cleared and the
##                   controls line timed out (its timer run out by hand): the HUD as it stays (no before frame)

const ROOT := "user://shots/hud"

## Swims nowhere: the cell holds still while the shot is set up.
class Still:
	extends RefCounted

	func next_intent(_sim: PoolSim) -> SimIntent:
		return SimIntent.new()

var out_dir := "user://hud_look"
var text_scale := 100
var only: PackedStringArray = ["cell", "pool", "creature"]
var main: Node


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--text-scale="):
			text_scale = arg.trim_prefix("--text-scale=").to_int()
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",", false)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	_wipe(ROOT)
	DirAccess.make_dir_recursive_absolute(ROOT)
	SaveSlots.folder = ROOT.path_join("saves")
	var service := SettingsService.new(ROOT.path_join("settings.cfg"))
	service.load_file()
	service.set_value("accessibility/text_scale", text_scale)
	SettingsService.set_shared(service)
	if only.has("cell"):
		await _cell()
	if only.has("pool"):
		await _pool()
	if only.has("creature"):
		await _creature()
	if main != null:
		main.queue_free()
		await _frames(2)
	_wipe(ROOT)
	quit()


func _new_main(world: String, slot: String) -> void:
	if main != null:
		main.queue_free()
		await _frames(2)
	main = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(4)
	main.flags.world = world
	main.open_session(ROOT.path_join(slot))
	main.intent_provider = Still.new()


func _cell() -> void:
	await _new_main("endless", "cell.json")
	main.start_new("grazer", 4242)
	var pool: PoolScene = main.pool
	pool.pause_on_focus_loss = false
	await _frames(60)
	await _shot("cell_start")
	var hud: Hud = main.hud
	# The panels as laid out, printed so test_world_hud's rects can be refreshed from them later (that test still
	# holds the pre-glass rects as fixed inputs).
	print("panels cell_start ", hud.panel_rects())
	hud._on_sim_event({"type": "ate", "absorbed": 8.0, "points": 1})
	hud._on_sim_event({"type": "ate", "absorbed": 8.0, "points": 1})
	hud.show_hint(RefusalHints.TEXTS["mouth is not facing it"])
	pool.sim.state.health = pool.sim.state.max_health * 0.6
	await _frames(4)
	pool.set_paused(true)
	await _frames(4)
	await _shot("cell_busy")
	print("panels cell_busy ", hud.panel_rects())
	pool.set_paused(false)
	pool.sim.debug_set_energy(0.0)
	await _frames(45)
	hud.show_message(Hud.rested_line(pool.sim.state))
	pool.set_paused(true)
	await _frames(4)
	await _shot("cell_starving")
	print("panels cell_starving ", hud.panel_rects())
	# The brightest water: the sunlit tile nearest the origin, fed again, for text contrast.
	pool.set_paused(false)
	pool.sim.debug_set_energy(80.0)
	pool.sim.state.health = pool.sim.state.max_health
	var at := _sunlit_tile_centre(pool.sim)
	if pool.sim.debug_teleport_abs(at.x, at.y, -PI / 2.0):
		await _frames(90)
		await _shot("cell_sunlit")
	else:
		push_error("hud_look_shots: no sunlit tile to move to")


## The centre (absolute metres at size 1, 64 m tiles) of the band 0 sunlit tile nearest the origin.
func _sunlit_tile_centre(sim: PoolSim) -> Vector2:
	var best := Vector2(INF, INF)
	if sim.world == null:
		return best
	var tile_am: float = sim.world.content.config.tile_bu
	for ty in range(-4, 5):
		for tx in range(-4, 5):
			if sim.world.gen._region(0, tx, ty) != "sunlit":
				continue
			var c := Vector2((tx + 0.5) * tile_am, (ty + 0.5) * tile_am)
			if c.length() < best.length():
				best = c
	return best


func _pool() -> void:
	await _new_main("pool", "pool.json")
	main.start_new("hunter", 4242)
	main.pool.pause_on_focus_loss = false
	await _frames(60)
	await _shot("pool_start")


func _creature() -> void:
	await _new_main("endless", "creature.json")
	var stage: CreatureStage = main.open_creature_stage()
	await _frames(30)
	await _tooltip(stage)
	stage.enter_world()
	await _frames(90)
	var world: CreatureWorld = stage.world_scene()
	if world != null:
		print("creature_world keys line visible ", world.hud._hint_panel.visible, " dock line alpha ",
			world.hud._ways_text.modulate.a, " dock ", world.hud.get_node("%Dock").get_global_rect())
	await _shot("creature_world")
	if world == null:
		push_error("hud_look_shots: the creature world did not open")
		return
	world.hud.show_notice(CreatureWorld.DEATH_NOTICE % ["killed by a hexapod", 30])
	world.hud.refresh()
	await _frames(2)
	await _shot("creature_death")
	world.set_intent(Vector2(0.0, 1.0), false, false)
	await _frames(150)
	world.set_intent(Vector2.ZERO, false, true)
	await _frames(3)
	world.set_intent(Vector2.ZERO, false, false)
	world.hud.flash_points(5)
	await _frames(2)
	print("creature_notice notice '", world.hud.notice_text(), "' goal '", world.hud._goal_text.text, "'")
	await _shot("creature_notice")
	world.set_intent(Vector2.ZERO, true, false)
	await _frames(3)
	world.set_intent(Vector2.ZERO, false, false)
	world.hud.clear_notice()
	world.hud._keys_t = 0.001
	await _frames(2)
	world.hud.refresh()
	print("creature_away keys line visible ", world.hud._hint_panel.visible, " dock line visible ",
		world.hud._ways_text.is_visible_in_tree(), " alpha ", world.hud._ways_text.modulate.a, " dock ",
		world.hud.get_node("%Dock").get_global_rect(), " '", world.hud._ways_text.text, "'")
	await _shot("creature_away")
	world.clear_intent()


## Holds the mouse over the creature editor's Random button (or else the first visible button with a tooltip)
## until its tooltip shows.
func _tooltip(stage: Node) -> void:
	var target: Control = null
	for b: Button in stage.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and not b.tooltip_text.is_empty() and (target == null or b.name == "Random"):
			target = b
	if target == null:
		push_error("hud_look_shots: no editor button with a tooltip")
		return
	var at := target.get_global_rect().get_center()
	Input.warp_mouse(root.get_final_transform() * at)
	await _frames(2)
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	root.push_input(ev, true)
	await _frames(60)
	print("editor_tooltip over '", target.name, "' (", target.tooltip_text, ")")
	await _shot("editor_tooltip")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join("%s_%d.png" % [shot_name, text_scale])
	img.save_png(path)
	print("shot ", path, " ", img.get_size())


func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)
