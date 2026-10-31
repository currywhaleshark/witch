shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D color_map : source_color, hint_default_white;
uniform sampler2D normal_map : hint_normal;
uniform sampler2D rough_map : hint_default_white;
uniform sampler2D metal_map : hint_default_white;
uniform vec4 rough_channel = vec4(0.0,1.0,0.0,0.0);
uniform vec4 metal_channel = vec4(0.0,0.0,1.0,0.0);
uniform vec4 base_color : source_color = vec4(1.0);
uniform float roughness_value = 0.8;
uniform float metallic_value = 0.0;
uniform float normal_strength = 0.0;
uniform bool textured_roughness = false;
uniform bool textured_metallic = false;
uniform bool incoming = false;
uniform float sweep_height = -0.1;
uniform mat4 character_from_world;

void fragment() {
    vec3 p = (character_from_world * INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float height = p.y + 0.014 * sin(p.x * 23.0 + p.z * 17.0);
    if (incoming && height > sweep_height) { discard; }
    if (!incoming && height <= sweep_height) { discard; }
    vec4 tex = texture(color_map, UV) * base_color;
    ALBEDO = tex.rgb;
    ROUGHNESS = roughness_value * (textured_roughness ? dot(texture(rough_map, UV), rough_channel) : 1.0);
    METALLIC = metallic_value * (textured_metallic ? dot(texture(metal_map, UV), metal_channel) : 1.0);
    if (!FRONT_FACING) { NORMAL = -NORMAL; }
    if (normal_strength > 0.0) {
        NORMAL_MAP = texture(normal_map, UV).rgb;
        NORMAL_MAP_DEPTH = normal_strength;
    }
    float edge = 1.0 - smoothstep(0.0, 0.045, abs(height - sweep_height));
    EMISSION = mix(vec3(0.22,0.85,0.77), vec3(1.0,0.84,0.50), edge) * edge * 1.5;
}
