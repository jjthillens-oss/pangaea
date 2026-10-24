class_name PartIcon
extends SubViewport
## A palette icon for the cell editor (S4.4): one part model, drawn once in its own little world
## from a three-quarter view, on a clear background. Its texture goes on the palette button.
## The model is the one the pool draws (PlayerCellView.PART_SCENES), so a new part mesh from art
## shows up in the palette with no change here.

const PX := 96
## The camera looks down and from the side at the part, which points along -Z from its origin.
const VIEW_DIR := Vector3(0.75, 0.6, -0.35)
## Room round the part, as a share of its largest size.
const MARGIN := 1.25

var type_id := ""


func _init(p_type_id: String = "") -> void:
	type_id = p_type_id
	name = "Icon_" + type_id
	size = Vector2i(PX, PX)
	transparent_bg = true
	own_world_3d = true
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.65, 0.8)
	environment.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var light := DirectionalLight3D.new()
	light.transform = Transform3D(Basis.looking_at(Vector3(-0.4, -1.0, -0.6)), Vector3.ZERO)
	add_child(light)
	var model := Node3D.new()
	model.name = "Model"
	add_child(model)
	var packed: PackedScene = PlayerCellView.PART_SCENES.get(type_id)
	if packed != null:
		model.add_child(packed.instantiate())
	var bounds := bounds_of(model)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(bounds.size[bounds.get_longest_axis_index()], 0.05) * MARGIN
	var centre := bounds.get_center()
	camera.transform = Transform3D(Basis.looking_at(-VIEW_DIR), centre + VIEW_DIR.normalized() * 4.0)
	camera.far = 10.0
	add_child(camera)


func _ready() -> void:
	render_target_update_mode = SubViewport.UPDATE_ONCE   # the part does not move: draw it once


## True when the part has a model to draw.
func has_model() -> bool:
	return get_node("Model").get_child_count() > 0


## The box round every mesh under `root`, in root's frame (an empty box at the origin for none).
static func bounds_of(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in root.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		var to_root := Transform3D.IDENTITY
		var n: Node = visual
		while n != root and n is Node3D:
			to_root = (n as Node3D).transform * to_root
			n = n.get_parent()
		var box := to_root * visual.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out
