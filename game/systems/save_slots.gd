class_name SaveSlots
extends RefCounted
## The save slots the title screen offers (UI pass): COUNT files,
## user://saves/slot_1.json to slot_3.json. Slot 1 is the slot every earlier build used
## (GameSession.DEFAULT_SLOT), so an existing lineage shows up there. Each file keeps the usual
## backup and safe writes (PersistenceService); the save schema is unchanged.

const COUNT := 3

## Where the slot files live. Tests point it elsewhere so they never touch the player's saves.
static var folder := "user://saves"


## Slot n's file (n from 1 to COUNT, clamped). Slot 1 is GameSession.DEFAULT_SLOT.
static func path(n: int) -> String:
	return folder.path_join("slot_%d.json" % clampi(n, 1, COUNT))


## The slot number of a path, or 0 when it is not one of the slots (a --slot file, a smoke slot).
static func number_of(slot_path: String) -> int:
	for n in range(1, COUNT + 1):
		if path(n) == slot_path:
			return n
	return 0


## Every slot's summary, in order: GameSession.peek_slot() plus "slot" (1-based) and "path".
## Reading never writes.
static func peek_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in range(1, COUNT + 1):
		out.append(peek(n))
	return out


static func peek(n: int) -> Dictionary:
	var slot_path := path(n)
	# A pool-only session with no creatures: reading a summary needs neither.
	var session := GameSession.new(slot_path, PoolLayout.DEFAULT_PATH, "")
	var result := session.peek_slot()
	result.slot = n
	result.path = slot_path
	return result


## Deletes a slot's save and its backup (and a temporary file left by an interrupted write). Files
## set aside as unreadable (.corrupt-*) are left for the player to look at. Returns the first error.
static func delete(slot_path: String) -> Error:
	var first := OK
	for file in [slot_path, slot_path + PersistenceService.BACKUP_SUFFIX, slot_path + PersistenceService.TEMP_SUFFIX]:
		if FileAccess.file_exists(file):
			var err := DirAccess.remove_absolute(file)
			if err != OK and first == OK:
				first = err
	return first
