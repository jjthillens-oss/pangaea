class_name Locomotion
extends RefCounted
## Swimming on the movement plane, driven by Phenotype stats (M1 step 2). Custom kinematics, no
## physics bodies: deterministic, headless and shared with creature AI later.
##
## `speed` is the top speed, sideways drift included (ActorState.speed_multiplier() halves it
## while starving), `acceleration` is the m/s^2 rate and `turn_rate` caps the heading change per
## tick. The cell turns first and then swims: thrust follows how well the heading matches the
## wanted direction. steer() only changes velocity; PoolArena.move() moves the cell.

const INPUT_DEADZONE := 0.05
const ALIGN_POWER := 2.0       ## thrust share = max(0, cos(heading error))^ALIGN_POWER
const BRAKE_FACTOR := 1.5      ## slowing toward a lower target: this times acceleration
const COAST_FACTOR := 0.9      ## no input: forward speed decays at this times acceleration
const LATERAL_DAMPING := 6.0   ## 1/s: sideways velocity decays, so the cell carves instead of drifting


## Position, velocity and heading of one swimmer, plus the previous tick's values for drawing
## between ticks.
class MotionState:
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var heading := 0.0
	var prev_position := Vector2.ZERO
	var prev_heading := 0.0

	func _init(p_position := Vector2.ZERO, p_heading := 0.0) -> void:
		place(p_position, p_heading)

	## Puts the swimmer at rest at a point, with no motion to draw between ticks.
	func place(p_position: Vector2, p_heading: float) -> void:
		position = p_position
		prev_position = p_position
		heading = p_heading
		prev_heading = p_heading
		velocity = Vector2.ZERO


## `move` is the wanted direction; its length (0..1) is the throttle.
static func steer(m: MotionState, move: Vector2, p: Phenotype, speed_mul: float, dt: float) -> void:
	m.prev_heading = m.heading
	var throttle := minf(move.length(), 1.0)
	var target := 0.0
	var slow := p.acceleration * COAST_FACTOR
	if throttle > INPUT_DEADZONE:
		var want := move.angle()
		m.heading = wrapf(rotate_toward(m.heading, want, p.turn_rate * dt), -PI, PI)
		var align := maxf(0.0, cos(angle_difference(m.heading, want)))
		target = p.speed * speed_mul * throttle * pow(align, ALIGN_POWER)
		slow = p.acceleration * BRAKE_FACTOR
	var fwd := Vector2.from_angle(m.heading)
	var side := fwd.orthogonal()
	var u := m.velocity.dot(fwd)
	var w := m.velocity.dot(side) * exp(-LATERAL_DAMPING * dt)
	# While turning, part of the speed is still sideways; thrust only up to what keeps the total
	# within the top speed.
	var top := p.speed * speed_mul
	target = minf(target, sqrt(maxf(0.0, top * top - w * w)))
	u = minf(target, u + p.acceleration * dt) if u < target else maxf(target, u - slow * dt)
	m.velocity = fwd * u + side * w
