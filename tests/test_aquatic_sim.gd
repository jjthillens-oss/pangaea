extends TestCase

const CreatureData := preload("res://game/systems/creature/creature_data.gd")
## The Aquatic stage's rules and world (aquatic plan sections 4, 5, 8 and 9): two bodies swim the same route
## differently, every depth hazard warns before it harms, species stay in their niches, mating opens the editor and
## a commit makes the next generation, the cell lineage arrives in the body, and the sim is deterministic.

## The slice's own content (PR #192): the golden species run keeps to it, so content appended to the rules later
## (aquatic-r2 steps 6 and 7) never changes the run.
const SLICE_SPECIES := ["grazer", "shoal"]
const SLICE_SHELTERS := ["shelter_reef_west", "shelter_reef_east", "shelter_ledge"]
const SLICE_SITES := ["plankton_bay", "plankton_shelf", "algae_west", "algae_east", "vents"]
## The md5 of the golden species run (_golden_species_run: its snapshot, animals and events, floats rounded to 1e-4),
## recorded on the hard-wired grazer and shoal code before aquatic-r2's data-driven species refactor. The refactored
## code must play the slice's species exactly as that code did. Content added later that changes this run must be
## kept out of it in _slice_rules(), not re-recorded.
const GOLDEN_SPECIES_RUN := "dafeaab3a7ed0346e1dbb431ce583af4"

var rules: Dictionary
var _golden_sim: AquaticSim
var _golden_log: Array = []
var _golden_states := {}


func before_each() -> void:
	rules = AquaticLineage.rules()


func _sim(body: Dictionary, seed_value := 7) -> AquaticSim:
	return AquaticSim.new(rules, seed_value, body)


## Swims a fixed course: straight down the route for `straight` seconds, then a hard right turn for `turn` seconds.
## Returns {"straight_m", "turn_radius_m", "depth"}.
func _course(body: Dictionary) -> Dictionary:
	var sim := _sim(body)
	sim.player.pos = Vector3(0.0, -6.0, 20.0)
	var start: Vector3 = sim.player.pos
	for i in 5 * AquaticSim.TICK_HZ:
		sim.step(AquaticSim.Intent.new(1.0, 0.0, 0.0))
	var straight := Vector2(sim.player.pos.x - start.x, sim.player.pos.z - start.z).length()
	var h0 := float(sim.player.heading)
	for i in AquaticSim.TICK_HZ:
		sim.step(AquaticSim.Intent.new(1.0, 1.0, 0.0))
	var turned := absf(wrapf(float(sim.player.heading) - h0, -PI, PI))
	return {"straight_m": straight, "turn_rate": turned, "speed": float(sim.player.speed)}


func test_body_rules_are_legal_for_both_variants() -> void:
	for body in [AquaticBody.DARTER, AquaticBody.HOVERER]:
		check(AquaticBody.validate(body, rules.body).is_empty(), "variant is legal: %s" % [AquaticBody.validate(body, rules.body)])
	var bad := AquaticBody.DARTER.duplicate()
	bad.fins = 9
	check_has_error(AquaticBody.validate(bad, rules.body), "Fins")
	bad = AquaticBody.DARTER.duplicate()
	bad.erase("tail")
	check_has_error(AquaticBody.validate(bad, rules.body), "no tail")


func test_two_bodies_swim_the_same_course_differently() -> void:
	var darter := _course(AquaticBody.DARTER)
	var hoverer := _course(AquaticBody.HOVERER)
	check(darter.straight_m > hoverer.straight_m * 1.3, "the darter goes further in a straight line (%.1f vs %.1f m)" % [darter.straight_m, hoverer.straight_m])
	check(hoverer.turn_rate > darter.turn_rate * 1.3, "the hoverer turns tighter at speed (%.2f vs %.2f rad in a second)" % [hoverer.turn_rate, darter.turn_rate])
	var ds := AquaticBody.stats(AquaticBody.DARTER, rules.body)
	var hs := AquaticBody.stats(AquaticBody.HOVERER, rules.body)
	check(hs.rated_depth > float(rules.world.zones[3].depth), "the hoverer can stand the deep (%.0f m)" % hs.rated_depth)
	check(ds.rated_depth < float(rules.world.zones[3].depth), "the darter cannot (%.0f m)" % ds.rated_depth)
	check(ds.top_speed > float(rules.hazards.lancer.pursue_speed), "the darter outruns the lancer (%.1f m/s)" % ds.top_speed)
	check(hs.top_speed < float(rules.hazards.lancer.pursue_speed), "the hoverer cannot, it must hide (%.1f m/s)" % hs.top_speed)
	check(hs.idle_drift >= 0.0 and ds.idle_drift < 0.0, "the hoverer holds its depth, the darter sinks when idle")


func test_the_hoverer_holds_depth_and_the_darter_sinks() -> void:
	for pair in [[AquaticBody.HOVERER, true], [AquaticBody.DARTER, false]]:
		var sim := _sim(pair[0])
		sim.player.pos = Vector3(0.0, -6.0, 0.0)
		for i in 4 * AquaticSim.TICK_HZ:
			sim.step(AquaticSim.Intent.new())
		var held := absf(float(sim.player.pos.y) + 6.0) < 0.3
		check_eq(held, pair[1], "idle depth after 4 s: %.2f" % sim.player.pos.y)


func test_pressure_warns_before_it_drains() -> void:
	var sim := _sim(AquaticBody.DARTER)
	var rated := float(sim.player.stats.rated_depth)
	sim.player.pos = Vector3(0.0, -(rated + 6.0), -230.0)
	var hp := float(sim.player.health)
	var warned_at := -1
	var first_harm := -1
	for i in 8 * AquaticSim.TICK_HZ:
		sim.player.pos.y = -(rated + 6.0)
		sim.step(AquaticSim.Intent.new())
		for e in sim.take_events():
			if e.type == "pressure_warning" and warned_at < 0:
				warned_at = sim.tick
		if first_harm < 0 and float(sim.player.health) < hp:
			first_harm = sim.tick
	check(warned_at > 0, "the pressure warning fired")
	check(first_harm - warned_at >= int(round(float(rules.hazards.pressure.warn) * AquaticSim.TICK_HZ)),
			"no harm until the warning ran (%d ticks)" % (first_harm - warned_at))
	# Rising clears it at once.
	sim.player.pos.y = -(rated - 5.0)
	sim.step(AquaticSim.Intent.new())
	check_eq(sim.pressure_ticks, 0, "rising above the rated depth clears the pressure")


func test_the_lancer_investigates_then_pursues_and_gives_up_at_a_shelter() -> void:
	var sim := _sim(AquaticBody.HOVERER)
	var home := AquaticSim._v(rules.hazards.lancer.home)
	sim.lancer.pos = home
	sim.player.pos = home + Vector3(0.0, 2.0, 8.0)
	var order: Array = []
	var hp := float(sim.player.health)
	var harm_before_pursuit := false
	for i in 12 * AquaticSim.TICK_HZ:
		sim.step(AquaticSim.Intent.new())
		for e in sim.take_events():
			if e.type in ["lancer_investigate", "lancer_pursue", "struck", "lancer_gave_up"]:
				order.append(e.type)
		if float(sim.player.health) < hp and not "lancer_pursue" in order:
			harm_before_pursuit = true
		if order.has("lancer_gave_up"):
			break
	check(order.size() >= 3 and order[0] == "lancer_investigate" and order[1] == "lancer_pursue", "it investigates, then pursues: %s" % [order])
	check(not harm_before_pursuit, "no strike before the pursuit")
	check(order.has("lancer_gave_up"), "it disengages")
	# Hidden in a shelter, it gives up without a strike.
	sim = _sim(AquaticBody.HOVERER)
	var cave: Dictionary = rules.world.shelters[2]
	sim.lancer.pos = AquaticSim._v(cave.pos) + Vector3(0.0, 2.0, -9.0)
	sim.player.pos = AquaticSim._v(cave.pos) + Vector3(0.0, 1.0, 0.0)
	sim.lancer.state = "pursue"
	sim.lancer.until = sim.tick + 300
	sim.step(AquaticSim.Intent.new())
	check_eq(String(sim.lancer.state), "disengage", "a sheltered fish is left alone")


func test_the_drifter_warns_before_its_sweep() -> void:
	var sim := _sim(AquaticBody.HOVERER)
	var hp := float(sim.player.health)
	var warned_at := -1
	var hit_at := -1
	for i in 20 * AquaticSim.TICK_HZ:
		# Sit right in its path, slightly ahead of it.
		sim.player.pos = sim.drifter.pos + Vector3(2.0, 0.0, 0.0)
		sim.step(AquaticSim.Intent.new())
		for e in sim.take_events():
			if e.type == "drifter_warning" and warned_at < 0:
				warned_at = sim.tick
			if e.type == "struck" and e.by == "drifter" and hit_at < 0:
				hit_at = sim.tick
		if hit_at > 0:
			break
	check(warned_at > 0 and hit_at > 0, "the drifter warned and then swept (%d, %d)" % [warned_at, hit_at])
	check(hit_at - warned_at >= int(round(float(rules.hazards.drifter.warn) * AquaticSim.TICK_HZ)), "its warning ran first")
	check(float(sim.player.health) > 0.0 or sim.deaths == 0, "one sweep does not kill a healthy fish")
	check(float(sim.player.health) < hp, "the sweep hurts")


func test_species_stay_in_their_niches() -> void:
	var sim := _sim(AquaticBody.DARTER, 11)
	for i in 90 * AquaticSim.TICK_HZ:
		sim.step(AquaticSim.Intent.new(0.6, 0.3 if (i / 600) % 2 == 0 else -0.3, 0.0))
	for a in sim.animals:
		var cfg: Dictionary = rules.species[a.species]
		check(a.pos.distance_to(a.home) < float(cfg.wander) + float(cfg.get("follow_leash", 0.0)) + 12.0,
				"%s stays near its home (%.1f m)" % [a.id, a.pos.distance_to(a.home)])
		check_eq(String(sim.zone_at(a.home).id), String(cfg.zone), "%s's home is in its zone" % a.id)


func test_befriending_the_grazers_takes_spaced_signals() -> void:
	var sim := _sim(AquaticBody.HOVERER)
	var g: Dictionary = sim.animals[0]
	var points := sim.points
	for k in 3:
		sim.player.pos = g.pos + Vector3(0.0, 1.0, 2.0)
		var intent := AquaticSim.Intent.new()
		intent.signal_call = true
		sim.step(intent)
		sim.step(intent)   # a second call at once does not count
		for i in AquaticSim.TICK_HZ:
			sim.player.pos = g.pos + Vector3(0.0, 1.0, 2.0)
			sim.step(AquaticSim.Intent.new())
	check_eq(String(sim.relations.grazer.standing), "friend", "three spaced signals befriend the grazers")
	check(sim.points >= points + int(rules.world.points.friend), "a friendship earns points")
	# A bite makes them foes.
	sim.player.pos = g.pos + Vector3(0.0, 0.0, 1.0)
	sim.player.heading = AquaticSim.forward_of(0.0).signed_angle_to(g.pos - sim.player.pos, Vector3.UP)
	var bite := AquaticSim.Intent.new()
	bite.bite = true
	sim.step(bite)
	check_eq(String(sim.relations.grazer.standing), "foe", "a bite is remembered")


func test_mating_opens_the_editor_and_a_commit_makes_the_next_generation() -> void:
	var sim := _sim(AquaticBody.DARTER)
	sim.player.pos = sim.kin.pos + Vector3(1.0, 0.0, 0.0)
	sim.player.energy = 10.0
	var press := AquaticSim.Intent.new()
	press.interact = true
	sim.step(press)
	check(sim.take_events().any(func(e): return e.type == "mate_not_ready"), "too hungry to mate")
	sim.player.energy = float(sim.player.stats.energy_capacity)
	sim.player.pos = sim.kin.pos + Vector3(1.0, 0.0, 0.0)
	sim.step(press)
	check(sim.take_events().any(func(e): return e.type == "mate"), "fed, by the kin: the editor opens")
	var child := AquaticBody.DARTER.duplicate()
	child.fins = 2
	var cost := AquaticBody.edit_cost(AquaticBody.DARTER, child, rules.editor)
	check_eq(cost, int(rules.editor.step_cost.fins), "one fin step costs its step")
	sim.points = cost
	check(sim.apply_offspring(child, cost), "the commit is taken")
	check_eq(int(sim.player.generation), 2, "the next generation")
	check_eq(sim.history.size(), 1, "the parent is recorded")
	check_eq(sim.points, 0, "the points are spent")
	check(not sim.apply_offspring(child, 99), "a commit the points cannot pay for is refused")


func test_the_cell_lineage_arrives_in_the_body() -> void:
	var conv: Dictionary = rules.conversion
	var hunter := AquaticBody.from_genome([{"type": "mouth_jaw"}, {"type": "flagellum"}, {"type": "flagellum"}], 0.12, conv)
	check_eq(String(hunter.body.mouth), "jaw", "a jaw cell hunts")
	check_eq(int(hunter.body.tail_size), 2, "two flagella make a tail of strength 2")
	check_eq(int(hunter.body.length), 3, "a flagellum lineage starts as a darter")
	check_near(float(hunter.body.hue), 0.12, 1e-6, "the cell's colour carries over")
	var grazer := AquaticBody.from_genome([{"type": "mouth_filter"}, {"type": "cilia"}, {"type": "cilia"}, {"type": "eye_spot"}], 0.4, conv)
	check_eq(String(grazer.body.mouth), "filter", "a filter cell grazes")
	check_eq(int(grazer.body.fins), 2, "two cilia make fins of size 2")
	check_eq(int(grazer.body.length), 1, "a cilia lineage starts as a hoverer")
	check(grazer.notes.size() >= 3, "each conversion is explained")
	for made in [hunter, grazer]:
		check(AquaticBody.validate(made.body, rules.body).is_empty(), "the converted body is legal")
	var read := AquaticLineage.read("", rules, 5)
	check(read.ok and read.source == "new" and not read.writable, "no slot: a fresh lineage, never written")
	check(not String(read.lineage_id).is_empty(), "with a lineage id")


func test_fish_bodies_are_legal_creature_descriptions() -> void:
	var body_rules: Dictionary = CreatureData.rules()
	var part_rules: Dictionary = CreatureData.part_rules()
	check(rules.body.tails.size() >= 5, "five tails in the rules: %s" % [rules.body.tails])
	for tail in rules.body.tails:
		for sense in rules.body.senses:
			for mouth in rules.body.mouths:
				for corner in [AquaticBody.DARTER, AquaticBody.HOVERER]:
					var body: Dictionary = corner.duplicate()
					body.tail = tail
					body.sense = sense
					body.mouth = mouth
					var desc = AquaticBody.to_description(body)
					var problems: PackedStringArray = desc.validate_parts(body_rules, part_rules)
					check(problems.is_empty(), "%s %s %s: %s" % [tail, sense, mouth, problems])
	# The animals of the world are drawn the same way, from legal bodies (fish_view.gd).
	var fish_view := preload("res://game/scenes/aquatic/fish_view.gd")
	for id in fish_view.SPECIES.keys() + ["(fallback)"]:
		var body: Dictionary = fish_view.SPECIES[id].body if id != "(fallback)" else fish_view.FALLBACK.body
		check(AquaticBody.validate(body, rules.body).is_empty(), "%s's body is legal: %s" % [id, AquaticBody.validate(body, rules.body)])
		var problems: PackedStringArray = AquaticBody.to_description(body).validate_parts(body_rules, part_rules)
		check(problems.is_empty(), "%s is a legal description: %s" % [id, problems])


## The fish are drawn with recorded creature parts, told apart by their handles (AquaticBody.TAIL_ART,
## PECTORAL_HANDLES). A handle is set by its index (H1_, H2_, ...), so a reorder of these parts' handles in
## part_rules.json would silently change what every fish looks like: this pins the order the art mapping assumes.
func test_fish_part_handles_keep_their_meaning() -> void:
	var part_rules: Dictionary = CreatureData.part_rules()
	var expected := {"tail_fluke": ["H1_Span", "H2_Beat"], "fin": ["H1_Height", "H2_Sweep", "H3_Ripple"],
			"dorsal_spine": ["H1_Height", "H2_Rake"]}
	for type in expected:
		check(part_rules.has(type), "%s is a recorded part" % type)
		if not part_rules.has(type):
			continue
		var keys := []
		for h in part_rules[type].handles:
			keys.append(String(h.key))
		check_eq(keys.slice(0, expected[type].size()), expected[type], "%s handle order" % type)
	# Every tail's pieces use a recorded part with no more handles than it has, and the tails look different.
	var seen := {}
	for tail in rules.body.tails:
		check(AquaticBody.TAIL_ART.has(tail), "%s has its art" % tail)
		var art: Array = AquaticBody.TAIL_ART.get(tail, [])
		for piece in art:
			var handles: Array = part_rules[piece.part].handles
			check(piece.handles.size() <= handles.size(), "%s: %s takes at most %d handles" % [tail, piece.part, handles.size()])
		var key := JSON.stringify(art.map(func(p): return [p.part, p.roll, p.handles, p.ring]))
		check(not seen.has(key), "%s is drawn unlike %s" % [tail, seen.get(key, "")])
		seen[key] = tail
	# The pectorals change shape with each fin step, and the spine plate shows exactly when the dorsal stings.
	var min_dorsal := int(rules.body.spines.min_dorsal)
	for dorsal in range(int(rules.body.ranges.dorsal[0]), int(rules.body.ranges.dorsal[1]) + 1):
		var body := AquaticBody.DARTER.duplicate()
		body.dorsal = dorsal
		var spines := 0
		for p in AquaticBody.to_description(body).parts:
			spines += 1 if String(p.type) == "dorsal_spine" else 0
		var stings: bool = AquaticBody.stats(body, rules.body).spines
		check_eq(spines, 1 if stings else 0, "dorsal %d: a spine plate exactly when it stings (min %d)" % [dorsal, min_dorsal])


## The distance a body covers in its first second from still with a full burst, in the sim itself (aquatic-r2).
func _dash_1s(body: Dictionary) -> float:
	var sim := _sim(body)
	sim.player.pos = Vector3(0.0, -6.0, 20.0)
	var start: Vector3 = sim.player.pos
	var intent := AquaticSim.Intent.new(1.0, 0.0, 0.0)
	intent.burst = true
	for i in AquaticSim.TICK_HZ:
		sim.step(intent)
	return Vector2(sim.player.pos.x - start.x, sim.player.pos.z - start.z).length()


## Bible §2 and §12 (aquatic-r2, PROPOSED tuning): every tail is a tradeoff. On the darter, the hoverer and a middle
## body, at every tail size, no tail is at least as good as another on all four counts (top speed, a one-second burst
## dash in the water, the yaw rate at 4 m/s and the swim cost) and better on one.
func test_no_tail_part_beats_another_on_every_count() -> void:
	var middle := {"length": 2, "girth": 2, "tail": "fluke", "tail_size": 2, "fins": 2, "dorsal": 1, "bladder": 1,
			"sense": "eyes", "mouth": "both", "hue": 0.5}
	for corner in [["darter", AquaticBody.DARTER], ["hoverer", AquaticBody.HOVERER], ["middle", middle]]:
		for size in [1, 2, 3]:
			var counts := {}
			for tail in rules.body.tails:
				var body: Dictionary = (corner[1] as Dictionary).duplicate()
				body.tail = tail
				body.tail_size = size
				var s := AquaticBody.stats(body, rules.body)
				counts[tail] = [float(s.top_speed), _dash_1s(body), AquaticBody.yaw_rate(s, 4.0), -float(s.thrust_cost)]
			for a in counts:
				for b in counts:
					if a == b:
						continue
					var no_worse := true
					var better := false
					for k in 4:
						no_worse = no_worse and counts[a][k] >= counts[b][k] - 0.0001
						better = better or counts[a][k] > counts[b][k] + 0.0001
					check(not (no_worse and better), "%s size %d: %s beats %s on every count (%s vs %s)" % [corner[0],
							size, a, b, counts[a], counts[b]])
	# The burst the editor shows is the burst the water gives: the stat reads the tail's own burst share.
	var paddle := AquaticBody.DARTER.duplicate()
	paddle.tail = "paddle"
	var lunate := AquaticBody.DARTER.duplicate()
	lunate.tail = "lunate"
	check(_dash_1s(paddle) > _dash_1s(AquaticBody.DARTER) and _dash_1s(lunate) < _dash_1s(AquaticBody.DARTER),
			"the paddle dashes further than the fluke, the lunate less")
	check(AquaticBody.stats(lunate, rules.body).top_speed > AquaticBody.stats(AquaticBody.DARTER, rules.body).top_speed,
			"and the lunate cruises faster")


## The editor's test swim (AquaticSim.trial, aquatic-r2; the roles are PROPOSED and named in the editor's TAIL_ROLES):
## on the darter at full tail strength each tail wins the course its role promises.
func test_each_tail_wins_its_own_course() -> void:
	var runs := {}
	for tail in rules.body.tails:
		var body := AquaticBody.DARTER.duplicate()
		body.tail = tail
		body.tail_size = 3
		runs[tail] = AquaticSim.trial(rules, body)
	var best := func(key: String, most: bool) -> String:
		var out := ""
		for tail in runs:
			if out == "" or (float(runs[tail][key]) > float(runs[out][key])) == most and runs[tail][key] != runs[out][key]:
				out = tail
		return out
	var table := JSON.stringify(runs.keys().map(func(t): return [t, snappedf(runs[t].dash_1s_m, 0.01),
			snappedf(runs[t].cruise_10s_m, 0.01), snappedf(runs[t].turn_1s_rad, 0.001), snappedf(runs[t].energy_10s, 0.01)]))
	check_eq(best.call("cruise_10s_m", true), "lunate", "the lunate cruises furthest in 10 s: %s" % table)
	check_eq(best.call("dash_1s_m", true), "paddle", "the paddle dashes furthest in 1 s")
	check_eq(best.call("energy_10s", false), "whip", "the whip swims 10 s on the least energy")
	check_eq(best.call("energy_10s", true), "paddle", "the paddle on the most")
	check(best.call("turn_1s_rad", true) in ["whip", "ribbon"], "the whip or the ribbon turns most in a second at speed")
	check(runs.lunate.dash_1s_m < runs.fluke.dash_1s_m and runs.lunate.turn_1s_rad < runs.fluke.turn_1s_rad,
			"the lunate pays for its cruise: a shorter dash and a wider turn than the fluke")
	check(runs.ribbon.turn_1s_rad > runs.fluke.turn_1s_rad and runs.ribbon.energy_10s > runs.fluke.energy_10s,
			"the ribbon turns more than the fluke and costs more")
	# "Strong even when small": at strength 1 on the hoverer the ribbon outswims the fluke.
	var small_fluke := AquaticBody.HOVERER.duplicate()
	small_fluke.tail = "fluke"
	check(AquaticSim.trial(rules, AquaticBody.HOVERER).cruise_10s_m > AquaticSim.trial(rules, small_fluke).cruise_10s_m,
			"at strength 1 the ribbon cruises further than the fluke")
	# The turn course is drawn: 3 s ahead then turning, sampled from the start.
	var path: Array = runs.fluke.path
	var ticks := 3 * AquaticSim.TICK_HZ + int(round(AquaticSim.TRIAL_TURN_S * AquaticSim.TICK_HZ))
	check_eq(path.size(), 1 + ticks / AquaticSim.TRIAL_PATH_EVERY, "the path has a sample every %d ticks" % AquaticSim.TRIAL_PATH_EVERY)
	check(absf(float(path[path.size() - 1][0])) > 3.0, "and it turns off the straight line")


## The editor's preview is the water: trial() is the sim swum on the same course (a hand run in the full world, with its
## food, animals and hazards, covers the same metres), its energy is the sim's swim cost, and a long burst reaches the
## burst speed the editor shows.
func test_the_editor_preview_and_the_water_agree() -> void:
	var paddle := AquaticBody.DARTER.duplicate()
	paddle.tail = "paddle"
	var whip := AquaticBody.HOVERER.duplicate()
	whip.tail = "whip"
	for body in [AquaticBody.DARTER, AquaticBody.HOVERER, paddle, whip]:
		var t := AquaticSim.trial(rules, body)
		var s := AquaticBody.stats(body, rules.body)
		var label := "%s/%d" % [body.tail, int(body.length)]
		var dash := AquaticSim.Intent.new(1.0, 0.0, 0.0)
		dash.burst = true
		var sim := _sim(body)
		sim.player.pos = AquaticSim.TRIAL_START
		sim.player.heading = 0.0
		for i in AquaticSim.TICK_HZ:
			sim.step(dash)
		check_near(AquaticSim._flat_from_start(sim.player.pos), float(t.dash_1s_m), 1e-5, "%s: the dash in the world" % label)
		sim = _sim(body)
		sim.player.pos = AquaticSim.TRIAL_START
		sim.player.heading = 0.0
		for i in 10 * AquaticSim.TICK_HZ:
			sim.step(AquaticSim.Intent.new(1.0, 0.0, 0.0))
		check_near(AquaticSim._flat_from_start(sim.player.pos), float(t.cruise_10s_m), 1e-5, "%s: the cruise in the world" % label)
		check_near(float(t.energy_10s), (float(s.upkeep) + float(s.thrust_cost)) * 10.0, 1e-3, "%s: the energy is the swim cost" % label)
		# A long burst and a long cruise reach the speeds the editor shows (fed, so it never starves).
		for pair in [[dash, float(s.burst_speed), "burst"], [AquaticSim.Intent.new(1.0, 0.0, 0.0), float(s.top_speed), "top"]]:
			sim = _sim(body)
			sim.player.pos = AquaticSim.TRIAL_START
			for i in 14 * AquaticSim.TICK_HZ:
				sim.player.energy = float(s.energy_capacity)
				sim.step(pair[0])
			check(absf(float(sim.player.speed) - float(pair[1])) <= float(pair[1]) * 0.02,
					"%s: the %s speed swum (%.2f) is the stat (%.2f)" % [label, pair[2], float(sim.player.speed), float(pair[1])])


## The rules cut back to the slice's species, shelters and feeding sites.
func _slice_rules() -> Dictionary:
	var r: Dictionary = rules.duplicate(true)
	var species := {}
	for id in SLICE_SPECIES:
		species[id] = r.species[id]
	r.species = species
	if r.has("species_order"):
		r.species_order = SLICE_SPECIES.duplicate()
	r.world.shelters = (r.world.shelters as Array).filter(func(s): return String(s.id) in SLICE_SHELTERS)
	r.world.feeding = (r.world.feeding as Array).filter(func(s): return String(s.id) in SLICE_SITES)
	return r


func _golden_step(intent: AquaticSim.Intent) -> void:
	_golden_sim.step(intent)
	for e in _golden_sim.take_events():
		# What each event does in play (which animal, which standing, how much rapport), not which fields name it:
		# the refactor may add names to an event for the HUD.
		_golden_log.append([int(e.tick), String(e.type), String(e.get("id", "")), String(e.get("standing", "")),
				int(e.get("rapport", -1))])
	for a in _golden_sim.animals:
		_golden_states["%s:%s" % [a.species, a.state]] = true


## Puts the fish 1 m from `a`, facing it.
func _face(sim: AquaticSim, a: Dictionary) -> void:
	sim.player.pos = a.pos + Vector3(0.0, 0.0, 1.0)
	sim.player.heading = AquaticSim.forward_of(0.0).signed_angle_to(a.pos - sim.player.pos, Vector3.UP)


static func _rounded(v: Variant) -> Variant:
	if v is float:
		return snappedf(v, 0.0001)
	if v is Array or v is PackedStringArray:
		var out := []
		for x in v:
			out.append(_rounded(x))
		return out
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _rounded(v[k])
		return d
	return v


## A scripted 80 s run of the darter on the slice's content that goes through every species rule: a call nobody hears,
## three spaced calls (one too fast each time) that befriend the grazers and one after, the friends following on the
## reef, the lancer finding the fish among them (the ally warning, the grazers hiding, the chase and the sting), a bite
## that makes the grazers foes and has them flee, two bites that catch a fish of the shoal, and fifty seconds of
## swimming in which it respawns. Returns {"md5", "types", "states", "relations"}.
func _golden_species_run() -> Dictionary:
	var sim := AquaticSim.new(_slice_rules(), 7, AquaticBody.DARTER)
	_golden_sim = sim
	_golden_log = []
	_golden_states = {}
	var call := AquaticSim.Intent.new()
	call.signal_call = true
	var bite := AquaticSim.Intent.new()
	bite.bite = true
	for i in 600:
		_golden_step(AquaticSim.Intent.new(1.0, 0.3 * sin(i * 0.02), -0.25))
	sim.player.pos = sim.nest_pos() + Vector3(0.0, 1.0, 0.0)
	_golden_step(call)
	var g: Dictionary = sim.animals[0]
	for k in 3:
		sim.player.pos = g.pos + Vector3(0.0, 1.0, 2.0)
		_golden_step(call)
		_golden_step(call)
		for i in AquaticSim.TICK_HZ:
			sim.player.pos = g.pos + Vector3(0.0, 1.0, 2.0)
			_golden_step(AquaticSim.Intent.new())
	_golden_step(call)
	sim.player.pos = Vector3(-10.0, -16.0, -56.0)
	for i in 300:
		_golden_step(AquaticSim.Intent.new(0.3, 0.2, 0.0))
	sim.player.pos = Vector3(-6.0, -26.0, -96.0)
	for a in sim.animals:
		if a.species == "grazer":
			a.pos = sim.player.pos + Vector3(float(int(String(a.id).right(2))) - 3.0, 1.0, 3.0)
	sim.lancer.pos = sim.player.pos + Vector3(0.0, 0.0, -10.0)
	for i in 480:
		_golden_step(AquaticSim.Intent.new())
	for a in sim.animals:
		if a.species == "grazer" and a.alive:
			_face(sim, a)
			break
	_golden_step(bite)
	for i in 120:
		_golden_step(AquaticSim.Intent.new())
	var prey: Dictionary = {}
	for a in sim.animals:
		if a.species == "shoal" and a.alive:
			prey = a
			break
	for k in 2:
		for i in 31:
			_face(sim, prey)
			_golden_step(bite if i == 0 else AquaticSim.Intent.new())
	for i in 3000:
		_golden_step(AquaticSim.Intent.new(0.6, 0.4 * sin(i * 0.013), 0.15 * cos(i * 0.007)))
	var animals := []
	for a in sim.animals:
		animals.append([a.id, a.hp, a.respawn_at, a.heading, AquaticSim._arr(a.target)])
	var run := {"snapshot": sim.snapshot(), "animals": animals, "events": _golden_log, "meals": sim.meals,
			"deaths": sim.deaths, "lancer": [sim.lancer.state, sim.lancer.until, sim.lancer.cooldown_until]}
	var types := {}
	for e in _golden_log:
		types[e[1]] = true
	return {"md5": JSON.stringify(_rounded(run), "", true).md5_text(), "types": types, "states": _golden_states,
			"relations": sim.relations.duplicate(true)}


## aquatic-r2 step 5: the species rules became data (rules.species_order and per-species flags); this run, recorded on
## the hard-wired code before that, proves the grazers and the shoal still play exactly as they did.
func test_the_slice_species_play_as_recorded() -> void:
	var run := _golden_species_run()
	for type in ["signal_unheard", "signal_too_fast", "signal_answered", "relation", "ally_warning", "lancer_pursue",
			"stung", "bit", "killed"]:
		check(run.types.has(type), "the run goes through '%s': %s" % [type, run.types.keys()])
	for state in ["grazer:wander", "grazer:follow", "grazer:hide", "grazer:flee", "shoal:wander", "shoal:flee"]:
		check(run.states.has(state), "the run sees %s: %s" % [state, run.states.keys()])
	check_eq(String(run.relations.grazer.standing), "foe", "the bitten grazers end as foes")
	check_eq(String(run.md5), GOLDEN_SPECIES_RUN, "the slice's species play as recorded before the refactor")


## aquatic-r2 step 5: a species is data. Every entry in the rules is complete, and two made-up species added only to a
## copy of the rules (a befriendable one that follows and warns, and a prey that always flees) are built after the
## slice's species without moving them, befriended, bitten, caught and respawned by the same code, named in its
## events and the HUD's lines, and written in the save's relations.
func test_species_logic_is_data_driven() -> void:
	var order: Array = rules.species_order
	check_eq(order.size(), rules.species.size(), "species_order lists every species once: %s" % [order])
	for id in rules.species:
		check(id in order, "%s is in species_order" % id)
		var cfg: Dictionary = rules.species[id]
		for key in ["name", "one", "count", "zone", "home", "wander", "speed", "flee_speed", "flee_reach", "flees", "health"]:
			check(cfg.has(key), "%s has %s" % [id, key])
		check(String(cfg.get("flees", "")) in ["always", "foe"], "%s flees always or as a foe" % id)
		if cfg.has("signals_to_friend"):
			check(cfg.has("signal_reach") and cfg.has("signal_gap"), "%s can be called" % id)
		if cfg.get("home") is String:
			check((rules.world.shelters as Array).any(func(sh): return String(sh.id) == String(cfg.home)), "%s's home shelter exists" % id)
	var r: Dictionary = rules.duplicate(true)
	r.species["test_puffers"] = {"name": "test puffers", "one": "a test puffer", "count": 3, "zone": "shallows",
			"home": [-10.0, -8.0, -10.0], "wander": 3.0, "speed": 1.5, "flee_speed": 3.0, "flee_reach": 8.0, "flees": "foe",
			"signals_to_friend": 2, "signal_reach": 8.0, "signal_gap": 0.5, "follow_leash": 30.0, "warn_reach": 22.0, "health": 30.0}
	r.species["test_darts"] = {"name": "test darts", "one": "a test dart", "count": 3, "zone": "shallows",
			"home": [14.0, -6.0, -8.0], "wander": 3.0, "speed": 2.0, "flee_speed": 3.0, "flee_reach": 6.0, "flees": "always",
			"health": 10.0, "meal": 40.0, "respawn": 1.0}
	r.species_order = order + ["test_puffers", "test_darts"]
	var plain := _sim(AquaticBody.DARTER)
	var sim := AquaticSim.new(r, 7, AquaticBody.DARTER)
	check_eq(sim.animals.size(), plain.animals.size() + 6, "the added species' animals are built")
	for i in plain.animals.size():
		check(sim.animals[i].id == plain.animals[i].id and sim.animals[i].pos == plain.animals[i].pos,
				"%s is where it was without the added species" % plain.animals[i].id)
	check(sim.relations.has("test_puffers") and String(sim.relations.test_puffers.standing) == "neutral", "a relation for each")
	var puffer: Dictionary = sim.animals[plain.animals.size()]
	var dart: Dictionary = sim.animals[plain.animals.size() + 3]
	check_eq(String(puffer.id), "test_puffers_01", "ids come from the species")
	# Two spaced calls befriend the puffers; the grazers far off on the reef do not hear them.
	var hud := preload("res://game/ui/aquatic_hud.gd")
	var lines := PackedStringArray()
	for k in 2:
		var call := AquaticSim.Intent.new()
		call.signal_call = true
		sim.player.pos = puffer.pos + Vector3(0.0, 1.0, 2.0)
		sim.step(call)
		for i in AquaticSim.TICK_HZ:
			sim.player.pos = puffer.pos + Vector3(0.0, 1.0, 2.0)
			sim.step(AquaticSim.Intent.new())
		for e in sim.take_events():
			lines.append(hud.event_text(e))
	check_eq(String(sim.relations.test_puffers.standing), "friend", "two spaced calls befriend the puffers")
	check_eq(String(sim.relations.grazer.standing), "neutral", "and only them")
	check(lines.has("The test puffers are your friends now (+%d points)" % int(rules.world.points.friend)), "named by the HUD: %s" % [lines])
	check_eq(sim._ally_near(), "test_puffers", "friends near warn of the lancer")
	sim.step(AquaticSim.Intent.new())
	check(sim.animals.slice(plain.animals.size(), plain.animals.size() + 3).any(func(a): return a.state == "follow"),
			"friends follow the fish in their own zone")
	# A neutral dart flees a fish near it; a bite catches it (a meal of its own size) and it comes back.
	_face(sim, dart)
	sim.step(AquaticSim.Intent.new())
	check_eq(String(dart.state), "flee", "prey that always flees runs from a neutral fish")
	sim.player.energy = 10.0
	var bite := AquaticSim.Intent.new()
	bite.bite = true
	_face(sim, dart)
	sim.step(bite)
	var killed: Array = sim.take_events().filter(func(e): return e.type == "killed")
	check(killed.size() == 1 and killed[0].species == "test_darts" and hud.event_text(killed[0]) == "You caught a test dart",
			"one bite catches a dart: %s" % [killed])
	check_near(float(sim.player.energy), 50.0, 0.2, "its meal is its own")
	check_eq(String(sim.relations.test_darts.standing), "neutral", "prey with no calls is never a foe")
	for i in AquaticSim.TICK_HZ + 1:
		sim.step(AquaticSim.Intent.new())
	check(killed.size() == 1 and sim.animals.filter(func(a): return a.id == killed[0].id)[0].alive, "it respawns after its own time")
	# A bite on a puffer makes them foes, and the save keeps it.
	_face(sim, puffer)
	sim.step(bite)
	var turned: Array = sim.take_events().filter(func(e): return e.type == "relation")
	check(turned.size() == 1 and turned[0].species == "test_puffers" and hud.event_text(turned[0]) == "The test puffers will remember that bite",
			"a bite makes the puffers foes: %s" % [turned])
	var block := sim.to_save()
	check_eq(String(block.relations.test_puffers.standing), "foe", "the save's relations hold the added species")
	check(SaveGame.validate_aquatic(block, func(b): return AquaticBody.validate(b, rules.body)).is_empty(), "in a valid block")


## Steers the fish at the nearest live animal of `species` and bites when it is in reach. Returns the "killed" event
## of the first one it catches within `seconds`, with the energy of that tick's meal ("meal"), or {}. The sim's own
## swim: thrust, turn and rise only.
func _hunt(sim: AquaticSim, species: String, seconds: float) -> Dictionary:
	for i in int(seconds * AquaticSim.TICK_HZ):
		var target: Dictionary = {}
		for a in sim.animals:
			if a.alive and a.species == species and (target.is_empty()
					or a.pos.distance_to(sim.player.pos) < target.pos.distance_to(sim.player.pos)):
				target = a
		if target.is_empty():
			return {}
		var to: Vector3 = target.pos - sim.player.pos
		var off := wrapf(atan2(-to.x, -to.z) - float(sim.player.heading), -PI, PI)
		var intent := AquaticSim.Intent.new(1.0 if absf(off) < 1.0 else 0.3, clampf(-off * 3.0, -1.0, 1.0), clampf(to.y * 0.8, -1.0, 1.0))
		intent.bite = to.length() <= float(sim.player.stats.radius) + 1.6
		sim.step(intent)
		var events := sim.take_events()
		for e in events:
			if e.type == "killed" and e.species == species:
				var meal: Array = events.filter(func(x): return x.type == "ate")
				return e.merged({"meal": float(meal[0].energy) if not meal.is_empty() else 0.0})
	return {}


## aquatic-r2 (PROPOSED): the glass minnows are the jaw lineage's first meat, in the shallows by the nest; the
## plankton and algae there feed only a filter mouth. A jaw darter (the smoke's hunter cell) swims one down and eats it.
func test_minnows_feed_a_jaw_lineage_in_the_shallows() -> void:
	var hunter: Dictionary = AquaticBody.from_genome([{"type": "mouth_jaw"}, {"type": "flagellum"}, {"type": "flagellum"}], 0.12,
			rules.conversion).body
	var sim := _sim(hunter)
	var home := sim.home_of("minnow")
	check_eq(String(sim.zone_at(home).id), "shallows", "the minnows live in the shallows")
	check(home.distance_to(sim.nest_pos()) < 30.0, "near the nest (%.0f m)" % home.distance_to(sim.nest_pos()))
	for site in rules.world.feeding:
		if String(sim.zone_at(AquaticSim._v(site.pos)).id) == "shallows":
			check_eq(String(rules.world.food[site.kind].diet), "plant", "%s feeds a filter mouth, not a jaw" % site.id)
	sim.player.energy = 30.0
	var meals := sim.meals
	var caught := _hunt(sim, "minnow", 30.0)
	check(String(caught.get("id", "")).begins_with("minnow_"), "the jaw darter catches a minnow by swimming it down: %s" % [caught])
	if caught.is_empty():
		return
	check_eq(sim.meals, meals + 1, "a meal")
	check_near(float(caught.meal), float(rules.species.minnow.meal), 1e-6, "worth the minnow's meal")
	check_eq(String(sim.zone_at(sim.player.pos).id), "shallows", "without leaving the shallows (%.1f m deep)" % -sim.player.pos.y)
	check_eq(String(sim.relations.minnow.standing), "neutral", "prey is never a foe")
	# They always flee a fish near them, and come back after their respawn.
	var a: Dictionary = sim.animals.filter(func(x): return x.id == caught.id)[0]
	for i in AquaticSim._ticks(rules.species.minnow.respawn) + 1:
		sim.player.pos = Vector3(0.0, -5.0, 25.0)
		sim.step(AquaticSim.Intent.new())
	check(a.alive, "the caught minnow comes back")
	_face(sim, a)
	sim.step(AquaticSim.Intent.new())
	check_eq(String(a.state), "flee", "a minnow flees a fish near it")


## aquatic-r2 (PROPOSED): the reef cleaners at the east arch are befriended with two spaced calls; a friend resting at
## their station is tended and healed (one "cleaned" event a visit), a neutral or a fast fish is not, and a bite makes
## them foes that tend no more.
func test_cleaners_befriend_and_heal_a_resting_friend() -> void:
	var sim := _sim(AquaticBody.HOVERER)
	var st: Dictionary = rules.species.cleaner.station
	var home := sim.home_of("cleaner")
	check_eq(String(sim.zone_at(home).id), "reef", "the cleaners live on the reef")
	var spot := home + Vector3(0.0, 0.0, 1.5)
	var cleaned := [0]
	var rest := func(seconds: float, speed: float) -> void:
		for i in int(seconds * AquaticSim.TICK_HZ):
			sim.player.pos = spot
			sim.player.speed = speed
			sim.step(AquaticSim.Intent.new())
			for e in sim.take_events():
				if e.type == "cleaned":
					cleaned[0] += 1
	sim.player.health = 20.0
	rest.call(2.0, 0.0)
	check_near(float(sim.player.health), 20.0, 1e-6, "a neutral fish is not tended")
	check_eq(String(sim.station_here().get("standing", "")), "neutral", "though it is at the station")
	for k in int(rules.species.cleaner.signals_to_friend):
		var call := AquaticSim.Intent.new()
		call.signal_call = true
		sim.player.pos = spot
		sim.step(call)
		rest.call(1.0, 0.0)
	check_eq(String(sim.relations.cleaner.standing), "friend", "two spaced calls befriend the cleaners")
	# A new visit, hurt, as a friend.
	sim.player.pos = home + Vector3(0.0, 0.0, 20.0)
	sim.step(AquaticSim.Intent.new())
	sim.take_events()
	sim.player.health = 20.0
	var hp := float(sim.player.health)
	cleaned[0] = 0
	rest.call(3.0, 0.0)
	check_near(float(sim.player.health), hp + float(st.heal_per_s) * 3.0, 0.1, "resting at the station heals (%.1f -> %.1f)" % [hp, sim.player.health])
	check_eq(cleaned[0], 1, "one 'cleaned' event for the visit")
	check(bool(sim.station_here().get("tending", false)), "the station tends the fish")
	var cleaners: Array = sim.animals.filter(func(x): return x.species == "cleaner")
	check(cleaners.all(func(x): return x.state == "clean"), "the cleaners gather round it")
	check(cleaners.all(func(x): return x.pos.distance_to(sim.player.pos) < float(sim.player.stats.radius) + 2.0), "close to it")
	# Leaving and coming back is another visit; swimming through fast is not a rest.
	sim.player.pos = home + Vector3(0.0, 0.0, 20.0)
	sim.step(AquaticSim.Intent.new())
	sim.take_events()
	sim.player.health = 20.0
	rest.call(0.5, 0.0)
	check_eq(cleaned[0], 2, "a new visit is cleaned again")
	hp = float(sim.player.health)
	rest.call(1.0, float(st.rest_speed) * 3.0)
	check(float(sim.player.health) <= hp + 1e-6, "a fish swimming past at speed is not tended")
	# A bite: foes, and no more cleaning.
	var c: Dictionary = cleaners.filter(func(x): return x.alive)[0]
	_face(sim, c)
	var bite := AquaticSim.Intent.new()
	bite.bite = true
	sim.step(bite)
	check_eq(String(sim.relations.cleaner.standing), "foe", "a bite makes the cleaners foes")
	sim.player.health = 20.0
	cleaned[0] = 0
	rest.call(2.0, 0.0)
	check_near(float(sim.player.health), 20.0, 1e-6, "a foe is not tended")
	check_eq(cleaned[0], 0, "and not cleaned")
	check(not bool(sim.station_here().get("tending", true)), "the station is closed to it")


## aquatic-r2 (PROPOSED): resting at the nest heals, as the nest is home (Spore's nest heals): a hurt fish within the
## nest's radius that keeps still heals rest_heal_per_s up to its full health, and the HUD is told; a fish swimming
## through, or one away from the nest, is not healed, and the slice's rules (no rest_heal_per_s) never heal there.
func test_resting_at_the_nest_heals() -> void:
	var cfg: Dictionary = rules.world.nest
	check(float(cfg.get("rest_heal_per_s", 0.0)) > 0.0, "the rules give the nest a rest heal")
	var sim := _sim(AquaticBody.DARTER)
	var full := float(sim.player.stats.max_health)
	var spot: Vector3 = sim.player.pos
	check(spot.distance_to(sim.nest_pos()) <= float(cfg.radius), "the fish starts at the nest")
	var rest := func(s: AquaticSim, at: Vector3, seconds: float, speed: float) -> void:
		for i in int(seconds * AquaticSim.TICK_HZ):
			s.player.pos = at
			s.player.speed = speed
			s.step(AquaticSim.Intent.new())
			s.take_events()
	sim.player.health = full * 0.5
	rest.call(sim, spot, 2.0, 0.0)
	check_near(float(sim.player.health), full * 0.5 + float(cfg.rest_heal_per_s) * 2.0, 0.05,
			"two seconds' rest at the nest heals %.0f (%.1f of %.0f)" % [float(cfg.rest_heal_per_s) * 2.0, float(sim.player.health), full])
	check(bool(sim.nest_here().get("resting", false)) and bool(sim.nest_here().get("heals", false)), "the HUD is told the fish is healing")
	var hp := float(sim.player.health)
	rest.call(sim, spot, 1.0, float(cfg.rest_speed) * 3.0)
	check(float(sim.player.health) <= hp + 1e-6, "swimming through the nest is no rest")
	check(not bool(sim.nest_here().get("resting", true)), "and the HUD is told so")
	var away: Vector3 = sim.nest_pos() + Vector3(0.0, 0.0, -float(cfg.radius) - 4.0)
	rest.call(sim, away, 2.0, 0.0)
	check(float(sim.player.health) <= hp + 1e-6, "resting away from the nest does not heal")
	check(sim.nest_here().is_empty(), "the fish is not at the nest")
	sim.player.health = full - 1.0
	rest.call(sim, spot, 3.0, 0.0)
	check_near(float(sim.player.health), full, 1e-6, "the nest heals up to full health and no further")
	var slice := rules.duplicate(true)
	(slice.world.nest as Dictionary).erase("rest_heal_per_s")
	var old := AquaticSim.new(slice, 7, AquaticBody.DARTER)
	old.player.health = full * 0.5
	rest.call(old, spot, 2.0, 0.0)
	check_near(float(old.player.health), full * 0.5, 1e-6, "rules without a rest heal (PR #192's slice) never heal at the nest")


## aquatic-r2 (PROPOSED): the vent glowfins flee any fish, but a fish with the lure sense draws them to its head from
## the lure's reach while it stays near their home, so a lure angler can catch them; with eyes they keep away.
func test_a_lure_draws_glowfins_and_eyes_do_not() -> void:
	var deep := AquaticBody.HOVERER.duplicate()
	deep.girth = 3
	deep.bladder = 3
	var angler := deep.duplicate()
	angler.sense = "lure"
	var cfg: Dictionary = rules.species.glowfin
	var nearest := func(sim: AquaticSim) -> float:
		var out := INF
		for a in sim.animals:
			if a.alive and a.species == "glowfin":
				out = minf(out, a.pos.distance_to(sim.player.pos))
		return out
	var runs := {}
	for body in [angler, deep]:
		var sim := _sim(body)
		var home := sim.home_of("glowfin")
		check(float(sim.player.stats.rated_depth) >= -home.y, "%s stands the vents' depth" % body.sense)
		var spot := home + Vector3(0.0, 0.0, 9.0)
		var lured_events := 0
		var seen_lured := false
		for i in 8 * AquaticSim.TICK_HZ:
			sim.player.pos = spot
			sim.player.heading = 0.0
			sim.step(AquaticSim.Intent.new())
			lured_events += sim.take_events().filter(func(e): return e.type == "lured").size()
			seen_lured = seen_lured or sim.animals.any(func(a): return a.state == "lured")
		runs[body.sense] = {"sim": sim, "nearest": nearest.call(sim), "events": lured_events, "seen": seen_lured}
	check(runs.lure.seen and runs.lure.nearest < 2.5, "a lure draws a glowfin to the fish's head (%.1f m)" % runs.lure.nearest)
	check_eq(runs.lure.events, 1, "one 'lured' event while they come")
	check(not runs.eyes.seen and runs.eyes.nearest > 3.0, "with eyes they keep away (%.1f m)" % runs.eyes.nearest)
	# The lure angler bites one it has drawn in.
	var sim: AquaticSim = runs.lure.sim
	var lured: Array = sim.animals.filter(func(a): return a.state == "lured")
	check(not lured.is_empty(), "glowfins at the lure")
	if not lured.is_empty():
		sim.player.energy = 10.0
		sim.player.heading = AquaticSim.forward_of(0.0).signed_angle_to(lured[0].pos - sim.player.pos, Vector3.UP)
		var bite := AquaticSim.Intent.new()
		bite.bite = true
		sim.step(bite)
		var killed: Array = sim.take_events().filter(func(e): return e.type == "killed")
		check(killed.size() == 1 and killed[0].species == "glowfin", "a bite catches a lured glowfin: %s" % [killed])
		check(float(sim.player.energy) > 10.0 + float(cfg.meal) - 0.5, "a glowfin's meal (%.1f)" % sim.player.energy)
	# Beyond the leash from their home they let the lure go.
	var far: Vector3 = sim.home_of("glowfin") + Vector3(0.0, 0.0, float(cfg.lured.leash) + 4.0)
	for i in 2 * AquaticSim.TICK_HZ:
		sim.player.pos = far
		sim.step(AquaticSim.Intent.new())
	check(not sim.animals.any(func(a): return a.alive and a.state == "lured"), "they keep to their home's reach")


## Every species in the rules has its look in the world (fish_view.gd), and no animal starts within reach of the
## fish at the nest.
func test_every_species_is_drawn_and_none_crowds_the_spawn() -> void:
	var fish_view := preload("res://game/scenes/aquatic/fish_view.gd")
	for id in rules.species_order:
		check(fish_view.SPECIES.has(id), "%s has its look in FishView.SPECIES" % id)
	var sim := _sim(AquaticBody.DARTER)
	for a in sim.animals:
		var reach := maxf(8.0, float(rules.species[a.species].flee_reach) + 3.0)
		check(a.pos.distance_to(sim.player.pos) > reach, "%s starts clear of the fish (%.1f m)" % [a.id, a.pos.distance_to(sim.player.pos)])


## The rules entry with `id` in rules.world[`list`] ("shelters" or "feeding").
func _site(list: String, id: String) -> Dictionary:
	for s in rules.world[list]:
		if String(s.id) == id:
			return s
	return {}


## aquatic-r2 (PROPOSED): a fish inside the vent chimney hears the drifter's warning but is not swept, though the
## drifter passes within its sweep reach; the same pass sweeps a fish just above the chimney.
func test_the_vent_chimney_hides_a_fish_from_the_drifter_sweep() -> void:
	var chimney := _site("shelters", "shelter_vent_chimney")
	check(not chimney.is_empty(), "the vent chimney is a shelter")
	if chimney.is_empty():
		return
	var deep := AquaticBody.HOVERER.duplicate()
	deep.girth = 3
	deep.bladder = 3
	var centre := AquaticSim._v(chimney.pos)
	var runs := {}
	for spot in [["inside", centre], ["above", centre + Vector3(0.0, float(chimney.radius) + 1.0, 0.0)]]:
		var sim := _sim(deep)
		var run := {"warned": false, "struck": false, "closest": INF, "sheltered": sim.sheltered(spot[1])}
		for i in 30 * AquaticSim.TICK_HZ:
			sim.player.pos = spot[1]
			sim.player.health = float(sim.player.stats.max_health)
			sim.step(AquaticSim.Intent.new())
			run.closest = minf(run.closest, (spot[1] as Vector3).distance_to(sim.drifter.pos))
			for e in sim.take_events():
				run.warned = run.warned or e.type == "drifter_warning"
				run.struck = run.struck or (e.type == "struck" and e.by == "drifter")
		runs[spot[0]] = run
	var reach := float(rules.hazards.drifter.sweep_reach)
	check_eq(String(runs.inside.sheltered), "shelter_vent_chimney", "the fish is in the chimney")
	check(runs.inside.closest < reach, "the drifter passes within its sweep of the chimney (%.1f m)" % runs.inside.closest)
	check(runs.inside.warned and not runs.inside.struck, "inside: warned, not swept (%s)" % [runs.inside])
	check(String(runs.above.sheltered) == "" and runs.above.warned and runs.above.struck, "just above it: swept (%s)" % [runs.above])
	var hud := preload("res://game/ui/aquatic_hud.gd").new()
	var sim := _sim(deep)
	hud.setup(sim)
	sim.player.pos = centre
	sim.drifter.warn_ticks = 10
	hud.refresh(0.0)
	check_eq(hud.warn_label.text, "A huge shadow passes over your hiding place", "the HUD says the fish is hidden")
	hud.free()


## aquatic-r2 (PROPOSED): the pillar ring lies inside the lancer's territory, and a hoverer (slower than the lancer)
## that reaches it ends a pursuit unhurt; the same chase away from it ends in a strike.
func test_the_pillar_ring_ends_a_lancer_pursuit() -> void:
	var over := _site("shelters", "shelter_pillars")
	check(not over.is_empty(), "the pillar ring is a shelter")
	if over.is_empty():
		return
	var lancer: Dictionary = rules.hazards.lancer
	var centre := AquaticSim._v(over.pos)
	check(centre.distance_to(AquaticSim._v(lancer.home)) < float(lancer.territory), "it is inside the lancer's territory")
	check(float(AquaticBody.stats(AquaticBody.HOVERER, rules.body).top_speed) < float(lancer.pursue_speed), "the hoverer cannot outswim it")
	var runs := {}
	for way in [["to", 0.0], ["away", PI]]:
		var sim := _sim(AquaticBody.HOVERER)
		# 9 m out on the ring's +Z side, swimming at top speed; the lancer 10 m behind, chasing.
		sim.player.pos = centre + Vector3(0.0, 1.5, 9.0)
		sim.player.heading = float(way[1])
		sim.player.speed = float(sim.player.stats.top_speed)
		sim.lancer.pos = sim.player.pos - AquaticSim.forward_of(float(way[1])) * 10.0
		sim.lancer.state = "pursue"
		sim.lancer.until = sim.tick + int(round(float(lancer.pursue) * AquaticSim.TICK_HZ))
		var run := {"why": "", "struck": false}
		for i in 8 * AquaticSim.TICK_HZ:
			sim.step(AquaticSim.Intent.new(1.0, 0.0, 0.0))
			for e in sim.take_events():
				if e.type == "struck" and e.by == "lancer":
					run.struck = true
				if e.type == "lancer_gave_up" and run.why == "":
					run.why = String(e.why)
			if run.why != "":
				break
		runs[way[0]] = run
	check(runs.to.why == "hidden" and not runs.to.struck, "into the pillar ring: it gives up unhurt (%s)" % [runs.to])
	check(runs.away.struck, "away from it: struck (%s)" % [runs.away])


## aquatic-r2 (PROPOSED): the krill swarm (twilight, in the lancer's patrol) feeds a filter mouth and not a jaw; the
## fallen giant's carcass (deep) feeds a jaw and not a filter mouth; each regrows on its own timer, the krill drifts in
## open water and the carcass lies on the floor, and the nest-side algae bed is filter food in the shallows.
func test_new_feeding_grounds_feed_the_right_mouths_and_regrow() -> void:
	var filter := AquaticBody.HOVERER.duplicate()
	filter.mouth = "filter"
	var jaw := AquaticBody.HOVERER.duplicate()
	jaw.mouth = "jaw"
	for c in [["krill_swarm", filter, true], ["krill_swarm", jaw, false], ["fallen_giant", jaw, true], ["fallen_giant", filter, false],
			["algae_nest", filter, true], ["algae_nest", jaw, false]]:
		var sim := _sim(c[1])
		var site := _site("feeding", c[0])
		check(not site.is_empty(), "%s is a feeding site" % c[0])
		if site.is_empty():
			continue
		var item: Dictionary = sim.food.filter(func(f): return f.site == c[0])[0]
		var kind: Dictionary = rules.world.food[site.kind]
		sim.player.energy = 10.0
		sim.player.pos = item.pos
		sim.step(AquaticSim.Intent.new())
		var ate: Array = sim.take_events().filter(func(e): return e.type == "ate")
		check_eq(not item.alive, c[2], "%s by a %s mouth: eaten %s" % [c[0], c[1].mouth, c[2]])
		if not c[2]:
			continue
		check(ate.size() == 1 and is_equal_approx(float(ate[0].energy), float(kind.energy)), "worth its energy: %s" % [ate])
		var regrow := AquaticSim._ticks(kind.regrow)
		for i in regrow - 1:
			sim.player.pos = Vector3(0.0, -5.0, 25.0)
			sim.step(AquaticSim.Intent.new())
		check(not item.alive, "%s is not back before its %.0f s" % [c[0], float(kind.regrow)])
		sim.step(AquaticSim.Intent.new())
		check(item.alive, "%s regrows after %.0f s" % [c[0], float(kind.regrow)])
	var sim := _sim(AquaticBody.DARTER)
	for f in sim.food:
		var on_floor := float(f.pos.y) - sim.floor_at(f.pos.x, f.pos.z) <= float(rules.world.floor_margin) + 0.01
		if f.site == "krill_swarm":
			check(not on_floor and float(f.pos.y) > sim.floor_at(f.pos.x, f.pos.z) + 3.0, "%s drifts in open water" % f.id)
		elif f.site == "fallen_giant":
			check(on_floor, "%s lies on the floor" % f.id)


## Every shelter and feeding site, and every food item, sits in the water inside the walls, in the zone its rules entry
## names and no deeper than the deepest legal rated depth (a shelter's centre may lie on the floor, as the west arch's
## does, but not under it, and its reach rises into open water); the ids are unique (the save's discovered list keeps
## them); and no shelter lies across the drifter's loop, so a fish in its path is swept.
func test_every_site_sits_in_the_water_and_its_zone() -> void:
	var sim := _sim(AquaticBody.DARTER)
	var w: Dictionary = rules.world
	var r: Dictionary = rules.body.ranges
	var rd: Dictionary = rules.body.rated_depth
	var deepest := float(rd.base) + float(rd.per_girth) * (int(r.girth[1]) - 1) + float(rd.per_bladder) * int(r.bladder[1])
	var ids := {}
	var zone_of := {}
	for list in ["shelters", "feeding"]:
		for site in w[list]:
			var p := AquaticSim._v(site.pos)
			var id := String(site.id)
			check(not ids.has(id), "%s is a unique id" % id)
			ids[id] = true
			zone_of[id] = String(site.get("zone", ""))
			check_eq(String(sim.zone_at(p).id), String(site.get("zone", "")), "%s is in its zone" % id)
			var floor_y := sim.floor_at(p.x, p.z)
			var in_water := p.y > floor_y + float(w.floor_margin) if list == "feeding" else \
					(p.y >= floor_y - 0.01 and p.y + float(site.radius) > floor_y + float(w.floor_margin) + 2.0)
			check(p.y < -float(w.surface_margin) and in_water, "%s is in the water (%.1f, floor %.1f)" % [id, p.y, floor_y])
			check(absf(p.x) <= AquaticSim.WALL_START and p.z < float(w.shore_z) and p.z > float(w.end_z), "%s is inside the walls" % id)
			check(-p.y <= deepest, "%s is no deeper than %.0f m" % [id, deepest])
	for f in sim.food:
		check(-float(f.pos.y) <= deepest and String(sim.zone_at(f.pos).id) == zone_of[f.site],
				"%s (%s) is in its site's zone at %.1f m" % [f.id, f.site, -f.pos.y])
	var period := AquaticSim._ticks(rules.hazards.drifter.period)
	for site in w.shelters:
		var closest := INF
		for t in range(0, period, 6):
			sim.tick = t
			sim._move_drifter()
			closest = minf(closest, AquaticSim._v(site.pos).distance_to(sim.drifter.pos))
		check(closest > float(site.radius) + 2.0, "%s keeps off the drifter's loop (%.1f m)" % [site.id, closest])


## The world draws every food kind a site uses, and every shelter and landmark look names a real site and a real scene
## (or, for a landmark, a fish FishView draws).
func test_every_site_and_food_kind_is_drawn() -> void:
	var world := preload("res://game/scenes/aquatic/aquatic_world.gd")
	var fish_view := preload("res://game/scenes/aquatic/fish_view.gd")
	for site in rules.world.feeding:
		check(world.FOOD_SCENES.has(site.kind) and ResourceLoader.exists(world.FOOD_SCENES.get(site.kind, "")),
				"the %s food has its scene" % site.kind)
	for id in world.SHELTER_LOOKS:
		check(not _site("shelters", id).is_empty(), "%s is a shelter in the rules" % id)
		check(ResourceLoader.exists(String(world.SHELTER_LOOKS[id].scene)), "%s's scene exists" % id)
	for id in world.SITE_LANDMARKS:
		check(not _site("feeding", id).is_empty(), "%s is a feeding site in the rules" % id)
		check(fish_view.SPECIES.has(String(world.SITE_LANDMARKS[id].fish)), "%s is drawn as a fish FishView knows" % id)


func test_the_world_is_deterministic() -> void:
	var a := _sim(AquaticBody.HOVERER, 42)
	var b := _sim(AquaticBody.HOVERER, 42)
	for i in 20 * AquaticSim.TICK_HZ:
		var intent := AquaticSim.Intent.new(1.0, sin(i * 0.01), -0.3)
		a.step(intent)
		b.step(intent)
	check_eq(a.state_hash(), b.state_hash(), "same seed and intents, same world")
	check(_sim(AquaticBody.HOVERER, 43).state_hash() != _sim(AquaticBody.HOVERER, 42).state_hash(), "another seed, another world")


func test_food_regrows_and_the_diet_decides_what_is_eaten() -> void:
	var sim := _sim(AquaticBody.DARTER)
	var plankton: Dictionary = sim.food[0]
	sim.player.energy = 10.0
	sim.player.pos = plankton.pos
	sim.step(AquaticSim.Intent.new())
	check(not plankton.alive, "an omnivore eats plankton")
	for i in int(round(float(rules.world.food.plankton.regrow) * AquaticSim.TICK_HZ)) + 1:
		sim.player.pos = Vector3(0.0, -5.0, 25.0)
		sim.step(AquaticSim.Intent.new())
	check(plankton.alive, "it regrows")
	var hunter := AquaticBody.DARTER.duplicate()
	hunter.mouth = "jaw"
	sim = _sim(hunter)
	sim.player.pos = sim.food[0].pos
	sim.step(AquaticSim.Intent.new())
	check(sim.food[0].alive, "a jaw does not filter plankton")


## Save v5 (plan decision 2): what the sim keeps comes back as it was, the world is rebuilt from the seed, and the
## lineage is written only to a slot it can read.
func test_the_saved_block_restores_the_fish_and_keeps_the_save_rules() -> void:
	var sim := _sim(AquaticBody.DARTER)
	sim.player.pos = Vector3(4.0, -20.0, -60.0)
	sim.player.heading = 0.75
	sim.player.energy = 30.0
	sim.player.health = 9.0
	sim.meals = 5
	sim.discovered.append("kelp_arch")
	sim.relations.grazer.standing = "friend"
	sim.relations.grazer.rapport = 3
	check(sim.apply_offspring(AquaticBody.HOVERER, 0), "a new generation")
	# A place in the water (the floor rises here), with its zone found, as a swim there would leave it.
	sim.player.pos = sim._clamp_to_water(Vector3(4.0, -12.0, -60.0))
	sim._discover(String(sim.zone_at(sim.player.pos).id))
	var block := sim.to_save()
	var save := SaveGame.new_run(7, "test")
	save.aquatic = block
	check(SaveGame.validate_aquatic(block, func(b): return AquaticBody.validate(b, rules.body)).is_empty(),
		"the block passes the save's checks: %s" % [SaveGame.validate_aquatic(block)])
	var again := SaveGame.from_dict(JSON.parse_string(JSON.stringify(save.to_dict())))
	var back := AquaticSim.new(rules, 7, again.aquatic.body, {"aquatic": again.aquatic, "points": 4})
	check_eq(JSON.stringify(back.to_save(), "", true), JSON.stringify(block, "", true), "the same block after a round trip")
	check_eq(back.points, 4, "points are the save's")
	check_eq(back.snapshot().food, _sim(AquaticBody.DARTER).snapshot().food, "the food comes from the seed")
	var dead := block.duplicate(true)
	dead.health = 0.0
	var fresh := AquaticSim.new(rules, 7, dead.body, {"aquatic": dead})
	check(fresh.player.pos.distance_to(fresh.nest_pos()) < 5.0 and float(fresh.player.health) > 0.0,
		"a fish saved with no health starts again at the nest")


func test_the_lineage_is_written_only_to_a_slot_it_can_read() -> void:
	var dir := "user://test_saves/aquatic_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	var slot := dir + "/slot.json"
	for f in [slot, slot + ".bak", slot + ".tmp"]:
		DirAccess.remove_absolute(f)
	var lineage := AquaticLineage.read(slot, rules, 11)
	check(lineage.ok and lineage.writable and not lineage.returning, "an empty slot founds a lineage it can write")
	var sim := AquaticSim.new(rules, 11, lineage.body, lineage)
	sim.points = 9
	check_eq(AquaticLineage.write(slot, lineage, sim), OK, "written")
	var again := AquaticLineage.read(slot, rules, 99)
	check(again.returning and again.lineage_id == lineage.lineage_id, "read back as a line that has swum")
	check_eq(int(again.points), 9, "with its points, no starting floor")
	check_eq(int(again.world_seed), 11, "and the save's seed")
	var file := FileAccess.open(slot, FileAccess.WRITE)
	file.store_string("not json")
	file.close()
	DirAccess.remove_absolute(slot + ".bak")
	var broken := AquaticLineage.read(slot, rules, 11)
	check(not broken.writable and not broken.errors.is_empty(), "a slot that will not load is not writable")
	check(AquaticLineage.write(slot, broken, AquaticSim.new(rules, 11, broken.body, broken)) != OK, "and is never written")
	check_eq(FileAccess.get_file_as_string(slot), "not json", "the broken file is left as it is")
	for f in [slot, slot + ".bak", slot + ".tmp"]:
		DirAccess.remove_absolute(f)
