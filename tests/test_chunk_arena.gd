extends TestCase
## The endless world's colliders (ChunkArena, S1; docs/s1/s1-core.md section 6.3): with the near
## grids and candidate chunks every query comes out bit-identical to PoolArena's own loops over the
## canonical arrays (G6), at home and 100 km out (G12); the grids are exact under adds and removes
## (C-19); settle hands a deep push to the reference; bad colliders and duplicate keys are refused.

const DT := 1.0 / 60.0
const BODY_R := 0.5


## Tile-like colliders for `count` chunks out of the keys in [lo, hi]^2: 3 to 8 a chunk, r 0.6 to 4.0,
## a third within 6 tm of a chunk edge. {Vector2i: Array[Dictionary] {id, x, y, r}} (abs tm).
static func _layout(rng: RandomNumberGenerator, lo: int, hi: int, count: int, chunk := 32.0) -> Dictionary:
	var keys: Array[Vector2i] = []
	for y in range(lo, hi + 1):
		for x in range(lo, hi + 1):
			keys.append(Vector2i(x, y))
	while keys.size() > count:
		keys.remove_at(rng.randi_range(0, keys.size() - 1))
	var out := {}
	for key in keys:
		var list: Array[Dictionary] = []
		for i in rng.randi_range(3, 8):
			list.append(_collider(rng, key, "c_%d_%d_%d" % [key.x, key.y, i], chunk))
		out[key] = list
	return out


static func _collider(rng: RandomNumberGenerator, key: Vector2i, id: String, chunk := 32.0) -> Dictionary:
	var x := rng.randf_range(0.0, chunk)
	var y := rng.randf_range(0.0, chunk)
	if rng.randf() < 1.0 / 3.0:
		# Near an edge: one axis within 6 tm of a side.
		var near := rng.randf_range(0.001, 6.0)
		if rng.randf() < 0.5:
			x = near if rng.randf() < 0.5 else chunk - near
		else:
			y = near if rng.randf() < 0.5 else chunk - near
	return {"id": id, "x": key.x * chunk + x, "y": key.y * chunk + y, "r": rng.randf_range(0.6, 4.0)}


## A grid arena and its brute-force reference (rock_grid false), both holding `layout`.
static func _pair(layout: Dictionary) -> Array[ChunkArena]:
	var grid := ChunkArena.create_endless()
	var plain := ChunkArena.create_endless()
	plain.rock_grid = false
	for key: Vector2i in layout:
		grid.add_chunk(key, layout[key])
		plain.add_chunk(key, layout[key])
	return [grid, plain]


## A query point: half within 8 tm of a collider, a quarter within 4 tm of a loaded chunk's edge,
## the rest anywhere over the keys' span.
static func _point(rng: RandomNumberGenerator, arena: ChunkArena, lo: int, hi: int) -> Vector2:
	var roll := rng.randf()
	if roll < 0.5 and not arena._centers.is_empty():
		var c := arena._centers[rng.randi_range(0, arena._centers.size() - 1)]
		return c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 8.0)
	var keys := arena.chunk_keys()
	if roll < 0.75 and not keys.is_empty():
		var key := keys[rng.randi_range(0, keys.size() - 1)]
		var base := Vector2(key.x * 32.0 - arena.origin_x, key.y * 32.0 - arena.origin_y)
		var along := rng.randf_range(0.0, 32.0)
		var off := rng.randf_range(-4.0, 4.0) + (0.0 if rng.randf() < 0.5 else 32.0)
		return base + (Vector2(along, off) if rng.randf() < 0.5 else Vector2(off, along))
	return Vector2(rng.randf_range(lo * 32.0 - 10.0, (hi + 1) * 32.0 + 10.0) - arena.origin_x,
		rng.randf_range(lo * 32.0 - 10.0, (hi + 1) * 32.0 + 10.0) - arena.origin_y)


## Runs `queries` mixed queries on both arenas and returns the first difference ("" when none),
## counting interesting outcomes into `seen`.
func _compare(grid: ChunkArena, plain: ChunkArena, rng: RandomNumberGenerator, queries: int, lo: int, hi: int, seen: Dictionary) -> String:
	for i in queries:
		var p := _point(rng, grid, lo, hi)
		var r := rng.randf_range(0.0, PoolArena.GRID_BODY_R + 0.5)
		match i % 7:
			0:
				var a := grid.is_clear(p, r)
				if a != plain.is_clear(p, r):
					return "is_clear(%s, %s)" % [p, r]
				if not a:
					seen.blocked = seen.get("blocked", 0) + 1
			1, 2:
				var v := Vector2.ZERO if rng.randf() < 0.1 else Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 6.0)
				var ma := Locomotion.MotionState.new(p)
				var mb := Locomotion.MotionState.new(p)
				ma.velocity = v
				mb.velocity = v
				var free := p
				if i % 7 == 1:
					var da := grid.move(ma, BODY_R, DT)
					var db := plain.move(mb, BODY_R, DT)
					if da != db or ma.prev_position != mb.prev_position:
						return "move from %s at %s" % [p, v]
					free = p + v * DT
				else:
					grid.settle(ma, r)
					plain.settle(mb, r)
				if ma.position != mb.position or ma.velocity != mb.velocity:
					return "move or settle from %s at %s: %s %s against %s %s" % [p, v, ma.position, ma.velocity, mb.position, mb.velocity]
				if ma.position != free:
					seen.pushed = seen.get("pushed", 0) + 1
			3:
				var b := p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 20.0)
				var shrink: float = [PoolArena.SIGHT_SHRINK, 1.0, 1.3][rng.randi_range(0, 2)]
				var a := grid.segment_clear(p, b, shrink)
				if a != plain.segment_clear(p, b, shrink):
					return "segment_clear(%s, %s, %s)" % [p, b, shrink]
				if not a:
					seen.unseen = seen.get("unseen", 0) + 1
			4:
				var to := p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 24.0)
				var side := rng.randi_range(-1, 1)
				var a := grid.route_point(p, to, r, PoolArena.ROUTE_CLEARANCE, PoolArena.ROUTE_MARGIN, side)
				if a != plain.route_point(p, to, r, PoolArena.ROUTE_CLEARANCE, PoolArena.ROUTE_MARGIN, side):
					return "route_point(%s, %s, %s, side %d)" % [p, to, r, side]
				if a != to:
					seen.detours = seen.get("detours", 0) + 1
			5:
				var slack := rng.randf_range(0.0, 0.3)
				var facing := NAN if rng.randf() < 0.5 else rng.randf_range(-PI, PI)
				var bearing := rng.randf_range(0.2, PI)
				var a := grid.rock_contact(p, r, slack, facing, bearing)
				if a != plain.rock_contact(p, r, slack, facing, bearing):
					return "rock_contact(%s, %s, %s, %s, %s)" % [p, r, slack, facing, bearing]
				if not a.is_empty():
					seen.contacts = seen.get("contacts", 0) + 1
			6:
				if not grid.rocks_near(p, r):
					seen.ruled_out = seen.get("ruled_out", 0) + 1
					for k in plain._centers.size():
						if p.distance_to(plain._centers[k]) < plain._radii[k] + r:
							return "rocks_near(%s, %s) ruled out %s" % [p, r, plain.rocks[k].id]
	return ""


func test_ten_thousand_mixed_queries_match_the_brute_force_reference() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var arenas := _pair(_layout(rng, -3, 2, 30))
	for arena in arenas:
		arena.set_origin(64.0, -32.0)
	var seen := {}
	var diff := _compare(arenas[0], arenas[1], rng, 10000, -3, 2, seen)
	check(diff.is_empty(), "first difference: %s" % diff)
	for what in ["blocked", "pushed", "unseen", "detours", "contacts", "ruled_out"]:
		check(int(seen.get(what, 0)) > 50, "the queries met %s (%d)" % [what, int(seen.get(what, 0))])


func test_slow_a_hundred_thousand_mixed_queries_match_the_brute_force_reference() -> void:
	for seed_value in [32, 33, 34]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var arenas := _pair(_layout(rng, -3, 2, 30))
		var seen := {}
		var diff := _compare(arenas[0], arenas[1], rng, 100000, -3, 2, seen)
		check(diff.is_empty(), "seed %d, first difference: %s" % [seed_value, diff])


func test_route_point_ties_resolve_as_the_reference() -> void:
	# Every key round the route is loaded, so candidates come from the row walk.
	var layout := {}
	for y in range(-2, 4):
		for x in range(-2, 4):
			var none: Array[Dictionary] = []
			layout[Vector2i(x, y)] = none
	var a: Array[Dictionary] = [{"id": "a", "x": 33.0, "y": 31.0, "r": 1.5}]
	var b: Array[Dictionary] = [{"id": "b", "x": 31.0, "y": 33.0, "r": 1.5}]
	layout[Vector2i(1, 0)] = a
	layout[Vector2i(0, 1)] = b
	var arenas := _pair(layout)
	var only_a := ChunkArena.create_endless()
	only_a.rock_grid = false
	only_a.add_chunk(Vector2i(1, 0), a)
	var from := Vector2.ZERO
	var to := Vector2(64.0, 64.0)
	var dir := to.normalized()
	check_eq(Vector2(33.0, 31.0).dot(dir), Vector2(31.0, 33.0).dot(dir), "the two rocks tie along the line")
	var expected := only_a.route_point(from, to, BODY_R)
	check(expected != to, "rock a alone is in the way")
	check_eq(arenas[1].route_point(from, to, BODY_R), expected, "the reference goes round a, first in (y, x) order")
	check_eq(arenas[0].route_point(from, to, BODY_R), expected, "so does the grid")


## A collider blocks a route while its centre projects up to its own radius past the target, so its
## centre can lie farther out than the route's box grown by the blocking distance: here diagonally
## past the target, across a chunk edge the grown box does not reach.
func test_route_point_sees_a_blocker_just_past_its_target_across_a_chunk_edge() -> void:
	var from := Vector2(0.0, 12.95)
	var dir := Vector2.from_angle(PI / 4.0)
	var to := from + dir * 20.0
	var c := from + dir * 23.5 + dir.orthogonal() * -4.4
	check(c.y >= 32.0 and maxf(from.y, to.y) + ChunkArena.MAX_COLLIDER_R + BODY_R + PoolArena.ROUTE_CLEARANCE + PoolArena.GRID_SLACK < 32.0,
		"the collider lies in the next chunk row, beyond the grown box of the route")
	var none: Array[Dictionary] = []
	var blocker: Array[Dictionary] = [{"id": "past", "x": float(c.x), "y": float(c.y), "r": ChunkArena.MAX_COLLIDER_R}]
	var arenas := _pair({Vector2i(0, 0): none, Vector2i(0, 1): blocker, Vector2i(1, 0): none, Vector2i(1, 1): none})
	var reference := arenas[1].route_point(from, to, BODY_R)
	check(reference != to, "the reference goes round it")
	check_eq(arenas[0].route_point(from, to, BODY_R), reference, "and so does the grid")


func test_set_origin_at_100_km_gives_the_same_results_as_at_the_origin() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 35
	var big := Vector2i(100000, -100000)
	var near := ChunkArena.create_endless()
	var far_first := ChunkArena.create_endless()    # origin set, then the chunks added
	var far_after := ChunkArena.create_endless()    # chunks added at origin 0, then the origin set
	far_first.set_origin(big.x, big.y)
	var by_key := {}
	for i in 60:
		# Centres on the 2^-10 grid, so O + d is exact in float64.
		var x := roundf(rng.randf_range(-48.0, 48.0) * 1024.0) / 1024.0
		var y := roundf(rng.randf_range(-48.0, 48.0) * 1024.0) / 1024.0
		var key := Vector2i(floori(x / 32.0), floori(y / 32.0))
		if not by_key.has(key):
			var list: Array[Dictionary] = []
			by_key[key] = list
		by_key[key].append({"id": "c%02d" % i, "x": x, "y": y, "r": roundf(rng.randf_range(0.6, 4.0) * 1024.0) / 1024.0})
	for key: Vector2i in by_key:
		var shifted: Array[Dictionary] = []
		for c: Dictionary in by_key[key]:
			shifted.append({"id": c.id, "x": c.x + big.x, "y": c.y + big.y, "r": c.r})
		near.add_chunk(key, by_key[key])
		far_first.add_chunk(key + Vector2i(big.x / 32, big.y / 32), shifted)
		far_after.add_chunk(key + Vector2i(big.x / 32, big.y / 32), shifted)
	far_after.set_origin(big.x, big.y)
	check_eq(far_first._centers, near._centers, "local centres 100 km out equal those at home (set first)")
	check_eq(far_after._centers, near._centers, "and with the origin set after the chunks")
	var bad := 0
	for i in 2000:
		var p := Vector2(roundf(rng.randf_range(-52.0, 52.0) * 1024.0) / 1024.0, roundf(rng.randf_range(-52.0, 52.0) * 1024.0) / 1024.0)
		var q := p + Vector2(roundf(rng.randf_range(-16.0, 16.0) * 1024.0) / 1024.0, roundf(rng.randf_range(-16.0, 16.0) * 1024.0) / 1024.0)
		var r := roundf(rng.randf_range(0.0, 1.6) * 1024.0) / 1024.0
		for far: ChunkArena in [far_first, far_after]:
			var ma := Locomotion.MotionState.new(p)
			var mb := Locomotion.MotionState.new(p)
			ma.velocity = (q - p) * 4.0
			mb.velocity = ma.velocity
			near.move(ma, r, DT)
			far.move(mb, r, DT)
			if near.is_clear(p, r) != far.is_clear(p, r) or near.rocks_near(p, r) != far.rocks_near(p, r) \
					or near.segment_clear(p, q) != far.segment_clear(p, q) or near.route_point(p, q, r) != far.route_point(p, q, r) \
					or near.rock_contact(p, r, 0.2) != far.rock_contact(p, r, 0.2) or ma.position != mb.position or ma.velocity != mb.velocity:
				bad += 1
	check_eq(bad, 0, "queries that differ 100 km out")
	# Moving the frame back and forth recomputes from the absolute centres: nothing accumulates.
	for i in 500:
		far_after.set_origin(big.x + 32.0 * (i % 7), big.y - 96.0 * (i % 3))
	far_after.set_origin(big.x, big.y)
	check_eq(far_after._centers, near._centers, "after 500 rebases")
	check_eq(far_after.rocks[0].center, far_after._centers[0], "rocks[k].center follows")


## The near grid a full re-mark gives: per cell, how many of all the loaded colliders reach it.
static func _re_mark(arena: ChunkArena, key: Vector2i) -> PackedInt32Array:
	var n := ChunkArena.CHUNK_GRID_N
	var cell := arena.chunk_tm / n
	var out := PackedInt32Array()
	out.resize(n * n)
	out.fill(0)
	for k in arena.chunk_keys():
		for c: Dictionary in arena._chunk_colliders[k]:
			var reach: float = c.r + PoolArena.GRID_BODY_R + PoolArena.GRID_SLACK
			for gy in n:
				var y0 := key.y * arena.chunk_tm + gy * cell
				var dy := maxf(maxf(y0 - c.y, c.y - (y0 + cell)), 0.0)
				if dy >= reach:
					continue   # no cell of this row is in reach (saves time only)
				for gx in n:
					var x0 := key.x * arena.chunk_tm + gx * cell
					var dx := maxf(maxf(x0 - c.x, c.x - (x0 + cell)), 0.0)
					if dx * dx + dy * dy < reach * reach:
						out[gy * n + gx] += 1
	return out


func test_incremental_grids_equal_a_full_re_mark_after_every_add_and_remove() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 36
	var arena := ChunkArena.create_endless()
	var nonzero := 0
	for step in 200:
		var key := Vector2i(rng.randi_range(-3, 2), rng.randi_range(-3, 2))
		if arena.has_chunk(key):
			arena.remove_chunk(key)
		else:
			var list: Array[Dictionary] = []
			for i in rng.randi_range(0, 8):
				list.append(_collider(rng, key, "s%d_%d" % [step, i]))
			arena.add_chunk(key, list)
		# Only the changed chunk and its neighbours can change; every grid is checked every 10 steps.
		for k in arena.chunk_keys():
			if step % 10 != 9 and (absi(k.x - key.x) > 1 or absi(k.y - key.y) > 1):
				continue
			var want := _re_mark(arena, k)
			if arena._grids[k] != want:
				check(false, "step %d: the grid of %s differs from a full re-mark" % [step, k])
				return
			nonzero += want.size() - want.count(0)
	check(nonzero > 1000, "the grids were exercised (%d marked cells seen)" % nonzero)


func test_settle_falls_back_to_the_reference_when_a_body_is_pushed_out_of_its_box() -> void:
	var colliders: Array[Dictionary] = [{"id": "big", "x": 16.0, "y": 16.0, "r": 4.0},
		{"id": "east", "x": 22.6, "y": 16.4, "r": 1.0}, {"id": "south", "x": 16.3, "y": 22.7, "r": 1.2}]
	var arenas := _pair({Vector2i(0, 0): colliders})
	for angle in [0.0, 1.6, 3.0, 4.6]:
		# 2.5 tm deep in the big collider: a push of 2.5 tm, past SETTLE_TRAVEL_TM.
		var p := Vector2(16.0, 16.0) + Vector2.from_angle(angle) * (4.0 + BODY_R - 2.5)
		var a := Locomotion.MotionState.new(p)
		var b := Locomotion.MotionState.new(p)
		a.velocity = Vector2(-1.0, 0.5)
		b.velocity = a.velocity
		var before := arenas[0].settle_fallbacks
		arenas[0].settle(a, BODY_R)
		arenas[1].settle(b, BODY_R)
		check_eq(arenas[0].settle_fallbacks, before + 1, "angle %.1f: settle fell back once" % angle)
		check(a.position == b.position and a.velocity == b.velocity, "angle %.1f: %s %s equals the reference %s %s" % [
			angle, a.position, a.velocity, b.position, b.velocity])
		check(arenas[1].is_clear(a.position, BODY_R - 1e-3), "angle %.1f: out of every collider" % angle)
	var shallow := Locomotion.MotionState.new(Vector2(16.0, 16.0) + Vector2(4.0 + BODY_R - 0.3, 0.0))
	var before := arenas[0].settle_fallbacks
	arenas[0].settle(shallow, BODY_R)
	check_eq(arenas[0].settle_fallbacks, before, "a shallow push stays on the candidates")


func test_the_canonical_arrays_follow_key_then_list_order() -> void:
	var arena := ChunkArena.create_endless()
	for key: Vector2i in [Vector2i(1, 1), Vector2i(0, 0), Vector2i(-1, 1), Vector2i(2, 0), Vector2i(0, -1)]:
		var list: Array[Dictionary] = []
		for i in 3:
			list.append({"id": "k%d_%d_%d" % [key.x, key.y, i], "x": key.x * 32.0 + 4.0 + 8.0 * i, "y": key.y * 32.0 + 3.0 + i, "r": 1.0})
		arena.add_chunk(key, list)
	var want: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 0), Vector2i(2, 0), Vector2i(-1, 1), Vector2i(1, 1)]
	check_eq(arena.chunk_keys(), want, "keys sorted by (y, x)")
	var ids := PackedStringArray()
	for key in want:
		for i in 3:
			ids.append("k%d_%d_%d" % [key.x, key.y, i])
	check_eq(_ids(arena), ids, "colliders in key order, then list order")
	arena.remove_chunk(Vector2i(2, 0))
	ids = ids.slice(0, 6) + ids.slice(9)
	check_eq(_ids(arena), ids, "after a remove")
	check_eq(arena._centers.size(), 12, "centres follow")
	check_eq(arena._radii.size(), 12, "radii follow")
	for k in arena.rocks.size():
		check_eq(arena.rocks[k].center, arena._centers[k], "%s centre" % arena.rocks[k].id)
	check(not arena.has_chunk(Vector2i(2, 0)) and arena.has_chunk(Vector2i(1, 1)), "has_chunk")
	var shells: Array[Dictionary] = [{"id": "s1", "center": Vector2(40.0, 2.0), "radius": 1.0},
		{"id": "s0", "center": Vector2(-3.0, -5.0), "radius": 1.0}, {"id": "s2", "center": Vector2(-30.0, 40.0), "radius": 1.5},
		{"id": "s3", "center": Vector2(-20.0, -10.0), "radius": 1.0}]
	var from_shells := ChunkArena.from_shells(shells)
	check_eq(_ids(from_shells), PackedStringArray(["s0", "s3", "s1", "s2"]), "from_shells: chunks in (y, x) order, input order within one")
	check(not from_shells.is_clear(Vector2(-3.0, -5.0), 0.5) and from_shells.is_clear(Vector2(10.0, 10.0), 0.5), "and collides")


static func _ids(arena: ChunkArena) -> PackedStringArray:
	var out := PackedStringArray()
	for rock in arena.rocks:
		out.append(rock.id)
	return out


func test_add_chunk_refuses_bad_colliders_and_duplicate_keys() -> void:
	var arena := ChunkArena.create_endless()
	var bad: Array[Dictionary] = [{"id": "big", "x": 5.0, "y": 5.0, "r": 4.5}, {"id": "flat", "x": 6.0, "y": 6.0, "r": 0.0},
		{"id": "nan", "x": NAN, "y": 6.0, "r": 1.0}, {"id": "out", "x": 33.0, "y": 6.0, "r": 1.0},
		{"id": "ok", "x": 10.0, "y": 10.0, "r": 4.0}]
	arena.add_chunk(Vector2i(0, 0), bad)
	check_eq(_ids(arena), PackedStringArray(["ok"]), "only the good collider")
	var again: Array[Dictionary] = [{"id": "twice", "x": 20.0, "y": 20.0, "r": 1.0}]
	arena.add_chunk(Vector2i(0, 0), again)
	check_eq(_ids(arena), PackedStringArray(["ok"]), "a key added twice changes nothing")
	check_eq(arena.chunk_keys().size(), 1, "one key")


func test_wall_depth_is_zero_and_add_rock_adds_nothing() -> void:
	var arena := ChunkArena.create_endless()
	check_eq(arena.wall_depth(Vector2(1e6, -1e6)), 0.0, "no walls")
	arena.add_rock("r", Vector2.ZERO, 1.0)
	check_eq(arena.rocks.size(), 0, "add_rock refuses")
	check_eq(arena._centers.size(), 0, "nothing in the arrays")
	check(arena.is_clear(Vector2(1e5, 3.0), 0.5), "an empty world is clear everywhere")
	var m := Locomotion.MotionState.new(Vector2(5000.0, 0.0))
	m.velocity = Vector2(6.0, 0.0)
	check_near(arena.move(m, BODY_R, DT), 0.1, 1e-3, "no wall slows a body far out")
