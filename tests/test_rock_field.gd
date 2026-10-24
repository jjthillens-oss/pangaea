extends TestCase
## Direct checks that the decorative rock field follows the pool layout after rebuilds.


func test_layout_rocks_become_distinct_nodes_at_their_plane_positions() -> void:
	var layout := PoolLayout.load_from("res://tests/fixtures/pool_test_rocks.json")
	var field := RockField.new()
	field.build(layout)
	check_eq(field.get_child_count(), layout.rocks.size(), "one visual for each layout rock")
	for rock in layout.rocks:
		var node := field.get_node_or_null(NodePath(rock.id)) as Node3D
		check(node != null, "%s has an imported scene" % rock.id)
		if node == null:
			continue
		check(
			node.position.is_equal_approx(PlaneSpace.to_world(rock.center)), "%s position" % rock.id
		)
		check_near(node.rotation.y, deg_to_rad(rock.yaw_deg), 0.0001, "%s yaw" % rock.id)
		check(node.scale.is_equal_approx(Vector3.ONE * rock.scale), "%s uniform scale" % rock.id)
	field.free()


func test_rebuild_replaces_old_rocks_and_applies_new_rotation() -> void:
	var layout := PoolLayout.new()
	layout.rocks = [
		{
			"id": "first",
			"asset": "rock_a",
			"center": Vector2(2.0, 3.0),
			"yaw_deg": 0.0,
			"scale": 1.0
		}
	]
	var field := RockField.new()
	field.build(layout)
	var old_node := field.get_node("first") as Node3D
	layout.rocks = [
		{
			"id": "second",
			"asset": "rock_c",
			"center": Vector2(-4.0, 5.0),
			"yaw_deg": 90.0,
			"scale": 2.0
		}
	]
	field.build(layout)
	check_eq(field.get_child_count(), 1, "rebuild leaves only the new layout's rock")
	check(field.get_node_or_null("first") == null, "old rock leaves the field")
	check(old_node.get_parent() == null, "old instance is detached")
	var replacement := field.get_node("second") as Node3D
	check(replacement != old_node, "rebuild creates a fresh instance")
	check(
		replacement.position.is_equal_approx(Vector3(-4.0, PlaneSpace.SWIM_Y, 5.0)), "new position"
	)
	check_near(replacement.rotation.y, PI / 2.0, 0.0001, "new yaw")
	check(replacement.scale.is_equal_approx(Vector3.ONE * 2.0), "new scale")
	field.free()
