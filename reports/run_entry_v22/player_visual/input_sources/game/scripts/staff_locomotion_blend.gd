extends RefCounted
## Keeps a two-hand prop closed while mixing poses with different arm-twist winding.
## Only used between idle and run; authored clips, movement and action clocks are untouched.
const LEFT_GRIP_OFFSET := Vector3(-0.0074299667, 0.0480000190, 0.0158049259)
const GRIP_SPACING := -0.26
var arms: Array = []
var grip: Transform3D

func initialize(skeleton: Skeleton3D, right_grip: Transform3D) -> void:
	grip = right_grip
	for side in ["R", "L"]:
		var chain: Array[int] = []
		for stem in ["upper_arm", "forearm"]:
			for suffix in ["", ".001", ".002"]:
				chain.append(skeleton.find_bone("DEF-" + stem + "." + side + suffix))
		chain.append(skeleton.find_bone("DEF-hand." + side))
		var lengths: Array[float] = []
		for start in [0, 3]:
			lengths.append(skeleton.get_bone_global_rest(chain[start]).origin.distance_to(skeleton.get_bone_global_rest(chain[start + 3]).origin))
		arms.append({"bones": chain, "lengths": lengths, "offset": grip.origin if side == "R" else LEFT_GRIP_OFFSET})

func capture(skeleton: Skeleton3D) -> Dictionary:
	var poses := {}
	for arm in arms:
		for index: int in arm.bones:
			poses[index] = skeleton.get_bone_global_pose(index)
	return poses

func apply(skeleton: Skeleton3D, first: Dictionary, second: Dictionary, weight: float) -> void:
	var right: int = arms[0].bones[6]
	var frame_a: Transform3D = first[right] * grip
	var frame_b: Transform3D = second[right] * grip
	# Interpolate the held object once in skeleton space, then solve both hands to it.
	# Local rotation interpolation can accumulate almost a full turn down a twist chain.
	var frame := frame_a.interpolate_with(frame_b, weight)
	var hand_bases: Array[Basis] = [frame.basis * grip.basis.inverse()]
	var left: int = arms[1].bones[6]
	var relative_a: Basis = frame_a.basis.inverse() * first[left].basis
	var relative_b: Basis = frame_b.basis.inverse() * second[left].basis
	hand_bases.append(frame.basis * relative_a.slerp(relative_b, weight))
	var shoulders: Array[Vector3] = []
	for arm in arms:
		shoulders.append(skeleton.get_bone_global_pose(arm.bones[0]).origin)
	# Translate the shared grip only when needed to keep both wrists within reach.
	# This also handles short stop/restart blends without stretching either arm.
	for iteration in 8:
		for side in 2:
			var arm: Dictionary = arms[side]
			var shift: Vector3 = frame.basis.y * (GRIP_SPACING if side == 1 else 0.0) - hand_bases[side] * arm.offset
			var delta: Vector3 = frame.origin + shift - shoulders[side]
			var reach: float = arm.lengths[0] + arm.lengths[1] - 0.0005
			if delta.length() > reach:
				frame.origin = shoulders[side] + delta.normalized() * reach - shift
	for side in 2:
		var arm: Dictionary = arms[side]
		var ids: Array = arm.bones
		var shoulder := shoulders[side]
		var wrist: Vector3 = frame.origin + frame.basis.y * (GRIP_SPACING if side == 1 else 0.0) - hand_bases[side] * arm.offset
		var delta := wrist - shoulder
		var distance := maxf(delta.length(), 0.000001)
		var axis := delta / distance
		var along: float = (arm.lengths[0] * arm.lengths[0] - arm.lengths[1] * arm.lengths[1] + distance * distance) / (2.0 * distance)
		var height: float = sqrt(maxf(0.0, arm.lengths[0] * arm.lengths[0] - along * along))
		var preferred: Vector3 = first[ids[3]].origin.lerp(second[ids[3]].origin, weight) - shoulder
		var pole := preferred - axis * preferred.dot(axis)
		if pole.length_squared() < 0.00000001:
			pole = axis.cross(Vector3.UP)
			if pole.length_squared() < 0.00000001:
				pole = axis.cross(Vector3.RIGHT)
		var elbow := shoulder + axis * along + pole.normalized() * height
		for start in [0, 3]:
			var a := shoulder if start == 0 else elbow
			var b := elbow if start == 0 else wrist
			var direction := (b - a).normalized()
			for segment in 3:
				var index: int = ids[start + segment]
				var sampled: Transform3D = first[index].interpolate_with(second[index], weight)
				var align := Quaternion(sampled.basis.y.normalized(), direction)
				var basis := Basis(align) * sampled.basis
				skeleton.set_bone_global_pose(index, Transform3D(basis, a.lerp(b, segment / 3.0)))
		skeleton.set_bone_global_pose(ids[6], Transform3D(hand_bases[side], wrist))
