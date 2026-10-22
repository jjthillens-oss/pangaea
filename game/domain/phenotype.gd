class_name Phenotype
extends RefCounted
## Capabilities derived from a genome. The single authoritative stat calculation (Bible section 12):
## the editor preview, the HUD and gameplay all read these numbers.
##
## Rules: each part type adds its effects; every further copy adds diminishing_factor times the
## previous copy's share (copies are ranked largest first, so part order never matters); upkeep
## and mass are paid in full for every copy; mass slows speed and acceleration; stats are capped.
## Directional parts keep their angle so interactions can check facing.

var speed: float = 0.0          ## m/s at full health and energy
var acceleration: float = 0.0   ## m/s^2
var turn_rate: float = 0.0      ## rad/s
var max_health: float = 0.0
var energy_capacity: float = 0.0
var upkeep: float = 0.0         ## energy per second at rest
var move_cost: float = 0.0      ## extra energy per meter moved
var sight: float = 0.0          ## m
var mass: float = 1.0
var radius: float = 0.5         ## m
var defense: float = 0.0        ## share of incoming damage blocked, 0..cap
var bite_damage: float = 0.0
var ram_damage: float = 0.0     ## all spikes hitting at once; a real ram uses only the spikes facing the target
## When several spikes hit at once, each further one (strongest first) adds this share of the previous.
var spike_stacking: float = 1.0
var diets: PackedStringArray = []
## Facing data for interactions: [{"type", "angle", "arc"}] with angles in radians, 0 = front.
## Mouths also carry "diet"; spikes also carry "damage" (that spike's own ram damage at its size).
var mouths: Array[Dictionary] = []
var spikes: Array[Dictionary] = []


static func derive(genome: Genome, catalog: PartCatalog) -> Phenotype:
	var p := Phenotype.new()
	var sums := {}
	for part in _ranked_parts(genome, catalog):
		var type_id: String = part["type"]
		var scale := float(part.get("scale", 1.0))
		var share := pow(catalog.diminishing_factor, int(part["rank"])) * scale
		var def: Dictionary = catalog.parts[type_id]
		for stat in def["effects"]:
			# Costs (upkeep, mass) are paid in full for every copy; only benefits diminish.
			var full_cost: bool = stat == "upkeep" or stat == "mass"
			sums[stat] = sums.get(stat, 0.0) + def["effects"][stat] * (scale if full_cost else share)
		var arc := deg_to_rad(def["arc_deg"])
		if def["category"] == "mouth":
			p.mouths.append({"type": type_id, "angle": float(part["angle"]), "arc": arc, "diet": def["diet"]})
			if not p.diets.has(def["diet"]):
				p.diets.append(def["diet"])
		elif type_id == "spike":
			var damage: float = def["effects"].get("ram_damage", 0.0) * scale
			p.spikes.append({"type": type_id, "angle": float(part["angle"]), "arc": arc, "damage": damage})

	p.mass = catalog.base("mass", 1.0) + sums.get("mass", 0.0)
	p.radius = catalog.base("radius", 0.5)
	p.speed = _cap(catalog, "speed", (catalog.base("speed") + sums.get("speed", 0.0)) / p.mass)
	p.acceleration = _cap(catalog, "acceleration", (catalog.base("acceleration") + sums.get("acceleration", 0.0)) / p.mass)
	p.turn_rate = _cap(catalog, "turn_rate", catalog.base("turn_rate") + sums.get("turn_rate", 0.0))
	p.max_health = catalog.base("max_health") + sums.get("max_health", 0.0)
	p.energy_capacity = catalog.base("energy_capacity") + sums.get("energy_capacity", 0.0)
	p.upkeep = catalog.base("upkeep") + sums.get("upkeep", 0.0)
	p.move_cost = catalog.base("move_cost") * p.mass
	p.sight = _cap(catalog, "sight", catalog.base("sight") + sums.get("sight", 0.0))
	p.defense = _cap(catalog, "defense", sums.get("defense", 0.0))
	p.bite_damage = sums.get("bite_damage", 0.0)
	p.ram_damage = sums.get("ram_damage", 0.0)
	p.spike_stacking = catalog.diminishing_factor
	return p


## Known parts, each with "rank": its position among parts of the same type, largest first.
## Ranking by size (then id) keeps the stats independent of the order parts were added in.
static func _ranked_parts(genome: Genome, catalog: PartCatalog) -> Array[Dictionary]:
	var by_type := {}
	for part in genome.parts:
		if catalog.has_part(str(part.get("type", ""))):
			by_type.get_or_add(part["type"], []).append(part)
	var ranked: Array[Dictionary] = []
	for type_id in by_type:
		var group: Array = by_type[type_id]
		group.sort_custom(func(a, b):
			var sa := float(a.get("scale", 1.0))
			var sb := float(b.get("scale", 1.0))
			return sa > sb if sa != sb else str(a.get("id", "")) < str(b.get("id", "")))
		for i in group.size():
			var entry: Dictionary = group[i].duplicate()
			entry["rank"] = i
			ranked.append(entry)
	return ranked


static func _cap(catalog: PartCatalog, stat: String, value: float) -> float:
	return minf(value, float(catalog.caps[stat])) if catalog.caps.has(stat) else value


func can_eat(diet: String) -> bool:
	return diets.has(diet)


func to_dict() -> Dictionary:
	return {
		"speed": speed, "acceleration": acceleration, "turn_rate": turn_rate,
		"max_health": max_health, "energy_capacity": energy_capacity, "upkeep": upkeep,
		"move_cost": move_cost, "sight": sight, "mass": mass, "defense": defense,
		"bite_damage": bite_damage, "ram_damage": ram_damage, "diets": Array(diets),
	}
