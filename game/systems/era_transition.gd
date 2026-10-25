class_name EraTransition
extends RefCounted
## The cell-to-creature crossing as a save transaction (Bible section 18: "Era changes are transactions with
## pre-transition checkpoints"; section 4: save before transition, keep the prior save as a recoverable checkpoint).
## ShoreLink holds the rules; this writes the files, through PersistenceService's own safe writes.
##
## cross(), in order: (1) the slot is written as it stands, the cell at the shore; (2) that save is written again
## as the checkpoint, <slot>.pre-terrestrial; (3) the save moves ashore in memory (ShoreLink.cross) and the slot is
## written. A failure at (1) or (2) changes nothing in memory; one at (3) undoes the move in memory, and the slot
## still holds (1). An interruption anywhere leaves the slot loadable, so the safe equivalent of a pending
## transaction is the order of the writes and nothing is put in pending_transactions.
##
## restore() brings the checkpoint back as the slot (the slot's own save becomes its .bak, as every write does), so
## a lineage that came ashore can go back to the water; the checkpoint stays.

const CHECKPOINT_SUFFIX := ".pre-terrestrial"


static func checkpoint_path(slot: String) -> String:
	return slot + CHECKPOINT_SUFFIX


static func has_checkpoint(slot: String) -> bool:
	return FileAccess.file_exists(checkpoint_path(slot)) or FileAccess.file_exists(
			checkpoint_path(slot) + PersistenceService.BACKUP_SUFFIX)


## Crosses `save` ashore with `creature` as the lineage's first creature (CreatureRules.from_cell) and writes it.
## Returns {"ok", "errors", "checkpoint"}: the checkpoint's path once it is written, else "".
static func cross(save: SaveGame, slot: String, persistence: PersistenceService, creature: Dictionary) -> Dictionary:
	var out := {"ok": false, "errors": PackedStringArray(), "checkpoint": ""}
	if not ShoreLink.in_water(save):
		out.errors.append("The lineage is already ashore (era '%s')." % save.era)
		return out
	if ShoreLink.shore_of(save).is_empty():
		out.errors.append("No shore has risen for this lineage yet.")
		return out
	var err := persistence.save_to(slot, save)
	if err != OK:
		out.errors.append("Could not save before going ashore: %s." % error_string(err))
		return out
	var cp := checkpoint_path(slot)
	err = persistence.save_to(cp, save)
	if err != OK:
		out.errors.append("Could not keep the checkpoint %s: %s." % [cp, error_string(err)])
		return out
	out.checkpoint = cp
	var before := ShoreLink.cross(save, creature)
	err = persistence.save_to(slot, save)
	if err != OK:
		ShoreLink.undo(save, before)
		out.errors.append("Could not save the lineage ashore: %s." % error_string(err))
		return out
	out.ok = true
	return out


## Writes the checkpoint back as the slot, when it belongs to `lineage_id` (the slot's lineage; "" skips the check, so
## a slot that will not load can still go back). Returns {"ok", "errors", "save"}.
static func restore(slot: String, persistence: PersistenceService, lineage_id := "") -> Dictionary:
	var out := {"ok": false, "errors": PackedStringArray(), "save": null}
	if not has_checkpoint(slot):
		out.errors.append("This slot has no checkpoint from before it came ashore.")
		return out
	var loaded := persistence.load_from(checkpoint_path(slot))
	if not loaded.ok:
		out.errors = loaded.errors
		return out
	var save: SaveGame = loaded.save
	if not lineage_id.is_empty() and save.lineage_id != lineage_id:
		out.errors.append("The checkpoint belongs to another lineage (%s)." % save.lineage_id)
		return out
	var err := persistence.save_to(slot, save)
	if err != OK:
		out.errors.append("Could not write the checkpoint back: %s." % error_string(err))
		return out
	out.ok = true
	out.save = save
	return out


## Removes the checkpoint with its backup and temporary files (a slot deleted or founded anew).
static func forget(slot: String) -> void:
	var cp := checkpoint_path(slot)
	for path in [cp, cp + PersistenceService.BACKUP_SUFFIX, cp + PersistenceService.TEMP_SUFFIX]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
