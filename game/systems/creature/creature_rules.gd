class_name CreatureRules
extends RefCounted
## The creature stage's creature as the lineage save carries it (save schema v3, SaveGame.creature; owner direction
## of 2026-10-24: follow the Bible, section 18). No file of its own: PersistenceService writes and reads the slot, and
## this class only knows the fresh creature, the stage's starting points and the body rules the save is checked with.
## Not domain code: it reads the data files through CreatureData.
##
## A creature is {"name", "body" (body_codec's dictionary, the editor's look keys included), "generation", "history"};
## its points are the save's adaptation_points.

const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")

const STARTER_BODY := "quadruped"
const DEFAULT_NAME := "Newcomer"
## The world tuning file (owned by the world track); start_points falls back to DEFAULT_START_POINTS without it.
const TUNING_PATH := "res://game/data/creature/creature_stage.json"
const DEFAULT_START_POINTS := 150
## The body key the editor keeps the skin colour in (CreatureEditor.SKIN_COLOR_KEY), and the cell skin's softening.
const SKIN_COLOR_KEY := "skin_color"
const CELL_SKIN_SATURATION := 0.55
const CELL_SKIN_VALUE := 0.8

## The body rules and part rules bodies are validated with (CreatureData's by default; tests may inject).
var rules: Dictionary
var part_rules: Dictionary


func _init(p_rules: Dictionary = {}, p_part_rules: Dictionary = {}) -> void:
	rules = p_rules if not p_rules.is_empty() else CreatureData.rules()
	part_rules = p_part_rules if not p_part_rules.is_empty() else CreatureData.part_rules()


## The tuning's start_points, or DEFAULT_START_POINTS when the tuning file is not there yet: the adaptation points a
## lineage founded from the creature stage starts with (one opened from a pool save keeps the pool's points).
static func start_points() -> int:
	if not FileAccess.file_exists(TUNING_PATH):
		return DEFAULT_START_POINTS
	var data = JSON.parse_string(FileAccess.get_file_as_string(TUNING_PATH))
	if data is Dictionary and (data.get("start_points") is int or data.get("start_points") is float):
		return int(data["start_points"])
	return DEFAULT_START_POINTS


## A fresh creature: the starter quadruped, generation 1 and no history.
static func new_creature() -> Dictionary:
	return {"name": DEFAULT_NAME, "body": CreatureData.body(STARTER_BODY).to_dict(), "generation": 1, "history": []}


## The first creature of a lineage that came ashore (ShoreLink, the cell-to-creature link): the fresh creature, its
## skin the cell's hue (the genome's appearance.hue, 0 to 1) as "#rrggbb" in the body's "skin_color", the key the
## editor reads. Everything else the lineage keeps (id, genome, history, points) stays in the save.
static func from_cell(genome: Genome) -> Dictionary:
	var creature := new_creature()
	var hue = genome.appearance.get("hue") if genome != null else null
	if hue is float or hue is int:
		var body: Dictionary = creature["body"]
		body[SKIN_COLOR_KEY] = "#" + cell_skin(float(hue)).to_html(false)
	return creature


## The skin a cell of hue `hue` (0 to 1) gives its first creature: that hue, softened to sit among the editor's swatches.
static func cell_skin(hue: float) -> Color:
	return Color.from_hsv(fposmod(hue, 1.0), CELL_SKIN_SATURATION, CELL_SKIN_VALUE)


## Every problem with a body dictionary: the codec's reading problems, the body rules and the part rules.
func body_problems(body: Dictionary) -> PackedStringArray:
	var desc: RefCounted = BodyCodec.from_dict(body)
	var out: PackedStringArray = desc.validate(rules)
	out.append_array(desc.validate_parts(rules, part_rules))
	return out


## body_problems as the Callable SaveGame.validate takes.
func body_validator() -> Callable:
	return body_problems


## Every problem with a creature dictionary, body rules included (SaveGame.validate_creature).
func validate(creature: Dictionary) -> PackedStringArray:
	return SaveGame.validate_creature(creature, body_validator())
