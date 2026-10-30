extends Node3D
## Folding shields. Presentation only: the arena owns the shield clock and every block roll.
## Two tri-fold panels assemble folded at the witch's sides, swing their flaps open, hover there
## for the shield's duration (the one nearer a threat recoils on a block), then fold and come apart.
const PARTS = preload("res://assets/props/folding_shield_v1/folding_shield.glb")
const ASSEMBLE_SECONDS := 0.3
const OPEN_SECONDS := 0.22
const CLOSE_SECONDS := 0.16
const SCATTER_SECONDS := 0.4
const SCALE := 1.15
# Panel placement in the witch's facing frame (forward is -Z): out to each side, a little ahead,
# each turned 55 degrees outward and leaned back slightly.
const SIDE_OFFSET := Vector3(0.66, 0.68, -0.1)
const TURN := deg_to_rad(55.0)
const TILT := deg_to_rad(8.0)
# Flap hinge angles: open is bent slightly forward into a shallow cup, closed is folded behind.
const FLAP_OPEN := 0.25
const FLAP_CLOSED := PI * 0.96
const TEAL := Color(0.35, 0.95, 0.85)

var panels: Array[Dictionary] = []
var mode := "assembling"
var age := 0.0
var _end := 0.0
var _yaw := 0.0
var _opening := 0.0
var _arena: Node3D

func initialize(arena: Node3D, at: Vector3, facing_yaw: float) -> void:
	_arena = arena
	name = "FoldingShields"
	top_level = true
	_yaw = facing_yaw
	for side in [-1.0, 1.0]:
		var holder := Node3D.new()
		holder.scale = Vector3.ONE * SCALE
		add_child(holder)
		var model: Node3D = PARTS.instantiate()
		holder.add_child(model)
		var parts: Array[Dictionary] = []
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		meshes.sort_custom(func(a, b): return str(a.name) < str(b.name))
		for mesh: MeshInstance3D in meshes:
			var rest: Transform3D = holder.global_transform.affine_inverse() * mesh.global_transform
			mesh.reparent(holder, true)
			mesh.transform = rest
			var materials: Array[StandardMaterial3D] = []
			var glow: Array[bool] = []
			for surface in mesh.mesh.get_surface_count():
				var material: StandardMaterial3D = mesh.get_active_material(surface).duplicate()
				mesh.set_surface_override_material(surface, material)
				materials.append(material)
				# Already emissive (the teal core and port) keeps its own glow throughout.
				glow.append(material.emission_enabled)
			var part_name := str(mesh.name)
			var hinge := 1.0 if part_name.ends_with("_R") else (-1.0 if part_name.ends_with("_L") else 0.0)
			# The centre plate arrives first, then each flap swings in from its own side.
			var outward := Vector3(hinge * 0.8 + side * 0.4, 0.5, 0.3).normalized()
			parts.append({"mesh": mesh, "materials": materials, "glow": glow, "rest": rest, "hinge": hinge, "outward": outward,
				"start": rest.origin + outward * 0.5, "spin": Basis(Vector3(0.3, 1.0, 0.2).normalized(), 1.3 * (1.0 + hinge * 0.3)),
				"delay": 0.0 if hinge == 0.0 else 0.18 + 0.06 * (hinge + 1.0) * 0.5})
		model.queue_free()
		var light := OmniLight3D.new()
		light.light_color = TEAL; light.omni_range = 0.9; light.light_energy = 0.0; light.shadow_enabled = false
		light.position = Vector3(0, 0.03, 0.35)
		holder.add_child(light)
		panels.append({"node": holder, "side": side, "parts": parts, "light": light, "recoil": 0.0})
	_place(at)
	_pose(0.0)

func sync(dt: float, at: Vector3, facing_yaw: float, active: bool) -> void:
	# Called by the arena on its own (pausable) clock.
	age += dt
	_yaw = lerp_angle(_yaw, facing_yaw, minf(1.0, dt * 12.0))
	for panel in panels:
		panel.recoil = maxf(0.0, panel.recoil - dt)
	if not active and mode in ["assembling", "open"]:
		mode = "closing"; _end = 0.0
	if mode in ["closing", "scatter"]:
		_end += dt
		if mode == "closing" and _end >= CLOSE_SECONDS:
			mode = "scatter"; _end = 0.0
		elif mode == "scatter" and _end >= SCATTER_SECONDS:
			queue_free()
			return
	elif age >= ASSEMBLE_SECONDS + OPEN_SECONDS and mode == "assembling":
		mode = "open"
		_lock_flourish()
	_place(at)
	_pose(dt)

func block(threat: Vector3) -> Vector3:
	# A blocked hit: the panel on the threat's side kicks back and its core flares. Returns its face.
	var right := Basis(Vector3.UP, _yaw) * Vector3.RIGHT
	var side := 1.0 if (threat - global_position).dot(right) >= 0.0 else -1.0
	for panel in panels:
		if panel.side == side:
			panel.recoil = 0.18
			panel.light.light_energy = 3.0
			return panel.node.global_position + panel.node.global_basis * Vector3(0, 0.05, 0.06)
	return global_position

func dismiss() -> void:
	if mode != "scatter":
		mode = "scatter"; _end = 0.0

func _place(at: Vector3) -> void:
	position = at
	rotation = Vector3(0, _yaw, 0)
	for panel in panels:
		var side: float = panel.side
		var bob := 0.02 * sin(age * 3.0 + side)
		var offset := Vector3(side * SIDE_OFFSET.x, SIDE_OFFSET.y + bob, SIDE_OFFSET.z)
		# The model's emblem side faces its local +Z; turn it to face out along -Z.
		var basis := Basis(Vector3.UP, -side * TURN) * Basis(Vector3.RIGHT, TILT) * Basis(Vector3.UP, PI)
		if panel.recoil > 0.0:
			offset -= basis * Vector3(0, 0, 0.08 * sin(panel.recoil / 0.18 * PI))
		panel.node.position = offset
		panel.node.basis = basis.scaled(Vector3.ONE * SCALE)

func _lock_flourish() -> void:
	if not is_instance_valid(_arena):
		return
	_arena.play_cue(2.1, -6.0)
	for panel in panels:
		panel.light.light_energy = 2.2
		var fx = _arena.spawn_vfx()
		var face: Vector3 = panel.node.global_position
		fx.flash(face, 0.26, TEAL.lightened(0.3), 0.12, 1.0)
		fx.sparks(face, Vector3.UP, 8, 3.0, 0.9, Color(1.0, 0.78, 0.45), 0.3, 0.012, _arena.map.ground_y(face))

func _pose(dt: float) -> void:
	var assemble := clampf(age / ASSEMBLE_SECONDS, 0.0, 1.0)
	if mode in ["assembling", "open"]:
		_opening = smoothstep(0.0, 1.0, clampf((age - ASSEMBLE_SECONDS) / OPEN_SECONDS, 0.0, 1.0))
	elif mode == "closing":
		_opening = 1.0 - smoothstep(0.0, 1.0, _end / CLOSE_SECONDS)
	var scatter := smoothstep(0.0, 1.0, _end / SCATTER_SECONDS) if mode == "scatter" else 0.0
	for panel in panels:
		var light: OmniLight3D = panel.light
		# A faint standing glow; locking and blocking flare it and it eases back down.
		light.light_energy = maxf(0.12 * _opening * (1.0 - scatter), light.light_energy - dt * 6.0)
		for part in panel.parts:
			var mesh: MeshInstance3D = part.mesh
			var rest: Transform3D = part.rest
			var hinge: float = part.hinge
			var arrive := smoothstep(0.0, 1.0, clampf((assemble - float(part.delay)) / 0.55, 0.0, 1.0))
			var spin: Basis = part.spin
			var basis: Basis = spin.slerp(Basis.IDENTITY, arrive) * rest.basis
			if hinge != 0.0:
				# Flaps turn about their own hinge (their origin): folded behind, then open slightly cupped.
				basis = Basis(Vector3.UP, hinge * lerpf(FLAP_CLOSED, -FLAP_OPEN, _opening)) * basis
			var origin: Vector3 = (part.start as Vector3).lerp(rest.origin, arrive)
			if scatter > 0.0:
				origin += (part.outward as Vector3) * scatter * 0.45 + Vector3.DOWN * scatter * scatter * 0.3
				basis = Basis.IDENTITY.slerp(spin, scatter) * basis
			mesh.transform = Transform3D(basis, origin)
			mesh.visible = mode != "assembling" or assemble > float(part.delay) * 0.9
			var alpha := arrive * (1.0 - scatter)
			for index in part.materials.size():
				var material: StandardMaterial3D = part.materials[index]
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 0.999 else BaseMaterial3D.TRANSPARENCY_DISABLED
				material.albedo_color.a = alpha
				if not part.glow[index]:
					# Pieces glow teal while they fly in or come apart, like the summon assemblies.
					material.emission_enabled = true
					material.emission = TEAL
					material.emission_energy_multiplier = (1.0 - arrive) * 0.9 + scatter * 0.6

func debug_state() -> Dictionary:
	return {"mode": mode, "age": age, "panels": panels.size(), "opening": _opening}
