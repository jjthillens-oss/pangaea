extends TestCase
## The rules and the simulation stay pure (M1 step 2 layering): no clock, input, OS, scene tree,
## files or global random numbers, so the same seed and intents always give the same world and
## the sim runs headless. Only seeded RandomNumberGenerator instances are allowed.

const DOMAIN_DIR := "res://game/domain"
const SIM_FILES: PackedStringArray = ["res://game/systems/pool_sim.gd", "res://game/systems/plankton_field.gd",
	"res://game/systems/carrion_field.gd", "res://game/systems/sim_intent.gd"]
## part_catalog.gd reads its tuning data from a file (an existing read-only load).
const FILE_ALLOWED: PackedStringArray = ["res://game/domain/part_catalog.gd"]
const BANNED := {
	"global random numbers": "(?<![\\w.])(randf|randi|randomize|randf_range|randi_range|randfn|seed)\\(",
	"the clock": "\\bTime\\.",
	"the OS": "\\bOS\\.",
	"input": "\\bInput\\.",
	"the scene tree": "get_tree\\(",
	"a Node base": "extends\\s+Node",
}
const FILES_PATTERN := "\\b(FileAccess|DirAccess)\\b"


func _scanned() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(DOMAIN_DIR):
		if f.ends_with(".gd"):
			out.append(DOMAIN_DIR + "/" + f)
	out.append_array(SIM_FILES)
	return out


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
