"""Stable exact-TRS bake helpers shared by motion derivatives."""
import bpy,json,gzip
from mathutils import Matrix
from automation_rigid_common import dump
I=Matrix.Identity(4)

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
