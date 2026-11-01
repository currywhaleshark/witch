"""Extract original Tripo hands and prepare local shoe/ankle repairs on a copy."""
from pathlib import Path
import bpy, bmesh, math, json, sys, hashlib
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/model_refinement_v28'
DEST=ROOT/'assets/characters/player/3d/source/middle_school_v1/model_refinement_v28'
BASE=OUT/'live_before.blend'
RAW=ROOT/'assets/characters/player/3d/source/middle_school_v1/witch_semilong_middle_school_v1_raw.glb'
sys.path.insert(0,str(ROOT/'tools'))
import validate_hand_motion_v13 as check
assert bpy.app.background
bpy.ops.wm.open_mainfile(filepath=str(BASE),load_ui=False,use_scripts=False)
rig=bpy.data.objects['PlayerRig_v7']
before=check.snapshot(rig.name,set())
(OUT/'protected_baseline.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
rig.data.pose_position='REST'
old=bpy.data.objects['Body_Hands_v7']
old_coords=[v.co.copy() for v in old.data.vertices]
old.data.calc_loop_triangles()
old_tris=[tuple(t.vertices) for t in old.data.loop_triangles]
tree=BVHTree.FromPolygons(old_coords,old_tris,all_triangles=True)
old_weights=[{old.vertex_groups[g.group].name:g.weight for g in v.groups} for v in old.data.vertices]
existing=set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(RAW))
imported=[o for o in bpy.data.objects if o not in existing]
raw=next(o for o in imported if o.type=='MESH')
raw.data.transform(Matrix.Scale(1.735258273,4));raw.matrix_world=Matrix.Identity(4)
report={'base_sha256':check.sha(BASE),'raw_sha256':check.sha(RAW),'hands':{}}

def barycentric(p,a,b,c):
    v0,v1,v2=b-a,c-a,p-a
    aa,ab,bb,pa,pb=v0.dot(v0),v0.dot(v1),v1.dot(v1),v2.dot(v0),v2.dot(v1)
    det=max(aa*bb-ab*ab,1e-20)
    v=(bb*pa-ab*pb)/det;w=(aa*pb-ab*pa)/det
    q=np.maximum([1-v-w,v,w],0);q/=max(q.sum(),1e-10)
    return q

hands=[]
for side,sign in [('L',1),('R',-1)]:
    me=raw.data.copy();ob=bpy.data.objects.new('TripoHand_'+side+'_v28',me);bpy.context.scene.collection.objects.link(ob)
    sw=Vector((sign*.332,-.012,.868));sd=Vector((sign*.56,.06,-.827)).normalized()
    su=Vector((0,1,0));su=(su-sd*su.dot(sd)).normalized();sn=su.cross(sd).normalized()
    b=rig.data.bones['DEF-hand.'+side];tw=b.head_local.copy();td=(b.tail_local-tw).normalized()
    tu=rig.data.bones['DEF-pinky.01.'+side].head_local-rig.data.bones['DEF-index.01.'+side].head_local
    tu=(tu-td*tu.dot(td)).normalized();tn=tu.cross(td).normalized()
    source_frame=Matrix((su,sd,sn)).transposed();target_frame=Matrix((tu,td,tn)).transposed()
    rotate=target_frame@source_frame.inverted()
    bm=bmesh.new();bm.from_mesh(me)
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if sign*v.co.x<.28 or v.co.z>.92],context='VERTS')
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-7,plane_co=sw-sd*.006,plane_no=sd,clear_inner=True,clear_outer=False)
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000025)
    bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.000008)
    bm.to_mesh(me);bm.free();me.update()
    high_tris=sum(len(p.vertices)-2 for p in me.polygons)
    for v in me.vertices:v.co=tw+rotate@(v.co-sw)
    for p in me.polygons:p.use_smooth=True
    bpy.context.view_layer.objects.active=ob;ob.select_set(True)
    dec=ob.modifiers.new('Hand_shape_preserving_reduction','DECIMATE');dec.ratio=min(1,4400/max(high_tris,1));dec.use_collapse_triangulate=True
    with bpy.context.temp_override(object=ob,active_object=ob,selected_objects=[ob],selected_editable_objects=[ob]):bpy.ops.object.modifier_apply(modifier=dec.name)
    distances=[]
    for v in ob.data.vertices:
        hit,normal,tri,dist=tree.find_nearest(v.co)
        distances.append(dist)
        ids=old_tris[tri];weights={}
        for i,mix in zip(ids,barycentric(hit,*[old_coords[k] for k in ids])):
            for name,value in old_weights[i].items():weights[name]=weights.get(name,0)+float(mix)*value
        weights={n:w for n,w in sorted(weights.items(),key=lambda p:p[1],reverse=True)[:4] if w>1e-5}
        total=sum(weights.values())
        for name,value in weights.items():
            group=ob.vertex_groups.get(name) or ob.vertex_groups.new(name=name);group.add([v.index],value/total,'REPLACE')
    arm=ob.modifiers.new('Shared_body_rig','ARMATURE');arm.object=rig;ob.parent=rig
    report['hands'][side]={'raw_selected_triangles':high_tris,'triangles':sum(len(p.vertices)-2 for p in ob.data.polygons),'nearest_transfer_max_m':max(distances),'nearest_transfer_mean_m':sum(distances)/len(distances),'source_wrist':list(sw),'source_direction':list(sd),'source_width':list(su),'target_wrist':list(tw)}
    ob.select_set(False);hands.append(ob)
for ob in imported:bpy.data.objects.remove(ob,do_unlink=True)
old.name='ARCHIVE_Hands_pre_v28';old.hide_set(True);old.hide_render=True
for ob in bpy.context.selected_objects:ob.select_set(False)
for ob in hands:ob.select_set(True)
bpy.context.view_layer.objects.active=hands[0]
with bpy.context.temp_override(object=hands[0],active_object=hands[0],selected_objects=hands,selected_editable_objects=hands):bpy.ops.object.join()
hand=hands[0];hand.name='Body_Hands_v7';hand['source']='Original Tripo high-poly hands, extracted and reoriented onto the unchanged v11 rest; v28 derivative'

shoe=bpy.data.objects['Outfit_Shoes_v7'];sock=bpy.data.objects['Outfit_Socks_v7']
for ob in [shoe,sock,bpy.data.objects['Face_Core_v8']]:
    archive=ob.copy();archive.data=ob.data.copy();archive.name='ARCHIVE_'+ob.name+'_pre_v28';bpy.context.scene.collection.objects.link(archive);archive.hide_set(True);archive.hide_render=True
    ob.data=ob.data.copy()
for v in shoe.data.vertices:
    sign=1 if v.co.x>0 else -1;side='L' if sign>0 else 'R'
    v.co.x+=sign*.021
    for g in list(v.groups):shoe.vertex_groups[g.group].remove([v.index])
    shoe.vertex_groups['DEF-foot.'+side].add([v.index],1,'REPLACE')
for v in sock.data.vertices:
    if v.co.z>.17:continue
    sign=1 if v.co.x>0 else -1;side='L' if sign>0 else 'R'
    z=v.co.z
    if z<.106:
        center=Vector((sign*.108,.004,z));v.co=center+(v.co-center)*.90;v.co.z=.078;v.co.y-=.006
    foot=max(0,min(1,(.17-z)/.045));foot=foot*foot*(3-2*foot)
    for g in list(v.groups):sock.vertex_groups[g.group].remove([v.index])
    if foot>0:sock.vertex_groups['DEF-foot.'+side].add([v.index],foot,'REPLACE')
    if foot<1:sock.vertex_groups['DEF-shin.'+side+'.002'].add([v.index],1-foot,'REPLACE')
shoe.data.update();sock.data.update()
report['shoes']={'lateral_alignment_m':.021,'weights':'rigid ipsilateral foot','socks_bottom_z_before':.105,'socks_bottom_z_after':.078}
# Match authoring preview to the runtime covered regions.
for name in ['Body_Torso_v7','Body_Arms_v7','Body_LowerLegs_v7','Body_Feet_v7']:
    bpy.data.objects[name].hide_set(True);bpy.data.objects[name].hide_render=True
rig.data.pose_position='POSE';bpy.context.scene.frame_set(71)
bpy.ops.wm.save_as_mainfile(filepath=str(DEST/'model_refinement_v28.blend'))
report['source_sha256']=check.sha(DEST/'model_refinement_v28.blend')
(OUT/'initial_build.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('MODEL_REFINEMENT_V28_PREPARED',json.dumps(report),flush=True)
