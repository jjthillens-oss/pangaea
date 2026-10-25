extends RefCounted
## Test helper (not a test file): growth, faked for the scene's tests (S2 spine 3.17, s2-view 10.0).
## FakeGrowth has the read API of T2's Growth (spine 3.7) and words its hint() exactly as T2 does
## (s2-sim 3.5), so the HUD can be driven through every state on cue. The builders make the growth
## events of spine 3.11 by hand, positions in local tm as the sim emits them. open_pool() opens a
## pool whose growth() is a FakeGrowth, the way FakeWorldEvents.open_pool opens one.
##
##     const FakeGrowthEvents := preload("res://tests/fakes/fake_growth_events.gd")
##     var growth := FakeGrowthEvents.FakeGrowth.new()
##     var pool := FakeGrowthEvents.open_pool(FakeEvents.endless_session(), growth)
##     ...
##     pool.free()

const FakeEvents := preload("res://tests/fakes/fake_world_events.gd")
const POOL_SCENE := preload("res://game/scenes/pool/pool.tscn")

## The shipped rings (world_cell.json growth.rings, s2-sim 4.1) and the hint's wait: a blocker is
## named once the ring has been full and not calm for blocked_hint_s 3.0 s.
const RINGS: Array[float] = [90.0, 120.0, 150.0, 170.0, 180.0, 190.0, 200.0, 205.0, 210.0]
const HINT_TICKS := 180
const LABELS: Array[String] = ["about 20 µm", "about 32 µm", "about 51 µm", "about 82 µm", "about 131 µm",
	"about 210 µm", "about 336 µm", "about 537 µm", "about 859 µm", "about 1.37 mm"]
## Every line hint() can give (spine 3.15), "" included.
const HINTS: PackedStringArray = ["", "Growing…", "Ring full: something is hunting you",
	"Ring full: stop chasing to grow", "Ring full: stop eating to grow", "Ring full: get clear of the shells",
	"Not while something is hunting you", "Ready to grow (G)"]
const BLOCKER_LINES := {"hunted": "Ring full: something is hunting you", "chasing": "Ring full: stop chasing to grow",
	"eating": "Ring full: stop eating to grow", "wedged": "Ring full: get clear of the shells"}


## Growth's read API with fields set by hand. "Full" is full_since >= 0, as in Growth.
class FakeGrowth extends RefCounted:
	var trigger := "auto"
	var armed := false
	var meter := 0.0
	var calm_ticks := 0
	var full_since := -1
	var blocked_ticks := 0
	var blocker := ""
	var due := false
	var beat_until := -1
	var places := {}   ## size -> Vector2i(found, total), S3's places line

	func places_found(n: int) -> Vector2i:
		return places.get(n, Vector2i.ZERO)

	func ring(n: int) -> float:
		return RINGS[n - 1] if n >= 1 and n <= RINGS.size() else 0.0

	func is_full(n: int) -> bool:
		return ring(n) > 0.0 and meter >= ring(n) - 1e-9

	func at_top(n: int, max_in_build: int) -> bool:
		return n >= max_in_build

	## s2-sim 3.5's hint(), word for word.
	func hint() -> String:
		var full := full_since >= 0
		if full and calm_ticks > 0:
			return "Growing…"
		if blocked_ticks >= HINT_TICKS and BLOCKER_LINES.has(blocker):
			return BLOCKER_LINES[blocker]
		if trigger == "press" and armed and blocker == "hunted":
			return "Not while something is hunting you"
		if trigger == "press" and full and not armed:
			return "Ready to grow (G)"
		return ""

	## Fills the ring of size n (full since tick 0).
	func fill(n: int) -> FakeGrowth:
		meter = ring(n)
		full_since = 0
		return self

	## The fields that give hint() == `line` at size n (one of HINTS).
	func show_line(line: String, n := 1) -> FakeGrowth:
		meter = 0.0
		full_since = -1
		calm_ticks = 0
		blocked_ticks = 0
		blocker = ""
		armed = false
		trigger = "auto"
		match line:
			"Growing…":
				fill(n)
				calm_ticks = 30
			"Not while something is hunting you":
				fill(n)
				trigger = "press"
				armed = true
				blocker = "hunted"
			"Ready to grow (G)":
				fill(n)
				trigger = "press"
			"":
				meter = ring(n) * 0.5
			_:
				fill(n)
				blocker = str(BLOCKER_LINES.find_key(line))
				blocked_ticks = HINT_TICKS
		return self


## A pool whose growth() is the fake instead of the sim's.
class GrowthPool extends PoolScene:
	var fake_growth: Object

	func growth() -> Object:
		return fake_growth


## The session's pool with `growth` as its growth, built as FakeWorldEvents.open_pool builds one
## (outside the tree, readied by hand). `provider` swims for the cell; null means the player's
## SwimInput, as in the game. Free it with pool.free().
static func open_pool(session: GameSession, growth: Object, provider: Object = null) -> PoolScene:
	var pool: PoolScene = POOL_SCENE.instantiate()
	pool.set_script(GrowthPool)
	pool.set(&"fake_growth", growth)
	pool.pause_on_focus_loss = false
	pool.setup(session, provider)
	FakeEvents.ready_tree(pool)
	return pool


# --- the growth events (spine 3.11; s2-sim 3.10), local tm ---

static func began(center_old: Vector2, from: int, to: int, factor := 1.6) -> Dictionary:
	return {"type": "growth_began", "from": from, "to": to, "center_old": center_old, "center_am": [0.0, 0.0],
		"factor": factor}


static func converted(id: String, species: String, to: String, position: Vector2, radius: float,
		food_id := "") -> Dictionary:
	return {"type": "creature_converted", "id": id, "species": species, "to": to, "position": position,
		"radius": radius, "food_id": food_id}


## `haze`: [{kind, look, position (old frame)}]; `remnants`: creature ids; `morsels`: food ids.
static func grew(settled_to: Vector2, haze := [], remnants := [], morsels := [], from := 1, to := 2) -> Dictionary:
	return {"type": "grew", "from": from, "to": to, "center": Vector2.ZERO, "settled_from": Vector2.ZERO,
		"settled_to": settled_to, "remnants": remnants, "morsels": morsels, "haze": haze,
		"checkpoint_am": [0.0, 0.0, -PI / 2.0, float(to)]}


static func ring_full(size: int, ring: float) -> Dictionary:
	return {"type": "ring_full", "size": size, "ring": ring}


static func lump(reason: String, amount: float, id := "") -> Dictionary:
	return {"type": "meter_lump", "reason": reason, "amount": amount, "id": id}


static func blocked(blocker: String) -> Dictionary:
	return {"type": "growth_blocked", "blocker": blocker}


static func unblocked() -> Dictionary:
	return {"type": "growth_unblocked"}


static func waiting(reason: String) -> Dictionary:
	return {"type": "growth_waiting", "reason": reason}


## The pair the sim emits at the build top: earned {reason "ring"} then ring_paid.
static func ring_paid(points: int, size := 2, energy := 100.0) -> Array[Dictionary]:
	return [{"type": "earned", "points": points, "reason": "ring"},
		{"type": "ring_paid", "size": size, "energy": energy, "points": points}]


## Spine 3.11 names the find's type "type", which the event's own type holds; this fake calls it "kind".
static func discovered(kind: String, id: String, size := 1, with_lump := true) -> Dictionary:
	return {"type": "discovered", "kind": kind, "id": id, "size": size, "lump": with_lump}


## One site of a chunk_loaded event (C-V10): {id, species, posts: [{position, heading}]}.
static func site(id: String, species: String, posts: Array[Dictionary] = []) -> Dictionary:
	return {"id": id, "species": species, "posts": posts}


static func post(position: Vector2, heading := 0.0) -> Dictionary:
	return {"position": position, "heading": heading}


## A chunk_loaded event's `sites` list.
static func sites_payload(sites: Array[Dictionary]) -> Array[Dictionary]:
	return sites.duplicate(true)


## Two Lurker sites of two posts each (s_a, s_b) and a rammer's (s_r), round `center`, at 1 / `factor`
## of the base layout: 1 as first loaded (the posts offset from center), else re-expressed round it.
static func lair_sites(center: Vector2, factor := 1.0) -> Array[Dictionary]:
	var at := func(offset: Vector2) -> Vector2:
		return center + offset if factor == 1.0 else offset / factor
	return sites_payload([
		site("s_a", "lurker", [post(at.call(Vector2(4.0, 3.0)), 0.5), post(at.call(Vector2(-5.0, 2.0)), 2.0)] as Array[Dictionary]),
		site("s_b", "lurker", [post(at.call(Vector2(2.0, -6.0)), -1.0), post(at.call(Vector2(8.0, 1.0)), 3.0)] as Array[Dictionary]),
		site("s_r", "rammer", [post(at.call(Vector2(0.0, 9.0)), 0.0)] as Array[Dictionary])])


## A creature_post_move event (spine 3.15) from `from` to `to` of creature `id`.
static func post_move(from: Vector2, to: Vector2, id := "") -> Dictionary:
	return {"type": "creature_post_move", "id": id, "post": 1, "from": from, "to": to}
