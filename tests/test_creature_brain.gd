extends TestCase
## CreatureBrain (M1 step 3) with synthetic percepts: the brain decides only from what it is told
## it senses, and these tests tell it exactly that. Timings are integer ticks (60 Hz). The species
## blocks below are the step 3 plan's creatures_m1.json values.

const DT := 1.0 / 60.0
const AI := {"think_hz": 10.0, "engaged_think_hz": 20.0, "dead_reckon_cap_s": 0.5, "unreachable_window_s": 2.0,
	"unreachable_min_m": 0.5, "return_fail_limit": 3, "settle_s": 3.0, "tell_start_max_speed": 0.3}
const AMBUSH_BLOCK := {
	"behavior": "ambush", "body_size": 1.5,
	"metabolism_share": 0.1, "start_energy_share": 0.9, "hungry_below": 0.6, "full_above": 0.85,
	"senses": {"fov_deg": 200.0, "near_m": 1.0, "memory_s": 2.0},
	"speeds": {"wander": 0.5, "forage": 0.6, "pursue": 0.85, "flee": 1.0},
	"prey_max_radius_share": 1.6,
	"notice_s": 0.5, "give_up_s": 5.0, "leash_m": 9.0,
	"forage_radius_m": 18.0, "forage_timeout_s": 30.0, "forage_retry_s": 20.0,
	"refractory_s": 6.0, "nav_timeout_s": 20.0,
	"attack": {"kind": "bite", "tell": "lunge", "start_min_m": 2.5, "start_max_m": 3.0, "standoff_m": 2.75, "aim_deg": 20.0,
		"lead_s": 1.2, "lead_cap_m": 1.0, "tell_s": 1.2,
		"burst_speed": 4.5, "burst_s": 0.35, "glide_s": 0.25, "glide_drag": 6.0,
		"recover_s": 1.0, "blocked_recover_s": 1.0, "knockback": 1.5},
	"flee": {"below_health_share": 0.35, "for_s": 4.0},
}
const RAMMER_BLOCK := {
	"behavior": "territorial", "body_size": 1.25,
	"metabolism_share": 0.25, "start_energy_share": 0.6, "hungry_below": 0.7, "full_above": 0.9,
	"senses": {"fov_deg": 270.0, "near_m": 0.8, "memory_s": 3.0},
	"speeds": {"wander": 0.45, "forage": 0.5, "pursue": 1.0, "flee": 1.0},
	"intruder_min_radius": 0.3,
	"notice_s": 0.5, "give_up_s": 8.0, "territory_margin_m": 2.0, "territory_exit_m": 1.0, "leash_m": 3.0,
	"rest_s": [4.0, 8.0], "refractory_s": 3.0, "nav_timeout_s": 8.0,
	"attack": {"kind": "ram", "tell": "puff", "start_min_m": 3.0, "start_max_m": 5.0, "standoff_m": 4.0, "aim_deg": 15.0,
		"lead_s": 1.6, "lead_cap_m": 1.2, "tell_s": 1.2,
		"burst_speed": 4.0, "burst_s": 0.9, "glide_s": 0.3, "glide_drag": 5.0,
		"recover_s": 1.2, "blocked_recover_s": 2.0, "knockback": 2.5},
	"flee": {"below_health_share": 0.4, "for_s": 5.0},
}
const AMBUSH_PARTS := [["mouth_jaw", 0.0], ["flagellum", 2.8], ["flagellum", -2.8]]
const RAMMER_PARTS := [["mouth_filter", 0.0], ["spike", 0.3, 0.8], ["spike", -0.3, 0.8], ["spike", 1.9, 0.8],
	["spike", -1.9, 0.8], ["flagellum", 3.14159]]
const ZONE_R := 6.0   ## the rammer's zone; its territory is this plus the 2 m margin

var catalog: PartCatalog
var ambush_cfg: Dictionary
var rammer_cfg: Dictionary
var ambush_body: Phenotype
var rammer_body: Phenotype


## One creature: a brain and a body. The body moves by the brain's drive, or stays where the test
## puts it (moving = false), so the brain sees exactly the self the test scripts.
class Critter:
	var mem: CreatureBrain.Memory
	var m: Locomotion.MotionState
	var p: Phenotype
	var number := 1
	var health_share := 1.0
	var energy_share := 0.9
	var events: Array[Dictionary] = []

	func view() -> Dictionary:
		return {"id": "c_%d" % number, "species": mem.cfg.species_id, "position": m.position, "heading": m.heading,
			"velocity": m.velocity, "speed_now": m.velocity.length(), "radius": p.radius, "speed": p.speed,
			"acceleration": p.acceleration, "health_share": health_share, "energy_share": energy_share}

	func label() -> String:
		return mem.state if mem.phase.is_empty() else "%s/%s" % [mem.state, mem.phase]

	## Its events of one type, in order, each with the tick it came on.
	func of(type: String) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for e in events:
			if e.type == type:
				out.append(e)
		return out

	func first_tick(type: String) -> int:
		var found := of(type)
		return -1 if found.is_empty() else int(found[0].tick)


func before_each() -> void:
	catalog = PartCatalog.load_from()
	ambush_cfg = CreatureBrain.config("ambush_hunter", AMBUSH_BLOCK, AI)
	rammer_cfg = CreatureBrain.config("rammer", RAMMER_BLOCK, AI)
	ambush_body = _derive(AMBUSH_PARTS, 1.5)
	rammer_body = _derive(RAMMER_PARTS, 1.25)


func _derive(parts: Array, size: float) -> Phenotype:
	var genome := Genome.create(StableId.generate("lineage"))
	for part in parts:
		genome.add_part(part[0], part[1], part[2] if part.size() > 2 else 1.0)
	return Phenotype.derive(genome, catalog, size)


## A settled ambush hunter at `home` facing `heading`, sated (energy 0.9) and unhurt.
func _ambush(home := Vector2.ZERO, heading := 0.0, settled := true, seed_value := 11) -> Critter:
	var c := Critter.new()
	c.mem = CreatureBrain.create("ambush", ambush_cfg, home, heading, {}, seed_value, 0)
	if settled:
		c.mem.ignore_all_until = 0
	c.m = Locomotion.MotionState.new(home, heading)
	c.p = ambush_body
	return c


## A settled rammer guarding the zone at `center` (territory 8 m, leash disc 11 m), sated.
func _rammer(home := Vector2(0.0, -2.0), heading := PI / 2.0, center := Vector2.ZERO, seed_value := 11) -> Critter:
	var c := Critter.new()
	c.mem = CreatureBrain.create("territorial", rammer_cfg, home, heading, {"center": center, "radius": ZONE_R}, seed_value, 0)
	c.mem.ignore_all_until = 0
	c.m = Locomotion.MotionState.new(home, heading)
	c.p = rammer_body
	return c


## A percept of a body at `at` as the creature senses it now (sight unless `extra` says otherwise).
func _percept(c: Critter, id: String, at: Vector2, extra := {}) -> Dictionary:
	var b := {"id": id, "species": "lineage", "position": at, "velocity": Vector2.ZERO, "radius": 0.5, "by": "sight",
		"engageable": true, "bite": false, "spikes": 0}
	b.merge(extra, true)
	var v := c.view()
	b["distance"] = Vector2(v.position).distance_to(at)
	b["bearing"] = CreatureSenses.bearing(v, at)
	return b


## One tick as the sim runs it: think when due, drive, then move (or hold the body, shifted by
## `drift`), clamp to the leash, and collect events stamped with the tick.
func _tick(c: Critter, tick: int, percepts: Array, moving := true, drift := Vector2.ZERO, food: Array = [],
		arena: PoolArena = null) -> Dictionary:
	if CreatureBrain.think_due(c.mem, c.number, tick):
		CreatureBrain.think(c.mem, c.view(), percepts, food, tick, arena)
	var d := CreatureBrain.drive(c.mem, c.view(), tick, arena)
	if moving:
		CreatureBrain.move_body(c.mem, c.m, d, c.p, 1.0, DT)
		if arena != null:
			arena.move(c.m, c.p.radius, DT)
		else:
			c.m.prev_position = c.m.position
			c.m.position += c.m.velocity * DT
		var disc := CreatureBrain.leash_disc(c.mem)
		PoolArena.clamp_to_disc(c.m, disc.center, disc.radius)
	else:
		c.m.position += drift
	_collect(c, tick)
	return d


func _collect(c: Critter, tick: int) -> void:
	for e in c.mem.events:
		var copy: Dictionary = e.duplicate()
		copy["tick"] = tick
		c.events.append(copy)
	c.mem.events.clear()


## Runs ticks from..to-1 with the same still body `id` at `at` in view; returns the tick after.
func _run(c: Critter, from: int, to: int, id: String, at: Vector2, moving := true) -> int:
	for t in range(from, to):
		_tick(c, t, [_percept(c, id, at)], moving)
	return to


func _no_vectors(value: Variant) -> bool:
	match typeof(value):
		TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3:
			return false
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_DICTIONARY:
			for k in value:
				if not _no_vectors(value[k]):
					return false
		TYPE_ARRAY:
			for v in value:
				if not _no_vectors(v):
					return false
	return true


# --- config ---

func test_the_config_turns_every_duration_into_the_plans_tick_counts() -> void:
	# Notice, tell, burst, glide, recover, blocked recover, give-up, memory, refractory, flee, nav timeout, settle.
	var want := {"ambush": [30, 72, 21, 15, 60, 60, 300, 120, 360, 240, 1200, 180],
		"rammer": [30, 72, 54, 18, 72, 120, 480, 180, 180, 300, 480, 180]}
	for key in want:
		var cfg: Dictionary = ambush_cfg if key == "ambush" else rammer_cfg
		var a: Dictionary = cfg.attack
		var got := [cfg.notice_ticks, a.tell_ticks, a.burst_ticks, a.glide_ticks, a.recover_ticks, a.blocked_recover_ticks,
			cfg.give_up_ticks, cfg.memory_ticks, cfg.refractory_ticks, cfg.flee_ticks, cfg.nav_timeout_ticks, cfg.settle_ticks]
		check_eq(got, want[key], key)
		check_eq([cfg.think_ticks, cfg.engaged_think_ticks, cfg.dead_reckon_ticks, cfg.unreachable_ticks], [6, 3, 30, 120], key + " ai")
	check_eq(rammer_cfg.rest_ticks, [240, 480], "rammer rest")
	check_eq([ambush_cfg.forage_timeout_ticks, ambush_cfg.forage_retry_ticks], [1800, 1200], "ambush forage")
	check_near(ambush_cfg.attack.aim, deg_to_rad(20.0), 1e-9, "aim in radians")
	check_near(ambush_cfg.attack.travel, 2.129, 0.001, "lunge travel, per tick")
	check_near(rammer_cfg.attack.travel, 4.196, 0.001, "charge travel, per tick")
	check_near(ambush_cfg.attack.reach, InteractionResolver.BITE_REACH, 1e-9, "a bite reaches like the resolver's")
	check_near(rammer_cfg.attack.reach, InteractionResolver.RAM_REACH, 1e-9, "a ram reaches like the resolver's")
	check_eq(CreatureBrain.ticks(0.35), 21, "0.35 s")
	check_eq(CreatureBrain.ticks(1.2), 72, "1.2 s")


# --- 1. noticing ---

func test_a_resting_hunter_notices_prey_but_not_its_kind_a_body_too_big_an_ignored_id_or_anything_while_settling() -> void:
	var ahead := Vector2(2.0, 0.0)
	var c := _ambush()
	_run(c, 0, 7, "a", ahead)
	check_eq(c.label(), "notice", "prey in view")
	check_eq(c.mem.target, "a", "the prey is the target")
	var noticed := c.of("creature_noticed")
	check_eq(noticed.size(), 1, "one notice")
	if not noticed.is_empty():
		check_eq(noticed[0].by, "sight", "noticed by sight")
	var kin := _ambush()
	for t in 60:
		_tick(kin, t, [_percept(kin, "c_9", ahead, {"species": "ambush_hunter", "radius": 0.75})])
	check_eq(kin.label(), "rest/lurk", "its own kind is not prey")
	var big := _ambush()
	for t in 60:
		_tick(big, t, [_percept(big, "big", ahead, {"species": "rammer", "radius": 1.21})])
	check_eq(big.label(), "rest/lurk", "a body over 1.6 times its radius cannot be bitten, so it is not prey")
	var edge := _ambush()
	for t in 7:
		_tick(edge, t, [_percept(edge, "edge", ahead, {"species": "rammer", "radius": 1.2})])
	check_eq(edge.label(), "notice", "exactly 1.6 times its radius is prey")
	var ignoring := _ambush()
	ignoring.mem.ignore["a"] = 1000
	for t in 7:
		_tick(ignoring, t, [_percept(ignoring, "a", ahead)])
	check_eq(ignoring.label(), "rest/lurk", "an ignored id is not noticed")
	for t in range(7, 14):
		_tick(ignoring, t, [_percept(ignoring, "a", ahead), _percept(ignoring, "b", Vector2(3.0, 0.5))])
	check_eq(ignoring.mem.target, "b", "another id is")
	var settling := _ambush(Vector2.ZERO, 0.0, false)
	_run(settling, 0, 200, "a", ahead)
	var at := settling.first_tick("creature_noticed")
	check(at >= 180 and at < 186, "a new creature notices nothing while it settles (180 ticks), then at its next think: %d" % at)


# --- 2. notice ---

func test_notice_lasts_exactly_thirty_ticks_then_a_hungry_hunter_chases_and_a_sated_one_watches() -> void:
	for hungry in [true, false]:
		for number in [1, 4]:
			var c := _ambush()
			c.number = number
			c.energy_share = 0.5 if hungry else 0.9
			var labels := []
			for t in 90:
				_tick(c, t, [_percept(c, "a", Vector2(4.0, 0.0))], false)
				labels.append(c.label())
			var start := c.first_tick("creature_noticed")
			var name := "%s, number %d" % ["hungry" if hungry else "sated", number]
			check(start >= 0, name + ": noticed")
			if start < 0:
				continue
			check_eq(labels[start + 29], "notice", name + ": still noticing 29 ticks on")
			check_eq(labels[start + 30], "chase/pursue" if hungry else "rest/watch", name + ": 30 ticks on")


func test_a_body_that_is_not_engageable_is_watched_by_a_hunter_and_held_in_notice_by_a_rammer() -> void:
	var hunter := _ambush()
	hunter.energy_share = 0.5
	for t in 120:
		_tick(hunter, t, [_percept(hunter, "a", Vector2(4.0, 0.0), {"engageable": false})], false)
	check_eq(hunter.label(), "rest/watch", "a hungry hunter without the token only watches")
	check(not CreatureBrain.is_engaged_with(hunter.mem, "a"), "watching is not engagement")
	var rammer := _rammer()
	for t in 200:
		_tick(rammer, t, [_percept(rammer, "a", Vector2(0.0, 3.0), {"engageable": false})], false)
	check_eq(rammer.label(), "notice/wait", "a rammer without the token stays in notice")
	check(not CreatureBrain.is_engaged_with(rammer.mem, "a"), "noticing is not engagement")
	for t in range(200, 500):
		_tick(rammer, t, [_percept(rammer, "a", Vector2(0.0, 3.0), {"engageable": false})], false)
	var gave_up := rammer.of("creature_gave_up")
	check_eq(gave_up.size(), 1, "the wait ends by the give-up timer, so it cannot last forever")
	if not gave_up.is_empty():
		check_eq(gave_up[0].reason, "timer", "reason")
		check_eq(int(gave_up[0].tick) - rammer.first_tick("creature_noticed"), 480, "at the rammer's give-up time")


func test_a_watching_hunter_aims_only_at_a_target_in_its_window_in_front_that_it_may_engage() -> void:
	var cases := [
		["in window, ahead", Vector2(2.75, 0.0), true, false, "chase/aim"],
		["too far", Vector2(4.0, 0.0), true, false, "rest/watch"],
		["not engageable", Vector2(2.75, 0.0), false, false, "rest/watch"],
		["off to the side, held still", Vector2(0.0, 2.75), true, false, "rest/watch"],
		["off to the side, free to turn", Vector2(0.0, 2.75), true, true, "chase/aim"],
	]
	for case in cases:
		var c := _ambush()
		var labels := []
		for t in 150:
			_tick(c, t, [_percept(c, "a", case[1], {"engageable": case[2]})], case[3])
			labels.append(c.label())
			if c.mem.state == "attack":
				break
		check(labels.has("rest/watch"), "%s: watched first" % case[0])
		check(labels.has(case[4]), "%s: reaches %s (%s)" % [case[0], case[4], labels.back()])
		if case[4] == "rest/watch":
			check(not labels.has("chase/aim"), "%s: never aims" % case[0])


func test_a_sated_hunter_pushed_off_its_home_swims_back_past_prey_in_view_and_notices_it_once_home() -> void:
	# A sated hunter 2 m from home (a missed lunge, a shove) with prey in view all the way: it does
	# not stop to notice prey it would not chase, so it gets home, then notices it once and watches.
	var cases := [
		["pushed back", Vector2(-2.0, 0.0), Vector2(4.0, 0.0)],
		["pushed sideways", Vector2(0.0, 2.0), Vector2(3.5, 1.0)],
		["pushed forward, the prey to one side", Vector2(2.0, 0.0), Vector2(2.0, -4.0)],
	]
	for case in cases:
		var c := _ambush()
		c.m.position = case[1]
		var home_at := -1
		for t in 900:
			_tick(c, t, [_percept(c, "a", case[2])])
			if home_at < 0 and c.m.position.distance_to(c.mem.home) <= CreatureBrain.ARRIVE_HOME_M:
				home_at = t
		var noticed := c.of("creature_noticed")
		check(home_at >= 0, "%s: home within 15 s (%.2f m off, %d notices)" % [case[0], c.m.position.distance_to(c.mem.home), noticed.size()])
		check(noticed.size() <= 1, "%s: at most one notice (%d)" % [case[0], noticed.size()])
		if not noticed.is_empty():
			check(int(noticed[0].tick) >= home_at, "%s: the notice came once it was home (tick %d, home at %d)" % [case[0], noticed[0].tick, home_at])
		check_eq(c.label(), "rest/watch", "%s: it watches the prey from home" % case[0])
	# Prey that hurt it, or that it bit before, is still noticed on the way home, even behind other prey.
	var hurt := _ambush()
	hurt.m.position = Vector2(-2.0, 0.0)
	hurt.mem.attacker = "a"
	_tick(hurt, 5, [_percept(hurt, "b", Vector2(1.0, 0.0)), _percept(hurt, "a", Vector2(4.0, 0.0))])
	_tick(hurt, 11, [_percept(hurt, "b", Vector2(1.0, 0.0)), _percept(hurt, "a", Vector2(4.0, 0.0))])
	check_eq(hurt.label(), "notice", "its attacker is noticed away from home")
	check_eq(hurt.mem.target, "a", "the attacker, not the nearer prey")
	var bitten := _ambush()
	bitten.m.position = Vector2(-2.0, 0.0)
	bitten.mem.landed_on["a"] = 0
	_tick(bitten, 5, [_percept(bitten, "a", Vector2(4.0, 0.0))])
	_tick(bitten, 11, [_percept(bitten, "a", Vector2(4.0, 0.0))])
	check_eq(bitten.label(), "notice", "prey it bit before is noticed away from home")


# --- 3. phases ---

func test_a_tell_starts_only_when_nearly_still_in_the_window_and_aimed() -> void:
	var c := _ambush()
	c.energy_share = 0.5
	c.m.velocity = Vector2(0.0, 0.5)
	var at := Vector2(2.75, 0.0)
	_run(c, 0, 100, "a", at, false)
	check_eq(c.label(), "chase/aim", "it aims but does not tell while moving at 0.5 m/s")
	check(c.of("creature_tell").is_empty(), "no tell while moving")
	c.m.velocity = Vector2(0.0, 0.31)
	_run(c, 100, 130, "a", at, false)
	check(c.of("creature_tell").is_empty(), "nor at 0.31 m/s")
	c.m.velocity = Vector2(0.0, 0.29)
	_run(c, 130, 140, "a", at, false)
	check_eq(c.of("creature_tell").size(), 1, "a tell at 0.29 m/s")
	for case in [["below the window", Vector2(2.4, 0.0)], ["beyond it", Vector2(3.1, 0.0)], ["off its aim", Vector2(2.75, 0.0).rotated(deg_to_rad(21.0))]]:
		var held := _ambush()
		held.energy_share = 0.5
		_run(held, 0, 200, "a", case[1], false)
		check(held.of("creature_tell").is_empty(), "no tell %s" % case[0])


func test_a_tell_strikes_exactly_seventy_two_ticks_later_then_bursts_glides_and_recovers() -> void:
	for number in [0, 2, 5]:
		var c := _ambush()
		c.number = number
		c.energy_share = 0.5
		var modes := []
		for t in 400:
			modes.append(_tick(c, t, [_percept(c, "a", Vector2(2.75, 0.0))], true).mode)
		var tell := c.first_tick("creature_tell")
		check(tell >= 0, "number %d: a tell" % number)
		if tell < 0:
			continue
		check_eq(c.first_tick("creature_strike") - tell, 72, "number %d: the strike 72 ticks after the tell" % number)
		var want := []
		for i in 72:
			want.append("tell")
		for i in 21:
			want.append("burst")
		for i in 15:
			want.append("glide")
		want.append("steer")
		check_eq(modes.slice(tell, tell + want.size()), want, "number %d: tell, burst, glide, recover" % number)
		var recovered := c.of("creature_recovered")
		check(not recovered.is_empty() and int(recovered[0].tick) == tell + 108, "number %d: recovers when the glide ends" % number)
		if not recovered.is_empty():
			check_eq(recovered[0].outcome, "missed", "number %d: nothing landed" % number)


func test_a_strike_holds_its_locked_heading_however_the_target_moves() -> void:
	var c := _ambush()
	c.energy_share = 0.5
	var target := Vector2(2.75, 0.0)
	var velocity := Vector2(0.0, 0.9)
	_run(c, 0, 10, "a", target)
	CreatureBrain.begin_tell(c.mem, c.view(), 10)
	_collect(c, 10)
	var lock := c.mem.lock_heading
	var lead := target + (velocity * 1.2).limit_length(1.0)
	check_near(lock, 0.0, 1e-9, "the lock aims at the target as last seen, still")
	for t in range(11, 130):
		# The target swerves back and forth through the tell and the strike.
		velocity = Vector2(0.0, 2.0 if (t / 10) % 2 == 0 else -2.0)
		target += velocity * DT
		var d := _tick(c, t, [_percept(c, "a", target, {"velocity": velocity})])
		if d.mode == "tell" or d.mode == "burst" or d.mode == "glide":
			check_near(float(d.face), lock, 1e-9, "tick %d (%s): the drive faces the lock" % [t, d.mode])
		if d.mode == "burst" or d.mode == "glide":
			check_near(c.m.heading, lock, 1e-6, "tick %d: the body's heading is the lock" % t)
	check_eq(c.of("creature_strike").size(), 1, "it struck")
	# A moving target: the lock aims at the lead point, capped.
	var moving := _ambush()
	moving.energy_share = 0.5
	var u := 0
	while u < 600 and moving.mem.target.is_empty():
		_tick(moving, u, [_percept(moving, "a", Vector2(2.75, 0.0), {"velocity": Vector2(0.0, 0.9)})], false)
		u += 1
	check(not moving.mem.target.is_empty(), "the moving target is noticed within 10 s")
	if moving.mem.target.is_empty():
		return
	CreatureBrain.begin_tell(moving.mem, moving.view(), u - 1)
	check_near(moving.mem.lock_heading, lead.angle(), 1e-6, "lead 1.2 s x 0.9 m/s, capped at 1.0 m")


func test_a_landed_strike_recovers_at_once_and_resets_the_give_up_timer() -> void:
	var c := _ambush()
	c.energy_share = 0.5
	var t := 0
	while t < 400 and c.of("creature_strike").is_empty():
		_tick(c, t, [_percept(c, "a", Vector2(2.75, 0.0))])
		t += 1
	_tick(c, t, [_percept(c, "a", Vector2(2.75, 0.0))])
	CreatureBrain.on_strike_landed(c.mem, t)
	_collect(c, t)
	check_eq(c.label(), "attack/recover", "recovering")
	check_eq(c.mem.outcome, "hit", "outcome")
	check_eq(c.mem.landed_on.get("a", -1), t, "it remembers landing on it")
	check_eq(c.mem.engaged_tick, t, "the give-up timer restarts")
	var recovered := c.of("creature_recovered")
	check(not recovered.is_empty() and int(recovered[0].tick) == t and recovered[0].outcome == "hit", "creature_recovered {hit} at once")
	var landed := t
	for i in 60:
		t += 1
		_tick(c, t, [_percept(c, "a", Vector2(2.75, 0.0))])
		if c.mem.state != "attack":
			break
	check_eq(t - landed, 60, "the recover lasts 60 ticks")
	check_eq(c.label(), "chase/pursue", "then a hungry hunter chases again")


# --- 4. give-ups ---

## Runs the creature into a chase on "a" at `at` (hungry); returns the next tick.
func _into_chase(c: Critter, at: Vector2, drift := Vector2.ZERO) -> int:
	c.energy_share = 0.5
	var t := 0
	while t < 100 and c.mem.state != "chase":
		_tick(c, t, [_percept(c, "a", at)], false, drift)
		t += 1
	check_eq(c.mem.state, "chase", "in a chase on a")
	return t


func _gave_up(c: Critter) -> Dictionary:
	var found := c.of("creature_gave_up")
	return {} if found.is_empty() else found[0]


func test_a_chase_gives_up_lost_exactly_its_memory_after_the_last_percept() -> void:
	for kind in ["ambush", "rammer"]:
		var c := _ambush() if kind == "ambush" else _rammer()
		var at := Vector2(5.0, 0.0) if kind == "ambush" else Vector2(0.0, 5.5)
		var drift := Vector2(0.0, 0.01) if kind == "ambush" else Vector2(0.01, 0.0)
		var t := _into_chase(c, at, drift)
		for i in 10:
			_tick(c, t, [_percept(c, "a", at)], false, drift)
			t += 1
		# The last percept its brain took in: perception happens on think ticks only.
		var last := int(c.mem.seen["a"].tick)
		check(last >= t - 3, kind + ": thinking at 20 Hz in the chase")
		while t < last + 400 and _gave_up(c).is_empty():
			_tick(c, t, [], false, drift)
			t += 1
		var g := _gave_up(c)
		check_eq(g.get("reason", ""), "lost", kind)
		check_eq(int(g.get("tick", -1)) - last, 120 if kind == "ambush" else 180, kind + ": exactly the memory after the last percept")


func test_a_chase_gives_up_on_its_timer_with_the_target_kept_just_outside_the_window() -> void:
	for kind in ["ambush", "rammer"]:
		var c := _ambush() if kind == "ambush" else _rammer(Vector2(-3.0, 0.0), 0.0)
		var at := Vector2(3.3, 0.0) if kind == "ambush" else Vector2(2.3, 0.0)
		var drift := Vector2(0.0, 0.006)
		var t := 0
		c.energy_share = 0.5
		while t < 700 and _gave_up(c).is_empty():
			_tick(c, t, [_percept(c, "a", at)], false, drift)
			t += 1
		check(c.of("creature_tell").is_empty(), kind + ": never in its window")
		var g := _gave_up(c)
		check_eq(g.get("reason", ""), "timer", kind)
		check_eq(int(g.get("tick", -1)) - c.first_tick("creature_noticed"), 300 if kind == "ambush" else 480, kind + ": at its give-up time")


func test_a_hunter_gives_up_at_its_leash_when_the_target_is_farther_out() -> void:
	var at_leash := _ambush()
	at_leash.m.position = Vector2(8.8, 0.0)
	at_leash.mem.home = Vector2.ZERO
	at_leash.energy_share = 0.5
	for t in 60:
		_tick(at_leash, t, [_percept(at_leash, "a", Vector2(12.5, 0.0))], false)
	check_eq(_gave_up(at_leash).get("reason", ""), "leash", "8.8 m out with a 9 m leash")
	var inside := _ambush()
	inside.m.position = Vector2(8.0, 0.0)
	inside.energy_share = 0.5
	for t in 60:
		_tick(inside, t, [_percept(inside, "a", Vector2(12.5, 0.0))], false)
	check(_gave_up(inside).is_empty(), "8 m out is not at the leash")
	var nearer := _ambush()
	nearer.m.position = Vector2(8.8, 0.0)
	nearer.energy_share = 0.5
	for t in 60:
		_tick(nearer, t, [_percept(nearer, "a", Vector2(5.0, 0.0))], false)
	check(_gave_up(nearer).is_empty(), "at the leash, but the target is nearer home")


func test_a_rammer_gives_up_when_the_target_leaves_its_territory_and_leash() -> void:
	var c := _rammer()
	var t := _into_chase(c, Vector2(0.0, 5.0), Vector2(0.01, 0.0))
	for i in 20:
		_tick(c, t, [_percept(c, "a", Vector2(0.0, 10.9))], false, Vector2(0.01, 0.0))
		t += 1
	check(_gave_up(c).is_empty(), "10.9 m from the center is still within territory + leash")
	for i in 20:
		_tick(c, t, [_percept(c, "a", Vector2(0.0, 11.1))], false, Vector2(0.01, 0.0))
		t += 1
	check_eq(_gave_up(c).get("reason", ""), "left_territory", "11.1 m out")


func test_a_pursuit_that_makes_no_progress_gives_up_unreachable() -> void:
	for kind in ["ambush", "rammer"]:
		var c := _ambush() if kind == "ambush" else _rammer()
		var at := Vector2(5.0, 0.0) if kind == "ambush" else Vector2(0.0, 6.5)
		var t := _into_chase(c, at)
		var pursuing := c.mem.state_tick
		while t < 400 and _gave_up(c).is_empty():
			_tick(c, t, [_percept(c, "a", at)], false)
			t += 1
		var g := _gave_up(c)
		check_eq(g.get("reason", ""), "unreachable", kind)
		check_eq(int(g.get("tick", -1)) - pursuing, 120, kind + ": 120 ticks without moving 0.5 m")
	var moving := _ambush()
	var t2 := _into_chase(moving, Vector2(5.0, 0.0), Vector2(0.0, 0.01))
	for i in 150:
		_tick(moving, t2, [_percept(moving, "a", Vector2(5.0, 0.0))], false, Vector2(0.0, 0.01))
		t2 += 1
	check(_gave_up(moving).is_empty(), "moving 0.6 m a second is progress")


func test_a_target_that_goes_away_ends_the_chase_but_an_attack_in_progress_completes_first() -> void:
	var c := _ambush()
	var t := _into_chase(c, Vector2(5.0, 0.0), Vector2(0.0, 0.01))
	CreatureBrain.on_target_gone(c.mem, "a", t)
	_collect(c, t)
	check_eq(_gave_up(c).get("reason", ""), "target_gone", "in a chase: at once")
	check(not c.mem.seen.has("a"), "forgotten")
	check_eq(c.label(), "wander/return", "it goes home")
	var mid := _ambush()
	mid.energy_share = 0.5
	var u := 0
	while u < 300 and mid.of("creature_tell").is_empty():
		_tick(mid, u, [_percept(mid, "a", Vector2(2.75, 0.0))])
		u += 1
	var tell := u - 1
	CreatureBrain.on_target_gone(mid.mem, "a", u)
	for i in 300:
		_tick(mid, u, [])
		u += 1
	check_eq(mid.first_tick("creature_strike") - tell, 72, "the tell still runs its course")
	var g := _gave_up(mid)
	check_eq(g.get("reason", ""), "target_gone", "then it gives up")
	check_eq(int(g.get("tick", -1)) - tell, 72 + 21 + 15 + 60, "when the recover ends")


# --- 5. refractory ---

func test_a_given_up_target_is_ignored_for_the_refractory_time_and_another_is_noticed_at_once() -> void:
	for kind in ["ambush", "rammer"]:
		var c := _ambush() if kind == "ambush" else _rammer()
		var at := Vector2(5.0, 0.0) if kind == "ambush" else Vector2(0.0, 5.0)
		var t := _into_chase(c, at)
		while t < 600 and _gave_up(c).is_empty():
			_tick(c, t, [_percept(c, "a", at)], false)
			t += 1
		var gave := int(_gave_up(c).get("tick", -1))
		var refractory := 360 if kind == "ambush" else 180
		check_eq(c.mem.ignore.get("a", -1), gave + refractory, kind + ": ignored until")
		var again := c.events.size()
		var noticed_at := -1
		while t < gave + refractory + 20 and noticed_at < 0:
			_tick(c, t, [_percept(c, "a", at)], false)
			for e in c.events.slice(again):
				if e.type == "creature_noticed":
					noticed_at = e.tick
			t += 1
		check(noticed_at >= gave + refractory and noticed_at <= gave + refractory + 6,
			"%s: noticed again only once the refractory time is over (%d, gave up at %d)" % [kind, noticed_at, gave])
		var other := _ambush() if kind == "ambush" else _rammer()
		var u := _into_chase(other, at)
		while u < 600 and _gave_up(other).is_empty():
			_tick(other, u, [_percept(other, "a", at)], false)
			u += 1
		var gave_other := u - 1
		_tick(other, u, [_percept(other, "a", at), _percept(other, "b", at + Vector2(0.0, 1.0))], false)
		u += 1
		while u < gave_other + 8 and other.mem.target != "b":
			_tick(other, u, [_percept(other, "a", at), _percept(other, "b", at + Vector2(0.0, 1.0))], false)
			u += 1
		check_eq(other.mem.target, "b", kind + ": another body is noticed at its next think")


# --- 6. pain ---

func test_pain_from_behind_makes_it_notice_the_attacker_on_the_next_tick() -> void:
	var c := _ambush()
	c.number = 0
	for t in 21:
		_tick(c, t, [])
	CreatureBrain.on_hurt(c.mem, {"id": "a", "species": "lineage", "position": Vector2(-1.2, 0.0), "velocity": Vector2(0.5, 0.0),
		"radius": 0.5}, 20)
	check(CreatureBrain.think_due(c.mem, c.number, 21), "a think is due on the next tick, off its 10 Hz slot")
	_tick(c, 21, [])
	var noticed := c.of("creature_noticed")
	check(not noticed.is_empty() and int(noticed[0].tick) == 21, "noticed on the next tick")
	if not noticed.is_empty():
		check_eq(noticed[0].target, "a", "the attacker")
		check_eq(noticed[0].by, "pain", "by pain")
	for t in range(22, 60):
		_tick(c, t, [])
	check_eq(c.label(), "chase/pursue", "a sated hunter still goes after what hurt it")
	# A rammer retaliates even outside its territory.
	var r := _rammer()
	r.m.position = Vector2(0.0, 7.8)
	CreatureBrain.on_hurt(r.mem, {"id": "a", "species": "lineage", "position": Vector2(0.0, 9.0), "radius": 0.5}, 0)
	for t in range(1, 40):
		_tick(r, t, [_percept(r, "a", Vector2(0.0, 9.0), {"by": "near"})], false)
	check_eq(r.label(), "chase/pursue", "the rammer chases its attacker 9 m from the center")


# --- 7. flee ---

func test_hurt_below_its_flee_share_it_flees_for_its_flee_time_then_returns_home_to_rest() -> void:
	for kind in ["ambush", "rammer"]:
		var c := _ambush() if kind == "ambush" else _rammer(Vector2.ZERO, 0.0)
		c.health_share = 0.3
		for t in 10:
			_tick(c, t, [])
		CreatureBrain.on_hurt(c.mem, {"id": "a", "species": "lineage", "position": c.m.position + Vector2(-1.2, 0.0), "radius": 0.5}, 9)
		var labels := {}
		var rested_at := Vector2.INF
		for t in range(10, 1500):
			_tick(c, t, [])
			labels[t] = c.label()
			if c.mem.state == "rest" and not rested_at.is_finite() and c.first_tick("creature_fled") >= 0:
				rested_at = c.m.position
		var fled := c.first_tick("creature_fled")
		var span := 240 if kind == "ambush" else 300
		check_eq(fled, 10, kind + ": flees on the next tick")
		check_eq(labels.get(fled + span - 1, ""), "flee", kind + ": still fleeing")
		check_eq(labels.get(fled + span, ""), "wander/return", kind + ": then swims home")
		check(rested_at.is_finite() and rested_at.distance_to(c.mem.home) <= CreatureBrain.ARRIVE_HOME_M,
			kind + ": and rests at home (%s)" % rested_at)
	# Hurt again while fleeing: the flee starts over.
	var again := _ambush()
	again.health_share = 0.3
	CreatureBrain.on_hurt(again.mem, {"id": "a", "species": "lineage", "position": Vector2(-1.2, 0.0), "radius": 0.5}, 0)
	for t in range(1, 101):
		_tick(again, t, [])
	CreatureBrain.on_hurt(again.mem, {"id": "a", "species": "lineage", "position": again.m.position + Vector2(-1.0, 0.0), "radius": 0.5}, 100)
	for t in range(101, 400):
		_tick(again, t, [])
		if again.mem.state != "flee":
			check_eq(t, 101 + 240, "the second flee runs its full time")
			break


func test_a_hurt_below_the_flee_share_interrupts_a_tell_but_never_a_strike() -> void:
	var c := _ambush()
	c.energy_share = 0.5
	var t := 0
	while t < 300 and c.of("creature_tell").is_empty():
		_tick(c, t, [_percept(c, "a", Vector2(2.75, 0.0))])
		t += 1
	c.health_share = 0.3
	CreatureBrain.on_hurt(c.mem, {"id": "a", "species": "lineage", "position": Vector2(2.75, 0.0), "radius": 0.5}, t)
	_tick(c, t + 1, [])
	var recovered := c.of("creature_recovered")
	check(not recovered.is_empty() and recovered[0].outcome == "interrupted", "the tell is interrupted")
	check_eq(c.label(), "flee", "and it flees")
	check(c.of("creature_strike").is_empty(), "no strike")
	var s := _ambush()
	s.energy_share = 0.5
	var u := 0
	while u < 300 and s.of("creature_strike").is_empty():
		_tick(s, u, [_percept(s, "a", Vector2(2.75, 0.0))])
		u += 1
	s.health_share = 0.3
	CreatureBrain.on_hurt(s.mem, {"id": "a", "species": "lineage", "position": Vector2(2.75, 0.0), "radius": 0.5}, u)
	# The burst began on tick u - 1, so 20 burst ticks and the 15 glide ticks are still to come.
	var modes := []
	for i in 40:
		modes.append(_tick(s, u + i, []).mode)
	check_eq(modes.slice(0, 35), modes.slice(0, 20).map(func(_m): return "burst") + modes.slice(20, 35).map(func(_m): return "glide"),
		"the strike runs its course")
	check_eq(s.label(), "flee", "then it flees")


# --- 8. rammer ---

func test_a_rammer_notices_intruders_inside_its_territory_only() -> void:
	for case in [["inside", Vector2(0.0, 5.0), {}, true], ["outside", Vector2(0.0, 8.2), {}, false],
			["tiny", Vector2(0.0, 3.0), {"radius": 0.2}, false], ["its own kind", Vector2(0.0, 3.0), {"species": "rammer"}, false],
			["an ambush hunter", Vector2(0.0, 3.0), {"species": "ambush_hunter", "radius": 0.75}, true]]:
		var c := _rammer()
		for t in 12:
			_tick(c, t, [_percept(c, "a", case[1], case[2])], false)
		check_eq(c.mem.state == "notice", case[3], "%s: %s" % [case[0], c.label()])


func test_a_puff_is_cancelled_when_the_target_is_seen_leaving_the_territory() -> void:
	for case in [[9.01, true], [8.99, false]]:
		var c := _rammer()
		var t := 0
		var at := Vector2(0.0, 2.0)
		while t < 60 and c.mem.state != "chase":
			_tick(c, t, [_percept(c, "a", at)], false)
			t += 1
		CreatureBrain.begin_tell(c.mem, c.view(), t)
		_collect(c, t)
		var tell := t
		for i in 150:
			t += 1
			var out := Vector2(0.0, case[0]) if t > tell + 30 else at
			_tick(c, t, [_percept(c, "a", out)], false)
		var cancelled := c.of("tell_cancelled")
		if case[1]:
			check_eq(cancelled.size(), 1, "seen 9.01 m from the center during the puff")
			if not cancelled.is_empty():
				check_eq(cancelled[0].reason, "left_territory", "reason")
			check(c.of("creature_strike").is_empty(), "no strike")
			var recovered := c.of("creature_recovered")
			check(not recovered.is_empty() and recovered[0].outcome == "cancelled", "recovers, cancelled")
		else:
			check(cancelled.is_empty(), "8.99 m is still inside territory + exit")
			check_eq(c.first_tick("creature_strike") - tell, 72, "so it charges")


func test_a_rammer_lets_an_intruder_go_rather_than_puff_at_it_past_its_territory_exit() -> void:
	# The chase follows an intruder out to territory + leash (11 m), but a puff at a target seen past
	# territory + exit (9 m) is cancelled at once. So a rammer that would start a puff out there
	# gives the intruder up instead: no tell that is called off 3 ticks later.
	for case in [[9.5, false], [10.5, false], [8.5, true]]:
		var c := _rammer()
		var stop: float = case[0]
		var at := Vector2(0.0, 5.0)
		for t in 900:
			var v := Vector2(0.0, 2.0) if at.y < stop else Vector2.ZERO
			at.y = minf(at.y + v.y * DT, stop)
			_tick(c, t, [_percept(c, "a", at, {"velocity": v})])
			if not c.of("creature_gave_up").is_empty() or not c.of("creature_strike").is_empty():
				break
		var name := "the intruder stopped %.1f m from the center" % stop
		check(c.of("tell_cancelled").is_empty(), name + ": no puff called off")
		if case[1]:
			check_eq(c.of("creature_tell").size(), 1, name + ": inside the exit it puffs")
			check_eq(c.of("creature_strike").size(), 1, name + ": and charges")
			continue
		check(c.of("creature_tell").is_empty(), name + ": no puff")
		var gave_up := c.of("creature_gave_up")
		check_eq(gave_up.size(), 1, name + ": it gives the intruder up")
		if not gave_up.is_empty():
			check_eq(gave_up[0].reason, "left_territory", name + ": reason")
			check_eq(c.mem.ignore.get("a", -1), int(gave_up[0].tick) + 180, name + ": and ignores it for its refractory time")


func test_a_blocked_charge_dazes_the_rammer_for_its_blocked_recover_time() -> void:
	var c := _rammer()
	var t := 0
	while t < 60 and c.mem.state != "chase":
		_tick(c, t, [_percept(c, "a", Vector2(0.0, 2.0))], false)
		t += 1
	CreatureBrain.begin_tell(c.mem, c.view(), t)
	var told := t
	while t < told + 400 and c.mem.phase != "strike":
		t += 1
		_tick(c, t, [_percept(c, "a", Vector2(0.0, 2.0))], false)
	check_eq(c.mem.phase, "strike", "the puff ends in a charge")
	if c.mem.phase != "strike":
		return
	CreatureBrain.on_blocked(c.mem, t)
	_collect(c, t)
	check_eq(c.mem.outcome, "blocked", "outcome")
	check_eq(c.mem.recover_ticks, 120, "dazed for 120 ticks")
	var blocked := t
	while t < blocked + 200 and c.mem.state == "attack":
		t += 1
		_tick(c, t, [_percept(c, "a", Vector2(0.0, 2.0))], false)
	check_eq(t - blocked, 120, "the recover ends 120 ticks on")


func test_a_rammer_rests_four_to_eight_seconds_drawn_from_its_own_rng() -> void:
	var spans := {}
	for seed_value in 40:
		var mem := CreatureBrain.create("territorial", rammer_cfg, Vector2.ZERO, 0.0, {"center": Vector2.ZERO, "radius": ZONE_R}, seed_value, 100)
		var span := mem.rest_until - 100
		check(span >= 240 and span <= 480, "seed %d: %d ticks" % [seed_value, span])
		spans[span] = true
		var same := CreatureBrain.create("territorial", rammer_cfg, Vector2.ZERO, 0.0, {"center": Vector2.ZERO, "radius": ZONE_R}, seed_value, 100)
		check_eq(same.rest_until, mem.rest_until, "seed %d: the same seed rests the same" % seed_value)
	check(spans.size() >= 10, "the rests vary (%d distinct)" % spans.size())


# --- 9. a new tell every time ---

func test_every_attack_has_its_own_aim_and_tell_and_a_strike_never_follows_a_strike() -> void:
	for kind in ["ambush", "rammer"]:
		var c := _ambush() if kind == "ambush" else _rammer()
		c.mem.trace = true
		c.energy_share = 0.5
		var at := Vector2(2.75, 0.0) if kind == "ambush" else Vector2(0.0, 3.0)
		for t in 2400:
			_tick(c, t, [_percept(c, "a", at)])
			if c.mem.phase == "strike" and t == c.mem.phase_tick + 2:
				CreatureBrain.on_strike_landed(c.mem, t)   # keeps the chase alive past the give-up timer
				_collect(c, t)
		var tells := c.of("creature_tell").size()
		check(tells >= 3, "%s: several attacks (%d)" % [kind, tells])
		var last_attack := ""
		for e in c.of("creature_state"):
			if e.to == "attack/tell":
				check_eq(e.from, "chase/aim", "%s tick %d: a tell comes from aiming" % [kind, e.tick])
			if e.to == "attack/strike":
				check_eq(e.from, "attack/tell", "%s tick %d: a strike comes from a tell" % [kind, e.tick])
		for e in c.events:
			if e.type == "creature_tell" or e.type == "creature_strike":
				check(e.type != last_attack, "%s tick %d: %s twice in a row" % [kind, e.tick, e.type])
				last_attack = e.type


# --- 10. drive bounds ---

func test_drive_stays_in_bounds_over_ten_thousand_ticks_of_random_percepts() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3030
	var arena := PoolArena.create(40.0, 36.0, 39.5)
	arena.add_rock("r1", Vector2(4.0, 1.0), 1.2)
	arena.add_rock("r2", Vector2(-3.0, -4.0), 1.5)
	arena.add_rock("r3", Vector2(1.0, -7.0), 0.8)
	var allowed_modes := ["steer", "turn", "tell", "burst", "glide"]
	var counts := {"tells": 0, "strikes": 0, "gave_up": 0, "fled": 0}
	for kind in ["ambush", "rammer"]:
		var c := _ambush(Vector2(0.0, 2.0)) if kind == "ambush" else _rammer(Vector2(0.0, 2.0))
		var bodies := []
		for t in 10000:
			if rng.randf() < 0.02:
				bodies.clear()
				for i in rng.randi_range(0, 3):
					bodies.append({"id": "b%d" % rng.randi_range(0, 4),
						"species": ["lineage", "rammer", "ambush_hunter"][rng.randi_range(0, 2)],
						"position": c.m.position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.5, 9.0),
						"velocity": Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 3.0),
						"radius": rng.randf_range(0.2, 1.0), "engageable": rng.randf() < 0.8})
			if rng.randf() < 0.01:
				c.energy_share = rng.randf()
				c.health_share = rng.randf_range(0.2, 1.0)
			var percepts := []
			for b in bodies:
				b.position += b.velocity * DT
				if rng.randf() < 0.9:
					percepts.append(_percept(c, b.id, b.position, b))
			var d := _tick(c, t, percepts, true, Vector2.ZERO, [], arena)
			var move: Vector2 = d.move
			var bad := not move.is_finite() or not is_finite(float(d.speed_mul)) or not is_finite(float(d.face))
			if bad or move.length() > 1.0 + 1e-6 or float(d.speed_mul) > 1.0 or not allowed_modes.has(d.mode):
				check(false, "%s tick %d: drive out of bounds %s" % [kind, t, d])
				return
			var striking := CreatureBrain.is_striking(c.mem)
			if (d.mode == "burst" or d.mode == "glide") != striking or bool(d.strike) != striking:
				check(false, "%s tick %d: %s outside a strike or a strike without it (%s)" % [kind, t, d.mode, c.label()])
				return
			if c.mem.state == "chase" and not is_equal_approx(float(d.speed_mul), float(c.mem.cfg.speeds.pursue)):
				check(false, "%s tick %d: chasing at share %.2f" % [kind, t, d.speed_mul])
				return
			if not c.m.position.is_finite() or not c.m.velocity.is_finite():
				check(false, "%s tick %d: the body went to NaN" % [kind, t])
				return
			if t % 97 == 0 and not bodies.is_empty() and rng.randf() < 0.5:
				var b: Dictionary = bodies[0]
				CreatureBrain.on_hurt(c.mem, b, t)
			if c.mem.phase == "strike" and rng.randf() < 0.05:
				CreatureBrain.on_strike_landed(c.mem, t)
			_collect(c, t)
		counts.tells += c.of("creature_tell").size()
		counts.strikes += c.of("creature_strike").size()
		counts.gave_up += c.of("creature_gave_up").size()
		counts.fled += c.of("creature_fled").size()
	check(counts.tells >= 5 and counts.strikes >= 5 and counts.gave_up >= 5 and counts.fled >= 2,
		"the random run reached tells, strikes, give-ups and flees: %s" % counts)


# --- 11. determinism ---

func test_the_same_seed_gives_the_same_choices_and_the_memory_dict_holds_no_vectors() -> void:
	var arena := PoolArena.create(40.0, 36.0, 39.5)
	arena.add_rock("r1", Vector2(3.0, 3.0), 1.5)
	var runs := []
	for seed_value in [5, 5, 6]:
		var c := _rammer(Vector2(0.0, -2.0), PI / 2.0, Vector2.ZERO, seed_value)
		var goals := []
		for t in 6000:
			_tick(c, t, [], true, Vector2.ZERO, [], arena)
			if c.mem.goal.is_finite() and (goals.is_empty() or goals.back() != c.mem.goal):
				goals.append(c.mem.goal)
		runs.append({"goals": goals, "dict": JSON.stringify(c.mem.to_dict(), "", true, true)})
		check(goals.size() >= 5, "seed %d: it patrolled (%d goals)" % [seed_value, goals.size()])
		check(_no_vectors(c.mem.to_dict()), "seed %d: to_dict holds only arrays, numbers and strings" % seed_value)
	check_eq(runs[1].goals, runs[0].goals, "the same seed picks the same patrol goals")
	check_eq(runs[1].dict, runs[0].dict, "and ends in the same memory")
	check(runs[2].goals != runs[0].goals, "another seed picks others")
	var busy := _ambush()
	busy.energy_share = 0.5
	_run(busy, 0, 150, "a", Vector2(2.75, 0.0))
	CreatureBrain.on_hurt(busy.mem, {"id": "b", "species": "rammer", "position": Vector2(-1.0, 0.0), "radius": 0.625}, 150)
	var d := busy.mem.to_dict()
	check(_no_vectors(d), "mid-attack, with a lane, a lock and memories, still no vectors or NaN")
	for key in ["seen", "landed_on", "ignore", "lane", "lock_heading", "rng_state", "phase_tick", "target"]:
		check(d.has(key), "to_dict has %s" % key)


# --- 12. stuck ---

func test_three_failed_returns_home_mark_the_creature_stuck() -> void:
	var c := _ambush()
	c.m.position = Vector2(5.0, 0.0)
	var t := 0
	while t < 2000 and c.label() != "wander/return":
		_tick(c, t, [], false)
		t += 1
	check_eq(c.label(), "wander/return", "pushed 5 m off home, it swims back")
	if c.label() != "wander/return":
		return
	var start := c.mem.phase_tick
	for i in 2 * 1200:
		_tick(c, t, [], false)
		t += 1
	check_eq(c.mem.return_fails, 2, "two timeouts")
	check(not c.mem.stuck, "not stuck yet")
	while t < start + 3 * 1200 + 1:
		_tick(c, t, [], false)
		t += 1
	check_eq(c.mem.return_fails, 3, "three timeouts")
	check(c.mem.stuck, "stuck after the third")
	check_eq(c.label(), "wander/return", "it keeps trying")
	c.m.position = Vector2(0.1, 0.0)
	for i in 10:
		_tick(c, t, [], false)
		t += 1
	check(not c.mem.stuck and c.mem.return_fails == 0, "home at last: no longer stuck")


# --- 13. tell guards ---

func test_no_tell_starts_when_its_lane_would_leave_the_leash() -> void:
	var out := _ambush()
	out.m.position = Vector2(8.0, 0.0)
	out.energy_share = 0.5
	_run(out, 0, 200, "a", Vector2(10.75, 0.0), false)
	check(out.of("creature_tell").is_empty(), "8 m from home facing out: the lunge would end 10.1 m out")
	check_eq(out.label(), "chase/aim", "it holds its aim instead")
	var back := _ambush(Vector2.ZERO, PI)
	back.m.position = Vector2(8.0, 0.0)
	back.energy_share = 0.5
	_run(back, 0, 200, "a", Vector2(5.25, 0.0), false)
	check_eq(back.of("creature_tell").size(), 1, "the same distance facing home: a tell")


func test_a_target_too_close_gets_a_run_up_to_the_stand_off_point_first() -> void:
	for kind in ["ambush", "rammer"]:
		var c := _ambush() if kind == "ambush" else _rammer(Vector2.ZERO, 0.0)
		c.energy_share = 0.5
		var at := Vector2(1.6, 0.0)
		var farthest := 0.0
		var t := 0
		while t < 900 and c.of("creature_tell").is_empty():
			_tick(c, t, [_percept(c, "a", at)])
			farthest = maxf(farthest, c.m.position.distance_to(at))
			t += 1
		var a: Dictionary = c.mem.cfg.attack
		check_eq(c.of("creature_tell").size(), 1, kind + ": a tell in the end")
		var d := c.m.position.distance_to(at)
		check(d >= float(a.start_min_m) and d <= float(a.start_max_m), "%s: from inside its window (%.2f m)" % [kind, d])
		check(farthest >= float(a.start_min_m), "%s: it backed off first (%.2f m)" % [kind, farthest])


func test_a_run_up_past_the_leash_ends_on_the_leash_circle_turned_to_aim_and_tell() -> void:
	# A rammer 0.5 m inside its 11 m leash disc, facing out, with an intruder 3 m further in: its
	# 4 m stand-off point lies 0.5 m past the leash. It goes to the circle, turns and charges.
	var c := _rammer(Vector2.ZERO, 0.0)
	var disc := CreatureBrain.leash_disc(c.mem)
	c.m.position = Vector2(float(disc.radius) - 0.5, 0.0)
	var at := c.m.position - Vector2(3.0, 0.0)
	var t := 0
	while t < 600 and c.of("creature_tell").is_empty() and c.of("creature_gave_up").is_empty():
		_tick(c, t, [_percept(c, "a", at)])
		t += 1
	check_eq(c.of("creature_gave_up").size(), 0, "no give-up while it can still aim")
	check_eq(c.of("creature_tell").size(), 1, "a tell from the leash circle")
	check(c.m.position.distance_to(disc.center) <= float(disc.radius) + 1e-3, "inside its leash")
	check(t < 300, "within 5 s (%d ticks)" % t)


func test_a_creature_left_alone_reaches_its_tell_from_any_side_and_distance() -> void:
	for kind in ["ambush", "rammer"]:
		for dist in ([1.0, 2.0, 2.75, 4.0, 7.0] if kind == "ambush" else [1.5, 3.0, 4.0, 6.0]):
			for bearing in [0.0, PI / 2.0, PI]:
				var c := _ambush() if kind == "ambush" else _rammer(Vector2.ZERO, 0.0)
				c.energy_share = 0.5
				var at: Vector2 = Vector2.from_angle(bearing) * dist
				var t := 0
				var at_tell := {}
				while t < 900 and at_tell.is_empty():
					_tick(c, t, [_percept(c, "a", at)])
					if not c.of("creature_tell").is_empty():
						at_tell = {"d": c.m.position.distance_to(at), "speed": c.m.velocity.length(),
							"aim": absf(angle_difference(c.m.heading, (at - c.m.position).angle()))}
					t += 1
				var name := "%s %.2f m at %d deg" % [kind, dist, roundi(rad_to_deg(bearing))]
				check(not at_tell.is_empty(), name + ": a tell within 15 s")
				if at_tell.is_empty():
					continue
				var a: Dictionary = c.mem.cfg.attack
				check(at_tell.d >= float(a.start_min_m) - 1e-6 and at_tell.d <= float(a.start_max_m) + 1e-6, "%s: in the window (%.2f)" % [name, at_tell.d])
				check(at_tell.speed <= 0.3, "%s: nearly still (%.2f m/s)" % [name, at_tell.speed])
				check(at_tell.aim <= float(a.aim) + 1e-6, "%s: aimed (%.1f deg)" % [name, rad_to_deg(at_tell.aim)])


func test_a_pursuer_aims_at_prey_swimming_at_it_or_across_it_but_never_tells_on_prey_swimming_away() -> void:
	# Grazing at about 30% throttle (0.87 m/s) from 4.5 m (ambush) or 5 m (rammer) away.
	for kind in ["ambush", "rammer"]:
		for heading_deg in [0, 90, 180, 270]:
			var c := _ambush() if kind == "ambush" else _rammer(Vector2.ZERO, 0.0)
			c.energy_share = 0.5
			var at: Vector2 = Vector2(4.5, 0.0) if kind == "ambush" else Vector2(5.0, 0.0)
			var velocity := Vector2.from_angle(deg_to_rad(heading_deg)) * 0.87
			var name := "%s, prey heading %d deg" % [kind, heading_deg]
			var at_tell := {}
			for t in 900:
				at += velocity * DT
				if kind == "rammer" and at.length() > 7.5:
					velocity = -velocity   # it stays in the territory, turning back at its edge
				_tick(c, t, [_percept(c, "a", at, {"velocity": velocity})])
				if not c.of("creature_tell").is_empty():
					at_tell = {"d": c.m.position.distance_to(at), "speed": c.m.velocity.length()}
					break
				if not c.of("creature_gave_up").is_empty():
					break
			var a: Dictionary = c.mem.cfg.attack
			if kind == "ambush" and heading_deg == 0:
				check(at_tell.is_empty(), name + ": swimming straight away is never told on")
				check_eq(_gave_up(c).get("reason", ""), "timer", name + ": the chase ends on its timer")
				continue
			check(not at_tell.is_empty(), name + ": a tell")
			if at_tell.is_empty():
				continue
			check(at_tell.d >= float(a.start_min_m) and at_tell.d <= float(a.start_max_m), "%s: in the window (%.2f m)" % [name, at_tell.d])
			check(at_tell.speed <= 0.3, "%s: from rest (%.2f m/s)" % [name, at_tell.speed])
	# Head-on, the pursuer stops in chase/aim and lets the prey come instead of meeting it.
	var waits := _ambush()
	waits.energy_share = 0.5
	waits.mem.trace = true
	var p := Vector2(6.0, 0.0)
	for t in 300:
		p += Vector2(-0.87, 0.0) * DT
		_tick(waits, t, [_percept(waits, "a", p, {"velocity": Vector2(-0.87, 0.0)})])
		if waits.mem.state == "attack":
			break
	var aimed_from := -1
	for e in waits.of("creature_state"):
		if e.to == "chase/aim":
			aimed_from = e.tick
	check(aimed_from >= 0, "it aims")
	check(waits.m.position.length() < 1.5, "it held its ground (%.2f m moved)" % waits.m.position.length())


# --- 14. the strike lane ---

func test_the_strike_lane_measures_the_lunge_and_the_charge() -> void:
	var lunge := CreatureBrain.strike_lane(ambush_cfg.attack, 0.75, 0.5, Vector2(1.0, 2.0), 0.3)
	var charge := CreatureBrain.strike_lane(rammer_cfg.attack, 0.625, 0.5, Vector2.ZERO, -1.0)
	# The per-tick travel, a few centimetres short of the plan's integrals (3.71 and 5.70).
	check_near(lunge.length, 3.679, 0.001, "lunge length")
	check_near(lunge.half_width, 1.55, 1e-9, "lunge half-width")
	check_near(charge.length, 5.671, 0.001, "charge length")
	check_near(charge.half_width, 1.475, 1e-9, "charge half-width")
	for case in [[ambush_cfg.attack, lunge], [rammer_cfg.attack, charge]]:
		var a: Dictionary = case[0]
		var m := Locomotion.MotionState.new(Vector2.ZERO, 0.0)
		for i in int(a.burst_ticks):
			Locomotion.burst(m, 0.0, float(a.burst_speed))
			m.position += m.velocity * DT
		for i in int(a.glide_ticks):
			Locomotion.glide(m, float(a.glide_drag), DT)
			m.position += m.velocity * DT
		check_near(case[1].travel, m.position.x, 0.01, "%s: the travel is the per-tick sum" % a.tell)


func test_the_strike_lane_holds_every_point_where_the_strike_could_hit() -> void:
	for kind in ["ambush", "rammer"]:
		var a: Dictionary = (ambush_cfg if kind == "ambush" else rammer_cfg).attack
		var body := ambush_body if kind == "ambush" else rammer_body
		var origin := Vector2(3.0, -2.0)
		var heading := 0.7
		var lane := CreatureBrain.strike_lane(a, body.radius, 0.5, origin, heading)
		var prey := _derive([["mouth_filter", 0.0], ["flagellum", PI]], 1.0)
		var m := Locomotion.MotionState.new(origin, heading)
		var allowed := 0
		var outside := 0
		for i in int(a.burst_ticks) + int(a.glide_ticks):
			if i < int(a.burst_ticks):
				Locomotion.burst(m, heading, float(a.burst_speed))
			else:
				Locomotion.glide(m, float(a.glide_drag), DT)
			m.position += m.velocity * DT
			if i % 3 != 0:
				continue
			var attacker := InteractionResolver.Actor.new("c", m.position, m.heading, body)
			for gx in range(-30, 31):
				for gy in range(-30, 31):
					var p := m.position + Vector2(gx, gy) * 0.08
					var target := InteractionResolver.Actor.new("t", p, 0.0, prey)
					attacker.cooldowns.clear()
					var hit: Dictionary
					if a.kind == "bite":
						hit = InteractionResolver.bite(attacker, target, 0.0)
					else:
						var closing := m.velocity.dot((p - m.position).normalized())
						hit = InteractionResolver.ram(attacker, target, closing, 0.0)
					if hit.allowed:
						allowed += 1
						if not CreatureBrain.lane_contains(lane, p):
							outside += 1
		check(allowed > 200, "%s: the sample finds hits (%d)" % [kind, allowed])
		check_eq(outside, 0, "%s: every allowed hit on a still prey lies in the lane" % kind)


func test_the_lane_a_tell_shows_is_the_lane_its_strike_runs() -> void:
	# F1: creature_tell's lane is the strike's own: from where the tell starts, along the locked
	# heading (which leads a moving target, so it is not the body's heading), and as wide as the
	# strike reaches a prey of the target's size. The strike then starts there, along it.
	var prey_r := 0.4
	for kind in ["ambush", "rammer"]:
		var c := _ambush() if kind == "ambush" else _rammer(Vector2.ZERO, 0.0)
		c.energy_share = 0.5
		var at := Vector2(2.75, 0.0) if kind == "ambush" else Vector2(4.0, 0.0)
		var prey := {"velocity": Vector2(0.0, 0.9), "radius": prey_r}
		var t := 0
		while t < 60 and c.mem.target.is_empty():
			_tick(c, t, [_percept(c, "a", at, prey)], false)
			t += 1
		check_eq(c.mem.target, "a", kind + ": the prey is noticed")
		if c.mem.target.is_empty():
			continue
		var origin := c.m.position
		CreatureBrain.begin_tell(c.mem, c.view(), t)
		_collect(c, t)
		var told := c.of("creature_tell")
		check_eq(told.size(), 1, kind + ": a tell")
		if told.is_empty():
			continue
		var lane: Dictionary = told[0].lane
		var a: Dictionary = c.mem.cfg.attack
		var half: float = c.p.radius + float(a.reach) + prey_r
		check(absf(angle_difference(c.mem.lock_heading, c.m.heading)) > deg_to_rad(10.0),
			"%s: the lock leads the target, %.1f degrees off the body's heading" % [kind, rad_to_deg(absf(angle_difference(c.mem.lock_heading, c.m.heading)))])
		check_near(float(lane.heading), c.mem.lock_heading, 1e-9, kind + ": the lane runs along the lock")
		check(Vector2(lane.origin).distance_to(origin) < 1e-9, kind + ": from where the tell starts")
		check_near(float(lane.half_width), half, 1e-9, kind + ": as wide as its radius, its reach and the prey's radius")
		check_near(float(lane.travel), float(a.travel), 1e-9, kind + ": as long as the strike travels")
		check_near(float(lane.length), float(a.travel) + half, 1e-9, kind + ": plus the reach at its end")
		check_eq(lane, CreatureBrain.strike_lane(a, c.p.radius, prey_r, origin, c.mem.lock_heading), kind + ": strike_lane() of the lock")
		var struck := {}
		while t < 400 and struck.is_empty():
			t += 1
			at += Vector2(prey.velocity) * DT
			_tick(c, t, [_percept(c, "a", at, prey)])
			var strikes := c.of("creature_strike")
			if not strikes.is_empty():
				struck = strikes[0]
		check(not struck.is_empty(), kind + ": it strikes")
		if struck.is_empty():
			continue
		check_near(float(struck.heading), float(lane.heading), 1e-9, kind + ": the strike runs along the lane")
		check(Vector2(struck.position).distance_to(lane.origin) < 1e-6, kind + ": from the lane's origin")


# --- the schedule, foraging and the respawn hooks ---

func test_thinks_run_at_ten_hertz_staggered_twenty_while_engaged_and_on_every_deadline() -> void:
	var a := _ambush()
	var due := []
	for t in 24:
		if CreatureBrain.think_due(a.mem, 1, t):
			due.append(t)
	check_eq(due, [5, 11, 17, 23], "number 1 at rest: every 6 ticks on its slot")
	due.clear()
	for t in 24:
		if CreatureBrain.think_due(a.mem, 4, t):
			due.append(t)
	check_eq(due, [2, 8, 14, 20], "number 4: another slot")
	var c := _ambush()
	c.energy_share = 0.5
	var t := _into_chase(c, Vector2(5.0, 0.0), Vector2(0.0, 0.01))
	due.clear()
	for u in range(t, t + 12):
		if CreatureBrain.think_due(c.mem, c.number, u):
			due.append(u - t)
	check_eq(due.size(), 4, "in a chase: every 3 ticks (%s)" % [due])
	var n := _ambush()
	n.number = 3
	_run(n, 0, 10, "a", Vector2(4.0, 0.0), false)
	var started := n.mem.phase_tick
	check(CreatureBrain.think_due(n.mem, 3, started + 30), "the notice's end is a think, whatever the slot")
	check_eq(CreatureBrain.next_deadline(n.mem), started + 30, "the next deadline is the notice's end")


func test_a_hungry_hunter_forages_carrion_near_home_and_goes_home_when_full() -> void:
	var c := _ambush()
	c.energy_share = 0.5
	var meat := {"id": "m1", "kind": "meat", "position": Vector2(4.0, 1.0), "radius": 0.3}
	var far := {"id": "m2", "kind": "meat", "position": Vector2(9.0, 9.0), "radius": 0.3}
	var fed := false
	var t := 0
	while t < 900 and not fed:
		var food := []
		for f in [meat, far]:
			var copy: Dictionary = f.duplicate()
			copy["distance"] = c.m.position.distance_to(f.position)
			food.append(copy)
		food.sort_custom(func(x, y): return x.distance < y.distance)
		var d := _tick(c, t, [], true, Vector2.ZERO, food if c.mem.state == "forage" else [])
		if d.feed == "m1":
			fed = true
		t += 1
	check(fed, "it swam to the carrion and fed on it")
	check(c.m.position.distance_to(meat.position) <= c.p.radius + 0.3 + InteractionResolver.FEED_REACH, "in feeding reach")
	c.energy_share = 0.9
	for i in 600:
		_tick(c, t, [], true, Vector2.ZERO, [])
		t += 1
	check_eq(c.label(), "rest/lurk", "full, it went home and lurks")
	# Nothing to eat: it looks round home for 30 s, then waits 20 s before trying again.
	var bare := _ambush()
	bare.energy_share = 0.5
	var labels := []
	for u in 3200:
		_tick(bare, u, [], true)
		labels.append(bare.label())
	var gave := labels.find("wander/return")
	check(gave >= 1800 and gave <= 1806, "forage gives up 30 s after it began (%d)" % gave)
	check(bare.mem.forage_after >= gave + 1200, "and waits 20 s")
	check(labels.slice(gave, gave + 1150).count("forage/seek") == 0, "no foraging in between")
	check(labels.slice(gave + 1200).has("forage/seek"), "then forages again")


func test_a_hungry_rammer_grazes_plankton_inside_its_territory_only() -> void:
	var c := _rammer(Vector2.ZERO, 0.0)
	c.energy_share = 0.5
	var inside := {"id": "pk_1", "kind": "plant", "position": Vector2(3.0, 2.0), "radius": 0.2}
	var outside := {"id": "pk_2", "kind": "plant", "position": Vector2(0.0, 9.0), "radius": 0.2}
	var fed_on := ""
	for t in 900:
		var food := []
		for f in [outside, inside]:
			var copy: Dictionary = f.duplicate()
			copy["distance"] = c.m.position.distance_to(f.position)
			food.append(copy)
		food.sort_custom(func(x, y): return x.distance < y.distance)
		var d := _tick(c, t, [], true, Vector2.ZERO, food if c.mem.state == "forage" else [])
		if not str(d.feed).is_empty():
			fed_on = d.feed
			break
	check_eq(fed_on, "pk_1", "it grazes the plankton inside its territory")


func test_forgetting_a_body_drops_it_and_a_forced_return_rests_the_creature_at_home() -> void:
	var c := _ambush()
	c.energy_share = 0.5
	var t := _into_chase(c, Vector2(5.0, 0.0), Vector2(0.0, 0.01))
	c.mem.landed_on["a"] = 3
	check(CreatureBrain.is_engaged_with(c.mem, "a"), "engaged with a")
	CreatureBrain.forget(c.mem, "a", t + 1800, t)
	_collect(c, t)
	check(not CreatureBrain.is_engaged_with(c.mem, "a"), "no longer engaged")
	check(not c.mem.seen.has("a") and not c.mem.landed_on.has("a"), "no memory of it")
	check_eq(c.mem.ignore.get("a", -1), t + 1800, "ignored until the given tick")
	check(c.of("creature_gave_up").is_empty(), "forgetting is silent")
	check_eq(c.label(), "wander/return", "it goes home")
	var mid := _ambush()
	mid.energy_share = 0.5
	var u := 0
	while u < 300 and mid.of("creature_tell").is_empty():
		_tick(mid, u, [_percept(mid, "a", Vector2(2.75, 0.0))])
		u += 1
	CreatureBrain.force_return(mid.mem, "a", u + 100, u)
	_collect(mid, u)
	var recovered := mid.of("creature_recovered")
	check(recovered.size() == 1 and recovered[0].outcome == "cancelled", "the tell is called off, once (%d)" % recovered.size())
	check_eq(mid.label(), "rest/lurk", "at rest")
	check_eq(mid.mem.target, "", "with no target")
	for i in 200:
		u += 1
		_tick(mid, u, [])
	check(mid.of("creature_strike").is_empty(), "and no strike follows")


# --- S2: the cfg's own lengths, the relationship switches and scale_cfg (plan B.6) ---

## creatures_m1.json's relationships block with every rule on (spine 4.2).
const RELATIONSHIPS_ON := {"rules": {"prey_share": true, "intruder_share": true, "fear": true, "no_engage_above": true,
	"outgrown_hazards": true}, "prey_share": 1.0, "intruder_max_radius_share": 1.2, "fear_radius_share": 1.25,
	"tolerance": 1e-6}
const LADDER_QS := [0.625, 0.390625]


## Every leaf of a cfg as [path, value] ("attack.reach"); dictionaries are walked into, lists are leaves.
static func leaves(d: Dictionary, prefix := "") -> Array:
	var out := []
	for key in d:
		var path := prefix + str(key)
		if d[key] is Dictionary:
			out.append_array(leaves(d[key], path + "."))
		else:
			out.append([path, d[key]])
	return out


static func _at(d: Dictionary, path: String) -> Variant:
	var v: Variant = d
	for part in path.split("."):
		v = v[part]
	return v


func _rules_only(rule: String) -> Dictionary:
	var rel: Dictionary = RELATIONSHIPS_ON.duplicate(true)
	for r in rel.rules:
		rel.rules[r] = r == rule
	return rel


func test_the_config_copies_todays_lengths_into_cfg_and_keeps_m1s_shares_with_no_relationships() -> void:
	var want := {"arrive_home_m": 0.3, "home_slack_m": 1.0, "arrive_goal_m": 0.5, "face_at_standoff_m": 0.25,
		"leash_give_up_m": 0.25, "forage_patrol_m": 6.0, "patrol_inset_m": 1.0, "default_territory_m": 6.0,
		"flee_lookahead_m": 4.0, "flee_edge_m": 1.0, "approach_wait_mps": 0.2, "feed_reach": 0.25, "route_margin": 0.6,
		"route_clearance": 0.1, "post_hysteresis_m": 2.0, "share_tolerance": 1e-6}
	for cfg in [ambush_cfg, rammer_cfg]:
		for key in want:
			check_eq(cfg[key], want[key], "%s %s" % [cfg.species_id, key])
		check(is_inf(cfg.intruder_max_radius_share) and is_inf(cfg.fear_radius_share), cfg.species_id + ": rules 2 and 3 off")
		check_eq(cfg.engage_rule, false, cfg.species_id + ": rule 4 off")
		check_eq([cfg.post_switch, cfg.post_rest_ticks], ["", 0], cfg.species_id + ": no habit")
	check_eq(ambush_cfg.prey_max_radius_share, 1.6, "the ambush hunter's own share")
	check_eq(rammer_cfg.prey_max_radius_share, InteractionResolver.BITE_SIZE_LIMIT, "the default share")
	check_eq(ambush_cfg.attack.reach, InteractionResolver.BITE_REACH, "a bite reaches as the resolver's")
	check_eq(rammer_cfg.attack.reach, InteractionResolver.RAM_REACH, "a ram too")


func test_the_relationships_block_sets_each_rule_behind_its_own_switch() -> void:
	var on := CreatureBrain.config("ambush_hunter", AMBUSH_BLOCK, AI, RELATIONSHIPS_ON)
	check_eq(on.prey_max_radius_share, 1.0, "rule 1: the block's prey share")
	check_eq(on.intruder_max_radius_share, 1.2, "rule 2")
	check_eq(on.fear_radius_share, 1.25, "rule 3")
	check_eq(on.engage_rule, true, "rule 4")
	for rule in ["prey_share", "intruder_share", "fear", "no_engage_above"]:
		var cfg := CreatureBrain.config("ambush_hunter", AMBUSH_BLOCK, AI, _rules_only(rule))
		check_eq(cfg.prey_max_radius_share, 1.0 if rule == "prey_share" else 1.6, rule + " alone: the prey share")
		check_eq(is_inf(cfg.intruder_max_radius_share), rule != "intruder_share", rule + " alone: the intruder share")
		check_eq(is_inf(cfg.fear_radius_share), rule != "fear", rule + " alone: the fear share")
		check_eq(cfg.engage_rule, rule == "no_engage_above", rule + " alone: the engage rule")
	check_eq(CreatureBrain.config("ambush_hunter", AMBUSH_BLOCK, AI, _rules_only("")), ambush_cfg,
		"a block with every rule off gives M1's cfg")
	var loose: Dictionary = RELATIONSHIPS_ON.duplicate(true)
	loose.tolerance = 1e-4
	check_eq(CreatureBrain.config("rammer", RAMMER_BLOCK, AI, loose).share_tolerance, 1e-4, "the block's tolerance")
	var lurker: Dictionary = AMBUSH_BLOCK.duplicate(true)
	lurker["habit"] = {"post_switch": "out_of_sight", "post_rest_s": 8.0, "trail_s": 20.0}
	var elder: Dictionary = RAMMER_BLOCK.duplicate(true)
	elder["habit"] = {"post_switch": "nearer_cell", "post_hysteresis_m": 3.0}
	var l := CreatureBrain.config("lurker", lurker, AI)
	var e := CreatureBrain.config("elder_rammer", elder, AI)
	check_eq([l.post_switch, l.post_rest_ticks, l.post_hysteresis_m], ["out_of_sight", 480, 2.0], "a lurker's habit")
	check_eq([e.post_switch, e.post_rest_ticks, e.post_hysteresis_m], ["nearer_cell", 0, 3.0], "an elder rammer's")


func test_scale_cfg_at_q_one_is_an_equal_copy() -> void:
	for cfg in [ambush_cfg, rammer_cfg, CreatureBrain.config("ambush_hunter", AMBUSH_BLOCK, AI, RELATIONSHIPS_ON)]:
		var same := CreatureBrain.scale_cfg(cfg, 1.0)
		check_eq(same, cfg, cfg.species_id + ": equal")
		same.attack.reach = 9.0
		same.speeds.flee = 9.0
		same.leash_m = 99.0
		check(cfg.attack.reach != 9.0 and cfg.speeds.flee != 9.0 and cfg.leash_m != 99.0, cfg.species_id + ": a deep copy")


func test_scale_cfg_scales_every_length_and_speed_by_q_and_keeps_the_rest() -> void:
	var cfgs := {"ambush": ambush_cfg, "rammer": rammer_cfg,
		"rules on": CreatureBrain.config("rammer", RAMMER_BLOCK, AI, RELATIONSHIPS_ON)}
	var scaled_keys := 0
	for q in LADDER_QS:
		for name in cfgs:
			var cfg: Dictionary = cfgs[name]
			var s := CreatureBrain.scale_cfg(cfg, q)
			for leaf in leaves(cfg):
				var path: String = leaf[0]
				var kind := CreatureBrain.key_kind(path)
				if path == "attack.travel":
					continue
				if kind == "length" or kind == "speed":
					check_eq(_at(s, path), float(leaf[1]) * q, "%s q %.6f: %s x q" % [name, q, path])
					scaled_keys += 1
				else:
					check_eq(_at(s, path), leaf[1], "%s q %.6f: %s kept" % [name, q, path])
			var a: Dictionary = s.attack
			var flight := Locomotion.strike_travel(float(a.burst_speed), int(a.burst_ticks), float(a.glide_drag),
				int(a.glide_ticks), CreatureBrain.DT)
			check_eq(a.travel, flight, "%s q %.6f: the travel is the scaled burst's own (D-26)" % [name, q])
			check(a.travel != float(cfg.attack.travel) * q, "%s q %.6f: which is not travel x q" % [name, q])
	check(scaled_keys >= 3 * 2 * 25, "the lengths and speeds were scaled (%d)" % scaled_keys)
	var small := CreatureBrain.scale_cfg(rammer_cfg, 0.625)
	check(is_inf(small.forage_radius_m), "INF stays INF")
	check_eq(CreatureBrain.scale_cfg(cfgs["rules on"], 0.625).fear_radius_share, 1.25, "a share is kept")
	check_eq([small.leash_m, small.attack.reach, small.feed_reach, small.attack.burst_speed], [1.875, 0.21875, 0.15625, 2.5],
		"the rammer's leash, ram reach, feed reach and burst at q 0.625")
	check_eq([small.speeds.flee, small.attack.burst_ticks, small.attack.aim, small.hungry_below],
		[rammer_cfg.speeds.flee, rammer_cfg.attack.burst_ticks, rammer_cfg.attack.aim, rammer_cfg.hungry_below],
		"its speed shares, ticks, aim and hunger share kept")


func test_a_scaled_cfgs_strike_lane_is_the_strike_it_runs() -> void:
	for q in LADDER_QS:
		for kind in ["ambush", "rammer"]:
			var a: Dictionary = CreatureBrain.scale_cfg(ambush_cfg if kind == "ambush" else rammer_cfg, q).attack
			var body := (ambush_body if kind == "ambush" else rammer_body).scaled(q)
			var lane := CreatureBrain.strike_lane(a, body.radius, 0.5, Vector2.ZERO, 0.0)
			var where := "%s at q %.6f" % [kind, q]
			check_eq(lane.travel, a.travel, where + ": the lane runs the cfg's travel")
			check_eq(lane.half_width, body.radius + float(a.reach) + 0.5, where + ": as wide as its scaled radius and reach")
			var m := Locomotion.MotionState.new(Vector2.ZERO, 0.0)
			for i in int(a.burst_ticks):
				Locomotion.burst(m, 0.0, float(a.burst_speed))
				m.position += m.velocity * DT
			for i in int(a.glide_ticks):
				Locomotion.glide(m, float(a.glide_drag), DT)
				m.position += m.velocity * DT
			check_near(float(lane.travel), m.position.x, 0.01 * q, where + ": the travel is the scaled strike's flight")


# --- S2: relationship rules 1 to 4 in the brain (plan B.6; D-63) ---

## A settled ambush hunter or rammer as above, its cfg built with the relationships block `rel`.
func _with_rules(kind: String, rel: Dictionary, settled := true) -> Critter:
	var c := (_ambush(Vector2.ZERO, 0.0, settled) if kind == "ambush" else _rammer())
	c.mem.cfg = CreatureBrain.config(c.mem.cfg.species_id, AMBUSH_BLOCK if kind == "ambush" else RAMMER_BLOCK, AI, rel)
	return c


## `ticks` ticks from 0 with the same still percepts (built at `places`: [id, position, extra]),
## the body held still; returns the critter.
func _watch(c: Critter, ticks: int, places: Array) -> Critter:
	for t in ticks:
		var percepts := []
		for place in places:
			percepts.append(_percept(c, place[0], place[1], place[2]))
		_tick(c, t, percepts, false)
	return c


func test_rule_1_an_ambush_brain_picks_prey_up_to_its_prey_share_with_the_tolerance() -> void:
	var ahead := Vector2(2.0, 0.0)
	# The hunter's radius is 0.75: with the rule on (share 1.0) prey ends at 0.75; off, M1's 1.6 (1.2).
	for case in [[RELATIONSHIPS_ON, 0.75, true], [RELATIONSHIPS_ON, 0.75 + 0.5e-6, true], [RELATIONSHIPS_ON, 0.75 + 2e-6, false],
			[RELATIONSHIPS_ON, 0.76, false], [_rules_only(""), 0.76, true], [_rules_only(""), 1.2, true],
			[_rules_only(""), 1.21, false], [_rules_only("prey_share"), 0.76, false], [{}, 0.76, true]]:
		var c := _watch(_with_rules("ambush", case[0]), 7, [["b", ahead, {"species": "rammer", "radius": case[1]}]])
		var rules: String = "every rule" if case[0] == RELATIONSHIPS_ON else str(case[0].get("rules", "no block"))
		check_eq(c.mem.state == "notice", case[2], "%s, radius %.7f: %s" % [rules, case[1], c.label()])
		check(c.of("creature_fled").is_empty(), "%s, radius %.7f: no fear in this range" % [rules, case[1]])


func test_rule_2_a_rammer_charges_intruders_up_to_its_intruder_share_and_still_charges_ambush_hunters() -> void:
	var inside := Vector2(0.0, 3.0)
	# The rammer's radius is 0.625: with the rule on (share 1.2) intruders end at 0.75, an ambush
	# hunter exactly (0.625 x 1.2 == 0.75, and the tolerance holds it either way); off, no upper bound.
	for case in [[RELATIONSHIPS_ON, 0.75, true], [RELATIONSHIPS_ON, 0.75 + 0.5e-6, true], [RELATIONSHIPS_ON, 0.75 + 2e-6, false],
			[RELATIONSHIPS_ON, 0.3, true], [RELATIONSHIPS_ON, 0.29, false], [_rules_only(""), 0.76, true],
			[_rules_only("intruder_share"), 0.76, false], [_rules_only(""), 0.29, false]]:
		var c := _watch(_with_rules("rammer", case[0]), 12, [["b", inside, {"species": "ambush_hunter", "radius": case[1]}]])
		var rules: String = "every rule" if case[0] == RELATIONSHIPS_ON else str(case[0].rules)
		check_eq(c.mem.state == "notice", case[2], "%s, radius %.7f: %s" % [rules, case[1], c.label()])
	var off := _watch(_rammer(), 12, [["b", inside, {"species": "ambush_hunter", "radius": 5.0}]])
	check_eq(off.label(), "notice", "M1's rammer charges a body of any size")


func test_rule_3_a_creature_flees_the_nearest_body_it_fears_on_sight_and_only_with_the_rule_on() -> void:
	var near := Vector2(0.0, 1.0)
	var far := Vector2(3.0, 1.0)
	# The rammer (0.625, share 1.25) fears from 0.78125; it is not an intruder there (above 0.75).
	for case in [[RELATIONSHIPS_ON, 0.78125, "flee"], [RELATIONSHIPS_ON, 0.78125 - 0.5e-6, "flee"],
			[RELATIONSHIPS_ON, 0.78125 - 2e-6, "rest"], [RELATIONSHIPS_ON, 50.0, "flee"],
			[_rules_only("fear"), 0.78125, "flee"], [_rules_only(""), 0.78125, "notice"], [{}, 50.0, "notice"]]:
		var c := _watch(_with_rules("rammer", case[0]), 7, [["big", near, {"species": "lurker", "radius": case[1]}]])
		var where := "%s, radius %.7f" % ["every rule" if case[0] == RELATIONSHIPS_ON else str(case[0].get("rules", "no block")), case[1]]
		check_eq(c.mem.state, case[2], where)
		check_eq(c.of("creature_fled").size(), 1 if case[2] == "flee" else 0, where + ": fled once or not at all")
		check_eq(c.mem.fear_of, "big" if case[2] == "flee" else "", where + ": fear_of")
	var c := _watch(_with_rules("rammer", RELATIONSHIPS_ON), 7, [["big_a", near, {"species": "lurker", "radius": 0.8}],
		["big_b", far, {"species": "lurker", "radius": 2.0}]])
	var fled := c.of("creature_fled")
	check(fled.size() == 1 and fled[0].from == "big_a" and int(fled[0].tick) == 5, "it flees the nearer one at its first think: %s" % [fled])
	check_eq(c.mem.fear_of, "big_a", "and remembers which")
	check_eq(c.mem.flee_from, near, "it flees from where it saw it")
	check_eq(c.mem.target, "", "with no target")
	var d := CreatureBrain.drive(c.mem, c.view(), 7, null)
	check(Vector2(d.move).dot(Vector2(c.m.position - near).normalized()) > 0.99, "and swims straight away from it: %s" % d.move)
	check_eq(float(d.speed_mul), float(c.mem.cfg.speeds.flee), "at its flee speed")
	# Fear ignores the settle window (Q-S7): a fresh spawn flees at once.
	var fresh := _watch(_with_rules("ambush", RELATIONSHIPS_ON, false), 7, [["big", Vector2(2.0, 0.0), {"species": "lurker", "radius": 0.9375}]])
	check(fresh.mem.ignore_all_until > 7, "still settling")
	check_eq(fresh.label(), "flee", "an ambush hunter (0.75, fears from 0.9375) flees while it settles")


func test_rule_3_a_feared_body_in_view_keeps_the_flee_going_and_its_end_clears_fear_of() -> void:
	var c := _with_rules("rammer", RELATIONSHIPS_ON)
	var big := ["big", Vector2(0.0, 1.0), {"species": "lurker", "radius": 0.8}]
	_watch(c, 100, [big])
	# Thinks fall on ticks 5, 11, ... 95 (number 1, every 6 ticks): the last sighting is at 95.
	check_eq(c.mem.state_tick, 95, "every sighting restarts the flee")
	check_eq(c.of("creature_fled").size(), 1, "one creature_fled for the whole flee")
	var labels := {}
	for t in range(100, 420):
		_tick(c, t, [], false)
		labels[t] = c.label()
	check_eq(labels[394], "flee", "still fleeing 300 ticks after the last sighting less one")
	check_eq(labels[395], "wander/return", "then home, exactly the flee time after it")
	check_eq(c.mem.fear_of, "", "fear_of is cleared when the flee ends")
	check(not c.mem.flee_from.is_finite(), "and so is flee_from")
	check(not c.mem.to_dict().has("fear_of"), "so the memory dict is M1's again")


func test_rule_3_the_flee_steers_from_the_feared_body_before_the_attacker_and_a_hurt_restarts_it() -> void:
	var c := _with_rules("rammer", RELATIONSHIPS_ON)
	c.health_share = 0.3
	CreatureBrain.on_hurt(c.mem, {"id": "a", "species": "lineage", "position": Vector2(-1.2, -2.0), "radius": 0.5}, 0)
	_tick(c, 1, [], false)
	check_eq(c.label(), "flee", "hurt below its flee share, it flees the attacker")
	check_eq(c.mem.flee_from, Vector2(-1.2, -2.0), "from where it was hurt")
	var big_at := Vector2(2.0, -2.0)
	for t in range(2, 12):
		_tick(c, t, [_percept(c, "big", big_at, {"species": "lurker", "radius": 0.8})], false)
	check_eq(c.mem.fear_of, "big", "a feared body seen while fleeing becomes what it flees")
	check_eq(c.mem.flee_from, big_at, "the flee handler steers from it, not from the attacker")
	check_eq(c.mem.state_tick, 11, "the flee time restarted at the sighting")
	check_eq(c.of("creature_fled").size(), 1, "no second creature_fled: it was already fleeing")
	CreatureBrain.on_hurt(c.mem, {"id": "a", "species": "lineage", "position": Vector2(-1.0, -2.0), "radius": 0.5}, 20)
	for t in range(21, 30):
		_tick(c, t, [], false)
	check_eq(c.mem.state_tick, 21, "a hurt restarts it as in M1")
	check_eq(c.mem.flee_from, big_at, "and the remembered feared body still comes first")


func test_rule_3_interrupts_a_tell_but_never_a_strike_and_the_strike_ends_in_the_flee() -> void:
	var big := {"species": "lurker", "radius": 1.0}
	var c := _with_rules("ambush", RELATIONSHIPS_ON)
	c.energy_share = 0.5
	var t := 0
	while t < 300 and c.of("creature_tell").is_empty():
		_tick(c, t, [_percept(c, "a", Vector2(2.75, 0.0))])
		t += 1
	check_eq(c.label(), "attack/tell", "telling at its prey")
	for i in 6:
		_tick(c, t + i, [_percept(c, "a", Vector2(2.75, 0.0)), _percept(c, "big", Vector2(-6.0, 0.0), big)])
	var recovered := c.of("creature_recovered")
	check(recovered.size() == 1 and recovered[0].outcome == "interrupted", "the tell is interrupted: %s" % [recovered])
	check_eq(c.label(), "flee", "and it flees")
	check_eq(c.mem.target, "", "dropping its prey")
	check(c.of("creature_strike").is_empty(), "no strike")
	var s := _with_rules("ambush", RELATIONSHIPS_ON)
	s.energy_share = 0.5
	var u := 0
	while u < 300 and s.of("creature_strike").is_empty():
		_tick(s, u, [_percept(s, "a", Vector2(2.75, 0.0))])
		u += 1
	var modes := []
	for i in 40:
		modes.append(_tick(s, u + i, [_percept(s, "big", Vector2(-6.0, 0.0), big)]).mode)
	check_eq(modes.slice(0, 35), modes.slice(0, 20).map(func(_m): return "burst") + modes.slice(20, 35).map(func(_m): return "glide"),
		"the strike runs its course")
	check_eq(s.label(), "flee", "then it flees")
	check_eq(s.of("creature_fled").size(), 1, "once")


func test_rule_4_a_hurt_from_a_body_above_the_engage_share_is_fled_not_answered() -> void:
	# [kind, relationships, attacker radius, what it does on the next think]
	for case in [["rammer", RELATIONSHIPS_ON, 0.75, "notice"], ["rammer", RELATIONSHIPS_ON, 0.75 + 0.5e-6, "notice"],
			["rammer", RELATIONSHIPS_ON, 0.75 + 2e-6, "flee"],
			["rammer", RELATIONSHIPS_ON, 0.76, "flee"], ["rammer", _rules_only(""), 0.76, "notice"],
			["rammer", _rules_only("no_engage_above"), 5.0, "notice"],
			["ambush", RELATIONSHIPS_ON, 0.75, "notice"], ["ambush", RELATIONSHIPS_ON, 0.76, "flee"],
			["ambush", _rules_only("no_engage_above"), 1.2, "notice"], ["ambush", _rules_only("no_engage_above"), 1.21, "flee"],
			["ambush", {}, 1.21, "notice"]]:
		var c := _with_rules(case[0], case[1])
		var at := c.m.position + Vector2(-1.0, 0.0)
		CreatureBrain.on_hurt(c.mem, {"id": "a", "species": "lurker", "position": at, "radius": case[2]}, 0)
		_tick(c, 1, [], false)
		var where := "%s, %s, attacker %.7f" % [case[0], "every rule" if case[1] == RELATIONSHIPS_ON else str(case[1].get("rules", "no block")), case[2]]
		check_eq(c.mem.state, case[3], where)
		if case[3] == "flee":
			var fled := c.of("creature_fled")
			check(fled.size() == 1 and fled[0].from == "a", where + ": creature_fled from the attacker")
			check_eq(c.mem.flee_from, at, where + ": from where it was hurt")
			check_eq(c.mem.fear_of, "", where + ": a hurt is no fear")
	# Engaged, M1 keeps its target when hurt by another; rule 4 flees the body above its share.
	for rel in [RELATIONSHIPS_ON, _rules_only("")]:
		var r := _watch(_with_rules("rammer", rel), 60, [["b", Vector2(0.0, 6.0), {}]])
		check_eq(r.label(), "chase/pursue", "chasing an intruder")
		CreatureBrain.on_hurt(r.mem, {"id": "a", "species": "lurker", "position": Vector2(-1.0, -2.0), "radius": 0.76}, 60)
		_tick(r, 61, [_percept(r, "b", Vector2(0.0, 6.0))], false)
		if rel == RELATIONSHIPS_ON:
			check_eq(r.label(), "flee", "with rule 4 it flees")
		else:
			check(r.mem.state == "chase" and r.mem.target == "b", "without it, it keeps its target: %s" % r.label())


func test_the_memory_dict_holds_fear_of_only_when_it_is_set() -> void:
	var c := _ambush()
	var plain := c.mem.to_dict()
	check(not plain.has("fear_of"), "left out at its default")
	c.mem.fear_of = "big"
	var feared := c.mem.to_dict()
	check_eq(feared.get("fear_of", ""), "big", "written when set")
	feared.erase("fear_of")
	check_eq(feared, plain, "and nothing else changes")
	CreatureBrain.forget(c.mem, "big", 0, 0)
	check_eq(c.mem.fear_of, "", "forgetting the body clears it")
	c.mem.fear_of = "big"
	CreatureBrain.on_target_gone(c.mem, "other", 0)
	check_eq(c.mem.fear_of, "big", "another body going away does not")
	CreatureBrain.on_target_gone(c.mem, "big", 0)
	check_eq(c.mem.fear_of, "", "the body going away does")
	c.mem.fear_of = "big"
	CreatureBrain.force_return(c.mem, "player", 0, 0)
	check_eq(c.mem.fear_of, "", "a forced return clears it")


func test_with_every_rule_on_m1_bodies_decide_as_with_every_rule_off() -> void:
	# Every M1 pair lies inside the shares (plan B.6): the same scripted encounters, the same memory.
	var bodies := [["cell", 0.5, "lineage"], ["hunter", 0.75, "ambush_hunter"], ["rammer", 0.625, "rammer"]]
	for kind in ["ambush", "rammer"]:
		for hungry in [false, true]:
			var runs := []
			for rel in [{}, RELATIONSHIPS_ON]:
				var c := _with_rules(kind, rel)
				c.energy_share = 0.5 if hungry else 0.9
				var rng := RandomNumberGenerator.new()
				rng.seed = 5150
				for t in 900:
					var percepts := []
					for b in bodies:
						if b[2] == c.mem.cfg.species_id:
							continue
						var at := Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
						percepts.append(_percept(c, b[0], at, {"radius": b[1], "species": b[2]}))
					percepts.sort_custom(func(x, y): return x.distance < y.distance)
					if t % 97 == 40:
						var p: Dictionary = percepts[rng.randi_range(0, percepts.size() - 1)]
						CreatureBrain.on_hurt(c.mem, p, t)
					_tick(c, t, percepts)
				runs.append({"memory": c.mem.to_dict(), "events": c.events})
			var where := "%s, %s" % [kind, "hungry" if hungry else "sated"]
			check_eq(runs[1].memory, runs[0].memory, where + ": the same memory after 900 ticks")
			check_eq(runs[1].events, runs[0].events, where + ": the same events")
			check(runs[0].events.size() > 5, where + ": and something happened (%d events)" % runs[0].events.size())


func test_a_scaled_brain_feeds_and_strikes_exactly_as_far_as_the_resolver_lets_its_scaled_body() -> void:
	# The brain's reaches are cfg lengths (scale_cfg x q); the resolver's are its constants x the
	# actor's reach_scale (q). Each pair must agree, or a small creature would stop short or eat air.
	for q in [1.0] + LADDER_QS:
		var cfg := CreatureBrain.scale_cfg(rammer_cfg, q)
		var body := rammer_body.scaled(q)
		var mem := CreatureBrain.create("territorial", cfg, Vector2.ZERO, 0.0, {"center": Vector2.ZERO, "radius": ZONE_R}, 1, 0)
		var me := {"position": Vector2.ZERO, "radius": body.radius}
		var actor := InteractionResolver.Actor.new("c_1", Vector2.ZERO, 0.0, body)
		actor.reach_scale = q
		var touched := 0
		var refused := 0
		for i in 80:
			var x := body.radius + 0.1 + i * 0.005
			var food := {"id": "pk", "kind": "plant", "position": Vector2(x, 0.0), "radius": 0.1, "energy": 1.0}
			var touching := CreatureBrain._touching(mem, me, food)
			var fed := InteractionResolver.feed(actor, food, float(i))
			check_eq(touching, fed.allowed, "q %.6f, food at %.3f: the brain touches it as the resolver feeds (%s)" % [q, x, fed.reason])
			touched += 1 if touching else 0
			refused += 0 if touching else 1
		check(touched > 0 and refused > 0, "q %.6f: the sweep crosses the reach" % q)
		for kind in ["bite", "ram"]:
			var c: Dictionary = (ambush_cfg if kind == "bite" else rammer_cfg)
			var a: Dictionary = CreatureBrain.scale_cfg(c, q).attack
			var striker := (ambush_body if kind == "bite" else rammer_body).scaled(q)
			var prey := Phenotype.new()
			prey.radius = 0.3 * q
			var lane := CreatureBrain.strike_lane(a, striker.radius, prey.radius, Vector2.ZERO, 0.0)
			var hitter := InteractionResolver.Actor.new("c_1", Vector2.ZERO, 0.0, striker)
			hitter.reach_scale = q
			for edge in [-1e-4, 1e-4]:
				var target := InteractionResolver.Actor.new("t", Vector2(float(lane.half_width) + edge, 0.0), 0.0, prey)
				var r := InteractionResolver.bite(hitter, target, 0.0) if kind == "bite" else InteractionResolver.ram(hitter, target, 1.0, 0.0)
				check_eq(r.reason != "out of reach", edge < 0.0, "q %.6f, %s %+.4f m from the lane's edge: %s" % [q, kind, edge, r.reason])


## D-82: the smallest disc holding two discs. One that holds the other is the answer; otherwise the
## disc spanning both along the line through their centres, which touches each from inside.
func test_union_disc_is_the_smallest_disc_holding_both() -> void:
	var big := {"center": Vector2(0.0, 0.0), "radius": 5.0}
	var small := {"center": Vector2(1.0, 0.0), "radius": 2.0}
	check_eq(CreatureBrain.union_disc(big, small), big, "the larger holds the smaller")
	check_eq(CreatureBrain.union_disc(small, big), big, "either way round")
	check_eq(CreatureBrain.union_disc(big, big.duplicate()), big, "equal discs: one of them")
	var a := {"center": Vector2(0.0, 0.0), "radius": 1.0}
	var b := {"center": Vector2(10.0, 0.0), "radius": 3.0}
	check_eq(CreatureBrain.union_disc(a, b), {"center": Vector2(6.0, 0.0), "radius": 7.0}, "apart: (10 + 1 + 3) / 2 = 7, from 6")
	var c := {"center": Vector2(0.0, 0.0), "radius": 4.0}
	var d := {"center": Vector2(3.0, 4.0), "radius": 2.0}
	var u := CreatureBrain.union_disc(c, d)
	check_near(float(u.radius), 5.5, 1e-9, "overlapping: (5 + 4 + 2) / 2")
	check(Vector2(u.center).is_equal_approx(Vector2(0.9, 1.2)), "its centre 1.5 along the line: %s" % [u.center])
	for disc in [c, d]:
		check_near(Vector2(disc.center).distance_to(u.center) + float(disc.radius), float(u.radius), 1e-5, "it touches each from inside")
