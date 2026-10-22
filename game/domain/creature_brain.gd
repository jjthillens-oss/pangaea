class_name CreatureBrain
extends RefCounted
## A creature's mind (M1 step 3). Pure: it decides from its own memory and the percepts the senses
## hand it, never from the world's tables, so it knows where a body is only if it sensed it.
##
## think() makes every decision that needs perception: what to notice, when to chase, give up,
## forage or flee, and when to start a tell. It runs at 10 Hz (20 Hz while engaged), staggered by
## the creature's number, on the tick after it is hurt, and on the exact tick a timed decision
## falls due (think_due()). drive() runs every tick: it advances the attack's timed phases (tell,
## strike, glide) at their exact tick and steers from memory only, dead-reckoning the last percept.
## So a tell always lasts exactly its tick count, whatever the think schedule.
##
## Two behaviors:
## - "ambush" lurks at home. It watches prey it notices and strikes prey that comes into its window
##   in front; when hungry, or when the prey hurt it, it pursues within its leash.
## - "territorial" rests in and patrols a territory and charges intruders.
## Every attack goes notice -> chase/aim -> a tell whose heading locks at its start (at a capped
## lead point) -> a burst and a glide along that line, with no homing -> recover. Every pursuit
## gives up (lost, timer, leash, left_territory, unreachable, target_gone) and every navigation goal
## has a progress check and a timeout. All timers are integer ticks.
##
## The sim's side of the contract (CreatureField and PoolSim):
## - self_view: {"id", "species", "position", "heading", "velocity", "speed_now", "radius", "speed",
##   "acceleration", "health_share", "energy_share"}; speed and acceleration are the phenotype's.
## - Each tick: think() when think_due(), then drive(), then move_body() and PoolArena.move(), then
##   PoolArena.clamp_to_disc() to leash_disc(). Drain `events` and add the creature's id.
## - Hooks: on_hurt() for every landed hit on it; on_strike_landed() and on_blocked() during a strike;
##   on_target_gone() when a body it may remember dies, is removed or is concealed; forget() and
##   force_return() at the player's respawn.
## - The token: before a think, set "engageable" on the player's percept and on its entry in `seen`
##   (decisions read the remembered entry, which may be older than the token's last change); after a
##   think or a hook, read is_engaged_with().

const TICKS_PER_SECOND := 60
const DT := 1.0 / 60.0

const AMBUSH := "ambush"
const TERRITORIAL := "territorial"

# States and phases; the debug panel shows "state/phase".
const REST := "rest"
const WANDER := "wander"
const FORAGE := "forage"
const NOTICE := "notice"
const CHASE := "chase"
const ATTACK := "attack"
const FLEE := "flee"
const LURK := "lurk"            ## rest (ambush): at home, facing out
const WATCH := "watch"          ## rest (ambush): at home, turning to track what it noticed
const PATROL := "patrol"
const RETURN_HOME := "return"
const SEEK := "seek"
const EAT := "eat"
const WAIT := "wait"            ## notice (territorial): the target is not engageable (the token)
const PURSUE := "pursue"
const AIM := "aim"
const TELL := "tell"
const STRIKE := "strike"
const GLIDE := "glide"
const RECOVER := "recover"

# drive() modes. "turn" and "tell" brake (steer with no input) and turn toward "face".
const MODE_STEER := "steer"
const MODE_TURN := "turn"
const MODE_TELL := "tell"
const MODE_BURST := "burst"
const MODE_GLIDE := "glide"

const NEVER := 1 << 60

## m: home is reached within this (the plan's arrival distance).
const ARRIVE_HOME_M := 0.3
## m: a resting creature pushed farther than this from home (by a body or a rock) swims back.
const HOME_SLACK_M := 1.0
## m: a patrol or forage point is reached within this.
const ARRIVE_GOAL_M := 0.5
## m: within this of its stand-off point a pursuer stops and turns to face the target, so a run-up
## that ends facing away still comes round to aim. Half the ambush window's width.
const FACE_AT_STANDOFF_M := 0.25
## m/s: a target beyond the window that closes on the pursuer at least this fast is awaited in
## chase/aim (braking, facing it) until it comes into the window, instead of being met and overrun.
const APPROACH_WAIT_MPS := 0.2
## Share of the braking deceleration (Locomotion.BRAKE_FACTOR x acceleration) planned for when
## slowing toward a goal, so it arrives without overshooting even while turning.
const ARRIVE_BRAKE_SHARE := 0.5
## m: the ambush leash give-up fires this close to the leash circle (the plan's 0.25 m).
const LEASH_GIVE_UP_M := 0.25
## m: an ambush hunter that sees no carrion forages by patrolling points this far round its home.
const FORAGE_PATROL_M := 6.0
## m: patrol points are picked this far inside the territory edge.
const PATROL_INSET_M := 1.0
## m: a territorial creature given no territory (a debug spawn) guards this circle round its home,
## the M1 zone radius.
const DEFAULT_TERRITORY_M := 6.0
## Ticks a cancelled puff deflates before the rammer swims home: 0.4 s, the view's deflate.
const CANCEL_RECOVER_TICKS := 24
## m: fleeing steers at a point this far ahead, away from the attacker.
const FLEE_LOOKAHEAD_M := 4.0
## m: this close to the leash circle, fleeing slides along it instead of pushing out.
const FLEE_EDGE_M := 1.0
## Random goal tries (each must be clear of rocks) before falling back to home.
const GOAL_TRIES := 12
## rad: a striking creature is blocked by a rock it touches within this of its heading (60 degrees).
const BLOCKED_BEARING := PI / 3.0


## Everything a brain remembers. Durations in cfg are already ticks (config()).
class Memory:
	var behavior := ""
	var cfg: Dictionary = {}
	var state := "rest"
	var phase := ""
	var state_tick := 0
	var phase_tick := 0
	var target := ""
	## id -> {"position", "velocity", "tick", "by", "species", "radius", "engageable"}; an entry is
	## dropped once it is cfg.memory_ticks old.
	var seen := {}
	var engaged_tick := -1           ## when the current engagement began; reset by a landed hit
	var landed_on := {}              ## id -> tick of our last hit on it
	var lock_heading := NAN          ## set at tell entry, cleared at recover
	var lane := {}                   ## strike_lane() at tell entry, cleared at recover
	var goal := Vector2.INF          ## patrol, forage or food point
	var goal_tick := 0
	var food_id := ""
	var progress := {}               ## {"position", "tick"}: the unreachable and navigation checks
	var route_side := 0              ## PoolArena.route_point side; flipped when a route stalls
	var ignore := {}                 ## id -> tick it is ignored until (refractory, killer ignore)
	var ignore_all_until := 0        ## settling after a spawn: notices nothing before this tick
	var attacker := ""               ## the last body that hurt it
	var pain := false                ## a hurt not yet answered by think()
	var flee_from := Vector2.INF
	var rest_until := 0
	var forage_after := 0
	var outcome := ""                ## hit | missed | blocked | interrupted | cancelled
	var recover_ticks := 0
	var gone := ""                   ## a target that went away mid-attack; the give-up waits for recover
	var return_fails := 0
	var stuck := false
	var home := Vector2.ZERO
	var home_heading := 0.0
	var territory_center := Vector2.INF
	var territory_r := 0.0
	var wake := false                ## think on the next tick whatever the schedule
	var trace := false               ## emit creature_state on every state change (debug)
	var rng := RandomNumberGenerator.new()
	var events: Array[Dictionary] = []

	## The whole memory for snapshots and hashing: vectors as [x, y], no NaN or infinity (null
	## instead), dictionaries in id order, and the RNG's seed and state. cfg and events are left out.
	func to_dict() -> Dictionary:
		var seen_out := {}
		for id in CreatureBrain._sorted_keys(seen):
			var e: Dictionary = seen[id]
			seen_out[id] = {"position": CreatureBrain._pair(e.position), "velocity": CreatureBrain._pair(e.velocity),
				"tick": e.tick, "by": e.by, "species": e.species, "radius": e.radius, "engageable": e.engageable}
		var landed_out := {}
		for id in CreatureBrain._sorted_keys(landed_on):
			landed_out[id] = landed_on[id]
		var ignore_out := {}
		for id in CreatureBrain._sorted_keys(ignore):
			ignore_out[id] = ignore[id]
		var lane_out := {}
		if not lane.is_empty():
			lane_out = {"origin": CreatureBrain._pair(lane.origin), "heading": lane.heading, "travel": lane.travel,
				"length": lane.length, "half_width": lane.half_width}
		var progress_out := {}
		if not progress.is_empty():
			progress_out = {"position": CreatureBrain._pair(progress.position), "tick": progress.tick}
		return {
			"behavior": behavior, "state": state, "phase": phase, "state_tick": state_tick, "phase_tick": phase_tick,
			"target": target, "seen": seen_out, "engaged_tick": engaged_tick, "landed_on": landed_out,
			"lock_heading": lock_heading if is_finite(lock_heading) else null, "lane": lane_out,
			"goal": CreatureBrain._pair(goal) if goal.is_finite() else null, "goal_tick": goal_tick, "food_id": food_id,
			"progress": progress_out, "route_side": route_side, "ignore": ignore_out, "ignore_all_until": ignore_all_until,
			"attacker": attacker, "pain": pain, "flee_from": CreatureBrain._pair(flee_from) if flee_from.is_finite() else null,
			"rest_until": rest_until, "forage_after": forage_after, "outcome": outcome, "recover_ticks": recover_ticks,
			"gone": gone, "return_fails": return_fails, "stuck": stuck, "home": CreatureBrain._pair(home),
			"home_heading": home_heading,
			"territory_center": CreatureBrain._pair(territory_center) if territory_center.is_finite() else null,
			"territory_r": territory_r, "wake": wake, "rng_seed": rng.seed, "rng_state": rng.state,
		}


## Seconds to ticks, once, at load: roundi(s x 60), so 1.2 s is 72 and 0.35 s is 21.
static func ticks(seconds: Variant) -> int:
	return roundi(float(seconds) * TICKS_PER_SECOND)


## A brain's cfg from a species block and the shared "ai" block of creatures_m1.json: every duration
## in ticks, angles in radians, and the strike's travel and reach worked out. SpeciesCatalog builds
## it once at load (and validates the data); tests build it from inline blocks.
static func config(species_id: String, species: Dictionary, ai: Dictionary) -> Dictionary:
	var attack: Dictionary = species.get("attack", {})
	var senses: Dictionary = species.get("senses", {})
	var flee: Dictionary = species.get("flee", {})
	var kind := str(attack.get("kind", ""))
	var a := {
		"kind": kind, "tell": str(attack.get("tell", "")),
		"start_min_m": float(attack.get("start_min_m", 0.0)), "start_max_m": float(attack.get("start_max_m", 0.0)),
		"standoff_m": float(attack.get("standoff_m", 0.0)), "aim": deg_to_rad(float(attack.get("aim_deg", 0.0))),
		"lead_s": float(attack.get("lead_s", 0.0)), "lead_cap_m": float(attack.get("lead_cap_m", 0.0)),
		"tell_ticks": ticks(attack.get("tell_s", 0.0)), "burst_speed": float(attack.get("burst_speed", 0.0)),
		"burst_ticks": ticks(attack.get("burst_s", 0.0)), "glide_ticks": ticks(attack.get("glide_s", 0.0)),
		"glide_drag": float(attack.get("glide_drag", 0.0)), "recover_ticks": ticks(attack.get("recover_s", 0.0)),
		"blocked_recover_ticks": ticks(attack.get("blocked_recover_s", 0.0)),
		"knockback": float(attack.get("knockback", 0.0)),
		"reach": InteractionResolver.BITE_REACH if kind == "bite" else InteractionResolver.RAM_REACH,
	}
	a["travel"] = Locomotion.strike_travel(a.burst_speed, a.burst_ticks, a.glide_drag, a.glide_ticks, DT)
	var rest: Array = species.get("rest_s", [0.0, 0.0])
	var speeds: Dictionary = species.get("speeds", {})
	return {
		"species_id": species_id, "behavior": str(species.get("behavior", "")),
		"think_ticks": maxi(1, roundi(TICKS_PER_SECOND / float(ai.get("think_hz", 10.0)))),
		"engaged_think_ticks": maxi(1, roundi(TICKS_PER_SECOND / float(ai.get("engaged_think_hz", 20.0)))),
		"dead_reckon_ticks": ticks(ai.get("dead_reckon_cap_s", 0.5)),
		"unreachable_ticks": ticks(ai.get("unreachable_window_s", 2.0)),
		"unreachable_min_m": float(ai.get("unreachable_min_m", 0.5)),
		"return_fail_limit": int(ai.get("return_fail_limit", 3)),
		"settle_ticks": ticks(ai.get("settle_s", 3.0)),
		"tell_start_max_speed": float(ai.get("tell_start_max_speed", 0.3)),
		"hungry_below": float(species.get("hungry_below", 0.0)), "full_above": float(species.get("full_above", 1.0)),
		"memory_ticks": ticks(senses.get("memory_s", 2.0)),
		"speeds": {"wander": float(speeds.get("wander", 0.5)), "forage": float(speeds.get("forage", 0.5)),
			"pursue": float(speeds.get("pursue", 1.0)), "flee": float(speeds.get("flee", 1.0))},
		"prey_max_radius_share": float(species.get("prey_max_radius_share", InteractionResolver.BITE_SIZE_LIMIT)),
		"intruder_min_radius": float(species.get("intruder_min_radius", 0.0)),
		"notice_ticks": ticks(species.get("notice_s", 0.5)), "give_up_ticks": ticks(species.get("give_up_s", 5.0)),
		"leash_m": float(species.get("leash_m", 0.0)),
		"forage_radius_m": float(species.get("forage_radius_m", INF)),
		"forage_timeout_ticks": ticks(species.get("forage_timeout_s", 0.0)),
		"forage_retry_ticks": ticks(species.get("forage_retry_s", 0.0)),
		"refractory_ticks": ticks(species.get("refractory_s", 0.0)),
		"nav_timeout_ticks": ticks(species.get("nav_timeout_s", 10.0)),
		"territory_margin_m": float(species.get("territory_margin_m", 0.0)),
		"territory_exit_m": float(species.get("territory_exit_m", 0.0)),
		"rest_ticks": [ticks(rest[0]), ticks(rest[1])] if rest.size() == 2 else [0, 0],
		"flee_below": float(flee.get("below_health_share", 0.0)), "flee_ticks": ticks(flee.get("for_s", 0.0)),
		"attack": a,
	}


## A new brain, resting at home and settling (it notices nothing for cfg.settle_ticks).
## `territory` is the guarded zone's own circle {"center", "radius"}; the territory adds
## cfg.territory_margin_m. Ambush brains pass {}.
static func create(behavior: String, cfg: Dictionary, home: Vector2, home_heading: float, territory: Dictionary,
		seed_value: int, tick: int) -> Memory:
	var mem := Memory.new()
	mem.behavior = behavior
	mem.cfg = cfg
	mem.home = home
	mem.home_heading = home_heading
	mem.rng.seed = seed_value
	if behavior == TERRITORIAL:
		mem.territory_center = territory.get("center", home)
		mem.territory_r = float(territory.get("radius", DEFAULT_TERRITORY_M)) + float(cfg.territory_margin_m)
	mem.ignore_all_until = tick + int(cfg.settle_ticks)
	mem.state_tick = tick
	if behavior == AMBUSH:
		_enter(mem, REST, LURK, tick)
	else:
		_rest(mem, tick)
	return mem


## The disc the sim clamps the body to after every move: (home, leash) for an ambush brain,
## (territory center, territory radius + leash) for a territorial one. {"center", "radius"}.
static func leash_disc(mem: Memory) -> Dictionary:
	if mem.behavior == TERRITORIAL:
		return {"center": mem.territory_center, "radius": mem.territory_r + float(mem.cfg.leash_m)}
	return {"center": mem.home, "radius": float(mem.cfg.leash_m)}


## True when the brain is in chase or attack with this body as its target (the token counts these).
static func is_engaged_with(mem: Memory, id: String) -> bool:
	return not id.is_empty() and mem.target == id and (mem.state == CHASE or mem.state == ATTACK)


## True during the strike's burst and glide, the only ticks a creature's hit can land.
static func is_striking(mem: Memory) -> bool:
	return mem.state == ATTACK and (mem.phase == STRIKE or mem.phase == GLIDE)


## Whether think() should run this tick: after a hurt, on the creature's slot of the 10 Hz schedule
## (20 Hz while in chase or attack), or when a timed decision falls due (next_deadline()).
static func think_due(mem: Memory, number: int, tick: int) -> bool:
	if mem.wake:
		return true
	var engaged := mem.state == CHASE or mem.state == ATTACK
	var period: int = mem.cfg.engaged_think_ticks if engaged else mem.cfg.think_ticks
	if posmod(tick + number, maxi(period, 1)) == 0:
		return true
	return tick >= next_deadline(mem)


## The first tick at which a timed decision falls due: a notice or recover ending, the target's
## memory running out, the give-up timer, the unreachable window, a flee or rest ending, or a
## navigation timeout. NEVER when nothing is pending.
static func next_deadline(mem: Memory) -> int:
	var due := NEVER
	match mem.state:
		NOTICE:
			if mem.phase != WAIT:
				due = mem.phase_tick + int(mem.cfg.notice_ticks)
			due = mini(due, _give_up_deadline(mem))
		CHASE:
			due = _give_up_deadline(mem)
			if mem.phase == PURSUE and not mem.progress.is_empty():
				due = mini(due, int(mem.progress.tick) + int(mem.cfg.unreachable_ticks))
		ATTACK:
			if mem.phase == RECOVER:
				due = mem.phase_tick + mem.recover_ticks
		FLEE:
			due = mem.state_tick + int(mem.cfg.flee_ticks)
		REST:
			if mem.phase == WATCH and mem.seen.has(mem.target):
				due = int(mem.seen[mem.target].tick) + int(mem.cfg.memory_ticks)
			elif mem.behavior == TERRITORIAL:
				due = mem.rest_until
		WANDER, FORAGE:
			if mem.phase == RETURN_HOME:
				due = mem.phase_tick + int(mem.cfg.nav_timeout_ticks)
			elif mem.goal.is_finite() and mem.phase != EAT:
				due = mem.goal_tick + int(mem.cfg.nav_timeout_ticks)
			if mem.phase == SEEK and int(mem.cfg.forage_timeout_ticks) > 0:
				due = mini(due, mem.phase_tick + int(mem.cfg.forage_timeout_ticks))
			if not mem.progress.is_empty() and mem.phase != EAT:
				due = mini(due, int(mem.progress.tick) + int(mem.cfg.unreachable_ticks))
	return due


## Every perception-based decision. `percepts` come from CreatureSenses.perceive (nearest first);
## `food` from CreatureSenses.perceive_food, passed only while foraging. `arena` may be null (no
## rocks: no detours and every goal point is clear).
static func think(mem: Memory, self_view: Dictionary, percepts: Array, food: Array, tick: int, arena: PoolArena) -> void:
	mem.wake = false
	_remember(mem, percepts, tick)
	# A hurt during a strike waits for the strike to end; the strike always completes.
	if mem.pain and not is_striking(mem):
		mem.pain = false
		if _answer_pain(mem, self_view, tick):
			return
	match mem.state:
		REST:
			if mem.phase == WATCH:
				_think_watch(mem, self_view, tick)
			else:
				_think_rest(mem, self_view, percepts, tick)
		WANDER:
			_think_wander(mem, self_view, percepts, tick, arena)
		FORAGE:
			_think_forage(mem, self_view, percepts, food, tick, arena)
		NOTICE:
			_think_notice(mem, self_view, tick)
		CHASE:
			_think_chase(mem, self_view, tick)
		ATTACK:
			_think_attack(mem, self_view, tick)
		FLEE:
			_think_flee(mem, tick)


## Runs every tick. Advances the attack's timed phases at their exact tick, then returns what to do
## from memory alone: {"mode": steer|turn|tell|burst|glide, "move": Vector2 (|move| <= 1),
## "speed_mul" (share of top speed, <= 1), "face" (heading to turn toward in turn/tell/burst/glide,
## else 0), "strike": bool, "target": String, "feed": food id or ""}.
static func drive(mem: Memory, self_view: Dictionary, tick: int, arena: PoolArena) -> Dictionary:
	if mem.state == ATTACK:
		_advance_attack(mem, self_view, tick)
	var speeds: Dictionary = mem.cfg.speeds
	match mem.state:
		REST:
			if mem.phase == WATCH and mem.seen.has(mem.target):
				return _turn(mem, _face(self_view, _reckon(mem, mem.target, tick)), speeds.wander)
			if mem.behavior == AMBUSH:
				return _turn(mem, mem.home_heading, speeds.wander)
			return _coast(mem, speeds.wander)
		WANDER:
			if mem.phase == RETURN_HOME:
				return _seek(mem, self_view, mem.home, speeds.wander, arena, true)
			if mem.goal.is_finite():
				return _seek(mem, self_view, mem.goal, speeds.wander, arena, true)
			return _coast(mem, speeds.wander)
		FORAGE:
			if mem.phase == EAT and mem.goal.is_finite():
				var out := _turn(mem, _face(self_view, mem.goal), speeds.forage)
				out.feed = mem.food_id
				return out
			if mem.goal.is_finite():
				return _seek(mem, self_view, mem.goal, speeds.forage, arena, true)
			return _coast(mem, speeds.forage)
		NOTICE:
			if mem.seen.has(mem.target):
				return _turn(mem, _face(self_view, _reckon(mem, mem.target, tick)), speeds.wander)
			return _coast(mem, speeds.wander)
		CHASE:
			return _drive_chase(mem, self_view, tick, arena)
		ATTACK:
			return _drive_attack(mem, self_view)
		FLEE:
			return _drive_flee(mem, self_view, arena)
	return _coast(mem, speeds.wander)


## Moves the body by a drive() result (the section 6 movement table). steer: Locomotion.steer.
## turn and tell: brake (steer with no input), then turn toward `face` at the turn rate. burst:
## the strike's speed along the lock. glide: the strike's drag. `speed_mul` is the condition's
## multiplier (ActorState.speed_multiplier()); a strike ignores it. The caller then moves the body
## (PoolArena.move) and clamps it to leash_disc().
static func move_body(mem: Memory, m: Locomotion.MotionState, d: Dictionary, p: Phenotype, speed_mul: float, dt: float) -> void:
	var attack: Dictionary = mem.cfg.attack
	match str(d.mode):
		MODE_BURST:
			Locomotion.burst(m, float(d.face), float(attack.burst_speed))
		MODE_GLIDE:
			Locomotion.glide(m, float(attack.glide_drag), dt)
		MODE_TURN, MODE_TELL:
			Locomotion.steer(m, Vector2.ZERO, p, float(d.speed_mul) * speed_mul, dt)
			m.heading = wrapf(rotate_toward(m.heading, float(d.face), p.turn_rate * dt), -PI, PI)
		_:
			Locomotion.steer(m, d.move, p, float(d.speed_mul) * speed_mul, dt)


## The danger lane of a strike from `origin` along `heading`: the body travels `travel` (the per-tick
## burst and glide, Locomotion.strike_travel) and can hit a prey of radius `prey_radius` within its
## own radius plus the weapon's reach. {"origin", "heading", "travel", "length" (travel + radius +
## reach + prey radius), "half_width" (radius + reach + prey radius)}. The brain's leash check, the
## view's floor lane, the gizmos and the tests all use this.
static func strike_lane(attack: Dictionary, own_radius: float, prey_radius: float, origin: Vector2, heading: float) -> Dictionary:
	var travel := Locomotion.strike_travel(float(attack.burst_speed), int(attack.burst_ticks), float(attack.glide_drag),
		int(attack.glide_ticks), DT)
	var reach := InteractionResolver.BITE_REACH if str(attack.kind) == "bite" else InteractionResolver.RAM_REACH
	var half := own_radius + reach + prey_radius
	return {"origin": origin, "heading": heading, "travel": travel, "length": travel + half, "half_width": half}


## True when `p` lies on the lane's rectangle: from its origin forward to its length, within its
## half-width either side.
static func lane_contains(lane: Dictionary, p: Vector2) -> bool:
	var rel: Vector2 = (p - lane.origin).rotated(-float(lane.heading))
	return rel.x >= 0.0 and rel.x <= float(lane.length) and absf(rel.y) <= float(lane.half_width)


## Starts a tell at the target now (think does this when the tell-start conditions hold; tests use
## it to start one at an exact tick). Locks the heading at the target's dead-reckoned position plus
## its velocity times lead_s, capped at lead_cap_m, and emits creature_tell with the lane.
static func begin_tell(mem: Memory, self_view: Dictionary, tick: int) -> void:
	var attack: Dictionary = mem.cfg.attack
	var lock := _lock_heading(mem, self_view, tick)
	var prey_r: float = mem.seen[mem.target].radius
	mem.lock_heading = lock
	mem.lane = strike_lane(attack, float(self_view.radius), prey_r, self_view.position, lock)
	mem.outcome = ""
	_enter(mem, ATTACK, TELL, tick)
	_emit(mem, {"type": "creature_tell", "target": mem.target, "kind": attack.tell, "ticks": attack.tell_ticks,
		"lane": mem.lane.duplicate()})


## A landed hit on it. `attacker` is the hitter's body ({"id", "species", "position", "velocity",
## "radius", "engageable"}); it is in contact, so its position is known (pain). The next tick's
## think answers: flee below the flee share, else notice the attacker.
static func on_hurt(mem: Memory, attacker: Dictionary, tick: int) -> void:
	var id := str(attacker.get("id", ""))
	if id.is_empty():
		return
	mem.attacker = id
	mem.pain = true
	mem.wake = true
	mem.ignore.erase(id)
	mem.seen[id] = {"position": attacker.get("position", Vector2.ZERO), "velocity": attacker.get("velocity", Vector2.ZERO),
		"tick": tick, "by": "pain", "species": str(attacker.get("species", "")), "radius": float(attacker.get("radius", 0.5)),
		"engageable": bool(attacker.get("engageable", true))}


## Its strike hit the target: recover at once. The hit also resets the give-up timer.
static func on_strike_landed(mem: Memory, tick: int) -> void:
	if not is_striking(mem):
		return
	mem.landed_on[mem.target] = tick
	mem.engaged_tick = tick
	_recover(mem, "hit", tick)


## Its strike ran into a rock ahead: recover for blocked_recover_ticks (dazed).
static func on_blocked(mem: Memory, tick: int) -> void:
	if is_striking(mem):
		_recover(mem, "blocked", tick)


## A body it may remember died, was removed or was concealed: it is forgotten, and an engagement
## with it gives up (target_gone). An attack in progress completes first and gives up at recover.
static func on_target_gone(mem: Memory, id: String, tick: int) -> void:
	mem.seen.erase(id)
	mem.landed_on.erase(id)
	if mem.attacker == id:
		mem.attacker = ""
		mem.pain = false
	if id.is_empty() or mem.target != id:
		return
	match mem.state:
		ATTACK:
			mem.gone = id
		NOTICE, CHASE:
			_give_up(mem, "target_gone", tick)
		REST:
			mem.target = ""
			_enter(mem, REST, LURK, tick)


## Forgets a body without a give-up event (the player's respawn: every brain forgets the player).
## With `ignore_until` after `tick`, the body is also ignored until then (the killer's ignore).
static func forget(mem: Memory, id: String, ignore_until: int, tick: int) -> void:
	mem.seen.erase(id)
	mem.landed_on.erase(id)
	if mem.attacker == id:
		mem.attacker = ""
		mem.pain = false
	if ignore_until > tick:
		mem.ignore[id] = ignore_until
	if id.is_empty() or mem.target != id:
		return
	if is_striking(mem) or (mem.state == ATTACK and mem.phase == TELL):
		_emit(mem, {"type": "creature_recovered", "target": id, "outcome": "cancelled"})
	_drop_target(mem)
	if mem.state == REST:
		_enter(mem, REST, LURK, tick)
	elif mem.state == NOTICE or mem.state == CHASE or mem.state == ATTACK:
		_after_engagement(mem, tick)


## The sim has put the body back at its home and heading (respawn rule C2): forget `forget_id`
## (ignored until `ignore_until` when that is later than `tick`), drop any attack, rest.
static func force_return(mem: Memory, forget_id: String, ignore_until: int, tick: int) -> void:
	if is_striking(mem) or (mem.state == ATTACK and mem.phase == TELL):
		_emit(mem, {"type": "creature_recovered", "target": mem.target, "outcome": "cancelled"})
	_drop_target(mem)
	forget(mem, forget_id, ignore_until, tick)
	mem.attacker = ""
	mem.pain = false
	mem.goal = Vector2.INF
	mem.food_id = ""
	mem.return_fails = 0
	mem.stuck = false
	if mem.behavior == AMBUSH:
		_enter(mem, REST, LURK, tick)
	else:
		_rest(mem, tick)


# --- think, per state ---

static func _think_rest(mem: Memory, me: Dictionary, percepts: Array, tick: int) -> void:
	if mem.behavior == AMBUSH and Vector2(me.position).distance_to(mem.home) > HOME_SLACK_M:
		_enter(mem, WANDER, RETURN_HOME, tick, me.position)
		return
	var found := _pick_new_target(mem, me, percepts, tick)
	if not found.is_empty():
		_notice(mem, found.id, found.by, tick)
		return
	if _hungry(mem, me) and tick >= mem.forage_after:
		_start_forage(mem, me, tick)
		return
	if mem.behavior == TERRITORIAL and tick >= mem.rest_until:
		_enter(mem, WANDER, PATROL, tick)


static func _think_watch(mem: Memory, me: Dictionary, tick: int) -> void:
	if not mem.seen.has(mem.target):
		mem.target = ""
		_enter(mem, REST, LURK, tick)
		return
	if Vector2(me.position).distance_to(mem.home) > HOME_SLACK_M:
		mem.target = ""
		_enter(mem, WANDER, RETURN_HOME, tick, me.position)
		return
	if not bool(mem.seen[mem.target].engageable) or not _can_engage(mem, me):
		return
	if _hungry(mem, me):
		_chase(mem, me, PURSUE, tick, true)
	elif _fresh(mem, mem.target, tick) and _in_window(mem, me, tick) and _aimed(mem, me, tick):
		_chase(mem, me, AIM, tick, true)


static func _think_wander(mem: Memory, me: Dictionary, percepts: Array, tick: int, arena: PoolArena) -> void:
	var found := _pick_new_target(mem, me, percepts, tick)
	# A sated hunter on its way home does not stop for prey it would not chase (it would notice,
	# watch from off its home, set off again and notice again); it notices it once home. Prey that
	# hurt it or that it bit is still worth a chase.
	if not found.is_empty() and mem.behavior == AMBUSH and mem.phase == RETURN_HOME and not _hungry(mem, me) \
			and not mem.landed_on.has(found.id) and found.id != mem.attacker:
		found = {}
	if not found.is_empty():
		_notice(mem, found.id, found.by, tick)
		return
	var at: Vector2 = me.position
	if mem.phase == RETURN_HOME:
		if at.distance_to(mem.home) <= ARRIVE_HOME_M:
			mem.return_fails = 0
			mem.stuck = false
			if mem.behavior == AMBUSH:
				_enter(mem, REST, LURK, tick)
			else:
				_rest(mem, tick)
			return
		if tick - mem.phase_tick >= int(mem.cfg.nav_timeout_ticks):
			mem.return_fails += 1
			if mem.return_fails >= int(mem.cfg.return_fail_limit):
				mem.stuck = true
			_enter(mem, WANDER, RETURN_HOME, tick, at)
			return
		_check_progress(mem, me, tick)
		return
	# Patrol (territorial): a random clear point in the territory, then a rest.
	if not mem.goal.is_finite() or tick - mem.goal_tick >= int(mem.cfg.nav_timeout_ticks):
		_set_goal(mem, _random_point(mem, me, mem.territory_center, maxf(0.0, mem.territory_r - PATROL_INSET_M), arena), tick, at)
		return
	if at.distance_to(mem.goal) <= ARRIVE_GOAL_M:
		_rest(mem, tick)
		return
	_check_progress(mem, me, tick)


static func _think_forage(mem: Memory, me: Dictionary, percepts: Array, food: Array, tick: int, arena: PoolArena) -> void:
	var found := _pick_new_target(mem, me, percepts, tick)
	if not found.is_empty():
		_notice(mem, found.id, found.by, tick)
		return
	if float(me.energy_share) >= float(mem.cfg.full_above):
		mem.food_id = ""
		mem.goal = Vector2.INF
		if mem.behavior == AMBUSH:
			_enter(mem, WANDER, RETURN_HOME, tick, me.position)
		else:
			_rest(mem, tick)
		return
	var at: Vector2 = me.position
	if mem.phase == EAT:
		var still := {}
		for f in food:
			if f.id == mem.food_id:
				still = f
		if still.is_empty() or not _touching(me, still):
			_start_forage(mem, me, tick)
		else:
			mem.goal = still.position
		return
	var timeout: int = mem.cfg.forage_timeout_ticks
	if timeout > 0 and tick - mem.phase_tick >= timeout:
		mem.forage_after = tick + int(mem.cfg.forage_retry_ticks)
		mem.food_id = ""
		mem.goal = Vector2.INF
		_enter(mem, WANDER, RETURN_HOME, tick, at)
		return
	var meal := _pick_food(mem, me, food)
	if not meal.is_empty():
		if mem.food_id != meal.id:
			mem.food_id = meal.id
			_set_goal(mem, meal.position, tick, at)
		elif tick - mem.goal_tick >= int(mem.cfg.nav_timeout_ticks):
			# Still the nearest meal after a navigation timeout: try the other way round.
			var side := -mem.route_side if mem.route_side != 0 else mem.rng.randi_range(0, 1) * 2 - 1
			_set_goal(mem, meal.position, tick, at)
			mem.route_side = side
		mem.goal = meal.position
		if _touching(me, meal):
			_enter(mem, FORAGE, EAT, tick)
			return
		_check_progress(mem, me, tick)
		return
	# Nothing to eat in view: look round home (ambush) or the territory (territorial).
	if not mem.food_id.is_empty():
		mem.food_id = ""
		mem.goal = Vector2.INF
	var stale := tick - mem.goal_tick >= int(mem.cfg.nav_timeout_ticks)
	if not mem.goal.is_finite() or at.distance_to(mem.goal) <= ARRIVE_GOAL_M or stale:
		var center := mem.home if mem.behavior == AMBUSH else mem.territory_center
		var r := FORAGE_PATROL_M if mem.behavior == AMBUSH else maxf(0.0, mem.territory_r - PATROL_INSET_M)
		_set_goal(mem, _random_point(mem, me, center, r, arena), tick, at)
		return
	_check_progress(mem, me, tick)


static func _think_notice(mem: Memory, me: Dictionary, tick: int) -> void:
	var reason := _give_up_reason(mem, me, tick)
	if not reason.is_empty():
		_give_up(mem, reason, tick)
		return
	if mem.phase != WAIT and tick - mem.phase_tick < int(mem.cfg.notice_ticks):
		return
	var engageable: bool = mem.seen[mem.target].engageable
	if mem.behavior == AMBUSH:
		if engageable and _wants_chase(mem, me) and _can_engage(mem, me):
			_chase(mem, me, PURSUE, tick, false)
		else:
			_enter(mem, REST, WATCH, tick)
		return
	if not (_intruding(mem, mem.target, tick) or mem.target == mem.attacker):
		_drop_target(mem)
		_enter(mem, WANDER, PATROL, tick)
	elif engageable and _can_engage(mem, me):
		_chase(mem, me, PURSUE, tick, false)
	elif mem.phase != WAIT:
		# No token: it keeps facing the intruder until the give-up rules end the notice.
		_enter(mem, NOTICE, WAIT, tick)


static func _think_chase(mem: Memory, me: Dictionary, tick: int) -> void:
	if mem.phase == PURSUE:
		_track_progress(mem, me, tick)
	var reason := _give_up_reason(mem, me, tick)
	if not reason.is_empty():
		_give_up(mem, reason, tick)
		return
	if mem.phase == PURSUE:
		var coming := _in_window(mem, me, tick) or _approaching(mem, me, tick)
		if _fresh(mem, mem.target, tick) and coming and _aimed(mem, me, tick):
			_enter(mem, CHASE, AIM, tick)
		return
	if _tell_ok(mem, me, tick):
		# A puff at a target past the territory exit would be cancelled on the next think: a rammer
		# lets it go there instead of telling for nothing.
		if mem.behavior == TERRITORIAL and _past_exit(mem, Vector2(mem.seen[mem.target].position)):
			_give_up(mem, "left_territory", tick)
			return
		begin_tell(mem, me, tick)
		return
	if _in_window(mem, me, tick) or _approaching(mem, me, tick):
		return
	if mem.behavior == AMBUSH and not _wants_chase(mem, me):
		# A sated hunter that struck from watching goes back to watching, or home.
		if Vector2(me.position).distance_to(mem.home) <= HOME_SLACK_M:
			_enter(mem, REST, WATCH, tick)
		else:
			_drop_target(mem)
			_enter(mem, WANDER, RETURN_HOME, tick, me.position)
		return
	_enter(mem, CHASE, PURSUE, tick, me.position)


static func _think_attack(mem: Memory, me: Dictionary, tick: int) -> void:
	if mem.phase == TELL:
		if mem.behavior == TERRITORIAL and _fresh(mem, mem.target, tick):
			if _past_exit(mem, Vector2(mem.seen[mem.target].position)):
				_emit(mem, {"type": "tell_cancelled", "target": mem.target, "reason": "left_territory"})
				_recover(mem, "cancelled", tick)
		return
	if mem.phase != RECOVER or tick - mem.phase_tick < mem.recover_ticks:
		return
	if mem.outcome == "cancelled":
		_drop_target(mem)
		_enter(mem, WANDER, RETURN_HOME, tick, me.position)
		return
	var reason := _give_up_reason(mem, me, tick)
	if not reason.is_empty():
		_give_up(mem, reason, tick)
		return
	var t := mem.target
	var wanted := _hungry(mem, me) if mem.behavior == AMBUSH else _intruding(mem, t, tick)
	if bool(mem.seen[t].engageable) and _can_engage(mem, me) and (wanted or t == mem.attacker):
		# Back to the chase; its next attack needs a new tell.
		_chase(mem, me, PURSUE, tick, false)
	else:
		_after_engagement(mem, tick)


static func _think_flee(mem: Memory, tick: int) -> void:
	if mem.seen.has(mem.attacker):
		mem.flee_from = _reckon(mem, mem.attacker, tick)
	if tick - mem.state_tick >= int(mem.cfg.flee_ticks):
		mem.flee_from = Vector2.INF
		_enter(mem, WANDER, RETURN_HOME, tick)


## Answers a hurt (pain), never during a strike: below the flee share it flees (a tell is
## interrupted), a fleeing creature flees again, and an idle one, or one noticing something else,
## notices the attacker. An engaged creature keeps its target. Returns true when it changed state.
static func _answer_pain(mem: Memory, me: Dictionary, tick: int) -> bool:
	if not mem.seen.has(mem.attacker):
		return false
	if float(me.health_share) < float(mem.cfg.flee_below) or mem.state == FLEE:
		if mem.state == ATTACK and mem.phase == TELL:
			_emit(mem, {"type": "creature_recovered", "target": mem.target, "outcome": "interrupted"})
		_drop_target(mem)
		mem.flee_from = _reckon(mem, mem.attacker, tick)
		_enter(mem, FLEE, "", tick)
		mem.state_tick = tick   # a flee that is hurt again starts over
		_emit(mem, {"type": "creature_fled", "from": mem.attacker})
		return true
	var idle := mem.state == REST or mem.state == WANDER or mem.state == FORAGE
	if idle or (mem.state == NOTICE and mem.target != mem.attacker):
		_notice(mem, mem.attacker, "pain", tick)
		return true
	return false


# --- drive helpers ---

static func _advance_attack(mem: Memory, me: Dictionary, tick: int) -> void:
	var attack: Dictionary = mem.cfg.attack
	if mem.phase == TELL and tick - mem.phase_tick >= int(attack.tell_ticks):
		_enter(mem, ATTACK, STRIKE, tick)
		_emit(mem, {"type": "creature_strike", "target": mem.target, "kind": attack.kind, "position": me.position,
			"heading": mem.lock_heading})
	if mem.phase == STRIKE and tick - mem.phase_tick >= int(attack.burst_ticks):
		_enter(mem, ATTACK, GLIDE, tick)
	if mem.phase == GLIDE and tick - mem.phase_tick >= int(attack.glide_ticks):
		_recover(mem, "missed", tick)


static func _drive_chase(mem: Memory, me: Dictionary, tick: int, arena: PoolArena) -> Dictionary:
	var share: float = mem.cfg.speeds.pursue
	if not mem.seen.has(mem.target):
		return _coast(mem, share)
	var target_at := _reckon(mem, mem.target, tick)
	var at: Vector2 = me.position
	if mem.phase == AIM:
		return _turn(mem, _face(me, target_at), share)
	# The stand-off point: on the line from the target through the creature, standoff_m out. From
	# too close this lies behind it, so it swims out first (a run-up). A point past the leash is
	# taken in to the leash circle: there it stops and turns to aim, instead of pressing outward
	# against the clamp, facing away from its target (the threat fuzz, invariant 7).
	var away := at - target_at
	var out := away / away.length() if away.length() > 1e-6 else Vector2.from_angle(float(me.heading) + PI)
	var standoff := target_at + out * float(mem.cfg.attack.standoff_m)
	var disc := leash_disc(mem)
	var reach: Vector2 = standoff - disc.center
	if reach.length() > float(disc.radius):
		standoff = disc.center + reach / reach.length() * float(disc.radius)
	if at.distance_to(standoff) <= FACE_AT_STANDOFF_M:
		return _turn(mem, _face(me, target_at), share)
	return _seek(mem, me, standoff, share, arena, true)


static func _drive_attack(mem: Memory, me: Dictionary) -> Dictionary:
	var out := _coast(mem, 1.0)
	match mem.phase:
		TELL:
			out.mode = MODE_TELL
			out.face = mem.lock_heading
		STRIKE, GLIDE:
			out.mode = MODE_BURST if mem.phase == STRIKE else MODE_GLIDE
			out.face = mem.lock_heading
			out.move = Vector2.from_angle(mem.lock_heading)
			out.strike = true
	return out


static func _drive_flee(mem: Memory, me: Dictionary, arena: PoolArena) -> Dictionary:
	var at: Vector2 = me.position
	var from := mem.flee_from if mem.flee_from.is_finite() else at - Vector2.from_angle(float(me.heading))
	var away := at - from
	away = away / away.length() if away.length() > 1e-6 else Vector2.from_angle(float(me.heading))
	# Near the leash circle, slide along it: drop the outward part of the way out.
	var disc := leash_disc(mem)
	var off: Vector2 = at - disc.center
	if off.length() > float(disc.radius) - FLEE_EDGE_M and off.length() > 1e-6:
		var n := off / off.length()
		var outward := away.dot(n)
		if outward > 0.0:
			away -= n * outward
			away = away / away.length() if away.length() > 1e-3 else n.orthogonal()
	return _seek(mem, me, at + away * FLEE_LOOKAHEAD_M, float(mem.cfg.speeds.flee), arena, false)


## Steers toward `goal` (round the first rock in the way), slowing on arrival when `arrive` is set
## so the body stops there without overshooting.
static func _seek(mem: Memory, me: Dictionary, goal: Vector2, share: float, arena: PoolArena, arrive: bool) -> Dictionary:
	var at: Vector2 = me.position
	var way := goal
	if arena != null:
		way = arena.route_point(at, goal, float(me.radius), PoolArena.ROUTE_CLEARANCE, PoolArena.ROUTE_MARGIN, mem.route_side)
	var to := way - at
	if to.length() < 1e-6:
		return _coast(mem, share)
	var throttle := 1.0
	if arrive:
		var top := maxf(float(me.speed) * share, 1e-3)
		var brake := float(me.acceleration) * Locomotion.BRAKE_FACTOR * ARRIVE_BRAKE_SHARE
		throttle = clampf(sqrt(2.0 * brake * at.distance_to(goal)) / top, 0.0, 1.0)
	var out := _coast(mem, share)
	out.move = to / to.length() * throttle
	return out


static func _coast(mem: Memory, share: float) -> Dictionary:
	return {"mode": MODE_STEER, "move": Vector2.ZERO, "speed_mul": share, "face": 0.0, "strike": false,
		"target": mem.target, "feed": ""}


static func _turn(mem: Memory, face: float, share: float) -> Dictionary:
	var out := _coast(mem, share)
	out.mode = MODE_TURN
	out.face = face
	return out


# --- decisions ---

## The first percept (nearest first) worth noticing now, or {}: prey for an ambush brain (another
## species it could bite), an intruder for a territorial one (another species of at least
## intruder_min_radius inside the territory). Nothing while settling, while hurt below the flee share,
## or for an ignored id.
static func _pick_new_target(mem: Memory, me: Dictionary, percepts: Array, tick: int) -> Dictionary:
	if tick < mem.ignore_all_until or not _can_engage(mem, me):
		return {}
	for p in percepts:
		if p.species == mem.cfg.species_id or mem.ignore.has(p.id):
			continue
		var r: float = p.radius
		if mem.behavior == AMBUSH:
			if r <= float(me.radius) * float(mem.cfg.prey_max_radius_share):
				return p
		elif r >= float(mem.cfg.intruder_min_radius) and Vector2(p.position).distance_to(mem.territory_center) <= mem.territory_r:
			return p
	return {}


static func _pick_food(mem: Memory, me: Dictionary, food: Array) -> Dictionary:
	var disc := leash_disc(mem)
	for f in food:
		var at: Vector2 = f.position
		# Food it cannot reach from inside its leash is no meal.
		if at.distance_to(disc.center) > float(disc.radius) + float(me.radius) + float(f.radius) + InteractionResolver.FEED_REACH:
			continue
		if mem.behavior == AMBUSH and at.distance_to(mem.home) > float(mem.cfg.forage_radius_m):
			continue
		if mem.behavior == TERRITORIAL and at.distance_to(mem.territory_center) > mem.territory_r:
			continue
		return f
	return {}


## Why the engagement should end now, or "": target_gone, lost (not perceived for the memory
## length), timer (no landed hit for give_up), leash (ambush: at its leash with the target farther
## out), left_territory (territorial: the target beyond territory + leash), unreachable (pursuing
## without moving unreachable_min_m for the unreachable window).
static func _give_up_reason(mem: Memory, me: Dictionary, tick: int) -> String:
	if not mem.gone.is_empty() and mem.gone == mem.target:
		return "target_gone"
	if not mem.seen.has(mem.target):
		return "lost"
	if tick - mem.engaged_tick >= int(mem.cfg.give_up_ticks):
		return "timer"
	var target_at := _reckon(mem, mem.target, tick)
	if mem.behavior == AMBUSH:
		var own := Vector2(me.position).distance_to(mem.home)
		if own >= float(mem.cfg.leash_m) - LEASH_GIVE_UP_M and target_at.distance_to(mem.home) > own:
			return "leash"
	elif target_at.distance_to(mem.territory_center) > mem.territory_r + float(mem.cfg.leash_m):
		return "left_territory"
	if mem.state == CHASE and mem.phase == PURSUE and not mem.progress.is_empty():
		if tick - int(mem.progress.tick) >= int(mem.cfg.unreachable_ticks):
			return "unreachable"
	return ""


static func _give_up_deadline(mem: Memory) -> int:
	var due := mem.engaged_tick + int(mem.cfg.give_up_ticks)
	if mem.seen.has(mem.target):
		due = mini(due, int(mem.seen[mem.target].tick) + int(mem.cfg.memory_ticks))
	return due


## The tell-start conditions: the target perceived now, in the window and aimed at, engageable, the
## creature nearly still (tell_start_max_speed), and the lane's end inside its leash disc.
static func _tell_ok(mem: Memory, me: Dictionary, tick: int) -> bool:
	if not _fresh(mem, mem.target, tick) or not bool(mem.seen[mem.target].engageable):
		return false
	if float(me.speed_now) > float(mem.cfg.tell_start_max_speed):
		return false
	if not (_in_window(mem, me, tick) and _aimed(mem, me, tick)):
		return false
	var lock := _lock_heading(mem, me, tick)
	var end: Vector2 = Vector2(me.position) + Vector2.from_angle(lock) * float(mem.cfg.attack.travel)
	var disc := leash_disc(mem)
	return end.distance_to(disc.center) <= float(disc.radius)


static func _lock_heading(mem: Memory, me: Dictionary, tick: int) -> float:
	var attack: Dictionary = mem.cfg.attack
	var e: Dictionary = mem.seen[mem.target]
	var lead: Vector2 = (Vector2(e.velocity) * float(attack.lead_s)).limit_length(float(attack.lead_cap_m))
	return _face(me, _reckon(mem, mem.target, tick) + lead)


static func _in_window(mem: Memory, me: Dictionary, tick: int) -> bool:
	if not mem.seen.has(mem.target):
		return false
	var d := Vector2(me.position).distance_to(_reckon(mem, mem.target, tick))
	return d >= float(mem.cfg.attack.start_min_m) and d <= float(mem.cfg.attack.start_max_m)


## The target is beyond the window and closing on it at APPROACH_WAIT_MPS or more: aim and let it come.
static func _approaching(mem: Memory, me: Dictionary, tick: int) -> bool:
	if not mem.seen.has(mem.target):
		return false
	var to_me: Vector2 = Vector2(me.position) - _reckon(mem, mem.target, tick)
	if to_me.length() <= float(mem.cfg.attack.start_max_m):
		return false
	return Vector2(mem.seen[mem.target].velocity).dot(to_me / to_me.length()) >= APPROACH_WAIT_MPS


static func _aimed(mem: Memory, me: Dictionary, tick: int) -> bool:
	if not mem.seen.has(mem.target):
		return false
	return absf(angle_difference(float(me.heading), _face(me, _reckon(mem, mem.target, tick)))) <= float(mem.cfg.attack.aim)


## Whether the ambush brain wants to pursue its target: hungry, or the target hurt it, or it once
## landed a hit on the target.
static func _wants_chase(mem: Memory, me: Dictionary) -> bool:
	return _hungry(mem, me) or mem.landed_on.has(mem.target) or mem.target == mem.attacker


## A territorial brain's puff rule: a target seen beyond territory_r + territory_exit_m is leaving.
static func _past_exit(mem: Memory, at: Vector2) -> bool:
	return at.distance_to(mem.territory_center) > mem.territory_r + float(mem.cfg.territory_exit_m)


static func _intruding(mem: Memory, id: String, tick: int) -> bool:
	return mem.seen.has(id) and _reckon(mem, id, tick).distance_to(mem.territory_center) <= mem.territory_r


static func _hungry(mem: Memory, me: Dictionary) -> bool:
	return float(me.energy_share) < float(mem.cfg.hungry_below)


## A creature hurt below its flee share starts nothing new.
static func _can_engage(mem: Memory, me: Dictionary) -> bool:
	return float(me.health_share) >= float(mem.cfg.flee_below)


static func _fresh(mem: Memory, id: String, tick: int) -> bool:
	return mem.seen.has(id) and int(mem.seen[id].tick) == tick


static func _touching(me: Dictionary, food: Dictionary) -> bool:
	var reach := float(me.radius) + float(food.radius) + InteractionResolver.FEED_REACH
	return Vector2(me.position).distance_to(food.position) <= reach


# --- memory and transitions ---

## Remembers every percept, then drops memories cfg.memory_ticks old and expired ignores.
static func _remember(mem: Memory, percepts: Array, tick: int) -> void:
	for p in percepts:
		mem.seen[p.id] = {"position": p.position, "velocity": p.velocity, "tick": tick, "by": p.by, "species": p.species,
			"radius": p.radius, "engageable": p.engageable}
	var memory: int = mem.cfg.memory_ticks
	for id in mem.seen.keys():
		if tick - int(mem.seen[id].tick) >= memory:
			mem.seen.erase(id)
	for id in mem.ignore.keys():
		if int(mem.ignore[id]) <= tick:
			mem.ignore.erase(id)


## Where a remembered body is now: its last position moved on by its last velocity for the age of
## the memory, at most dead_reckon_ticks.
static func _reckon(mem: Memory, id: String, tick: int) -> Vector2:
	var e: Dictionary = mem.seen[id]
	var age := mini(tick - int(e.tick), int(mem.cfg.dead_reckon_ticks))
	return Vector2(e.position) + Vector2(e.velocity) * (age * DT)


static func _face(me: Dictionary, p: Vector2) -> float:
	var to: Vector2 = p - Vector2(me.position)
	return to.angle() if to.length() > 1e-6 else float(me.heading)


static func _notice(mem: Memory, id: String, by: String, tick: int) -> void:
	mem.target = id
	mem.gone = ""
	mem.engaged_tick = tick
	_enter(mem, NOTICE, "", tick)
	_emit(mem, {"type": "creature_noticed", "target": id, "by": by})


## Into chase. From watching, the give-up timer starts now; from a notice or a recover it keeps
## running from the notice (or the last landed hit).
static func _chase(mem: Memory, me: Dictionary, phase: String, tick: int, restart_timer: bool) -> void:
	if restart_timer:
		mem.engaged_tick = tick
	_enter(mem, CHASE, phase, tick, me.position)


static func _give_up(mem: Memory, reason: String, tick: int) -> void:
	_emit(mem, {"type": "creature_gave_up", "target": mem.target, "reason": reason})
	mem.ignore[mem.target] = tick + int(mem.cfg.refractory_ticks)
	if mem.attacker == mem.target:
		mem.attacker = ""
	_drop_target(mem)
	_after_engagement(mem, tick)


## Where an engagement ends: an ambush brain goes home, a territorial one patrols.
static func _after_engagement(mem: Memory, tick: int) -> void:
	_drop_target(mem)
	if mem.behavior == AMBUSH:
		_enter(mem, WANDER, RETURN_HOME, tick)
	else:
		_enter(mem, WANDER, PATROL, tick)


static func _drop_target(mem: Memory) -> void:
	mem.target = ""
	mem.gone = ""
	mem.lock_heading = NAN
	mem.lane = {}


static func _recover(mem: Memory, outcome: String, tick: int) -> void:
	var attack: Dictionary = mem.cfg.attack
	mem.outcome = outcome
	match outcome:
		"blocked":
			mem.recover_ticks = attack.blocked_recover_ticks
		"cancelled":
			mem.recover_ticks = CANCEL_RECOVER_TICKS
		_:
			mem.recover_ticks = attack.recover_ticks
	mem.lock_heading = NAN
	mem.lane = {}
	_enter(mem, ATTACK, RECOVER, tick)
	_emit(mem, {"type": "creature_recovered", "target": mem.target, "outcome": outcome})


static func _rest(mem: Memory, tick: int) -> void:
	var span: Array = mem.cfg.rest_ticks
	mem.rest_until = tick + mem.rng.randi_range(int(span[0]), maxi(int(span[0]), int(span[1])))
	_enter(mem, REST, "", tick)


static func _start_forage(mem: Memory, me: Dictionary, tick: int) -> void:
	mem.food_id = ""
	mem.goal = Vector2.INF
	_enter(mem, FORAGE, SEEK, tick, me.position)


static func _set_goal(mem: Memory, p: Vector2, tick: int, at: Vector2) -> void:
	mem.goal = p
	mem.goal_tick = tick
	mem.route_side = 0
	mem.progress = {"position": at, "tick": tick}


## A random point within `r` of `center` that a body of this radius fits at, from the brain's RNG;
## home when GOAL_TRIES draws all land on rocks.
static func _random_point(mem: Memory, me: Dictionary, center: Vector2, r: float, arena: PoolArena) -> Vector2:
	for i in GOAL_TRIES:
		var p := center + Vector2.from_angle(mem.rng.randf() * TAU) * (sqrt(mem.rng.randf()) * r)
		if arena == null or arena.is_clear(p, float(me.radius)):
			return p
	return mem.home


## Navigation recovery: a body that moved less than unreachable_min_m over the unreachable window
## re-plans round the other side of the rock in its way (the RNG picks the first side).
static func _check_progress(mem: Memory, me: Dictionary, tick: int) -> void:
	if mem.progress.is_empty():
		mem.progress = {"position": me.position, "tick": tick}
		return
	if Vector2(me.position).distance_to(mem.progress.position) >= float(mem.cfg.unreachable_min_m):
		mem.progress = {"position": me.position, "tick": tick}
	elif tick - int(mem.progress.tick) >= int(mem.cfg.unreachable_ticks):
		mem.route_side = (mem.rng.randi_range(0, 1) * 2 - 1) if mem.route_side == 0 else -mem.route_side
		mem.progress = {"position": me.position, "tick": tick}


## The pursuit's progress anchor: it moves on whenever the body has moved unreachable_min_m from it.
static func _track_progress(mem: Memory, me: Dictionary, tick: int) -> void:
	if mem.progress.is_empty() or Vector2(me.position).distance_to(mem.progress.position) >= float(mem.cfg.unreachable_min_m):
		mem.progress = {"position": me.position, "tick": tick}


## Changes state and phase. A new state restarts state_tick; every change restarts phase_tick and the
## route side, and every change but into eating drops the goal point. With `at` given, the progress
## anchor starts there; otherwise it starts at the next think.
static func _enter(mem: Memory, state: String, phase: String, tick: int, at := Vector2.INF) -> void:
	var before := _label(mem.state, mem.phase)
	if state != mem.state:
		mem.state_tick = tick
	mem.state = state
	mem.phase = phase
	mem.phase_tick = tick
	mem.route_side = 0
	mem.progress = {"position": at, "tick": tick} if at.is_finite() else {}
	if not (state == FORAGE and phase == EAT):
		mem.goal = Vector2.INF
	if mem.trace and before != _label(state, phase):
		_emit(mem, {"type": "creature_state", "from": before, "to": _label(state, phase)})


static func _label(state: String, phase: String) -> String:
	return state if phase.is_empty() else "%s/%s" % [state, phase]


static func _emit(mem: Memory, event: Dictionary) -> void:
	mem.events.append(event)


static func _pair(v: Vector2) -> Array:
	return [v.x, v.y]


static func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys
