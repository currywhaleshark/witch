"""Read-only left-hand contact diagnostic against the actual runtime GLBs.

No source or animation changes. Uses strict triangle intersections with 64-bit
indices; cuff/sleeve contacts are reported separately, not silently excluded.
"""
from pathlib import Path
import sys, json, bpy, numpy as np
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from exoskeleton_v4_geometry import read, garment, skin, crosses

REPORT = ROOT / 'reports/drive_attack_v30/left_hand_diagnostic'
REPORT.mkdir(parents=True, exist_ok=True)
SOURCE = ROOT / 'assets/characters/player/3d/source/middle_school_v1/drive_attack_v30'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE / 'drive_attack_v30.blend'), load_ui=False, use_scripts=False)
r = bpy.data.objects['PlayerRig_v7']
r.data.pose_position = 'POSE'
for track in r.animation_data.nla_tracks:
    track.mute = True
contract = json.loads((SOURCE / 'runtime_contract.json').read_text(encoding='utf-8'))
C = np.array([[1, 0, 0, 0], [0, 0, 1, 0], [0, -1, 0, 0], [0, 0, 0, 1]], dtype=float)

def load_parts(relative):
    path = ROOT / 'game/assets/characters/player' / relative
    d, _ = read(path)
    names = [n['name'] for n in d['nodes'] if 'mesh' in n and 'skin' in n
             for _ in d['meshes'][n['mesh']]['primitives']]
    return list(zip(names, garment(path)))

body = load_parts('hand_rebuild_v29/body_standard_v29.glb')
hand = next(p for n, p in body if n == 'Body_Hands_v7')
names, binds, v, j, w, f = hand
# Model-rest X identifies the anatomical left hand before it crosses the torso.
left_faces = f[np.all(v[f, 0] > 0, axis=1)]
assert len(left_faces) > 1000
left_hand = (names, binds, v, j, w, left_faces)
left_used = np.unique(left_faces)
obstacles = {
    'body': [(n, p) for n, p in body if n in ('Body_Torso_v7', 'Body_Pelvis_v7')],
    'civilian': load_parts('model_refinement_v28/outfit_civilian_v28.glb'),
    'transformed': load_parts('transformation_v25/outfit_transformed_v4.glb'),
}
rows = []
clips = ['combat_idle_rh_v20', 'drive_bolt_loop_v30', 'drive_grinder_sweep_v30',
         'drive_chainsaw_cut_loop_v30', 'drive_chainsaw_spin_v30']
for name in clips:
    action = bpy.data.actions[name]
    r.animation_data.action = action
    r.animation_data.action_slot = action.slots[0]
    frames = contract['clips'][name]['frames'] if name in contract['clips'] else 1
    for phase in (np.linspace(0, 1, 9) if frames > 1 else [0.]):
        frame = 1 + phase * (frames - 1)
        bpy.context.scene.frame_set(int(frame), subframe=frame-int(frame))
        bpy.context.view_layer.update()
        pose = {p.name: (C @ np.array(p.matrix)).tolist() for p in r.pose.bones}
        hv, hf = skin([left_hand], pose)
        hand_tree = BVHTree.FromPolygons(hv.tolist(), hf.tolist(), all_triangles=True)
        low, high = hv[left_used].min(axis=0), hv[left_used].max(axis=0)
        hit_by_group = {}
        for group, parts in obstacles.items():
            hits = {}
            for mesh_name, part in parts:
                ov, of = skin([part], pose)
                # Broad phase only; the narrow phase still tests actual triangles.
                tri = ov[of]
                mask = np.all(tri.max(axis=1) >= low, axis=1) & np.all(tri.min(axis=1) <= high, axis=1)
                of = of[mask]
                if not len(of):
                    continue
                tree = BVHTree.FromPolygons(ov.tolist(), of.tolist(), all_triangles=True)
                pairs = np.array(hand_tree.overlap(tree), dtype=np.int64)
                if not len(pairs):
                    continue
                a, b = hv[hf[pairs[:, 0]]], ov[of[pairs[:, 1]]]
                crossing = np.zeros(len(pairs), dtype=bool)
                for k in range(3):
                    crossing |= crosses(a[:, k], a[:, (k+1) % 3], b) | crosses(b[:, k], b[:, (k+1) % 3], a)
                if np.any(crossing):
                    hit_faces = np.unique(pairs[crossing, 0])
                    hit_vertex_ids = np.unique(hf[hit_faces])
                    hits[mesh_name] = {
                        'hand_triangles_crossing': int(len(hit_faces)),
                        'hand_local_vertex_count_in_crossing_faces': int(len(hit_vertex_ids)),
                    }
            if hits:
                hit_by_group[group] = hits
        row = {'clip': name, 'phase': float(phase), 'frame': float(frame), 'contacts': hit_by_group,
               'left_wrist_gltf': pose['DEF-hand.L'][0:3],
               'left_hand_aabb_gltf': [low.tolist(), high.tolist()]}
        rows.append(row)
    print('HAND_DIAGNOSTIC', name, sum(bool(x['contacts']) for x in rows if x['clip'] == name), flush=True)
out = {
    'scope': 'Actual runtime left-hand triangles vs body torso/pelvis and both outfit GLBs, skinned by saved v30 poses. Strict non-coplanar crossings. Sleeve/cuff intersections are included and named. Not a full enclosed-volume or continuous collision certificate.',
    'source_blend': str(SOURCE / 'drive_attack_v30.blend'),
    'left_hand_triangles': int(len(left_faces)), 'samples': len(rows), 'poses': rows,
}
(REPORT / 'contacts.json').write_text(json.dumps(out, indent=2), encoding='utf-8')
print('DRIVE_HAND_DIAGNOSTIC_COMPLETE', len(rows), flush=True)
