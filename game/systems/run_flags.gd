class_name RunFlags
extends RefCounted
## Launch options given after "--" on the command line (M1 step 2):
##   --seed=N        world seed for a new lineage (a whole number, 0 or more)
##   --slot=PATH     save slot instead of GameSession.DEFAULT_SLOT (user:// or an absolute path)
##   --perf-tour     run the dev performance tour (dev builds only)
## Other arguments are kept in `other` for tools that read their own (the play smoke's --phase).

var seed_value := -1           ## -1: none given
var slot := ""                 ## "": the default slot
var perf_tour := false
var other: PackedStringArray = []
## Flags that were given but not usable, in plain words.
var problems: PackedStringArray = []


static func from_args(args: PackedStringArray) -> RunFlags:
	var flags := RunFlags.new()
	for arg in args:
		if arg.begins_with("--seed="):
			var text := arg.trim_prefix("--seed=")
			if text.is_valid_int() and text.to_int() >= 0:
				flags.seed_value = text.to_int()
			else:
				flags.problems.append("--seed needs a whole number of 0 or more, got '%s'." % text)
		elif arg.begins_with("--slot="):
			var path := arg.trim_prefix("--slot=")
			if path.is_absolute_path() and not path.begins_with("res://"):
				flags.slot = path
			else:
				flags.problems.append("--slot needs a user:// or absolute path, got '%s'." % path)
		elif arg == "--perf-tour":
			flags.perf_tour = true
		else:
			flags.other.append(arg)
	return flags


## The flags this process was launched with.
static func current() -> RunFlags:
	return from_args(OS.get_cmdline_user_args())
