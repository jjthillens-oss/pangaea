class_name GameSession
extends RefCounted
## One play session's save slot and running pool (M1 step 2). Main owns it; it is not an autoload.
## New lineage, continue, save and the interim death respawn all go through here, using the
## existing save schema (no new fields): energy, health, heading and the world's food are not
## saved, so Continue restarts them.
##
## There is no timed autosave. Saving happens when the player asks (pause menu, save and quit,
## the quit dialog) and once when a new lineage starts, so Continue always has a file.

const DEFAULT_SLOT := "user://saves/slot_1.json"   ## %APPDATA%\Pangaea\saves\slot_1.json on Windows
## Moving further than this since the last save counts as an unsaved change.
const DIRTY_MOVE_M := 1.0

var slot: String
var catalog: PartCatalog
var layout: PoolLayout
var persistence: PersistenceService
var sim: PoolSim
## Where the running save came from: "new", "primary" or "backup" ("" before a run starts).
var load_source := ""
## The last save attempt: {"ok", "error"} ({} before any).
var last_save := {}
## Points changed, the cell moved more than DIRTY_MOVE_M, or it died since the last save.
var dirty: bool:
	get:
		return _is_dirty()

var _saved_points := 0
var _saved_position := Vector2.ZERO
var _saved_history_size := 0


func _init(p_slot: String = DEFAULT_SLOT, layout_path: String = PoolLayout.DEFAULT_PATH) -> void:
	slot = p_slot
	catalog = PartCatalog.load_from()
	persistence = PersistenceService.new(catalog)
	layout = PoolLayout.load_from(layout_path)


## The first eight hex digits of a lineage id in two groups, for showing to the player:
## "lineage_3f9a1c07b2e84d65" -> "3F9A-1C07".
static func lineage_tag(lineage_id: String) -> String:
	var body := lineage_id.trim_prefix("lineage_").to_upper()
	if body.length() < 8:
		return body
	return "%s-%s" % [body.substr(0, 4), body.substr(4, 4)]


## What the slot holds, without writing anything:
## {"exists", "ok", "source": "primary"|"backup"|"", "summary", "errors"}. The summary (when ok) is
## {"lineage_id", "lineage_tag", "body" ("" for an evolved body), "generation",
##  "adaptation_points", "saved_at_unix", "world_seed", "genome": Genome}.
func peek_slot() -> Dictionary:
	var exists := FileAccess.file_exists(slot) or FileAccess.file_exists(slot + PersistenceService.BACKUP_SUFFIX)
	var result := {"exists": exists, "ok": false, "source": "", "summary": {}, "errors": PackedStringArray()}
	if not exists:
		return result
	var loaded := persistence.load_from(slot)
	result.ok = loaded.ok
	result.source = loaded.source
	result.errors = loaded.errors
	if loaded.ok:
		var save: SaveGame = loaded.save
		result.summary = {
			"lineage_id": save.lineage_id,
			"lineage_tag": lineage_tag(save.lineage_id),
			"body": Lineage.starting_body_of(save.genome, catalog),
			"generation": save.genome.generation,
			"adaptation_points": save.adaptation_points,
			"saved_at_unix": save.saved_at_unix,
			"world_seed": save.world_seed,
			"genome": save.genome,
		}
	return result


## Founds a lineage with a starting body, saves it to the slot and starts the pool.
## seed_value -1 picks a random non-negative seed. Returns {"ok", "errors", "saved"}: the run
## starts even when the first save fails (saved false, the reason in errors).
func start_new(body: String, seed_value: int = -1) -> Dictionary:
	var errors := layout.validate()
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "saved": false}
	if seed_value < 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		seed_value = rng.randi()
	var founded := Lineage.found(seed_value, BuildInfo.build_id(), catalog, body)
	if not founded.ok:
		return {"ok": false, "errors": founded.errors, "saved": false}
	var save: SaveGame = founded.save
	save.player["position"] = PlaneSpace.to_save(layout.spawn)
	sim = PoolSim.create(save, catalog, layout)
	load_source = "new"
	var written := _write()
	var result_errors := PackedStringArray()
	if not written.ok:
		result_errors.append(written.error)
	return {"ok": true, "errors": result_errors, "saved": written.ok}


## Loads the slot (falling back to its backup) and starts the pool. Returns {"ok", "source", "errors"};
## errors explain a fallback to the backup even when ok.
func continue_run() -> Dictionary:
	var errors := layout.validate()
	if not errors.is_empty():
		return {"ok": false, "source": "", "errors": errors}
	var loaded := persistence.load_from(slot)
	if not loaded.ok:
		return {"ok": false, "source": "", "errors": loaded.errors}
	sim = PoolSim.create(loaded.save, catalog, layout)
	load_source = loaded.source
	_mark_saved()
	return {"ok": true, "source": loaded.source, "errors": loaded.errors}


## Writes the running save to the slot. Refused while the cell is dead (the death must be
## resolved first). Returns {"ok", "error"}.
func save_now() -> Dictionary:
	if sim == null:
		last_save = {"ok": false, "error": "There is no run to save."}
	elif sim.dead:
		last_save = {"ok": false, "error": "Your cell is dead; continue before saving."}
	else:
		last_save = _write()
	return last_save


## Applies the death rule to the lineage and puts the cell back at the start. Returns the points
## lost (0 and nothing changed when the cell is not dead).
func respawn_after_death() -> int:
	if sim == null or not sim.dead:
		return 0
	var lost := Lineage.apply_death(sim.save, "starved")
	sim.respawn_player()
	return lost


func _write() -> Dictionary:
	sim.write_position_to_save()
	var err := persistence.save_to(slot, sim.save)
	if err != OK:
		return {"ok": false, "error": "Could not save to %s: %s." % [slot, error_string(err)]}
	_mark_saved()
	return {"ok": true, "error": ""}


func _mark_saved() -> void:
	_saved_points = sim.save.adaptation_points
	_saved_position = sim.motion.position
	_saved_history_size = sim.save.lineage_history.size()


func _is_dirty() -> bool:
	if sim == null:
		return false
	return sim.dead or sim.save.adaptation_points != _saved_points \
		or sim.save.lineage_history.size() != _saved_history_size \
		or sim.motion.position.distance_to(_saved_position) > DIRTY_MOVE_M
