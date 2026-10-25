extends RefCounted
## Deliberately primitive geometry; not production character art.
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

static func enemy(parent: Node3D, heavy: bool) -> Node3D:
	var model = Node3D.new()
	parent.add_child(model)
	var tint = Color("755249") if heavy else Color("55646a")
	box(model, Vector3(0, 0.7, 0), Vector3(0.75, 0.8, 0.56), tint)
	box(model, Vector3(0, 1.22, 0), Vector3(0.58, 0.36, 0.45), Color("9b8c77"))
	box(model, Vector3(0, 1.23, -0.24), Vector3(0.32, 0.075, 0.025), Color("ff946f"))
	for x in [-0.3, 0.3]:
		cylinder(model, Vector3(x, 0.2, 0), 0.16, 0.4, tint)
		box(model, Vector3(x * 1.7, 0.7, 0), Vector3(0.22, 0.65, 0.3), tint)
	if heavy:
		model.scale = Vector3.ONE * 1.15
	return model
