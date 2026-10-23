class_name WorldMarkers
extends Node3D
## The endless sea's two way-markers (S1, docs/s1/s1-content.md 6.11): the cream column standing at
## the generation start (the checkpoint, where a death brings the lineage back), and, once the cell
## is more than ARROW_FROM_TM from where the lineage began, a flat arrow lying beside the cell and
## pointing there: abs (0, 0), the home block's centre (build plan Q9). Both are the kit's pieces
## with the kit's materials as shipped (build plan Q3). Pool mode shows neither.
##
## The node is world_rebuilt: update() places both from the sim every frame, so a rebase or a moved
## checkpoint needs nothing more. The HUD's world overlay reads column(), arrow_state() and
## arrow_tip() for its pip and its distance label.

const ARROW_FROM_TM := 40.0         ## the arrow shows beyond this distance from the origin (plan A.6)
const ARROW_RING_GAP := 1.2         ## the arrow sits this far outside the cell's radius
const ARROW_Y := 0.05
## The markers' cream, for the HUD's pip and label (C-9; Q3 keeps it apart from the UI cream #F4EAD2).
const MARKER_COLOR := Color("#F4E8DA")
const COLUMN_ID := "marker_checkpoint_column"
const ARROW_ID := "marker_origin_arrow"
## Where the lineage began, absolute am (S1: the home block's centre).
const ORIGIN_AM := [0.0, 0.0]

var _column: Node3D
var _arrow: Node3D
var _arrow_front := 0.0             ## how far the arrow's mesh reaches ahead of its origin (its -Z extent)
var _arrow_state := {"visible": false, "direction": Vector2.ZERO, "distance_tm": 0.0}


## Instances both marker pieces from `kit` in the endless sea; in the pool (no world, or no kit) the
## node stays empty and hidden.
func setup(sim: PoolSim, kit: PlacementKit) -> void:
	clear()
	visible = sim != null and sim.world != null and kit != null
	if not visible:
		return
	_column = _instance(kit, COLUMN_ID)
	_arrow = _instance(kit, ARROW_ID)
	_arrow_front = _front_of(_arrow)
	_arrow.visible = false


## Frees both pieces.
func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_column = null
	_arrow = null
	_arrow_state = {"visible": false, "direction": Vector2.ZERO, "distance_tm": 0.0}


## Places the column at the checkpoint and the arrow beside the cell drawn at `cell_at` (the pool's
## plane, as the cell view stands this frame), from the sim's float64 absolute positions.
func update(sim: PoolSim, cell_at: Vector2) -> void:
	if not visible or _column == null or sim == null or sim.world == null:
		return
	var cp := sim.world.checkpoint_am
	_column.position = PlaneSpace.to_world(sim.world.local_of_abs(cp[0], cp[1]))
	_arrow_state = origin_arrow(sim.absolute_position_am(), PackedFloat64Array(ORIGIN_AM))
	_arrow.visible = _arrow_state.visible and not sim.dead
	if _arrow.visible:
		var d: Vector2 = _arrow_state.direction
		_arrow.position = PlaneSpace.to_world(cell_at + d * (sim.phenotype.radius + ARROW_RING_GAP), ARROW_Y)
		_arrow.rotation = Vector3(0.0, PlaneSpace.yaw_for_heading(d.angle()), 0.0)


## The column piece (tests and the HUD overlay), or null in the pool.
func column() -> Node3D:
	return _column


## The arrow piece (tests), or null in the pool.
func arrow() -> Node3D:
	return _arrow


## The last update's origin_arrow result: {visible, direction, distance_tm}.
func arrow_state() -> Dictionary:
	return _arrow_state


## The arrow's tip in the pool's space, where the HUD puts its distance label.
func arrow_tip() -> Vector3:
	if _arrow == null:
		return Vector3.ZERO
	return _arrow.position + PlaneSpace.to_world(_arrow_state.direction) * _arrow_front


## Pure: whether the arrow shows for a cell at `cell_abs` (absolute am) and where it points, all
## from float64 differences: {visible: distance > ARROW_FROM_TM, direction: unit plane vector toward
## `target_abs` (zero at the target), distance_tm}. In S1 (size 1) am and tm are the same.
static func origin_arrow(cell_abs: PackedFloat64Array, target_abs := PackedFloat64Array([0.0, 0.0])) -> Dictionary:
	var dx: float = target_abs[0] - cell_abs[0]
	var dy: float = target_abs[1] - cell_abs[1]
	var d := sqrt(dx * dx + dy * dy)
	var direction := Vector2(dx / d, dy / d) if d > 0.0 else Vector2.ZERO
	return {"visible": d > ARROW_FROM_TM, "direction": direction, "distance_tm": d}


## "312 m" below 1,000 m (rounded); "1.4 km" from there (one decimal); "100 km" from 100 km (no
## decimal).
static func distance_text(d_tm: float) -> String:
	if roundi(d_tm) < 1000:
		return "%d m" % roundi(d_tm)
	var tenths := roundi(d_tm / 100.0)
	if tenths < 1000:
		return "%.1f km" % (tenths / 10.0)
	return "%d km" % roundi(d_tm / 1000.0)


func _instance(kit: PlacementKit, id: String) -> Node3D:
	var a: Dictionary = kit.assets.get(id, {})
	var path := str(a.get("glb", "res://assets/export/%s.glb" % id))
	var piece: Node3D = (load(path) as PackedScene).instantiate()
	piece.name = id
	add_child(piece)
	return piece


## How far ahead (-Z, the model's front) `piece`'s first mesh reaches from the piece's origin.
static func _front_of(piece: Node3D) -> float:
	var meshes := piece.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return 0.0
	var mi := meshes[0] as MeshInstance3D
	var box := mi.transform * mi.get_aabb()
	return maxf(-box.position.z, 0.0)
