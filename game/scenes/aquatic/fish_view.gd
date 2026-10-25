extends RefCounted
## Builds the Aquatic stage's fish (PROPOSED): an AquaticBody drawn as a creature-stage body description on a SpineRig,
## with the creature skin (generated, owner-approved runtime skins) and its Blender-authored parts. Skin arrays are
## built once per body and size and shared, so a shoal of one species costs one build. Presentation only.

const SkinCpu := preload("res://game/systems/creature/skin_cpu.gd")
const BodyField := preload("res://game/domain/creature/body_field.gd")
const AnchorResolver := preload("res://game/domain/creature/anchor_resolver.gd")
const SpineRig := preload("res://game/scenes/creature/spine_rig.gd")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const Look := preload("res://game/scenes/creature/creature_look.gd")

## The species' bodies and sizes (scale_m: the reference length, about the fish's length at body length 2).
const SPECIES := {
	"grazer": {"body": {"length": 1, "girth": 2, "tail": "ribbon", "tail_size": 1, "fins": 2, "dorsal": 1, "bladder": 2,
			"sense": "eyes", "mouth": "filter", "hue": 0.13}, "scale_m": 0.85, "sat": 0.7, "val": 0.95, "pattern": 1},
	"shoal": {"body": {"length": 2, "girth": 1, "tail": "fluke", "tail_size": 2, "fins": 1, "dorsal": 1, "bladder": 1,
			"sense": "eyes", "mouth": "filter", "hue": 0.58}, "scale_m": 0.5, "sat": 0.15, "val": 0.95, "pattern": 2},
	"lancer": {"body": {"length": 3, "girth": 2, "tail": "fluke", "tail_size": 3, "fins": 1, "dorsal": 2, "bladder": 1,
			"sense": "eyes", "mouth": "jaw", "hue": 0.98}, "scale_m": 2.3, "sat": 0.55, "val": 0.55, "pattern": 3},
	"drifter": {"body": {"length": 3, "girth": 3, "tail": "fluke", "tail_size": 3, "fins": 2, "dorsal": 0, "bladder": 3,
			"sense": "barbels", "mouth": "filter", "hue": 0.62}, "scale_m": 17.0, "sat": 0.35, "val": 0.4, "pattern": 4},
}

## The player's and its kin's size: about 1.6 m long at body length 2.
const PLAYER_SCALE_M := 1.6

static var _arrays := {}
static var _part_rules := {}


static func color_of(hue: float, sat := 0.6, val := 0.85) -> Color:
	return Color.from_hsv(fposmod(hue, 1.0), sat, val)


## A rig for `body` at `scale_m`, skinned at `divisions`. Faces -Z, like the sim's heading 0.
static func make(body: Dictionary, scale_m: float, divisions: int, color: Color, pattern_index := 0) -> Node3D:
	var desc = AquaticBody.to_description(body, scale_m)
	var key := JSON.stringify([body, scale_m, divisions], "", true)
	if not _arrays.has(key):
		_arrays[key] = SkinCpu.build(desc, divisions)
	if _part_rules.is_empty():
		_part_rules = CreatureData.part_rules()
	var rig := SpineRig.new()
	rig.setup(desc, _arrays[key], color)
	var orientations: Dictionary = CreatureData.part_orientations(_part_rules)
	rig.add_parts(AnchorResolver.resolve_all(desc, BodyField.from_description(desc), orientations), orientations)
	rig.use_skin_shader(Look.shader_params(color, Look.rival_pattern(pattern_index)))
	rig.swim_amplitude_deg = 12.0
	rig.swim_wavelength = 1.0
	return rig


static func make_species(species: String, divisions: int, index := 0) -> Node3D:
	var s: Dictionary = SPECIES[species]
	return make(s.body, float(s.scale_m), divisions, color_of(float(s.body.hue), float(s.sat), float(s.val)), int(s.pattern) + index)


## The rig's swim wave follows its speed: faster beats as it swims faster, a slow idle wave when still.
static func animate(rig: Node3D, speed: float, delta: float) -> void:
	rig.set("swim_frequency", clampf(0.5 + speed * 0.28, 0.5, 3.2))
	rig.call("swim", delta)
