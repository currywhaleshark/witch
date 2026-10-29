extends Node3D
## Rigid staff appearance only. No combat clocks, resources, hit tests or global RNG.
const ASSET := "res://assets/weapons/staff_transform_v2/"
const TOOLS := ["bolt_cutter", "grinder", "chainsaw"]
var loaded_ok := false
var last_error := ""
var active_tool := ""
var appearance := "basic"
var tool_roots: Dictionary = {}
var common_root: Node3D
var _config: Dictionary
var _parts: Array = []
var _ornaments: Dictionary = {}
var _elapsed := 99.0
var _mechanism_time := 0.0
var _spark_meshes: Array[MeshInstance3D] = []
var _ring: MeshInstance3D
var _effect_material: StandardMaterial3D
var _effect_age := 99.0
var _transition_serial := 0
var _departing_root: Node3D
var _jaw_opening := deg_to_rad(8.0)

func initialize() -> bool:
	var data = JSON.parse_string(FileAccess.get_file_as_string(ASSET + "parts.json"))
	if not data is Dictionary:
		last_error = "staff_parts_metadata_missing"
		return false
	_config = data
	var scene = load(_config.asset)
	if not scene is PackedScene:
		last_error = "staff_parts_scene_missing"
		return false
	var model: Node3D = scene.instantiate()
	add_child(model)
	_departing_root = Node3D.new()
	_departing_root.name = "DepartingToolParts"
	model.add_child(_departing_root)
	common_root = model.find_child("common", true, false)
	for tool in TOOLS:
		tool_roots[tool] = model.find_child(tool, true, false)
		if not is_instance_valid(tool_roots[tool]):
			last_error = "staff_group_missing_" + tool
			return false
		tool_roots[tool].visible = false
	_ornaments.ornament_seal = model.find_child("ornament_seal", true, false)
	if not is_instance_valid(common_root) or not is_instance_valid(_ornaments.ornament_seal):
		last_error = "staff_common_or_ornament_missing"
		return false
	for spec in _config.parts:
		var node: MeshInstance3D = model.find_child(spec.name, true, false)
		if not is_instance_valid(node):
			last_error = "staff_part_missing_" + spec.name
			return false
		if spec.group in TOOLS:
			_parts.append({"node":node,"rest":node.transform,"weight":0.0,"spec":spec})
			node.visible = false
	_make_light()
	loaded_ok = true
	set_appearance("basic")
	return true

func set_tool(tool) -> void:
	if not loaded_ok:
		return
	var next := "" if tool == null else String(tool)
	if next not in TOOLS:
		next = ""
	if active_tool == next:
		return
	active_tool = next
	_elapsed = 0.0
	_effect_age = 0.0
	_transition_serial += 1
	# Pose is deliberately untouched here: rapid switching reverses from current parts.

func set_appearance(profile: String) -> bool:
	if not loaded_ok or not _config.appearance_profiles.has(profile):
		return false
	appearance = profile
	var selected: Array = _config.appearance_profiles[profile]
	for key in _ornaments:
		_ornaments[key].visible = key in selected
	return true

func advance(dt: float, frozen: bool, attack_phase := -1.0, seconds_to_release := -1.0) -> void:
	if not loaded_ok or frozen:
		return
	var step := maxf(dt, 0.0)
	_elapsed += step
	_effect_age += step
	_mechanism_time += step
	if attack_phase >= 0.0:
		_jaw_opening = _cutter_opening(attack_phase)
	else:
		# An interrupted attack relaxes from its current aperture instead of snapping.
		_jaw_opening = move_toward(_jaw_opening, deg_to_rad(float(_config.cutter.idle_degrees)), step * 2.5)
	var duration: float = _config.assembly_seconds
	# At extreme IAS an attack may release before a normal cosmetic assembly could finish.
	# Accelerate only the presentation so the correct head is present at the unchanged hit.
	if seconds_to_release >= 0.0:
		duration = minf(duration, maxf(seconds_to_release, step))
	for index in _parts.size():
		var part: Dictionary = _parts[index]
		var wanted: bool = part.spec.group == active_tool
		var delay: float = float(part.spec.delay) * float(_config.assembly_seconds)
		if seconds_to_release >= 0.0:
			delay = minf(delay, maxf(seconds_to_release - step * 2.0, 0.0))
		var w: float = part.weight
		var previous_weight := w
		if wanted and _elapsed >= delay:
			w = move_toward(w, 1.0, step / maxf(duration - delay, step))
		elif not wanted:
			w = move_toward(w, 0.0, step / float(_config.dissolve_seconds))
		part.weight = w
		var mesh: MeshInstance3D = part.node
		var parent: Node3D = tool_roots[part.spec.group] if wanted else _departing_root
		if mesh.get_parent() != parent:
			# Module roots are identity transforms. Move the same rigid pieces to the
			# cosmetic exit layer while the gameplay-facing active module hides at once.
			mesh.reparent(parent, false)
		mesh.visible = w > 0.00001
		var rest: Transform3D = part.rest
		var t := smoothstep(0.0, 1.0, w)
		var previous_t := smoothstep(0.0, 1.0, previous_weight)
		# Each rigid piece first appears outside the head, then follows a short curved path.
		var angle := float(index) * 2.39996323
		var radial := Vector3(cos(angle), .25 + .15 * sin(angle * 2.0), sin(angle))
		var offset := radial * (.10 + .025 * float(index % 3))
		if wanted and w > 0.0:
			if previous_weight <= 0.0:
				mesh.transform = Transform3D(Basis(Vector3.UP, .40) * rest.basis * .04, rest.origin + offset)
			var current := mesh.transform
			mesh.transform = rest
			_drive(part, attack_phase)
			var target := mesh.transform
			var share := clampf((t-previous_t) / maxf(1.0-previous_t,.000001),0.0,1.0)
			mesh.transform = target if w >= .99999 else current.interpolate_with(target,share)
		elif previous_weight > 0.0:
			# Shrink and move the actual moving pose, including running chain teeth and
			# rotor orientation. Never reconstruct an exiting mechanism from its bind pose.
			mesh.position += offset * (previous_t-t)
			mesh.basis *= maxf(.04,t) / maxf(.04,previous_t)
	for tool in TOOLS:
		tool_roots[tool].visible = tool == active_tool
	_light()

func finish_assembly() -> void:
	# Called only on an actual attack release; never advances gameplay or restarts the clip.
	for part in _parts:
		if part.spec.group == active_tool:
			if part.node.get_parent() != tool_roots[active_tool]:
				part.node.reparent(tool_roots[active_tool], false)
			part.weight = 1.0
			part.node.visible = true
			part.node.transform = part.rest
		elif part.weight > 0.0:
			part.weight = 0.0
			part.node.visible = false
	for tool in TOOLS:
		tool_roots[tool].visible = tool == active_tool

func _drive(part: Dictionary, phase: float) -> void:
	var mesh: MeshInstance3D = part.node
	var rest: Transform3D = part.rest
	match String(part.spec.driver):
		"disc":
			mesh.basis = Basis(Vector3.FORWARD, _mechanism_time * 24.0) * rest.basis
		"drive":
			mesh.basis = Basis(Vector3.FORWARD, _mechanism_time * 7.0) * rest.basis
		"jaw":
			mesh.basis = Basis(Vector3.BACK, -float(part.spec.side) * _jaw_opening) * rest.basis
		"cutter_link":
			var frame := _cutter_link_frame(float(part.spec.side))
			mesh.position.y = frame.slider_y
			mesh.basis = Basis(Vector3.BACK, frame.angle) * rest.basis
		"cutter_slider":
			mesh.position.y = _cutter_link_frame(1.0).slider_y
		"cutter_drive":
			mesh.basis = Basis(Vector3.FORWARD, _jaw_opening * 4.0) * rest.basis
		"chain":
			var old: Dictionary = _chain_point(float(part.spec.phase))
			var now: Dictionary = _chain_point(float(part.spec.phase) + _mechanism_time * 1.7)
			mesh.position = now.point
			mesh.basis = Basis(Vector3.BACK, float(now.angle) - float(old.angle)) * rest.basis

func _cutter_opening(phase: float) -> float:
	var timing: Dictionary = _config.cutter.phase
	var idle := deg_to_rad(float(_config.cutter.idle_degrees))
	var wide := deg_to_rad(float(_config.cutter.open_degrees))
	if phase < float(timing.fully_open):
		return lerpf(idle, wide, smoothstep(0.0, float(timing.fully_open), phase))
	if phase < float(timing.snap_start):
		return wide
	if phase < float(timing.impact):
		# Accelerate into the stop. The actual release frame supplies exactly 0.5.
		var closing := inverse_lerp(float(timing.snap_start), float(timing.impact), phase)
		return wide * (1.0 - closing * closing)
	return idle * smoothstep(float(timing.hold_end), float(timing.relaxed), phase)

func _cutter_link_frame(side: float) -> Dictionary:
	var spec: Dictionary = _config.cutter
	var pivot := Vector2(side * float(spec.jaw_pivot[0]), float(spec.jaw_pivot[1]))
	var rest_pin := Vector2(side * float(spec.jaw_pin[0]), float(spec.jaw_pin[1]))
	var pin := pivot + (rest_pin - pivot).rotated(-side * _jaw_opening)
	var x := side * float(spec.slider_x)
	var length: float = spec.link_length_m
	var y := pin.y - sqrt(maxf(0.0, length * length - (pin.x - x) * (pin.x - x)))
	var rest_direction := rest_pin - Vector2(x, float(spec.slider_rest_y))
	return {"slider_y":y, "angle":(pin - Vector2(x,y)).angle() - rest_direction.angle()}

static func _chain_point(phase: float) -> Dictionary:
	var radius := .069
	var leg := .27
	var arc := PI * radius
	var distance := fposmod(phase, 1.0) * (2.0 * leg + 2.0 * arc)
	if distance < leg:
		return {"point":Vector3(radius, .77 + distance, 0),"angle":0.0}
	distance -= leg
	if distance < arc:
		var a := distance / radius
		return {"point":Vector3(radius * cos(a),1.04 + radius * sin(a),0),"angle":a}
	distance -= arc
	if distance < leg:
		return {"point":Vector3(-radius,1.04 - distance,0),"angle":PI}
	var a := PI + (distance - leg) / radius
	return {"point":Vector3(radius*cos(a),.77+radius*sin(a),0),"angle":a}

func _make_light() -> void:
	_effect_material = StandardMaterial3D.new()
	_effect_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_effect_material.albedo_color = Color("72e3c4")
	_effect_material.emission_enabled = true
	_effect_material.emission = Color("72e3c4")
	_effect_material.emission_energy_multiplier = 1.5
	var sphere := SphereMesh.new()
	sphere.radius = .006
	sphere.height = .012
	sphere.radial_segments = 6
	sphere.rings = 3
	for i in 12:
		var mote := MeshInstance3D.new()
		mote.mesh = sphere
		mote.material_override = _effect_material
		mote.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mote)
		mote.visible = false
		_spark_meshes.append(mote)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = .132
	torus.outer_radius = .135
	torus.rings = 32
	torus.ring_segments = 4
	_ring.mesh = torus
	_ring.material_override = _effect_material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_ring.visible = false

func _light() -> void:
	var progress := clampf(_effect_age / float(_config.assembly_seconds), 0, 1)
	var visible_fx := progress < 1.0
	_ring.visible = visible_fx
	_ring.position = Vector3(0, .59 + .34 * progress, 0)
	_ring.scale = Vector3.ONE * (.8 + .3 * sin(PI*progress))
	for i in _spark_meshes.size():
		var mote := _spark_meshes[i]
		mote.visible = visible_fx
		var angle := i * TAU / _spark_meshes.size() + progress * 2.2
		var radius := .16 * (1.0-progress) + .035
		mote.position = Vector3(cos(angle)*radius,.64+.3*fmod(i*.37+progress,1),sin(angle)*radius)
		mote.scale = Vector3.ONE * maxf(.05,sin(PI*progress))

func debug_state() -> Dictionary:
	var groups: Dictionary = {}
	for tool in TOOLS:
		var weights: Array = _parts.filter(func(p): return p.spec.group == tool).map(func(p): return p.weight)
		groups[tool] = {"min":weights.min(),"max":weights.max(),"visible":tool_roots[tool].visible}
	return {"loaded":loaded_ok,"active_tool":active_tool,"appearance":appearance,
		"elapsed":_elapsed,"mechanism_time":_mechanism_time,"serial":_transition_serial,
		"groups":groups,"parts":_parts.size(),"effects":_ring.visible,
		"jaw_opening_degrees":rad_to_deg(_jaw_opening)}
