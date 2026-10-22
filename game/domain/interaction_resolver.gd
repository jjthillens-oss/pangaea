class_name InteractionResolver
extends RefCounted
## The one place that decides whether feed, bite and ram are allowed and what they do
## (Bible section 14). The editor preview and live play call the same functions.
## A refusal names the missing requirement and changes nothing.
##
## Positions are on the movement plane (Vector2, meters). Heading 0 faces +X; part angles are
## relative to the heading. Cooldowns are absolute times in seconds, keyed by action and target.

const FEED_REACH := 0.25      ## m beyond both radii
const BITE_REACH := 0.3
const RAM_REACH := 0.35
const BITE_SIZE_LIMIT := 1.6  ## a jaw cannot bite something more than this many times its radius
const BITE_COOLDOWN := 0.6
const RAM_COOLDOWN := 0.5
const FEED_COOLDOWN := 0.25


## An actor taking part in an interaction.
class Actor:
	var id: String
	var position: Vector2
	var heading: float
	var phenotype: Phenotype
	var cooldowns: Dictionary = {}

	func _init(p_id: String, p_position: Vector2, p_heading: float, p_phenotype: Phenotype) -> void:
		id = p_id
		position = p_position
		heading = p_heading
		phenotype = p_phenotype


static func _result(allowed: bool, reason: String, effect: Dictionary = {}) -> Dictionary:
	return {"allowed": allowed, "reason": reason, "effect": effect}


## Angle of `point` relative to the actor's facing, in -PI..PI.
static func relative_angle(actor: Actor, point: Vector2) -> float:
	return wrapf((point - actor.position).angle() - actor.heading, -PI, PI)


static func _facing(actor: Actor, point: Vector2, part_angle: float, arc: float) -> bool:
	return absf(angle_difference(part_angle, relative_angle(actor, point))) <= arc * 0.5


static func _ready_at(actor: Actor, key: String, now: float) -> bool:
	return now >= float(actor.cooldowns.get(key, 0.0))


## food: {"id", "kind": "plant"|"meat", "position": Vector2, "radius": float, "energy": float, "points": int}
static func feed(actor: Actor, food: Dictionary, now: float) -> Dictionary:
	var p := actor.phenotype
	if not p.can_eat(food.kind):
		return _result(false, "needs a %s" % ("filter mouth" if food.kind == "plant" else "jaw"))
	var dist := actor.position.distance_to(food.position)
	if dist > p.radius + food.radius + FEED_REACH:
		return _result(false, "out of reach")
	var facing := false
	for mouth in p.mouths:
		if mouth.diet == food.kind and _facing(actor, food.position, mouth.angle, mouth.arc):
			facing = true
	if not facing:
		return _result(false, "mouth is not facing it")
	if not _ready_at(actor, "feed", now):
		return _result(false, "still swallowing")
	actor.cooldowns["feed"] = now + FEED_COOLDOWN
	return _result(true, "", {"energy": food.energy, "points": food.get("points", 0), "consume": food.id})


static func bite(attacker: Actor, target: Actor, now: float) -> Dictionary:
	var p := attacker.phenotype
	if p.bite_damage <= 0.0:
		return _result(false, "needs a jaw")
	if target.phenotype.radius > p.radius * BITE_SIZE_LIMIT:
		return _result(false, "too big to bite")
	if attacker.position.distance_to(target.position) > p.radius + target.phenotype.radius + BITE_REACH:
		return _result(false, "out of reach")
	var facing := false
	for mouth in p.mouths:
		if mouth.type == "mouth_jaw" and _facing(attacker, target.position, mouth.angle, mouth.arc):
			facing = true
	if not facing:
		return _result(false, "jaw is not facing it")
	var key := "bite:" + target.id
	if not _ready_at(attacker, key, now):
		return _result(false, "jaw is recovering")
	attacker.cooldowns[key] = now + BITE_COOLDOWN
	return _result(true, "", {"damage": p.bite_damage * (1.0 - target.phenotype.defense), "target": target.id})


## A ram lands with every spike that points at the target. Damage scales with closing speed.
static func ram(attacker: Actor, target: Actor, closing_speed: float, now: float) -> Dictionary:
	var p := attacker.phenotype
	if p.spikes.is_empty():
		return _result(false, "needs a spike")
	if attacker.position.distance_to(target.position) > p.radius + target.phenotype.radius + RAM_REACH:
		return _result(false, "out of reach")
	var hits := 0
	for spike in p.spikes:
		if _facing(attacker, target.position, spike.angle, spike.arc):
			hits += 1
	if hits == 0:
		return _result(false, "no spike points at it")
	var key := "ram:" + target.id
	if not _ready_at(attacker, key, now):
		return _result(false, "spikes are recovering")
	attacker.cooldowns[key] = now + RAM_COOLDOWN
	var impact := clampf(closing_speed / maxf(p.speed, 0.01), 0.25, 1.5)
	var damage := p.ram_damage * hits * impact * (1.0 - target.phenotype.defense)
	return _result(true, "", {"damage": damage, "target": target.id, "spikes": hits})
