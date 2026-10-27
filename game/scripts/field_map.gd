extends Node3D
## Field layout, navigation and sight lines.
## "flat" is the original open test arena: no navmesh, routes are straight lines.
## Any other id loads res://data/maps/<id>.json, builds walls and floors, and bakes a navmesh at runtime.
const Shape = preload("res://scripts/shapes.gd")
const WORLD_LAYER = 1
# Sight lines and orbs fly at chest height, so low walls block feet but not shots.
const SIGHT_HEIGHT = 1.2
const FADE_ALPHA = 0.25
# Navmesh tops of low props (benches, carts) sit above this and are not walkable floor.
const FLOOR_TOP = 0.45
var id = "flat"
var built_iteration = 0
var data: Dictionary = {}
var bounds = Rect2(-14.25, -12.25, 28.5, 24.5)
var region: NavigationRegion3D
var fadeable: Array = []
var faded: Array = []

func build(map_id: String) -> void:
	id = map_id
	for child in get_children():
		child.free()
	fadeable.clear()
	faded.clear()
	region = null
	data = {}
	if map_id == "flat":
		_build_flat()
		return
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % map_id))
	var b: Array = data.bounds
	bounds = Rect2(b[0], b[1], b[2] - b[0], b[3] - b[1])
	region = NavigationRegion3D.new()
	add_child(region)
	var mesh = NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = WORLD_LAYER
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	mesh.agent_radius = 0.5
	mesh.agent_height = 1.5
	mesh.agent_max_climb = 0.25
	region.navigation_mesh = mesh
	for floor_rect in data.floors:
		_solid(region, floor_rect, -0.7, 0.0, Color(floor_rect[4]), false)
	for wall in data.walls:
		_solid(region, wall, 0.0, wall[4], Color(wall[5]), wall[4] > SIGHT_HEIGHT)
	for mark in data.get("marks", []):
		# Flat floor paint (stair treads, kerb lines); purely visual.
		Shape.box(self, Vector3((mark[0] + mark[2]) / 2.0, 0.006, (mark[1] + mark[3]) / 2.0), Vector3(mark[2] - mark[0], 0.012, mark[3] - mark[1]), Color(mark[4]))
	region.bake_navigation_mesh(false)
	# The navigation server picks the new mesh up a few physics frames later; until then
	# routes fall back to straight lines (see nav_ready).
	built_iteration = NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map)

func nav_ready() -> bool:
	return region == null or NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) > built_iteration + 1

func _solid(parent: Node3D, rect: Array, bottom: float, top: float, color: Color, fades: bool) -> void:
	# Axis-aligned block [x0, z0, x1, z1, ...] from bottom to top, with collision on the world layer.
	var size = Vector3(rect[2] - rect[0], top - bottom, rect[3] - rect[1])
	var body = StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	parent.add_child(body)
	body.position = Vector3((rect[0] + rect[2]) / 2.0, (bottom + top) / 2.0, (rect[1] + rect[3]) / 2.0)
	var mesh: MeshInstance3D = Shape.box(body, Vector3.ZERO, size, color)
	var collision = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	if fades:
		body.set_meta("fade", true)
		fadeable.append({"body": body, "mesh": mesh})

func _build_flat() -> void:
	bounds = Rect2(-14.25, -12.25, 28.5, 24.5)
	Shape.box(self, Vector3(0, -0.35, 0), Vector3(30, 0.7, 26), Color("334a50"))
	for x in range(-14, 15, 2):
		Shape.box(self, Vector3(x, 0.005, 0), Vector3(0.025, 0.01, 25.6), Color("40595e"))
	for z in range(-12, 13, 2):
		Shape.box(self, Vector3(0, 0.005, z), Vector3(29.6, 0.01, 0.025), Color("40595e"))
	Shape.ring(self, Vector3(0, 0.02, 0), 5.0, Color("59716d"), 0.025)
	Shape.ring(self, Vector3(0, 0.02, 0), 5.2, Color("8a795a"), 0.025)
	for wall in [[-15.25, -13, -14.75, 13], [14.75, -13, 15.25, 13], [-15, -13.25, 15, -12.75], [-15, 12.75, 15, 13.25]]:
		_solid(self, wall, 0.0, 1.2, Color("233740"), false)
	for x in [-14, 14]:
		for z in [-12, -6, 0, 6, 12]:
			Shape.cylinder(self, Vector3(x, 0.65, z), 0.3, 1.3, Color("c69b62"))
			Shape.sphere(self, Vector3(x, 1.35, z), 0.15, Color("8dd8c4"))

func start_point() -> Vector3:
	return Vector3(0, 0, 2) if data.is_empty() else Vector3(data.start[0], 0, data.start[1])

func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	# Waypoints from one point to another; a straight line where there is no navmesh.
	if region == null or not nav_ready():
		return PackedVector3Array([to])
	var points = NavigationServer3D.map_get_path(get_world_3d().navigation_map, from, to, true)
	return points if not points.is_empty() else PackedVector3Array([to])

func snap(pos: Vector3) -> Vector3:
	# Nearest walkable point: clicks on walls or the void move to their edge.
	if region == null or not nav_ready():
		return pos
	var near: Vector3 = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, pos)
	return Vector3(near.x, 0, near.z) if near.y < FLOOR_TOP else pos

func walkable(pos: Vector3) -> bool:
	if not bounds.has_point(Vector2(pos.x, pos.z)):
		return false
	if region == null or not nav_ready():
		return true
	var near: Vector3 = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, pos)
	return near.y < FLOOR_TOP and Vector2(near.x - pos.x, near.z - pos.z).length() < 0.35

func sees(a: Vector3, b: Vector3) -> bool:
	# Chest-height sight line; tall walls and props block it, low walls do not.
	var query = PhysicsRayQueryParameters3D.create(Vector3(a.x, SIGHT_HEIGHT, a.z), Vector3(b.x, SIGHT_HEIGHT, b.z), WORLD_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func zone_at(pos: Vector3) -> Dictionary:
	for zone in data.get("zones", []):
		var r: Array = zone.rect
		if pos.x >= r[0] and pos.x <= r[2] and pos.z >= r[1] and pos.z <= r[3]:
			return zone
	return {}

func respawn_point(witch: Vector3, rng: RandomNumberGenerator) -> Vector3:
	# A5 re-entry away from the witch: field edges on the flat arena, listed spots on a map.
	if data.is_empty():
		var pos = Vector3.ZERO
		for attempt in 12:
			var along = rng.randf_range(-1, 1)
			pos = [Vector3(13, 0, along * 11), Vector3(-13, 0, along * 11), Vector3(along * 13, 0, 11), Vector3(along * 13, 0, -11)][rng.randi() % 4]
			if pos.distance_to(witch) >= 8:
				break
		return pos
	var far: Array = []
	for spot in data.respawns:
		var at = Vector3(spot[0], 0, spot[1])
		if at.distance_to(witch) >= 10:
			far.append(at)
	if far.is_empty():
		far = data.respawns.map(func(spot): return Vector3(spot[0], 0, spot[1]))
	return far[rng.randi() % far.size()]

func fade_between(eye: Vector3, target: Vector3) -> void:
	# Tall walls between the camera and the witch turn see-through; everything else stays solid.
	var hits: Array = []
	var exclude: Array[RID] = []
	var space = get_world_3d().direct_space_state
	for attempt in 4:
		var query = PhysicsRayQueryParameters3D.create(eye, target, WORLD_LAYER, exclude)
		var hit = space.intersect_ray(query)
		if hit.is_empty():
			break
		exclude.append(hit.rid)
		if hit.collider.has_meta("fade"):
			hits.append(hit.collider)
	for entry in fadeable:
		var want: bool = hits.has(entry.body)
		var material: StandardMaterial3D = entry.mesh.material_override
		var color: Color = material.albedo_color
		if want and not faded.has(entry.body):
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color = Color(color, FADE_ALPHA)
			faded.append(entry.body)
		elif not want and faded.has(entry.body):
			material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			material.albedo_color = Color(color, 1.0)
			faded.erase(entry.body)
