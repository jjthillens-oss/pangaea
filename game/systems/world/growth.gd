class_name Growth
extends RefCounted
## The growth meter (S2, plan B.2 and B.3): a ring round the cell that fills as it eats, and the
## decision to grow. PoolSim owns one in the endless world when the world file switches growth on
## (null in the pool and with growth off, so those ticks are exactly S1's: D-46). It is pure sim
## state: it reads the sim at the end of every tick (observe, D-20) and never a clock, input or the
## scene; the player's choices come in through the tick's intent (SimIntent.grow and trigger).
##
## The meter. Every input goes through add(): the drain moves energy above drain_floor_share of the
## capacity into the meter at most ring / drain_ring_seconds a second, so a full ring takes at least
## that long and a fed cell is no longer always full (balance input 1). When the meter reaches the
## ring it is full (ring_full); at the build top (size == max_in_build) a full ring pays out at once
## instead (D-32): energy to capacity, top_payout_points through Lineage.earn, the meter back to 0.
##
## The decision (B.3, D-86). While the ring is full below the build top, every tick is calm or names
## its blocker (blocker_of: "hunted", "chasing", "eating", "wedged", in that order). A calm tick counts
## towards calm_ticks: in press mode once the player has armed it (G), in auto mode once the showcase
## window is over or a creature that will flip at the next size is in view; calm_ticks reaching
## cfg.calm_ticks sets `due`, and the next tick's streaming step 1 grows. A blocked tick resets the
## count; blocked for blocked_hint_s, the blocker is named (growth_blocked) until a calm tick clears it
## (growth_unblocked). hint() is the HUD's line for all this.
##
## All lengths are current tm; all times are ticks of PoolSim.DT.

const NEVER := CreatureBrain.NEVER
## A meter within this of the ring counts as full (float rounding in the drain's sums).
const FULL_EPSILON := 1e-9
## The sizes the ring table covers: rings[n - 1] is the ring at size n; past it there is no next size.
const LAST_RING_SIZE := 9
## The HUD lines (spine 3.15): hint() returns one of these or "". BP-19: the HUD shows the bound key in
## place of the "(G)".
const HINT_GROWING := "Growing…"
const HINT_READY := "Ready to grow (G)"
const HINT_NOT_WHILE_HUNTED := "Not while something is hunting you"
const BLOCKER_HINTS := {
	"hunted": "Ring full: something is hunting you",
	"chasing": "Ring full: stop chasing to grow",
	"eating": "Ring full: stop eating to grow",
	"wedged": "Ring full: get clear of the shells",
}
## A brain in one of these attack phases, aimed at the cell, hunts it.
const AIMED_PHASES: PackedStringArray = [CreatureBrain.TELL, CreatureBrain.STRIKE, CreatureBrain.GLIDE]

var cfg: Dictionary                 ## the world file's growth block (WorldConfig.growth)
var trigger := "auto"               ## "auto" | "press" (the player's setting, through the intent)
var armed := false                  ## press mode: G pressed, waiting for calm
var meter := 0.0
var calm_ticks := 0                 ## consecutive calm ticks while the ring is full
var full_since := -1                ## tick the ring filled at this size; -1 not full
var blocked_ticks := 0              ## consecutive not-calm ticks while full
var blocker := ""                   ## "" | "hunted" | "chasing" | "eating" | "wedged"
var due := false                    ## grow in the next tick's streaming step 1
var beat_until := -1
var last_meal := -NEVER             ## D-81: -1 would make the first two seconds of a run "not quiet"
var last_bite := -NEVER
var last_ram := -NEVER
## [[tick, {creature id: distance}], ...], oldest first, at most chase_window_ticks + 1 entries.
var closing: Array = []
## Kinds, models and looks already paid at this size, each sorted.
var paid := {"place": [], "landmark": [], "food": []}
## [{type, id, size}] this lineage, in find order.
var discoveries: Array = []
var energy_at_death := -1.0
## The prefetch of the next size's chunks (BP-4): it runs while meter >= prefetch_share x ring, at
## most prefetch_per_tick chunks a tick.
var prefetch_share := 0.9
var prefetch_per_tick := 1


static func create(p_cfg: Dictionary, p_trigger: String) -> Growth:
	var g := Growth.new()
	g.cfg = p_cfg
	g.trigger = p_trigger
	g.prefetch_share = float(p_cfg.prefetch_share)
	g.prefetch_per_tick = int(p_cfg.prefetch_per_tick)
	return g


## The world file's growth block when it switches growth on, else {} (growth off: D-46).
static func config_of(config: WorldConfig) -> Dictionary:
	return config.growth if bool(config.switches.get("growth", false)) else {}


## The ring at size `n`: rings[n - 1], or 0.0 past the table (no next size).
func ring(n: int) -> float:
	if n < 1 or n > LAST_RING_SIZE:
		return 0.0
	return float(cfg.rings[n - 1])


func is_full(n: int) -> bool:
	var r := ring(n)
	return r > 0.0 and meter >= r - FULL_EPSILON


static func at_top(n: int, max_in_build: int) -> bool:
	return n >= max_in_build


## Every meter input: `amount` is added up to the ring. Any reason but the drain reports the part
## kept (meter_lump). Reaching the ring marks it full (ring_full); at the build top it pays out at
## once (D-32).
func add(sim: PoolSim, amount: float, reason: String, id: String) -> void:
	var n := sim.size()
	var r := ring(n)
	var before := meter
	meter = minf(meter + amount, r)
	if reason != "drain":
		sim._emit({"type": "meter_lump", "reason": reason, "amount": meter - before, "id": id})
	if is_full(n) and full_since < 0:
		meter = r
		full_since = sim.tick
		sim._emit({"type": "ring_full", "size": n, "ring": r})
	if is_full(n) and at_top(n, sim.world.max_size):
		sim.refill_energy()
		var points := Lineage.earn(sim.save, int(cfg.top_payout_points))
		sim._emit({"type": "earned", "points": points, "reason": "ring"})
		sim._emit({"type": "ring_paid", "size": n, "energy": sim.state.energy_capacity, "points": points})
		meter = 0.0
		full_since = -1


## The end of every endless tick (D-20), on this tick's events, in s2-sim 3.5's order.
func observe(sim: PoolSim, ev: Array) -> void:
	# 1. The player's trigger, through the intent.
	var wanted := sim.intent_trigger
	if (wanted == "auto" or wanted == "press") and wanted != trigger:
		trigger = wanted
		armed = false
	# 2. The tick's events: the cell's own bites, rams and meals.
	for e: Dictionary in ev:
		match str(e.type):
			"hit":
				if str(e.attacker) == CreatureField.PLAYER_ID:
					if e.kind == "bite":
						last_bite = sim.tick
					elif e.kind == "ram":
						last_ram = sim.tick
			"ate":
				last_meal = sim.tick
	# 3. Nothing more while dead or waiting to respawn.
	if sim.dead or sim.respawn_pending:
		return
	var n := sim.size()
	_drain(sim)   # 4
	_note_closing(sim)   # 5
	# 6. Only a full ring below the top has a window.
	if not is_full(n) or at_top(n, sim.world.max_size):
		calm_ticks = 0
		blocked_ticks = 0
		blocker = ""
		if not is_full(n):
			armed = false
		return
	var now_blocker := blocker_of(sim)   # 7
	# 8. A press arms it, and says why it waits.
	if sim.intent_grow:
		armed = true
		if not now_blocker.is_empty():
			sim._emit({"type": "growth_waiting", "reason": now_blocker})
	# 9. The window (D-86).
	var hint_at := _hint_ticks()
	if now_blocker.is_empty():
		if blocked_ticks >= hint_at:
			sim._emit({"type": "growth_unblocked"})
		blocked_ticks = 0
		blocker = ""
		var counts := armed if trigger == "press" else (calm_ticks > 0
			or sim.tick - full_since >= CreatureBrain.ticks(cfg.showcase_s) or _flip_in_view(sim, n))
		if counts:
			calm_ticks += 1
			if calm_ticks == int(cfg.calm_ticks):
				due = true
	else:
		calm_ticks = 0
		blocked_ticks += 1
		if blocked_ticks == hint_at or (blocked_ticks > hint_at and now_blocker != blocker):
			sim._emit({"type": "growth_blocked", "blocker": now_blocker})
		blocker = now_blocker


## The first B.3 calm condition the tick fails, in priority order (BP-5), or "" when it is calm:
## - "hunted": a creature holds the token on the cell, aims a tell, strike or glide at it, or touches
##   it (within both radii and PoolSim.TOUCH_MARGIN);
## - "chasing": the cell bit or rammed within quiet_ticks, or closed more than chase_close_tm over
##   chase_window_ticks on a fleeing creature it could hurt (the closing history);
## - "eating": the cell ate within quiet_ticks;
## - "wedged" (only `with_wedge`, below the build top): the next size has no clear point within its
##   four rings round the cell (WorldStream.next_size_clear_point is INF, BP-4).
## Pure: it reads the sim and this meter's history, at any size. The wedge is tested last, so the point
## is computed only on ticks that are otherwise calm.
func blocker_of(sim: PoolSim, with_wedge := true) -> String:
	if _hunted(sim):
		return "hunted"
	var quiet := int(cfg.quiet_ticks)
	if sim.tick - last_bite < quiet or sim.tick - last_ram < quiet or _closing_in():
		return "chasing"
	if sim.tick - last_meal < quiet:
		return "eating"
	if with_wedge and not at_top(sim.size(), sim.world.max_size) and not sim.world.next_size_clear_point(sim).is_finite():
		return "wedged"
	return ""


## The HUD's line (spine 3.15), "" for none: "Growing…" while a full ring counts its calm ticks; the
## blocker's line once it has blocked for blocked_hint_s; in press mode, armed and hunted, "Not while
## something is hunting you" at once; in press mode, full and not armed, "Ready to grow (G)".
func hint() -> String:
	var full := full_since >= 0   # a full ring at the top pays out at once, so this is full below it
	if full and calm_ticks > 0:
		return HINT_GROWING
	if full and blocked_ticks >= _hint_ticks() and BLOCKER_HINTS.has(blocker):
		return BLOCKER_HINTS[blocker]
	if trigger == "press" and armed and blocker == "hunted":
		return HINT_NOT_WHILE_HUNTED
	if trigger == "press" and full and not armed:
		return HINT_READY
	return ""


func _hint_ticks() -> int:
	return CreatureBrain.ticks(cfg.blocked_hint_s)


func _hunted(sim: PoolSim) -> bool:
	if sim.creatures == null:
		return false
	if not sim.creatures.engaged_on_player.is_empty():
		return true
	var at := sim.motion.position
	var r_cell := sim.phenotype.radius
	for c in sim.creatures.awake():
		var b := c.brain
		if b != null and b.state == CreatureBrain.ATTACK and b.target == CreatureField.PLAYER_ID and AIMED_PHASES.has(b.phase):
			return true
		if at.distance_to(c.motion.position) <= r_cell + c.phenotype.radius + PoolSim.TOUCH_MARGIN:
			return true
	return false


## Step 5: this tick's distances to every fleeing creature within chase_track_tm that the cell could
## hurt (its jaw can bite it, or one of its spikes faces it), ids sorted; entries older than
## chase_window_ticks drop off the front.
func _note_closing(sim: PoolSim) -> void:
	var d := {}
	if sim.creatures != null:
		var at := sim.motion.position
		var track := float(cfg.chase_track_tm)
		for c in sim.creatures.awake():
			if c.brain == null or c.brain.state != CreatureBrain.FLEE:
				continue
			var dist := at.distance_to(c.motion.position)
			if dist <= track and _can_hurt(sim, c.motion.position, c.phenotype.radius):
				d[c.id] = dist
	var ids := d.keys()
	ids.sort()
	var sorted := {}
	for id in ids:
		sorted[id] = d[id]
	closing.append([sim.tick, sorted])
	var oldest := sim.tick - int(cfg.chase_window_ticks)
	while not closing.is_empty() and int(closing[0][0]) < oldest:
		closing.pop_front()


## The cell's jaw can bite a body of radius `r`, or one of its spikes faces `pos`.
static func _can_hurt(sim: PoolSim, pos: Vector2, r: float) -> bool:
	var p := sim.phenotype
	if p.bite_damage > 0.0 and r <= p.radius * InteractionResolver.BITE_SIZE_LIMIT:
		return true
	for spike in p.spikes:
		if absf(angle_difference(float(spike.angle), InteractionResolver.relative_angle(sim.actor, pos))) <= float(spike.arc) / 2.0:
			return true
	return false


## Chasing by the history: a creature in both the newest entry and the one chase_window_ticks before
## it is more than chase_close_tm nearer now.
func _closing_in() -> bool:
	if closing.size() < 2:
		return false
	var now: Array = closing[-1]
	var then: Array = closing[0]
	if int(then[0]) != int(now[0]) - int(cfg.chase_window_ticks):
		return false
	var d_now: Dictionary = now[1]
	var d_then: Dictionary = then[1]
	for id in d_now:
		if d_then.has(id) and float(d_then[id]) - float(d_now[id]) > float(cfg.chase_close_tm):
			return true
	return false


## D-49: an awake creature drawn at this size (q 1) that will be a rival or prey at the next, in the
## camera's view of the cell.
static func _flip_in_view(sim: PoolSim, n: int) -> bool:
	if sim.creatures == null:
		return false
	var cam: Dictionary = sim.layout.camera
	var aspect := float(sim.species.fairness.spawn_view_aspect)
	for c in sim.creatures.awake():
		if c.scripted or not sim.species.has_species(c.species_id) or sim.species.q_of(c.species_id, n) != 1.0:
			continue
		var role := str(sim.species.at_size(c.species_id, n + 1).get("ladder_role", ""))
		if role != "rival" and role != "prey":
			continue
		if ViewFootprint.contains(sim.motion.position, c.motion.position, cam, float(cam.distance), aspect, c.phenotype.radius):
			return true
	return false


## Step 4: energy above the floor share of the capacity moves into the meter, at most
## ring / drain_ring_seconds a second, never past the ring.
func _drain(sim: PoolSim) -> void:
	var n := sim.size()
	var r := ring(n)
	var cap := sim.state.energy_capacity
	var floor_e := float(cfg.drain_floor_share) * cap
	if sim.state.energy <= floor_e or r - meter <= 0.0:
		return
	var amount := minf(r / float(cfg.drain_ring_seconds) * PoolSim.DT, minf(sim.state.energy - floor_e, r - meter))
	sim.state.energy -= amount
	add(sim, amount, "drain", "")


## The meter's state for the endless snapshot (spine 3.12): closing ids and paid lists sorted.
func snapshot() -> Dictionary:
	var hist := []
	for entry: Array in closing:
		var d: Dictionary = entry[1]
		var ids := d.keys()
		ids.sort()
		var sorted := {}
		for id in ids:
			sorted[id] = d[id]
		hist.append([entry[0], sorted])
	return {"trigger": trigger, "armed": armed, "meter": meter, "calm": calm_ticks, "full_since": full_since,
		"blocked": blocked_ticks, "blocker": blocker, "due": due, "beat_until": beat_until,
		"last_meal": last_meal, "last_bite": last_bite, "last_ram": last_ram, "closing": hist,
		"paid": {"place": paid.place.duplicate(), "landmark": paid.landmark.duplicate(), "food": paid.food.duplicate()},
		"discoveries": discoveries.size(), "energy_at_death": energy_at_death}
