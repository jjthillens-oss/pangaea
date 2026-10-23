extends TestCase
## The off-screen threat arrows (M1 step 3, plan section 15; never cut): where an arrow goes on the
## screen edge for a creature off screen, which creatures get one, what each arrow row copies from
## its brain and the shapes it is drawn with. The HUD drawing them from the live pool camera (its
## own refresh, the drawn record, a telling arrow) is covered by the scene smoke, because these
## tests run before the scene tree does.

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


func test_an_arrow_row_copies_its_brains_tell_and_glyph() -> void:
	var player := CreatureField.PLAYER_ID
	var tell := _memory(CreatureBrain.ATTACK, CreatureBrain.TELL, player)
	tell.behavior = CreatureBrain.TERRITORIAL
	var row := ThreatIndicators.indicator_for("c_3", "rammer", tell, Vector2(960, 1010), Vector2(0, 470))
	check(row.id == "c_3" and row.species == "rammer" and row.glyph == "star" and row.position == Vector2(960, 1010),
		"the row names the creature, its glyph and its place (%s)" % row)
	check(row.direction.is_equal_approx(Vector2.DOWN), "its direction is a unit vector (%s)" % row.direction)
	check(row.telling, "a tell's arrow is telling")
	var watch := _memory(CreatureBrain.REST, CreatureBrain.WATCH, player)
	watch.behavior = CreatureBrain.AMBUSH
	var calm := ThreatIndicators.indicator_for("c_1", "ambush_hunter", watch, Vector2(70, 540), Vector2.ZERO)
	check(not calm.telling and not calm.noticing and calm.glyph == "jaw", "a watching hunter's arrow is not telling or noticing and shows the jaw")
	check(calm.direction == Vector2.DOWN, "a zero direction falls back to down")
	check(not row.noticing, "a tell is not a notice")
	var notice := ThreatIndicators.indicator_for("c_2", "ambush_hunter", _memory(CreatureBrain.NOTICE, "", player), Vector2(960, 1010), Vector2.DOWN)
	check(notice.noticing and not notice.telling, "a creature noticing the cell has a noticing arrow")
	var wait := ThreatIndicators.indicator_for("c_4", "rammer", _memory(CreatureBrain.NOTICE, CreatureBrain.WAIT, player), Vector2(960, 1010), Vector2.DOWN)
	check(not wait.noticing, "a rammer waiting for its turn is past its notice")


## True when `rect` overlaps the disc of radius `r` around `c`.
func _hits_disc(rect: Rect2, c: Vector2, r: float) -> bool:
	return c.clamp(rect.position, rect.end).distance_to(c) < r


func _row(at: Vector2, telling: bool, noticing := false) -> Dictionary:
	return {"id": "c_1", "glyph": "jaw", "position": at, "direction": (at - RECT.get_center()).normalized(),
		"telling": telling, "noticing": noticing}


func test_only_a_telling_arrow_pulses_and_shows_its_mark_clear_of_the_badge() -> void:
	var at := Vector2(1400, INNER.end.y)
	var calm := ThreatIndicators.arrow_shape(_row(at, false), 1.0, RECT)
	check_eq(calm.radius, ThreatIndicators.BADGE_RADIUS_PX, "an arrow that is not telling never pulses")
	check(not (calm.mark as Rect2).has_area() and calm.mark_h == 0.0, "and shows no '!'")
	# Off screen the creature's own "!" is hidden, so its arrow carries the notice: a "!" with no pulse.
	var notice := ThreatIndicators.arrow_shape(_row(at, false, true), 1.0, RECT)
	check_eq(notice.radius, ThreatIndicators.BADGE_RADIUS_PX, "a noticing arrow does not pulse")
	check((notice.mark as Rect2).has_area() and notice.mark_h == ThreatIndicators.MARK_PX, "but shows its '!' at rest size")
	var rest := ThreatIndicators.arrow_shape(_row(at, true), 0.0, RECT)
	var top := ThreatIndicators.arrow_shape(_row(at, true), 1.0, RECT)
	check_eq(rest.radius, ThreatIndicators.BADGE_RADIUS_PX, "a telling arrow at the bottom of its pulse")
	check_near(top.radius, ThreatIndicators.BADGE_RADIUS_PX * (1.0 + ThreatIndicators.PULSE_GROW), 1e-4, "grows at the top of it")
	# Around the inset edge, at both ends of the pulse: the mark is on screen and clear of the badge.
	var bad := PackedStringArray()
	for i in 72:
		var p := INNER.get_center() + Vector2.from_angle(TAU * i / 72.0) * 3000.0
		var edge := ThreatIndicators.edge_point(RECT, p, false, MARGIN)
		for pulse in [0.0, 1.0]:
			var shape := ThreatIndicators.arrow_shape(_row(edge, true), pulse, RECT)
			var mark: Rect2 = shape.mark
			if not mark.has_area() or _hits_disc(mark, shape.center, shape.radius) or not RECT.encloses(mark) or not RECT.encloses(shape.badge):
				bad.append("%s pulse %.0f: mark %s badge %s" % [edge, pulse, mark, shape.badge])
	check(bad.is_empty(), "every telling arrow's '!' is on screen and clear of its badge: %s" % bad)


func test_the_hud_draws_the_arrows_last_and_never_hides_them() -> void:
	var hud := (load("res://game/ui/hud.tscn") as PackedScene).instantiate() as Control
	var arrows := hud.get_node_or_null("ThreatIndicators") as Control
	check(arrows is ThreatIndicators, "the HUD has the arrow layer")
	if arrows != null:
		check(arrows.visible, "visible in the scene")
		check_eq(arrows.get_index(), hud.get_child_count() - 1, "the last child, so it draws over the rest of the HUD")
		check(arrows.anchor_right == 1.0 and arrows.anchor_bottom == 1.0, "and spans the screen")
	hud.free()


func test_top_and_bottom_arrows_keep_to_their_band_with_the_mark_beside_the_badge() -> void:
	var band := ThreatIndicators.band_px()
	check_near(band, 70.0 + 30.0 * 1.25, 1e-4, "the band is the margin plus a badge at the top of its pulse")
	var bad := PackedStringArray()
	for x in range(int(INNER.position.x), int(INNER.end.x) + 1, 5):
		for y in [INNER.position.y, INNER.end.y]:
			var at := Vector2(x, y)
			for pulse in [0.0, 1.0]:
				var shape := ThreatIndicators.arrow_shape(_row(at, true), pulse, RECT)
				var reach: Rect2 = (shape.badge as Rect2).merge(shape.mark)
				var from_edge: float = RECT.end.y - reach.position.y if y > RECT.get_center().y else reach.end.y - RECT.position.y
				var mark_at: Vector2 = shape.mark_at
				var inward := mark_at.x > x if x <= RECT.get_center().x else mark_at.x < x
				if from_edge > band + 1e-3 or not RECT.encloses(reach) or absf(mark_at.y - y) > 1e-3 or not inward:
					bad.append("%s pulse %.0f: reach %s, mark at %s" % [at, pulse, reach, mark_at])
	check(bad.is_empty(), "every top and bottom arrow stays within %.1f px of its edge, its '!' beside the badge toward the middle: %s" % [band, bad.slice(0, 4)])
