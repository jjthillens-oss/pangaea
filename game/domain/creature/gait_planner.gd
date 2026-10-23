extends RefCounted
## Gait planner (PROPOSED). Moves one body over flat ground and decides where every foot is, in world space, from a
## throttle and a turn input. Pure rules: no scene or file access, deterministic for the same inputs and time steps.
##
## One gait clock per body: the cycle period is T = rel_stride(Fr) * h / s, with s the fastest hip speed over the
## ground and Fr = s^2 / (g * h). Each leg runs its own phase, pulled towards clock + pattern offset, so a pattern
## change blends in over a cycle or two. A stance foot stays fixed in the world; it lifts when its phase reaches the
## duty factor, or early if the hip has moved out of reach. A swinging foot aims at where its rest point will be at
## mid-stance, predicted from the current speed and turn rate.

const STANCE := 0
const SWING := 1
const EPS := 1e-9

var mech: RefCounted
var table: RefCounted

## Body state in world space. Yaw is about +Y; yaw 0 faces -Z.
var position := Vector3.ZERO
var yaw := 0.0
var v := 0.0
var omega := 0.0

var cycle_phase := 0.0
var band := 0
var duty := 0.0
var froude_now := 0.0
var period := INF

## Per leg, in the order of mech.legs.
var foot: Array[Vector3] = []
var state := PackedInt32Array()
var leg_phase := PackedFloat64Array()
## Each leg's phase speed relative to the clock (1 when in step with its pattern).
var leg_rate := PackedFloat64Array()
var swing_from: Array[Vector3] = []
var swing_u := PackedFloat64Array()
var swing_time := PackedFloat64Array()

var idle_time := 0.0

## Posture (PROPOSED): the body bobs, pitches with acceleration, banks into turns and sways at a walk, about the
## point at hip height above the body origin. It never lifts a hip above its rest height, so it cannot overstretch a
## leg. bob is a height change in metres (never above 0).
var bob := 0.0
var pitch := 0.0
var roll := 0.0
var sway := 0.0
var posture_basis := Basis()
var _pose := Transform3D(Basis(), Vector3.ZERO)

## Per-leg values copied out of mech.legs once, so the per-frame loop reads arrays instead of dictionaries.
var _hip := PackedVector3Array()
var _rest := PackedVector3Array()
var _length := PackedFloat64Array()
var _reach := PackedFloat64Array()
## _offsets[band][leg]: pattern phase offset.
var _offsets: Array[PackedFloat64Array] = []
var _v_prev := 0.0

## Telemetry.
var time := 0.0
var cycles := 0.0
var steps := 0
var early_lifts := 0
var settle_steps := 0
var distance := 0.0
var turned := 0.0
## Largest hip-to-foot distance over leg length seen on a stance foot.
var max_stance_reach_ratio := 0.0


static func create(mechanics: RefCounted, start_position := Vector3.ZERO, start_yaw := 0.0) -> RefCounted:
	var p = load("res://game/domain/creature/gait_planner.gd").new()
	p.mech = mechanics
	p.table = mechanics.table
	p.position = start_position
	p.yaw = start_yaw
	p.duty = p.table.bands[0]["duty"]
	p._pose = Transform3D(Basis(), Vector3(0.0, mechanics.hip_height, 0.0))
	for leg in mechanics.legs:
		p._hip.append(leg["hip"])
		p._rest.append(leg["rest"])
		p._length.append(leg["length"])
		p._reach.append(leg["reach"])
	for b in p.table.bands:
		var offs := PackedFloat64Array()
		for i in mechanics.legs.size():
			offs.append(mechanics.pattern_offset(i, b["pattern"]))
		p._offsets.append(offs)
	for i in mechanics.legs.size():
		var rest: Vector3 = p.rest_world(i)
		p.foot.append(rest)
		p.state.append(STANCE)
		p.leg_phase.append(mechanics.pattern_offset(i, p.table.bands[0]["pattern"]))
		p.leg_rate.append(1.0)
		p.swing_from.append(rest)
		p.swing_u.append(0.0)
		p.swing_time.append(0.0)
	return p


## Advances the body and its feet by `dt` seconds. `throttle` and `turn` are in [-1, 1]; positive turn is to the left.
func step(dt: float, throttle: float, turn: float) -> void:
	time += dt
	var cmd: Vector2 = mech.clamp_to_envelope(clampf(throttle, -1.0, 1.0) * mech.v_top,
			clampf(turn, -1.0, 1.0) * mech.omega_max)
	v = move_toward(v, cmd.x, mech.accel_max * dt)
	omega = move_toward(omega, cmd.y, mech.angular_accel_max * dt)
	var clamped: Vector2 = mech.clamp_to_envelope(v, omega)
	v = clamped.x
	omega = clamped.y

	_update_posture(dt)
	var moved := body_after(dt)
	distance += absf(v) * dt
	turned += absf(omega) * dt
	position = moved[0]
	yaw = moved[1]

	var s: float = mech.hip_speed_max(v, omega)
	froude_now = mech.froude(s)
	band = table.pick_band(band, froude_now)
	duty = table.bands[band]["duty"]
	var offsets: PackedFloat64Array = _offsets[band]
	period = table.rel_stride(froude_now) * mech.hip_height / s if s > EPS else INF
	var dphi := dt / period if s > EPS else 0.0
	cycle_phase = fposmod(cycle_phase + dphi, 1.0)
	cycles += dphi
	idle_time = idle_time + dt if s <= EPS else 0.0

	var next_body := body_after(dt)
	var next_origin: Vector3 = next_body[0]
	var next_basis := Basis(Vector3.UP, next_body[1])
	var basis := Basis(Vector3.UP, yaw)

	for i in foot.size():
		var prev := leg_phase[i]
		var err := wrapf(cycle_phase + offsets[i] - prev, -0.5, 0.5)
		leg_rate[i] = clampf(1.0 + table.phase_coupling * err, 0.5, 1.5)
		var next := prev + dphi * leg_rate[i]
		var reached_duty := dphi > 0.0 and prev < duty and next >= duty
		leg_phase[i] = fposmod(next, 1.0)
		if state[i] == STANCE:
			var hip_local := _posed_hip(i)
			var dist := foot[i].distance_to(position + basis * hip_local)
			max_stance_reach_ratio = maxf(max_stance_reach_ratio, dist / _length[i])
			if reached_duty:
				_lift(i)
			elif foot[i].distance_to(next_origin + next_basis * hip_local) > _reach[i]:  # lift now, not overstretch
				early_lifts += 1
				_lift(i)
		else:
			_advance_swing(i, dt)

	if idle_time > table.settle_idle_time and not state.has(SWING):
		for i in foot.size():
			if foot[i].distance_to(rest_world(i)) > table.settle_threshold_ratio * _length[i]:
				settle_steps += 1
				_lift(i)
				break


## Body position and yaw after `t` more seconds at the current speed and turn rate (an exact arc).
func body_after(t: float) -> Array:
	var y := yaw + omega * t
	var p := position
	if absf(omega) < EPS:
		p += Vector3(-sin(yaw), 0.0, -cos(yaw)) * v * t
	else:
		p += Vector3(cos(y) - cos(yaw), 0.0, sin(yaw) - sin(y)) * (v / omega)
	return [p, y]


func hip_world(i: int) -> Vector3:
	return position + Basis(Vector3.UP, yaw) * _posed_hip(i)


func rest_world(i: int) -> Vector3:
	return position + Basis(Vector3.UP, yaw) * _rest[i]


func predicted_rest(i: int, t: float) -> Vector3:
	var future := body_after(t)
	return (future[0] as Vector3) + Basis(Vector3.UP, future[1]) * _rest[i]


## The body's pose relative to its ground origin: posture rotation about the point at hip height, plus bob and sway.
## The root bone of a rig takes exactly this transform.
func body_pose_local() -> Transform3D:
	return Transform3D(posture_basis, Vector3(sway, mech.hip_height + bob, 0.0))


func _posed_hip(i: int) -> Vector3:
	return _pose * (_hip[i] - Vector3(0.0, mech.hip_height, 0.0))


func _update_posture(dt: float) -> void:
	var g: float = table.g_eff
	var h: float = mech.hip_height
	var a_long := (v - _v_prev) / dt if dt > 0.0 else 0.0
	_v_prev = v
	var k := 1.0 - exp(-dt / table.posture_smoothing)
	var target_pitch := clampf(-table.pitch_gain * a_long / g, -deg_to_rad(table.pitch_max_deg),
			deg_to_rad(table.pitch_max_deg))
	var target_roll := clampf(table.roll_gain * atan(v * omega / g), -deg_to_rad(table.roll_max_deg),
			deg_to_rad(table.roll_max_deg))
	pitch = lerpf(pitch, target_pitch, k)
	roll = lerpf(roll, target_roll, k)
	posture_basis = Basis(Vector3.BACK, roll) * Basis(Vector3.RIGHT, pitch)
	# Two dips per cycle (one per stance of each diagonal pair or tripod), deeper at speed.
	var gait_strength := clampf(froude_now / 1.0, 0.0, 1.0)
	bob = -table.bob_ratio * h * gait_strength * (0.5 - 0.5 * cos(TAU * 2.0 * cycle_phase))
	# At a walk the body shifts a little towards the side that is standing.
	var walk_strength := clampf(froude_now / 0.2, 0.0, 1.0) if table.bands[band]["pattern"] == "walk" else 0.0
	sway = table.sway_ratio * h * walk_strength * sin(TAU * cycle_phase)
	# Never lift a hip above its rest height: lower the body by the highest hip's rise.
	var rise := 0.0
	for i in _hip.size():
		rise = maxf(rise, (posture_basis * (_hip[i] - Vector3(0.0, h, 0.0))).y + bob - (_hip[i].y - h))
	bob -= rise
	_pose = body_pose_local()


func is_finite_state() -> bool:
	if not (position.is_finite() and is_finite(yaw) and is_finite(v) and is_finite(omega)):
		return false
	for f in foot:
		if not f.is_finite():
			return false
	return true


## One line of foot positions, for determinism checks.
func log_line() -> String:
	var parts := PackedStringArray(["%.4f" % time, "%.6f" % position.x, "%.6f" % position.z, "%.6f" % yaw])
	for i in foot.size():
		parts.append("%d" % state[i])
		parts.append("%.6f,%.6f,%.6f" % [foot[i].x, foot[i].y, foot[i].z])
	return " ".join(parts)


func _lift(i: int) -> void:
	state[i] = SWING
	swing_from[i] = foot[i]
	swing_u[i] = 0.0
	var natural: float = (1.0 - duty) * period / leg_rate[i] if is_finite(period) else table.max_swing_time
	swing_time[i] = clampf(natural, table.min_swing_time, table.max_swing_time)


## Where a swinging foot should land, `remaining` seconds from now: its rest point at mid-stance, pulled back towards
## the rest point at landing if that would put it out of reach.
func _landing_target(i: int, remaining: float) -> Vector3:
	var normal_stance: float = duty * period / leg_rate[i] if is_finite(period) else 0.0
	var stance := minf(_stance_time_after_landing(i, remaining), normal_stance)
	var target := predicted_rest(i, remaining + 0.5 * stance)
	var land := body_after(remaining)
	var basis := Basis(Vector3.UP, land[1])
	var hip: Vector3 = (land[0] as Vector3) + basis * _posed_hip(i)
	var rest: Vector3 = (land[0] as Vector3) + basis * _rest[i]
	var reach: float = _reach[i]
	if target.distance_to(hip) <= reach:
		return target
	# Largest t in [0, 1] with |rest + t * (target - rest) - hip| <= reach; the rest point itself is in reach.
	var a := rest - hip
	var d := target - rest
	var dd := d.length_squared()
	var ad := a.dot(d)
	var t := (-ad + sqrt(maxf(0.0, ad * ad - dd * (a.length_squared() - reach * reach)))) / dd
	return rest + d * clampf(t, 0.0, 1.0)


## How long the foot will stand once it lands `remaining` seconds from now: until its phase next reaches the duty
## factor. Aiming the swing at the rest point for half of this centres the stance sweep on the rest point.
func _stance_time_after_landing(i: int, remaining: float) -> float:
	if not is_finite(period):
		return 0.0
	var rate := period / leg_rate[i]  # seconds per unit of this leg's phase
	var q := leg_phase[i] if leg_phase[i] >= duty else leg_phase[i] + 1.0
	var at_landing := q + remaining / rate
	return maxf(0.0, (1.0 + duty - at_landing) * rate)


func _advance_swing(i: int, dt: float) -> void:
	swing_u[i] = minf(1.0, swing_u[i] + dt / swing_time[i])
	var u := swing_u[i]
	var remaining := (1.0 - u) * swing_time[i]
	var target := _landing_target(i, remaining)
	if u >= 1.0:
		foot[i] = target
		state[i] = STANCE
		steps += 1
		return
	var p := swing_from[i].lerp(target, smoothstep(0.0, 1.0, u))
	p.y = lerpf(swing_from[i].y, target.y, u) + sin(PI * u) * table.swing_lift_ratio * _length[i]
	foot[i] = p
