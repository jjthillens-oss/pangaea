extends SceneTree
## Runs the creature world scene through the real main loop for tests/test_creature_world_scene.gd, which cannot
## put nodes inside the tree itself (the runner's tests execute before the tree's first frame). Prints one
## "PROBE_RESULT {json}" line after PROBE_FRAMES frames and quits. Not a test file (no test_ prefix).

const PROBE_FRAMES := 120
const DT := 1.0 / 60.0


class ScriptErrorCounter extends Logger:
	var count := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			count += 1

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _world: Node3D
var _frames := 0
var _errors := ScriptErrorCounter.new()


func _initialize() -> void:
	OS.add_logger(_errors)
	var body = load("res://game/systems/creature/creature_data.gd").body("s1_quadruped")
	_world = load("res://game/scenes/creature/creature_world.tscn").instantiate()
	root.add_child(_world)
	_world.setup(body.to_dict(), 5, 150)
	_world.set_intent(Vector2(0.0, 1.0), false, false)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < PROBE_FRAMES:
		return false
	var rig: Node3D = _world.player_rig
	var skeleton: Skeleton3D = rig.body.skeleton
	var bones_finite := true
	for b in skeleton.get_bone_count():
		bones_finite = bones_finite and skeleton.get_bone_global_pose(b).origin.is_finite()
	var drawn := 0
	for id in _world.rival_rigs:
		if (_world.rival_rigs[id] as Node3D).visible:
			drawn += 1
	var p: Vector3 = _world.sim.player()["position"]
	print("PROBE_RESULT " + JSON.stringify({"z": p.z, "x": p.x, "solved_frames": rig.solved_frames,
			"solved_finite": rig.solved_finite, "max_stance_slip_ratio": rig.max_stance_slip_ratio,
			"bones_finite": bones_finite, "rivals_drawn": drawn, "script_errors": _errors.count,
			"setup_ms": _world.setup_ms}))
	OS.remove_logger(_errors)
	quit(0)
	return true
