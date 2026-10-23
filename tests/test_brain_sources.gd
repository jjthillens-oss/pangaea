extends TestCase
## The brain scales with its cfg, and only with its cfg (S2, plan B.6; D-25, D-55, D-85).
##
## A creature drawn below its entry size runs on CreatureBrain.scale_cfg(cfg, q), which multiplies
## every length and speed key. Two holes would let a length escape that:
## - a cfg key nobody classified: scale_cfg would keep it as it is. The classification walk builds
##   every config the game and the brain tests make and refuses any key whose key_kind() is "";
## - a length read from somewhere else than cfg: a constant of InteractionResolver, PoolArena,
##   PoolLayout or ChunkArena named in creature_brain.gd or creature_senses.gd, or one of the
##   brain's own length and speed constants read outside config(). The source scan refuses both,
##   with comments and string contents stripped first, so prose never trips it.

const BRAIN := "res://game/domain/creature_brain.gd"
const SENSES := "res://game/domain/creature_senses.gd"
## Another class's constant, named in code.
const FOREIGN := "\\b(InteractionResolver|PoolArena|PoolLayout|ChunkArena)\\.[A-Z][A-Z0-9_]*\\b"
## A share, not a length: the default of prey_max_radius_share, read by config().
const FOREIGN_ALLOWED: PackedStringArray = ["InteractionResolver.BITE_SIZE_LIMIT"]
## The brain's own length and speed defaults: named only on their const line and inside config().
const OWN_DEFAULTS: PackedStringArray = ["ARRIVE_HOME_M", "HOME_SLACK_M", "ARRIVE_GOAL_M", "FACE_AT_STANDOFF_M",
	"LEASH_GIVE_UP_M", "FORAGE_PATROL_M", "PATROL_INSET_M", "DEFAULT_TERRITORY_M", "FLEE_LOOKAHEAD_M", "FLEE_EDGE_M",
	"APPROACH_WAIT_MPS", "POST_HYSTERESIS_M"]
const KINDS: PackedStringArray = ["length", "speed", "time", "rate", "share", "count", "angle", "text", "flag"]
const BrainTests := preload("res://tests/test_creature_brain.gd")
## Every relationship rule on, as creatures_m1.json's block (spine 4.2).
const RELATIONSHIPS := {"rules": {"prey_share": true, "intruder_share": true, "fear": true, "no_engage_above": true,
	"outgrown_hazards": true}, "prey_share": 1.0, "intruder_max_radius_share": 1.2, "fear_radius_share": 1.25,
	"tolerance": 1e-6}


## `text` with every comment and the contents of every string removed (the quotes stay), line for
## line, so line numbers still match the file. A backslash escapes the next character in a string.
static func code_only(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line in text.split("\n"):
		var kept := ""
		var quote := ""
		var escaped := false
		for c in line:
			if quote.is_empty():
				if c == "#":
					break
				if c == "\"" or c == "'":
					quote = c
				kept += c
			elif escaped:
				escaped = false
			elif c == "\\":
				escaped = true
			elif c == quote:
				quote = ""
				kept += c
		out.append(kept)
	return out


## The lines (0-based, [first, last]) of `func_name`'s body: from its "static func" line to the line
## before the next line that starts at column 0 with code. [-1, -1] when there is no such function.
static func body_of(lines: PackedStringArray, func_name: String) -> Array:
	var first := -1
	for i in lines.size():
		if first < 0:
			if lines[i].begins_with("static func %s(" % func_name):
				first = i
		elif not lines[i].is_empty() and lines[i][0] != "\t" and lines[i][0] != " ":
			var last := i - 1
			while last > first and lines[last].strip_edges().is_empty():
				last -= 1
			return [first, last]
	return [first, lines.size() - 1] if first >= 0 else [-1, -1]


## Every breach of the scan in one source, as "<where>:<line>: <what>".
static func breaches(source: String, where: String) -> PackedStringArray:
	var out := PackedStringArray()
	var lines := code_only(source)
	var config := body_of(lines, "config")
	var foreign := RegEx.create_from_string(FOREIGN)
	for i in lines.size():
		for m in foreign.search_all(lines[i]):
			if not m.get_string() in FOREIGN_ALLOWED:
				out.append("%s:%d: names %s" % [where, i + 1, m.get_string()])
		if i >= config[0] and i <= config[1]:
			continue
		for name in OWN_DEFAULTS:
			var own := RegEx.create_from_string("\\b%s\\b" % name)
			if own.search(lines[i]) != null and not lines[i].begins_with("const %s " % name):
				out.append("%s:%d: reads %s outside config()" % [where, i + 1, name])
	return out


func _source(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	check(text.length() > 1000, "%s was read" % path)
	return text


# --- the source scan ---

func test_the_brain_and_the_senses_name_no_other_class_length_and_read_their_own_only_in_config() -> void:
	for path in [BRAIN, SENSES]:
		var found := breaches(_source(path), path.get_file())
		check(found.is_empty(), "%s:\n  %s" % [path.get_file(), "\n  ".join(found)])


func test_the_scan_sees_through_comments_and_strings_and_finds_what_it_must() -> void:
	var lines := code_only("a = 1 # PoolArena.ROUTE_MARGIN\nb = \"PoolArena.ROUTE_MARGIN # \\\" x\" + PoolArena.ROUTE_MARGIN")
	check_eq(lines[0], "a = 1 ", "a comment goes")
	check_eq(lines[1], "b = \"\" + PoolArena.ROUTE_MARGIN", "a string's contents go, escaped quote and all; code after it stays")
	var planted := "\n".join([
		"const HOME_SLACK_M := 1.0",
		"static func config(a) -> Dictionary:",
		"\treturn {\"home_slack_m\": HOME_SLACK_M, \"r\": InteractionResolver.BITE_SIZE_LIMIT}",
		"",
		"",
		"static func _seek(mem) -> void:",
		"\tvar w := route(PoolArena.ROUTE_MARGIN, ChunkArena.X_1, PoolLayout.CELL_RADIUS)   # PoolArena.ROUTE_CLEARANCE",
		"\tvar s := HOME_SLACK_M + float(mem.cfg.home_slack_m)",
		"\tvar t := \"InteractionResolver.FEED_REACH and FLEE_EDGE_M\"",
		"\tvar u := InteractionResolver.relative_angle(a, b)",
	])
	var found := breaches(planted, "planted")
	check_eq(found.size(), 4, "three foreign constants and one read outside config(): %s" % [found])
	for want in ["planted:7: names PoolArena.ROUTE_MARGIN", "planted:7: names ChunkArena.X_1",
			"planted:7: names PoolLayout.CELL_RADIUS", "planted:8: reads HOME_SLACK_M outside config()"]:
		check(want in found, "finds " + want)


func test_config_is_found_and_holds_every_default_the_scan_exempts() -> void:
	var lines := code_only(_source(BRAIN))
	var config := body_of(lines, "config")
	check(config[0] > 0 and config[1] - config[0] > 30, "config() found, %d lines long" % (config[1] - config[0] + 1))
	var body := "\n".join(lines.slice(config[0], config[1] + 1))
	for name in OWN_DEFAULTS:
		check(RegEx.create_from_string("\\b%s\\b" % name).search(body) != null, "config() copies %s into cfg" % name)
		check(("const %s " % name) in "\n".join(lines), "%s is a const of the brain" % name)
	var missing := body_of(lines, "no_such_function")
	check(missing[0] == -1 and missing[1] == -1, "a missing function has no body")


func test_world_lengths_equal_the_resolver_and_arena_constants() -> void:
	var w := CreatureBrain.WORLD_LENGTHS
	check_eq(w.size(), 5, "five lengths")
	check_eq(float(w.feed_reach), InteractionResolver.FEED_REACH, "feed reach")
	check_eq(float(w.bite_reach), InteractionResolver.BITE_REACH, "bite reach")
	check_eq(float(w.ram_reach), InteractionResolver.RAM_REACH, "ram reach")
	check_eq(float(w.route_margin), PoolArena.ROUTE_MARGIN, "route margin")
	check_eq(float(w.route_clearance), PoolArena.ROUTE_CLEARANCE, "route clearance")


# --- the classification walk ---

## The configs the game builds (every species of creatures_m1.json and of the test species), and the
## brain tests' blocks with no relationships, with every rule on and with a habit.
func _configs() -> Dictionary:
	var out := {}
	for path in [SpeciesCatalog.DEFAULT_PATH, "res://tests/fixtures/creatures_test.json"]:
		var cat := SpeciesCatalog.load_from(path)
		check(not cat.configs.is_empty(), "%s builds configs" % path.get_file())
		for id in cat.configs:
			out["%s %s" % [path.get_file(), id]] = cat.configs[id]
	var ambush: Dictionary = BrainTests.AMBUSH_BLOCK.duplicate(true)
	ambush["habit"] = {"post_switch": "out_of_sight", "post_rest_s": 8.0, "trail_s": 20.0}
	var rammer: Dictionary = BrainTests.RAMMER_BLOCK.duplicate(true)
	rammer["habit"] = {"post_switch": "nearer_cell", "post_hysteresis_m": 2.0}
	for block in [["ambush", BrainTests.AMBUSH_BLOCK, ambush], ["rammer", BrainTests.RAMMER_BLOCK, rammer]]:
		out[block[0] + " block"] = CreatureBrain.config(block[0], block[1], BrainTests.AI)
		out[block[0] + " block, every rule, a habit"] = CreatureBrain.config(block[0], block[2], BrainTests.AI, RELATIONSHIPS)
	return out


func test_every_cfg_key_is_classified_and_every_classified_key_is_built() -> void:
	var walked := {}
	var configs := _configs()
	for name in configs:
		for leaf in BrainTests.leaves(configs[name]):
			var kind := CreatureBrain.key_kind(leaf[0])
			walked[leaf[0]] = true
			check(kind in KINDS, "%s: '%s' is classified (got '%s')" % [name, leaf[0], kind])
			if kind == "length" or kind == "speed":
				check(leaf[1] is float, "%s: '%s' is a float, so it can be scaled" % [name, leaf[0]])
	for path in CreatureBrain.KEY_KINDS:
		check(walked.has(path), "'%s' is a key some config builds" % path)
		check(CreatureBrain.KEY_KINDS[path] in KINDS, "'%s' has a known kind" % path)
	check(walked.size() >= 70, "the walk reached the whole cfg (%d keys)" % walked.size())


func test_an_unknown_key_has_no_kind() -> void:
	for path in ["foo_m", "attack", "attack.foo_m", "speeds", "speeds.sprint", "", "ATTACK.REACH"]:
		check_eq(CreatureBrain.key_kind(path), "", path)
	check_eq(CreatureBrain.key_kind("attack.burst_speed"), "speed", "the spine's example")
	check_eq(CreatureBrain.key_kind("rest_ticks"), "time", "a list of ticks is a time")
