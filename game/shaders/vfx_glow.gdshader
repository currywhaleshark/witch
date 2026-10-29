shader_type spatial;
// Sparks, flashes and slash ribbons. UV2.x selects the falloff:
// 0 = streak (UV.x tail->head, UV.y across), 1 = round glow.
// Premultiplied blend: `cover` hides part of the background so brass/orange hues stay
// saturated on bright ground, and the rest adds light like a glow on dark ground.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float intensity = 1.5;
uniform float cover = 0.55;

void fragment() {
	float a;
	if (UV2.x > 0.5) {
		float d = length(UV * 2.0 - 1.0);
		a = pow(clamp(1.0 - d, 0.0, 1.0), 1.7);
	} else {
		float across = 1.0 - abs(UV.y * 2.0 - 1.0);
		a = across * across * mix(0.08, 1.0, UV.x);
	}
	a = clamp(a * COLOR.a, 0.0, 1.0);
	ALBEDO = COLOR.rgb * intensity * a;
	ALPHA = a * cover;
}
