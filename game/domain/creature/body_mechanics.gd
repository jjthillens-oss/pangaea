extends RefCounted
## What a body can do, derived from its anatomy (PROPOSED): hip height, foot rest positions, reach, the speed and
## turn envelope, and acceleration limits. Pure rules: no scene or file access.
##
## Body-local axes: +X right, +Y up, -Z forward. The body origin sits on the ground under the body centre, so a hip
## at (x, 0, z) in the body data is at (x, hip_height, z) here.
##
## Uneven legs (owner direction 2026-10-24: walking must follow leg sizes, like an ape on long arms or a frog on long
## hind legs): every leg stands at stance_height_ratio of its own length. A line through those heights along the body
## gives hip_height (its height at the hips' centre) and rest_pitch, the body's standing tilt (positive lifts the
## front), within MAX_REST_PITCH_DEG. Legs keep their hips in the untilted body frame; the planner tilts the body.

const EPS := 1e-9
## The steepest standing tilt uneven legs give a body (PROPOSED; a gorilla knuckle-walks at about 20 degrees).
const MAX_REST_PITCH_DEG := 30.0

var name := ""
var table: RefCounted
var hip_height := 0.0
## The body's standing tilt about +X from uneven legs (radians, positive lifts the front); see the header.
var rest_pitch := 0.0
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
	_fit_stance(m, body["legs"], gait_table.stance_height_ratio)
	var tilt := Basis(Vector3.RIGHT, m.rest_pitch)
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
			"rest": _rest_point(hip, tilt, m.hip_height, side * gait_table.foot_splay_ratio * length),
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


## Sets m.hip_height and m.rest_pitch from the legs' standing heights (ratio x length) by a least-squares line over
## the hips' z (see the header). Even legs, or legs all at one z, give no tilt.
static func _fit_stance(m: RefCounted, legs: Array, ratio: float) -> void:
	var n := float(legs.size())
	if n == 0.0:
		return
	var mz := 0.0
	var mh := 0.0
	for leg in legs:
		mz += float((leg["hip"] as Array)[2])
		mh += ratio * (float(leg["upper"]) + float(leg["lower"]))
	mz /= n
	mh /= n
	var szz := 0.0
	var szh := 0.0
	for leg in legs:
		var dz := float((leg["hip"] as Array)[2]) - mz
		szz += dz * dz
		szh += dz * (ratio * (float(leg["upper"]) + float(leg["lower"])) - mh)
	var slope := szh / szz if szz > EPS else 0.0
	# Height at the hips' centre (z = 0 by construction of the gait origin), and the tilt: height grows towards -Z
	# (the front) when the slope is negative.
	m.hip_height = mh - slope * mz
	var limit := deg_to_rad(MAX_REST_PITCH_DEG)
	m.rest_pitch = clampf(atan(-slope), -limit, limit)


## A foot's rest point on the ground under its hip as the tilted body carries it, `splay` out to the side.
static func _rest_point(hip: Vector3, tilt: Basis, hip_height: float, splay: float) -> Vector3:
	var posed := tilt * (hip - Vector3(0.0, hip_height, 0.0))
	return Vector3(posed.x + splay, 0.0, posed.z)


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
