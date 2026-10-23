extends TestCase
## S2's habits (B.7, D-23, gate S2G6): a brain with two posts moves between them only from a CALM
## state with no target, the Lurker after its dwell with the cell out of sight, the elder rammer when
## the cell is nearer the other zone by the hysteresis; its leash disc is the union of the two posts'
## (D-82), its moves stay inside it, and a rebase shifts the posts (D-83). The brains are
## creatures_m1.json's Lurker and elder rammer at their entry size.

const DT := 1.0 / 60.0
## Every state and phase the brain has, so the CALM table is checked against all their pairs.
const STATES := ["rest", "wander", "forage", "notice", "chase", "attack", "flee"]
const PHASES := ["", "lurk", "watch", "patrol", "return", "seek", "eat", "wait", "pursue", "aim", "tell", "strike",
	"glide", "recover"]
## Lurker posts 8 m apart; elder rammer zones (own radius 3 m) 10 m apart, as the tiles space them.
const LURK_A := Vector2(0.0, 0.0)
const LURK_B := Vector2(8.0, 0.0)
const ZONE_A := Vector2(0.0, 0.0)
const ZONE_B := Vector2(10.0, 0.0)
const ZONE_R := 3.0
## Two-post sites on a bounded arena, before the tiles exist (spine 3.17); other test files read it
## through posts_fixture().
const POSTS_FIXTURE := "res://tests/fixtures/creatures_posts_test.json"

var parts: PartCatalog
var species: SpeciesCatalog
var lurker_cfg: Dictionary
var elder_cfg: Dictionary


## One creature, as in test_creature_brain: a brain and a body, and the cell's place in its view.
class Critter:
	var mem: CreatureBrain.Memory
	var m: Locomotion.MotionState
	var p: Phenotype
	var number := 1
	var cell := Vector2.INF
	var cell_seen := false
	var events: Array[Dictionary] = []

	func view() -> Dictionary:
		return {"id": "c_%d" % number, "species": mem.cfg.species_id, "position": m.position, "heading": m.heading,
			"velocity": m.velocity, "speed_now": m.velocity.length(), "radius": p.radius, "speed": p.speed,
			"acceleration": p.acceleration, "health_share": 1.0, "energy_share": 0.9, "cell": cell, "cell_seen": cell_seen}

	func label() -> String:
		return "%s/%s" % [mem.state, mem.phase]

	func moves() -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for e in events:
			if e.type == "creature_post_move":
				out.append(e)
		return out


func before_each() -> void:
	parts = PartCatalog.load_from()
	species = SpeciesCatalog.load_from()
	lurker_cfg = species.brain_config("lurker")
	elder_cfg = species.brain_config("elder_rammer")


## creatures_posts_test.json read for tests: {"soft_start", "rocks": [{"id", "center", "radius"}],
## "sites": [{"id", "species", "home", "heading", "territory", "post_b": {"home", "heading",
## "territory"}, "posts" (CreatureBrain.set_posts' two posts)}]}, each territory its zone's circle ({}
## for an ambush post).
static func posts_fixture() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(POSTS_FIXTURE))
	var zones := {}
	for z in data.zones:
		zones[z.id] = {"center": Vector2(z.center[0], z.center[1]), "radius": float(z.radius)}
	var rocks: Array[Dictionary] = []
	for r in data.arena.rocks:
		rocks.append({"id": str(r.id), "center": Vector2(r.center[0], r.center[1]), "radius": float(r.radius)})
	var sites: Array[Dictionary] = []
	for s in data.sites:
		var b: Dictionary = s.post_b
		var site := {"id": str(s.id), "species": str(s.species), "home": Vector2(s.home[0], s.home[1]), "heading": float(s.heading),
			"territory": zones.get(str(s.get("territory_zone", "")), {}),
			"post_b": {"home": Vector2(b.home[0], b.home[1]), "heading": float(b.heading),
				"territory": zones.get(str(b.get("territory_zone", "")), {})}}
		site["posts"] = [{"home": site.home, "heading": site.heading, "territory": site.territory}, site.post_b.duplicate()]
		sites.append(site)
	return {"soft_start": float(data.arena.soft_start), "rocks": rocks, "sites": sites}


## The site's two posts moved so that post a's home is `at` (zones with them), as set_posts takes them.
static func posts_at(site: Dictionary, at: Vector2) -> Array:
	var by: Vector2 = at - Vector2(site.home)
	var out: Array = []
	for p in site.posts:
		var t: Dictionary = p.territory
		out.append({"home": Vector2(p.home) + by, "heading": p.heading,
			"territory": {} if t.is_empty() else {"center": Vector2(t.center) + by, "radius": t.radius}})
	return out


## The shells within the post-path capsule of a two-post site (BP-11): the segment between its post
## homes, widened by the body's radius plus the route clearance, both at q (the species' own size).
static func capsule_hits(site: Dictionary, radius: float, q: float, rocks: Array[Dictionary]) -> Array:
	var reach := radius + float(CreatureBrain.WORLD_LENGTHS.route_clearance) * q
	var a: Vector2 = site.home
	var b: Vector2 = site.post_b.home
	var out := []
	for r in rocks:
		var p: Vector2 = r.center
		var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		if p.distance_to(a + (b - a) * t) - float(r.radius) <= reach:
			out.append(r.id)
	return out


## A settled Lurker resting at post A, posts A and B.
func _lurker(tick := 0) -> Critter:
	var c := Critter.new()
	c.mem = CreatureBrain.create("ambush", lurker_cfg, LURK_A, 0.0, {}, 7, tick)
	c.mem.ignore_all_until = 0
	CreatureBrain.set_posts(c.mem, [{"home": LURK_A, "heading": 0.0, "territory": {}},
		{"home": LURK_B, "heading": PI, "territory": {}}])
	c.m = Locomotion.MotionState.new(LURK_A, 0.0)
	c.p = species.phenotype("lurker", parts)
	return c


## A settled elder rammer resting at zone A's home, guarding zone A, posts A and B.
func _elder(tick := 0, cfg := {}) -> Critter:
	var c := Critter.new()
	var use: Dictionary = elder_cfg if cfg.is_empty() else cfg
	var home_a := ZONE_A + Vector2(0.0, -1.0)
	c.mem = CreatureBrain.create("territorial", use, home_a, PI / 2.0, {"center": ZONE_A, "radius": ZONE_R}, 7, tick)
	c.mem.ignore_all_until = 0
	CreatureBrain.set_posts(c.mem, [{"home": home_a, "heading": PI / 2.0, "territory": {"center": ZONE_A, "radius": ZONE_R}},
		{"home": ZONE_B + Vector2(0.0, 1.0), "heading": -PI / 2.0, "territory": {"center": ZONE_B, "radius": ZONE_R}}])
	c.m = Locomotion.MotionState.new(home_a, PI / 2.0)
	c.p = species.phenotype("elder_rammer", parts)
	return c


## One think with nothing in view, its events collected.
func _think(c: Critter, tick: int) -> void:
	CreatureBrain.think(c.mem, c.view(), [], [], tick, null)
	_collect(c, tick)


func _collect(c: Critter, tick: int) -> void:
	for e in c.mem.events:
		var copy: Dictionary = e.duplicate()
		copy["tick"] = tick
		c.events.append(copy)
	c.mem.events.clear()


## One tick as the sim runs it (test_creature_brain's _tick, no rocks). Returns false when the move,
## before the clamp, left the leash disc.
func _tick(c: Critter, tick: int) -> bool:
	if CreatureBrain.think_due(c.mem, c.number, tick):
		CreatureBrain.think(c.mem, c.view(), [], [], tick, null)
	var d := CreatureBrain.drive(c.mem, c.view(), tick, null)
	CreatureBrain.move_body(c.mem, c.m, d, c.p, 1.0, DT)
	c.m.prev_position = c.m.position
	c.m.position += c.m.velocity * DT
	var disc := CreatureBrain.leash_disc(c.mem)
	var inside := c.m.position.distance_to(disc.center) <= float(disc.radius)
	PoolArena.clamp_to_disc(c.m, disc.center, disc.radius)
	_collect(c, tick)
	return inside


# --- CALM ---

func test_calm_is_s1s_set_and_is_calm_answers_it_for_every_state_and_phase() -> void:
	check_eq(CreatureBrain.CALM.keys(), ["rest/lurk", "rest/", "wander/patrol", "forage/seek", "forage/eat"],
		"CALM is S1 3.11's set (D-62)")
	var mem := _lurker().mem
	var calm := 0
	for state in STATES:
		for phase in PHASES:
			mem.state = state
			mem.phase = phase
			var want := CreatureBrain.CALM.has("%s/%s" % [state, phase])
			check_eq(CreatureBrain.is_calm(mem), want, "is_calm(%s/%s)" % [state, phase])
			calm += 1 if want else 0
	check_eq(calm, 5, "every CALM label is a state/phase the brain has")


# --- posts and the union disc ---

func test_set_posts_takes_post_zero_and_its_leash_disc_is_the_union_of_its_posts_discs() -> void:
	var c := _lurker()
	check_eq(c.mem.post, 0, "it guards post 0")
	check_eq(c.mem.home, LURK_A, "from post 0's home")
	check_eq(c.mem.post_since, c.mem.state_tick, "since its state tick")
	var leash := float(lurker_cfg.leash_m)
	var want := CreatureBrain.union_disc({"center": LURK_A, "radius": leash}, {"center": LURK_B, "radius": leash})
	check_eq(CreatureBrain.leash_disc(c.mem), want, "the Lurker's leash disc is its two posts' union")
	check_eq(want.radius, leash + 4.0, "which spans both posts")
	var site := {"species": "lurker", "home": LURK_A, "heading": 0.0}
	var catalog := species.two_post_disc_for(site, {}, {"home": LURK_B, "heading": PI}, {})
	check_eq(CreatureBrain.leash_disc(c.mem), {"center": catalog.center, "radius": catalog.radius},
		"and the species catalog's two-post disc (the worldgen's reach)")
	# Each post's disc is the leash disc a one-post brain at that post has.
	var e := _elder()
	var discs: Array = []
	for i in 2:
		var p: Dictionary = e.mem.posts[i]
		var one := CreatureBrain.create("territorial", elder_cfg, p.home, p.heading, p.territory, 7, 0)
		discs.append(CreatureBrain.leash_disc(one))
	check_eq(CreatureBrain.leash_disc(e.mem), CreatureBrain.union_disc(discs[0], discs[1]),
		"the elder rammer's leash disc is the union of its one-post discs")
	check_eq(e.mem.territory_center, ZONE_A, "it guards zone A")
	check_eq(e.mem.territory_r, ZONE_R + float(elder_cfg.territory_margin_m), "with its margin")
	var e_site := {"species": "elder_rammer", "home": e.mem.posts[0].home, "heading": PI / 2.0}
	var e_catalog := species.two_post_disc_for(e_site, {"center": ZONE_A, "radius": ZONE_R}, e.mem.posts[1],
		{"center": ZONE_B, "radius": ZONE_R})
	check_eq(CreatureBrain.leash_disc(e.mem), {"center": e_catalog.center, "radius": e_catalog.radius},
		"and the species catalog's two-post disc")


func test_the_brain_takes_post_zero_keeps_its_own_copy_of_the_posts_and_needs_two() -> void:
	var far := CreatureBrain.create("territorial", elder_cfg, Vector2(30.0, 30.0), 0.0, {}, 7, 0)
	CreatureBrain.set_posts(far, [{"home": ZONE_A, "heading": 1.0, "territory": {"center": ZONE_A, "radius": ZONE_R}},
		{"home": ZONE_B, "heading": 2.0, "territory": {"center": ZONE_B, "radius": ZONE_R}}])
	check_eq([far.home, far.home_heading, far.territory_center, far.territory_r],
		[ZONE_A, 1.0, ZONE_A, ZONE_R + float(elder_cfg.territory_margin_m)], "it takes post 0 whatever create() was given")
	var c := Critter.new()
	c.mem = CreatureBrain.create("ambush", lurker_cfg, LURK_A, 0.0, {}, 7, 0)
	var posts := [{"home": LURK_A, "heading": 0.0, "territory": {}}, {"home": LURK_B, "heading": PI, "territory": {}}]
	CreatureBrain.set_posts(c.mem, posts)
	posts[1].home = Vector2(50.0, 0.0)
	check_eq(c.mem.posts[1].home, LURK_B, "a change to the caller's posts (a site's) leaves the brain's")
	var one := CreatureBrain.create("ambush", lurker_cfg, LURK_A, 0.0, {}, 7, 0)
	CreatureBrain.set_posts(one, [posts[0]])
	check(one.posts.is_empty(), "one post is refused")
	check_eq(CreatureBrain.leash_disc(one), {"center": LURK_A, "radius": float(lurker_cfg.leash_m)}, "its disc is M1's")


# --- when a post move may start ---

func test_a_post_move_starts_only_from_calm_with_no_target_never_in_watch_notice_chase_attack_or_flee() -> void:
	for kind in ["lurker", "elder"]:
		for state in STATES:
			for phase in PHASES:
				for target in ["", "c_9"]:
					var c := _lurker() if kind == "lurker" else _elder()
					if kind == "elder":
						c.cell = ZONE_B   # nearer zone B by its whole spacing
					c.mem.state = state
					c.mem.phase = phase
					c.mem.target = target
					_think(c, 600)
					var calm := CreatureBrain.CALM.has("%s/%s" % [state, phase])
					var allowed: bool = calm and str(target).is_empty() and (kind == "elder" or state == "rest")
					var label := "%s %s/%s target '%s'" % [kind, state, phase, target]
					check_eq(c.moves().size(), 1 if allowed else 0, label + ": moves only when allowed")
					check_eq(c.mem.post, 1 if allowed else 0, label + ": its post")


func test_a_brain_with_posts_but_no_habit_never_moves_and_one_without_posts_never_reads_the_habit() -> void:
	var c := Critter.new()
	var plain := CreatureBrain.config("ambush_hunter", species.species.ambush_hunter, species.ai)
	c.mem = CreatureBrain.create("ambush", plain, LURK_A, 0.0, {}, 7, 0)
	CreatureBrain.set_posts(c.mem, [{"home": LURK_A, "heading": 0.0, "territory": {}},
		{"home": LURK_B, "heading": PI, "territory": {}}])
	c.m = Locomotion.MotionState.new(LURK_A, 0.0)
	c.p = species.phenotype("ambush_hunter", parts)
	_think(c, 6000)
	check(c.moves().is_empty() and c.mem.post == 0, "no habit, no move")
	var lone := _lurker()
	lone.mem.posts = []
	_think(lone, 6000)
	check(lone.moves().is_empty() and lone.label() == "rest/lurk", "no posts, no move")


func test_out_of_sight_waits_its_dwell_at_rest_and_at_the_post_and_never_while_the_cell_is_seen() -> void:
	var dwell := int(lurker_cfg.post_rest_ticks)
	check_eq(dwell, 480, "8 s at rest (D-23)")
	var c := _lurker()
	_think(c, dwell - 1)
	check(c.moves().is_empty(), "not before its dwell")
	c.cell_seen = true
	c.cell = LURK_A + Vector2(3.0, 0.0)
	_think(c, dwell)
	check(c.moves().is_empty(), "not while it sees the cell")
	c.cell_seen = false
	_think(c, dwell)
	check_eq(c.moves().size(), 1, "at its dwell with the cell out of sight (placed, not seen)")
	var move: Dictionary = c.moves()[0]
	check_eq([move.post, move.from, move.to], [1, LURK_A, LURK_B], "to post 1, from post A's home to post B's")
	check_eq(c.label(), "wander/return", "by the M1 return path")
	check_eq([c.mem.home, c.mem.home_heading, c.mem.post_since], [LURK_B, PI, dwell], "post B's home and heading, taken now")
	# The dwell counts from its rest...
	var rested := _lurker()
	rested.mem.state_tick = 100
	_think(rested, 100 + dwell - 1)
	check(rested.moves().is_empty(), "rested one tick too few")
	_think(rested, 100 + dwell)
	check_eq(rested.moves().size(), 1, "rested its dwell")
	# ...and from taking the post.
	var posted := _lurker()
	posted.mem.post_since = 300
	_think(posted, 300 + dwell - 1)
	check(posted.moves().is_empty(), "at the post one tick too few")
	_think(posted, 300 + dwell)
	check_eq(posted.moves().size(), 1, "at the post its dwell")


func test_nearer_cell_needs_the_cell_nearer_the_other_zone_by_its_hysteresis() -> void:
	check_eq(float(elder_cfg.post_hysteresis_m), 2.0, "2 m (D-23)")
	# Zones 10 m apart on the x axis: the cell at x is nearer zone B by 2x - 10, more than 2 m past x = 6.
	for x in [6.0, 5.75, 0.0]:
		var c := _elder()
		c.cell = Vector2(x, 0.0)
		_think(c, 600)
		check(c.moves().is_empty(), "not at x = %.2f" % x)
	var at := _elder()
	at.cell = Vector2(6.25, 0.0)
	_think(at, 600)
	check_eq(at.moves().size(), 1, "at x = 6.25")
	check_eq([at.mem.territory_center, at.mem.territory_r], [ZONE_B, ZONE_R + float(elder_cfg.territory_margin_m)],
		"it guards zone B now")
	var none := _elder()
	_think(none, 600)
	check(none.moves().is_empty(), "no cell placed (dead or concealed), no move")
	var bare := _elder()
	bare.mem.posts[1].territory = {}
	bare.cell = ZONE_B
	_think(bare, 600)
	check(bare.moves().is_empty(), "a post without a zone is never nearer")
	# Not before it is home again: going home is not calm.
	at.cell = ZONE_A
	_think(at, 601)
	check_eq(at.moves().size(), 1, "on its way to zone B it does not turn back")
	# The hysteresis is a length: at q = 0.625 it is 1.25 m (cfg, scale_cfg), so x = 5.75 moves it.
	var small := _elder(0, CreatureBrain.scale_cfg(elder_cfg, 0.625))
	small.cell = Vector2(5.75, 0.0)
	_think(small, 600)
	check_eq(small.moves().size(), 1, "at a third of the way past the scaled hysteresis")


# --- the lure, in motion ---

func test_the_lure_moves_an_elder_rammer_back_and_forth_and_every_move_stays_in_its_union_disc() -> void:
	var c := _elder()
	c.cell = ZONE_B + Vector2(0.0, -2.0)
	var outside := 0
	var t := 0
	while t < 1200 and not (c.mem.post == 1 and c.label() == "rest/"):
		outside += 0 if _tick(c, t) else 1
		t += 1
	check_eq(c.moves().size(), 1, "the cell at zone B lures it there once")
	check(c.label() == "rest/" and c.m.position.distance_to(c.mem.home) <= float(elder_cfg.arrive_home_m),
		"it reaches zone B's home and rests (%s at %s, tick %d)" % [c.label(), c.m.position, t])
	check(t * DT < float(elder_cfg.nav_timeout_ticks) * DT, "within its navigation timeout (%.1f s)" % (t * DT))
	c.cell = ZONE_A
	var back := t
	while t < back + 1200 and not (c.mem.post == 0 and c.label() == "rest/"):
		outside += 0 if _tick(c, t) else 1
		t += 1
	check_eq(c.moves().size(), 2, "and back to zone A")
	check(c.label() == "rest/" and c.m.position.distance_to(c.mem.home) <= float(elder_cfg.arrive_home_m),
		"it reaches zone A's home and rests")
	check_eq(outside, 0, "no move left the union disc before the clamp")
	check(not c.mem.stuck, "and it never got stuck")


func test_a_lurker_alone_moves_post_to_post_every_dwell_and_stays_in_its_union_disc() -> void:
	var c := _lurker()
	var outside := 0
	for t in 2400:
		outside += 0 if _tick(c, t) else 1
	var moves := c.moves()
	check(moves.size() >= 2, "it moved at least twice in 40 s (%d)" % moves.size())
	var dwell := int(lurker_cfg.post_rest_ticks)
	check(int(moves[0].tick) >= dwell and int(moves[0].tick) < dwell + int(lurker_cfg.think_ticks),
		"the first move on the first think after its dwell (tick %d)" % moves[0].tick)
	for i in moves.size():
		check_eq(moves[i].to, LURK_B if i % 2 == 0 else LURK_A, "move %d goes to the other post" % i)
	check(int(moves[1].tick) - int(moves[0].tick) >= dwell, "and rests its dwell before the next")
	check_eq(outside, 0, "no move left the union disc before the clamp")


# --- snapshots and rebases ---

func test_the_memory_dict_leaves_the_post_fields_out_at_their_defaults() -> void:
	var keys := ["posts", "post", "post_since", "leash_center", "leash_r"]
	var plain := CreatureBrain.create("ambush", lurker_cfg, LURK_A, 0.0, {}, 7, 0).to_dict()
	for k in keys:
		check(not plain.has(k), "no posts: no %s" % k)
	var c := _lurker()
	var d := c.mem.to_dict()
	check_eq(d.posts, [{"home": [0.0, 0.0], "heading": 0.0, "territory": {}}, {"home": [8.0, 0.0], "heading": PI, "territory": {}}],
		"posts as pairs")
	check_eq([d.leash_center, d.leash_r], [[c.mem.leash_center.x, c.mem.leash_center.y], c.mem.leash_r], "and the union")
	check(not d.has("post") and not d.has("post_since"), "post 0 since tick 0 are defaults")
	_think(c, 480)
	d = c.mem.to_dict()
	check_eq([d.post, d.post_since], [1, 480], "after a move both are written")
	var e := _elder().mem.to_dict()
	check_eq(e.posts[1].territory, {"center": [10.0, 0.0], "radius": ZONE_R}, "a zone as a pair and its radius")


func test_a_rebase_shifts_every_post_and_the_union_centre() -> void:
	var by := Vector2(96.0, -64.0)
	var e := _elder()
	var before := e.mem.posts.duplicate(true)
	var center := e.mem.leash_center
	var r := e.mem.leash_r
	RebaseShift.posts(e.mem, by)
	for i in 2:
		check_eq(e.mem.posts[i].home, Vector2(before[i].home) - by, "post %d's home" % i)
		check_eq(e.mem.posts[i].territory.center, Vector2(before[i].territory.center) - by, "post %d's zone centre" % i)
		check_eq(e.mem.posts[i].territory.radius, before[i].territory.radius, "post %d's zone radius" % i)
	check_eq(e.mem.leash_center, center - by, "the union disc's centre")
	check_eq(e.mem.leash_r, r, "and not its radius")
	var l := _lurker()
	RebaseShift.posts(l.mem, by)
	check_eq(l.mem.posts[1].territory, {}, "an ambush post has no zone to shift")
	var plain := CreatureBrain.create("ambush", lurker_cfg, LURK_A, 0.0, {}, 7, 0)
	RebaseShift.posts(plain, by)
	check(not plain.leash_center.is_finite(), "a brain without posts is left as it is")


# --- the posts fixture (BP-11) ---

func test_the_posts_fixture_puts_no_shell_within_any_post_path_capsule() -> void:
	var fx := posts_fixture()
	check_eq(fx.sites.map(func(s: Dictionary) -> String: return s.species), ["lurker", "elder_rammer"], "one site of each")
	for site: Dictionary in fx.sites:
		var id: String = site.species
		var n := species.entry_size(id)
		var record := species.at_size(id, n, parts)
		var radius: float = (record.phenotype as Phenotype).radius
		check_eq(record.q, 1.0, "%s at its entry size" % id)
		check_eq(capsule_hits(site, radius, record.q, fx.rocks), [], "%s: the path between its posts is clear" % site.id)
		# The same check finds a shell put across the path, and one just touching the capsule.
		var mid: Vector2 = (Vector2(site.home) + Vector2(site.post_b.home)) / 2.0
		var across: Array[Dictionary] = [{"id": "across", "center": mid, "radius": 0.5}]
		check_eq(capsule_hits(site, radius, record.q, across), ["across"], "%s: a shell across the path is found" % site.id)
		var side := (Vector2(site.post_b.home) - Vector2(site.home)).orthogonal().normalized()
		var reach := radius + float(CreatureBrain.WORLD_LENGTHS.route_clearance)
		var touching: Array[Dictionary] = [{"id": "touching", "center": mid + side * (reach + 0.5 - 1e-3), "radius": 0.5}]
		check_eq(capsule_hits(site, radius, record.q, touching), ["touching"], "%s: so is one touching the capsule" % site.id)
		var clear: Array[Dictionary] = [{"id": "clear", "center": mid + side * (reach + 0.5 + 1e-3), "radius": 0.5}]
		check_eq(capsule_hits(site, radius, record.q, clear), [], "%s: and not one just clear of it" % site.id)
