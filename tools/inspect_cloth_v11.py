"""Read-only cloth inspection helpers and an isolated waist-twist diagnostic.

Import this module from a background Blender evaluation. Imports create no data.
The optional --baseline-render command creates a temporary 97-frame action and
writes only renders/JSON below the supplied report directory; it never saves a
blend or modifies source assets. Pose changes are restored in memory.

Example:
  blender -b source_outfit_v10.blend -P tools/inspect_cloth_v11.py -- \
    --baseline-render reports/source_outfit_v11/review_agent

Bone-pose agreement, actual evaluated cloth deformation, and collision evidence
are separate results. None is labelled an arbitrary-pose or art approval.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import json
import math
from pathlib import Path
import sys

import numpy as np


STANDARD_POSES = [
    ("rest", None, 1),
    ("hip_combined_85", "v7_Stress_Hip_Combined", 85),
    ("hip_combined_113", "v7_Stress_Hip_Combined", 113),
    ("run_7", "v7_Trial_RunCycle", 7),
    ("attack_17", "v7_Trial_AttackPose", 17),
    ("shoulder_combined_85", "v7_Stress_Shoulder_Combined", 85),
    ("waist_minus45", "v11_Trial_WaistTwist", 19),
    ("waist_minus60", "v11_Trial_WaistTwist", 25),
    ("waist_plus45", "v11_Trial_WaistTwist", 67),
    ("waist_plus60", "v11_Trial_WaistTwist", 73),
]
WAIST_KEYS = [(1, 0), (19, -45), (25, -60), (49, 0), (67, 45), (73, 60), (97, 0)]


def _values(collection, field, width=1, dtype=np.float64):
    values = np.empty(len(collection) * width, dtype=dtype)
    collection.foreach_get(field, values)
    return values.reshape((-1, width)) if width > 1 else values


def mesh_record(obj, evaluated=False, world=True, depsgraph=None):
    """Capture actual evaluated vertices, triangle faces, UV loop data and edges.

    Index correspondence is valid only when topology is unchanged; shape keys
    and deform modifiers are included when evaluated=True. Temporary evaluated
    meshes are always released. No object/mesh is edited.
    """
    import bpy
    owner = obj.evaluated_get(depsgraph or bpy.context.evaluated_depsgraph_get()) if evaluated else obj
    mesh = owner.to_mesh(preserve_all_data_layers=True, depsgraph=depsgraph or bpy.context.evaluated_depsgraph_get()) if evaluated else obj.data
    try:
        mesh.calc_loop_triangles()
        vertices = _values(mesh.vertices, "co", 3)
        matrix = np.array(owner.matrix_world, dtype=np.float64)
        if world:
            vertices = vertices @ matrix[:3, :3].T + matrix[:3, 3]
        return {
            "name": obj.name, "space": "world" if world else "object",
            "vertices": vertices, "matrix_world": matrix,
            "edges": _values(mesh.edges, "vertices", 2, np.int32),
            "triangles": _values(mesh.loop_triangles, "vertices", 3, np.int32),
            "triangle_loops": _values(mesh.loop_triangles, "loops", 3, np.int32),
            "triangle_polygons": _values(mesh.loop_triangles, "polygon_index", 1, np.int32),
            "loop_vertices": _values(mesh.loops, "vertex_index", 1, np.int32),
            "polygon_starts": _values(mesh.polygons, "loop_start", 1, np.int32),
            "polygon_sizes": _values(mesh.polygons, "loop_total", 1, np.int32),
            "material_indices": _values(mesh.polygons, "material_index", 1, np.int32),
            "uv": {layer.name: _values(layer.data, "uv", 2) for layer in mesh.uv_layers},
        }
    finally:
        if evaluated:
            owner.to_mesh_clear()


def geometry_digest(record):
    digest = hashlib.sha256()
    for key in ("vertices", "edges", "loop_vertices", "polygon_starts", "polygon_sizes"):
        array = np.ascontiguousarray(record[key])
        digest.update(key.encode() + str(array.shape).encode() + array.tobytes())
    for name, uv in sorted(record["uv"].items()):
        digest.update(name.encode() + np.ascontiguousarray(uv).tobytes())
    return digest.hexdigest()


def source_preservation(source, candidate, tolerance=1e-7):
    """Exact indexed comparison; detects count changes before comparing UVs."""
    topology_keys = ("edges", "loop_vertices", "polygon_starts", "polygon_sizes")
    same_count = source["vertices"].shape == candidate["vertices"].shape
    delta = np.linalg.norm(source["vertices"] - candidate["vertices"], axis=1) if same_count else None
    uv_same = source["uv"].keys() == candidate["uv"].keys() and all(
        np.array_equal(source["uv"][key], candidate["uv"][key]) for key in source["uv"])
    return {
        "source": source["name"], "candidate": candidate["name"], "space": source["space"],
        "same_vertex_count": same_count,
        "same_indexed_topology": all(np.array_equal(source[key], candidate[key]) for key in topology_keys),
        "changed_vertices": int((delta > tolerance).sum()) if same_count else None,
        "maximum_rest_displacement": float(delta.max(initial=0)) if same_count else None,
        "all_uv_layers_and_loop_counts_unchanged": bool(uv_same),
        "source_geometry_uv_sha256": geometry_digest(source),
        "candidate_geometry_uv_sha256": geometry_digest(candidate),
        "scope": "Indexed rest surface; split parts require partition_preservation instead.",
    }


def partition_preservation(source, parts, vertex_maps, loop_maps, tolerance=1e-7):
    """Check source detail after garment separation using explicit source maps.

    Maps are dicts keyed by candidate object name; -1 means intentionally new
    geometry. Indices can come from stored attributes or the separation tool.
    This method does not guess coincident vertices/UVs when the map is absent.
    Source-ID-free unchanged meshes use source_preservation instead.
    """
    vertex_coverage = np.zeros(len(source["vertices"]), dtype=np.int32)
    loop_coverage = np.zeros(len(source["loop_vertices"]), dtype=np.int32)
    result = []
    for part in parts:
        name = part["name"]
        vm = np.asarray(vertex_maps[name], dtype=np.int64)
        lm = np.asarray(loop_maps[name], dtype=np.int64)
        assert len(vm) == len(part["vertices"]) and len(lm) == len(part["loop_vertices"])
        assert (vm >= -1).all() and (vm < len(vertex_coverage)).all()
        assert (lm >= -1).all() and (lm < len(loop_coverage)).all()
        valid_v = vm >= 0; valid_l = lm >= 0
        np.add.at(vertex_coverage, vm[valid_v], 1); np.add.at(loop_coverage, lm[valid_l], 1)
        delta = np.linalg.norm(part["vertices"][valid_v] - source["vertices"][vm[valid_v]], axis=1)
        mapped_corners = vm[part["loop_vertices"][valid_l]]
        corner_identity_ok = np.array_equal(mapped_corners, source["loop_vertices"][lm[valid_l]])
        uv = {}
        for layer in source["uv"]:
            if layer not in part["uv"]:
                uv[layer] = {"present": False}; continue
            difference = np.linalg.norm(part["uv"][layer][valid_l] - source["uv"][layer][lm[valid_l]], axis=1)
            uv[layer] = {"present": True, "changed_source_corners": int((difference > tolerance).sum()),
                         "maximum_delta": float(difference.max(initial=0))}
        result.append({"name": name, "mapped_vertices": int(valid_v.sum()), "new_vertices": int((~valid_v).sum()),
                       "changed_source_vertices": int((delta > tolerance).sum()),
                       "maximum_rest_displacement": float(delta.max(initial=0)),
                       "new_face_corners": int((~valid_l).sum()),
                       "mapped_corner_vertex_ids_match": bool(corner_identity_ok), "uv": uv})
    return {"parts": result, "source_vertices_not_represented": int((vertex_coverage == 0).sum()),
            "source_corners_not_represented": int((loop_coverage == 0).sum()),
            "source_corners_repeated": int((loop_coverage > 1).sum()),
            "scope": "Mapped vertex and UV preservation; inspect missing/repeated corners as explicit separation changes."}


def source_maps_from_attributes(source, obj, vertex_attribute, face_attribute):
    """Read explicit POINT/FACE source IDs and derive source corner IDs.

    Intended for parts separated by copying original faces. Unknown/new IDs stay
    -1. A face that has been retopologized must provide another mapping method;
    this helper raises rather than guessing its UV correspondence by proximity.
    """
    mesh = obj.data
    point_attr = mesh.attributes[vertex_attribute]; face_attr = mesh.attributes[face_attribute]
    assert point_attr.domain == "POINT" and face_attr.domain == "FACE"
    vm = _values(point_attr.data, "value", 1, np.int32)
    fm = _values(face_attr.data, "value", 1, np.int32)
    lm = np.full(len(mesh.loops), -1, dtype=np.int32)
    for polygon in mesh.polygons:
        source_face = int(fm[polygon.index])
        if source_face < 0:
            continue
        start = int(source["polygon_starts"][source_face]); size = int(source["polygon_sizes"][source_face])
        assert size == polygon.loop_total, (obj.name, polygon.index, "face topology changed")
        candidates = source["loop_vertices"][start:start + size]
        for loop_index in polygon.loop_indices:
            original_vertex = vm[mesh.loops[loop_index].vertex_index]
            match = np.flatnonzero(candidates == original_vertex)
            assert len(match) == 1, (obj.name, polygon.index, "ambiguous source corner")
            lm[loop_index] = start + int(match[0])
    return vm, lm, fm


def protected_rig_report(rig, protected_reference):
    """Validate protected v8 bones while allowing explicit v11 helper bones."""
    actual = {bone.name: {"parent": bone.parent.name if bone.parent else None,
                          "matrix": np.array(bone.matrix_local).tolist()} for bone in rig.data.bones}
    missing = sorted(set(protected_reference) - set(actual)); changed = []
    for name in set(protected_reference) & set(actual):
        reference = protected_reference[name]
        if actual[name]["parent"] != reference["parent"] or not np.array_equal(
                np.asarray(actual[name]["matrix"]), np.asarray(reference["matrix"])):
            changed.append(name)
    added = sorted(set(actual) - set(protected_reference))
    return {"rig_id": rig.get("rig_id"), "total_bones": len(actual),
            "protected_count": len(protected_reference), "missing_protected": missing,
            "changed_protected_parent_or_rest": sorted(changed),
            "protected_rest_and_parents_unchanged": not missing and not changed,
            "added_bones": {name: actual[name] for name in added}}


def number_summary(values):
    x = np.asarray(values, dtype=np.float64)
    if not len(x):
        return {"count": 0, "max": None, "p95": None, "p99": None}
    assert np.isfinite(x).all()
    return {"count": int(x.size), "max": float(x.max()), "p95": float(np.percentile(x, 95)),
            "p99": float(np.percentile(x, 99)), "gt2": int((x > 2).sum()),
            "gt4": int((x > 4).sum()), "gt10": int((x > 10).sum())}


def deformation_metrics(rest, posed):
    """Actual deformed surface metrics, independent of bone-head agreement."""
    assert rest["vertices"].shape == posed["vertices"].shape
    # Blender may choose a different diagonal for a bent quad when computing
    # loop triangles. Verify polygon topology, then measure the same rest
    # triangles in both poses, as a skinned runtime mesh does.
    for key in ("loop_vertices", "polygon_starts", "polygon_sizes"):
        assert np.array_equal(rest[key], posed[key]), key
    assert np.isfinite(posed["vertices"]).all()
    edge = rest["edges"]
    l0 = np.linalg.norm(rest["vertices"][edge[:, 1]] - rest["vertices"][edge[:, 0]], axis=1)
    l1 = np.linalg.norm(posed["vertices"][edge[:, 1]] - posed["vertices"][edge[:, 0]], axis=1)
    tri = rest["triangles"]
    t0 = rest["vertices"][tri]; t1 = posed["vertices"][tri]
    a0 = np.linalg.norm(np.cross(t0[:, 1] - t0[:, 0], t0[:, 2] - t0[:, 0]), axis=1) * .5
    a1 = np.linalg.norm(np.cross(t1[:, 1] - t1[:, 0], t1[:, 2] - t1[:, 0]), axis=1) * .5
    valid = a0 > 1e-12
    area_ratio = a1[valid] / a0[valid]
    return {"all_vertices_finite": True, "vertices_evaluated": len(posed["vertices"]),
            "edge_ratio": number_summary(l1[l0 > 1e-6] / l0[l0 > 1e-6]),
            "edge_ratio_rest_at_least_1mm": number_summary(l1[l0 >= .001] / l0[l0 >= .001]),
            "maximum_edge_length_gain": float((l1 - l0).max(initial=0)),
            "triangle_area_ratio": number_summary(area_ratio),
            "triangles_collapsed_below_1_percent_rest_area": int((area_ratio < .01).sum()),
            "scope": "Evaluated cloth vertices with fixed rest triangulation; not rig transforms and not collision approval."}


def _segment_triangle(p, q, triangle, epsilon=1e-9):
    """Moller-Trumbore segment hit; coplanar cases are reported separately."""
    a, b, c = triangle
    direction = q - p; e1 = b - a; e2 = c - a
    cross = np.cross(direction, e2); det = float(np.dot(e1, cross))
    scale = float(np.linalg.norm(e1) * np.linalg.norm(cross))
    if scale < 1e-24 or abs(det) < epsilon * scale:
        return None
    inv = 1.0 / det; delta = p - a
    u = float(np.dot(delta, cross) * inv)
    if u < -epsilon or u > 1 + epsilon:
        return None
    crossed = np.cross(delta, e1); v = float(np.dot(direction, crossed) * inv)
    if v < -epsilon or u + v > 1 + epsilon:
        return None
    t = float(np.dot(e2, crossed) * inv)
    return p + t * direction if -epsilon <= t <= 1 + epsilon else None


def _coplanar_triangles_overlap(first, second, normal, epsilon=1e-7):
    axis = int(np.argmax(np.abs(normal)))
    a = np.delete(first, axis, axis=1); b = np.delete(second, axis, axis=1)
    for triangle in (a, b):
        for i, j in ((0, 1), (1, 2), (2, 0)):
            edge = triangle[j] - triangle[i]; perpendicular = np.array([-edge[1], edge[0]])
            length = np.linalg.norm(perpendicular)
            if length < 1e-15:
                continue
            perpendicular /= length
            pa = a @ perpendicular; pb = b @ perpendicular
            if pa.max() < pb.min() - epsilon or pb.max() < pa.min() - epsilon:
                return False
    return True


def surface_contact_metrics(cloth, body, contact_distance=.002, epsilon=1e-9):
    """Actual triangle crossings plus explicitly limited proximity evidence.

    BVH overlap is only a candidate generator; segment/triangle tests confirm
    noncoplanar crossings. Coplanar surface contact is tested separately by 2D
    separating axes; coplanar contact alone does not prove volume penetration.
    Nearest normal signs are local hints, never a volume-inside test for an
    open/multipart fitting body. Vertex AND triangle-centroid samples are used.
    """
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    cv, ct = cloth["vertices"], cloth["triangles"]
    bv, bt = body["vertices"], body["triangles"]
    cbvh = BVHTree.FromPolygons(cv.tolist(), ct.tolist(), all_triangles=True)
    bbvh = BVHTree.FromPolygons(bv.tolist(), bt.tolist(), all_triangles=True)
    candidates = cbvh.overlap(bbvh)
    hits = []
    for ci, bi in candidates:
        ca, ba = cv[ct[ci]], bv[bt[bi]]
        cn = np.cross(ca[1] - ca[0], ca[2] - ca[0]); bn = np.cross(ba[1] - ba[0], ba[2] - ba[0])
        cnorm, bnorm = np.linalg.norm(cn), np.linalg.norm(bn)
        if cnorm < 1e-20 or bnorm < 1e-20:
            continue
        if np.linalg.norm(np.cross(cn / cnorm, bn / bnorm)) < 1e-7 and abs(np.dot(ca[0] - ba[0], bn / bnorm)) < 1e-7:
            continue
        points = []
        for triangle, target in ((ca, ba), (ba, ca)):
            for i, j in ((0, 1), (1, 2), (2, 0)):
                hit = _segment_triangle(triangle[i], triangle[j], target, epsilon)
                if hit is not None:
                    points.append(hit)
        if points:
            hits.append({"cloth_triangle": int(ci), "body_triangle": int(bi), "point": np.mean(points, axis=0).tolist()})
    # BVH.overlap omits coplanar triangles in Blender. Query the radius enclosing
    # each cloth triangle, then confirm plane agreement and 2D triangle overlap.
    coplanar = set()
    body_triangles = bv[bt]
    body_normals = np.cross(body_triangles[:, 1] - body_triangles[:, 0], body_triangles[:, 2] - body_triangles[:, 0])
    body_lengths = np.linalg.norm(body_normals, axis=1)
    body_normals /= np.maximum(body_lengths[:, None], 1e-30)
    for ci, ca in enumerate(cv[ct]):
        cn = np.cross(ca[1] - ca[0], ca[2] - ca[0]); length = np.linalg.norm(cn)
        if length < 1e-20:
            continue
        cn /= length; center = ca.mean(axis=0); radius = float(np.linalg.norm(ca - center, axis=1).max()) + 1e-7
        for _, _, bi, _ in bbvh.find_nearest_range(Vector(center), radius):
            bn = body_normals[bi]; ba = body_triangles[bi]
            if body_lengths[bi] < 1e-20 or np.linalg.norm(np.cross(cn, bn)) >= 1e-7:
                continue
            if abs(np.dot(ca[0] - ba[0], bn)) < 1e-7 and _coplanar_triangles_overlap(ca, ba, cn):
                coplanar.add((int(ci), int(bi)))
    samples = np.concatenate([cv, cv[ct].mean(axis=1)])
    distances = []; signed = []
    for xyz in samples:
        location, normal, _, distance = bbvh.find_nearest(Vector(xyz))
        if location is None:
            continue
        distances.append(float(distance)); signed.append(float(np.dot(xyz - np.array(location), np.array(normal))))
    distances = np.array(distances); signed = np.array(signed)
    return {"body": body["name"], "cloth": cloth["name"],
            "confirmed_noncoplanar_crossing_pairs": len(hits),
            "cloth_triangles_with_crossing": len({hit["cloth_triangle"] for hit in hits}),
            "crossing_examples": hits[:100], "confirmed_coplanar_contact_pairs": len(coplanar),
            "proximity_samples": len(distances), "samples_within_contact_distance": int((distances <= contact_distance).sum()),
            "contact_distance": contact_distance,
            "minimum_unsigned_distance": float(distances.min()) if len(distances) else None,
            "nearest_normal_negative_samples_hint_only": int((signed < -.001).sum()),
            "scope": "Actual crossings, coplanar surface contacts and sampled proximity; local-normal signs do not prove volume penetration. Visual inspection required."}


@contextmanager
def preserved_pose(rig):
    """Restore all touched pose/action/NLA state after an isolated sample."""
    import bpy
    scene = bpy.context.scene
    rig.animation_data_create()
    action = rig.animation_data.action; slot = rig.animation_data.action_slot
    frame = scene.frame_current; subframe = scene.frame_subframe; position = rig.data.pose_position
    bones = {p.name: (p.rotation_mode, p.matrix_basis.copy()) for p in rig.pose.bones}
    mute = [(track, track.mute) for track in rig.animation_data.nla_tracks]
    try:
        for track, _ in mute:
            track.mute = True
        yield
    finally:
        rig.animation_data.action = action
        if action is not None and slot is not None:
            rig.animation_data.action_slot = slot
        rig.data.pose_position = position
        scene.frame_set(frame, subframe=subframe)
        for name, (mode, matrix) in bones.items():
            rig.pose.bones[name].rotation_mode = mode
            rig.pose.bones[name].matrix_basis = matrix
        for track, state in mute:
            track.mute = state
        bpy.context.view_layer.update()


def create_waist_twist_action(rig, name="v11_Trial_WaistTwist", spine_share=.65):
    """Create a reusable 97-frame diagnostic: fixed pelvis, spine/chest ±60°.

    Local +Y is the long axis of both v8 spine bones. Exact ±45° keys are also
    included. All bones receive constant rest TRS tracks so clip switching does
    not inherit a previous pose. No rig bones/bind matrices/source actions change.
    This returns a new action but does not save the blend or promote a runtime.
    """
    import bpy
    from mathutils import Matrix, Quaternion
    assert 0 <= spine_share <= 1
    assert name not in bpy.data.actions, f"Action already exists: {name}"
    assert all(name in rig.pose.bones for name in ("DEF-pelvis", "DEF-spine", "DEF-chest"))
    with preserved_pose(rig):
        action = bpy.data.actions.new(name)
        rig.animation_data.action = action
        rig.data.pose_position = "POSE"
        for frame, degrees in WAIST_KEYS:
            for bone in rig.pose.bones:
                bone.rotation_mode = "QUATERNION"; bone.matrix_basis = Matrix.Identity(4)
            rig.pose.bones["DEF-spine"].rotation_quaternion = Quaternion((0, 1, 0), math.radians(degrees * spine_share))
            rig.pose.bones["DEF-chest"].rotation_quaternion = Quaternion((0, 1, 0), math.radians(degrees * (1 - spine_share)))
            for bone in rig.pose.bones:
                for channel in ("location", "rotation_quaternion", "scale"):
                    bone.keyframe_insert(data_path=channel, frame=frame, group=bone.name)
        for layer in action.layers:
            for strip in layer.strips:
                for slot in action.slots:
                    bag = strip.channelbag(slot)
                    if bag:
                        for curve in bag.fcurves:
                            for key in curve.keyframe_points:
                                key.interpolation = "LINEAR"
        action["diagnostic_only"] = True
        action["twist_spine_share"] = spine_share
        action["twist_key_degrees_json"] = json.dumps(WAIST_KEYS)
        action["pelvis_fixed"] = True
    return action


def apply_action_sample(rig, action, frame):
    import bpy
    from mathutils import Matrix
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    rig.data.pose_position = "POSE"
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()


def baseline_render(out):
    import bpy
    from mathutils import Vector
    assert bpy.app.background, "Use a separate background Blender; never run this renderer in live authoring."
    out = Path(out).resolve(); out.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene; rig = bpy.data.objects["PlayerRig_v7"]
    names = ["SourceOutfit_Upper_v10", "SourceOutfit_Skirt_v10"]
    before = {name: mesh_record(bpy.data.objects[name], world=False) for name in names}
    action = create_waist_twist_action(rig)
    report = {"source_blend": bpy.data.filepath, "source_saved": False,
              "action": action.name, "key_degrees": WAIST_KEYS, "spine_share": .65,
              "pelvis_fixed": True, "frames": [], "scope": "Blender baseline renders only; no candidate or engine approval."}
    cam = scene.camera
    cam.animation_data_clear(); cam.constraints.clear(); cam.data.ortho_scale = 1.93
    cam.location = (0, -5, .91)
    cam.rotation_euler = (Vector((0, 0, .87)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x = 600; scene.render.resolution_y = 800; scene.render.resolution_percentage = 100
    with preserved_pose(rig):
        apply_action_sample(rig, action, 1)
        rest = {name: mesh_record(bpy.data.objects[name], evaluated=True) for name in names}
        pelvis = np.array(rig.pose.bones["DEF-pelvis"].matrix)
        for label, frame in (("minus60", 25), ("plus60", 73)):
            apply_action_sample(rig, action, frame)
            assert np.array_equal(pelvis, np.array(rig.pose.bones["DEF-pelvis"].matrix)), "Pelvis must be identical across the waist test."
            entry = {"frame": frame, "label": label, "bone_pose": {
                name: np.array(rig.pose.bones[name].matrix).tolist() for name in ("DEF-pelvis", "DEF-spine", "DEF-chest")}, "evaluated_cloth": {}}
            for name in names:
                entry["evaluated_cloth"][name] = deformation_metrics(rest[name], mesh_record(bpy.data.objects[name], evaluated=True))
            filename = f"v10_waist_{label}_front.png"
            scene.render.filepath = str(out / filename); bpy.ops.render.render(write_still=True)
            entry["render"] = filename; report["frames"].append(entry)
    report["source_preservation"] = {name: source_preservation(before[name], mesh_record(bpy.data.objects[name], world=False)) for name in names}
    (out / "baseline_waist.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("BASELINE_WAIST_COMPLETE", str(out), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-render", type=Path, required=True)
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    args = parser.parse_args(argv)
    baseline_render(args.baseline_render)


if __name__ == "__main__":
    main()
