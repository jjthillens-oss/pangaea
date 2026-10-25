class_name SocialTraits
extends RefCounted
## Anatomy to social traits (PROPOSED, docs/stages/social-plan.md sections 4 and 6): what a body can do with the
## four signals (Sing, Display, Share, Calm), how much it can carry, and which bounded role it takes in a band.
## Pure rules: no scene, file or clock access. The body numbers come from CreatureStats (read-only; the creature
## stage owns it), the organ lists and weights from game/data/social/social_slice.json.
##
## Organs (Bible section 12, communication organs): a detail-role part is a voice organ when its type is in
## organs.voice_types, a hearing organ when it is in organs.hearing_types, and a display organ otherwise. A type the
## part rules do not list, or a part whose role is not "detail", is no organ at all, so a new part never changes a
## signal by accident. A mirrored part counts twice, as in CreatureStats.count_parts.

const DETAIL_ROLE := "detail"
const HAND_ROLE := "hand"
## The role order used to break ties when the tuning has none (forager, scout, defender).
const ROLE_ORDER: Array[String] = ["forager", "scout", "defender"]


## Returns {voice_m, hearing_mult, display_strength, display_count, voice_organs, hearing_organs, sight_m, speed_mps,
## can_carry, carry_count, hands, role, role_scores}.
## - voice_m: how far its song carries (signals.sing.range_m, plus voice_bonus_m with a voice organ).
## - hearing_mult: how much further it hears a song (signals.sing.hearing_mult with a hearing organ, else 1).
## - display_strength: 1 plus a step per display organ with diminishing returns (display_strength_of).
## - carry_count: carry.with_hand with a hand-role part, else carry.with_mouth with a mouth, else 0.
## `stats` is CreatureStats.of(body, ...) for the same body; `tuning` is the whole social tuning.
static func of(body: RefCounted, stats: Dictionary, part_rules: Dictionary, tuning: Dictionary) -> Dictionary:
	var organs: Dictionary = tuning["organs"]
	var details := CreatureStats.types_with_role(part_rules, DETAIL_ROLE)
	var voice_types := PackedStringArray()
	var hearing_types := PackedStringArray()
	var display_types := PackedStringArray()
	for type in details:
		if (organs["voice_types"] as Array).has(type):
			voice_types.append(type)
		elif (organs["hearing_types"] as Array).has(type):
			hearing_types.append(type)
		else:
			display_types.append(type)
	var voices := CreatureStats.count_parts(body, voice_types, part_rules)
	var hearing := CreatureStats.count_parts(body, hearing_types, part_rules)
	var displays := CreatureStats.count_parts(body, display_types, part_rules)
	var hands := CreatureStats.count_parts(body, CreatureStats.types_with_role(part_rules, HAND_ROLE), part_rules)
	var sing: Dictionary = tuning["signals"]["sing"]
	var carry: Dictionary = tuning["carry"]
	var has_mouth := bool(stats.get("has_mouth", false))
	var carry_count := 0
	if hands > 0:
		carry_count = int(carry["with_hand"])
	elif has_mouth:
		carry_count = int(carry["with_mouth"])
	var scores := role_scores(stats, hands, tuning["roles"])
	return {
		"voice_m": float(sing["range_m"]) + (float(sing["voice_bonus_m"]) if voices > 0 else 0.0),
		"hearing_mult": float(sing["hearing_mult"]) if hearing > 0 else 1.0,
		"display_strength": display_strength_of(displays, tuning["signals"]["display"]),
		"display_count": displays,
		"voice_organs": voices,
		"hearing_organs": hearing,
		"sight_m": float(stats.get("sight_m", 0.0)),
		"speed_mps": float(stats.get("speed_mps", 0.0)),
		"can_carry": carry_count > 0,
		"carry_count": carry_count,
		"hands": hands,
		"role": role_of(scores, tuning["roles"].get("order", ROLE_ORDER)),
		"role_scores": scores,
	}


## Display strength from `count` display organs: 1, plus display.per_display for the first organ and display.falloff
## times the step before for each next one, at most display.display_cap organs counting (diminishing returns, Bible
## section 12). With the PROPOSED numbers: 0 organs 1.0, 1 organ 1.5, 2 organs 1.8, 4 organs about 2.09.
static func display_strength_of(count: int, display: Dictionary) -> float:
	var strength := 1.0
	var step := float(display["per_display"])
	for i in mini(maxi(count, 0), int(display["display_cap"])):
		strength += step
		step *= float(display["falloff"])
	return strength


## The three role scores from the body numbers (roles weights in the tuning):
## scout = sight_m * per_sight_m + speed_mps * per_speed_mps; defender = weapons * per_weapon + mass_kg * per_kg;
## forager = hands * per_hand + mouths * per_mouth.
static func role_scores(stats: Dictionary, hands: int, roles: Dictionary) -> Dictionary:
	var scout: Dictionary = roles["scout"]
	var defender: Dictionary = roles["defender"]
	var forager: Dictionary = roles["forager"]
	return {
		"scout": float(stats.get("sight_m", 0.0)) * float(scout["per_sight_m"])
				+ float(stats.get("speed_mps", 0.0)) * float(scout["per_speed_mps"]),
		"defender": float(stats.get("weapons", 0)) * float(defender["per_weapon"])
				+ float(stats.get("mass_kg", 0.0)) * float(defender["per_kg"]),
		"forager": float(hands) * float(forager["per_hand"]) + float(stats.get("mouths", 0)) * float(forager["per_mouth"]),
	}


## The role with the highest score; ties go to the earlier role in `order` (forager, scout, defender).
static func role_of(scores: Dictionary, order: Array = ROLE_ORDER) -> String:
	var best := ""
	var best_score := -INF
	for role in order:
		var s := float(scores.get(role, -INF))
		if s > best_score:
			best = String(role)
			best_score = s
	return best
