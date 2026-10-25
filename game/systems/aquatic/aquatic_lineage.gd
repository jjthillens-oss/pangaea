class_name AquaticLineage
extends RefCounted
## What the Aquatic stage carries over from the cell stage (aquatic plan sections 4 and 8, PROPOSED): reads the
## lineage save and the tuning data, never writes either. Saving the aquatic stage waits for the owner's OK on a save
## schema change (plan decision 2), so the slice keeps its own progress in memory only.

const RULES_PATH := "res://game/data/aquatic/aquatic_rules.json"
const SPECIES_PATH := "res://game/data/creatures_m1.json"


static func rules(path := RULES_PATH) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


## The lineage in `slot_path`, read-only. Returns {"ok", "source": "save" | "new", "errors", "lineage_id",
## "generation", "world_seed", "hue", "points", "cell_parts", "body", "notes", "discoveries", "species_seen"}.
## A slot with no save (or one that will not load) gives a fresh omnivore lineage that is never written, so a
## player can always try the stage; "errors" then says why.
static func read(slot_path: String, aquatic_rules: Dictionary, world_seed: int) -> Dictionary:
	var catalog := PartCatalog.load_from()
	var errors := PackedStringArray()
	var save: SaveGame = null
	var source := "new"
	if slot_path != "" and (FileAccess.file_exists(slot_path) or FileAccess.file_exists(slot_path + PersistenceService.BACKUP_SUFFIX)):
		var loaded: Dictionary = PersistenceService.new(catalog).load_from(slot_path)
		if loaded.ok:
			save = loaded.save
			source = "save"
		else:
			errors.append_array(loaded.errors)
	if save == null:
		var founded := Lineage.found(world_seed, BuildInfo.build_id(), catalog, "omnivore")
		if not founded.ok:
			return {"ok": false, "errors": founded.errors}
		save = founded.save
	var genome: Genome = save.genome
	var hue := float(genome.appearance.get("hue", 0.55))
	var made := AquaticBody.from_genome(genome.parts, hue, aquatic_rules.conversion)
	var start := int(aquatic_rules.editor.start_points)
	return {
		"ok": true, "source": source, "errors": errors,
		"lineage_id": save.lineage_id, "generation": genome.generation, "world_seed": save.world_seed,
		"hue": hue, "points": maxi(start, save.adaptation_points), "carried_points": save.adaptation_points,
		"cell_parts": genome.parts.map(func(p): return String(p.type)),
		"body": made.body, "notes": made.notes,
		"discoveries": save.discoveries.size(),
		"species_seen": species_names(),
	}


## The cell stage's species, by name, as the entry card remembers them: the microscopic world is history, not
## deleted (Bible §6).
static func species_names() -> PackedStringArray:
	var out := PackedStringArray()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SPECIES_PATH))
	if data is Dictionary and data.get("species") is Dictionary:
		var ids: Array = (data.species as Dictionary).keys()
		ids.sort()
		for id in ids:
			out.append(String(data.species[id].get("name", id)))
	return out
