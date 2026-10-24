extends SceneTree
## Two-process creature stage smoke (creature-stage plan, PROPOSED). tools/check.sh runs it twice with
## --fixed-fps 60, so each frame is one sim tick. It drives the real main scene into the creature stage and through
## the editor's and the world's method twins, as a player would use the mouse, the keys and the pad, and prints one
## PASS or FAIL line per check and a TIME line per step. Exit code 0 when every check passes, 1 otherwise.
##
##   -- --phase=build --creature --slot=user://smoke/creature.json --seed=4242
##       Main opens the stage into the editor on the starter quadruped. The limb tool grows a pair of limbs at the
##       neck, then a maw, two eyes and two feet go on (aimed with screen_of / handle_screen), the points fall, a
##       swatch is chosen, and Done enters the world with that body, colour and title. A scripted drive walks to
##       the nearest ripe fruit (an "ate" event, the points up), bites the nearest rival when one is in reach (or
##       notes that none came within 20 s), walks back to the nest and evolves: the editor again, with the points.
##       Done once more, Escape in the world (back to the editor, the points kept), Escape in the editor (the
##       title), then Quit. creature_expect.json records what the lineage save must hold.
##   -- --phase=reload --creature --slot=user://smoke/creature.json
##       A new process opens the stage from that lineage save and finds the same body SHA-256, points and generation.
##
## The stage writes into the session's lineage slot (save schema v3). The slot stays under user://smoke/ (the build
## phase clears it with its .tmp and .bak first): the smoke stops before playing if --slot points anywhere else.

const MAIN_SCENE := "res://game/scenes/main.tscn"
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const WalkerRig := preload("res://game/scenes/creature/walker_rig.gd")
const Picking := preload("res://game/domain/creature/editor_picking.gd")
const SMOKE_DIR := "user://smoke"
const EXPECT_PATH := "user://smoke/creature_expect.json"
const STARTER := "quadruped"
const SWATCH := 2                   ## the skin swatch chosen in the editor (CreatureEditor.SKIN_COLORS)
const FRUIT_TICKS := 3600           ## the nearest ripe fruit is reached within 60 s of sim time
const BITE_TICKS := 1200            ## a rival is bitten within 20 s, else the check is skipped with a note
const NEST_TICKS := 3600            ## the walk back to the nest
const SETTLE_FRAMES := 3            ## a screen change (deferred signals, the skin worker) settles in this many
const DRAW_TOLERANCE_M := 2.0       ## the player's rig is drawn this close to the sim's position


## Calls back after every other node's _process each frame (the highest process_priority), so it sees what the
## world's physics tick left behind in that frame.
class FrameProbe extends Node:
	var on_frame: Callable

	func _init(callback: Callable) -> void:
		on_frame = callback
		process_priority = 1000

	func _process(_delta: float) -> void:
		on_frame.call()


var main: Main
var _failures := 0
var _checks := 0
var _finished := false
var _quit_expected := false
var _step_name := ""
var _step_msec := 0
## The world watched by the probe, its last tick seen and the events since _watch(), by kind.
var _world: CreatureWorld
var _last_tick := -1
var _events := {}


func _initialize() -> void:
	var phase := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):
			phase = arg.trim_prefix("--phase=")
	print("Creature smoke, phase '%s', build %s" % [phase, BuildInfo.build_id()])
	root.add_child(FrameProbe.new(_probe_frame))
	match phase:
		"build":
			await _build()
		"reload":
			await _reload()
		_:
			_check(false, "--phase is build or reload (got '%s')" % phase)
	_report()


## The game quit: as the phases expect after Quit, or before the smoke finished (a quit with exit code 0 would
## hide that).
func _finalize() -> void:
	if _finished:
		return
	_finished = true
	if _quit_expected:
		_check(true, "Quit closes the game")
		_report()
		return
	print("FAIL the game quit before the smoke finished (step '%s')" % _step_name)
	quit(1)


func _report() -> void:
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


# Build phase

func _build() -> void:
	_begin("stage opens")
	_remove(EXPECT_PATH)
	await _open_main()
	if not _store_is_safe():
		return
	_remove(_slot())
	_remove(_slot() + PersistenceService.TEMP_SUFFIX)
	_remove(_slot() + PersistenceService.BACKUP_SUFFIX)   # a load falls back to the .bak
	# Opened before the slot was cleared: open it again on the empty slot.
	var stage := main.open_creature_stage()
	await _frames(SETTLE_FRAMES)
	_check(stage != null and main.screen == stage and main.creature_stage == stage, "--creature opens the creature stage as the screen")
	_check(stage.mode() == "editor" and stage.load_problems.is_empty(), "the stage opens in the editor on a fresh slot %s" % [stage.load_problems])
	var editor := stage.editor_scene()
	_check(editor != null, "the editor scene is up")
	if editor == null:
		return
	_check(_text_without_colour(editor.working_body()) == BodyCodec.encode(CreatureData.body(STARTER)), "on the starter quadruped")
	_check(editor.points() == CreatureRules.start_points(), "with the start points (%d)" % editor.points())
	_check(int(stage.state["world_seed"]) == main.flags.seed_value, "the stage uses the --seed world seed (%d)" % int(stage.state["world_seed"]))
	_check(not FileAccess.file_exists(stage.slot_path), "nothing is written until something happens")
	_end()

	_begin("editor edits")
	var points_before := editor.points()
	var desc = editor.working_body()
	var chains_before: int = desc.limb_chains().size()
	var parts_before: int = desc.parts.size()
	var side := signf(editor.camera.global_position.x)
	var head: Vector3 = desc.position_m(0)
	var r0: float = desc.radius_m(0)
	editor.choose_tool("maw")
	# Under the chin, on the spine (a maw snaps to the middle line); the head's own parts crowd the rest of it, so
	# the maw and the eyes go on before the neck limbs.
	var on_spine := func(hit: Dictionary) -> bool:
		return String(Picking.anchor_at(editor.working_body(), hit["field"], hit["point"])["host"]) == "spine"
	var maw_at := _aim(editor, _spread(head + Vector3(0.0, -0.6 * r0, -0.2 * r0), r0, side, [-0.2, 0.0, 0.2])
			+ _spread(head + Vector3(0.0, -0.6 * r0, 0.3 * r0), r0, side, [-0.2, 0.0, 0.2]), on_spine)
	var maw := editor.click_skin(maw_at) if maw_at.x >= 0.0 else {"ok": false, "reason": "no spot"}
	_check(bool(maw["ok"]), "a maw on the head: %s" % maw.get("reason", ""))
	editor.choose_tool("eye")
	# Off the top and bottom lines by more than the editor's middle snap, so the eye gets a twin.
	var eye_at := _aim(editor, _spread(head + Vector3(0.0, 0.0, 0.2 * r0), r0, side, [0.2, 0.4, 0.0, 0.6]),
			func(hit: Dictionary) -> bool: return absf((hit["point"] as Vector3).x) > 0.3 * r0)
	var eyes := editor.click_skin(eye_at) if eye_at.x >= 0.0 else {"ok": false, "reason": "no spot"}
	_check(bool(eyes["ok"]), "eyes on the head: %s" % eyes.get("reason", ""))
	desc = editor.working_body()
	var eye_parts: Array = desc.parts.filter(func(p): return p["type"] == "eye")
	_check(eye_parts.size() >= 2 and bool(eye_parts.back()["mirror"]), "a mirrored pair of eyes")
	# The neck: a spot between the first two vertebrae where the ray enters the skin off the middle plane (so the
	# limb tool grows a mirrored pair) and no handle is in reach of the press (it would be grabbed instead).
	var neck_mid: Vector3 = (desc.position_m(0) + desc.position_m(1)) * 0.5
	var r1: float = desc.radius_m(1)
	var neck := _aim(editor, _spread(neck_mid, r1, side, [-0.4, -0.2, 0.0, 0.2, 0.4, 0.6]),
			func(hit: Dictionary) -> bool: return absf((hit["point"] as Vector3).x) > 0.3 * _nearest_radius(desc, hit["point"]))
	_check(neck.x >= 0.0, "a neck spot off the middle plane and clear of the handles (%s)" % neck)
	editor.choose_tool("limb")
	_check(editor.tool == "limb", "the limb tool is chosen")
	var grown := editor.press(neck)
	_check(bool(grown["ok"]) and editor.dragging and editor.selected.get("kind", "") == "joint",
			"a limb grows from the neck with its tip in hand: %s %s" % [grown.get("reason", ""), editor.selected.get("kind", "")])
	var limb_id := ""
	if bool(grown["ok"]) and editor.selected.get("kind", "") == "joint":
		limb_id = String(editor.selected["limb"])
		var tip: Vector3 = editor.selected["world"]
		var to: Vector2 = editor._unproject(tip + Vector3(0.0, -0.05, -0.08))
		var pulled := editor.drag_to(to)
		_check(pulled.is_empty() or bool(pulled.get("ok", true)), "its tip is pulled out: %s" % pulled.get("reason", ""))
	editor.release()
	desc = editor.working_body()
	var limb_index: int = desc.limb_index(limb_id) if not limb_id.is_empty() else -1
	_check(limb_index >= 0 and bool(desc.limbs[limb_index]["mirror"]) and desc.limb_chains().size() == chains_before + 2,
			"a mirrored pair of limbs (%d chains)" % desc.limb_chains().size())
	if limb_index >= 0:
		var tip_id := String(desc.limbs[limb_index]["joints"][-1]["id"])
		_check(editor.handle_screen("joint", tip_id).x >= 0.0, "the new tip's handle is on screen")
	var feet := {"ok": false, "reason": "no limb"}
	if limb_index >= 0:
		# The new limb, between its second and third joints (clear of their handles): a foot goes to its end.
		var joints: Array = desc.limbs[limb_index]["joints"]
		var mid := (_joint_m(desc, joints[1]) + _joint_m(desc, joints[2])) * 0.5
		var radius: float = float(joints[1]["r"]) * desc.scale_m()
		editor.choose_tool("foot")
		var foot_at := _aim(editor, [mid, mid + Vector3(0.0, 0.3 * radius, 0.0), mid - Vector3(0.0, 0.3 * radius, 0.0)],
				func(hit: Dictionary) -> bool: return (hit["point"] as Vector3).distance_to(mid) < 2.0 * radius)
		feet = editor.click_skin(foot_at) if foot_at.x >= 0.0 else {"ok": false, "reason": "no spot"}
	_check(bool(feet["ok"]), "feet at the limbs' ends: %s" % feet.get("reason", ""))
	desc = editor.working_body()
	var foot_parts: Array = desc.parts.filter(func(p): return p["type"] == "foot")
	_check(not foot_parts.is_empty() and bool(foot_parts.back()["mirror"]) and String(foot_parts.back()["host"]).ends_with(":end"),
			"a mirrored pair of feet on the limbs' ends (%s)" % [foot_parts.back() if not foot_parts.is_empty() else {}])
	_check(desc.parts.size() == parts_before + 3, "three part entries added (%d)" % (desc.parts.size() - parts_before))
	var cost: int = editor.session.cost()
	_check(cost > 0 and editor.session.preview()["affordable"], "the edits cost %d points, affordable" % cost)
	await _frames(1)
	_check(editor.hud.cost_text.text.contains(str(points_before - cost)), "the HUD shows the points left (%s)" % editor.hud.cost_text.text)
	var swatch: Color = CreatureEditor.SKIN_COLORS[SWATCH]
	editor.set_skin_color(swatch)
	_check(editor.skin_color == swatch and String(editor.working_body().extra.get("skin_color", "")) == swatch.to_html(false), "a swatch chosen")
	_check(editor.refusal_text == "", "nothing refused (%s)" % editor.refusal_text)
	var body_text := BodyCodec.encode(editor.working_body())
	_end()

	_begin("done enters the world")
	var done := editor.finish()
	_check(bool(done["ok"]) and int(done["points_left"]) == points_before - cost, "Done commits: %s" % done.get("reason", ""))
	await _frames(SETTLE_FRAMES)
	_check(stage.mode() == "world" and stage.editor == null, "the stage enters the world")
	var world := stage.world_scene()
	_check(world != null and world.sim != null, "the world scene is up")
	if world == null or world.sim == null:
		return
	_check(world.sim.points == points_before - cost, "the world starts with the points left (%d)" % world.sim.points)
	_check(BodyCodec.encode(world.sim.body_of("player")) == body_text, "on the committed body")
	_check(stage.last_save == OK and FileAccess.file_exists(stage.slot_path), "Done saved the lineage slot")
	_check(world.player_rig is WalkerRig and world.sim.player()["has_legs"], "the player walks on a walker rig")
	var mat := world.player_rig.body.mesh_instance.material_override as ShaderMaterial
	_check(mat != null and (mat.get_shader_parameter("color_base") as Color).is_equal_approx(swatch), "the player's skin is the swatch's colour")
	_check(world.hud._name_text.text == "Newcomer · Generation 1", "the HUD names the creature and generation (%s)" % world.hud._name_text.text)
	_check(world.hud._points_text.text == "Points %d" % world.sim.points, "the HUD shows the points (%s)" % world.hud._points_text.text)
	_check(world.hud.notice_text() == "", "no notice (%s)" % world.hud.notice_text())
	print("    setup %s" % [world.setup_ms])
	_end()

	_begin("eats")
	_watch(world)
	var points_at_start: int = world.sim.points
	var walked := await _walk_until(world, func() -> Vector3: return _nearest_ripe_fruit(world),
			func() -> bool: return _count("ate") > 0, FRUIT_TICKS)
	_check(_count("ate") > 0, "the player ate the nearest fruit after %.1f s" % (walked * CreatureWorldSim.DT))
	_check(world.sim.points > points_at_start, "the points went up (%d -> %d)" % [points_at_start, world.sim.points])
	_check(world.hud._points_flash.visible, "the HUD flashes the meal")
	var drawn: Vector3 = world.player_rig.body.transform.origin
	_check(drawn.is_finite() and drawn.distance_to(world.sim.player()["position"]) < DRAW_TOLERANCE_M, "the rig is drawn at the sim's position")
	_end()

	_begin("bites")
	var bit_before := _count("bit")
	var chased := await _walk_until(world, func() -> Vector3: return _nearest_rival(world),
			func() -> bool: return _count("bit") > bit_before, BITE_TICKS, true)
	if _count("bit") > bit_before:
		_check(true, "the player bit a rival after %.1f s" % (chased * CreatureWorldSim.DT))
	else:
		print("NOTE no rival came within reach in %d s; the bite check is skipped" % int(BITE_TICKS * CreatureWorldSim.DT))
	world.set_intent(Vector2.ZERO, false, false)
	_end()

	_begin("evolves at the nest")
	var home := await _walk_until(world, func() -> Vector3: return world.sim.nest, func() -> bool: return world.sim.at_nest(), NEST_TICKS)
	_check(world.sim.at_nest(), "back at the nest after %.1f s" % (home * CreatureWorldSim.DT))
	var points_at_nest: int = world.sim.points
	world.set_intent(Vector2.ZERO, false, true)
	await _frames(SETTLE_FRAMES)
	_check(stage.mode() == "editor" and stage.world == null, "evolve leaves the world")
	var editor2 := stage.editor_scene()
	_check(editor2 != null and editor2.points() == points_at_nest, "the editor is back with the points (%d)" % points_at_nest)
	_check(int(stage.state["generation"]) == 2 and (stage.state["history"] as Array).size() == 1, "generation 2, generation 1 in the history")
	_check(stage.save_now() == OK, "save_now writes the lineage slot")
	var stored := _read_slot()
	_check(stored.ok and stored.save.adaptation_points == points_at_nest and int(stored.save.creature["generation"]) == 2,
			"the lineage save holds them %s" % [stored.errors])
	_end()

	_begin("escape precedence")
	if editor2 == null:
		return
	var again := editor2.finish()
	_check(bool(again["ok"]), "Done without edits: %s" % again.get("reason", ""))
	await _frames(SETTLE_FRAMES)
	var world2 := stage.world_scene()
	_check(stage.mode() == "world" and world2 != null, "the world again")
	_check(world2 != null and world2.hud._name_text.text == "Newcomer · Generation 2", "the HUD's title moved to generation 2")
	await _key(KEY_ESCAPE)
	_check(stage.mode() == "editor" and stage.editor_scene() != null and stage.world == null, "Escape in the world goes back to the editor")
	_check(stage.editor_scene() != null and stage.editor_scene().points() == points_at_nest, "with the points kept")
	_check(main.screen == stage, "the stage is still the screen")
	await _key(KEY_ESCAPE)
	await _frames(SETTLE_FRAMES)
	_check(main.creature_stage == null and main.start_screen != null and main.screen == main.start_screen, "Escape in the editor leaves the stage for the title")
	var left := _read_slot()
	_check(left.ok and int(left.save.creature["generation"]) == 2 and left.save.adaptation_points == points_at_nest,
			"leaving saved the lineage save %s" % [left.errors])
	if left.ok:
		var creature: Dictionary = left.save.creature
		var expect := {"body_sha256": BodyCodec.hash_text(BodyCodec.from_dict(creature["body"])), "points": left.save.adaptation_points,
				"generation": int(creature["generation"]), "history": (creature["history"] as Array).size()}
		var file := FileAccess.open(EXPECT_PATH, FileAccess.WRITE)
		file.store_string(JSON.stringify(expect, "\t"))
		file.close()
		_check(FileAccess.file_exists(EXPECT_PATH), "expect.json written")
	_end()

	_begin("quit")
	_quit_expected = true
	main.quit_to_desktop()
	await _frames(2)


# Reload phase

func _reload() -> void:
	_begin("reload")
	await _open_main()
	if not _store_is_safe():
		return
	var expect_text := FileAccess.get_file_as_string(EXPECT_PATH)
	var expect = JSON.parse_string(expect_text)
	_check(expect is Dictionary, "creature_expect.json from the build phase")
	if not expect is Dictionary:
		return
	var stage := main.creature_stage
	_check(stage != null and main.screen == stage and stage.mode() == "editor", "the stage opens in the editor")
	if stage == null:
		return
	_check(stage.load_problems.is_empty(), "the lineage save loaded %s" % [stage.load_problems])
	_check(BodyCodec.hash_text(BodyCodec.from_dict(stage.state["body"])) == String(expect["body_sha256"]), "the same body SHA-256")
	_check(int(stage.state["points"]) == int(expect["points"]), "the same points (%d)" % int(stage.state["points"]))
	_check(int(stage.state["generation"]) == int(expect["generation"]) and (stage.state["history"] as Array).size() == int(expect["history"]),
			"the same generation and history")
	await _frames(SETTLE_FRAMES)
	var editor := stage.editor_scene()
	_check(editor != null and editor.points() == int(expect["points"]), "the editor opens with them")
	_check(editor != null and BodyCodec.hash_text(editor.working_body()) == String(expect["body_sha256"]), "on that body")
	_check(editor != null and editor.hud.points_text.text.contains(str(int(expect["points"]))),
			"the HUD shows the points (%s)" % (editor.hud.points_text.text if editor else ""))
	_end()

	_begin("quit")
	_quit_expected = true
	main.quit_to_desktop()
	await _frames(2)


# Drive

## Steers the player towards `goal.call()` every frame (camera-relative, as the world takes it), biting when `bite`,
## until `done.call()` or `max_frames`. Returns the frames run.
func _walk_until(world: CreatureWorld, goal: Callable, done: Callable, max_frames: int, bite := false) -> int:
	var frames := 0
	while not done.call() and frames < max_frames:
		var target: Vector3 = goal.call()
		var me: Vector3 = world.sim.player()["position"]
		var d := Vector2(target.x - me.x, target.z - me.z)
		var move := Vector2.ZERO
		if d.length() > 1e-3:
			move = _camera_relative(d.normalized(), world.camera_yaw)
		world.set_intent(move, bite, false)
		await process_frame
		frames += 1
	world.set_intent(Vector2.ZERO, false, false)
	return frames


## The inverse of CreatureWorld._camera_relative_to_world: a ground direction as the move the world turns back
## into it.
static func _camera_relative(d: Vector2, yaw: float) -> Vector2:
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(-forward.y, forward.x)
	return Vector2(d.dot(right), d.dot(forward))


static func _nearest_ripe_fruit(world: CreatureWorld) -> Vector3:
	var snap: Dictionary = world.sim.snapshot()
	var me := _vec(snap["player"]["position"])
	var best := INF
	var at := me
	for f in snap["fruit"]:
		if not f["ripe"]:
			continue
		var p := _vec(f["position"])
		var d := Vector2(p.x - me.x, p.z - me.z).length()
		if d < best:
			best = d
			at = p
	return at


static func _nearest_rival(world: CreatureWorld) -> Vector3:
	var snap: Dictionary = world.sim.snapshot()
	var me := _vec(snap["player"]["position"])
	var best := INF
	var at := me
	for r in snap["rivals"]:
		if not r["alive"]:
			continue
		var p := _vec(r["position"])
		var d := Vector2(p.x - me.x, p.z - me.z).length()
		if d < best:
			best = d
			at = p
	return at


static func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## The first of `candidates` (body-space points) whose screen position is clear of every handle and whose ray
## enters the skin at a point `want` accepts; Vector2(-1, -1) when none does.
static func _aim(editor: CreatureEditor, candidates: Array, want: Callable) -> Vector2:
	for c in candidates:
		var at := editor.screen_of(c)
		if is_nan(at.x) or not _clear_of_handles(editor, at):
			continue
		var hit: Dictionary = editor._skin_hit(at)
		if bool(hit["hit"]) and want.call(hit):
			return at
	return Vector2(-1, -1)


## Points around `centre` on the camera's side (`side`), `ups` radii up, each at three sideways reaches.
static func _spread(centre: Vector3, radius: float, side: float, ups: Array) -> Array:
	var out := []
	for up in ups:
		for sideways in [0.7, 1.0, 0.4]:
			out.append(centre + Vector3(sideways * radius * side, float(up) * radius, 0.0))
	return out


static func _nearest_radius(desc: RefCounted, p: Vector3) -> float:
	var best := 0
	for i in desc.vertebrae.size():
		if desc.position_m(i).distance_to(p) < desc.position_m(best).distance_to(p):
			best = i
	return desc.radius_m(best)


## The body's text with the editor's skin_color left out, to compare with a starter's.
static func _text_without_colour(desc: RefCounted) -> String:
	var dict: Dictionary = desc.to_dict().duplicate(true)
	for key in ["skin_color", "pattern_seed", "coat_pattern", "detail_pattern"]:   # the editor's look (creature_look.gd)
		dict.erase(key)
	return BodyCodec.encode(BodyCodec.from_dict(dict))


## No handle within the editor's pick distance of a screen point (a press there would grab it).
static func _clear_of_handles(editor: CreatureEditor, at: Vector2) -> bool:
	for h in editor.handles:
		if editor._unproject(h["world"]).distance_to(at) <= CreatureEditor.HANDLE_PICK_PX + 4.0:
			return false
	return true


static func _joint_m(desc: RefCounted, joint: Dictionary) -> Vector3:
	var p: Array = joint["p"]
	return Vector3(float(p[0]), float(p[1]), float(p[2])) * desc.scale_m()


# Watching

func _watch(world: CreatureWorld) -> void:
	_world = world
	_last_tick = world.sim.tick_count
	_events.clear()


## After the frame's _process: the player's events of the tick this frame ran (none when no tick ran).
func _probe_frame() -> void:
	if _world == null or not is_instance_valid(_world) or _world.sim == null:
		return
	if _world.sim.tick_count == _last_tick:
		return
	_last_tick = _world.sim.tick_count
	for e in _world.last_events():
		var mine: bool = e.get("who", e.get("by", "")) == CreatureWorldSim.PLAYER_ID
		if mine:
			_events[e["kind"]] = _count(String(e["kind"])) + 1


func _count(kind: String) -> int:
	return int(_events.get(kind, 0))


# Helpers

func _open_main() -> void:
	main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(2)


## The session's lineage slot, which the stage reads and writes.
func _slot() -> String:
	return main.session.slot


## The lineage save in the slot, read the way Continue reads it.
func _read_slot() -> Dictionary:
	return PersistenceService.new(PartCatalog.load_from()).load_from(_slot())


## Refuses to play unless the lineage slot is under user://smoke/.
func _store_is_safe() -> bool:
	var path := _slot()
	var safe := path.begins_with(SMOKE_DIR + "/")
	_check(safe, "the smoke plays on a slot under %s/ (%s)" % [SMOKE_DIR, path])
	return safe


func _frames(count: int) -> void:
	for i in count:
		await process_frame


## A key press and release, as the player's keyboard sends it.
func _key(keycode: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = down
		Input.parse_input_event(event)
		await _frames(1)
	await _frames(1)


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])


func _begin(step: String) -> void:
	_step_name = step
	_step_msec = Time.get_ticks_msec()


func _end() -> void:
	print("TIME %s: %d ms" % [_step_name, Time.get_ticks_msec() - _step_msec])
