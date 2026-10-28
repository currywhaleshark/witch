extends RefCounted
## Roadside props for the alley maps, assembled from primitives. Presentation only: each prop sits
## inside its map entry's collision box (props), or in the strip walkers keep clear of walls
## (clutter), so collision, navigation and sight lines do not change.
const Shape = preload("res://scripts/shapes.gd")
const WOOD = Color("7a6446")
const RUBBER = Color("2a2a2a")
const CARDBOARD = [Color("a98a5c"), Color("9c7f55"), Color("b49a6c")]
const SACK = Color("d8d2bf")

static func build(body: Node3D, model: String, rect: Array, height: float) -> bool:
	# Replaces a prop's plain block with its model. The model's origin is the ground at the centre of
	# the footprint; x and z keep the footprint's world axes.
	var w: float = rect[2] - rect[0]
	var d: float = rect[3] - rect[1]
	var root = Node3D.new()
	body.add_child(root)
	root.position.y = -height / 2.0
	match model:
		"cart": _cart(root)
		"bins": _bins(root)
		"booth": _booth(root)
		"stall": _stall(root, w)
		"pyeongsang": _pyeongsang(root, w, d)
		"stake": _stake(root)
		_:
			root.free()
			return false
	body.get_child(0).hide()
	return true

static func _turned(node: Node3D, degrees: Vector3) -> Node3D:
	node.rotation_degrees = degrees
	return node

static func _font() -> SystemFont:
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "sans-serif"])
	font.font_weight = 700
	return font

static func _glass(piece: MeshInstance3D, alpha: float) -> void:
	var material: StandardMaterial3D = piece.material_override
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = alpha
	material.roughness = 0.15

static func _cart(root: Node3D) -> void:
	# A worn handcart (리어카): plank bed with low sides on two bicycle wheels, handles on a prop
	# stand, a couple of boxes and a sack left on it.
	Shape.box(root, Vector3(0.15, 0.55, 0), Vector3(1.5, 0.06, 1.0), WOOD)
	for z in [-0.5, 0.5]:
		Shape.box(root, Vector3(0.15, 0.69, z), Vector3(1.5, 0.22, 0.04), WOOD.darkened(0.15))
	Shape.box(root, Vector3(0.9, 0.69, 0), Vector3(0.04, 0.22, 1.0), WOOD.darkened(0.15))
	for z in [-0.42, 0.42]:
		Shape.box(root, Vector3(-0.15, 0.5, z), Vector3(1.9, 0.05, 0.05), Color("4f504e"))
	Shape.box(root, Vector3(-1.0, 0.5, 0), Vector3(0.05, 0.05, 0.9), Color("4f504e"))
	Shape.box(root, Vector3(-0.85, 0.25, 0), Vector3(0.05, 0.5, 0.05), Color("4f504e"))
	Shape.box(root, Vector3(0.15, 0.32, 0), Vector3(0.05, 0.05, 1.12), Color("4f504e"))
	for z in [-0.58, 0.58]:
		_turned(Shape.cylinder(root, Vector3(0.15, 0.32, z), 0.32, 0.06, RUBBER), Vector3(90, 0, 0))
		_turned(Shape.cylinder(root, Vector3(0.15, 0.32, z), 0.06, 0.08, Color("8d8a82")), Vector3(90, 0, 0))
	_turned(Shape.box(root, Vector3(0.45, 0.78, -0.18), Vector3(0.5, 0.42, 0.45), CARDBOARD[0]), Vector3(0, 8, 0))
	_turned(Shape.box(root, Vector3(-0.1, 0.72, 0.2), Vector3(0.42, 0.3, 0.36), CARDBOARD[1]), Vector3(0, -12, 0))
	var sack: MeshInstance3D = Shape.sphere(root, Vector3(0.55, 0.72, 0.25), 0.22, SACK)
	sack.scale = Vector3(1.2, 0.7, 0.9)

static func _bins(root: Node3D) -> void:
	# Two wheelie bins by the wall with tied rubbish bags heaped in front and one on a lid.
	for spec in [[-0.38, Color("35577a")], [0.3, Color("3f6b55")]]:
		var x: float = spec[0]
		Shape.box(root, Vector3(x, 0.42, -0.2), Vector3(0.56, 0.84, 0.6), spec[1])
		Shape.box(root, Vector3(x, 0.86, -0.2), Vector3(0.62, 0.05, 0.66), spec[1].darkened(0.25))
		for side in [-0.2, 0.2]:
			_turned(Shape.cylinder(root, Vector3(x + side, 0.07, -0.5), 0.07, 0.05, RUBBER), Vector3(0, 0, 90))
	for bag in [[-0.5, 0.21, 0.3, 0.28], [0.05, 0.18, 0.38, 0.24], [0.52, 0.2, 0.28, 0.26], [0.3, 1.05, -0.2, 0.2]]:
		var heap: MeshInstance3D = Shape.sphere(root, Vector3(bag[0], bag[1], bag[2]), bag[3], Color("e2ded2"))
		heap.scale = Vector3(1.0, 0.8, 0.9)
	_turned(Shape.box(root, Vector3(0.75, 0.4, -0.45), Vector3(0.03, 0.8, 0.55), CARDBOARD[2]), Vector3(0, 0, -10))

static func _booth(root: Node3D) -> void:
	# A 2000s coin/card phone booth: slim teal frame on a dark plinth, tall glazing split by mullions
	# above a low kick rail, a glazed front door with its handle, a header board with its white
	# label, and the silver payphone on the back wall.
	# Modelled 2.27m to the cap; real booths stand 2.2-2.4m, so it is scaled up to 2.4m.
	root.scale = Vector3.ONE * (2.4 / 2.27)
	var teal = Color("3a93ab")
	var half := 0.46
	Shape.box(root, Vector3(0, 0.02, 0), Vector3(1.4, 0.04, 1.4), Color("8c877d"))
	Shape.box(root, Vector3(0, 0.075, 0), Vector3(0.98, 0.07, 0.98), Color("2b2d2e"))
	for x in [-half, half]:
		for z in [-half, half]:
			Shape.box(root, Vector3(x, 1.05, z), Vector3(0.07, 1.9, 0.07), teal)
	# Faces: outward normal, along-face axis; the front (+z) is the door.
	for face in [[Vector3(0, 0, -1), Vector3(1, 0, 0)], [Vector3(-1, 0, 0), Vector3(0, 0, 1)], [Vector3(1, 0, 0), Vector3(0, 0, 1)], [Vector3(0, 0, 1), Vector3(1, 0, 0)]]:
		var normal: Vector3 = face[0]
		var along: Vector3 = face[1]
		var plane: Vector3 = normal * half
		var flat := func(length: float, height: float, depth: float) -> Vector3:
			return along * length + Vector3(0, height, 0) + normal.abs() * depth
		Shape.box(root, plane + Vector3(0, 0.22, 0), flat.call(0.9, 0.2, 0.04), teal.darkened(0.1))
		for y in [0.345, 0.9, 1.97]:
			Shape.box(root, plane + Vector3(0, y, 0), flat.call(0.9, 0.05, 0.05), teal)
		_glass(Shape.box(root, plane + Vector3(0, 1.15, 0), flat.call(0.88, 1.6, 0.02), Color("a9c8cf")), 0.3)
		var mullions: Array = [0.0] if normal.z > 0 else [-0.15, 0.15]
		for m in mullions:
			Shape.box(root, plane + along * m + Vector3(0, 1.15, 0), flat.call(0.035, 1.6, 0.045), teal)
		if normal.z > 0:
			Shape.box(root, plane + along * 0.1 + normal * 0.03 + Vector3(0, 1.1, 0), Vector3(0.025, 0.4, 0.025), Color("c9ccce"))
	Shape.box(root, Vector3(0, 2.11, 0), Vector3(0.98, 0.22, 0.98), teal)
	Shape.box(root, Vector3(0, 2.245, 0), Vector3(0.92, 0.05, 0.92), teal.lightened(0.12))
	for side in [[Vector3(0, 0, 1), 0.0], [Vector3(1, 0, 0), 90.0]]:
		var label = Label3D.new()
		label.text = "주화/카드겸용공중전화기"
		label.font = _font()
		label.font_size = 48
		label.pixel_size = 0.0016
		label.modulate = Color("f2f0ea")
		label.outline_size = 0
		root.add_child(label)
		label.position = Vector3(0, 2.11, 0) + side[0] * 0.495
		label.rotation_degrees.y = side[1]
	Shape.box(root, Vector3(0, 1.35, -half + 0.1), Vector3(0.28, 0.42, 0.14), Color("a9adb0"))
	Shape.box(root, Vector3(0.02, 1.38, -half + 0.175), Vector3(0.1, 0.12, 0.01), Color("2b2d2e"))
	Shape.box(root, Vector3(-0.1, 1.38, -half + 0.18), Vector3(0.05, 0.22, 0.05), RUBBER)
	Shape.box(root, Vector3(0, 1.02, -half + 0.12), Vector3(0.4, 0.03, 0.2), Color("6b6a64"))

static func _stall(root: Node3D, w: float) -> void:
	# The shut stationery shop's front stall: a table under a roped blue tarp, two coin-op mini arcade
	# cabinets with dark screens and an empty capsule machine.
	var table: float = w - 1.3
	var x0: float = -w / 2.0 + table / 2.0 + 0.05
	var tarp = Color("35577a")
	for x in [x0 - table / 2.0 + 0.1, x0 + table / 2.0 - 0.1]:
		for z in [-0.42, 0.42]:
			Shape.box(root, Vector3(x, 0.36, z), Vector3(0.05, 0.72, 0.05), Color("6b6a64"))
	Shape.box(root, Vector3(x0, 0.76, 0), Vector3(table + 0.1, 0.06, 1.1), tarp)
	Shape.box(root, Vector3(x0, 0.5, 0.55), Vector3(table + 0.1, 0.52, 0.02), tarp.darkened(0.15))
	Shape.box(root, Vector3(x0 - table / 2.0, 0.5, 0), Vector3(0.02, 0.52, 1.1), tarp.darkened(0.15))
	for lump in [[x0 - 0.5, 0.18], [x0 + 0.2, 0.22], [x0 + 0.75, 0.15]]:
		var bump: MeshInstance3D = Shape.sphere(root, Vector3(lump[0], 0.8, -0.05), lump[1], tarp.lightened(0.05))
		bump.scale = Vector3(1.4, 0.55, 1.2)
	for x in [x0 - table / 4.0, x0 + table / 4.0]:
		Shape.box(root, Vector3(x, 0.86, 0), Vector3(0.02, 0.02, 1.14), Color("d8c9a0"))
	for spec in [[w / 2.0 - 0.95, Color("c9a640")], [w / 2.0 - 0.5, Color("a8433a")]]:
		var x: float = spec[0]
		Shape.box(root, Vector3(x, 0.42, 0), Vector3(0.42, 0.84, 0.5), spec[1].darkened(0.2))
		_turned(Shape.box(root, Vector3(x, 0.92, 0.08), Vector3(0.4, 0.3, 0.05), Color("1d2428")), Vector3(-25, 0, 0))
		Shape.box(root, Vector3(x, 0.68, 0.27), Vector3(0.4, 0.06, 0.12), spec[1])
		Shape.cylinder(root, Vector3(x - 0.08, 0.74, 0.28), 0.015, 0.08, RUBBER)
	Shape.box(root, Vector3(w / 2.0 - 0.75, 0.25, -0.45), Vector3(0.36, 0.5, 0.2), Color("a8433a"))
	_glass(Shape.sphere(root, Vector3(w / 2.0 - 0.75, 0.64, -0.45), 0.16, Color("c9d6dc")), 0.4)

static func _pyeongsang(root: Node3D, w: float, d: float) -> void:
	# A low wooden platform for sitting out: plank top on six legs, a rolled straw mat, a basin and
	# two empty bottles.
	for x in [-w / 2.0 + 0.2, 0.0, w / 2.0 - 0.2]:
		for z in [-d / 2.0 + 0.2, d / 2.0 - 0.2]:
			Shape.box(root, Vector3(x, 0.2, z), Vector3(0.1, 0.4, 0.1), WOOD.darkened(0.25))
	Shape.box(root, Vector3(0, 0.37, 0), Vector3(w - 0.2, 0.06, d - 0.2), WOOD.darkened(0.3))
	var planks: int = int((d - 0.1) / 0.24)
	for i in planks:
		var z: float = -d / 2.0 + 0.05 + 0.24 * (i + 0.5)
		Shape.box(root, Vector3(0, 0.425, z), Vector3(w - 0.1, 0.05, 0.2), WOOD.lightened(0.05 * (i % 3)))
	_turned(Shape.cylinder(root, Vector3(-w / 2.0 + 0.6, 0.55, 0), 0.1, d - 0.5, Color("a8925a")), Vector3(90, 0, 0))
	Shape.cylinder(root, Vector3(w / 2.0 - 0.7, 0.5, -0.3), 0.3, 0.12, Color("4f6f9a"), 0.24)
	for z in [0.35, 0.47]:
		Shape.cylinder(root, Vector3(w / 2.0 - 0.6, 0.57, z), 0.035, 0.24, Color("2f6b3a"))

static func _stake(root: Node3D) -> void:
	# Same ground origin and 0.96m collision footprint as the map's blockout.
	var scene: PackedScene = load("res://assets/actors/boss_trial_v1/stake_v1.glb")
	var stake := scene.instantiate()
	stake.name = "LureStakeVisual"
	root.add_child(stake)

static func clutter(parent: Node3D, pos: Vector3, yaw: float, kind: String, rng: RandomNumberGenerator) -> Node3D:
	# A small heap against a far wall: local x runs along the wall, +z points into the alley, and
	# everything stays within 0.2m of pos in z so it sits inside the strip walkers keep clear.
	var root = Node3D.new()
	parent.add_child(root)
	root.position = pos
	root.rotation_degrees.y = yaw
	root.set_meta("clutter", kind)
	match kind:
		"tubs":
			# Rubber tubs used as planters, with peppers or greens.
			for i in rng.randi_range(2, 3):
				var x: float = (i - 1) * 0.55 + rng.randf_range(-0.05, 0.05)
				var tub = Color("2e2a28") if rng.randf() < 0.6 else Color("8a3a30")
				Shape.cylinder(root, Vector3(x, 0.12, 0), 0.2, 0.24, tub, 0.23)
				Shape.cylinder(root, Vector3(x, 0.23, 0), 0.19, 0.02, Color("4a3a2c"))
				for leaf in rng.randi_range(2, 3):
					Shape.sphere(root, Vector3(x + rng.randf_range(-0.09, 0.09), 0.33 + rng.randf_range(0, 0.1), rng.randf_range(-0.07, 0.07)), rng.randf_range(0.08, 0.12), Color("4f6b3a").lightened(rng.randf_range(0, 0.15)))
		"briquettes":
			# Spent coal briquettes stacked for collection, one or two broken beside them.
			for stack in rng.randi_range(2, 3):
				var x: float = stack * 0.2 - 0.2
				for level in rng.randi_range(2, 5):
					Shape.cylinder(root, Vector3(x, 0.07 + level * 0.14, rng.randf_range(-0.02, 0.02)), 0.075, 0.135, Color("a39d92").lightened(rng.randf_range(0, 0.12)))
			var broken: MeshInstance3D = Shape.cylinder(root, Vector3(0.45, 0.04, 0.08), 0.075, 0.08, Color("b5aea3"))
			broken.rotation_degrees.z = 70
		"boxes":
			# Cardboard boxes, one flattened against the wall.
			var x := -0.3
			for i in rng.randi_range(2, 3):
				var size = Vector3(rng.randf_range(0.35, 0.5), rng.randf_range(0.25, 0.4), rng.randf_range(0.28, 0.36))
				_turned(Shape.box(root, Vector3(x, size.y / 2.0, 0), size, CARDBOARD[rng.randi() % CARDBOARD.size()]), Vector3(0, rng.randf_range(-12, 12), 0))
				x += size.x * 0.8
			_turned(Shape.box(root, Vector3(x + 0.1, 0.4, -0.15), Vector3(0.6, 0.8, 0.02), CARDBOARD[2]), Vector3(-10, 0, 0))
		"sacks":
			# Tied white woven sacks of rubble.
			for i in rng.randi_range(2, 3):
				var sack: MeshInstance3D = Shape.sphere(root, Vector3((i - 1) * 0.42, 0.18, rng.randf_range(-0.03, 0.03)), 0.24, SACK.darkened(rng.randf_range(0, 0.15)))
				sack.scale = Vector3(1.0, 0.75, 0.75)
				Shape.cylinder(root, Vector3((i - 1) * 0.42, 0.37, 0), 0.04, 0.08, SACK.darkened(0.2))
		"crates":
			# Plastic bottle crates, stacked two or three high.
			var colors = [Color("3f7a52"), Color("2f5d8a"), Color("a8433a")]
			for column in rng.randi_range(1, 2):
				for level in rng.randi_range(1, 3):
					var crate = colors[rng.randi() % colors.size()]
					var at = Vector3(column * 0.58, 0.15 + level * 0.3, 0)
					_turned(Shape.box(root, at, Vector3(0.55, 0.28, 0.36), crate), Vector3(0, rng.randf_range(-5, 5), 0))
					Shape.box(root, at + Vector3(0, 0.02, 0), Vector3(0.47, 0.25, 0.37), crate.darkened(0.35))
	return root
