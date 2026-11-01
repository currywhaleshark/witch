"""Smooth the existing shoe opening, validate and export the v28 derivative."""
from pathlib import Path
import bpy,bmesh,sys,json,struct
from mathutils import Vector
from mathutils.kdtree import KDTree
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/model_refinement_v28'
SOURCE=ROOT/'assets/characters/player/3d/source/middle_school_v1/model_refinement_v28/model_refinement_v28.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE),load_ui=False,use_scripts=False)
rig=bpy.data.objects['PlayerRig_v7'];rig.data.pose_position='REST'
ob=bpy.data.objects['Outfit_Shoes_v7']
# Smooth only the semantic cut at the ankle opening. Weld is calculation-only:
# original shoe face indexing, atlas coordinates and separate leather pieces stay.
bm=bmesh.new();bm.from_mesh(ob.data)
bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000015);bm.verts.ensure_lookup_table();bm.verts.index_update()
print('shoe weld',len(bm.verts),flush=True)
original={v.index:v.co.copy() for v in bm.verts}
rim={v for e in bm.edges if e.is_boundary for v in e.verts if v.co.z>.087 and -.072<v.co.y<.078} if not ob.get('v28_rim_finished',False) else set()
for iteration in range(7):
 moved={}
 for v in rim:
  near=[e.other_vert(v) for e in v.link_edges if e.is_boundary and e.other_vert(v) in rim]
  if len(near)==2:moved[v]=v.co.lerp((near[0].co+near[1].co)*.5,.62)
 for v,p in moved.items():v.co=p
tree=KDTree(len(bm.verts))
for v in bm.verts:tree.insert(original[v.index],v.index)
tree.balance();deltas=[]
for v in ob.data.vertices:
 p,i,dist=tree.find(v.co)
 if bm.verts[i] in rim and dist<.00003:
  delta=bm.verts[i].co-original[i];v.co+=delta;deltas.append(delta.length)
bm.free();ob.data.update()
ob['v28_rim_finished']=True
print('rim smoothed',len(deltas),flush=True)
# Remove micrometer-scale collapsed triangles from the extracted hand's cut.
hand=bpy.data.objects['Body_Hands_v7'];bm=bmesh.new();bm.from_mesh(hand.data)
bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.000015)
bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(hand.data);bm.free();hand.data.update()
if not hand.get('v28_wrist_coverage',False):
 for v in hand.data.vertices:
  side='L' if v.co.x>0 else 'R';bone=rig.data.bones['DEF-hand.'+side]
  axis=(bone.tail_local-bone.head_local).normalized();distance=(v.co-bone.head_local).dot(axis)
  if distance<.015:v.co-=axis*.014*max(0,min(1,(.015-distance)/.021))
 hand['v28_wrist_coverage']=True;hand.data.update()
# New wrist strips need their own valid UVs; their neutral skin material avoids
# stretching the sleeve color that was attached to the original source wrist.
import math
if not hand.get('v28_hand_atlas_baked',False):
 wrist=bpy.data.materials.get('WristSkin_v28') or bpy.data.materials['PlayerSkin_v7'].copy();wrist.name='WristSkin_v28'
 if wrist.name not in [m.name for m in hand.data.materials]:hand.data.materials.append(wrist)
 wrist_index=list(hand.data.materials).index(wrist)
uv=hand.data.uv_layers.active.data
for p in hand.data.polygons:
 coords=[uv[i].uv.copy() for i in p.loop_indices]
 area=abs(sum(coords[i].x*coords[(i+1)%len(coords)].y-coords[(i+1)%len(coords)].x*coords[i].y for i in range(len(coords))))*.5
 if area<1e-10:
  assert not hand.get('v28_hand_atlas_baked',False),'Rebake the hand atlas after fixing degenerate UVs'
  p.material_index=wrist_index
  normal=p.normal;drop=max(range(3),key=lambda a:abs(normal[a]));axes=[a for a in range(3) if a!=drop]
  for i in p.loop_indices:
   q=hand.data.vertices[hand.data.loops[i].vertex_index].co
   uv[i].uv=(q[axes[0]]*.5+.5,q[axes[1]]*.5+.25)
sock=bpy.data.objects['Outfit_Socks_v7']
if not sock.data.uv_layers:
 layer=sock.data.uv_layers.new(name='SockCylinder_v28')
 for p in sock.data.polygons:
  values=[]
  for i in p.loop_indices:
   q=sock.data.vertices[sock.data.loops[i].vertex_index].co;sign=1 if q.x>0 else -1
   values.append([i,(math.atan2(q.y-.004,q.x-sign*.108)/(2*math.pi))%1,q.z*1.8])
  wrap=max(v[1] for v in values)-min(v[1] for v in values)>.5
  for i,u,v in values:layer.data[i].uv=(u+.5 if not wrap else ((u+.5)%1),v)
template=bpy.data.objects['TEMPLATE_CompleteCoveredBody_v8'];template.hide_set(True);template.hide_render=True
rig.data.pose_position='POSE';bpy.context.scene.frame_set(71)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
sys.path.insert(0,str(ROOT/'tools'))
import validate_hand_motion_v13 as check
before=json.loads((OUT/'protected_baseline.json').read_text(encoding='utf-8'))
after=check.snapshot(rig.name,set())
changed=['Body_Hands_v7','Face_Core_v8','Outfit_Shoes_v7','Outfit_Socks_v7']
protected={n:after['meshes'][n]==v for n,v in before['meshes'].items() if n not in changed}
preserve={'protected_meshes':protected,'rig_unchanged':before['rig']==after['rig'],'actions_unchanged':before['actions']==after['actions'],'shoe_rim_max_delta_m':max(deltas,default=0),'source_sha256':check.sha(SOURCE)}
(OUT/'preservation.json').write_text(json.dumps(preserve,indent=2),encoding='utf-8')
assert all(protected.values()) and preserve['rig_unchanged'] and preserve['actions_unchanged'],preserve
sys.path.insert(0,'C:/Users/yurib/.agents/skills/blender-asset-qa/scripts')
import qa_check
rig.data.pose_position='REST'
qa={name:qa_check.run(objects=[name],profile='game',eps=.00015,no_modifiers=True) for name in changed}
(OUT/'asset_qa_before_adjudication.json').write_text(json.dumps(qa,indent=2),encoding='utf-8')
# Left and right hands/shoes/socks are intentionally separate. Repeat topology
# checks with calculation-only welded UV seams on each side, at the same geometry.
qa_sides={}
for name in ['Body_Hands_v7','Outfit_Shoes_v7','Outfit_Socks_v7']:
 for side,sign in [('L',1),('R',-1)]:
  source=bpy.data.objects[name];copy=source.copy();copy.data=source.data.copy();copy.name=name+'_QA_'+side;bpy.context.scene.collection.objects.link(copy)
  temp=bmesh.new();temp.from_mesh(copy.data);bmesh.ops.delete(temp,geom=[v for v in temp.verts if sign*v.co.x<0],context='VERTS')
  bmesh.ops.remove_doubles(temp,verts=list(temp.verts),dist=.000015);temp.to_mesh(copy.data);temp.free()
  qa_sides[name+'.'+side]=qa_check.run(objects=[copy.name],profile='game',eps=.000015,no_modifiers=True)
  bpy.data.objects.remove(copy,do_unlink=True)
(OUT/'asset_qa_separate_parts.json').write_text(json.dumps(qa_sides,indent=2),encoding='utf-8')
(OUT/'asset_qa.json').write_text(json.dumps(qa,indent=2),encoding='utf-8')
print('QA',json.dumps({n:{'pass':v['pass'],'errors':v['errors'],'warnings':v['warnings']} for n,v in qa.items()}),flush=True)
# Export only replacement components. Accepted v27 auxiliary hair stays external.
import export_source_outfit_v11 as exporter
data=(ROOT/'game/assets/characters/player/run_arm_v21/body_standard_v21.glb').read_bytes();length=struct.unpack_from('<I',data,12)[0];gltf=json.loads(data[20:20+length])
clips=[a['name'] for a in gltf['animations']]
sys.argv=['export','--',str(ROOT/'assets/characters/player/3d/exports/model_refinement_v28'),str(OUT/'export_reference.json'),'--filename-version','v28','--parts','body','eyes','outfit','--extra-garment','SourceOutfit_SkirtLining_v11','--sample-step','12']
for clip in clips:sys.argv+=['--clip',clip]
exporter.main()
print('V28_EXPORTED',clips,flush=True)
