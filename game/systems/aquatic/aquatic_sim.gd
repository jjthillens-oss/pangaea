class_name AquaticSim
extends RefCounted
## The Aquatic stage's world (aquatic plan section 8, PROPOSED): one reef-to-deep route, the player's fish, its kin
## at the nest, the reef grazers, the silver shoal, the lancer and the abyssal drifter, and the feeding sites.
## Deterministic at 60 ticks a second: durations are whole ticks (converted once here), actors are kept in id order,
## and every random draw comes from a stream seeded by the world seed. No scene, clock, input or files: the stage
## feeds it an intent per tick and reads its state and events.
##
## Coordinates are Godot's: +Y up (the surface is y = 0, depth is -y), the route runs from the shore at +Z down to
## the deep at -Z. A heading of 0 faces -Z; a positive turn input turns right.
##
## Every depth hazard warns before it harms (Bible §6): pressure runs a warning before its drain, the lancer
## investigates before it pursues and only strikes from a pursuit, and the drifter's sweep needs its warning to have
## run. tests/test_aquatic_sim.gd checks each.

const TICK_HZ := 60
const DT := 1.0 / TICK_HZ
const PLAYER_ID := "player"
const KIN_ID := "kin"
const BITE_COOLDOWN := 30   ## ticks
const STARVE_DRAIN := 2.0   ## health per second with no energy left
const VERTICAL_RESPONSE := 3.0   ## per second: how fast vertical speed reaches its target
## The route's rock walls (the sea floor asset's, tools/blender/make_aquatic_world.py): the floor rises WALL_HEIGHT
## over WALL_SPAN from |x| = WALL_START.
const WALL_START := 36.0
const WALL_SPAN := 16.0
const WALL_HEIGHT := 16.0

## One tick's input. thrust, turn and rise are -1..1; bite, signal and interact are presses on this tick.
class Intent:
	var thrust := 0.0
	var turn := 0.0
	var rise := 0.0
	var burst := false
	var bite := false
	var signal_call := false
	var interact := false

	func _init(p_thrust := 0.0, p_turn := 0.0, p_rise := 0.0) -> void:
		thrust = p_thrust
		turn = p_turn
		rise = p_rise


var rules: Dictionary
var world_seed := 0
var tick := 0
## {"pos": Vector3, "heading", "speed", "vy", "energy", "health", "body", "stats", "generation"}
var player := {}
var kin := {}
## Lineage facts carried from the cell stage (AquaticLineage.read): lineage_id, notes, species_seen, ...
var lineage := {}
var points := 0
var meals := 0
var deaths := 0
## Each: {"id", "kind", "site", "pos", "alive", "regrow_at"}, in id order.
var food: Array = []
## Each: {"id", "species", "pos", "heading", "hp", "alive", "respawn_at", "target", "state"}, in id order.
var animals: Array = []
## {"pos", "heading", "state": patrol | investigate | pursue | disengage, "until", "cooldown_until", "angle"}
var lancer := {}
## {"pos", "heading", "warn_ticks", "cooldown_until"}
var drifter := {}
## species id -> {"standing": "neutral" | "friend" | "foe", "rapport", "last_signal"}
var relations := {}
## zone and site ids found, in the order found.
var discovered: PackedStringArray = []
## The generations this run has made: {"generation", "body"}.
var history: Array = []
## This tick's events: {"type", ...}. The stage drains them with take_events().
var events: Array = []
var pressure_ticks := 0
var last_cause := ""

var _t := {}   ## durations in ticks
var _rng_food := RandomNumberGenerator.new()
var _rng_life := RandomNumberGenerator.new()
var _bite_ready_at := 0
var _at_shore := false
var _zone := ""


## A world for `body` (an AquaticBody dictionary) from the rules (aquatic_rules.json) and the world seed.
func _init(p_rules: Dictionary, p_world_seed: int, body: Dictionary, p_lineage := {}) -> void:
	rules = p_rules
	world_seed = p_world_seed
	lineage = p_lineage
	_rng_food.seed = hash([world_seed, "aquatic.food"])
	_rng_life.seed = hash([world_seed, "aquatic.life"])
	var hz: Dictionary = rules.hazards
	var w: Dictionary = rules.world
	_t = {
		"pressure_warn": _ticks(hz.pressure.warn),
		"investigate": _ticks(hz.lancer.investigate), "pursue": _ticks(hz.lancer.pursue),
		"disengage": _ticks(hz.lancer.disengage), "lancer_cooldown": _ticks(hz.lancer.cooldown),
		"drifter_period": _ticks(hz.drifter.period), "drifter_warn": _ticks(hz.drifter.warn),
		"drifter_cooldown": _ticks(hz.drifter.cooldown),
		"signal_gap": _ticks(rules.species.grazer.signal_gap),
	}
	for kind in w.food:
		_t["regrow_" + kind] = _ticks(w.food[kind].regrow)
	points = int(p_lineage.get("points", int(rules.editor.start_points)))
	_place_player(body, int(p_lineage.get("generation", 1)))
	kin = {"pos": nest_pos() + Vector3(2.5, 0.4, -1.5), "heading": PI * 0.5}
	_build_food()
	_build_animals()
	lancer = {"pos": _v(hz.lancer.home), "heading": 0.0, "state": "patrol", "until": 0, "cooldown_until": 0, "angle": 0.0}
	drifter = {"pos": Vector3.ZERO, "heading": 0.0, "warn_ticks": 0, "cooldown_until": 0}
	_move_drifter()
	for species in ["grazer", "shoal"]:
		relations[species] = {"standing": "neutral", "rapport": 0, "last_signal": -1000000}
	var saved: Dictionary = p_lineage.get("aquatic", {})
	if not saved.is_empty():
		restore(saved)
	_zone = zone_at(player.pos).id
	_discover(_zone)


static func _ticks(seconds: Variant) -> int:
	return maxi(1, int(round(float(seconds) * TICK_HZ)))


static func _v(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _place_player(body: Dictionary, generation: int) -> void:
	var s := AquaticBody.stats(body, rules.body)
	player = {"pos": nest_pos() + Vector3(0.0, 0.5, -3.0), "heading": 0.0, "speed": 0.0, "vy": 0.0,
			"energy": s.energy_capacity * 0.8, "health": s.max_health, "body": body.duplicate(), "stats": s,
			"generation": generation}


# --- the route ---------------------------------------------------------------------------------------------------

func nest_pos() -> Vector3:
	return _v(rules.world.nest.pos)


## The sea floor's height (y) at `z`: the floor profile's points, joined by straight lines.
func floor_y(z: float) -> float:
	var pts: Array = rules.world.floor
	if z >= float(pts[0][0]):
		return float(pts[0][1])
	for i in range(1, pts.size()):
		var a: Array = pts[i - 1]
		var b: Array = pts[i]
		if z >= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (z - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(pts[pts.size() - 1][1])


## The floor's height at (x, z): the profile plus the side walls.
func floor_at(x: float, z: float) -> float:
	return floor_y(z) + wall_rise(x)


static func wall_rise(x: float) -> float:
	return WALL_HEIGHT * smoothstep(0.0, 1.0, clampf((absf(x) - WALL_START) / WALL_SPAN, 0.0, 1.0))


## The zone (rules.world.zones entry) at a position, by its depth.
func zone_at(pos: Vector3) -> Dictionary:
	var zones: Array = rules.world.zones
	var depth := -pos.y
	var out: Dictionary = zones[0]
	for z in zones:
		if depth >= float(z.depth):
			out = z
	return out


func _clamp_to_water(pos: Vector3) -> Vector3:
	var w: Dictionary = rules.world
	pos.x = clampf(pos.x, -float(w.half_width), float(w.half_width))
	pos.z = clampf(pos.z, float(w.end_z), float(w.shore_z))
	pos.y = clampf(pos.y, floor_at(pos.x, pos.z) + float(w.floor_margin), -float(w.surface_margin))
	return pos


func sheltered(pos: Vector3) -> String:
	for s in rules.world.shelters:
		if pos.distance_to(_v(s.pos)) <= float(s.radius):
			return String(s.id)
	return ""


static func forward_of(heading: float) -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


# --- setup -------------------------------------------------------------------------------------------------------

func _build_food() -> void:
	var n := 0
	for site in rules.world.feeding:
		var centre := _v(site.pos)
		for i in int(site.items):
			var a := _rng_food.randf() * TAU
			var r := sqrt(_rng_food.randf()) * float(site.spread)
			var p := centre + Vector3(cos(a) * r, (_rng_food.randf() - 0.5) * 3.0, sin(a) * r)
			if String(site.kind) != "plankton":
				p.y = floor_at(p.x, p.z) + 0.6
			n += 1
			food.append({"id": "food_%03d" % n, "kind": String(site.kind), "site": String(site.id),
					"pos": _clamp_to_water(p), "alive": true, "regrow_at": 0})


func _build_animals() -> void:
	var sp: Dictionary = rules.species
	var home_of := {"grazer": _shelter_pos(String(sp.grazer.home)), "shoal": _v(sp.shoal.home)}
	for species in ["grazer", "shoal"]:
		var cfg: Dictionary = sp[species]
		for i in int(cfg.count):
			var home: Vector3 = home_of[species]
			var p := _clamp_to_water(home + _wander_offset(float(cfg.wander)))
			animals.append({"id": "%s_%02d" % [species, i + 1], "species": species, "home": home, "pos": p,
					"heading": _rng_life.randf() * TAU, "hp": float(cfg.health), "alive": true, "respawn_at": 0,
					"target": p, "state": "wander"})


func _shelter_pos(id: String) -> Vector3:
	for s in rules.world.shelters:
		if String(s.id) == id:
			return _v(s.pos) + Vector3(0.0, 3.0, 0.0)
	return nest_pos()


func _wander_offset(radius: float) -> Vector3:
	var a := _rng_life.randf() * TAU
	var r := sqrt(_rng_life.randf()) * radius
	return Vector3(cos(a) * r, (_rng_life.randf() - 0.5) * radius * 0.4, sin(a) * r)


# --- the tick ----------------------------------------------------------------------------------------------------

func step(intent: Intent) -> void:
	tick += 1
	_swim(intent)
	_feed()
	_zones_and_sites()
	_animals_tick()
	_lancer_tick()
	_drifter_tick()
	_pressure_tick()
	_actions(intent)
	_regrow()
	if float(player.health) <= 0.0:
		_die()


func take_events() -> Array:
	var out := events
	events = []
	return out


func _emit(type: String, extra := {}) -> void:
	var e := {"type": type, "tick": tick}
	e.merge(extra)
	events.append(e)


func _swim(intent: Intent) -> void:
	var s: Dictionary = player.stats
	var thrust := clampf(intent.thrust, -1.0, 1.0)
	var starving := float(player.energy) <= 0.0
	if starving:
		thrust *= 0.4
	var burst := intent.burst and thrust > 0.0 and not starving
	var power := float(s.accel) * thrust * (float(s.burst_share) if burst else 1.0)
	if thrust < 0.0:
		power *= 0.35
	var speed := float(player.speed)
	speed += (power - float(s.drag) * speed) * DT
	player.speed = speed
	player.heading = wrapf(float(player.heading) - clampf(intent.turn, -1.0, 1.0) * AquaticBody.yaw_rate(s, absf(speed)) * DT, -PI, PI)
	var rise := clampf(intent.rise, -1.0, 1.0)
	var target_vy := rise * float(s.trim) if absf(rise) > 0.01 else float(s.idle_drift)
	player.vy = float(player.vy) + (target_vy - float(player.vy)) * minf(1.0, VERTICAL_RESPONSE * DT)
	var pos: Vector3 = player.pos + forward_of(player.heading) * speed * DT + Vector3(0.0, float(player.vy), 0.0) * DT
	player.pos = _clamp_to_water(pos)
	var cost := float(s.upkeep) + float(s.thrust_cost) * absf(thrust) * (float(rules.body.burst.energy_share) if burst else 1.0)
	player.energy = maxf(0.0, float(player.energy) - cost * DT)
	if starving:
		_hurt(STARVE_DRAIN * DT, "starvation")


func _feed() -> void:
	var s: Dictionary = player.stats
	var reach := float(rules.world.eat_reach) + float(s.radius)
	var food_rules: Dictionary = rules.world.food
	for f in food:
		if not f.alive or player.pos.distance_to(f.pos) > reach:
			continue
		var diet := String(food_rules[f.kind].diet)
		if (diet == "plant" and not s.eats_plants) or (diet == "meat" and not s.eats_meat):
			continue
		f.alive = false
		f.regrow_at = tick + int(_t["regrow_" + String(f.kind)])
		_gain_meal(float(food_rules[f.kind].energy), String(f.kind))


func _gain_meal(energy: float, kind: String) -> void:
	player.energy = minf(float(player.stats.energy_capacity), float(player.energy) + energy)
	meals += 1
	_emit("ate", {"kind": kind, "energy": energy})
	if meals % int(rules.world.points.meals_per_point) == 0:
		points += 1
		_emit("points", {"amount": 1, "why": "meals"})


func _regrow() -> void:
	for f in food:
		if not f.alive and tick >= int(f.regrow_at):
			f.alive = true
	for a in animals:
		if not a.alive and tick >= int(a.respawn_at):
			a.alive = true
			a.hp = float(rules.species[a.species].health)
			a.pos = _clamp_to_water(a.home + _wander_offset(float(rules.species[a.species].wander)))


func _discover(id: String) -> bool:
	if id in discovered:
		return false
	discovered.append(id)
	return true


func _zones_and_sites() -> void:
	var z := zone_at(player.pos)
	if String(z.id) != _zone:
		_zone = String(z.id)
		_emit("zone", {"id": _zone, "name": String(z.name)})
	if _discover(_zone):
		points += int(rules.world.points.zone_found)
		_emit("found", {"id": _zone, "name": String(z.name), "points": int(rules.world.points.zone_found)})
	var sight := float(player.stats.sight)
	for list in [rules.world.shelters, rules.world.feeding]:
		for site in list:
			if player.pos.distance_to(_v(site.pos)) <= minf(sight, 14.0) and _discover(String(site.id)):
				_emit("found", {"id": String(site.id), "name": String(site.name), "points": 0})
	var at_shore: bool = player.pos.distance_to(_v(rules.world.shore.pos)) <= float(rules.world.shore.radius)
	if at_shore and not _at_shore:
		_emit("shore")
	_at_shore = at_shore


# --- animals -----------------------------------------------------------------------------------------------------

func _animals_tick() -> void:
	var lancer_hunting := String(lancer.state) in ["investigate", "pursue"]
	for a in animals:
		if not a.alive:
			continue
		var cfg: Dictionary = rules.species[a.species]
		var rel: Dictionary = relations[a.species]
		var to_player: Vector3 = player.pos - a.pos
		var speed := float(cfg.speed)
		var goal: Vector3 = a.target
		a.state = "wander"
		if a.species == "grazer" and lancer_hunting and a.pos.distance_to(lancer.pos) < 18.0:
			a.state = "hide"
			goal = a.home
			speed = float(cfg.flee_speed)
		elif to_player.length() < float(cfg.flee_reach) and (a.species == "shoal" or rel.standing == "foe"):
			a.state = "flee"
			goal = a.pos - to_player.normalized() * 6.0
			speed = float(cfg.flee_speed)
		elif a.species == "grazer" and rel.standing == "friend" and _zone == "reef" \
				and player.pos.distance_to(a.home) < float(cfg.follow_leash):
			a.state = "follow"
			var side := Vector3(float(int(String(a.id).right(2)) % 3) - 1.0, 0.6, 1.0).normalized() * 3.5
			goal = player.pos + side
			speed = maxf(speed, float(player.speed) * 1.1)
		else:
			if a.pos.distance_to(a.target) < 1.0:
				a.target = _clamp_to_water(a.home + _wander_offset(float(cfg.wander)))
			goal = a.target
		var d: Vector3 = goal - a.pos
		if d.length() > 0.05:
			var stepv := d.normalized() * minf(d.length(), speed * DT)
			a.pos = _clamp_to_water(a.pos + stepv)
			a.heading = atan2(-stepv.x, -stepv.z)


func _lancer_tick() -> void:
	var cfg: Dictionary = rules.hazards.lancer
	var home := _v(cfg.home)
	var p: Vector3 = player.pos
	var dist := p.distance_to(lancer.pos)
	var in_territory := p.distance_to(home) < float(cfg.territory)
	var hidden := sheltered(p) != ""
	var goal: Vector3 = lancer.pos
	var speed := float(cfg.patrol_speed)
	match String(lancer.state):
		"patrol":
			lancer.angle = float(lancer.angle) + float(cfg.patrol_speed) / float(cfg.patrol_radius) * DT
			goal = home + Vector3(cos(lancer.angle), 0.0, sin(lancer.angle)) * float(cfg.patrol_radius)
			if tick >= int(lancer.cooldown_until) and dist < float(cfg.notice) and in_territory and not hidden:
				_set_lancer("investigate", _t.investigate)
				_emit("lancer_investigate")
				if _friend_near(float(rules.species.grazer.warn_reach)):
					_emit("ally_warning")
		"investigate":
			goal = p
			speed = float(cfg.investigate_speed)
			if hidden or not in_territory:
				_disengage("hidden" if hidden else "left")
			elif tick >= int(lancer.until):
				_set_lancer("pursue", _t.pursue)
				_emit("lancer_pursue")
		"pursue":
			goal = p
			speed = float(cfg.pursue_speed)
			if dist <= float(cfg.strike_reach):
				_hurt(float(cfg.strike_damage), "lancer")
				_emit("struck", {"by": "lancer", "damage": float(cfg.strike_damage)})
				if player.stats.spines:
					_emit("stung", {"who": "lancer"})
				_disengage("struck")
			elif hidden or not in_territory or tick >= int(lancer.until):
				_disengage("hidden" if hidden else ("left" if not in_territory else "outlasted"))
		"disengage":
			goal = home
			speed = float(cfg.patrol_speed) * 1.5
			if tick >= int(lancer.until):
				lancer.state = "patrol"
	var d: Vector3 = goal - lancer.pos
	if d.length() > 0.05:
		var stepv := d.normalized() * minf(d.length(), speed * DT)
		lancer.pos = _clamp_to_water(lancer.pos + stepv)
		lancer.heading = atan2(-stepv.x, -stepv.z)


func _friend_near(reach: float) -> bool:
	if relations.grazer.standing != "friend":
		return false
	for a in animals:
		if a.alive and a.species == "grazer" and a.pos.distance_to(player.pos) < reach:
			return true
	return false


func _set_lancer(state: String, ticks: int) -> void:
	lancer.state = state
	lancer.until = tick + ticks


func _disengage(why: String) -> void:
	_set_lancer("disengage", _t.disengage)
	lancer.cooldown_until = tick + _t.disengage + _t.lancer_cooldown
	_emit("lancer_gave_up", {"why": why})


func _move_drifter() -> void:
	var cfg: Dictionary = rules.hazards.drifter
	var theta := TAU * float(tick % int(_t.drifter_period)) / float(_t.drifter_period)
	var c := _v(cfg.centre)
	var r: Array = cfg.radii
	var x := c.x + float(r[0]) * cos(theta)
	var z := c.z + float(r[1]) * sin(theta)
	var pos := Vector3(x, floor_y(z) + float(cfg.height_over_floor), z)
	var tangent := Vector3(-float(r[0]) * sin(theta), 0.0, float(r[1]) * cos(theta))
	drifter.pos = pos
	drifter.heading = atan2(-tangent.x, -tangent.z)


func _drifter_tick() -> void:
	var cfg: Dictionary = rules.hazards.drifter
	_move_drifter()
	var dist: float = player.pos.distance_to(drifter.pos)
	if dist < float(cfg.warn_reach):
		if int(drifter.warn_ticks) == 0:
			_emit("drifter_warning")
		drifter.warn_ticks = int(drifter.warn_ticks) + 1
	else:
		drifter.warn_ticks = 0
	if dist < float(cfg.sweep_reach) and int(drifter.warn_ticks) > int(_t.drifter_warn) and tick >= int(drifter.cooldown_until):
		_hurt(float(cfg.sweep_damage), "drifter")
		var away: Vector3 = (player.pos - drifter.pos)
		away.y = 0.0
		player.pos = _clamp_to_water(player.pos + (away.normalized() if away.length() > 0.01 else Vector3.BACK) * 4.0)
		drifter.cooldown_until = tick + int(_t.drifter_cooldown)
		_emit("struck", {"by": "drifter", "damage": float(cfg.sweep_damage)})


func _pressure_tick() -> void:
	var depth := -float(player.pos.y)
	if depth <= float(player.stats.rated_depth):
		if pressure_ticks > 0:
			_emit("pressure_clear")
		pressure_ticks = 0
		return
	if pressure_ticks == 0:
		_emit("pressure_warning", {"rated": float(player.stats.rated_depth)})
	pressure_ticks += 1
	if pressure_ticks > int(_t.pressure_warn):
		_hurt(float(rules.hazards.pressure.drain_per_s) * DT, "pressure")


## The hazard warnings live now, for the HUD: {"pressure": 0..1 of the warning run (1 = draining), "lancer":
## its state, "drifter": 0..1 of its warning}.
func warnings() -> Dictionary:
	return {"pressure": minf(1.0, float(pressure_ticks) / float(_t.pressure_warn)) if pressure_ticks > 0 else 0.0,
			"lancer": String(lancer.state),
			"drifter": minf(1.0, float(drifter.warn_ticks) / float(_t.drifter_warn)) if int(drifter.warn_ticks) > 0 else 0.0}


func _hurt(amount: float, cause: String) -> void:
	player.health = float(player.health) - amount
	last_cause = cause


func _die() -> void:
	deaths += 1
	_emit("died", {"cause": last_cause})
	var s: Dictionary = player.stats
	player.pos = nest_pos() + Vector3(0.0, 0.5, -3.0)
	player.speed = 0.0
	player.vy = 0.0
	player.health = float(s.max_health)
	player.energy = float(s.energy_capacity) * float(rules.world.death.energy_share)
	pressure_ticks = 0
	drifter.warn_ticks = 0
	if String(lancer.state) != "patrol":
		_disengage("died")


# --- the player's actions ----------------------------------------------------------------------------------------

func _actions(intent: Intent) -> void:
	if intent.bite and tick >= _bite_ready_at:
		_bite_ready_at = tick + BITE_COOLDOWN
		_bite()
	if intent.signal_call:
		_signal()
	if intent.interact:
		_interact()


func _bite() -> void:
	var s: Dictionary = player.stats
	var fwd := forward_of(player.heading)
	var reach := float(s.radius) + 1.8
	var best := {}
	var best_d := INF
	for a in animals:
		if not a.alive:
			continue
		var to: Vector3 = a.pos - player.pos
		if to.length() <= reach and to.length() < best_d and (to.length() < 0.5 or fwd.dot(to.normalized()) > 0.3):
			best = a
			best_d = to.length()
	if best.is_empty():
		_emit("bite_missed")
		return
	var rel: Dictionary = relations[best.species]
	if best.species == "grazer" and rel.standing != "foe":
		rel.standing = "foe"
		rel.rapport = 0
		_emit("relation", {"species": "grazer", "standing": "foe"})
	if float(s.bite) <= 0.0:
		_emit("bite_weak", {"species": best.species})
		return
	best.hp = float(best.hp) - float(s.bite)
	_emit("bit", {"id": best.id, "species": best.species})
	if float(best.hp) <= 0.0:
		best.alive = false
		best.respawn_at = tick + int(_t.regrow_fish)
		_emit("killed", {"id": best.id, "species": best.species})
		if s.eats_meat:
			_gain_meal(float(rules.world.food.fish.energy), "fish")


func _signal() -> void:
	var cfg: Dictionary = rules.species.grazer
	var rel: Dictionary = relations.grazer
	var near := false
	for a in animals:
		if a.alive and a.species == "grazer" and a.pos.distance_to(player.pos) <= float(cfg.signal_reach):
			near = true
			break
	if not near:
		_emit("signal_unheard")
		return
	if rel.standing != "neutral":
		_emit("signal_answered", {"species": "grazer", "standing": rel.standing})
		return
	if tick - int(rel.last_signal) < int(_t.signal_gap):
		_emit("signal_too_fast")
		return
	rel.last_signal = tick
	rel.rapport = int(rel.rapport) + 1
	_emit("signal_answered", {"species": "grazer", "rapport": rel.rapport, "needed": int(cfg.signals_to_friend)})
	if int(rel.rapport) >= int(cfg.signals_to_friend):
		rel.standing = "friend"
		points += int(rules.world.points.friend)
		_emit("relation", {"species": "grazer", "standing": "friend", "points": int(rules.world.points.friend)})


## Mating (plan section 6): with energy above the mark and the kin in reach, a press opens the editor.
func can_mate() -> bool:
	return float(player.energy) >= float(player.stats.energy_capacity) * float(rules.world.mating.energy_share)


func _interact() -> void:
	if player.pos.distance_to(kin.pos) > float(rules.world.mating.reach):
		return
	if can_mate():
		_emit("mate")
	else:
		_emit("mate_not_ready", {"needed": float(player.stats.energy_capacity) * float(rules.world.mating.energy_share)})


## The editor committed a new body: the next generation swims from here, the parent is recorded, mating costs
## energy. `cost` points are spent. Returns false (nothing changes) when the body is not legal or too costly.
func apply_offspring(body: Dictionary, cost: int) -> bool:
	if not AquaticBody.validate(body, rules.body).is_empty() or cost > points or cost < 0:
		return false
	history.append({"generation": int(player.generation), "body": (player.body as Dictionary).duplicate()})
	points -= cost
	var s := AquaticBody.stats(body, rules.body)
	player.body = body.duplicate()
	player.stats = s
	player.generation = int(player.generation) + 1
	player.health = float(s.max_health)
	player.energy = float(s.energy_capacity) * float(rules.world.mating.energy_after_share)
	_emit("generation", {"generation": int(player.generation)})
	return true


## A plain snapshot (vectors as [x, y, z]) for tests and the determinism check.
func snapshot() -> Dictionary:
	var a_out := []
	for a in animals:
		a_out.append([a.id, _arr(a.pos), a.alive, a.state])
	var f_out := []
	for f in food:
		f_out.append([f.id, f.alive])
	return {"tick": tick, "player": [_arr(player.pos), player.heading, player.speed, player.energy, player.health],
			"animals": a_out, "food": f_out, "lancer": [_arr(lancer.pos), lancer.state], "drifter": _arr(drifter.pos),
			"points": points, "relations": relations.duplicate(true), "discovered": Array(discovered)}


## The save's aquatic block (schema v5, SaveGame header): what a lineage keeps between sessions. The points are the
## save's adaptation_points, so they are not in here; the world itself (food, animals, hazards) comes back from the
## seed.
func to_save() -> Dictionary:
	var rel := {}
	for species in relations:
		rel[species] = {"standing": String(relations[species].standing), "rapport": int(relations[species].rapport)}
	return {"body": (player.body as Dictionary).duplicate(), "generation": int(player.generation),
			"history": history.duplicate(true), "discovered": Array(discovered), "relations": rel, "meals": meals,
			"position": _arr(player.pos), "heading": float(player.heading), "energy": float(player.energy),
			"health": float(player.health)}


## Takes back a saved block (already validated by the save): the body, generation, history, finds, relations and
## meals, and the fish where it was, kept inside the water and its bars inside the body's limits. A fish saved with
## no health left starts again at the nest, as a death would.
func restore(saved: Dictionary) -> void:
	_place_player(saved.body, int(saved.generation))
	history = (saved.history as Array).duplicate(true)
	discovered = PackedStringArray(saved.discovered)
	meals = int(saved.meals)
	for species in saved.relations:
		if relations.has(species):
			relations[species].standing = String(saved.relations[species].standing)
			relations[species].rapport = int(saved.relations[species].rapport)
	var s: Dictionary = player.stats
	if float(saved.health) > 0.0:
		player.pos = _clamp_to_water(_v(saved.position))
		player.heading = float(saved.heading)
		player.health = minf(float(saved.health), float(s.max_health))
	player.energy = clampf(float(saved.energy), 0.0, float(s.energy_capacity))


static func _arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func state_hash() -> int:
	return hash(JSON.stringify(snapshot(), "", true, true))
