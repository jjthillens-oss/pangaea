extends RefCounted
## Loads the art team's part meshes (assets/export/cpart_<type>.glb in the main project) and the creature skin shader
## at runtime, since this prototype is its own Godot project and cannot import files outside its folder. Not domain
## code: it reads files. Each part scene is built once and duplicated per placement.

const ASSETS := "../../assets/export"

static var _scenes := {}
static var _skin_shader: Shader


static func asset_path(file: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(ASSETS).path_join(file).simplify_path()


## A new instance of a part type's scene, or null if its GLB is missing.
static func instance(type: String) -> Node3D:
	if not _scenes.has(type):
		var path := asset_path("cpart_%s.glb" % type)
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		_scenes[type] = doc.generate_scene(state) if doc.append_from_file(path, state) == OK else null
	var scene = _scenes[type]
	return scene.duplicate() if scene else null


## Sets handle k (0-based, per mille) on every mesh in the part that has a shape key named "H<k+1>_...".
static func set_handles(part: Node, handles: Array) -> void:
	for mi in part.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in mesh.get_blend_shape_count():
			var key := String(mesh.get_blend_shape_name(s))
			for k in handles.size():
				if key.begins_with("H%d_" % (k + 1)):
					(mi as MeshInstance3D).set_blend_shape_value(s, float(handles[k]) / 1000.0)


## The art team's creature skin shader (assets/export/shaders/creature_skin.gdshader), or null if missing.
static func skin_shader() -> Shader:
	if _skin_shader == null:
		var path := asset_path("shaders/creature_skin.gdshader")
		if FileAccess.file_exists(path):
			_skin_shader = Shader.new()
			_skin_shader.code = FileAccess.get_file_as_string(path)
	return _skin_shader


## Frees the cached scenes and shader (call when the viewer exits, so nothing is reported as leaked).
static func clear() -> void:
	for scene in _scenes.values():
		if scene:
			scene.free()
	_scenes.clear()
	_skin_shader = null
