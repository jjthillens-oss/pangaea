extends TestCase
## The Social stage's sim stays pure, like the pool and creature sims (CLAUDE.md; docs/stages/social-plan.md
## section 14): game/systems/social/social_sim.gd uses no clock, input, OS, scene tree, files or global random
## numbers, and the two brains decide from percepts only: they never name the player or reach for the sim.
## game/domain/social/ is covered by tests/test_sim_purity.gd's DOMAIN_DIR scan; this file adds the sim and the
## perception ban, and checks that neither scan is vacuous.

const SIM_FILES: PackedStringArray = ["res://game/systems/social/social_sim.gd"]
const BRAIN_FILES: PackedStringArray = ["res://game/domain/social/companion_brain.gd",
	"res://game/domain/social/hunter_brain.gd"]
const DOMAIN_SOCIAL := "res://game/domain/social"
## The same patterns as tests/test_sim_purity.gd (kept in step by hand: that file is shared).
const SIM_PURITY := "res://tests/test_sim_purity.gd"
const BANNED := {
	"global random numbers": "(?<![\\w.])(randf|randi|randomize|randf_range|randi_range|randfn|seed)\\(",
	"the clock": "\\bTime\\.",
	"the OS": "\\bOS\\.",
	"input": "\\bInput\\.",
	"the scene tree": "get_tree\\(",
	"a Node base": "extends\\s+Node",
}
const FILES_PATTERN := "\\b(FileAccess|DirAccess)\\b"
const PERCEPTION_BANNED := {
	"the player's id": "[\"']player[\"']",
	"the sim": "\\b(SocialSim|PoolSim|CreatureField|CreatureWorldSim|roster)\\b|\\bsim\\.",
}


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


func test_the_social_sim_uses_no_clock_input_files_tree_or_global_random() -> void:
	for path in SIM_FILES:
		check(FileAccess.file_exists(path), "%s exists (the scan is not vacuous)" % path)
		var code := _code_only(FileAccess.get_file_as_string(path))
		check(code.length() > 1000, "%s has code to scan" % path)
		for what in BANNED:
			check(not _matches(code, BANNED[what]), "%s uses %s" % [path, what])
		check(not _matches(code, FILES_PATTERN), "%s reads or writes files" % path)


func test_the_brains_decide_from_percepts_only() -> void:
	for path in BRAIN_FILES:
		check(FileAccess.file_exists(path), "%s exists (the scan is not vacuous)" % path)
		var text := FileAccess.get_file_as_string(path)
		check(text.contains("static func decide("), "%s has its decide()" % path)
		var with_strings := _code_keep_strings(text)
		var code := _code_only(text)
		check(not _matches(with_strings, PERCEPTION_BANNED["the player's id"]), "%s names the player" % path)
		check(not _matches(code, PERCEPTION_BANNED["the sim"]), "%s reaches for the sim" % path)
		for what in BANNED:
			check(not _matches(code, BANNED[what]), "%s uses %s" % [path, what])
		check(not _matches(code, FILES_PATTERN), "%s reads or writes files" % path)


func test_the_perception_ban_catches_what_it_should() -> void:
	# The patterns themselves: a brain that named the player or read the sim would fail.
	check(_matches(_code_keep_strings("var who := \"player\""), PERCEPTION_BANNED["the player's id"]), "a player literal")
	check(_matches(_code_only("var x = sim.individuals()"), PERCEPTION_BANNED["the sim"]), "a sim call")
	check(_matches(_code_only("var s: SocialSim"), PERCEPTION_BANNED["the sim"]), "the sim's class")
	check(not _matches(_code_only("# the sim. in a comment"), PERCEPTION_BANNED["the sim"]), "comments do not count")


func test_the_domain_scan_covers_the_social_rules() -> void:
	var source := FileAccess.get_file_as_string(SIM_PURITY)
	check(source.contains("const DOMAIN_DIR := \"res://game/domain\""), "test_sim_purity scans game/domain")
	check(source.contains("_collect(dir + \"/\" + sub, out)"), "and its subfolders")
	var files := DirAccess.get_files_at(DOMAIN_SOCIAL)
	var gd := 0
	for f in files:
		if f.ends_with(".gd"):
			gd += 1
	check(gd >= 5, "game/domain/social holds the social rules (%d files)" % gd)
	for path in BRAIN_FILES:
		check(path.begins_with(DOMAIN_SOCIAL + "/"), "%s is inside the domain scan" % path)
