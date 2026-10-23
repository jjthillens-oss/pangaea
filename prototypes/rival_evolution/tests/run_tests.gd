extends SceneTree

const Simulation := preload("res://simulation.gd")

var failures := 0


func _init() -> void:
	check(Simulation.run(17)["text"] == Simulation.run(17)["text"], "same seed gives byte-identical output")
	check(Simulation.run(17)["text"] != Simulation.run(18)["text"], "different seeds differ")
	var in_bounds := true
	for seed_value in range(20):
		var result: Dictionary = Simulation.run(seed_value, 200)
		for rival in result["history"]:
			in_bounds = in_bounds and rival["size"] >= Simulation.SIZE_MIN and rival["size"] <= Simulation.SIZE_MAX
			in_bounds = in_bounds and rival["speed"] >= Simulation.SPEED_MIN and rival["speed"] <= Simulation.SPEED_MAX
			in_bounds = in_bounds and rival["mouth"] >= 0 and rival["mouth"] < Simulation.MOUTHS.size()
			in_bounds = in_bounds and rival["spikes"] >= Simulation.SPIKES_MIN and rival["spikes"] <= Simulation.SPIKES_MAX
	check(in_bounds, "all traits stay bounded over 200 generations for 20 seeds")
	check(Simulation.run(1)["text"].count("Generation ") == 20, "runner emits 20 generations")
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func check(ok: bool, description: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + description)
	if not ok:
		failures += 1
