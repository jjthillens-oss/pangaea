class_name UserSettings
extends RefCounted
## What this computer remembers about its player (S2; build plan BP-3, 7.2): the hints already
## followed and the lineages that have seen the first giant pass. It is per machine, never in a save:
## a hint is about the player, not the lineage (D-43), and the giant pass comes once per lineage on
## this computer (D-42).
##
## It is player memory only. The player's settings, including the growth trigger and reduce camera
## motion, are main's SettingsService on user://settings.cfg; this file never reads or writes that
## one, and the sim gets the trigger through SimIntent, never from here.
##
## The file:
##     [hints]     followed = PackedStringArray(...)
##     [ambience]  giant_pass_lineages = PackedStringArray(...)
## A missing or damaged file gives the defaults, never an error, and the damaged file stays until the
## next save replaces it. Unknown sections and keys are ignored (and not written back), and a value
## of the wrong type falls back to its default. A write goes to a temporary file first, so one that
## fails leaves the old file as it was, and no temporary file.

const PATH := "user://player_memory.cfg"
const TEMP_SUFFIX := ".tmp"

## Hint ids the player has followed; each is never shown again.
var hints_followed := PackedStringArray()
## Lineage ids that have had their first giant pass on this computer.
var giant_pass_lineages := PackedStringArray()


static func load_from(path := PATH) -> UserSettings:
	var memory := UserSettings.new()
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(path) or cfg.load(path) != OK:
		return memory
	memory.hints_followed = _strings(cfg, "hints", "followed")
	memory.giant_pass_lineages = _strings(cfg, "ambience", "giant_pass_lineages")
	return memory


func save_to(path := PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("hints", "followed", hints_followed)
	cfg.set_value("ambience", "giant_pass_lineages", giant_pass_lineages)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + TEMP_SUFFIX
	# A temporary file that cannot be opened is never made, so a failed save leaves nothing behind.
	var err := cfg.save(tmp)
	if err != OK:
		return err
	# The rename replaces the old file in one step (on Windows the engine removes it first).
	err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		DirAccess.remove_absolute(tmp)
	return err


## The list at [section] key, or an empty one when it is missing or not a PackedStringArray.
static func _strings(cfg: ConfigFile, section: String, key: String) -> PackedStringArray:
	if not cfg.has_section_key(section, key):
		return PackedStringArray()
	var value = cfg.get_value(section, key)
	return value if value is PackedStringArray else PackedStringArray()
