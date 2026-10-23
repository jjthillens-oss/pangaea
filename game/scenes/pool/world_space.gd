class_name WorldSpace
extends Node
## The pool's floating origin on screen (S1; docs/s1/s1-interfaces.md 3.14, s1-content.md 6.1 and
## 6.2). The endless sim keeps every position local to an origin that moves by whole chunks when the
## cell swims far from it (a rebase): the sim emits "rebased" {offset_tm}, and every local position
## it holds drops by that offset at once. The scene must follow in the same frame without a jump.
##
## Every Node3D under the pool is covered by one of three groups (test_world_scene checks it):
##   world_space      registered here and shifted by -offset on a rebase (and re-expressed at a
##                    growth, apply_growth): the containers that hold
##                    world pieces (shells, landmarks, zone patches and labels, effects) and the
##                    leaves that keep a position of their own (strike lanes, dying creature views,
##                    positional audio players);
##   world_rebuilt    placed from the sim every frame, so a rebase needs nothing (food, the cell,
##                    the creatures, the markers, the camera, which shifts its focus instead);
##   camera_relative  kept under the camera focus every frame (the Backdrop, the lights, art's
##                    ambience).
##
## Containers and leaves. A registered container places its children in its own frame (to_frame)
## when it adds them, so a container that has moved by -offset carries its children with it. A leaf
## sets its own position in current local coordinates whenever it is reused. Repeated rebases leave
## a container far from the pool's origin with its children far the other way; renormalize_far()
## moves those children back by the container's position (each container's renormalize()), which
## changes no world position, so float32 positions stay small however far the cell swims.

const GROUP := &"world_space"
## A container farther than this (tm) from the pool's origin renormalises after a rebase.
const RENORMALIZE_TM := 512.0
## The keys a rare place carries beyond {id, kind, position}, copied when the stream sends them: its
## orientation (docs/s1/s1-build-plan.md B-15).
const PLACE_ORIENTATION_KEYS: PackedStringArray = ["yaw_deg", "mirror"]

var _nodes: Array[Node3D] = []


## Adds `node` to the shifted set (and the "world_space" group); it leaves when it leaves the tree.
func register(node: Node3D) -> void:
	if node == null or _nodes.has(node):
		return
	_nodes.append(node)
	node.add_to_group(GROUP)
	var leave := unregister.bind(node)
	if not node.tree_exiting.is_connected(leave):
		node.tree_exiting.connect(leave, CONNECT_ONE_SHOT)


func unregister(node: Node3D) -> void:
	if node == null:
		return
	_nodes.erase(node)
	if is_instance_valid(node) and node.is_in_group(GROUP):
		node.remove_from_group(GROUP)


## A rebase moved every local position by -offset_tm: every registered node moves with it, in
## registration order.
func apply_rebase(offset_tm: Vector2) -> void:
	var shift := Vector3(offset_tm.x, 0.0, offset_tm.y)
	for node in registered():
		node.position -= shift


## A growth re-expressed every local position round `center_old` by 1 / `factor` (S2, C-V2): each
## registered container re-expresses its own children in place and stays at position 0 and scale 1
## (its apply_growth; a container never scales, see to_frame); any other registered node (a leaf:
## lanes, dying views, audio players, WorldFx, the beat's effects) moves and shrinks by itself.
func apply_growth(center_old: Vector2, factor: float) -> void:
	for node in registered():
		if node.has_method(&"apply_growth"):
			node.call(&"apply_growth", center_old, factor)
		else:
			node.position = reexpress_point(node.position, center_old, factor)
			node.scale /= factor


## A point of the old frame in the new one: ((x - cx) / f, y / f, (z - cy) / f). PlaneSpace puts a
## plane point c at x = c.x, z = c.y.
static func reexpress_point(p: Vector3, center_old: Vector2, factor: float) -> Vector3:
	return Vector3((p.x - center_old.x) / factor, p.y / factor, (p.z - center_old.y) / factor)


## The registered nodes still alive, in registration order.
func registered() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node in _nodes:
		if is_instance_valid(node):
			out.append(node)
	return out


## Each registered container farther than RENORMALIZE_TM from the pool's origin renormalises
## (moves its children by its position and itself back to the origin; nothing moves on screen).
func renormalize_far() -> void:
	for node in registered():
		if node.has_method(&"renormalize") and Vector2(node.position.x, node.position.z).length() > RENORMALIZE_TM:
			node.call(&"renormalize")


## A container's frame: where sim-local (0, 0) sits in its own space (x, z).
static func frame_of(container: Node3D) -> Vector2:
	return Vector2(-container.position.x, -container.position.z)


## Sim-local plane point `p` at height `y` in `container`'s space: PlaneSpace.to_world(p, y) less
## the container's position in x and z (a container never turns or scales).
static func to_frame(container: Node3D, p: Vector2, y: float = PlaneSpace.SWIM_Y) -> Vector3:
	var at := PlaneSpace.to_world(p, y)
	if container == null:
		return at
	return Vector3(at.x - container.position.x, at.y, at.z - container.position.z)


## The spine 3.12 chunk_loaded payload of a loaded chunk, every position local through the world's
## frame now: the scene's own copy of the stream's event (CT-13), so the pool can draw the chunks
## already loaded when it is built.
static func chunk_loaded_event(world: WorldStream, chunk: WorldChunk) -> Dictionary:
	var shells := []
	for s in chunk.shells:
		shells.append({"id": s.id, "position": world.local_of_tm(float(s.x), float(s.y)), "radius": float(s.r),
			"kind": s.kind, "asset": s.asset, "yaw_deg": s.yaw_deg, "scale": s.scale, "tint": s.tint})
	var zones := []
	for z in chunk.zones:
		zones.append({"id": z.id, "center": world.local_of_tm(float(z.x), float(z.y)), "radius": float(z.radius),
			"region": z.region})
	var anchors := []
	for a in chunk.anchors:
		anchors.append({"id": a.id, "position": world.local_of_tm(float(a.x), float(a.y)), "model": a.model,
			"dressing": a.dressing})
	var places := []
	for p in chunk.places:
		var place := {"id": p.id, "kind": p.kind, "position": world.local_of_tm(float(p.x), float(p.y))}
		for k in PLACE_ORIENTATION_KEYS:
			if p.has(k):
				place[k] = p[k]
		places.append(place)
	return {"type": "chunk_loaded", "key": chunk.key, "shells": shells, "zones": zones, "anchors": anchors,
		"places": places}
