class_name Relationships
extends RefCounted
## Who is what to whom across the growth ladder (S2, plan B.6 and B.7; the numbers are PROPOSED and
## live in creatures_m1.json). Pure functions of sizes and radii, so the brain, the species catalog,
## the growth tick and the scene all read the same answer.
##
## Words: n is the cell's size, c a species' entry size (the size at which it is drawn as a threat),
## q = 1.6^(c - n) the factor its record is scaled by at n (Phenotype.scaled), and rel its radius at
## n over the player's, which is 0.5 tm at every size.
##
## The relationship rules each compare two radii with a tolerance, so that 0.625 x 1.2 can never
## round below 0.75 (rammers keep charging ambush hunters):
##   1 prey: an ambush brain picks bodies up to its radius x its prey share;
##   2 intruder: a territorial brain charges bodies from its intruder_min_radius up to its radius x
##     its intruder share;
##   3 fear: a creature flees a body of at least its radius x its fear share in its senses;
##   4 no engage above share: a creature hurt by a body above its engage share (rule 1's share for an
##     ambush brain, rule 2's for a territorial one) flees it instead of answering;
##   5 outgrown hazards: a hazard's thread does no damage below its entry size (S3).
## Every M1 pair lies inside these shares, so the M1 world is the same with the rules on or off.
## Each rule function takes the tolerance last; brains pass cfg.share_tolerance.

const TOLERANCE := 1e-6
const PLAYER_RADIUS := 0.5      ## tm, at every size (plan B.1)
const GROWTH_FACTOR := 1.6      ## tm grows by this per size (WorldConfig.GROWTH_FACTOR)
## 1 / GROWTH_FACTOR, exact in binary (5/8), so q below the entry size is exactly 0.625^(n - c).
const SHRINK_FACTOR := 0.625
## The ladder's rel thresholds (plan B.7): above RIVAL_MIN_REL a rival, from PREY_MIN_REL prey, from
## MORSEL_MIN_REL a morsel, below that haze.
const RIVAL_MIN_REL := 0.8
const PREY_MIN_REL := 0.45
const MORSEL_MIN_REL := 0.25


## q = 1.6^(c - n): exactly 1.0 at the entry size, exactly 0.625^(n - c) below it (0.625, 0.390625,
## 0.244140625, ...) and 1.6 multiplied up above it (a ghost's size, for the scene).
static func q_of(entry_size: int, size: int) -> float:
	var q := 1.0
	for i in absi(entry_size - size):
		q *= GROWTH_FACTOR if entry_size > size else SHRINK_FACTOR
	return q


## A radius at the cell's size over the player's radius.
static func rel(radius_at_size: float) -> float:
	return radius_at_size / PLAYER_RADIUS


## What a species is to a cell of size n: "threat" at its entry size, "ghost" while the cell is
## smaller, else by rel: "rival" above 0.8, "prey" from 0.45, "morsel" from 0.25, "haze" below.
static func ladder_role(entry_size: int, size: int, radius_at_size: float, tol := TOLERANCE) -> String:
	if entry_size == size:
		return "threat"
	if entry_size > size:
		return "ghost"
	var x := rel(radius_at_size)
	if x > RIVAL_MIN_REL + tol:
		return "rival"
	if x >= PREY_MIN_REL - tol:
		return "prey"
	if x >= MORSEL_MIN_REL - tol:
		return "morsel"
	return "haze"


## Rule 1: an ambush brain of radius own_r may pick a body of radius other_r.
static func can_prey(prey_share: float, own_r: float, other_r: float, tol := TOLERANCE) -> bool:
	return other_r <= own_r * prey_share + tol


## Rule 2: a territorial brain of radius own_r charges a body of radius other_r. The lower bound is
## M1's intruder_min_radius, compared as M1 does; an INF share (rule 2 off) has no upper bound.
static func is_intruder(min_r: float, max_share: float, own_r: float, other_r: float, tol := TOLERANCE) -> bool:
	if other_r < min_r:
		return false
	return is_inf(max_share) or other_r <= own_r * max_share + tol


## Rule 3: a creature of radius own_r fears a body of radius other_r. An INF share (rule 3 off)
## fears nothing.
static func fears(fear_share: float, own_r: float, other_r: float, tol := TOLERANCE) -> bool:
	return not is_inf(fear_share) and other_r >= own_r * fear_share - tol


## Rule 4: a body of radius other_r is above the engage share of a creature of radius own_r, so a
## hurt from it is fled, never answered. An INF share puts nothing above it.
static func above_engage(engage_share: float, own_r: float, other_r: float, tol := TOLERANCE) -> bool:
	return not is_inf(engage_share) and other_r > own_r * engage_share + tol


## Rule 5: a hazard's thread damage at q; none once the cell has outgrown it (q < 1).
static func thread_damage(base: float, q: float) -> float:
	return 0.0 if q < 1.0 else base


## Whether a creature at q can attack the player at all. Catalog rule 15 makes this exact: every
## species below its entry size is too small to bite or charge the cell.
static func can_attack_player(q: float) -> bool:
	return q == 1.0
