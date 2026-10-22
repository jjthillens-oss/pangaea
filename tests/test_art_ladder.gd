extends TestCase
## Technical-artist checks for the quality-ladder demo (docs/art/quality_ladder.md): each rung
## loads at its recorded size, keeps the sample cell's socket contract and stays in budget, and
## the target rung arrives with its skeleton and named, correctly looping clips.

const RUNGS := ["0_blockout", "1_form", "2_surfaced", "3_target"]
const SOCKETS := ["socket_mouth", "socket_tail", "socket_top", "socket_side_L", "socket_side_R"]
## Bible section 16 proposal for ordinary creatures (upper bound) and microscopic texture size.
const MAX_TRIANGLES := 15000
const MAX_TEXTURE_PX := 512


func _record(rung: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://assets/records/cell_ladder_%s.json" % rung))


func _load(rung: String) -> Node3D:
	var packed: PackedScene = load("res://assets/export/cell_ladder_%s.glb" % rung)
	return packed.instantiate() if packed else null


func _global(node: Node3D, root: Node3D) -> Vector3:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != root and n is Node3D:
		if n is BoneAttachment3D:
			# Outside a tree the attachment has not copied its bone pose yet; use the rest pose.
			var att := n as BoneAttachment3D
			var skel: Skeleton3D = att.get_parent()
			t = skel.get_bone_global_rest(skel.find_bone(att.bone_name)) * t
			n = skel
			continue
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t.origin


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n)
	return out


func test_every_rung_has_record_and_loads() -> void:
	for rung in RUNGS:
		var record := _record(rung)
		check(record.get("ladder_rung") == rung, "%s record names its rung" % rung)
		check(record.get("status") == "PROPOSED", "%s stays a PROPOSED reference asset, not production" % rung)
		var node := _load(rung)
		check(node != null, "%s loads" % rung)
		if node:
			node.free()


func test_rungs_keep_socket_contract_and_face_forward() -> void:
	for rung in RUNGS:
		var node := _load(rung)
		if node == null:
			check(false, "%s loads" % rung)
			continue
		for socket in SOCKETS:
			check(node.find_child(socket, true, false) != null, "%s has %s" % [rung, socket])
		var mouth: Node3D = node.find_child("socket_mouth", true, false)
		var top: Node3D = node.find_child("socket_top", true, false)
		if mouth and top:
			var m := _global(mouth, node)
			check(m.z < -0.3 and absf(m.x) < 0.01, "%s mouth faces Godot forward (-Z), got %s" % [rung, m])
			check(_global(top, node).y > 0.3, "%s top socket points up" % rung)
		node.free()


func test_rungs_stay_in_budget() -> void:
	for rung in RUNGS:
		var record := _record(rung)
		check(int(record.triangles) <= MAX_TRIANGLES, "%s: %d triangles within %d" % [rung, record.triangles, MAX_TRIANGLES])
		for tex in record.get("textures", []):
			check(tex.size[0] <= MAX_TEXTURE_PX and tex.size[1] <= MAX_TEXTURE_PX, "%s: %s within %d px" % [rung, tex.name, MAX_TEXTURE_PX])
		var node := _load(rung)
		if node == null:
			continue
		var tris := 0
		for mi in _meshes(node):
			for s in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(s)
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				tris += idx.size() / 3 if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		# Blender's count is of the evaluated mesh; the export should match it closely.
		check(absi(tris - int(record.triangles)) <= int(record.triangles) / 20, "%s: Godot sees %d triangles, record says %d" % [rung, tris, record.triangles])
		node.free()


func test_surfaced_rungs_have_textured_membrane() -> void:
	for rung in ["2_surfaced", "3_target"]:
		var node := _load(rung)
		if node == null:
			continue
		var found := false
		for mi in _meshes(node):
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s) as BaseMaterial3D
				if mat and mat.resource_name == "M_CellMembrane":
					found = true
					check(mat.albedo_texture != null, "%s membrane has an albedo texture" % rung)
					check(mat.roughness_texture != null, "%s membrane has a roughness texture" % rung)
		check(found, "%s has the M_CellMembrane material" % rung)
		node.free()


func test_target_has_rig_and_clips() -> void:
	var record := _record("3_target")
	check(record.get("rig_family") == "cell_single_body", "target uses the M1 single-body cell rig family")
	var node := _load("3_target")
	if node == null:
		check(false, "target loads")
		return
	var skel: Skeleton3D = node.find_children("*", "Skeleton3D", true, false).front() if node.find_children("*", "Skeleton3D", true, false).size() > 0 else null
	check(skel != null, "target has a Skeleton3D")
	if skel:
		for bone in ["root", "body", "mouth", "tail_01", "tail_05", "eye_L", "lid_upper_R"]:
			check(skel.find_bone(bone) >= 0, "skeleton has %s" % bone)
	var players := node.find_children("*", "AnimationPlayer", true, false)
	check(players.size() == 1, "target has one AnimationPlayer")
	if players.size() == 1:
		var player: AnimationPlayer = players[0]
		for clip in record.animations:
			check(player.has_animation(clip.name), "has clip %s" % clip.name)
			if player.has_animation(clip.name):
				var anim := player.get_animation(clip.name)
				var want := Animation.LOOP_LINEAR if clip.loop else Animation.LOOP_NONE
				check(anim.loop_mode == want, "%s loop mode" % clip.name)
				check_near(anim.length, float(clip.frames) / float(clip.fps), 0.05, "%s length in seconds" % clip.name)
	node.free()
