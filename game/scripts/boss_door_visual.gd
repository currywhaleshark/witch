extends Node3D
## A segmented door and a light membrane. Arena owns creation, shots, pause and removal.
const MODEL = preload("res://assets/actors/boss_trial_v1/door_v1.glb")
var player: AnimationPlayer
var open_clip := ""
var portal: MeshInstance3D
var elapsed := 0.0
var shot_time := 1.0
var open_fraction := 0.0

func initialize() -> void:
	name = "BossDoorVisual"
	var model := MODEL.instantiate()
	add_child(model)
	player = model.find_children("*", "AnimationPlayer", true, false)[0]
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip in player.get_animation_list():
		if clip == "open" or clip.ends_with("|open") or clip.ends_with("/open"):
			open_clip = clip
	var surface := QuadMesh.new()
	surface.size = Vector2(0.91, 1.87)
	portal = MeshInstance3D.new()
	portal.name = "PortalLight"
	portal.mesh = surface
	portal.position = Vector3(0, 1.13, 0.035)
	portal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform float progress = 0.0;
uniform float pulse = 0.0;
uniform float opacity = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float edge = pow(max(abs(p.x), abs(p.y)), 3.0);
	float bands = 0.5 + 0.5 * sin(p.y * 18.0 - progress * 7.0 + sin(p.x * 8.0));
	ALBEDO = mix(vec3(0.025, 0.055, 0.07), vec3(0.25, 0.75, 0.94), edge * 0.55 + bands * 0.12 + pulse * 0.5);
	ALPHA = opacity * (0.6 + edge * 0.3);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	portal.material_override = material
	add_child(portal)
	sync_effect(0.0, 1.35)

func configure(windup: float) -> void:
	shot_time = maxf(windup, 0.01)
	sync_effect(0.0, shot_time + 0.35)

func sync_effect(dt: float, life: float) -> void:
	elapsed += dt
	open_fraction = smoothstep(0.0, minf(0.4, shot_time * 0.5), elapsed)
	if not open_clip.is_empty():
		if player.current_animation != open_clip: player.play(open_clip)
		player.seek(player.get_animation(open_clip).length * open_fraction, true)
	var mat: ShaderMaterial = portal.material_override
	mat.set_shader_parameter("progress", elapsed)
	mat.set_shader_parameter("pulse", exp(-pow((elapsed - shot_time) / 0.09, 2.0)))
	mat.set_shader_parameter("opacity", open_fraction * smoothstep(0.0, 0.2, life))
