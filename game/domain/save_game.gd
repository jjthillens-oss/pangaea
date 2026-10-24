class_name SaveGame
extends RefCounted
## One run's persistent state, schema version 3 (Bible section 18).
## v2 (M1) adds adaptation_points; v3 (the creature stage) adds the creature; see SaveMigrations for the
## steps. Plain data plus validation. File handling, migration and recovery live in PersistenceService.
##
## The creature (v3): {} until the lineage enters the creature stage, then {"name": String, "body":
## Dictionary (the body codec's dictionary, extra keys such as the editor's skin_color included),
## "generation": int >= 1, "history": Array}. Its points are adaptation_points: one lineage, one pool
## of points, carried between the cell pool and the creature stage. The body's rules (the body rules
## and the part rules) are data a service loads, so validate() takes them as an optional Callable
## (body Dictionary -> PackedStringArray of problems); without one the creature's types are still
## checked. A body that breaks the rules fails to load with the reasons, like an invalid genome: parts
## are never dropped.

const SCHEMA_VERSION := 3
## 2^53: save files keep numbers as doubles, which hold whole numbers exactly only up to here.
const MAX_WORLD_SEED := 9007199254740992
## Era ids are PROPOSED names from Bible section 4.
const ERAS: PackedStringArray = ["microscopic", "aquatic", "terrestrial", "social", "tribal", "civilization", "interstellar"]

var build_id: String = ""
var world_seed: int = 0
var lineage_id: String = ""
var era: String = "microscopic"
var genome: Genome
## Unspent adaptation points, earned by eating and surviving, spent in the editor.
var adaptation_points: int = 0
## The creature stage's creature (see above), {} before the lineage has one.
var creature: Dictionary = {}
## Ordered events: {"generation": int, "genome_id": String, "event": String}
var lineage_history: Array = []
var discoveries: Array = []
var relationships: Array = []
var settlements: Array = []
var world_changes: Array = []
var player: Dictionary = {"position": [0.0, 0.0, 0.0]}
var pending_transactions: Array = []
var saved_at_unix: int = 0
## Type problems found by from_dict (not saved). validate() reports them.
var load_problems: Array = []


static func new_run(seed: int, p_build_id: String) -> SaveGame:
	var save := SaveGame.new()
	save.world_seed = seed
	save.build_id = p_build_id
	save.lineage_id = StableId.generate("lineage")
	save.genome = Genome.create(save.lineage_id)
	save.lineage_history.append({"generation": 1, "genome_id": save.genome.genome_id, "event": "founded"})
	return save


func validate(catalog: PartCatalog, creature_body_rules: Callable = Callable()) -> PackedStringArray:
	var errors := PackedStringArray(load_problems)
	if not StableId.is_valid(lineage_id, "lineage"):
		errors.append("Save has an invalid lineage id '%s'." % lineage_id)
	if not ERAS.has(era):
		errors.append("Unknown era '%s'." % era)
	if adaptation_points < 0:
		errors.append("Adaptation points must not be negative.")
	if world_seed < 0:
		errors.append("World seed must not be negative.")
	elif world_seed > MAX_WORLD_SEED:
		errors.append("World seed %d is above %d, the largest a save file keeps exactly." % [world_seed, MAX_WORLD_SEED])
	if genome == null:
		errors.append("Save has no genome.")
	else:
		if genome.lineage_id != lineage_id:
			errors.append("Genome belongs to lineage '%s', not '%s'." % [genome.lineage_id, lineage_id])
		errors.append_array(genome.validate(catalog))
	if lineage_history.is_empty():
		errors.append("Lineage history is empty; it must at least record the founding.")
	var pos = player.get("position")
	if not (pos is Array and pos.size() == 3):
		errors.append("Player position must be three numbers.")
	errors.append_array(validate_creature(creature, creature_body_rules))
	return errors


## Every problem with a creature dictionary: {} is fine (no creature yet); otherwise the four keys with
## their types, generation 1 or higher, a name that is not blank, then the body against `body_rules`
## when one is given (a Callable taking the body Dictionary and returning its problems).
static func validate_creature(data: Dictionary, body_rules: Callable = Callable()) -> PackedStringArray:
	var errors := PackedStringArray()
	if data.is_empty():
		return errors
	var problems := []
	var creature_name := JsonValues.text(data, "name", problems)
	var body := JsonValues.dict(data, "body", problems)
	var generation := JsonValues.whole(data, "generation", problems)
	JsonValues.array(data, "history", problems)
	for problem in problems:
		errors.append("Creature: %s" % problem)
	if not errors.is_empty():
		return errors
	if creature_name.strip_edges().is_empty():
		errors.append("Creature: the name is blank.")
	if generation < 1:
		errors.append("Creature: generation must be 1 or higher, got %d." % generation)
	if body_rules.is_valid():
		for problem in body_rules.call(body):
			errors.append("Creature body: %s" % problem)
	return errors


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"build_id": build_id,
		"world_seed": world_seed,
		"lineage_id": lineage_id,
		"era": era,
		"genome": genome.to_dict() if genome else {},
		"adaptation_points": adaptation_points,
		"creature": creature.duplicate(true),
		"lineage_history": lineage_history.duplicate(true),
		"discoveries": discoveries.duplicate(true),
		"relationships": relationships.duplicate(true),
		"settlements": settlements.duplicate(true),
		"world_changes": world_changes.duplicate(true),
		"player": player.duplicate(true),
		"pending_transactions": pending_transactions.duplicate(true),
		"saved_at_unix": saved_at_unix,
	}


## Expects data already migrated to SCHEMA_VERSION. Fields of the wrong type are recorded in
## load_problems and reported by validate(); nothing is dropped silently.
static func from_dict(data: Dictionary) -> SaveGame:
	var save := SaveGame.new()
	var problems := save.load_problems
	save.build_id = JsonValues.text(data, "build_id", problems)
	save.world_seed = JsonValues.whole(data, "world_seed", problems)
	save.lineage_id = JsonValues.text(data, "lineage_id", problems)
	save.era = JsonValues.text(data, "era", problems)
	var genome_data = data.get("genome")
	save.genome = Genome.from_dict(genome_data) if genome_data is Dictionary else null
	save.adaptation_points = JsonValues.whole(data, "adaptation_points", problems)
	save.creature = JsonValues.dict(data, "creature", problems)
	# JSON reads every number as a float; the creature's generation is a whole number in memory.
	var generation = save.creature.get("generation")
	if generation is float and is_finite(generation) and generation == floorf(generation):
		save.creature["generation"] = int(generation)
	save.lineage_history = JsonValues.array(data, "lineage_history", problems)
	save.discoveries = JsonValues.array(data, "discoveries", problems)
	save.relationships = JsonValues.array(data, "relationships", problems)
	save.settlements = JsonValues.array(data, "settlements", problems)
	save.world_changes = JsonValues.array(data, "world_changes", problems)
	save.player = JsonValues.dict(data, "player", problems)
	save.pending_transactions = JsonValues.array(data, "pending_transactions", problems)
	save.saved_at_unix = JsonValues.whole(data, "saved_at_unix", problems)
	return save
