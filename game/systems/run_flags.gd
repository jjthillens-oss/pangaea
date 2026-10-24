class_name RunFlags
extends RefCounted
## Launch options given after "--" on the command line (M1 step 2):
##   --seed=N        world seed for a new lineage (a whole number from 0 to MAX_SEED)
##   --slot=PATH     save slot instead of GameSession.DEFAULT_SLOT (a file under user:// or at an
##                   absolute path)
##   --perf-tour     run the dev performance tour (dev builds only)
##   --creature      open the creature stage preview instead of the title (on the lineage slot, --slot's too)
## Other arguments are kept in `other` for tools that read their own (the play smoke's --phase).

## The range a random seed is drawn from (GameSession.start_new), so a flag seed is never one a
## save file cannot hold exactly.
const MAX_SEED := 4294967295
## Longer text could overflow a 64-bit whole number; anything that long is above MAX_SEED anyway.
const MAX_SEED_DIGITS := 18
## A drive letter, a colon and a separator: an absolute Windows path.
const DRIVE_PATTERN := "^[A-Za-z]:[/\\\\]"

var seed_value := -1           ## -1: none given
var slot := ""                 ## "": the default slot
var perf_tour := false
var creature := false
var other: PackedStringArray = []
## Flags that were given but not usable, in plain words.
var problems: PackedStringArray = []


static func from_args(args: PackedStringArray) -> RunFlags:
	var flags := RunFlags.new()
	for arg in args:
		if arg.begins_with("--seed="):
			var text := arg.trim_prefix("--seed=")
			var value := text.to_int() if text.is_valid_int() and text.length() <= MAX_SEED_DIGITS else -1
			if value >= 0 and value <= MAX_SEED:
				flags.seed_value = value
			else:
				flags.problems.append("--seed needs a whole number from 0 to %d, got '%s'." % [MAX_SEED, text])
		elif arg.begins_with("--slot="):
			var path := arg.trim_prefix("--slot=")
			if _is_file_slot(path):
				flags.slot = path
			else:
				flags.problems.append("--slot needs a file under user:// or at an absolute path, got '%s'." % path)
		elif arg == "--perf-tour":
			flags.perf_tour = true
		elif arg == "--creature":
			flags.creature = true
		else:
			flags.other.append(arg)
	return flags


## A file under user:// or at an absolute file system path ("/...", "C:/..." or "C:\..."). Other
## "name:" forms such as res:// and uid:// are not save locations, and a path ending in a separator
## names a folder.
static func _is_file_slot(path: String) -> bool:
	var absolute := path.begins_with("user://") or path.begins_with("/") \
		or RegEx.create_from_string(DRIVE_PATTERN).search(path) != null
	return absolute and not path.get_file().is_empty()


## The flags this process was launched with.
static func current() -> RunFlags:
	return from_args(OS.get_cmdline_user_args())
