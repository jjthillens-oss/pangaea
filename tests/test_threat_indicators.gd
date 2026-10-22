extends TestCase
## The off-screen threat arrows (M1 step 3, plan section 15; never cut): where an arrow goes on the
## screen edge for a creature off screen, and which creatures get one. The HUD drawing them from
## the live pool camera is covered by the scene smoke.

const RECT := Rect2(0.0, 0.0, 1920.0, 1080.0)
const MARGIN := 70.0
const INNER := Rect2(70.0, 70.0, 1780.0, 940.0)


func _on_inner_edge(p: Vector2) -> bool:
	var on_x := absf(p.x - INNER.position.x) < 1e-3 or absf(p.x - INNER.end.x) < 1e-3
	var on_y := absf(p.y - INNER.position.y) < 1e-3 or absf(p.y - INNER.end.y) < 1e-3
	var inside := p.x >= INNER.position.x - 1e-3 and p.x <= INNER.end.x + 1e-3 \
		and p.y >= INNER.position.y - 1e-3 and p.y <= INNER.end.y + 1e-3
	return inside and (on_x or on_y)


## The point lies on the ray from the screen's center through `toward` (within 1e-5 of the
## direction: Vector2 holds 32-bit floats).
func _on_ray(p: Vector2, toward: Vector2) -> bool:
	var c := RECT.get_center()
	var a := (p - c).normalized()
	var b := (toward - c).normalized()
	return a.dot(b) > 0.0 and absf(a.cross(b)) < 1e-5


func test_an_on_screen_point_stays_where_it_is() -> void:
	for p in [Vector2(960, 540), Vector2(100, 100), Vector2(1800, 1000), Vector2(70, 1010)]:
		check_eq(ThreatIndicators.edge_point(RECT, p, false, MARGIN), p, "on screen at %s" % p)


func test_an_off_screen_point_goes_to_the_inset_edge_along_the_ray_from_the_center() -> void:
	var cases := {
		Vector2(960, 2000): Vector2(960, 1010),      # straight below: the bottom edge
		Vector2(960, -500): Vector2(960, 70),        # straight above: the top
		Vector2(5000, 540): Vector2(1850, 540),      # right
		Vector2(-300, 540): Vector2(70, 540),        # left
	}
	for p: Vector2 in cases:
		var e := ThreatIndicators.edge_point(RECT, p, false, MARGIN)
		check(e.distance_to(cases[p]) < 1e-3, "%s goes to %s (got %s)" % [p, cases[p], e])
	for p in [Vector2(1200, 1500), Vector2(-50, 900), Vector2(3000, -2000), Vector2(1900, 1070), Vector2(-1e6, 3e5)]:
		var e := ThreatIndicators.edge_point(RECT, p, false, MARGIN)
		check(_on_inner_edge(e), "%s lands on the inset edge (got %s)" % [p, e])
		check(_on_ray(e, p), "%s lands along the ray from the center (got %s)" % [p, e])
	# A point in the margin band is on screen but would put the arrow half off it.
	var band := ThreatIndicators.edge_point(RECT, Vector2(960, 1060), false, MARGIN)
	check(band.distance_to(Vector2(960, 1010)) < 1e-3, "a point in the margin band moves in to the inset edge (got %s)" % band)


func test_a_corner_point_lands_on_the_inset_corner() -> void:
	var c := RECT.get_center()
	for corner in [INNER.position, INNER.end, Vector2(INNER.end.x, INNER.position.y), Vector2(INNER.position.x, INNER.end.y)]:
		var far: Vector2 = c + (corner - c) * 3.0
		var e := ThreatIndicators.edge_point(RECT, far, false, MARGIN)
		check(e.distance_to(corner) < 1e-3, "beyond %s lands on it (got %s)" % [corner, e])


func test_a_point_behind_the_camera_is_mirrored_and_always_goes_to_the_edge() -> void:
	var c := RECT.get_center()
	# Behind the camera a body projects mirrored through the center: one below the screen shows
	# up above it.
	var e := ThreatIndicators.edge_point(RECT, Vector2(960, 300), true, MARGIN)
	check(e.distance_to(Vector2(960, 1010)) < 1e-3, "mirrored to the bottom edge (got %s)" % e)
	var off := ThreatIndicators.edge_point(RECT, Vector2(2500, -700), true, MARGIN)
	check(_on_inner_edge(off) and _on_ray(off, c - (Vector2(2500, -700) - c)), "an off-screen projection is mirrored too (got %s)" % off)
	var dead_center := ThreatIndicators.edge_point(RECT, c, true, MARGIN)
	check(_on_inner_edge(dead_center), "straight behind still lands on an edge (got %s)" % dead_center)


func test_edge_points_are_never_nan() -> void:
	var inputs := [Vector2(NAN, 3.0), Vector2(INF, 0.0), Vector2(-INF, -INF), RECT.get_center()]
	for behind in [false, true]:
		for p: Vector2 in inputs:
			var e := ThreatIndicators.edge_point(RECT, p, behind, MARGIN)
			check(e.is_finite(), "%s (behind %s) gives a finite point (got %s)" % [p, behind, e])
	var tiny := ThreatIndicators.edge_point(Rect2(0, 0, 100, 100), Vector2(500, 50), false, 80.0)
	check(tiny.is_finite(), "a margin wider than half the screen still gives a finite point (got %s)" % tiny)


func _memory(state: String, phase: String, target: String) -> CreatureBrain.Memory:
	var mem := CreatureBrain.Memory.new()
	mem.state = state
	mem.phase = phase
	mem.target = target
	return mem


func test_an_arrow_follows_only_a_creature_whose_attention_is_on_the_cell() -> void:
	var player := CreatureField.PLAYER_ID
	var on := [
		[CreatureBrain.NOTICE, "", "a creature noticing the cell"],
		[CreatureBrain.NOTICE, CreatureBrain.WAIT, "a rammer waiting for its turn"],
		[CreatureBrain.REST, CreatureBrain.WATCH, "an ambush hunter watching it"],
		[CreatureBrain.CHASE, CreatureBrain.PURSUE, "a pursuer"],
		[CreatureBrain.CHASE, CreatureBrain.AIM, "one aiming"],
		[CreatureBrain.ATTACK, CreatureBrain.TELL, "a tell"],
		[CreatureBrain.ATTACK, CreatureBrain.STRIKE, "a strike"],
		[CreatureBrain.ATTACK, CreatureBrain.RECOVER, "a recovery"],
	]
	for row in on:
		check(ThreatIndicators.watches_player(_memory(row[0], row[1], player)), "%s gets an arrow" % row[2])
	var off := [
		[CreatureBrain.REST, CreatureBrain.LURK, player, "a lurking ambush hunter"],
		[CreatureBrain.WANDER, CreatureBrain.RETURN_HOME, player, "one swimming home"],
		[CreatureBrain.FLEE, "", player, "one fleeing the cell"],
		[CreatureBrain.FORAGE, CreatureBrain.SEEK, "", "a forager"],
		[CreatureBrain.CHASE, CreatureBrain.PURSUE, "c_4", "a chase after another creature"],
		[CreatureBrain.ATTACK, CreatureBrain.TELL, "c_2", "a tell on another creature"],
	]
	for row in off:
		check(not ThreatIndicators.watches_player(_memory(row[0], row[1], row[2])), "%s gets none" % row[3])
	check(ThreatIndicators.is_telling(_memory(CreatureBrain.ATTACK, CreatureBrain.TELL, player)), "a tell pulses")
	check(not ThreatIndicators.is_telling(_memory(CreatureBrain.ATTACK, CreatureBrain.STRIKE, player)), "a strike is past its tell")
	check(not ThreatIndicators.is_telling(_memory(CreatureBrain.CHASE, CreatureBrain.AIM, player)), "aiming is not a tell")


func test_each_threat_behavior_has_its_own_glyph() -> void:
	check_eq(ThreatIndicators.GLYPHS.get("ambush"), "jaw", "an ambush hunter shows fangs")
	check_eq(ThreatIndicators.GLYPHS.get("territorial"), "star", "a rammer shows spikes")
	var species := SpeciesCatalog.load_from()
	for id in species.species_ids():
		check(ThreatIndicators.GLYPHS.has(str(species.species[id].behavior)), "%s's behavior has a glyph" % id)
