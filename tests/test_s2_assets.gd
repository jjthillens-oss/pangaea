extends TestCase
## The S2 (First growth) art already on main (s2-build-plan section 8, A3): the Lurker and elder
## rammer bodies, the algae ball, the morsel and remnant material overrides, the silt trail, the
## near ghosts, the haze sprites, the backdrops, and sample_cell's growth keys. Budgets, node names,
## material names (the bodies' drop-in contract, A4), blend shapes, and no food or threat hue in
## decor or ghosts.

const AMBIENCE := "res://assets/export/ambience/"
const RESERVED := {"food": Color("#CFE86A"), "threat": Color("#D9466B")}
const MIN_LAB_HUE_GAP_DEG := 25.0
## Below this LAB chroma a colour reads as grey and carries no hue to confuse.
const GREY_CHROMA := 8.0

## id -> [triangle budget, mesh node names, material names that must be present].
const BODIES := {
	"creature_lurker_body": [4000, ["Body", "Brow", "Eye_L", "Eye_R", "Pupil_L", "Pupil_R"],
		["M_AmbushBody", "M_AmbushBrow", "M_AmbushEye", "M_AmbushPupil"]],
	"creature_elder_rammer_body": [4000, ["Body", "Eye_L", "Eye_R", "Hood", "Lid_L", "Lid_R", "Pupil_L", "Pupil_R"],
		["M_RammerBody", "M_RammerEye", "M_RammerHood", "M_RammerLid", "M_RammerPupil", "M_Threat"]],
	"algae_ball": [400, ["AlgaeBall"], ["M_AlgaeBall"]],
}
## Texture name prefix -> [count, size].
const SPRITES := {
	"T_Ghost_": [9, Vector2i(512, 512)],
	"T_Haze_": [11, Vector2i(128, 128)],
	"T_Backdrop_": [5, Vector2i(-1, -1)],
	"T_SiltTrail": [1, Vector2i(256, 64)],
}
const OVERRIDES := ["res://assets/export/M_Morsel.tres", "res://assets/export/M_RemnantLimp.tres"]


func _lab(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	var x := (0.4124 * l.r + 0.3576 * l.g + 0.1805 * l.b) / 0.95047
	var y := 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b
	var z := (0.0193 * l.r + 0.1192 * l.g + 0.9505 * l.b) / 1.08883
	var f := func(t: float) -> float: return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
	return Vector3(116.0 * f.call(y) - 16.0, 500.0 * (f.call(x) - f.call(y)), 200.0 * (f.call(y) - f.call(z)))


## The smallest LAB hue gap from either reserved colour, or 180 for a grey colour.
func _reserved_gap(c: Color) -> float:
	var lab := _lab(c)
	if Vector2(lab.y, lab.z).length() < GREY_CHROMA:
		return 180.0
	var hue := rad_to_deg(atan2(lab.z, lab.y))
	var gap := 180.0
	for name: String in RESERVED:
		var r := _lab(RESERVED[name])
		gap = minf(gap, absf(fposmod(hue - rad_to_deg(atan2(r.z, r.y)) + 180.0, 360.0) - 180.0))
	return gap


func _files(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(AMBIENCE):
		if f.begins_with(prefix) and f.ends_with(".png"):
			out.append(f)
	return out


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D:
			out.append(n)
	return out


func test_bodies_keep_their_budgets_nodes_and_materials() -> void:
	for id: String in BODIES:
		var row: Array = BODIES[id]
		var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/records/%s.json" % id))
		check(int(record.get("triangles", 1 << 30)) <= int(row[0]), "%s within %d triangles" % [id, row[0]])
		var root: Node = (load("res://assets/export/%s.glb" % id) as PackedScene).instantiate()
		var names := {}
		var mats := {}
		var tris := 0
		for mi in _meshes(root):
			names[String(mi.name)] = true
			for s in mi.mesh.get_surface_count():
				tris += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
				var m := mi.get_active_material(s)
				if m:
					mats[m.resource_name] = true
		check(tris <= int(row[0]), "%s draws %d triangles, at most %d" % [id, tris, row[0]])
		for n: String in row[1]:
			check(names.has(n), "%s has its %s node" % [id, n])
		for m: String in row[2]:
			check(mats.has(m), "%s wears %s" % [id, m])
		root.free()


func test_sample_cell_keeps_its_ripeness_and_stretch_blend_shapes() -> void:
	var root: Node = (load("res://assets/export/sample_cell.glb") as PackedScene).instantiate()
	var shapes := {}
	for mi in _meshes(root):
		if mi.name == "Body" and mi.mesh is ArrayMesh:
			for i in (mi.mesh as ArrayMesh).get_blend_shape_count():
				shapes[String((mi.mesh as ArrayMesh).get_blend_shape_name(i))] = true
	check(shapes.has("Ripeness") and shapes.has("Stretch"), "Body has Ripeness and Stretch, found %s" % [shapes.keys()])
	root.free()


func test_sprites_are_all_there_at_their_sizes_and_clear_of_reserved_hues() -> void:
	for prefix: String in SPRITES:
		var row: Array = SPRITES[prefix]
		var files := _files(prefix)
		check_eq(files.size(), int(row[0]), "%s* textures" % prefix)
		for f in files:
			var tex: Texture2D = load(AMBIENCE + f)
			check(tex != null, "%s loads" % f)
			if tex == null:
				continue
			var size: Vector2i = row[1]
			if size.x > 0:
				check_eq(Vector2i(tex.get_width(), tex.get_height()), size, "%s size" % f)
			var img := tex.get_image()
			if img.is_compressed():
				img.decompress()
			# Texel by texel: the ghost layer draws far giants from the backdrops with its own fog and
			# brightness, so no single texel may sit near the food or threat hue.
			var step := maxi(1, img.get_width() / 128)
			var worst := 180.0
			for y in range(0, img.get_height(), step):
				for x in range(0, img.get_width(), step):
					var c := img.get_pixel(x, y)
					if c.a > 0.1:
						worst = minf(worst, _reserved_gap(Color(c.r, c.g, c.b)))
			check(worst >= MIN_LAB_HUE_GAP_DEG, "%s keeps %.0f degrees of LAB hue from food and threat" % [f, worst])


func test_material_overrides_load_and_stay_clear_of_reserved_hues() -> void:
	for path in OVERRIDES:
		var m := load(path) as BaseMaterial3D
		check(m != null, "%s loads as a material" % path)
		if m:
			var gap := _reserved_gap(m.albedo_color)
			check(gap >= MIN_LAB_HUE_GAP_DEG, "%s albedo keeps %.0f degrees of LAB hue from food and threat" % [path, gap])


## S3 pieces that lie wholly below the swim plane (s3-view A3V-2, A3V-3): albedo luminance at most
## 0.40, so the engine draws them as authored, and the cradle ring at the old pool's band-1 radius.
func test_below_plane_s3_pieces_stay_dim_and_the_cradle_is_full_size() -> void:
	for id in ["cradle_ring", "home_beacon"]:
		var root: Node = (load("res://assets/export/%s.glb" % id) as PackedScene).instantiate()
		for mi in _meshes(root):
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
				if m:
					var luma := m.albedo_color.srgb_to_linear().get_luminance()
					check(luma <= 0.40, "%s %s albedo luminance %.2f, at most 0.40" % [id, m.resource_name, luma])
		root.free()
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/records/cradle_ring.json"))
	check_near(float(record.get("radius_bu", 0.0)), 14.0625, 1e-4, "cradle_ring radius_bu")
	check_near(float(record.get("top_bu", 0.0)), -1.6, 1e-4, "cradle_ring top_bu")
