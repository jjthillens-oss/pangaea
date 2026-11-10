extends TestCase
## Direct checks that pool rocks use the current per-asset MultiMesh field.


func test_pool_layout_populates_instances_at_their_plane_positions() -> void:
	var layout := PoolLayout.load_from("res://tests/fixtures/pool_test_rocks.json")
	var field := RockField.new()
	field.build_pool(layout)
	check_eq(field.assets_in_use().size(), 2, "both rock assets are in use")
	for rock in layout.rocks:
		var instances := field.instances_of(rock.asset)
		check_eq(instances.size(), 1, "%s has one instance" % rock.asset)
		if instances.is_empty():
			continue
		var instance: Dictionary = instances[0]
		check_eq(instance.id, rock.id, "instance keeps the rock ID")
		check_eq(instance.key, RockField.POOL_KEY, "pool rocks share the pool key")
		var transform: Transform3D = instance.transform
		check(transform.origin.is_equal_approx(PlaneSpace.to_world(rock.center)), "rock position")
		check_near(transform.basis.get_scale().x, rock.scale, 0.0001, "uniform scale")
		check_near(transform.basis.get_euler().y, deg_to_rad(rock.yaw_deg), 0.0001, "yaw")
		var multimesh := field.multimesh_of(rock.asset)
		check(multimesh != null, "asset has a MultiMesh")
		if multimesh != null:
			check_eq(multimesh.multimesh.instance_count, 1, "one rendered instance")
	field.free()


func test_rebuild_replaces_old_asset_and_applies_new_rotation() -> void:
	var layout := PoolLayout.new()
	layout.rocks = [{"id": "first", "asset": "rock_a", "center": Vector2(2.0, 3.0),
		"yaw_deg": 0.0, "scale": 1.0, "radius": 1.0}]
	var field := RockField.new()
	field.build_pool(layout)
	check_eq(field.instances_of("rock_a").size(), 1, "first layout is present")
	layout.rocks = [{"id": "second", "asset": "rock_c", "center": Vector2(-4.0, 5.0),
		"yaw_deg": 90.0, "scale": 2.0, "radius": 2.0}]
	field.build_pool(layout)
	check(field.instances_of("rock_a").is_empty(), "old rock leaves the field")
	check(field.multimesh_of("rock_a") == null, "old MultiMesh is detached")
	check_eq(field.assets_in_use(), PackedStringArray(["rock_c"]), "only new asset remains")
	var instances := field.instances_of("rock_c")
	check_eq(instances.size(), 1, "new asset has one instance")
	if not instances.is_empty():
		var instance: Dictionary = instances[0]
		check_eq(instance.id, "second", "new rock ID")
		var transform: Transform3D = instance.transform
		check(transform.origin.is_equal_approx(PlaneSpace.to_world(Vector2(-4.0, 5.0))), "new position")
		check_near(transform.basis.get_euler().y, PI / 2.0, 0.0001, "new yaw")
		check(transform.basis.get_scale().is_equal_approx(Vector3.ONE * 2.0), "new scale")
	field.free()
