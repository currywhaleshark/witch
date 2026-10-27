extends RefCounted
## Shared primitives and model factories. Unfinished enemy types retain their blockouts.
const ActorVisual = preload("res://scripts/actor_visual.gd")
static func material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.68
	if glow:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 0.65
	return m

static func mesh(parent: Node3D, geometry: Mesh, pos: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.mesh = geometry
	node.material_override = material(color, glow)
	parent.add_child(node)
	node.position = pos
	return node

static func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var geometry = BoxMesh.new()
	geometry.size = size
	return mesh(parent, geometry, pos, color)

static func cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, top: float = -1.0) -> MeshInstance3D:
	var geometry = CylinderMesh.new()
	geometry.bottom_radius = radius
	geometry.top_radius = radius if top < 0 else top
	geometry.height = height
	geometry.radial_segments = 24
	return mesh(parent, geometry, pos, color)

static func sphere(parent: Node3D, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var geometry = SphereMesh.new()
	geometry.radius = radius
	geometry.height = radius * 2
	return mesh(parent, geometry, pos, color)

static func ring(parent: Node3D, pos: Vector3, radius: float, color: Color, width: float = 0.035) -> MeshInstance3D:
	var geometry = TorusMesh.new()
	geometry.inner_radius = maxf(0.01, radius - width)
	geometry.outer_radius = radius + width
	geometry.rings = 32
	geometry.ring_segments = 8
	return mesh(parent, geometry, pos, color, true)

static func fan(parent: Node3D, pos: Vector3, radius: float, angle: float, color: Color) -> MeshInstance3D:
	# Flat circular sector facing -Z (look_at direction), used as a ground warning.
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps = 16
	var half: float = deg_to_rad(angle) / 2.0
	for i in steps:
		var a0: float = -half + 2.0 * half * i / steps
		var a1: float = -half + 2.0 * half * (i + 1) / steps
		surface.add_vertex(Vector3.ZERO)
		surface.add_vertex(Vector3(sin(a1), 0, -cos(a1)) * radius)
		surface.add_vertex(Vector3(sin(a0), 0, -cos(a0)) * radius)
	var node = mesh(parent, surface.commit(), pos, color)
	node.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	return node

static func door_frame(parent: Node3D, pos: Vector3, color: Color) -> Node3D:
	# Hovering wooden door frame for the boss crossfire pattern.
	var frame = Node3D.new()
	parent.add_child(frame)
	frame.position = pos
	for x in [-0.55, 0.55]:
		box(frame, Vector3(x, 1.2, 0), Vector3(0.14, 2.2, 0.14), color)
	box(frame, Vector3(0, 2.3, 0), Vector3(1.24, 0.14, 0.14), color)
	box(frame, Vector3(0, 1.2, 0.02), Vector3(0.96, 2.0, 0.02), Color("1d2a33"))
	return frame

static func body(parent: Node3D, pos: Vector3, layer: int) -> CharacterBody3D:
	var node = CharacterBody3D.new()
	node.collision_layer = layer
	node.collision_mask = 7
	node.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	parent.add_child(node)
	node.position = pos
	var shape = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.5
	shape.shape = capsule
	shape.position.y = 0.75
	node.add_child(shape)
	return node

static func pick_volume(parent: Node3D, radius: float, height: float, layer: int) -> Area3D:
	# Cursor-only volume covering the drawn silhouette at any facing; movement keeps the capsule.
	var area = Area3D.new()
	area.collision_layer = layer
	area.collision_mask = 0
	area.monitoring = false
	parent.add_child(area)
	var shape = CollisionShape3D.new()
	var cylinder_shape = CylinderShape3D.new()
	cylinder_shape.radius = radius
	cylinder_shape.height = height
	shape.shape = cylinder_shape
	shape.position.y = height / 2
	area.add_child(shape)
	return area

static func witch(parent: Node3D) -> Node3D:
	var model = Node3D.new()
	parent.add_child(model)
	cylinder(model, Vector3(0, 0.51, 0), 0.46, 0.65, Color("253e43"), 0.23)
	box(model, Vector3(0, 0.94, 0), Vector3(0.47, 0.4, 0.33), Color("c4ae86"))
	sphere(model, Vector3(0, 1.3, 0), 0.23, Color("edc7ac"))
	sphere(model, Vector3(0, 1.43, 0.09), 0.27, Color("c9d9d2"))
	cylinder(model, Vector3(0, 1.62, 0), 0.51, 0.07, Color("20363f"))
	cylinder(model, Vector3(0, 1.88, 0), 0.32, 0.5, Color("304d54"), 0.035)
	for x in [-0.2, 0.2]:
		box(model, Vector3(x, 0.15, 0), Vector3(0.15, 0.3, 0.24), Color("202d33"))
	var staff = cylinder(model, Vector3(0.57, 0.8, -0.1), 0.045, 1.65, Color("c79a59"))
	staff.name = "Staff"
	box(model, Vector3(0.57, 1.55, -0.1), Vector3(0.34, 0.15, 0.13), Color("b6d3ca"))
	ring(model, Vector3(0.57, 1.69, -0.1), 0.14, Color("8ce7d0"))
	return model

static func enemy(parent: Node3D, kind: String) -> Node3D:
	var actor := ActorVisual.create(parent, kind)
	if actor != null:
		return actor
	# The boss and legacy test types retain their existing silhouettes.
	var model = Node3D.new()
	parent.add_child(model)
	match kind:
		"rag":
			# Soot rag-ghoul: hunched black-plastic heap with torn flyer scraps for a face.
			box(model, Vector3(0, 0.55, 0), Vector3(0.8, 0.75, 0.7), Color("23272b"))
			box(model, Vector3(0, 1.0, -0.05), Vector3(0.55, 0.35, 0.5), Color("2e3338"))
			for x in [-0.14, 0.12]:
				box(model, Vector3(x, 1.02, -0.31), Vector3(0.16, 0.2, 0.02), Color("d9d2bf"))
			for x in [-0.42, 0.42]:
				box(model, Vector3(x, 0.45, -0.1), Vector3(0.14, 0.55, 0.14), Color("1b1e21"))
		"crow":
			# Wire crow: bulb head on a wire-bundle body, frayed cable wings, raised off the ground.
			box(model, Vector3(0, 1.05, 0), Vector3(0.42, 0.36, 0.7), Color("3a3f44"))
			sphere(model, Vector3(0, 1.32, -0.32), 0.17, Color("f2d27a"))
			for x in [-1, 1]:
				var wing = box(model, Vector3(x * 0.45, 1.1, 0.05), Vector3(0.55, 0.05, 0.4), Color("6b5a3e"))
				wing.rotation.z = x * 0.35
			cylinder(model, Vector3(0, 0.5, 0.05), 0.04, 0.9, Color("6b5a3e"))
		"latch":
			# Latch boss: door-frame torso of chained brass locks with a pale blue flame in the gap.
			for x in [-0.4, 0.4]:
				box(model, Vector3(x, 1.0, 0), Vector3(0.18, 1.5, 0.3), Color("6b4a32"))
				box(model, Vector3(x * 1.3, 0.25, 0), Vector3(0.16, 0.5, 0.16), Color("4a3828"))
			box(model, Vector3(0, 1.8, 0), Vector3(1.0, 0.2, 0.3), Color("6b4a32"))
			sphere(model, Vector3(0, 1.1, 0), 0.22, Color("9fd8ff"))
			for y in [0.7, 1.35]:
				box(model, Vector3(0.62, y, -0.1), Vector3(0.26, 0.3, 0.12), Color("c69b62"))
				box(model, Vector3(-0.62, y + 0.15, -0.1), Vector3(0.26, 0.3, 0.12), Color("c69b62"))
		"brute":
			# Iron-door brute: brick body with rusted blue gate leaves strapped to both arms.
			box(model, Vector3(0, 0.75, 0), Vector3(0.85, 0.95, 0.6), Color("8a4b3b"))
			box(model, Vector3(0, 1.36, 0), Vector3(0.5, 0.32, 0.42), Color("6d6255"))
			for x in [-1, 1]:
				box(model, Vector3(x * 0.62, 0.75, -0.12), Vector3(0.12, 1.0, 0.75), Color("3f6fa8"))
				cylinder(model, Vector3(x * 0.28, 0.2, 0), 0.18, 0.4, Color("5a3a30"))
		_:
			var tint = Color("755249") if kind == "heavy" else Color("55646a")
			box(model, Vector3(0, 0.7, 0), Vector3(0.75, 0.8, 0.56), tint)
			box(model, Vector3(0, 1.22, 0), Vector3(0.58, 0.36, 0.45), Color("9b8c77"))
			box(model, Vector3(0, 1.23, -0.24), Vector3(0.32, 0.075, 0.025), Color("ff946f"))
			for x in [-0.3, 0.3]:
				cylinder(model, Vector3(x, 0.2, 0), 0.16, 0.4, tint)
				box(model, Vector3(x * 1.7, 0.7, 0), Vector3(0.22, 0.65, 0.3), tint)
	return model
