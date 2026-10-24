extends RefCounted
## What a body can do, derived from its anatomy (PROPOSED): hip height, foot rest positions, reach, the speed and
## turn envelope, and acceleration limits. Pure rules: no scene or file access.
##
## Body-local axes: +X right, +Y up, -Z forward. The body origin sits on the ground under the body centre, so a hip
## at (x, 0, z) in the body data is at (x, hip_height, z) here.

const EPS := 1e-9

var name := ""
var table: RefCounted
var hip_height := 0.0
## One entry per leg: {side: -1 left / +1 right, k: index front to back on its side, hip: Vector3, upper: float,
## lower: float, length: float, reach: float, rest: Vector3 (foot rest point on the ground), pole: Vector3 (which
## way the knee points, body-local, in leg lengths from the hip)}.
var legs: Array = []
var legs_per_side := 0
## Largest hip distance from the body's vertical axis.
var hip_radius_max := 0.0
## Top hip speed over the ground (m/s): the speed at the table's top Froude number.
var v_top := 0.0
## Fastest turn in place (rad/s): the outermost hip moves at v_top.
var omega_max := 0.0
var accel_max := 0.0
var angular_accel_max := 0.0


static func create(body_name: String, body: Dictionary, gait_table: RefCounted) -> RefCounted:
	var m = load("res://game/domain/creature/body_mechanics.gd").new()
	m.name = body_name
	m.table = gait_table
	var min_len := INF
	for leg in body["legs"]:
		min_len = minf(min_len, float(leg["upper"]) + float(leg["lower"]))
	m.hip_height = gait_table.stance_height_ratio * min_len
	var counts := {-1: 0, 1: 0}
	for leg in body["legs"]:
		var side := -1 if String(leg["side"]) == "L" else 1
		var hip_xz: Array = leg["hip"]
		var hip := Vector3(float(hip_xz[0]), m.hip_height + float(hip_xz[1]), float(hip_xz[2]))
		var length := float(leg["upper"]) + float(leg["lower"])
		m.legs.append({
			"side": side,
			"k": counts[side],
			"hip": hip,
			"upper": float(leg["upper"]),
			"lower": float(leg["lower"]),
			"length": length,
			"reach": gait_table.reach_margin * length,
			"rest": Vector3(hip.x + side * gait_table.foot_splay_ratio * length, 0.0, hip.z),
			"pole": _pole_direction(String(leg.get("knee", "forward")), side),
		})
		counts[side] += 1
		m.hip_radius_max = maxf(m.hip_radius_max, Vector2(hip.x, hip.z).length())
	m.legs_per_side = maxi(counts[-1], counts[1])
	m.v_top = sqrt(gait_table.fr_top() * gait_table.g_eff * m.hip_height)
	m.omega_max = m.v_top / m.hip_radius_max
	# Reach top speed in `accel_cycles` cycles of the top gait. v_top^2 / (lambda_top * h) = Fr_top * g / lambda_top,
	# so the acceleration limit is the same for every leg length.
	m.accel_max = gait_table.fr_top() * gait_table.g_eff / (gait_table.accel_cycles
			* gait_table.rel_stride(gait_table.fr_top()))
	m.angular_accel_max = m.accel_max / m.hip_radius_max
	return m


## "forward" and "back" knees point along the body, a little below the hip; "out" knees point sideways and up, like
## an insect's.
static func _pole_direction(knee: String, side: int) -> Vector3:
	match knee:
		"back":
			return Vector3(0.0, -0.25, 1.0)
		"out":
			return Vector3(side * 1.0, 0.6, 0.0)
	return Vector3(0.0, -0.25, -1.0)


## Fastest hip speed over the ground when the body moves forward at `v` and turns at `omega` (about +Y).
func hip_speed_max(v: float, omega: float) -> float:
	var s := 0.0
	for leg in legs:
		var hip: Vector3 = leg["hip"]
		s = maxf(s, Vector2(omega * hip.z, -v - omega * hip.x).length())
	return s


## Scales (v, omega) down together so no hip outruns v_top.
func clamp_to_envelope(v: float, omega: float) -> Vector2:
	var s := hip_speed_max(v, omega)
	if s <= v_top or s < EPS:
		return Vector2(v, omega)
	var k := v_top / s
	return Vector2(v * k, omega * k)


## Froude number for a hip ground speed.
func froude(speed: float) -> float:
	return speed * speed / (table.g_eff * hip_height)


## Phase offset of a leg in a pattern. A leg lifts when its phase (cycle phase + offset) reaches the duty factor, so a
## larger offset lifts earlier. "walk": a wave from the back leg forward on each side, then the other side, so four
## legs step left hind, left fore, right hind, right fore. "trot": neighbours alternate, giving diagonal pairs on four
## legs and tripods on six.
func pattern_offset(leg_index: int, pattern: String) -> float:
	var leg: Dictionary = legs[leg_index]
	var right := 1 if leg["side"] > 0 else 0
	if pattern == "walk":
		return fposmod(float(leg["k"]) / float(2 * legs_per_side) + 0.5 * right, 1.0)
	return 0.5 * float((leg["k"] + right) % 2)
