class_name FoodView
extends MultiMeshInstance3D
## One kind of food drawn from the sim's items as a single MultiMesh (M1 step 2): plankton
## ("plant") or carrion ("meat"). The mesh comes from the item's Blender asset. sync() writes the
## whole instance buffer once per frame.
##
## Drawn only: plankton bobs and spins and grows in when it appears; carrion sinks to just under
## the swim plane and grows to full size when it appears, then lies still, turned by its id, and
## shrinks over the last seconds before it rots away. Food of the starting world is simply there.
## None of this changes the items.
##
## S2 (s2-view 4.6, V-10, V-24): the view wears a look (LOOKS: the plankton, the algae ball at size 2,
## carrion), and each item draws at its own radius over the look's, so carrion shrunk by a growth is
## drawn smaller. Morsels (HIDDEN_SOURCES) are drawn by their creature's own view, not here. At a
## growth the beat keeps what was last drawn (snapshot) and draws it on, re-expressed, from a copy
## (retired_copy) that fades while the new food grows in. Through the beat the food's heights (the
## bob, carrion's lie and sink) are drawn at the depth factor k, as every depth layer is, so carrion
## kept by the tick lies where frame A drew it.

const FLOATS_PER_INSTANCE := 12   ## a 3x4 transform, row by row
const MIN_CAPACITY := 16
const PLANT_BOB_M := 0.06
const PLANT_BOB_HZ := 0.25
const PLANT_SPIN_RAD_S := 0.35
const PLANT_GROW_S := 0.6
const MEAT_Y := -0.04
const MEAT_SETTLE_S := 0.6        ## new carrion sinks and grows in over this long...
const MEAT_SINK_M := 0.5          ## ...from this far above where it lies...
const MEAT_SETTLE_SCALE := 0.3    ## ...and this share of its size
const MEAT_SHRINK_S := 10.0       ## carrion shrinks over its last this many seconds
const MEAT_MIN_SCALE := 0.15
const GOLDEN_ANGLE := 2.399963229728653
## The looks: each an asset scene whose first MeshInstance3D is drawn, and the item radius (tm) the
## mesh was built for (assets/records/*.json item_radius_m).
const LOOKS := {
	"plankton": {"scene": "res://assets/export/plankton.glb", "radius": 0.18},
	"algae_ball": {"scene": "res://assets/export/algae_ball.glb", "radius": 0.18},
	"carrion": {"scene": "res://assets/export/carrion.glb", "radius": 0.3},
}
## Each kind's look until set_look() picks another.
const KIND_LOOKS := {"plant": "plankton", "meat": "carrion"}
## Items from these sources are drawn elsewhere (a morsel by its creature's view, V-24).
const HIDDEN_SOURCES: PackedStringArray = ["morsel"]

@export_enum("plant", "meat") var kind := "plant"
## The food's Blender asset; its first MeshInstance3D gives the mesh.
@export var source: PackedScene

## The look worn now (a LOOKS key).
var look := ""
## The growth beat's depth factor: heights above and below the plane are drawn times this (1 outside
## a beat).
var depth_k := 1.0
var _buffer := PackedFloat32Array()
var _look_radius := 1.0
## The item id drawn at each instance, as last drawn (snapshot()).
var _ids := PackedStringArray()
## Look meshes by scene path, loaded once.
static var _look_meshes := {}


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if multimesh == null:
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = food_mesh()
		_reserve(MIN_CAPACITY)
	if look.is_empty():
		look = KIND_LOOKS[kind]
		_look_radius = float(LOOKS[look].radius)


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


## The mesh of look `name` (a LOOKS key), loaded once; null for an unknown look.
static func look_mesh(name: String) -> Mesh:
	if not LOOKS.has(name):
		return null
	var path: String = LOOKS[name].scene
	if not _look_meshes.has(path):
		var scene := (load(path) as PackedScene).instantiate()
		var found := scene.find_children("*", "MeshInstance3D", true, false)
		_look_meshes[path] = (found[0] as MeshInstance3D).mesh if not found.is_empty() else null
		scene.free()
	return _look_meshes[path]


## Wears look `name` (a LOOKS key): its mesh from now on, and items drawn at their radius over its.
## An unknown look is ignored.
func set_look(name: String) -> void:
	if name == look or not LOOKS.has(name) or multimesh == null:
		return
	look = name
	multimesh.mesh = look_mesh(name)
	_look_radius = float(LOOKS[name].radius)


## How many items are drawn.
func shown_count() -> int:
	return multimesh.visible_instance_count if multimesh != null else 0


## Draws `items` (PlanktonField or CarrionField items) at sim time `now`; items from HIDDEN_SOURCES
## are left out.
func sync(items: Array[Dictionary], now: float) -> void:
	if multimesh == null:
		return
	if items.size() > multimesh.instance_count:
		_reserve(maxi(items.size(), multimesh.instance_count * 2))
	var i := 0
	for item in items:
		if item.has("source") and HIDDEN_SOURCES.has(item.source):
			continue
		_write(i, _transform_for(item, now))
		_ids[i] = item.id
		i += 1
	multimesh.buffer = _buffer
	multimesh.visible_instance_count = i


## Every item as last drawn: id -> its instance transform (the pool's space, the frame then).
func snapshot() -> Dictionary:
	var out := {}
	if multimesh == null:
		return out
	for i in multimesh.visible_instance_count:
		var o := i * FLOATS_PER_INSTANCE
		var b := _buffer
		out[_ids[i]] = Transform3D(Vector3(b[o], b[o + 4], b[o + 8]), Vector3(b[o + 1], b[o + 5], b[o + 9]),
			Vector3(b[o + 2], b[o + 6], b[o + 10]), Vector3(b[o + 3], b[o + 7], b[o + 11]))
	return out


## A still copy of this view's mesh drawn at `transforms` (from a snapshot), each re-expressed round
## `center_old` by 1 / `factor` as a growth re-expresses the world (WorldSpace.reexpress_point, its
## basis divided by `factor`), so it draws on screen exactly where they were.
func retired_copy(transforms: Array[Transform3D], center_old: Vector2, factor: float) -> StillInstances:
	var moved: Array[Transform3D] = []
	for t in transforms:
		moved.append(Transform3D(t.basis.scaled(Vector3.ONE / factor), WorldSpace.reexpress_point(t.origin, center_old, factor)))
	var copy := StillInstances.make(multimesh.mesh if multimesh != null else food_mesh(), moved)
	copy.name = String(name) + "Retired"
	return copy


func _transform_for(item: Dictionary, now: float) -> Transform3D:
	var p: Vector2 = item.position
	var r := float(item.get("radius", _look_radius)) / _look_radius
	if kind == "plant":
		var phase: Vector2 = item.get("phase", Vector2.ZERO)
		# Items of the starting world are simply there; later ones grow in as the zone regrows.
		var born := int(item.get("born_tick", 0))
		var grow := clampf((now - born * PoolSim.DT) / PLANT_GROW_S, 0.0, 1.0) if born > 0 else 1.0
		var bob := PLANT_BOB_M * sin(now * TAU * PLANT_BOB_HZ + phase.x) * depth_k
		var basis := Basis(Vector3.UP, phase.y + now * PLANT_SPIN_RAD_S).scaled(Vector3.ONE * (maxf(grow, 0.01) * r))
		return Transform3D(basis, PlaneSpace.to_world(p, PlaneSpace.SWIM_Y + bob))
	var age := float(item.get("age", 0.0))
	var left := float(item.get("lifetime", 0.0)) - age
	var shrink := clampf(left / MEAT_SHRINK_S, MEAT_MIN_SCALE, 1.0)
	var settle := 1.0 if item.get("source", "") == "initial" else ease(clampf(age / MEAT_SETTLE_S, 0.0, 1.0), 0.4)
	var yaw := fposmod(str(item.get("id", "")).hash() * GOLDEN_ANGLE, TAU)
	var size := shrink * lerpf(MEAT_SETTLE_SCALE, 1.0, settle) * r
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size),
		PlaneSpace.to_world(p, (MEAT_Y + MEAT_SINK_M * (1.0 - settle)) * depth_k))


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
	_ids.resize(count)
