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

// Covering (PROPOSED, art-owned; docs/art/creature_art_contract.md section 2.4a). Single pass, no shells or fins:
// the relief is a screen-space bump from a rest-space height field, so it costs a few noise taps per pixel.
uniform int covering : hint_range(0, 3) = 0;          // 0 default (unchanged), 1 fur, 2 scales, 3 smooth-wet
uniform float covering_strength : hint_range(0.0, 1.0) = 1.0; // 0 = the default look, 1 = the full covering
uniform float fur_length : hint_range(0.0, 1.0) = 0.5;   // longer: bigger clumps, wider fuzz rim, darker roots
uniform float fur_density : hint_range(20.0, 400.0) = 220.0; // strands per body length
uniform float scale_size : hint_range(8.0, 120.0) = 45.0;  // scales per body length (rest space)
uniform float wet_gloss : hint_range(0.0, 1.0) = 0.8;    // smooth-wet: 1 is a wet, glossy film
// Fur shells (covering 1 only). The base pass is layer 0; SpineRig chains FUR_SHELLS copies of this material as
// next_pass with shell_layer 1..shell_count, each pushed out along the normal and alpha-tested into strands.
uniform int shell_layer = 0;                           // 0 = the skin itself; >0 = a fur shell (discarded unless fur)
uniform int shell_count = 6;
uniform float fur_height_m : hint_range(0.0, 0.1) = 0.022; // shell height at fur_length 1, in metres

varying vec4 skin;     // spine_u, ring_v, limb_id, limb_t
varying vec3 rest_pos; // rest-pose body-space position, x folded so both sides match, scaled to the body
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

// Strand mask for shell height h (0 root, 1 tip): jittered strands per cell, tapering, some shorter.
float fur_strand(vec3 p, float h) {
	vec3 c = floor(p);
	vec3 o = hash33(c) * 0.5 + 0.25;
	float d = length(fract(p) - o);
	float len = 0.45 + 0.55 * hash13(c + 3.1);
	return (h < len) ? step(d, 0.62 * pow(1.0 - h / len, 0.8) + 0.06) : 0.0;
}

void fragment() {
	if (shell_layer > 0) {
		if (covering != 1 || covering_strength <= 0.0) { discard; }
		float h = float(shell_layer) / float(max(shell_count, 1));
		vec3 fp = rest_pos * fur_density * 0.45 + vec3(float(pattern_seed) * 1.7);
		fp.z += h * 0.6;   // strands lean back along the body
		if (fur_strand(fp, h / max(covering_strength, 0.01)) < 0.5) { discard; }
	}
	float u = skin.x;
	float v = skin.y;
	bool on_limb = skin.z > 0.5;
	float fold = 2.0 * min(v, 1.0 - v);                  // 0 back, 1 belly, same on both sides
	vec3 seed = vec3(float(pattern_seed) * 17.13, float(pattern_seed) * 7.71, float(pattern_seed) * 3.37);
	vec3 rp = rest_pos * detail_scale + seed;            // patterns in rest space, a set count per body length
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
		coat *= 1.0 - smoothstep(0.2, 0.6, skin.w);       // the coat runs down onto the limbs and fades
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
		det = on_limb ? smoothstep(0.6, 0.8, sin(TAU * skin.w * detail_scale * 0.4)) : 0.0;
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
		vec3 fp = rest_pos * fur_density + seed;
		float strand = value_noise(fp * vec3(1.0, 1.0, 0.22));
		float clump = fbm(rest_pos * fur_density * mix(0.12, 0.04, fur_length) + seed * 0.5);
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

	if (shell_layer > 0) {
		col *= mix(0.95, 1.18, float(shell_layer) / float(max(shell_count, 1)));   // dark roots, light tips
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	if (covering != 0 && cs > 0.0) {
		// Screen-space bump (surface gradient from derivatives); needs no tangents.
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
