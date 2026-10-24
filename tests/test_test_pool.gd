extends TestCase
## IB-03, the editor's test drive (TestPool): the working body swims a small empty dish with its own
## numbers, stays inside it, and going back leaves the editor's work as it was.

var catalog: PartCatalog
var pool: TestPool


func before_each() -> void:
	catalog = PartCatalog.load_from()
	pool = TestPool.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(pool)


func after_each() -> void:
	pool.free()


func _genome(flagella: int) -> Genome:
	var g := SaveGame.new_run(5, "test+dev").genome
	for i in flagella:
		g.add_part("flagellum", PI + 0.3 * i)
	return g


func _swim(genome: Genome, move: Vector2, ticks: int) -> float:
	pool.start(genome, Phenotype.derive(genome, catalog))
	for i in ticks:
		pool.step(move, PoolSim.DT)
	return pool.motion.position.distance_to(Vector2.ZERO)


func test_it_draws_the_working_body_at_the_centre() -> void:
	var genome := _genome(1)
	genome.add_part("spike", -PI / 2.0)
	pool.start(genome, Phenotype.derive(genome, catalog))
	check(pool.visible, "shown")
	check_eq(pool.motion.position, Vector2.ZERO, "at the centre")
	var view := pool.find_child("PlayerCell", true, false) as PlayerCellView
	var drawn := view.part_nodes().map(func(n: Node) -> String: return n.get_meta("part_type"))
	check_eq(drawn, genome.parts.map(func(p: Dictionary) -> String: return p.type), "every part drawn")


func test_the_body_swims_with_its_own_numbers() -> void:
	# A second flagellum is faster on the sea's own Locomotion, so the drive shows the tradeoff.
	var one := _swim(_genome(1), Vector2.UP, 60)
	var two := _swim(_genome(2), Vector2.UP, 60)
	check(one > 0.5, "it swims (%.2f m in a second)" % one)
	check(two > one, "a faster body goes farther (%.2f > %.2f)" % [two, one])
	check(pool.motion.velocity.length() <= pool.phenotype.speed + 1e-3,
		"never past its top speed (%.2f)" % pool.motion.velocity.length())


func test_it_stays_inside_the_dish() -> void:
	var genome := _genome(2)
	pool.start(genome, Phenotype.derive(genome, catalog))
	var widest := 0.0
	for i in 900:
		pool.step(Vector2.from_angle(0.4 + i * 0.002), PoolSim.DT)
		widest = maxf(widest, pool.motion.position.length())
	check(widest <= TestPool.RADIUS_M - TestPool.BODY_M + 1e-4, "inside the wall (%.3f)" % widest)
	check(widest > TestPool.RADIUS_M * 0.8, "and reaches it (%.3f)" % widest)


func test_back_hides_it_and_says_so() -> void:
	var genome := _genome(1)
	pool.start(genome, Phenotype.derive(genome, catalog))
	var count := [0]
	pool.left.connect(func() -> void: count[0] += 1)
	(pool.find_child("BackToEditor", true, false) as Button).pressed.emit()
	check(not pool.visible, "hidden")
	check_eq(count[0], 1, "left once")
