class_name ShoreLink
extends RefCounted
## The links between eras on the save (Bible section 4, transition contract; owner "Go", 2026-10-25,
## docs/DECISIONS.md "Cell to creature link" and "One continuous game"). Plain data on a SaveGame, no files:
## EraTransition does the writes.
##
## Two links, one after the other (LINKS): the cell's pool opens on the sea (microscopic to aquatic, event
## "entered_the_sea"), and the sea's shore opens on land (aquatic to terrestrial, event "came_ashore"). cross() takes
## the link that leaves the save's era.
##
## The cell's side, the sea edge: it rises once the lineage fills its ring at the build's top size (the first
## ring_paid there). It is a world change, {"kind": "shore", "x_am", "y_am", "size"} in save.world_changes (an array
## whose elements the schema leaves to their readers), so it stays where it rose across a reload. Destination: it
## stands on a clear point near where it rose, and the offer opens only when the cell swims into its reach. Choice:
## the player swims out or stays in the pool, as often as they like. The Aquatic stage owns the shore's side.
##
## Crossing writes the next era, the link's lineage event and, onto land, the lineage's first creature, carrying the
## lineage id, genome, history, points, discoveries and world seed over unchanged. Into the sea the aquatic block
## stays as it is (empty for a cell), so AquaticLineage builds the first fish from the cell's parts.

const KIND := "shore"
## The cell's era, whose pool the sea edge rises in, and the era it opens on.
const FROM_ERA := "microscopic"
const TO_ERA := "aquatic"
## from era -> {"to", "event"}.
const LINKS := {
	"microscopic": {"to": "aquatic", "event": "entered_the_sea"},
	"aquatic": {"to": "terrestrial", "event": "came_ashore"},
}
## How far ahead of the cell the shore rises (tm at the size it rose): inside the 3 x 3 chunks round the cell
## (32 tm each), so the clear point is found among the colliders that are loaded.
const RISE_AHEAD_TM := 20.0
## The way it rises: plane -y, up the screen, as the camera always looks north.
const RISE_DIRECTION := Vector2(0.0, -1.0)
## The offer opens within this many tm of the shore's centre, and after "Stay in the water" opens again only once
## the cell has been out past REOPEN_SHARE of that.
const REACH_TM := 4.0
const REOPEN_SHARE := 1.5


## The shore's world change, or {} before it has risen.
static func shore_of(save: SaveGame) -> Dictionary:
	for change in save.world_changes:
		if change is Dictionary and change.get("kind") == KIND:
			return change
	return {}


## The link out of `from_era`: {"to", "event", "checkpoint_suffix"}, or {} for an era with no way on yet.
static func link(from_era: String) -> Dictionary:
	if not LINKS.has(from_era):
		return {}
	var l: Dictionary = LINKS[from_era]
	return {"to": l.to, "event": l.event, "checkpoint_suffix": ".pre-" + str(l.to)}


## Whether the lineage is still a cell, so its sea edge may rise and be crossed.
static func in_water(save: SaveGame) -> bool:
	return save.era == FROM_ERA


## Whether the save's era has a link out of it.
static func can_cross(save: SaveGame) -> bool:
	return LINKS.has(save.era)


## Records the shore at (x_am, y_am), risen at size `n`, once: false (and nothing changed) when one has risen
## already or the lineage is ashore.
static func raise(save: SaveGame, x_am: float, y_am: float, n: int) -> bool:
	if not in_water(save) or not shore_of(save).is_empty():
		return false
	save.world_changes.append({"kind": KIND, "x_am": x_am, "y_am": y_am, "size": n})
	return true


## The shore's centre in absolute am, or an empty array before it has risen.
static func point_am(save: SaveGame) -> PackedFloat64Array:
	var s := shore_of(save)
	if s.is_empty():
		return PackedFloat64Array()
	return PackedFloat64Array([float(s.get("x_am", 0.0)), float(s.get("y_am", 0.0))])


## The cell's distance to the shore in am, INF before it has risen.
static func distance_am(save: SaveGame, cell_am: PackedFloat64Array) -> float:
	var p := point_am(save)
	if p.is_empty() or cell_am.size() < 2:
		return INF
	return Vector2(cell_am[0] - p[0], cell_am[1] - p[1]).length()


## Whether a cell `d_am` from the shore at size `n` is in its reach.
static func in_reach(d_am: float, n: int) -> bool:
	return d_am <= REACH_TM * WorldConfig.tm_to_am(n)


## Whether a cell that stayed in the water has swum far enough out for the offer to open again.
static func out_of_reach(d_am: float, n: int) -> bool:
	return d_am > REACH_TM * REOPEN_SHARE * WorldConfig.tm_to_am(n)


## The lineage event the crossing out of the save's era appends: the generation and genome that crossed.
static func event_of(save: SaveGame) -> Dictionary:
	return {"generation": save.genome.generation, "genome_id": save.genome.genome_id,
		"event": str(link(save.era).get("event", ""))}


## Moves the save across the link out of its era in memory: era, the lineage event and, when `payload` has one, its
## "creature" (onto land, the lineage's first creature). Returns what it replaced, for undo() when the write fails;
## {} (and nothing changed) when the era has no link out.
static func cross(save: SaveGame, payload := {}) -> Dictionary:
	if not can_cross(save):
		return {}
	var before := {"era": save.era, "history_size": save.lineage_history.size(), "creature": save.creature}
	save.lineage_history.append(event_of(save))
	save.era = str(link(save.era).to)
	if payload.has("creature"):
		save.creature = (payload.creature as Dictionary).duplicate(true)
	return before


## Puts back what cross() replaced.
static func undo(save: SaveGame, before: Dictionary) -> void:
	if before.is_empty():
		return
	save.era = String(before["era"])
	save.lineage_history.resize(int(before["history_size"]))
	save.creature = before["creature"]
