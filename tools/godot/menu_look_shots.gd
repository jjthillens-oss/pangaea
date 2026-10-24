extends SceneTree
## Look-review screenshots of the title screen and the creature editor (menus pass). Run under Xvfb:
##   xvfb-run -a -s "-screen 0 1920x1080x24" GODOT --path . --audio-driver Dummy --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 1920x1080 --script res://tools/godot/menu_look_shots.gd -- --out=DIR
## Uses its own slots and settings under user://shots/, never the player's.

const ROOT := "user://shots"

var out_dir := "user://menu_look"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	SaveSlots.folder = ROOT.path_join("saves")
	var service := SettingsService.new(ROOT.path_join("settings.cfg"))
	service.load_file()
	SettingsService.set_shared(service)
	var main: Node = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(90)
	_shot("title")
	main.open_creature_stage()
	await _frames(90)
	_shot("editor")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
