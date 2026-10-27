"""Keep a quiet idle's existing pleated skirt shape in pelvis-local space.

This is a pose-only correction for the low-amplitude standing idle. It is not
the moving-leg collision solution and must not be used for running/large hips.
The caller supplies frame-one matrix_basis copies, applies the body pose, then
calls apply before keying the complete pose. No mesh, rest, action or file edit.
"""
import bpy


class IdleSkirtFix:
    names = tuple(f'DEF-skirt.{i:02}' for i in range(1, 17)) + tuple(
        f'DEF-skirt_lower.{i:02}' for i in range(1, 17))

    def __init__(self, rig, reference_basis):
        self.rig = rig
        self.reference_basis = {name: reference_basis[name].copy() for name in self.names}
        if any(name not in rig.pose.bones for name in self.names):
            raise ValueError('Expected the existing 32 v11 skirt supports')

    def apply(self):
        for name, matrix in self.reference_basis.items():
            self.rig.pose.bones[name].matrix_basis = matrix
        bpy.context.view_layer.update()
        return {'method': 'fixed_reference_local_supports', 'support_count': len(self.names)}
