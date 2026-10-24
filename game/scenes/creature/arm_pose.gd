extends RefCounted
## The rest pose of an arm on a walker (PROPOSED): a limb the gait planner does not own hangs from its attach joint
## with the elbow bent a little forward, its tip just above the ground when the arm is long enough to reach it, and
## swings with the gait's cadence so it feels alive. Geometry only, in metres: the walker rig turns the result into
## bone poses with two_bone() and arc(). No scene or file access.

## The hand hangs this far down the arm's length, so the elbow keeps a slight bend.
const HANG_RATIO := 0.9
## The hand sits this far out from the shoulder, so the arm clears the flank.
const OUT_RATIO := 0.1
## Forward swing per metre of arm at full speed, opposite on the two sides, once per gait cycle.
const SWING_RATIO := 0.12
## The slow idle sway per metre of arm, on its own clock.
const IDLE_RATIO := 0.03
const IDLE_PERIOD_S := 2.8
## The elbow points this far out to the side of straight forward.
const POLE_OUT := 0.4


## Where the hand and the elbow aim, in the world: {target: Vector3, pole: Vector3}. `shoulder` is the arm's root in
## the world, `heading` the body's yaw basis, `side` -1 left or 1 right, `length` the arm's joint-to-joint length,
## `floor_y` the lowest height the tip may take (the ground plus what the tip must clear), `phase` the gait's cycle
## phase (0..1), `speed` the body's speed as a share of its top speed and `time` the planner's clock.
static func hang(shoulder: Vector3, heading: Basis, side: float, length: float, floor_y: float, phase: float,
		speed: float, time: float) -> Dictionary:
	var forward := heading * Vector3.FORWARD
	var out := heading * Vector3(signf(side) if side != 0.0 else 1.0, 0.0, 0.0)
	var drop := clampf(shoulder.y - floor_y, 0.0, HANG_RATIO * length)
	var side_phase := 0.0 if side < 0.0 else 0.5
	var swing: float = length * (SWING_RATIO * speed * sin(TAU * (phase + side_phase))
			+ IDLE_RATIO * sin(TAU * (time / IDLE_PERIOD_S + 0.4 * side_phase)))
	return {"target": shoulder + Vector3.DOWN * drop + forward * swing + out * OUT_RATIO * length,
			"pole": shoulder + forward * length + out * POLE_OUT * length}


## Bone pose rotations [root, middle] that put a two-bone chain's tip at `target` with its elbow towards `pole`, all
## in the root's parent space with the root at the origin. `mid_rest` is the middle joint's rest offset from the root
## and `tip_rest` the tip's; the piece past the middle joint keeps its rest shape, as the leg IK treats it. A target
## out of reach gets a straight arm towards it; one too close folds the elbow.
static func two_bone(mid_rest: Vector3, tip_rest: Vector3, target: Vector3, pole: Vector3) -> Array:
	var a := mid_rest.length()
	var b := (tip_rest - mid_rest).length()
	var d := target.length()
	var u := target / d if d > 1e-6 else Vector3.DOWN
	var reach := clampf(d, absf(a - b) + 1e-4, a + b - 1e-4)
	var x := (a * a - b * b + reach * reach) / (2.0 * reach)
	var y := sqrt(maxf(a * a - x * x, 0.0))
	var n := pole - u * pole.dot(u)
	if n.length_squared() < 1e-8:
		n = u.cross(Vector3.RIGHT)
		if n.length_squared() < 1e-8:
			n = u.cross(Vector3.FORWARD)
	n = n.normalized()
	var mid := u * x + n * y
	var q_root := arc(mid_rest, mid)
	var lower_now: Vector3 = q_root * (tip_rest - mid_rest)
	var q_mid_global := arc(lower_now, u * reach - mid)
	return [q_root, q_root.inverse() * q_mid_global * q_root]


## The shortest rotation taking direction `from` to direction `to`; identity when either is zero.
static func arc(from: Vector3, to: Vector3) -> Quaternion:
	if from.length_squared() < 1e-12 or to.length_squared() < 1e-12:
		return Quaternion()
	var f := from.normalized()
	var t := to.normalized()
	if f.dot(t) < -0.9999:
		var axis := f.cross(Vector3.UP)
		if axis.length_squared() < 1e-8:
			axis = f.cross(Vector3.RIGHT)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(f, t)
