class_name Lineage
extends RefCounted
## Generation changes and death for a run (Bible sections 5 and 18). Reproduction commits an
## editor session into the next generation and records it; death returns the player to the
## current generation's start without erasing the lineage.

const REPRODUCE_ENERGY_SHARE := 0.7   ## energy needed, as a share of capacity
const DEATH_POINT_LOSS := 0.25        ## approved 2026-10-22: unspent points drop by a quarter


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


static func can_reproduce(state: ActorState) -> Dictionary:
	if not state.is_alive():
		return {"ok": false, "reason": "not alive"}
	var needed := state.energy_capacity * REPRODUCE_ENERGY_SHARE
	if state.energy < needed:
		return {"ok": false, "reason": "needs %d more energy" % ceili(needed - state.energy)}
	return {"ok": true, "reason": ""}


## Commits the session into the save as the next generation. Returns {"ok", "errors"}.
## Nothing in the save changes unless the commit succeeds.
static func reproduce(save: SaveGame, session: EditorSession) -> Dictionary:
	if session.original.genome_id != save.genome.genome_id:
		return {"ok": false, "errors": PackedStringArray(["Editor session is for a different genome."])}
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


## Applies the death rule and records it. Returns the points lost.
static func apply_death(save: SaveGame, cause: String) -> int:
	var lost := floori(save.adaptation_points * DEATH_POINT_LOSS)
	save.adaptation_points -= lost
	save.lineage_history.append({
		"generation": save.genome.generation,
		"genome_id": save.genome.genome_id,
		"event": "died",
		"cause": cause,
		"points_lost": lost,
	})
	return lost
