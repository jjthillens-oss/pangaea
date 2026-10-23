extends SceneTree
## Screenshots of the menus for review (UI pass). Run under Xvfb (docs/TOOLCHAIN.md):
##   xvfb-run -a -s "-screen 0 1920x1080x24" GODOT --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 1920x1080 --script res://tools/ui_shots.gd -- --out=DIR
## --text-scale=115 or 130 takes them at a larger text size. Uses its own slots and settings under
## user://shots/, never the player's.

const ROOT := "user://shots"

var out_dir := "user://shots_out"
var text_scale := 100
var main: Main


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--text-scale="):
			text_scale = arg.trim_prefix("--text-scale=").to_int()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	_wipe(ROOT)
	SaveSlots.folder = ROOT.path_join("saves")
	var service := SettingsService.new(ROOT.path_join("settings.cfg"))
	service.load_file()
	service.set_value("accessibility/text_scale", text_scale)
	SettingsService.set_shared(service)
	main = load("res://game/scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(20)
	await _shot("title_empty")

	# A lineage in slot 1, then back to the title.
	main.start_new("hunter", 4242)
	main.pool.pause_on_focus_loss = false
	await _frames(40)
	main.save_and_quit_to_title()
	await _frames(20)
	await _shot("title_saved")

	main.start_screen.open_picker()
	await _frames(40)
	await _shot("picker")
	main.start_screen.select("hunter")
	await _frames(40)
	await _shot("picker_hunter")
	main.start_screen.show_main()
	await _frames(20)

	main.open_slots()
	await _frames(20)
	await _shot("slots")
	main.slot_picker.close()
	await _frames(5)

	var menu := main.open_settings()
	for i in SettingsMenu.TABS.size():
		menu.show_tab(i)
		await _frames(6)
		await _shot("settings_%s" % SettingsMenu.TABS[i].to_lower())
	InputPrompts.device = "pad"
	InputPrompts.generation += 1
	menu.show_tab(2)
	menu.begin_capture("grow", "pad")
	await _frames(6)
	await _shot("settings_controls_pad_capture")
	menu.close()
	await _frames(5)
	await _shot("title_pad_hint")
	InputPrompts.device = "keys"
	InputPrompts.generation += 1

	main.continue_run()
	main.pool.pause_on_focus_loss = false
	await _frames(40)
	main.pool.request_pause("key")
	await _frames(6)
	await _shot("pause_menu")
	_wipe(ROOT)
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(shot_name + ".png"))
	print("shot ", shot_name)


func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)
