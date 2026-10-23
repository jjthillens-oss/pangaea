extends TestCase
## The rules and the simulation stay pure (M1 step 2 layering): no clock, input, OS, scene tree,
## files or global random numbers, so the same seed and intents always give the same world and
## the sim runs headless. Only seeded RandomNumberGenerator instances are allowed. The endless
## world's sim files live in WORLD_DIR (S1 spine D-1), and every script there is scanned as it lands.

const DOMAIN_DIR := "res://game/domain"
const SIM_FILES: PackedStringArray = ["res://game/systems/pool_sim.gd", "res://game/systems/plankton_field.gd",
	"res://game/systems/carrion_field.gd", "res://game/systems/sim_intent.gd", "res://game/systems/species_catalog.gd",
	"res://game/systems/creature_field.gd"]
## Every .gd in it and its subfolders is scanned, like DOMAIN_DIR (S1: the endless world's sim).
const WORLD_DIR := "res://game/systems/world"
## These read their tuning data from a file (read-only loads): the part and species catalogs, and the
## endless world's four loaders (S1 spine 3.1). world_content.gd only calls the loaders.
const FILE_ALLOWED: PackedStringArray = ["res://game/domain/part_catalog.gd", "res://game/systems/species_catalog.gd",
	"res://game/systems/world/world_config.gd", "res://game/systems/world/tile_catalog.gd",
	"res://game/systems/world/home_block.gd", "res://game/systems/world/placement_kit.gd"]
## Files that must be scanned once they exist (non-vacuity: a scan that silently skipped them would
## pass): the world's generator and stream, and the endless domain rules.
const MUST_SCAN: PackedStringArray = ["res://game/systems/world/world_gen.gd", "res://game/systems/world/world_stream.gd",
	"res://game/domain/chunk_arena.gd", "res://game/domain/rebase_shift.gd", "res://game/domain/world_hash.gd",
	"res://game/systems/world/growth.gd", "res://game/systems/world/remnant_field.gd", "res://game/domain/relationships.gd"]
## S2's sim files (S2 gate S2G27): the growth economy, the remnants and the relationship rules. They
## have landed, so each must exist as well as be scanned: a move or a rename would otherwise take it
## out of the scan with nothing failing.
const S2_FILES: PackedStringArray = ["res://game/systems/world/growth.gd", "res://game/systems/world/remnant_field.gd",
	"res://game/domain/relationships.gd"]
const BANNED := {
	"global random numbers": "(?<![\\w.])(randf|randi|randomize|randf_range|randi_range|randfn|seed)\\(",
	"the clock": "\\bTime\\.",
	"the OS": "\\bOS\\.",
	"input": "\\bInput\\.",
	"the scene tree": "get_tree\\(",
	"a Node base": "extends\\s+Node",
}
const FILES_PATTERN := "\\b(FileAccess|DirAccess)\\b"
## Creature perception and decisions (M1 step 3) work only from the percepts they are given: they
## never name the player or reach for the sim's tables.
const PERCEPTION_FILES: PackedStringArray = ["res://game/domain/creature_senses.gd", "res://game/domain/creature_brain.gd"]
const PERCEPTION_BANNED := {
	"the player's id": "[\"']player[\"']",
	"the sim": "\\b(PoolSim|CreatureField|roster)\\b|\\bsim\\.",
}


func _scanned() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(DOMAIN_DIR):
		if f.ends_with(".gd"):
			out.append(DOMAIN_DIR + "/" + f)
	out.append_array(SIM_FILES)
	_gd_files_under(WORLD_DIR, out)
	return out


## Every .gd under dir, subfolders included; nothing when dir does not exist.
static func _gd_files_under(dir: String, out: PackedStringArray) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in DirAccess.get_directories_at(dir):
		_gd_files_under(dir.path_join(sub), out)


## The source with comments and string contents removed, so prose cannot trip the scan.
func _code_only(text: String) -> String:
	var out := PackedStringArray()
	for line in text.split("\n"):
		var kept := ""
		var quote := ""
		for c in line:
			if quote.is_empty():
				if c == "#":
					break
				if c == "\"" or c == "'":
					quote = c
				kept += c
			elif c == quote:
				quote = ""
				kept += c
		out.append(kept)
	return "\n".join(out)


## The source with comments removed but strings kept, so a "player" literal is still seen.
func _code_keep_strings(text: String) -> String:
	var out := PackedStringArray()
	for line in text.split("\n"):
		var kept := ""
		var quote := ""
		for c in line:
			if quote.is_empty():
				if c == "#":
					break
				if c == "\"" or c == "'":
					quote = c
			elif c == quote:
				quote = ""
			kept += c
		out.append(kept)
	return "\n".join(out)


func _matches(code: String, pattern: String) -> bool:
	var re := RegEx.new()
	re.compile(pattern)
	return re.search(code) != null


func test_rules_and_sim_use_no_clock_input_files_tree_or_global_random() -> void:
	var files := _scanned()
	check(files.size() >= 15, "scanned the domain and the sim (%d files)" % files.size())
	for path in files:
		var code := _code_only(FileAccess.get_file_as_string(path))
		check(not code.is_empty(), "%s readable" % path)
		for what in BANNED:
			check(not _matches(code, BANNED[what]), "%s uses %s" % [path, what])
		if not FILE_ALLOWED.has(path):
			check(not _matches(code, FILES_PATTERN), "%s touches files" % path)


func test_the_scan_covers_the_world_directory() -> void:
	var files := _scanned()
	var world := PackedStringArray()
	_gd_files_under(WORLD_DIR, world)
	for path in world:
		check(files.has(path), "%s is scanned" % path)
	for path in MUST_SCAN:
		if FileAccess.file_exists(path):
			check(files.has(path), "%s exists and is scanned" % path)
	check(files.has("res://game/domain/world_hash.gd"), "the endless hash (T0.1) is scanned through the domain directory")
	for path in S2_FILES:
		check(FileAccess.file_exists(path), "%s exists (S2G27)" % path)
		check(files.has(path), "%s is scanned (S2G27)" % path)
		check(MUST_SCAN.has(path), "%s is in MUST_SCAN" % path)
	for path in FILE_ALLOWED:
		check(not path.begins_with(WORLD_DIR) or path.get_file() in ["world_config.gd", "tile_catalog.gd", "home_block.gd", "placement_kit.gd"],
			"only the four loaders may touch files in the world directory (%s)" % path)
	print("test-sim-purity: %d files scanned, %d in %s" % [files.size(), world.size(), WORLD_DIR])


func test_the_scan_catches_what_it_is_for() -> void:
	var bad := "var x := randf()\nvar t := Time.get_ticks_msec()\nextends Node3D\nget_tree().quit()\nvar f := FileAccess.open(p, 1)"
	check(_matches(_code_only(bad), BANNED["global random numbers"]), "global randf")
	check(_matches(_code_only(bad), BANNED["the clock"]), "Time")
	check(_matches(_code_only(bad), BANNED["a Node base"]), "extends Node3D")
	check(_matches(_code_only(bad), BANNED["the scene tree"]), "get_tree")
	check(_matches(_code_only(bad), FILES_PATTERN), "FileAccess")
	var fine := "var x := rng.randf()  # randf() in a comment\nvar s := \"Time.now\"\nvar r := my_randf(2)"
	check(not _matches(_code_only(fine), BANNED["global random numbers"]), "seeded RNG, comments and other names are fine")
	check(not _matches(_code_only(fine), BANNED["the clock"]), "text in strings is fine")


func test_creature_perception_never_names_the_player_or_the_sim() -> void:
	for path in PERCEPTION_FILES:
		var code := _code_keep_strings(FileAccess.get_file_as_string(path))
		check(code.contains("static func"), "%s readable" % path)
		for what in PERCEPTION_BANNED:
			check(not _matches(code, PERCEPTION_BANNED[what]), "%s names %s" % [path, what])


func test_the_perception_scan_keeps_strings_and_drops_comments() -> void:
	var bad := "if p.id == \"player\":\nvar s := 'player'\nvar x := sim.motion\nvar f: CreatureField\nvar r = roster[0]\nPoolSim.DT"
	var code := _code_keep_strings(bad)
	check(_matches(code, PERCEPTION_BANNED["the player's id"]), "a \"player\" literal")
	check(_matches(code.split("\n")[1], PERCEPTION_BANNED["the player's id"]), "a 'player' literal")
	for line in code.split("\n").slice(2):
		check(_matches(line, PERCEPTION_BANNED["the sim"]), "the sim: %s" % line)
	check(not _matches(_code_only(bad), PERCEPTION_BANNED["the player's id"]), "_code_only would miss the literal, hence the new helper")
	var fine := "# the player's \"player\" id, sim.motion\nvar players := 2\nvar simulated := true\nvar s := \"a # in a string\" # a 'player' comment"
	var kept := _code_keep_strings(fine)
	check(not _matches(kept, PERCEPTION_BANNED["the player's id"]), "comments and other words are fine")
	check(not _matches(kept, PERCEPTION_BANNED["the sim"]), "simulated and players are other names")
	check(kept.contains("a # in a string"), "a # inside a string is kept")
