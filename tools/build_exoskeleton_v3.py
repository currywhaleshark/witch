"""Live-MCP semantic separation, body fitting and a rigid auxiliary equipment rig."""
import bpy, math, json
from mathutils import Vector, Matrix

ROOT='C:/Users/yurib/Documents/New project/witch'
SCENE='ExoskeletonV3_Fit'
SOURCE='ExoskeletonV2_WorkingMesh'

def frame(origin, direction, front):
    y=Vector(direction).normalized();z=Vector(front);z=(z-y*z.dot(y)).normalized();x=y.cross(z).normalized()
    m=Matrix((x,y,z)).transposed().to_4x4();m.translation=Vector(origin);return m

def hinge(s,e,w,preferred):
    a=(s-e).normalized();b=(w-e).normalized();n=a.cross(b)
    if n.length<.08:n=Vector(preferred)
    else:n.normalize()
    if n.dot(preferred)<0:n=-n
    return n

def classify(p):
    x,y,z=p;side='L' if x>0 else 'R'
    if z<.365:return ('knee_' if z>.277 else 'shin_')+side
    if z>.785:
        if abs(x)<.095:return 'back_power'
        if abs(x)<.118:return 'back_link_'+side
        return 'shoulder_'+side
    if z>.666:return 'upper_'+side
    if z>.594:return 'elbow_'+side
    if z>.455:return 'forearm_'+side
    return 'wrist_'+side

def fit_v3():
    scene=bpy.data.scenes[SCENE];bpy.context.window.scene=scene
    assert not bpy.data.objects.get('ExoskeletonRig_v3'),'Existing v3 is preserved; use the explicit iteration updater.'
    body=bpy.data.objects['ReferenceBodyRig_v29'];body.data.pose_position='REST'
    raw=bpy.data.objects[SOURCE];me=raw.data;me.calc_loop_triangles()
    rest={b.name:body.matrix_world@b.matrix_local for b in body.data.bones}
    def at(name):return rest[name].translation.copy()
    frames={};fit={};anchors={};config={'arm_offset_shoulder':.145,'arm_offset_elbow':.145,'arm_offset_wrist':.10,
        'back_offset': [0,.265,.065], 'shin_front':.105,'shin_side':.018}
    chest=rest['DEF-chest']
    # Raw front is -Y. The back's display face must point +Y, away from the wearer.
    back_center=at('DEF-chest')+Vector(config['back_offset'])
    back_frame=frame(back_center,(0,0,1),(0,1,0))
    source_back=frame((0,0,.875),(0,0,1),(0,-1,0))
    back_fit=back_frame@Matrix.Diagonal((1.12,1.12,1.12,1))@source_back.inverted()
    for role in ['back_power','back_link_L','back_link_R']:
        frames[role]=back_frame;fit[role]=back_fit
    for side,sign in [('L',1),('R',-1)]:
        s=at('DEF-upper_arm.'+side);e=at('DEF-forearm.'+side);w=at('DEF-hand.'+side)
        n=hinge(s,e,w,Vector((sign,0,0)))
        ss=s+n*config['arm_offset_shoulder'];ee=e+n*config['arm_offset_elbow'];ww=w+n*config['arm_offset_wrist']
        sr=Vector((sign*.133,0,.842));er=Vector((sign*.219,0,.636));wr=Vector((sign*.263,0,.428))
        upper=frame(ss,ee-ss,n);fore=frame(ee,ww-ee,n)
        source_upper=frame(sr,er-sr,(0,-1,0));source_fore=frame(er,wr-er,(0,-1,0))
        upper_fit=upper@Matrix.Diagonal((.95,(ee-ss).length/(er-sr).length,.95,1))@source_upper.inverted()
        fore_fit=fore@Matrix.Diagonal((.95,(ww-ee).length/(wr-er).length,.95,1))@source_fore.inverted()
        for part in ['upper','shoulder']:
            role=part+'_'+side;frames[role]=upper;fit[role]=upper_fit
        # Shoulder hood is on the side; the elbow rotor follows the flexion plane.
        lateral=Vector((sign,0,0));hood=frame(ss,ee-ss,lateral)
        frames['shoulder_'+side]=hood
        fit['shoulder_'+side]=hood@Matrix.Diagonal((.95,(ee-ss).length/(er-sr).length,.95,1))@source_upper.inverted()
        for part in ['elbow','forearm','wrist']:
            role=part+'_'+side;frames[role]=fore;fit[role]=fore_fit
        knee=at('DEF-shin.'+side);ankle=at('DEF-foot.'+side)
        a=knee+Vector((sign*config['shin_side'],-config['shin_front'],0))
        b=ankle+Vector((sign*config['shin_side'],-config['shin_front'],.015))
        source_leg=frame((sign*.106,0,.32),(0,0,-1),(0,-1,0))
        leg=frame(a,b-a,(0,-1,0));leg_fit=leg@Matrix.Diagonal((.92,(b-a).length/.31,.92,1))@source_leg.inverted()
        for part in ['knee','shin']:
            role=part+'_'+side;frames[role]=leg;fit[role]=leg_fit
        anchors[side]={'hinge_rest':list(n),'shoulder':list(ss),'elbow':list(ee),'wrist':list(ww),
            'raw_shoulder':list(sr),'raw_elbow':list(er),'raw_wrist':list(wr),
            'upper_length':(ee-ss).length,'forearm_length':(ww-ee).length}
    groups={role:[] for role in frames}
    for poly in me.polygons:groups[classify(poly.center)].append(poly.index)
    data=bpy.data.armatures.new('ExoskeletonRigData_v3');rig=bpy.data.objects.new('ExoskeletonRig_v3',data)
    scene.collection.objects.link(rig);bpy.context.view_layer.objects.active=rig;rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    root=data.edit_bones.new('EXO-root');root.head=(0,0,0);root.tail=(0,0,.10)
    for role,m in frames.items():
        b=data.edit_bones.new('EXO-'+role);b.head=m.translation;b.tail=m.translation+m.to_3x3().col[1]*.075;b.matrix=m;b.parent=root;b.use_connect=False
    bpy.ops.object.mode_set(mode='OBJECT');rig.show_in_front=True
    parts=[];uv=me.uv_layers.active.data
    for role,faces in groups.items():
        polygons=[me.polygons[i] for i in faces];used=sorted({i for p in polygons for i in p.vertices});indices={v:i for i,v in enumerate(used)}
        m=fit[role];normal_matrix=m.to_3x3().inverted().transposed()
        new=bpy.data.meshes.new('ExoV3_'+role);new.from_pydata([m@me.vertices[i].co for i in used],[],[tuple(indices[i] for i in p.vertices) for p in polygons])
        for mat in me.materials:new.materials.append(mat)
        layer=new.uv_layers.new(name='UVMap');normals=[]
        for src,dst in zip(polygons,new.polygons):
            dst.use_smooth=src.use_smooth;dst.material_index=src.material_index
            for a,b in zip(src.loop_indices,dst.loop_indices):layer.data[b].uv=uv[a].uv;normals.append((normal_matrix@me.corner_normals[a].vector).normalized())
        new.normals_split_custom_set(normals);new.update()
        obj=bpy.data.objects.new('ExoV3_'+role,new);scene.collection.objects.link(obj);obj.parent=rig
        vg=obj.vertex_groups.new(name='EXO-'+role);vg.add(list(range(len(new.vertices))),1,'REPLACE')
        mod=obj.modifiers.new('Rigid equipment skin','ARMATURE');mod.object=rig
        obj['part_role']=role;obj['source_face_count']=len(faces);obj['rigid_bone']='EXO-'+role
        obj['source_polygon_ids']=faces
        parts.append({'name':obj.name,'role':role,'bone':'EXO-'+role,'triangles':len(faces),'fit_matrix':[list(r) for r in m]})
    # Body imports keep their own original data; only this isolated reference scene is hidden by region.
    for obj in scene.objects:
        if obj.type=='MESH' and len(obj.data.polygons)<100 and not obj.name.startswith('ExoV3_'):obj.hide_set(True);obj.hide_render=True
    manifest={'version':'exoskeleton_v3','status':'fitting iteration','parts':parts,'config':config,'anchors':anchors,
        'rig_rest_frames':{n:[list(r) for r in m] for n,m in frames.items()},
        'body_rest_frames':{n:[list(r) for r in m] for n,m in rest.items()},
        'original_source_triangles':len(me.polygons),'triangles':sum(x['triangles'] for x in parts),
        'coordinate_system':'Blender Z-up, character front -Y; Godot export converts to Y-up.'}
    scene['exoskeleton_v3_manifest']=json.dumps(manifest);rig['rig_type']='rigid mechanical follower with shared joint frames'
    bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/assets/equipment/exoskeleton_v3/exoskeleton_v3.blend')
    print('EXO_V3_FIT',len(parts),manifest['triangles'])

fit_v3()
