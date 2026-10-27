"""Read-only Blender hand anatomy, grip, preservation and provenance checker.

blender -b --python tools/validate_hand_motion_v13.py -- --source candidate.blend \
  --baseline baseline.blend --output report.json --clips combat_idle_staff \
  --contract hand_motion_contract.json --provenance external_motion_sources.json

Only the output JSON is written. Run in a separate background process. The
report separates measured anatomy/grip proxies from mesh-contact/art approval.
See reports/hand_motion_v13/validation_report_spec.md for the optional contracts.
"""
from array import array
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import traceback

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BASELINE = ROOT / "assets/characters/player/3d/source/middle_school_v1/combat_animation_v12/combat_animation_v12.blend"
FINGERS = ("index", "middle", "ring", "pinky")


def sha(path):
    with Path(path).open("rb") as stream:
        digest = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def vec(value):
    return [float(x) for x in value]


def finite_matrix(value):
    return all(math.isfinite(x) for row in value for x in row)


def curves(action):
    if getattr(action, "is_action_layered", False):
        for layer in action.layers:
            for strip in layer.strips:
                for slot in action.slots:
                    bag = strip.channelbag(slot)
                    if bag:
                        yield from bag.fcurves
    elif hasattr(action, "fcurves"):
        yield from action.fcurves


def action_digest(action):
    records = []
    for curve in curves(action):
        records.append((curve.data_path, curve.array_index, curve.extrapolation,
                        [(tuple(k.co), tuple(k.handle_left), tuple(k.handle_right),
                          k.interpolation, k.handle_left_type, k.handle_right_type)
                         for k in curve.keyframe_points]))
    return hashlib.sha256(repr(sorted(records, key=lambda x: (x[0], x[1]))).encode()).hexdigest()


def mesh_signature(obj):
    mesh = obj.data
    geometry, uv_hash, weights = (hashlib.sha256() for _ in range(3))
    for collection, field, width, dtype in (
        (mesh.vertices, "co", 3, "f"), (mesh.edges, "vertices", 2, "i"),
        (mesh.loops, "vertex_index", 1, "i"),
        (mesh.polygons, "loop_start", 1, "i"),
        (mesh.polygons, "loop_total", 1, "i"),
        (mesh.polygons, "material_index", 1, "i"),
    ):
        values = array(dtype, [0]) * (len(collection) * width)
        collection.foreach_get(field, values)
        geometry.update(field.encode() + values.tobytes())
    if mesh.shape_keys:
        for block in mesh.shape_keys.key_blocks:
            values = array("f", [0]) * (len(block.data) * 3)
            block.data.foreach_get("co", values)
            geometry.update(block.name.encode() + values.tobytes())
    for layer in mesh.uv_layers:
        values = array("f", [0]) * (len(layer.data) * 2)
        layer.data.foreach_get("uv", values)
        uv_hash.update(layer.name.encode() + values.tobytes())
    for group in obj.vertex_groups:
        weights.update(group.name.encode() + b"\0")
    for vertex in mesh.vertices:
        groups = sorted((group.group, group.weight) for group in vertex.groups)
        weights.update(struct.pack("<II", vertex.index, len(groups)))
        for index, weight in groups:
            weights.update(struct.pack("<If", index, weight))
    return {"vertices": len(mesh.vertices), "polygons": len(mesh.polygons),
            "geometry_sha256": geometry.hexdigest(), "uv_sha256": uv_hash.hexdigest(),
            "weights_sha256": weights.hexdigest(),
            "object_matrix": [vec(row) for row in obj.matrix_world]}


def rig_record(rig):
    return {bone.name: {"parent": bone.parent.name if bone.parent else None,
                        "rest": [vec(row) for row in bone.matrix_local],
                        "head": vec(bone.head_local), "tail": vec(bone.tail_local),
                        "deform": bone.use_deform}
            for bone in rig.data.bones}


def snapshot(rig_name, excluded_meshes):
    rig = bpy.data.objects[rig_name]
    return {"meshes": {obj.name: mesh_signature(obj) for obj in bpy.data.objects
                       if obj.type == "MESH" and obj.name not in excluded_meshes
                       and not obj.get("preview_only", False)},
            "excluded_preview_meshes": [obj.name for obj in bpy.data.objects
                                        if obj.type == "MESH" and
                                        (obj.name in excluded_meshes or obj.get("preview_only", False))],
            "rig": rig_record(rig), "rig_id": rig.get("rig_id"),
            "actions": {action.name: action_digest(action) for action in bpy.data.actions}}


def sample_action(rig, action, frame):
    rig.animation_data_create()
    rig.animation_data.action = None
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    rig.data.pose_position = "POSE"
    rig.animation_data.action = action
    if len(action.slots):
        rig.animation_data.action_slot = action.slots[0]
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()


def hand_frame(rig, side, body_right):
    hand = rig.data.bones["DEF-hand." + side]
    middle = rig.data.bones["DEF-middle.01." + side]
    thumb = rig.data.bones["DEF-thumb.01." + side]
    direction = (middle.tail_local - middle.head_local).normalized()
    thumb_axis = thumb.head_local - middle.head_local
    thumb_axis = (thumb_axis - direction * thumb_axis.dot(direction)).normalized()
    location = (hand.head_local - rig.data.bones["DEF-pelvis"].head_local).dot(body_right)
    if abs(location) < 0.001 or thumb_axis.length < 0.9:
        raise ValueError("Degenerate hand landmark frame: " + side)
    # The handed sign comes from the actual side of the body in rest space;
    # thumb-side and finger direction come from geometric landmarks.
    sign = 1 if location > 0 else -1
    return {"side_coordinate": location, "sign": sign, "finger": direction,
            "thumb": thumb_axis, "palm": thumb_axis.cross(direction).normalized() * sign}


def anatomy_sample(rig, side, frame, minimum_bend, minimum_alignment):
    hand = rig.pose.bones["DEF-hand." + side]
    rest_hand = hand.bone
    hand_delta = hand.matrix.to_3x3() @ rest_hand.matrix_local.to_3x3().inverted()
    palm = (hand_delta @ frame["palm"]).normalized()
    thumb_axis = (hand_delta @ frame["thumb"]).normalized()
    observations, failures, measurable = {}, [], 0
    for finger in FINGERS:
        joints = []
        for index in range(1, 4):
            bone = rig.pose.bones[f"DEF-{finger}.{index:02}.{side}"]
            parent_delta = bone.parent.matrix.to_3x3() @ bone.parent.bone.matrix_local.to_3x3().inverted()
            straight = (parent_delta @ (bone.bone.tail_local - bone.bone.head_local)).normalized()
            bent = (bone.tail - bone.head).normalized()
            dot = max(-1.0, min(1.0, straight.dot(bent)))
            angle = math.degrees(math.acos(dot))
            curl = bent - straight * dot
            transported_palm = (parent_delta @ frame["palm"]).normalized()
            alignment = curl.normalized().dot(transported_palm) if angle >= minimum_bend and curl.length > 1e-6 else None
            if alignment is not None:
                measurable += 1
                if alignment < minimum_alignment:
                    failures.append(bone.name)
            joints.append({"bone": bone.name, "bend_degrees": angle,
                           "curl_dot_anatomical_palm": alignment,
                           "curl_toward_palm": None if alignment is None else alignment >= minimum_alignment})
        observations[finger] = joints
    thumb = rig.pose.bones[f"DEF-thumb.03.{side}"]
    straight_thumb_tip = hand.matrix @ rest_hand.matrix_local.inverted() @ thumb.bone.tail_local
    thumb_displacement = thumb.tail - straight_thumb_tip
    finger_roots = [rig.pose.bones[f"DEF-{name}.01.{side}"].head for name in FINGERS]
    finger_center = sum(finger_roots, Vector()) / len(finger_roots)
    return {"hand_side_coordinate_in_rest": frame["side_coordinate"],
            "expected_chirality_sign_from_rest_side": frame["sign"],
            "thumb_side_armature": vec(thumb_axis), "anatomical_palm_normal_armature": vec(palm),
            "hand_matrix_determinant": hand.matrix.to_3x3().determinant(),
            "measurable_joint_count": measurable, "wrong_direction_joints": failures,
            "fingers": observations,
            "thumb_opposition": {
                "tip_displacement_toward_finger_side_m": thumb_displacement.dot(-thumb_axis),
                "tip_displacement_toward_palm_m": thumb_displacement.dot(palm),
                "tip_to_finger_root_center_m": (thumb.tail - finger_center).length,
                "scope": "Measured thumb opposition proxies; not a surface contact or aesthetic verdict."}}


def line_distance(point, center, axis):
    delta = point - center
    return (delta - axis * delta.dot(axis)).length


def secondary_grip_sample(rig, specification, primary):
    """Measure the support hand against the actual primary-hand shaft."""
    side = specification["bone"].rsplit(".", 1)[-1]
    center = Vector(primary["attachment_center_world"])
    axis = Vector(primary["shaft_axis_world"]).normalized()
    points = []
    for finger in FINGERS:
        bones = [rig.pose.bones[f"DEF-{finger}.{index:02}.{side}"] for index in range(1, 4)]
        points.extend([rig.matrix_world @ bones[0].head] + [rig.matrix_world @ bone.tail for bone in bones])
    cage = sum(points, Vector()) / len(points)
    axial = (cage - center).dot(axis)
    return {"bone": specification["bone"], "finger_cage_center_world": vec(cage),
            "finger_cage_center_to_axis_m": line_distance(cage, center, axis),
            "actual_shaft_axial_m": axial,
            "shaft_axial_error_m": abs(axial - specification["shaft_axial_m"]),
            "scope": "Support-hand finger cage against primary-hand shaft; not skin/contact clearance."}


def grip_sample(rig, attachment, hand_mesh):
    hand = rig.pose.bones[attachment["bone"]]
    basis = Matrix(attachment["basis_columns_bone_local"]).transposed().to_4x4()
    transform = rig.matrix_world @ hand.matrix @ Matrix.Translation(Vector(attachment["offset_bone_local"])) @ basis
    center, axis = transform.translation, (transform.to_3x3() @ Vector((0, 1, 0))).normalized()
    side = hand.name.rsplit(".", 1)[-1]
    per_finger, centers = {}, []
    for finger in FINGERS:
        bones = [rig.pose.bones[f"DEF-{finger}.{index:02}.{side}"] for index in range(1, 4)]
        points = [rig.matrix_world @ bones[0].head] + [rig.matrix_world @ bone.tail for bone in bones]
        # The four joint points form a crude bent-finger cage. This is a proxy,
        # explicitly separate from skin-surface contact.
        cage_center = sum(points, Vector()) / 4
        centers.append(cage_center)
        per_finger[finger] = {"joint_axis_distances_m": [line_distance(p, center, axis) for p in points],
                              "cage_center_to_axis_m": line_distance(cage_center, center, axis),
                              "tip_to_axis_m": line_distance(points[-1], center, axis)}
    cage = sum(centers, Vector()) / len(centers)
    thumb_tip = rig.matrix_world @ rig.pose.bones[f"DEF-thumb.03.{side}"].tail
    result = {"attachment_center_world": vec(center), "shaft_axis_world": vec(axis),
              "shaft_radius_m": attachment.get("shaft_radius_m"),
              "finger_cage_center_to_axis_m": line_distance(cage, center, axis),
              "finger_cage_center_to_grip_origin_m": (cage - center).length,
              "thumb_tip_to_axis_m": line_distance(thumb_tip, center, axis),
              "fingers": per_finger}
    if hand_mesh is not None:
        evaluated = hand_mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mesh = evaluated.to_mesh()
        try:
            points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
            tree = BVHTree.FromPolygons(points, [list(p.vertices) for p in mesh.polygons])
            nearest = tree.find_nearest(center)
            result["grip_origin_to_hand_surface_m"] = float(nearest[3]) if nearest[0] is not None else None
            if nearest[0] is not None:
                radial = line_distance(nearest[0], center, axis)
                axial = (nearest[0] - center).dot(axis)
                result["nearest_hand_surface_world"] = vec(nearest[0])
                result["nearest_hand_surface_polygon"] = int(nearest[2])
                result["nearest_hand_surface_axis_distance_m"] = radial
                result["nearest_hand_surface_axial_m"] = axial
                result["nearest_hand_surface_inside_shaft_volume"] = (
                    radial < attachment.get("shaft_radius_m", 0.0) and
                    -attachment.get("below_grip_m", 0.0) <= axial <= attachment.get("above_grip_m", 0.0))
            result["evaluated_hand_vertices_finite"] = all(all(math.isfinite(c) for c in point) for point in points)
        finally:
            evaluated.to_mesh_clear()
    result["scope"] = "Cage/axis and nearest skin distances, not full staff-finger collision or grasp force validation."
    return result


def import_source_animation(path):
    before = {action.as_pointer() for action in bpy.data.actions}
    suffix = path.suffix.lower()
    if suffix == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(path), use_anim=True)
    elif suffix == ".bvh":
        bpy.ops.import_anim.bvh(filepath=str(path), target="ARMATURE")
    elif suffix in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=str(path))
    elif suffix == ".blend":
        with bpy.data.libraries.load(str(path), link=False) as (available, requested):
            requested.actions = list(available.actions)
    else:
        raise ValueError("Unsupported source animation format; use extracted FBX/BVH/glTF/blend: " + str(path))
    result = []
    for action in bpy.data.actions:
        if action.as_pointer() in before:
            continue
        fcurves = list(curves(action))
        count = sum(len(curve.keyframe_points) for curve in fcurves)
        result.append({"name": action.name, "frame_range": vec(action.frame_range),
                       "curve_count": len(fcurves), "key_count": count,
                       "key_values_finite": all(math.isfinite(c) for curve in fcurves for key in curve.keyframe_points for c in key.co),
                       "action_sha256": action_digest(action)})
    return result


def validate_provenance(manifest_path, required_clips, candidate_actions, failures):
    if manifest_path is None:
        if required_clips:
            failures.append("provenance: manifest required for external clips")
        return {"status": "not_requested" if not required_clips else "missing", "sources": []}
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    sources, covered = [], set()
    imported_cache = {}
    for entry in manifest.get("sources", []):
        record = dict(entry)
        issues = []
        for key in ("source_file", "source_sha256", "source_url", "license", "license_url", "author", "target_clips"):
            if not entry.get(key):
                issues.append("missing " + key)
        source = (manifest_path.parent / entry.get("source_file", "")).resolve()
        if not source.is_file():
            issues.append("source file missing")
        else:
            record["actual_source_sha256"] = sha(source)
            if record["actual_source_sha256"] != entry.get("source_sha256", "").lower():
                issues.append("source file hash mismatch")
            try:
                # glTF key coordinates depend on the scene's import frame rate.
                # Match the recorded import settings before comparing action hashes.
                saved_fps = bpy.context.scene.render.fps
                saved_fps_base = bpy.context.scene.render.fps_base
                try:
                    if "source_import_fps" in entry:
                        source_fps = int(entry["source_import_fps"])
                        source_fps_base = float(entry.get("source_import_fps_base", 1.0))
                        if source_fps <= 0 or not math.isfinite(source_fps_base) or source_fps_base <= 0:
                            raise ValueError("invalid source import frame rate")
                        bpy.context.scene.render.fps = source_fps
                        bpy.context.scene.render.fps_base = source_fps_base
                    record["actual_import_fps"] = bpy.context.scene.render.fps
                    record["actual_import_fps_base"] = bpy.context.scene.render.fps_base
                    cache_key = (str(source), record["actual_source_sha256"], record["actual_import_fps"], record["actual_import_fps_base"])
                    record["reused_same_run_source_import"] = cache_key in imported_cache
                    if cache_key not in imported_cache:
                        imported_cache[cache_key] = import_source_animation(source)
                    record["actually_imported_actions"] = imported_cache[cache_key]
                finally:
                    bpy.context.scene.render.fps = saved_fps
                    bpy.context.scene.render.fps_base = saved_fps_base
                loaded = record["actually_imported_actions"]
                if not loaded or not all(a["key_count"] > 0 and a["key_values_finite"] for a in loaded):
                    issues.append("imported source has no finite keyed animation")
                requested = entry.get("source_action")
                def original_name(name):
                    # FBX names include their armature, e.g. Armature.003|Take.
                    # Repeated imports can suffix that component or the action.
                    def without_copy_suffix(component):
                        stem, dot, suffix = component.rpartition(".")
                        return stem if dot and len(suffix) == 3 and suffix.isdigit() else component
                    return "|".join(without_copy_suffix(component) for component in name.split("|"))
                matching = [action for action in loaded if not requested or
                            action["name"] == requested or original_name(action["name"]) == requested]
                if len(matching) != 1:
                    issues.append("source_action does not select exactly one actually imported action")
                else:
                    record["selected_imported_action"] = matching[0]
                    expected_source_action = entry.get("source_action_sha256")
                    if expected_source_action and expected_source_action != matching[0]["action_sha256"]:
                        issues.append("imported source action hash mismatch")
            except Exception as exc:
                issues.append("source import failed: " + str(exc))
        for item in entry.get("target_clips", []):
            name = item.get("name") if isinstance(item, dict) else str(item)
            expected = item.get("action_sha256") if isinstance(item, dict) else None
            if name not in candidate_actions:
                issues.append("target action not loaded: " + name)
            elif not expected or candidate_actions[name] != expected:
                issues.append("target action hash missing/mismatch: " + name)
            else:
                covered.add(name)
        record["issues"] = issues
        if issues:
            failures.extend("provenance: " + issue for issue in issues)
        sources.append(record)
    missing = sorted(set(required_clips) - covered)
    if missing:
        failures.append("provenance: uncovered external clips " + ", ".join(missing))
    return {"status": "checked" if not any(r["issues"] for r in sources) and not missing else "failed",
            "sources": sources, "covered_target_clips": sorted(covered),
            "scope": "Local source bytes and actually imported keyed actions, attribution fields, and target action hashes. License text requires human review; source import does not prove retarget quality or causal derivation."}


def run(args, report):
    contract = json.loads(args.contract.read_text(encoding="utf-8-sig")) if args.contract else {}
    failures, warnings = report["failures"], report["warnings"]
    report.update({"source": str(args.source), "source_sha256": sha(args.source),
                   "baseline": str(args.baseline), "baseline_sha256": sha(args.baseline),
                   "contract": str(args.contract) if args.contract else None})
    if contract.get("expected_source_sha256") and report["source_sha256"] != contract["expected_source_sha256"]:
        failures.append("candidate source hash mismatch")
    if contract.get("protected_baseline_sha256") and report["baseline_sha256"] != contract["protected_baseline_sha256"]:
        failures.append("baseline source hash mismatch")
    bpy.ops.wm.open_mainfile(filepath=str(args.baseline))
    baseline = snapshot(args.rig, set(args.allow_mesh_change))
    bpy.ops.wm.open_mainfile(filepath=str(args.source))
    candidate = snapshot(args.rig, set(args.allow_mesh_change))
    allowed_actions = set(args.allow_action_change)
    if not contract.get("preserve_all_baseline_actions", False):
        allowed_actions |= set(args.clips)
    archive_checks = {}
    for original, archived in contract.get("archived_actions", {}).items():
        archive_checks[original] = {"archive": archived,
            "matches_baseline_action": original in baseline["actions"] and
            candidate["actions"].get(archived) == baseline["actions"][original]}
        if not archive_checks[original]["matches_baseline_action"]:
            failures.append("archived original action missing/mismatch: " + original)
    changed_meshes = [name for name, value in baseline["meshes"].items() if candidate["meshes"].get(name) != value]
    changed_actions = [name for name, value in baseline["actions"].items()
                       if name not in allowed_actions and candidate["actions"].get(name) != value]
    preservation = {"protected_mesh_count": len(baseline["meshes"]), "changed_protected_meshes": changed_meshes,
                    "excluded_preview_meshes": baseline["excluded_preview_meshes"],
                    "explicitly_allowed_mesh_changes": args.allow_mesh_change,
                    "new_meshes": sorted(set(candidate["meshes"]) - set(baseline["meshes"])),
                    "all_rest_and_parents_unchanged": baseline["rig"] == candidate["rig"],
                    "baseline_bone_count": len(baseline["rig"]), "candidate_bone_count": len(candidate["rig"]),
                    "baseline_rig_id": baseline["rig_id"], "candidate_rig_id": candidate["rig_id"],
                    "allowed_changed_actions": sorted(allowed_actions), "changed_protected_actions": changed_actions,
                    "archived_original_action_checks": archive_checks,
                    "protected_action_count": len(set(baseline["actions"]) - allowed_actions),
                    "candidate_action_sha256": candidate["actions"], "baseline_mesh_signatures": baseline["meshes"],
                    "candidate_mesh_signatures": candidate["meshes"]}
    report["preservation"] = preservation
    if changed_meshes or changed_actions or not preservation["all_rest_and_parents_unchanged"]:
        failures.append("source geometry/UV/weights/rest/protected action preservation failed")
    if baseline["rig_id"] != candidate["rig_id"] or len(candidate["rig"]) != contract.get("expected_bones", 107):
        failures.append("rig id or expected bone count mismatch")
    rig = bpy.data.objects[args.rig]
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    body_right = Vector(contract.get("body_right_rest", [-1, 0, 0])).normalized()
    anatomy = {side: hand_frame(rig, side, body_right) for side in ("L", "R")}
    report["anatomy_basis"] = {"body_right_rest": vec(body_right), "minimum_measurable_bend_degrees": args.minimum_bend,
                                "minimum_curl_dot_palm": args.minimum_alignment,
                                "straight_joint_policy": "not measurable, never silently counted as anatomical pass"}
    report["loop_matrix_tolerance"] = args.loop_tolerance
    attachment = contract.get("staff_attachment")
    grip_thresholds = contract.get("grip_thresholds", {})
    if not attachment:
        warnings.append("No staff_attachment contract: grip checks not performed")
    hand_mesh = bpy.data.objects.get(contract.get("hand_mesh", "Body_Hands_v7"))
    report["clips"] = {}
    anatomical_side_coverage = {side: 0 for side in ("L", "R")}
    for name in args.clips:
        if name not in bpy.data.actions:
            failures.append("missing clip: " + name)
            continue
        action = bpy.data.actions[name]
        clip_contract = contract.get("clips", {}).get(name, {})
        first, last = (int(round(value)) for value in action.frame_range)
        frames = list(range(first, last + 1))
        clip = {"frame_range": [first, last], "frame_count": len(frames), "frames": [],
                "loop": bool(clip_contract.get("loop", action.get("combat_loop", False))) or name in args.loop_clip,
                "finite_pose_frames": 0, "wrong_direction_joint_samples": 0, "measurable_joint_samples": 0}
        report["clips"][name] = clip
        if clip_contract.get("frames") is not None and clip_contract["frames"] != len(frames):
            failures.append("clip frame count mismatch: " + name)
        keyed = list(curves(action))
        if not keyed or not all(math.isfinite(c) for curve in keyed for key in curve.keyframe_points
                                for c in (*key.co, *key.handle_left, *key.handle_right)):
            failures.append("missing/nonfinite animation keys: " + name)
        endpoints = []
        for frame in frames:
            sample_action(rig, action, frame)
            finite = all(finite_matrix(bone.matrix) and finite_matrix(bone.matrix_basis) for bone in rig.pose.bones)
            if not finite:
                failures.append(f"nonfinite pose: {name}@{frame}")
                continue
            clip["finite_pose_frames"] += 1
            if frame in (first, last):
                endpoints.append({bone.name: bone.matrix.copy() for bone in rig.pose.bones})
            record = {"frame": frame, "hands": {}}
            for side in ("L", "R"):
                measured = anatomy_sample(rig, side, anatomy[side], args.minimum_bend, args.minimum_alignment)
                record["hands"][side] = measured
                clip["measurable_joint_samples"] += measured["measurable_joint_count"]
                anatomical_side_coverage[side] += measured["measurable_joint_count"]
                clip["wrong_direction_joint_samples"] += len(measured["wrong_direction_joints"])
                if measured["hand_matrix_determinant"] <= 0:
                    failures.append(f"reflected hand transform: {name}@{frame}/{side}")
            if attachment:
                grip = grip_sample(rig, attachment, hand_mesh)
                record["staff_grip"] = grip
                secondary = clip_contract.get("secondary_grip", contract.get("secondary_grip"))
                if secondary:
                    support = secondary_grip_sample(rig, secondary, grip)
                    ranges = secondary.get("required_frame_ranges")
                    required = ranges is None or any(a <= frame <= b for a, b in ranges)
                    support["contact_required_at_frame"] = required
                    record["support_hand_grip"] = support
                    if not all(math.isfinite(support[key]) for key in ("finger_cage_center_to_axis_m", "shaft_axial_error_m")):
                        failures.append(f"nonfinite support hand grip: {name}@{frame}")
                    elif required and (support["finger_cage_center_to_axis_m"] > secondary["max_cage_axis_distance_m"] or
                                       support["shaft_axial_error_m"] > secondary["max_axial_error_m"]):
                        failures.append(f"support hand detached from shaft: {name}@{frame}")
                if grip.get("evaluated_hand_vertices_finite") is False:
                    failures.append(f"nonfinite evaluated hand mesh: {name}@{frame}")
                for key, maximum in grip_thresholds.items():
                    if key not in grip or not isinstance(grip[key], (int, float)) or grip[key] > maximum:
                        failures.append(f"grip threshold {key}: {name}@{frame}")
            clip["frames"].append(record)
        if clip["wrong_direction_joint_samples"]:
            failures.append(f"anatomical finger curl wrong direction: {name} ({clip['wrong_direction_joint_samples']} joint samples)")
        if clip["measurable_joint_samples"] == 0:
            warnings.append("No bent joints to test chirality in clip: " + name)
        if any(frame.get("staff_grip", {}).get("nearest_hand_surface_inside_shaft_volume", False)
               for frame in clip["frames"]):
            warnings.append("Measured nearest hand surface enters staff cylinder in clip: " + name +
                            "; anatomy pass is not contact clearance")
        if len(endpoints) == 2:
            difference = max(abs(endpoints[0][bone][i][j] - endpoints[1][bone][i][j])
                             for bone in endpoints[0] for i in range(4) for j in range(4))
            clip["first_last_pose_matrix_max_abs_difference"] = difference
            if clip["loop"] and difference > args.loop_tolerance:
                failures.append("loop endpoint mismatch: " + name)
        elif clip["loop"]:
            failures.append("loop has fewer than two evaluable endpoint frames: " + name)
        print("HAND_CLIP_CHECKED", name, len(frames), flush=True)
    report["anatomical_side_measurable_joint_samples"] = anatomical_side_coverage
    for side, count in anatomical_side_coverage.items():
        if not count:
            failures.append("no measurable curled joints in selected clips for hand: " + side)
    required = set(args.external_clip) | set(contract.get("external_clips", []))
    report["provenance"] = validate_provenance(args.provenance, required, candidate["actions"], failures)
    report["source_file_unchanged"] = sha(args.source) == report["source_sha256"]
    report["baseline_file_unchanged"] = sha(args.baseline) == report["baseline_sha256"]
    if not report["source_file_unchanged"] or not report["baseline_file_unchanged"]:
        failures.append("source file changed during checker run")
    report["grip_thresholds"] = grip_thresholds
    if attachment and not grip_thresholds:
        warnings.append("Grip distances are measured only; no numerical grip acceptance thresholds supplied")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--clips", nargs="+", required=True)
    parser.add_argument("--contract", type=Path)
    parser.add_argument("--provenance", type=Path)
    parser.add_argument("--external-clip", action="append", default=[])
    parser.add_argument("--loop-clip", action="append", default=[])
    parser.add_argument("--allow-action-change", action="append", default=[])
    parser.add_argument("--allow-mesh-change", action="append", default=[])
    parser.add_argument("--rig", default="PlayerRig_v7")
    parser.add_argument("--minimum-bend", type=float, default=3.0)
    parser.add_argument("--minimum-alignment", type=float, default=0.0)
    parser.add_argument("--loop-tolerance", type=float, default=1e-5)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    for name in ("source", "baseline", "output", "contract", "provenance"):
        value = getattr(args, name)
        if value is not None:
            setattr(args, name, value.resolve())
    # Reject unsafe output paths before entering the report-writing error handler.
    if args.output in (args.source, args.baseline, args.contract, args.provenance) or args.output.suffix.lower() != ".json":
        parser.error("Output must be a separate JSON report, never an input file")
    report = {"schema_version": "hand_motion_validation_v13.1", "passed": False,
              "scope": "Integer-frame bone anatomy, source preservation, grip distance proxies and imported-source provenance. Not Godot parity, arbitrary-pose collision or art approval.",
              "failures": [], "warnings": []}
    try:
        if not bpy.app.background:
            raise RuntimeError("Use a separate background Blender process")
        run(args, report)
    except Exception as exc:
        report["failures"].append(str(exc))
        report["exception"] = traceback.format_exc()
    report["passed"] = not report["failures"]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False), encoding="utf-8")
    print("HAND_MOTION_VALIDATION_COMPLETE" if report["passed"] else "HAND_MOTION_VALIDATION_FAILED", str(args.output), flush=True)
    if not report["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
