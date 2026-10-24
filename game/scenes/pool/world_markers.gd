class_name WorldMarkers
extends Node3D
## The endless sea's two way-markers (S1, docs/s1/s1-content.md 6.11): the cream column standing
## beside the generation start (the checkpoint, where a death brings the lineage back), and, once the
## cell is more than ARROW_FROM_TM from where the lineage began, a flat arrow lying beside the cell
## and pointing there: abs (0, 0), the home block's centre (build plan Q9). Both are the kit's pieces
## with the kit's materials as shipped (build plan Q3). Pool mode shows neither.
##
## The column stands COLUMN_BESIDE_TM east of the checkpoint, not on it, so a cell that starts or
## comes back there starts next to it, never inside it. The camera always looks north, so a piece due
## east stands beside the cell on screen whichever way the cell faces (one to the south would rise
## across it). Its drawn height is kept to COLUMN_TOP_MAX_M above the swim plane whatever the GLB
## brings (the kit's soft shaft is exactly that tall), so at the default camera it never runs out of
## the top of the screen from the spawn, even drawn opaque.
##
## The node is world_rebuilt: update() places both from the sim every frame, so a rebase or a moved
## checkpoint needs nothing more. The HUD's world overlay reads column(), arrow_state() and
## arrow_tip() for its pip and its distance label.
##
## Growth (S2, V-18): the arrow's threshold is ARROW_FROM_TM in the current tm (64 am at size 2),
## while the distance it reports stays in am, so a growth never changes the number. Through the
## growth beat both pieces are drawn at k of their size (set_size_k), and so are their offsets (the
## column's beside the checkpoint, the arrow's from the cell), so frame 0 draws them where the last
## frame did; the column holds at the old checkpoint until the relations change
## (hold_column_until), then fades out there over COLUMN_FADE_S and in at the new one over the next
## COLUMN_FADE_S.

const ARROW_FROM_TM := 40.0         ## the arrow shows beyond this distance from the origin (plan A.6)
const ARROW_RING_GAP := 1.2         ## the arrow sits this far outside the cell's radius
const ARROW_Y := 0.05
## The markers' cream, for the HUD's pip and label (C-9; Q3 keeps it apart from the UI cream #F4EAD2).
const MARKER_COLOR := Color("#F4E8DA")
## Where the column stands from the checkpoint (plane x, y; tm): due east, clear of a starting cell's
## radius (about 1 tm) and of the column's own 0.25 tm flare by a little over a cell.
const COLUMN_BESIDE_TM := Vector2(2.6, 0.0)
## The highest the column is drawn above the swim plane (m): the kit's shaft, -1.5 to +4.5 (art PR
## #63). A taller piece is squashed to it; at the default camera (14 m, pitch 55, fov 45) its top
## then shows about 200 px below the screen's top with the cell at the spawn.
const COLUMN_TOP_MAX_M := 4.5
const COLUMN_ID := "marker_checkpoint_column"
const ARROW_ID := "marker_origin_arrow"
## Where the lineage began, absolute am (S1: the home block's centre).
const ORIGIN_AM := [0.0, 0.0]
## The column's cross-fade after a growth: out at the old checkpoint, then in at the new one.
const COLUMN_FADE_S := 0.5

## Beat seconds now (the pool sets it every frame; -1 when no beat runs).
var beat_t := -1.0

var _column: Node3D
var _arrow: Node3D
var _arrow_front := 0.0             ## how far the arrow's mesh reaches ahead of its origin (its -Z extent)
var _arrow_state := {"visible": false, "direction": Vector2.ZERO, "distance_tm": 0.0, "distance_am": 0.0}
var _column_scale := Vector3.ONE    ## the column's own scale (its height kept to COLUMN_TOP_MAX_M)
var _size_k := 1.0
var _shown_cp := PackedFloat64Array()   ## the checkpoint the column stood at last frame (am)
var _held_cp := PackedFloat64Array()    ## the checkpoint it holds at through a growth (am), or empty
var _hold_until := -1.0


## Instances both marker pieces from `kit` in the endless sea; in the pool (no world, or no kit) the
## node stays empty and hidden.
func setup(sim: PoolSim, kit: PlacementKit) -> void:
	clear()
	visible = sim != null and sim.world != null and kit != null
	if not visible:
		return
	_column = _instance(kit, COLUMN_ID)
	_column.scale.y = column_scale(_top_of(_column))
	_column_scale = _column.scale
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
	_arrow_state = {"visible": false, "direction": Vector2.ZERO, "distance_tm": 0.0, "distance_am": 0.0}
	_size_k = 1.0
	_shown_cp = PackedFloat64Array()
	_held_cp = PackedFloat64Array()
	_hold_until = -1.0
	beat_t = -1.0


## Both pieces at k of their size (the growth beat's depth factor; 1 when none runs).
func set_size_k(k: float) -> void:
	_size_k = k
	if _column != null:
		_column.scale = _column_scale * k
		_arrow.scale = Vector3.ONE * k


## A growth: the column keeps standing at the checkpoint it stood at until beat second `beat_s`,
## then cross-fades to the new one.
func hold_column_until(beat_s: float) -> void:
	if not _shown_cp.is_empty():
		_held_cp = _shown_cp
		_hold_until = beat_s


## Places the column beside the checkpoint and the arrow beside the cell drawn at `cell_at` (the
## pool's plane, as the cell view stands this frame), from the sim's float64 absolute positions. The
## arrow's threshold is in the tm of `shown_size` (the pool's shown_size(): the old size until a
## growth's chord, V-7; 0 for the sim's).
func update(sim: PoolSim, cell_at: Vector2, shown_size := 0) -> void:
	if not visible or _column == null or sim == null or sim.world == null:
		return
	var cp := PackedFloat64Array([sim.world.checkpoint_am[0], sim.world.checkpoint_am[1]])
	var fade := 0.0
	if not _held_cp.is_empty():
		var since := beat_t - _hold_until if beat_t >= 0.0 else INF
		if since < COLUMN_FADE_S:
			cp = _held_cp
			fade = clampf(since / COLUMN_FADE_S, 0.0, 1.0)
		elif since < 2.0 * COLUMN_FADE_S:
			fade = 1.0 - (since - COLUMN_FADE_S) / COLUMN_FADE_S
		else:
			_held_cp = PackedFloat64Array()
	_shown_cp = cp
	_column.position = PlaneSpace.to_world(column_point(sim.world.local_of_abs(cp[0], cp[1]), _size_k))
	_set_column_fade(fade)
	_arrow_state = origin_arrow(sim.absolute_position_am(), PackedFloat64Array(ORIGIN_AM), WorldConfig.tm_to_am(shown_size if shown_size > 0 else sim.world.size))
	_arrow.visible = _arrow_state.visible and not sim.dead
	if _arrow.visible:
		var d: Vector2 = _arrow_state.direction
		_arrow.position = PlaneSpace.to_world(cell_at + d * (sim.phenotype.radius + ARROW_RING_GAP) * _size_k, ARROW_Y)
		_arrow.rotation = Vector3(0.0, PlaneSpace.yaw_for_heading(d.angle()), 0.0)


## The column piece (tests and the HUD overlay), or null in the pool.
func column() -> Node3D:
	return _column


## The arrow piece (tests), or null in the pool.
func arrow() -> Node3D:
	return _arrow


## How far the column has faded (0 drawn, 1 gone), for tests.
func column_fade() -> float:
	return float(_column.get_meta(&"fade", 0.0)) if _column != null else 0.0


func _set_column_fade(fade: float) -> void:
	if fade == column_fade():
		return
	_column.set_meta(&"fade", fade)
	for n: Node in _column.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).transparency = fade


## The last update's origin_arrow result: {visible, direction, distance_am, distance_tm}.
func arrow_state() -> Dictionary:
	return _arrow_state


## The arrow's tip in the pool's space, where the HUD puts its distance label.
func arrow_tip() -> Vector3:
	if _arrow == null:
		return Vector3.ZERO
	return _arrow.position + PlaneSpace.to_world(_arrow_state.direction) * _arrow_front


## Pure: whether the arrow shows for a cell at `cell_abs` (absolute am) and where it points, all
## from float64 differences: {visible: distance > ARROW_FROM_TM in tm (x `tm_to_am` am), direction:
## unit plane vector toward `target_abs` (zero at the target), distance_am}. The distance is in am
## at every size (V-18); `distance_tm` is the same number, named when S1 had am and tm the same.
static func origin_arrow(cell_abs: PackedFloat64Array, target_abs := PackedFloat64Array([0.0, 0.0]),
		tm_to_am := 1.0) -> Dictionary:
	var dx: float = target_abs[0] - cell_abs[0]
	var dy: float = target_abs[1] - cell_abs[1]
	var d := sqrt(dx * dx + dy * dy)
	var direction := Vector2(dx / d, dy / d) if d > 0.0 else Vector2.ZERO
	return {"visible": d > ARROW_FROM_TM * tm_to_am, "direction": direction, "distance_am": d, "distance_tm": d}


## Pure: where the column stands (the pool's plane) for a checkpoint at `checkpoint_local`, drawn at
## `k` of its size (its offset too).
static func column_point(checkpoint_local: Vector2, k := 1.0) -> Vector2:
	return checkpoint_local + COLUMN_BESIDE_TM * k


## Pure: the column's y scale for a piece whose meshes reach `top_m` above its origin: 1, or less
## so that it reaches COLUMN_TOP_MAX_M.
static func column_scale(top_m: float) -> float:
	return COLUMN_TOP_MAX_M / top_m if top_m > COLUMN_TOP_MAX_M else 1.0


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


## How high `piece`'s meshes reach above its origin (m, in the piece's own frame, unscaled).
static func _top_of(piece: Node3D) -> float:
	var top := 0.0
	for n: Node in piece.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var t := Transform3D.IDENTITY
		var at: Node = mi
		while at != piece:
			t = (at as Node3D).transform * t
			at = at.get_parent()
		top = maxf(top, (t * mi.get_aabb()).end.y)
	return top


## How far ahead (-Z, the model's front) `piece`'s first mesh reaches from the piece's origin.
static func _front_of(piece: Node3D) -> float:
	var meshes := piece.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return 0.0
	var mi := meshes[0] as MeshInstance3D
	var box := mi.transform * mi.get_aabb()
	return maxf(-box.position.z, 0.0)
