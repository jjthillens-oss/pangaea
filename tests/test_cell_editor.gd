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
