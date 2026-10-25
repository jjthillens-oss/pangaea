extends SceneTree
## Screenshots of the Aquatic stage for the look review (aquatic-r2): the real AquaticStage with the player parked
## at fixed places along the route, and the fin and tail editor. The sim is not stepped (nothing moves), so a view
## is the same frame on every run. Run under Xvfb (docs/TOOLCHAIN.md):
##   xvfb-run -a -s "-screen 0 1920x1080x24" GODOT --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 1920x1080 --fixed-fps 60 \
##     --script res://tools/godot/aquatic_shots.gd -- --out=DIR [--view=nest_start,editor,...]
## Views: nest_start (the spawn frame), nest_far (looking back at the nest from about 25 m), reef_west and reef_east
## (the reef shelters), twilight_ledge (the ledge shelter), fallen_giant, deep_vents, editor (the fin and tail
## editor as it opens) and editor_tails (one editor frame per tail in the rules, the fish held side-on:
## editor_tail_<id>.png; with --close, close views of the fish only at tail strength 3: tail_<id>_<angle>.png, then
## fins_<n>_<angle>.png for the side fin steps and dorsal_<n>_<angle>.png for the back fin steps).

const StageScript := preload("res://game/scenes/aquatic/aquatic_stage.gd")
## view -> [player position, heading]. Heading 0 faces -Z (down the route), PI faces back to the shore.
const PLACES := {
	"nest_start": [],
	"nest_far": [Vector3(6.0, -12.0, -16.0), PI],
	"reef_west": [Vector3(-12.0, -15.0, -36.0), -0.25],
	"reef_east": [Vector3(14.0, -20.0, -72.0), -0.25],
	"twilight_ledge": [Vector3(-4.0, -30.0, -106.0), 0.25],
	"fallen_giant": [Vector3(-16.0, -64.0, -212.0), 0.35],
	"deep_vents": [Vector3(6.0, -72.0, -250.0), 0.0],
}
const ALL_VIEWS := ["nest_start", "nest_far", "reef_west", "reef_east", "twilight_ledge", "fallen_giant",
		"deep_vents", "editor", "editor_tails"]

var out_dir := "user://aquatic_shots"
var views: PackedStringArray = []
var close := false
var stage: Node


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--view="):
			views = arg.trim_prefix("--view=").split(",", false)
		elif arg == "--close":
			close = true
	if views.is_empty():
		views = PackedStringArray(ALL_VIEWS)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	stage = StageScript.new()
	stage.name = "AquaticStage"
	root.add_child(stage)
	stage.setup("", 4250)
	stage.set_physics_process(false)
	stage.hud.hide_card()
	var start: Dictionary = {"pos": stage.sim.player.pos, "heading": float(stage.sim.player.heading)}
	for view in views:
		if PLACES.has(view):
			var place: Array = PLACES[view]
			var pos: Vector3 = start.pos if place.is_empty() else place[0]
			pos.y = maxf(pos.y, stage.sim.floor_at(pos.x, pos.z) + 2.0)
			stage.sim.player.pos = pos
			stage.sim.player.heading = start.heading if place.is_empty() else float(place[1])
			stage.world.sync(0.0)
			await _frames(30)
			await _shot(view)
		elif view == "editor":
			var editor: Control = stage.open_editor()
			await _frames(30)
			await _shot("editor")
			editor.call("cancel_edit")
			await _frames(4)
		elif view == "editor_tails":
			await _tails()
		else:
			push_warning("aquatic_shots: unknown view '%s'" % view)
	quit(0)


func _tails() -> void:
	var editor: Control = stage.open_editor()
	await _frames(10)
	editor.set_process(false)
	var holder: Node3D = editor.get("rig_holder")
	holder.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	if close:
		# The tails at full strength, then the fin steps and the dorsal, each from the angles that show them.
		editor.set("points", 99)
		editor.call("step", "tail_size", 3)
		for tail in stage.rules.body.tails:
			editor.call("set_choice", "tail", String(tail))
			await _close_shots(editor, "tail_%s" % tail, ["side", "rear", "top"])
		editor.call("set_choice", "tail", "fluke")
		for fins in [1, 2, 3]:
			editor.call("step", "fins", fins - int(editor.get("body").fins))
			await _close_shots(editor, "fins_%d" % fins, ["front", "top"])
		for dorsal in [0, 1, 2]:
			editor.call("step", "dorsal", dorsal - int(editor.get("body").dorsal))
			await _close_shots(editor, "dorsal_%d" % dorsal, ["side", "front"])
	else:
		for tail in stage.rules.body.tails:
			editor.call("set_choice", "tail", String(tail))
			holder.rotation = Vector3(0.0, -PI * 0.5, 0.0)
			await _frames(20)
			await _shot("editor_tail_%s" % tail)
	editor.call("cancel_edit")
	await _frames(4)


## Close views of the editor's fish (it faces +X, side-on to the camera): only the plinth viewport is saved.
func _close_shots(editor: Control, name: String, angles: Array) -> void:
	var viewport := editor.get("viewport") as SubViewport
	var cam := viewport.get_camera_3d()
	var places := {
		"side": [Vector3(0.0, 0.95, 1.9), Vector3(0.0, 0.85, 0.0)],
		"rear": [Vector3(-1.6, 1.6, 1.15), Vector3(-0.35, 0.85, 0.0)],
		"front": [Vector3(1.4, 1.5, 1.35), Vector3(0.15, 0.85, 0.0)],
		"top": [Vector3(0.0, 2.7, 0.05), Vector3(0.0, 0.85, 0.0)],
	}
	for angle in angles:
		cam.position = places[angle][0]
		cam.look_at(places[angle][1], Vector3.UP)
		await _frames(12)
		var path := out_dir.path_join("%s_%s.png" % [name, angle])
		viewport.get_texture().get_image().save_png(path)
		print("aquatic_shots: wrote ", path)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await process_frame
	var path := out_dir.path_join(name + ".png")
	root.get_viewport().get_texture().get_image().save_png(path)
	print("aquatic_shots: wrote ", path)
