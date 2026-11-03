"""Append after build_drive_tree_v1.py in live MCP. Preserve the v1 scenes."""
import bpy, json
from mathutils import Vector
ROOT='C:/Users/yurib/Documents/New project/witch'
V2_IDS=['guillotine','guillotine_saw','guillotine_lock']

def name_key(ob):return ob.name

def summarize_v2(asset):
    scene=bpy.data.scenes['DriveV2_'+asset];bpy.context.window.scene=scene;bpy.context.view_layer.update()
    meshes=sorted([o for o in scene.objects if o.type=='MESH'],key=name_key)
    info={'id':asset,'revision':'drive_tree_v2','parts':[],'sockets':{},'units':'metres','runtime_status':'prepared_asset','triangles':0,'part_count':len(meshes),'up':[0,1,0],'forward':[0,0,-1]}
    points=[]
    for o in meshes:
        o.data.calc_loop_triangles();n=len(o.data.loop_triangles);info['triangles']+=n
        points += [G(o.matrix_world@v.co) for v in o.data.vertices]
        info['parts'].append({'name':o.name,'role':o['part_role'],'group':o['motion_group'],'delay':o['assembly_delay'],'surface':o['surface_key'],'origin':G(o.location),'triangles':n,'attach_bone':''})
    for o in scene.objects:
        if o.type=='EMPTY':info['sockets'][o.name.split('__')[-1]]={'position':G(o.location),'direction':list(o['godot_axis'])}
    lo=[min(p[i] for p in points) for i in range(3)];hi=[max(p[i] for p in points) for i in range(3)]
    info['aabb_godot']={'min':lo,'max':hi};info['dimensions']=[round(b-a,6) for a,b in zip(lo,hi)]
    cutting=next(o for o in meshes if o['part_role']==('descending_saw' if asset=='guillotine_saw' else 'falling_blade'))
    minimum=min((cutting.matrix_world@v.co).z for v in cutting.data.vertices)
    # Saw rotation uses its full radius so a tip cannot penetrate the ground.
    if asset=='guillotine_saw':
        pivot=scene.objects['v2_'+asset+'__Socket_saw_axis'].location
        radius=max(Vector(((cutting.matrix_world@v.co).x-pivot.x,(cutting.matrix_world@v.co).z-pivot.z)).length for v in cutting.data.vertices)
        minimum=pivot.z-radius
    info['mechanism']={'drop_distance':round(minimum-.002,6),'ground_clearance':.002,'blade_slot_z':[-.15,-.05],
       'lock_first':asset=='guillotine_lock','review_timing_only':True}
    info['materials']=sorted({m.name for o in meshes for m in o.data.materials});scene['manifest_json']=json.dumps(info)
    print('V2_MODEL',asset,info['part_count'],info['triangles'],info['mechanism'])

def build_v2():
    for asset in V2_IDS:
        assert bpy.data.scenes.get('DriveV2_'+asset) is None,'Existing v2 is preserved'
        source=bpy.data.scenes['DriveV1_'+asset];scene=bpy.data.scenes.new('DriveV2_'+asset)
        scene['asset_id']='v2_'+asset;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
        scene.world=source.world;scene.render.engine='BLENDER_EEVEE';bpy.context.window.scene=scene
        for ob in source.objects:
            role=ob.get('part_role','')
            if role in ['ground_foundation','anvil']:continue
            clone=ob.copy()
            if ob.data:clone.data=ob.data.copy()
            clone.name='v2_'+ob.name;scene.collection.objects.link(clone)
            if role.startswith(('foot_','foot_trim_')):clone.location.x+=.07 if clone.location.x>0 else -.07
            if clone.get('motion_group','').startswith('clamp_'):clone.location.y-=.13
            if ob.type=='EMPTY' and ob.name.endswith('Socket_impact'):clone.location=V((0,.002,-.1))
        # Open channel all the way through the base; the diagonal edge can reach the floor.
        box('ground_front',(0,.065,-.24),(1.68,.13,.18),'steel',.012,delay=.01)
        box('ground_rear',(0,.065,.14),(1.68,.13,.38),'steel',.012,delay=.01)
        box('anvil_front',(0,.22,-.215),(1.17,.13,.13),'silver',.010,delay=.12)
        box('anvil_rear',(0,.22,.045),(1.17,.13,.19),'silver',.010,delay=.12)
        summarize_v2(asset)

def save_v2():bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/assets/weapons/drive_tree_v2/drive_tree_v2.blend')
