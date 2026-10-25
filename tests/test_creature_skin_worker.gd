extends TestCase
## The editor's skin worker returns the requested body and coalesces queued edits.

const Fixtures := preload("res://tests/creature_fixtures.gd")
const CreatureData := preload("res://game/systems/creature/creature_data.gd")
const BodyCodec := preload("res://game/domain/creature/body_codec.gd")
const SkinWorker := preload("res://game/scenes/creature/creature_editor_skin_worker.gd")


func test_immediate_build_returns_a_skin_for_the_requested_body() -> void:
	var body: RefCounted = Fixtures.body("bean")
	var worker := SkinWorker.new(CreatureData.rules(), 12)
	var built: Dictionary = worker.build_now(body.to_dict())
	check(worker.builder in ["CPU", "GPU"], "the selected builder is recorded")
	check_eq(
		BodyCodec.encode(built["desc"]),
		BodyCodec.encode(body),
		"build describes the requested body"
	)
	check((built["arrays"]["vertices"] as PackedVector3Array).size() > 0, "build has vertices")
	check((built["arrays"]["indices"] as PackedInt32Array).size() > 0, "build has triangles")
	check(float(built["ms"]) >= 0.0, "build reports nonnegative elapsed time")
	worker.stop()


func test_queued_edits_keep_the_latest_body_and_collect_once() -> void:
	var first: RefCounted = Fixtures.body("bean")
	var latest: RefCounted = Fixtures.body("fish")
	var worker := SkinWorker.new(CreatureData.rules(), 12)
	check(worker.collect().is_empty(), "nothing is ready before work starts")
	worker.post(first.to_dict())
	worker.post(latest.to_dict())
	check(worker.is_building(), "queued work is visible to the editor")
	worker.start()
	var built := {}
	for attempt in 500:
		built = worker.collect()
		if not built.is_empty():
			break
		OS.delay_msec(10)
	check(not built.is_empty(), "the worker finishes the latest queued edit within five seconds")
	if not built.is_empty():
		check_eq(
			BodyCodec.encode(built["desc"]),
			BodyCodec.encode(latest),
			"only the newest queued body is built"
		)
		check(
			(built["arrays"]["vertices"] as PackedVector3Array).size() > 0,
			"queued build has vertices"
		)
		check(worker.collect().is_empty(), "a completed result is delivered once")
		check(not worker.is_building(), "the worker returns to idle after collection")
	worker.stop()
