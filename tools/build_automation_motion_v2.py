"""Correct giant mechanisms and retarget the CC0 Quaternius wolf gallop.

Runs in an isolated Blender process. Old sources/exports are immutable inputs.
Mechanical parts retain unit scale and one-bone rigid weights at every key.
"""
import bpy, json, gzip, math, sys, shutil, hashlib, copy
import numpy as np
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from automation_rigid_common import part_points, about, dump
I=Matrix.Identity(4);REPORT=ROOT/'reports/automation_motion_v2'
ACTOR=sys.argv[sys.argv.index('--')+1]
OLD_VERSION=2 if ACTOR=='hound' else 1;VERSION=OLD_VERSION+1
OLD=ROOT/f"assets/actors/automation_batch2/{ACTOR}{'_v' if ACTOR.endswith('_armour') else '_game_v'}{OLD_VERSION}"
BASE=ROOT/f"assets/actors/automation_batch2/{ACTOR}{'_v' if ACTOR.endswith('_armour') else '_game_v'}{VERSION}";BASE.mkdir(parents=True,exist_ok=True)
OUT=REPORT/ACTOR;(OUT/'local').mkdir(parents=True,exist_ok=True)

def smooth(a,b,t):
    u=max(0.,min(1.,(t-a)/(b-a)));return u*u*(3-2*u)

def deform_rows(rig,clips):
    """Read previous saved actions exactly at their authored sample times."""
    rows={}
    for clip,c in clips.items():
        a=bpy.data.actions[clip];rig.animation_data.action=a;rig.animation_data.action_slot=a.slots[0]
        rows[clip]=[]
        for t in c['times']:
            f=1+t*24;bpy.context.scene.frame_set(int(f),subframe=f%1);bpy.context.view_layer.update()
            rows[clip].append({'time':t,'world':{b.name:[list(r) for r in b.matrix] for b in rig.pose.bones}})
    return rows

def write_variant(actor,version,base,out,mesh,rig,contract,records):
    """Bake complete constant TRS tracks, retain source poses for re-export."""
    sc=bpy.context.scene;sc.render.fps=24
    rests={b.name:b.matrix_local.copy() for b in rig.data.bones}
    parents={b.name:b.parent.name if b.parent else None for b in rig.data.bones}
    localrests={n:rests[p].inverted()@r if (p:=parents[n]) else r for n,r in rests.items()}
    if rig.animation_data:
        rig.animation_data.action=None
        for tr in list(rig.animation_data.nla_tracks):rig.animation_data.nla_tracks.remove(tr)
    else:rig.animation_data_create()
    for b in rig.pose.bones:b.rotation_mode='QUATERNION'
    for clip,rows in records.items():
        if clip in bpy.data.actions:bpy.data.actions[clip].name='Previous_'+clip
        a=bpy.data.actions.new(clip);a.use_fake_user=True;rig.animation_data.action=a;last={}
        for row in rows:
            f=1+24*row['time'];world={n:Matrix(m) for n,m in row['world'].items()}
            for n,pb in rig.pose.bones.items():
                p=parents[n];local=world[p].inverted()@world[n] if p else world[n]
                basis=localrests[n].inverted()@local;loc,q,s=basis.decompose()
                assert max(abs(x-1) for x in s)<2e-5,(actor,clip,row['time'],n,list(s))
                if n in last and q.dot(last[n])<0:q.negate()
                last[n]=q.copy();pb.location=loc;pb.rotation_quaternion=q;pb.scale=(1,1,1)
                for prop in ('location','rotation_quaternion','scale'):pb.keyframe_insert(prop,frame=f,group=n)
        for layer in a.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    for fc in cb.fcurves:
                        for k in fc.keyframe_points:k.interpolation='LINEAR'
        a['duration_seconds']=contract['clips'][clip]['seconds'];a['loop']=contract['clips'][clip]['loop']
        track=rig.animation_data.nla_tracks.new();track.name='CLIP_'+clip;track.mute=True
        st=track.strips.new(clip,1,a);st.action_slot=a.slots[0]
        contract['clips'][clip]['times']=[r['time'] for r in rows]
    # Old curves are preserved in the old file, not duplicated into the new one.
    used={st.action for o in sc.objects if o.animation_data for tr in o.animation_data.nla_tracks for st in tr.strips}
    used.update(o.animation_data.action for o in sc.objects if o.animation_data and o.animation_data.action)
    for a in list(bpy.data.actions):
        if a not in used:bpy.data.actions.remove(a)
    rig.animation_data.action=None
    for pb in rig.pose.bones:pb.matrix_basis=I
    sc.frame_set(1);bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig
    bpy.ops.export_scene.gltf(filepath=str(base/f'{actor}_static.glb'),export_format='GLB',use_selection=True,export_animations=False,export_skins=True,export_def_bones=False,export_apply=False,export_extras=True,export_yup=True,export_tangents=True)
    contract['rest_world']={n:[list(r) for r in m] for n,m in rests.items()}
    for n,m in contract['parts_metadata'].items():m['pivot_blender']=list(rests[n].translation)
    for n,m in contract['sockets'].items():m['rest_blender']=list(rests[n].translation)
    dump(base/'rig.json',contract)
    raw=json.dumps(records,separators=(',',':')).encode();(base/'animation_samples.json.gz').write_bytes(gzip.compress(raw,mtime=0))
    dump(out/'local/animation_samples.json',records)
    rig.animation_data.action=bpy.data.actions['idle'];rig.animation_data.action_slot=rig.animation_data.action.slots[0]
    sc.frame_start=1;sc.frame_end=1+round(contract['clips']['idle']['seconds']*24);sc.frame_set(1)
    rig.show_in_front=True
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':area.spaces.active.overlay.show_overlays=True
    bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(base/f'{actor}_game_v{version}.blend'),compress=True)
    (base/'.gitignore').write_text('*.blend1\n*_static.glb\n',encoding='utf8')

if ACTOR.endswith('_armour'):
    base_actor=ACTOR.removesuffix('_armour');base_version=3 if base_actor=='hound' else 2
    base_source=ROOT/f'assets/actors/automation_batch2/{base_actor}_game_v{base_version}'
    bpy.ops.wm.open_mainfile(filepath=str(base_source/f'{base_actor}_game_v{base_version}.blend'),load_ui=False,use_scripts=False)
    sc=bpy.context.scene;base_rig=next(o for o in sc.objects if o.type=='ARMATURE')
    with bpy.data.libraries.load(str(OLD/f'{ACTOR}_game_v1.blend'),link=False) as (src,dst):
        dst.objects=[ACTOR+'_Rigid_Surface']
    mesh=dst.objects[0];sc.collection.objects.link(mesh)
    rig=base_rig.copy();rig.data=base_rig.data.copy();rig.name=ACTOR+'_Rig';sc.collection.objects.link(rig)
    rig.animation_data_clear();rig.animation_data_create();mesh.parent=rig
    for mod in mesh.modifiers:
        if mod.type=='ARMATURE':mod.object=rig
    contract=json.loads((OLD/'rig.json').read_text(encoding='utf8'))
    newcontract=json.loads((base_source/'rig.json').read_text(encoding='utf8'))
    records=json.loads(gzip.decompress((base_source/'animation_samples.json.gz').read_bytes()))
    oldrows=json.loads(gzip.decompress((OLD/'animation_samples.json.gz').read_bytes()))
    records['death']=oldrows['death']
    oldrests={n:Matrix(m) for n,m in contract['rest_world'].items()};newrests={b.name:b.matrix_local.copy() for b in rig.data.bones}
    for row in records['death']:
        for n,m in list(row['world'].items()):row['world'][n]=[list(r) for r in Matrix(m)@oldrests[n].inverted()@newrests[n]]
    for clip,c in newcontract['clips'].items():
        if clip!='death':contract['clips'][clip]=copy.deepcopy(c)
    contract['base_asset']=f'res://assets/actors/automation_batch2/{base_actor}_v{base_version}/{base_actor}_v{base_version}.glb'
    contract['correction_version']=2
    write_variant(ACTOR,2,BASE,OUT,mesh,rig,contract,records)
    dump(BASE/'preservation.json',{'armour_geometry_uv_normals_weights_materials_unchanged':True,'base_source':str(base_source.relative_to(ROOT)),'alive_clips_match_current_base':True,'previous_death_detachment_retained':True,'previous_files_untouched':True})
    print('ARMOUR_MOTION_VARIANT_SAVED',ACTOR,flush=True)
    raise SystemExit(0)

bpy.ops.wm.open_mainfile(filepath=str(OLD/f'{ACTOR}_game_v{OLD_VERSION}.blend'),load_ui=False,use_scripts=False)
sc=bpy.context.scene
if bpy.context.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
mesh=next(o for o in sc.objects if o.type=='MESH' and o.find_armature());rig=mesh.find_armature()
contract=json.loads((OLD/'rig.json').read_text(encoding='utf8'));geo=json.loads((OLD/'geometry.json').read_text(encoding='utf8'))
oldrest={n:Matrix(m) for n,m in contract['rest_world'].items()}
records=deform_rows(rig,contract['clips']);oldrecords=copy.deepcopy(records)
oldverts=np.array([tuple(v.co) for v in mesh.data.vertices]);oldnormals=[n.vector.copy() for n in mesh.data.corner_normals]
oldgroups={v.index:mesh.vertex_groups[v.groups[0].group].name for v in mesh.data.vertices}
rig.animation_data.action=None
for pb in rig.pose.bones:pb.matrix_basis=I
bpy.context.view_layer.update()
points=part_points(mesh)

if ACTOR=='giant':
    # Undo the non-uniform whole-character fitting for the original round gear.
    # The source wheel was near-circular; global character scaling made it oval.
    A=np.diag([-2.46,-3.,2.8/.838]);offset=np.array([.03*2.46,.08*3.,.006])
    gv=np.array(points['gear']);raw=(gv-offset)@np.linalg.inv(A).T
    center=raw.mean(0);vals,axes=np.linalg.eigh(np.cov(raw.T));normal=axes[:,0]
    if normal[1]>0:normal=-normal
    for _ in range(4):
        rel=raw-center;radial=rel-np.outer(rel@normal,normal);rad=np.linalg.norm(radial,axis=1)
        ring=raw[rad>.070];_,axes=np.linalg.eigh(np.cov(ring.T));normal=axes[:,0]
        if normal[1]>0:normal=-normal
        u=np.array([1.,0,0]);u-=normal*(u@normal);u/=np.linalg.norm(u);v=np.cross(normal,u)
        xy=np.column_stack(((raw-center)@u,(raw-center)@v));theta=np.arctan2(xy[:,1],xy[:,0]);env=[]
        for lo in np.linspace(-math.pi,math.pi,65)[:-1]:
            ids=np.where((theta>=lo)&(theta<lo+math.tau/64))[0]
            if len(ids):env.append(xy[ids[np.argmax(np.linalg.norm(xy[ids],axis=1))]])
        e=np.array(env);coef=np.linalg.lstsq(np.column_stack((2*e,np.ones(len(e)))),(e*e).sum(1),rcond=None)[0]
        center+=u*coef[0]+v*coef[1];center+=normal*np.mean((ring-center)@normal)
    nw=np.linalg.inv(A).T@normal;nw/=np.linalg.norm(nw)
    uw=A@u;uw-=nw*(uw@nw);uw/=np.linalg.norm(uw);vw=np.cross(nw,uw)
    T=2.9*np.column_stack((uw,vw,nw))@np.column_stack((u,v,normal)).T@np.linalg.inv(A)
    pivot=A@center+offset
    core_old=np.mean(np.array(points['core']),axis=0);core_new=pivot+nw*.103
    cq=Vector((0,1,0)).rotation_difference(Vector(nw));C=np.array(cq.to_matrix())
    transforms={'gear':(T,pivot-T@pivot),'core':(C,core_new-C@core_old)}
    for vert in mesh.data.vertices:
        n=oldgroups[vert.index]
        if n in transforms:
            tm,tr=transforms[n];vert.co=Vector(tm@np.array(vert.co)+tr)
    normals=[]
    for loop,n in zip(mesh.data.loops,oldnormals):
        group=oldgroups[loop.vertex_index]
        if group in transforms:n=Vector(np.linalg.inv(transforms[group][0]).T@np.array(n)).normalized()
        normals.append(n)
    # This source uses automatic corner normals. Keep that representation:
    # converting to custom normals collapses a few hidden opposing-face fans.
    # Unchanged components therefore retain their exact automatic normals.
    mesh.data.update()
    new_points=part_points(mesh)
    # Key stem centreline from cross-sections below the bow (not the bow PCA).
    faces=np.array([[oldverts[i] for i in f.vertices] for f in mesh.data.polygons if oldgroups[f.vertices[0]]=='key'])
    centres=[]
    for z in np.linspace(2.461,2.490,16):
        pp=[]
        for f in faces:
            for a,b in zip(f,np.roll(f,-1,axis=0)):
                if (a[2]<z)!=(b[2]<z):pp.append(a+(b-a)*(z-a[2])/(b[2]-a[2]))
        pp=np.array(pp);centres.append((pp.min(0)+pp.max(0))/2)
    centres=np.array(centres);fit=np.linalg.lstsq(np.column_stack((centres[:,2],np.ones(len(centres)))),centres[:,:2],rcond=None)[0]
    kp=np.r_[np.array([2.425,1])@fit,2.425];kn=np.r_[fit[0],1.];kn/=np.linalg.norm(kn)
    mechanisms={'gear':{'pivot':pivot.tolist(),'axis':nw.tolist(),'old_axis':[0,1,0],'old_pivot':list(oldrest['gear'].translation),'uniform_source_scale':2.9},'key':{'pivot':kp.tolist(),'axis':kn.tolist(),'old_axis':[0,0,1],'old_pivot':list(oldrest['key'].translation),'stem_fit_rms_m':float(np.sqrt(np.mean((np.column_stack((centres[:,2],np.ones(len(centres))))@fit-centres[:,:2])**2)))}}
    for m in mechanisms.values():m['axis_correction_degrees']=math.degrees(math.acos(np.clip(np.dot(m['axis'],m['old_axis']),-1,1)))
    bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
    for n,p in [('gear',pivot),('key',kp),('core',core_new),('Socket_core',core_new)]:
        b=rig.data.edit_bones[n];delta=Vector(p)-b.head;b.head+=delta;b.tail+=delta
    bpy.ops.object.mode_set(mode='OBJECT');newrest={b.name:b.matrix_local.copy() for b in rig.data.bones}
    changed=['gear','key','core','Socket_core'];death_relative={}
    for clip,rows in records.items():
        for row,oldrow in zip(rows,oldrecords[clip]):
            t=row['time'];duration=contract['clips'][clip]['seconds'];u=t/duration
            for n in changed:
                d=Matrix(oldrow['world'][n])@oldrest[n].inverted()
                if n in mechanisms:
                    m=mechanisms[n];angle=(math.tau*u if clip in ('idle','walk') else .25*math.sin(math.pi*u)) if n=='gear' else (math.tau*u if clip=='idle' else .3*math.sin(math.tau*u))
                    if clip!='death' or t<=.22+1e-8:
                        oldR=about(Vector(m['old_pivot']),Vector(m['old_axis']),angle);newR=about(Vector(m['pivot']),Vector(m['axis']),angle)
                        newd=d@oldR.inverted()@newR
                        if clip=='death':death_relative[n]=d.inverted()@newd
                        d=newd
                    else:d=d@death_relative[n]
                if clip=='death' and t>.22 and n in ('gear','key','core'):
                    ps=new_points[n];lowest=min((d@p).z for p in ps)
                    if lowest<.005:d=Matrix.Translation((0,0,.005-lowest))@d
                row['world'][n]=[list(r) for r in d@newrest[n]]
    contract['mechanisms']=mechanisms;contract['core_fitted_center_blender']=core_new.tolist()
    geo['motion_correction']={'mechanisms':mechanisms,'gear_rest_refit':'uniform source scale restores round wheel; UV/topology/weights retained','core_center':core_new.tolist()}
    dump(BASE/'mechanisms.json',geo['motion_correction'])
    print('MECHANISM_FIT',json.dumps(mechanisms),flush=True)

elif ACTOR=='hound':
    source=json.loads(gzip.decompress((ROOT/'assets/actors/automation_batch2/motion_sources/quaternius/wolf_gallop_samples.json.gz').read_bytes()))
    source_samples=source['samples'];joints={n:[Vector(v) for v in ps] for n,ps in geo['joints'].items()}
    pivots={n:m.translation for n,m in oldrest.items()};reflect=np.diag([1.,-1.,1.])
    source_rest={n:Matrix(b['matrix']) for n,b in source['rest'].items()}
    phases={'fore.L':(0.,.275),'fore.R':(.175,.455),'hind.L':(.50,.70),'hind.R':(.625,.825)}
    stats={'ik_clamps':0,'max_clamp_m':0,'clamp_samples':[],'air_reach_adaptation_max_m':0.,'pistons':{k:{'min':1e9,'max':0} for k in geo['pistons']}}
    def source_at(phase):
        f=(phase%1)*240;i=min(int(f),239);u=f-i
        a,b=source_samples[i]['bones'],source_samples[i+1]['bones'];out={}
        for n in a:
            ma,mb=Matrix(a[n]['matrix']),Matrix(b[n]['matrix'])
            q=ma.to_quaternion().slerp(mb.to_quaternion(),u)
            out[n]={'head':Vector(a[n]['head']).lerp(Vector(b[n]['head']),u),'tail':Vector(a[n]['tail']).lerp(Vector(b[n]['tail']),u),'matrix':Matrix.Translation(ma.translation.lerp(mb.translation,u))@q.to_matrix().to_4x4()}
        return out
    def source_pitch(s,n):
        r=np.array((s[n]['matrix']@source_rest[n].inverted()).to_3x3());r=reflect@r@reflect
        return math.atan2(r[2,1],r[1,1])
    def seg(a,b,aa,bb):
        # A fixed sagittal hinge frame avoids shortest-quaternion roll flips.
        def frame(direction):
            y=direction.normalized();x=Vector((1,0,0));x=(x-y*x.dot(y)).normalized();z=x.cross(y).normalized()
            return Matrix((x,y,z)).transposed()
        r=frame(bb-aa)@frame(b-a).transposed();return Matrix.Translation(aa)@r.to_4x4()@Matrix.Translation(-a)
    def ik(a,c,l1,l2,pole,stem,phase,contact):
        if not contact:
            vector=c-a;length=vector.length;threshold=l1+l2-.045;width=.035
            if length>threshold:
                bounded=threshold+width*math.tanh((length-threshold)/width)
                stats['air_reach_adaptation_max_m']=max(stats['air_reach_adaptation_max_m'],length-bounded)
                c=a+vector*(bounded/length)
        delta=c-a;raw=delta.length;length=min(l1+l2-.0005,max(abs(l1-l2)+.0005,raw));direction=delta.normalized();c=a+direction*length
        if raw>length+1e-5:
            stats['ik_clamps']+=1;stats['max_clamp_m']=max(stats['max_clamp_m'],raw-length)
            stats['clamp_samples'].append({'stem':stem,'phase':phase,'contact':contact,'shortfall':raw-length})
        x=(l1*l1-l2*l2+length*length)/(2*length);h=math.sqrt(max(0,l1*l1-x*x));p=Vector(pole);p=(p-direction*p.dot(direction)).normalized()
        return a+direction*x+p*h,c
    def pose(t):
        # Two anatomical gallops fit the existing half-second/3.25m contract.
        phase=(t*4)%1;s=source_at(phase);wave=math.tau*phase
        pitch=max(-.13,min(.13,source_pitch(s,'Torso3')*.40))
        z=-.108+(s['Torso3']['head'].z-1.75)*.20
        body=Matrix.Translation((0,0,z))@about(pivots['chest'],'X',pitch)
        back=max(-.14,min(.14,(source_pitch(s,'Back')-source_pitch(s,'Torso3'))*.32))
        spine=(pivots['chest']+pivots['pelvis'])*.5
        d={'root':I.copy(),'chest':body,'pelvis':body@about(spine,'X',back)}
        neckangle=max(-.10,min(.10,(source_pitch(s,'Neck1')-pitch)*.35))
        d['neck']=body@about(pivots['neck'],'X',neckangle)
        d['head']=d['neck']@about(pivots['head'],'X',max(-.10,min(.10,(source_pitch(s,'Head')-pitch-neckangle)*.30)))
        d['jaw']=d['head']@about(pivots['jaw'],'X',math.radians(8)+.025*math.sin(wave))
        d['key']=body@about(pivots['key'],'Z',math.tau*t/.25)
        d['tail_01']=d['pelvis']@about(pivots['tail_01'],'X',max(-.16,min(.16,source_pitch(s,'Tail1')*.30)))
        d['tail_02']=d['tail_01']@about(pivots['tail_02'],'X',max(-.18,min(.18,(source_pitch(s,'Tail4')-source_pitch(s,'Tail1'))*.35)))
        for stem,js in joints.items():
            limb,side=stem.split('.');parent='chest' if limb=='fore' else 'pelvis';a=d[parent]@js[0]
            srcfoot=('IKFrontLeg.' if limb=='fore' else 'IKBackLeg.')+side
            srchip=('FrontUpperLeg.' if limb=='fore' else 'BackLeg.')+side
            foot=s[srcfoot]['head'];srcrest=Vector(source['rest'][srchip]['head']);start,end=phases[stem]
            duty=end-start;f=(phase-start)%1;center=.020 if limb=='fore' else -.015
            travel=-(foot.y-srcrest.y)*.27
            # Re-time the planted portion to exact 6.5m/s. Airborne recovery
            # retains the source's asymmetric fold and leading-leg sequence.
            travel_start=-(source_at(start)[srcfoot]['head'].y-srcrest.y)*.27
            travel_end=-(source_at(end)[srcfoot]['head'].y-srcrest.y)*.27
            planted_start=center+1.625*duty/2;planted_end=center-1.625*duty/2
            contact=f<=duty+1e-8
            if contact:travel=planted_start-1.625*f
            else:
                air=(f-duty)/(1-duty);h=.0005
                def derivative(at):return -(source_at(at+h)[srcfoot]['head'].y-source_at(at-h)[srcfoot]['head'].y)*.27/(2*h)
                def y(at):return -(source_at(at)[srcfoot]['head'].y-srcrest.y)*.27
                def hermite(q,y0,y1,v0,v1,span):
                    q2=q*q;q3=q2*q
                    return (2*q3-3*q2+1)*y0+(q3-2*q2+q)*v0*span+(-2*q3+3*q2)*y1+(q3-q2)*v1*span
                width=.18*(1-duty)
                if air<.18:travel=hermite(air/.18,planted_end,y(end+width),-1.625,derivative(end+width),width)
                elif air>.82:travel=hermite((air-.82)/.18,y(start-width),planted_start,derivative(start-width),-1.625,width)
            pawpitch=max(-.95,min(.70,source_pitch(s,srcfoot)))
            if contact:pawpitch=0.
            else:
                air=(f-duty)/(1-duty);pawpitch*=smooth(0,.15,air)*(1-smooth(.82,1,air))
            R=Matrix.Rotation(pawpitch,4,'X');paw=limb+'_paw.'+side
            support=-min((R@(p-js[-1])).z for p in points[paw])+.005
            # Source ankle lift plus an exact planted interval. Recovery is
            # zero-velocity at touchdown; no knee-driven orbit of the feet.
            lift=max(0.,(foot.z-(.205 if limb=='fore' else .16))*.25)
            if contact:lift=0.
            else:
                air=(f-duty)/(1-duty);lift*=smooth(0,.12,air)*(1-smooth(.88,1,air))
            target=Vector((js[-1].x,js[0].y+travel,support+lift))
            if limb=='hind':
                hv=s['BackLowerLeg.'+side]['tail']-s['BackLowerLeg.'+side]['head'];hv=Vector((0,-hv.y,hv.z)).normalized()*(js[3]-js[2]).length
                # Source digitigrade hock swing is retained, with modest limits
                # appropriate to the shorter mechanical lower leg.
                angle=math.atan2(hv.y,-hv.z);angle=max(-.45,min(.80,angle));hv=Vector((0,math.sin(angle),-math.cos(angle)))*hv.length
                b,c=ik(a,target-hv,(js[1]-js[0]).length,(js[2]-js[1]).length,(0,1,0),stem,phase,contact);target=c+hv
                d['hind_hock.'+side]=seg(js[2],js[3],c,target)
            else:b,target=ik(a,target,(js[1]-js[0]).length,(js[2]-js[1]).length,(0,-1,0),stem,phase,contact);c=target
            d[limb+'_upper.'+side]=seg(js[0],js[1],a,b);d[limb+'_lower.'+side]=seg(js[1],js[2],b,c)
            d[paw]=Matrix.Translation(target)@R@Matrix.Translation(-js[-1])
        for stem,p in geo['pistons'].items():
            a0,b0=Vector(p['a']),Vector(p['b']);a=d[p['a_bone']]@a0;b=d[p['b_bone']]@b0
            q=(b0-a0).rotation_difference(b-a).to_matrix().to_4x4()
            d[p['case']]=Matrix.Translation(a)@q@Matrix.Translation(-a0);d[p['rod']]=Matrix.Translation(b)@q@Matrix.Translation(-b0)
            met=stats['pistons'][stem];met['min']=min(met['min'],(b-a).length);met['max']=max(met['max'],(b-a).length)
        for n,parent in [('core','head'),('core_glow','head'),('tail_glow','tail_02'),('Socket_attack','head'),('Socket_core','head'),('Socket_bar','root')]:d[n]=d[parent].copy()
        return d
    times=sorted(set([round(i/240,9) for i in range(121)]+[.5]+[round((c+ph)/4,9) for c in (0,1) for interval in phases.values() for ph in interval]))
    records['run']=[]
    for t in times:
        d=pose(t);records['run'].append({'time':t,'world':{n:[list(r) for r in d[n]@oldrest[n]] for n in oldrest}})
    # Piston stock lengths are measured, not stretched as part of animation.
    fit_before=copy.deepcopy(contract['piston_fits']);fits=[]
    for stem,p in geo['pistons'].items():
        met=stats['pistons'][stem]
        oldfit=next(f for f in fit_before if f['name']==stem)
        lo=min(met['min'],oldfit['minimum_distance']);hi=max(met['max'],oldfit['maximum_distance'])
        # The short rear-right cylinder uses a sub-mm retained overlap. These
        # are baked rigid visual parts, not a pressure-seal/physics simulation.
        rear_clear=.0006 if stem=='hind.R' else .003;overlap=.0008 if stem=='hind.R' else .003
        case=max(oldfit['case_length'],hi-lo+rear_clear+overlap);rod=lo-rear_clear
        fits.append({'name':stem,'minimum_distance':lo,'maximum_distance':hi,'original_case_length':oldfit['case_length'],'original_rod_length':oldfit['rod_length'],'case_length':case,'rod_length':rod,'minimum_overlap':case+rod-hi,'minimum_rod_rear_clearance':lo-rod,'two_stage_possible':case<lo-.0003})
        assert case<lo-.0003,(stem,fits[-1])
        a0,b0=Vector(p['a']),Vector(p['b']);axis=(b0-a0).normalized()
        for name,anchor,old,new in [(p['case'],a0,oldfit['case_length'],case),(p['rod'],b0,oldfit['rod_length'],rod)]:
            for vert in mesh.data.vertices:
                if oldgroups[vert.index]==name:vert.co+=axis*(vert.co-anchor).dot(axis)*(new/old-1)
    normal_matrices={}
    for f in fits:
        p=geo['pistons'][f['name']];axis=np.array((Vector(p['b'])-Vector(p['a'])).normalized())
        for n,old,new in [(p['case'],f['original_case_length'],f['case_length']),(p['rod'],f['original_rod_length'],f['rod_length'])]:
            normal_matrices[n]=np.linalg.inv(np.eye(3)+np.outer(axis,axis)*(new/old-1)).T
    mesh.data.update()
    points=part_points(mesh)
    for row in records['death']:
        for n in points:
            if 'piston' not in n:continue
            d=Matrix(row['world'][n])@oldrest[n].inverted();low=min((d@p).z for p in points[n])
            if low<.005:row['world'][n]=[list(r) for r in Matrix.Translation((0,0,.005-low))@Matrix(row['world'][n])]
    contract['piston_fits']=fits
    contract['motion_source']={'author':'Quaternius','pack':'Ultimate Animated Animal Pack','license':'CC0 1.0','source':'../motion_sources/quaternius/Wolf.blend','action':'Gallop','source_frames':[0,17],'source_fps':30,'cycles_per_clip':2,'anatomical_cycle_seconds':.25,'distance_per_anatomical_cycle_m':1.625,'retarget':'evaluated IK paw trajectories/body/head/tail; fixed-length mechanical limb solve; source leading-leg order and hock articulation; exact constant-speed planted intervals','source_sha256':source['sha256']}
    contract['run_contact_phases']=phases;contract['run_dense_sample_hz']=240
    dump(OUT/'retarget_analysis.json',{'stats':stats,'piston_ranges':fits})
    print('HOUND_RETARGET',json.dumps({'stats':{k:v for k,v in stats.items() if k!='clamp_samples'},'pistons':fits}),flush=True)

else:raise ValueError(ACTOR)

newverts=np.array([tuple(v.co) for v in mesh.data.vertices]);delta=np.linalg.norm(newverts-oldverts,axis=1)
preservation={'previous_source':str(OLD.relative_to(ROOT)), 'changed_vertex_groups':sorted(set(oldgroups[i] for i in np.where(delta>1e-7)[0])),'changed_vertices':int((delta>1e-7).sum()),'maximum_rest_vertex_delta_m':float(delta.max()),'triangles':len(mesh.data.polygons),'uv_topology_weights_materials_preserved':True,'changed_clips':'run; changed piston parts receive death floor support only' if ACTOR=='hound' else 'gear/key mechanical transforms in living clips; changed-part floor support on death','previous_files_untouched':True}
dump(BASE/'preservation.json',preservation);dump(BASE/'geometry.json',geo)
contract['correction_version']=VERSION;contract['prepared_only']=True
write_variant(ACTOR,VERSION,BASE,OUT,mesh,rig,contract,records)
print('MOTION_VARIANT_SAVED',ACTOR,VERSION,flush=True)
