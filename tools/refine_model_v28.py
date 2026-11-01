"""Fit extracted Tripo anatomy to the existing, immutable hand skeleton."""
from pathlib import Path
import bpy,bmesh,numpy as np,json,sys,math
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/model_refinement_v28'
DEST=ROOT/'assets/characters/player/3d/source/middle_school_v1/model_refinement_v28/model_refinement_v28.blend'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'extracted_hands.blend'),load_ui=False,use_scripts=False)
rig=bpy.data.objects['PlayerRig_v7'];rig.data.pose_position='REST'
ob=bpy.data.objects['Body_Hands_v7'];old=bpy.data.objects['ARCHIVE_Hands_pre_v28']
report={}
def frame(side):
 b=rig.data.bones['DEF-hand.'+side];w=b.head_local.copy();d=(b.tail_local-w).normalized()
 u=rig.data.bones['DEF-pinky.01.'+side].head_local-rig.data.bones['DEF-index.01.'+side].head_local
 u=(u-d*u.dot(d)).normalized();n=u.cross(d).normalized()
 return w,Matrix((u,d,n)).transposed()
# Cuff fabric belongs to the outfit, not the common hand. Remove it and extend
# the exposed skin boundary back through the unchanged wrist, preserving UVs.
bm=bmesh.new();bm.from_mesh(ob.data)
for side,sign in [('L',1),('R',-1)]:
 w,F=frame(side);d=F.col[1]
 verts=[v for v in bm.verts if sign*v.co.x>0]
 edges=[e for e in bm.edges if all(sign*v.co.x>0 for v in e.verts)]
 faces=[f for f in bm.faces if all(sign*v.co.x>0 for v in f.verts)]
 bmesh.ops.bisect_plane(bm,geom=verts+edges+faces,dist=1e-7,plane_co=w+d*.019,plane_no=d,clear_inner=True,clear_outer=False)
bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
bm.to_mesh(ob.data);bm.free();ob.data.update()

for side,sign in [('L',1),('R',-1)]:
 w,F=frame(side);inv=F.transposed()
 ids=[v.index for v in ob.data.vertices if sign*v.co.x>0]
 xyz=np.array([list(inv@(ob.data.vertices[i].co-w)) for i in ids]);lookup={i:k for k,i in enumerate(ids)}
 adj={i:[] for i in ids}
 for e in ob.data.edges:
  a,b=e.vertices
  if a in adj and b in adj:adj[a].append(b);adj[b].append(a)
 unseen={i for i in ids if xyz[lookup[i],1]>.08};branches=[]
 while unseen:
  seed=unseen.pop();todo=[seed];comp=[seed]
  while todo:
   for k in adj[todo.pop()]:
    if k in unseen:unseen.remove(k);todo.append(k);comp.append(k)
  if len(comp)>30:branches.append(comp)
 branches.sort(key=lambda c:np.mean([xyz[lookup[i],0] for i in c]))
 assert len(branches)==4,(side,len(branches))
 # Centerline controls map the relaxed original digits onto the existing rest
 # phalanges. An affine-augmented radial basis warp preserves surface detail.
 src=[];dst=[]
 roots=[(-.024,.061,-.016),(-.002,.065,-.014),(.019,.058,-.003),(.036,.049,.007)]
 for digit,branch,base in zip(['index','middle','ring','pinky'],branches,roots):
  pts=xyz[[lookup[i] for i in branch]];tip_d=float(pts[:,1].max())-.001
  target=[inv@(rig.data.bones[f'DEF-{digit}.0{j}.{side}'].head_local-w) for j in range(1,4)]
  target.append(inv@(rig.data.bones[f'DEF-{digit}.03.{side}'].tail_local-w))
  for k,t in enumerate([0,.46,.77,1]):
   sd=base[1]+(tip_d-base[1])*t
   if k==0:sp=np.array(base)
   else:
    near=pts[np.argsort(abs(pts[:,1]-sd))[:max(8,int(len(pts)*.13))]]
    sp=near.mean(axis=0);sp[1]=sd
   src.append(sp);dst.append(list(target[k]))
 # Thumb is oblique to the other fingers, and must keep its own influence.
 for j,p in enumerate([(-.026,.027,.012),(-.041,.043,.021),(-.050,.059,.027),(-.055,.072,.029)]):
  b=rig.data.bones[f'DEF-thumb.0{min(j+1,3)}.{side}']
  src.append(p);dst.append(list(inv@((b.head_local if j<3 else b.tail_local)-w)))
 # Wrist and metacarpal support prevents global fitting from folding the palm.
 for u,d,n in [(-.020,.019,0),(.020,.019,0),(0,.019,-.011),(0,.019,.011),(0,.036,-.014),(0,.036,.013)]:
  src.append([u,d,n]);dst.append([u*.82,d*.78,n*.85])
 A=np.array(src);B=np.array(dst);scale=.1;X=A/scale;Y=B/scale
 dist=np.linalg.norm(X[:,None,:]-X[None,:,:],axis=2)
 P=np.column_stack([np.ones(len(X)),X]);K=np.block([[dist+np.eye(len(X))*1e-5,P],[P.T,np.zeros((4,4))]])
 coeff=np.linalg.solve(K,np.vstack([Y,np.zeros((4,3))]))
 xp=xyz/scale;features=np.column_stack([np.linalg.norm(xp[:,None,:]-X[None,:,:],axis=2),np.ones(len(xp)),xp])
 fitted=(features@coeff)*scale
 for i,p in zip(ids,fitted):ob.data.vertices[i].co=w+F@Vector(p)
 report[side]={'control_points':len(src),'maximum_fit_residual_m':float(np.max(np.linalg.norm((np.column_stack([dist,np.ones(len(X)),X])@coeff)*scale-B,axis=1))),'source_controls':np.array(src).tolist(),'target_controls':np.array(dst).tolist()}

# Extend the now bare wrist boundary under the sleeve, with smooth skin normals.
bm=bmesh.new();bm.from_mesh(ob.data)
for side,sign in [('L',1),('R',-1)]:
 w,F=frame(side);inv=F.transposed()
 boundary=[e for e in bm.edges if e.is_boundary and all(sign*v.co.x>0 and (inv@(v.co-w)).y<.03 for v in e.verts)]
 for step in range(1,4):
  result=bmesh.ops.extrude_edge_only(bm,edges=boundary,use_normal_flip=False)
  verts=[g for g in result['geom'] if isinstance(g,bmesh.types.BMVert)]
  for v in verts:
   q=inv@(v.co-w);q.y=.015-(.021*step/3)
   # Keep a rounded wrist rather than a cuff-shaped lip.
   angle=math.atan2(q.z/.011,q.x/.018);q.x=.018*math.cos(angle);q.z=.011*math.sin(angle)
   v.co=w+F@q
  boundary=[g for g in result['geom'] if isinstance(g,bmesh.types.BMEdge) and g.is_boundary and all(v in verts for v in g.verts)]
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
bm.to_mesh(ob.data);bm.free();ob.data.update()

# Geometry now agrees with the immutable rig. Surface transfer is restricted
# to the matching side and digit to prevent nearby fingers borrowing weights.
old.data.calc_loop_triangles()
coords=[v.co.copy() for v in old.data.vertices];tris=[tuple(t.vertices) for t in old.data.loop_triangles]
tree=BVHTree.FromPolygons(coords,tris,all_triangles=True)
weights=[{old.vertex_groups[g.group].name:g.weight for g in v.groups} for v in old.data.vertices]
ob.vertex_groups.clear()
for v in ob.data.vertices:
 side='L' if v.co.x>0 else 'R';w,F=frame(side);q=F.transposed()@(v.co-w)
 if q.y<.027:
  t=max(0,min(1,(q.y+.006)/.032));ws={'DEF-hand.'+side:t,'DEF-forearm.'+side+'.002':1-t}
 else:
  hit,normal,tri,dist=tree.find_nearest(v.co);ia,ib,ic=tris[tri]
  a,b,c=coords[ia],coords[ib],coords[ic];v0,v1,v2=b-a,c-a,hit-a
  aa,ab,bb,pa,pb=v0.dot(v0),v0.dot(v1),v1.dot(v1),v2.dot(v0),v2.dot(v1);det=max(aa*bb-ab*ab,1e-20)
  f=(bb*pa-ab*pb)/det;g=(aa*pb-ab*pa)/det;mix=np.maximum([1-f-g,f,g],0);mix/=mix.sum();ws={}
  for i,factor in zip([ia,ib,ic],mix):
   for name,value in weights[i].items():ws[name]=ws.get(name,0)+float(factor)*value
  ws=dict(sorted(ws.items(),key=lambda pair:pair[1],reverse=True)[:4])
 total=sum(ws.values())
 for name,value in ws.items():
  if value>1e-8:(ob.vertex_groups.get(name) or ob.vertex_groups.new(name=name)).add([v.index],value/total,'REPLACE')
for p in ob.data.polygons:p.use_smooth=True
for m in ob.data.materials:
 if m and m.use_nodes:
  for n in m.node_tree.nodes:
   if n.type=='BSDF_PRINCIPLED':n.inputs['Roughness'].default_value=.8;n.inputs['Specular IOR Level'].default_value=.23

# A conservative young-face form pass: smoother cheek/jaw transitions, a softer
# chin and tiny nose/lip relief. Eye and hair contact regions stay unchanged.
face=bpy.data.objects['Face_Core_v8'];orig=[v.co.copy() for v in face.data.vertices]
neighbors=[set() for v in orig]
for e in face.data.edges:
 a,b=e.vertices;neighbors[a].add(b);neighbors[b].add(a)
def gauss(x,c,s):return math.exp(-((x-c)/s)**2)
for v,p in zip(face.data.vertices,orig):
 x,y,z=p;front=max(0,min(1,(-y-.045)/.05));lower=gauss(z,1.437,.042)*front
 if neighbors[v.index]:
  avg=sum((orig[i] for i in neighbors[v.index]),Vector())/len(neighbors[v.index])
  shift=(avg-p)*(.28*lower);shift.z*=.35;v.co+=shift
 # Broad, tiny cheek volume and a less pinched lower face retain middle-school proportions.
 cheek=gauss(abs(x),.056,.030)*gauss(z,1.467,.025)*front
 v.co.y-=.0014*cheek
 chin=gauss(x,0,.035)*gauss(z,1.408,.018)*front
 v.co.z+=.0013*chin;v.co.y-=.0008*chin
 nose=gauss(x,0,.009)*gauss(z,1.474,.009)*front
 v.co.y-=.0013*nose
 lips=gauss(x,0,.013)*gauss(z,1.439,.006)*front
 v.co.y-=.0007*lips
face.data.update()
for m in face.data.materials:
 if m and m.use_nodes:
  for n in m.node_tree.nodes:
   if n.type=='BSDF_PRINCIPLED':n.inputs['Roughness'].default_value=.84;n.inputs['Specular IOR Level'].default_value=.23
report['face']={'max_vertex_delta_m':max((v.co-p).length for v,p in zip(face.data.vertices,orig)),'topology_uv_weights_unchanged':True,'identity':'existing v8 face retained; local form refinement'}
rig.data.pose_position='POSE';bpy.context.scene.frame_set(71)
bpy.ops.wm.save_as_mainfile(filepath=str(DEST))
(OUT/'refinement.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('V28_REFINED',json.dumps({k:v.get('maximum_fit_residual_m',v) for k,v in report.items()}))
