"""Geometric staff/body probes shared by authoring and independent QA.

The full 10mm-radius shaft and a conservative 118mm head sphere are sampled.
Hand meshes are intentional grips and are excluded; core torso/head/hair are
never excluded. Sleeve/cuff probes omit only 45mm around each palm grip.
"""
import bpy,math
from mathutils import Vector
from mathutils.bvhtree import BVHTree
CORE=['Body_Torso_v7','Body_Pelvis_v7','Face_Core_v8','Face_Ears_v7','Hair_Semilong_v7']
CIVILIAN=['SourceOutfit_Cardigan_v11','SourceOutfit_Inner_v11','SourceOutfit_Skirt_v11']
TRANSFORMED=['TF_cape_v4','TF_blouse_v4','TF_sleeve_L_v4','TF_sleeve_R_v4','TF_waist_v4','TF_skirt_v4','TF_tails_v4']

def trees(names):
    dg=bpy.context.evaluated_depsgraph_get();result={}
    for name in names:
        ob=bpy.data.objects.get(name)
        if ob is None:continue
        ev=ob.evaluated_get(dg)
        result[name]=BVHTree.FromPolygons([ev.matrix_world@v.co for v in ev.data.vertices],[p.vertices[:] for p in ev.data.polygons])
    return result

def probe(c,axis,slide,spacing,meshes,step=.008,head=True):
    low,high=-.42+slide,.78+slide
    count=math.ceil((high-low)/step)
    min_clearance=100.;nearest=None;crossings=[];close=[]
    for name,tree in meshes.items():
        hit=tree.ray_cast(c+axis*low,axis,high-low)
        if hit[0] is not None:
            u=low+hit[3]
            if name in CORE or all(abs(u-g)>.045 for g in (0,spacing)):
                crossings.append({'mesh':name,'axial_m':u,'position':list(hit[0])})
        for i in range(count+1):
            u=low+(high-low)*i/count
            if name not in CORE and any(abs(u-g)<.045 for g in (0,spacing)):continue
            pos=c+axis*u;hit=tree.find_nearest(pos)
            if hit[0] is None:continue
            clearance=float(hit[3])-.010
            if clearance<min_clearance:min_clearance=clearance;nearest={'mesh':name,'axial_m':u,'position':list(pos),'surface':list(hit[0])}
            if clearance<.003:close.append((name,u,clearance))
        if head:
            pos=c+axis*(.77+slide);hit=tree.find_nearest(pos)
            if hit[0] is not None:
                clearance=float(hit[3])-.118
                if clearance<min_clearance:min_clearance=clearance;nearest={'mesh':name,'part':'head_sphere','position':list(pos),'surface':list(hit[0])}
                if clearance<.003:close.append((name,'head',clearance))
    return {'shaft_crossings':crossings,'minimum_probe_clearance_m':min_clearance,'closest':nearest,'near_probe_count':len(close)}

def append_transformed(root,rig):
    path=root/'assets/characters/player/3d/source/transformed_v1/fit_v4/transformed_fit_v4.blend'
    with bpy.data.libraries.load(str(path),link=False) as (a,b):b.objects=[n for n in a.objects if n.startswith('TF_') and n.endswith('_v4')]
    for ob in b.objects:
        bpy.context.scene.collection.objects.link(ob);ob.parent=rig
        for mod in ob.modifiers:
            if mod.type=='ARMATURE':mod.object=rig
    return b.objects
