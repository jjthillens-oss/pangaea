extends SceneTree
## Records tests/fixtures/save_v3_s2.json (S2 T4.4; build plan 7.1 and BP-18; gate S2G19): a save
## as an S2 build writes it for a lineage that has grown to size 2, so every later build has a real
## v3 file to load, continue and, from S3 on, migrate. It is not part of the test suite:
## test_persistence and test_endless_save read what it wrote. v3 is frozen once S2 ships, so the
## file is recorded once and committed; recording it again needs a reason in the commit message.
##
## The save is a founded omnivore lineage (seed 2024) with every S2 field away from its default: size
## 2 with a part-full ring, the checkpoint where it last settled, the cell a little way from it,
## and a ledger that holds a find of each type at both sizes (D-33, D-71). It goes through
## PersistenceService.save_to, the S2 writer (validation, sorted keys, full precision, the
## read-back check), into a scratch slot under user://, and the written text is copied to the
## fixture path, so no backup lands beside the fixture.
##
##   godot --headless --path . --script res://tools/godot/record_save_v3.gd [-- --out=<path>]
## --out defaults to the fixture. Exit code: 0 written, 1 refused by the writer, 2 an unwritable
## file or a bad argument.

const OUT := "res://tests/fixtures/save_v3_s2.json"
const SCRATCH := "user://record_save_v3/slot.json"
const SEED := 2024
const BODY := "omnivore"
const POINTS := 16
## At size 2 the ring is 120 (world_cell.json growth.rings): 37.5 is under a third of it.
const GROWTH := {"size": 2, "meter": 37.5}
## Absolute am, as every v3 place; build plan 7.1's checkpoint.
const CHECKPOINT := {"x_am": 812.25, "y_am": -40.0625, "heading": 1.25, "size": 2}
## The cell swam on from its checkpoint: absolute am.
const POSITION := [830.5, -52.375]
## In find order: both food looks of size 1, the fixed rare place, then size 2's algae ball and a
## landmark (a landmark pays its lump only at the build top, size 2 in S2).
const DISCOVERIES := [
	{"type": "food", "id": "plankton", "size": 1},
	{"type": "food", "id": "carrion", "size": 1},
	{"type": "place", "id": "giant_husk", "size": 1},
	{"type": "food", "id": "algae_ball", "size": 2},
	{"type": "landmark", "id": "landmark_arch", "size": 2},
]


func _initialize() -> void:
	var out := OUT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		else:
			push_error("record_save_v3: unknown argument %s" % arg)
			quit(2)
			return
	var catalog := PartCatalog.load_from()
	var save := compose(catalog)
	if save == null:
		quit(1)
		return
	var err := PersistenceService.new(catalog).save_to(SCRATCH, save)
	if err != OK:
		push_error("record_save_v3: the writer refused the save: %s" % error_string(err))
		quit(1)
		return
	var text := FileAccess.get_file_as_string(SCRATCH)
	for leftover in [SCRATCH, SCRATCH + PersistenceService.BACKUP_SUFFIX]:
		if FileAccess.file_exists(leftover):
			DirAccess.remove_absolute(leftover)
	DirAccess.remove_absolute(SCRATCH.get_base_dir())
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		push_error("record_save_v3: cannot write %s" % out)
		quit(2)
		return
	f.store_string(text)
	f.close()
	print("record_save_v3: wrote %s (%s, size %d)" % [out, save.lineage_id, save.growth.size])
	quit(0)


## The save the fixture holds, before the writer stamps saved_at_unix. The lineage id and the
## genome ids are new each call; every other field is this file's constants. null when the body
## cannot be founded.
static func compose(catalog: PartCatalog) -> SaveGame:
	var founded := Lineage.found(SEED, BuildInfo.build_id(), catalog, BODY)
	if not founded.ok:
		push_error("record_save_v3: %s" % "; ".join(founded.errors))
		return null
	var save: SaveGame = founded.save
	save.adaptation_points = POINTS
	save.player["position"] = PlaneSpace.to_save_abs(POSITION[0], POSITION[1])
	save.growth = GROWTH.duplicate(true)
	save.checkpoint = CHECKPOINT.duplicate(true)
	save.discoveries = DISCOVERIES.duplicate(true)
	return save
