extends TestCase
## Endless saves (S1, gate G11): Continue lands where the save was made, within a micrometre, at
## 5 km and 100 km from home; the position goes through the file as float64 (PlaneSpace.to_save_abs,
## full precision) and never through a float32 Vector2. An endless save is a plain v2 save, so a
## pool session reads it too: its far position is not a clear place in the pool, and the cell
## starts at the spawn.
##
## tests/fixtures/save_v2_endless_5km.json is a real v2 save written once by write_fixture() and
## committed. The suite never calls write_fixture(); to write the file again, run by hand:
##
##     printf 'extends SceneTree\nfunc _init():\n\tload("res://tests/test_endless_save.gd").write_fixture()\n\tquit()\n' > /tmp/write_fixture.gd
##     godot --headless --path . --script /tmp/write_fixture.gd

const SaveFolder := preload("res://tests/save_folder.gd")
const SwimBot := preload("res://game/dev/swim_bot.gd")
const FIXTURE := "res://tests/fixtures/save_v2_endless_5km.json"
## The fixture's place: absolute am at size 1, 5 km east of home. A float32 cannot hold its x.
const FIXTURE_X := 5000.123456789012
const FIXTURE_Y := -3.25
const FIXTURE_SEED := 4242
## T1's fixture world: the shipped settings with their content on the minimal fixtures, until T4's land.
const WORLD := "res://tests/fixtures/world/world_min.json"
## G11: Continue lands within a micrometre of the pre-save position, on each axis.
const MICROMETRE := 1e-6
## How far a Continue may move a cell out of a shell: _clear_point_near's 40 rings of 0.5 tm.
const CLEAR_SEARCH_TM := 20.0

var slot := ""
var _swept := false


func before_each() -> void:
	if not _swept:
		SaveFolder.sweep_stale()
		_swept = true
	SaveFolder.clear()
	slot = SaveFolder.path("endless_slot.json")


func after_each() -> void:
	SaveFolder.clear()


## Writes the fixture: a founded omnivore lineage (seed 4242) at FIXTURE_X, FIXTURE_Y, through
## PersistenceService.save_to, so the file is a v2 save in the shipped format. By hand only.
static func write_fixture() -> void:
	var catalog := PartCatalog.load_from()
	var founded := Lineage.found(FIXTURE_SEED, "test+dev", catalog, "omnivore")
	var save: SaveGame = founded.save
	save.player["position"] = PlaneSpace.to_save_abs(FIXTURE_X, FIXTURE_Y)
	var path := ProjectSettings.globalize_path(FIXTURE)
	var err := PersistenceService.new(catalog).save_to(path, save)
	print("wrote %s: %s" % [path, error_string(err)])


## Copies the fixture into this test's slot, as a player's file would be.
func _fixture_in_slot() -> void:
	DirAccess.make_dir_recursive_absolute(SaveFolder.dir())
	var file := FileAccess.open(slot, FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string(FIXTURE))
	file.close()


func test_the_5km_fixture_is_a_v2_save_holding_the_far_place() -> void:
	var loaded := PersistenceService.new(PartCatalog.load_from()).load_from(FIXTURE)
	check(loaded.ok, "the fixture loads: %s" % [loaded.errors])
	if not loaded.ok:
		return
	var save: SaveGame = loaded.save
	check_eq(save.world_seed, FIXTURE_SEED, "the seed")
	check_eq(Lineage.starting_body_of(save.genome, PartCatalog.load_from()), "omnivore", "the body")
	var at := PlaneSpace.from_save_abs(save.player.position)
	check_eq(at.size(), 2, "an absolute position")
	if at.size() == 2:
		# Godot's parse is within one ulp (about 9e-13 here), not exact.
		check_near(at[0], FIXTURE_X, 1e-9, "x")
		check_near(at[1], FIXTURE_Y, 1e-9, "y")
		check(Vector2(at[0], at[1]).x != at[0], "x is one a float32 cannot hold")


func test_a_pool_session_loads_the_endless_5km_fixture_at_the_spawn() -> void:
	_fixture_in_slot()
	var session := GameSession.new(slot)
	var peek := session.peek_slot()
	check(peek.ok and peek.errors.is_empty(), "the slot reads as a usable save: %s" % [peek.errors])
	var r := session.continue_run()
	check(r.ok, "continued: %s" % [r.errors])
	if not r.ok:
		return
	check_eq(r.source, "primary", "from the file itself")
	check(r.errors.is_empty(), "no error: %s" % [r.errors])
	var sim := session.sim
	check_eq(sim.motion.position, session.layout.spawn, "5 km out is not in the pool: the cell starts at the spawn")
	check_eq(sim.motion.heading, session.layout.spawn_heading, "facing the spawn heading")
	check(sim.arena.is_clear(sim.motion.position, sim.phenotype.radius), "in open water")
	check_eq(sim.save.lineage_id, peek.summary.lineage_id, "the same lineage")
	check(not session.dirty, "nothing unsaved right after continuing")


## A new endless lineage, saved to the slot.
func _endless(seed_value: int) -> GameSession:
	var session := GameSession.new(slot, PoolLayout.DEFAULT_PATH, SpeciesCatalog.DEFAULT_PATH, WORLD)
	var started := session.start_new("omnivore", seed_value)
	check(started.ok, "an endless lineage starts: %s" % [started.errors])
	return session


## Continues the slot in a new endless session (as a new launch would); null when it fails.
func _continue() -> GameSession:
	var again := GameSession.new(slot, PoolLayout.DEFAULT_PATH, SpeciesCatalog.DEFAULT_PATH, WORLD)
	var r := again.continue_run()
	check(r.ok, "continued: %s" % [r.errors])
	return again if r.ok else null


## Swims straight along `direction` for `ticks`, driven by a SwimBot.
static func _swim(sim: PoolSim, ticks: int, direction: Vector2) -> void:
	var bot = SwimBot.new(direction)
	for i in ticks:
		sim.step(bot.next_intent(sim))


## Teleports to (x, y) am, swims 60 ticks, saves, continues in a new session, and checks the
## continued cell is within a micrometre of where it was saved on each axis. Returns the new session.
func _save_and_continue_at(x: float, y: float, seed_value: int) -> GameSession:
	var session := _endless(seed_value)
	if session.sim == null:
		return null
	var sim := session.sim
	check(sim.debug_teleport_abs(x, y), "teleported to (%.6f, %.6f)" % [x, y])
	_swim(sim, 60, Vector2(0.6, -0.8))
	var before := sim.absolute_position_am()
	# A float32 anywhere on the path would show: x is not one a float32 holds, and its float32 is
	# far more than a micrometre off (0.24 mm at 5 km). y near home could not show it.
	check(float(Vector2(before[0], 0.0).x) != before[0], "x is beyond float32: (%.9f, %.9f)" % [before[0], before[1]])
	check(session.save_now().ok, "saved")
	var again := _continue()
	if again == null:
		return null
	var after := again.sim.absolute_position_am()
	check(absf(after[0] - before[0]) <= MICROMETRE and absf(after[1] - before[1]) <= MICROMETRE,
		"within a micrometre: saved (%.9f, %.9f), continued (%.9f, %.9f), off by (%s, %s)"
		% [before[0], before[1], after[0], after[1], after[0] - before[0], after[1] - before[1]])
	return again


func test_continue_at_5_km_lands_within_a_micrometre_of_the_pre_save_position() -> void:
	_save_and_continue_at(5000.123456789012, -3.25, 4242)


func test_continue_at_100_km_lands_within_a_micrometre_of_the_pre_save_position() -> void:
	_save_and_continue_at(100000.3, -100000.7, 4243)


func test_an_endless_session_loads_the_5km_fixture_near_its_position() -> void:
	_fixture_in_slot()
	var session := _continue()
	if session == null:
		return
	var sim := session.sim
	check(sim.is_endless(), "endless")
	var at := sim.absolute_position_am()
	var dx := at[0] - FIXTURE_X
	var dy := at[1] - FIXTURE_Y
	check(dx * dx + dy * dy <= CLEAR_SEARCH_TM * CLEAR_SEARCH_TM, "within %.0f tm of the saved place: (%.9f, %.9f)"
		% [CLEAR_SEARCH_TM, at[0], at[1]])
	check(sim.arena.is_clear(sim.motion.position, sim.phenotype.radius), "in open water")
	var saved_local := sim.world.local_of_abs(FIXTURE_X, FIXTURE_Y)
	if sim.arena.is_clear(saved_local, sim.phenotype.radius):
		check(absf(dx) <= MICROMETRE and absf(dy) <= MICROMETRE, "the saved place is clear, so the cell is there: off by (%s, %s)"
			% [dx, dy])
	check(not session.dirty, "nothing unsaved right after continuing")


func test_slow_ten_save_and_continue_cycles_do_not_drift() -> void:
	var session := _endless(4245)
	if session.sim == null:
		return
	check(session.sim.debug_teleport_abs(100000.3, -100000.7), "100 km out")
	for cycle in 10:
		_swim(session.sim, 60, Vector2.from_angle(cycle * 0.7))
		var before := session.sim.absolute_position_am()
		check(session.save_now().ok, "cycle %d saved" % cycle)
		var again := _continue()
		if again == null:
			return
		var after := again.sim.absolute_position_am()
		check(absf(after[0] - before[0]) <= MICROMETRE and absf(after[1] - before[1]) <= MICROMETRE,
			"cycle %d: off by (%s, %s)" % [cycle, after[0] - before[0], after[1] - before[1]])
		session = again
