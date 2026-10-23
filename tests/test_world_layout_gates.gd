extends TestCase
## G15 on the shipped world (S1; docs/s1/s1-content.md 5.4, docs/s1/s1-build-plan.md B-11 and B-17):
## the density a swimmer meets and the variety of the arrangement, read from WorldGen alone (no sim)
## at size 1, over 20 seeds.
##
## Density, split as B-17 settles it: 20 straight swims of 2 km from home at 3.3 tm/s (about the
## fastest starting body, the hunter's 3.26), sampled every 0.5 s. In every 30 s some sample lies
## within 9 tm of a zone's edge, and in every 60 s some sample has a live site's home inside the view
## ring (33.9 tm). Variety, over the 32 x 32 tiles round each swim's midpoint: no tile repeats its
## edge neighbour's id, no landmark model stands within 3 tiles of itself, every region shows up in
## every square and no row or column runs three drift tiles; over the 20 squares together drift holds
## 12 to 18 % of the ordinary tiles and each region at least 10 % (B-11). One square is too small to
## hold the shares: the regions come from a smooth field, and a square's drift share runs from about
## 5 to 27 % over these seeds.

const SEEDS := 20
const START := Vector2(0.0, 9.0)        ## the spawn, abs tm
const SWIM_TM := 2000.0
const SWIM_SPEED := 3.3                 ## tm/s
const SAMPLE_S := 0.5
## The density gates: a zone's edge within ZONE_NEAR_TM at least every ZONE_WINDOW_S, a live site's
## home within the view ring at least every SITE_WINDOW_S.
const ZONE_NEAR_TM := 9.0
const ZONE_WINDOW_S := 30.0
const SITE_WINDOW_S := 60.0
## A zone's centre counts only within ZONE_NEAR_TM + its radius (at most 8), a site's within the view
## ring, so a sample reads the chunks whose squares come within the larger of the two.
const MAX_ZONE_R := 8.0
## The variety square round each swim's midpoint, in tiles.
const SQUARE_TILES := 32
const MODEL_SPACING_TILES := 3
## B-11's shares over all the squares: drift within DRIFT_SHARE, each region at least REGION_FLOOR.
const DRIFT_SHARE := Vector2(0.12, 0.18)
const REGION_FLOOR := 0.10
const REGIONS: PackedStringArray = ["sunlit", "reef", "drift"]

var species: SpeciesCatalog
var content: WorldContent
var view_tm := 0.0
var chunk_tm := 0.0
var tile_tm := 0.0
var swims: Array[Dictionary] = []


func before_each() -> void:
	if content != null:
		return
	species = SpeciesCatalog.load_from()
	content = WorldContent.load_from(WorldConfig.DEFAULT_PATH, PoolLayout.load_from(), species)
	view_tm = float(content.config.rings.view)
	chunk_tm = float(content.config.chunk_tm)
	tile_tm = float(content.config.tile_bu) * WorldConfig.bu_to_tm(1)


## Seed s's swim direction: 2 pi x unit(mix32(s, 77)).
static func heading_of(seed: int) -> Vector2:
	return Vector2.from_angle(TAU * WorldHash.unit(WorldHash.mix32(seed, 77)))


## One swim: the longest stretches (s) without a zone in reach and without a live site in view,
## counted from the start to the end, with the chunks memoised per key.
func _swim(gen: WorldGen, seed: int) -> Dictionary:
	var memo := {}
	var dir := heading_of(seed)
	var step := SWIM_SPEED * SAMPLE_S
	var samples := ceili(SWIM_TM / step) + 1
	var look := maxf(view_tm, ZONE_NEAR_TM + MAX_ZONE_R)
	var last_zone := 0.0
	var last_site := 0.0
	var zone_gap := 0.0
	var site_gap := 0.0
	var zone_at := Vector2.ZERO
	var site_at := Vector2.ZERO
	for k in samples:
		var t := k * SAMPLE_S
		var p := START + dir * (k * step)
		var near_zone := false
		var near_site := false
		for cy in range(floori((p.y - look) / chunk_tm), floori((p.y + look) / chunk_tm) + 1):
			for cx in range(floori((p.x - look) / chunk_tm), floori((p.x + look) / chunk_tm) + 1):
				var key := Vector2i(cx, cy)
				if not memo.has(key):
					memo[key] = gen.chunk(1, cx, cy)
				var c: WorldChunk = memo[key]
				if not near_zone:
					for z in c.zones:
						if p.distance_to(Vector2(z.x, z.y)) - float(z.radius) <= ZONE_NEAR_TM:
							near_zone = true
							break
				if not near_site:
					for s in c.sites:
						if p.distance_to(Vector2(s.x, s.y)) <= view_tm:
							near_site = true
							break
		if near_zone or k == samples - 1:
			if t - last_zone > zone_gap:
				zone_gap = t - last_zone
				zone_at = p
			last_zone = t
		if near_site or k == samples - 1:
			if t - last_site > site_gap:
				site_gap = t - last_site
				site_at = p
			last_site = t
	return {"zone_gap": zone_gap, "zone_at": zone_at, "site_gap": site_gap, "site_at": site_at, "chunks": memo.size()}


## The 20 swims, run once for both density tests.
func _swims() -> Array[Dictionary]:
	if swims.is_empty():
		for seed in range(1, SEEDS + 1):
			swims.append(_swim(WorldGen.create(content, species, seed), seed))
	return swims


## Seed s's variety square: the tile coordinates round the swim's midpoint.
func _square(seed: int) -> Rect2i:
	var mid := START + heading_of(seed) * (SWIM_TM / 2.0)
	var m := Vector2i(floori(mid.x / tile_tm), floori(mid.y / tile_tm))
	return Rect2i(m - Vector2i(SQUARE_TILES / 2, SQUARE_TILES / 2), Vector2i(SQUARE_TILES, SQUARE_TILES))


static func _ordinary(info: Dictionary) -> bool:
	return info.region != WorldGen.HOME and info.region != WorldGen.RARE


# ---- Slow ----

## B-17's first half: a zone's edge within 9 tm at least every 30 s.
func test_slow_a_straight_swim_never_goes_30_s_without_a_zone_in_reach() -> void:
	var worst := 0.0
	var worst_at := ""
	var chunks := 0
	var all := _swims()
	for i in SEEDS:
		var r: Dictionary = all[i]
		chunks += int(r.chunks)
		check(float(r.zone_gap) <= ZONE_WINDOW_S, "seed %d: %.1f s without a zone within %.0f tm, ending at %s" % [
			i + 1, r.zone_gap, ZONE_NEAR_TM, r.zone_at])
		if float(r.zone_gap) > worst:
			worst = r.zone_gap
			worst_at = "seed %d at %s" % [i + 1, r.zone_at]
	check(chunks > SEEDS * 100, "the swims read the world (%d chunks)" % chunks)
	print("test-layout-gates: longest stretch without a zone in reach %.1f s (%s)" % [worst, worst_at])


## B-17's second half: a live site's home in the view ring at least every 60 s.
func test_slow_a_straight_swim_passes_a_live_site_every_minute() -> void:
	var worst := 0.0
	var worst_at := ""
	var all := _swims()
	for i in SEEDS:
		var r: Dictionary = all[i]
		check(float(r.site_gap) <= SITE_WINDOW_S, "seed %d: %.1f s without a live site in view, ending at %s" % [
			i + 1, r.site_gap, r.site_at])
		if float(r.site_gap) > worst:
			worst = r.site_gap
			worst_at = "seed %d at %s" % [i + 1, r.site_at]
	print("test-layout-gates: longest stretch without a live site in view %.1f s (%s)" % [worst, worst_at])


func test_slow_no_tile_repeats_its_edge_neighbour() -> void:
	var pairs := 0
	for seed in range(1, SEEDS + 1):
		var gen := WorldGen.create(content, species, seed)
		var sq := _square(seed)
		for ty in range(sq.position.y, sq.end.y):
			for tx in range(sq.position.x, sq.end.x):
				var a := gen.tile_info(0, tx, ty)
				if not _ordinary(a):
					continue
				for d in [Vector2i(1, 0), Vector2i(0, 1)]:
					var b := gen.tile_info(0, tx + d.x, ty + d.y)
					if _ordinary(b):
						pairs += 1
						check(a.id != b.id, "seed %d: tiles (%d, %d) and (%d, %d) are both %s" % [seed, tx, ty, tx + d.x, ty + d.y, a.id])
	check(pairs > SEEDS * SQUARE_TILES * SQUARE_TILES, "edge pairs compared (%d)" % pairs)


func test_slow_the_same_landmark_model_is_never_within_3_tiles() -> void:
	var anchors := 0
	var nearest := 1 << 30
	for seed in range(1, SEEDS + 1):
		var gen := WorldGen.create(content, species, seed)
		var sq := _square(seed)
		var by_model := {}
		for ly in range(WorldGen.fdiv(sq.position.y, 2), WorldGen.fdiv(sq.end.y - 1, 2) + 1):
			for lx in range(WorldGen.fdiv(sq.position.x, 2), WorldGen.fdiv(sq.end.x - 1, 2) + 1):
				var lm := gen.landmark_of_cell(0, lx, ly)
				if lm.is_empty():
					continue
				anchors += 1
				if not by_model.has(lm.model):
					by_model[lm.model] = []
				by_model[lm.model].append(lm.tile)
		for model in by_model:
			var at: Array = by_model[model]
			for i in at.size():
				for j in i:
					var d := maxi(absi(at[i].x - at[j].x), absi(at[i].y - at[j].y))
					nearest = mini(nearest, d)
					check(d >= MODEL_SPACING_TILES, "seed %d: %s at tiles %s and %s, %d apart" % [seed, model, at[i], at[j], d])
	check(anchors > SEEDS * 100, "anchors placed (%d)" % anchors)
	print("test-layout-gates: %d anchors; the same model stands at least %d tiles apart" % [anchors, nearest])


## B-11: the coordinate drift rule keeps drift at 12 to 18 % and every region at 10 % or more, and no
## row or column runs three drift tiles.
func test_slow_every_region_shows_up_and_drift_never_runs_three() -> void:
	var totals := {"sunlit": 0, "reef": 0, "drift": 0}
	var least := {"sunlit": 1.0, "reef": 1.0, "drift": 1.0}
	var most := {"sunlit": 0.0, "reef": 0.0, "drift": 0.0}
	for seed in range(1, SEEDS + 1):
		var gen := WorldGen.create(content, species, seed)
		var sq := _square(seed)
		var counts := {"sunlit": 0, "reef": 0, "drift": 0}
		var ordinary := 0
		for ty in range(sq.position.y, sq.end.y):
			var run := 0
			for tx in range(sq.position.x, sq.end.x):
				var info := gen.tile_info(0, tx, ty)
				if _ordinary(info):
					ordinary += 1
					counts[info.region] += 1
				run = run + 1 if info.region == "drift" else 0
				check(run < 3, "seed %d: three drift tiles run in row %d to (%d, %d)" % [seed, ty, tx, ty])
		for tx in range(sq.position.x, sq.end.x):
			var run := 0
			for ty in range(sq.position.y, sq.end.y):
				run = run + 1 if gen.tile_info(0, tx, ty).region == "drift" else 0
				check(run < 3, "seed %d: three drift tiles run in column %d to (%d, %d)" % [seed, tx, tx, ty])
		for region in REGIONS:
			check(counts[region] > 0, "seed %d: %s shows up in the square round %s" % [seed, region, sq.get_center()])
			var share := float(counts[region]) / maxf(1.0, ordinary)
			least[region] = minf(least[region], share)
			most[region] = maxf(most[region], share)
			totals[region] += counts[region]
	var all := float(totals.sunlit + totals.reef + totals.drift)
	check(all > 0.9 * SEEDS * SQUARE_TILES * SQUARE_TILES, "ordinary tiles counted (%d)" % all)
	var drift: float = totals.drift / all
	check(drift >= DRIFT_SHARE.x and drift <= DRIFT_SHARE.y, "drift holds %.1f %% of the ordinary tiles, within [%.0f, %.0f] %%" % [
		100.0 * drift, 100.0 * DRIFT_SHARE.x, 100.0 * DRIFT_SHARE.y])
	for region in REGIONS:
		check(totals[region] / all >= REGION_FLOOR, "%s holds %.1f %% of the ordinary tiles" % [region, 100.0 * totals[region] / all])
	var spread := PackedStringArray()
	for region in REGIONS:
		spread.append("%s %.1f to %.1f %%" % [region, 100.0 * least[region], 100.0 * most[region]])
	print("test-layout-gates: region shares sunlit %.1f %%, reef %.1f %%, drift %.1f %%; per square %s" % [
		100.0 * totals.sunlit / all, 100.0 * totals.reef / all, 100.0 * drift, ", ".join(spread)])
