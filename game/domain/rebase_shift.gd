class_name RebaseShift
extends RefCounted
## The floating origin's shift (S1): when the endless world moves its origin by `by` (a whole number
## of chunks), every position the sim keeps relative to it moves by -by. The helpers here shift the
## values that are stored as they are (bodies, food items; WorldStream.rebase shifts the creatures'
## bodies and brain memories itself, in one pass); zones, sites and colliders are re-derived from
## their absolute float64 values instead, so they never drift however many rebases a run has
## (WorldStream.rebase). Pure: domain classes only.
##
## Every shifted value moves by an exact multiple of 32 tm, so its only error is the float32 rounding
## of the result: at most 3.8 um under 128 tm.

## Vector2 values that are not positions, so a rebase leaves them alone. The reflection test
## (tests/test_float_origin.gd) fails on any other Vector2 it finds that a rebase does not move; add
## one here only with its reason.
const NOT_POSITIONS := {
	"velocity": "a velocity (MotionState, seen entries)",
	"drive.move": "a direction",
	"script_move": "a direction",
	"phase": "radians (plankton drift)",
	"omega": "radians per second (plankton drift)",
	"drift_period": "seconds (PlanktonField)",
	"events": "local as of the emitting tick (spine 3.12)",
}


## `p` moved by -by; an unset point (INF) stays unset.
static func point(p: Vector2, by: Vector2) -> Vector2:
	return p - by if p.is_finite() else p


## A swimmer's position and its previous tick's, so the view's interpolation between them stays
## continuous across the rebase.
static func motion(m: Locomotion.MotionState, by: Vector2) -> void:
	m.position -= by
	m.prev_position -= by


## A two-post brain's posts (their homes and zone centres) and the centre of its union leash disc
## (D-83); a brain without posts is left as it is. WorldStream.rebase shifts the rest of a brain's
## memory itself and calls this for the posts.
static func posts(mem: CreatureBrain.Memory, by: Vector2) -> void:
	if mem.posts.is_empty():
		return
	for p in mem.posts:
		p.home -= by
		var t: Dictionary = p.territory
		if not t.is_empty():
			t.center -= by
	mem.leash_center = point(mem.leash_center, by)


## The named Vector2 keys of every item in `list` (plankton: position and anchor; carrion: position).
## Item by item, so each item is visited once (each key moves once either way).
static func items(list: Array[Dictionary], keys: PackedStringArray, by: Vector2) -> void:
	if keys.size() == 2:
		var k0 := keys[0]
		var k1 := keys[1]
		for item in list:
			item[k0] -= by
			item[k1] -= by
		return
	for item in list:
		for k in keys:
			item[k] -= by
