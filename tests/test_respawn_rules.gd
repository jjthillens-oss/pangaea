extends TestCase
## RespawnRules (M1 step 3): the death streak, the per-streak shelter and energy pick, the creatures
## sent home from around the checkpoint and the history's cause strings. The tables are the plan's
## fairness block (grace_s 5/8/10, respawn_energy_share 0.6/0.8/1.0, streak_window_s 90,
## respawn_clear_m 12).

const WINDOW := 90 * 60
const GRACE_S := [5.0, 8.0, 10.0]
const ENERGY_SHARE := [0.6, 0.8, 1.0]
const CLEAR_M := 12.0


func _body(id: String, position: Vector2, alive: bool = true) -> Dictionary:
	return {"id": id, "species": "rammer", "position": position, "velocity": Vector2.ZERO, "radius": 0.4, "alive": alive}


func test_the_first_death_starts_the_streak_at_one_however_long_the_cell_lived() -> void:
	check_eq(RespawnRules.streak_after(0, 0, WINDOW), 1, "a death on the first tick")
	check_eq(RespawnRules.streak_after(0, WINDOW - 1, WINDOW), 1, "a death just inside the window")
	check_eq(RespawnRules.streak_after(0, WINDOW * 10, WINDOW), 1, "a death after a long life")


func test_each_death_within_ninety_seconds_of_the_last_respawn_grows_the_streak_by_one() -> void:
	var streak := 0
	var seen: Array[int] = []
	for alive in [600, 3000, WINDOW - 1, 1]:
		streak = RespawnRules.streak_after(streak, alive, WINDOW)
		seen.append(streak)
	check_eq(seen, [1, 2, 3, 4], "1, 2, 3 and on past the table")


func test_a_life_of_ninety_seconds_or_more_resets_the_streak_to_one() -> void:
	check_eq(RespawnRules.streak_after(2, WINDOW - 1, WINDOW), 3, "one tick short of 90 s still counts")
	check_eq(RespawnRules.streak_after(2, WINDOW, WINDOW), 1, "exactly 90 s resets")
	check_eq(RespawnRules.streak_after(3, WINDOW + 1, WINDOW), 1, "longer resets too")
	check_eq(RespawnRules.streak_after(9, WINDOW * 4, WINDOW), 1, "however long the run of deaths was")


func test_pick_reads_the_table_by_streak_and_keeps_the_last_entry_beyond_it() -> void:
	check_eq(RespawnRules.pick(GRACE_S, 1), 5.0, "first death: 5 s of shelter")
	check_eq(RespawnRules.pick(GRACE_S, 2), 8.0, "second: 8 s")
	check_eq(RespawnRules.pick(GRACE_S, 3), 10.0, "third: 10 s")
	check_eq(RespawnRules.pick(GRACE_S, 4), 10.0, "fourth: still 10 s")
	check_eq(RespawnRules.pick(GRACE_S, 99), 10.0, "a long losing run keeps the most help")
	check_eq(RespawnRules.pick(ENERGY_SHARE, 1), 0.6, "first death: 60% energy")
	check_eq(RespawnRules.pick(ENERGY_SHARE, 2), 0.8, "second: 80%")
	check_eq(RespawnRules.pick(ENERGY_SHARE, 7), 1.0, "past the table: full")


func test_pick_treats_a_streak_below_one_as_the_first_death_and_an_empty_table_as_zero() -> void:
	check_eq(RespawnRules.pick(GRACE_S, 0), 5.0, "streak 0 (no death yet)")
	check_eq(RespawnRules.pick(GRACE_S, -3), 5.0, "a negative streak")
	check_eq(RespawnRules.pick([], 2), 0.0, "an empty table")
	check_eq(RespawnRules.pick([7], 3), 7.0, "a one-entry table")


func test_a_quick_run_of_deaths_raises_the_shelter_and_energy_and_a_long_life_lowers_them_again() -> void:
	# Deaths at these ticks after each respawn: three quick ones, a long life, then a quick one.
	var streak := 0
	var grace: Array[float] = []
	var energy: Array[float] = []
	for alive in [1200, 2400, 900, WINDOW + 600, 300]:
		streak = RespawnRules.streak_after(streak, alive, WINDOW)
		grace.append(RespawnRules.pick(GRACE_S, streak))
		energy.append(RespawnRules.pick(ENERGY_SHARE, streak))
	check_eq(grace, [5.0, 8.0, 10.0, 5.0, 8.0], "shelter seconds")
	check_eq(energy, [0.6, 0.8, 1.0, 0.6, 0.8], "energy shares")


func test_to_relocate_lists_the_bodies_within_twelve_metres_sorted_by_id_with_the_edge_included() -> void:
	var checkpoint := Vector2(0.0, 9.0)
	var bodies := [
		_body("c3", checkpoint + Vector2(12.0, 0.0)),        # exactly 12.0 m east
		_body("c10", checkpoint + Vector2(0.0, -11.99)),     # just inside, north
		_body("c1", checkpoint + Vector2(-12.001, 0.0)),     # just outside, west
		_body("c2", checkpoint + Vector2(0.0, 12.0)),        # exactly 12.0 m south
		_body("c7", checkpoint + Vector2(3.0, -4.0)),        # close
		_body("c4", checkpoint + Vector2(9.0, 9.0)),         # 12.73 m on the diagonal
	]
	var got := RespawnRules.to_relocate(checkpoint, CLEAR_M, bodies)
	check_eq(got, PackedStringArray(["c10", "c2", "c3", "c7"]), "sorted by id, both 12.0 m bodies in")
	var reversed := bodies.duplicate()
	reversed.reverse()
	check_eq(RespawnRules.to_relocate(checkpoint, CLEAR_M, reversed), got, "the body order does not matter")


func test_to_relocate_skips_dead_bodies_and_is_empty_when_nothing_is_near() -> void:
	var checkpoint := Vector2(-24.1, 16.6)
	var bodies := [
		_body("b", checkpoint + Vector2(1.0, 1.0), false),
		_body("a", checkpoint + Vector2(2.0, 0.0)),
		{"id": "d", "position": checkpoint + Vector2(0.5, 0.0)},   # no alive key: live
	]
	check_eq(RespawnRules.to_relocate(checkpoint, CLEAR_M, bodies), PackedStringArray(["a", "d"]), "the dead body stays")
	var far := [_body("x", checkpoint + Vector2(20.0, 0.0)), _body("y", checkpoint + Vector2(0.0, -30.0))]
	check_eq(RespawnRules.to_relocate(checkpoint, CLEAR_M, far), PackedStringArray(), "nothing within 12 m")
	check_eq(RespawnRules.to_relocate(checkpoint, CLEAR_M, []), PackedStringArray(), "no bodies at all")


func test_death_causes_are_starved_or_killed_by_the_killers_species() -> void:
	check_eq(RespawnRules.death_cause({"cause": "starved"}), "starved", "step 2's death record")
	check_eq(RespawnRules.death_cause({"cause": "starved", "by": "", "by_species": "", "reason": "Out of energy"}), "starved", "a starving record in the step 3 shape")
	var hunter := {"cause": "killed", "by": "c4", "by_species": "ambush_hunter", "reason": "Caught by an ambush hunter"}
	check_eq(RespawnRules.death_cause(hunter), "killed:ambush_hunter", "the ambush hunter")
	check_eq(RespawnRules.death_cause({"cause": "killed", "by": "c9", "by_species": "rammer", "reason": "Rammed"}), "killed:rammer", "the rammer")
	check_eq(RespawnRules.death_cause({"cause": "killed", "by": "debug", "by_species": ""}), "killed", "a kill with no species")
	check_eq(RespawnRules.death_cause({}), "starved", "a record without a cause")


func test_the_cause_string_lands_in_the_lineage_history_unchanged() -> void:
	var save := SaveGame.new_run(7, "test+dev")
	save.adaptation_points = 13
	var cause := RespawnRules.death_cause({"cause": "killed", "by": "c4", "by_species": "ambush_hunter"})
	var lost := Lineage.apply_death(save, cause)
	check_eq(lost, 3, "a quarter of 13, rounded down")
	var last: Dictionary = save.lineage_history[-1]
	check_eq(last.event, "died", "a died entry")
	check_eq(last.cause, "killed:ambush_hunter", "with the killer's species")
