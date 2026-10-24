extends TestCase
## SpeciesCatalog.at_size (S2, plan B.6, s2-sim 3.2, gate S2G3): a species' record at the cell's
## size n is its entry-size self drawn at q = 1.6^(c - n), exactly, for every species of
## creatures_m1.json and every size from its entry size c up the ladder. A creature built from its
## record then acts as its scaled body: it eats what its scaled brain swims up to, and every strike it
## starts runs inside its scaled leash.

const DT := 1.0 / 60.0
## The top of the growth ladder (world_cell.json's ten size labels, the entry sizes' range).
const TOP := SpeciesCatalog.MAX_ENTRY_SIZE
## The record's fields (s2-sim 3.2), no more and no fewer.
const FIELDS := ["carcass_rings", "cfg", "flee_share", "fov", "ladder_role", "near_m", "phenotype", "q", "reach_scale",
	"rel", "sight"]
## A guarded zone's own radius at the entry size; at size n it is this x q, like everything else.
const ZONE_R := 6.0

var parts: PartCatalog
var species: SpeciesCatalog


func before_each() -> void:
	parts = PartCatalog.load_from()
	species = SpeciesCatalog.load_from()


## Every field of the record against what s2-sim 3.2 says it is, worked out here from the species'
## own block, body and brain config.
func _check_record(cat: SpeciesCatalog, id: String, n: int, where: String) -> void:
	var rec := cat.at_size(id, n, parts)
	var c := cat.entry_size(id)
	var block: Dictionary = cat.species[id]
	var keys: Array = rec.keys()
	keys.sort()
	check_eq(keys, FIELDS, where + ": the record's fields")
	# q = 0.625^(n - c) = 5^k / 8^k, both exact integers, so q is exact on the whole ladder.
	var five := 1
	for i in n - c:
		five *= 5
	var q := float(five) / float(1 << (3 * (n - c)))
	check_eq(rec.q, q, where + ": q")
	var own := cat.phenotype(id, parts)
	var drawn := own.scaled(q)
	var p: Phenotype = rec.phenotype
	for prop in own.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			check_eq(p.get(prop.name), drawn.get(prop.name), "%s: body %s" % [where, prop.name])
	check_eq(rec.cfg, CreatureBrain.scale_cfg(cat.brain_config(id), q), where + ": the brain config at q")
	check_eq(rec.sight, p.sight, where + ": sight")
	check_eq(rec.fov, deg_to_rad(float(block.senses.fov_deg)), where + ": field of view (an angle, kept)")
	check_eq(rec.near_m, float(block.senses.near_m) * q, where + ": near sense")
	check_eq(rec.carcass_rings, [float(CreatureField.CARCASS_RINGS_M[0]) * q, float(CreatureField.CARCASS_RINGS_M[1]) * q],
		where + ": carcass rings")
	check_eq(rec.reach_scale, q, where + ": the resolver's reach scale")
	check_eq(rec.flee_share, float(block.speeds.flee), where + ": flee share (a share, kept)")
	check_eq(rec.rel, p.radius / 0.5, where + ": rel")
	check_eq(rec.ladder_role, Relationships.ladder_role(c, n, p.radius, cat.share_tolerance()), where + ": ladder role")
	check(is_same(cat.at_size(id, n, parts), rec), where + ": memoised")


func test_every_record_from_the_entry_size_up_the_ladder_is_the_entry_self_drawn_at_q_exactly() -> void:
	var ids := species.species_ids()
	check_eq(ids.size(), 4, "the M1 pair and the two size-2 species")
	var records := 0
	# Asked up the ladder and, in a second catalog, down it: a record never depends on which sizes
	# came first (each is drawn from the entry self, not from the size below).
	for down in [false, true]:
		var cat := SpeciesCatalog.load_from() if down else species
		for id in ids:
			var c := cat.entry_size(id)
			var sizes := range(c, TOP + 1)
			if down:
				sizes.reverse()
			for n in sizes:
				_check_record(cat, id, n, "%s at size %d%s" % [id, n, " (asked downwards)" if down else ""])
				records += 1
	check_eq(records, 2 * (2 * TOP + 2 * (TOP - 1)), "every (species, n >= c) both ways")


func test_the_ladder_q_runs_from_one_at_the_entry_size() -> void:
	check_eq([species.at_size("rammer", 1, parts).q, species.at_size("rammer", 2, parts).q,
		species.at_size("rammer", 3, parts).q], [1.0, 0.625, 0.390625], "1, 1 / 1.6, 1 / 1.6^2")
	check_eq([species.at_size("lurker", 2, parts).q, species.at_size("lurker", 3, parts).q], [1.0, 0.625],
		"a size-2 species starts at 1 one size later")
	check_eq(species.at_size("ambush_hunter", TOP, parts).q, 1953125.0 / 134217728.0, "the ladder's top: 5^9 / 8^9")


## A hungry rammer at size 2 (q = 0.625) in its zone, a plant ahead: its scaled brain swims up to
## the plant, and the resolver, at the body's reach scale, lets it eat. The same run at its own size
## first. The brain names the plant only once the body reaches it: one that settled to eat at the
## unscaled feed reach would ask from out of the resolver's reach (and eat only if it coasted in).
func test_a_rammer_at_q_0_625_swims_to_a_plant_and_eats_it() -> void:
	for n in [1, 2]:
		var rec := species.at_size("rammer", n, parts)
		var q: float = rec.q
		var body: Phenotype = rec.phenotype
		var mem := CreatureBrain.create("territorial", rec.cfg, Vector2.ZERO, 0.0, {"center": Vector2.ZERO, "radius": ZONE_R * q}, 11, 0)
		mem.ignore_all_until = 0
		var m := Locomotion.MotionState.new(Vector2.ZERO, 0.0)
		var actor := InteractionResolver.Actor.new("c_1", m.position, m.heading, body)
		actor.reach_scale = float(rec.reach_scale)
		var plant := {"id": "pk_1", "kind": "plant", "position": Vector2(3.0, 2.0) * q, "radius": 0.2 * q, "energy": 1.0}
		var ate := -1
		var refused := {}
		for t in 1500:
			var me := {"id": "c_1", "species": "rammer", "position": m.position, "heading": m.heading, "velocity": m.velocity,
				"speed_now": m.velocity.length(), "radius": body.radius, "speed": body.speed, "acceleration": body.acceleration,
				"health_share": 1.0, "energy_share": 0.5}
			var food := []
			if mem.state == "forage":
				var seen: Dictionary = plant.duplicate()
				seen["distance"] = m.position.distance_to(plant.position)
				food.append(seen)
			if CreatureBrain.think_due(mem, 1, t):
				CreatureBrain.think(mem, me, [], food, t, null)
			var d := CreatureBrain.drive(mem, me, t, null)
			CreatureBrain.move_body(mem, m, d, body, 1.0, DT)
			m.prev_position = m.position
			m.position += m.velocity * DT
			var disc := CreatureBrain.leash_disc(mem)
			PoolArena.clamp_to_disc(m, disc.center, disc.radius)
			mem.events.clear()
			if str(d.feed).is_empty():
				continue
			actor.position = m.position
			actor.heading = m.heading
			var r := InteractionResolver.feed(actor, plant, t * DT)
			if r.allowed:
				ate = t
				break
			refused[r.reason] = int(refused.get(r.reason, 0)) + 1
		check(ate >= 0, "size %d (q %.3f): it ate the plant it swam to (refused: %s)" % [n, q, refused])
		check(not refused.has("out of reach"), "size %d: and never asked for it from out of reach (%s)" % [n, refused])
		var gap := m.position.distance_to(plant.position) - body.radius - float(plant.radius)
		check(gap <= InteractionResolver.FEED_REACH * q, "size %d: from within its scaled reach (%.3f m)" % [n, gap])


## Rule 6 and the brain's tell check at every size where the species lives: the strike lane fits its
## room at that size, and every strike its scaled brain starts ends inside the leash disc drawn from
## the data at q (an ambush brain's home and leash; a territorial one's zone, margin and leash). The
## creature is held still facing a prey-sized body in the middle of its strike window, from places
## across its leash disc and in eight directions; an ambush brain near its leash circle facing out
## holds its strike there.
func test_every_strike_a_scaled_creature_starts_ends_inside_its_leash_at_every_live_size() -> void:
	var checked := 0
	for id in species.species_ids():
		var block: Dictionary = species.species[id]
		var territorial := str(block.behavior) == "territorial"
		for n in range(species.entry_size(id), TOP + 1):
			if not species.live_at(id, n, parts):
				continue
			var rec := species.at_size(id, n, parts)
			var q: float = rec.q
			var body: Phenotype = rec.phenotype
			var a: Dictionary = rec.cfg.attack
			var where := "%s at size %d (q %.4f)" % [id, n, q]
			check_eq(species.strike_room_problem(id, ZONE_R * q if territorial else 0.0, where, parts, n), "",
				where + ": rule 6, the lane fits its room")
			var zone := {"center": Vector2.ZERO, "radius": ZONE_R * q} if territorial else {}
			var leash := float(block.leash_m) * q
			if territorial:
				leash += (ZONE_R + float(block.territory_margin_m)) * q
			var prey_r := 0.4 * q
			var window := (float(a.start_min_m) + float(a.start_max_m)) / 2.0
			var started := 0
			var held := 0
			for f in [0.0, 0.5, 0.8, 0.9, 0.97]:
				for j in 8:
					var heading := TAU * j / 8.0
					var at := Vector2(f * leash, 0.0)
					var target := at + Vector2.from_angle(heading) * window
					var tell := _first_tell(rec, zone, at, heading, target, prey_r)
					var end := at + Vector2.from_angle(heading) * float(a.travel)
					if tell.is_empty():
						held += 1 if end.length() > leash else 0
						continue
					started += 1
					var lane: Dictionary = tell.lane
					var lane_end: Vector2 = Vector2(lane.origin) + Vector2.from_angle(float(lane.heading)) * float(lane.travel)
					check(lane_end.length() <= leash + 1e-6, "%s from %.2f m facing %d deg: the strike ends %.3f m out, inside %.3f m" % [
						where, at.x, j * 45, lane_end.length(), leash])
					check_eq(lane.travel, a.travel, where + ": the lane runs its scaled travel")
					check_near(float(lane.half_width), body.radius + float(a.reach) + prey_r, 1e-9, where + ": as wide as its scaled body")
			check(started > 0, "%s: strikes started (%d)" % [where, started])
			if not territorial:
				check(held > 0, "%s: and some were held at the leash (%d)" % [where, held])
			checked += 1
	check_eq(checked, 16, "four live sizes of each of the four species")


## The first creature_tell of a hungry, settled creature built from `rec` (home at the origin), held
## still at `at` facing `heading`, with one still body of radius `prey_r` at `target` in view; {} when
## none comes within 2 s.
func _first_tell(rec: Dictionary, zone: Dictionary, at: Vector2, heading: float, target: Vector2, prey_r: float) -> Dictionary:
	var cfg: Dictionary = rec.cfg
	var body: Phenotype = rec.phenotype
	var mem := CreatureBrain.create(str(cfg.behavior), cfg, Vector2.ZERO, 0.0, zone, 7, 0)
	mem.ignore_all_until = 0
	var me := {"id": "c_1", "species": cfg.species_id, "position": at, "heading": heading, "velocity": Vector2.ZERO,
		"speed_now": 0.0, "radius": body.radius, "speed": body.speed, "acceleration": body.acceleration,
		"health_share": 1.0, "energy_share": 0.5}
	var percept := {"id": "a", "species": "lineage", "position": target, "velocity": Vector2.ZERO, "radius": prey_r,
		"by": "sight", "engageable": true, "bite": false, "spikes": 0, "distance": at.distance_to(target),
		"bearing": CreatureSenses.bearing(me, target)}
	for t in 120:
		if CreatureBrain.think_due(mem, 1, t):
			CreatureBrain.think(mem, me, [percept], [], t, null)
		CreatureBrain.drive(mem, me, t, null)
		for e in mem.events:
			if e.type == "creature_tell":
				return e
		mem.events.clear()
	return {}


func test_the_fastest_chase_at_each_size_is_the_quickest_live_pursuer() -> void:
	# The editor's rule 3 warning (S4.6) compares the new body with this.
	for n in range(1, TOP + 1):
		var want := 0.0
		var who := ""
		for id in species.species_ids():
			if species.live_at(id, n, parts):
				var chase := float(species.species[id].speeds.pursue) * (species.at_size(id, n, parts).phenotype as Phenotype).speed
				if chase > want:
					want = chase
					who = id
		var got := species.fastest_chase(n, parts)
		check_eq(got, {"speed": want, "species": who}, "size %d" % n)
	var first := species.fastest_chase(1, parts)
	check(float(first.speed) > 0.0 and first.species != "", "something hunts a new cell (%s)" % [first])
	var bound := float(species.fairness.max_pursue_share_of_slowest_fed) * float(SpeciesCatalog._starting_bodies(parts).slowest_fed)
	check(float(first.speed) <= bound + 1e-6, "and rule 3 holds for the starting bodies (%.3f <= %.3f)" % [first.speed, bound])
