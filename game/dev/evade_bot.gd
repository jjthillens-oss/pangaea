extends RefCounted
## Dev and test driver for PoolSim (debug builds only; no class_name, loaded by path): a cell that
## dodges the way a player watching the screen would. About threats it reads only the sim's events;
## of the sim itself it reads only its own cell (place, heading, alive).
##
##  1. On a creature_tell aimed at the cell it waits `reaction_ticks` (0.4 s, the fairness
##     contract's reaction, F2) from the tell's tick.
##  2. Then it swims perpendicular to the tell's lane, on the side with the shorter turn from its
##     heading; on a tie (within TIE_RAD) the side of the lane's centre line it is already on. With
##     `far_side` it takes the other perpendicular instead, the longer turn a player may pick (the
##     S5 grid measures that side too; F2 promises only turns under about 120 degrees).
##  3. It holds that until the same creature's creature_recovered, dodged or tell_cancelled, or
##     until that creature dies or is removed.
##  4. Then it swims straight away from the creature for `away_ticks` (AWAY_TICKS unless a driver
##     that closes in after a strike sets it lower) and returns to its base intent.
##
## Between threats it follows `base` (a Callable(sim) -> SimIntent; none: it stays still), for
## example a heading and throttle, or ForageBot's next_intent.
##
##     var bot = load("res://game/dev/evade_bot.gd").new()
##     bot.base = func(sim: PoolSim) -> SimIntent: return SimIntent.new(Vector2.UP * 0.3)
##     sim.step(bot.next_intent(sim, events_from_the_last_step))

const PLAYER_ID := "player"
const REACTION_TICKS := 24   ## 0.4 s after the tell starts (plan F2 and the S5 grid)
const AWAY_TICKS := 60       ## 1.0 s straight away from the creature once its strike is over
const TIE_RAD := 1e-3        ## turns this close count as equal (then the lane side decides)

var reaction_ticks := REACTION_TICKS
var away_ticks := AWAY_TICKS
var base := Callable()
var throttle := 1.0          ## of the dodge and of the swim away
var far_side := false        ## dodge to the perpendicular with the longer turn (tests measure it)
var reacted_at := -1         ## the sim tick of its first dodge intent (tests guard the latency)
var tell_tick := -1          ## the tick of the last creature_tell it reacted to
var tells_seen := 0
var _threat := {}            ## {"id", "heading", "origin", "react_at", "dir"}; dir is ZERO until it reacts
var _away := {}              ## {"from": Vector2, "until": tick}


## The intent for the coming tick. `events` are the ones the sim reported since the last call (they
## happened on tick sim.tick - 1, unless an event names its own "tick").
func next_intent(sim: PoolSim, events: Array) -> SimIntent:
	_observe(sim.tick - 1, events)
	if sim.dead:
		return SimIntent.new()
	if not _threat.is_empty() and sim.tick >= int(_threat.react_at):
		if _threat.dir == Vector2.ZERO:
			_threat.dir = side(sim.motion.position, sim.motion.heading, float(_threat.heading), _threat.origin)
			if far_side:
				_threat.dir = -_threat.dir
			if reacted_at < 0:
				reacted_at = sim.tick
		return SimIntent.new(_threat.dir * throttle)
	if not _away.is_empty():
		if sim.tick < int(_away.until):
			var off: Vector2 = sim.motion.position - _away.from
			var dir := off / off.length() if off.length() > 1e-6 else Vector2.from_angle(sim.motion.heading)
			return SimIntent.new(dir * throttle)
		_away = {}
	return base.call(sim) if base.is_valid() else SimIntent.new()


## True while it is dodging a strike (between the reaction and the strike's end).
func is_dodging() -> bool:
	return not _threat.is_empty() and _threat.dir != Vector2.ZERO


## The dodge direction: perpendicular to a lane along `lane_heading` from `origin`, on the side with
## the shorter turn from `heading`; on a tie, the side of the lane's centre line `at` is on.
static func side(at: Vector2, heading: float, lane_heading: float, origin: Vector2) -> Vector2:
	var n := Vector2.from_angle(lane_heading).orthogonal()
	var a := absf(angle_difference(heading, n.angle()))
	var b := absf(angle_difference(heading, (-n).angle()))
	if absf(a - b) > TIE_RAD:
		return n if a < b else -n
	return n if (at - origin).dot(n) >= 0.0 else -n


func _observe(tick: int, events: Array) -> void:
	for e in events:
		match str(e.get("type", "")):
			"creature_tell":
				if e.get("target", "") != PLAYER_ID:
					continue
				var lane: Dictionary = e.lane
				var at := int(e.get("tick", tick))
				_threat = {"id": e.id, "heading": float(lane.heading), "origin": lane.origin,
					"react_at": at + reaction_ticks, "dir": Vector2.ZERO}
				_away = {}
				tell_tick = at
				tells_seen += 1
			"creature_recovered", "tell_cancelled", "dodged":
				if _threat.is_empty() or e.get("id", "") != _threat.id:
					continue
				var from: Vector2 = e.get("position", _threat.origin)
				_away = {"from": from, "until": tick + 1 + away_ticks} if away_ticks > 0 else {}
				_threat = {}
			"creature_died", "creature_removed":
				# Gone mid-tell or mid-strike (killed by another body): nothing is coming any more.
				if not _threat.is_empty() and e.get("id", "") == _threat.id:
					_threat = {}
