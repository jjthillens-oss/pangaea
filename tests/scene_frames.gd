extends RefCounted
## Test helper (not a test file): frames and pixels for the scene's tests outside the tree (S2,
## s2-view 10.0), as tests/test_rebase_view.gd draws them. The runner has no scene tree, so a frame
## runs by hand: the sim ticks and its events route, then the pool and the nodes under it that move
## tracked points process. Points are projected with Camera3D's own projection for a camera outside
## the tree, on a SCREEN-sized view.
##
##     const Frames := preload("res://tests/scene_frames.gd")
##     Frames.frame(pool)
##     var px := Frames.project(pool.camera, Frames.in_pool(pool, node))

const DT := 1.0 / 60.0
const SCREEN := Vector2(1920.0, 1080.0)
## The instances tracked of each of the beat's still MultiMeshes (old food, glitter).
const STILL_POINTS := 8


## One frame as the engine runs it at 60 fps: the sim ticks and its events route, then the pool
## processes, and so do the nodes under it that move tracked points (the labels, the cell, the
## creature views). `tick` false draws a frame with no tick (the beat's clock does not move).
static func frame(pool: PoolScene, tick := true) -> void:
	if tick:
		pool._physics_process(DT)
	pool._process(DT)
	pool.feedback._process(DT)
	pool.cell_view._process(DT)
	for view in pool.creature_layer.get_children():
		if not view.is_queued_for_deletion():
			view._process(DT)


## `node`'s origin in the pool's space, from its own transforms up to the pool (a top_level node's
## transform is already the pool's space).
static func in_pool(pool: Node, node: Node3D) -> Vector3:
	var t := node.transform
	var n := node
	while not n.top_level and n.get_parent() != pool and n.get_parent() is Node3D:
		n = n.get_parent()
		t = n.transform * t
	return t.origin


## Camera3D.unproject_position for a camera outside the tree on a `screen`-sized view (keep-height
## fov).
static func project(camera: Camera3D, p: Vector3, screen := SCREEN) -> Vector2:
	var view := camera.transform.affine_inverse() * p
	var clip := Projection.create_perspective(camera.fov, screen.aspect(), camera.near, camera.far) * Vector4(view.x, view.y, view.z, 1.0)
	var ndc := Vector2(clip.x, clip.y) / clip.w
	return Vector2((ndc.x + 1.0) * 0.5 * screen.x, (1.0 - ndc.y) * 0.5 * screen.y)


## The views a growth must keep in place, by name -> point in the pool's space: the cell, the
## creature views, every shell instance (live, retiring and fresh) by id, the landmark pieces, the
## zone patches and labels, the markers, the Backdrop's centre, the beat's effects (with the first
## instances of its old food copies and glitter), the silt trail's ribbons and lair mouths and the
## ghosts drawn ("ghost <name>").
static func tracked_points(pool: PoolScene) -> Dictionary:
	var out := {"cell": pool.cell_view.position}
	for view in pool.creature_layer.views():
		out["creature " + view.name] = in_pool(pool, view)
	var rocks := pool.rocks
	for asset in rocks.assets_in_use():
		for e in rocks.instances_of(asset):
			out["shell " + str(e.id)] = rocks.transform * (e.transform as Transform3D).origin
		for e in rocks.retiring_of(asset) + rocks.fresh_of(asset):
			out["shell " + str(e.id)] = rocks.transform * (e.transform as Transform3D).origin
	for piece in pool.landmarks.pieces():
		out["landmark " + piece.name] = in_pool(pool, piece)
	for child in pool.zone_lights.get_children():
		if child is MeshInstance3D:
			out["patch " + child.name] = in_pool(pool, child)
	for child in pool.feedback.get_children():
		if child is Label3D and child.visible:
			out["label " + child.name] = in_pool(pool, child)
	if pool.markers.column() != null:
		out["column"] = in_pool(pool, pool.markers.column())
	out["backdrop"] = pool.backdrop.position
	if pool.silt_trail != null:
		for child in pool.silt_trail.get_children():
			out["silt " + child.name] = in_pool(pool, child)
	if pool.ghosts != null:
		for ghost in pool.ghosts.billboards():
			out["ghost " + ghost.name] = in_pool(pool, ghost)
	if pool.growth_beat != null and pool.growth_beat.fx != null:
		for child in pool.growth_beat.fx.get_children():
			out["fx " + child.name] = in_pool(pool, child)
			if child is StillInstances:
				var still := child as StillInstances
				for i in mini(still.transforms.size(), STILL_POINTS):
					out["fx %s %d" % [child.name, i]] = in_pool(pool, still) + still.transforms[i].origin
	return out
