extends Node3D
## Prepared equipment rig follower. No active skill or character/combat mutation.
const DIR := "res://assets/equipment/exoskeleton_v3/"
var manifest: Dictionary
var rig: Skeleton3D
var body: Skeleton3D
var rest: Dictionary = {}
var body_rest: Dictionary = {}
var current_frames: Dictionary = {}
var bridge_lengths: Dictionary = {}

func vec(a: Array) -> Vector3:
	return Vector3(a[0],a[2],-a[1])

func matrix(a: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(a[0][0],a[1][0],a[2][0]),Vector3(a[0][1],a[1][1],a[2][1]),Vector3(a[0][2],a[1][2],a[2][2])),Vector3(a[0][3],a[1][3],a[2][3]))

func find_rig(node: Node) -> Skeleton3D:
	if node is Skeleton3D:return node
	for child in node.get_children():
		var found:=find_rig(child)
		if found!=null:return found
	return null

func initialize(character: Skeleton3D) -> bool:
	body=character
	manifest=JSON.parse_string(FileAccess.get_file_as_string(DIR+"parts.json"))
	var packed:PackedScene=load(DIR+"exoskeleton_v3.glb")
	var asset:=packed.instantiate();add_child(asset);rig=find_rig(asset)
	if rig==null:return false
	for role in manifest.mechanism_rest_godot:rest[role]=matrix(manifest.mechanism_rest_godot[role])
	for i in body.get_bone_count():body_rest[body.get_bone_name(i)]=body.get_bone_global_rest(i)
	return true

func bone(name: String) -> Transform3D:
	return body.get_bone_global_pose(body.find_bone(name))

func frame(origin: Vector3,direction: Vector3,front: Vector3) -> Transform3D:
	var y:=direction.normalized();var z:=(front-y*front.dot(y)).normalized();var x:=y.cross(z).normalized()
	return Transform3D(Basis(x,y,z),origin)

func sync_pose() -> void:
	var cfg:Dictionary=manifest.config
	var chest:Transform3D=bone("DEF-chest")*body_rest["DEF-chest"].affine_inverse()
	var poses:Dictionary={}
	for role in ["back_power","back_link_L","back_link_R"]:poses[role]=chest*rest[role]
	for side in ["L","R"]:
		var sign_value:=1.0 if side=="L" else -1.0
		var upper:String="DEF-upper_arm."+side;var fore:String="DEF-forearm."+side;var shin:String="DEF-shin."+side
		var s:=bone(upper).origin;var e:=bone(fore).origin;var w:=bone("DEF-hand."+side).origin
		var delta:Transform3D=bone(upper)*body_rest[upper].affine_inverse()
		var preferred:Vector3=delta.basis*vec(manifest.anchors[side].hinge_rest)
		# The anatomical flexion side is fixed by handedness. Choosing the sign
		# against upper-arm roll flips the entire linkage during wrist pronation.
		var n:=(s-e).normalized().cross((w-e).normalized())*sign_value
		if n.length()<.08:n=preferred.normalized()
		else:n=n.normalized()
		var ss:Vector3=s+n*cfg.arm_offset_shoulder;var ee:Vector3=e+n*cfg.arm_offset_elbow;var ww:Vector3=w+n*cfg.arm_offset_wrist
		poses["upper_"+side]=frame(ss,ee-ss,n)
		poses["shoulder_"+side]=frame(ss,ee-ss,delta.basis*Vector3(sign_value,0,0))
		poses["elbow_"+side]=frame(ee,ww-ee,n)
		poses["forearm_"+side]=poses["elbow_"+side];poses["wrist_"+side]=poses["elbow_"+side]
		var leg:Transform3D=bone(shin)*body_rest[shin].affine_inverse()
		for role in ["knee_"+side,"shin_"+side]:poses[role]=leg*rest[role]
		var spec:Dictionary=manifest.bridge[side]
		var start:Vector3=chest*vec(spec.start);var axis:Vector3=(ss-start).normalized();var length:float=start.distance_to(ss)
		bridge_lengths[side]=length
		for i in int(spec.segments):
			poses["bridge_%s_%d"%[side,i]]=frame(start+axis*(length-float(spec.segment_length))*i/(int(spec.segments)-1.0),axis,chest.basis*Vector3.UP)
		poses["mount_"+side]=chest*rest["mount_"+side]
	for role in poses:
		var i:=rig.find_bone("EXO-"+role);assert(i>=0)
		var movement:Transform3D=poses[role]*rest[role].affine_inverse()
		rig.set_bone_global_pose(i,movement*rig.get_bone_global_rest(i))
	current_frames=poses
