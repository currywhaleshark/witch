extends RefCounted
## Prepared art presentation only. Skill rules, targets and ranges belong to game code.
static func prepare(model: Node3D) -> void:
	if model.has_meta("batch2_glow_materials"): return
	var materials: Array[StandardMaterial3D] = []
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var source: Material = mi.mesh.surface_get_material(i)
			if source is StandardMaterial3D and source.emission_enabled:
				var material: StandardMaterial3D = source.duplicate()
				mi.set_surface_override_material(i, material)
				materials.append(material)
	model.set_meta("batch2_glow_materials", materials)

static func sample(model: Node3D, actor: String, clip: String, seconds: float) -> void:
	prepare(model)
	var energy := 1.3
	if actor == "beacon":
		if clip == "deploy": energy *= smoothstep(.35, .50, seconds)
		elif clip == "shutdown": energy *= 1.0 - smoothstep(0.0, .12, seconds)
		elif clip == "death": energy *= 1.0 - smoothstep(.02, .08, seconds)
	elif actor == "giant":
		if clip == "assemble": energy *= smoothstep(1.10, 1.20, seconds)
		elif clip == "death": energy *= 1.0 - smoothstep(.18, .35, seconds)
	for material in model.get_meta("batch2_glow_materials"):
		material.emission_energy_multiplier = energy
	if actor == "giant": sample_steam(model, clip, seconds)

static func sample_steam(model: Node3D, clip: String, seconds: float) -> void:
	# Six small socket-following billboards, deterministic for seeking and pausing.
	# Prepared presentation helper; no gameplay, collision or weather simulation.
	if not model.has_meta("batch2_steam"):
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, .35, 1.0])
		gradient.colors = PackedColorArray([Color(1,1,1,.40), Color(1,1,1,.22), Color(1,1,1,0)])
		var texture := GradientTexture2D.new(); texture.gradient = gradient
		texture.width = 64; texture.height = 64; texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(.5,.5); texture.fill_to = Vector2(1,.5)
		var quad := QuadMesh.new(); quad.size = Vector2.ONE
		var puffs: Array[MeshInstance3D] = []
		for i in 6:
			var puff := MeshInstance3D.new(); puff.mesh = quad; puff.name = "PreparedSteam" + str(i)
			var material := StandardMaterial3D.new(); material.albedo_texture = texture
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			puff.material_override = material; puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			model.add_child(puff); puffs.append(puff)
		model.set_meta("batch2_steam", puffs)
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var puffs: Array = model.get_meta("batch2_steam")
	for i in puffs.size():
		var puff: MeshInstance3D = puffs[i]
		puff.visible = clip in ["idle", "walk", "slam", "hit"]
		if not puff.visible: continue
		var socket := skeleton.find_bone("Socket_exhaust." + ("L" if i < 3 else "R"))
		var source := model.to_local(skeleton.to_global(skeleton.get_bone_global_pose(socket).origin))
		var age := fposmod(seconds + float(i % 3) / 3.0, 1.0)
		puff.position = source + Vector3(.035 * sin(age * 4.0 + i), age * .46, 0)
		puff.scale = Vector3.ONE * lerpf(.10, .28, age)
		var material: StandardMaterial3D = puff.material_override
		material.albedo_color = Color(.67,.79,.79, smoothstep(0.0,.13,age) * (1.0-smoothstep(.55,1.0,age)))
