extends RefCounted
## Dev and test tool (debug builds only; no class_name, loaded by path): the balance lab. It runs a
## dev bot in the real pool, with the real species, for one starting body and one seed, and counts
## how the cell does: time alive, deaths and what caused them, meals and energy a minute, time spent
## starving, threat meetings, hits, dodges and kills. It only reads the sim and its events; the bots
## only hand it intents, so a run changes nothing in the game and repeats exactly for a seed.
## tests/balance/balance_lab_main.gd sweeps it over bodies, bots and seeds and writes the report
## (tools/balance_lab.sh); tests/test_balance_lab.gd checks it.
##
## The bots, each the way the tests already use it:
##   forage  ForageBot alone: nearest food its body eats, never minds a creature (a careless player)
##   wary    ForageBot with avoid_threats: passes over food by creatures, steers clear, dodges tells
##   evade   ForageBot under EvadeBot: nearest food, dodging each tell 0.4 s after it starts (gate #32)
##   hunt    HuntBot: hunts rammers with the jaw and lives on the carrion (gate #30, meant for hunters)
##   kiter   KiterBot: circles creature after creature and bites dazed ones (the fuzz driver, reckless)
##
##     var lab = load("res://game/dev/balance_lab.gd").new()
##     var run: Dictionary = lab.run("grazer", "evade", 501, 300 * 60)

const ForageBot := preload("res://game/dev/forage_bot.gd")
const EvadeBot := preload("res://game/dev/evade_bot.gd")
const HuntBot := preload("res://game/dev/hunt_bot.gd")
const KiterBot := preload("res://game/dev/kiter_bot.gd")

const BOTS: PackedStringArray = ["forage", "wary", "evade", "hunt", "kiter"]
const BUILD_ID := "balance-lab+dev"
## A dead cell continues at its checkpoint after this, as a player reading the death notice would
## (the gates' DEATH_NOTICE_TICKS).
const DEATH_NOTICE_TICKS := 90

var catalog: PartCatalog
var layout: PoolLayout
var species: SpeciesCatalog


func _init(p_catalog: PartCatalog = null, p_layout: PoolLayout = null, p_species: SpeciesCatalog = null) -> void:
	catalog = p_catalog if p_catalog != null else PartCatalog.load_from()
	layout = p_layout if p_layout != null else PoolLayout.load_from()
	species = p_species if p_species != null else SpeciesCatalog.load_from()


## The bodies a lineage may start as, sorted.
func bodies() -> PackedStringArray:
	var out := PackedStringArray(catalog.starting_bodies.keys())
	out.sort()
	return out


## One run: a new `body` lineage at the spawn driven by `bot` for `ticks`. Returns the counts (see
## _new_run) with the run's state hash, so two runs of the same seed can be compared.
func run(body: String, bot: String, seed_value: int, ticks: int) -> Dictionary:
	var r := Lineage.found(seed_value, BUILD_ID, catalog, body)
	if not r.ok:
		return {"ok": false, "errors": r.errors}
	r.save.player["position"] = PlaneSpace.to_save(layout.spawn)
	var sim := PoolSim.create(r.save, catalog, layout, species)
	sim.drain_events()
	var driver := _driver(bot, seed_value)
	if not driver.is_valid():
		return {"ok": false, "errors": PackedStringArray(["Unknown bot '%s'." % bot])}
	var out := _new_run(body, bot, seed_value, ticks)
	out.fits = fits(sim.phenotype, bot)
	var events: Array = []
	var dead_since := -1
	var alive_since := 0
	var energy_sum := 0.0
	var met := {}   # creature id -> true: it noticed or told at the cell this life
	for i in ticks:
		if sim.dead:
			if dead_since < 0:
				dead_since = sim.tick
			elif sim.tick - dead_since >= DEATH_NOTICE_TICKS:
				sim.respawn_player()
				dead_since = -1
				alive_since = sim.tick
				events.append_array(sim.drain_events())
		sim.step(driver.call(sim, events))
		events = sim.drain_events()
		if sim.dead:
			out.dead_ticks += 1
		else:
			energy_sum += sim.state.energy / sim.state.energy_capacity
			if sim.state.is_starving():
				out.starving_ticks += 1
		for e in events:
			_count(out, e, sim, alive_since, met)
	out.alive_ticks = ticks - int(out.dead_ticks)
	out.mean_energy_share = energy_sum / maxf(1.0, float(out.alive_ticks))
	out.points = sim.save.adaptation_points
	out.distance_m = float(sim.stats.distance_m)
	out.state_hash = sim.state_hash()
	if out.first_death_tick < 0:
		out.first_death_tick = ticks   # never died: counts as lasting the whole run
	return out


func _new_run(body: String, bot: String, seed_value: int, ticks: int) -> Dictionary:
	return {"ok": true, "body": body, "bot": bot, "seed": seed_value, "ticks": ticks,
		"alive_ticks": 0, "dead_ticks": 0, "starving_ticks": 0, "first_death_tick": -1, "mean_energy_share": 0.0,
		"deaths": 0, "starved": 0, "killed": 0, "killed_by": {}, "lives_ticks": [],
		"meals": 0, "plankton_meals": 0, "carrion_meals": 0, "energy_supplied": 0.0,
		"notices": 0, "tells": 0, "hits_taken": 0, "damage_taken": 0.0, "hits_dealt": 0, "dodges": 0, "kills": 0,
		"points": 0, "distance_m": 0.0, "state_hash": 0, "fits": true}


func _count(out: Dictionary, e: Dictionary, sim: PoolSim, alive_since: int, met: Dictionary) -> void:
	match str(e.type):
		"died":
			out.deaths += 1
			out.lives_ticks.append(sim.tick - alive_since)
			if out.first_death_tick < 0:
				out.first_death_tick = sim.tick
			if e.cause == "starved":
				out.starved += 1
			else:
				out.killed += 1
				var by := str(e.by_species) if not str(e.by_species).is_empty() else str(e.cause)
				out.killed_by[by] = int(out.killed_by.get(by, 0)) + 1
			met.clear()
		"ate":
			out.meals += 1
			out.energy_supplied += float(e.get("supplied", 0.0))
			if str(e.kind) == "meat":
				out.carrion_meals += 1
			else:
				out.plankton_meals += 1
		"creature_noticed":
			if e.target == CreatureField.PLAYER_ID:
				out.notices += 1
		"creature_tell":
			if e.target == CreatureField.PLAYER_ID:
				out.tells += 1
		"hit":
			if e.target == CreatureField.PLAYER_ID:
				out.hits_taken += 1
				out.damage_taken += float(e.get("dealt", 0.0))
			elif e.attacker == CreatureField.PLAYER_ID:
				out.hits_dealt += 1
		"dodged":
			out.dodges += 1
		"creature_died":
			if e.by == CreatureField.PLAYER_ID:
				out.kills += 1


## Callable(sim, events) -> SimIntent for a bot name, or an empty Callable. Each is a lambda that
## holds its bot (a bound method alone would not keep a RefCounted bot alive).
func _driver(bot: String, seed_value: int) -> Callable:
	match bot:
		"forage":
			var f = ForageBot.new()
			return func(sim: PoolSim, _events: Array) -> SimIntent: return f.next_intent(sim)
		"wary":
			var f = ForageBot.new()
			f.avoid_threats = true
			return func(sim: PoolSim, _events: Array) -> SimIntent: return f.next_intent(sim)
		"evade":
			var f = ForageBot.new()
			var e = EvadeBot.new()
			e.base = func(sim: PoolSim) -> SimIntent: return f.next_intent(sim)
			return func(sim: PoolSim, events: Array) -> SimIntent: return e.next_intent(sim, events)
		"hunt":
			var h = HuntBot.new()
			return func(sim: PoolSim, events: Array) -> SimIntent: return h.next_intent(sim, events)
		"kiter":
			var k = KiterBot.new(seed_value)
			return func(sim: PoolSim, _events: Array) -> SimIntent: return k.next_intent(sim)
	return Callable()


## Whether a bot plays the way this body is meant to be played: the foragers need a body that eats
## plankton ("plant"), the hunter one that bites. The kiter fits every body (it is the reckless
## stress driver). A run that does not fit still counts, but raises no flags: a grazer that cannot
## bite starving under HuntBot says nothing about balance.
static func fits(phenotype: Phenotype, bot: String) -> bool:
	match bot:
		"forage", "wary", "evade":
			return phenotype.can_eat("plant")
		"hunt":
			return phenotype.bite_damage > 0.0
	return true


## Per body and bot, over the runs given: the means and totals the report shows. Rows are sorted by
## body, then by bot in BOTS order.
static func summarize(runs: Array) -> Array[Dictionary]:
	var groups := {}
	for r in runs:
		if not r.get("ok", false):
			continue
		var key := "%s|%s" % [r.body, r.bot]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(r)
	var keys := groups.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var pa := a.split("|")
		var pb := b.split("|")
		if pa[0] != pb[0]:
			return pa[0] < pb[0]
		return BOTS.find(pa[1]) < BOTS.find(pb[1]))
	var rows: Array[Dictionary] = []
	for key in keys:
		var list: Array = groups[key]
		var minutes := 0.0
		var alive_min := 0.0
		var row := {"body": list[0].body, "bot": list[0].bot, "fits": bool(list[0].get("fits", true)), "runs": list.size(), "seeds": [],
			"deaths": 0, "starved": 0, "killed": 0, "killed_by": {}, "meals": 0, "carrion_meals": 0,
			"tells": 0, "notices": 0, "dodges": 0, "hits_taken": 0, "kills": 0, "survived_runs": 0,
			"starving_ticks": 0, "alive_ticks": 0, "first_death_ticks": [], "energy_share_sum": 0.0}
		for r in list:
			row.seeds.append(r.seed)
			minutes += float(r.ticks) / 3600.0
			alive_min += float(r.alive_ticks) / 3600.0
			for k in ["deaths", "starved", "killed", "meals", "carrion_meals", "tells", "notices", "dodges", "hits_taken",
					"kills", "starving_ticks", "alive_ticks"]:
				row[k] += int(r[k])
			for by in r.killed_by:
				row.killed_by[by] = int(row.killed_by.get(by, 0)) + int(r.killed_by[by])
			row.survived_runs += 1 if int(r.deaths) == 0 else 0
			row.first_death_ticks.append(int(r.first_death_tick))
			row.energy_share_sum += float(r.mean_energy_share)
		row.minutes = minutes
		row.survival_share = float(row.survived_runs) / list.size()
		row.deaths_per_5_min = row.deaths / minutes * 5.0
		row.starved_per_5_min = row.starved / minutes * 5.0
		row.meals_per_min = row.meals / maxf(alive_min, 1e-6)
		row.meetings_per_min = (row.notices + row.tells) / minutes
		row.dodge_share = float(row.dodges) / row.tells if row.tells > 0 else 0.0
		row.starving_share = float(row.starving_ticks) / maxf(1.0, float(row.alive_ticks))
		row.mean_energy_share = row.energy_share_sum / list.size()
		var firsts: Array = row.first_death_ticks.duplicate()
		firsts.sort()
		row.median_first_death_s = float(firsts[firsts.size() / 2]) / 60.0
		row.erase("energy_share_sum")
		rows.append(row)
	return rows


## Flags for a body and bot that look out of balance, plain words, for the report. Thresholds are
## the lab's own reading aids (PROPOSED), not gates: the step 3 gates stay in test_threat_gates.
static func flags(row: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if not row.get("fits", true):
		return out
	var careful: bool = row.bot in ["wary", "evade", "hunt"]
	if row.starved_per_5_min > 0.25:
		out.append("starves (%.2f per 5 min)" % row.starved_per_5_min)
	if careful and row.deaths_per_5_min > 0.5:
		out.append("a careful bot is worn down (%.2f deaths per 5 min)" % row.deaths_per_5_min)
	if careful and row.meetings_per_min < 0.5:
		out.append("few threats met (%.2f a minute)" % row.meetings_per_min)
	if row.meals_per_min < 1.0:
		out.append("eats little (%.2f meals a minute alive)" % row.meals_per_min)
	if careful and row.mean_energy_share > 0.9 and row.deaths == 0:
		out.append("never under pressure (mean energy %.0f%%, no deaths)" % (row.mean_energy_share * 100.0))
	if row.starving_share > 0.2:
		out.append("starving %.0f%% of the time alive" % (row.starving_share * 100.0))
	return out
