extends RefCounted
## PROPOSED flat-ground drive for bodies the two-bone gait planner cannot move. A spine-only body
## uses a head-to-tail travelling wave with short alternating belly contacts. A body with short,
## two-joint legs shuffles: pairs lift in alternation, while the other feet remain on the ground.
## This is deterministic kinematics, not a friction or terrain simulation.

const DT := 1.0 / 60.0
const WAVE_HZ := 1.25
const WAVE_COUNT := 1.25
const WAVE_DEG := 8.0
const BELLY_DUTY := 0.18
const SHUFFLE_HZ := 2.0
const FOOT_DUTY := 0.56

var desc: RefCounted
var mode := ""
var position := Vector3.ZERO
var yaw := 0.0
var v := 0.0
var omega := 0.0
var time := 0.0
var phase := 0.0
var length_m := 0.0
var segments := 0
var leg_length_m := 0.0
var root_lift_m := 0.0
var speed_top := 0.0
var distance := 0.0
var max_belly_slip_ratio := 0.0
var max_foot_slip_ratio := 0.0
var max_pitch := 0.0
var max_roll := 0.0
var root_pitch := 0.0
var root_roll := 0.0
var belly_anchor: Array[Vector3] = []
var belly_planted := PackedByteArray()
var foot_anchor: Array[Vector3] = []
var foot_planted := PackedByteArray()
var foot_rest := PackedVector3Array()
var foot_target_world: Array[Vector3] = []
var max_swing_travel_m := 0.0


static func create(description: RefCounted) -> RefCounted:
	var p = load("res://domain/ground_drive.gd").new()
	p.desc = description
	p.segments = description.vertebrae.size()
	for i in p.segments - 1:
		p.length_m += description.position_m(i).distance_to(description.position_m(i + 1))
	var chains: Array = description.limb_chains()
	if chains.is_empty():
		p.mode = "slither"
		p.speed_top = speed_for_slither(p.length_m, p.segments)
		p.root_lift_m = description.max_radius_m()
		for i in p.segments:
			p.belly_anchor.append(Vector3.ZERO)
			p.belly_planted.append(0)
	else:
		var shortest := INF
		var all_stubs := true
		var lowest := INF
		for chain in chains:
			var pts: PackedVector3Array = chain["points"]
			if pts.size() != 2:
				all_stubs = false
				break
			var reach := pts[0].distance_to(pts[1])
			shortest = minf(shortest, reach)
			lowest = minf(lowest, pts[1].y)
			p.foot_rest.append(pts[1])
		if all_stubs and shortest <= maxf(0.15, 0.65 * p.length_m):
			p.mode = "shuffle"
			p.leg_length_m = shortest
			p.speed_top = clampf(0.4 * shortest, 0.005, 0.15)
			p.root_lift_m = -lowest
			for i in p.foot_rest.size():
				p.foot_anchor.append(Vector3.ZERO)
				p.foot_target_world.append(Vector3.ZERO)
				p.foot_planted.append(0)
	return p


## Longer bodies have a longer useful lateral stroke; more segments provide more alternating
## contacts. Both contributions have caps so a very long or finely segmented body cannot run away.
static func speed_for_slither(body_length_m: float, segment_count: int) -> float:
	var length_factor := clampf(body_length_m, 0.4, 4.0)
	var contact_factor := 0.45 + 0.55 * clampf(float(segment_count - 3) / 21.0, 0.0, 1.0)
	return minf(0.55, 0.16 * length_factor * contact_factor)


func step(dt: float, throttle: float, turn: float) -> void:
	if dt <= 0.0 or mode.is_empty():
		return
	time += dt
	var requested := clampf(throttle, -1.0, 1.0) * speed_top
	v = move_toward(v, requested, 2.0 * speed_top * dt)
	var turn_rate := 0.7 if mode == "slither" else 0.4
	omega = move_toward(omega, clampf(turn, -1.0, 1.0) * turn_rate, 2.0 * dt)
	yaw += omega * dt
	position += Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, -v * dt)
	distance += absf(v) * dt
	phase = fposmod(phase + dt * (WAVE_HZ if mode == "slither" else SHUFFLE_HZ), 1.0)
	if mode == "slither":
		_step_belly()
	else:
		_step_feet()
	_sample_root_orientation()


func posed_root_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * Basis.from_euler(Vector3(root_pitch, 0.0, root_roll)),
			position + Vector3(0.0, body_lift(), 0.0))


func _sample_root_orientation() -> void:
	# Remove heading before measuring the root's local pitch and roll.
	var up := Basis(Vector3.UP, -yaw) * (posed_root_transform().basis * Vector3.UP)
	max_pitch = maxf(max_pitch, absf(atan2(up.z, up.y)))
	max_roll = maxf(max_roll, absf(atan2(up.x, up.y)))


func within_stability_gate() -> bool:
	return max_pitch <= deg_to_rad(5.0) and max_roll <= deg_to_rad(5.0)


## Relative rotation of one vertebra, travelling from vertebra 0 toward the tail.
func spine_angle(i: int) -> float:
	if mode != "slither" or i == 0:
		return 0.0
	var u := float(i) / float(maxi(1, segments - 1))
	return deg_to_rad(WAVE_DEG) * sin(TAU * (phase - WAVE_COUNT * u))


func limb_angle(i: int) -> float:
	if mode != "shuffle":
		return 0.0
	var u := fposmod(phase + (0.5 if i % 2 == 1 else 0.0), 1.0)
	if u < FOOT_DUTY:
		return 0.0
	return deg_to_rad(15.0) * sin(PI * (u - FOOT_DUTY) / (1.0 - FOOT_DUTY))


func body_lift() -> float:
	if mode == "shuffle":
		return root_lift_m + 0.05 * leg_length_m * maxf(0.0, sin(TAU * 2.0 * phase))
	return root_lift_m


func _step_belly() -> void:
	for i in segments:
		var u := float(i) / float(maxi(1, segments - 1))
		var contact_phase := fposmod(phase - WAVE_COUNT * u, 1.0)
		var planted := contact_phase < BELLY_DUTY
		var rest: Vector3 = desc.position_m(i)
		var sway := Vector3(0.055 * length_m * sin(TAU * contact_phase), 0.0, 0.0)
		var at := position + Basis(Vector3.UP, yaw) * (rest + sway)
		if planted:
			if belly_planted[i] == 0:
				belly_anchor[i] = at
			else:
				max_belly_slip_ratio = maxf(max_belly_slip_ratio,
						at.distance_to(belly_anchor[i]) / maxf(length_m, 0.001))
		belly_planted[i] = 1 if planted else 0


func _step_feet() -> void:
	for i in foot_rest.size():
		var u := fposmod(phase + (0.5 if i % 2 == 1 else 0.0), 1.0)
		var planted := u < FOOT_DUTY
		var at := position + Basis(Vector3.UP, yaw) * foot_rest[i]
		at.y = 0.0
		if planted:
			if foot_planted[i] == 0:
				foot_anchor[i] = foot_target_world[i] if time > DT else at
				foot_anchor[i].y = 0.0
			foot_target_world[i] = foot_anchor[i]
			max_foot_slip_ratio = maxf(max_foot_slip_ratio,
					foot_target_world[i].distance_to(foot_anchor[i]) / maxf(leg_length_m, 0.001))
		else:
			# The swing begins at the old ground anchor and finishes at a forward landing
			# target. The target is in world space, so stance remains planted as the root moves.
			var swing_u := (u - FOOT_DUTY) / (1.0 - FOOT_DUTY)
			var lead := Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0,
					-signf(v) * minf(0.3 * leg_length_m, absf(v) / SHUFFLE_HZ))
			var landing := at + lead
			var target := foot_anchor[i].lerp(landing, swing_u)
			target.y = sin(PI * swing_u) * 0.35 * leg_length_m
			foot_target_world[i] = target
			max_swing_travel_m = maxf(max_swing_travel_m,
					Vector2(target.x - foot_anchor[i].x, target.z - foot_anchor[i].z).length())
		foot_planted[i] = 1 if planted else 0


func is_finite_state() -> bool:
	if not (position.is_finite() and is_finite(yaw) and is_finite(v) and is_finite(omega)
			and is_finite(phase) and is_finite(max_belly_slip_ratio) and is_finite(max_foot_slip_ratio)):
		return false
	for at in belly_anchor:
		if not at.is_finite():
			return false
	for at in foot_anchor:
		if not at.is_finite():
			return false
	for at in foot_target_world:
		if not at.is_finite():
			return false
	return true
