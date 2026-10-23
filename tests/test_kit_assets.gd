extends TestCase
## The endless world's band-0 placement kit (game/data/placement_kit.json) and its pieces, against
## the art contract of docs/s1/s1-interfaces.md sections 4.4 and 5 (project files). The kit is
## written by tools/blender/make_s1_kit.py from the asset records; this checks the data rules the
## seed relies on and every GLB's footprint, swim band, height, colour and nodes.

const KIT_PATH := "res://game/data/placement_kit.json"
const CLASSES := {"fp_s": [0.6, 0.9], "fp_m": [0.9, 1.2], "fp_l": [1.2, 1.5]}
const KINDS := ["shell", "landmark", "rare", "marker"]
const KEYS := {
	"shell": ["footprint_class", "footprint_radius_m", "pickable"],
	"landmark": ["group", "footprint_radius_m"],
	"rare": ["rare_kind", "colliders"],
	"marker": [],
}
const COMMON_KEYS := ["id", "kind", "band", "glb", "record", "scale", "yaw_rule", "dressings", "placeholder", "approved"]
const YAW_RULES := {"shell": ["free", "slot"], "landmark": ["free", "steps_90"], "rare": ["fixed"], "marker": ["fixed"]}
const BUDGETS := {"shell": 1300, "landmark": 6000, "rare": 12000, "marker": 800}
const LAIR_ID := "marker_lair_mouth"
const LAIR_NODE := "LairMouth"
const LAIR_INNER := 1.3
const LAIR_OUTER := 2.6
const LAIR_FLOOR := -1.2
const MAX_COLLIDER_R := 4.0
const HOME_ROCKS := ["rock_a", "rock_b", "rock_c"]
const BAND_HEIGHTS: Array[float] = [-0.45, -0.3375, -0.225, -0.1125, 0.0, 0.1125, 0.225, 0.3375, 0.45]
const OUTLINE := Vector2(0.85, 1.15)
const ANCHOR_R := 3.0
const TOP_MAX := 4.0
const APRON_Y := -0.6
## LAB hues of the food glow and the threat pink; no surface comes within this many degrees.
const FOOD_HUE := 114.0
const THREAT_HUE := 11.0
const HUE_GAP := 25.0


func _kit() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT_PATH))
	return data if data is Dictionary else {}


func _record(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


func _pascal(id: String) -> String:
	var out := ""
	for part in id.split("_"):
		out += part.capitalize().replace(" ", "")
	return out


## Every mesh's vertices and triangles in the scene root's space.
func _geometry(root: Node3D) -> Array:
	var verts := PackedVector3Array()
	var tris := PackedInt32Array()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var t := Transform3D.IDENTITY
			var walk: Node = n
			while walk != root and walk is Node3D:
				t = (walk as Node3D).transform * t
				walk = walk.get_parent()
			var mesh := (n as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				var base := verts.size()
				for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
					verts.append(t * v)
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				for i in idx:
					tris.append(base + i)
	return [verts, tris]


## The farthest reach of any horizontal section at `heights`, per 1-degree azimuth bin (Godot x, z).
func _outline(verts: PackedVector3Array, tris: PackedInt32Array, heights: Array[float]) -> PackedFloat32Array:
	var best := PackedFloat32Array()
	best.resize(360)
	for k in range(0, tris.size() - 2, 3):
		var tri := [verts[tris[k]], verts[tris[k + 1]], verts[tris[k + 2]]]
		for h in heights:
			var cut: Array[Vector2] = []
			for e in 3:
				var a: Vector3 = tri[e]
				var b: Vector3 = tri[(e + 1) % 3]
				if (a.y - h) * (b.y - h) <= 0.0 and a.y != b.y:
					var c := a.lerp(b, (h - a.y) / (b.y - a.y))
					cut.append(Vector2(c.x, -c.z))
			if cut.size() < 2:
				continue
			var steps := int(rad_to_deg(absf(cut[0].angle_to(cut[1]))) * 4.0) + 1
			for j in steps + 1:
				var c := cut[0].lerp(cut[1], float(j) / steps)
				var bin := int(fposmod(rad_to_deg(c.angle()), 360.0)) % 360
				best[bin] = maxf(best[bin], c.length())
	return best


## Far side of the collider union along a ray at `deg` (Blender x, y = Godot x, -z).
func _far(colliders: Array, deg: float) -> float:
	var d := Vector2.from_angle(deg_to_rad(deg))
	var far := 0.0
	for c: Dictionary in colliders:
		var centre := Vector2(c.center[0], c.center[1])
		var b := d.dot(centre)
		var disc := b * b - (centre.length_squared() - float(c.radius) * float(c.radius))
		if disc >= 0.0:
			far = maxf(far, b + sqrt(disc))
	return far


func _lab_hue(c: Color) -> float:
	var l := c.srgb_to_linear()
	var f := func(t: float) -> float: return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
	var x := (0.4124 * l.r + 0.3576 * l.g + 0.1805 * l.b) / 0.95047
	var y := 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b
	var z := (0.0193 * l.r + 0.1192 * l.g + 0.9505 * l.b) / 1.08883
	return fposmod(rad_to_deg(atan2(200.0 * (f.call(y) - f.call(z)), 500.0 * (f.call(x) - f.call(y)))), 360.0)


func _hue_gap(a: float, b: float) -> float:
	return absf(fposmod(a - b + 180.0, 360.0) - 180.0)


func test_the_kit_follows_the_placement_rules() -> void:
	var kit := _kit()
	check(not kit.is_empty(), "the kit parses")
	check_eq(kit.get("footprint_classes"), CLASSES, "footprint classes")
	var ids := {}
	var groups := [0, 0, 0, 0]
	var rare_kinds := {}
	var id_re := RegEx.create_from_string("^[a-z][a-z0-9_]{2,40}$")
	var tint_re := RegEx.create_from_string("^#[0-9A-F]{6}$")
	var growth_re := RegEx.create_from_string("^Growth_[A-Za-z]+$")
	for a: Dictionary in kit.assets:
		var id: String = a.id
		check(id_re.search(id) != null and not ids.has(id), "%s: id is valid and unique" % id)
		ids[id] = a
		check(a.kind in KINDS, "%s: kind" % id)
		var keys: Array = COMMON_KEYS + KEYS.get(a.kind, [])
		check_eq(a.keys().size(), keys.size(), "%s: exact key set" % id)
		for k in keys:
			check(a.has(k), "%s has %s" % [id, k])
		check_eq(int(a.band), -1 if a.kind == "marker" else 0, "%s: band" % id)
		var lo: float = a.scale[0]
		var hi: float = a.scale[1]
		check(lo >= 0.5 and lo <= hi and hi <= 2.0 and hi / lo <= 2.0, "%s: scale %s" % [id, a.scale])
		check(a.yaw_rule in YAW_RULES[a.kind], "%s: yaw rule %s" % [id, a.yaw_rule])
		var dressing_ids := {}
		for d: Dictionary in a.dressings:
			check(not dressing_ids.has(d.id), "%s: dressing ids unique" % id)
			dressing_ids[d.id] = true
			check(tint_re.search(d.tint) != null, "%s: tint %s" % [id, d.tint])
			check(d.growth == "" or growth_re.search(d.growth) != null, "%s: growth %s" % [id, d.growth])
		check(ResourceLoader.exists(a.glb) and FileAccess.file_exists(a.record), "%s: glb and record exist" % id)
		var rec := _record(a.record)
		check_eq(rec.get("id"), id, "%s: record id" % id)
		check_eq("res://" + String(rec.get("export_path", "")), a.glb, "%s: record export path" % id)
		check_eq(a.placeholder, String(rec.get("review_state", "")).begins_with("blockout"), "%s: placeholder matches the review state" % id)
		if a.approved:
			check(not a.placeholder and rec.get("status") == "APPROVED", "%s: approved only when finished and approved" % id)
		match a.kind:
			"shell":
				var fr: float = a.footprint_radius_m
				check_near(fr, float(rec.get("footprint_radius_m", -1.0)), 1e-6, "%s: record footprint" % id)
				var cls: Array = CLASSES[a.footprint_class]
				check(fr > 0.0 and cls[0] / fr >= lo - 1e-6 and cls[1] / fr <= hi + 1e-6, "%s covers its class %s" % [id, a.footprint_class])
			"landmark":
				check_eq(float(a.footprint_radius_m), float(kit.landmark.collide_radius_bu), "%s: footprint is the collider" % id)
				check(lo >= 0.9 and hi <= 1.1, "%s: landmark scale within 0.9 to 1.1" % id)
				check(int(a.group) >= 0 and int(a.group) < 4, "%s: group" % id)
				groups[int(a.group)] += 1
				check_eq(a.dressings.size(), 3, "%s: three dressings" % id)
				for d: Dictionary in a.dressings:
					check(d.scale >= lo and d.scale <= hi, "%s: dressing %s scale inside the range" % [id, d.id])
			"rare":
				check(not rare_kinds.has(a.rare_kind), "%s: rare kind unique" % id)
				rare_kinds[a.rare_kind] = true
				check(lo == 1.0 and hi == 1.0, "%s: rare scale is 1" % id)
				for c: Dictionary in a.colliders:
					check(c.radius >= 0.6 and c.radius <= MAX_COLLIDER_R, "%s: collider radius %s" % [id, c.radius])
			"marker":
				check(lo == 1.0 and hi == 1.0, "%s: marker scale is 1" % id)
	check_eq(groups, kit.landmark.groups.map(func(g): return int(g)), "landmark group sizes")
	for marker in ["marker_checkpoint_column", "marker_origin_arrow"]:
		check(ids.has(marker), "%s is in the kit" % marker)
	for rock in HOME_ROCKS:
		check(ids.has(rock) and ids[rock].kind == "shell" and not ids[rock].pickable and float(ids[rock].footprint_radius_m) == 1.0
			and ids[rock].scale == [0.8, 1.5], "%s is a home-block shell, not pickable" % rock)
	# Coverage: every radius in every class fits at least two pickable shells.
	for cls: String in CLASSES:
		var bounds: Array = CLASSES[cls]
		for step in 13:
			var r: float = lerpf(bounds[0], bounds[1], step / 12.0)
			if step == 12 and cls != "fp_l":
				r -= 1e-4
			var fits := 0
			for a: Dictionary in kit.assets:
				if a.kind == "shell" and a.pickable:
					var s: float = r / float(a.footprint_radius_m)
					if s >= a.scale[0] - 1e-6 and s <= a.scale[1] + 1e-6:
						fits += 1
			check(fits >= 2, "%s radius %.3f fits %d pickable shells" % [cls, r, fits])


func test_every_kit_piece_meets_the_art_contract() -> void:
	var kit := _kit()
	for a: Dictionary in kit.assets:
		if a.id in HOME_ROCKS:
			continue  # the M1 rocks keep test_assets' rock contract
		var id: String = a.id
		var rec := _record(a.record)
		var scene: Node3D = (load(a.glb) as PackedScene).instantiate()
		var root_name := LAIR_NODE if id == LAIR_ID else _pascal(id)
		check(scene.find_child(root_name, true, false) != null, "%s: root mesh %s" % [id, root_name])
		for d: Dictionary in a.dressings:
			if d.growth != "":
				check(scene.find_child(d.growth, true, false) != null, "%s: growth node %s" % [id, d.growth])
		var tris_budget: int = BUDGETS[a.kind]
		check(int(rec.triangles) <= tris_budget, "%s: %d triangles, budget %d" % [id, rec.triangles, tris_budget])
		var geo := _geometry(scene)
		var verts: PackedVector3Array = geo[0]
		var tris: PackedInt32Array = geo[1]
		var box := AABB(verts[0], Vector3.ZERO)
		for v in verts:
			box = box.expand(v)
		var top := box.end.y
		var hi: float = a.scale[1]
		var lo: float = a.scale[0]
		if a.kind != "marker":
			check(absf(box.get_center().x) <= 0.15 and absf(box.get_center().z) <= 0.15, "%s: bounds centred on the pivot" % id)
		var outline := _outline(verts, tris, BAND_HEIGHTS)
		match a.kind:
			"shell":
				var fr: float = a.footprint_radius_m
				for o in outline:
					check(o >= OUTLINE.x * fr - 1e-3 and o <= OUTLINE.y * fr + 1e-3, "%s: band outline %.3f for footprint %.2f" % [id, o, fr])
				check(top <= 0.6 + 1e-3 and box.position.y <= -1.5, "%s: top %.2f, base %.2f" % [id, top, box.position.y])
			"landmark":
				var cr: float = kit.landmark.collide_radius_bu
				for o in outline:
					check(o * lo >= OUTLINE.x * cr - 1e-3 and o * hi <= OUTLINE.y * cr + 1e-3, "%s: band outline %.3f at scales %.2f-%.2f" % [id, o, lo, hi])
				check(top * hi <= TOP_MAX + 1e-3, "%s: top %.2f at the top scale" % [id, top * hi])
				for v in verts:
					var r := Vector2(v.x, v.z).length() * hi
					check(r <= ANCHOR_R + 1e-3, "%s: inside the anchor (%.2f)" % [id, r])
					check(v.y * hi < APRON_Y or r <= OUTLINE.y * cr + 1e-3, "%s: no overhang at r %.2f, y %.2f" % [id, r, v.y * hi])
			"rare":
				for i in 360:
					var e_lo := INF
					var e_hi := 0.0
					for k in 5:
						var e := _far(a.colliders, i + k / 4.0)
						e_lo = minf(e_lo, e)
						e_hi = maxf(e_hi, e)
					check(outline[i] <= OUTLINE.y * e_hi + 1e-3 and outline[i] >= OUTLINE.x * e_lo - 1e-3,
						"%s: band outline %.2f at %d degrees, collider edge %.2f-%.2f" % [id, outline[i], i, e_lo, e_hi])
				check(top <= TOP_MAX + 1e-3, "%s: top %.2f" % [id, top])
				for v in verts:
					if v.y > 0.6:
						var inside := false
						for c: Dictionary in a.colliders:
							inside = inside or Vector2(v.x, -v.z).distance_to(Vector2(c.center[0], c.center[1])) <= OUTLINE.y * float(c.radius) + 1e-3
						check(inside, "%s: geometry above the plane stays over its colliders" % id)
			"marker":
				if id == "marker_checkpoint_column":
					check(box.size.x <= 0.5 + 1e-3 and box.size.z <= 0.5 + 1e-3, "%s: at most 0.5 wide" % id)
				elif id == LAIR_ID:
					# docs/s2/lurker-lair-mouth-spec.md: authored at the Lurker's radius R = 1, origin at the ring's
					# centre on the lip top, everything below it, the hollow's floor at -1.2, outer radius about 2.6,
					# and the horseshoe open toward +X (the lunge), so nothing stands in the opening near the lip.
					check(box.end.y <= 1e-3, "%s: all geometry at or below the lip top, got %.3f" % [id, box.end.y])
					check(box.position.y >= LAIR_FLOOR - 0.1, "%s: floor at about %.1f, got %.3f" % [id, LAIR_FLOOR, box.position.y])
					var reach := 0.0
					for v in verts:
						reach = maxf(reach, Vector2(v.x, v.z).length())
						if v.x > 0.0 and absf(atan2(-v.z, v.x)) < deg_to_rad(40.0):
							check(v.y < -0.5 or Vector2(v.x, v.z).length() < LAIR_INNER + 0.05, "%s: the opening toward +X is clear" % id)
					check(reach <= LAIR_OUTER * 1.15, "%s: outer radius about %.1f, got %.2f" % [id, LAIR_OUTER, reach])
				else:
					check(box.size.y <= 0.1 and maxf(box.size.x, box.size.z) <= 1.5, "%s: flat and at most 1.5 long" % id)
		# No surface near the food or threat hue.
		var stack: Array[Node] = [scene]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			if n is MeshInstance3D:
				var mesh := (n as MeshInstance3D).mesh
				for s in mesh.get_surface_count():
					var mat := mesh.surface_get_material(s) as BaseMaterial3D
					if mat != null and mat.albedo_color.s > 0.05:
						var h := _lab_hue(mat.albedo_color)
						check(_hue_gap(h, FOOD_HUE) >= HUE_GAP and _hue_gap(h, THREAT_HUE) >= HUE_GAP, "%s: %s hue %.0f" % [id, mat.resource_name, h])
		scene.free()


## CIE L* of an sRGB colour.
func _lstar(c: Color) -> float:
	var y := c.srgb_to_linear().get_luminance()
	return 116.0 * pow(y, 1.0 / 3.0) - 16.0 if y > 0.008856 else 903.3 * y


## The wayfinding markers read as soft light, never as glaring white (S1 integration pass): the
## column is an additive, unlit, fog-free cream shaft about 6 m tall that fades at both ends and peaks
## near L* 80; the arrow is unlit cream at about L* 85.
func test_markers_are_soft_cream_light_not_white() -> void:
	var column: Node = (load("res://assets/export/marker_checkpoint_column.glb") as PackedScene).instantiate()
	var box := AABB()
	var shader_mat: ShaderMaterial = null
	var stack: Array[Node] = [column]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D:
			var mesh := (n as MeshInstance3D).mesh
			box = mesh.get_aabb()
			shader_mat = mesh.surface_get_material(0) as ShaderMaterial
	check_near(box.size.y, 6.0, 0.05, "column is about 6 m tall")
	check(box.position.y < -1.0 and box.end.y > 4.0, "column runs from below the plane to well above it")
	check(shader_mat != null, "column draws with M_CheckpointColumn.tres")
	if shader_mat:
		var code := shader_mat.shader.code
		for mode in ["unshaded", "blend_add", "fog_disabled", "depth_draw_never"]:
			check(code.contains(mode), "column shader is %s" % mode)
		var tint: Color = shader_mat.get_shader_parameter("tint")
		check(_lstar(tint) >= 75.0 and _lstar(tint) <= 85.0, "column peak L* %.1f is about 80" % _lstar(tint))
		var h := _lab_hue(tint)
		check(_hue_gap(h, FOOD_HUE) >= HUE_GAP and _hue_gap(h, THREAT_HUE) >= HUE_GAP, "column tint hue %.0f is clear of food and threat" % h)
	column.free()
	var arrow: Node = (load("res://assets/export/marker_origin_arrow.glb") as PackedScene).instantiate()
	stack = [arrow]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D:
			var mat := (n as MeshInstance3D).mesh.surface_get_material(0) as BaseMaterial3D
			check(mat != null and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "arrow is drawn unlit")
			if mat:
				check(_lstar(mat.albedo_color) <= 93.0, "arrow tint L* %.1f keeps its brightest texels near 85, not white" % _lstar(mat.albedo_color))
	arrow.free()
