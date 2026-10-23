extends RefCounted
## PROPOSED deterministic kinematic swimming. No ground contacts or physics forces.

const GaitBody := preload("res://domain/gait_body.gd")
const AQUATIC_PARTS := ["fin", "flipper", "tail_fluke"]

var desc: RefCounted
var mode := ""
var position := Vector3.ZERO
var yaw := 0.0
var v := 0.0
var omega := 0.0
var phase := 0.0
var cycles := 0.0
var length_m := 0.0
var speed_top := 0.0
var wave_hz := 0.0
var wave_count := 1.0
var amplitude := 0.0
var root_pitch := 0.0
var root_roll := 0.0
var max_pitch := 0.0
var max_roll := 0.0
var max_curvature := 0.0
var max_stance_slip_ratio := 0.0 # No stance exists in water.
var cycle_origin := Vector3.ZERO
var last_cycle_progress := 0.0
var cycle_progress_min := INF


static func aquatic(description: RefCounted, medium := "air") -> bool:
	if medium == "water":
		return true
	var has_part := false
	for part in description.parts:
		if AQUATIC_PARTS.has(String(part["type"])):
			has_part = true
	if not has_part or not GaitBody.from_description(description)["legs"].is_empty():
		return false
	# A two-joint stub that reaches below the belly is a ground leg too.
	for chain in description.limb_chains():
		var points: PackedVector3Array = chain["points"]
		if points[points.size() - 1].y < -description.max_radius_m():
			return false
	return true


static func create(description: RefCounted, medium := "air") -> RefCounted:
	var p = load("res://domain/swim_drive.gd").new()
	if not aquatic(description, medium):
		return p
	p.desc = description
	for i in description.vertebrae.size() - 1:
		p.length_m += description.position_m(i).distance_to(description.position_m(i + 1))
	p.length_m = maxf(p.length_m, 0.2)
	var tail := false
	var fins := 0
	for part in description.parts:
		if String(part["type"]) == "tail_fluke":
			tail = true
		elif ["fin", "flipper"].has(String(part["type"])):
			fins += 2 if bool(part.get("mirror", false)) else 1
	p.mode = "tail_wave" if tail or fins < 2 else "fin_stroke"
	p.speed_top = clampf(0.32 * p.length_m + 0.06 * fins, 0.12, 0.65)
	p.amplitude = deg_to_rad(clampf(5.0 + 5.0 / p.length_m, 7.0, 14.0))
	p.wave_hz = clampf(p.speed_top / maxf(0.55 * p.length_m, 0.1), 0.45, 2.0)
	p.cycle_origin = p.position
	return p


func step(dt: float, throttle: float, turn: float) -> void:
	if dt <= 0.0 or mode.is_empty():
		return
	var wanted := clampf(throttle, -1.0, 1.0) * speed_top
	v = move_toward(v, wanted, speed_top * 2.0 * dt)
	omega = move_toward(omega, clampf(turn, -1.0, 1.0) * 0.55, 2.0 * dt)
	yaw += omega * dt
	var forward := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	position += forward * v * dt
	# Buoyancy is neutral: no acceleration toward or away from a surface.
	root_pitch = deg_to_rad(4.0) * clampf(throttle, -1.0, 1.0)
	root_roll = deg_to_rad(4.0) * clampf(turn, -1.0, 1.0)
	var up := Basis(Vector3.UP, -yaw) * (posed_root_transform().basis * Vector3.UP)
	max_pitch = maxf(max_pitch, absf(atan2(up.z, up.y)))
	max_roll = maxf(max_roll, absf(atan2(up.x, up.y)))
	var old_cycle := floori(cycles)
	cycles += wave_hz * dt * clampf(absf(v) / speed_top, 0.25, 1.0)
	phase = fposmod(cycles, 1.0)
	if floori(cycles) > old_cycle:
		last_cycle_progress = (position - cycle_origin).dot(forward)
		cycle_progress_min = minf(cycle_progress_min, last_cycle_progress)
		cycle_origin = position
	for i in desc.vertebrae.size():
		max_curvature = maxf(max_curvature, absf(spine_angle(i)) / maxf(length_m / maxi(1, desc.vertebrae.size() - 1), 0.01))


func spine_angle(i: int) -> float:
	if mode != "tail_wave" or i == 0:
		return 0.0
	var u := float(i) / float(maxi(1, desc.vertebrae.size() - 1))
	return amplitude * (0.2 + 0.8 * u) * sin(TAU * (phase - wave_count * u))


func fin_angle(i: int) -> float:
	return 1.5 * amplitude * sin(TAU * phase + PI * float(i % 2))


func posed_root_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * Basis.from_euler(Vector3(root_pitch, 0.0, root_roll)), position)


func within_stability_gate() -> bool:
	return max_pitch <= deg_to_rad(5.0) and max_roll <= deg_to_rad(5.0)


func is_finite_state() -> bool:
	return position.is_finite() and is_finite(yaw) and is_finite(v) and is_finite(phase) \
		and is_finite(max_curvature) and is_finite(max_pitch) and is_finite(max_roll)
