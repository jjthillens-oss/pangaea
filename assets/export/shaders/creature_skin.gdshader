// The creature skin (docs/art/creature_art_contract.md section 2). PROPOSED, art-owned.
// It reads only what the skin runtime writes: CUSTOM0 = (spine_u, ring_v, limb_id, limb_t), and COLOR.r as an
// optional crease hint. The paint layers come from those channels, so stretched bodies do not smear; fine detail is
// triplanar in object space. Bodies are mirror-symmetric, so patterns use the folded ring value
// f = 2 * min(v, 1 - v) (0 on the back, 1 on the belly) or sin/cos of v, and the dorsal wrap never shows.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Paint, set per creature from the body save.
uniform int base_pattern : hint_range(0, 3) = 0;      // 0 plain, 1 mottled, 2 cellular, 3 fine scales
uniform int coat_pattern : hint_range(0, 3) = 1;      // 0 none, 1 saddle, 2 dorsal stripe, 3 countershade
uniform int detail_pattern : hint_range(0, 4) = 0;    // 0 none, 1 cross bands, 2 spots, 3 limb rings, 4 eye spots
uniform vec3 color_base : source_color = vec3(0.86, 0.74, 0.56);
uniform vec3 color_coat : source_color = vec3(0.36, 0.42, 0.66);
uniform vec3 color_detail : source_color = vec3(0.95, 0.9, 0.78);
uniform int pattern_seed = 0;
uniform float coat_reach : hint_range(0.0, 1.0) = 0.5;
uniform float detail_scale : hint_range(1.0, 40.0) = 9.0;

// Look.
uniform int stage_look : hint_range(0, 1) = 1;        // 0 cell (soft membrane, rim glow), 1 creature (opaque)
uniform float anim_phase = 0.0;                       // ANIM_PHASE from the gait runtime, in turns
uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform float ripeness : hint_range(0.0, 1.0) = 0.0;

// Triplanar fine detail (greyscale; white means none).
uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float detail_tiling = 6.0;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.35;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.7;

// Covering (PROPOSED, art-owned; docs/art/creature_art_contract.md section 2.4a). The relief is a screen-space bump
// from a rest-space height field, so it costs a few noise taps per pixel; fur also draws strands from shell passes.
uniform int covering : hint_range(0, 3) = 0;          // 0 default (unchanged), 1 fur, 2 scales, 3 smooth-wet
uniform float covering_strength : hint_range(0.0, 1.0) = 1.0; // 0 = the default look, 1 = the full covering
uniform float fur_length : hint_range(0.0, 1.0) = 0.5;   // longer: bigger clumps, wider fuzz rim, taller shells
uniform float fur_density : hint_range(20.0, 400.0) = 220.0; // strands per body length
uniform float scale_size : hint_range(8.0, 120.0) = 45.0;  // scales per body length (rest space)
uniform float wet_gloss : hint_range(0.0, 1.0) = 0.8;    // smooth-wet: 1 is a wet, glossy film
// Fur shells (covering 1 only). The base pass is layer 0; SpineRig chains FUR_SHELLS copies of this material as
// next_pass with shell_layer 1..shell_count, each pushed out along the normal and alpha-tested into strands.
uniform int shell_layer = 0;                           // 0 = the skin itself; >0 = a fur shell (discarded unless fur)
uniform int shell_count = 6;
uniform float fur_height_m : hint_range(0.0, 0.1) = 0.05; // shell height at fur_length 1, in metres
uniform float fur_shag : hint_range(0.0, 1.0) = 0.6;    // 0 even strands; 1 long, ragged locks that taper to points

// Fur shell tuning (PROPOSED; lengths in strand cells unless noted).
const float FUR_CELLS = 0.7;         // strand cells per fur_density unit (154 strands per body length at 220)
const float FUR_LEAN = 1.1;          // strand tip offset along the lie per unit of fur height (about 48 degrees)
const float FUR_STRAND_R = 0.3;      // strand radius at the root
const float FUR_JITTER = 0.4;        // how far a strand's root wanders inside its cell
const float FUR_LOCK_CELLS = 7.0;    // between lock centres
const float FUR_LOCK_R = 4.0;        // a lock's radius at the root (its outer strands are the shortest)
const float FUR_CORE = 3.5;          // half-width of a lock's solid core at the root, at fur_shag 1, far away
const float FUR_ETA_CLAMP = 0.35;    // outline pixels this far (fur heights) below the skin still start the fur
const float FUR_TILT = 0.25;         // outline strands' normal turned this far toward the camera

varying vec4 skin;     // spine_u, ring_v, limb_id, limb_t
varying vec3 rest_pos; // rest-pose body-space position, x folded so both sides match, scaled to the body
varying vec3 rest_raw; // the same, unfolded: the fur shells' frame (strands need no mirror symmetry, and the fold
                       // would flatten the derivatives of triangles that cross the midline, where a back's outline is)
varying vec3 obj_pos;
varying vec3 obj_normal;
varying float crease;

// CUSTOM1.xyz = the vertex's rest-pose body-space position in metres (the mesh's own vertex array before skinning).
// Spots, cells and scales live there, so they neither stretch with the spine coordinates nor slide when the body bends.
uniform bool has_rest_custom1 = true;
uniform float body_length_m = 1.0;

void vertex() {
	skin = CUSTOM0;
	vec3 rest = has_rest_custom1 ? CUSTOM1.xyz : VERTEX;
	rest_pos = vec3(abs(rest.x), rest.y, rest.z) / max(body_length_m, 0.001);
	rest_raw = rest / max(body_length_m, 0.001);
	obj_pos = VERTEX;
	obj_normal = NORMAL;
	if (shell_layer > 0 && covering == 1) {
		float h = float(shell_layer) / float(max(shell_count, 1));
		VERTEX += NORMAL * h * fur_height_m * (0.3 + 0.7 * fur_length) * covering_strength;
		VERTEX.y -= h * h * fur_height_m * 0.35 * fur_length;   // tips droop a little
	}
	crease = COLOR.r;
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), u.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), u.x), u.y),
			mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), u.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * value_noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

// x: distance to the nearest feature, y: to the second nearest (cell walls), z: a random value for the nearest feature.
vec3 voronoi(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = hash33(i + g);
				float d = length(g + o - f);
				if (d < d1) { d2 = d1; d1 = d; id = hash13(i + g + 7.7); } else if (d < d2) { d2 = d; }
			}
		}
	}
	return vec3(d1, d2, id);
}

vec3 triplanar_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

// The nearest lock centre to p (xyz, in lock cells) and its random value (w): a cheap Voronoi over the 2x2x2 cells
// around p, with the centres kept inside the middle half of their cells.
vec4 fur_lock(vec3 p) {
	vec3 b = floor(p - 0.5);
	float best = 8.0;
	vec4 res = vec4(p, 0.0);
	for (int z = 0; z <= 1; z++) {
		for (int y = 0; y <= 1; y++) {
			for (int x = 0; x <= 1; x++) {
				vec3 c = b + vec3(float(x), float(y), float(z));
				vec3 q = c + 0.25 + 0.5 * hash33(c + 11.3);
				float d = dot(q - p, q - p);
				if (d < best) { best = d; res = vec4(q, hash13(c + 5.9)); }
			}
		}
	}
	return res;
}

// A strand's root (xyz, in strand cells) and length (w, a fraction of the fur height). Every strand belongs to its
// nearest lock (centre lock_c); fur_shag shortens a lock's outer strands, so each lock ends in a point, and gives the
// locks their own lengths. The distance to the lock centre is measured along `axis` (the outline, so a lock shows its
// full profile there) when `along` is set, else across the surface (axis is then the normal).
vec4 fur_root(vec3 cell, vec3 axis, bool along, vec3 lock_c, float lock_len, float shag) {
	vec3 o = cell + (0.5 - 0.5 * FUR_JITTER) + FUR_JITTER * hash33(cell);
	vec3 oc = o - lock_c;
	float lr = along ? abs(dot(oc, axis)) : length(oc - axis * dot(oc, axis));
	lr = min(lr / FUR_LOCK_R, 1.0);
	float rnd = hash13(cell + 3.1);
	float len = (0.55 + 0.45 * rnd + 0.3 * shag * (1.0 - rnd)) * (1.0 - shag + shag * lock_len);
	return vec4(o, len * (1.0 - min(1.2 * shag, 0.95) * lr));
}

// Over the skin: does the ray's path through one shell's slab pass through the strand rooted in `cell`? a and b are
// the path's ends in root space (strand cells, with the lean and the lock's gather undone) at fur heights ha (this
// shell) and hb (the shell below); distances are along the surface (n is the rest normal). Strands thin to nothing.
bool fur_slab_hit(vec3 a, vec3 b, float ha, float hb, vec3 cell, vec3 n, vec3 lock_c, float lock_len, float shag, float len_scale) {
	vec4 r = fur_root(cell, n, false, lock_c, lock_len, shag);
	float len = r.w * len_scale;
	if (len <= 0.0) {
		return false;
	}
	vec3 ab = b - a;
	ab -= n * dot(ab, n);
	vec3 ao = r.xyz - a;
	ao -= n * dot(ao, n);
	float t = clamp(dot(ao, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
	float hh = mix(ha, hb, t);
	return hh < len && length(ao - ab * t) < FUR_STRAND_R * (1.0 - hh / len);
}

// On the outline: is the strand rooted in `cell` at height eta within its radius of q, measured along the outline (bd)?
bool fur_fin_hit(vec3 q, float eta, vec3 cell, vec3 bd, vec3 lock_c, float lock_len, float shag) {
	vec4 r = fur_root(cell, bd, true, lock_c, lock_len, shag);
	return eta < r.w && abs(dot(q - r.xyz, bd)) < FUR_STRAND_R * (1.0 - eta / r.w);
}

void fragment() {
	float shell_tone = 1.0;
	float shell_graze = 0.0;
	bool shell_fin = false;
	vec3 shell_normal = vec3(0.0, 1.0, 0.0);
	vec3 paint_d = vec3(0.0);   // shells: from this fragment to the skin its strand grows from (rest units)
	vec3 paint_gu = vec3(0.0);  // rest-space gradients of spine_u, the folded ring value and limb_t
	vec3 paint_gf = vec3(0.0);
	vec3 paint_gt = vec3(0.0);
	if (shell_layer > 0) {
		// Shells cast no shadows: their strands, sized for the shadow map (the lock cores most), darkened the body in
		// blotches. The skin pass still casts the body's shadow.
		if (covering != 1 || covering_strength <= 0.0 || IN_SHADOW_PASS) { discard; }
		// Screen derivatives first: they are undefined once some pixels of a quad have discarded.
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 dndx = dFdx(NORMAL);
		vec3 dndy = dFdy(NORMAL);
		vec3 rdx = dFdx(rest_raw);
		vec3 rdy = dFdy(rest_raw);
		vec2 sdx = dFdx(skin.xw);
		vec2 sdy = dFdy(skin.xw);
		float fold0 = 2.0 * min(skin.y, 1.0 - skin.y);
		float fdx = dFdx(fold0);
		float fdy = dFdy(fold0);
		float shells = float(max(shell_count, 1));
		float h = float(shell_layer) / shells;
		float hb = h - 1.0 / shells;
		vec3 nv = normalize(NORMAL);
		float nd = clamp(dot(nv, VIEW), 0.0, 1.0);
		float sn = sqrt(1.0 - nd * nd);
		vec3 tvv = (VIEW - nv * nd) / max(sn, 1e-4);   // along the surface, toward the viewer
		float cs = covering_strength;
		float cells = fur_density * FUR_CELLS;                         // strand cells per body length
		float height_m = fur_height_m * (0.3 + 0.7 * fur_length) * cs; // the outer shell's height (vertex())
		float height_view = height_m * length(MODEL_MATRIX[0].xyz);

		// View-space directions along the surface map onto the rest surface (and the normal field) through the
		// derivatives: tv_rest is where tvv goes, kappa this shell's curvature along the view.
		vec3 m = cross(dpdx, dpdy);
		float m2 = max(dot(m, m), 1e-30);
		float ta = dot(cross(tvv, dpdy), m) / m2;
		float tb = dot(cross(dpdx, tvv), m) / m2;
		vec3 tv_rest = ta * rdx + tb * rdy;
		float kappa = dot(ta * dndx + tb * dndy, tvv);
		vec3 rn = cross(rdx, rdy);
		float rn2 = max(dot(rn, rn), 1e-30);
		vec3 n = rn * inversesqrt(rn2) * (dot(m, nv) < 0.0 ? -1.0 : 1.0);   // the outward rest normal

		// The lie of the fur in rest space, from the surface gradients of the paint coordinates: body strands point
		// toward the tail (spine_u rises head to tail) and a little down, limb strands toward the limb's tip (limb_t
		// rises root to tip). The two blend over the first 30% of a limb, so nothing jumps at a shoulder or hip.
		vec3 ex = cross(rdy, rn) / rn2;   // grad f = dFdx(f) * ex + dFdy(f) * ey
		vec3 ey = cross(rn, rdx) / rn2;
		vec3 g_u = sdx.x * ex + sdy.x * ey;
		vec3 g_t = sdx.y * ex + sdy.y * ey;
		paint_gu = g_u;
		paint_gt = g_t;
		paint_gf = fdx * ex + fdy * ey;
		// The ring value jumps from 1 to 0 across the seam's triangles; their fold gradient is meaningless there
		// (a real one is under about 20 per rest unit even on a thin limb, a seam's well over 100).
		if (dot(paint_gf, paint_gf) > 2500.0) {
			paint_gf = vec3(0.0);
		}
		vec3 down = vec3(0.0, -1.0, 0.0);
		vec3 body_lie = (dot(g_u, g_u) > 1e-4 ? normalize(g_u) : vec3(0.0, 0.0, 1.0)) + 0.4 * down;
		vec3 limb_lie = (dot(g_t, g_t) > 1e-4 ? normalize(g_t) : down) + 0.15 * down;
		float lw = skin.z > 0.5 ? smoothstep(0.0, 0.3, skin.w) : 0.0;
		vec3 lie = mix(body_lie, limb_lie, lw);
		lie -= n * dot(lie, n);
		lie = dot(lie, lie) > 1e-8 ? normalize(lie) : vec3(0.0);

		// Lean and locks: tip is the outer tip's offset in strand cells. Strands gather toward their lock's centre with
		// height and each lock has its own length and tilt (fur_shag), so the outline breaks into pointed locks.
		vec3 x0 = rest_raw * cells + vec3(float(pattern_seed) * 1.7);
		float shag = fur_shag;
		float gather = 0.8 * shag;
		vec3 tip = lie * (height_m / max(body_length_m, 0.001) * cells * FUR_LEAN);

		// On a convex outline of radius rho (along the view) the ray dips rho * (1 - sn) below this shell point, at
		// rho * nd along the surface. When that stays above the skin (eta >= 0) the pixel is the fur's outline: every
		// shell would see the same cut through the fur at that closest point, like a fin, so only the outer shell draws
		// it, as strands at height eta leaning along the outline. Slices of separate shells never show there, which is
		// what made the close-up flakes.
		float rho = kappa > 1e-4 ? 1.0 / kappa : 1e4;
		float dip = rho * (1.0 - sn);
		float eta = h - dip / max(height_view, 1e-6);
		if (eta >= -FUR_ETA_CLAMP) {
			// (Down to -0.35: the curvature from derivatives is only an estimate, and an overestimate would leave a gap
			// between the skin's edge and the fur; there the outline starts at its roots.)
			if (shell_layer < shell_count) { discard; }
			eta = max(eta, 0.0);
			vec3 xt = x0 - (tv_rest * (rho * nd) + n * (dip * length(tv_rest))) * cells;
			vec3 bd = cross(n, tv_rest);
			bd = dot(bd, bd) > 1e-12 ? normalize(bd) : vec3(0.0);
			vec3 tipb = bd * dot(tip, bd);
			vec4 lk = fur_lock((xt - tipb * eta) / FUR_LOCK_CELLS);
			vec3 lock_c = lk.xyz * FUR_LOCK_CELLS;
			tipb += bd * (length(tip) * (lk.w - 0.5) * 0.55 * shag);
			float lock_len = 1.0 - 0.45 * fract(lk.w * 7.31);
			vec3 q = xt - tipb * eta;
			q += bd * (dot(q - lock_c, bd) * (1.0 / (1.0 - gather * eta) - 1.0));
			vec3 c1 = floor(q - bd * 0.35);
			vec3 c2 = floor(q + bd * 0.35);
			// Each lock also has a solid core that tapers to its tip, so it reads as a lock at a distance where single
			// strands are thinner than a pixel; its strands carry on past the core, so close up it ends in strand tips.
			// The core shows only where a strand cell is under about 5 pixels (full under 2), so close up the lock is
			// all strands. pixel_m is this fragment's pixel size in metres, cell_m a strand cell's.
			float pixel_m = (PROJECTION_MATRIX[3][3] > 0.5 ? 1.0 : -VERTEX.z) * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
			float cell_m = body_length_m * length(MODEL_MATRIX[0].xyz) / cells;
			float lod = 1.0 - smoothstep(2.0, 5.0, cell_m / max(pixel_m, 1e-6));
			float lock_tip = 1.0 - shag + shag * lock_len;
			float core = FUR_CORE * shag * lod * (1.0 - eta / max(0.8 * lock_tip, 1e-3));
			bool hit = abs(dot(q - lock_c, bd)) * (1.0 - gather * eta) < core;
			if (!hit) {
				hit = fur_fin_hit(q, eta, c1, bd, lock_c, lock_len, shag);
			}
			if (!hit && any(notEqual(c1, c2))) {
				hit = fur_fin_hit(q, eta, c2, bd, lock_c, lock_len, shag);
			}
			if (!hit) { discard; }
			shell_tone = mix(0.9, 1.05, eta);
			paint_d = (xt - tipb * eta - x0) / cells;
			shell_normal = normalize(nv * 1.001 - VIEW * nd);   // the outline's normal, across the view
			shell_graze = 1.0;
			shell_fin = true;
		} else {
			// Over the skin: classic shells near the silhouette (face-on shell fragments read as specks, so they fade
			// out where N.V is high). The ray's path through this shell's slab, down to the shell below, is tested
			// rather than one point, so the slices of one strand join.
			float rim_keep = 1.0 - smoothstep(0.2, 0.45, nd);
			if (rim_keep <= 0.0) { discard; }
			vec3 w = -tv_rest * (height_view / shells * sn / max(nd, 0.15)) * cells;
			float wl = length(w);
			if (wl > 3.0) { w *= 3.0 / wl; }
			vec4 lk = fur_lock((x0 - tip * h) / FUR_LOCK_CELLS);
			vec3 lock_c = lk.xyz * FUR_LOCK_CELLS;
			tip += cross(n, lie) * (length(tip) * (lk.w - 0.5) * 0.55 * shag);
			float lock_len = 1.0 - 0.45 * fract(lk.w * 7.31);
			// Undo the gather along the surface only, so a strand keeps its cells from root to tip.
			vec3 a = x0 - tip * h;
			vec3 b = x0 + w - tip * hb;
			vec3 da = a - lock_c;
			vec3 db = b - lock_c;
			a += (da - n * dot(da, n)) * (1.0 / (1.0 - gather * h) - 1.0);
			b += (db - n * dot(db, n)) * (1.0 / (1.0 - gather * hb) - 1.0);
			float len_scale = min(cs, 1.0) * rim_keep;
			vec3 ca = floor(a);
			vec3 cb = floor(b);
			bool hit = fur_slab_hit(a, b, h, hb, ca, n, lock_c, lock_len, shag, len_scale);
			if (!hit && any(notEqual(ca, cb))) {
				hit = fur_slab_hit(a, b, h, hb, cb, n, lock_c, lock_len, shag, len_scale);
			}
			if (!hit) { discard; }
			shell_tone = mix(0.92, 1.04, h);
			paint_d = -tip * h / cells;
			shell_normal = nv;
			shell_graze = pow(1.0 - nd, mix(3.0, 1.6, fur_length));
		}
	}
	float u = skin.x;
	float v = skin.y;
	bool on_limb = skin.z > 0.5;
	float fold = 2.0 * min(v, 1.0 - v);                  // 0 back, 1 belly, same on both sides
	float limb_t = skin.w;
	vec3 paint_rest = rest_pos;
	if (shell_layer > 0) {
		// A strand takes the paint of the skin it grows from, not of the point where this shell meets it (that made
		// flecks of a stripe's colour along the outline).
		u += dot(paint_gu, paint_d);
		fold = clamp(fold + dot(paint_gf, paint_d), 0.0, 1.0);
		limb_t += dot(paint_gt, paint_d);
		vec3 r = rest_raw + paint_d;
		paint_rest = vec3(abs(r.x), r.y, r.z);
	}
	vec3 seed = vec3(float(pattern_seed) * 17.13, float(pattern_seed) * 7.71, float(pattern_seed) * 3.37);
	vec3 rp = paint_rest * detail_scale + seed;          // patterns in rest space, a set count per body length
	float wobble = fbm(rp * 0.7);

	// Base layer.
	vec3 col = color_base;
	if (base_pattern == 1) {
		col *= mix(0.78, 1.12, wobble);
	} else if (base_pattern == 2) {
		vec3 c = voronoi(rp * 1.4);
		col *= mix(0.72, 1.06, smoothstep(0.02, 0.14, c.y - c.x)) * mix(0.94, 1.04, c.z);
	} else if (base_pattern == 3) {
		vec3 c = voronoi(rp * 3.5);
		col *= mix(0.8, 1.06, smoothstep(0.0, 0.6, c.x)) * mix(0.95, 1.03, c.z);
	}

	// Coat: covers the back and fades toward the belly.
	float coat = 0.0;
	float edge = 0.06 + 0.08 * wobble;
	if (coat_pattern == 1) {
		float along = smoothstep(0.08, 0.22, u) * smoothstep(0.92, 0.7, u);
		coat = along * smoothstep(coat_reach + edge, coat_reach - edge, fold);
	} else if (coat_pattern == 2) {
		coat = smoothstep(0.25 * coat_reach + edge * 0.5, 0.25 * coat_reach - edge * 0.5, fold);
	} else if (coat_pattern == 3) {
		coat = 1.0 - smoothstep(coat_reach - 0.25, coat_reach + 0.25, fold);
	}
	if (on_limb) {
		coat *= 1.0 - smoothstep(0.2, 0.6, limb_t);       // the coat runs down onto the limbs and fades
	}
	col = mix(col, color_coat, coat);

	// Detail.
	float det = 0.0;
	if (detail_pattern == 1) {
		float band = sin(TAU * (u * detail_scale * 0.5 + 0.25 * wobble));
		det = smoothstep(0.45, 0.7, band) * (1.0 - smoothstep(0.7, 0.95, fold));
	} else if (detail_pattern == 2) {
		vec3 c = voronoi(rp * 1.1);
		float r = 0.16 + 0.16 * c.z;
		det = smoothstep(r + 0.05, r - 0.01, c.x) * (1.0 - smoothstep(0.75, 1.0, fold));
	} else if (detail_pattern == 3) {
		det = on_limb ? smoothstep(0.6, 0.8, sin(TAU * limb_t * detail_scale * 0.4)) : 0.0;
	} else if (detail_pattern == 4) {
		vec3 c = voronoi(rp * 0.55);
		float r = 0.2 + 0.08 * c.z;
		det = smoothstep(r + 0.04, r, c.x) - 0.7 * smoothstep(r * 0.55, r * 0.45, c.x);
		det *= step(0.45, c.z) * (1.0 - smoothstep(0.5, 0.8, fold));
	}
	col = mix(col, color_detail, clamp(det, 0.0, 1.0));

	// Triplanar fine detail in object space.
	vec3 w = triplanar_weights(normalize(obj_normal));
	vec3 tp = obj_pos * detail_tiling;
	float grain = texture(detail_tex, tp.yz).r * w.x + texture(detail_tex, tp.xz).r * w.y + texture(detail_tex, tp.xy).r * w.z;
	col *= mix(1.0, grain, detail_strength);
	float rough = clamp(roughness_base + 0.25 * (1.0 - grain) * detail_strength, 0.0, 1.0);

	// Covering: albedo, roughness, specular and a bump height in rest space.
	float spec = 0.4;
	float bump_h = 0.0;
	float bump_amp = 0.0;
	float fuzz = 0.0;
	float cs = covering_strength;
	if (covering == 1) {
		// Fur: strands stretched along the body axis (rest z), grouped into clumps; roots darken, tips lighten.
		vec3 fp = paint_rest * fur_density + seed;
		float strand = value_noise(fp * vec3(1.0, 1.0, 0.22));
		float clump = fbm(paint_rest * fur_density * mix(0.12, 0.04, fur_length) + seed * 0.5);
		float hair = mix(strand, clump, 0.45);
		col *= mix(1.0, mix(1.0 - 0.45 * fur_length, 1.1, hair), cs);
		rough = mix(rough, 0.92, cs);
		spec = mix(spec, 0.22, cs);
		bump_h = hair;
		bump_amp = 0.25 + 0.3 * fur_length;
		fuzz = cs * (0.35 + 0.45 * fur_length);
	} else if (covering == 2) {
		// Scales: domed cells with a grooved border and a sheen that varies per scale.
		vec3 c = voronoi(rest_pos * scale_size + seed);
		float wall = c.y - c.x;
		float dome = smoothstep(0.0, 0.45, wall);
		col *= mix(1.0, mix(0.68, 1.06, dome) * mix(0.93, 1.05, c.z), cs);
		rough = mix(rough, mix(0.62, 0.38, dome) - 0.08 * c.z, cs);
		spec = mix(spec, 0.5, cs);
		bump_h = dome;
		bump_amp = 0.55;
	} else if (covering == 3) {
		// Smooth-wet: darker saturated albedo, a tight glossy film over a soft wobble.
		col = mix(col, pow(col, vec3(1.25)) * 0.9, cs * wet_gloss);
		rough = mix(rough, mix(0.45, 0.06, wet_gloss), cs);
		spec = mix(spec, 0.65, cs);
		bump_h = fbm(rest_pos * 6.0 + seed);
		bump_amp = 0.1;
	}

	// State.
	float ripple = 0.5 + 0.5 * sin(TAU * (anim_phase - u * 1.5));
	col = mix(col, col * vec3(1.08, 1.05, 0.96), ripeness);
	float grey = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(grey) * 0.7, damage * 0.6);
	col *= 1.0 - 0.35 * crease;

	col *= shell_tone;
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	if (covering != 0 && cs > 0.0 && shell_layer == 0) {
		// Screen-space bump (surface gradient from derivatives); needs no tangents. Skin pass only: a shell has
		// discarded pixels (undefined derivatives), and the grazing brighten below made pale flakes on shells.
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		float hx = dFdx(bump_h);
		float hy = dFdy(bump_h);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (hx * r1 + hy * r2);
		NORMAL = normalize(abs(det) * NORMAL - grad * bump_amp * cs * 0.003 / (1.0 + 3.0 * fwidth(bump_h)));   // 0.003 m relief, faded where it would alias
		if (covering == 1) {
			float graze = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), mix(3.0, 1.6, fur_length));
			RIM = fuzz;
			RIM_TINT = 0.7;
			ALBEDO = mix(col, col * 1.35 + vec3(0.04), graze * fuzz);
		}
		if (covering == 3) {
			CLEARCOAT = cs * wet_gloss;
			CLEARCOAT_ROUGHNESS = 0.05;
		}
	} else if (shell_layer > 0) {
		// Fur shell: strands are lit about as the skin halfway to facing the camera, with the skin's fuzz rim and a
		// gentler grazing lift, so the fringe continues the skin's silhouette tone instead of turning dark or pale.
		// Strands are lit as the skin they grow from: on the outline as the skin's own outline (its fuzz rim and grazing
		// lift, the normal turned a little toward the camera), over the skin exactly as the skin under them. Darker or
		// paler strands read as specks or a dark mane rather than the skin's own fur.
		if (shell_fin) {
			NORMAL = normalize(mix(shell_normal, VIEW, FUR_TILT));
			RIM = fuzz;
			RIM_TINT = 0.7;
			ALBEDO = mix(col, col * 1.35 + vec3(0.04), fuzz);
		} else {
			RIM = fuzz;
			RIM_TINT = 0.7;
			ALBEDO = mix(col, col * 1.35 + vec3(0.04), shell_graze * fuzz);
		}
	}
	if (stage_look == 0) {
		// A soft membrane: rim glow, a gentle back-lit sheen and a slow breathing ripple.
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
		RIM = 0.6;
		RIM_TINT = 0.3;
		EMISSION = col * (0.12 * rim + 0.04 * ripple);
		ROUGHNESS = 0.3;
		SSS_STRENGTH = 0.4;
	} else {
		EMISSION = col * 0.015 * ripple;
	}
}
