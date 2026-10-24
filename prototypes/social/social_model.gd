extends RefCounted
## PROPOSED social rules, isolated from the creature stage and production saves.

const IDS: PackedStringArray = ["ara", "bren", "cyra"]
const HELP_LIFE := 3
const BROKEN_LIFE := 6

var seed := 1
var player_food := 3
var player_stamina := 6
var route_food := 3
var insight := 0
var signal_bonus := 0
var shared_routes := 0
var contests := 0
var people := {}


func _init(world_seed: int = 1) -> void:
	seed = world_seed
	# Fixed IDs and arithmetic traits make restart and tie order reproducible.
	for index in IDS.size():
		var id := IDS[index]
		people[id] = {
			"id": id,
			"disposition": posmod(seed * 17 + index * 11, 3),
			"food_need": 2 + posmod(seed + index, 2),
			"danger_need": 1 + posmod(seed * 3 + index, 2),
			"memory": [],
			"promise": false
		}


func person(id: String) -> Dictionary:
	return (people.get(id, {}) as Dictionary).duplicate(true)


func _memory_count(id: String, kind: String) -> int:
	var count := 0
	for event: Dictionary in people[id].memory:
		if event.kind == kind:
			count += 1
	return count


func memory_count(id: String, kind: String) -> int:
	return _memory_count(id, kind) if people.has(id) else 0


func trust(id: String) -> int:
	if not people.has(id):
		return -99
	var p: Dictionary = people[id]
	return int(p.disposition) + signal_bonus + 2 * _memory_count(id, "help") - 3 * _memory_count(id, "broken") - _memory_count(id, "contest")


func _age_memory(id: String) -> void:
	var kept := []
	for event: Dictionary in people[id].memory:
		var next := event.duplicate()
		next.ttl = int(next.ttl) - 1
		if next.ttl > 0:
			kept.append(next)
	people[id].memory = kept


func _remember(id: String, kind: String, lifetime: int) -> void:
	people[id].memory.append({"kind": kind, "ttl": lifetime})


func promise_help(id: String) -> bool:
	if not people.has(id) or people[id].promise:
		return false
	people[id].promise = true
	return true


func break_promise(id: String) -> bool:
	if not people.has(id) or not people[id].promise:
		return false
	_age_memory(id)
	people[id].promise = false
	_remember(id, "broken", BROKEN_LIFE)
	return true


## Every signal is an encounter. Replies use disposition, current need and prior memory.
## Failure returns a reason and spends nothing. A response records its consequence.
func interact(id: String, intention: String) -> Dictionary:
	if not people.has(id):
		return {"ok": false, "response": "Unknown individual"}
	if not ["greet", "share", "warn", "challenge"].has(intention):
		return {"ok": false, "response": "Unknown intention"}
	var p: Dictionary = people[id]
	if intention == "share" and (player_food < 1 or int(p.food_need) < 1):
		return {"ok": false, "response": "No food can be shared"}
	if intention == "warn" and int(p.danger_need) < 1:
		return {"ok": false, "response": "No danger to warn of"}
	if intention == "challenge" and player_stamina < 2:
		return {"ok": false, "response": "Too tired to contest"}
	_age_memory(id)
	var before := trust(id)
	var response := ""
	match intention:
		"greet":
			response = "welcomes" if before >= 3 else "watches cautiously"
		"share":
			player_food -= 1
			p.food_need = int(p.food_need) - 1
			_remember(id, "help", HELP_LIFE)
			if p.promise:
				p.promise = false
			response = "accepts food" if before >= 0 else "takes food carefully"
		"warn":
			p.danger_need = int(p.danger_need) - 1
			_remember(id, "help", HELP_LIFE)
			if p.promise:
				p.promise = false
			response = "takes shelter" if before >= 0 else "checks the warning"
		"challenge":
			player_stamina -= 2
			contests += 1
			_remember(id, "contest", HELP_LIFE)
			response = "yields route" if before >= 2 else "holds ground"
	return {"ok": true, "response": response, "trust": trust(id), "intention": intention}


## A companion helps move one food past danger only when the earned trust is sufficient.
func carry_together(id: String) -> Dictionary:
	if not people.has(id):
		return {"ok": false, "response": "Unknown individual"}
	if trust(id) < 4:
		return {"ok": false, "response": "Needs more trust"}
	if route_food < 1:
		return {"ok": false, "response": "Route is empty"}
	if player_stamina < 1:
		return {"ok": false, "response": "Too tired to carry"}
	route_food -= 1
	player_food += 1
	player_stamina -= 1
	shared_routes += 1
	insight += 1
	return {"ok": true, "response": "Carried food past danger together"}


## One local, reversible prototype choice after a shared route.
func adapt_clear_signal() -> bool:
	if insight < 1 or signal_bonus > 0:
		return false
	insight -= 1
	signal_bonus = 1
	return true


func best_partner() -> String:
	var ordered := Array(IDS)
	ordered.sort_custom(func(a: String, b: String) -> bool:
		if trust(a) == trust(b):
			return a < b
		return trust(a) > trust(b)
	)
	return ordered[0]


func snapshot() -> String:
	var entries := []
	for id in IDS:
		entries.append(person(id))
	return JSON.stringify({
		"seed": seed,
		"food": player_food,
		"stamina": player_stamina,
		"route_food": route_food,
		"insight": insight,
		"signal_bonus": signal_bonus,
		"shared_routes": shared_routes,
		"contests": contests,
		"people": entries
	})
