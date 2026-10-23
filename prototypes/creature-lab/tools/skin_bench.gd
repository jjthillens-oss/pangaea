extends SceneTree
## Spine skin bench: GDScript builder versus the compute-shader builder on every spine test body, at the preview and
## bake grids. Checks that both give the same mesh and times them. The GPU path needs a Vulkan device:
## xvfb-run godot --path prototypes/creature-lab --rendering-method forward_plus --rendering-driver vulkan \
##   --script res://tools/skin_bench.gd
## Writes results/skin_bench.json.

const Lab := preload("res://lab_spine.gd")
const SkinCpu := preload("res://skin/skin_cpu.gd")
const SkinGpu := preload("res://skin/skin_gpu.gd")
const MeshChecks := preload("res://skin/mesh_checks.gd")

const GPU_REPEATS := 7


func _init() -> void:
	var gpu = SkinGpu.new()
	var report := {"engine": Engine.get_version_info()["string"], "gpu_device": gpu.device_name(),
			"cpu": OS.get_processor_name(), "bodies": []}
	print("GPU device: %s" % (gpu.device_name() if gpu.is_available() else "none (GDScript only)"))
	var rules := Lab.rules()
	for body_name in Lab.BODY_NAMES:
		var desc = Lab.body(body_name)
		for divisions in [int(rules["preview_divisions"]), int(rules["bake_divisions"])]:
			var cpu := SkinCpu.build(desc, divisions)
			var row := {"body": body_name, "divisions": divisions, "vertebrae": desc.vertebrae.size(),
					"vertices": cpu["vertices"].size(), "triangles": cpu["indices"].size() / 3,
					"cpu_ms": cpu["ms"], "watertight_cpu": MeshChecks.watertight(cpu["indices"]),
					"topology_fixes": cpu["topology_fixes"]}
			if gpu.is_available():
				var times := []
				var first: Dictionary = {}
				var hashes := {}
				for r in GPU_REPEATS:
					var g: Dictionary = gpu.build(desc, divisions)
					times.append(g["ms"]["total"])
					hashes[MeshChecks.mesh_hash(g)] = true
					if r == 0:
						first = g
				times.sort()
				row["gpu_ms_median"] = times[times.size() / 2]
				row["gpu_ms_min"] = times[0]
				row["gpu_ms_breakdown_first"] = first["ms"]
				row["gpu_repeat_identical"] = hashes.size() == 1
				row["same_topology"] = first["indices"] == cpu["indices"]
				row["max_vertex_gap_cells"] = MeshChecks.max_vertex_gap(cpu["vertices"], first["vertices"]) / cpu["cell"]
				row["watertight_gpu"] = MeshChecks.watertight(first["indices"])
			report["bodies"].append(row)
			print("%-8s /%-3d %6d tris  GDScript %7.1f ms  GPU %s  same mesh %s  watertight %s"
					% [body_name, divisions, row["triangles"], cpu["ms"]["total"],
					("%6.1f ms" % row["gpu_ms_median"]) if row.has("gpu_ms_median") else "  n/a",
					str(row.get("same_topology", "n/a")), str(row["watertight_cpu"])])
	gpu.free_resources()
	var f := FileAccess.open("res://results/skin_bench.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t", false, true) + "\n")
	quit()
