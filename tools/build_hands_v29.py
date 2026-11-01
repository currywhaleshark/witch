"""Rebuild both player hands from round volumes fitted to the existing finger bones (v29 candidate).

The v28 hands were extracted from the Tripo raw scan: flat 1-4mm fingers that taper to points and a
34x25mm wrist that pinches against a ~50mm forearm. This builds new hands directly on the unchanged
rest skeleton instead: rounded capsules along every finger bone, a padded palm with thenar and
hypothenar volumes, and a wrist that continues the forearm. Metaballs give the smooth unions; the
result is voxel-remeshed and decimated. Weights come from the same bones (forearm.002, hand, 15
finger segments), max four influences. Only `Body_Hands_v7` geometry/material/weights change.

Usage: blender -b -P tools/build_hands_v29.py -- <out_dir> [--save]
Opens the v28 source read-only; with --save writes the derivative to the v29 source folder.
"""
import json, math, sys
from pathlib import Path
import bmesh, bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
V28 = ROOT / "assets/characters/player/3d/source/middle_school_v1/model_refinement_v28/model_refinement_v28.blend"
V29_DIR = ROOT / "assets/characters/player/3d/source/middle_school_v1/hand_rebuild_v29"
args = sys.argv[sys.argv.index("--") + 1:]
out_dir = Path(args[0]); out_dir.mkdir(parents=True, exist_ok=True)
SAVE = "--save" in args

# Target radii (m) per finger segment; anime-leaning but round: ~12mm proximal, ~9mm tip diameter.
RADII = {"thumb": (0.0086, 0.0076, 0.0064), "index": (0.0069, 0.0063, 0.0056), "middle": (0.0071, 0.0065, 0.0057),
         "ring": (0.0067, 0.0061, 0.0054), "pinky": (0.0058, 0.0054, 0.0048)}
FINGERS = ("index", "middle", "ring", "pinky")
WRIST_HALF = (0.0225, 0.0150)  # half width / half thickness at the wrist joint (~47 x 37mm after palm/pad blending)
FOREARM_REACH = 0.045           # how far the skin continues up the forearm under the sleeve (v28: 20mm)
STIFF = 4.0
WEIGHT_SMOOTH_ITERATIONS = 6
THRESHOLD = 0.6
# Surface radius of a stiffness-s metaball element: R * sqrt(1 - (t/s)^(1/3)) for Blender's falloff.
SURF = math.sqrt(1.0 - (THRESHOLD / STIFF) ** (1.0 / 3.0))

bpy.ops.wm.open_mainfile(filepath=str(V28), load_ui=False, use_scripts=False)
rig = bpy.data.objects["PlayerRig_v7"]
rig.data.pose_position = "REST"
bones = rig.data.bones
W = rig.matrix_world


def joint(name, end="head"):
    b = bones[name]
    return W @ (b.head_local if end == "head" else b.tail_local)


def chain(finger, side):
    names = [f"DEF-{finger}.0{i}.{side}" for i in (1, 2, 3)]
    return names, [joint(names[0])] + [joint(n, "tail") for n in names]


def frame_for(side):
    wrist = joint(f"DEF-hand.{side}")
    tip = joint(f"DEF-hand.{side}", "tail")
    axis = (tip - wrist).normalized()
    across = (joint(f"DEF-index.01.{side}") - joint(f"DEF-pinky.01.{side}")).normalized()
    normal = axis.cross(across).normalized()
    across = normal.cross(axis).normalized()
    fa = bones[f"DEF-forearm.{side}.002"]
    forearm_dir = ((W @ fa.tail_local) - (W @ fa.head_local)).normalized()
    return wrist, axis, across, normal, forearm_dir


def add_element(mb, kind, center, radius, axes=None, half=None):
    """Add a metaball element whose *surface* has the requested radius / half extents."""
    el = mb.elements.new()
    el.type = kind
    el.co = center
    el.radius = radius / SURF
    el.stiffness = STIFF
    if axes is not None:
        x, y, z = axes
        from mathutils import Matrix
        el.rotation = Matrix((x, y, z)).transposed().to_quaternion()
    if half is not None:
        if kind == "CAPSULE":
            el.size_x = half[0]
        else:
            el.size_x, el.size_y, el.size_z = [h / el.radius for h in half]
    return el


def capsule(mb, a, b, r):
    d = b - a
    x = d.normalized()
    y = x.orthogonal().normalized()
    z = x.cross(y)
    return add_element(mb, "CAPSULE", (a + b) * 0.5, r, (x, y, z), (d.length * 0.5,))


def ellipsoid(mb, center, axes, half):
    # Ellipsoid elements scale the unit ball by size_*; pick radius = largest half and scale others.
    r = max(half)
    el = add_element(mb, "ELLIPSOID", center, r, axes)
    el.size_x, el.size_y, el.size_z = [h / r for h in half]
    return el


def build_side(side):
    mb = bpy.data.metaballs.new(f"HandSDF_{side}")
    mb.resolution = 0.0011
    mb.render_resolution = 0.0011
    mb.threshold = THRESHOLD
    wrist, axis, across, normal, forearm_dir = frame_for(side)
    mcp = {f: joint(f"DEF-{f}.01.{side}") for f in FINGERS}
    knuckle_mid = sum(mcp.values(), Vector()) / 4
    # Fingers: one capsule per phalanx, tips pulled in so the round end sits at the bone tail.
    for f in FINGERS + ("thumb",):
        names, pts = chain(f, side)
        for i in range(3):
            a, b = pts[i], pts[i + 1]
            if i == 2:
                b = b - (b - a).normalized() * RADII[f][2] * 0.85
            capsule(mb, a, b, RADII[f][i])
    # Metacarpals: four short capsules from the carpal block to each knuckle make the palm's back.
    base = wrist + axis * 0.018
    for f in FINGERS:
        start = base.lerp(mcp[f], 0.15) + across * (mcp[f] - knuckle_mid).dot(across) * 0.55
        capsule(mb, start, mcp[f], RADII[f][0] * 1.25)
    # Palm pad: a flattened ellipsoid filling between the metacarpals.
    palm_len = (knuckle_mid - wrist).length
    centre = wrist.lerp(knuckle_mid, 0.55)
    width = (mcp["index"] - mcp["pinky"]).length
    ellipsoid(mb, centre, (axis, across, normal), (palm_len * 0.44, width * 0.5 + 0.005, 0.0128))
    # Thenar (thumb ball) and hypothenar pads on the palm side.
    t1 = joint(f"DEF-thumb.01.{side}")
    thenar = t1.lerp(wrist.lerp(mcp["index"], 0.45), 0.5) - normal * 0.003
    ellipsoid(mb, thenar, (axis, across, normal), (0.020, 0.012, 0.010))
    hyp = wrist.lerp(mcp["pinky"], 0.5) - normal * 0.002
    ellipsoid(mb, hyp, (axis, across, normal), (0.020, 0.0095, 0.0095))
    # Wrist and forearm continuation: elliptical section that matches the forearm under the sleeve.
    # Densely overlapping slices (4mm apart, 14mm long) so the sleeve-side skin reads as one smooth limb.
    for k in range(13):
        t = k / 12.0
        p = wrist - forearm_dir * FOREARM_REACH * t + axis * 0.004 * (1 - t)
        grow = 1.0 + 0.10 * t  # slightly thicker toward the elbow, never pinched
        ellipsoid(mb, p, (forearm_dir, across, normal), (0.014, WRIST_HALF[0] * grow, WRIST_HALF[1] * grow))
    obj = bpy.data.objects.new(f"HandSDF_{side}", mb)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def meshify(obj, voxel=0.0012, target_tris=3600):
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(obj.evaluated_get(deps))
    tmp = bpy.data.objects.new(obj.name + "_mesh", me)
    bpy.context.scene.collection.objects.link(tmp)
    rem = tmp.modifiers.new("remesh", "REMESH")
    rem.mode = "VOXEL"; rem.voxel_size = voxel; rem.use_smooth_shade = True
    sm = tmp.modifiers.new("smooth", "CORRECTIVE_SMOOTH")
    sm.iterations = 6; sm.smooth_type = "SIMPLE"; sm.use_only_smooth = True
    deps = bpy.context.evaluated_depsgraph_get()
    me2 = bpy.data.meshes.new_from_object(tmp.evaluated_get(deps))
    tri_count = sum(len(p.vertices) - 2 for p in me2.polygons)
    tmp2 = bpy.data.objects.new(obj.name + "_dec", me2)
    bpy.context.scene.collection.objects.link(tmp2)
    dec = tmp2.modifiers.new("dec", "DECIMATE")
    dec.ratio = min(1.0, target_tris / max(1, tri_count)); dec.use_collapse_triangulate = True
    deps = bpy.context.evaluated_depsgraph_get()
    final = bpy.data.meshes.new_from_object(tmp2.evaluated_get(deps))
    for o in (obj, tmp, tmp2):
        bpy.data.objects.remove(o, do_unlink=True)
    return final


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-12)))
    return (p - (a + ab * t)).length, t


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def weights_for(p, side):
    wrist, axis, across, normal, forearm_dir = frame_for(side)
    w = {}
    # Forearm versus hand across the wrist joint.
    along = (p - wrist).dot(axis)
    fore = 1.0 - smoothstep(-0.014, 0.004, along)
    if fore > 0:
        w[f"DEF-forearm.{side}.002"] = fore
    rest = 1.0 - fore
    if rest <= 0:
        return w
    # Nearest finger chain (by polyline distance) among chains the vertex is past the base of.
    best = None
    for f in FINGERS + ("thumb",):
        names, pts = chain(f, side)
        start_dir = (pts[1] - pts[0]).normalized()
        s = (p - pts[0]).dot(start_dir)
        lead = 0.010 if f == "thumb" else 0.004
        if s < -lead:
            continue
        d = min(seg_dist(p, pts[i], pts[i + 1])[0] for i in range(3))
        if best is None or d < best[0]:
            best = (d, f, names, pts, s, lead)
    finger = 0.0
    if best is not None:
        d, f, names, pts, s, lead = best
        finger = smoothstep(-lead, 0.004, s)
        # Split the chain share across its segments with a short blend at each joint.
        lengths = [(pts[i + 1] - pts[i]).length for i in range(3)]
        dists = [seg_dist(p, pts[i], pts[i + 1]) for i in range(3)]
        i = min(range(3), key=lambda k: dists[k][0])
        share = {i: 1.0}
        t = dists[i][1]
        blend = 0.0035 / lengths[i]
        if t < blend and i > 0:
            a = 0.5 + 0.5 * t / blend; share = {i: a, i - 1: 1 - a}
        elif t > 1 - blend and i < 2:
            a = 0.5 + 0.5 * (1 - t) / blend; share = {i: a, i + 1: 1 - a}
        for k, v in share.items():
            w[names[k]] = w.get(names[k], 0) + rest * finger * v
    w[f"DEF-hand.{side}"] = w.get(f"DEF-hand.{side}", 0) + rest * (1 - finger)
    top = sorted(w.items(), key=lambda kv: -kv[1])[:4]
    total = sum(v for _, v in top)
    return {k: v / total for k, v in top if v / total > 0.002}


hand_obj = bpy.data.objects["Body_Hands_v7"]
old_tris = sum(len(p.vertices) - 2 for p in hand_obj.data.polygons)
old_mat = hand_obj.data.materials[0]
# Skin tone: mean of the v28 hand atlas over skin pixels, so the new hands match its look in-engine.
img = next(n.image for n in old_mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image)
px = list(img.pixels)
cols = [px[i:i + 4] for i in range(0, len(px), 4)]
skin = [c for c in cols if c[3] > 0.5 and sum(c[:3]) > 0.9]
mean = [sum(c[k] for c in skin) / len(skin) for k in range(3)]
# Image pixels are sRGB-encoded; the Principled base colour is linear.
mean = [((c + 0.055) / 1.055) ** 2.4 if c > 0.04045 else c / 12.92 for c in mean]

meshes = [meshify(build_side(s)) for s in ("L", "R")]
bm = bmesh.new()
for me in meshes:
    bm.from_mesh(me)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
new_me = bpy.data.meshes.new("PlayerHands_v29")
bm.to_mesh(new_me); bm.free()
for p in new_me.polygons:
    p.use_smooth = True
mat = old_mat.copy(); mat.name = "HandsSkin_v29"
bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
for link in list(bsdf.inputs["Base Color"].links):
    mat.node_tree.links.remove(link)
bsdf.inputs["Base Color"].default_value = (mean[0], mean[1], mean[2], 1.0)
for n in [n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE"]:
    mat.node_tree.nodes.remove(n)
new_me.materials.append(mat)
old_me = hand_obj.data
hand_obj.data = new_me
for g in list(hand_obj.vertex_groups):
    hand_obj.vertex_groups.remove(g)
groups = {}
max_inf = 0
for v in new_me.vertices:
    p = hand_obj.matrix_world @ v.co
    side = "L" if p.x > 0 else "R"
    wv = weights_for(p, side)
    max_inf = max(max_inf, len(wv))
    for name, value in wv.items():
        g = groups.get(name) or hand_obj.vertex_groups.new(name=name)
        groups[name] = g
        g.add([v.index], value, "REPLACE")
# Smooth weights over the surface so neighbouring fingers' webbing and knuckles never switch owner
# abruptly (abrupt switches stretched faces into spikes when the grip curls the fingers).
adj = [[] for _ in new_me.vertices]
for e in new_me.edges:
    a, b = e.vertices
    adj[a].append(b); adj[b].append(a)
table = [{hand_obj.vertex_groups[g.group].name: g.weight for g in v.groups} for v in new_me.vertices]
for _ in range(WEIGHT_SMOOTH_ITERATIONS):
    nxt = []
    for i, own in enumerate(table):
        acc = dict((k, v * 0.5) for k, v in own.items())
        ring = adj[i]
        for j in ring:
            for k, v in table[j].items():
                acc[k] = acc.get(k, 0) + 0.5 * v / len(ring)
        top = sorted(acc.items(), key=lambda kv: -kv[1])[:4]
        total = sum(v for _, v in top)
        nxt.append({k: v / total for k, v in top if v / total > 0.002})
    table = nxt
max_inf = 0
for g in hand_obj.vertex_groups:
    g.remove(list(range(len(new_me.vertices))))
for i, wv in enumerate(table):
    total = sum(wv.values())
    max_inf = max(max_inf, len(wv))
    for name, value in wv.items():
        hand_obj.vertex_groups[name].add([i], value / total, "REPLACE")
hand_obj["v29_rebuilt_hands"] = True
new_tris = sum(len(p.vertices) - 2 for p in new_me.polygons)


# Measurements on the new geometry in rest pose (same method as the v28 diagnosis).
def section(center, n, groups_filter=None, slab=0.0015, radius=0.05):
    pts = [hand_obj.matrix_world @ v.co for v in new_me.vertices]
    pts = [q for q in pts if abs((q - center).dot(n)) < slab and (q - center).length < radius]
    if len(pts) < 4:
        return None
    u = n.orthogonal().normalized(); w2 = n.cross(u)
    us = [(q - center).dot(u) for q in pts]; ws = [(q - center).dot(w2) for q in pts]
    return [round((max(us) - min(us)) * 1000, 1), round((max(ws) - min(ws)) * 1000, 1)]


wrist, axis, across, normal, forearm_dir = frame_for("L")
names, pts = chain("middle", "L")
report = {"tris_old": old_tris, "tris_new": new_tris, "max_influences": max_inf, "skin_rgb": [round(c, 4) for c in mean],
          "wrist_section_mm": section(wrist, axis, radius=0.04), "forearm_minus30mm_section_mm": section(wrist - forearm_dir * 0.03, forearm_dir, radius=0.045),
          "middle_prox_mid_section_mm": section(pts[0].lerp(pts[1], 0.5), (pts[1] - pts[0]).normalized(), radius=0.012),
          "middle_tip_mid_section_mm": section(pts[2].lerp(pts[3], 0.5), (pts[3] - pts[2]).normalized(), radius=0.012),
          "palm_mid_section_mm": section(wrist.lerp(pts[0], 0.5), axis, radius=0.06),
          "groups": sorted(groups)}

# Close-up renders (rest pose and the combat idle grip) for review.
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"; scene.display.shading.color_type = "MATERIAL"
scene.display.shading.show_cavity = True; scene.display.shading.cavity_type = "BOTH"
scene.render.resolution_x = scene.render.resolution_y = 640
scene.render.film_transparent = False
for o in scene.objects:
    if o.type == "MESH" and o.name not in ("Body_Hands_v7", "Body_Arms_v7"):
        o.hide_render = True
cam_data = bpy.data.cameras.new("cam"); cam_data.type = "ORTHO"; cam_data.ortho_scale = 0.22
cam = bpy.data.objects.new("cam", cam_data); scene.collection.objects.link(cam); scene.camera = cam


def shoot(tag, centre, dirs):
    for view, d in dirs:
        cam.location = centre + d * 0.6
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(out_dir / f"{tag}_{view}.png")
        bpy.ops.render.render(write_still=True)


centre = wrist + axis * 0.06
shoot("v29_rest", centre, (("dorsal", normal), ("palmar", -normal), ("side", across)))
idle = bpy.data.actions.get("combat_idle_rh_v20")
if idle is not None:
    rig.data.pose_position = "POSE"
    rig.animation_data_create(); rig.animation_data.action = idle
    scene.frame_set(int(idle.frame_range[0]) + 10)
    bpy.context.view_layer.update()
    for side in ("L", "R"):
        pb = rig.pose.bones[f"DEF-hand.{side}"]
        c = rig.matrix_world @ pb.head + (rig.matrix_world.to_3x3() @ (pb.tail - pb.head)).normalized() * 0.05
        shoot(f"v29_idle_{side}", c, (("front", Vector((0, -1, 0))), ("side", Vector((1 if side == 'L' else -1, 0, 0)))))
    rig.data.pose_position = "REST"; scene.frame_set(1)
(out_dir / "build_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print("V29_HANDS", json.dumps(report))
if SAVE:
    for o in [o for o in scene.objects if o.name == "cam"]:
        bpy.data.objects.remove(o, do_unlink=True)
    for o in scene.objects:
        if o.type == "MESH":
            o.hide_render = False
    V29_DIR.mkdir(parents=True, exist_ok=True)
    old_me.name = "ARCHIVE_Hands_v28_mesh"; old_me.use_fake_user = True
    bpy.ops.wm.save_as_mainfile(filepath=str(V29_DIR / "hand_rebuild_v29.blend"), compress=True)
    print("V29_SAVED", V29_DIR / "hand_rebuild_v29.blend")
