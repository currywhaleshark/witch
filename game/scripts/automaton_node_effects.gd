extends Node3D
## Appearance only. The arena still owns detonation, damage and lifetime.
var actor: Node3D
var variant := "base"
var consumed := 0.0
var lifetime := 1.0
var clock := 0.0
var blade_angle := 0.0
var _fuse_bones: Array[int] = []
var _points: Array[Vector3] = []
var _head := -1
var _blade := -1
var _axis := Vector3.RIGHT
var _flame: MeshInstance3D
var _core: MeshInstance3D
var _sparks: Array[MeshInstance3D] = []
var _target := ""
var _approach_start := 0.0

func initialize(visual: Node3D, node_kind: String, total_life: float) -> void:
	actor=visual; variant=node_kind; lifetime=maxf(total_life,0.01)
	var path := "res://assets/actors/automaton_nodes_v1/automaton_%s.json" % variant.to_lower()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	if variant=="A":
		_head=actor.skeleton.find_bone("part_002")
		for i in 12: _fuse_bones.append(actor.skeleton.find_bone("fuse_%02d"%i))
		for p in data.fuse_points_head_local: _points.append(Vector3(p[0],p[1],p[2]))
		_flame=_ember(0.031,0.085,Color(1.0,0.27,0.025)); _core=_ember(0.016,0.045,Color(1.0,0.87,0.36))
	else:
		_blade=actor.skeleton.find_bone("node_blade")
		var a: Array=data.blade_axis_local; _axis=Vector3(a[0],a[1],a[2])
	for i in 6: _sparks.append(_ember(0.006+0.002*(i%2),0.018,Color(1.0,0.57,0.13)))

func _ember(radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh:=SphereMesh.new(); mesh.radius=radius; mesh.height=height; mesh.radial_segments=8; mesh.rings=4
	var mat:=StandardMaterial3D.new(); mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color=color; mat.emission_enabled=true; mat.emission=color; mat.emission_energy_multiplier=1.2
	var node:=MeshInstance3D.new(); node.mesh=mesh; node.material_override=mat
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(node); return node

func sync(ally: Dictionary, dt: float, target_distance: float) -> void:
	clock+=dt
	blade_angle+=dt*(24.0 if actor.visual_state=="attack" else 7.0)
	if variant!="A": return
	consumed=maxf(consumed,clampf(1.0-float(ally.life)/lifetime,0.0,1.0)*0.96)
	if str(ally.target)!=_target:
		_target=str(ally.target); _approach_start=target_distance
	if _target!="" and is_finite(target_distance) and _approach_start>1.8:
		# A visual anticipation cue, never an independent explosion countdown.
		consumed=maxf(consumed,clampf(1.0-(target_distance-1.8)/(_approach_start-1.8),0.0,1.0)*0.96)

func apply_pose() -> void:
	if not is_instance_valid(actor): return
	var dead: bool=actor._death_time>=0.0
	if variant=="A":
		var remaining:=maxf(0.04,1.0-consumed)*12.0
		for i in 12:
			var amount:=clampf(remaining-i,0.0,1.0)
			if dead and actor._death_clip=="explode": amount=0.0
			actor.skeleton.set_bone_pose_scale(_fuse_bones[i],Vector3.ONE*maxf(0.0001,amount))
		actor.skeleton.force_update_all_bone_transforms()
		var index:=mini(11,floori(remaining)); var t:=remaining-index
		var local_point: Vector3=_points[index].lerp(_points[index+1],t)
		var tip: Vector3=actor.skeleton.global_transform*actor.skeleton.get_bone_global_pose(_head)*local_point
		_flame.visible=not dead; _core.visible=not dead
		_flame.global_position=tip+Vector3.UP*(0.022+0.005*sin(clock*23.0)); _core.global_position=tip+Vector3.UP*0.016
		_flame.scale=Vector3.ONE*(0.88+0.12*sin(clock*31.0))
		for i in _sparks.size():
			var phase:=fposmod(clock*2.1+i*0.173,1.0); var angle:=i*2.399963+clock*3.0
			_sparks[i].visible=not dead
			_sparks[i].global_position=tip+Vector3(cos(angle)*phase*.055,phase*.15,sin(angle)*phase*.055)
			_sparks[i].scale=Vector3.ONE*(1.0-phase)
	elif not dead and _blade>=0:
		actor.skeleton.set_bone_pose_rotation(_blade,Quaternion(_axis,blade_angle))
		actor.skeleton.force_update_all_bone_transforms()
		var bone: Transform3D=actor.skeleton.global_transform*actor.skeleton.get_bone_global_pose(_blade)
		for i in _sparks.size():
			_sparks[i].visible=actor.visual_state=="attack" and actor.fraction>=0.35 and actor.fraction<=0.8
			var phase:=fposmod(clock*5.0+i*.173,1.0)
			_sparks[i].global_position=bone.origin+Vector3(phase*.12,.11+phase*.10,-.08-phase*.12)
	else:
		for spark in _sparks: spark.visible=false

func debug_state() -> Dictionary:
	return {"variant":variant,"consumed":consumed,"clock":clock,"lit":variant=="A" and _flame!=null and _flame.visible}
