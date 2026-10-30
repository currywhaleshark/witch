shader_type spatial;
// Champion/elite aura: a wider inflated shell, drawn additively only outside the silhouette mask,
// fading outward and flickering upward like heat, in the grade colour. Presentation only.
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
stencil_mode read, compare_not_equal, 64;

uniform vec4 color : source_color = vec4(0.5, 0.65, 1.0, 1.0);
uniform float width = 0.07;
uniform float strength = 0.55;

varying vec3 world_pos;

void vertex() {
	float scale = length(MODEL_MATRIX[0].xyz);
	VERTEX += normalize(NORMAL) * width / max(scale, 0.0001);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Brightest next to the body (facing the camera), fading toward the shell's own edge.
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float falloff = smoothstep(0.0, 0.6, facing);
	float flicker = 0.6 + 0.4 * sin(world_pos.y * 8.0 - TIME * 4.0 + world_pos.x * 4.0 + world_pos.z * 3.0);
	float breath = 0.8 + 0.2 * sin(TIME * 2.2);
	ALBEDO = color.rgb;
	ALPHA = clamp(falloff * flicker * breath * strength, 0.0, 1.0);
}
