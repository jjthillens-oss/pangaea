class_name SocialSim
extends RefCounted
## The Social stage preview slice's world (PROPOSED, docs/stages/social-plan.md sections 4 to 10 and 14): the
## player's creature, a band of three, a wary loner and a hunter on an 80 m field with the player's nest at the
## centre, the band's den, the loner's perch, the hunter's lair and a grove of fruit bushes, advanced in fixed 60 Hz
## ticks by tick(). Deterministic for a world seed and the intents given, like CreatureWorldSim: every duration is a
## whole tick (SocialRules.with_ticks converts the tuning once), every loop runs in id order, every random draw comes
## from a RandomNumberGenerator stream seeded from the world seed (separate streams for the cast's places, the names,
## the brains' noise and the grove), and snapshot() is plain data with ground vectors as [x, z] pairs. Scenes draw
## its state and react to its events; they never pass it a frame delta.
##
## The bodies reuse the creature stage's anatomy and movement code read-only (CreatureStats, GaitBody,
## BodyMechanics, GaitPlanner and CreatureWorldRules' steer, clamp and separate). The social rules are the pure ones in
## game/domain/social/: SocialTraits (anatomy to signals and roles), SocialMemory (fading memory, capped reputation),
## SocialRules (the one resolver for signals and orders) and the two brains, which get percepts only.
##
## Tick order (tests depend on it):
##  1. timers: the player's signal and bite cooldowns, the individuals' bite cooldowns;
##  2. the player's intent: dismiss, then the order, then the signal (each a one-tick press);
##  3. the player moves (not while fainted), clamped to the field;
##  4. needs: hunger rises, fear fades and rises with the hunter's closeness;
##  5. brains, the individuals in id order and then the hunter, each on its own cadence (near: every
##     tiers.near_brain_every_ticks, far: every tiers.far_every_ticks, staggered by its place in that order);
##     their reports become events;
##  6. movement: near actors steer their gait planner every tick, far actors are placed directly on their brain tick;
##  7. contacts: overlapping bodies are pushed apart once, in id order, positions only;
##  8. the player's target (the individual its signals go to) is chosen again;
##  9. the tick count.
##
## tick() returns the tick's events, each {kind, ...}: "refused" {action, reason, who} (a signal the player could not
## give: it costs nothing); "response" {who, name, signal, response, words, trust}; "joined" {who, name};
## "befriended" {who, name} (a loner: it stays where it lives); "ack" {who, order, words}; "order_refused" {who,
## order, reason}; "dismissed" {who, name}; "ate" {who, bush}.

const TICKS_PER_SECOND := 60
const DT := 1.0 / 60.0
const PLAYER_ID := "player"
## The streams: world_seed * STRIDE + offset.
const STRIDE := 1000003
const CAST_STREAM := 11
const NAME_STREAM := 23
const NOISE_STREAM := 37
const GROVE_STREAM := 41
## The player's signals go to the best individual within this distance (in front of it first).
const TARGET_M := 15.0
## How long an individual answers a signal with movement (turns to the player, steps closer or back).
const ATTENTION_S := 2.0
## A carried fruit and a bush's fruit, for touch.
const FRUIT_RADIUS_M := 0.5
## How many names are drawn at most to give every individual a different one.
const NAME_TRIES := 8
## How far from a site's edge its residents are first placed.
const SITE_FILL := 0.8
## The brain's answer words for the five responses (CompanionBrain attention.response).
const ATTENTION_WORD := {"fits": "welcomes", "ok": "listens", "unsure": "unsure", "startles": "backs"}
const SITES: Array[String] = ["nest", "den", "perch", "lair"]

const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const GaitBody := preload("res://game/domain/creature/gait_body.gd")
const BodyMechanics := preload("res://game/domain/creature/body_mechanics.gd")
const GaitPlanner := preload("res://game/domain/creature/gait_planner.gd")
const Rules := preload("res://game/domain/creature/creature_world_rules.gd")

var tick_count := 0
var world_seed := 0
## The tuning with whole-tick durations (SocialRules.with_ticks).
var tuning: Dictionary
## SocialData.creature_data(): body rules, part rules, gait table, the creature stage's numbers, the presets.
var data: Dictionary
var half_size := 40.0
## Site name -> {position: Vector2, radius}.
var sites := {}
## The player's creature.
var me: Dictionary
## The individuals (the band and the loner), in id order.
var cast: Array = []
var hunter_c: Dictionary
## The grove's bushes, in id order: {id, position: Vector2, ripe, regrow_at, reserved_by}.
var bushes: Array = []
## Group ("band", "loner") -> reputation (SocialMemory.reputation_after).
var reputation := {}

var _rng_cast := RandomNumberGenerator.new()
var _rng_names := RandomNumberGenerator.new()
var _rng_noise := RandomNumberGenerator.new()
var _rng_grove := RandomNumberGenerator.new()
var _target := ""
var _attention_t := 1


## `player_body` is the codec's body dictionary of the player's creature; `p_tuning` the slice's tuning (raw or
## already with ticks); `p_data` SocialData.creature_data().
func _init(player_body: Dictionary, p_world_seed: int, p_tuning: Dictionary, p_data: Dictionary) -> void:
	world_seed = p_world_seed
	tuning = p_tuning if p_tuning.has("tick_hz") else SocialRules.with_ticks(p_tuning)
	data = p_data
	_rng_cast.seed = world_seed * STRIDE + CAST_STREAM
	_rng_names.seed = world_seed * STRIDE + NAME_STREAM
	_rng_noise.seed = world_seed * STRIDE + NOISE_STREAM
	_rng_grove.seed = world_seed * STRIDE + GROVE_STREAM
	_attention_t = SocialRules.to_ticks(ATTENTION_S, int(tuning["tick_hz"]))
	half_size = float(tuning["field_half_size_m"])
	for site in SITES:
		sites[site] = {"position": _v2(tuning[site]["position"]), "radius": float(tuning[site]["radius_m"])}
	me = _make(PLAYER_ID, BodyCodec.from_dict(player_body), _v2(tuning["player"]["start"]), 0.0)
	me.merge({"fainted": false, "faint_until": 0, "carrying": 0, "cooldown_t": 0, "bite_cooldown": 0}, true)
	var specs: Array = (tuning["cast"] as Array).duplicate()
	specs.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	var taken := {}
	for spec in specs:
		var home: Dictionary = sites[String(spec["home"])]
		var at := _spot_in(_rng_cast, home["position"], float(home["radius"]) * SITE_FILL)
		var yaw := _rng_cast.randf_range(-PI, PI)
		var c := _make(String(spec["id"]), BodyCodec.from_dict(data["presets"][String(spec["preset"])]), at, yaw)
		c.merge({"name": _unique_name(taken), "preset": String(spec["preset"]), "disposition": String(spec["disposition"]),
				"group": String(spec["group"]), "home": String(spec["home"]), "hunger": float(spec["hunger"]), "fear": 0.0,
				"memory": [], "hostile_until": 0, "member": false, "befriended": false, "order": {}, "carrying": 0,
				"reserved": "", "pick_left": -1, "learned": {}, "attention": {}, "role": String(c["traits"]["role"]),
				"brain": CompanionBrain.fresh_memory(Rules.forward(yaw))}, true)
		taken[c["name"]] = true
		cast.append(c)
		if not reputation.has(c["group"]):
			reputation[c["group"]] = 0.0
	var h: Dictionary = tuning["hunter"]
	hunter_c = _make(String(h["id"]), BodyCodec.from_dict(data["presets"][String(h["preset"])]),
			sites["lair"]["position"], _rng_cast.randf_range(-PI, PI))
	hunter_c.merge({"preset": String(h["preset"]), "nerve": int(h["nerve"]), "waypoint": 0,
			"brain": HunterBrain.fresh_memory(Rules.forward(hunter_c["yaw"]))}, true)
	var grove: Dictionary = tuning["grove"]
	var spots := _grove_spots(_rng_grove, _v2(grove["centre"]), float(grove["radius_m"]), int(grove["count"]),
			float(grove["min_spacing_m"]))
	for i in spots.size():
		bushes.append({"id": "g%d" % (i + 1), "position": spots[i], "ripe": true, "regrow_at": 0, "reserved_by": ""})
	_target = _pick_target()


func _make(id: String, body: RefCounted, at: Vector2, yaw: float) -> Dictionary:
	var stats: Dictionary = CreatureStats.of(body, data["part_rules"], data["gait_table"], data["creature_tuning"])
	var traits := SocialTraits.of(body, stats, data["part_rules"], tuning)
	var pos := Vector3(at.x, 0.0, at.y)
	var c := {"id": id, "body": body, "stats": stats, "traits": traits, "gait": GaitBody.from_description(body),
			"mech": null, "planner": null, "position": pos, "yaw": yaw, "health": float(stats["max_health"]),
			"tier": "near", "heading": Rules.forward(yaw), "throttle": 0.0, "state": "idle", "last_brain": 0,
			"bite_cooldown": 0, "wants_bite": false}
	if stats["has_legs"]:
		c["mech"] = BodyMechanics.create(id, c["gait"]["body"], data["gait_table"])
		c["planner"] = GaitPlanner.create(c["mech"], pos, yaw)
	return c


## A name no one else has yet (at most NAME_TRIES draws; the last draw stands if they all clash).
func _unique_name(taken: Dictionary) -> String:
	var names: Dictionary = tuning["names"]
	var out := ""
	for i in NAME_TRIES:
		out = SocialRules.make_name(_rng_names, names["syllables"], names["parts"])
		if not taken.has(out):
			break
	return out


## A point inside the circle (centre, radius), uniform over its area.
static func _spot_in(rng: RandomNumberGenerator, centre: Vector2, radius: float) -> Vector2:
	var angle := rng.randf_range(-PI, PI)
	var r := radius * sqrt(rng.randf())
	return centre + Vector2(cos(angle), sin(angle)) * r


## `count` points inside the grove, at least `spacing` apart where a bounded number of draws allows it.
static func _grove_spots(rng: RandomNumberGenerator, centre: Vector2, radius: float, count: int, spacing: float) -> Array:
	var out := []
	var tries := 0
	while out.size() < count and tries < count * 40:
		tries += 1
		var p := _spot_in(rng, centre, radius)
		var clear := true
		for q in out:
			if (q as Vector2).distance_to(p) < spacing:
				clear = false
				break
		if clear:
			out.append(p)
	while out.size() < count:
		out.append(_spot_in(rng, centre, radius))
	return out


# --- The tick. ------------------------------------------------------------------------------------------------------

## Advances one tick. intent: {move: Vector2 (a ground direction, x along +X and y along +Z, length 0..1 as the
## throttle), signal: String (one of SocialRules.SIGNALS, on the tick it was pressed), order: String (one of
## SocialRules.ORDERS, on the tick it was given), dismiss: String (an individual's id), bite: bool (held)}.
## Returns the tick's events.
func tick(intent: Dictionary) -> Array:
	var events := []
	# 1. Timers.
	me["cooldown_t"] = maxi(0, int(me["cooldown_t"]) - 1)
	me["bite_cooldown"] = maxi(0, int(me["bite_cooldown"]) - 1)
	for c in cast:
		c["bite_cooldown"] = maxi(0, int(c["bite_cooldown"]) - 1)
	# 2. The player's intent.
	var dismiss := String(intent.get("dismiss", ""))
	if dismiss != "":
		_dismiss(dismiss, events)
	var sig := String(intent.get("signal", ""))
	if sig != "":
		_signal(sig, events)
	# 3. The player moves.
	var move: Vector2 = intent.get("move", Vector2.ZERO)
	if move.length() > 1.0:
		move = move.normalized()
	if not me["fainted"]:
		_drive(me, Rules.steer(me["yaw"], move, move.length()))
	# 4. Needs.
	_update_needs()
	# 5. Brains.
	var actors := _actors()
	var moved := {}
	for i in actors.size():
		var c: Dictionary = actors[i]
		var every := int(tuning["tiers"]["far_every_ticks"]) if c["tier"] == "far" \
				else int(tuning["tiers"]["near_brain_every_ticks"])
		if (tick_count + i) % maxi(1, every) != 0:
			continue
		var elapsed := maxi(1, tick_count - int(c["last_brain"])) if tick_count > 0 else 1
		c["last_brain"] = tick_count
		if c["id"] == hunter_c["id"]:
			continue
		_think(c, elapsed, events)
		if c["tier"] == "far":
			_jump(c, elapsed)
			moved[c["id"]] = true
	# 6. Movement (near actors).
	for c in actors:
		if c["tier"] == "near" and not moved.has(c["id"]):
			_drive(c, Rules.steer(c["yaw"], c["heading"], float(c["throttle"])))
	# 7. Contacts.
	_separate()
	# 8. The target.
	_target = _pick_target()
	# 9.
	tick_count += 1
	return events


## The individuals and then the hunter: the actors with brains, in the order their brains run.
func _actors() -> Array:
	var out := cast.duplicate()
	out.append(hunter_c)
	return out


## Every body: the player, the individuals, the hunter (contacts run in this order).
func _bodies() -> Array:
	var out := [me]
	out.append_array(cast)
	out.append(hunter_c)
	return out


func _update_needs() -> void:
	var needs: Dictionary = tuning["needs"]
	var rise := 1.0 / float(maxi(1, int(needs["hunger_full_t"])))
	var fade := 1.0 / float(maxi(1, int(needs["fear_decay_t"])))
	var costs: Dictionary = tuning["roles"]["costs"]
	for c in cast:
		var mult := float((costs.get(c["role"], {}) as Dictionary).get("hunger_mult", 1.0))
		c["hunger"] = minf(1.0, float(c["hunger"]) + rise * mult)
		c["fear"] = maxf(0.0, float(c["fear"]) - fade)
		var sight := float(c["traits"]["sight_m"])
		var dist := _dist(c, hunter_c)
		if sight > 0.0 and dist <= sight:
			c["fear"] = maxf(float(c["fear"]), 1.0 - dist / sight)


## One decision of an individual's brain, from its percepts.
func _think(c: Dictionary, elapsed: int, events: Array) -> void:
	var d := CompanionBrain.decide(_percepts(c, elapsed), c["brain"], tuning)
	c["heading"] = d["heading"]
	c["throttle"] = float(d["throttle"]) * _speed_mult(c)
	c["state"] = d["state"]
	c["wants_bite"] = bool(d["bite"])
	var report: Dictionary = d["report"]
	if not report.is_empty():
		_on_report(c, report, events)


func _on_report(_c: Dictionary, _report: Dictionary, _events: Array) -> void:
	pass


func _speed_mult(c: Dictionary) -> float:
	if not c.has("role") or not c["member"]:
		return 1.0
	return float(((tuning["roles"]["costs"] as Dictionary).get(c["role"], {}) as Dictionary).get("speed_mult", 1.0))


## What an individual senses (CompanionBrain's percepts): directions and distances, never ids or positions.
func _percepts(c: Dictionary, elapsed: int) -> Dictionary:
	var at := _g(c)
	var p := {"carrying": int(c["carrying"]), "fear": float(c["fear"]), "hunger": float(c["hunger"]), "role": c["role"],
			"disposition": c["disposition"], "heading": Rules.forward(c["yaw"]),
			"bite_reach": float(c["stats"]["bite_reach_m"]) + float(hunter_c["stats"]["body_radius_m"]),
			"noise": _rng_noise.randf_range(-1.0, 1.0), "elapsed_t": elapsed,
			"room": int(c["traits"]["carry_count"]) - int(c["carrying"])}
	var home: Dictionary = sites["nest"] if c["member"] else sites[c["home"]]
	p["home"] = _seen_site(at, home)
	p["nest"] = _seen_site(at, sites["nest"])
	if c["member"] and not me["fainted"]:
		p["leader"] = _seen(at, _g(me))
	var order: Dictionary = c["order"]
	if not order.is_empty():
		var o := {"name": order["name"], "mode": String(order.get("mode", "")), "ticks_left": _ticks_left(order)}
		if order.has("spot"):
			var s := _seen(at, order["spot"])
			o["target_dir"] = s["dir"]
			o["target_dist"] = s["dist"]
		p["order"] = o
	if _sees(c, hunter_c):
		p["threat"] = _seen(at, _g(hunter_c))
	var food := _food_for(c)
	if not food.is_empty():
		p["food"] = food
	var attention: Dictionary = c["attention"]
	if not attention.is_empty() and tick_count < int(attention["until"]) and not me["fainted"]:
		var a := _seen(at, _g(me))
		a["response"] = attention["response"]
		p["attention"] = a
	if not c["member"] and not me["fainted"] and _dist(c, me) <= float(c["traits"]["sight_m"]):
		p["visitor"] = _seen(at, _g(me))
	return p


func _ticks_left(order: Dictionary) -> int:
	if int(order.get("until", -1)) < 0:
		return -1
	return maxi(0, int(order["until"]) - tick_count)


## The bush an individual walks to: a hungry individual without an order eats at the nearest ripe, free bush it can
## see; it reserves the bush first, so no two go for the same one. {} when it wants none (and its reservation goes).
func _food_for(c: Dictionary) -> Dictionary:
	var wants: bool = not c["member"] and c["order"].is_empty() \
			and float(c["hunger"]) >= float(tuning["fit"]["hungry_at"])
	if not wants:
		_release(c)
		return {}
	var at := _g(c)
	var held := _bush(String(c["reserved"]))
	if held.is_empty() or not held["ripe"]:
		_release(c)
		var best := {}
		var best_d := float(c["traits"]["sight_m"])
		for b in bushes:
			if b["ripe"] and String(b["reserved_by"]) == "":
				var dist := at.distance_to(b["position"])
				if dist <= best_d:
					best = b
					best_d = dist
		if best.is_empty():
			return {}
		best["reserved_by"] = c["id"]
		c["reserved"] = best["id"]
		held = best
	var out := _seen(at, held["position"])
	out["reserved_ok"] = true
	return out


## Gives up an individual's bush reservation and any picking in progress.
func _release(c: Dictionary) -> void:
	var b := _bush(String(c.get("reserved", "")))
	if not b.is_empty() and b["reserved_by"] == c["id"]:
		b["reserved_by"] = ""
	c["reserved"] = ""
	c["pick_left"] = -1


## A far actor's movement for `elapsed` ticks at once, placed directly (the planner's body follows).
func _jump(c: Dictionary, elapsed: int) -> void:
	var heading: Vector2 = c["heading"]
	var speed := float(c["stats"]["speed_mps"]) * float(c["stats"].get("speed_factor", 1.0))
	var step := heading * clampf(float(c["throttle"]), 0.0, 1.0) * speed * DT * elapsed
	if heading.length_squared() > 0.0:
		c["yaw"] = atan2(-heading.x, -heading.y)
	_place(c, c["position"] + Vector3(step.x, 0.0, step.y))
	if c["planner"] != null:
		c["planner"].yaw = c["yaw"]


func _drive(c: Dictionary, command: Vector2) -> void:
	var planner = c["planner"]
	if planner == null:
		return
	planner.step(DT, command.x * float(c["stats"].get("speed_factor", 1.0)), command.y)
	_place(c, planner.position)
	c["yaw"] = planner.yaw


func _place(c: Dictionary, p: Vector3) -> void:
	var clamped: Vector3 = Rules.clamp_to_field(Vector3(p.x, 0.0, p.z), half_size, float(c["stats"]["body_radius_m"]))
	c["position"] = clamped
	if c["planner"] != null:
		c["planner"].position = clamped


func _separate() -> void:
	var bodies := _bodies()
	for i in bodies.size():
		for j in range(i + 1, bodies.size()):
			var a: Dictionary = bodies[i]
			var b: Dictionary = bodies[j]
			var push: Array = Rules.separate(a["position"], float(a["stats"]["body_radius_m"]), float(a["stats"]["mass_kg"]),
					b["position"], float(b["stats"]["body_radius_m"]), float(b["stats"]["mass_kg"]))
			if push[0] != Vector3.ZERO or push[1] != Vector3.ZERO:
				_place(a, a["position"] + push[0])
				_place(b, b["position"] + push[1])


# --- Signals, joining and dismissal (plan section 4). -----------------------------------------------------------

func _signal(kind: String, events: Array) -> void:
	if me["fainted"]:
		events.append({"kind": "refused", "action": kind, "who": "", "reason": "You are out cold"})
		return
	var tid := _pick_target()
	if tid == "":
		events.append({"kind": "refused", "action": kind, "who": "",
				"reason": "No one to answer: come within %s of someone" % SocialRules.metres(TARGET_M)})
		return
	var c := _individual_of(tid)
	var check := SocialRules.check_signal(kind, _actor(), _signal_target(c), tuning)
	if not check["ok"]:
		events.append({"kind": "refused", "action": kind, "who": tid, "reason": check["reason"]})
		return
	me["cooldown_t"] = int(tuning["signals"]["cooldown_t"])
	var strength := float(me["traits"]["display_strength"]) if kind == "display" else 1.0
	var r := SocialRules.respond(kind, _respond_target(c), trust_of(c), tuning, strength)
	if String(r["memory_kind"]) != "":
		_remember(c, String(r["memory_kind"]), float(r["scale"]))
	if r["gift_taken"]:
		me["carrying"] = int(me["carrying"]) - 1
		c["hunger"] = maxf(0.0, float(c["hunger"]) - float(tuning["needs"]["eat_drop"]))
	if ATTENTION_WORD.has(r["response"]):
		c["attention"] = {"response": ATTENTION_WORD[r["response"]], "until": tick_count + _attention_t}
	events.append({"kind": "response", "who": tid, "name": c["name"], "signal": kind, "response": r["response"],
			"words": r["words"], "trust": trust_of(c)})
	_maybe_join(c, events)


## A band individual whose trust reached trust.join_at joins (while the band has room); a loner is befriended and
## stays where it lives.
func _maybe_join(c: Dictionary, events: Array) -> void:
	if c["member"] or trust_of(c) < float(tuning["trust"]["join_at"]):
		return
	if c["group"] != "band":
		if not c["befriended"]:
			c["befriended"] = true
			events.append({"kind": "befriended", "who": c["id"], "name": c["name"]})
		return
	var cap := int(tuning["band"]["cap"])
	if band().size() >= cap:
		events.append({"kind": "refused", "action": "join", "who": c["id"], "reason": "Your band is full (%d)" % cap})
		return
	c["member"] = true
	c["befriended"] = true
	_release(c)
	c["order"] = {"name": "follow", "until": -1}
	events.append({"kind": "joined", "who": c["id"], "name": c["name"]})


func _dismiss(id: String, events: Array) -> void:
	var c := _individual_of(id)
	if c.is_empty():
		return
	var check := SocialRules.check_order(SocialRules.DISMISS, _order_companion(c), {}, tuning)
	if not check["ok"]:
		events.append({"kind": "order_refused", "who": id, "order": SocialRules.DISMISS, "reason": check["reason"]})
		return
	c["member"] = false
	c["order"] = {}
	_release(c)
	_remember(c, "parted", 1.0)
	events.append({"kind": "ack", "who": id, "order": SocialRules.DISMISS, "words": check["ack"]})
	events.append({"kind": "dismissed", "who": id, "name": c["name"]})


## A memory of `kind` for the individual, and the event's capped step in its group's reputation.
func _remember(c: Dictionary, kind: String, scale: float) -> void:
	c["memory"] = SocialMemory.add(c["memory"], kind, tick_count, tuning, scale)
	var group := String(c["group"])
	reputation[group] = SocialMemory.reputation_after(float(reputation.get(group, 0.0)),
			SocialMemory.event_weight(kind, tuning, scale), tuning)


func _actor() -> Dictionary:
	return {"position": _g(me), "cooldown_t": int(me["cooldown_t"]), "carrying": int(me["carrying"]),
			"traits": me["traits"]}


func _signal_target(c: Dictionary) -> Dictionary:
	return {"position": _g(c), "heading": Rules.forward(c["yaw"]), "traits": c["traits"],
			"hostile_left_t": hostile_left(c), "group_hostile": SocialMemory.group_hostile(float(reputation[c["group"]]), tuning)}


func _respond_target(c: Dictionary) -> Dictionary:
	return {"hunger": float(c["hunger"]), "fear": float(c["fear"]), "disposition": c["disposition"],
			"busy": c["state"] == "flee" or (c["state"] == "assist"), "traits": c["traits"]}


func _order_companion(c: Dictionary) -> Dictionary:
	return {"role": c["role"], "fear": float(c["fear"]), "trust": trust_of(c),
			"hostile": hostile_left(c) > 0 or SocialMemory.group_hostile(float(reputation[c["group"]]), tuning),
			"member": c["member"], "home_name": c["home"]}


## The individual the player's signals go to: within TARGET_M, the lowest distance * (2 - cos(angle))^2, where angle
## is between the player's facing and the direction to it, so the one the player faces wins over a closer one to its
## side (3 m straight ahead scores 3, 2 m to the side 8, 1 m behind 9); ties by id. "" when there is none or the
## player is out cold.
func _pick_target() -> String:
	if me.is_empty() or me["fainted"]:
		return ""
	var at := _g(me)
	var facing := Rules.forward(me["yaw"])
	var best := ""
	var best_score := INF
	for c in cast:
		var to := _g(c) - at
		var dist := to.length()
		if dist > TARGET_M:
			continue
		var off := 2.0 - (facing.dot(to / dist) if dist > 0.001 else 1.0)
		var score := dist * off * off
		if score < best_score:
			best = c["id"]
			best_score = score
	return best


# --- Senses and geometry. ----------------------------------------------------------------------------------------

func _sees(c: Dictionary, other: Dictionary) -> bool:
	return _dist(c, other) <= float(c["traits"]["sight_m"])


static func _g(c: Dictionary) -> Vector2:
	var p: Vector3 = c["position"]
	return Vector2(p.x, p.z)


static func _dist(a: Dictionary, b: Dictionary) -> float:
	return _g(a).distance_to(_g(b))


static func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _seen(from: Vector2, to: Vector2) -> Dictionary:
	var d := to - from
	var dist := d.length()
	return {"dir": d / dist if dist > 1e-6 else Vector2(0.0, -1.0), "dist": dist}


static func _seen_site(from: Vector2, site: Dictionary) -> Dictionary:
	var out := _seen(from, site["position"])
	out["radius"] = float(site["radius"])
	return out


func _bush(id: String) -> Dictionary:
	if id == "":
		return {}
	for b in bushes:
		if b["id"] == id:
			return b
	return {}


func _individual_of(id: String) -> Dictionary:
	for c in cast:
		if c["id"] == id:
			return c
	return {}


func _body(id: String) -> Dictionary:
	if id == PLAYER_ID:
		return me
	if id == hunter_c["id"]:
		return hunter_c
	return _individual_of(id)


# --- What the scene, the HUD and tests read. -------------------------------------------------------------------

## The individual's trust in the player now (SocialMemory.trust).
func trust_of(c: Dictionary) -> float:
	return SocialMemory.trust(c["memory"], tick_count, float(tuning["trust"]["base"][c["disposition"]]),
			float(reputation.get(c["group"], 0.0)), tuning)


## Ticks the individual stays hostile (0 when it listens).
func hostile_left(c: Dictionary) -> int:
	return maxi(0, int(c["hostile_until"]) - tick_count)


## The band's member ids, in id order.
func band() -> PackedStringArray:
	var out := PackedStringArray()
	for c in cast:
		if c["member"]:
			out.append(c["id"])
	return out


## Every individual as the HUD reads it (individual()), in id order.
func individuals() -> Array:
	var out := []
	for c in cast:
		out.append(_view(c))
	return out


## One individual as the HUD reads it: {id, name, preset, role, disposition, group, home, position (Vector3), yaw,
## state, tier, member, befriended, order, hunger, fear, carrying, trust, trust_word, mood, hostile_left_t, fits}.
## {} for an unknown id.
func individual(id: String) -> Dictionary:
	var c := _individual_of(id)
	return _view(c) if not c.is_empty() else {}


func _view(c: Dictionary) -> Dictionary:
	var trust := trust_of(c)
	var shown := {"hunger": float(c["hunger"]), "fear": float(c["fear"]), "disposition": c["disposition"],
			"trust": trust, "traits": c["traits"], "member": c["member"], "hostile_left_t": hostile_left(c),
			"group_hostile": SocialMemory.group_hostile(float(reputation[c["group"]]), tuning)}
	return {"id": c["id"], "name": c["name"], "preset": c["preset"], "role": c["role"], "disposition": c["disposition"],
			"group": c["group"], "home": c["home"], "position": c["position"], "yaw": c["yaw"], "state": c["state"],
			"tier": c["tier"], "member": c["member"], "befriended": c["befriended"],
			"order": String((c["order"] as Dictionary).get("name", "")), "hunger": float(c["hunger"]),
			"fear": float(c["fear"]), "carrying": int(c["carrying"]), "trust": trust,
			"trust_word": SocialRules.trust_word(trust, tuning), "mood": SocialRules.mood(shown, tuning),
			"hostile_left_t": hostile_left(c), "fits": SocialRules.fitting_signal(shown, tuning)}


## The player as the scene and HUD read it.
func player() -> Dictionary:
	var s: Dictionary = me["stats"]
	return {"position": me["position"], "yaw": me["yaw"], "health": float(me["health"]),
			"max_health": float(s["max_health"]), "fainted": me["fainted"], "carrying": int(me["carrying"]),
			"carry_count": int(me["traits"]["carry_count"]), "cooldown_t": int(me["cooldown_t"]),
			"has_legs": s["has_legs"], "has_mouth": s["has_mouth"], "traits": me["traits"],
			"at_nest": _g(me).distance_to(sites["nest"]["position"]) <= float(sites["nest"]["radius"])}


## The hunter as the scene and HUD read it: {id, preset, position (Vector3), yaw, state, nerve, tier}.
func hunter() -> Dictionary:
	return {"id": hunter_c["id"], "preset": hunter_c["preset"], "position": hunter_c["position"],
			"yaw": hunter_c["yaw"], "state": String(hunter_c["brain"].get("state", "patrol")),
			"nerve": int(hunter_c["nerve"]), "tier": hunter_c["tier"]}


## The id of the individual the player's signals go to now ("" for none).
func target_id() -> String:
	return _target


## Whether `kind` can be given now, by the same check tick() makes: {ok, reason, range_m, target}.
func preview_signal(kind: String) -> Dictionary:
	if me["fainted"]:
		return {"ok": false, "reason": "You are out cold", "range_m": 0.0, "target": ""}
	var tid := _pick_target()
	if tid == "":
		return {"ok": false, "reason": "No one to answer: come within %s of someone" % SocialRules.metres(TARGET_M),
				"range_m": 0.0, "target": ""}
	var out := SocialRules.check_signal(kind, _actor(), _signal_target(_individual_of(tid)), tuning)
	out["target"] = tid
	return out


## The gait planner of a body (the player's with PLAYER_ID), for the scene's walker rigs; null without legs.
func planner_of(id: String) -> RefCounted:
	var c := _body(id)
	return c["planner"] if not c.is_empty() else null


func body_of(id: String) -> RefCounted:
	var c := _body(id)
	return c["body"] if not c.is_empty() else null


func gait_of(id: String) -> Dictionary:
	var c := _body(id)
	return c["gait"] if not c.is_empty() else {}


## Puts a body at a ground point facing `yaw` (tests and the dev tools only; the stage never calls it).
func place(id: String, at: Vector2, yaw: float) -> void:
	var c := _body(id)
	if c.is_empty():
		return
	c["yaw"] = yaw
	if c["planner"] != null:
		c["planner"].yaw = yaw
	_place(c, Vector3(at.x, 0.0, at.y))


## Plain data in a fixed order: ground vectors as [x, z] pairs, lists in id order.
func snapshot() -> Dictionary:
	var out := {"tick": tick_count, "world_seed": world_seed, "target": _target, "band": Array(band()),
			"reputation": _sorted(reputation), "player": _body_snapshot(me), "individuals": [], "hunter": _body_snapshot(hunter_c),
			"bushes": []}
	out["player"].merge({"fainted": me["fainted"], "carrying": me["carrying"], "cooldown_t": me["cooldown_t"]}, true)
	for c in cast:
		var s := _body_snapshot(c)
		s.merge({"name": c["name"], "preset": c["preset"], "role": c["role"], "member": c["member"],
				"befriended": c["befriended"], "hunger": c["hunger"], "fear": c["fear"], "carrying": c["carrying"],
				"reserved": c["reserved"], "order": String((c["order"] as Dictionary).get("name", "")),
				"memory": (c["memory"] as Array).duplicate(true), "hostile_until": c["hostile_until"],
				"trust": trust_of(c)}, true)
		out["individuals"].append(s)
	out["hunter"].merge({"nerve": hunter_c["nerve"], "waypoint": hunter_c["waypoint"]}, true)
	for b in bushes:
		out["bushes"].append({"id": b["id"], "position": _arr(b["position"]), "ripe": b["ripe"],
				"reserved_by": b["reserved_by"]})
	return out


func _body_snapshot(c: Dictionary) -> Dictionary:
	return {"id": c["id"], "position": _arr(_g(c)), "yaw": c["yaw"], "health": c["health"], "state": c["state"],
			"tier": c["tier"]}


static func _arr(v: Vector2) -> Array:
	return [v.x, v.y]


static func _sorted(d: Dictionary) -> Dictionary:
	var keys := d.keys()
	keys.sort()
	var out := {}
	for k in keys:
		out[k] = d[k]
	return out
