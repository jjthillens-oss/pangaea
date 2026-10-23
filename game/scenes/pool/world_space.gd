class_name WorldSpace
extends Node
## The pool's floating origin on screen (S1; docs/s1/s1-interfaces.md 3.14, s1-content.md 6.1 and
## 6.2). The endless sim keeps every position local to an origin that moves by whole chunks when the
## cell swims far from it (a rebase): the sim emits "rebased" {offset_tm}, and every local position
## it holds drops by that offset at once. The scene must follow in the same frame without a jump.
##
## Every Node3D under the pool is covered by one of three groups (test_world_scene checks it):
##   world_space      registered here and shifted by -offset on a rebase: the containers that hold
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

