"""Actual runtime mesh contact audit shared by blocking and final pose checks."""
from pathlib import Path
import sys, json, gzip, numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from exoskeleton_v4_geometry import read, garment, skin, crosses
C = np.array([[1,0,0,0],[0,0,1,0],[0,-1,0,0],[0,0,0,1]], dtype=float)

def load_parts(relative):
    path = ROOT / 'game/assets/characters/player' / relative
    d, _ = read(path)
    names = [n['name'] for n in d['nodes'] if 'mesh' in n and 'skin' in n
             for _ in d['meshes'][n['mesh']]['primitives']]
    return list(zip(names, garment(path)))

def crossing_faces(av, af, bv, bf):
    used = np.unique(af)
    low, high = av[used].min(axis=0), av[used].max(axis=0)
    tri = bv[bf]
    mask = np.all(tri.max(axis=1) >= low, axis=1) & np.all(tri.min(axis=1) <= high, axis=1)
    bf = bf[mask]
    if not len(bf):
        return np.empty(0, dtype=np.int64)
    ai, af_local = np.unique(af, return_inverse=True)
    bi, bf_local = np.unique(bf, return_inverse=True)
    at = BVHTree.FromPolygons(av[ai].tolist(), af_local.reshape(-1,3).tolist(), all_triangles=True)
    bt = BVHTree.FromPolygons(bv[bi].tolist(), bf_local.reshape(-1,3).tolist(), all_triangles=True)
    pairs = np.array(at.overlap(bt), dtype=np.int64)
    if not len(pairs):
        return np.empty(0, dtype=np.int64)
    a, b = av[af[pairs[:,0]]], bv[bf[pairs[:,1]]]
    hit = np.zeros(len(pairs), dtype=bool)
    for i in range(3):
        hit |= crosses(a[:,i], a[:,(i+1)%3], b) | crosses(b[:,i], b[:,(i+1)%3], a)
    return np.unique(pairs[hit,0])

def inside_votes(tree, point):
    votes = 0
    for direction in ((.873,.367,.323),(-.231,.917,.325),(.312,-.277,.909)):
        direction = Vector(direction).normalized()
        p = Vector(point); hits = 0
        for _ in range(64):
            found, normal, index, distance = tree.ray_cast(p, direction, 5.)
            if found is None:
                break
            hits += 1; p = found + direction * .00001
        votes += hits % 2
    return votes

class Audit:
    def __init__(self):
        body = load_parts('hand_rebuild_v29/body_standard_v29.glb')
        self.hands = next(p for n,p in body if n == 'Body_Hands_v7')
        self.obstacles = {'body': [(n,p) for n,p in body if n in ('Body_Torso_v7','Body_Pelvis_v7')],
                          'civilian': load_parts('model_refinement_v28/outfit_civilian_v28.glb'),
                          'transformed': load_parts('transformation_v25/outfit_transformed_v4.glb')}
        names, binds, v, j, w, f = self.hands
        self.faces = {}; self.distal = {}
        for side, sign in [('L',1),('R',-1)]:
            fs = f[np.all(v[f,0]*sign > 0, axis=1)]
            self.faces[side] = fs
            hand_local = v @ binds[names.index('DEF-hand.'+side)].T
            # Only used to distinguish the old covered wrist/cuff interface.
            # All whole-hand torso intersections remain failures, including wrists.
            self.distal[side] = np.all(hand_local[fs,1] > .030, axis=1)

    def check(self, bones_blender, both=True):
        pose = {n: C @ np.array(m) for n,m in bones_blender.items()}
        hv, _ = skin([self.hands], pose)
        result = {}
        hand_pairs = crossing_faces(hv,self.faces['L'],hv,self.faces['R'])
        if len(hand_pairs):
            result['hand_to_hand']={'left_crossing_faces':int(len(hand_pairs))}
        for group, parts in self.obstacles.items():
            group_result = {}
            for name, part in parts:
                ov, of = skin([part], pose)
                contacts = {}
                for side in (('L','R') if both else ('L',)):
                    ids = crossing_faces(hv,self.faces[side],ov,of)
                    if len(ids):
                        contacts[side] = {'whole_hand_faces':int(len(ids)),
                                          'distal_hand_faces':int(np.count_nonzero(self.distal[side][ids]))}
                    if group == 'body':
                        # Detect a completely contained hand even without surface crossings.
                        points = hv[np.unique(self.faces[side][self.distal[side]])]
                        tree = BVHTree.FromPolygons(ov.tolist(),of.tolist(),all_triangles=True)
                        votes = inside_votes(tree, points.mean(axis=0))
                        if votes >= 2:
                            contacts.setdefault(side, {})['inside_votes'] = votes
                if contacts:
                    group_result[name] = contacts
            if group_result:
                result[group] = group_result
        return result

if __name__ == '__main__':
    folder = ROOT / 'reports/drive_attack_v32'
    path = folder / ('contact_pose_reference.json.gz' if '--final' in sys.argv else 'pose_probe.json')
    if path.suffix == '.gz':
        with gzip.open(path,'rt',encoding='utf-8') as f:rows=json.load(f)
    else:
        rows = json.loads(path.read_text(encoding='utf-8'))
    audit = Audit(); results = []
    for i,row in enumerate(rows):
        result = audit.check(row['bones_blender'])
        results.append({'clip':row['clip'],'phase':row['phase'],'contacts':result})
        if i%25 == 24:
            print('HAND_CONTACT_POSES',i+1,flush=True)
    counts = {}
    for clip in dict.fromkeys(row['clip'] for row in results):
        these = [x for x in results if x['clip']==clip]
        counts[clip] = {'samples':len(these),'body_crossing_or_inside_poses':sum('body' in x['contacts'] for x in these),
                        'hand_to_hand_crossing_poses':sum('hand_to_hand' in x['contacts'] for x in these)}
    out = {'scope':'Whole hands vs actual runtime torso/pelvis and both outfits. Strict triangles and body ray-parity centroid containment probes. Distal means beyond 30mm bone-local wrist; cuff contacts are separately named, never excluded from whole-hand counts. Not swept collision or a watertight-volume certificate.',
           'summary':counts,'poses':results}
    output = folder / ('hand_contact_final.json' if '--final' in sys.argv else 'hand_contact_probe.json')
    output.write_text(json.dumps(out,indent=2),encoding='utf-8')
    print('HAND_CONTACT_COMPLETE',counts,flush=True)
