extends RefCounted
## Test helper (not a test file): the endless world's scene, faked (S1 spine 3.16). It opens pools
## the way main does, in pool mode or on T2's FakeWorldGen with the real placement kit, and builds
## the stream's scene events (spine 3.12) by hand, so the scene's tests can drive
## PoolScene.apply_world_event and the HUD without a streaming sim. Positions are local tm, as the
## stream emits them.
##
##     const FakeEvents := preload("res://tests/fakes/fake_world_events.gd")
##     var pool := FakeEvents.open_pool(FakeEvents.endless_session())
##     ...
##     pool.free()

const POOL_SCENE := preload("res://game/scenes/pool/pool.tscn")
const FakeWorldGen := preload("res://tests/fakes/fake_world_gen.gd")
## A slot the tests never write: their sessions are built here, not started through start_new.
const SLOT := "user://test_world_scene/slot.json"
const SEED := 4242
const DT := 1.0 / 60.0


## A cell that holds still.
class Still:
	func next_intent(_sim: PoolSim) -> SimIntent:
		return SimIntent.new()


## Swims one way at full throttle.
class Straight:
	var dir := Vector2.RIGHT

	func _init(p_dir := Vector2.RIGHT) -> void:
		dir = p_dir

	func next_intent(_sim: PoolSim) -> SimIntent:
		return SimIntent.new(dir)


## A pool-mode session with the M1 creatures: a new `body` lineage of `seed_value` at the spawn,
## its sim running and nothing saved.
static func pool_session(seed_value := SEED, body := "omnivore") -> GameSession:
	var session := GameSession.new(SLOT)
	var founded := Lineage.found(seed_value, "test+dev", session.catalog, body)
	founded.save.player["position"] = PlaneSpace.to_save(session.layout.spawn)
	session.sim = PoolSim.create(founded.save, session.catalog, session.layout, session.species)
	return session


## An endless session on FakeWorldGen (a shell per chunk, a zone per 2 x 2 chunks, a rammer site
## per 4 x 4) with the M1 creatures and the shipped placement kit (whose pieces the scene draws), at
## the home spawn or at `at` (absolute am). Nothing is saved.
static func endless_session(seed_value := SEED, at := PackedFloat64Array()) -> GameSession:
	var session := GameSession.new(SLOT)
	var content: WorldContent = FakeWorldGen.fixture_content()
	content.kit = PlacementKit.load_from()
	session.world = content
	session.sim = FakeWorldGen.endless_sim(seed_value, session.catalog, session.layout, session.species, content, at)
	return session


## An endless session on the shipped world (WorldContent from WorldConfig.DEFAULT_PATH, the real
## generator, kit and home block) with the M1 creatures: a new omnivore lineage at the home spawn or
## at `at` (absolute am). Nothing is saved.
static func shipped_session(seed_value := SEED, at := PackedFloat64Array()) -> GameSession:
	var session := GameSession.new(SLOT)
	var content := WorldContent.load_from(WorldConfig.DEFAULT_PATH, session.layout, session.species)
	session.world = content
	var founded := Lineage.found(seed_value, "test+dev", session.catalog, "omnivore")
	var place: PackedFloat64Array = at if not at.is_empty() else content.home.spawn
	founded.save.player["position"] = PlaneSpace.to_save_abs(place[0], place[1])
	session.sim = PoolSim.create(founded.save, session.catalog, session.layout, session.species, content)
	return session


## The session's pool, built as main builds it but outside the tree (the test runner has none): set
## up, then readied as the tree readies it (children first), which builds it. `provider` swims for
## the cell (a still cell by default). Art's ambience, mounted during the pool's ready, is not
## readied; ready_tree(pool.get_node("Ambience")) does it. Free the pool with pool.free().
static func open_pool(session: GameSession, provider: Object = null) -> PoolScene:
	var pool: PoolScene = POOL_SCENE.instantiate()
	pool.pause_on_focus_loss = false
	pool.setup(session, provider if provider != null else Still.new())
	ready_tree(pool)
	return pool


## Readies `node` as the tree would: its children first, then itself.
static func ready_tree(node: Node) -> void:
	for child in node.get_children():
		ready_tree(child)
	node.notification(Node.NOTIFICATION_READY)


## One tick and one frame, as the engine runs them at 60 fps: the sim steps and its events route,
## then the frame draws.
static func frame(pool: PoolScene) -> void:
	pool._physics_process(DT)
	pool._process(DT)


# --- the stream's scene events (spine 3.12), local tm ---

## A chunk_loaded shell: kind "shell" (drawn by the shell layer), "landmark" (an anchor's collider,
## drawn with its anchor) or "set_piece" (a rare piece's collider, drawn by its place).
static func shell(id: String, pos: Vector2, r: float, asset: String, yaw_deg := 0.0, scale := 1.0, tint := "#FFFFFF",
		kind := "shell") -> Dictionary:
	return {"id": id, "position": pos, "radius": r, "kind": kind, "asset": asset, "yaw_deg": yaw_deg, "scale": scale,
		"tint": tint}


static func zone(id: String, center: Vector2, radius: float, region: String) -> Dictionary:
	return {"id": id, "center": center, "radius": radius, "region": region}


static func anchor(id: String, pos: Vector2, model: String, dressing: String) -> Dictionary:
	return {"id": id, "position": pos, "model": model, "dressing": dressing}


## A rare place; yaw_deg and mirror are the orientation keys the scene reads when the stream sends
## them (s1-content.md 17.10).
static func place(id: String, kind: String, pos: Vector2, yaw_deg := 0.0, mirror := false) -> Dictionary:
	return {"id": id, "kind": kind, "position": pos, "yaw_deg": yaw_deg, "mirror": mirror}


static func loaded(key: Vector2i, shells := [], zones := [], anchors := [], places := []) -> Dictionary:
	return {"type": "chunk_loaded", "key": key, "shells": shells, "zones": zones, "anchors": anchors, "places": places}


static func unloaded(key: Vector2i) -> Dictionary:
	return {"type": "chunk_unloaded", "key": key}


static func rebased(offset_tm: Vector2, origin_am := [0.0, 0.0]) -> Dictionary:
	return {"type": "rebased", "offset_tm": offset_tm, "origin_am": origin_am}


static func tile_entered(tile: Vector2i, region: String, rare := "") -> Dictionary:
	return {"type": "tile_entered", "tile": tile, "region": region, "rare": rare}


## The chunk_loaded event of a chunk a WorldStream holds, through the scene's own builder.
static func from_chunk(world: WorldStream, chunk: WorldChunk) -> Dictionary:
	return WorldSpace.chunk_loaded_event(world, chunk)
