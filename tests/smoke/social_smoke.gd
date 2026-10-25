extends SceneTree
## Social stage preview smoke (docs/stages/social-plan.md sections 11 and 14, PROPOSED). tools/check.sh runs it with
## --fixed-fps 60, so each frame is one sim tick. It drives the real main scene into the Social stage, as --social
## does, and prints one PASS or FAIL line per check. Exit code 0 when every check passes, 1 otherwise.
##
##   -- --social --slot=user://smoke/social.json --seed=4260
##       First a lineage with a land creature (a raptor body, named) is saved in the slot, as the creature stage
##       writes it; its SHA-256 and the slot folder's file list are kept. Main opens the Social stage on it: the
##       body and name are the slot's, every body is drawn and the entry card holds the sim. Then, through the
##       stage's own actions: Share with nothing carried and an order with no band are refused in words and spend
##       nothing; Sing backs the wary loner away; each band member joins after the signal that fits its mood (a
##       fruit picked by touch for the hungry one). Follow is acknowledged and the band keeps up over a 10 m walk;
##       an Investigate past the field's edge is acknowledged, then reported as unreachable within the order's
##       timeout; Assist feeds the nest until the group task is done; the hunter watches a band that stands
##       together, the scout warns and the hunter disengages; Retreat sends the band to the nest; the player
##       faints and recovers with the band whole; one member is dismissed. Leaving returns to the title, the
##       title's Social stage button opens the stage again, the pause key asks first and Back to title leaves. Last,
##       the slot's bytes and the folder's file list are unchanged: the stage never writes the save.
## Moving the player between beats with sim.place() (tests and tools only) keeps the run short; every answer, join,
## acknowledgement and report comes from the sim.

const MAIN_SCENE := "res://game/scenes/main.tscn"
const SocialData := preload("res://game/systems/social/social_data.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const SMOKE_DIR := "user://smoke"
const SETTLE_FRAMES := 3
const BODY_PRESET := "raptor"
const CREATURE_NAME := "Smoke Walker"
const CAST := ["b1", "b2", "b3"]
## Slack on the band's follow distance, as the sim tests allow (members queue behind each other).
const FOLLOW_SLACK_M := 2.0

var main: Main
var stage: SocialStage
var tuning: Dictionary
var _move := Vector2.ZERO
var _failures := 0
var _checks := 0


func _initialize() -> void:
	print("Social smoke, build %s" % BuildInfo.build_id())
	await _run()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


func _run() -> void:
	var slot := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--slot="):
			slot = arg.trim_prefix("--slot=")
	_check(slot.begins_with(SMOKE_DIR + "/"), "the smoke plays on a slot under %s/ (%s)" % [SMOKE_DIR, slot])
	if not slot.begins_with(SMOKE_DIR + "/"):
		return
	DirAccess.make_dir_recursive_absolute(slot.get_base_dir())
	for file in DirAccess.get_files_at(slot.get_base_dir()):
		if file.begins_with(slot.get_file()):
			DirAccess.remove_absolute(slot.get_base_dir().path_join(file))
	tuning = SocialData.tuning()
	var catalog := PartCatalog.load_from()
	var founded := Lineage.found(4260, BuildInfo.build_id(), catalog, "omnivore")
	var creature := CreatureRules.new_creature()
	creature["body"] = (SocialData.creature_data()["presets"][BODY_PRESET] as Dictionary).duplicate(true)
	creature["name"] = CREATURE_NAME
	founded.save.creature = creature
	_check(founded.ok and PersistenceService.new(catalog).save_to(slot, founded.save) == OK,
			"a lineage with a %s creature is saved in the slot" % BODY_PRESET)
	var sha_before := FileAccess.get_sha256(slot)
	var files_before := _listing(slot.get_base_dir())
	print("  slot %s sha256 %s, folder %s" % [slot, sha_before, files_before])

	main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(SETTLE_FRAMES)
	stage = main.social_stage
	_check(stage != null and main.screen == stage, "--social opens the Social stage as the screen")
	if stage == null:
		return
	var in_slot: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(slot)) as Dictionary)["creature"]["body"]
	await _opening(in_slot)
	await _refusals()
	await _loner()
	await _befriend_band()
	if stage.sim.band().size() == CAST.size():
		await _follow()
		await _investigate()
		await _assist()
		await _hunter_and_retreat()
		await _faint()
		await _dismiss()
	await _leave_and_return(slot)
	_check(FileAccess.get_sha256(slot) == sha_before, "the slot's bytes are unchanged (SHA-256)")
	var files_after := _listing(slot.get_base_dir())
	_check(files_after == files_before, "the slot folder holds the same files: %s" % [files_after])


## The stage on the slot's creature (`in_slot`: the body as the slot file holds it): its body and name, every body
## drawn, the entry card holding the sim.
func _opening(in_slot: Dictionary) -> void:
	var sim := stage.sim
	_check(stage.body_source == "slot" and stage.body_note == "", "the body comes from the slot (%s)" % stage.body_source)
	_check(stage.creature_name == CREATURE_NAME, "the creature's name is the slot's (%s)" % stage.creature_name)
	var walked := BodyCodec.hash_text(sim.body_of(SocialSim.PLAYER_ID))
	_check(walked == BodyCodec.hash_text(BodyCodec.from_dict(in_slot)),
			"the player walks the slot's %s body (body SHA-256 %s)" % [BODY_PRESET, walked.left(12)])
	var drawn := []
	for id in [SocialSim.PLAYER_ID, "b1", "b2", "b3", "l1", "h1"]:
		var rig: Node3D = stage.world.rigs.get(id)
		if rig != null and rig.is_inside_tree() and rig.is_visible_in_tree():
			drawn.append(id)
	_check(drawn.size() == 6, "the player, the band, the loner and the hunter are drawn: %s" % [drawn])
	_check(sim.individuals().size() == 4 and String(sim.hunter()["id"]) == "h1", "four individuals and a hunter")
	_check(stage.hud.card_visible(), "the entry card shows")
	var at := sim.tick_count
	await _frames(10)
	_check(stage.held() and sim.tick_count == at, "the entry card holds the sim")
	stage.begin()
	stage.driver = func() -> Dictionary: return {"move": _move, "bite": false}
	at = sim.tick_count
	await _frames(10)
	_check(not stage.held() and sim.tick_count == at + 10, "after the card, one sim tick a frame (%d)" % (sim.tick_count - at))


## Refusals explain and spend nothing: Share with empty hands, an order with no band.
func _refusals() -> void:
	var sim := stage.sim
	_stand_before("b1", 2.0)
	await _frames(1)
	var preview := sim.preview_signal("share")
	var mark := stage.event_log.size()
	stage.signal_now("share")
	await _frames(1)
	var refused := _of(_since(mark), "refused")
	_check(refused.size() == 1 and refused[0]["reason"] == "Nothing to share: carry a fruit first",
			"Share with nothing carried is refused in words: %s" % [refused])
	_check(not bool(preview["ok"]) and String(preview["reason"]) == "Nothing to share: carry a fruit first",
			"the dock's preview gave the same reason first")
	_check(int(sim.player()["cooldown_t"]) == 0 and _of(_since(mark), "response").is_empty(),
			"the refusal spends no cooldown and gets no answer")
	mark = stage.event_log.size()
	stage.give_order("follow")
	await _frames(1)
	refused = _of(_since(mark), "refused")
	_check(refused.size() == 1 and refused[0]["reason"] == "No one in your band yet",
			"an order with no band is refused in words: %s" % [refused])


## The wary loner backs away from a loud signal.
func _loner() -> void:
	var sim := stage.sim
	_stand_before("l1", 2.5)
	await _frames(1)
	_check(sim.target_id() == "l1", "the loner is the target")
	var before := _gap("l1")
	var mark := stage.event_log.size()
	stage.signal_now("sing")
	await _frames(60)
	var r := _of(_since(mark), "response")
	_check(r.size() == 1 and r[0]["response"] == "startles" and r[0]["words"] == "backs away",
			"Sing startles the wary loner: %s" % [r])
	_check(_gap("l1") > before + 0.3, "it backs away (%.2f m -> %.2f m)" % [before, _gap("l1")])
	await _frames(int(tuning["signals"]["cooldown_t"]))


## Each band member joins after the signal that fits its visible mood (Share needs a fruit, picked by touch).
func _befriend_band() -> void:
	var sim := stage.sim
	var cooldown := int(tuning["signals"]["cooldown_t"])
	for id in CAST:
		var fits_seen := {}
		var mark := stage.event_log.size()
		for attempt in 12:
			var c := sim.individual(id)
			if bool(c["member"]):
				break
			var fits := String(c["fits"])
			fits_seen[fits] = true
			if fits == "share" and int(sim.player()["carrying"]) == 0:
				for b in sim.bush_states():
					if b["ripe"]:
						sim.place(SocialSim.PLAYER_ID, b["position"], 0.0)
						break
				await _frames(3)
				_check(int(sim.player()["carrying"]) > 0, "a fruit is picked by touch for the hungry %s" % c["name"])
			_stand_before(id, 2.0)
			await _frames(2)
			stage.signal_now(fits)
			await _frames(cooldown + 4)
		var events := _since(mark)
		var answers := []
		for e in _of(events, "response"):
			if e["who"] == id:
				answers.append("%s:%s" % [e["signal"], e["response"]])
		var joined := _of(events, "joined").filter(func(e: Dictionary) -> bool: return e["who"] == id)
		var all_fit := not answers.is_empty() and answers.all(func(a: String) -> bool: return a.ends_with(":fits"))
		_check(joined.size() == 1 and sim.band().has(id),
				"%s (%s) joins the band after %s" % [sim.individual(id)["name"], id, answers])
		_check(all_fit, "every signal given to %s fitted its mood (%s)" % [id, fits_seen.keys()])
	_check(Array(sim.band()) == CAST, "the band holds all three: %s" % [sim.band()])


## Follow is acknowledged and the band keeps up over a 10 m walk.
func _follow() -> void:
	var sim := stage.sim
	var mark := stage.event_log.size()
	stage.give_order("follow")
	await _frames(1)
	var acks := _of(_since(mark), "ack")
	_check(acks.size() == 3 and acks.all(func(a: Dictionary) -> bool: return a["words"] == "follows you"),
			"each member acknowledges Follow (%d)" % acks.size())
	await _frames(120)
	var start := _ground(sim.player()["position"])
	var way := (Vector2.ZERO - start).normalized()
	_move = way
	var walked := 0.0
	for t in 900:
		await _frames(1)
		walked = _ground(sim.player()["position"]).distance_to(start)
		if walked >= 10.0:
			break
	_move = Vector2.ZERO
	await _frames(90)
	_check(walked >= 10.0, "the player walks 10 m (%.1f m)" % walked)
	var limit := float(tuning["band"]["follow_m"]) + FOLLOW_SLACK_M
	for id in CAST:
		_check(_gap(id) <= limit and sim.individual(id)["state"] == "follow",
				"%s keeps up (%.1f m, %s)" % [id, _gap(id), sim.individual(id)["state"]])


## An Investigate past the field's east edge is acknowledged, then reported as unreachable within the timeout.
func _investigate() -> void:
	var sim := stage.sim
	sim.place(SocialSim.PLAYER_ID, Vector2(36.0, 0.0), -PI / 2.0)
	sim.place("b1", Vector2(34.0, 2.0), -PI / 2.0)
	sim.place("b2", Vector2(34.0, -2.0), -PI / 2.0)
	sim.place("b3", Vector2(33.0, 0.0), -PI / 2.0)
	await _frames(10)
	var mark := stage.event_log.size()
	stage.give_order("investigate")
	await _frames(1)
	var acks := _of(_since(mark), "ack")
	_check(acks.size() == 3 and acks.all(func(a: Dictionary) -> bool: return a["words"] == "goes to look"),
			"each member acknowledges Investigate: %s" % [acks])
	var timeout := int(tuning["orders"]["timeout_t"])
	var waited := 0
	while waited < timeout + 60 and _of(_since(mark), "cannot").size() < 3:
		await _frames(1)
		waited += 1
	var cannot := _of(_since(mark), "cannot")
	_check(cannot.size() == 3 and cannot.all(func(e: Dictionary) -> bool: return e["reason"] == "can't reach that spot"),
			"each reports it can't reach that spot, after %d ticks (timeout %d): %s" % [waited, timeout, cannot])
	_check(waited <= timeout, "within the order's timeout")
	_check(_of(_since(mark), "arrived").is_empty(), "no one claims to arrive")


## Assist from the nest: the band gathers until the group task is done.
func _assist() -> void:
	var sim := stage.sim
	sim.place(SocialSim.PLAYER_ID, Vector2(0.0, 4.0), PI)
	await _frames(60)
	var mark := stage.event_log.size()
	stage.give_order("assist")
	await _frames(1)
	var acks := _of(_since(mark), "ack")
	_check(acks.size() == 3 and acks.all(func(a: Dictionary) -> bool: return a["words"] == "gathers food"),
			"each member acknowledges Assist and gathers: %s" % [acks])
	var start := sim.tick_count
	var waited := 0
	while waited < 9000 and _of(_since(mark), "task_done").is_empty():
		await _frames(30)
		waited += 30
	var events := _since(mark)
	var delivered := 0
	var who := {}
	for e in _of(events, "delivered"):
		delivered += int(e["count"])
		who[e["who"]] = true
	_check(not _of(events, "task_done").is_empty(),
			"the group task is done: %d fruit in %d ticks by %s" % [delivered, sim.tick_count - start, who.keys()])
	_check(delivered >= int(tuning["task"]["fruit_goal"]) and who.size() >= 2, "six fruit, a group effort")
	_check(sim.task_state()["rounds_done"] == 1, "one round counted")


## The hunter watches a band that stands together, the scout warns, the hunter disengages; Retreat sends the band home.
func _hunter_and_retreat() -> void:
	var sim := stage.sim
	var waited := 0
	while waited < 1800 and String(sim.hunter()["state"]) != "patrol":
		await _frames(10)
		waited += 10
	_check(String(sim.hunter()["state"]) == "patrol", "the hunter patrols again (%d ticks)" % waited)
	var hp := _ground(sim.hunter()["position"])
	var away := (Vector2.ZERO - hp).normalized()
	var at := hp + away * 11.0
	var facing := atan2(away.x, away.y)
	sim.place(SocialSim.PLAYER_ID, at, facing)
	var side := Vector2(away.y, -away.x)
	sim.place("b1", at + side * 1.5 - away * 0.5, facing)
	sim.place("b2", at - side * 1.5 - away * 0.5, facing)
	sim.place("b3", at + away * 1.5, facing)
	var scout := ""
	for c in sim.individuals():
		if c["role"] == "scout" and c["member"]:
			scout = c["id"]
	var mark := stage.event_log.size()
	var states := []
	for t in 900:
		await _frames(1)
		states = _of(_since(mark), "hunter_state").map(func(e: Dictionary) -> String: return e["state"])
		if states.has("disengage"):
			break
	var events := _since(mark)
	var warned := _of(events, "warned")
	_check(scout != "" and warned.size() >= 1 and warned[0]["who"] == scout, "the scout (%s) warns the band" % scout)
	var watch := states.find("investigate")
	_check(watch >= 0 and states.find("disengage", watch) > watch, "the hunter watches, then disengages: %s" % [states])
	_check(_of(events, "hit").is_empty(), "it never strikes a band that stands together")
	_check(Array(sim.band()) == CAST, "the band is whole")
	mark = stage.event_log.size()
	stage.give_order("retreat")
	await _frames(1)
	var acks := _of(_since(mark), "ack")
	_check(acks.size() == 3 and acks.all(func(a: Dictionary) -> bool: return a["words"] == "heads home"),
			"each member acknowledges Retreat: %s" % [acks])
	var home := float(tuning["nest"]["radius_m"])
	var held := func(id: String) -> bool:
		return _ground(sim.individual(id)["position"]).length() <= home and sim.individual(id)["state"] == "wait"
	waited = 0
	while waited < 1800 and not CAST.all(held):
		await _frames(10)
		waited += 10
	for id in CAST:
		var d := _ground(sim.individual(id)["position"]).length()
		var state := String(sim.individual(id)["state"])
		_check(d <= home and state == "wait", "%s waits at the nest (%.1f m from its centre, %s, %d ticks)" % [id, d, state, waited])


## The player faints and recovers at the nest; the band keeps every member.
func _faint() -> void:
	var sim := stage.sim
	stage.give_order("follow")
	await _frames(60)
	var mark := stage.event_log.size()
	sim.me["health"] = 0.0
	var waited := 0
	while waited < int(tuning["player"]["faint_t"]) + 120 and _of(_since(mark), "recovered").is_empty():
		await _frames(1)
		waited += 1
	var events := _since(mark)
	var fainted := _of(events, "fainted")
	_check(fainted.size() == 1 and Array(fainted[0]["band"]) == CAST, "the player faints with its band: %s" % [fainted])
	_check(_of(events, "recovered").size() == 1 and bool(sim.player()["at_nest"]), "and recovers at the nest (%d ticks)" % waited)
	_check(Array(sim.band()) == CAST, "the band keeps every member")
	_check(_of(events, "ack").size() == 3, "each member follows again")


func _dismiss() -> void:
	var sim := stage.sim
	var mark := stage.event_log.size()
	stage.dismiss("b3")
	await _frames(1)
	var events := _since(mark)
	_check(_of(events, "dismissed").size() == 1 and not sim.band().has("b3") and sim.band().size() == 2,
			"one member is dismissed: band %s" % [sim.band()])
	var ack := _of(events, "ack")
	_check(ack.size() == 1 and ack[0]["words"] == "goes back to the den", "it says where it goes: %s" % [ack])


## Leaving returns to the title; the title's Social stage button opens the stage again, which still reads the slot;
## the pause key asks first and Back to title leaves.
func _leave_and_return(slot: String) -> void:
	stage.leave()
	await _frames(SETTLE_FRAMES)
	_check(main.social_stage == null and main.start_screen != null and main.screen == main.start_screen,
			"leaving returns to the title")
	if main.start_screen == null:
		return
	var button: Button = main.start_screen.social_button
	_check(button != null and button.visible and button.get_parent().name == "Preview",
			"the title shows the Social stage button under Preview")
	if button == null:
		return
	button.pressed.emit()
	await _frames(SETTLE_FRAMES)
	stage = main.social_stage
	_check(stage != null and main.screen == stage, "the title's Social stage button opens the stage")
	if stage == null:
		return
	_check(stage.slot == slot and stage.body_source == "slot", "on the same slot's creature (%s)" % stage.body_source)
	await _press(&"pause")
	_check(not stage.hud.card_visible() and not stage.leave_dialog.is_open(), "a first key press only closes the card")
	await _press(&"pause")
	_check(stage.leave_dialog.is_open() and stage.held(), "the pause key asks before leaving, the sim held")
	stage.leave_dialog.choose("leave")
	await _frames(SETTLE_FRAMES)
	_check(main.social_stage == null and main.screen == main.start_screen, "Back to title leaves")


func _press(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(2)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
	await _frames(2)


## Puts the player `dist` m in front of individual `id`, facing it (as the sim tests do).
func _stand_before(id: String, dist: float) -> void:
	var c := stage.sim.individual(id)
	var p := _ground(c["position"])
	var at := p + Vector2(-sin(c["yaw"]), -cos(c["yaw"])) * dist
	var to := p - at
	stage.sim.place(SocialSim.PLAYER_ID, at, atan2(-to.x, -to.y))


func _gap(id: String) -> float:
	return _ground(stage.sim.individual(id)["position"]).distance_to(_ground(stage.sim.player()["position"]))


func _since(mark: int) -> Array:
	return stage.event_log.slice(mark)


static func _of(events: Array, kind: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["kind"] == kind)


static func _ground(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _listing(dir: String) -> Array:
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	return files


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])
