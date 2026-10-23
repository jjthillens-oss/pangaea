class_name CreatureWorldSim
extends RefCounted
## The creature stage's test field (PROPOSED, creature-stage-plan.md section 5): the player's creature, six rivals,
## fruit bushes and meat on a flat square field with the nest at its centre, advanced in fixed 60 Hz ticks by tick().
## Deterministic for a world seed and the intents given, like PoolSim: every duration is a whole tick (converted
## once at load from the tuning's seconds), every sort breaks ties by id, every draw comes from one
## RandomNumberGenerator seeded from the world seed, and snapshot() is plain data in a fixed order. Scenes draw its
## state and react to its events; they never pass it a frame delta.
##
## Each legged creature moves on its own gait planner (domain/creature/gait_planner.gd): the sim steers the planner
## with a throttle and turn from CreatureWorldRules.steer and the planner integrates position and yaw inside its
## envelope. The scene's WalkerRig reads that same planner (planner_of) for the feet; the sim never reads the scene.
## A body without legs cannot walk: the player stays at the nest (has_legs false) with evolve still available.
##
## Tick order (tests depend on it):
##  1. the bodies' positions are noted once, before anything moves;
##  2. the player steers and moves (clamped to the field's walls);
##  3. each rival in id order: percepts from the note (nearest food and creature in sight, fullness, the nest), the
##     brain's decision (domain/creature/creature_rival_brain.gd, percepts only), steer, move, clamp;
##  4. contacts: overlapping bodies are pushed apart once, in id order, positions only;
##  5. condition: health regenerates, rivals get hungrier;
##  6. eating: the player, then each rival; fruit by touch (half points without a mouth), meat needs a mouth;
##  7. bites: the player's, then each rival's, each on the nearest target in reach and in the bite cone, with a
##     cooldown; every body alive at the start of this step may bite, so a mutual kill kills both;
##  8. deaths: the player first (back at the nest, full health, the points loss, meat where it fell), then rivals in
##     id order (meat, gone until their respawn tick, at a drawn spot);
##  9. respawns, fruit regrowth and meat decay;
## 10. evolve: on the rising edge of the intent, at the nest an "evolve" event, elsewhere a "refused" one;
## 11. the tick count.
##
## tick() returns the tick's events, each {kind, ...}: "ate" {who, food, points, position}, "bit" {by, target,
## damage}, "hit" {target, by, damage} (the two sides of one landed bite), "died" {who, cause, by, position, points}
## (the player's also carries points_lost), "evolve" {points}, "refused" {reason}.

const TICKS_PER_SECOND := 60
const DT := 1.0 / 60.0
const PLAYER_ID := "player"
## Ground radius of a fruit bush and of a piece of meat, m (the scene draws them at this size too).
const FRUIT_RADIUS_M := 0.5
const MEAT_RADIUS_M := 0.3
## Rivals come back this long after they die (PROPOSED).
const RIVAL_RESPAWN_S := 15.0
## A rival goes from full to starving in this long (PROPOSED).
const RIVAL_EMPTY_S := 150.0
const FRUIT_FULLNESS := 0.25
const MEAT_FULLNESS := 0.5
const FIELD_MARGIN_M := 2.0
const WORLD_SEED_STRIDE := 1000003
const FIELD_SEED_OFFSET := 7

const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const GaitBody := preload("res://game/domain/creature/gait_body.gd")
const BodyMechanics := preload("res://game/domain/creature/body_mechanics.gd")
const GaitPlanner := preload("res://game/domain/creature/gait_planner.gd")
const Rules := preload("res://game/domain/creature/creature_world_rules.gd")
const Brain := preload("res://game/domain/creature/creature_rival_brain.gd")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")

var tick_count := 0
var points := 0
var world_seed := 0
var tuning: Dictionary
var data: Dictionary
var rng := RandomNumberGenerator.new()
var half_size := 80.0
var nest_radius := 6.0
var nest := Vector3.ZERO
## Whole-tick durations from the tuning's seconds.
var ticks := {}
## The player's creature (`me`: see _make_creature). Its planner is null when the body has no legs.
var me: Dictionary
## Rivals in id order ("r1".."rN"), each a creature dictionary with a brain memory.
var rivals: Array = []
## {id, position, ripe, regrow_at}
var fruit: Array = []
## {id, position, points, decay_at}
var meat: Array = []
var _next_meat := 1
var _evolve_held := false
var _bite_held := false
var _last_notice := ""


## `data` is load_data(): the body rules, the part rules, the editor costs, the gait table and the starter bodies.
## An empty dictionary loads it from the data files (a convenience for tests; the scene passes its own).
func _init(body_dict: Dictionary, p_world_seed: int, p_tuning: Dictionary, p_data: Dictionary = {}) -> void:
	world_seed = p_world_seed
	tuning = p_tuning
	data = p_data if not p_data.is_empty() else load_data()
	rng.seed = world_seed * WORLD_SEED_STRIDE + FIELD_SEED_OFFSET
	half_size = float(tuning["field_half_size_m"])
	nest_radius = float(tuning["nest_radius_m"])
	points = int(tuning["start_points"])
	ticks = {
		"fruit_regrow": Rules.to_ticks(float(tuning["fruit"]["regrow_s"]), TICKS_PER_SECOND),
		"meat_decay": Rules.to_ticks(float(tuning["meat"]["decay_s"]), TICKS_PER_SECOND),
		"bite_cooldown": Rules.to_ticks(float(tuning["bite"]["cooldown_s"]), TICKS_PER_SECOND),
		"rival_respawn": Rules.to_ticks(RIVAL_RESPAWN_S, TICKS_PER_SECOND),
	}
	me = _make_creature(PLAYER_ID, BodyCodec.from_dict(body_dict), nest, 0.0)
	var fruit_spots: Array = Rules.scatter(rng, int(tuning["fruit"]["count"]), half_size, nest_radius, FIELD_MARGIN_M)
	for i in fruit_spots.size():
		fruit.append({"id": "f%d" % (i + 1), "position": fruit_spots[i], "ripe": true, "regrow_at": 0})
	var count := int(tuning["rivals"]["count"])
	var starters: Dictionary = data["starter_bodies"]
	var names: Array = Rules.pick_rival_starters(starters, count, rng)
	var spots: Array = Rules.scatter(rng, names.size(), half_size * 0.5, nest_radius, FIELD_MARGIN_M)
	for i in names.size():
		var body = Rules.draw_rival_body(BodyCodec.from_dict(starters[names[i]]), rng, data["body_rules"],
				data["part_rules"], data["editor_costs"])
		var yaw := rng.randf_range(-PI, PI)
		var rival := _make_creature("r%d" % (i + 1), body, spots[i], yaw)
		rival["starter"] = names[i]
		rival["fullness"] = rng.randf_range(0.3, 1.0)
		rival["memory"] = Brain.fresh_memory(Rules.forward(yaw))
		rivals.append(rival)


## The data every sim needs, from the data files and the art records (CreatureData reads them; the sim itself only
## takes dictionaries). Starter bodies are codec dictionaries by name.
static func load_data() -> Dictionary:
	var starters := {}
	var bodies: Dictionary = CreatureData.read_json(CreatureData.DATA_DIR + "/starter_bodies.json")["bodies"]
	for n in bodies:
		starters[String(n)] = bodies[n]
	return {"body_rules": CreatureData.rules(), "part_rules": CreatureData.part_rules(),
			"editor_costs": CreatureData.editor_costs(), "gait_table": CreatureData.gait_table(),
			"starter_bodies": starters}


static func load_tuning() -> Dictionary:
	return CreatureData.read_json(CreatureData.DATA_DIR + "/creature_stage.json")


func _make_creature(id: String, body: RefCounted, at: Vector3, yaw: float) -> Dictionary:
	var stats: Dictionary = CreatureStats.of(body, data["part_rules"], data["gait_table"], tuning)
	var c := {"id": id, "body": body, "stats": stats, "planner": null, "mech": null, "gait": GaitBody.from_description(body),
			"position": at, "yaw": yaw, "health": float(stats["max_health"]), "cooldown": 0, "alive": true,
			"respawn_at": 0, "fullness": 1.0, "memory": {}, "mode": "", "starter": ""}
	if stats["has_legs"]:
		c["mech"] = BodyMechanics.create(id, c["gait"]["body"], data["gait_table"])
		c["planner"] = GaitPlanner.create(c["mech"], at, yaw)
	return c


## Advances one tick. intent: {move: Vector2 (a ground direction, x along +X and y along +Z, length 0..1 as the
## throttle), bite: bool, evolve: bool}. Returns the tick's events.
func tick(intent: Dictionary) -> Array:
	var events := []
	var move: Vector2 = intent.get("move", Vector2.ZERO)
	# 1. Positions before anything moves.
	var noted := {}
	for c in _creatures():
		noted[c["id"]] = {"position": c["position"], "mass": float(c["stats"]["mass_kg"]), "alive": c["alive"]}
	# 2. The player.
	if move.length() > 1.0:
		move = move.normalized()
	_drive(me, Rules.steer(me["yaw"], move, move.length()))
	# 3. Rivals.
	for r in rivals:
		if not r["alive"]:
			continue
		var decision: Dictionary = Brain.decide(_percepts(r, noted), r["memory"], tuning["rivals"])
		r["mode"] = decision["mode"]
		r["wants_bite"] = decision["bite"]
		_drive(r, Rules.steer(r["yaw"], decision["heading"], float(decision["throttle"])))
	# 4. Contacts.
	var bodies := _alive_creatures()
	for i in bodies.size():
		for j in range(i + 1, bodies.size()):
			var a: Dictionary = bodies[i]
			var b: Dictionary = bodies[j]
			var push: Array = Rules.separate(a["position"], float(a["stats"]["body_radius_m"]), float(a["stats"]["mass_kg"]),
					b["position"], float(b["stats"]["body_radius_m"]), float(b["stats"]["mass_kg"]))
			if push[0] != Vector3.ZERO or push[1] != Vector3.ZERO:
				_place(a, a["position"] + push[0])
				_place(b, b["position"] + push[1])
	# 5. Condition.
	var regen := float(tuning["health"]["regen_per_s"]) * DT
	for c in bodies:
		c["health"] = minf(float(c["stats"]["max_health"]), c["health"] + regen)
		if c["cooldown"] > 0:
			c["cooldown"] -= 1
	for r in rivals:
		if r["alive"]:
			r["fullness"] = maxf(0.0, r["fullness"] - DT / RIVAL_EMPTY_S)
	# 6. Eating.
	for c in bodies:
		_eat(c, events)
	# 7. Bites.
	var biters := bodies.duplicate()
	var bite := bool(intent.get("bite", false))
	if bite:
		if me["stats"]["has_mouth"]:
			_bite(me, biters, events)
		elif not _bite_held:
			events.append({"kind": "refused", "reason": "No mouth to bite with"})
	_bite_held = bite
	for r in rivals:
		if r["alive"] and r.get("wants_bite", false):
			_bite(r, biters, events)
	# 8. Deaths.
	if me["alive"] and me["health"] <= 0.0:
		var lost := points - Rules.points_after_death(points, float(tuning["death"]["points_loss_share"]))
		points -= lost
		_drop_meat(me["position"])
		events.append({"kind": "died", "who": PLAYER_ID, "cause": "killed by %s" % _killer_name(me.get("last_hit_by", "")),
				"by": me.get("last_hit_by", ""), "position": me["position"], "points": points, "points_lost": lost})
		_respawn(me, nest, 0.0)
	for r in rivals:
		if r["alive"] and r["health"] <= 0.0:
			r["alive"] = false
			r["respawn_at"] = tick_count + int(ticks["rival_respawn"])
			_drop_meat(r["position"])
			events.append({"kind": "died", "who": r["id"], "cause": "killed by %s" % _killer_name(r.get("last_hit_by", "")),
					"by": r.get("last_hit_by", ""), "position": r["position"], "points": 0})
	# 9. Respawns, regrowth, decay.
	for r in rivals:
		if not r["alive"] and tick_count >= int(r["respawn_at"]):
			var spot: Array = Rules.scatter(rng, 1, half_size * 0.8, nest_radius, FIELD_MARGIN_M)
			r["alive"] = true
			r["fullness"] = 0.6
			_respawn(r, spot[0] if not spot.is_empty() else Vector3(half_size * 0.5, 0.0, 0.0), rng.randf_range(-PI, PI))
			r["memory"] = Brain.fresh_memory(Rules.forward(r["yaw"]))
	for f in fruit:
		if not f["ripe"] and tick_count >= int(f["regrow_at"]):
			f["ripe"] = true
	var kept := []
	for m in meat:
		if tick_count < int(m["decay_at"]):
			kept.append(m)
	meat = kept
	# 10. Evolve.
	var evolve := bool(intent.get("evolve", false))
	if evolve and not _evolve_held:
		var verdict: Dictionary = Rules.can_evolve(at_nest())
		if verdict["ok"]:
			events.append({"kind": "evolve", "points": points})
		else:
			events.append({"kind": "refused", "reason": verdict["reason"]})
	_evolve_held = evolve
	# 11.
	tick_count += 1
	return events


func _drive(c: Dictionary, command: Vector2) -> void:
	var planner = c["planner"]
	if planner == null:
		return
	planner.step(DT, command.x, command.y)
	_place(c, Rules.clamp_to_field(planner.position, half_size, float(c["stats"]["body_radius_m"])))
	c["yaw"] = planner.yaw


func _place(c: Dictionary, p: Vector3) -> void:
	var clamped: Vector3 = Rules.clamp_to_field(p, half_size, float(c["stats"]["body_radius_m"]))
	c["position"] = clamped
	if c["planner"] != null:
		c["planner"].position = clamped


func _respawn(c: Dictionary, at: Vector3, yaw: float) -> void:
	c["health"] = float(c["stats"]["max_health"])
	c["cooldown"] = 0
	c["position"] = at
	c["yaw"] = yaw
	c.erase("last_hit_by")
	if c["mech"] != null:
		c["planner"] = GaitPlanner.create(c["mech"], at, yaw)


func _percepts(r: Dictionary, noted: Dictionary) -> Dictionary:
	var me: Vector3 = r["position"]
	var sight := float(r["stats"]["sight_m"])
	var out := {"fullness": r["fullness"], "heading": Rules.forward(r["yaw"]), "bite_reach": float(r["stats"]["bite_reach_m"])
			if r["stats"]["has_mouth"] else 0.0, "noise": rng.randf_range(-1.0, 1.0)}
	var to_nest := Vector2(nest.x - me.x, nest.z - me.z)
	out["nest"] = {"dir": to_nest.normalized() if to_nest.length() > 1e-6 else Vector2(0.0, -1.0), "dist": to_nest.length()}
	var best := INF
	var food := {}
	for f in fruit:
		if f["ripe"]:
			var d := _ground_distance(me, f["position"])
			if d < best and d <= sight:
				best = d
				food = {"dir": _ground_dir(me, f["position"]), "dist": d}
	if r["stats"]["has_mouth"]:
		for m in meat:
			var d := _ground_distance(me, m["position"])
			if d < best and d <= sight:
				best = d
				food = {"dir": _ground_dir(me, m["position"]), "dist": d}
	out["food"] = food
	best = INF
	var creature := {}
	for id in _creature_ids():
		if id == r["id"] or not noted[id]["alive"] or _at_nest(noted[id]["position"]):
			continue   # a creature at the nest is not prey
		var d := _ground_distance(me, noted[id]["position"])
		if d < best and d <= sight:
			best = d
			creature = {"dir": _ground_dir(me, noted[id]["position"]), "dist": d,
					"mass_ratio": float(noted[id]["mass"]) / maxf(1e-6, float(r["stats"]["mass_kg"]))}
	out["creature"] = creature
	return out


func _eat(c: Dictionary, events: Array) -> void:
	var reach := float(c["stats"]["bite_reach_m"])
	var is_player: bool = c["id"] == PLAYER_ID
	for f in fruit:
		if f["ripe"] and Rules.touches(c["position"], reach, f["position"], FRUIT_RADIUS_M):
			f["ripe"] = false
			f["regrow_at"] = tick_count + int(ticks["fruit_regrow"])
			var worth := Rules.fruit_points(int(tuning["fruit"]["points"]), c["stats"]["has_mouth"],
					float(tuning["bite"]["no_mouth_fruit_share"]))
			if is_player:
				points += worth
			else:
				c["fullness"] = minf(1.0, c["fullness"] + FRUIT_FULLNESS)
			events.append({"kind": "ate", "who": c["id"], "food": "fruit", "points": worth if is_player else 0,
					"position": f["position"]})
			return
	if not c["stats"]["has_mouth"]:
		return
	for i in meat.size():
		var m: Dictionary = meat[i]
		if Rules.touches(c["position"], reach, m["position"], MEAT_RADIUS_M):
			meat.remove_at(i)
			if is_player:
				points += int(m["points"])
			else:
				c["fullness"] = minf(1.0, c["fullness"] + MEAT_FULLNESS)
			events.append({"kind": "ate", "who": c["id"], "food": "meat", "points": int(m["points"]) if is_player else 0,
					"position": m["position"]})
			return


## A bite from `biter` on the nearest body in its cone and reach. Nothing at the nest can be bitten: it is the
## player's safe ground (and the respawn point), so a hungry rival cannot farm a creature that cannot leave it.
func _bite(biter: Dictionary, bodies: Array, events: Array) -> void:
	if not biter["alive"] or biter["cooldown"] > 0 or not biter["stats"]["has_mouth"]:
		return
	var best := INF
	var target := {}
	for c in bodies:
		if c["id"] == biter["id"] or _at_nest(c["position"]):
			continue
		if Rules.bite_lands(biter["position"], biter["yaw"], float(biter["stats"]["bite_reach_m"]), c["position"],
				float(c["stats"]["body_radius_m"])):
			var d := _ground_distance(biter["position"], c["position"])
			if d < best:
				best = d
				target = c
	biter["cooldown"] = int(ticks["bite_cooldown"])
	if target.is_empty():
		return
	var damage := float(biter["stats"]["bite_power"])
	target["health"] -= damage
	target["last_hit_by"] = biter["id"]
	events.append({"kind": "bit", "by": biter["id"], "target": target["id"], "damage": damage})
	events.append({"kind": "hit", "target": target["id"], "by": biter["id"], "damage": damage})


func _drop_meat(at: Vector3) -> void:
	meat.append({"id": "m%d" % _next_meat, "position": at, "points": int(tuning["meat"]["points"]),
			"decay_at": tick_count + int(ticks["meat_decay"])})
	_next_meat += 1


func _creatures() -> Array:
	var out := [me]
	out.append_array(rivals)
	return out


func _creature_ids() -> Array:
	var out := [PLAYER_ID]
	for r in rivals:
		out.append(r["id"])
	return out


func _alive_creatures() -> Array:
	var out := []
	for c in _creatures():
		if c["alive"]:
			out.append(c)
	return out


static func _ground_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


static func _ground_dir(a: Vector3, b: Vector3) -> Vector2:
	var d := Vector2(b.x - a.x, b.z - a.z)
	return d.normalized() if d.length() > 1e-6 else Vector2(0.0, -1.0)


## The player as the scene and HUD read it.
func player() -> Dictionary:
	var s: Dictionary = me["stats"]
	return {"position": me["position"], "yaw": me["yaw"], "health": me["health"],
			"max_health": float(s["max_health"]), "speed_mps": float(s["speed_mps"]), "has_legs": s["has_legs"],
			"has_mouth": s["has_mouth"], "bite_power": float(s["bite_power"]), "bite_reach_m": float(s["bite_reach_m"]),
			"sight_m": float(s["sight_m"]), "mass_kg": float(s["mass_kg"]), "cooldown": me["cooldown"],
			"body_length_m": float(s["body_length_m"]), "at_nest": at_nest()}


func at_nest() -> bool:
	return _at_nest(me["position"])


func _at_nest(at: Vector3) -> bool:
	return _ground_distance(at, nest) <= nest_radius


## "a hexapod" for a rival id, "you" for the player, "a rival" for anything else: what a death notice reads.
func _killer_name(id: String) -> String:
	if id == PLAYER_ID:
		return "you"
	var c := _creature(id)
	if c.is_empty() or String(c["starter"]).is_empty():
		return "a rival"
	return "a %s" % String(c["starter"]).trim_prefix("s1_").replace("_", " ")


## The gait planner of a creature (the player's with PLAYER_ID), for the scene's walker rigs; null without legs.
func planner_of(id: String) -> RefCounted:
	var c := _creature(id)
	return c["planner"] if not c.is_empty() else null


func body_of(id: String) -> RefCounted:
	var c := _creature(id)
	return c["body"] if not c.is_empty() else null


func gait_of(id: String) -> Dictionary:
	var c := _creature(id)
	return c["gait"] if not c.is_empty() else {}


func _creature(id: String) -> Dictionary:
	if id == PLAYER_ID:
		return me
	for r in rivals:
		if r["id"] == id:
			return r
	return {}


## Plain data in a fixed order: vectors as [x, y, z] arrays, lists in id order.
func snapshot() -> Dictionary:
	var out := {"tick": tick_count, "points": points, "player": _creature_snapshot(me), "rivals": [], "fruit": [],
			"meat": []}
	for r in rivals:
		out["rivals"].append(_creature_snapshot(r))
	for f in fruit:
		out["fruit"].append({"id": f["id"], "position": _arr(f["position"]), "ripe": f["ripe"]})
	for m in meat:
		out["meat"].append({"id": m["id"], "position": _arr(m["position"]), "points": m["points"]})
	return out


func _creature_snapshot(c: Dictionary) -> Dictionary:
	return {"id": c["id"], "position": _arr(c["position"]), "yaw": c["yaw"], "health": c["health"],
			"max_health": float(c["stats"]["max_health"]), "alive": c["alive"], "mode": c["mode"],
			"fullness": c["fullness"], "starter": c["starter"]}


static func _arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]
