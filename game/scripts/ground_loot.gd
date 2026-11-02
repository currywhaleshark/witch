extends RefCounted
## Ground spacing and screen labels share one hit layout; neither consumes gameplay RNG.
const SPACING := 0.7
const PICK_RADIUS := 14.0
const FONT_SIZE := 13
const LABEL_GAP := 4.0
const LABEL_SECONDS := 5.0
const DROP_SECONDS := 0.4
const DROP_HEIGHT := 0.95
var cached_key: Array = []
var cached_labels: Array = []

static func pose_drop(visual: Node3D, age: float) -> void:
	var phase := clampf(age / DROP_SECONDS, 0.0, 1.0)
	# Start at waist height, accelerate downward, and tumble once before resting flat.
	visual.position.y = DROP_HEIGHT * (1.0 - phase * phase)
	visual.rotation = Vector3(TAU * phase, 0.7 * sin(PI * phase), 0.35 * sin(PI * phase)) if phase < 1.0 else Vector3.ZERO

static func find_position(field: Node3D, at: Vector3, drops: Array):
	var origin: Vector3 = field.snap(at)
	origin.x = clampf(origin.x, field.bounds.position.x + SPACING, field.bounds.end.x - SPACING)
	origin.z = clampf(origin.z, field.bounds.position.y + SPACING, field.bounds.end.y - SPACING)
	# Expanding rings keep repeated drops near their source, including along walls and edges.
	var rings := ceili(field.bounds.size.length() / SPACING) + 1
	for ring in rings:
		var samples := maxi(1, ring * 8)
		for sample in samples:
			var angle := TAU * float(sample) / samples
			var point := origin + Vector3(cos(angle), 0, sin(angle)) * (ring * SPACING)
			if not field.bounds.has_point(Vector2(point.x, point.z)):
				continue
			var occupied := false
			for loot in drops:
				if is_instance_valid(loot.node) and Vector2(point.x - loot.node.position.x, point.z - loot.node.position.z).length_squared() < SPACING * SPACING - 0.00001:
					occupied = true
					break
			if not occupied and field.walkable(point):
				return field.grounded(point)
	# A completely full field defers this drop until a pickup makes room, rather than stacking it.
	return null

func labels(drops: Array, camera: Camera3D, font: Font, viewport_size: Vector2, shown_ids: Array, focused_id: int) -> Array:
	var key: Array = [drops.size(), camera.global_transform, camera.size, camera.fov, viewport_size, shown_ids, focused_id]
	if key == cached_key:
		return cached_labels
	cached_key = key
	var previous_labels := cached_labels
	cached_labels = []
	var area := Rect2(Vector2(8, 8), Vector2(viewport_size.x - 16, viewport_size.y - 179))
	var discs: Array[Rect2] = []
	var visible_drops: Array = []
	for loot in drops:
		if not is_instance_valid(loot.node) or camera.is_position_behind(loot.visual.global_position):
			continue
		var anchor := camera.unproject_position(loot.visual.global_position)
		if not area.has_point(anchor):
			continue
		if shown_ids.has(loot.node.get_instance_id()):
			if loot.node.get_instance_id() == focused_id:
				visible_drops.push_front(loot)
			else:
				visible_drops.append(loot)
		discs.append(Rect2(anchor - Vector2.ONE * PICK_RADIUS, Vector2.ONE * PICK_RADIUS * 2))
	for loot in visible_drops:
		var anchor := camera.unproject_position(loot.visual.global_position)
		var above := camera.unproject_position(loot.visual.global_position + Vector3.UP * 0.3)
		var size := Vector2(font.get_string_size(loot.name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 14, ceilf(font.get_height(FONT_SIZE)) + 8)
		var base := Rect2(above - Vector2(size.x / 2, size.y - 4), size)
		base.position = base.position.clamp(area.position, (area.end - size).max(area.position))
		# Test the nearest rows/columns first. A separate column handles dense piles without
		# pushing every label off the top of the screen. Existing item discs stay unobscured.
		var candidates: Array[Rect2] = []
		var pitch := size + Vector2.ONE * LABEL_GAP
		var columns := ceili(area.size.x / pitch.x)
		var rows := ceili(area.size.y / pitch.y)
		for x in range(-columns, columns + 1):
			for y in range(-rows, rows + 1):
				var rect := Rect2(base.position + Vector2(x, y) * pitch, size)
				if area.encloses(rect):
					candidates.append(rect)
		candidates.sort_custom(func(a: Rect2, b: Rect2): return a.position.distance_squared_to(base.position) < b.position.distance_squared_to(base.position))
		# Keep the hovered label under the pointer when neighbouring labels time out or Alt
		# changes visibility. Camera/mesh motion still carries it along with its own item.
		if loot.node.get_instance_id() == focused_id:
			for previous in previous_labels:
				if is_same(previous.loot, loot):
					# Subtract anchors first: an unchanged anchor must give exactly zero,
					# even when authored models have fractional support heights.
					var stable := Rect2(previous.rect.position + (anchor - previous.anchor), size)
					if area.encloses(stable):
						candidates.push_front(stable)
					break
		for rect in candidates:
			var occupied := false
			for disc in discs:
				if rect.grow(LABEL_GAP / 2).intersects(disc):
					occupied = true
					break
			if occupied:
				continue
			for placed in cached_labels:
				if rect.grow(LABEL_GAP).intersects(placed.rect):
					occupied = true
					break
			if not occupied:
				cached_labels.append({"loot": loot, "rect": rect, "anchor": anchor})
				break
	return cached_labels

func invalidate() -> void:
	cached_key.clear()
	cached_labels.clear()

static func pick(screen: Vector2, layout: Array, drops: Array, camera: Camera3D) -> Dictionary:
	# Drawn labels take precedence; disc selection uses distance, not drop order.
	for entry in layout:
		if entry.rect.has_point(screen):
			return entry.loot
	var closest: Dictionary = {}
	var distance := PICK_RADIUS * PICK_RADIUS
	for loot in drops:
		if not is_instance_valid(loot.node) or camera.is_position_behind(loot.visual.global_position):
			continue
		var next := camera.unproject_position(loot.visual.global_position).distance_squared_to(screen)
		if next < distance:
			distance = next
			closest = loot
	return closest
