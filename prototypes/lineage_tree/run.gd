extends SceneTree

const TreeModel := preload("res://lineage_tree.gd")


func _init() -> void:
	var save_path := ""
	var out_path := ""
	var ascii_only := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--save="):
			save_path = argument.trim_prefix("--save=")
		elif argument.begins_with("--out="):
			out_path = argument.trim_prefix("--out=")
		elif argument == "--ascii-only":
			ascii_only = true
		else:
			printerr("Unknown option: " + argument)
			quit(2)
			return
	if save_path == "":
		printerr("Missing --save=PATH")
		quit(2)
		return
	var result: Dictionary = TreeModel.load_save(save_path)
	if not result["ok"]:
		printerr(result["error"])
		quit(2)
		return
	var tree: Dictionary = TreeModel.timeline(result["save"])
	print(TreeModel.ascii(tree).trim_suffix("\n"))
	if not ascii_only:
		if out_path == "":
			out_path = save_path.get_basename() + ".svg"
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file == null:
			printerr("Cannot write SVG: " + out_path)
			quit(2)
			return
		file.store_string(TreeModel.svg(tree, result["save"]))
		print("SVG: " + out_path)
	quit(0)
