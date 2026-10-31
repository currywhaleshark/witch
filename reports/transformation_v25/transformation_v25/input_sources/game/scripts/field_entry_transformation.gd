extends Node3D
## Field entry presentation. Arena gates combat while this timeline is active.
const Shape = preload("res://scripts/shapes.gd")
const OUTFIT := "res://assets/characters/player/transformation_v25/outfit_transformed_v4.glb"
var visual: Node3D
var contract: Dictionary
var active := false
var elapsed := 0.0
var grasped := false
var changed_outfit := false
var phase := "civilian"
var cues: Array = []
var error := ""
var _floating: Transform3D
var _rings: Array = []
var _motes: Array = []
var _staff_ring: MeshInstance3D
var _light: OmniLight3D
var _glow: ShaderMaterial
var _overlays: Array = []
var _started_assembly := false
var _fx_material: StandardMaterial3D

func initialize(player_visual: Node3D, data: Dictionary) -> void:
	visual = player_visual
	contract = data
	var frame: Dictionary = data.floating_staff_frame
	var columns: Array = frame.basis_columns
	_floating = Transform3D(Basis(vec(columns[0]),vec(columns[1]),vec(columns[2])),vec(frame.origin))
	_fx_material = Shape.material(Color("87e3d4"),true)
	_fx_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fx_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fx_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_staff_ring = Shape.ring(self,Vector3.ZERO,.15,Color.WHITE,.009)
	decorate(_staff_ring)
	for i in 3:
		var ring := Shape.ring(self,Vector3.ZERO,.37 + .025*i,Color.WHITE,.012)
		decorate(ring)
		_rings.append(ring)
	for i in 26:
		var mote := Shape.sphere(self,Vector3.ZERO,.008 if i%3 else .012,Color.WHITE)
		decorate(mote)
		_motes.append(mote)
	_light = OmniLight3D.new()
	_light.omni_range = 2.0
	_light.light_color = Color("9eece4")
	_light.light_energy = 0.0
	add_child(_light)
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, blend_add, depth_draw_never; uniform float strength = 0.0; void fragment(){ float rim=pow(1.0-max(dot(normalize(NORMAL),normalize(VIEW)),0.0),1.5); ALBEDO=vec3(0.45,0.88,1.0); ALPHA=strength*(0.40+rim*0.60); }"
	_glow = ShaderMaterial.new()
	_glow.shader = shader
	visible = false

func vec(a: Array) -> Vector3:
	return Vector3(float(a[0]),float(a[1]),float(a[2]))

func decorate(mesh: MeshInstance3D) -> void:
	mesh.material_override = _fx_material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.visible = false

func begin() -> void:
	active = true
	elapsed = 0.0
	grasped = false
	changed_outfit = false
	_started_assembly = false
	cues.clear()
	phase = "civilian"
	visible = true
	visual.staff_root.visible = false
	visual.staff_visual.sample_entry_assembly(0.0)
	visual._sample("entry",0.0)
	visual._state = "transforming"

func advance(dt: float) -> void:
	if not active: return
	elapsed = minf(elapsed+maxf(dt,0.0),float(contract.duration_seconds))
	visual._sample("entry",elapsed)
	var progress := clampf((elapsed-float(contract.assembly_start))/float(contract.assembly_end-contract.assembly_start),0.0,1.0)
	visual.staff_root.visible = progress > 0.0
	visual.staff_visual.sample_entry_assembly(progress)
	if progress > 0.0 and not _started_assembly:
		_started_assembly = true
		cues.append({"event":"assembly","pitch":1.35,"gain_db":-5.0})
	if elapsed+0.000001 >= float(contract.grasp_seconds):
		if not grasped:
			grasped = true
			cues.append({"event":"grasp","pitch":.95,"gain_db":-2.0})
		visual.staff_root.transform = held_frame()
	else:
		# Assemble in a fixed frame beside the open right hand. The bone attachment
		# exists already, but its current hand motion must not drag the floating parts.
		visual.staff_root.global_transform = visual.runtime.skeleton.global_transform * _floating
	phase = "civilian" if progress <= 0.0 else ("assembly" if not grasped else "grasp")
	if elapsed >= float(contract.outfit_begin):
		phase = "outfit"
		if _overlays.is_empty(): _apply_glow()
		if elapsed+0.000001 >= float(contract.outfit_swap) and not changed_outfit:
			_clear_glow()
			changed_outfit = visual.set_form("transformed")
			if not changed_outfit:
				error = visual.last_error
				cancel()
				return
			_apply_glow()
			cues.append({"event":"outfit","pitch":1.65,"gain_db":-4.5})
	_update_fx(progress)
	if elapsed+0.000001 >= float(contract.duration_seconds):
		active = false
		phase = "ready"
		_clear_glow()
		visible = false
		_light.light_energy = 0.0
		visual.staff_root.transform = held_frame()
		visual._sample("idle",0.0)
		visual._idle_time = 0.0
		visual._state = "idle"

func held_frame() -> Transform3D:
	return Transform3D(visual.STAFF_GRIP_BASIS,visual.STAFF_GRIP_OFFSET+visual.STAFF_GRIP_BASIS.y*visual.staff_slide)

func _apply_glow() -> void:
	var outfit: Node = visual.runtime.slots.outfit
	for mesh in outfit.find_children("*","MeshInstance3D",true,false):
		_overlays.append({"mesh":mesh,"previous":mesh.material_overlay})
		mesh.material_overlay = _glow

func _clear_glow() -> void:
	for item in _overlays:
		if is_instance_valid(item.mesh): item.mesh.material_overlay = item.previous
	_overlays.clear()

func _update_fx(progress: float) -> void:
	var assembly := sin(PI*clampf(progress,0.0,1.0))
	var change := clampf((elapsed-float(contract.outfit_begin))/float(contract.outfit_end-contract.outfit_begin),0.0,1.0)
	var flash := sin(PI*change)
	_glow.set_shader_parameter("strength",flash*.85)
	var origin := _floating.origin
	_staff_ring.visible = progress>0.0 and progress<1.0
	_staff_ring.position = origin + _floating.basis.y*(.12+.72*progress)
	_staff_ring.basis = _floating.basis
	_staff_ring.scale = Vector3.ONE*(.85+.3*assembly)
	for i in _rings.size():
		var ring: MeshInstance3D = _rings[i]
		ring.visible = flash>.001
		ring.position = Vector3(0,.22+1.20*change + .09*i,0)
		ring.scale = Vector3.ONE*(.65+.5*flash)
		ring.rotation = Vector3(.12*sin(change*TAU+i),change*TAU,.10*cos(change*TAU+i))
	for i in _motes.size():
		var mote: MeshInstance3D = _motes[i]
		mote.visible = assembly>.001 or flash>.001
		var a := float(i)*2.399963+elapsed*2.2
		if flash>0.001:
			mote.position = Vector3(cos(a)*(.32+.12*sin(i)),.10+1.70*fposmod(i*.173+change*.8,1.0),sin(a)*.32)
		else:
			mote.position = origin+_floating.basis*Vector3(cos(a)*.18*(1-progress),-.30+1.35*fposmod(i*.173+progress,1.0),sin(a)*.18*(1-progress))
		mote.scale = Vector3.ONE*maxf(.05,maxf(assembly,flash))
	_fx_material.albedo_color = Color(.52,.90,.95,maxf(assembly,flash))
	_light.position = Vector3(0,1.1,.2) if flash>.001 else origin+_floating.basis.y*.65
	_light.light_energy = .60*assembly+.85*flash

func cancel() -> void:
	active = false
	phase = "cancelled"
	_clear_glow()
	visible = false
	_light.light_energy = 0.0
	cues.clear()
	visual.staff_visual.sample_entry_assembly(1.0)
	visual.staff_root.transform = held_frame()
	visual.staff_root.visible = grasped

func debug_state() -> Dictionary:
	return {"active":active,"elapsed":elapsed,"phase":phase,"grasped":grasped,"changed_outfit":changed_outfit,"error":error,"fx_visible":visible,"light_energy":_light.light_energy,"floating_origin":_floating.origin}
