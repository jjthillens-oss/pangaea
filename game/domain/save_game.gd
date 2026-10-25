class_name SaveGame
extends RefCounted
## One run's persistent state, schema version 5 (Bible section 18, plan E). Plain data plus
## validation; file handling, migration and recovery live in PersistenceService, and SaveMigrations
## holds each step (v1 -> v2 adds adaptation_points; v2 -> v3 adds the creature; v3 -> v4 is
## exact, S2; v4 -> v5 adds the aquatic stage).
##
## v4 (S2) adds the cell's size and growth meter, the checkpoint (absolute am in float64, heading,
## size) and gen_version, and step 4's fields with their defaults, so S4 adds none: spawn (null =
## the checkpoint) and the player's energy and health (null = fresh). A discovery is
## {type, id, size}. Every key is checked: a missing or an unknown one is a load problem, so a
## damaged or foreign file falls back to the backup instead of loading with data dropped. S2 was
## built as v3 while the creature stage took v3 on main (2026-10-24), so v4 is both, and a v3 file
## written by either preview build migrates (SaveMigrations.v3_to_v4).
##
## The creature (v3): {} until the lineage enters the creature stage, then {"name": String, "body":
## Dictionary (the body codec's dictionary, extra keys such as the editor's skin_color included),
## "generation": int >= 1, "history": Array}. Its points are adaptation_points: one lineage, one
## pool of points, carried between the cell pool and the creature stage. The body's rules (the body
## rules and the part rules) are data a service loads, so validate() takes them as an optional
## Callable (body Dictionary -> PackedStringArray of problems); without one the creature's types are
## still checked. A body that breaks the rules fails to load with the reasons, like an invalid
## genome: parts are never dropped.
##
## The aquatic stage (v5, owner approval 2026-10-25, docs/stages/aquatic-plan.md decision 2): {} until the lineage
## swims in the Aquatic stage, then {"body": the AquaticBody dictionary, "generation": int >= 1, "history": Array,
## "discovered": Array of zone and site ids, "relations": {species: {"standing", "rapport"}}, "meals": int >= 0,
## "position": [x, y, z], "heading": number, "energy" and "health": numbers >= 0}. Its points are adaptation_points,
## as the creature's are. validate() takes the body's rules as an optional Callable, as for the creature.
##
## v4 was frozen once S2 shipped (build plan BP-18): no key is added or changed after that; a later need is
## v5, with its own migration and fixture. The genome's appearance stays a free dictionary (S4's
## membrane lives there). The growth trigger, reduce motion, hints and the giant pass are not in a
## save (SettingsService and UserSettings). A build older than S2 refuses a v4 save as newer.

const SCHEMA_VERSION := 5
## 2^53: save files keep numbers as doubles, which hold whole numbers exactly only up to here.
const MAX_WORLD_SEED := 9007199254740992
## Era ids are PROPOSED names from Bible section 4.
const ERAS: PackedStringArray = ["microscopic", "aquatic", "terrestrial", "social", "tribal", "civilization", "interstellar"]
## The sizes a save may name: the whole ladder (plan B.1), whatever the top of the build reading it.
const MIN_SIZE := 1
const MAX_SIZE := 10
## A rare place's kind, a landmark's model, or a food look whose lump is paid (D-33).
const DISCOVERY_TYPES: PackedStringArray = ["place", "landmark", "food"]
## The keys of a v5 save, and of each object v4 or v5 adds or changes, sorted.
const KEYS: PackedStringArray = ["adaptation_points", "aquatic", "build_id", "checkpoint", "creature", "discoveries", "era",
	"gen_version", "genome", "growth", "lineage_history", "lineage_id", "pending_transactions", "player", "relationships",
	"saved_at_unix", "schema_version", "settlements", "spawn", "world_changes", "world_seed"]
const PLAYER_KEYS: PackedStringArray = ["energy", "health", "position"]
const GROWTH_KEYS: PackedStringArray = ["meter", "size"]
const CHECKPOINT_KEYS: PackedStringArray = ["heading", "size", "x_am", "y_am"]
const SPAWN_KEYS: PackedStringArray = ["heading", "x_am", "y_am"]
const DISCOVERY_KEYS: PackedStringArray = ["id", "size", "type"]
const AQUATIC_KEYS: PackedStringArray = ["body", "discovered", "energy", "generation", "health", "heading", "history", "meals",
	"position", "relations"]
const AQUATIC_STANDINGS: PackedStringArray = ["neutral", "friend", "foe"]

var build_id: String = ""
var world_seed: int = 0
var lineage_id: String = ""
var era: String = "microscopic"
var genome: Genome
## Unspent adaptation points, earned by eating and surviving, spent in the editor.
var adaptation_points: int = 0
## The creature stage's creature (see above), {} before the lineage has one.
var creature: Dictionary = {}
## The aquatic stage's state (v5): {} until the lineage swims there. See the header.
var aquatic: Dictionary = {}
## Ordered events: {"generation": int, "genome_id": String, "event": String}
var lineage_history: Array = []
## What this lineage has found, in find order: {"type": DISCOVERY_TYPES, "id": String, "size": int}.
var discoveries: Array = []
var relationships: Array = []
var settlements: Array = []
var world_changes: Array = []
## position: three numbers (absolute am in endless). energy, health: null = fresh (S4 fills them).
var player: Dictionary = {"position": [0.0, 0.0, 0.0], "energy": null, "health": null}
var pending_transactions: Array = []
## The cell's size and how full its growth ring is. A new lineage starts at size 1, empty.
var growth: Dictionary = {"size": 1, "meter": 0.0}
## Where the cell comes back after a death: absolute am, heading, and the size it was set at. The
## default is the home spawn (pool_m1.json's (0, 9) facing -1.5708; the home block sits at the origin).
var checkpoint: Dictionary = {"x_am": 0.0, "y_am": 9.0, "heading": -1.5708, "size": 1}
## The spawning spot, {x_am, y_am, heading} (S4). null means the checkpoint, all S2 and S3 write.
var spawn = null
## The world generator this run was saved under; a different one regenerates the world (plan E).
var gen_version: int = 1
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


func validate(catalog: PartCatalog, creature_body_rules: Callable = Callable(), aquatic_body_rules: Callable = Callable()) -> PackedStringArray:
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
	errors.append_array(_key_problems("player", player, PLAYER_KEYS))
	for key in ["energy", "health"]:
		var value = player.get(key)
		if value != null and not (_is_number(value) and value >= 0.0):
			errors.append("Field 'player.%s' must be null or a finite number of at least 0." % key)
	errors.append_array(_growth_problems())
	errors.append_array(_place_problems("checkpoint", checkpoint, CHECKPOINT_KEYS))
	if spawn != null:
		if spawn is Dictionary:
			errors.append_array(_place_problems("spawn", spawn, SPAWN_KEYS))
		else:
			errors.append("Field 'spawn' must be null or an object.")
	if gen_version < 1:
		errors.append("Field 'gen_version' must be at least 1.")
	for i in discoveries.size():
		errors.append_array(_discovery_problems(i, discoveries[i]))
	errors.append_array(validate_creature(creature, creature_body_rules))
	errors.append_array(validate_aquatic(aquatic, aquatic_body_rules))
	return errors


## Every problem with an aquatic dictionary: {} is fine (the lineage has not swum there); otherwise exactly the
## AQUATIC_KEYS with their types, then the body against `body_rules` when one is given.
static func validate_aquatic(data: Dictionary, body_rules: Callable = Callable()) -> PackedStringArray:
	var errors := PackedStringArray()
	if data.is_empty():
		return errors
	for problem in _key_problems("aquatic", data, AQUATIC_KEYS):
		errors.append(problem)
	if not errors.is_empty():
		return errors
	var problems := []
	var body := JsonValues.dict(data, "body", problems)
	var generation := JsonValues.whole(data, "generation", problems)
	JsonValues.array(data, "history", problems)
	var discovered := JsonValues.array(data, "discovered", problems)
	var relations := JsonValues.dict(data, "relations", problems)
	var meals := JsonValues.whole(data, "meals", problems)
	for problem in problems:
		errors.append("Aquatic: %s" % problem)
	if not errors.is_empty():
		return errors
	if generation < 1:
		errors.append("Aquatic: generation must be 1 or higher, got %d." % generation)
	if meals < 0:
		errors.append("Aquatic: meals must not be negative.")
	for id in discovered:
		if not (id is String and not (id as String).is_empty()):
			errors.append("Aquatic: every discovered entry must be a non-empty id.")
			break
	for species in relations:
		var r: Variant = relations[species]
		if not (r is Dictionary and String(r.get("standing", "")) in AQUATIC_STANDINGS and _is_number(r.get("rapport"))
				and float(r.rapport) >= 0.0):
			errors.append("Aquatic: the relation with '%s' needs a standing (neutral, friend or foe) and a rapport of 0 or more." % species)
	var pos: Variant = data.position
	if not (pos is Array and pos.size() == 3 and pos.all(func(v): return _is_number(v))):
		errors.append("Aquatic: position must be three numbers.")
	if not _is_number(data.heading):
		errors.append("Aquatic: heading must be a number.")
	for key in ["energy", "health"]:
		if not (_is_number(data[key]) and float(data[key]) >= 0.0):
			errors.append("Aquatic: %s must be a number of at least 0." % key)
	if body_rules.is_valid():
		for problem in body_rules.call(body):
			errors.append("Aquatic body: %s" % problem)
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
		"aquatic": aquatic.duplicate(true),
		"lineage_history": lineage_history.duplicate(true),
		"discoveries": discoveries.duplicate(true),
		"relationships": relationships.duplicate(true),
		"settlements": settlements.duplicate(true),
		"world_changes": world_changes.duplicate(true),
		"player": player.duplicate(true),
		"pending_transactions": pending_transactions.duplicate(true),
		"growth": growth.duplicate(true),
		"checkpoint": checkpoint.duplicate(true),
		"spawn": spawn.duplicate(true) if spawn is Dictionary else spawn,
		"gen_version": gen_version,
		"saved_at_unix": saved_at_unix,
	}


## Expects data already migrated to SCHEMA_VERSION. Missing, unknown and wrong-typed fields are
## recorded in load_problems and reported by validate(); nothing is dropped silently. Sizes read as
## whole floats (JSON has no integers) come back as ints, as a running save holds them.
static func from_dict(data: Dictionary) -> SaveGame:
	var save := SaveGame.new()
	var problems := save.load_problems
	for key in data:
		if not (key is String and KEYS.has(key)):
			problems.append("Field '%s' is not part of a v%d save." % [key, SCHEMA_VERSION])
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
	save.aquatic = _aquatic_ints(JsonValues.dict(data, "aquatic", problems))
	save.lineage_history = JsonValues.array(data, "lineage_history", problems)
	save.discoveries = JsonValues.array(data, "discoveries", problems)
	for entry in save.discoveries:
		if entry is Dictionary:
			_size_as_int(entry)
	save.relationships = JsonValues.array(data, "relationships", problems)
	save.settlements = JsonValues.array(data, "settlements", problems)
	save.world_changes = JsonValues.array(data, "world_changes", problems)
	save.player = JsonValues.dict(data, "player", problems)
	save.pending_transactions = JsonValues.array(data, "pending_transactions", problems)
	save.growth = _size_as_int(JsonValues.dict(data, "growth", problems))
	save.checkpoint = _size_as_int(JsonValues.dict(data, "checkpoint", problems))
	# null is a value here (the checkpoint), so only a missing key is a problem at this point.
	if data.has("spawn"):
		save.spawn = data.spawn.duplicate(true) if data.spawn is Dictionary else data.spawn
	else:
		problems.append("Field 'spawn' is missing.")
	save.gen_version = JsonValues.whole(data, "gen_version", problems)
	save.saved_at_unix = JsonValues.whole(data, "saved_at_unix", problems)
	return save


## JSON reads every number as a float; the aquatic block's whole numbers (generation, meals, the body's sizes and
## the rapports) are ints in memory, as the stage holds them.
static func _aquatic_ints(data: Dictionary) -> Dictionary:
	for key in ["generation", "meals"]:
		if data.has(key):
			data[key] = _whole_or_same(data[key])
	if data.get("body") is Dictionary:
		for key in data.body:
			data.body[key] = _whole_or_same(data.body[key]) if key != "hue" else data.body[key]
	if data.get("relations") is Dictionary:
		for species in data.relations:
			if data.relations[species] is Dictionary and data.relations[species].has("rapport"):
				data.relations[species]["rapport"] = _whole_or_same(data.relations[species].rapport)
	for entry in data.get("history", []):
		if entry is Dictionary:
			entry["generation"] = _whole_or_same(entry.get("generation"))
			if entry.get("body") is Dictionary:
				for key in entry.body:
					entry.body[key] = _whole_or_same(entry.body[key]) if key != "hue" else entry.body[key]
	return data


static func _whole_or_same(v: Variant) -> Variant:
	return int(v) if v is float and is_finite(v) and v == floorf(v) else v


func _growth_problems() -> PackedStringArray:
	var errors := _key_problems("growth", growth, GROWTH_KEYS)
	if growth.has("size") and not _is_size(growth.size):
		errors.append("Field 'growth.size' must be a whole number from %d to %d." % [MIN_SIZE, MAX_SIZE])
	if growth.has("meter") and not (_is_number(growth.meter) and growth.meter >= 0.0):
		errors.append("Field 'growth.meter' must be a finite number of at least 0.")
	return errors


## The checkpoint or the spawn: finite x_am, y_am and heading, and for the checkpoint its size.
static func _place_problems(what: String, place: Dictionary, keys: PackedStringArray) -> PackedStringArray:
	var errors := _key_problems(what, place, keys)
	for key in ["x_am", "y_am", "heading"]:
		if place.has(key) and not _is_number(place[key]):
			errors.append("Field '%s.%s' must be a finite number." % [what, key])
	if keys.has("size") and place.has("size") and not _is_size(place.size):
		errors.append("Field '%s.size' must be a whole number from %d to %d." % [what, MIN_SIZE, MAX_SIZE])
	return errors


static func _discovery_problems(i: int, entry: Variant) -> PackedStringArray:
	var what := "discoveries[%d]" % i
	if not entry is Dictionary:
		return PackedStringArray(["Field '%s' must be an object." % what])
	var errors := _key_problems(what, entry, DISCOVERY_KEYS)
	if entry.has("type") and not (entry.type is String and DISCOVERY_TYPES.has(entry.type)):
		errors.append("Field '%s.type' must be one of %s." % [what, ", ".join(DISCOVERY_TYPES)])
	if entry.has("id") and not (entry.id is String and not entry.id.is_empty()):
		errors.append("Field '%s.id' must be non-empty text." % what)
	if entry.has("size") and not _is_size(entry.size):
		errors.append("Field '%s.size' must be a whole number from %d to %d." % [what, MIN_SIZE, MAX_SIZE])
	return errors


## Each missing key and each unknown one of a v3 object, by name.
static func _key_problems(what: String, object: Dictionary, keys: PackedStringArray) -> PackedStringArray:
	var errors := PackedStringArray()
	for key in keys:
		if not object.has(key):
			errors.append("Field '%s.%s' is missing." % [what, key])
	for key in object:
		if not (key is String and keys.has(key)):
			errors.append("Field '%s.%s' is not part of a v%d save." % [what, key, SCHEMA_VERSION])
	return errors


## A finite number. JSON reads every number as a float; a running save may hold ints.
static func _is_number(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value))


## A whole number from MIN_SIZE to MAX_SIZE (2.0 counts, 2.5 does not).
static func _is_size(value: Variant) -> bool:
	return _is_number(value) and value == floorf(value) and value >= MIN_SIZE and value <= MAX_SIZE


## Turns a whole float "size" into an int in place; anything else is left for validate() to report.
static func _size_as_int(object: Dictionary) -> Dictionary:
	var value = object.get("size")
	if value is float and is_finite(value) and value == floorf(value):
		object["size"] = int(value)
	return object
