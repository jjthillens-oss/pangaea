#[compute]
#version 450
// Spine skin on the GPU (prototype 0b): the same field, Surface Nets, normals and weights as skin/skin_cpu.gd and
// domain/body_field.gd, in passes chosen by `mode`. Outputs are compacted with prefix sums (no atomics), so the vertex
// and triangle order matches the GDScript builder and repeats exactly from run to run.

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

const uint MODE_FIELD = 0u;
const uint MODE_COUNT = 1u;
const uint MODE_SCAN_LOCAL = 2u;
const uint MODE_SCAN_BLOCKS = 3u;
const uint MODE_SCAN_ADD = 4u;
const uint MODE_VERTS = 5u;
const uint MODE_QUADS = 6u;
const uint MODE_FIX_MARK = 7u;
const uint MODE_FIX_APPLY = 8u;
const float FLIP_SCALE = 1.0001; // skin_cpu.gd FLIP_SCALE

const float SUPPORT = 1.6;
const float ISO = 0.22628403;
const float ISO_P = 0.011586752; // ISO^3: grids store sum f^3 (domain/body_field.gd)
const int MAX_BONES = 32;

layout(push_constant, std430) uniform Pass {
	uint mode;
	uint target; // scans: 0 = cell vertex flags, 1 = quad counts
	uint block_count;
	uint pad;
} pc;

layout(set = 0, binding = 0, std430) restrict readonly buffer Params {
	vec4 origin_cell; // xyz origin, w cell size
	ivec4 dims_n; // xyz grid points, w total points
	ivec4 counts; // x capsules, y bones
	uvec4 split[2]; // 256-bit table: bit m set if corner mask m splits into two groups (skin_cpu.gd _split_table)
} params;

// Capsule k: caps[2k] = (a, ra), caps[2k + 1] = (b, rb).
layout(set = 0, binding = 1, std430) restrict readonly buffer Capsules { vec4 caps[]; };
layout(set = 0, binding = 2, std430) restrict buffer Field { float field[]; };
layout(set = 0, binding = 3, std430) restrict buffer CellOffsets { uint cell_offset[]; };
layout(set = 0, binding = 4, std430) restrict buffer QuadOffsets { uint quad_offset[]; };
layout(set = 0, binding = 5, std430) restrict buffer Blocks { uint blocks[]; };
layout(set = 0, binding = 6, std430) restrict buffer Totals { uint totals[]; };
layout(set = 0, binding = 7, std430) restrict writeonly buffer Vertices { float vertices[]; };
layout(set = 0, binding = 8, std430) restrict writeonly buffer Normals { float normals[]; };
layout(set = 0, binding = 9, std430) restrict writeonly buffer Bones { int bones[]; };
layout(set = 0, binding = 10, std430) restrict writeonly buffer Weights { float weights[]; };
layout(set = 0, binding = 11, std430) restrict writeonly buffer Indices { uint indices[]; };

shared uint scan_tmp[256];

const int EDGE_TABLE[24] = int[24](0, 1, 2, 3, 4, 5, 6, 7, 0, 2, 1, 3, 4, 6, 5, 7, 0, 4, 1, 5, 2, 6, 3, 7);



// Falloff of capsule k at p (x) and the closest point's axis parameter (y).
vec2 capsule(int k, vec3 p) {
	vec3 a = caps[2 * k].xyz;
	vec3 ab = caps[2 * k + 1].xyz - a;
	float len2 = dot(ab, ab);
	float t = len2 > 0.0 ? clamp(dot(p - a, ab) / len2, 0.0, 1.0) : 0.0;
	float big_r = SUPPORT * mix(caps[2 * k].w, caps[2 * k + 1].w, t);
	vec3 d = p - (a + ab * t);
	float q = dot(d, d) / (big_r * big_r);
	if (q >= 1.0) {
		return vec2(0.0, t);
	}
	float u = 1.0 - q;
	return vec2(u * u * u, t);
}

// sum f^3 over capsules (the p-norm blend without the final root, which does not move the surface).
float sample_field(vec3 p) {
	float s = 0.0;
	for (int k = 0; k < params.counts.x; k++) {
		float f = capsule(k, p).x;
		s += f * f * f;
	}
	return s;
}

ivec3 coords(uint i) {
	int nx = params.dims_n.x;
	int nxy = params.dims_n.x * params.dims_n.y;
	return ivec3(int(i) % nx, (int(i) / nx) % params.dims_n.y, int(i) / nxy);
}

bool is_inside(uint i) {
	return field[i] > ISO_P;
}

uint corner_index(uint base, int c) {
	int nx = params.dims_n.x;
	int nxy = params.dims_n.x * params.dims_n.y;
	return base + uint((c & 1) + ((c >> 1) & 1) * nx + ((c >> 2) & 1) * nxy);
}

uint cell_mask(uint i) {
	uint mask = 0u;
	for (int c = 0; c < 8; c++) {
		if (is_inside(corner_index(i, c))) mask |= 1u << c;
	}
	return mask;
}

bool cell_crossed(uint i) {
	ivec3 g = coords(i);
	if (g.x >= params.dims_n.x - 1 || g.y >= params.dims_n.y - 1 || g.z >= params.dims_n.z - 1) {
		return false;
	}
	uint mask = 0u;
	for (int c = 0; c < 8; c++) {
		if (is_inside(corner_index(i, c))) {
			mask |= 1u << c;
		}
	}
	return mask != 0u && mask != 255u;
}

// Bit 0: x edge crossed, bit 1: y edge, bit 2: z edge (only for points whose four surrounding cells exist).
uint crossed_edges(uint i) {
	ivec3 g = coords(i);
	if (g.x < 1 || g.y < 1 || g.z < 1 || g.x >= params.dims_n.x - 1 || g.y >= params.dims_n.y - 1 || g.z >= params.dims_n.z - 1) {
		return 0u;
	}
	uint nx = uint(params.dims_n.x);
	uint nxy = uint(params.dims_n.x * params.dims_n.y);
	bool inside = is_inside(i);
	uint bits = 0u;
	if (inside != is_inside(i + 1u)) bits |= 1u;
	if (inside != is_inside(i + nx)) bits |= 2u;
	if (inside != is_inside(i + nxy)) bits |= 4u;
	return bits;
}

void write_quad(inout uint at, uint q0, uint q1, uint q2, uint q3, bool starts_inside) {
	uint v0 = cell_offset[q0];
	uint v1 = cell_offset[q1];
	uint v2 = cell_offset[q2];
	uint v3 = cell_offset[q3];
	if (starts_inside) {
		indices[at] = v0; indices[at + 1u] = v2; indices[at + 2u] = v1;
		indices[at + 3u] = v0; indices[at + 4u] = v3; indices[at + 5u] = v2;
	} else {
		indices[at] = v0; indices[at + 1u] = v1; indices[at + 2u] = v2;
		indices[at + 3u] = v0; indices[at + 4u] = v2; indices[at + 5u] = v3;
	}
	at += 6u;
}

void main() {
	uint i = gl_GlobalInvocationID.x;
	uint n = uint(params.dims_n.w);
	if (pc.mode == MODE_FIELD) {
		if (i >= n) return;
		vec3 p = params.origin_cell.xyz + vec3(coords(i)) * params.origin_cell.w;
		field[i] = sample_field(p);
		quad_offset[i] = 0u; // also the topology-fix marks; start clear
	} else if (pc.mode == MODE_COUNT) {
		if (i >= n) return;
		cell_offset[i] = cell_crossed(i) ? 1u : 0u;
		quad_offset[i] = bitCount(crossed_edges(i));
	} else if (pc.mode == MODE_SCAN_LOCAL) {
		uint lid = gl_LocalInvocationID.x;
		uint value = 0u;
		if (i < n) value = pc.target == 0u ? cell_offset[i] : quad_offset[i];
		scan_tmp[lid] = value;
		barrier();
		for (uint step = 1u; step < 256u; step <<= 1u) {
			uint add = lid >= step ? scan_tmp[lid - step] : 0u;
			barrier();
			scan_tmp[lid] += add;
			barrier();
		}
		if (i < n) {
			if (pc.target == 0u) cell_offset[i] = scan_tmp[lid] - value;
			else quad_offset[i] = scan_tmp[lid] - value;
		}
		if (lid == 255u) blocks[gl_WorkGroupID.x] = scan_tmp[255];
	} else if (pc.mode == MODE_SCAN_BLOCKS) {
		if (i != 0u) return;
		uint sum = 0u;
		for (uint b = 0u; b < pc.block_count; b++) {
			uint v = blocks[b];
			blocks[b] = sum;
			sum += v;
		}
		totals[pc.target] = sum;
	} else if (pc.mode == MODE_SCAN_ADD) {
		if (i >= n) return;
		if (pc.target == 0u) cell_offset[i] += blocks[gl_WorkGroupID.x];
		else quad_offset[i] += blocks[gl_WorkGroupID.x];
	} else if (pc.mode == MODE_VERTS) {
		if (i >= n || !cell_crossed(i)) return;
		uint v = cell_offset[i];
		vec3 sum = vec3(0.0);
		float count = 0.0;
		for (int e = 0; e < 12; e++) {
			int c0 = EDGE_TABLE[2 * e];
			int c1 = EDGE_TABLE[2 * e + 1];
			bool in0 = is_inside(corner_index(i, c0));
			bool in1 = is_inside(corner_index(i, c1));
			if (in0 != in1) {
				// Interpolate on F = S^(1/3), close to linear across a cell (skin_cpu.gd does the same).
				float v0 = pow(field[corner_index(i, c0)], 1.0 / 3.0) - ISO;
				float v1 = pow(field[corner_index(i, c1)], 1.0 / 3.0) - ISO;
				vec3 p0 = vec3(float(c0 & 1), float((c0 >> 1) & 1), float((c0 >> 2) & 1));
				vec3 p1 = vec3(float(c1 & 1), float((c1 >> 1) & 1), float((c1 >> 2) & 1));
				sum += mix(p0, p1, clamp(v0 / (v0 - v1), 0.0, 1.0));
				count += 1.0;
			}
		}
		float cell = params.origin_cell.w;
		vec3 p = params.origin_cell.xyz + (vec3(coords(i)) + sum / count) * cell;
		vertices[3u * v] = p.x; vertices[3u * v + 1u] = p.y; vertices[3u * v + 2u] = p.z;
		float h = 0.25 * cell;
		vec3 g = vec3(sample_field(p + vec3(h, 0, 0)) - sample_field(p - vec3(h, 0, 0)),
				sample_field(p + vec3(0, h, 0)) - sample_field(p - vec3(0, h, 0)),
				sample_field(p + vec3(0, 0, h)) - sample_field(p - vec3(0, 0, h)));
		vec3 nrm = dot(g, g) > 0.0 ? normalize(-g) : vec3(0.0, 1.0, 0.0);
		normals[3u * v] = nrm.x; normals[3u * v + 1u] = nrm.y; normals[3u * v + 2u] = nrm.z;
		float w[MAX_BONES];
		int bone_count = params.counts.y;
		for (int b = 0; b < MAX_BONES; b++) w[b] = 0.0;
		float total = 0.0;
		for (int k = 0; k < params.counts.x; k++) {
			vec2 c = capsule(k, p);
			if (c.x > 0.0) {
				w[k] += c.x * (1.0 - c.y);
				w[k + 1] += c.x * c.y;
				total += c.x;
			}
		}
		if (total <= 0.0) {
			int best_k = 0;
			float best_d = 1e30;
			for (int k = 0; k < params.counts.x; k++) {
				vec3 a = caps[2 * k].xyz;
				vec3 ab = caps[2 * k + 1].xyz - a;
				float len2 = dot(ab, ab);
				float t = len2 > 0.0 ? clamp(dot(p - a, ab) / len2, 0.0, 1.0) : 0.0;
				float d = length(p - (a + ab * t));
				if (d < best_d) { best_d = d; best_k = k; }
			}
			w[best_k] = 1.0;
		}
		int out_bone[4];
		float out_w[4];
		float wsum = 0.0;
		for (int slot = 0; slot < 4; slot++) {
			int best = -1;
			for (int b = 0; b < bone_count; b++) {
				if (w[b] > 0.0 && (best < 0 || w[b] > w[best])) best = b;
			}
			if (best < 0) {
				out_bone[slot] = 0;
				out_w[slot] = 0.0;
			} else {
				out_bone[slot] = best;
				out_w[slot] = w[best];
				w[best] = 0.0;
			}
			wsum += out_w[slot];
		}
		for (int slot = 0; slot < 4; slot++) {
			bones[4u * v + uint(slot)] = out_bone[slot];
			weights[4u * v + uint(slot)] = out_w[slot] / wsum;
		}
	} else if (pc.mode == MODE_FIX_MARK) {
		// skin_cpu.gd step 1b: a crossed cell whose inside or outside corners form two groups gets its strongest
		// outside corner marked to move inside.
		if (i >= n) return;
		ivec3 g = coords(i);
		if (g.x >= params.dims_n.x - 1 || g.y >= params.dims_n.y - 1 || g.z >= params.dims_n.z - 1) return;
		uint m = cell_mask(i);
		if (m == 0u || m == 255u) return;
		if ((params.split[m >> 7u][(m >> 5u) & 3u] & (1u << (m & 31u))) == 0u) return;
		int best = -1;
		for (int c = 0; c < 8; c++) {
			if (((m >> c) & 1u) == 0u && (best < 0 || field[corner_index(i, c)] > field[corner_index(i, best)])) best = c;
		}
		quad_offset[corner_index(i, best)] = 1u;
	} else if (pc.mode == MODE_FIX_APPLY) {
		if (i >= n) return;
		if (quad_offset[i] != 0u) {
			field[i] = max(field[i], ISO_P * FLIP_SCALE);
			quad_offset[i] = 0u;
		}
	} else if (pc.mode == MODE_QUADS) {
		if (i >= n) return;
		uint bits = crossed_edges(i);
		if (bits == 0u) return;
		uint nx = uint(params.dims_n.x);
		uint nxy = uint(params.dims_n.x * params.dims_n.y);
		uint at = 6u * quad_offset[i];
		bool inside = is_inside(i);
		if ((bits & 1u) != 0u) write_quad(at, i - nx - nxy, i - nxy, i, i - nx, inside);
		if ((bits & 2u) != 0u) write_quad(at, i - 1u - nxy, i - 1u, i, i - nxy, inside);
		if ((bits & 4u) != 0u) write_quad(at, i - 1u - nx, i - nx, i, i - 1u, inside);
	}
}
