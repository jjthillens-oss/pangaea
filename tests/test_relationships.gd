extends TestCase
## Relationships (S2, plan B.6 and B.7): q along the ladder, the ladder roles at every boundary, the
## relationship rules 1 to 5 with their tolerance, and the reason the M1 world does not change: every
## M1 pair lies inside the shares. The shares are creatures_m1.json's relationships block (spine 4.2).

const TOL := Relationships.TOLERANCE
const PREY_SHARE := 1.0
const INTRUDER_SHARE := 1.2
const FEAR_SHARE := 1.25
const PLAYER_R := 0.5
const AMBUSH_R := 0.75
const RAMMER_R := 0.625
const INTRUDER_MIN_R := 0.3


func test_q_is_exactly_one_at_the_entry_size_and_exact_powers_of_0_625_below_it() -> void:
	for n in range(1, 11):
		check_eq(Relationships.q_of(n, n), 1.0, "size %d at its own entry size" % n)
	check_eq(Relationships.q_of(1, 2), 0.625, "a size-1 species at size 2")
	check_eq(Relationships.q_of(1, 3), 0.390625, "at size 3")
	check_eq(Relationships.q_of(1, 4), 0.244140625, "at size 4")
	check_eq(Relationships.q_of(2, 1), 1.6, "a size-2 species seen from size 1")
	for c in range(1, 11):
		for n in range(c, 11):
			check_eq(Relationships.q_of(c, n), pow(0.625, n - c), "c %d at n %d is 0.625^%d exactly" % [c, n, n - c])
			check_eq(Relationships.q_of(c, n), Relationships.q_of(1, n - c + 1), "only the difference counts")
	check(Relationships.q_of(3, 1) > 2.55 and Relationships.q_of(3, 1) < 2.57, "two sizes up is about 2.56")


func test_rel_is_the_radius_over_the_players() -> void:
	check_eq(Relationships.rel(PLAYER_R), 1.0, "the player")
	check_eq(Relationships.rel(AMBUSH_R), 1.5, "the ambush hunter at size 1")
	check_eq(Relationships.rel(AMBUSH_R * 0.625), 0.9375, "and at size 2")
	check_eq(Relationships.rel(RAMMER_R * 0.625), 0.78125, "the rammer at size 2")


func test_ladder_roles_change_exactly_at_each_boundary() -> void:
	check_eq(Relationships.ladder_role(2, 2, 0.01), "threat", "at its entry size, whatever its radius")
	check_eq(Relationships.ladder_role(1, 1, 5.0), "threat", "a big one too")
	check_eq(Relationships.ladder_role(2, 1, 0.75), "ghost", "above the cell's size")
	check_eq(Relationships.ladder_role(4, 1, 0.01), "ghost", "far above")
	# rel x is a radius of x / 2; halving and doubling are exact, so rel(r) is x exactly.
	var cases := [
		[Relationships.RIVAL_MIN_REL + 2.0 * TOL, "rival"], [Relationships.RIVAL_MIN_REL + TOL, "prey"],
		[Relationships.RIVAL_MIN_REL, "prey"],
		[Relationships.PREY_MIN_REL, "prey"], [Relationships.PREY_MIN_REL - TOL, "prey"],
		[Relationships.PREY_MIN_REL - 2.0 * TOL, "morsel"],
		[Relationships.MORSEL_MIN_REL, "morsel"], [Relationships.MORSEL_MIN_REL - TOL, "morsel"],
		[Relationships.MORSEL_MIN_REL - 2.0 * TOL, "haze"], [0.0, "haze"], [3.0, "rival"],
	]
	for case in cases:
		var r: float = case[0] * PLAYER_R
		check_eq(Relationships.rel(r), float(case[0]), "rel %.7f is exact" % case[0])
		check_eq(Relationships.ladder_role(1, 2, r), case[1], "rel %.7f" % case[0])


func test_the_m1_species_at_size_two_are_a_rival_and_prey() -> void:
	var q := Relationships.q_of(1, 2)
	check_eq(Relationships.ladder_role(1, 2, AMBUSH_R * q), "rival", "the ambush hunter (rel 0.9375)")
	check_eq(Relationships.ladder_role(1, 2, RAMMER_R * q), "prey", "the rammer (rel 0.78125)")
	check_eq(Relationships.ladder_role(1, 3, AMBUSH_R * Relationships.q_of(1, 3)), "prey", "the ambush hunter at size 3")
	check_eq(Relationships.ladder_role(1, 4, RAMMER_R * Relationships.q_of(1, 4)), "morsel", "the rammer at size 4 (rel 0.305)")
	check_eq(Relationships.ladder_role(1, 5, RAMMER_R * Relationships.q_of(1, 5)), "haze", "and at size 5 (rel 0.191)")


func test_rule_1_prey_is_up_to_the_prey_share_with_the_tolerance() -> void:
	check(Relationships.can_prey(PREY_SHARE, AMBUSH_R, PLAYER_R), "the player")
	check(Relationships.can_prey(PREY_SHARE, AMBUSH_R, RAMMER_R), "a rammer")
	check(Relationships.can_prey(PREY_SHARE, AMBUSH_R, AMBUSH_R), "a body its own size")
	check(Relationships.can_prey(PREY_SHARE, AMBUSH_R, AMBUSH_R + 0.5 * TOL), "within the tolerance")
	check(not Relationships.can_prey(PREY_SHARE, AMBUSH_R, AMBUSH_R + 2.0 * TOL), "past it")
	check(Relationships.can_prey(1.6, AMBUSH_R, 1.2), "M1's share 1.6 reaches 1.2")
	check(not Relationships.can_prey(1.6, AMBUSH_R, 1.21), "and no further")
	check(not Relationships.can_prey(PREY_SHARE, AMBUSH_R, AMBUSH_R, -2.0 * TOL), "the tolerance is the caller's")


func test_rule_2_intruders_lie_between_the_minimum_and_the_share_and_rammers_still_charge_ambush_hunters() -> void:
	check(RAMMER_R * INTRUDER_SHARE == AMBUSH_R, "0.625 x 1.2 is 0.75 in float64 (the tolerance still applies)")
	check(Relationships.is_intruder(INTRUDER_MIN_R, INTRUDER_SHARE, RAMMER_R, AMBUSH_R), "an ambush hunter is an intruder")
	check(Relationships.is_intruder(INTRUDER_MIN_R, INTRUDER_SHARE, RAMMER_R, AMBUSH_R + 0.5 * TOL), "within the tolerance")
	check(not Relationships.is_intruder(INTRUDER_MIN_R, INTRUDER_SHARE, RAMMER_R, AMBUSH_R + 2.0 * TOL), "past it")
	check(Relationships.is_intruder(INTRUDER_MIN_R, INTRUDER_SHARE, RAMMER_R, PLAYER_R), "the player")
	check(Relationships.is_intruder(INTRUDER_MIN_R, INTRUDER_SHARE, RAMMER_R, INTRUDER_MIN_R), "the minimum itself")
	check(not Relationships.is_intruder(INTRUDER_MIN_R, INTRUDER_SHARE, RAMMER_R, INTRUDER_MIN_R - 1e-9), "below it, as M1 compares")
	check(Relationships.is_intruder(INTRUDER_MIN_R, INF, RAMMER_R, 50.0), "rule 2 off (INF): no upper bound")
	check(Relationships.is_intruder(INTRUDER_MIN_R, INF, 0.0, 50.0), "even for a body of no radius")
	check(not Relationships.above_engage(INTRUDER_SHARE, RAMMER_R, AMBUSH_R), "and a bite from an ambush hunter is answered")


func test_rule_3_fear_is_from_the_fear_share_down_to_the_tolerance() -> void:
	var edge := RAMMER_R * FEAR_SHARE
	check_eq(edge, 0.78125, "a rammer fears from 0.78125")
	check(Relationships.fears(FEAR_SHARE, RAMMER_R, edge), "at the share")
	check(Relationships.fears(FEAR_SHARE, RAMMER_R, edge - 0.5 * TOL), "within the tolerance below it")
	check(not Relationships.fears(FEAR_SHARE, RAMMER_R, edge - 2.0 * TOL), "not past it")
	check(not Relationships.fears(FEAR_SHARE, RAMMER_R, AMBUSH_R), "no M1 body is 1.25 times another (0.75 / 0.625 = 1.2)")
	check(not Relationships.fears(INF, RAMMER_R, 50.0), "rule 3 off (INF) fears nothing")
	check(not Relationships.fears(INF, 0.0, 50.0), "even with no radius")
	var q := Relationships.q_of(1, 2)
	check(Relationships.fears(FEAR_SHARE, RAMMER_R * q, PLAYER_R), "at size 2 the rammer fears the cell (0.48828 <= 0.5)")
	check(not Relationships.fears(FEAR_SHARE, AMBUSH_R * q, PLAYER_R), "the ambush hunter does not (0.5859 > 0.5)")
	check(Relationships.fears(FEAR_SHARE, AMBUSH_R * q, AMBUSH_R), "it fears a Lurker (0.75)")
	check(not Relationships.fears(FEAR_SHARE, RAMMER_R, AMBUSH_R), "an elder rammer (0.625) does not fear a Lurker (0.78125 > 0.75)")


func test_rule_4_only_a_body_above_the_engage_share_is_fled() -> void:
	var q := Relationships.q_of(1, 2)
	check(Relationships.above_engage(INTRUDER_SHARE, RAMMER_R * q, PLAYER_R), "a size-2 cell bites a rammer: 0.5 > 0.46875")
	check(Relationships.above_engage(PREY_SHARE, AMBUSH_R * q, PLAYER_R), "and an ambush hunter: 0.5 > 0.46875")
	check(not Relationships.above_engage(INTRUDER_SHARE, RAMMER_R, AMBUSH_R), "at the share: answered")
	check(not Relationships.above_engage(INTRUDER_SHARE, RAMMER_R, AMBUSH_R + 0.5 * TOL), "within the tolerance: answered")
	check(Relationships.above_engage(INTRUDER_SHARE, RAMMER_R, AMBUSH_R + 2.0 * TOL), "past it: fled")
	check(not Relationships.above_engage(INF, RAMMER_R, 50.0), "an INF share puts nothing above it")
	check(not Relationships.above_engage(INF, 0.0, 50.0), "even with no radius")


func test_rule_5_an_outgrown_hazard_does_no_damage() -> void:
	check_eq(Relationships.thread_damage(7.5, 1.0), 7.5, "at its entry size")
	check_eq(Relationships.thread_damage(7.5, Relationships.q_of(3, 4)), 0.0, "once outgrown")
	check_eq(Relationships.thread_damage(7.5, Relationships.q_of(4, 3)), 7.5, "to a smaller cell")


func test_only_a_creature_at_its_entry_size_can_attack_the_player() -> void:
	for c in range(1, 5):
		check(Relationships.can_attack_player(Relationships.q_of(c, c)), "c %d at its entry size" % c)
		check(not Relationships.can_attack_player(Relationships.q_of(c, c + 1)), "c %d one size later" % c)


func test_every_m1_pair_lies_inside_the_shares() -> void:
	# Plan B.6: with every rule on, no M1 creature decides differently (S2G1). The player has no brain.
	var bodies := {"player": PLAYER_R, "ambush hunter": AMBUSH_R, "rammer": RAMMER_R}
	for a in ["ambush hunter", "rammer"]:
		for b in bodies:
			if a == b:
				continue
			var own: float = bodies[a]
			var other: float = bodies[b]
			var where := "%s seeing %s" % [a, b]
			check(not Relationships.fears(FEAR_SHARE, own, other), where + ": no fear")
			if a == "ambush hunter":
				check_eq(Relationships.can_prey(PREY_SHARE, own, other), Relationships.can_prey(1.6, own, other), where + ": prey as M1")
				check(not Relationships.above_engage(PREY_SHARE, own, other), where + ": answered as M1")
			elif a == "rammer":
				check(Relationships.is_intruder(INTRUDER_MIN_R, INTRUDER_SHARE, own, other), where + ": an intruder as M1")
				check(not Relationships.above_engage(INTRUDER_SHARE, own, other), where + ": answered as M1")
