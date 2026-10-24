extends RefCounted
## Dev and test driver for PoolSim (debug builds only; no class_name, loaded by path): a player who
## has not learned yet what hurts, for the growth gates (S2 gate S2G16, s2-sim 3.12). It wraps
## ForageBot.
##  - Mode "clumsy": until the cell has died DEATHS_TO_LEARN times, it swims straight at an awake
##    creature at q == 1 that is on screen (the default zoom's view), full throttle, until that
##    charge ends with a hit on the cell or the cell's death. A creature it charged when a hit
##    landed is passed over from then on, as a player remembers what bit them. With no such
##    creature on screen, and after the second death, it is plain ForageBot.
##  - Mode "die": below DIE_BELOW of its energy capacity it swims at the nearest awake creature at
##    q == 1 within DIE_REACH_TM, or holds still and starves when there is none; above it, plain
##    ForageBot. The die-on-purpose gate measures that dying never grows a cell faster than eating.
## q is the creature's species at the cell's size (SpeciesCatalog.q_of): in the pool and at size 1
## every M1 species is at q == 1, at size 2 only the species that enter there. Neither mode presses
## Grow in an auto run; its `keys` (EvadeBot.GrowthKeys) send the trigger on its first intent.
##
## It reads its own cell (death, energy, the hits it took: sim.stats.hits_taken) and the creatures,
## as a player watching the screen would; like player input it only returns a SimIntent and never
## changes the sim.
##
##     var bot = load("res://game/dev/clumsy_bot.gd").new("clumsy")
##     sim.step(bot.next_intent(sim))

const ForageBot := preload("res://game/dev/forage_bot.gd")
const EvadeBot := preload("res://game/dev/evade_bot.gd")

const CLUMSY := "clumsy"
const DIE := "die"
const DEATHS_TO_LEARN := 2     ## clumsy: deaths after which it forages only
const DIE_BELOW := 0.5         ## die: share of the energy capacity below which it seeks a death
const DIE_REACH_TM := 40.0     ## die: how far (current tm) it looks for a creature to die on
## What it sees: the camera's view of the plane at the default zoom, on a 16:9 screen (HuntBot's).
const VIEW_ASPECT := 16.0 / 9.0
const Q_SLACK := 1e-9          ## q is exactly 1.0 at the entry size (Relationships.q_of)

var mode := CLUMSY
var keys := EvadeBot.GrowthKeys.new()
var forage = ForageBot.new()
var deaths := 0                ## the cell's deaths it has seen
var charges := 0               ## creatures it set off at (tests guard that it was clumsy)
var _target := ""
var _hit_by := {}              ## clumsy: creature id -> true, charged when a hit on the cell landed
var _was_dead := false
var _hits_seen := 0


func _init(p_mode := CLUMSY) -> void:
	assert(p_mode == CLUMSY or p_mode == DIE, "ClumsyBot: mode is clumsy or die")
	mode = p_mode
	forage.keys.trigger = ""   # this bot sends the keys


## The id of the creature it swims at now, or "".
func target_id() -> String:
	return _target


func next_intent(sim: PoolSim) -> SimIntent:
	return keys.apply(sim, _intent(sim))


func _intent(sim: PoolSim) -> SimIntent:
	_watch(sim)
	if sim.dead:
		return SimIntent.new()
	if mode == DIE:
		return _die(sim)
	if deaths >= DEATHS_TO_LEARN:
		return forage.next_intent(sim)
	var c := _charge_target(sim)
	if c == null:
		return forage.next_intent(sim)
	return _at(sim, c)


## Deaths (the cell going dead) and hits on the cell since the last call. A hit ends the charge and
## marks the creature charged; a death ends it too.
func _watch(sim: PoolSim) -> void:
	if sim.dead and not _was_dead:
		deaths += 1
		_target = ""
	_was_dead = sim.dead
	var hits := int(sim.stats.hits_taken)
	if hits > _hits_seen and not _target.is_empty():
		_hit_by[_target] = true
		_target = ""
	_hits_seen = hits


## Clumsy: the creature it charges, kept while it stays awake, at q == 1 and on screen; else the
## nearest such one it has not been hit while charging (ties by id). null when there is none.
func _charge_target(sim: PoolSim) -> CreatureField.Creature:
	var cam := sim.layout.camera
	var best: CreatureField.Creature = null
	var best_d := INF
	for c: CreatureField.Creature in _active(sim):
		if _hit_by.has(c.id) or not at_q1(sim, c):
			continue
		if not ViewFootprint.contains(sim.motion.position, c.motion.position, cam, float(cam.distance), VIEW_ASPECT):
			continue
		if c.id == _target:
			return c
		var d := sim.motion.position.distance_to(c.motion.position)
		if d < best_d or (d == best_d and c.id < best.id):
			best_d = d
			best = c
	if best != null:
		charges += 1
	_target = best.id if best != null else ""
	return best


## Die: below DIE_BELOW of capacity, at the nearest awake q == 1 creature within DIE_REACH_TM
## (ties by id), or still; above it, ForageBot.
func _die(sim: PoolSim) -> SimIntent:
	if sim.state.energy >= sim.state.energy_capacity * DIE_BELOW:
		_target = ""
		return forage.next_intent(sim)
	var best: CreatureField.Creature = null
	var best_d := INF
	for c: CreatureField.Creature in _active(sim):
		if not at_q1(sim, c):
			continue
		var d := sim.motion.position.distance_to(c.motion.position)
		if d <= DIE_REACH_TM and (d < best_d or (d == best_d and c.id < best.id)):
			best_d = d
			best = c
	if best == null:
		_target = ""
		return SimIntent.new()
	if best.id != _target:
		charges += 1
	_target = best.id
	return _at(sim, best)


## Full throttle straight at the creature (round a rock in the way, as ForageBot goes for food).
func _at(sim: PoolSim, c: CreatureField.Creature) -> SimIntent:
	var pos := sim.motion.position
	var to := sim.arena.route_point(pos, c.motion.position, sim.phenotype.radius) - pos
	return SimIntent.new(to.normalized()) if to.length() > 1e-6 else SimIntent.new()


## Whether the creature's species is at q == 1 at the cell's size (a data creature; one with no
## species record is not).
static func at_q1(sim: PoolSim, c: CreatureField.Creature) -> bool:
	if sim.species == null or not sim.species.has_species(c.species_id):
		return false
	return absf(sim.species.q_of(c.species_id, sim.size()) - 1.0) <= Q_SLACK


## The creatures that act this tick: all of them in the pool, the awake ones in the endless world
## (CreatureField.awake(), S1 spine 3.10). Read by name, so the bot also loads before the endless
## world.
static func _active(sim: PoolSim) -> Array:
	var field: Object = sim.creatures
	if field == null:
		return []
	return field.call("awake") if field.has_method("awake") else sim.creatures.creatures
