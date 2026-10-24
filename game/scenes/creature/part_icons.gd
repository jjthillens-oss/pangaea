extends Node
## Pictures of the art team's part meshes for the creature editor's palette (owner playtest, 2026-10-24: "you can't
## tell, it just lists the items"). Each part type's scene (PartLibrary) is rendered once in a small transparent
## SubViewport of its own world, framed on its bounds from a three-quarter view, and handed out as an ImageTexture
## through icon_ready. Nothing is written to disk, so a part art changes shows on the next launch. A headless run
## (tests, smokes) renders nothing and the palette keeps its text.

signal icon_ready(type: String, texture: Texture2D)

const PartLibrary := preload("res://game/scenes/creature/part_library.gd")
const ICON_PX := 64
## The view: yaw and pitch (rad) round the part, and its bounds' radius times this as the distance.
const VIEW_YAW := 0.75
const VIEW_PITCH := 0.45
const VIEW_DISTANCE := 2.6

## type -> Texture2D, kept for the whole run so the editor's next visit needs no rendering.
static var icons := {}
var _viewport: SubViewport
var _camera: Camera3D
var _stage: Node3D


## Renders an icon for each type in `types`, one per two frames, emitting icon_ready as each is done. Types already
## rendered are handed out again at once.
func render(types: Array) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_ensure_viewport()
	for type in types:
		if icons.has(type):
			icon_ready.emit(type, icons[type])
			continue
		var node := PartLibrary.instance(String(type))
		if node == null:
			continue
		_stage.add_child(node)
		_frame(node)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			return
		var image := _viewport.get_texture().get_image()
		node.queue_free()
		if image == null or image.is_empty():
			continue
		var tex := ImageTexture.create_from_image(image)
		icons[type] = tex
		icon_ready.emit(type, tex)


func _ensure_viewport() -> void:
	if _viewport != null:
		return
	_viewport = SubViewport.new()
	_viewport.name = "PartIconViewport"
	_viewport.size = Vector2i(ICON_PX, ICON_PX)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.environment.ambient_light_energy = 0.6
	_viewport.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.8, 0.6, 0.0)
	key.light_energy = 1.3
	_viewport.add_child(key)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_viewport.add_child(_camera)


## Points the camera at the part's bounds (all its meshes) from the icon view.
func _frame(node: Node3D) -> void:
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b: AABB = (node.global_transform.affine_inverse() * m.global_transform) * m.mesh.get_aabb() \
				if m.is_inside_tree() else m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var centre := box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.01)
	var dir := Vector3(sin(VIEW_YAW) * cos(VIEW_PITCH), sin(VIEW_PITCH), cos(VIEW_YAW) * cos(VIEW_PITCH))
	var eye := centre + dir * radius * VIEW_DISTANCE
	_camera.near = radius * 0.05
	_camera.far = radius * 10.0
	_camera.transform = Transform3D(Basis.looking_at(centre - eye, Vector3.UP), eye)
