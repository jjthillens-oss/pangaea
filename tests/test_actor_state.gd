extends TestCase

var phenotype: Phenotype


func before_each() -> void:
	var catalog := PartCatalog.load_from()
	var genome := Genome.create(StableId.generate("lineage"))
	genome.add_part("mouth_filter", 0.0)
	phenotype = Phenotype.derive(genome, catalog)


func test_fresh_state_is_full_health_and_part_fed() -> void:
	var s := ActorState.fresh(phenotype)
	check_near(s.health, 30.0, 0.0001, "health")
	check_near(s.energy, 60.0, 0.0001, "energy starts at 60%")
	check(s.is_alive() and not s.is_starving(), "alive and fed")


func test_upkeep_and_movement_drain_energy() -> void:
	var s := ActorState.fresh(phenotype)
	s.tick(phenotype, 10.0, 0.0)
	check_near(s.energy, 60.0 - 0.55 * 10.0, 0.0001, "resting upkeep")
	var before := s.energy
	s.tick(phenotype, 0.0, 10.0)
	check_near(before - s.energy, phenotype.move_cost * 10.0, 0.0001, "moving costs energy per meter")


func test_starvation_slows_and_hurts_but_food_recovers() -> void:
	var s := ActorState.fresh(phenotype)
	s.energy = 0.2
	s.tick(phenotype, 1.0, 0.0)
	check_eq(s.energy, 0.0, "energy floors at zero")
	check(s.is_starving(), "starving")
	check(s.speed_multiplier() < 1.0, "slowed while starving")
	check_near(s.health, 30.0 - ActorState.STARVATION_DAMAGE, 0.0001, "starvation damage")
	check(s.is_alive(), "still alive")
	s.eat(20.0)
	check(not s.is_starving(), "food ends starvation")
	check_near(s.speed_multiplier(), 1.0, 0.0001, "full speed again")


func test_starving_long_enough_kills_and_the_dead_stay_still() -> void:
	var s := ActorState.fresh(phenotype)
	s.energy = 0.0
	s.tick(phenotype, 30.0, 0.0)
	check(not s.is_alive(), "dead")
	check_eq(s.health, 0.0, "health floors at zero")
	s.energy = s.energy_capacity
	s.tick(phenotype, 10.0, 0.0)
	check_eq(s.health, 0.0, "no regeneration after death, even when full")
	check_near(s.energy, s.energy_capacity, 0.0001, "no metabolism after death")


func test_health_regenerates_only_when_well_fed() -> void:
	var s := ActorState.fresh(phenotype)
	s.health = 10.0
	s.tick(phenotype, 1.0, 0.0)
	check_near(s.health, 10.0 + 30.0 * ActorState.REGEN_RATE, 0.0001, "regenerates above half energy")
	s.energy = 30.0
	s.tick(phenotype, 1.0, 0.0)
	check_near(s.health, 10.6, 0.0001, "no regeneration below half energy")
	s.energy = 100.0
	s.health = 29.9
	s.tick(phenotype, 10.0, 0.0)
	check_near(s.health, 30.0, 0.0001, "never above max")


func test_full_stomach_wastes_the_rest() -> void:
	var s := ActorState.fresh(phenotype)
	s.energy = 95.0
	check_near(s.eat(20.0), 5.0, 0.0001, "absorbed")
	check_near(s.energy, 100.0, 0.0001, "capped at capacity")


func test_damage_is_applied_as_given() -> void:
	var s := ActorState.fresh(phenotype)
	check_near(s.take_damage(6.0), 6.0, 0.0001, "dealt")
	check_near(s.health, 24.0, 0.0001, "health")
	check_near(s.take_damage(100.0), 24.0, 0.0001, "only the health that was left")
	check_eq(s.health, 0.0, "health floors at zero")


func test_bad_amounts_change_nothing() -> void:
	var s := ActorState.fresh(phenotype)
	check_eq(s.eat(NAN), 0.0, "NaN food")
	check_eq(s.eat(-5.0), 0.0, "negative food")
	check_near(s.energy, 60.0, 0.0001, "energy unchanged")
	check_eq(s.take_damage(NAN), 0.0, "NaN damage")
	check_eq(s.take_damage(-5.0), 0.0, "negative damage heals nothing")
	check_near(s.health, 30.0, 0.0001, "health unchanged")
