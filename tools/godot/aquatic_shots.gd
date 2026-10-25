extends SceneTree
## Screenshots of the Aquatic stage for the look review (aquatic-r2): the real AquaticStage with the player parked
## at fixed places along the route, and the fin and tail editor. The sim is not stepped (nothing moves), so a view
## is the same frame on every run. Run under Xvfb (docs/TOOLCHAIN.md):
##   xvfb-run -a -s "-screen 0 1920x1080x24" GODOT --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 1920x1080 --fixed-fps 60 \
##     --script res://tools/godot/aquatic_shots.gd -- --out=DIR [--view=nest_start,editor,...]
## Views: nest_start (the spawn frame), nest_far (looking back at the nest from about 25 m), reef_west and reef_east
## (the reef shelters), twilight_ledge (the ledge shelter), fallen_giant, deep_vents; aquatic-r2's content:
## shallows_minnows (the minnow school), fallen_giant_near (the dead giant and its carcass), reef_cleaners (a hurt friend resting at the cleaner station, the sim stepped
## 4 s so they gather), glowfins_lured (a deep lure body by the glowfins' home, stepped 6 s), krill_pillars (the
## krill swarm and the pillar ring), vent_chimney; editor (the fin and tail
## editor as it opens) and editor_tails (one editor frame per tail in the rules, the fish held side-on:
## editor_tail_<id>.png; with --close, close views of the fish only at tail strength 3: tail_<id>_<angle>.png, then
## fins_<n>_<angle>.png for the side fin steps and dorsal_<n>_<angle>.png for the back fin steps).

const StageScript := preload("res://game/scenes/aquatic/aquatic_stage.gd")
## view -> [player position, heading, or a point to face]. Heading 0 faces -Z (down the route), PI faces back to the
## shore.
const PLACES := {
	"nest_start": [],
	"nest_far": [Vector3(6.0, -12.0, -16.0), PI],
	"reef_west": [Vector3(-12.0, -15.0, -36.0), -0.25],
	"reef_east": [Vector3(14.0, -20.0, -72.0), -0.25],
	"twilight_ledge": [Vector3(-4.0, -30.0, -106.0), 0.25],
	"fallen_giant": [Vector3(-16.0, -64.0, -212.0), 0.35],
	"deep_vents": [Vector3(6.0, -72.0, -250.0), 0.0],
	"shallows_minnows": [Vector3(5.0, -4.5, -1.0), Vector3(12.0, -5.0, -8.0)],
	"fallen_giant_near": [Vector3(-10.0, -66.0, -216.0), Vector3(-22.0, -73.0, -232.0)],
	"reef_cleaners": [],
	"glowfins_lured": [],
	"krill_pillars": [Vector3(-4.0, -36.0, -136.0), Vector3(8.0, -42.0, -162.0)],
	"vent_chimney": [Vector3(15.0, -77.0, -247.0), Vector3(28.0, -82.0, -262.0)],
}
## The views that step the sim or change the fish come last, so they leave the others as they were.
const ALL_VIEWS := ["nest_start", "nest_far", "reef_west", "reef_east", "twilight_ledge", "fallen_giant",
		"deep_vents", "shallows_minnows", "fallen_giant_near", "krill_pillars", "vent_chimney", "editor", "editor_tails", "reef_cleaners",
		"glowfins_lured"]

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
		if view == "reef_cleaners":
			# A hurt friend of the cleaners rests at their station; they gather round it.
			var sim: AquaticSim = stage.sim
			sim.relations.cleaner.standing = "friend"
			sim.player.health = float(sim.player.stats.max_health) * 0.4
			await _hold(sim.home_of("cleaner") + Vector3(0.0, 0.0, 1.5), 0.0, 4.0)
			await _shot(view)
		elif view == "glowfins_lured":
			# A deep-rated lure body waits by the glowfins' home; they come to its lure.
			var sim: AquaticSim = stage.sim
			var angler := AquaticBody.HOVERER.duplicate()
			angler.girth = 3
			angler.bladder = 3
			angler.sense = "lure"
			angler.mouth = "jaw"
			sim.apply_offspring(angler, 0)
			sim.take_events()
			stage.world.rebuild_player()
			await _hold(sim.home_of("glowfin") + Vector3(0.0, 0.0, 9.0), 0.0, 6.0)
			await _shot(view)
		elif PLACES.has(view):
			var place: Array = PLACES[view]
			var pos: Vector3 = start.pos if place.is_empty() else place[0]
			pos.y = maxf(pos.y, stage.sim.floor_at(pos.x, pos.z) + 2.0)
			stage.sim.player.pos = pos
			var heading := float(start.heading)
			if place.size() > 1 and place[1] is Vector3:
				var to: Vector3 = place[1] - pos
				heading = atan2(-to.x, -to.z)
			elif place.size() > 1:
				heading = float(place[1])
			stage.sim.player.heading = heading
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


## Steps the sim `seconds` with the fish held at `pos`, facing `heading`, still, then lets the view settle.
func _hold(pos: Vector3, heading: float, seconds: float) -> void:
	var sim: AquaticSim = stage.sim
	for i in int(seconds * AquaticSim.TICK_HZ):
		sim.player.pos = pos
		sim.player.heading = heading
		sim.player.speed = 0.0
		sim.step(AquaticSim.Intent.new())
		sim.take_events()
	stage.world.sync(0.0)
	await _frames(30)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await process_frame
	var path := out_dir.path_join(name + ".png")
	root.get_viewport().get_texture().get_image().save_png(path)
	print("aquatic_shots: wrote ", path)
