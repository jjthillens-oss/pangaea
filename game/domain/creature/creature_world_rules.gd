extends RefCounted
## The test field's pure rules (PROPOSED, creature-stage-plan.md section 5): steering a body towards a direction,
## the field's walls, when a bite lands, what food is worth, the death toll, and the seeded draws that lay out the
## field and dress the rivals. CreatureWorldSim (game/systems/creature/) calls these in its tick order; nothing here
## keeps state. Pure rules: no scene or file access; every draw comes from the RandomNumberGenerator it is handed.

const Session := preload("res://game/domain/creature/creature_editor_session.gd")
const GaitBody := preload("res://game/domain/creature/gait_body.gd")

## A heading error this large (rad) asks for the full turn rate; the throttle falls with the cosine of the error and
## is nothing past a right angle, so a body turns in place before it walks the other way.
const TURN_WINDOW_RAD := 0.5
## A bite lands only on a target within this half-angle of the biter's heading.
const BITE_CONE_DEG := 60.0
## Food and nest keep-out: nothing grows this far into the nest's surroundings.
const NEST_CLEAR_MARGIN_M := 4.0
## Rivals wear at most this many drawn parts.
const RIVAL_PARTS_MAX := 4
## How many anchors a rival draw tries per part before giving up on it.
const RIVAL_ANCHOR_TRIES := 6


## Seconds in the tuning to whole ticks, once at load.
static func to_ticks(seconds: float, ticks_per_second: int) -> int:
	return maxi(1, int(round(seconds * ticks_per_second)))


## The planner command (throttle, turn) that steers a body at `yaw` (0 faces -Z, about +Y) towards the ground
## direction `desired` (x along +X, y along +Z) at `throttle`. Positive turn is to the left, as the planner takes it.
static func steer(yaw: float, desired: Vector2, throttle: float) -> Vector2:
	if desired.length_squared() < 1e-12 or throttle <= 0.0:
		return Vector2.ZERO
	var wanted := atan2(-desired.x, -desired.y)
	var err := wrapf(wanted - yaw, -PI, PI)
	var turn := clampf(err / TURN_WINDOW_RAD, -1.0, 1.0)
	return Vector2(clampf(throttle, 0.0, 1.0) * maxf(0.0, cos(err)), turn)


## A body's forward direction on the ground for a yaw.
static func forward(yaw: float) -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


## The field's walls: a point is kept `radius` inside the square of half size `half`.
static func clamp_to_field(p: Vector3, half: float, radius: float) -> Vector3:
	var r := minf(radius, half)
	return Vector3(clampf(p.x, -half + r, half - r), p.y, clampf(p.z, -half + r, half - r))


## Whether a mouth at `biter` facing `yaw` with `reach` past its skin touches a target of `target_radius`, in the bite
## cone.
static func bite_lands(biter: Vector3, yaw: float, reach: float, target: Vector3, target_radius: float) -> bool:
	var to := Vector2(target.x - biter.x, target.z - biter.z)
	var dist := to.length()
	if dist - target_radius > reach:
		return false
	if dist < 1e-6:
		return true
	return rad_to_deg(forward(yaw).angle_to(to / dist)) <= BITE_CONE_DEG


## Food in reach: the ground distance between the two centres within `reach` plus the food's radius.
static func touches(creature: Vector3, reach: float, food: Vector3, food_radius: float) -> bool:
	return Vector2(food.x - creature.x, food.z - creature.z).length() <= reach + food_radius


## What a fruit is worth: the full value with a mouth, else the no-mouth share (rounded down, at least 1).
static func fruit_points(base: int, has_mouth: bool, no_mouth_share: float) -> int:
	return base if has_mouth else maxi(1, int(floor(base * no_mouth_share)))


## Points left after a death: the loss share rounded down.
static func points_after_death(points: int, loss_share: float) -> int:
	return points - int(floor(points * loss_share))


## Evolving happens only at the nest.
static func can_evolve(at_nest: bool) -> Dictionary:
	if at_nest:
		return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "Return to the nest to evolve"}


## Push that separates two round bodies on the ground, as [move for a, move for b] (by inverse mass).
static func separate(a: Vector3, ra: float, ma: float, b: Vector3, rb: float, mb: float) -> Array:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var dist := d.length()
	var overlap := ra + rb - dist
	if overlap <= 0.0:
		return [Vector3.ZERO, Vector3.ZERO]
	var n := d / dist if dist > 1e-6 else Vector2(1.0, 0.0)
	var total := ma + mb
	var share_a := mb / total if total > 0.0 else 0.5
	return [Vector3(-n.x, 0.0, -n.y) * overlap * share_a, Vector3(n.x, 0.0, n.y) * overlap * (1.0 - share_a)]


## `count` ground points over the field, outside the nest and its margin, from `rng`, in draw order.
static func scatter(rng: RandomNumberGenerator, count: int, half: float, nest_radius: float, margin: float) -> Array:
	var out := []
	var keep_out := nest_radius + NEST_CLEAR_MARGIN_M
	var tries := 0
	while out.size() < count and tries < count * 20:
		tries += 1
		var p := Vector3(rng.randf_range(-half + margin, half - margin), 0.0, rng.randf_range(-half + margin, half - margin))
		if Vector2(p.x, p.z).length() < keep_out:
			continue
		out.append(p)
	return out


## Picks `count` legged starter bodies (as codec dictionaries) from `starters` (name -> dict, used in sorted name
## order), repeating when there are fewer legged bodies than rivals.
static func pick_rival_starters(starters: Dictionary, count: int, rng: RandomNumberGenerator) -> Array:
	var names: Array = starters.keys()
	names.sort()
	var legged := []
	for n in names:
		var body = load("res://game/domain/creature/body_codec.gd").from_dict(starters[n])
		if not (GaitBody.from_description(body)["body"]["legs"] as Array).is_empty():
			legged.append(n)
	var out := []
	for i in count:
		if legged.is_empty():
			break
		out.append(legged[rng.randi_range(0, legged.size() - 1)])
	return out


## Dresses a starter body with 0..RIVAL_PARTS_MAX parts drawn from `rng` on anchors that validate (the editor
## session refuses what the rules do not allow, so a refused draw is skipped). Returns a new description.
static func draw_rival_body(starter: RefCounted, rng: RandomNumberGenerator, body_rules: Dictionary,
		part_rules: Dictionary, costs: Dictionary) -> RefCounted:
	var session = Session.new(starter, body_rules, part_rules, costs, 1000000)
	var types: Array = part_rules.keys()
	types.sort()
	var spine_types := []
	for t in types:
		if (part_rules[t]["hosts"] as Array).has("spine"):
			spine_types.append(t)
	var wanted := rng.randi_range(0, RIVAL_PARTS_MAX)
	for i in wanted:
		var type: String = spine_types[rng.randi_range(0, spine_types.size() - 1)]
		var rule: Dictionary = part_rules[type]
		for attempt in RIVAL_ANCHOR_TRIES:
			var u := rng.randi_range(50, 950)
			var ring := rng.randi_range(0, 999)
			var scale := rng.randi_range(700, 1300)
			var on_middle := String(rule["centerline"]) == "required"
			if on_middle:
				ring = 0 if rng.randf() < 0.5 else 500
			elif ring == 0 or ring == 500:
				ring += 1
			var anchor := {"host": "spine", "u": u, "ring": ring, "scale": scale, "mirror": not on_middle}
			if session.add_part(type, anchor)["ok"]:
				break
	var done: Dictionary = session.commit()
	return done["body"] if done["ok"] else starter
