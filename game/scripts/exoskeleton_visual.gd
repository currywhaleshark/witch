extends "res://tests/helpers/exoskeleton_v4.gd"
## The fitted v4 exoskeleton worn while the exoskeleton skill runs. It follows the review helper's
## contract (assets/equipment/exoskeleton_v4/README.md): a child of the character's Skeleton3D,
## initialize(skeleton), the fitted outfit copy for the civilian form, and
## sync_pose_for_motion(motion, phase) after the body pose is sampled. Presentation only: arena
## owns the skill's clock and bonuses. It fades in and out instead of the part-by-part assembly,
## because its pieces are one skinned rig.
const FADE_SECONDS := 0.25
const FITTED_CIVILIAN := V4_DIR + "outfit_civilian_fit_v4.glb"
var materials: Array[BaseMaterial3D] = []
var shown := 0.0
var swapped_outfit := false

func prepare() -> void:
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface)
			if material is BaseMaterial3D:
				material = material.duplicate()
				mesh.set_surface_override_material(surface, material)
				materials.append(material)
	set_shown(0.0)

func wear(player: Node3D) -> void:
	# The civilian sleeves have an equipment-fitted copy; the transformed outfit needs none.
	if player.form == "civilian" and not swapped_outfit:
		var part: Dictionary = player.PARTS.outfit.duplicate(true)
		part.asset = FITTED_CIVILIAN
		swapped_outfit = player.replace_parts({"outfit": part})

func take_off(player: Node3D) -> void:
	if swapped_outfit:
		player.replace_parts({"outfit": player.PARTS.outfit.duplicate(true)})
		swapped_outfit = false

func set_shown(value: float) -> void:
	shown = clampf(value, 0.0, 1.0)
	for material in materials:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if shown < 0.999 else BaseMaterial3D.TRANSPARENCY_DISABLED
		material.albedo_color.a = shown
	visible = shown > 0.001

static func motion_for(player: Node3D) -> String:
	# The fitted clearance keys are named by motion; map the character's current state onto them.
	match str(player._state):
		"attack": return str(player._attack_clip_kind)
		"hit": return "hit_react"
		"collapse", "dead": return "collapse"
		"cast", "spring_jump", "run": return str(player._state)
		# The v32 tool attacks have no fitted clearance keys; the bolt's area cut reuses the swing.
		"area": return "attack" if str(player._area_clip) == "attack" else "idle"
	return "idle"
