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
const FIXTURE := "res://tests/fixtures/save_v2_endless_5km.json"
## The fixture's place: absolute am at size 1, 5 km east of home. A float32 cannot hold its x.
const FIXTURE_X := 5000.123456789012
const FIXTURE_Y := -3.25
const FIXTURE_SEED := 4242

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
