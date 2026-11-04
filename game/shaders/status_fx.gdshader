shader_type spatial;
// Enemy status markers. floor(UV2.x) picks the shape and fract(UV2.x) is a shape parameter;
// UV2.y is how much background it hides (premultiplied: 1 = opaque like a drop of blood or a
// cable, ~0.5 = a glow that also adds light).
// 0 = soft round glow, 1 = band (UV.y across a strip; param = hardness),
// 2 = five-point star, 3 = cracked shield (param = how far the halves have split), 4 = drop.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

float star(vec2 p) {
	float angle = atan(p.x, p.y);
	float sector = 6.2831853 / 5.0;
	float a = mod(angle + sector * 0.5, sector) - sector * 0.5;
	float edge = mix(1.0, 0.45, smoothstep(0.0, sector * 0.5, abs(a)));
	return 1.0 - smoothstep(edge - 0.12, edge, length(p));
}

float shield(vec2 p) {
	// Flat top, straight upper sides, tapering to a point below.
	float width = p.y > 0.3 ? 0.78 : mix(0.0, 0.78, clamp((p.y + 0.92) / 1.22, 0.0, 1.0));
	float side = 1.0 - smoothstep(width - 0.07, width, abs(p.x));
	float top = 1.0 - smoothstep(0.74, 0.8, p.y);
	return side * top * step(-0.92, p.y);
}

float zig(float y) {
	// The crack: a zigzag running top to bottom.
	return 0.14 * (abs(fract(y * 1.6 + 0.25) * 2.0 - 1.0) * 2.0 - 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	float shape = floor(UV2.x + 0.001);
	float param = fract(UV2.x + 0.001);
	float a = 0.0;
	vec3 color = COLOR.rgb;
	if (shape < 0.5) {
		a = pow(clamp(1.0 - length(p), 0.0, 1.0), 1.6);
	} else if (shape < 1.5) {
		float across = 1.0 - abs(UV.y * 2.0 - 1.0);
		a = smoothstep(0.0, mix(0.9, 0.25, param), across);
		// A cable reads round: lighter along its middle.
		color = mix(color, color * 1.6 + 0.08, param * smoothstep(0.55, 1.0, across));
	} else if (shape < 2.5) {
		a = star(p * 1.08);
		color = mix(color, vec3(1.0), 0.6 * (1.0 - smoothstep(0.0, 0.45, length(p))));
	} else if (shape < 3.5) {
		float side = p.x - zig(p.y) < 0.0 ? -1.0 : 1.0;
		vec2 q = p - vec2(side * param * 0.5, -param * 0.12);
		float inside = step(0.05, (q.x - zig(q.y)) * side);
		float fill = shield(q) * inside;
		float rim = clamp(fill - shield(q * 1.22) * step(0.14, (q.x - zig(q.y)) * side), 0.0, 1.0);
		a = rim + fill * 0.32;
		color = mix(color * 0.55, color, rim);
	} else {
		// A drop: round below, pointed above, with a small highlight.
		vec2 q = vec2(p.x, p.y + 0.25);
		float body = 1.0 - smoothstep(0.6, 0.7, length(q));
		float half_width = mix(0.55, 0.0, clamp(p.y / 0.95, 0.0, 1.0));
		float tip = (1.0 - smoothstep(half_width - 0.08, half_width, abs(p.x))) * step(0.0, p.y) * step(p.y, 0.95);
		a = max(body, tip);
		color = mix(color, color * 1.9 + 0.12, 1.0 - smoothstep(0.0, 0.22, length(q - vec2(-0.2, 0.12))));
	}
	a = clamp(a * COLOR.a, 0.0, 1.0);
	ALBEDO = color * a;
	ALPHA = a * UV2.y;
}
