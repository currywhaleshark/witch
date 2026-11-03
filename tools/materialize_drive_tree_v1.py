"""Live-MCP atlas connection and portable GLB export; original scene data stays editable."""
import bpy,math,json
from mathutils import Vector
ROOT='C:/Users/yurib/Documents/New project/witch'
S=ROOT+'/assets/weapons/drive_tree_v1';G=ROOT+'/game/assets/weapons/drive_tree_v1'
KEYS=['navy','brass','steel','silver','black','teal','core','rope']

def final_material(glow=False):
    name='M_DriveV1_Glow' if glow else 'M_DriveV1_Surface'
    mat=bpy.data.materials.get(name)
    if mat:return mat
    mat=bpy.data.materials.new(name);mat.use_nodes=True
    nodes=mat.node_tree.nodes;links=mat.node_tree.links;p=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
    for key in ['color','normal','orm']+(['emission'] if glow else []):
        image=bpy.data.images.load(S+'/textures/drive_'+key+'.png',check_existing=True)
        image.colorspace_settings.name='sRGB' if key in ['color','emission'] else 'Non-Color';image.pack()
        tex=nodes.new('ShaderNodeTexImage');tex.image=image;tex.label=key
        if key=='color':links.new(tex.outputs['Color'],p.inputs['Base Color'])
        elif key=='normal':
            n=nodes.new('ShaderNodeNormalMap');n.uv_map='DriveTrim';links.new(tex.outputs['Color'],n.inputs['Color']);links.new(n.outputs['Normal'],p.inputs['Normal'])
        elif key=='emission':links.new(tex.outputs['Color'],p.inputs['Emission Color']);p.inputs['Emission Strength'].default_value=1
        else:
            n=nodes.new('ShaderNodeSeparateColor');n.mode='RGB';links.new(tex.outputs['Color'],n.inputs['Color']);links.new(n.outputs['Green'],p.inputs['Roughness']);links.new(n.outputs['Blue'],p.inputs['Metallic'])
            group=bpy.data.node_groups.get('glTF Material Output')
            if not group:
                group=bpy.data.node_groups.new('glTF Material Output','ShaderNodeTree');group.interface.new_socket(name='Occlusion',in_out='INPUT',socket_type='NodeSocketFloat')
            a=nodes.new('ShaderNodeGroup');a.node_tree=group;links.new(n.outputs['Red'],a.inputs['Occlusion'])
    return mat

def atlas(o):
    key=o['surface_key'];key='brass' if key=='edge' else key
    idx=KEYS.index(key);me=o.data
    # Each planar chart intentionally samples the same trim tile. No unique bake.
    uv=me.uv_layers.active;uv.name='DriveTrim'
    for face in me.polygons:
        loops=list(face.loop_indices);coords=[me.vertices[me.loops[i].vertex_index].co for i in loops]
        u=(coords[1]-coords[0]).normalized();v=face.normal.cross(u).normalized()
        points=[(c.dot(u),c.dot(v)) for c in coords]
        low=[min(c[i] for c in points) for i in range(2)];high=[max(c[i] for c in points) for i in range(2)]
        for li,p in zip(loops,points):
            a=.055+.89*(p[0]-low[0])/max(1e-9,high[0]-low[0]);b=.055+.89*(p[1]-low[1])/max(1e-9,high[1]-low[1])
            # Blender UV origin is bottom-left; PNG's is top-left.
            uv.data[li].uv=((idx%4+a)/4,1-(idx//4+b)/2)
    me.materials.clear();me.materials.append(final_material(key=='core'))

def export_one(asset):
    scene=bpy.data.scenes['DriveV1_'+asset];bpy.context.window.scene=scene
    obs=[o for o in scene.objects if o.type=='MESH']
    for o in obs:atlas(o)
    info=json.loads(scene['manifest_json']);info['materials']=['M_DriveV1_Surface','M_DriveV1_Glow'];info['texture_set']='drive_tree_v1 shared trim'
    scene['manifest_json']=json.dumps(info)
    for o in scene.objects:o.select_set(True)
    bpy.context.view_layer.objects.active=obs[0]
    originals=[]
    for o in obs:
        me=o.data;me.calc_loop_triangles();tris=list(me.loop_triangles)
        new=bpy.data.meshes.new(o.name+'_Export');new.from_pydata([v.co for v in me.vertices],[],[list(t.vertices) for t in tris]);new.update()
        for m in me.materials:new.materials.append(m)
        uv=new.uv_layers.new(name='DriveTrim');normals=[]
        for i,t in enumerate(tris):
            new.polygons[i].use_smooth=me.polygons[t.polygon_index].use_smooth
            for corner,li in enumerate(t.loops):uv.data[i*3+corner].uv=me.uv_layers.active.data[li].uv;normals.append(me.corner_normals[li].vector)
        new.normals_split_custom_set(normals);originals.append((o,me,new));o.data=new
    try:
        bpy.ops.export_scene.gltf(filepath=G+'/'+asset+'.glb',export_format='GLB',use_selection=True,use_active_scene=True,
            export_animations=False,export_skins=False,export_extras=True,export_tangents=True,export_yup=True,export_cameras=False,export_lights=False)
    finally:
        for o,me,new in originals:o.data=me;bpy.data.meshes.remove(new)
    print('DRIVE_EXPORTED',asset,info['triangles'])

def save():bpy.ops.wm.save_as_mainfile(filepath=S+'/drive_tree_v1.blend')
