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
## front), within MAX_REST_PITCH_DEG. A hip set higher or lower on the body than the hips' centre (an ape's shoulder
## above its hip) counts against its leg's height, so a sitting-up body leans onto long arms. Should the tilt cap leave
## a hip above stance_height_max_ratio of its leg, the whole body sits lower. Legs keep their hips in the untilted body
## frame; the planner tilts the body. Speeds and strides scale with gait_height, the lowest standing hip, so the
## shortest legs set the pace they can keep their feet under (on even legs it is hip_height).
##
## Bound (gait_table.gd): a body on four legs whose hind legs are bound_hind_ratio times its front legs' length or
## more (a frog, a rabbit) is `long_hind`, and its bands use their long_hind_pattern when they name one.

const EPS := 1e-9
## The steepest standing tilt uneven legs give a body (PROPOSED; a gorilla knuckle-walks at about 20 degrees).
const MAX_REST_PITCH_DEG := 30.0

var name := ""
var table: RefCounted
var hip_height := 0.0
## The lowest hip's standing height: the height the Froude number, the stride and the top speed use (see the header).
var gait_height := 0.0
## The body's standing tilt about +X from uneven legs (radians, positive lifts the front); see the header.
var rest_pitch := 0.0
## One entry per leg: {side: -1 left / +1 right, k: index front to back on its side (by hip z, ties in input order), hip: Vector3, upper: float,
## lower: float, length: float, reach: float, rest: Vector3 (foot rest point on the ground), pole: Vector3 (which
## way the knee points, body-local, in leg lengths from the hip)}.
var legs: Array = []
var legs_per_side := 0
## Four legs with the hind pair much longer than the front (see the header): bands use their long_hind_pattern.
var long_hind := false
## Largest hip distance from the body's vertical axis.
var hip_radius_max := 0.0
## Top hip speed over the ground (m/s): the speed at the table's top Froude number on gait_height.
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
	var ranks := _front_to_back_ranks(body["legs"])
	for li in (body["legs"] as Array).size():
		var leg: Dictionary = body["legs"][li]
		var side := -1 if String(leg["side"]) == "L" else 1
		var hip_xz: Array = leg["hip"]
		var hip := Vector3(float(hip_xz[0]), m.hip_height + float(hip_xz[1]), float(hip_xz[2]))
		var length := float(leg["upper"]) + float(leg["lower"])
		m.legs.append({
			"side": side,
			"k": ranks[li],
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
	m.gait_height = INF
	for leg in m.legs:
		m.gait_height = minf(m.gait_height, m.hip_height + (tilt * ((leg["hip"] as Vector3)
				- Vector3(0.0, m.hip_height, 0.0))).y)
	m.long_hind = _is_long_hind(m.legs, gait_table.bound_hind_ratio)
	m.v_top = sqrt(gait_table.fr_top() * gait_table.g_eff * m.gait_height)
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
	# Each hip wants the body origin's line at its own standing height less its offset above the hips' centre.
	var mz := 0.0
	var mh := 0.0
	for leg in legs:
		mz += float((leg["hip"] as Array)[2])
		mh += _origin_height_wanted(leg, ratio)
	mz /= n
	mh /= n
	var szz := 0.0
	var szh := 0.0
	for leg in legs:
		var dz := float((leg["hip"] as Array)[2]) - mz
		szz += dz * dz
		szh += dz * (_origin_height_wanted(leg, ratio) - mh)
	var slope := szh / szz if szz > EPS else 0.0
	# Height at the hips' centre (z = 0 by construction of the gait origin), and the tilt: height grows towards -Z
	# (the front) when the slope is negative.
	m.hip_height = mh - slope * mz
	var limit := deg_to_rad(MAX_REST_PITCH_DEG)
	m.rest_pitch = clampf(atan(-slope), -limit, limit)
	# Sit lower when the capped tilt leaves a hip standing too tall for its leg.
	var tilt := Basis(Vector3.RIGHT, m.rest_pitch)
	var excess := 0.0
	for leg in legs:
		var hip: Array = leg["hip"]
		var posed := tilt * Vector3(float(hip[0]), float(hip[1]), float(hip[2]))
		var length := float(leg["upper"]) + float(leg["lower"])
		excess = maxf(excess, m.hip_height + posed.y - m.table.stance_height_max_ratio * length)
	m.hip_height -= excess


static func _origin_height_wanted(leg: Dictionary, ratio: float) -> float:
	return ratio * (float(leg["upper"]) + float(leg["lower"])) - float((leg["hip"] as Array)[1])


## Each leg's index front to back among the legs on its side: by hip z, ties in input order.
static func _front_to_back_ranks(legs: Array) -> PackedInt32Array:
	var ranks := PackedInt32Array()
	for i in legs.size():
		var zi := float((legs[i]["hip"] as Array)[2])
		var r := 0
		for j in legs.size():
			if j == i or String(legs[j]["side"]) != String(legs[i]["side"]):
				continue
			var zj := float((legs[j]["hip"] as Array)[2])
			if zj < zi or (zj == zi and j < i):
				r += 1
		ranks.append(r)
	return ranks


## Two legs a side, and the shorter hind leg at least `ratio` times the longer front leg.
static func _is_long_hind(legs: Array, ratio: float) -> bool:
	if legs.size() != 4:
		return false
	var front := 0.0
	var hind := INF
	for leg in legs:
		if leg["k"] == 0:
			front = maxf(front, leg["length"])
		else:
			hind = minf(hind, leg["length"])
	return front > EPS and hind >= ratio * front


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


## Froude number for a hip ground speed, on gait_height.
func froude(speed: float) -> float:
	return speed * speed / (table.g_eff * gait_height)


## Phase offset of a leg in a pattern. A leg lifts when its phase (cycle phase + offset) reaches the duty factor, so a
## larger offset lifts earlier. "walk": a wave from the back leg forward on each side, then the other side, so four
## legs step left hind, left fore, right hind, right fore. "trot": neighbours alternate, giving diagonal pairs on four
## legs and tripods on six. "bound": both legs of a pair together, the front pair bound_pair_lag of a cycle ahead, so
## the hind pair stands after it and pushes off last (gait_table.gd).
func pattern_offset(leg_index: int, pattern: String) -> float:
	var leg: Dictionary = legs[leg_index]
	var right := 1 if leg["side"] > 0 else 0
	if pattern == "walk":
		return fposmod(float(leg["k"]) / float(2 * legs_per_side) + 0.5 * right, 1.0)
	if pattern == "bound":
		return table.bound_pair_lag if leg["k"] == 0 else 0.0
	return 0.5 * float((leg["k"] + right) % 2)


## The pattern this body uses in band `band_index`: the band's long_hind_pattern for a long_hind body, else its pattern.
func band_pattern(band_index: int) -> String:
	var b: Dictionary = table.bands[band_index]
	if long_hind and String(b.get("long_hind_pattern", "")) != "":
		return String(b["long_hind_pattern"])
	return String(b["pattern"])
