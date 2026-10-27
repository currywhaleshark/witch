"""Author five in-place staff combat clips on the unchanged 107-bone v11 bind.

Background Blender only. Reads v11; saves a separate v12 authoring candidate.
Reuses v5 continuous swing/twist across the real three-segment limb chains,
v11 two-segment skirt supports and cardigan clearance fitting. No source mesh,
weight, bind or historical action changes. Runtime props are separate.
"""
import bpy,math,json,hashlib,sys,ast,time
import numpy as np
from pathlib import Path
from mathutils import Matrix,Quaternion,Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parent.parent
SOURCE=(ROOT/'assets/characters/player/3d/source/middle_school_v1/source_outfit_v11/source_outfit_v11.blend').resolve()
OUT=(ROOT/'assets/characters/player/3d/source/middle_school_v1/combat_animation_v12').resolve();OUT.mkdir(parents=True,exist_ok=True)
REPORT=(ROOT/'reports/combat_animation_v12/animation_agent').resolve();REPORT.mkdir(parents=True,exist_ok=True)
assert Path(bpy.data.filepath).resolve()==SOURCE
s=bpy.context.scene;r=bpy.data.objects['PlayerRig_v7'];assert len(r.data.bones)==107
def borrow(path,names):
    tree=ast.parse(path.read_text(encoding='utf-8'));nodes=[n for n in tree.body if isinstance(n,(ast.FunctionDef,ast.AsyncFunctionDef)) and n.name in names]
    assert len(nodes)==len(names),(path,names)
    exec(compile(ast.Module(body=nodes,type_ignores=[]),str(path),'exec'),globals())
borrow(ROOT/'tools/close_clothing_run_loop_v11.py',{'array_bytes','mesh_signature','rig_signature','curves','action_digest'})
borrow(ROOT/'tools/bake_skirt_support_v11.py',{'support_pose','collision_adjust'})
borrow(ROOT/'reports/source_outfit_v11/cardigan_audit/build_cardigan_candidate.py',{'deformed_points','evaluated_collision_tree'})
baseline_meshes={o.name:mesh_signature(o) for o in bpy.data.objects if o.type=='MESH'};baseline_rig=rig_signature();baseline_actions={a.name:action_digest(a) for a in bpy.data.actions}
source_sha=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
REST={b.name:b.matrix_local.copy() for b in r.data.bones};INV={n:m.inverted() for n,m in REST.items()}
upper_names=[f'DEF-skirt.{i+1:02}' for i in range(16)];lower_names=[f'DEF-skirt_lower.{i+1:02}' for i in range(16)];support_names=upper_names+lower_names
HELPERS=[f'DEF-cardigan.{i+1:02}' for i in range(8)];new=bpy.data.objects['SourceOutfit_Skirt_v11']
p=np.array([v.co[:] for v in new.data.vertices]);skin=np.zeros((len(p),32))
for v in new.data.vertices:
    for g in v.groups:
        n=new.vertex_groups[g.group].name
        if n in support_names:skin[v.index,support_names.index(n)]=g.weight
def rig_weights(obj):
    w=np.zeros((len(obj.data.vertices),len(r.data.bones)))
    for v in obj.data.vertices:
        for g in v.groups:
            i=r.data.bones.find(obj.vertex_groups[g.group].name)
            if i>=0:w[v.index,i]=g.weight
    return w
cardigan=bpy.data.objects['SourceOutfit_Cardigan_v11'];cw=rig_weights(cardigan);coords=np.array([v.co[:] for v in cardigan.data.vertices]);helper_ids=[r.data.bones.find(n) for n in HELPERS]
colliders=[(bpy.data.objects[n],rig_weights(bpy.data.objects[n])) for n in ['Body_Torso_v7','Body_Pelvis_v7','Body_UpperLegs_v7']]
sample_ids=np.where((cw[:,helper_ids].sum(1)>.12)&(coords[:,2]<1.20))[0];sample_ids=sample_ids[::max(1,len(sample_ids)//900)];A=cw[sample_ids][:,helper_ids]
ring=np.eye(8)*2
for i in range(8):ring[i,(i+1)%8]=-1;ring[i,(i-1)%8]=-1
regularizer=np.eye(8)*.6+ring*.8
for tr in r.animation_data.nla_tracks:tr.mute=True
r.data.pose_position='POSE'
# Preserve the already authored thumb opposition and finger curl fixture.
grip_action=bpy.data.actions['v7_Hand_OpenGrip'];r.animation_data.action=grip_action;r.animation_data.action_slot=grip_action.slots[0];s.frame_set(49);bpy.context.view_layer.update()
GRIP={pb.name:pb.matrix_basis.copy() for pb in r.pose.bones if any(pb.name.startswith('DEF-'+d+'.') for d in ['thumb','index','middle','ring','pinky'])}
r.animation_data.action=None
for pb in r.pose.bones:pb.rotation_mode='QUATERNION';pb.matrix_basis=Matrix.Identity(4)
bpy.context.view_layer.update()
def sm(t):t=max(0,min(1,t));return t*t*(3-2*t)
def blend_stops(t,stops):
    for (a,va),(b,vb) in zip(stops,stops[1:]):
        if a<=t<=b:return np.array(va)*(1-sm((t-a)/(b-a)))+np.array(vb)*sm((t-a)/(b-a))
    return np.array(stops[-1][1])
def qworld(x=0,y=0,z=0):return Quaternion((0,0,1),math.radians(z))@Quaternion((0,1,0),math.radians(y))@Quaternion((1,0,0),math.radians(x))
def aim(rest_name,direction,delta=Quaternion()):
    base=delta@REST[rest_name].to_quaternion();old=base@Vector((0,1,0));return old.rotation_difference(direction.normalized())@base
def solve_ik(a,target,l1,l2,pole):
    delta=target-a;dist=max(1e-6,min(delta.length,l1+l2-.0005));axis=delta.normalized();target=a+axis*dist;x=(l1*l1-l2*l2+dist*dist)/(2*dist);h=math.sqrt(max(0,l1*l1-x*x));side=pole-axis*pole.dot(axis)
    if side.length<1e-5:side=axis.cross(Vector((1,0,0)))
    return a+axis*x+side.normalized()*h,target
CHAIN={}
for side in ('L','R'):
    for first,last in [('upper_arm','forearm'),('forearm','hand'),('thigh','shin'),('shin','foot')]:
        firstn='DEF-'+first+'.'+side;lastn='DEF-'+last+'.'+side;qa=REST[firstn].to_quaternion();rel=qa.inverted()@REST[lastn].to_quaternion();tw=rel.to_swing_twist('Y')[1];entries=[]
        for i,suffix in enumerate(('', '.001','.002')):
            n=firstn+suffix;fraction=i/3;offset=(qa@Quaternion((0,1,0),tw*fraction)).inverted()@REST[n].to_quaternion();entries.append((n,fraction,offset))
        CHAIN[firstn]=(entries,sum(r.data.bones[n].length for n,f,o in entries))
def chain_desired(firstn,a,b,qa,qb,desired,twists):
    relative=qa.inverted()@qb
    if relative.w<0:relative.negate()
    twist=relative.to_swing_twist('Y')[1];previous=twists.get(firstn,twist)
    while twist-previous>math.pi:twist-=math.tau
    while twist-previous<-math.pi:twist+=math.tau
    twists[firstn]=twist
    for n,f,offset in CHAIN[firstn][0]:desired[n]=Matrix.LocRotScale(a.lerp(b,f),qa@Quaternion((0,1,0),twist*f)@offset,Vector((1,1,1)))
def apply_desired(desired):
    for n,m in desired.items():
        pb=r.pose.bones[n];parent=pb.parent
        pb.matrix_basis=INV[n]@REST[parent.name]@desired.get(parent.name,parent.matrix).inverted()@m if parent else INV[n]@m
    bpy.context.view_layer.update()
def hand_orientation(axis):
    x=Vector(axis).normalized();y=Vector((0,-1,-.25));y=(y-x*y.dot(x)).normalized();z=x.cross(y).normalized();return Matrix((x,y,z)).transposed().to_quaternion()@Quaternion((0,1,0),-math.atan2(.4131677,.9106548))
def body_pose(kind,t,twists):
    for pb in r.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    desired={};phase=math.tau*t;bob=-.012;lean=0;yaw=0;chest_yaw=0;pitch=0;recoil=0
    right=np.array([-.255,-.19,1.055]);left=np.array([.275,-.035,.945]);axis=np.array([0,-.10,1.0]);left_guide=0
    if kind=='idle':bob+=.0025*math.sin(phase);lean=1.2*math.sin(phase);right[2]+=.002*math.sin(phase)
    elif kind=='run':bob=-.065+.012*math.cos(2*phase);lean=5;chest_yaw=3*math.sin(phase);right[2]+=.009*math.cos(2*phase);left=np.array([.255,-.08+.09*math.sin(phase),1.015+.018*math.cos(phase)]);axis=np.array([.06*math.sin(phase),-.14,1])
    elif kind=='attack':
        right=blend_stops(t,[(0,right),(.24,[-.34,.025,1.19]),(.5,[-.09,-.33,1.12]),(.66,[.14,-.23,1.00]),(1,right)])
        axis=blend_stops(t,[(0,axis),(.24,[-.35,.20,.92]),(.5,[.58,-.80,.18]),(.66,[.94,-.23,.13]),(1,axis)])
        yaw=float(blend_stops(t,[(0,[0]),(.24,[-6]),(.5,[5]),(.66,[8]),(1,[0])])[0]);chest_yaw=float(blend_stops(t,[(0,[0]),(.24,[-13]),(.5,[10]),(.66,[16]),(1,[0])])[0]);lean=4*math.sin(math.pi*t);left[1]-=.05*math.sin(math.pi*t)
    elif kind=='cast':
        k=float(blend_stops(t,[(0,[0]),(.25,[.4]),(.5,[1]),(.66,[1]),(1,[0])])[0]);right=(1-k)*right+k*np.array([-.18,-.33,1.20]);left=(1-k)*left+k*np.array([.16,-.25,1.19]);axis=(1-k)*axis+k*np.array([0,-.86,.52]);left_guide=k;lean=2*k;chest_yaw=-3*k
    else:
        recoil=float(blend_stops(t,[(0,[0]),(1/3,[1]),(.65,[.35]),(1,[0])])[0]);lean=-8*recoil;right+=np.array([-.025,.075,-.018])*recoil;left+=np.array([.015,.04,.04])*recoil;axis+=np.array([-.10,.15,0])*recoil;bob-=.018*recoil
    rootrot=qworld(x=lean*.25,z=yaw);rootpos=REST['DEF-pelvis'].translation+Vector((0,0,bob));desired['DEF-pelvis']=Matrix.LocRotScale(rootpos,rootrot@REST['DEF-pelvis'].to_quaternion(),Vector((1,1,1)))
    for n,rot in [('DEF-spine',qworld(x=lean*.5,z=chest_yaw*.55)),('DEF-chest',qworld(x=lean*.25,z=chest_yaw*.45)),('DEF-neck',qworld(z=-chest_yaw*.15)),('DEF-head',qworld(z=-chest_yaw*.15)),('DEF-clavicle.L',Quaternion()),('DEF-clavicle.R',Quaternion())]:
        parent=r.data.bones[n].parent.name;base=desired[parent]@INV[parent]@REST[n];desired[n]=Matrix.LocRotScale(base.translation,rot@base.to_quaternion(),Vector((1,1,1)))
    pd=desired['DEF-pelvis']@INV['DEF-pelvis'];cd=desired['DEF-chest']@INV['DEF-chest']
    for sign,side in [(1,'L'),(-1,'R')]:
        # Two-joint IK retains limb lengths and avoids wide diagnostic splits.
        hip=pd@r.data.bones['DEF-thigh.'+side].head_local;ankle=r.data.bones['DEF-foot.'+side].head_local.copy()
        if kind=='run':
            u=(t+(0 if side=='L' else .5))%1
            if u<=.30:ankle.y+=-.37+.74*(u/.30)
            else:
                swing=(u-.30)/.70;ankle.y+=.37-.74*sm(swing);ankle.z+=.12*math.sin(math.pi*swing)
        elif kind=='attack':ankle.y+=(-.045 if side=='L' else .025)*math.sin(math.pi*t)
        knee,ankle=solve_ik(hip,ankle,CHAIN['DEF-thigh.'+side][1],CHAIN['DEF-shin.'+side][1],Vector((0,-1,0)))
        qt=aim('DEF-thigh.'+side,knee-hip,rootrot);qs=aim('DEF-shin.'+side,ankle-knee,rootrot);footq=qworld(x=(6*max(0,math.cos(phase+(0 if side=='L' else math.pi))) if kind=='run' else 0))@REST['DEF-foot.'+side].to_quaternion()
        chain_desired('DEF-thigh.'+side,hip,knee,qt,qs,desired,twists);chain_desired('DEF-shin.'+side,knee,ankle,qs,footq,desired,twists);desired['DEF-foot.'+side]=Matrix.LocRotScale(ankle,footq,Vector((1,1,1)));desired['DEF-toe.'+side]=desired['DEF-foot.'+side]@INV['DEF-foot.'+side]@REST['DEF-toe.'+side]
        clav='DEF-clavicle.'+side;shoulder=desired[clav]@INV[clav]@r.data.bones['DEF-upper_arm.'+side].head_local;target=Vector(right if side=='R' else left);elbow,wrist=solve_ik(shoulder,target,CHAIN['DEF-upper_arm.'+side][1],CHAIN['DEF-forearm.'+side][1],Vector((sign*.15,.4,-1)))
        qa=aim('DEF-upper_arm.'+side,elbow-shoulder,cd.to_quaternion());qf=aim('DEF-forearm.'+side,wrist-elbow,cd.to_quaternion())
        qh=hand_orientation(axis) if side=='R' else aim('DEF-hand.L',Vector((0,-.15-left_guide*.8,-1+left_guide*.8)),cd.to_quaternion())
        chain_desired('DEF-upper_arm.'+side,shoulder,elbow,qa,qf,desired,twists);chain_desired('DEF-forearm.'+side,elbow,wrist,qf,qh,desired,twists);desired['DEF-hand.'+side]=Matrix.LocRotScale(wrist,qh,Vector((1,1,1)))
    apply_desired(desired)
    for n,m in GRIP.items():
        factor=1 if n.endswith('.R') else (.32 if kind=='run' else .12)*(1-left_guide)
        loc,q,sc=m.decompose();r.pose.bones[n].matrix_basis=Matrix.LocRotScale(loc*factor,Quaternion().slerp(q,factor),Vector((1,1,1)))
    bpy.context.view_layer.update()
def base_skirt():
    pelvis=r.pose.bones['DEF-pelvis'];delta=pelvis.matrix@INV['DEF-pelvis'];directions=[]
    for side in ('L','R'):
        d=delta.to_3x3().inverted()@(r.pose.bones['DEF-shin.'+side].head-r.pose.bones['DEF-thigh.'+side].head).normalized();h=Vector((d.x,d.y,0))
        if h.length>.001:directions.append((h.normalized(),math.atan2(h.length,-d.z)))
    for n in upper_names:
        pb=r.pose.bones[n];base=delta@REST[n];radial=Vector((pb.bone.head_local.x,pb.bone.head_local.y+.004,0)).normalized();dr=(pb.bone.tail_local-pb.bone.head_local).normalized();angle=math.atan2(math.hypot(dr.x,dr.y),-dr.z)
        for horizontal,tilt in directions:
            influence=math.exp(-(math.acos(max(-1,min(1,radial.dot(horizontal))))/math.radians(62))**2)
            if tilt>math.radians(12):angle=max(angle,min(math.radians(108),tilt+math.radians(18))*influence)
        direction=delta.to_3x3()@(radial*math.sin(angle)+Vector((0,0,-math.cos(angle))));q=(base.to_quaternion()@Vector((0,1,0))).rotation_difference(direction)@base.to_quaternion();target=Matrix.LocRotScale(base.translation,q,Vector((1,1,1)));pb.matrix_basis=INV[n]@REST['DEF-pelvis']@pelvis.matrix.inverted()@target
    bpy.context.view_layer.update();support_pose(lower_fraction=.8,neighbor=16)
def fit_cardigan():
    dp=r.pose.bones['DEF-pelvis'].matrix@INV['DEF-pelvis'];ds=r.pose.bones['DEF-spine'].matrix@INV['DEF-spine'];tp,rp,sp=dp.decompose();ts,rs,ss=ds.decompose();loose=Matrix.LocRotScale(tp.lerp(ts,.5),rp.slerp(rs,.5),Vector((1,1,1)));bases=[]
    for n in HELPERS:target=loose@REST[n];bases.append(target.copy());r.pose.bones[n].matrix=target
    bpy.context.view_layer.update();base=deformed_points(cardigan,cw,r,INV)[sample_ids];collider=evaluated_collision_tree(colliders,r,INV);offsets=np.zeros((8,3))
    # Use an outward radial envelope instead of the fused source's unreliable
    # nearest-face normals. A high percentile preserves the pleat volume while
    # isolated source slivers cannot pull the coat inward or drive the fit.
    skirt_points=np.array([v.co[:] for v in new.evaluated_get(bpy.context.evaluated_depsgraph_get()).data.vertices]);center=np.array([dp.translation.x,dp.translation.y-.004]);radial=skirt_points[:,:2]-center;radius=np.linalg.norm(radial,axis=1);azimuth=np.arctan2(radial[:,1],radial[:,0]);height_centers=np.arange(.78,1.101,.04)+dp.translation.z;envelope=np.zeros((len(height_centers),32))
    for iz,z in enumerate(height_centers):
        for ia in range(32):
            angle=math.tau*ia/32;mask=(abs(skirt_points[:,2]-z)<.035)&(np.cos(azimuth-angle)>math.cos(math.radians(16)))
            if mask.any():envelope[iz,ia]=np.percentile(radius[mask],90)+.008
    for iteration in range(5):
        q=base+A@offsets;active=[];targets=[]
        for index,xyz in enumerate(q):
            point,normal,_,distance=collider.find_nearest(Vector(xyz));signed=float((Vector(xyz)-point).dot(normal))
            if signed<.008 and distance<.11:active.append(index);targets.append(np.array(normal)*min(.12,.008-signed))
            if xyz[2]<1.075+dp.translation.z:
                radial_xy=xyz[:2]-center;length=np.linalg.norm(radial_xy);ia=int(round(math.atan2(radial_xy[1],radial_xy[0])/math.tau*32))%32;iz=int(np.argmin(abs(height_centers-xyz[2])));clearance=envelope[iz,ia]-length
                if 0<clearance<.14:
                    active.append(index);targets.append(np.r_[radial_xy/max(length,1e-8),0]*clearance)
        if not active:break
        ar=A[active];offsets+=np.linalg.solve(ar.T@ar+regularizer,ar.T@np.array(targets)-regularizer@offsets);lengths=np.linalg.norm(offsets,axis=1);offsets*=np.minimum(1,.12/np.maximum(lengths,1e-12))[:,None]
    for i,n in enumerate(HELPERS):target=bases[i].copy();target.translation+=Vector(offsets[i]);r.pose.bones[n].matrix=target
    bpy.context.view_layer.update()
CLIPS=[('combat_idle_staff','idle',49,True,None),('combat_run_staff','run',25,True,None),('combat_attack_staff','attack',25,False,13),('combat_cast_staff','cast',33,False,17),('combat_hit_react','hit',13,False,5)]
report={'source_sha256':source_sha,'rig_id':r.get('rig_id'),'fps':24,'in_place':True,'clips':{},'continuous_twist':'v5 swing/twist scalar unwrapping distributed over each original three-segment limb; no single-bone twist shortcut','garment_support':'v11 two-segment skirt + regularized clearance and independent cardigan 8-bone fit'}
start_time=time.perf_counter()
for name,kind,count,loop,event in CLIPS:
    assert name not in bpy.data.actions,name
    values=[];twists={};r.animation_data.action=None;feet=[]
    for frame in range(1,count+1):
        s.frame_set(frame);body_pose(kind,(frame-1)/(count-1),twists);feet.append({side:list(r.pose.bones['DEF-foot.'+side].head) for side in ('L','R')});base_skirt();collision_adjust(stride=3,iterations=5);fit_cardigan();values.append({pb.name:pb.matrix_basis.copy() for pb in r.pose.bones})
    if loop or kind in ('attack','cast','hit'):values[-1]={n:m.copy() for n,m in values[0].items()}
    a=bpy.data.actions.new(name);a.use_fake_user=True;r.animation_data.action=a;previous={}
    for frame,data in enumerate(values,1):
        for n,m in data.items():
            pb=r.pose.bones[n];loc,q,scale=m.decompose()
            if n in previous and q.dot(previous[n])<0:q.negate()
            previous[n]=q.copy();pb.location=loc;pb.rotation_quaternion=q;pb.scale=scale
            for channel in ('location','rotation_quaternion','scale'):pb.keyframe_insert(data_path=channel,frame=frame,group=n)
    for curve in curves(a):
        for key in curve.keyframe_points:key.interpolation='LINEAR'
    a['combat_loop']=loop;a['event_frame']=event or 0;a['event_normalized']=(event-1)/(count-1) if event else -1
    track=r.animation_data.nla_tracks.new();track.name=name;strip=track.strips.new(name,1,a);strip.action_slot=a.slots[0];track.mute=True
    report['clips'][name]={'frames':count,'duration_seconds':(count-1)/24,'loop':loop,'event_frame':event,'event_normalized':(event-1)/(count-1) if event else None,'all_107_bones_keyed':True,'first_last_basis_max_difference':float(max(abs(np.array(values[0][n])-np.array(values[-1][n])).max() for n in values[0]))}
    if kind=='run':
        distance=(abs(feet[7]['L'][1]-feet[0]['L'][1])+abs(feet[19]['R'][1]-feet[12]['R'][1]))*.5/(7/24)
        report['clips'][name].update({'authored_cycle_distance_m':distance,'authored_speed_mps':distance,'contact_duty_fraction':.30,'foot_head_samples':feet,'distance_method':'Mean stance foot backward travel over frames1-8(L),13-20(R), divided by elapsed normalized cycle. In-place animation; runtime moves the character.'})
    print('COMBAT_CLIP_BUILT',name,count,'elapsed',round(time.perf_counter()-start_time,1),flush=True)
# A skinned local preview prop shares exactly the runtime attachment contract.
grip_basis=Matrix(((0,-1,0),(.9106548,0,-.4131677),(.4131677,0,.9106548))).transposed().to_4x4();grip=Matrix.Translation(Vector((-.007,.048,-.016)))@grip_basis;vertices=[];faces=[]
def cylinder(y0,y1,radius,segments=12):
    start=len(vertices)
    for y in (y0,y1):
        for i in range(segments):angle=math.tau*i/segments;vertices.append((radius*math.cos(angle),y,radius*math.sin(angle)))
    for i in range(segments):j=(i+1)%segments;faces.append((start+i,start+j,start+segments+j,start+segments+i))
    faces.append(tuple(start+i for i in reversed(range(segments))));faces.append(tuple(start+segments+i for i in range(segments)))
cylinder(-.42,.78,.010);cylinder(-.06,.06,.013);cylinder(.65,.72,.033,10);cylinder(.73,.78,.022,10)
mesh=bpy.data.meshes.new('StaffPreview_v12');mesh.from_pydata([REST['DEF-hand.R']@grip@Vector(v) for v in vertices],[],faces);mesh.update();staff=bpy.data.objects.new('PROP_StaffPreview_v12',mesh);s.collection.objects.link(staff);group=staff.vertex_groups.new(name='DEF-hand.R');group.add(list(range(len(vertices))),1,'REPLACE');mod=staff.modifiers.new('StaffGrip','ARMATURE');mod.object=r
mat=bpy.data.materials.new('StaffPreview_WarmMetal_v12');mat.diffuse_color=(.22,.15,.07,1);mat.use_nodes=True;bsdf=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bsdf.inputs['Base Color'].default_value=(.22,.15,.07,1);bsdf.inputs['Metallic'].default_value=.55;bsdf.inputs['Roughness'].default_value=.38;mesh.materials.append(mat);staff['preview_only']=True
report['staff_attachment']={'bone':'DEF-hand.R','asset_axis':'+Y','offset_bone_local':[-.007,.048,-.016],'basis_columns_bone_local':[[0,-1,0],[.9106548,0,-.4131677],[.4131677,0,.9106548]],'below_grip_m':.42,'above_grip_m':.78,'shaft_radius_m':.01,'preview_object':staff.name,'runtime_prop_separate':True,'grip_fixture_frame':49,'right_finger_curl_fraction':1.0}
report['all_original_mesh_geometry_uv_weights_unchanged']=baseline_meshes=={n:mesh_signature(bpy.data.objects[n]) for n in baseline_meshes};report['all_107_rest_and_parents_unchanged']=baseline_rig==rig_signature();report['all_existing_actions_unchanged']=baseline_actions=={n:action_digest(bpy.data.actions[n]) for n in baseline_actions};report['source_file_unchanged']=hashlib.sha256(SOURCE.read_bytes()).hexdigest()==source_sha
assert all(report[k] for k in ['all_original_mesh_geometry_uv_weights_unchanged','all_107_rest_and_parents_unchanged','all_existing_actions_unchanged','source_file_unchanged'])
scene_camera=s.camera;scene_camera.animation_data_clear();scene_camera.constraints.clear();scene_camera.data.ortho_scale=2.1;s.render.engine='BLENDER_EEVEE';s.render.resolution_x=720;s.render.resolution_y=900;s.render.resolution_percentage=100
for name,kind,count,loop,event in CLIPS:
    a=bpy.data.actions[name];r.animation_data.action=a;r.animation_data.action_slot=a.slots[0];r.data.pose_position='POSE'
    for frame in sorted(set([1,event or (count//4+1),count//2+1])):
        s.frame_set(frame);bpy.context.view_layer.update();scene_camera.location=(2.5,-5,1.7);scene_camera.rotation_euler=(Vector((0,-.10,.93))-scene_camera.location).to_track_quat('-Z','Y').to_euler();s.render.filepath=str(REPORT/(name+f'_{frame:03}.png'));bpy.ops.render.render(write_still=True)
report['elapsed_seconds']=time.perf_counter()-start_time
(REPORT/'animation_build.json').write_text(json.dumps(report,indent=2),encoding='utf-8');(OUT/'combat_animation_contract.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
r.animation_data.action=bpy.data.actions['combat_idle_staff'];r.animation_data.action_slot=r.animation_data.action.slots[0];r.data.pose_position='POSE';s.frame_set(1);bpy.context.view_layer.update();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'combat_animation_v12.blend'))
print('COMBAT_ANIMATIONS_SAVED',str(OUT/'combat_animation_v12.blend'),flush=True)
