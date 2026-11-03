extends "res://scripts/summon_assembly.gd"
## Asset-review only. Deterministic presentation samples, no gameplay, RNG or collision.
var asset_id := ""
var manifest: Dictionary = {}
var part_info: Dictionary = {}

func configure(id: String) -> void:
	asset_id = id
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons/firearm_tree_v1/%s.json" % id))
	parts_scene = load("res://assets/weapons/firearm_tree_v1/%s.glb" % id)
	assembly_name = "FirearmReview_" + id
	effect_radius = .32
	effect_height = .35
	for item in manifest.parts:
		part_delays[item.name] = float(item.delay)
		part_info[item.name] = item

func point(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

func around(pivot: Vector3, axis: Vector3, angle: float) -> Transform3D:
	var basis := Basis(axis, angle)
	return Transform3D(basis, pivot - basis * pivot)

func _light(phase: float, strength: float) -> void:
	super._light(phase, strength)
	# Static art views should contain only the model, with no additive zero-alpha residue.
	_ring.visible = strength > .001
	_core.visible = strength > .001
	for mote in _motes: mote.visible = strength > .001

func sample_demo(seconds: float) -> void:
	# Sampling from rest each time makes the review scrubber reversible and repeatable.
	mode = "assembling"
	_core.position = Vector3(0, effect_height * .465, 0)
	_core.scale = Vector3.ONE
	_core.material_override.albedo_color = Color.WHITE
	sample_progress(clampf(seconds / .65, 0.0, 1.0))
	if seconds < .65:
		return
	_light(1.0, 0.0)
	if asset_id == "gatling":
		var pivot := point(manifest.sockets.Socket_rotor.position)
		var transform := around(pivot, Vector3.BACK, (seconds - .65) * TAU * 1.5)
		for part in parts:
			if part_info[part.name].group == "rotor":
				part.mesh.transform = transform * part.target
	elif asset_id == "powder_barrel":
		var pivot := point(manifest.sockets.Socket_roll_axis.position)
		var distance := minf(maxf(seconds - .65, 0.0) * .65, .90)
		var roll := around(pivot, Vector3.RIGHT, -distance / .248)
		roll.origin.z -= distance
		var fuse_progress := clampf((seconds - .65) / 1.95, 0.0, 1.0)
		for i in parts.size():
			var part: Dictionary = parts[i]
			var info: Dictionary = part_info[part.name]
			part.mesh.transform = roll * part.target
			if info.group == "fuse":
				if info.role == "fuse_ember":
					part.mesh.visible = seconds < 2.60
					# Move the ember down the actual authored fuse, tip -> socket.
					var seg := mini(7, int(floor((1.0 - fuse_progress) * 8.0)))
					var fuse_name := "powder_barrel__fuse_%02d" % seg
					part.mesh.position = roll * point(part_info[fuse_name].origin)
				else:
					var index := int(str(info.role).trim_prefix("fuse_"))
					part.mesh.visible = float(index) < (1.0 - fuse_progress) * 8.0
			elif seconds >= 2.60:
				var t := seconds - 2.60
				var outward: Vector3 = (part.target.origin - pivot).normalized()
				if outward.length() < .01: outward = Vector3.RIGHT
				part.mesh.position += outward * t * 1.20 + Vector3.UP * (1.4 * t - 2.8 * t * t)
				part.mesh.basis = Basis(part.axis, t * (2.0 + i % 3)) * part.mesh.basis
				# Cosmetic floor clamp only; the skill has no live physics implementation yet.
				var low := INF
				for corner in part.corners: low = minf(low, (part.mesh.transform * corner).y)
				if low < 0.0: part.mesh.position.y -= low
				_opacity(part, 1.0 - smoothstep(.45, .90, t), 0.0)
		if seconds >= 2.60 and seconds < 2.77:
			_core.visible = true
			_core.position = pivot + Vector3(0, 0, -.9)
			_core.scale = Vector3.ONE * (1.0 + (seconds - 2.60) * 6.0)
			_core.material_override.albedo_color = Color(1.0,.63,.20,1.0-(seconds-2.60)/.17)
	elif asset_id == "smoke_launcher":
		for part in parts:
			var group: String = part_info[part.name].group
			if group.begins_with("canister_"):
				var index := int(group.trim_prefix("canister_"))
				var t := maxf(0.0, seconds - 1.10 - index * .14)
				var direction := point(manifest.sockets["Socket_launch_%s" % index].direction)
				part.mesh.position += direction * t * 1.5 + Vector3.DOWN * .35 * t * t
				_opacity(part, 1.0 - smoothstep(.32, .62, t), 0.0)
	elif asset_id in ["matchlock", "rifle", "shotgun"]:
		var kick := maxf(0.0, 1.0 - absf(seconds - 1.40) / .14)
		for part in parts: part.mesh.position.z += kick * .07
		if seconds > 2.05:
			var fade := smoothstep(2.05, 2.65, seconds)
			for part in parts:
				part.mesh.position += part.outward * fade * .12 + Vector3.UP * fade * .12
				_opacity(part, 1.0 - fade, fade * .3)
