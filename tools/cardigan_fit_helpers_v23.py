"""Garment-fit helpers borrowed by the v12 authoring helper.

The v12 helper originally borrowed these two functions from an unpublished
cardigan audit script that is not in the repository. They are rebuilt here from
their use in ``fit_cardigan``: linear-blend skinned rest vertices in armature
space, and a nearest-surface tree over the skinned collider bodies.
"""
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def deformed_points(obj, weights, rig, inverse_rest):
    # Rest vertices (object space) skinned by the current pose; armature at the origin.
    rest = np.array([(obj.matrix_world @ v.co)[:] for v in obj.data.vertices])
    homogeneous = np.c_[rest, np.ones(len(rest))]
    result = np.zeros((len(rest), 3))
    for index, bone in enumerate(rig.data.bones):
        column = weights[:, index]
        used = np.nonzero(column)[0]
        if not len(used):
            continue
        skin = np.array(rig.pose.bones[bone.name].matrix @ inverse_rest[bone.name])
        result[used] += column[used, None] * (homogeneous[used] @ skin.T)[:, :3]
    return result


def evaluated_collision_tree(colliders, rig, inverse_rest):
    # One tree over every skinned collider surface; face normals follow the source winding.
    points = []
    faces = []
    for obj, weights in colliders:
        offset = len(points)
        points += [Vector(p) for p in deformed_points(obj, weights, rig, inverse_rest)]
        faces += [[offset + i for i in polygon.vertices] for polygon in obj.data.polygons]
    return BVHTree.FromPolygons(points, faces, all_triangles=False)
