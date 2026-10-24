class_name SimIntent
extends RefCounted
## What the player (or a test driver) wants for one PoolSim tick. Input code builds it; the sim
## only reads it. `move` is the wanted direction on the plane and its length (0..1) the throttle.
## `grow` is a press of the Grow key this tick, and `trigger` the player's growth setting when the
## scene sends it ("auto" or "press"; "" leaves it as it is): S2, D-21 as BP-3 has it. Only the
## endless world with growth reads them.

var move := Vector2.ZERO
var grow := false
var trigger := ""


func _init(p_move := Vector2.ZERO) -> void:
	move = p_move
