extends TestCase
## S4.4, the cell editor (CellEditor over EditorSession; docs/s4/s4-plan.md): the next generation is
## built from a working copy, its numbers shown before and after, and committed through Lineage.

var catalog: PartCatalog
var save: SaveGame
var editor: CellEditor
var closes: Array = []


func before_each() -> void:
	catalog = PartCatalog.load_from()
	save = SaveGame.new_run(99, "test+dev")
	save.genome.add_part("mouth_filter", 0.0)
	save.genome.add_part("flagellum", PI)
	save.adaptation_points = 100
	editor = CellEditor.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(editor)
	closes = []
	editor.closed.connect(func(committed: bool) -> void: closes.append(committed))


func after_each() -> void:
	editor.free()


func _state(energy_share := 1.0) -> ActorState:
	var s := ActorState.fresh(Phenotype.derive(save.genome, catalog))
	s.energy = s.energy_capacity * energy_share
	return s


func _button(name: String) -> Button:
	return editor.find_child(name, true, false) as Button


func test_the_palette_offers_the_editor_parts_with_their_costs() -> void:
	editor.open(save, catalog, _state())
	for type_id: String in catalog.parts:
		var b := _button("Add_" + type_id)
		if catalog.in_editor(type_id):
			check(b != null and b.text.contains(str(catalog.cost_of(type_id))), "%s with its cost" % type_id)
		else:
			check(b == null, "%s is not offered" % type_id)


func test_the_palette_groups_the_parts_by_category_each_with_its_model_as_the_icon() -> void:
	# Spore's palette: the parts in groups (mouths, movement, ...), each tile the part itself.
	var groups := CellEditor.palette_groups(catalog)
	var headings := groups.map(func(g: Array) -> String: return g[0])
	var order := CellEditor.CATEGORIES.map(func(c: Array) -> String: return c[1])
	check_eq(headings, order.filter(func(h: String) -> bool: return headings.has(h)), "groups in the set order")
	var seen := []
	for group: Array in groups:
		var category := ""
		for c: Array in CellEditor.CATEGORIES:
			if c[1] == group[0]:
				category = c[0]
		for type_id: String in group[1]:
			check_eq(catalog.category_of(type_id), category, "%s under %s" % [type_id, group[0]])
			seen.append(type_id)
	var offered := catalog.parts.keys().filter(func(t: String) -> bool: return catalog.in_editor(t))
	seen.sort()
	offered.sort()
	check_eq(seen, offered, "every offered part once")
	for type_id: String in offered:
		var b := _button("Add_" + type_id)
		var icon := editor.find_child("Icon_" + type_id, false, false) as PartIcon
		check(icon != null and icon.has_model(), "%s has its model drawn for the icon" % type_id)
		check(b != null and icon != null and b.icon == icon.get_texture(), "%s shows it" % type_id)


func test_a_part_icon_frames_the_whole_part() -> void:
	for type_id: String in PlayerCellView.PART_SCENES:
		var icon := PartIcon.new(type_id)
		var bounds := PartIcon.bounds_of(icon.get_node("Model"))
		var camera := icon.find_children("*", "Camera3D", false, false)[0] as Camera3D
		check(bounds.size.length() > 0.0, "%s has a size" % type_id)
		check(camera.size >= bounds.size[bounds.get_longest_axis_index()], "%s fits the view" % type_id)
		check(camera.transform.basis.z.dot(camera.position - bounds.get_center()) > 0.0, "%s faces the camera" % type_id)
		icon.free()


func test_an_added_part_shows_its_cost_and_the_numbers_it_changes() -> void:
	editor.open(save, catalog, _state())
	var result := editor.add("cilia")
	check(result.ok, "added: %s" % [result])
	check(editor.selected != "", "and selected")
	var lines := {}
	for line in editor.stat_lines():
		lines[line[0]] = line
	check_eq(lines["Turning"][3], true, "turning is better (%s)" % [lines["Turning"]])
	check_eq(lines["Mass"][3], false, "mass is worse (%s)" % [lines["Mass"]])
	check_eq(lines["Health"][3], null, "health is unchanged")
	var points := editor.find_children("*", "Label", true, false).filter(
		func(l: Label) -> bool: return l.text.contains("this body costs"))
	check(not points.is_empty() and points[0].text.contains("costs %d" % catalog.cost_of("cilia")), "the cost line")
	check(not _button("Mate").disabled, "affordable")
	editor.undo()
	check_eq(editor.session.working.parts.size(), 2, "undo takes it off")
	editor.redo()
	check_eq(editor.session.working.parts.size(), 3, "redo puts it back")


func test_the_eats_line_previews_what_the_new_body_can_feed_on() -> void:
	# Bible section 5: the editor previews feeding with speed, turning, defense and energy.
	editor.open(save, catalog, _state())
	var eats := func() -> Array:
		return editor.stat_lines().filter(func(l: Array) -> bool: return l[0] == "Eats")[0]
	check_eq(eats.call(), ["Eats", "plants", "plants", null], "a filter mouth eats plants")
	var jaw: Dictionary = editor.add("mouth_jaw")
	check(jaw.ok, "a jaw added: %s" % [jaw])
	check_eq(eats.call(), ["Eats", "plants", "plants and meat", true], "a jaw adds meat")
	for part in editor.session.working.parts:
		if part.type == "mouth_filter":
			editor.selected = part.id
	check(editor.remove_selected().ok, "the filter taken off")
	check_eq(eats.call(), ["Eats", "plants", "meat", null], "a trade is neither better nor worse")
	check_eq(CellEditor.eats_text(PackedStringArray()), "nothing", "no mouth eats nothing")


func test_a_body_a_hunter_can_catch_is_allowed_with_a_warning() -> void:
	# Rule 3 holds for the starting bodies only; a heavy edit may be slower than a chase. The editor
	# allows the trade (Joshua's size and strength tradeoffs) and says so.
	var speed := Phenotype.derive(save.genome, catalog).speed
	editor.open(save, catalog, _state(), {"speed": speed - 0.05, "name": "ambush hunter"})
	var warning := editor.find_child("ChaseWarning", true, false) as Label
	check_eq(warning.text, "", "the body as it is outswims the chase (%.2f)" % speed)
	check(editor.add("spike").ok, "a spike added")
	check(editor.session.preview().phenotype.speed < speed - 0.05, "and it is slower now")
	check(warning.text.begins_with("The ambush hunter can catch this body"), "warned: %s" % warning.text)
	check(not editor.find_child("Mate", true, false).disabled, "but Mate is still allowed")
	editor.undo()
	check_eq(warning.text, "", "undone, the warning goes")
	editor.chase = {}
	check_eq(editor.chase_warning(0.1), "", "nothing chasing here, no warning")


func test_parts_go_where_they_fit_and_move_round_the_rim() -> void:
	editor.open(save, catalog, _state())
	check_eq(editor.free_angle("mouth_jaw"), 0.0, "a mouth at the front")
	var at_side := editor.free_angle("flagellum")
	check(absf(at_side) > 0.5 and absf(at_side) < PI - 0.5, "a second tail goes in a gap, the back is taken (%.2f)" % at_side)
	editor.add("eye_spot")
	var part: Dictionary = editor.session.working.parts[-1]
	check(absf(absf(float(part.angle)) - PI / 2.0) < 0.01, "an eye in the widest gap, at a side (%.2f)" % part.angle)
	check(editor.move_selected(1.0).ok, "moved")
	check(absf(float(editor.session.working.parts[-1].angle) - 1.0) < 1e-6, "to the angle")
	check(editor.resize_selected(CellEditor.SCALE_STEP).ok, "bigger")
	check(editor.mirror_selected().ok, "mirrored")
	check_eq(editor.session.working.parts.size(), 4, "a mirrored copy")
	var rim := editor.find_children("*", "Control", true, false).filter(func(c: Control) -> bool: return c is CellEditor.RimView)
	check_eq(rim.size(), 1, "one rim view")
	var view: CellEditor.RimView = rim[0]
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)   # out of a live tree it has no laid-out size
	view.size = Vector2(300, 300)
	check(view.at(0.0).y < view.center().y, "the front is up")
	for a in [0.3, -1.2, 2.9]:
		check(absf(angle_difference(view.angle_of(view.at(a)), a)) < 1e-5, "the rim maps angle %.1f both ways" % a)


func test_mate_commits_the_next_generation_and_back_keeps_the_body() -> void:
	editor.open(save, catalog, _state())
	var parent := save.genome.genome_id
	editor.add("spike")
	editor.cancel()
	check_eq(closes, [false], "back closes without a generation")
	check_eq(save.genome.genome_id, parent, "the body is as it was")
	check_eq(save.adaptation_points, 100, "and the points")
	editor.open(save, catalog, _state())
	editor.add("spike")
	var result := editor.commit()
	check(result.ok, "mate: %s" % [result.errors])
	check_eq(closes, [false, true], "mate closes with a generation")
	check_eq(save.genome.generation, 2, "generation 2")
	check_eq(save.genome.parent_genome_id, parent, "from the parent")
	check_eq(save.adaptation_points, 100 - catalog.cost_of("spike"), "the part paid for")


func test_mate_is_refused_without_the_points_or_the_energy() -> void:
	save.adaptation_points = 10
	editor.open(save, catalog, _state())
	editor.add("spike")
	check(_button("Mate").disabled, "mate is off without the points")
	var result := editor.commit()
	check(not result.ok and closes.is_empty(), "and refused")
	save.adaptation_points = 100
	editor.open(save, catalog, _state(0.5))
	editor.add("spike")
	result = editor.commit()
	check(not result.ok and closes.is_empty(), "a hungry cell cannot mate (%s)" % [result.errors])
	check_eq(save.genome.generation, 1, "nothing born")


func test_the_editor_covers_and_dims_the_whole_screen_over_the_game() -> void:
	# Anchored before it enters the pool's UI layer: anchoring a control inside the tree keeps the
	# offsets of its zero size, and the editor then drew at its smallest over the HUD, undimmed. (The
	# runner's root is not in a live tree, so this checks the anchors rather than the drawn rect.)
	var fresh := CellEditor.new()
	check_eq([fresh.anchor_left, fresh.anchor_top, fresh.anchor_right, fresh.anchor_bottom], [0.0, 0.0, 1.0, 1.0],
		"the editor is anchored to the whole screen")
	check_eq([fresh.offset_left, fresh.offset_top, fresh.offset_right, fresh.offset_bottom], [0.0, 0.0, 0.0, 0.0],
		"edge to edge")
	var dim := fresh.get_child(0) as ColorRect
	check(dim != null and dim.anchor_right == 1.0 and dim.anchor_bottom == 1.0 and dim.offset_right == 0.0,
		"and its dim covers all of it")
	fresh.free()


func test_the_body_is_seen_from_above_under_the_rim_each_dot_on_its_part() -> void:
	# The preview looks straight down, front up and right to the right, so the rim's dot for a part at
	# any angle sits in the part's direction, and the body's front fills the rim to BODY_ON_RIM.
	var camera := editor._preview.get_node("%Camera") as Camera3D
	check_eq(camera.projection, Camera3D.PROJECTION_ORTHOGONAL, "an orthographic view")
	var rim := editor._rim
	rim.set_anchors_preset(Control.PRESET_TOP_LEFT)   # out of a live tree it has no laid-out size
	rim.size = Vector2(CellEditor.DISH_PX, CellEditor.DISH_PX)   # the dish's, as laid out
	var inverse := camera.transform.affine_inverse()
	for angle: float in [0.0, 0.7, PI / 2.0, 2.4, PI, -PI / 2.0, -1.2]:
		var seen := inverse * PartPlacement.surface_point(angle)
		# Orthographic and square: the view's x is right, its y up, and it is camera.size metres tall.
		var on_screen := rim.center() + Vector2(seen.x, -seen.y) / camera.size * rim.size.y
		var dot := rim.at(angle) - rim.center()
		check(absf(angle_difference((on_screen - rim.center()).angle(), dot.angle())) < 0.1,
			"a part at %.1f rad shows under its dot (%s vs %s)" % [angle, on_screen - rim.center(), dot])
	var front := inverse * PartPlacement.surface_point(0.0)
	check_near(absf(front.y) / camera.size * rim.size.y, CellEditor.BODY_ON_RIM * rim.radius(), 0.5,
		"the body's front at %.1f of the rim" % CellEditor.BODY_ON_RIM)


func test_test_drive_swims_the_working_body_and_comes_back_unchanged() -> void:
	editor.open(save, catalog, _state())
	editor.add("spike")
	var parts_before := editor.session.working.parts.duplicate(true)
	var saved_before := save.genome.parts.duplicate(true)
	_button("TestDrive").pressed.emit()
	var pool := editor.find_children("*", "TestPool", false, false)[0] as TestPool
	check(pool.visible, "the test dish is shown")
	var view := pool.find_child("PlayerCell", true, false) as PlayerCellView
	check_eq(view.part_nodes().size(), parts_before.size(), "with the working body")
	for i in 30:
		pool.step(Vector2.RIGHT, PoolSim.DT)
	check(pool.motion.position.x > 0.0, "and it swims")
	_button("BackToEditor").pressed.emit()
	check(not pool.visible, "back to the editor")
	check_eq(editor.session.working.parts, parts_before, "the edit is kept")
	check_eq(save.genome.parts, saved_before, "nothing saved")
	check(closes.is_empty(), "the editor is still open")
