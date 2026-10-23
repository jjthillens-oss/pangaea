class_name RockField
extends Node3D
## The pool's rocks (M1 step 2): one Blender rock per layout rock, at its center on the swim plane
## with its yaw and uniform scale. The rocks the cell bumps into are PoolArena circles of the
## same centers; this node only draws them. The pool's WorldSpace shifts it across a rebase (S1), so
## the rocks are placed in its frame (WorldSpace.to_frame).

const ROCK_SCENES := {
	"rock_a": preload("res://assets/export/rock_a.glb"),
	"rock_b": preload("res://assets/export/rock_b.glb"),
	"rock_c": preload("res://assets/export/rock_c.glb"),
}


func build(layout: PoolLayout) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for rock in layout.rocks:
		var packed: PackedScene = ROCK_SCENES.get(rock.asset)
		if packed == null:
			push_error("Rock '%s' uses asset '%s', which the pool cannot draw." % [rock.id, rock.asset])
			continue
		var node: Node3D = packed.instantiate()
		node.name = rock.id
		node.position = WorldSpace.to_frame(self, rock.center)
		node.rotation = Vector3(0.0, deg_to_rad(rock.yaw_deg), 0.0)
		node.scale = Vector3.ONE * float(rock.scale)
		add_child(node)


## Moves every rock by this node's position and the node back to the origin: nothing moves on
## screen (WorldSpace.renormalize_far).
func renormalize() -> void:
	for child in get_children():
		(child as Node3D).position += position
	position = Vector3.ZERO
