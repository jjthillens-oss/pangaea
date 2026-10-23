class_name SpeciesCatalog
extends RefCounted
## The threat species (game/data/creatures_m1.json, M1 step 3): each species' body, behavior,
## senses and attack, its niche and the sites it lives at, the shared AI rates, combat knockback and
## the fairness numbers. Plain data plus checks of the data itself. The species live in their own
## file, so PoolLayout and its schema do not change.
##
## A species' genome is built with Genome.new() and fixed ids ("species:<id>", lineage "species",
## parts part_1..part_N), never StableId, so every load gives the same genome. Its parts are checked
## against the part catalog here (rule 1), never through Genome.validate, which wants lineage ids.
## Its body is Phenotype.derive at the species' body_size.
##
## Durations are seconds in the file and integer 60 Hz ticks everywhere else, converted once here:
## each species' brain config (CreatureBrain.config) and the fairness and spawning timers.
##
## validate() names every broken rule as "Rule N (name): ...", so the data cannot drift away from
## the fairness contract unnoticed (docs/milestones/m1-step3-plan.md, section 5):
##   1 genome, 2 weapon, 3 speed, 4 readability, 5 forgiving, 6 strike window, 7 sites,
##   8 checkpoint safety, 9 leash band, 10 pinch, 11 new-game fill, 12 fairness arrays, 13 unknown key,
##   15 outgrown (S2; 14 is kept for S3's veil).
##
## S2 (the growth ladder, plan B.6 and B.7): a species may name its entry_size, the cell's size at
## which it is drawn as a threat (1 when left out), and a habit (two posts, B.7); the top-level
## "relationships" block holds the relationship rules' shares and switches (D-18), which _prepare
## passes into every brain config. at_size(id, n) is the species' record at the cell's size n: its
## phenotype and cfg scaled by q = 1.6^(c - n) (Phenotype.scaled, CreatureBrain.scale_cfg), memoised.

const DEFAULT_PATH := "res://game/data/creatures_m1.json"
const SCHEMA_VERSION := 1
## The player's species in the senses' body format. No creature species may use it.
const PLAYER_SPECIES := "lineage"
const GENOME_PREFIX := "species:"
const GENOME_LINEAGE := "species"
## Species are built at sizes from the player's up to twice it (rule 1); Phenotype allows more.
const MIN_BODY_SIZE := 1.0
const MAX_BODY_SIZE := 2.0
## rad: a part angle may lie this far past PI (the data writes 3.14159), as Genome.validate allows.
const ANGLE_SLACK := 1e-4
## Rule 5 rams at this many times the rammer's top speed, past InteractionResolver.ram's impact cap,
## so the resolver itself gives the hardest ram.
const WORST_CLOSING_SHARE := 2.0
## rad: rule 5 aims at each spike arc's edges this far inside, where the most spikes overlap.
const ARC_NUDGE := 1e-4
const RULE_NAMES := {1: "genome", 2: "weapon", 3: "speed", 4: "readability", 5: "forgiving", 6: "strike window",
	7: "sites", 8: "checkpoint safety", 9: "leash band", 10: "pinch", 11: "new-game fill", 12: "fairness arrays",
	13: "unknown key", 15: "outgrown"}
const BEHAVIORS: PackedStringArray = ["ambush", "territorial"]
## The sizes of the growth ladder (plan B.1): entry_size lies in 1..MAX_ENTRY_SIZE.
const MAX_ENTRY_SIZE := 10
## The largest relationships.tolerance accepted: it absorbs float rounding, not real size differences.
const MAX_SHARE_TOLERANCE := 1e-3
## A habit's post switch (B.7, D-23): the ambush brain moves when the cell is out of its sight, the
## territorial one when the cell is nearer the other post's zone.
const POST_SWITCHES := {"out_of_sight": "ambush", "nearer_cell": "territorial"}

# Every key each block may hold, and its kind. A kind ending in "?" may be left out.
const TOP_KEYS := {"schema_version": "whole", "status": "text", "note": "text?", "ai": "object", "combat": "object",
	"fairness": "object", "spawning": "object", "species": "object", "sites": "list", "relationships": "object?"}
const AI_KEYS := {"think_hz": "number", "engaged_think_hz": "number", "dead_reckon_cap_s": "number",
	"unreachable_window_s": "number", "unreachable_min_m": "number", "return_fail_limit": "whole",
	"settle_s": "number", "tell_start_max_speed": "number"}
const COMBAT_KEYS := {"player_bite_knockback": "number", "player_ram_knockback": "number", "max_speed_after_hit": "number"}
const FAIRNESS_KEYS := {"min_tell_s": "number", "min_notice_s": "number", "min_recover_s": "number",
	"max_pursue_share_of_slowest_fed": "number", "max_single_hit_share": "number", "max_engaged_on_player": "whole",
	"spawn_safe_m": "number", "spawn_view_aspect": "number", "spawn_view_margin_m": "number",
	"respawn_clear_m": "number", "leash_band_margin_m": "number", "pinch_margin_m": "number",
	"grace_s": "numbers", "respawn_energy_share": "numbers", "streak_window_s": "number", "killer_ignore_s": "number",
	"start_grace_s": "number"}
const SPAWNING_KEYS := {"retry_s": "number", "min_gap_m": "number", "fade_in_s": "number"}
const SPECIES_KEYS := {"name": "text", "death_reason": "text", "death_tip": "text", "behavior": "text",
	"body_asset": "text", "body_size": "number", "parts": "list", "niche": "object", "metabolism_share": "number",
	"start_energy_share": "number", "hungry_below": "number", "full_above": "number", "senses": "object",
	"speeds": "object", "prey_max_radius_share": "number?", "intruder_min_radius": "number?", "notice_s": "number",
	"give_up_s": "number", "leash_m": "number", "forage_radius_m": "number?", "forage_timeout_s": "number?",
	"forage_retry_s": "number?", "refractory_s": "number", "nav_timeout_s": "number", "territory_margin_m": "number?",
	"territory_exit_m": "number?", "rest_s": "pair?", "attack": "object", "flee": "object", "carcass": "object",
	"entry_size": "whole?", "habit": "object?"}
## The optional species keys each behavior needs.
const BEHAVIOR_KEYS := {
	"ambush": ["prey_max_radius_share", "forage_radius_m", "forage_timeout_s", "forage_retry_s"],
	"territorial": ["intruder_min_radius", "territory_margin_m", "territory_exit_m", "rest_s"],
}
const ATTACK_KEYS := {"kind": "text", "tell": "text", "start_min_m": "number", "start_max_m": "number",
	"standoff_m": "number", "aim_deg": "number", "lead_s": "number", "lead_cap_m": "number", "tell_s": "number",
	"burst_speed": "number", "burst_s": "number", "glide_s": "number", "glide_drag": "number", "recover_s": "number",
	"blocked_recover_s": "number", "knockback": "number"}
const NICHE_KEYS := {"role": "text", "cap": "whole", "respawn_s": "number", "respawn_jitter_s": "number"}
const SENSES_KEYS := {"fov_deg": "number", "near_m": "number", "memory_s": "number"}
const SPEEDS_KEYS := {"wander": "number", "forage": "number", "pursue": "number", "flee": "number"}
const FLEE_KEYS := {"below_health_share": "number", "for_s": "number"}
const CARCASS_KEYS := {"chunks": "whole", "energy": "number", "on_starve": "flag"}
const PART_KEYS := {"type": "text", "angle": "number", "scale": "number?"}
const HABIT_KEYS := {"post_switch": "text", "post_rest_s": "number?", "post_hysteresis_m": "number?", "trail_s": "number?"}
const RELATIONSHIP_KEYS := {"rules": "object", "prey_share": "number", "intruder_max_radius_share": "number",
	"fear_radius_share": "number", "tolerance": "number"}
## One switch per relationship rule (Relationships), every one required.
const RULE_KEYS := {"prey_share": "flag", "intruder_share": "flag", "fear": "flag", "no_engage_above": "flag",
	"outgrown_hazards": "flag"}
const SITE_KEYS := {"id": "text", "species": "text", "home": "pair", "heading": "number", "territory_zone": "text?"}
const SUB_BLOCKS := {"attack": ATTACK_KEYS, "niche": NICHE_KEYS, "senses": SENSES_KEYS, "speeds": SPEEDS_KEYS,
	"flee": FLEE_KEYS, "carcass": CARCASS_KEYS}
const KIND_TEXT := {"number": "a number", "whole": "a whole number", "text": "text", "flag": "true or false",
	"list": "a list", "object": "an object", "pair": "two numbers", "numbers": "a list of numbers"}

## Problems found while reading (not saved). validate() reports them first.
var load_problems: Array = []
var schema_version := 0
var status := ""
## The "ai" block as written (CreatureBrain.config reads it).
var ai := {}
## {"player_bite_knockback", "player_ram_knockback", "max_speed_after_hit"}
var combat := {}
## The "fairness" block as written (seconds and meters); its timers are also below in ticks.
var fairness := {}
## {"retry_s", "min_gap_m", "fade_in_s"}
var spawning := {}
## species id -> its block as written.
var species := {}
## [{"id", "species", "home": Vector2, "heading", "territory_zone" ("" for none)}], in data order.
var sites: Array[Dictionary] = []
## species id -> CreatureBrain.config(): the brain's tick-based config. Empty while load_problems is not.
var configs := {}
## The "relationships" block as written (D-18); {} when the data has none, which is every rule off.
var relationships := {}
## Shelter after a respawn, by death streak (fairness.grace_s in ticks).
var grace_ticks: Array[int] = []
## Energy after a respawn, by death streak, as a share of capacity.
var respawn_energy_share: Array[float] = []
var streak_window_ticks := 0
var killer_ignore_ticks := 0
var start_grace_ticks := 0
var spawn_retry_ticks := 0
var fade_in_ticks := 0
## at_size's records, by "<id>/<n>", and the one part catalog they are built with (the first given).
var _records := {}
var _part_catalog: PartCatalog = null


## Never null: a missing or unreadable file gives a catalog whose validate() says why.
static func load_from(path: String = DEFAULT_PATH) -> SpeciesCatalog:
	var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var json := JSON.new()
	if text.is_empty() or json.parse(text) != OK:
		var broken := SpeciesCatalog.new()
		broken.load_problems.append("%s: missing or not readable JSON." % path.get_file())
		return broken
	return from_dict(json.data)


static func from_dict(data: Variant) -> SpeciesCatalog:
	var cat := SpeciesCatalog.new()
	var problems := cat.load_problems
	if not data is Dictionary:
		problems.append("Species data is not an object.")
		return cat
	_check_block(data, TOP_KEYS, "the species data", problems)
	if _kind_ok(data.get("schema_version"), "whole"):
		cat.schema_version = int(data.schema_version)
	cat.status = str(data.get("status", ""))
	cat.ai = _block(data, "ai", AI_KEYS, "ai", problems)
	cat.combat = _block(data, "combat", COMBAT_KEYS, "combat", problems)
	cat.fairness = _block(data, "fairness", FAIRNESS_KEYS, "fairness", problems)
	cat.spawning = _block(data, "spawning", SPAWNING_KEYS, "spawning", problems)
	if data.has("relationships"):
		cat.relationships = _block(data, "relationships", RELATIONSHIP_KEYS, "relationships", problems)
		if cat.relationships.get("rules") is Dictionary:
			_check_block(cat.relationships.rules, RULE_KEYS, "relationships rules", problems)

	var raw_species = data.get("species")
	if raw_species is Dictionary:
		for id in _sorted_keys(raw_species):
			var block = raw_species[id]
			var where := "species '%s'" % id
			if not block is Dictionary:
				problems.append("%s must be an object." % where)
				continue
			if id == PLAYER_SPECIES or str(id).is_empty():
				problems.append("%s: the id '%s' is the player's or empty." % [where, id])
			_check_species_block(block, where, problems)
			cat.species[str(id)] = (block as Dictionary).duplicate(true)

	var raw_sites = data.get("sites")
	if raw_sites is Array:
		for raw in raw_sites:
			if not raw is Dictionary:
				problems.append("A site entry is not an object.")
				continue
			var where := "site '%s'" % str(raw.get("id", "?"))
			var before := problems.size()
			_check_block(raw, SITE_KEYS, where, problems)
			if problems.size() > before:
				continue
			cat.sites.append({"id": str(raw.id), "species": str(raw.species), "home": Vector2(float(raw.home[0]), float(raw.home[1])),
				"heading": float(raw.heading), "territory_zone": str(raw.get("territory_zone", ""))})
	if problems.is_empty():
		cat._prepare()
	return cat


## Problems with the data itself; empty when the catalog is usable with this layout (its spawn is
## the step 3 checkpoint) and part catalog. Each broken rule is named "Rule N (name)".
func validate(layout: PoolLayout, part_catalog: PartCatalog) -> PackedStringArray:
	var errors := PackedStringArray(load_problems)
	if not errors.is_empty():
		return errors
	if schema_version != SCHEMA_VERSION:
		errors.append("Species schema %d is not the supported %d." % [schema_version, SCHEMA_VERSION])
	if species.is_empty():
		errors.append("The species data needs at least one species.")
	var starting := _starting_bodies(part_catalog)
	for id in species_ids():
		_check_species(id, layout, part_catalog, starting, errors)
	_check_sites(layout, part_catalog, errors)
	_check_shared(errors)
	return errors


## Species ids, sorted.
func species_ids() -> PackedStringArray:
	return PackedStringArray(_sorted_keys(species))


func has_species(species_id: String) -> bool:
	return species.has(species_id)


## The species' genome, the same on every load (see the class comment).
func genome(species_id: String) -> Genome:
	var g := Genome.new()
	g.genome_id = GENOME_PREFIX + species_id
	g.lineage_id = GENOME_LINEAGE
	for part in species.get(species_id, {}).get("parts", []):
		g.add_part(str(part.type), float(part.angle), float(part.get("scale", 1.0)))
	return g


## The species' body: its genome at its body_size.
func phenotype(species_id: String, part_catalog: PartCatalog) -> Phenotype:
	return Phenotype.derive(genome(species_id), part_catalog, float(species.get(species_id, {}).get("body_size", 1.0)))


## CreatureBrain.config() for the species ({} for an unknown one or a broken catalog).
func brain_config(species_id: String) -> Dictionary:
	return configs.get(species_id, {})


func behavior_of(species_id: String) -> String:
	return str(species.get(species_id, {}).get("behavior", ""))


## The niche the species fills: {"role", "cap", "respawn_s", "respawn_jitter_s"}.
func niche_of(species_id: String) -> Dictionary:
	return species.get(species_id, {}).get("niche", {})


# --- S2: the growth ladder ---

## The cell's size at which the species is drawn as a threat (data "entry_size", 1 when left out).
func entry_size(species_id: String) -> int:
	return int(species.get(species_id, {}).get("entry_size", 1))


## q at the cell's size n: Relationships.q_of(entry_size, n), exactly 1.0 at the entry size.
func q_of(species_id: String, n: int) -> float:
	return Relationships.q_of(entry_size(species_id), n)


## The species lives in a world of the cell's size n: n is at least its entry size and it is not yet
## haze there (Relationships.ladder_role). False for an unknown species. The radius comes from
## at_size, so its part catalog is the one at_size keeps.
func live_at(species_id: String, n: int, part_catalog: PartCatalog = null) -> bool:
	if not species.has(species_id) or n < entry_size(species_id):
		return false
	return str(at_size(species_id, n, part_catalog).get("ladder_role", "haze")) != "haze"


## The "relationships" block (D-18); {} when the data has none.
func relationships_cfg() -> Dictionary:
	return relationships


## The species' habit (B.7: its two posts and how it moves between them); {} when it has none.
func habit_of(species_id: String) -> Dictionary:
	return species.get(species_id, {}).get("habit", {})


## The species' record at the cell's size n, for n at least its entry size (plan B.6, s2-sim 3.2):
## {"q", "rel", "ladder_role", "phenotype" (phenotype(id).scaled(q)), "cfg" (scale_cfg of its brain
## config), "sight" (the scaled phenotype's), "fov" (radians), "near_m" (senses.near_m x q),
## "carcass_rings" (CreatureField.CARCASS_RINGS_M x q), "reach_scale" (q), "flee_share" (speeds.flee)}.
## At the entry size every value is the species' own, bit for bit. Memoised per (id, n) and built
## with one part catalog: the first one given, else the shipped one. {} with an error for an unknown
## species, a broken catalog or n below the entry size.
func at_size(species_id: String, n: int, part_catalog: PartCatalog = null) -> Dictionary:
	var key := "%s/%d" % [species_id, n]
	var known: Dictionary = _records.get(key, {})
	if not known.is_empty():
		return known
	if not configs.has(species_id) or n < entry_size(species_id):
		push_error("SpeciesCatalog.at_size: no record for '%s' at size %d (entry size %d)." % [species_id, n, entry_size(species_id)])
		return {}
	if _part_catalog == null:
		_part_catalog = part_catalog if part_catalog != null else PartCatalog.load_from()
	var q := q_of(species_id, n)
	var p := phenotype(species_id, _part_catalog).scaled(q)
	var block: Dictionary = species[species_id]
	var rings := CreatureField.CARCASS_RINGS_M
	var record := {
		"q": q, "rel": Relationships.rel(p.radius),
		"ladder_role": Relationships.ladder_role(entry_size(species_id), n, p.radius, share_tolerance()),
		"phenotype": p, "cfg": CreatureBrain.scale_cfg(configs[species_id], q),
		"sight": p.sight, "fov": deg_to_rad(float(block.senses.fov_deg)), "near_m": float(block.senses.near_m) * q,
		"carcass_rings": [float(rings[0]) * q, float(rings[1]) * q], "reach_scale": q,
		"flee_share": float(block.speeds.flee),
	}
	_records[key] = record
	return record


## The relationship rules' tolerance: the block's, else Relationships.TOLERANCE.
func share_tolerance() -> float:
	return float(relationships.get("tolerance", Relationships.TOLERANCE))


func site(site_id: String) -> Dictionary:
	for s in sites:
		if s.id == site_id:
			return s
	return {}


func sites_of(species_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in sites:
		if s.species == species_id:
			out.append(s)
	return out


## The circle a territorial site guards: its zone's own {"center", "radius"} (the brain adds the
## territory margin), or {} for an ambush site or an unknown zone.
func territory_of(s: Dictionary, layout: PoolLayout) -> Dictionary:
	return territory_from(s, layout.zone(str(s.get("territory_zone", ""))))


## territory_of with the zone given ({} for none), so a world tile's zone can stand in for the layout's.
func territory_from(s: Dictionary, zone: Dictionary) -> Dictionary:
	if behavior_of(str(s.species)) != "territorial" or zone.is_empty():
		return {}
	return {"center": zone.center, "radius": zone.radius}


## The disc a creature at this site can reach: the brain's own leash disc ({"center", "radius"}),
## which the sim clamps it to after every move.
func reach_disc(s: Dictionary, layout: PoolLayout) -> Dictionary:
	return reach_disc_for(s, territory_of(s, layout))


## reach_disc with the territory given (territory_from's answer), for a site that is not the layout's.
## CreatureBrain.create's territory and CreatureBrain.leash_disc written out, the same expressions,
## without building a brain (a world chunk asks for each of its sites).
##
## k (D-39) puts the disc in the caller's units when they are not the species' own: the brain's
## lengths are those of CreatureBrain.scale_cfg(cfg, k), each multiplied out here (the same products,
## so the same bits). A tile frame of band b holds a species of entry size c at k = 1.6^(c - 1) /
## 2.56^b: 1 for the M1 species in band 0, 1.6 for a size-2 species. The territory is already in the
## caller's units.
func reach_disc_for(s: Dictionary, territory: Dictionary, k := 1.0) -> Dictionary:
	var cfg := brain_config(str(s.species))
	if cfg.is_empty():
		return {}
	var home: Vector2 = s.home
	if str(cfg.behavior) == CreatureBrain.TERRITORIAL:
		var center: Vector2 = territory.get("center", home)
		var territory_r := float(territory.get("radius", float(cfg.default_territory_m) * k)) + float(cfg.territory_margin_m) * k
		return {"center": center, "radius": territory_r + float(cfg.leash_m) * k}
	return {"center": home, "radius": float(cfg.leash_m) * k}


## A two-post site's reach (B.7, D-38): each post's reach_disc_for and the smallest disc holding both
## (CreatureBrain.union_disc, D-82), which is the leash disc CreatureBrain.set_posts gives the brain.
## `s` is the site at its first post; `post_b` is {"home", "heading"}; each territory is its post's
## zone ({} for an ambush site). {"center", "radius", "posts": [disc_a, disc_b]}; {} for an unknown
## species.
func two_post_disc_for(s: Dictionary, territory_a: Dictionary, post_b: Dictionary, territory_b: Dictionary,
		k := 1.0) -> Dictionary:
	var a := reach_disc_for(s, territory_a, k)
	if a.is_empty():
		return {}
	var at_b := s.duplicate()
	at_b.home = post_b.home
	at_b.heading = float(post_b.get("heading", s.get("heading", 0.0)))
	var b := reach_disc_for(at_b, territory_b, k)
	var union := CreatureBrain.union_disc(a, b)
	return {"center": union.center, "radius": union.radius, "posts": [a, b]}


## Rule 6's lane check: the strike lane against what the creature may reach (its leash, plus its
## smallest territory and the territory margin for a territorial species). The rule's text, or ""
## when the lane fits. The lane's width needs the body radius, so the part catalog comes too.
## With n 0 the lane and leash are the species' own (rule 6, in the caller's units); with n >= 1
## they are its at_size(id, n) record's, against the cell's radius, and the territory is in tm.
func strike_room_problem(species_id: String, smallest_territory: float, where: String, part_catalog: PartCatalog,
		n := 0) -> String:
	var block: Dictionary = species.get(species_id, {})
	if block.is_empty() or brain_config(species_id).is_empty():
		return ""
	var cfg := brain_config(species_id)
	var radius := phenotype(species_id, part_catalog).radius if n == 0 else 0.0
	if n >= 1:
		var record := at_size(species_id, n, part_catalog)
		if record.is_empty():
			return ""
		cfg = record.cfg
		radius = (record.phenotype as Phenotype).radius
	var lane := CreatureBrain.strike_lane(cfg.attack, radius, PoolLayout.CELL_RADIUS, Vector2.ZERO, 0.0)
	var room := float(cfg.leash_m)
	var room_text := "its leash"
	if str(block.behavior) == "territorial":
		room += smallest_territory + float(cfg.territory_margin_m)
		room_text = "its smallest territory plus its leash"
	if float(lane.length) > room:
		return "%s strike lane %.2f m is longer than %s (%.2f m)." % [where, float(lane.length), room_text, room]
	return ""


## Rules 9 and 10 for one reach disc against a set of circles ({id, center, radius}) in the disc's
## frame: no surface near the leash circle, and no gap a body of radius r could wedge in between two
## circles, or between a circle and the soft wall at wall_r (INF: no wall, so no wall gap).
func check_disc_against_shells(where: String, disc: Dictionary, r: float, shells: Array[Dictionary],
		wall_r: float, errors: PackedStringArray) -> void:
	var center: Vector2 = disc.center
	var reach := float(disc.radius)
	# Rule 9: no rock surface near the leash circle, where the hard clamp would press it into the rock.
	var band := r + float(fairness.leash_band_margin_m)
	# Rule 10: a rock reaching into the disc leaves room to pass it (no gap a body could wedge in).
	var passage := 2.0 * r + float(fairness.pinch_margin_m)
	for i in shells.size():
		var rock: Dictionary = shells[i]
		var d: float = center.distance_to(rock.center)
		var to_circle: float = absf(d - reach) - rock.radius
		if to_circle < band:
			_rule(errors, 9, "%s: %s lies %.2f m from its leash circle; it needs %.2f m." % [where, rock.id, to_circle, band])
		if d - rock.radius >= reach + r:
			continue
		var to_wall: float = wall_r - rock.center.length() - rock.radius
		if to_wall > 0.0 and to_wall < passage:
			_rule(errors, 10, "%s: %s leaves %.2f m to the soft wall; it needs %.2f m." % [where, rock.id, to_wall, passage])
		for j in shells.size():
			if j == i:
				continue
			var other: Dictionary = shells[j]
			var between: float = rock.center.distance_to(other.center) - rock.radius - other.radius
			if between > 0.0 and between < passage:
				_rule(errors, 10, "%s: %s leaves %.2f m to %s; it needs %.2f m." % [where, rock.id, between, other.id, passage])


# --- the rules ---

func _check_species(id: String, layout: PoolLayout, part_catalog: PartCatalog, starting: Dictionary,
		errors: PackedStringArray) -> void:
	var block: Dictionary = species[id]
	var where := "species '%s'" % id
	var attack: Dictionary = block.attack
	var p := phenotype(id, part_catalog)

	# Rule 1: the genome's parts against the part catalog, and the body size.
	var parts: Array = block.parts
	if parts.size() > part_catalog.max_parts:
		_rule(errors, 1, "%s has %d parts; the limit is %d." % [where, parts.size(), part_catalog.max_parts])
	var counts := {}
	var categories := {}
	for part in parts:
		var type_id := str(part.type)
		if not part_catalog.has_part(type_id):
			_rule(errors, 1, "%s has a part of unknown type '%s'." % [where, type_id])
			continue
		counts[type_id] = int(counts.get(type_id, 0)) + 1
		categories[part_catalog.category_of(type_id)] = true
		var angle := float(part.angle)
		if absf(angle) > PI + ANGLE_SLACK:
			_rule(errors, 1, "%s part '%s' has an angle %.4f outside -PI..PI." % [where, type_id, angle])
		var scale := float(part.get("scale", 1.0))
		if scale < part_catalog.min_scale or scale > part_catalog.max_scale:
			_rule(errors, 1, "%s part '%s' has a scale %.2f outside %.2f..%.2f."
				% [where, type_id, scale, part_catalog.min_scale, part_catalog.max_scale])
	for type_id in _sorted_keys(counts):
		if counts[type_id] > part_catalog.max_count_of(type_id):
			_rule(errors, 1, "%s has %d '%s' parts; the limit is %d." % [where, counts[type_id], type_id, part_catalog.max_count_of(type_id)])
	for category in part_catalog.required_categories:
		if not categories.has(category):
			_rule(errors, 1, "%s needs at least one '%s' part." % [where, category])
	var size := float(block.body_size)
	if size < MIN_BODY_SIZE or size > MAX_BODY_SIZE:
		_rule(errors, 1, "%s body_size %.2f is outside %.1f..%.1f." % [where, size, MIN_BODY_SIZE, MAX_BODY_SIZE])

	# Rule 2: the behavior and the weapon it attacks with.
	var behavior := str(block.behavior)
	var kind := str(attack.kind)
	if behavior == "ambush":
		if not _has_jaw(p) or kind != "bite":
			_rule(errors, 2, "%s is an ambush species: it needs a jaw and attack kind 'bite' (kind '%s')." % [where, kind])
	elif behavior == "territorial":
		if p.spikes.is_empty() or kind != "ram":
			_rule(errors, 2, "%s is a territorial species: it needs a spike and attack kind 'ram' (kind '%s')." % [where, kind])
	else:
		_rule(errors, 2, "%s behavior '%s' is not one of %s." % [where, behavior, BEHAVIORS])
	if str(attack.tell).is_empty():
		_rule(errors, 2, "%s attack names no tell." % where)

	# Rule 3: strike speed and the escape rule (F3).
	var burst := float(attack.burst_speed)
	if not (burst > 0.0 and burst <= PoolLayout.MAX_SPEED):
		_rule(errors, 3, "%s burst_speed %.2f m/s is not above 0 and at most %.1f m/s (the tunnelling bound)."
			% [where, burst, PoolLayout.MAX_SPEED])
	if float(attack.glide_drag) < 0.0:
		_rule(errors, 3, "%s glide_drag must not be negative." % where)
	for key in SPEEDS_KEYS:
		var share := float(block.speeds[key])
		if not (share > 0.0 and share <= 1.0):
			_rule(errors, 3, "%s speeds.%s %.2f is not a share in (0, 1]." % [where, key, share])
	var pursue := float(block.speeds.pursue) * p.speed
	var bound := float(fairness.max_pursue_share_of_slowest_fed) * float(starting.slowest_fed)
	if pursue > bound:
		_rule(errors, 3, "%s pursues at %.3f m/s, above %.3f m/s (%.2f x the slowest fed starting body, %s at %.3f m/s)."
			% [where, pursue, bound, float(fairness.max_pursue_share_of_slowest_fed), starting.slowest_body, starting.slowest_fed])

	# Rule 4: readable timings, and every duration at least one tick.
	if float(attack.tell_s) < float(fairness.min_tell_s):
		_rule(errors, 4, "%s tell_s %.2f s is below the %.2f s floor." % [where, float(attack.tell_s), float(fairness.min_tell_s)])
	if float(block.notice_s) < float(fairness.min_notice_s):
		_rule(errors, 4, "%s notice_s %.2f s is below the %.2f s floor." % [where, float(block.notice_s), float(fairness.min_notice_s)])
	for key in ["recover_s", "blocked_recover_s"]:
		if float(attack[key]) < float(fairness.min_recover_s):
			_rule(errors, 4, "%s %s %.2f s is below the %.2f s floor." % [where, key, float(attack[key]), float(fairness.min_recover_s)])
	var durations := {"notice_s": block.notice_s, "give_up_s": block.give_up_s, "refractory_s": block.refractory_s,
		"nav_timeout_s": block.nav_timeout_s, "senses.memory_s": block.senses.memory_s, "flee.for_s": block.flee.for_s,
		"niche.respawn_s": block.niche.respawn_s}
	for key in ["tell_s", "burst_s", "glide_s", "recover_s", "blocked_recover_s"]:
		durations["attack." + key] = attack[key]
	for key in ["forage_timeout_s", "forage_retry_s"]:
		if block.has(key):
			durations[key] = block[key]
	if block.has("rest_s"):
		durations["rest_s[0]"] = block.rest_s[0]
		durations["rest_s[1]"] = block.rest_s[1]
		if float(block.rest_s[0]) > float(block.rest_s[1]):
			_rule(errors, 4, "%s rest_s must be [shortest, longest]." % where)
	_check_durations(where, durations, errors)
	var jitter := float(block.niche.respawn_jitter_s)
	if not (jitter >= 0.0 and jitter < float(block.niche.respawn_s)):
		_rule(errors, 4, "%s niche.respawn_jitter_s %.1f s must be at least 0 and below respawn_s." % [where, jitter])

	# Rule 5: the two-hit rule. No single hit takes max_single_hit_share of the smallest starting body.
	var worst := _worst_hit(p)
	var limit := float(fairness.max_single_hit_share) * float(starting.smallest_health)
	if not (worst < limit):
		_rule(errors, 5, "%s can deal %.2f in one hit, not below %.2f (%.2f x %.1f health)."
			% [where, worst, limit, float(fairness.max_single_hit_share), float(starting.smallest_health)])

	# Rule 6: the strike window, and a strike lane that fits inside what the creature may reach.
	var lo := float(attack.start_min_m)
	var hi := float(attack.start_max_m)
	var standoff := float(attack.standoff_m)
	if not (lo > 0.0 and lo <= standoff and standoff <= hi):
		_rule(errors, 6, "%s needs 0 < start_min_m <= standoff_m <= start_max_m (%.2f, %.2f, %.2f)." % [where, lo, standoff, hi])
	var aim := float(attack.aim_deg)
	if not (aim > 0.0 and aim < 180.0) or float(attack.lead_s) < 0.0 or float(attack.lead_cap_m) < 0.0:
		_rule(errors, 6, "%s needs 0 < aim_deg < 180 and lead_s, lead_cap_m >= 0." % where)
	var room_problem := strike_room_problem(id, _smallest_territory(id, layout), where, part_catalog)
	if not room_problem.is_empty():
		_rule(errors, 6, room_problem)

	# Plain ranges; no fairness rule hangs on them, but the brain and the sim assume them.
	if float(block.leash_m) <= 0.0:
		errors.append("%s: leash_m must be above 0." % where)
	var hungry := float(block.hungry_below)
	var full := float(block.full_above)
	if not (hungry >= 0.0 and hungry < full and full <= 1.0):
		errors.append("%s: needs 0 <= hungry_below < full_above <= 1." % where)
	for key in ["metabolism_share", "start_energy_share"]:
		if not (float(block[key]) > 0.0 and float(block[key]) <= 1.0):
			errors.append("%s: %s must be a share in (0, 1]." % [where, key])
	var fov := float(block.senses.fov_deg)
	if not (fov > 0.0 and fov <= 360.0) or float(block.senses.near_m) < 0.0:
		errors.append("%s: senses need 0 < fov_deg <= 360 and near_m >= 0." % where)
	if not (float(block.flee.below_health_share) >= 0.0 and float(block.flee.below_health_share) < 1.0):
		errors.append("%s: flee.below_health_share must be in [0, 1)." % where)
	if int(block.niche.cap) < 0 or str(block.niche.role).is_empty():
		errors.append("%s: the niche needs a role and a cap of 0 or more." % where)
	if int(block.carcass.chunks) < 0 or not (float(block.carcass.energy) > 0.0):
		errors.append("%s: the carcass needs 0 or more chunks of positive energy." % where)
	for key in ["name", "death_reason", "death_tip", "body_asset"]:
		if str(block[key]).is_empty():
			errors.append("%s: '%s' must not be empty." % [where, key])
	_check_ladder(id, p, errors)


## S2's species keys: the entry size, the habit, and rule 15. `p` is the species' own body (q = 1).
func _check_ladder(id: String, p: Phenotype, errors: PackedStringArray) -> void:
	var block: Dictionary = species[id]
	var where := "species '%s'" % id
	var c := entry_size(id)
	if c < 1 or c > MAX_ENTRY_SIZE:
		errors.append("%s: entry_size %d is outside 1..%d." % [where, c, MAX_ENTRY_SIZE])
	if block.has("habit"):
		var habit: Dictionary = block.habit
		var switch := str(habit.post_switch)
		if not POST_SWITCHES.has(switch):
			errors.append("%s: habit.post_switch '%s' is not one of %s." % [where, switch, POST_SWITCHES.keys()])
		elif POST_SWITCHES[switch] != str(block.behavior):
			errors.append("%s: habit.post_switch '%s' needs behavior '%s'." % [where, switch, POST_SWITCHES[switch]])
		elif switch == "out_of_sight" and not float(habit.get("post_rest_s", 0.0)) > 0.0:
			errors.append("%s: habit 'out_of_sight' needs post_rest_s above 0." % where)
		elif switch == "nearer_cell" and not float(habit.get("post_hysteresis_m", 0.0)) > 0.0:
			errors.append("%s: habit 'nearer_cell' needs post_hysteresis_m above 0." % where)
		if habit.has("post_rest_s"):
			_check_durations(where, {"habit.post_rest_s": habit.post_rest_s}, errors)
		if habit.has("trail_s") and not float(habit.trail_s) > 0.0:
			errors.append("%s: habit.trail_s must be above 0." % where)
	if c <= 1:
		return
	# Rule 15: one size past its entry (q = 1 / 1.6) it can no longer attack the cell, by the shares
	# of the relationships block: an ambush brain's prey share, a territorial one's intruder share.
	if relationships.is_empty():
		_rule(errors, 15, "%s has entry_size %d, which needs the relationships block." % [where, c])
		return
	var share_key := "prey_share" if str(block.behavior) == "ambush" else "intruder_max_radius_share"
	var reach := p.radius * Relationships.SHRINK_FACTOR * float(relationships[share_key])
	var below := Relationships.PLAYER_RADIUS - share_tolerance()
	if not reach < below:
		_rule(errors, 15, "%s one size past its entry reaches radius %.6f x %s %.2f = %.6f, not below %.6f: it could still attack the cell."
			% [where, p.radius * Relationships.SHRINK_FACTOR, share_key, float(relationships[share_key]), reach, below])


func _check_sites(layout: PoolLayout, part_catalog: PartCatalog, errors: PackedStringArray) -> void:
	var arena := layout.build_arena()
	var gap := float(spawning.min_gap_m)
	var checkpoint := layout.spawn
	var ids := {}
	var roles := {}
	for id in species_ids():
		var role := str(niche_of(id).role)
		if roles.has(role):
			_rule(errors, 7, "species '%s' and '%s' share the niche role '%s'." % [roles[role], id, role])
		roles[role] = id
		# A catalog with no sites at all is a test fixture: its tests place every creature.
		if not sites.is_empty() and int(niche_of(id).cap) > sites_of(id).size():
			_rule(errors, 7, "species '%s' has a niche cap %d above its %d sites." % [id, int(niche_of(id).cap), sites_of(id).size()])
	for i in sites.size():
		var s: Dictionary = sites[i]
		var where := "site '%s'" % s.id
		if s.id.is_empty() or ids.has(s.id):
			_rule(errors, 7, "%s: the id is empty or repeated." % where)
		ids[s.id] = true
		if not species.has(s.species):
			_rule(errors, 7, "%s names unknown species '%s'." % [where, s.species])
			continue
		var r := phenotype(s.species, part_catalog).radius
		var home: Vector2 = s.home
		var inside := layout.soft_start - r - 1.0
		if home.length() > inside or not arena.is_clear(home, r):
			_rule(errors, 7, "%s home %s is not a clear place within %.2f m of the pool center." % [where, home, inside])
		for j in i:
			if home.distance_to(sites[j].home) < gap:
				_rule(errors, 7, "%s is %.2f m from site '%s'; sites keep %.1f m apart." % [where, home.distance_to(sites[j].home), sites[j].id, gap])
		var territorial := behavior_of(s.species) == "territorial"
		if (territorial or not str(s.territory_zone).is_empty()) and layout.zone(s.territory_zone).is_empty():
			_rule(errors, 7, "%s territory_zone '%s' is not a zone of the layout." % [where, s.territory_zone])
			continue

		# Rule 8: what it can reach stays clear of the checkpoint, and it is placed far from it.
		var disc := reach_disc(s, layout)
		var center: Vector2 = disc.center
		var reach := float(disc.radius)
		var clear := checkpoint.distance_to(center) - reach - r
		if clear < float(fairness.respawn_clear_m):
			_rule(errors, 8, "%s can reach %.2f m from the checkpoint; it must stay %.1f m away." % [where, clear, float(fairness.respawn_clear_m)])
		if checkpoint.distance_to(home) < float(fairness.spawn_safe_m):
			_rule(errors, 8, "%s home is %.2f m from the checkpoint, under %.1f m." % [where, checkpoint.distance_to(home), float(fairness.spawn_safe_m)])

		# Rules 9 and 10: the rocks against the leash circle, each other and the soft wall.
		check_disc_against_shells(where, disc, r, layout.rocks, layout.soft_start, errors)

		# Rule 11: a new game fills every niche, so every home lies out of view of the checkpoint.
		var margin := float(layout.camera.look_ahead_max) + float(fairness.spawn_view_margin_m) + r
		if ViewFootprint.contains(checkpoint, home, layout.camera, float(layout.camera.zoom_max), float(fairness.spawn_view_aspect), margin):
			_rule(errors, 11, "%s home is in view of the checkpoint at the widest zoom (margin %.2f m)." % [where, margin])


## The ai, fairness and spawning blocks.
func _check_shared(errors: PackedStringArray) -> void:
	for key in ["think_hz", "engaged_think_hz"]:
		var hz := float(ai[key])
		if not (hz > 0.0 and hz <= CreatureBrain.TICKS_PER_SECOND):
			_rule(errors, 4, "ai.%s %.1f is not in (0, %d]." % [key, hz, CreatureBrain.TICKS_PER_SECOND])
	var durations := {"ai.dead_reckon_cap_s": ai.dead_reckon_cap_s, "ai.unreachable_window_s": ai.unreachable_window_s,
		"ai.settle_s": ai.settle_s, "fairness.streak_window_s": fairness.streak_window_s,
		"fairness.killer_ignore_s": fairness.killer_ignore_s, "fairness.start_grace_s": fairness.start_grace_s,
		"spawning.retry_s": spawning.retry_s, "spawning.fade_in_s": spawning.fade_in_s}
	var grace: Array = fairness.grace_s
	for i in grace.size():
		durations["fairness.grace_s[%d]" % i] = grace[i]
	_check_durations("the shared data", durations, errors)

	# Rule 12: one shelter and one energy share per death streak, never lower for a longer streak.
	var energy: Array = fairness.respawn_energy_share
	if grace.is_empty() or grace.size() != energy.size():
		_rule(errors, 12, "grace_s (%d) and respawn_energy_share (%d) need the same length, at least 1." % [grace.size(), energy.size()])
	for key in ["grace_s", "respawn_energy_share"]:
		var table: Array = fairness[key]
		for i in range(1, table.size()):
			if float(table[i]) < float(table[i - 1]):
				_rule(errors, 12, "%s must not decrease: %s." % [key, table])
				break
	for share in energy:
		if not (float(share) > 0.0 and float(share) <= 1.0):
			_rule(errors, 12, "respawn_energy_share %s is not a share in (0, 1]." % share)
			break

	if int(fairness.max_engaged_on_player) < 1:
		errors.append("fairness: max_engaged_on_player must be 1 or more.")
	if float(ai.unreachable_min_m) <= 0.0 or int(ai.return_fail_limit) < 1 or float(ai.tell_start_max_speed) < 0.0:
		errors.append("ai: unreachable_min_m must be above 0, return_fail_limit 1 or more, tell_start_max_speed 0 or more.")
	var after_hit := float(combat.max_speed_after_hit)
	if not (after_hit > 0.0 and after_hit <= PoolLayout.MAX_SPEED):
		errors.append("combat: max_speed_after_hit %.1f is not in (0, %.1f] (the tunnelling bound)." % [after_hit, PoolLayout.MAX_SPEED])
	if float(combat.player_bite_knockback) < 0.0 or float(combat.player_ram_knockback) < 0.0:
		errors.append("combat: knockbacks must not be negative.")
	for key in ["spawn_safe_m", "respawn_clear_m", "spawn_view_aspect"]:
		if not (float(fairness[key]) > 0.0):
			errors.append("fairness: %s must be above 0." % key)
	for key in ["spawn_view_margin_m", "leash_band_margin_m", "pinch_margin_m"]:
		if float(fairness[key]) < 0.0:
			errors.append("fairness: %s must not be negative." % key)
	if float(spawning.min_gap_m) < 0.0:
		errors.append("spawning: min_gap_m must not be negative.")
	if not relationships.is_empty():
		for key in ["prey_share", "intruder_max_radius_share", "fear_radius_share"]:
			if not float(relationships[key]) > 0.0:
				errors.append("relationships: %s must be above 0." % key)
		var tol := float(relationships.tolerance)
		if not (tol >= 0.0 and tol <= MAX_SHARE_TOLERANCE):
			errors.append("relationships: tolerance %s is not in [0, %s]." % [tol, MAX_SHARE_TOLERANCE])


## Rule 4's tick floor: each duration (seconds, by name) lasts at least one tick.
func _check_durations(where: String, durations: Dictionary, errors: PackedStringArray) -> void:
	for key in durations:
		if CreatureBrain.ticks(durations[key]) < 1:
			_rule(errors, 4, "%s %s %.4f s is shorter than one tick." % [where, key, float(durations[key])])


## The hardest single hit this body deals a defense-0 target of the player's size, through the
## resolver: a bite with each jaw, and a ram at the impact cap aimed where the most spikes overlap
## (each spike arc's edges, just inside).
func _worst_hit(p: Phenotype) -> float:
	var worst := 0.0
	var prey := Phenotype.new()
	var reach := p.radius + prey.radius
	for mouth in p.mouths:
		if mouth.type == "mouth_jaw":
			var bite := InteractionResolver.bite(_actor("attacker", Vector2.ZERO, p),
				_actor("prey", Vector2.from_angle(mouth.angle) * reach, prey), 0.0)
			if bite.allowed:
				worst = maxf(worst, float(bite.effect.damage))
	for spike in p.spikes:
		for edge in [-1.0, 1.0]:
			var aim: float = spike.angle + edge * (spike.arc * 0.5 - ARC_NUDGE)
			var ram := InteractionResolver.ram(_actor("attacker", Vector2.ZERO, p),
				_actor("prey", Vector2.from_angle(aim) * reach, prey), p.speed * WORST_CLOSING_SHARE, 0.0)
			if ram.allowed:
				worst = maxf(worst, float(ram.effect.damage))
	return worst


## The slowest fed starting body and the smallest starting health, from the part catalog:
## {"slowest_fed", "slowest_body", "smallest_health"}.
static func _starting_bodies(part_catalog: PartCatalog) -> Dictionary:
	var out := {"slowest_fed": INF, "slowest_body": "", "smallest_health": INF}
	for body_name in _sorted_keys(part_catalog.starting_bodies):
		var g := Genome.new()
		for part in part_catalog.starting_bodies[body_name]:
			g.add_part(part.type, part.angle, part.scale)
		var p := Phenotype.derive(g, part_catalog)
		if p.speed < float(out.slowest_fed):
			out.slowest_fed = p.speed
			out.slowest_body = body_name
		out.smallest_health = minf(float(out.smallest_health), p.max_health)
	return out


## The smallest zone radius among the species' territorial sites, or the brain's default territory
## for a species with none (a fixture's creatures, placed by tests).
func _smallest_territory(species_id: String, layout: PoolLayout) -> float:
	var smallest := INF
	for s in sites_of(species_id):
		var z := layout.zone(str(s.territory_zone))
		if not z.is_empty():
			smallest = minf(smallest, float(z.radius))
	return smallest if is_finite(smallest) else CreatureBrain.DEFAULT_TERRITORY_M


static func _has_jaw(p: Phenotype) -> bool:
	if p.bite_damage <= 0.0:
		return false
	for mouth in p.mouths:
		if mouth.type == "mouth_jaw":
			return true
	return false


static func _actor(id: String, position: Vector2, p: Phenotype) -> InteractionResolver.Actor:
	return InteractionResolver.Actor.new(id, position, 0.0, p)


static func _rule(errors: PackedStringArray, number: int, text: String) -> void:
	errors.append("Rule %d (%s): %s" % [number, RULE_NAMES[number], text])


# --- reading ---

## Converts the timers to ticks and builds each species' brain config, once the data has read cleanly.
func _prepare() -> void:
	for id in species_ids():
		configs[id] = CreatureBrain.config(id, species[id], ai, relationships)
	for s in fairness.grace_s:
		grace_ticks.append(CreatureBrain.ticks(s))
	for share in fairness.respawn_energy_share:
		respawn_energy_share.append(float(share))
	streak_window_ticks = CreatureBrain.ticks(fairness.streak_window_s)
	killer_ignore_ticks = CreatureBrain.ticks(fairness.killer_ignore_s)
	start_grace_ticks = CreatureBrain.ticks(fairness.start_grace_s)
	spawn_retry_ticks = CreatureBrain.ticks(spawning.retry_s)
	fade_in_ticks = CreatureBrain.ticks(spawning.fade_in_s)


static func _check_species_block(block: Dictionary, where: String, problems: Array) -> void:
	var before := problems.size()
	_check_block(block, SPECIES_KEYS, where, problems)
	var behavior = block.get("behavior")
	if behavior is String and BEHAVIOR_KEYS.has(behavior):
		for key in BEHAVIOR_KEYS[behavior]:
			if not block.has(key):
				problems.append("%s: '%s' is missing (a %s species needs it)." % [where, key, behavior])
	if problems.size() > before:
		return
	for key in SUB_BLOCKS:
		_check_block(block[key], SUB_BLOCKS[key], "%s %s" % [where, key], problems)
	if block.has("habit"):
		_check_block(block.habit, HABIT_KEYS, "%s habit" % where, problems)
	for part in block.parts:
		if part is Dictionary:
			_check_block(part, PART_KEYS, "%s part" % where, problems)
		else:
			problems.append("%s: a part entry is not an object." % where)


## A copy of the block at `key`, checked against its keys; {} when it is not an object.
static func _block(data: Dictionary, key: String, keys: Dictionary, where: String, problems: Array) -> Dictionary:
	var value = data.get(key)
	if not value is Dictionary:
		return {}
	_check_block(value, keys, where, problems)
	return (value as Dictionary).duplicate(true)


## Unknown keys (rule 13), then each known key's presence and kind.
static func _check_block(block: Dictionary, keys: Dictionary, where: String, problems: Array) -> void:
	for key in _sorted_keys(block):
		if not keys.has(key):
			problems.append("Rule 13 (%s): %s has an unknown key '%s'." % [RULE_NAMES[13], where, key])
	for key in keys:
		var kind: String = keys[key]
		var optional := kind.ends_with("?")
		kind = kind.trim_suffix("?")
		if not block.has(key):
			if not optional:
				problems.append("%s: '%s' is missing." % [where, key])
		elif not _kind_ok(block[key], kind):
			problems.append("%s: '%s' must be %s." % [where, key, KIND_TEXT[kind]])


static func _kind_ok(value: Variant, kind: String) -> bool:
	match kind:
		"number":
			return (value is float or value is int) and is_finite(value)
		"whole":
			return value is int or (value is float and is_finite(value) and value == floorf(value))
		"text":
			return value is String
		"flag":
			return value is bool
		"list":
			return value is Array
		"object":
			return value is Dictionary
		"pair":
			return value is Array and value.size() == 2 and _kind_ok(value[0], "number") and _kind_ok(value[1], "number")
		"numbers":
			if not value is Array:
				return false
			for v in value:
				if not _kind_ok(v, "number"):
					return false
			return true
	return false


static func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys
