shader_type canvas_item;
// The title screen's moving backdrop (UI pass): the deep-blue microscopic sea of the cell stage
// (docs/DECISIONS.md, "Microscopic world look"). Light falls in soft shafts from the surface and
// motes drift up through three depths, the near ones larger, brighter and sharper. Original work;
// all procedural. `motion` scales every movement (0.15 with "Reduce camera motion").

uniform vec4 surface_color : source_color = vec4(0.298, 0.608, 0.878, 1.0);   // Fluid light #4C9BE0
uniform vec4 mid_color : source_color = vec4(0.184, 0.435, 0.722, 1.0);       // ambient #2F6FB8
uniform vec4 deep_color : source_color = vec4(0.043, 0.18, 0.42, 1.0);        // Fluid deep #0B2E6B
uniform vec4 abyss_color : source_color = vec4(0.016, 0.07, 0.19, 1.0);
uniform vec4 mote_color : source_color = vec4(0.75, 0.9, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.42, 0.66, 0.88, 1.0);         // haze #6AA8E0
uniform float motion = 1.0;
uniform float aspect = 1.7778;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// One depth of drifting motes: a grid of cells, at most one mote per cell, rising and swaying.
float motes(vec2 uv, float scale, float speed, float size, float softness, float t) {
	vec2 p = uv * scale;
	p.y += t * speed;
	vec2 cell = floor(p);
	float total = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			float present = step(0.45, hash12(c + 7.1));
			vec2 h = hash22(c);
			vec2 centre = c + 0.5 + 0.35 * (h - 0.5);
			centre.x += 0.18 * sin(t * (0.3 + h.y * 0.4) + h.x * 6.2831);
			float r = size * (0.6 + 0.8 * hash12(c + 3.7));
			float d = length(p - centre);
			// A soft body with a brighter rim, like a tiny cell seen through water.
			float body = 1.0 - smoothstep(r * (1.0 - softness), r, d);
			float rim = exp(-pow((d - r * 0.82) / (r * 0.12 + 0.001), 2.0)) * 0.6;
			total += present * (body * 0.45 + rim) * (0.5 + 0.5 * h.y);
		}
	}
	return total;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * motion;
	float depth = uv.y;

	vec3 col = mix(surface_color.rgb, mid_color.rgb, smoothstep(0.0, 0.35, depth));
	col = mix(col, deep_color.rgb, smoothstep(0.3, 0.75, depth));
	col = mix(col, abyss_color.rgb, smoothstep(0.7, 1.05, depth));

	// Light shafts: slanted bands from the surface, swaying slowly, fading with depth.
	vec2 q = vec2(uv.x * aspect, uv.y);
	float slant = q.x + q.y * 0.35;
	float shafts = 0.0;
	shafts += pow(0.5 + 0.5 * sin(slant * 7.0 + t * 0.21), 6.0) * 0.5;
	shafts += pow(0.5 + 0.5 * sin(slant * 11.3 - t * 0.17 + 1.7), 8.0) * 0.35;
	shafts += pow(0.5 + 0.5 * sin(slant * 4.1 + t * 0.09 + 4.0), 5.0) * 0.4;
	shafts *= (1.0 - smoothstep(0.0, 0.85, depth)) * 0.32;
	col += glow_color.rgb * shafts;

	// A faint shimmer just under the surface.
	float shimmer = sin(q.x * 23.0 + sin(q.y * 17.0 + t * 0.8) * 2.0 + t * 0.5) * sin(q.x * 13.0 - t * 0.6 + q.y * 9.0);
	col += glow_color.rgb * max(shimmer, 0.0) * 0.05 * (1.0 - smoothstep(0.0, 0.3, depth));

	// Three depths of motes: far (small, dim, slow), middle, near (large, bright, quicker).
	vec2 m = vec2(uv.x * aspect, uv.y);
	float far = motes(m + vec2(3.1, 0.0), 26.0, 0.25, 0.12, 0.9, t);
	float mid = motes(m + vec2(9.7, 0.0), 13.0, 0.18, 0.13, 0.6, t);
	float near = motes(m + vec2(1.3, 0.0), 6.5, 0.12, 0.11, 0.35, t);
	float fade = 0.55 + 0.45 * (1.0 - depth);
	col += mote_color.rgb * (far * 0.06 + mid * 0.1 + near * 0.13) * fade;

	// Vignette toward the edges and corners.
	vec2 v = uv - 0.5;
	v.x *= aspect * 0.75;
	col *= 1.0 - smoothstep(0.35, 0.95, length(v)) * 0.45;

	COLOR = vec4(col, 1.0);
}
