extends SceneTree
## Screenshots of the Social stage preview (docs/stages/social-plan.md section 14) for the look review: the real
## stage (SocialStage on a slot that is only read; a missing one gives the starter body), played through its own
## actions: the entry card, the player before the curious strider with Display selected, its answer, the band
## befriended with the fitting signals (a fruit picked by touch for the hungry boar) and following, the orders menu
## open over the paused field, and the hunter. Run under Xvfb (docs/TOOLCHAIN.md):
##   xvfb-run -a -s "-screen 0 1920x1080x24" GODOT --path . --audio-driver Dummy --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 1920x1080 --fixed-fps 60 --script res://tools/godot/social_shots.gd \
##     -- --out=DIR [--slot=PATH] [--suffix=_1280] [--only=entry,recognition,...] [--title]
## The shots: entry, refusal (Share with empty hands, refused in words), recognition, response, band_follow,
## orders_menu, order_ack (Assist chosen in the menu and acknowledged), task_carry (a carrier bringing fruit to the
## nest), task_done and hunter. sim.place() (tests and tools only)
## moves the player between beats so the script stays short; every answer, join and order comes from the sim.
## --title instead runs Main (its own settings and slots under user://smoke/social_shots/): the title with the
## Social stage button focused, the stage that button opens, the leave question, and the title again after leaving
## (title, title_stage, leave_dialog, title_back).

const SEED := 4262
const FAST_TICKS := 12

var out_dir := "user://social_shots"
var slot := "user://smoke/social_shots/none.json"
var suffix := ""
var only: PackedStringArray = []
var title_mode := false
var stage: SocialStage
var _move := Vector2.ZERO


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--slot="):
			slot = arg.trim_prefix("--slot=")
		elif arg.begins_with("--suffix="):
			suffix = arg.trim_prefix("--suffix=")
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
		elif arg == "--title":
			title_mode = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	if title_mode:
		await _title()
		quit()
		return
	stage = SocialStage.new()
	stage.name = "SocialStage"
	root.add_child(stage)
	stage.setup(slot, SEED)
	print("social_shots: body ", stage.body_source, " ", stage.creature_name, " setup ", stage.world.setup_ms)
	await _frames(30)
	await _shot("entry")
	stage.begin()
	stage.driver = func() -> Dictionary: return {"move": _move, "bite": false}
	await _frames(2)

	# A refusal: Share with nothing carried, refused in words; it spends nothing.
	_stand_before("b2", 2.5)
	stage.choose_signal("share")
	await _frames(10)
	stage.signal_now("share")
	await _frames(20)
	print("social_shots: refusal ", stage.hud.caption_texts(), " cooldown ", stage.sim.player()["cooldown_t"])
	await _shot("refusal")
	# Until the refusal's caption has faded, so the next frames show one answer each.
	await _frames(int((SocialHud.CAPTION_S + 0.2) * 60.0))

	# Before the curious strider, facing it, Display selected.
	if not _face_for("b1", "display"):
		print("social_shots: no spot where b1 is the target and Display reaches it")
	stage.choose_signal("display")
	await _frames(30)
	print("social_shots: target ", stage.sim.target_id(), " display ", stage.sim.preview_signal("display"),
			" share ", stage.sim.preview_signal("share"))
	await _shot("recognition")
	stage.signal_now("display")
	await _frames(40)
	print("social_shots: after display ", stage.hud.caption_texts(), " trust ", stage.sim.individual("b1")["trust"])
	await _shot("response")

	for id in ["b1", "b2", "b3"]:
		await _befriend(id)
	print("social_shots: band ", stage.sim.band())
	# From the den's edge towards the nest, the band following.
	stage.give_order("follow")
	var den: Vector2 = stage.sim.sites["den"]["position"]
	var home: Vector2 = stage.sim.sites["nest"]["position"]
	var way := (home - den).normalized()
	_put(den + way * 3.0, atan2(-way.x, -way.y))
	await _frames(10)
	_move = way * 0.8
	await _frames(200)
	_move = Vector2.ZERO
	await _frames(50)
	# The band trails between the camera and the player: orbit to a front three-quarter view, as the right stick does.
	stage.world.camera_yaw = float(stage.sim.player()["yaw"]) + PI * 0.75
	stage.world.snap_camera()
	await _frames(4)
	await _shot("band_follow")

	stage.open_menu()
	stage._step_menu(2)
	await _frames(8)
	await _shot("orders_menu")
	# Assist, chosen in the menu: each member acknowledges.
	stage._step_menu(2)
	await _frames(4)
	stage.give_order(SocialRules.ORDERS[stage.menu_index])
	await _frames(15)
	print("social_shots: order_ack ", stage.hud.caption_texts())
	await _shot("order_ack")

	# The group task from the nest, the camera towards the grove.
	var grove_at: Vector2 = _v2(stage.sim.tuning["grove"]["centre"])
	var to_grove := (grove_at - home).normalized()
	_put(home + to_grove * 2.0, atan2(-to_grove.x, -to_grove.y))
	# Fast-forward the round (several stage ticks a rendered frame, through the stage's own loop) until a few fruit
	# are in, then at normal speed until a carrier is a few metres out, and fast again to the end of the round.
	var mark := stage.event_log.size()
	await _fast(func() -> bool: return int(stage.sim.task_state()["delivered"]) >= 2, 4000)
	var carrier := ""
	for t in 1500:
		await _frames(1)
		for c in stage.sim.individuals():
			var p: Vector3 = c["position"]
			var gap := Vector2(p.x, p.z).distance_to(home + to_grove * 2.0)
			if int(c["carrying"]) > 0 and gap < 6.0 and gap > 3.0:
				carrier = c["id"]
				print("social_shots: task_carry ", c["id"], " at %.1f m" % gap, " ", stage.sim.task_state())
		if carrier != "":
			break
	await _shot("task_carry")
	# Fast to one fruit short of the goal, then the last delivery at normal speed so its caption is on screen.
	var goal := int(stage.sim.task_state()["goal"])
	await _fast(func() -> bool: return int(stage.sim.task_state()["delivered"]) >= goal - 1, 4000)
	for t in 2400:
		await _frames(1)
		if stage.event_log.slice(mark).any(func(e: Dictionary) -> bool: return e["kind"] == "task_done"):
			break
	await _frames(15)
	print("social_shots: task_done ", stage.sim.task_state(), " ", stage.hud.caption_texts(), " ticks ",
			stage.sim.tick_count)
	await _shot("task_done")

	# Towards the grove, where the hunter patrols.
	var grove: Dictionary = stage.sim.tuning["grove"]
	var at := Vector2(float(grove["centre"][0]), float(grove["centre"][1])) + Vector2(-6.0, 10.0)
	stage.sim.place(SocialSim.PLAYER_ID, at, atan2(-6.0, 10.0))
	stage.world.camera_yaw = atan2(-6.0, 10.0)
	stage.world.snap_camera()
	await _frames(240)
	# Look from the player towards the hunter (an orbit, as the right stick does), so both are mid-screen.
	var hp: Vector3 = stage.sim.hunter()["position"]
	var me: Vector3 = stage.sim.player()["position"]
	var look := Vector2(hp.x - me.x, hp.z - me.z)
	stage.world.camera_yaw = atan2(-look.x, -look.y)
	stage.world.snap_camera()
	await _frames(3)
	print("social_shots: hunter ", stage.sim.hunter()["state"], " captions ", stage.hud.caption_texts())
	await _shot("hunter")
	quit()


## Main from the title: the Social stage button, the stage it opens, the leave question and the title again.
func _title() -> void:
	var dir := "user://smoke/social_shots"
	DirAccess.make_dir_recursive_absolute(dir)
	SaveSlots.folder = dir.path_join("saves")
	var service := SettingsService.new(dir.path_join("settings.cfg"))
	service.load_file()
	SettingsService.set_shared(service)
	var main: Main = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(40)
	var button: Button = main.start_screen.social_button
	button.grab_focus()
	await _frames(20)
	for path in ["MainView/Left", "MainView/Left/Title", "MainView/Left/Gap", "MainView/Left/Buttons",
			"MainView/Left/Preview", "MainView/Left/Preview/SocialButton", "Hint"]:
		var node := main.start_screen.get_node_or_null(path) as Control
		if node != null:
			print("social_shots: title ", path, " rect ", node.get_global_rect(), " visible ", node.visible)
	await _shot("title")
	button.pressed.emit()
	await _frames(40)
	print("social_shots: after the button the screen is ", main.screen, " social_stage ", main.social_stage)
	stage = main.social_stage
	await _shot("title_stage")
	stage.begin()
	stage.request_leave()
	await _frames(15)
	await _shot("leave_dialog")
	stage.leave_dialog.choose("leave")
	await _frames(40)
	print("social_shots: after leaving the screen is ", main.screen, " social_stage ", main.social_stage)
	stage = null
	await _shot("title_back")


## Befriends `id` the way the plan says: the signal that fits its visible mood, from close by; a fruit first when it
## is hungry (picked by touch at a ripe bush).
func _befriend(id: String) -> void:
	for attempt in 14:
		var c := stage.sim.individual(id)
		if bool(c["member"]):
			return
		var fits := String(c["fits"])
		if fits == "share" and int(stage.sim.player()["carrying"]) == 0:
			for b in stage.sim.bush_states():
				if b["ripe"]:
					stage.sim.place(SocialSim.PLAYER_ID, b["position"], 0.0)
					break
			await _frames(3)
		_stand_before(id, 2.0)
		await _frames(2)
		stage.signal_now(fits)
		await _frames(int(stage.sim.tuning["signals"]["cooldown_t"]) + 4)
	print("social_shots: could not befriend ", id, " ", stage.sim.individual(id))


## Stands the player in front of `id` (within its view, a few metres off) where `id` is the target and `kind` can be
## given; true when such a spot was found.
func _face_for(id: String, kind: String) -> bool:
	var c := stage.sim.individual(id)
	var p: Vector3 = c["position"]
	for dist in [3.0, 2.5, 4.0]:
		for k in 13:
			var off := deg_to_rad(10.0 * float((k + 1) / 2) * (1.0 if k % 2 == 1 else -1.0))
			var look := float(c["yaw"]) + off
			var at := Vector2(p.x, p.z) + Vector2(-sin(look), -cos(look)) * float(dist)
			var to := Vector2(p.x, p.z) - at
			_put(at, atan2(-to.x, -to.y))
			var preview := stage.sim.preview_signal(kind)
			if String(preview["target"]) == id and bool(preview["ok"]):
				return true
	_stand_before(id, 3.0)
	return false


## Puts the player at `at` facing `yaw`, the camera behind it.
func _put(at: Vector2, yaw: float) -> void:
	stage.sim.place(SocialSim.PLAYER_ID, at, yaw)
	stage.world.camera_yaw = yaw
	stage.world.snap_camera()


func _stand_before(id: String, dist: float) -> void:
	var c := stage.sim.individual(id)
	var p: Vector3 = c["position"]
	var at := Vector2(p.x, p.z) + Vector2(-sin(c["yaw"]), -cos(c["yaw"])) * dist
	var to := Vector2(p.x, p.z) - at
	stage.sim.place(SocialSim.PLAYER_ID, at, atan2(-to.x, -to.y))
	stage.world.camera_yaw = atan2(-to.x, -to.y)
	stage.world.snap_camera()


static func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _forward() -> Vector2:
	var yaw := float(stage.sim.player()["yaw"])
	return Vector2(-sin(yaw), -cos(yaw))


## Runs the stage FAST_TICKS ticks a rendered frame until `done` holds or `limit` ticks have passed, then lets the
## walkers' feet settle at normal speed. Each tick is the stage's own _physics_process (the same intent, events, HUD).
func _fast(done: Callable, limit: int) -> void:
	var ticks := 0
	while ticks < limit and not done.call():
		for i in FAST_TICKS:
			stage._physics_process(SocialSim.DT)
		ticks += FAST_TICKS
		await _frames(1)
	await _frames(45)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Where each body is: the sim's position, its rig body's, and its tag's point on screen.
func _report(shot_name: String) -> void:
	var cam := stage.world.camera
	print("social_shots: %s camera %s yaw %.2f" % [shot_name, cam.global_position, stage.world.camera_yaw])
	for id in stage.world.rigs:
		var rig: Node3D = stage.world.rigs[id]
		var planner = stage.sim.planner_of(id)
		var at := stage.world.tag_point(id)
		print("  %s planner %s body %s tag %s on screen %s" % [id, planner.position, rig.body.global_position, at,
				cam.unproject_position(at)])


func _shot(shot_name: String) -> void:
	if not only.is_empty() and not shot_name in only:
		return
	if stage != null:
		_report(shot_name)
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + suffix + ".png"))
	print("shot ", shot_name + suffix)
