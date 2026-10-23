extends TestCase
## The shader warm-up (pool.gd _fade_in, PlayerCellView.warm_up): under the start fade, the eat
## burst and both food meshes draw once where the camera sees them but the player cannot, so their
## shaders are ready before the first meal. The point lies on the view axis at a fixed depth, so it
## does not rely on anything under the cell, only on the fluid's opaque Backdrop lying between it
## and the camera.
## The test runner has no scene tree, so the pool camera here has no parent and its transform
## stands for the global one that _fade_in hands to PoolScene.warm_up_point.

## The pool, whose opaque Backdrop (docs/DECISIONS.md, "Microscopic world look") the warm-up has
## to lie behind to stay hidden.
const POOL_SCENE := "res://game/scenes/pool/pool.tscn"
## Window shapes the frustum must hold the point for: 16:9 (the 1280 x 720 window and full HD),
## 16:10, 4:3 and 21:9. The camera keeps its vertical field of view (Camera3D.KEEP_HEIGHT).
const ASPECTS: Array[float] = [16.0 / 9.0, 16.0 / 10.0, 4.0 / 3.0, 21.0 / 9.0]


## The Backdrop's height in the pool scene, or INF when it has none.
func _backdrop_y() -> float:
	var pool := (load(POOL_SCENE) as PackedScene).instantiate()
	var backdrop := pool.get_node_or_null("Backdrop") as Node3D
	var y := backdrop.position.y if backdrop else INF
	pool.free()
	return y


## Every zoom the wheel can reach, zoom_min to zoom_max in zoom_steps.
func _zooms(camera: Dictionary) -> Array[float]:
	var out: Array[float] = []
	var zoom := float(camera.zoom_min)
	while zoom <= float(camera.zoom_max) + 1e-6:
		out.append(zoom)
		zoom += float(camera.zoom_step)
	return out


## Whether `world` lies inside the frustum of `camera` for a window of this aspect: the projection
## Camera3D builds from its own fov and clip planes, as tests/test_pool_view.gd's _unproject does.
func _in_frustum(camera: Camera3D, world: Vector3, aspect: float) -> bool:
	var view := camera.transform.affine_inverse() * world
	var clip := Projection.create_perspective(camera.fov, aspect, camera.near, camera.far) * Vector4(view.x, view.y, view.z, 1.0)
	return clip.w > 0.0 and absf(clip.x) <= clip.w and absf(clip.y) <= clip.w and absf(clip.z) <= clip.w


func test_the_warm_up_point_is_in_view_inside_the_far_plane_and_behind_the_backdrop_at_every_zoom() -> void:
	var layout := PoolLayout.load_from()
	var backdrop_y := _backdrop_y()
	check(backdrop_y < INF, "the pool has a Backdrop")
	var zooms := _zooms(layout.camera)
	for wanted in [10.0, 14.0, 20.0]:
		check(zooms.has(wanted), "the zooms checked include %d m: %s" % [wanted, zooms])
	var camera := PoolCamera.new()
	camera.configure(layout.camera)
	# The cell's start and the farthest the camera looks toward the wall (the hard radius plus the
	# look-ahead), north and south.
	var reach := layout.hard_radius + float(layout.camera.look_ahead_max)
	var focuses: Array[Vector2] = [layout.spawn, Vector2(0.0, -reach), Vector2(0.0, reach)]
	var outside := PackedStringArray()
	var off_axis := PackedStringArray()
	var too_far := PackedStringArray()
	var too_shallow := PackedStringArray()
	for zoom in zooms:
		camera.distance = zoom
		for focus in focuses:
			camera.snap_to(PlaneSpace.to_world(focus))
			var at := PoolScene.warm_up_point(camera.transform)
			var where := "zoom %d m at %s" % [zoom, focus]
			for aspect in ASPECTS:
				if not _in_frustum(camera, at, aspect):
					outside.append("%s, aspect %.2f: %s" % [where, aspect, at])
			var toward := at - camera.position
			if toward.normalized().dot(-camera.basis.z) <= 0.9999:
				off_axis.append(where)
			if toward.length() >= camera.far:
				too_far.append("%s: %.1f m" % [where, toward.length()])
			if at.y >= backdrop_y:
				too_shallow.append("%s: y %.1f" % [where, at.y])
	check(outside.is_empty(), "the warm-up point is in the frustum; outside at %s" % [outside])
	check(off_axis.is_empty(), "on the view axis, where every window shape shows it; off it at %s" % [off_axis])
	check(too_far.is_empty(), "inside the far plane at %.0f m; beyond it at %s" % [camera.far, too_far])
	check(too_shallow.is_empty(), "behind the Backdrop at %.0f m; above it at %s" % [backdrop_y, too_shallow])
	camera.free()
