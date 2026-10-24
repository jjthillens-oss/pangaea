extends TestCase
## S4.1 pacing (docs/s4/s4-plan.md): the points a run earns buy a part at about the pace the owner
## asked for after his playtest (2026-10-24): parts from mating within minutes, not 20 minutes of
## grazing. Soak, since each run plays 6 minutes of the endless sea with growth on:
##  - ForageBot grazer (wary) and HuntBot hunter, seeds 11 and 12: by 3 minutes each can afford the
##    cheapest editor part (the first mate is within reach), and over 6 minutes a part of the mean
##    editor cost takes each 1.5 to 4.5 minutes of points, so neither diet runs away with the editor.
## Measured on e2 8520811 with the M1 costs (10 to 25): the grazer earned 46 points by 3 minutes and
## about 15 a minute, the hunter 66 and about 25, a mean part every 0.9 and 0.6 minutes; so the
## editor parts cost four times as much (40 to 100).

const ForageBot := preload("res://game/dev/forage_bot.gd")
const HuntBot := preload("res://game/dev/hunt_bot.gd")
const Gates := preload("res://tests/test_endless_gates.gd")
const TPS := 60.0
const RUN_S := 360.0
const FIRST_PART_BY_S := 180.0
const MEAN_PART_MIN_S := 90.0    ## a mean part takes at least 1.5 minutes of points
const MEAN_PART_MAX_S := 270.0   ## and at most 4.5
const SEEDS: Array[int] = [11, 12]


func test_soak_a_grazer_and_a_hunter_earn_a_part_every_few_minutes() -> void:
	var catalog := PartCatalog.load_from()
	var costs := []
	for type_id in catalog.parts:
		if catalog.in_editor(type_id):
			costs.append(catalog.cost_of(type_id))
	var cheapest: int = costs.min()
	var mean := 0.0
	for c in costs:
		mean += float(c) / costs.size()
	for b in [["forage", "grazer"], ["hunt", "hunter"]]:
		for seed_value in SEEDS:
			var run := points_run(b[0], b[1], seed_value)
			var per_s: float = run.total / RUN_S
			var part_s: float = mean / per_s if per_s > 0.0 else INF
			print("test-pacing-gates: %s %s seed %d: %d points by 3 min, %d by 6 (%s), a mean part (%.0f) every %.0f s" % [
				b[0], b[1], seed_value, run.at_first, run.total, run.sources, mean, part_s])
			check(run.at_first >= cheapest, "%s %s seed %d affords the cheapest part (%d) by 3 minutes (%d)" % [
				b[0], b[1], seed_value, cheapest, run.at_first])
			check(part_s >= MEAN_PART_MIN_S and part_s <= MEAN_PART_MAX_S,
				"%s %s seed %d earns a mean part in 1.5 to 4.5 minutes (%.0f s)" % [b[0], b[1], seed_value, part_s])


## One run from home with growth on: `bot_name` ("forage" wary or "hunt") on `body` for RUN_S, dying
## and going on as a player would. Returns {"at_first" (points at FIRST_PART_BY_S), "total", "sources"
## (reason -> points: the earned reasons and "meal" for food)}.
static func points_run(bot_name: String, body: String, seed_value: int) -> Dictionary:
	var sim: Variant = Gates.make_sim(body, seed_value, true)
	var bot: Variant
	if bot_name == "forage":
		bot = ForageBot.new()
		bot.avoid_threats = true
	else:
		bot = HuntBot.new()
	var start: int = sim.save.adaptation_points
	var out := {"at_first": 0, "total": 0, "sources": {}}
	var events: Array[Dictionary] = []
	var dead := {}
	for i in int(RUN_S * TPS):
		events.append_array(Gates.continue_after_death(sim, dead))
		var intent: SimIntent = bot.next_intent(sim, events) if bot_name == "hunt" else bot.next_intent(sim)
		events = Gates.tick(sim, intent)
		for e in events:
			var reason := ""
			match str(e.type):
				"earned":
					reason = str(e.reason)
				"ate":
					reason = "meal"
			if reason != "" and int(e.get("points", 0)) > 0:
				out.sources[reason] = int(out.sources.get(reason, 0)) + int(e.points)
		if i + 1 == int(FIRST_PART_BY_S * TPS):
			out.at_first = sim.save.adaptation_points - start
	out.total = sim.save.adaptation_points - start
	return out
