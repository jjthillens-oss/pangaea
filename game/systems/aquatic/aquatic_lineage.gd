class_name AquaticLineage
extends RefCounted
## What the Aquatic stage carries over from the cell stage (aquatic plan sections 4 and 8, PROPOSED), and what it
## keeps: read() takes the lineage save and the tuning data; write() puts the stage's progress back into the save's
## aquatic block (schema v5, owner approval 2026-10-25, plan decision 2) and its points into adaptation_points.
## The era is left as it is: when the cell stage leads into the sea is plan decision 3.

const RULES_PATH := "res://game/data/aquatic/aquatic_rules.json"
const SPECIES_PATH := "res://game/data/creatures_m1.json"
## The lineage event a crawl-capable fish writes when it turns the shore down (plan section 7a): later eras read
## the last of this and ShoreLink's "came_ashore" to tell which path the lineage is on.
const STAYED_EVENT := "stayed_in_the_sea"


static func rules(path := RULES_PATH) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


## The lineage in `slot_path`. Returns {"ok", "source": "save" | "new", "errors", "writable", "lineage_id",
## "generation", "world_seed", "hue", "points", "carried_points", "cell_parts", "body", "notes", "discoveries",
## "species_seen", "aquatic", "returning", "save"}. A lineage that has swum before ("returning") comes back with its
## saved fish, generation and points; one arriving from the cell gets its body from the cell's parts and at least
## the editor's starting points. An empty slot founds an omnivore lineage that write() saves there; a slot that
## will not load gives one that is never written ("writable" false), so the player can still swim and the save is
## left as it is; "errors" then says why.
static func read(slot_path: String, aquatic_rules: Dictionary, world_seed: int) -> Dictionary:
	var catalog := PartCatalog.load_from()
	var errors := PackedStringArray()
	var save: SaveGame = null
	var source := "new"
	var writable := slot_path != ""
	if slot_path != "" and (FileAccess.file_exists(slot_path) or FileAccess.file_exists(slot_path + PersistenceService.BACKUP_SUFFIX)):
		var loaded: Dictionary = PersistenceService.new(catalog).load_from(slot_path)
		if loaded.ok:
			save = loaded.save
			source = "save"
		else:
			errors.append_array(loaded.errors)
			writable = false
	if save == null:
		var founded := Lineage.found(world_seed, BuildInfo.build_id(), catalog, "omnivore")
		if not founded.ok:
			return {"ok": false, "errors": founded.errors}
		save = founded.save
	var genome: Genome = save.genome
	var hue := float(genome.appearance.get("hue", 0.55))
	var made := AquaticBody.from_genome(genome.parts, hue, aquatic_rules.conversion)
	var start := int(aquatic_rules.editor.start_points)
	var saved: Dictionary = save.aquatic.duplicate(true)
	var returning := not saved.is_empty()
	return {
		"ok": true, "source": source, "errors": errors, "writable": writable,
		"lineage_id": save.lineage_id, "generation": int(saved.generation) if returning else genome.generation,
		"world_seed": save.world_seed, "hue": hue,
		"points": save.adaptation_points if returning else maxi(start, save.adaptation_points),
		"carried_points": save.adaptation_points,
		"cell_parts": genome.parts.map(func(p): return String(p.type)),
		"body": saved.body if returning else made.body, "notes": [] if returning else made.notes,
		"discoveries": save.discoveries.size(),
		"species_seen": species_names(),
		"aquatic": saved, "returning": returning, "save": save,
	}


## Writes the stage's progress into the lineage in `slot_path`: the save's aquatic block from `sim` and its points.
## The slot is read again first, so whatever another stage wrote since is kept. Returns OK, or why nothing was
## written (a lineage read from a slot that would not load is never written; nor is a different lineage's slot).
static func write(slot_path: String, lineage: Dictionary, sim: AquaticSim) -> Error:
	if not bool(lineage.get("writable", false)) or slot_path == "":
		return ERR_UNAVAILABLE
	var service := PersistenceService.new(PartCatalog.load_from())
	var save: SaveGame = lineage.get("save")
	if FileAccess.file_exists(slot_path) or FileAccess.file_exists(slot_path + PersistenceService.BACKUP_SUFFIX):
		var loaded: Dictionary = service.load_from(slot_path)
		if not loaded.ok:
			return ERR_FILE_CORRUPT
		save = loaded.save
	if save == null or save.lineage_id != String(lineage.lineage_id):
		return ERR_INVALID_PARAMETER
	save.aquatic = sim.to_save()
	save.adaptation_points = sim.points
	if bool(lineage.get("stayed", false)) and last_path_event(save) != STAYED_EVENT:
		save.lineage_history.append({"generation": save.genome.generation, "genome_id": save.genome.genome_id,
				"event": STAYED_EVENT})
	return service.save_to(slot_path, save)


## The last path event in the lineage's history ("stayed_in_the_sea", "came_ashore"), or "" for none.
static func last_path_event(save: SaveGame) -> String:
	for i in range(save.lineage_history.size() - 1, -1, -1):
		var e: Variant = save.lineage_history[i]
		if e is Dictionary and String(e.get("event", "")) in [STAYED_EVENT, String(ShoreLink.link("aquatic").get("event", "came_ashore"))]:
			return String(e.event)
	return ""


## The first land creature of a fish that crawls ashore (plan section 7): the creature stage's four-legged starter
## (its legs are the lobe fins), longer with the fish's length and stouter with its girth, with the fish's mouth, its
## back fin when it had one, and its colour; CreatureRules.ashore keeps the skin rule in one place.
static func to_creature(body: Dictionary, genome: Genome) -> Dictionary:
	var creature := CreatureRules.new_creature()
	var cbody: Dictionary = creature["body"]
	cbody["reference_length_mm"] = 900 + 150 * int(body.get("length", 2))
	var stout := 0.85 + 0.15 * float(body.get("girth", 1))
	for v in cbody.get("vertebrae", []):
		v["r"] = int(round(float(v.r) * stout))
	var mouth := "maw" if String(body.get("mouth", "both")) == "filter" else "jaw"
	var parts: Array = []
	for part in cbody.get("parts", []):
		match String(part.type):
			"beak":
				part["type"] = mouth
				parts.append(part)
			"horn":
				pass
			"fin":
				if int(body.get("dorsal", 0)) > 0:
					parts.append(part)
			_:
				parts.append(part)
	cbody["parts"] = parts
	cbody[CreatureRules.SKIN_COLOR_KEY] = "#" + CreatureRules.cell_skin(float(body.get("hue", 0.55))).to_html(false)
	return CreatureRules.ashore(creature, genome)


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
