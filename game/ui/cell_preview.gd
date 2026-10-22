class_name CellPreview
extends SubViewportContainer
## A 3D view of one genome for menus (M1 step 2): the body picker's shared preview and the
## Continue card. It draws the same PlayerCellView the pool uses, in its own small world with its
## own light, so the menu shows exactly the parts the player will swim with. The cell sways
## gently between three-quarter views of its front, so both sides show without a full spin.

const CAMERA_POSITION := Vector3(0.0, 2.3, 3.3)
const CAMERA_TARGET := Vector3(0.0, -0.05, 0.0)
## The cell sits this far forward on the turntable, so the sway turns about the middle of the
## body plus its tail instead of the body's center.
const CENTER_OFFSET_M := 0.2
const FACING_YAW := -PI * 0.75     ## the front toward the camera's right
const SWAY_RAD := 0.75
const SWAY_HZ := 0.07

var _t := 0.0

@onready var _camera: Camera3D = %Camera
@onready var _turntable: Node3D = %Turntable
@onready var _cell: PlayerCellView = %Cell


func _ready() -> void:
	_camera.transform = Transform3D(Basis.looking_at(CAMERA_TARGET - CAMERA_POSITION, Vector3.UP), CAMERA_POSITION)
	_cell.position = Vector3(0.0, 0.0, -CENTER_OFFSET_M)
	_turntable.rotation.y = FACING_YAW


## Shows a genome's body and parts.
func show_genome(genome: Genome, phenotype: Phenotype) -> void:
	_cell.build(genome, phenotype)
	_t = 0.0


## The parts drawn now, in genome order (PlayerCellView.part_nodes).
func part_nodes() -> Array[Node]:
	return _cell.part_nodes()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		_turntable.rotation.y = FACING_YAW + SWAY_RAD * sin(_t * TAU * SWAY_HZ)
