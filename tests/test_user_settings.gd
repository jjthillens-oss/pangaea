extends TestCase
## Player memory (S2 T4.2; build plan BP-3 and 7.2; S2G22): UserSettings keeps the hints followed and
## the lineages that have seen the first giant pass in user://player_memory.cfg, apart from the
## player's settings, which are main's SettingsService on user://settings.cfg. Every test writes to a
## per-process folder under user://test_saves, never to the real files.
##
## The survival case runs both ways in one shared folder, as in user://: saving player memory leaves
## settings.cfg byte-identical, and SettingsService.save_file leaves player_memory.cfg byte-identical.

const SaveFolder := preload("res://tests/save_folder.gd")
const HINTS := ["eat_well", "sea_goes_on", "green_rim"]
const LINEAGES := ["lineage_3f9a1c07b2e84d65", "lineage_e3b989a856cc79e7"]

var _swept := false
var path := ""
## The player's settings in the test folder: the file main's SettingsService owns (its PATH's name).
var settings_path := ""


func before_each() -> void:
	if not _swept:
		SaveFolder.sweep_stale()
		_swept = true
	SaveFolder.clear()
	DirAccess.make_dir_recursive_absolute(SaveFolder.dir())
	path = SaveFolder.path(UserSettings.PATH.get_file())
	settings_path = SaveFolder.path(SettingsService.PATH.get_file())


func after_each() -> void:
	SaveFolder.clear()


func _write_raw(at: String, text: String) -> void:
	var f := FileAccess.open(at, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _remembering() -> UserSettings:
	var memory := UserSettings.new()
	memory.hints_followed = PackedStringArray(HINTS)
	memory.giant_pass_lineages = PackedStringArray(LINEAGES)
	return memory


func _is_default(memory: UserSettings) -> bool:
	return memory != null and memory.hints_followed.is_empty() and memory.giant_pass_lineages.is_empty()


## The player's settings as the game writes them: a growth trigger, reduce camera motion and a
## rebound grow key, saved by main's SettingsService into this test's folder.
func _save_settings() -> SettingsService:
	var service := SettingsService.new(settings_path)
	check(service.set_value("gameplay/growth_trigger", "press"), "the trigger set")
	check(service.set_value("accessibility/reduce_camera_motion", true), "reduce motion set")
	service.settings.bindings["grow"] = PackedStringArray(["key:72"])
	check_eq(service.save_file(), OK, "settings saved")
	return service


func test_player_memory_is_its_own_file_beside_the_settings() -> void:
	check_eq(UserSettings.PATH, "user://player_memory.cfg", "the path")
	check_eq(UserSettings.PATH.get_base_dir(), SettingsService.PATH.get_base_dir(), "the settings' folder")
	check(UserSettings.PATH.get_file() != SettingsService.PATH.get_file(), "not the settings file")
	check(_is_default(UserSettings.new()), "a new memory remembers nothing")


func test_what_is_saved_loads_back() -> void:
	var memory := _remembering()
	memory.hints_followed.append("a hint, with \"quotes\" and é")
	check_eq(memory.save_to(path), OK, "saved")
	check(not FileAccess.file_exists(path + UserSettings.TEMP_SUFFIX), "no temp file left")
	var loaded := UserSettings.load_from(path)
	check_eq(loaded.hints_followed, memory.hints_followed, "hints followed")
	check_eq(loaded.giant_pass_lineages, memory.giant_pass_lineages, "giant pass lineages")
	# The file is build plan 7.2's: [hints] followed and [ambience] giant_pass_lineages, nothing else.
	var cfg := ConfigFile.new()
	check_eq(cfg.load(path), OK, "a plain config file")
	check_eq(cfg.get_sections(), PackedStringArray(["hints", "ambience"]), "its sections")
	check_eq(cfg.get_section_keys("hints"), PackedStringArray(["followed"]), "the hints key")
	check_eq(cfg.get_section_keys("ambience"), PackedStringArray(["giant_pass_lineages"]), "the ambience key")
	check_eq(cfg.get_value("hints", "followed"), memory.hints_followed, "stored as a PackedStringArray")
	# Saving again replaces the file.
	loaded.giant_pass_lineages.append("lineage_0000000000000001")
	check_eq(loaded.save_to(path), OK, "saved again")
	check_eq(UserSettings.load_from(path).giant_pass_lineages.size(), LINEAGES.size() + 1, "the new lineage is kept")


func test_saving_makes_its_folder() -> void:
	var folder := SaveFolder.path("memory")
	var at := folder + "/" + UserSettings.PATH.get_file()
	check_eq(_remembering().save_to(at), OK, "saved into a folder that did not exist")
	check_eq(UserSettings.load_from(at).hints_followed, PackedStringArray(HINTS), "and loads")
	DirAccess.remove_absolute(at)
	DirAccess.remove_absolute(folder)


func test_a_missing_file_gives_the_defaults_and_creates_nothing() -> void:
	var folder := SaveFolder.path("nowhere")
	check(_is_default(UserSettings.load_from(folder + "/" + UserSettings.PATH.get_file())), "defaults")
	check(not DirAccess.dir_exists_absolute(folder), "no folder made")


func test_a_damaged_file_gives_the_defaults_and_stays_until_the_next_save() -> void:
	# The first section reads before the damage, so ignoring the parse error would keep "eat_well".
	# The engine logs the parse error; the load itself never fails.
	var damaged := "[hints]\nfollowed=PackedStringArray(\"eat_well\")\n\n[ambience\ngiant_pass_lineages="
	_write_raw(path, damaged)
	check(_is_default(UserSettings.load_from(path)), "defaults, never an error")
	check_eq(FileAccess.get_file_as_string(path), damaged, "the damaged file is left as it was")
	check_eq(_remembering().save_to(path), OK, "the next save replaces it")
	check_eq(UserSettings.load_from(path).hints_followed, PackedStringArray(HINTS), "and loads")
	_write_raw(path, "")
	check(_is_default(UserSettings.load_from(path)), "an empty file gives the defaults")


func test_a_value_of_the_wrong_type_falls_back_to_its_default_alone() -> void:
	for wrong in ["7", "\"eat_well\"", "[\"eat_well\"]", "PackedInt32Array(1, 2)", "{\"eat_well\": true}"]:
		_write_raw(path, "[hints]\nfollowed=%s\n\n[ambience]\ngiant_pass_lineages=PackedStringArray(\"lineage_a\")\n" % wrong)
		var loaded := UserSettings.load_from(path)
		check_eq(loaded.hints_followed, PackedStringArray(), "followed = %s falls back to empty" % wrong)
		check_eq(loaded.giant_pass_lineages, PackedStringArray(["lineage_a"]), "the other key is kept beside %s" % wrong)


func test_unknown_sections_and_keys_are_ignored() -> void:
	_write_raw(path, "[hints]\nfollowed=PackedStringArray(\"eat_well\")\nshown=3\n\n[future]\nveil=true\n\n"
		+ "[ambience]\ngiant_pass_lineages=PackedStringArray(\"lineage_a\")\n")
	var loaded := UserSettings.load_from(path)
	check_eq(loaded.hints_followed, PackedStringArray(["eat_well"]), "hints read")
	check_eq(loaded.giant_pass_lineages, PackedStringArray(["lineage_a"]), "lineages read")
	check_eq(loaded.save_to(path), OK, "saved")
	var cfg := ConfigFile.new()
	cfg.load(path)
	check_eq(cfg.get_sections(), PackedStringArray(["hints", "ambience"]), "only its own sections are written")
	check_eq(cfg.get_section_keys("hints"), PackedStringArray(["followed"]), "only its own keys")


func test_a_failed_write_leaves_the_old_file() -> void:
	check_eq(_remembering().save_to(path), OK, "saved")
	var before := FileAccess.get_file_as_bytes(path)
	# A folder where the temporary file goes: the write cannot start.
	DirAccess.make_dir_recursive_absolute(path + UserSettings.TEMP_SUFFIX)
	var changed := UserSettings.new()
	changed.hints_followed = PackedStringArray(["green_rim"])
	check(changed.save_to(path) != OK, "the write fails")
	check_eq(FileAccess.get_file_as_bytes(path), before, "the old file is unchanged")
	DirAccess.remove_absolute(path + UserSettings.TEMP_SUFFIX)


func test_a_write_that_cannot_be_moved_into_place_leaves_no_temp_file() -> void:
	# The path is a folder, so the final rename fails after the temporary file is written.
	var folder := SaveFolder.path("folder.cfg")
	DirAccess.make_dir_recursive_absolute(folder)
	check(_remembering().save_to(folder) != OK, "the write fails")
	check(not FileAccess.file_exists(folder + UserSettings.TEMP_SUFFIX), "no temp file left")
	DirAccess.remove_absolute(folder)


func test_saving_player_memory_leaves_the_settings_file_byte_identical() -> void:
	# S2G22's survival case, UserSettings' half: the two files share a folder, as in user://.
	_save_settings()
	var bytes := FileAccess.get_file_as_bytes(settings_path)
	check(bytes.size() > 0, "settings.cfg written")
	var memory := _remembering()
	check_eq(memory.save_to(path), OK, "saved")
	memory.hints_followed.append("they_flee")
	check_eq(memory.save_to(path), OK, "saved again")
	check_eq(FileAccess.get_file_as_bytes(settings_path), bytes, "settings.cfg is byte-identical")
	check_eq(UserSettings.load_from(path).hints_followed.size(), HINTS.size() + 1, "and player memory holds its own")
	var settings := SettingsService.new(settings_path)
	check(settings.load_file().is_empty(), "the settings load without problems")
	check_eq(settings.load_source, "file", "from the file")
	check_eq(settings.growth_trigger(), "press", "the trigger kept")
	check(settings.reduce_camera_motion(), "reduce motion kept")
	check_eq(settings.first_code("grow", "keys"), "key:72", "the grow key kept")


func test_saving_the_settings_leaves_player_memory_byte_identical() -> void:
	# S2G22's survival case, SettingsService's half: main's save writes a new ConfigFile holding only
	# its own sections, and it must never touch player_memory.cfg beside it. The second save replaces
	# a settings.cfg that is already there.
	check_eq(_remembering().save_to(path), OK, "player memory saved")
	var bytes := FileAccess.get_file_as_bytes(path)
	var service := _save_settings()
	check(service.set_value("gameplay/growth_trigger", "auto"), "the trigger changed")
	check_eq(service.save_file(), OK, "settings saved again")
	check(FileAccess.file_exists(settings_path), "settings.cfg is there")
	check_eq(FileAccess.get_file_as_bytes(path), bytes, "player_memory.cfg is byte-identical")
	var loaded := UserSettings.load_from(path)
	check_eq(loaded.hints_followed, PackedStringArray(HINTS), "hints followed survive")
	check_eq(loaded.giant_pass_lineages, PackedStringArray(LINEAGES), "giant pass lineages survive")
	var settings := SettingsService.new(settings_path)
	check(settings.load_file().is_empty(), "the settings load without problems")
	check_eq(settings.growth_trigger(), "auto", "the settings hold their own")
