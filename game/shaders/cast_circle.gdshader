shader_type spatial;
// Casting circle on the ground, drawn procedurally in polar coordinates. A shared dial (double
// ring, ticks, inner ring, hub) plus one motif per skill tree:
// 0 firearm: a six-chamber revolver cylinder and a crosshair;
// 1 drive: outer gear teeth, a counter-turning inner gear and spokes;
// 2 automation: a mainspring spiral, clock marks and a five-node network.
// Premultiplied blend keeps the tree colour readable on bright ground (additive washes to white).
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform int tree = 0;
uniform vec4 color : source_color = vec4(1.0, 0.6, 0.3, 1.0);
uniform float appear = 1.0;   // 0..1 sweep-in of the outer ring
uniform float strength = 1.0; // overall brightness
uniform float clock = 0.0;    // the circle's own (pausable) clock


float line(float d, float w) {
	float aa = fwidth(d) * 1.2;
	return 1.0 - smoothstep(w, w + aa, abs(d));
}

float fill(float d) {
	float aa = fwidth(d) * 1.2;
	return 1.0 - smoothstep(0.0, aa, d);
}

float segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

vec2 rotate(vec2 p, float angle) {
	float c = cos(angle), s = sin(angle);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float band(float r, float lo, float hi) {
	return step(lo, r) * step(r, hi);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float swept = fract((a + 3.14159265) / TAU);
	float glow = 0.0;

	// Shared dial.
	glow += line(r - 0.93, 0.010) * step(swept, appear);
	glow += line(r - 0.86, 0.005) * 0.7;
	float ticks = fract((a + clock * 0.35) * 48.0 / TAU);
	glow += line((ticks - 0.5) * r * TAU / 48.0, 0.006) * band(r, 0.875, 0.915) * 0.8;
	glow += line(r - 0.30, 0.008);
	glow += fill(r - 0.055) * 0.9;

	if (tree == 0) {
		// Revolver cylinder: six chambers turning slowly, with a fixed crosshair.
		vec2 q = rotate(p, -clock * 0.4);
		float qa = atan(q.y, q.x);
		float k = floor(qa / (TAU / 6.0) + 0.5);
		vec2 c = 0.58 * vec2(cos(k * TAU / 6.0), sin(k * TAU / 6.0));
		glow += line(length(q - c) - 0.105, 0.009);
		glow += fill(length(q - c) - 0.035) * 0.5;
		float cross_bar = min(max(abs(p.x) - 0.012, 0.0) + max(abs(abs(p.y) - 0.75) - 0.09, 0.0),
			max(abs(p.y) - 0.012, 0.0) + max(abs(abs(p.x) - 0.75) - 0.09, 0.0));
		glow += fill(cross_bar);
		glow += line(r - 0.42, 0.004) * 0.6;
	} else if (tree == 1) {
		// Gears: outer teeth turning one way, an inner gear and spokes the other.
		float outer_tooth = step(0.5, fract((a + clock * 0.3) * 24.0 / TAU));
		glow += band(r, 0.945, 0.99) * outer_tooth * 0.85;
		float inner_tooth = step(0.5, fract((a - clock * 0.6) * 12.0 / TAU));
		glow += band(r, 0.50, 0.56) * inner_tooth * 0.9;
		glow += line(r - 0.50, 0.007);
		glow += line(r - 0.38, 0.006);
		float spoke = fract((a - clock * 0.6) * 6.0 / TAU) - 0.5;
		glow += line(spoke * r * TAU / 6.0, 0.010) * band(r, 0.07, 0.38);
		// Small cogs meshing at four points of the inner gear.
		for (int i = 0; i < 4; i++) {
			float ang = float(i) * TAU / 4.0 + 0.785398 + clock * 0.3;
			vec2 c = 0.70 * vec2(cos(ang), sin(ang));
			vec2 d = p - c;
			float cog = step(0.5, fract((atan(d.y, d.x) + clock * 1.2) * 8.0 / TAU));
			glow += band(length(d), 0.055, 0.085) * cog * 0.8;
			glow += line(length(d) - 0.055, 0.005);
		}
	} else {
		// Automation: mainspring, clock marks and a turning five-node network.
		float coil = (r - 0.07) / 0.032 - (a - clock * 0.8) / TAU;
		glow += line((fract(coil) - 0.5) * 0.032, 0.0045) * band(r, 0.07, 0.27);
		float hour = fract(a * 12.0 / TAU) - 0.5;
		float major = step(abs(fract(a * 4.0 / TAU + 0.5) - 0.5), 0.02);
		glow += line(hour * r * TAU / 12.0, 0.010 + 0.008 * major) * band(r, 0.72 - 0.05 * major, 0.80);
		vec2 nodes[5];
		for (int i = 0; i < 5; i++) {
			float ang = float(i) * TAU / 5.0 + clock * 0.3;
			nodes[i] = 0.52 * vec2(cos(ang), sin(ang));
		}
		for (int i = 0; i < 5; i++) {
			glow += fill(length(p - nodes[i]) - 0.04);
			glow += line(length(p - nodes[i]) - 0.07, 0.005) * 0.8;
			glow += line(segment(p, nodes[i], nodes[(i + 2) % 5]), 0.004) * 0.6;
		}
	}

	// Soft inner wash so the circle reads as light on the ground, not just lines.
	glow += (1.0 - smoothstep(0.0, 0.95, r)) * 0.08;
	glow *= step(r, 1.0);
	float lit = clamp(glow * strength, 0.0, 1.0);
	ALBEDO = color.rgb * lit * 1.35;
	ALPHA = lit * 0.6;
}
