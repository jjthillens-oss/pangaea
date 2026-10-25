class_name EraTransition
extends RefCounted
## A crossing between eras as a save transaction (Bible section 18: "Era changes are transactions with
## pre-transition checkpoints"; section 4: save before transition, keep the prior save as a recoverable checkpoint).
## ShoreLink holds the links and their rules; this writes the files, through PersistenceService's own safe writes.
##
## cross(), in order: (1) the slot is written as it stands, at the edge of its era; (2) that save is written again
## as the checkpoint, <slot>.pre-<next era> (.pre-aquatic out of the pool, .pre-terrestrial onto land); (3) the save
## crosses in memory (ShoreLink.cross) and the slot is written. A failure at (1) or (2) changes nothing in memory; one
## at (3) undoes the move in memory, and the slot still holds (1). An interruption anywhere leaves the slot loadable,
## so the safe equivalent of a pending transaction is the order of the writes and nothing is put in
## pending_transactions.
##
## restore() brings a checkpoint back as the slot (the slot's own save becomes its .bak, as every write does), so a
## lineage can go back across the link it last crossed; the checkpoint stays.

## Every era a crossing leads to, so every checkpoint a slot can have.
static func checkpoint_eras() -> PackedStringArray:
	var out := PackedStringArray()
	for from_era: String in ShoreLink.LINKS:
		out.append(str(ShoreLink.LINKS[from_era].to))
	return out


## The checkpoint kept when the lineage on `slot` crossed into `to_era`.
static func checkpoint_path(slot: String, to_era: String) -> String:
	return slot + ".pre-" + to_era


static func has_checkpoint(slot: String, to_era: String) -> bool:
	return FileAccess.file_exists(checkpoint_path(slot, to_era)) or FileAccess.file_exists(
			checkpoint_path(slot, to_era) + PersistenceService.BACKUP_SUFFIX)


## Crosses `save` across the link out of its era and writes it; `payload` is ShoreLink.cross's (onto land,
## {"creature": the lineage's first creature}). Out of the pool the cell's sea edge must have risen.
## Returns {"ok", "errors", "checkpoint"}: the checkpoint's path once it is written, else "".
static func cross(save: SaveGame, slot: String, persistence: PersistenceService, payload := {}) -> Dictionary:
	var out := {"ok": false, "errors": PackedStringArray(), "checkpoint": ""}
	if not ShoreLink.can_cross(save):
		out.errors.append("The lineage's era '%s' has no way on yet." % save.era)
		return out
	if ShoreLink.in_water(save) and ShoreLink.shore_of(save).is_empty():
		out.errors.append("The sea has not opened for this lineage yet.")
		return out
	var to_era := str(ShoreLink.link(save.era).to)
	var err := persistence.save_to(slot, save)
	if err != OK:
		out.errors.append("Could not save before crossing: %s." % error_string(err))
		return out
	var cp := checkpoint_path(slot, to_era)
	err = persistence.save_to(cp, save)
	if err != OK:
		out.errors.append("Could not keep the checkpoint %s: %s." % [cp, error_string(err)])
		return out
	out.checkpoint = cp
	var before := ShoreLink.cross(save, payload)
	err = persistence.save_to(slot, save)
	if err != OK:
		ShoreLink.undo(save, before)
		out.errors.append("Could not save the lineage in its new era: %s." % error_string(err))
		return out
	out.ok = true
	return out


## Writes the checkpoint from before the lineage crossed into `to_era` back as the slot, when it belongs to
## `lineage_id` (the slot's lineage; "" skips the check, so a slot that will not load can still go back). Returns
## {"ok", "errors", "save"}.
static func restore(slot: String, persistence: PersistenceService, to_era: String, lineage_id := "") -> Dictionary:
	var out := {"ok": false, "errors": PackedStringArray(), "save": null}
	if not has_checkpoint(slot, to_era):
		out.errors.append("This slot has no checkpoint from before its lineage reached the %s era." % to_era)
		return out
	var loaded := persistence.load_from(checkpoint_path(slot, to_era))
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


## Every checkpoint file of `slot`, with their backup and temporary files.
static func checkpoint_files(slot: String) -> PackedStringArray:
	var out := PackedStringArray()
	for to_era in checkpoint_eras():
		var cp := checkpoint_path(slot, to_era)
		out.append_array([cp, cp + PersistenceService.BACKUP_SUFFIX, cp + PersistenceService.TEMP_SUFFIX])
	return out


## Removes every checkpoint with its backup and temporary files (a slot deleted or founded anew).
static func forget(slot: String) -> void:
	for path in checkpoint_files(slot):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
