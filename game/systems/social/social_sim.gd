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
## BodyMechanics, GaitPlanner and CreatureWorldRules' steer, clamp, separate and bite cone). The social rules are the
## pure ones in game/domain/social/: SocialTraits (anatomy to signals and roles), SocialMemory (fading memory, capped
## reputation), SocialRules (the one resolver for signals and orders) and the two brains, which get percepts only.
##
## Tick order (tests depend on it):
##  1. tiers: each actor within tiers.far_m of the player is near, else far ("tier" event on a change);
##  2. timers: cooldowns; the player recovers at the nest after a faint, its health regenerates;
##  3. the player's intent: dismiss, then the order, then the signal (each a one-tick press);
##  4. the player moves (not while fainted), clamped to the field;
##  5. needs and senses: hunger rises, fear fades and rises with the hunter's closeness, a band scout that first
##     sees the hunter warns the band;
##  6. brains, the individuals in id order and then the hunter, each on its own cadence (near: every
##     tiers.near_brain_every_ticks, far: every tiers.far_every_ticks, staggered by its place in that order); their
##     reports become events;
##  7. movement: near actors steer their gait planner every tick, far actors are placed directly on their brain tick
##     (the planner's body follows; its feet catch up when it is near again);
##  8. contacts: overlapping bodies are pushed apart once, in id order (the player walking into an individual is a
##     bump); the hunter is pushed out of the nest;
##  9. bites: the player's, then the companions' (on the hunter), then the hunter's strike;
## 10. food: the player picks fruit by touch; individuals pick (gatherers) or eat at the bush they reserved;
##     deliveries at the nest and the group task; bushes regrow;
## 11. the player faints at health 0 (the band keeps every member and memory and retreats to the nest);
## 12. the player's target (the individual its signals go to) is chosen again;
## 13. the tick count.
##
## tick() returns the tick's events, each {kind, ...}:
## - signals: "refused" {action, who, reason} (a signal, an order or a bite the player could not give; it costs
##   nothing), "response" {who, name, signal, response, words, trust}, "joined" {who, name}, "befriended" {who, name}
##   (a loner: it stays where it lives);
## - orders: "ack" {who, order, words} or "order_refused" {who, order, reason} for each member, then "arrived" {who,
##   order}, "found" {who, what}, "cannot" {who, order, reason}, "done" {who, order}, "lost" {who}; "dismissed" {who,
##   name}; "left" {who, name, reason} (a member that turned hostile);
## - the task: "picked" {who, bush}, "ate" {who, bush}, "delivered" {who, count, total}, "learned" {who, route},
##   "task_done" {round, count};
## - the hunter: "hunter_state" {state, why}, "warned" {who, name}, "hit" {target, by, damage}, "drove_off" {why};
## - bites and bumps: "bit" {by, target}, "hostile" {who, name, seconds}, "bumped" {who, name};
## - the leader: "fainted" {band}, "recovered" {};
## - "tier" {who, tier}.

const TICKS_PER_SECOND := 60
const DT := 1.0 / 60.0
const PLAYER_ID := "player"
## to_record()'s kind: a test-only contract (docs/stages/social-plan.md section 12), NOT the save. Nothing writes it.
const RECORD_KIND := "social_slice_record_v0"
## The streams: world_seed * STRIDE + offset.
const STRIDE := 1000003
const CAST_STREAM := 11
const NAME_STREAM := 23
const NOISE_STREAM := 37
const GROVE_STREAM := 41
## The player's signals go to the best individual within this distance (the one it faces first).
const TARGET_M := 15.0
## How long an individual answers a signal with movement (turns to the player, steps closer or back).
const ATTENTION_S := 2.0
## A bite on the hunter makes a fight for this long (Assist sends fighters at it).
const FIGHT_S := 5.0
## An investigation finds fruit or the lair within this distance of its spot.
const FOUND_M := 4.0
## A carrier stands at its bush when it is within orders.arrive_m plus this.
const REACH_SLACK_M := 0.25
## A carried fruit and a bush's fruit, for touch.
const FRUIT_RADIUS_M := 0.5
## How many names are drawn at most to give every individual a different one.
const NAME_TRIES := 8
## How far from a site's edge its residents are first placed.
const SITE_FILL := 0.8
## The route a gatherer learns (plan section 9).
const GROVE_ROUTE := "grove"
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
## The group task (feed the nest): {round, delivered, goal, rounds_done, helpers (ids, in id order)}.
var task := {}

var _rng_cast := RandomNumberGenerator.new()
var _rng_names := RandomNumberGenerator.new()
var _rng_noise := RandomNumberGenerator.new()
var _rng_grove := RandomNumberGenerator.new()
var _target := ""
var _attention_t := 1
var _fight_t := 1
var _fight_until := 0
var _bite_held := false
var _scout_sees := false


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
	var hz := int(tuning["tick_hz"])
	_attention_t = SocialRules.to_ticks(ATTENTION_S, hz)
	_fight_t = SocialRules.to_ticks(FIGHT_S, hz)
	half_size = float(tuning["field_half_size_m"])
	for site in SITES:
		sites[site] = {"position": _v2(tuning[site]["position"]), "radius": float(tuning[site]["radius_m"])}
	me = _make(PLAYER_ID, BodyCodec.from_dict(player_body), _v2(tuning["player"]["start"]), 0.0)
	me.merge({"fainted": false, "faint_until": 0, "carrying": 0, "cooldown_t": 0}, true)
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
				"reserved": "", "pick_left": -1, "gathering": false, "learned": {}, "attention": {}, "bump_until": 0,
				"saw_hunter": false, "role": String(c["traits"]["role"]),
				"brain": CompanionBrain.fresh_memory(Rules.forward(yaw))}, true)
		taken[c["name"]] = true
		cast.append(c)
		if not reputation.has(c["group"]):
			reputation[c["group"]] = 0.0
	var h: Dictionary = tuning["hunter"]
	hunter_c = _make(String(h["id"]), BodyCodec.from_dict(data["presets"][String(h["preset"])]),
			sites["lair"]["position"], _rng_cast.randf_range(-PI, PI))
	hunter_c.merge({"preset": String(h["preset"]), "nerve": int(h["nerve"]), "waypoint": 0, "prey": "",
			"brain": HunterBrain.fresh_memory(Rules.forward(hunter_c["yaw"]))}, true)
	hunter_c["state"] = "patrol"
	var grove: Dictionary = tuning["grove"]
	var spots := _grove_spots(_rng_grove, _v2(grove["centre"]), float(grove["radius_m"]), int(grove["count"]),
			float(grove["min_spacing_m"]))
	for i in spots.size():
		bushes.append({"id": "g%d" % (i + 1), "position": spots[i], "ripe": true, "regrow_at": 0, "reserved_by": ""})
	task = {"round": 1, "delivered": 0, "goal": int(tuning["task"]["fruit_goal"]), "rounds_done": 0, "helpers": []}
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
	# 1. Tiers.
	var far_m := float(tuning["tiers"]["far_m"])
	var actors := _actors()
	for c in actors:
		var tier := "far" if _dist(c, me) > far_m else "near"
		if tier != c["tier"]:
			c["tier"] = tier
			events.append({"kind": "tier", "who": c["id"], "tier": tier})
	# 2. Timers.
	me["cooldown_t"] = maxi(0, int(me["cooldown_t"]) - 1)
	for c in _bodies():
		c["bite_cooldown"] = maxi(0, int(c["bite_cooldown"]) - 1)
	if me["fainted"] and tick_count >= int(me["faint_until"]):
		_recover(events)
	if not me["fainted"] and float(me["health"]) > 0.0:
		me["health"] = minf(float(me["stats"]["max_health"]),
				float(me["health"]) + float(tuning["player"]["health_regen_per_s"]) * DT)
	# 3. The player's intent.
	var dismiss := String(intent.get("dismiss", ""))
	if dismiss != "":
		_dismiss(dismiss, events)
	var order := String(intent.get("order", ""))
	if order != "":
		_order(order, events)
	var sig := String(intent.get("signal", ""))
	if sig != "":
		_signal(sig, events)
	# 4. The player moves.
	var before := _g(me)
	var move: Vector2 = intent.get("move", Vector2.ZERO)
	if move.length() > 1.0:
		move = move.normalized()
	if not me["fainted"]:
		_drive(me, Rules.steer(me["yaw"], move, move.length()))
	var walked := _g(me) - before
	# 5. Needs and senses.
	_update_needs(events)
	# 6. Brains.
	var moved := {}
	for i in actors.size():
		var c: Dictionary = actors[i]
		var every := int(tuning["tiers"]["far_every_ticks"]) if c["tier"] == "far" \
				else int(tuning["tiers"]["near_brain_every_ticks"])
		if (tick_count + i) % maxi(1, every) != 0:
			continue
		var elapsed := maxi(1, tick_count - int(c["last_brain"]))
		c["last_brain"] = tick_count
		if c["id"] == hunter_c["id"]:
			_hunt(elapsed, events)
		else:
			_think(c, elapsed, events)
		if c["tier"] == "far":
			_jump(c, elapsed)
			moved[c["id"]] = true
	# 7. Movement (near actors).
	for c in actors:
		if c["tier"] == "near" and not moved.has(c["id"]):
			_drive(c, Rules.steer(c["yaw"], c["heading"], float(c["throttle"])))
	# 8. Contacts.
	_separate(walked, events)
	_keep_hunter_out()
	# 9. Bites.
	var bite := bool(intent.get("bite", false))
	if bite and not me["fainted"]:
		_player_bite(not _bite_held, events)
	_bite_held = bite
	for c in cast:
		if c["wants_bite"] and c["member"]:
			_companion_bite(c, events)
	# 10. Food.
	_food(events)
	# 11. The leader.
	if not me["fainted"] and float(me["health"]) <= 0.0:
		_faint(events)
	# 12. The target.
	_target = _pick_target()
	# 13.
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


func _update_needs(events: Array) -> void:
	var needs: Dictionary = tuning["needs"]
	var rise := 1.0 / float(maxi(1, int(needs["hunger_full_t"])))
	var fade := 1.0 / float(maxi(1, int(needs["fear_decay_t"])))
	var costs: Dictionary = tuning["roles"]["costs"]
	var spot_bonus := float(tuning["roles"]["scout"].get("spot_bonus_m", 0.0))
	_scout_sees = false
	for c in cast:
		var mult := float((costs.get(c["role"], {}) as Dictionary).get("hunger_mult", 1.0))
		c["hunger"] = minf(1.0, float(c["hunger"]) + rise * mult)
		c["fear"] = maxf(0.0, float(c["fear"]) - fade)
		var sight := float(c["traits"]["sight_m"])
		var dist := _dist(c, hunter_c)
		var sees := sight > 0.0 and dist <= sight
		if sees:
			c["fear"] = maxf(float(c["fear"]), 1.0 - dist / sight)
		# The scout's advantage: it spots the hunter roles.scout.spot_bonus_m further than its eyes alone, warns the
		# band the moment it does, and the band then senses the hunter through it.
		var spots := sight > 0.0 and dist <= sight + (spot_bonus if c["role"] == "scout" else 0.0)
		if c["member"] and c["role"] == "scout":
			if spots and not c["saw_hunter"]:
				events.append({"kind": "warned", "who": c["id"], "name": c["name"]})
			if spots:
				_scout_sees = true
		c["saw_hunter"] = spots


# --- Companions. -------------------------------------------------------------------------------------------------

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


## A brain's report: an order's progress and end. Investigate and timed orders end in follow; retreat waits at the
## nest.
func _on_report(c: Dictionary, report: Dictionary, events: Array) -> void:
	var order_name := String((c["order"] as Dictionary).get("name", ""))
	match String(report["kind"]):
		"arrived":
			events.append({"kind": "arrived", "who": c["id"], "order": order_name})
			if order_name == "investigate":
				events.append({"kind": "found", "who": c["id"], "what": _found_at(c["order"]["spot"])})
				_set_order(c, "follow")
		"cannot":
			events.append({"kind": "cannot", "who": c["id"], "order": order_name, "reason": String(report.get("reason", ""))})
			_set_order(c, "follow")
		"done":
			events.append({"kind": "done", "who": c["id"], "order": order_name})
			_set_order(c, "follow")
		"lost":
			events.append({"kind": "lost", "who": c["id"]})


## What an investigation finds at its spot: fruit, the hunter's lair, the hunter, or nothing.
func _found_at(spot: Vector2) -> String:
	for b in bushes:
		if b["ripe"] and spot.distance_to(b["position"]) <= FOUND_M:
			return "fruit"
	var lair: Dictionary = sites["lair"]
	if spot.distance_to(lair["position"]) <= float(lair["radius"]) + FOUND_M:
		return "the hunter's lair"
	if spot.distance_to(_g(hunter_c)) <= FOUND_M:
		return "the hunter"
	return "nothing"


func _speed_mult(c: Dictionary) -> float:
	if not c["member"]:
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
	c["gathering"] = false
	if not order.is_empty():
		var o := {"name": order["name"], "mode": String(order.get("mode", "")), "ticks_left": _ticks_left(order)}
		if order["name"] == "assist":
			# Fighters go for the foe while there is a fight; everyone else, and everyone without a fight, gathers.
			o["mode"] = "fight" if in_fight() and CompanionBrain.fights(c["role"], tuning) else "gather"
			c["gathering"] = o["mode"] == "gather"
		if order.has("spot"):
			var s := _seen(at, order["spot"])
			o["target_dir"] = s["dir"]
			o["target_dist"] = s["dist"]
		p["order"] = o
	var sees_hunter := _sees(c, hunter_c)
	if sees_hunter or (c["member"] and _scout_sees):
		p["threat"] = _seen(at, _g(hunter_c))
		if in_fight() and c["member"]:
			p["foe"] = p["threat"]
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


## The bush an individual walks to, reserved first so no two go for the same one: a gatherer (Assist without a
## fight) with room to carry takes the nearest ripe free bush (the band knows the grove); a hungry non-member without
## an order eats at the nearest ripe free bush it can see. {} when it wants none (and its reservation goes).
func _food_for(c: Dictionary) -> Dictionary:
	var gatherer: bool = c["gathering"] and int(c["carrying"]) < int(c["traits"]["carry_count"])
	var eater: bool = not c["member"] and (c["order"] as Dictionary).is_empty() \
			and float(c["hunger"]) >= float(tuning["fit"]["hungry_at"])
	if not gatherer and not eater:
		_release(c)
		return {}
	var at := _g(c)
	var held := _bush(String(c["reserved"]))
	if held.is_empty() or not held["ripe"]:
		_release(c)
		var best := {}
		var best_d := INF if gatherer else float(c["traits"]["sight_m"])
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


## Gives a member `name` in place of its order (releasing the old order's reservation).
func _set_order(c: Dictionary, name: String, mode: String = "", spot: Variant = null, until: int = -1) -> void:
	_release(c)
	c["gathering"] = false
	var o := {"name": name, "mode": mode, "until": until, "given": tick_count}
	if spot != null:
		o["spot"] = spot
	c["order"] = o


# --- Orders (plan section 7). ------------------------------------------------------------------------------------

## The player's order to the whole band: each member acknowledges it or refuses with a reason (a refusal leaves its
## old order as it was; a forager's "no fighter, I'll gather" is the one refusal that still gathers). A new order
## cancels the old one and releases its reservation.
func _order(name: String, events: Array) -> void:
	if not SocialRules.ORDERS.has(name):
		events.append({"kind": "refused", "action": name, "who": "", "reason": "Unknown order"})
		return
	if me["fainted"]:
		events.append({"kind": "refused", "action": name, "who": "", "reason": "You are out cold"})
		return
	var members := band()
	if members.is_empty():
		events.append({"kind": "refused", "action": name, "who": "", "reason": "No one in your band yet"})
		return
	var context := {"in_fight": in_fight()}
	var spot := _g(me) + Rules.forward(me["yaw"]) * float(tuning["orders"]["investigate_m"])
	if name == "investigate":
		context["spot_hunter_m"] = spot.distance_to(_g(hunter_c))
	for id in members:
		var c := _individual_of(id)
		var check := SocialRules.check_order(name, _order_companion(c), context, tuning)
		if not check["ok"] and String(check["mode"]) == "":
			events.append({"kind": "order_refused", "who": id, "order": name, "reason": check["reason"]})
			continue
		match name:
			"wait":
				_set_order(c, name, "", _g(c))
			"investigate":
				_set_order(c, name, "", spot, tick_count + int(tuning["orders"]["timeout_t"]))
			"retreat":
				_set_order(c, name, "", sites["nest"]["position"])
			_:
				_set_order(c, name, String(check["mode"]))
		if check["ok"]:
			events.append({"kind": "ack", "who": id, "order": name, "words": check["ack"]})
		else:
			events.append({"kind": "order_refused", "who": id, "order": name, "reason": check["reason"]})


## Whether there is a fight: the hunter pursues or strikes, or the player bit it within FIGHT_S.
func in_fight() -> bool:
	var state := String(hunter_c["state"])
	return state == "pursue" or state == "strike" or tick_count < _fight_until


# --- The hunter (plan section 8). ----------------------------------------------------------------------------------

## One decision of the hunter's brain: patrol, the tell, a bounded pursuit, disengagement and rest.
func _hunt(elapsed: int, events: Array) -> void:
	var p := _hunter_percepts(elapsed)
	var before := String(hunter_c["state"])
	var d := HunterBrain.decide(p, hunter_c["brain"], tuning)
	hunter_c["heading"] = d["heading"]
	hunter_c["throttle"] = float(d["throttle"])
	hunter_c["state"] = d["state"]
	if d["advance"]:
		hunter_c["waypoint"] = (int(hunter_c["waypoint"]) + 1) % (tuning["hunter"]["patrol"] as Array).size()
	var report: Dictionary = d["report"]
	var why := String(report.get("why", ""))
	if String(report.get("kind", "")) == "rested":
		hunter_c["nerve"] = int(tuning["hunter"]["nerve"])
	if d["state"] != before:
		events.append({"kind": "hunter_state", "state": d["state"], "why": why})
	if String(report.get("kind", "")) == "disengaged" and (why == "nerve" or why == "group") \
			and _pack_of(String(hunter_c["prey"])) == PLAYER_ID:
		events.append({"kind": "drove_off", "why": why})
		for c in cast:
			if c["member"]:
				_remember(c, "helped", 1.0)
	if d["strike"]:
		_strike(events)


func _hunter_percepts(elapsed: int) -> Dictionary:
	var h: Dictionary = tuning["hunter"]
	var at := _g(hunter_c)
	var p := {"nerve": int(hunter_c["nerve"]), "heading": Rules.forward(hunter_c["yaw"]), "elapsed_t": elapsed,
			"lair": _seen_site(at, sites["lair"]), "nest": _seen_site(at, sites["nest"])}
	var patrol: Array = h["patrol"]
	p["waypoint"] = _seen(at, _v2(patrol[int(hunter_c["waypoint"]) % patrol.size()]))
	var prey := _hunter_prey()
	hunter_c["prey"] = prey
	if prey != "":
		var c := _body(prey)
		var t := _seen(at, _g(c))
		t["group_near"] = _group_near(prey)
		t["in_nest"] = _in_nest(c)
		p["target"] = t
	return p


## The prey the hunter sees: the nearest body within its sight (plus the scout's noticed bonus for a scout); the
## player only while it is up. Ties by id.
func _hunter_prey() -> String:
	var h: Dictionary = tuning["hunter"]
	var sight := float(h["sight_m"])
	var bonus := float(tuning["roles"]["costs"]["scout"]["noticed_bonus_m"])
	var best := ""
	var best_d := INF
	var candidates := cast.duplicate()
	if not me["fainted"]:
		candidates.append(me)
	candidates.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	for c in candidates:
		var dist := _dist(hunter_c, c)
		var reach := sight + (bonus if c.get("role", "") == "scout" else 0.0)
		if dist <= reach and dist < best_d:
			best = c["id"]
			best_d = dist
	return best


## The pack a body stands with: the player and its band, or the individual's own group.
func _pack_of(id: String) -> String:
	if id == PLAYER_ID:
		return PLAYER_ID
	var c := _individual_of(id)
	if c.is_empty():
		return ""
	return PLAYER_ID if c["member"] else String(c["group"])


## How many of the prey's pack stand within hunter.group_radius_m of it (itself included; a fainted player not).
func _group_near(id: String) -> int:
	var pack := _pack_of(id)
	var at := _g(_body(id))
	var radius := float(tuning["hunter"]["group_radius_m"])
	var n := 0
	if pack == PLAYER_ID and not me["fainted"] and _g(me).distance_to(at) <= radius:
		n += 1
	for c in cast:
		if _pack_of(c["id"]) == pack and _g(c).distance_to(at) <= radius:
			n += 1
	return n


## The hunter's strike on its prey: a share of the player's health, or a fright for an individual (no individual
## is hurt in the slice; only the player can faint).
func _strike(events: Array) -> void:
	var prey := String(hunter_c["prey"])
	if prey == "":
		return
	var c := _body(prey)
	var h: Dictionary = tuning["hunter"]
	if _dist(hunter_c, c) > float(h["strike_reach_m"]) + float(c["stats"]["body_radius_m"]):
		return
	var damage := 0.0
	if prey == PLAYER_ID:
		damage = float(h["strike_health_share"]) * float(me["stats"]["max_health"])
		me["health"] = float(me["health"]) - damage
	else:
		c["fear"] = 1.0
	events.append({"kind": "hit", "target": prey, "by": hunter_c["id"], "damage": damage})


func _keep_hunter_out() -> void:
	var nest: Dictionary = sites["nest"]
	var edge := float(nest["radius"]) + float(hunter_c["stats"]["body_radius_m"])
	var off := _g(hunter_c) - (nest["position"] as Vector2)
	if off.length() < edge:
		var out: Vector2 = (nest["position"] as Vector2) + (off.normalized() if off.length() > 1e-6 else Vector2(1.0, 0.0)) * edge
		_place(hunter_c, Vector3(out.x, 0.0, out.y))


func _in_nest(c: Dictionary) -> bool:
	return _g(c).distance_to(sites["nest"]["position"]) <= float(sites["nest"]["radius"])


# --- Bites, bumps and the leader. ------------------------------------------------------------------------------

## The player's bite (Foe): the nearest body in reach and in the bite cone. On an individual: a bitten memory, a
## fright, and hostility after hostile.bites bites within hostile.window_t (a member then leaves the band). On the
## hunter: it costs nerve and makes a fight.
func _player_bite(fresh: bool, events: Array) -> void:
	if not me["stats"]["has_mouth"]:
		if fresh:
			events.append({"kind": "refused", "action": "bite", "who": "", "reason": "No mouth to bite with"})
		return
	if int(me["bite_cooldown"]) > 0:
		return
	var reach := float(me["stats"]["bite_reach_m"])
	var best := {}
	var best_d := INF
	var targets := cast.duplicate()
	targets.append(hunter_c)
	for c in targets:
		var dist := _dist(me, c)
		if dist < best_d and Rules.bite_lands(me["position"], me["yaw"], reach, c["position"], float(c["stats"]["body_radius_m"])):
			best = c
			best_d = dist
	if best.is_empty():
		return
	me["bite_cooldown"] = int(tuning["bite"]["cooldown_t"])
	events.append({"kind": "bit", "by": PLAYER_ID, "target": best["id"]})
	if best["id"] == hunter_c["id"]:
		hunter_c["nerve"] = maxi(0, int(hunter_c["nerve"]) - int(tuning["bite"]["nerve_cost"]))
		_fight_until = tick_count + _fight_t
		return
	_remember(best, SocialMemory.BITTEN, 1.0)
	best["fear"] = minf(1.0, float(best["fear"]) + float(tuning["bite"]["fear"]))
	var was := hostile_left(best) > 0
	best["hostile_until"] = maxi(int(best["hostile_until"]), SocialMemory.hostile_after(best["memory"], tick_count, tuning))
	if not was and hostile_left(best) > 0:
		events.append({"kind": "hostile", "who": best["id"], "name": best["name"],
				"seconds": ceili(float(hostile_left(best)) / float(tuning["tick_hz"]))})
		if best["member"]:
			best["member"] = false
			best["order"] = {}
			_release(best)
			events.append({"kind": "left", "who": best["id"], "name": best["name"], "reason": "you hurt it"})


## A fighter's bite on the hunter (Assist in a fight).
func _companion_bite(c: Dictionary, events: Array) -> void:
	if int(c["bite_cooldown"]) > 0 or not c["stats"]["has_mouth"]:
		return
	if not Rules.bite_lands(c["position"], c["yaw"], float(c["stats"]["bite_reach_m"]), hunter_c["position"],
			float(hunter_c["stats"]["body_radius_m"])):
		return
	c["bite_cooldown"] = int(tuning["bite"]["cooldown_t"])
	hunter_c["nerve"] = maxi(0, int(hunter_c["nerve"]) - int(tuning["bite"]["nerve_cost"]))
	events.append({"kind": "bit", "by": c["id"], "target": hunter_c["id"]})


## Leader loss (Bible section 8): the band keeps every member and memory; the members retreat to the nest and wait.
func _faint(events: Array) -> void:
	me["fainted"] = true
	me["health"] = 0.0
	me["faint_until"] = tick_count + int(tuning["player"]["faint_t"])
	for c in cast:
		if c["member"]:
			_set_order(c, "retreat", "", sites["nest"]["position"])
			c["order"]["by_faint"] = true
	events.append({"kind": "fainted", "band": Array(band())})


## The player wakes at the nest at full health; the members that retreated for it follow again.
func _recover(events: Array) -> void:
	me["fainted"] = false
	me["health"] = float(me["stats"]["max_health"])
	var nest: Vector2 = sites["nest"]["position"]
	place(PLAYER_ID, nest, 0.0)
	events.append({"kind": "recovered"})
	for c in cast:
		if c["member"] and bool((c["order"] as Dictionary).get("by_faint", false)):
			_set_order(c, "follow")
			events.append({"kind": "ack", "who": c["id"], "order": "follow", "words": "follows you"})


# --- Food and the group task (plan section 8). -------------------------------------------------------------------

func _food(events: Array) -> void:
	# The player picks a fruit by touch (to Share), never one an individual has reserved.
	if not me["fainted"] and int(me["carrying"]) < int(me["traits"]["carry_count"]):
		for b in bushes:
			if b["ripe"] and String(b["reserved_by"]) == "" \
					and Rules.touches(me["position"], float(me["stats"]["body_radius_m"]), Vector3(b["position"].x, 0.0, b["position"].y), FRUIT_RADIUS_M):
				_pick(b)
				me["carrying"] = int(me["carrying"]) + 1
				events.append({"kind": "picked", "who": PLAYER_ID, "bush": b["id"]})
				break
	var arrive := float(tuning["orders"]["arrive_m"]) + REACH_SLACK_M
	var learning: Dictionary = tuning["learning"]
	for c in cast:
		var b := _bush(String(c["reserved"]))
		if b.is_empty() or not b["ripe"] or _g(c).distance_to(b["position"]) > arrive:
			continue
		if int(c["pick_left"]) < 0:
			var search := 0 if _knows_route(c) else int(learning["search_t"])
			c["pick_left"] = int(tuning["task"]["pick_t"]) + search
		c["pick_left"] = int(c["pick_left"]) - 1
		if int(c["pick_left"]) > 0:
			continue
		var gather: bool = c["gathering"]
		_pick(b)
		c["reserved"] = ""
		c["pick_left"] = -1
		if gather:
			c["carrying"] = int(c["carrying"]) + 1
			events.append({"kind": "picked", "who": c["id"], "bush": b["id"]})
		else:
			c["hunger"] = maxf(0.0, float(c["hunger"]) - float(tuning["needs"]["eat_drop"]))
			events.append({"kind": "ate", "who": c["id"], "bush": b["id"]})
	# Deliveries.
	for c in cast:
		if not c["member"] or int(c["carrying"]) <= 0 or not _in_nest(c):
			continue
		var count := int(c["carrying"])
		c["carrying"] = 0
		task["delivered"] = int(task["delivered"]) + count
		if not (task["helpers"] as Array).has(c["id"]):
			task["helpers"].append(c["id"])
			task["helpers"].sort()
		events.append({"kind": "delivered", "who": c["id"], "count": count, "total": task["delivered"]})
		var route: Dictionary = c["learned"].get(GROVE_ROUTE, {"uses": 0, "inherited": false, "idle": 0})
		var knew := _knows_route(c)
		route["uses"] = int(route["uses"]) + 1
		c["learned"][GROVE_ROUTE] = route
		if not knew and _knows_route(c):
			events.append({"kind": "learned", "who": c["id"], "route": GROVE_ROUTE})
	if int(task["delivered"]) >= int(task["goal"]):
		_task_done(events)
	for b in bushes:
		if not b["ripe"] and tick_count >= int(b["regrow_at"]):
			b["ripe"] = true


func _pick(b: Dictionary) -> void:
	b["ripe"] = false
	b["reserved_by"] = ""
	b["regrow_at"] = tick_count + int(tuning["grove"]["regrow_t"])


## Whether the individual has learned the grove route (learning.route_after_deliveries deliveries): it skips the
## search at a bush.
func _knows_route(c: Dictionary) -> bool:
	var route: Dictionary = c["learned"].get(GROVE_ROUTE, {})
	return bool(route.get("inherited", false)) \
			or int(route.get("uses", 0)) >= int(tuning["learning"]["route_after_deliveries"])


## A round of the task is done: each companion that delivered remembers it ("helped"), the gatherers' Assist ends
## ("done"), and the next round starts.
func _task_done(events: Array) -> void:
	events.append({"kind": "task_done", "round": task["round"], "count": task["delivered"]})
	for id in task["helpers"]:
		var c := _individual_of(id)
		if not c.is_empty():
			_remember(c, "helped", 1.0)
	for c in cast:
		if c["member"] and String((c["order"] as Dictionary).get("name", "")) == "assist" and not in_fight():
			events.append({"kind": "done", "who": c["id"], "order": "assist"})
			_set_order(c, "follow")
	task["rounds_done"] = int(task["rounds_done"]) + 1
	task["round"] = int(task["round"]) + 1
	task["delivered"] = 0
	task["helpers"] = []


# --- Movement. ------------------------------------------------------------------------------------------------------

## A far actor's movement for `elapsed` ticks at once, placed directly (the planner's body follows).
func _jump(c: Dictionary, elapsed: int) -> void:
	var heading: Vector2 = c["heading"]
	var speed := float(c["stats"]["speed_mps"]) * float(c["stats"].get("speed_factor", 1.0))
	var step := heading * clampf(float(c["throttle"]), 0.0, 1.0) * speed * DT * elapsed
	if heading.length_squared() > 0.0 and step.length_squared() > 0.0:
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


## Pushes overlapping bodies apart. The player walking into an individual (`walked`, its move this tick, points at
## it) is a bump: a mild memory, at most one per bump.cooldown_t (plan section 5: one accident is never a war).
func _separate(walked: Vector2, events: Array) -> void:
	var bodies := _bodies()
	for i in bodies.size():
		for j in range(i + 1, bodies.size()):
			var a: Dictionary = bodies[i]
			var b: Dictionary = bodies[j]
			var push: Array = Rules.separate(a["position"], float(a["stats"]["body_radius_m"]), float(a["stats"]["mass_kg"]),
					b["position"], float(b["stats"]["body_radius_m"]), float(b["stats"]["mass_kg"]))
			if push[0] == Vector3.ZERO and push[1] == Vector3.ZERO:
				continue
			if i == 0 and b.has("bump_until") and walked.dot(_g(b) - _g(a)) > 0.0 and tick_count >= int(b["bump_until"]):
				b["bump_until"] = tick_count + int(tuning["bump"]["cooldown_t"])
				_remember(b, "bumped", 1.0)
				events.append({"kind": "bumped", "who": b["id"], "name": b["name"]})
			_place(a, a["position"] + push[0])
			_place(b, b["position"] + push[1])


# --- Signals, joining and dismissal (plan section 4). -----------------------------------------------------------

func _signal(kind: String, events: Array) -> void:
	var check := preview_signal(kind)
	if not check["ok"]:
		events.append({"kind": "refused", "action": kind, "who": check["target"], "reason": check["reason"]})
		return
	var tid := String(check["target"])
	var c := _individual_of(tid)
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
	_set_order(c, "follow")
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
	_release(c)
	c["order"] = {}
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
			"busy": c["state"] == "flee" or c["state"] == "assist", "traits": c["traits"]}


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
## state, tier, member, befriended, order, hunger, fear, carrying, reserved, learned, trust, trust_word, mood,
## hostile_left_t, fits}. {} for an unknown id.
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
			"fear": float(c["fear"]), "carrying": int(c["carrying"]), "reserved": c["reserved"],
			"learned": _knows_route(c), "trust": trust, "trust_word": SocialRules.trust_word(trust, tuning),
			"mood": SocialRules.mood(shown, tuning), "hostile_left_t": hostile_left(c),
			"fits": SocialRules.fitting_signal(shown, tuning)}


## The player as the scene and HUD read it.
func player() -> Dictionary:
	var s: Dictionary = me["stats"]
	return {"position": me["position"], "yaw": me["yaw"], "health": float(me["health"]),
			"max_health": float(s["max_health"]), "fainted": me["fainted"], "carrying": int(me["carrying"]),
			"carry_count": int(me["traits"]["carry_count"]), "cooldown_t": int(me["cooldown_t"]),
			"has_legs": s["has_legs"], "has_mouth": s["has_mouth"], "traits": me["traits"], "at_nest": _in_nest(me)}


## The hunter as the scene and HUD read it: {id, preset, position (Vector3), yaw, state, nerve, tier}.
func hunter() -> Dictionary:
	return {"id": hunter_c["id"], "preset": hunter_c["preset"], "position": hunter_c["position"],
			"yaw": hunter_c["yaw"], "state": String(hunter_c["state"]), "nerve": int(hunter_c["nerve"]),
			"tier": hunter_c["tier"]}


## The group task as the HUD reads it: {round, delivered, goal, rounds_done}.
func task_state() -> Dictionary:
	return {"round": int(task["round"]), "delivered": int(task["delivered"]), "goal": int(task["goal"]),
			"rounds_done": int(task["rounds_done"])}


## The grove as the scene draws it: [{id, position (Vector2), ripe}] in id order.
func bush_states() -> Array:
	var out := []
	for b in bushes:
		out.append({"id": b["id"], "position": b["position"], "ripe": b["ripe"]})
	return out


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


## Whether `order` would be taken now, by the same check tick() makes: {ok (some member takes it), reason (the
## first refusal, or why no one can), answers: [{who, ok, words, reason}] in id order}.
func preview_order(order: String) -> Dictionary:
	if me["fainted"]:
		return {"ok": false, "reason": "You are out cold", "answers": []}
	var members := band()
	if members.is_empty():
		return {"ok": false, "reason": "No one in your band yet", "answers": []}
	var context := {"in_fight": in_fight()}
	if order == "investigate":
		var spot := _g(me) + Rules.forward(me["yaw"]) * float(tuning["orders"]["investigate_m"])
		context["spot_hunter_m"] = spot.distance_to(_g(hunter_c))
	var answers := []
	var any := false
	var reason := ""
	for id in members:
		var check := SocialRules.check_order(order, _order_companion(_individual_of(id)), context, tuning)
		var takes: bool = check["ok"] or String(check["mode"]) != ""
		any = any or takes
		if not check["ok"] and reason == "":
			reason = String(check["reason"])
		answers.append({"who": id, "ok": check["ok"], "words": check["ack"], "reason": check["reason"]})
	return {"ok": any, "reason": reason, "answers": answers}


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
			"reputation": _sorted(reputation), "task": task.duplicate(true), "in_fight": in_fight(),
			"player": _body_snapshot(me), "individuals": [], "hunter": _body_snapshot(hunter_c), "bushes": []}
	out["player"].merge({"fainted": me["fainted"], "carrying": me["carrying"], "cooldown_t": me["cooldown_t"]}, true)
	for c in cast:
		var s := _body_snapshot(c)
		s.merge({"name": c["name"], "preset": c["preset"], "role": c["role"], "member": c["member"],
				"befriended": c["befriended"], "hunger": c["hunger"], "fear": c["fear"], "carrying": c["carrying"],
				"reserved": c["reserved"], "order": String((c["order"] as Dictionary).get("name", "")),
				"memory": (c["memory"] as Array).duplicate(true), "hostile_until": c["hostile_until"],
				"learned": (c["learned"] as Dictionary).duplicate(true), "trust": trust_of(c)}, true)
		out["individuals"].append(s)
	out["hunter"].merge({"nerve": hunter_c["nerve"], "waypoint": hunter_c["waypoint"], "prey": hunter_c["prey"]}, true)
	for b in bushes:
		out["bushes"].append({"id": b["id"], "position": _arr(b["position"]), "ripe": b["ripe"],
				"reserved_by": b["reserved_by"], "regrow_at": b["regrow_at"]})
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


# --- The test-only record (plan section 12: NOT the save; nothing writes it to disk). -----------------------------

## Who the individuals are and what they remember, as plain data: {record: RECORD_KIND, world_seed, tick,
## individuals: [{id, name, preset, role, member, befriended, memory, hostile_until, learned}] in id order,
## reputation, task}. Positions, needs and orders are not kept: a reloaded band gathers round the player.
func to_record() -> Dictionary:
	var people := []
	for c in cast:
		people.append({"id": c["id"], "name": c["name"], "preset": c["preset"], "role": c["role"], "member": c["member"],
				"befriended": c["befriended"], "memory": (c["memory"] as Array).duplicate(true),
				"hostile_until": c["hostile_until"], "learned": (c["learned"] as Dictionary).duplicate(true)})
	return {"record": RECORD_KIND, "world_seed": world_seed, "tick": tick_count, "individuals": people,
			"reputation": _sorted(reputation), "task": task.duplicate(true)}


## A world rebuilt from to_record(): the same seed's world with the recorded names, members, memories, hostility,
## learned routes, reputation and task, at the recorded tick; members stand round the player at its start and
## follow. null for a record of another kind.
static func from_record(record: Dictionary, player_body: Dictionary, p_tuning: Dictionary, p_data: Dictionary) -> SocialSim:
	if String(record.get("record", "")) != RECORD_KIND:
		return null
	var sim := SocialSim.new(player_body, int(record["world_seed"]), p_tuning, p_data)
	sim.tick_count = int(record["tick"])
	var spacing := float(sim.tuning["band"]["spacing_m"])
	var around := _v2(sim.tuning["player"]["start"])
	var n := 0
	for rec in record["individuals"]:
		var c := sim._individual_of(String(rec["id"]))
		if c.is_empty():
			continue
		c["name"] = String(rec["name"])
		c["member"] = bool(rec["member"])
		c["befriended"] = bool(rec["befriended"])
		var memory := []
		for e in rec["memory"]:
			memory.append(SocialMemory.entry(String(e["kind"]), int(e["tick"]), float(e.get("scale", 1.0))))
		c["memory"] = memory
		c["hostile_until"] = int(rec["hostile_until"])
		var learned := {}
		for route in rec["learned"]:
			var r: Dictionary = rec["learned"][route]
			learned[String(route)] = {"uses": int(r["uses"]), "inherited": bool(r["inherited"]), "idle": int(r["idle"])}
		c["learned"] = learned
		if c["member"]:
			n += 1
			var at := around + Vector2(cos(n * TAU / 3.0), sin(n * TAU / 3.0)) * spacing * 1.5
			sim.place(c["id"], at, c["yaw"])
			sim._set_order(c, "follow")
	for c in sim._bodies():
		c["last_brain"] = sim.tick_count
	var rep: Dictionary = record["reputation"]
	for group in rep:
		sim.reputation[String(group)] = float(rep[group])
	var t: Dictionary = record["task"]
	var helpers := []
	for id in t["helpers"]:
		helpers.append(String(id))
	sim.task = {"round": int(t["round"]), "delivered": int(t["delivered"]), "goal": int(t["goal"]),
			"rounds_done": int(t["rounds_done"]), "helpers": helpers}
	sim._target = sim._pick_target()
	return sim
