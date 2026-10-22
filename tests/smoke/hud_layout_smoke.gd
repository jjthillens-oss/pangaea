extends SceneTree
## HUD layout smoke (M1 step 2). The top center of the HUD (the starving banner and one-off
## messages) must never run under the status panel (top left) or the points panel (top right).
## tools/check.sh runs it after the play smoke. It prints one PASS or FAIL line per check, and the
## exit code is 0 when every check passes, 1 otherwise.
##
##   For each starting body, Main starts a lineage on a slot whose folder cannot be created, so
##   the HUD shows the real "Not saved yet: ..." message, and the cell's energy is emptied, so the
##   starving banner shows too. Then an unbound HUD gets the longest texts it can be given.
##
## The canvas is 1920 x 1080 at every window size (stretch mode canvas_items), so one layout covers
## the 1280 x 720 window and full screen. Saves stay under user://smoke/.

const MAIN_SCENE := "res://game/scenes/main.tscn"
const HUD_SCENE := "res://game/ui/hud.tscn"
## A file where the slot's folder should be, so no save can be written.
const BLOCKED_DIR := "user://smoke/hud_layout_blocked"
const VIEW_SIZE := Vector2(1920, 1080)
const STATUS_W := 480.0
## The least space between two HUD panels, so their borders never touch.
const MIN_GAP_PX := 16.0
const HEX := "0123456789ABCDEF"

var main: Main
var _failures := 0
var _checks := 0
var _finished := false


func _initialize() -> void:
	print("HUD layout smoke, build %s" % BuildInfo.build_id())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BLOCKED_DIR.get_base_dir()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BLOCKED_DIR))
	var blocker := FileAccess.open(BLOCKED_DIR, FileAccess.WRITE)
	blocker.store_string("not a folder")
	blocker.close()
	main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	await _frames(2)
	main.open_session(BLOCKED_DIR.path_join("slot_1.json"))
	await _frames(1)
	for body in BodyText.ORDER:
		var result := main.start_new(body, 4242)
		await _frames(1)
		_check(result.ok and not result.saved and main.hud.message_text.text.begins_with("Not saved yet: "),
			"the %s's HUD says '%s'" % [body, main.hud.message_text.text])
		main.pool.sim.debug_set_energy(0.0)
		main.hud.refresh()
		await _frames(2)
		_check_layout(main.hud, "the %s" % body)
	main.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BLOCKED_DIR))
	await _frames(1)
	await _check_longest_texts()
	_finished = true
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


func _finalize() -> void:
	if not _finished:
		print("FAIL the game quit before the smoke finished")
		quit(1)


## An evolved lineage at generation 999 with the widest tag, a five-digit points count and a
## message three times as long as a failed save's.
func _check_longest_texts() -> void:
	var hud: Hud = (load(HUD_SCENE) as PackedScene).instantiate()
	root.add_child(hud)
	await _frames(1)
	var font := hud.lineage_text.get_theme_font(&"font")
	var size := hud.lineage_text.get_theme_font_size(&"font_size")
	var widest := "0"
	for c in HEX:
		if font.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > font.get_string_size(widest, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x:
			widest = c
	hud.lineage_text.text = BodyText.lineage_line("", widest.repeat(4) + "-" + widest.repeat(4), 999)
	hud.points_text.text = Hud.points_line(99999)
	hud.state_text.text = "Starving"
	hud.state_chip.theme_type_variation = Hud.CHIP_STYLES["Starving"]
	hud.health_row.visible = true
	hud.starving_banner.visible = true
	hud.show_message("Not saved yet: Could not save to user://saves/slot_1.json: Can't open file. ".repeat(3).strip_edges())
	await _frames(2)
	_check_layout(hud, "the longest texts")
	hud.queue_free()
	await _frames(1)


func _check_layout(hud: Hud, what: String) -> void:
	var status := (hud.get_node("Frame/Status") as Control).get_global_rect()
	var points := (hud.get_node("Frame/Right/Points") as Control).get_global_rect()
	var banner := hud.starving_banner.get_global_rect()
	var message := hud.message.get_global_rect()
	_check(hud.starving_banner.visible and hud.message.visible, "%s: the banner and a message show" % what)
	_check(absf(status.size.x - STATUS_W) < 0.5, "%s: the status panel is %d px wide (%s, lineage '%s')"
		% [what, STATUS_W, _span(status), hud.lineage_text.text])
	for side in [["status panel", status], ["points panel", points]]:
		for center in [["banner", banner], ["message", message]]:
			_check(not center[1].grow(MIN_GAP_PX).intersects(side[1]), "%s: the %s %s stays %d px clear of the %s %s"
				% [what, center[0], _span(center[1]), MIN_GAP_PX, side[0], _span(side[1])])
	_check(not banner.intersects(message), "%s: the banner and the message do not overlap" % what)
	_check(banner.size.x <= Hud.CENTER_MAX_W + 0.5 and message.size.x <= Hud.CENTER_MAX_W + 0.5,
		"%s: the banner (%d px) and the message (%d px) are at most %d px wide"
		% [what, banner.size.x, message.size.x, Hud.CENTER_MAX_W])
	var view := Rect2(Vector2.ZERO, VIEW_SIZE)
	_check(view.encloses(status) and view.encloses(points) and view.encloses(banner) and view.encloses(message),
		"%s: every panel is on screen" % what)


## "[517..1403 x 28..101]"
func _span(r: Rect2) -> String:
	return "[%d..%d x %d..%d]" % [r.position.x, r.end.x, r.position.y, r.end.y]


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", what])
