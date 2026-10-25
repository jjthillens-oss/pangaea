class_name BodyText
extends RefCounted
## Words and numbers that describe a body to the player (M1 step 2): starting body names, their
## one-line roles, the diet line and the stat rows. Every number comes from Phenotype.derive, and
## the body cards, the Continue card, the HUD and the scene smoke all use these same formatters,
## so what the player reads is what the rules use.

const ORDER: PackedStringArray = ["grazer", "hunter", "omnivore"]
const NAMES := {"grazer": "UI_GRAZER_113814", "hunter": "UI_HUNTER_147847", "omnivore": "UI_OMNIVORE_EA442A"}
## A body that no longer matches any starting body (after the step 4 editor).
const EVOLVED_NAME := "UI_EVOLVED_CELL_CFC292"
const ROLES := {
	"grazer": "UI_A_STEADY_DRIFTER_WITH_AN_EYE_SPOT_AND_A_FILTER_M_1326BD",
	"hunter": "UI_TWO_TAILS_FOR_SPEED_AND_A_JAW_FOR_CARRION_HUNTER_C3D47B",
	"omnivore": "UI_A_FILTER_MOUTH_AND_A_JAW_SO_IT_CAN_EAT_ANYTHING__496362",
}
const DIET_WORDS := {"plant": "UI_PLANKTON_B1957F", "meat": "UI_CARRION_6EC07A"}


## "Grazer", or EVOLVED_NAME for "" (Lineage.starting_body_of found no match).
static func body_name(body: String) -> String:
	return TranslationServer.translate(str(NAMES.get(body, EVOLVED_NAME)))


static func role(body: String) -> String:
	return TranslationServer.translate(str(ROLES.get(body, "")))


## "Eats plankton", "Eats carrion" or "Eats both", from the body's mouths.
static func diet(p: Phenotype) -> String:
	var foods := PackedStringArray()
	for d in ["plant", "meat"]:
		if p.can_eat(d):
			foods.append(TranslationServer.translate(DIET_WORDS[d]))
	match foods.size():
		0:
			return TranslationServer.translate("UI_EATS_NOTHING_5064B9")
		1:
			return TranslationServer.translate("UI_EATS_S_C73430") % foods[0]
	return TranslationServer.translate("UI_EATS_BOTH_EBB968")


## The stats a player compares between bodies, as [name, value] pairs in display order.
static func stat_rows(p: Phenotype) -> Array[PackedStringArray]:
	return [
		PackedStringArray([TranslationServer.translate("UI_SPEED_2D2CB0"), TranslationServer.translate("UI_1F_M_S_0771B4") % p.speed]),
		PackedStringArray([TranslationServer.translate("UI_TURNING_9212A5"), TranslationServer.translate("UI_D_S_446F0C") % roundi(rad_to_deg(p.turn_rate))]),
		PackedStringArray([TranslationServer.translate("UI_UPKEEP_120946"), TranslationServer.translate("UI_2F_ENERGY_S_8EA4A4") % p.upkeep]),
		PackedStringArray([TranslationServer.translate("UI_SIGHT_3437DC"), TranslationServer.translate("UI_D_M_01BA69") % roundi(p.sight)]),
		PackedStringArray([TranslationServer.translate("UI_MAX_ENERGY_6D57F6"), "%d" % roundi(p.energy_capacity)]),
	]


## "Grazer lineage 3F9A-1C07 · Generation 1". A no-break space keeps the generation and its
## number together when the HUD wraps the line.
static func lineage_line(body: String, tag: String, generation: int) -> String:
	return TranslationServer.translate("UI_S_LINEAGE_S_GENERATION_U00A0_D_6E25CD") % [body_name(body), tag, generation]
