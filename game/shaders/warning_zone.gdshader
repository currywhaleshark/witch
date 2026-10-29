shader_type spatial;
// Ground attack warnings. The outline mesh keeps its full size and draws edges plus moving
// hazard stripes; the fill mesh is scaled by the arena from the attacker outwards, so its local
// edge is always the leading front and glows brightest there.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.91, 0.38, 0.30, 1.0);
uniform vec4 edge : source_color = vec4(1.0, 0.62, 0.36, 1.0);
uniform int kind = 0;            // 0 radial (fan/disc), 1 strip
uniform float extent = 1.0;      // radius or strip length (m)
uniform float width = 1.0;       // strip width (m)
uniform float half_angle = 3.2;  // fan half angle (rad); >= PI for a full disc
uniform bool filled = false;

varying vec3 local_pos;
varying vec3 world_pos;

void vertex() {
	local_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float front;
	float rim;
	if (kind == 0) {
		float r = length(local_pos.xz);
		front = r / extent;
		rim = extent - r;
		if (half_angle < 3.1) {
			float ang = abs(atan(local_pos.x, -local_pos.z));
			rim = min(rim, r * sin(max(half_angle - ang, 0.0)));
		}
	} else {
		front = 0.5 - local_pos.z / extent;
		rim = min(min(width * 0.5 - abs(local_pos.x), (1.0 - front) * extent), front * extent);
	}
	float line = 1.0 - smoothstep(0.03, 0.075, rim);
	vec3 color;
	float alpha;
	if (filled) {
		float lead = smoothstep(0.72, 1.0, front);
		color = mix(tint.rgb, edge.rgb, lead);
		alpha = 0.16 + 0.34 * lead + 0.4 * smoothstep(0.955, 0.995, front);
	} else {
		float stripe = step(0.55, fract((world_pos.x + world_pos.z) * 1.6 - TIME * 0.7));
		float pulse = 0.5 + 0.5 * sin(TIME * 9.0);
		color = mix(tint.rgb * 0.7, edge.rgb, line);
		alpha = mix(0.07 + 0.07 * stripe, 0.7 + 0.2 * pulse, line);
	}
	ALBEDO = color;
	ALPHA = alpha;
}
