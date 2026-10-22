class_name FoodView
extends MultiMeshInstance3D
## One kind of food drawn from the sim's items as a single MultiMesh (M1 step 2): plankton
## ("plant") or carrion ("meat"). The mesh comes from the item's Blender asset. sync() writes the
## whole instance buffer once per frame.
##
## Drawn only: plankton bobs and spins and grows in when it appears; carrion sinks onto the floor
## and grows to full size when it appears, then lies still, turned by its id, and shrinks over the
## last seconds before it rots away. Food of the starting world is simply there. None of this
## changes the items.

const FLOATS_PER_INSTANCE := 12   ## a 3x4 transform, row by row
const MIN_CAPACITY := 16
const PLANT_BOB_M := 0.06
const PLANT_BOB_HZ := 0.25
const PLANT_SPIN_RAD_S := 0.35
const PLANT_GROW_S := 0.6
const MEAT_Y := -0.04
const MEAT_SETTLE_S := 0.6        ## new carrion sinks and grows in over this long...
const MEAT_SINK_M := 0.5          ## ...from this far above the floor...
const MEAT_SETTLE_SCALE := 0.3    ## ...and this share of its size
const MEAT_SHRINK_S := 10.0       ## carrion shrinks over its last this many seconds
const MEAT_MIN_SCALE := 0.15
const GOLDEN_ANGLE := 2.399963229728653

@export_enum("plant", "meat") var kind := "plant"
## The food's Blender asset; its first MeshInstance3D gives the mesh.
@export var source: PackedScene

var _buffer := PackedFloat32Array()


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if multimesh == null:
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = food_mesh()
		_reserve(MIN_CAPACITY)


## The mesh every instance draws (also used for the eaten-item ghost).
func food_mesh() -> Mesh:
	if multimesh != null and multimesh.mesh != null:
		return multimesh.mesh
	if source == null:
		return null
	var scene := source.instantiate()
	var found := scene.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = (found[0] as MeshInstance3D).mesh if not found.is_empty() else null
	scene.free()
	return mesh


## How many items are drawn.
func shown_count() -> int:
	return multimesh.visible_instance_count if multimesh != null else 0


## Draws `items` (PlanktonField or CarrionField items) at sim time `now`.
func sync(items: Array[Dictionary], now: float) -> void:
	if multimesh == null:
		return
	if items.size() > multimesh.instance_count:
		_reserve(maxi(items.size(), multimesh.instance_count * 2))
	var i := 0
	for item in items:
		_write(i, _transform_for(item, now))
		i += 1
	multimesh.buffer = _buffer
	multimesh.visible_instance_count = items.size()


func _transform_for(item: Dictionary, now: float) -> Transform3D:
	var p: Vector2 = item.position
	if kind == "plant":
		var phase: Vector2 = item.get("phase", Vector2.ZERO)
		# Items of the starting world are simply there; later ones grow in as the zone regrows.
		var born := int(item.get("born_tick", 0))
		var grow := clampf((now - born * PoolSim.DT) / PLANT_GROW_S, 0.0, 1.0) if born > 0 else 1.0
		var bob := PLANT_BOB_M * sin(now * TAU * PLANT_BOB_HZ + phase.x)
		var basis := Basis(Vector3.UP, phase.y + now * PLANT_SPIN_RAD_S).scaled(Vector3.ONE * maxf(grow, 0.01))
		return Transform3D(basis, PlaneSpace.to_world(p, PlaneSpace.SWIM_Y + bob))
	var age := float(item.get("age", 0.0))
	var left := float(item.get("lifetime", 0.0)) - age
	var shrink := clampf(left / MEAT_SHRINK_S, MEAT_MIN_SCALE, 1.0)
	var settle := 1.0 if item.get("source", "") == "initial" else ease(clampf(age / MEAT_SETTLE_S, 0.0, 1.0), 0.4)
	var yaw := fposmod(str(item.get("id", "")).hash() * GOLDEN_ANGLE, TAU)
	var size := shrink * lerpf(MEAT_SETTLE_SCALE, 1.0, settle)
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size),
		PlaneSpace.to_world(p, MEAT_Y + MEAT_SINK_M * (1.0 - settle)))


func _write(i: int, t: Transform3D) -> void:
	var o := i * FLOATS_PER_INSTANCE
	var b := t.basis
	_buffer[o + 0] = b.x.x
	_buffer[o + 1] = b.y.x
	_buffer[o + 2] = b.z.x
	_buffer[o + 3] = t.origin.x
	_buffer[o + 4] = b.x.y
	_buffer[o + 5] = b.y.y
	_buffer[o + 6] = b.z.y
	_buffer[o + 7] = t.origin.y
	_buffer[o + 8] = b.x.z
	_buffer[o + 9] = b.y.z
	_buffer[o + 10] = b.z.z
	_buffer[o + 11] = t.origin.z


func _reserve(count: int) -> void:
	multimesh.instance_count = count
	multimesh.visible_instance_count = 0
	_buffer.resize(count * FLOATS_PER_INSTANCE)
	_buffer.fill(0.0)
