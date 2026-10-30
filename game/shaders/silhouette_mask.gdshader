shader_type spatial;
// First overlay pass for marked enemies: writes the body's own pixels into the stencil buffer and
// nothing else, so the outline and aura passes after it can draw only outside the silhouette.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
stencil_mode write, compare_always, 64;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
