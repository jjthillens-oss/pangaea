class_name Kin
extends RefCounted
## S4.3, kin and mating (docs/s4/s4-plan.md): Spore's mate call without a button. When the cell is
## ready to reproduce (alive, Lineage's REPRODUCE_ENERGY_SHARE of its energy, and points for the
## cheapest editor part) for CALL_S, a cell of its own species swims in from ARRIVE_RADII away and
## keeps beside it. Touching it at a calm moment (nothing hunting the cell, no fight in the last
## quiet ticks: Growth's blockers but eating) reports `mate` once; the scene opens the editor and calls
## finish(). A kin whose cell stops being ready for LEAVE_S, or that the cell leaves behind, goes.
##
## The kin is drawn from the cell's own genome and phenotype, so it looks like the cell. It is no
## creature: brains never see it, it never fights, eats or blocks, and it takes nothing from any
## random stream, so the sea plays out exactly as without it. A death, a respawn or a growth sends it
## away (WorldStream.grow, before it rescales the sea); a rebase shifts it (WorldStream.rebase). While
## absent its position is unset (INF), so neither moves it. It is not saved.
##
## Events: kin_arrived {position, heading}; kin_left {reason: "not ready"|"left behind"|"died"|
## "grew"|"mated"}; mate {position} (the kin's).

const CALL_S := 3.0             ## ready this long before a kin swims in
const LEAVE_S := 20.0           ## not ready this long and the kin goes
const ARRIVE_RADII := 12.0      ## it arrives this many cell radii away, to the cell's left
const HOLD_RADII := 2.6         ## and keeps this far, centre to centre
const LOST_RADII := 40.0        ## farther than this and it is left behind
const SPEED_SHARE := 0.8        ## its throttle: a little slower than the cell, so the cell can reach it

var present := false
var waiting := false            ## a mate was reported and the scene has not finished it
var motion := _unset_motion()
var ready_ticks := 0            ## consecutive ticks the cell has been ready
var unready_ticks := 0          ## consecutive ticks a present kin's cell has not been ready
var _side := 1.0                ## the side it holds: 1 left of the cell's heading at arrival, -1 right
var _size := 0                  ## the size it arrived at: a growth sends it away


## Whether the cell could mate now: alive and on the sea, enough energy, and points for a part.
static func is_ready(sim: PoolSim) -> bool:
	if sim.dead or sim.respawn_pending:
		return false
	if not Lineage.can_reproduce(sim.state).ok:
		return false
	return sim.save.adaptation_points >= cheapest_part(sim.catalog)


## The cheapest part the editor offers (0 when it offers none).
static func cheapest_part(catalog: PartCatalog) -> int:
	var best := -1
	for type_id: String in catalog.parts:
		if catalog.in_editor(type_id) and (best < 0 or catalog.cost_of(type_id) < best):
			best = catalog.cost_of(type_id)
	return maxi(best, 0)


## Whether nothing keeps the cell from mating: Growth's blockers, but a recent meal is fine.
static func is_calm(sim: PoolSim) -> bool:
	if sim.growth == null:
		return false
	var b := sim.growth.blocker_of(sim, false)
	return b == "" or b == "eating"


## Once a tick, at its end (PoolSim.step, after Growth.observe).
func tick(sim: PoolSim) -> void:
	var ready := is_ready(sim)
	ready_ticks = ready_ticks + 1 if ready else 0
	if not present:
		if ready_ticks >= CreatureBrain.ticks(CALL_S) and not sim.dead:
			_arrive(sim)
		return
	if sim.dead or sim.respawn_pending:
		leave(sim, "died")
		return
	if sim.size() != _size:
		leave(sim, "grew")
		return
	unready_ticks = 0 if ready or waiting else unready_ticks + 1
	var r := sim.phenotype.radius
	if unready_ticks >= CreatureBrain.ticks(LEAVE_S):
		leave(sim, "not ready")
		return
	if motion.position.distance_to(sim.motion.position) > LOST_RADII * r:
		leave(sim, "left behind")
		return
	_swim(sim)
	if waiting or not ready or not is_calm(sim):
		return
	if motion.position.distance_to(sim.motion.position) <= 2.0 * r + PoolSim.TOUCH_MARGIN:
		waiting = true
		sim._emit({"type": "mate", "position": motion.position})


## The scene is done with a mate (the editor closed, committed or not): the kin goes.
func finish(sim: PoolSim) -> void:
	if present:
		leave(sim, "mated")


## Sends the kin away now; `reason` goes on kin_left.
func leave(sim: PoolSim, reason: String) -> void:
	if not present:
		return
	present = false
	waiting = false
	unready_ticks = 0
	ready_ticks = 0
	motion = _unset_motion()
	sim._emit({"type": "kin_left", "reason": reason})


## A rebase moved every position by `offset`.
func rebase(offset: Vector2) -> void:
	if present:
		RebaseShift.motion(motion, offset)


## Where the kin wants to be: HOLD_RADII beside the cell, on its side.
func hold_point(sim: PoolSim) -> Vector2:
	var away := (motion.position - sim.motion.position)
	if away.length() < 1e-6:
		away = Vector2.from_angle(sim.motion.heading + _side * PI / 2.0)
	return sim.motion.position + away.normalized() * HOLD_RADII * sim.phenotype.radius


static func _unset_motion() -> Locomotion.MotionState:
	var m := Locomotion.MotionState.new()
	m.position = Vector2.INF
	m.prev_position = Vector2.INF
	return m


func _arrive(sim: PoolSim) -> void:
	var r := sim.phenotype.radius
	_side = 1.0
	var from := sim.motion.position + Vector2.from_angle(sim.motion.heading + PI / 2.0) * ARRIVE_RADII * r
	var at := sim._clear_point_near(from, r)
	motion.place(at, (sim.motion.position - at).angle())
	present = true
	waiting = false
	unready_ticks = 0
	_size = sim.size()
	sim._emit({"type": "kin_arrived", "position": at, "heading": motion.heading})


func _swim(sim: PoolSim) -> void:
	var r := sim.phenotype.radius
	var to := hold_point(sim) - motion.position
	var move := Vector2.ZERO
	if to.length() > 0.25 * r:
		move = to.normalized() * clampf(to.length() / (2.0 * r), 0.2, 1.0) * SPEED_SHARE
	Locomotion.steer(motion, move, sim.phenotype, 1.0, PoolSim.DT)
	if move == Vector2.ZERO:
		# At rest beside the cell it turns to face it.
		motion.heading = rotate_toward(motion.heading, (sim.motion.position - motion.position).angle(),
			sim.phenotype.turn_rate * PoolSim.DT)
	sim.move_body(motion, r)
