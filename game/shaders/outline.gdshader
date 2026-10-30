shader_type spatial;
// Selected-enemy outline: the mesh pushed out along its normals, drawn only where the silhouette
// mask is not set, so just a clean band around the body shows. Width is in metres.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
stencil_mode read, compare_not_equal, 64;

uniform vec4 color : source_color = vec4(1.0, 0.36, 0.30, 1.0);
uniform float width = 0.03;

void vertex() {
	// Keep the band the same world width whatever the enemy's scale.
	float scale = length(MODEL_MATRIX[0].xyz);
	VERTEX += normalize(NORMAL) * width / max(scale, 0.0001);
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = 1.0;
}
