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
## All lengths are current tm; all times are ticks of PoolSim.DT.

const NEVER := CreatureBrain.NEVER
## A meter within this of the ring counts as full (float rounding in the drain's sums).
const FULL_EPSILON := 1e-9
## The sizes the ring table covers: rings[n - 1] is the ring at size n; past it there is no next size.
const LAST_RING_SIZE := 9

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


## The end of every endless tick (D-20), on this tick's events.
func observe(sim: PoolSim, _ev: Array) -> void:
	# 1. The player's trigger, through the intent.
	var wanted := sim.intent_trigger
	if (wanted == "auto" or wanted == "press") and wanted != trigger:
		trigger = wanted
		armed = false
	if sim.dead or sim.respawn_pending:
		return
	_drain(sim)


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
