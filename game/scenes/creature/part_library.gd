extends RefCounted
## Loads the art team's part meshes (assets/export/cpart_<type>.glb, imported scenes) and the creature skin shader
## (assets/export/shaders/creature_skin.gdshader). Not domain code: it reads resources. Each part scene is loaded once
## and instantiated per placement. Ported from the creature lab, which read the same files from outside its project.

const ASSETS := "res://assets/export"

static var _scenes := {}
static var _skin_shader: Shader


static func asset_path(file: String) -> String:
	return ASSETS.path_join(file)


## A new instance of a part type's scene, or null if its GLB is missing.
static func instance(type: String) -> Node3D:
	if not _scenes.has(type):
		var path := asset_path("cpart_%s.glb" % type)
		_scenes[type] = load(path) if ResourceLoader.exists(path) else null
	var scene: PackedScene = _scenes[type]
	return scene.instantiate() if scene else null


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


## The art team's creature skin shader, or null if missing.
static func skin_shader() -> Shader:
	if _skin_shader == null:
		var path := asset_path("shaders/creature_skin.gdshader")
		if ResourceLoader.exists(path):
			_skin_shader = load(path)
	return _skin_shader


## Drops the cached scenes and shader (the lab freed generated scenes; imported scenes are shared resources).
static func clear() -> void:
	_scenes.clear()
	_skin_shader = null
