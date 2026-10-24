class_name TestPool
extends Control
## IB-03, the editor's test drive (S4.4; docs/s4/s4-plan.md): before mating, swim the working body
## round a small empty dish to feel its speed and turning, as Spore's editor lets you play the
## creature before you finish. It never touches the save, the sea or the session: the body is the
## editor's working copy, the dish has no food and nothing to meet, and Back (or Esc) returns to
## the editor as it was.

signal left

const RADIUS_M := 5.0          ## the dish's radius on the swim plane
const BODY_M := 0.6            ## the cell stops this far inside the wall
const FLOOR_Y := -0.6
## Above and behind the dish, aimed a little past its centre so the near rim stays on screen.
const CAMERA_POSITION := Vector3(0.0, 12.5, 6.0)
const CAMERA_TARGET := Vector3(0.0, FLOOR_Y, 0.8)
## Faint rings on the floor, so a swim shows against something.
const FLOOR_RINGS_M := [1.25, 2.5, 3.75]
const FLOOR_COLOR := Color(0.05, 0.14, 0.26)
const WALL_COLOR := Color(0.45, 0.75, 0.9, 0.55)

var phenotype: Phenotype
var motion := Locomotion.MotionState.new()

var _view: PlayerCellView
var _camera: Camera3D
var _speed: Label
var _back: Button
var _pointer_held := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)   # anchored out of the tree (see CellEditor._init)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


## Shows the dish with `genome`'s body at its centre, facing up the screen.
func start(genome: Genome, p_phenotype: Phenotype) -> void:
	phenotype = p_phenotype
	_view.build(genome, phenotype)
	motion.place(Vector2.ZERO, -PI / 2.0)
	_view.place(motion)
	_pointer_held = false
	visible = true
	if is_inside_tree():
		_back.grab_focus()


## One tick of swimming: `move` as the pool's swim keys give it (length is the throttle).
func step(move: Vector2, dt: float) -> void:
	Locomotion.steer(motion, move, phenotype, 1.0, dt)
	motion.prev_position = motion.position
	motion.position += motion.velocity * dt
	var room := RADIUS_M - BODY_M
	if motion.position.length() > room:
		# The dish wall: stop at it and keep only the speed along it.
		var out := motion.position.normalized()
		motion.position = out * room
		motion.velocity -= out * maxf(0.0, motion.velocity.dot(out))


func leave() -> void:
	visible = false
	_pointer_held = false
	left.emit()


func _physics_process(delta: float) -> void:
	if not visible or phenotype == null:
		return
	var keys := Input.get_vector(SwimInput.MOVE_ACTIONS[0], SwimInput.MOVE_ACTIONS[1],
		SwimInput.MOVE_ACTIONS[2], SwimInput.MOVE_ACTIONS[3])
	var pointer := Vector2.ZERO
	if _pointer_held and keys.is_zero_approx() and _camera.is_inside_tree():
		var m := _camera.get_viewport().get_mouse_position()
		var target: Variant = PlaneSpace.ray_to_plane(_camera.project_ray_origin(m), _camera.project_ray_normal(m))
		if target is Vector2:
			pointer = SwimInput.pointer_move(motion.position, target)
	step(SwimInput.combine(keys, pointer), delta)
	_view.show_motion(motion, 1.0)
	_speed.text = "Speed %.1f of %.1f" % [motion.velocity.length(), phenotype.speed]


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_pointer_held = button.pressed
		accept_event()


## Releases are watched before the GUI, so letting go over a button still stops the swim.
func _input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
		_pointer_held = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		leave()


func _build() -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.handle_input_locally = false
	container.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.05, 0.11)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.62, 0.8)
	environment.ambient_light_energy = 0.55
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.transform = Transform3D(Basis.looking_at(Vector3(-0.3, -1.0, -0.5)), Vector3.ZERO)
	viewport.add_child(light)
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = RADIUS_M
	floor_mesh.bottom_radius = RADIUS_M
	floor_mesh.height = 0.05
	floor_mesh.radial_segments = 96
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = FLOOR_COLOR
	floor_material.roughness = 0.9
	floor_mesh.material = floor_material
	var floor_node := MeshInstance3D.new()
	floor_node.name = "Floor"
	floor_node.mesh = floor_mesh
	floor_node.position = Vector3(0.0, FLOOR_Y, 0.0)
	viewport.add_child(floor_node)
	var wall := _ring(RADIUS_M, 0.1, WALL_COLOR)
	wall.name = "Wall"
	viewport.add_child(wall)
	for r: float in FLOOR_RINGS_M:
		viewport.add_child(_ring(r, 0.02, Color(WALL_COLOR, 0.12)))
	_view = (preload("res://game/scenes/pool/player_cell_view.tscn") as PackedScene).instantiate()
	viewport.add_child(_view)
	_camera = Camera3D.new()
	_camera.fov = 45.0
	_camera.transform = Transform3D(Basis.looking_at(CAMERA_TARGET - CAMERA_POSITION), CAMERA_POSITION)
	viewport.add_child(_camera)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	var title := Label.new()
	title.text = "Test drive"
	title.add_theme_font_size_override(&"font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var hint := Label.new()
	hint.text = "Swim with W A S D, or hold the left mouse button. Nothing here is saved."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.7)
	column.add_child(hint)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	var bottom := HBoxContainer.new()
	column.add_child(bottom)
	_speed = Label.new()
	_speed.name = "Speed"
	_speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_speed)
	_back = Button.new()
	_back.name = "BackToEditor"
	_back.text = "Back to the editor"
	_back.pressed.connect(leave)
	bottom.add_child(_back)


## A flat ring lying on the floor.
func _ring(radius: float, half_width: float, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - half_width
	mesh.outer_radius = radius + half_width
	mesh.rings = 96
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.scale = Vector3(1.0, 0.2, 1.0)
	node.position = Vector3(0.0, FLOOR_Y + 0.03, 0.0)
	return node
