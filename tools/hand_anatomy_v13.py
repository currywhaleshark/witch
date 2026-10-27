"""Anatomical hand overlay for the unchanged player_humanoid_v11 bind.

Call after sampling/retargeting the body pose, and before keying all deform bones.
This module does not load/save a file or create actions when imported.
"""
import math
import bpy
from mathutils import Matrix, Quaternion, Vector


class AnatomicalHandRig:
    def __init__(self, rig, legacy_grip_action='v7_Hand_OpenGrip'):
        self.rig = rig
        self.rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
        self.inverse = {n: m.inverted() for n, m in self.rest.items()}
        self.axes = {}
        for side in ('L', 'R'):
            hand = self.rest['DEF-hand.' + side]
            middle = rig.data.bones['DEF-middle.01.' + side]
            thumb = rig.data.bones['DEF-thumb.01.' + side]
            direction = (middle.tail_local - middle.head_local).normalized()
            radial = thumb.head_local - middle.head_local
            radial = (radial - direction * radial.dot(direction)).normalized()
            palm = radial.cross(direction).normalized() * (1 if side == 'R' else -1)
            inv = hand.to_3x3().inverted()
            self.axes[side] = {'thumb': inv @ radial, 'finger': inv @ direction,
                               'palm': inv @ palm, 'palm_rest_world': palm}
        animation = rig.animation_data
        old_action, old_slot = animation.action, animation.action_slot
        scene = bpy.context.scene
        old_frame = scene.frame_current
        action = bpy.data.actions[legacy_grip_action]
        animation.action = action
        animation.action_slot = action.slots[0]
        scene.frame_set(49)
        bpy.context.view_layer.update()
        self.finger_basis = {}
        for bone in rig.pose.bones:
            if not any(bone.name.startswith('DEF-' + digit + '.') for digit in
                       ('thumb', 'index', 'middle', 'ring', 'pinky')):
                continue
            side = bone.name[-1]
            palm = self.axes[side]['palm_rest_world']
            # Conjugate the incorrect legacy rotation through the palm plane.
            # This changes only rotation, never bone rests/skin/vertex positions.
            reflection = Matrix.Identity(3)
            for i in range(3):
                for j in range(3):
                    reflection[i][j] -= 2 * palm[i] * palm[j]
            rest_rotation = self.rest[bone.name].to_3x3()
            local_reflection = rest_rotation.inverted() @ reflection @ rest_rotation
            corrected = local_reflection @ bone.matrix_basis.to_3x3() @ local_reflection
            self.finger_basis[bone.name] = corrected.to_quaternion().normalized()
        animation.action = old_action
        if old_action is not None:
            animation.action_slot = old_slot
        scene.frame_set(old_frame)
        bpy.context.view_layer.update()

    def orientation(self, side, finger_direction, palm_normal):
        """Return the hand's world quaternion from anatomical directions."""
        sign = 1 if side == 'R' else -1
        finger = Vector(finger_direction).normalized()
        palm = Vector(palm_normal)
        palm = (palm - finger * palm.dot(finger)).normalized()
        thumb = finger.cross(palm).normalized() * sign
        desired = Matrix((thumb, finger, palm * sign)).transposed()
        axes = self.axes[side]
        local = Matrix((axes['thumb'], axes['finger'], axes['palm'] * sign)).transposed()
        return (desired @ local.inverted()).to_quaternion().normalized()

    def apply_fingers(self, side, curl=1.0):
        """Apply corrected fingers and thumb opposition; curl is in [0,1]."""
        amount = min(1.0, max(0.0, float(curl)))
        for name, rotation in self.finger_basis.items():
            if name.endswith('.' + side):
                bone = self.rig.pose.bones[name]
                bone.rotation_mode = 'QUATERNION'
                bone.location = (0, 0, 0)
                bone.rotation_quaternion = Quaternion().slerp(rotation, amount)
                bone.scale = (1, 1, 1)
        bpy.context.view_layer.update()

    def apply_wrist(self, side, world_rotation, twist_state=None):
        """Preserve wrist/elbow positions and continuously distribute forearm twist.

        Keep one twist_state dict across consecutive frames of an external clip.
        Other body joints and all skirt/cardigan support bones are unchanged.
        """
        state = twist_state if twist_state is not None else {}
        rig = self.rig
        first = 'DEF-forearm.' + side
        hand_name = 'DEF-hand.' + side
        a = rig.pose.bones[first].head.copy()
        b = rig.pose.bones[hand_name].head.copy()
        qa = rig.pose.bones[first].matrix.to_quaternion()
        qb = Quaternion(world_rotation).normalized()
        relative = qa.inverted() @ qb
        if relative.w < 0:
            relative.negate()
        twist = relative.to_swing_twist('Y')[1]
        previous = state.get(first, twist)
        while twist - previous > math.pi:
            twist -= math.tau
        while twist - previous < -math.pi:
            twist += math.tau
        state[first] = twist
        rest_first = self.rest[first].to_quaternion()
        rest_twist = (rest_first.inverted() @ self.rest[hand_name].to_quaternion()).to_swing_twist('Y')[1]
        desired = {}
        for i, suffix in enumerate(('', '.001', '.002')):
            name = first + suffix
            fraction = i / 3
            offset = (rest_first @ Quaternion((0, 1, 0), rest_twist * fraction)).inverted() @ self.rest[name].to_quaternion()
            rotation = qa @ Quaternion((0, 1, 0), twist * fraction) @ offset
            desired[name] = Matrix.LocRotScale(a.lerp(b, fraction), rotation, Vector((1, 1, 1)))
        desired[hand_name] = Matrix.LocRotScale(b, qb, Vector((1, 1, 1)))
        for name, matrix in desired.items():
            bone = rig.pose.bones[name]
            parent = bone.parent
            parent_matrix = desired.get(parent.name, parent.matrix)
            bone.matrix_basis = self.inverse[name] @ self.rest[parent.name] @ parent_matrix.inverted() @ matrix
        bpy.context.view_layer.update()

    def staff_attachment(self, old_contract):
        """Mirror only the grip centre to the correct palm side; keep shaft axis."""
        palm = self.axes['R']['palm'].normalized()
        previous = Vector(old_contract['offset_bone_local'])
        offset = previous - 2 * palm * palm.dot(previous)
        result = dict(old_contract)
        result.update({'offset_bone_local': list(offset),
                       'preview_object': 'PROP_StaffPreview_v13',
                       'right_finger_curl_fraction': 1.0,
                       'anatomical_curl': 'palmar; legacy dorsal curl corrected',
                       'basis_columns_bone_local': old_contract['basis_columns_bone_local']})
        return result
