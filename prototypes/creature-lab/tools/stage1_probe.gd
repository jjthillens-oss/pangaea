extends SceneTree
## Stage 1 quick probe: validity, skin build, closure, triangles and bones for each test body.
## Run: godot --headless --path prototypes/creature-lab --script res://tools/stage1_probe.gd

const Lab := preload("res://lab_spine.gd")
const BodyCodec := preload("res://domain/body_codec.gd")
const SkinCpu := preload("res://skin/skin_cpu.gd")
const MeshChecks := preload("res://skin/mesh_checks.gd")


func _init() -> void:
	var rules := Lab.rules()
	for body_name in Lab.stage1_names():
		var desc = Lab.body(body_name)
		var problems: PackedStringArray = desc.validate(rules)
		var skin := SkinCpu.build(desc, int(rules["preview_divisions"]))
		var game := SkinCpu.build(desc, int(rules["gameplay_divisions"]))
		print("%-16s valid %s  bones %d  bytes %d  /48 tris %d closed %s pieces %d fixes %d  %.0f ms  /40 tris %d"
				% [body_name, problems.is_empty(), desc.bone_count(), BodyCodec.encode(desc).length(),
				skin["indices"].size() / 3, MeshChecks.watertight(skin["indices"]),
				MeshChecks.pieces(skin["indices"]), skin["topology_fixes"], skin["ms"]["total"],
				game["indices"].size() / 3])
		for p in problems:
			print("    ", p)
	quit()
