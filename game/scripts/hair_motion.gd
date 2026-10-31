extends RefCounted
## Small independent hair rig. Body rest bones and gameplay motion stay intact.
const CONTRACT_PATH := "res://assets/characters/player/transformation_v27/hair_contract.json"
var data: Dictionary = {}
var runtime: Node3D
var _slot_id := 0
var _rig: Skeleton3D
var _last_head := Quaternion.IDENTITY
var _seen := false
var _sway := Vector3.ZERO

func initialize(character: Node3D) -> void:
	runtime = character
	data = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))

func reset() -> void:
	_seen = false
	_sway = Vector3.ZERO
	sync_anchors()
	if is_instance_valid(_rig):
		for i in _rig.get_bone_count():
			if String(_rig.get_bone_name(i)).begins_with("DEF-hair."):
				_rig.reset_bone_pose(i)

func sync_anchors() -> void:
	if runtime == null: return
	var slot: Node = runtime.slots.get("hair")
	if not is_instance_valid(slot):
		_rig = null
		_slot_id = 0
		return
	if slot.get_instance_id() != _slot_id:
		_slot_id = slot.get_instance_id()
		var rigs: Array[Node] = slot.find_children("*", "Skeleton3D", true, false)
		_rig = rigs[0] as Skeleton3D if rigs.size() == 1 and slot.has_meta("auxiliary_hair") else null
		_seen = false
		_sway = Vector3.ZERO
	if not is_instance_valid(_rig): return
	var source: Skeleton3D = runtime.skeleton
	var space := _rig.global_transform.affine_inverse() * source.global_transform
	for name in data.get("anchors", []):
		_rig.set_bone_global_pose(_rig.find_bone(name), space * source.get_bone_global_pose(source.find_bone(name)))

func advance(dt: float, entry_time: float = -1.0, frozen: bool = false) -> void:
	sync_anchors()
	if not is_instance_valid(_rig) or dt <= 0.0 or frozen: return
	var body: Skeleton3D = runtime.skeleton
	var head := (body.global_basis * body.get_bone_global_pose(body.find_bone("DEF-head")).basis).orthonormalized().get_rotation_quaternion()
	var target := Vector3.ZERO
	if _seen:
		var delta := _last_head.inverse() * head
		if delta.w < 0.0: delta = -delta
		if delta.get_angle() > .00001:
			target = (delta.get_axis() * (-delta.get_angle() / maxf(dt,.001)) * .035).limit_length(deg_to_rad(7.0))
	_seen = true
	_last_head = head
	_sway = _sway.lerp(target,1.0-exp(-dt*10.0))
	for i in _rig.get_bone_count():
		var name := String(_rig.get_bone_name(i))
		if not name.begins_with("DEF-hair."): continue
		var rest := _rig.get_bone_rest(i)
		var q := Quaternion.IDENTITY
		if entry_time >= 0.0:
			var samples: Array = data.entry_samples
			var f := clampf(entry_time*24.0,0.0,float(samples.size()-1))
			var a: Array = samples[int(f)].rotations[name]
			var b: Array = samples[mini(int(f)+1,samples.size()-1)].rotations[name]
			q = Quaternion(a[0],a[1],a[2],a[3]).slerp(Quaternion(b[0],b[1],b[2],b[3]),f-floorf(f))
		elif _sway.length() > .00001:
			# Head-local angular inertia transformed into each segment's rest axes.
			var local_axis := _rig.get_bone_global_rest(i).basis.inverse() * _rig.get_bone_global_rest(_rig.find_bone("DEF-head")).basis * _sway.normalized()
			q = Quaternion(local_axis.normalized(),_sway.length()*(.65 if ".01." in name else 1.0))
		_rig.set_bone_pose_rotation(i,rest.basis.get_rotation_quaternion()*q)

func debug_state() -> Dictionary:
	return {"active":is_instance_valid(_rig),"bones":_rig.get_bone_count() if is_instance_valid(_rig) else 0,"sway_radians":_sway.length()}
