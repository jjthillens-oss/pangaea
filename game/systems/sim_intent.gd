class_name SimIntent
extends RefCounted
## What the player (or a test driver) wants for one PoolSim tick. Input code builds it; the sim
## only reads it. `move` is the wanted direction on the plane and its length (0..1) the throttle.

var move := Vector2.ZERO


func _init(p_move := Vector2.ZERO) -> void:
	move = p_move
