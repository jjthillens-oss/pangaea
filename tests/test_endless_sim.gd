extends TestCase
## The endless sim end to end (S1 T2.9), on FakeWorldGen: the save path (the absolute position in
## am, float64, written and restored exactly), and determinism.

const FakeWorldGen := preload("res://tests/fakes/fake_world_gen.gd")
const SEED := 4309

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog


func before_each() -> void:
	catalog = PartCatalog.load_from()
	layout = PoolLayout.load_from()
	species = SpeciesCatalog.load_from()


func _endless(at := PackedFloat64Array()) -> PoolSim:
	return FakeWorldGen.endless_sim(SEED, catalog, layout, species, null, at)


func test_an_endless_save_writes_the_absolute_position() -> void:
	var sim := _endless()
	var rebased := 0
	for t in 3000:
		sim.step(SimIntent.new(Vector2(1.0, -0.4)))
		rebased += _count(sim.drain_events(), "rebased")
	check(rebased >= 1, "the swim moved the origin (%d)" % rebased)
	sim.write_position_to_save()
	var a := sim.absolute_position_am()
	check_eq(sim.save.player.position, PlaneSpace.to_save_abs(a[0], a[1]), "to_save_abs(absolute_position_am())")
	check_eq(PlaneSpace.from_save_abs(sim.save.player.position), a, "and it reads back exactly")
	check(a[0] > 100.0, "far from the spawn (%.2f)" % a[0])
	check_eq(a, PackedFloat64Array([sim.world.origin_x_am + float(sim.motion.position.x),
		sim.world.origin_y_am + float(sim.motion.position.y)]), "the origin plus the local place, in float64")


func test_an_endless_create_restores_the_origin_from_the_save_exactly() -> void:
	var at := PackedFloat64Array([5000.123456789, -3210.987654321])
	var sim := _endless(at)
	check_eq(sim.world.origin_x_am, at[0], "origin x exactly")
	check_eq(sim.world.origin_y_am, at[1], "origin y exactly")
	check(sim.motion.position.length() < 2.0, "the cell at the clear point nearest the origin")
	check(sim.arena.is_clear(sim.motion.position, sim.phenotype.radius), "clear")
	check_near(sim.motion.heading, sim._nearest_zone_direction(sim.motion.position).angle(), 1e-6,
		"away from the spawn it faces the nearest zone")
	for key in sim.world.view_set_keys(sim.motion.position):
		check(sim.world.chunk(key) != null, "view-set chunk %s loaded" % key)
	# Written back at once, the save holds the same place (the cell is at the origin's clear point).
	sim.write_position_to_save()
	var back := PlaneSpace.from_save_abs(sim.save.player.position)
	check_near(back[0], at[0] + sim.motion.position.x, 1e-9, "x round trip")
	check_near(back[1], at[1] + sim.motion.position.y, 1e-9, "y round trip")


func test_a_new_game_at_the_spawn_faces_the_spawn_heading() -> void:
	var sim := _endless()
	check_eq(sim.world.origin_x_am, 0.0, "origin at the spawn")
	check_eq(sim.world.origin_y_am, 9.0, "origin at the spawn")
	check_near(sim.motion.heading, -1.5708, 1e-9, "the spawn heading")


## A save inside a shell: the origin is still the saved place, and the cell takes the nearest clear
## point (plan E).
func test_a_restored_place_inside_a_shell_moves_the_cell_not_the_origin() -> void:
	# Chunk (3, 3)'s fake shell is centred at abs (120, 120), radius 1.
	var at := PackedFloat64Array([120.0, 120.0])
	var sim := _endless(at)
	check_eq(sim.world.origin_x_am, 120.0, "origin x")
	check_eq(sim.world.origin_y_am, 120.0, "origin y")
	check(sim.motion.position.length() >= FakeWorldGen.SHELL_R + sim.phenotype.radius - 1e-4,
		"the cell outside the shell (%.3f)" % sim.motion.position.length())
	check(sim.arena.is_clear(sim.motion.position, sim.phenotype.radius), "at a clear point")


func _count(events: Array[Dictionary], type: String) -> int:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type).size()
