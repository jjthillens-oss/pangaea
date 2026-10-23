extends SceneTree
## Deterministic swim-selection, propulsion, posture and curvature gates.

const Lab := preload("res://lab_swim.gd")
const LabSpine := preload("res://lab_spine.gd")
const Drive := preload("res://domain/swim_drive.gd")
const Rig := preload("res://rig/swim_rig.gd")
const SkinCpu := preload("res://skin/skin_cpu.gd")

var failures := 0


func _init() -> void:
	check(not Drive.aquatic(LabSpine.body("s1_quadruped")), "ground-reaching quadruped keeps walk mode")
	check(Drive.aquatic(LabSpine.body("s1_quadruped"), "water"), "explicit water override selects swim")
	for name in Lab.names():
		var desc = Lab.body(name)
		check(Drive.aquatic(desc), "%s anatomy selects swim" % name)
		var a = Drive.create(desc)
		var b = Drive.create(desc)
		check(a.mode == ("tail_wave" if name == "swim_tail" else "fin_stroke"), "%s mode" % name)
		var max_wave := 0.0
		var max_fin := 0.0
		for i in 600:
			a.step(1.0 / 60.0, 1.0, 0.25)
			b.step(1.0 / 60.0, 1.0, 0.25)
			max_wave = maxf(max_wave, absf(a.spine_angle(desc.vertebrae.size() - 1)))
			max_fin = maxf(max_fin, absf(a.fin_angle(0)))
		check(a.position == b.position and a.phase == b.phase, "%s deterministic 600-step state" % name)
		check(a.is_finite_state() and a.within_stability_gate(), "%s finite and pitch/roll <=5 deg" % name)
		check(a.cycle_progress_min > 0.02, "%s net forward progress/cycle %.3f m" % [name, a.cycle_progress_min])
		check(a.max_curvature < 2.0, "%s spine curvature %.3f rad/m" % [name, a.max_curvature])
		check(a.max_stance_slip_ratio == 0.0, "%s has no foot contact" % name)
		check(max_fin > 0.01, "%s fin stroke is phase locked" % name)
		check((max_wave > 0.01) == (name == "swim_tail"), "%s correct spinal propulsion" % name)
		print("SWIM %s mode=%s speed_top=%.3f hz=%.3f progress_min=%.3f curvature=%.3f pitch=%.2f roll=%.2f" % [
			name, a.mode, a.speed_top, a.wave_hz, a.cycle_progress_min, a.max_curvature,
			rad_to_deg(a.max_pitch), rad_to_deg(a.max_roll)])
	var desc = Lab.body("swim_tail")
	var rig = Rig.new()
	root.add_child(rig)
	rig.setup(desc, SkinCpu.build(desc, 32), Drive.create(desc), Color.WHITE)
	rig.planner.step(1.0 / 60.0, 1.0, 0.0)
	rig.sync(1.0 / 60.0)
	check(rig.body.skeleton.get_bone_count() == desc.bone_count(), "generated swim rig keeps full skeleton")
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
