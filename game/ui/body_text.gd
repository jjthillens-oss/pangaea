class_name BodyText
extends RefCounted
## Words and numbers that describe a body to the player (M1 step 2): starting body names, their
## one-line roles, the diet line and the stat rows. Every number comes from Phenotype.derive, and
## the body cards, the Continue card, the HUD and the scene smoke all use these same formatters,
## so what the player reads is what the rules use.

const ORDER: PackedStringArray = ["grazer", "hunter", "omnivore"]
const NAMES := {"grazer": "Grazer", "hunter": "Hunter", "omnivore": "Omnivore"}
## A body that no longer matches any starting body (after the step 4 editor).
const EVOLVED_NAME := "Evolved cell"
const ROLES := {
	"grazer": "A steady drifter with an eye spot and a filter mouth.",
	"hunter": "Two tails for speed and a jaw that tears carrion.",
	"omnivore": "A filter mouth and a jaw, so it can eat anything it finds.",
}
const DIET_WORDS := {"plant": "plankton", "meat": "carrion"}


## "Grazer", or EVOLVED_NAME for "" (Lineage.starting_body_of found no match).
static func body_name(body: String) -> String:
	return str(NAMES.get(body, EVOLVED_NAME))


static func role(body: String) -> String:
	return str(ROLES.get(body, ""))


## "Eats plankton", "Eats carrion" or "Eats both", from the body's mouths.
static func diet(p: Phenotype) -> String:
	var foods := PackedStringArray()
	for d in ["plant", "meat"]:
		if p.can_eat(d):
			foods.append(DIET_WORDS[d])
	match foods.size():
		0:
			return "Eats nothing"
		1:
			return "Eats " + foods[0]
	return "Eats both"


## The stats a player compares between bodies, as [name, value] pairs in display order.
static func stat_rows(p: Phenotype) -> Array[PackedStringArray]:
	return [
		PackedStringArray(["Speed", "%.1f m/s" % p.speed]),
		PackedStringArray(["Turning", "%d°/s" % roundi(rad_to_deg(p.turn_rate))]),
		PackedStringArray(["Upkeep", "%.2f energy/s" % p.upkeep]),
		PackedStringArray(["Sight", "%d m" % roundi(p.sight)]),
		PackedStringArray(["Max energy", "%d" % roundi(p.energy_capacity)]),
	]


## "Grazer lineage 3F9A-1C07 · Generation 1".
static func lineage_line(body: String, tag: String, generation: int) -> String:
	return "%s lineage %s · Generation %d" % [body_name(body), tag, generation]
