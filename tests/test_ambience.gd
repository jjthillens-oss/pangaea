extends TestCase
## The pool's ambience (game/scenes/pool/ambience/, docs/DECISIONS.md "The cell stage reads as a
## microscopic world"): decor only. It must never reach into the simulation or its random streams,
## stay inside the particle and billboard budgets, and keep clear of the food and threat colours
## (/mnt/project-files/pangaea/docs/ambience-handoff.md).

const AMBIENCE_DIR := "res://game/scenes/pool/ambience/"
const SCENE := "res://game/scenes/pool/ambience/pool_ambience.tscn"
const POOL_SCENE := "res://game/scenes/pool/pool.tscn"
const MAX_PARTICLES := 2000
const MAX_BACKDROPS := 12
## Reserved colours (docs/art/ART_DIRECTION.md): the food glow and the threat pink.
const RESERVED := {"food": Color("#CFE86A"), "threat": Color("#D9466B")}
## A decor tint counts as too close when its hue is within this many degrees of a reserved
## colour's while it is this saturated or more (HSV).
const MIN_HUE_GAP_DEG := 30.0
const MIN_SATURATION := 0.25


func _sources() -> Dictionary:
	var out := {}
	for file in DirAccess.get_files_at(AMBIENCE_DIR):
		if file.ends_with(".gd") or file.ends_with(".gdshader") or file.ends_with(".tscn"):
			out[file] = FileAccess.get_file_as_string(AMBIENCE_DIR + file)
	return out


func test_the_ambience_never_references_the_simulation() -> void:
	var sources := _sources()
	check(not sources.is_empty(), "the ambience has sources")
	var any_random := RegEx.create_from_string("(?<![\\w.])(randf|randi|randf_range|randi_range|randfn|randomize|seed)\\(")
	for file: String in sources:
		var text: String = sources[file]
		for banned in ["game/systems", "PoolSim", "SimRandom", ".sim", "sim."]:
			check(not text.contains(banned), "%s mentions %s" % [file, banned])
		# Its random numbers come from its own generator, never the global one.
		check(any_random.search(text) == null, "%s draws from the global random generator" % file)


func test_the_pool_adds_the_ambience_as_one_child() -> void:
	var text := FileAccess.get_file_as_string(POOL_SCENE)
	check(text.contains('path="%s"' % SCENE), "pool.tscn instances the ambience scene")
	check_eq(text.count('instance=ExtResource("90_ambience")'), 1, "one ambience node")


func test_the_ambience_stays_inside_its_budgets() -> void:
	var node: PoolAmbience = (load(SCENE) as PackedScene).instantiate()
	node._ready()
	check(node.particle_count() > 0 and node.particle_count() <= MAX_PARTICLES,
		"%d drifting quads, at most %d" % [node.particle_count(), MAX_PARTICLES])
	check(node.backdrop_count() > 0 and node.backdrop_count() <= MAX_BACKDROPS,
		"%d backdrop organisms, at most %d" % [node.backdrop_count(), MAX_BACKDROPS])
	# Nothing it draws casts a shadow on the play space or can be culled away by its own motion.
	for child in node.get_children():
		if child is GeometryInstance3D:
			check_eq((child as GeometryInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts no shadow" % child.name)
	node.free()


func test_decor_keeps_clear_of_the_food_and_threat_colours() -> void:
	for layer: String in PoolAmbience.LAYERS:
		for hex: String in PoolAmbience.LAYERS[layer].tints:
			var tint := Color(hex)
			for reserved: String in RESERVED:
				var gap := absf(fposmod(tint.h - RESERVED[reserved].h + 0.5, 1.0) - 0.5) * 360.0
				check(tint.s < MIN_SATURATION or gap >= MIN_HUE_GAP_DEG,
					"%s tint %s is %.0f degrees of hue from the %s colour" % [layer, hex, gap, reserved])


func test_drifting_decor_never_sits_on_the_swim_plane_band_it_would_seem_to_collide_in() -> void:
	# Microbes stay under the cell's belly (0.39 m), where fog takes them; specks and bubbles are
	# too small and faint to read as solid.
	var microbes: Dictionary = PoolAmbience.LAYERS.Microbes
	check(microbes.height.y <= -0.5, "microbes stay at least 0.5 m under the swim plane, top %.2f" % microbes.height.y)
