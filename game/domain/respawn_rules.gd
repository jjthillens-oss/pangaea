class_name RespawnRules
extends RefCounted
## The fairness math of a checkpoint respawn (M1 step 3, plan section 13): the death streak, the
## per-streak table pick (shelter seconds and the energy share), the creatures to send home from
## around the checkpoint and the lineage history's cause string. Pure, so PoolSim, the tests and
## the dev panel share one rule.
##
## The numbers live in the species data's "fairness" block (grace_s 5/8/10, respawn_energy_share
## 0.6/0.8/1.0, streak_window_s 90, respawn_clear_m 12); these functions only read them.


## The streak after a death that came `alive_ticks` after the last respawn (or the run's start).
## A death within the window grows it by one; a life of at least the window starts it again at 1,
## so the first death is always 1. A long life is the reward, so the boundary belongs to it: exactly
## the window resets the streak.
static func streak_after(prev_streak: int, alive_ticks: int, window_ticks: int) -> int:
	if alive_ticks < window_ticks:
		return maxi(prev_streak, 0) + 1
	return 1


## The table's value for a streak: entry 1 for the first death, and the last entry for every
## streak past the table's end (a long losing run keeps the most help). An empty table gives 0.
static func pick(table: Array, streak: int) -> float:
	if table.is_empty():
		return 0.0
	return float(table[clampi(streak, 1, table.size()) - 1])


## The ids of the live bodies within `clear_m` of the checkpoint, the edge included, sorted by id
## so the respawn's relocations and its `respawned.relocated` list are deterministic. Bodies use the
## senses' format ({id, position, alive, ...}); a body with alive false is skipped, and one with no
## alive key counts as live.
static func to_relocate(checkpoint: Vector2, clear_m: float, bodies: Array) -> PackedStringArray:
	var ids: Array[String] = []
	for body: Dictionary in bodies:
		if not bool(body.get("alive", true)):
			continue
		var p: Vector2 = body.position
		if p.distance_to(checkpoint) <= clear_m:
			ids.append(String(body.id))
	ids.sort()
	return PackedStringArray(ids)


## The lineage history's cause for a death record ({cause, by, by_species, reason}): "starved",
## or "killed:<species id>" for a creature's kill (D18). A kill with no species (a debug kill) is
## plain "killed"; any other cause is kept as written. A record without a cause is step 2's only
## death, starving.
static func death_cause(death: Dictionary) -> String:
	var cause := String(death.get("cause", "starved"))
	if cause != "killed":
		return cause
	var species := String(death.get("by_species", ""))
	if species.is_empty():
		return cause
	return "killed:" + species
