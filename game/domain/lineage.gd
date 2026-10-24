class_name Lineage
extends RefCounted
## Generation changes and death for a run (Bible sections 5 and 18). Reproduction commits an
## editor session into the next generation and records it; death returns the player to the
## current generation's start without erasing the lineage.

const REPRODUCE_ENERGY_SHARE := 0.7   ## energy needed, as a share of capacity
const DEATH_POINT_LOSS := 0.25        ## approved 2026-10-22: unspent points drop by a quarter
const SURVIVAL_INTERVAL := 30.0       ## seconds alive per survival point (PROPOSED)
const BODY_ANGLE_TOLERANCE := 0.01    ## rad: a part this close to a starting body's angle still matches it
const BODY_SCALE_TOLERANCE := 0.001


## Starts a new lineage with one of the catalog's starting bodies (approved 2026-10-22: grazer,
## hunter, omnivore). Returns {"ok", "errors", "save"}; the save is null unless the body is valid.
static func found(seed_value: int, build_id: String, catalog: PartCatalog, body_name: String) -> Dictionary:
	if not catalog.starting_bodies.has(body_name):
		return {"ok": false, "errors": PackedStringArray(["Unknown starting body '%s'." % body_name]), "save": null}
	var save := SaveGame.new_run(seed_value, build_id)
	for part in catalog.starting_bodies[body_name]:
		save.genome.add_part(part.type, part.angle, part.scale)
	var errors := save.validate(catalog)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "save": null}
	return {"ok": true, "errors": PackedStringArray(), "save": save}


## The starting body this genome still is ("grazer", "hunter", "omnivore"), or "" once it has
## been edited: same part types, angles within BODY_ANGLE_TOLERANCE and the same scales, in any order.
static func starting_body_of(genome: Genome, catalog: PartCatalog) -> String:
	for body_name in catalog.starting_bodies:
		var body: Array = catalog.starting_bodies[body_name]
		if body.size() != genome.parts.size():
			continue
		var unused := genome.parts.duplicate()
		var matched := true
		for wanted in body:
			var hit := -1
			for i in unused.size():
				if _same_part(unused[i], wanted):
					hit = i
					break
			if hit < 0:
				matched = false
				break
			unused.remove_at(hit)
		if matched:
			return body_name
	return ""


static func _same_part(part: Dictionary, wanted: Dictionary) -> bool:
	var angle = part.get("angle")
	var scale = part.get("scale", 1.0)
	if str(part.get("type", "")) != wanted.type or not (angle is float or angle is int) or not (scale is float or scale is int):
		return false
	return absf(angle_difference(float(angle), wanted.angle)) <= BODY_ANGLE_TOLERANCE \
		and absf(float(scale) - wanted.scale) <= BODY_SCALE_TOLERANCE


static func can_reproduce(state: ActorState) -> Dictionary:
	if not state.is_alive():
		return {"ok": false, "reason": "not alive"}
	var needed := state.energy_capacity * REPRODUCE_ENERGY_SHARE
	if state.energy < needed:
		return {"ok": false, "reason": "needs %d more energy" % ceili(needed - state.energy)}
	return {"ok": true, "reason": ""}


## can_reproduce(state).ok, building nothing (Kin asks every tick).
static func may_reproduce(state: ActorState) -> bool:
	return state.is_alive() and state.energy >= state.energy_capacity * REPRODUCE_ENERGY_SHARE


## Commits the session into the save as the next generation. Returns {"ok", "errors"}.
## Refused, with nothing in the save changed, when the actor cannot reproduce, the session is for
## another genome, or the session's points no longer match the save (for example after a death).
static func reproduce(save: SaveGame, session: EditorSession, state: ActorState) -> Dictionary:
	var gate := can_reproduce(state)
	if not gate.ok:
		return {"ok": false, "errors": PackedStringArray(["Cannot reproduce: %s." % gate.reason])}
	if session.original.genome_id != save.genome.genome_id:
		return {"ok": false, "errors": PackedStringArray(["Editor session is for a different genome."])}
	if session.available_points != save.adaptation_points:
		return {"ok": false, "errors": PackedStringArray(["Editor session is out of date: points changed since it opened."])}
	var result := session.commit()
	if not result.ok:
		return {"ok": false, "errors": result.errors}
	var child: Genome = result.genome
	save.genome = child
	save.adaptation_points = result.points_left
	save.lineage_history.append({
		"generation": child.generation,
		"genome_id": child.genome_id,
		"parent_genome_id": child.parent_genome_id,
		"event": "born",
		"part_count": child.parts.size(),
	})
	return {"ok": true, "errors": PackedStringArray()}


## Adaptation points earned by staying alive from `alive_before` to `alive_after` seconds
## (one point per SURVIVAL_INTERVAL crossed). Eating earns the food's own points.
static func survival_points(alive_before: float, alive_after: float) -> int:
	if not (is_finite(alive_before) and is_finite(alive_after)) or alive_after <= alive_before:
		return 0
	return maxi(0, floori(alive_after / SURVIVAL_INTERVAL) - floori(maxf(alive_before, 0.0) / SURVIVAL_INTERVAL))


## Adds earned points to the save. Returns the points added (negative or bad amounts add nothing).
static func earn(save: SaveGame, points: int) -> int:
	if points <= 0:
		return 0
	save.adaptation_points += points
	return points


## The points a death would cost with `points` unspent: DEATH_POINT_LOSS of them, rounded down.
## The death notice shows it before apply_death takes it.
static func death_loss(points: int) -> int:
	return floori(points * DEATH_POINT_LOSS)


## Applies the death rule and records it. Returns the points lost.
static func apply_death(save: SaveGame, cause: String) -> int:
	var lost := death_loss(save.adaptation_points)
	save.adaptation_points -= lost
	save.lineage_history.append({
		"generation": save.genome.generation,
		"genome_id": save.genome.genome_id,
		"event": "died",
		"cause": cause,
		"points_lost": lost,
	})
	return lost
