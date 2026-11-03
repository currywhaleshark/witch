"""Live-MCP material pass: call prepare(), bake_channel(...), then finish().

Only v3 copies change. V2 topology, custom normals, pivots and assembly metadata
are preserved; portable PBR textures replace procedural authoring nodes at export.
"""
import bpy
import math
import json
from mathutils import Vector

ROOT = 'C:/Users/yurib/Documents/New project/witch'
SOURCE = ROOT+'/assets/weapons/firearm_material_v3'
GAME = ROOT+'/game/assets/weapons/firearm_material_v3'
IDS = ['matchlock', 'rifle', 'shotgun']
PREFIX = 'FirearmMaterialV3_'

def obj_name(o):
    return o.name

def meshes():
    return sorted([o for o in bpy.data.scenes[PREFIX+'Bake'].objects if o.type=='MESH'],key=obj_name)

def select_all_parts():
    bpy.context.window.scene=bpy.data.scenes[PREFIX+'Bake']
    for o in bpy.context.selected_objects:o.select_set(False)
    obs=meshes()
    for o in obs:o.select_set(True)
    bpy.context.view_layer.objects.active=obs[0]
    return obs

def material(key):
    name='M_FirearmV3_Source_'+key
    old=bpy.data.materials.get(name)
    if old:return old
    mat=bpy.data.materials.new(name);mat.use_nodes=True;mat.use_fake_user=True
    nodes=mat.node_tree.nodes;links=mat.node_tree.links;nodes.clear()
    def node(kind,label):
        n=nodes.new(kind);n.label=label;return n
    def set_input(n,k,v):
        if isinstance(v,bpy.types.NodeSocket):links.new(v,n.inputs[k])
        else:n.inputs[k].default_value=v
    def calc(op,a,b=0):
        n=node('ShaderNodeMath',op);n.operation=op
        set_input(n,0,a);set_input(n,1,b);return n.outputs[0]
    def mix(a,b,f):
        n=node('ShaderNodeMixRGB','Layer color');set_input(n,0,f)
        set_input(n,1,(*a,1) if isinstance(a,tuple) else a)
        set_input(n,2,(*b,1) if isinstance(b,tuple) else b);return n.outputs[0]
    def multiply_vec(v,s):
        n=node('ShaderNodeVectorMath','Grain direction');n.operation='MULTIPLY'
        set_input(n,0,v);set_input(n,1,s);return n.outputs[0]
    def noise(v,scale,detail=2):
        n=node('ShaderNodeTexNoise','Surface variation');set_input(n,'Vector',v)
        n.inputs['Scale'].default_value=scale;n.inputs['Detail'].default_value=detail
        n.inputs['Roughness'].default_value=.62;return n.outputs['Fac']
    def ramp(v,lo,hi):
        n=node('ShaderNodeMapRange','Bounded mask');n.clamp=True;set_input(n,'Value',v)
        n.inputs['From Min'].default_value=lo;n.inputs['From Max'].default_value=hi
        return n.outputs[0]
    tc=node('ShaderNodeTexCoord','Stable part-local metres');v=tc.outputs['Object']
    generated=tc.outputs['Generated']
    cloud=noise(v,35,3);fine=noise(v,680,1)
    brush=noise(multiply_vec(v,(800,15,800)),1,2)
    wood=noise(multiply_vec(v,(140,5,140)),1,3)
    # Small bevel faces carry broken wear. This is independent of new topology.
    attr=node('ShaderNodeAttribute','Bevel exposure');attr.attribute_name='FW_Edge'
    wear=calc('MULTIPLY',attr.outputs['Fac'],ramp(cloud,.29,.66))
    wear=calc('MULTIPLY',wear,.64)
    ao=node('ShaderNodeAmbientOcclusion','Only this rigid part');ao.only_local=True
    ao.samples=8;ao.inputs['Distance'].default_value=.015
    rough=.5;metal=0.;emission=(0.,0.,0.);height=fine;strength=.10;distance=.00013
    if key in ['brass','edge']:
        # Metallic alloy and dielectric oxidation are separate masks.
        tarnish=ramp(noise(v,23,3),.39,.64)
        tarnish=calc('MULTIPLY',tarnish,calc('SUBTRACT',1,wear))
        color=mix((.64,.36,.115),(.13,.075,.031),tarnish)
        patina=calc('MULTIPLY',ramp(noise(v,67,2),.63,.79),calc('SUBTRACT',1,wear))
        color=mix(color,(.025,.095,.072),calc('MULTIPLY',patina,.45))
        color=mix(color,(.80,.52,.22),wear)
        metal=calc('SUBTRACT',1,calc('MAXIMUM',tarnish,patina))
        rough=calc('ADD',.29,calc('MULTIPLY',tarnish,.24))
        rough=calc('ADD',rough,calc('MULTIPLY',cloud,.07));height=brush
    elif key in ['steel','silver']:
        if key=='steel':
            # A blue-black oxide surface with exposed steel at worn edges.
            color=mix((.018,.029,.038),(.041,.065,.080),cloud)
            color=mix(color,(.46,.50,.52),wear)
            metal=wear
            rough=calc('ADD',.35,calc('MULTIPLY',brush,.17))
        else:
            color=mix((.45,.48,.49),(.62,.64,.63),cloud);metal=1.
            rough=calc('ADD',.30,calc('MULTIPLY',brush,.18))
        height=brush;distance=.00007
    elif key in ['navy','navy_wood']:
        color=mix((.009,.020,.033),(.025,.047,.065),cloud)
        exposed=(.15,.064,.026) if key=='navy_wood' else (.47,.49,.48)
        color=mix(color,exposed,calc('MULTIPLY',wear,.75))
        rough=calc('ADD',.42,calc('MULTIPLY',cloud,.18))
        metal=0. if key=='navy_wood' else wear
        height=wood if key=='navy_wood' else fine
        distance=.00019 if key=='navy_wood' else .00008
    elif key in ['wood','wood_light']:
        grain=ramp(wood,.31,.68)
        color=mix((.035,.012,.006),(.19,.077,.026),grain)
        color=mix(color,(.25,.13,.052),calc('MULTIPLY',wear,.50))
        rough=calc('ADD',.46,calc('MULTIPLY',wood,.20))
        height=wood;strength=.16;distance=.00035
    elif key in ['teal','core']:
        color=mix((.008,.09,.074),(.035,.30,.22),cloud)
        rough=calc('ADD',.24,calc('MULTIPLY',cloud,.10))
        emission=mix((.003,.025,.019),(.023,.18,.13),cloud)
        height=fine;strength=.035;distance=.00004
    elif key=='black':
        color=mix((.007,.013,.017),(.017,.030,.033),cloud);rough=.22;strength=.02
    elif key=='rope':
        color=mix((.12,.078,.03),(.45,.31,.14),brush)
        rough=.88;height=brush;strength=.2;distance=.0004
    elif key=='ember':
        color=mix((.12,.019,.002),(.5,.15,.012),cloud);rough=.80
        emission=mix((.18,.012,.001),(.85,.26,.025),cloud)
    else:
        raise ValueError(key)
    bump=node('ShaderNodeBump','Restrained surface relief');bump.inputs['Strength'].default_value=strength
    bump.inputs['Distance'].default_value=distance;links.new(height,bump.inputs['Height'])
    bsdf=node('ShaderNodeBsdfPrincipled','Editable PBR');set_input(bsdf,'Base Color',color)
    set_input(bsdf,'Roughness',rough);set_input(bsdf,'Metallic',metal)
    links.new(bump.outputs['Normal'],bsdf.inputs['Normal'])
    set_input(bsdf,'Emission Color',(*emission,1) if isinstance(emission,tuple) else emission)
    bsdf.inputs['Emission Strength'].default_value=1.0
    output=node('ShaderNodeOutputMaterial','Output');links.new(bsdf.outputs[0],output.inputs['Surface'])
    utility=node('ShaderNodeEmission','Bake utility');utility.inputs['Strength'].default_value=1.0
    orm=node('ShaderNodeCombineColor','ORM bake source');orm.mode='RGB'
    set_input(orm,'Red',calc('ADD',.4,calc('MULTIPLY',ao.outputs['AO'],.6)))
    set_input(orm,'Green',rough);set_input(orm,'Blue',metal)
    target=node('ShaderNodeTexImage','Bake target')
    mat['surface_key']=key
    return mat

def prepare():
    assert bpy.data.scenes.get(PREFIX+'Bake') is None,'Preserve existing revision'
    # Before any edit, keep a standalone backup of the current live file.
    bpy.ops.wm.save_as_mainfile(filepath=SOURCE+'/before_material_live.blend',copy=True)
    bake=bpy.data.scenes.new(PREFIX+'Bake');bake.unit_settings.system='METRIC'
    bake.unit_settings.scale_length=1.;bake.render.engine='CYCLES';bake.cycles.device='CPU'
    bake.cycles.samples=16;bake.cycles.use_denoising=False
    bake.render.bake.use_clear=True;bake.render.bake.use_selected_to_active=False
    bake.view_settings.view_transform='AgX'
    for asset_id in IDS:
        old=bpy.data.scenes['FirearmV2_'+asset_id]
        scene=bpy.data.scenes.new(PREFIX+asset_id);scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
        scene.render.engine='BLENDER_EEVEE';scene.view_settings.view_transform='AgX';scene.world=old.world
        scene['runtime_id']=asset_id;scene['asset_id']='v3_'+asset_id
        info=json.loads(old['manifest_json']);info['version']=3;info['blender_scene']=scene.name
        for p in info['parts']:p['name']=p['name'].replace('v2_','v3_',1)
        info['material_revision']='Shared baked PBR v3, accepted v2 geometry and sockets preserved'
        scene['manifest_json']=json.dumps(info)
        for ob in old.objects:
            new=ob.copy();new.name=ob.name.replace('v2_','v3_',1)
            if ob.type=='MESH':
                new.data=ob.data.copy();new.data.name=new.name+'_Mesh'
                key=ob.data.materials[0].name.removeprefix('M_FirearmV1_')
                if new.get('part_role') in ['navy_stock','short_stock']:key='navy_wood'
                new['original_material']=ob.data.materials[0].name;new['surface_key']=key
                new.data.materials.clear();new.data.materials.append(material(key))
                for face in new.data.polygons:face.material_index=0
                attr=new.data.attributes.new('FW_Edge','FLOAT','CORNER')
                for f in new.data.polygons:
                    area=f.area
                    # Restrict wear to bevel strips, never repaint a whole broad face.
                    value=max(0.,min(1.,(.00034-area)/.00028))
                    for li in f.loop_indices:attr.data[li].value=value
                new.data.uv_layers.active.name='FirearmAtlas'
                bake.collection.objects.link(new)
            scene.collection.objects.link(new)
    obs=select_all_parts()
    # Preserve each verified local chart; offset before packing to prevent accidental welding.
    for i,o in enumerate(obs):
        for uv in o.data.uv_layers.active.data:uv.uv.x+=i*2.
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.select_all(action='SELECT')
    bpy.ops.uv.average_islands_scale()
    bpy.ops.uv.pack_islands(rotate=True,scale=True,margin_method='FRACTION',margin=.008)
    bpy.ops.object.mode_set(mode='OBJECT')
    repair_guard_uvs()
    bpy.ops.wm.save_as_mainfile(filepath=SOURCE+'/firearm_material_v3.blend')
    print('V3_PREPARED',len(obs),'parts',len({o.data.materials[0].name for o in obs}),'procedural materials')

def repair_guard_uvs():
    obs=select_all_parts()
    for oi,ob in enumerate(obs):
        for uv in ob.data.uv_layers.active.data:uv.uv.x+=oi*3.
        if ob.get('part_role') not in ['guard','trigger_guard']:continue
        me=ob.data;layer=me.uv_layers.active
        for fi,face in enumerate(me.polygons):
            coords=[me.vertices[me.loops[li].vertex_index].co for li in face.loop_indices]
            # The inherited bent tube has warped quads. A planar projection can
            # turn their UV outline into a bow tie, even with isolated charts.
            # Convex face charts keep both exported triangles disjoint.
            if len(coords)==4:
                width=((coords[1]-coords[0]).length+(coords[3]-coords[2]).length)*.5
                height=((coords[2]-coords[1]).length+(coords[0]-coords[3]).length)*.5
                chart=[(0,0),(width,0),(width,height),(0,height)]
            else:
                radius=math.sqrt(max(face.area,1e-10)/math.pi)
                chart=[(radius*math.cos(i*math.tau/len(coords)),radius*math.sin(i*math.tau/len(coords))) for i in range(len(coords))]
            for li,p in zip(face.loop_indices,chart):
                layer.data[li].uv=(p[0]+fi*2.,p[1])
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.select_all(action='SELECT')
    bpy.ops.uv.average_islands_scale()
    bpy.ops.uv.pack_islands(rotate=True,scale=True,margin_method='FRACTION',margin=.008)
    bpy.ops.object.mode_set(mode='OBJECT')
    for ob in obs:
        ob.data.materials.clear();ob.data.materials.append(material(ob['surface_key']))
    print('Guard charts isolated; material source restored')

def bake_channel(channel):
    assert channel in ['color','normal','orm','emission']
    select_all_parts();scene=bpy.context.scene
    size={'color':1024,'normal':1024,'orm':512,'emission':256}[channel]
    space='sRGB' if channel in ['color','emission'] else 'Non-Color'
    name='FirearmV3_'+channel
    old=bpy.data.images.get(name)
    if old:bpy.data.images.remove(old)
    image=bpy.data.images.new(name,width=size,height=size,alpha=False,float_buffer=False)
    image.colorspace_settings.name=space
    if channel=='normal':image.generated_color=(.5,.5,1.,1.)
    graphs=[m for m in bpy.data.materials if m.name.startswith('M_FirearmV3_Source_')]
    for mat in graphs:
        nodes=mat.node_tree.nodes;links=mat.node_tree.links
        bsdf=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
        output=next(n for n in nodes if n.type=='OUTPUT_MATERIAL')
        target=next(n for n in nodes if n.label=='Bake target');target.image=image;nodes.active=target
        if channel=='normal':links.new(bsdf.outputs[0],output.inputs['Surface'])
        else:
            utility=next(n for n in nodes if n.label=='Bake utility')
            for link in list(utility.inputs['Color'].links):links.remove(link)
            if channel=='orm':
                source=next(n for n in nodes if n.label=='ORM bake source').outputs[0]
                links.new(source,utility.inputs['Color'])
            else:
                source=bsdf.inputs['Base Color' if channel=='color' else 'Emission Color']
                if source.is_linked:links.new(source.links[0].from_socket,utility.inputs['Color'])
                else:utility.inputs['Color'].default_value=source.default_value
            links.new(utility.outputs[0],output.inputs['Surface'])
    bpy.ops.object.bake(type='NORMAL' if channel=='normal' else 'EMIT',margin=max(2,size//128),use_clear=True)
    image.filepath_raw=SOURCE+'/textures/firearm_'+channel+'.png';image.file_format='PNG'
    image.save();image.pack()
    for mat in graphs:
        n=mat.node_tree.nodes;bsdf=next(x for x in n if x.type=='BSDF_PRINCIPLED')
        output=next(x for x in n if x.type=='OUTPUT_MATERIAL');mat.node_tree.links.new(bsdf.outputs[0],output.inputs['Surface'])
        next(x for x in n if x.label=='Bake target').image=None
    bpy.ops.wm.save_as_mainfile(filepath=SOURCE+'/firearm_material_v3.blend')
    print('V3_BAKED',channel,size)

def baked_material(glow=False):
    name='M_FirearmV3_Glow' if glow else 'M_FirearmV3_Surface'
    mat=bpy.data.materials.get(name)
    if mat:
        for n in mat.node_tree.nodes:
            if n.type=='TEX_IMAGE' and n.label in ['color','normal','orm','emission']:
                n.image=bpy.data.images['FirearmV3_'+n.label]
        return mat
    mat=bpy.data.materials.new(name);mat.use_nodes=True
    nodes=mat.node_tree.nodes;links=mat.node_tree.links
    bsdf=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
    for channel in ['color','normal','orm']+(['emission'] if glow else []):
        tex=nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images['FirearmV3_'+channel];tex.label=channel
        if channel=='color':links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
        elif channel=='normal':
            n=nodes.new('ShaderNodeNormalMap');n.uv_map='FirearmAtlas'
            links.new(tex.outputs['Color'],n.inputs['Color']);links.new(n.outputs['Normal'],bsdf.inputs['Normal'])
        elif channel=='emission':
            links.new(tex.outputs['Color'],bsdf.inputs['Emission Color']);bsdf.inputs['Emission Strength'].default_value=1
        else:
            s=nodes.new('ShaderNodeSeparateColor');s.mode='RGB';links.new(tex.outputs['Color'],s.inputs['Color'])
            links.new(s.outputs['Green'],bsdf.inputs['Roughness']);links.new(s.outputs['Blue'],bsdf.inputs['Metallic'])
            group=bpy.data.node_groups.get('glTF Material Output')
            if not group:
                group=bpy.data.node_groups.new('glTF Material Output','ShaderNodeTree')
                group.interface.new_socket(name='Occlusion',in_out='INPUT',socket_type='NodeSocketFloat')
            n=nodes.new('ShaderNodeGroup');n.node_tree=group;links.new(s.outputs['Red'],n.inputs['Occlusion'])
    return mat

def finish():
    for ob in meshes():
        ob.data.materials.clear();ob.data.materials.append(baked_material(ob['surface_key'] in ['teal','core','ember']))
    for asset_id in IDS:
        scene=bpy.data.scenes[PREFIX+asset_id];bpy.context.window.scene=scene
        obs=[o for o in scene.objects if o.type=='MESH']
        info=json.loads(scene['manifest_json']);info['materials']=sorted({m.name for o in obs for m in o.data.materials})
        info['texture_set']='firearm_material_v3 shared atlas';scene['manifest_json']=json.dumps(info)
        for ob in scene.objects:ob.select_set(True)
        bpy.context.view_layer.objects.active=obs[0]
        # Tangents cannot be exported directly on source n-gons. Use the exact
        # source loop tessellation on temporary export meshes, preserving every
        # source polygon and custom normal in the editable saved asset.
        originals=[]
        for ob in obs:
            original=ob.data;original.calc_loop_triangles()
            triangles=list(original.loop_triangles)
            temp=bpy.data.meshes.new(ob.name+'_ExportTriangles')
            temp.from_pydata([v.co for v in original.vertices],[],[list(t.vertices) for t in triangles])
            temp.update()
            for m in original.materials:temp.materials.append(m)
            uv=temp.uv_layers.new(name='FirearmAtlas');normals=[]
            for ti,t in enumerate(triangles):
                temp.polygons[ti].use_smooth=original.polygons[t.polygon_index].use_smooth
                for corner,li in enumerate(t.loops):
                    uv.data[ti*3+corner].uv=original.uv_layers.active.data[li].uv
                    normals.append(original.corner_normals[li].vector)
            temp.normals_split_custom_set(normals)
            originals.append((ob,original,temp));ob.data=temp
        try:
            bpy.ops.export_scene.gltf(filepath=GAME+'/'+asset_id+'.glb',export_format='GLB',use_selection=True,
                use_active_scene=True,export_animations=False,export_skins=False,export_extras=True,
                export_tangents=True,export_yup=True,export_cameras=False,export_lights=False)
        finally:
            for ob,original,temp in originals:ob.data=original;bpy.data.meshes.remove(temp)
        print('V3_EXPORTED',asset_id,info['triangles'],len(obs))
    bpy.ops.wm.save_as_mainfile(filepath=SOURCE+'/firearm_material_v3.blend')
