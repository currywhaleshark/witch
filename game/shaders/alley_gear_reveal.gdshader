shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform sampler2D slab_texture : source_color, filter_linear_mipmap;
uniform sampler2D gear_texture : source_color, filter_linear_mipmap;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
// The complete wheel remains independent; a future animation may drive this angle.
uniform float gear_angle = 0.0;
void fragment() {
	vec4 slab = texture(slab_texture, UV);
	vec2 p = (UV - vec2(0.53, 0.50)) * vec2(3.0, 2.0) / 2.4;
	float c = cos(gear_angle);
	float s = sin(gear_angle);
	vec2 wheel_uv = mat2(vec2(c, s), vec2(-s, c)) * p + vec2(0.5);
	vec4 wheel = texture(gear_texture, wheel_uv);
	float jagged = 0.018 * sin(UV.y * 77.0) + 0.011 * sin(UV.x * 93.0);
	float rim = length((UV - vec2(0.57, 0.51)) / vec2(0.41, 0.44));
	float aperture = 1.0 - smoothstep(0.91 + jagged, 0.95 + jagged, rim);
	aperture *= smoothstep(0.28 + jagged, 0.30 + jagged, UV.x);
	vec3 underneath = mix(vec3(0.045, 0.048, 0.052), wheel.rgb * 0.72, wheel.a);
	ALBEDO = mix(slab.rgb, underneath, aperture);
	ALPHA = slab.a * opacity;
	ROUGHNESS = 1.0;
}
