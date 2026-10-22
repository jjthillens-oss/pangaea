class_name SaveGame
extends RefCounted
## One run's persistent state, schema version 2 (Bible section 18).
## v2 (M1) adds adaptation_points; see SaveMigrations for the v1 -> v2 step. Plain data plus validation.
## File handling, migration and recovery live in PersistenceService.

const SCHEMA_VERSION := 2
## Era ids are PROPOSED names from Bible section 4.
const ERAS: PackedStringArray = ["microscopic", "aquatic", "terrestrial", "social", "tribal", "civilization", "interstellar"]

var build_id: String = ""
var world_seed: int = 0
var lineage_id: String = ""
var era: String = "microscopic"
var genome: Genome
## Unspent adaptation points, earned by eating and surviving, spent in the editor.
var adaptation_points: int = 0
## Ordered events: {"generation": int, "genome_id": String, "event": String}
var lineage_history: Array = []
var discoveries: Array = []
var relationships: Array = []
var settlements: Array = []
var world_changes: Array = []
var player: Dictionary = {"position": [0.0, 0.0, 0.0]}
var pending_transactions: Array = []
var saved_at_unix: int = 0


static func new_run(seed: int, p_build_id: String) -> SaveGame:
	var save := SaveGame.new()
	save.world_seed = seed
	save.build_id = p_build_id
	save.lineage_id = StableId.generate("lineage")
	save.genome = Genome.create(save.lineage_id)
	save.lineage_history.append({"generation": 1, "genome_id": save.genome.genome_id, "event": "founded"})
	return save


func validate(catalog: PartCatalog) -> PackedStringArray:
	var errors := PackedStringArray()
	if not StableId.is_valid(lineage_id, "lineage"):
		errors.append("Save has an invalid lineage id '%s'." % lineage_id)
	if not ERAS.has(era):
		errors.append("Unknown era '%s'." % era)
	if adaptation_points < 0:
		errors.append("Adaptation points must not be negative.")
	if world_seed < 0:
		errors.append("World seed must not be negative.")
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
		"lineage_history": lineage_history.duplicate(true),
		"discoveries": discoveries.duplicate(true),
		"relationships": relationships.duplicate(true),
		"settlements": settlements.duplicate(true),
		"world_changes": world_changes.duplicate(true),
		"player": player.duplicate(true),
		"pending_transactions": pending_transactions.duplicate(true),
		"saved_at_unix": saved_at_unix,
	}


## Expects data already migrated to SCHEMA_VERSION.
static func from_dict(data: Dictionary) -> SaveGame:
	var save := SaveGame.new()
	save.build_id = str(data.get("build_id", ""))
	save.world_seed = JsonValues.whole(data.get("world_seed"), -1)
	save.lineage_id = str(data.get("lineage_id", ""))
	save.era = str(data.get("era", ""))
	var genome_data = data.get("genome")
	save.genome = Genome.from_dict(genome_data) if genome_data is Dictionary else null
	save.adaptation_points = JsonValues.whole(data.get("adaptation_points"), -1)
	save.lineage_history = JsonValues.array(data.get("lineage_history"))
	save.discoveries = JsonValues.array(data.get("discoveries"))
	save.relationships = JsonValues.array(data.get("relationships"))
	save.settlements = JsonValues.array(data.get("settlements"))
	save.world_changes = JsonValues.array(data.get("world_changes"))
	save.player = JsonValues.dict(data.get("player"))
	save.pending_transactions = JsonValues.array(data.get("pending_transactions"))
	save.saved_at_unix = JsonValues.whole(data.get("saved_at_unix"), 0)
	return save

