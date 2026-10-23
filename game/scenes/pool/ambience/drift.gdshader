shader_type spatial;
// Decor that drifts through the water around the camera (docs/DECISIONS.md, "The cell stage reads
// as a microscopic world"): specks, bubbles and microbes, one camera-facing quad per instance of a
// MultiMesh. Each instance wraps inside a box that follows the camera's focus, so a few hundred
// quads fill the whole pool and the CPU never moves them. Shapes are drawn here, not textured.
//
// INSTANCE_CUSTOM: x phase (0..1), y size (m), z kind, w opacity as a share of the layer's `opacity`.
// Kinds: 0 speck, 1 bubble, 2 rod bacterium, 3 spirillum, 4 spore. Every kind draws at or under its
// tint's brightness, and engine fog stays on (blend_mix), so decor fades into the fluid.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform vec3 focus = vec3(0.0);          // the camera's focus on the swim plane (world)
uniform vec3 player = vec3(0.0, -100.0, 0.0);  // the player cell (world); far away when there is none
uniform vec2 box = vec2(48.0, 36.0);     // the wrap box across (x) and along (z) the plane, m
uniform vec2 height_range = vec2(-20.0, 6.0);  // the band the layer wraps in vertically (world y)
uniform vec3 drift = vec3(0.04, 0.0, -0.03);   // m/s
uniform float wobble = 0.25;             // m of slow side-to-side wander
uniform float scatter_radius = 0.0;      // microbes part around the cell within this distance, m
uniform float scatter_depth = 3.0;       // and only this far below it
uniform float depth_k = 1.0;            // growth: heights and the band scale by this (pool_ambience apply_scale_view)
uniform float size_k = 1.0;             // growth: quad sizes scale by this
uniform float opacity = 1.0;             // the layer's top opacity; INSTANCE_CUSTOM.w scales under it
uniform vec4 tint_a : source_color = vec4(0.86, 0.92, 0.98, 1.0);
uniform vec4 tint_b : source_color = vec4(0.71, 0.61, 0.88, 1.0);
uniform vec4 tint_c : source_color = vec4(0.91, 0.71, 0.35, 1.0);

varying float v_kind;
varying float v_alpha;
varying float v_phase;
varying float v_soft;

float wrap(float v, float lo, float size) {
	return lo + mod(v - lo, size);
}

void vertex() {
	vec4 data = INSTANCE_CUSTOM;
	v_phase = data.x;
	v_kind = data.z;
	v_alpha = data.w;
	float t = TIME + data.x * 97.0;
	vec3 p = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	p += drift * TIME;
	p += vec3(sin(t * 0.37), 0.4 * sin(t * 0.23 + 1.7), cos(t * 0.29)) * wobble;
	p.y *= depth_k;      // height_range arrives already scaled
	p.x = wrap(p.x, focus.x - box.x * 0.5, box.x);
	p.z = wrap(p.z, focus.z - box.y * 0.5, box.y);
	p.y = wrap(p.y, height_range.x, height_range.y - height_range.x);
	if (scatter_radius > 0.0) {
		vec2 away = p.xz - player.xz;
		float r = length(away);
		float below = player.y - p.y;
		if (r < scatter_radius && r > 0.001 && below > -0.5 && below < scatter_depth) {
			p.xz += away / r * (scatter_radius - r) * 0.85;
		}
	}
	// Out of focus away from the swim plane: bigger and softer (pre-blurred, no depth of field).
	float off_plane = clamp(abs(p.y) / (8.0 * depth_k), 0.0, 1.0);
	v_soft = off_plane;
	float size = data.y * size_k * (1.0 + 1.5 * off_plane * step(data.z, 1.5));
	// Rods, spirilla and spores turn slowly as they swim.
	float spin = data.x * 6.2832 + TIME * (0.2 + data.x * 0.3) * step(1.5, data.z);
	mat2 rot = mat2(vec2(cos(spin), sin(spin)), vec2(-sin(spin), cos(spin)));
	vec3 view = (VIEW_MATRIX * vec4(p, 1.0)).xyz;
	VERTEX = view + vec3(rot * VERTEX.xy * size, 0.0);
}

float capsule(vec2 q, float half_length, float radius) {
	q.y = max(abs(q.y) - half_length, 0.0);
	return length(q) - radius;
}

void fragment() {
	vec2 q = UV - 0.5;
	float r = length(q);
	float edge = mix(0.04, 0.16, v_soft);
	vec3 col = tint_a.rgb;
	float a = 0.0;
	if (v_kind < 0.5) {
		a = pow(1.0 - smoothstep(0.0, 0.5, r), 1.6);
	} else if (v_kind < 1.5) {
		// An air bubble: a bright rim, a clear middle and one highlight.
		float rim = smoothstep(0.30 - edge, 0.42, r) * (1.0 - smoothstep(0.44, 0.5, r));
		float spot = 1.0 - smoothstep(0.0, 0.07 + edge, length(q - vec2(-0.14, 0.15)));
		a = max(rim * 0.85, spot) + 0.06 * (1.0 - smoothstep(0.4, 0.5, r));
		col = tint_a.rgb;
	} else if (v_kind < 2.5) {
		// A rod bacterium: a plump capsule, lit from the top left, with a darker rim. Never brighter
		// than its tint (pool_ambience.gd MAX_LUMA_ALPHA).
		float d = capsule(q, 0.17, 0.17);
		a = 1.0 - smoothstep(-edge, 0.01, d);
		vec3 base = v_phase < 0.5 ? tint_b.rgb : tint_c.rgb;
		float lit = clamp(0.5 + 2.2 * dot(q, vec2(-0.5, 0.6)), 0.0, 1.0);
		col = base * mix(0.6, 1.0, lit);
		col *= mix(0.75, 1.0, smoothstep(-0.02, -0.06, d));
	} else if (v_kind < 3.5) {
		// A spirillum: a thin helix seen side on.
		float wave = 0.1 * sin(q.y * 9.0 + TIME * 3.0 + v_phase * 6.28);
		float d = abs(q.x - wave) - 0.05;
		a = (1.0 - smoothstep(-0.01, 0.02 + edge, d)) * (1.0 - smoothstep(0.38, 0.48, abs(q.y)));
		col = tint_a.rgb;
	} else {
		// A spore: a small spiky ball.
		float ang = atan(q.y, q.x);
		float d = r - (0.2 + 0.07 * pow(abs(cos(ang * 5.0 + v_phase * 6.28)), 6.0));
		a = 1.0 - smoothstep(-edge, 0.02, d);
		col = tint_c.rgb * mix(1.0, 0.8, smoothstep(0.0, 0.25, r));
	}
	ALBEDO = col;
	ALPHA = clamp(a * v_alpha * opacity, 0.0, 1.0);
}
