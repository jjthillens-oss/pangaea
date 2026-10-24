extends RefCounted
## Skin builder on the GPU (the native path): runs skin/surface_nets.glsl on a local RenderingDevice. Same grid, same
## outputs and the same vertex and triangle order as skin_cpu.gd. Needs the Forward+ or Mobile renderer (Vulkan, D3D12
## or Metal); `is_available()` is false under the Compatibility renderer and in headless runs.

const BodyField := preload("res://game/domain/creature/body_field.gd")
const SkinCpu := preload("res://game/systems/creature/skin_cpu.gd")
const SkinGrid := preload("res://game/systems/creature/skin_grid.gd")

const MODE_FIELD := 0
const MODE_COUNT := 1
const MODE_SCAN_LOCAL := 2
const MODE_SCAN_BLOCKS := 3
const MODE_SCAN_ADD := 4
const MODE_VERTS := 5
const MODE_QUADS := 6
const MODE_FIX_MARK := 7
const MODE_FIX_APPLY := 8
const FIX_PASSES := 6  # skin_cpu.gd FIX_PASSES
const GROUP := 256

var rd: RenderingDevice
var shader: RID
var pipeline: RID
## Buffers are kept between builds and grown when a bigger grid needs it, so live editing does not reallocate.
var _capacity := 0
var _cap_capsules := 0
var _buffers := {}
var _uniform_set: RID


func _init() -> void:
	rd = RenderingServer.create_local_rendering_device()
	if rd == null:
		return
	var file: RDShaderFile = load("res://game/systems/creature/surface_nets.glsl")  # needs an editor import (godot --import) first
	if file == null:
		rd = null
		return
	var spirv := file.get_spirv()
	if spirv.compile_error_compute != "":
		push_error(spirv.compile_error_compute)
		rd = null
		return
	shader = rd.shader_create_from_spirv(spirv)
	pipeline = rd.compute_pipeline_create(shader)


func is_available() -> bool:
	return rd != null


func device_name() -> String:
	return rd.get_device_name() if rd else ""


## Returns the same dictionary as skin_cpu.gd build(), with ms: {upload, gpu, readback, total}.
func build(desc: RefCounted, divisions: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var field = BodyField.from_description(desc)
	var grid := SkinGrid.layout(desc, divisions)
	var dims: Vector3i = grid["dims"]
	var n := dims.x * dims.y * dims.z
	var caps := PackedFloat32Array()
	for k in field.capsule_count():
		caps.append_array([field.a[k].x, field.a[k].y, field.a[k].z, field.ra[k],
				field.b[k].x, field.b[k].y, field.b[k].z, field.rb[k],
				field.start[k], field.a[k].distance_to(field.b[k]), field.chain_length[k], field.limb[k],
				float(field.bone_a[k]), float(field.bone_b[k]), field.attach_u[k], 0.0])
	_ensure_buffers(n, field.capsule_count())
	var origin: Vector3 = grid["origin"]
	var params := PackedFloat32Array([origin.x, origin.y, origin.z, grid["cell"]]).to_byte_array()
	params.append_array(PackedInt32Array([dims.x, dims.y, dims.z, n, field.capsule_count(),
			desc.bone_count(), 0, 0]).to_byte_array())
	params.append_array(_split_bits().to_byte_array())
	rd.buffer_update(_buffers["params"], 0, params.size(), params)
	var cap_bytes := caps.to_byte_array()
	rd.buffer_update(_buffers["capsules"], 0, cap_bytes.size(), cap_bytes)
	var t1 := Time.get_ticks_usec()

	var groups := int(ceil(float(n) / GROUP))
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, _uniform_set, 0)
	_pass(list, MODE_FIELD, 0, groups, groups)
	for fix in FIX_PASSES:
		_pass(list, MODE_FIX_MARK, 0, groups, groups)
		_pass(list, MODE_FIX_APPLY, 0, groups, groups)
	_pass(list, MODE_COUNT, 0, groups, groups)
	for target in 2:
		_pass(list, MODE_SCAN_LOCAL, target, groups, groups)
		_pass(list, MODE_SCAN_BLOCKS, target, groups, 1)
		_pass(list, MODE_SCAN_ADD, target, groups, groups)
	_pass(list, MODE_VERTS, 0, groups, groups)
	_pass(list, MODE_QUADS, 0, groups, groups)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	var t2 := Time.get_ticks_usec()

	var totals := rd.buffer_get_data(_buffers["totals"], 0, 8).to_int32_array()
	var vcount := totals[0]
	var icount := 6 * totals[1]
	var out := {
		"vertices": rd.buffer_get_data(_buffers["vertices"], 0, 12 * vcount).to_vector3_array(),
		"normals": rd.buffer_get_data(_buffers["normals"], 0, 12 * vcount).to_vector3_array(),
		"bones": rd.buffer_get_data(_buffers["bones"], 0, 16 * vcount).to_int32_array(),
		"weights": rd.buffer_get_data(_buffers["weights"], 0, 16 * vcount).to_float32_array(),
		"custom0": rd.buffer_get_data(_buffers["custom0"], 0, 16 * vcount).to_float32_array(),
		"indices": rd.buffer_get_data(_buffers["indices"], 0, 4 * icount).to_int32_array(),
		"dims": dims, "cell": grid["cell"],
	}
	var t3 := Time.get_ticks_usec()
	out["ms"] = {"upload": (t1 - t0) / 1000.0, "gpu": (t2 - t1) / 1000.0, "readback": (t3 - t2) / 1000.0,
			"total": (t3 - t0) / 1000.0}
	return out


## SkinCpu's split table as 8 words of 32 bits, so both builders fix the same cells.
static func _split_bits() -> PackedInt32Array:
	var words := PackedInt32Array()
	words.resize(8)
	var table: Array = SkinCpu._split_table()
	for m in 256:
		if table[m]:
			words[m >> 5] |= 1 << (m & 31)
	return words


func free_resources() -> void:
	if rd == null:
		return
	for b in _buffers.values():
		rd.free_rid(b)
	_buffers.clear()
	rd.free_rid(pipeline)
	rd.free_rid(shader)
	rd.free()
	rd = null


func _pass(list: int, mode: int, target: int, block_count: int, groups: int) -> void:
	var pc := PackedInt32Array([mode, target, block_count, 0]).to_byte_array()
	rd.compute_list_set_push_constant(list, pc, pc.size())
	rd.compute_list_dispatch(list, groups, 1, 1)
	rd.compute_list_add_barrier(list)


func _ensure_buffers(n: int, capsules: int) -> void:
	if n <= _capacity and capsules <= _cap_capsules and not _buffers.is_empty():
		return
	for b in _buffers.values():
		rd.free_rid(b)
	_buffers.clear()
	_capacity = int(n * 1.25)
	_cap_capsules = maxi(capsules, 32)
	var blocks := int(ceil(float(_capacity) / GROUP))
	var sizes := {
		"params": 80, "capsules": 64 * _cap_capsules, "field": 4 * _capacity, "cell_offset": 4 * _capacity,
		"quad_offset": 4 * _capacity, "blocks": 4 * blocks, "totals": 16, "vertices": 12 * _capacity,
		"normals": 12 * _capacity, "bones": 16 * _capacity, "weights": 16 * _capacity,
		"indices": 4 * 18 * _capacity, "custom0": 16 * _capacity,
	}
	var order := ["params", "capsules", "field", "cell_offset", "quad_offset", "blocks", "totals", "vertices",
			"normals", "bones", "weights", "indices", "custom0"]
	var uniforms: Array[RDUniform] = []
	for binding in order.size():
		var key: String = order[binding]
		_buffers[key] = rd.storage_buffer_create(sizes[key])
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding = binding
		u.add_id(_buffers[key])
		uniforms.append(u)
	_uniform_set = rd.uniform_set_create(uniforms, shader, 0)
