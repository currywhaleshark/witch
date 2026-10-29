shader_type spatial;
// Soft soot/steam puffs. UV2.y carries a per-puff seed so the noise edge differs per puff.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Sin-free hash (Hoskins): stays stable at the reduced float precision of GLES3 devices.
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	vec2 seed = vec2(UV2.y * 23.0, UV2.y * 11.0);
	float n = noise(UV * 3.0 + seed) * 0.6 + noise(UV * 6.0 + seed.yx) * 0.4;
	// GLES3 leaves smoothstep with edge0 > edge1 undefined, so invert explicitly.
	float body = 1.0 - smoothstep(0.1, 0.85, r + (n - 0.5) * 0.4);
	float round_edge = 1.0 - smoothstep(0.8, 1.0, r);
	ALBEDO = COLOR.rgb;
	ALPHA = clamp(body * round_edge * COLOR.a, 0.0, 1.0);
}
