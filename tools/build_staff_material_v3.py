"""Bake an editable, shared PBR atlas from the accepted v2 rigid meshes.
Run in isolated Blender: --background --factory-startup --python-exit-code 1.
"""
import bpy, json, hashlib, shutil, math, time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets/weapons/staff_transform_v2/authoring/staff_transform_v2.blend'
ASSET=ROOT/'assets/weapons/staff_material_v3'
GAME=ROOT/'game/assets/weapons/staff_material_v3'
REPORT=ROOT/'reports/staff_material_v3'
for folder in (ASSET/'authoring',ASSET/'exports',ASSET/'textures',GAME,REPORT):folder.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.device='CPU'
scene.cycles.samples=32
scene.cycles.use_denoising=False
scene.render.bake.margin=8
scene.render.bake.use_clear=True
scene.render.bake.use_selected_to_active=False
scene.view_settings.view_transform='Standard'
meshes=sorted((o for o in scene.objects if o.type=='MESH'),key=lambda o:o.name)

def geometry(obj):
    return {'vertices':[list(v.co) for v in obj.data.vertices],
            'polygons':[list(p.vertices) for p in obj.data.polygons],
            'matrix':[list(r) for r in obj.matrix_world],
            'smooth':[p.use_smooth for p in obj.data.polygons],
            'parent':obj.parent.name}
before={o.name:geometry(o) for o in meshes}
source_materials={o.name:[o.data.materials[p.material_index].name for p in o.data.polygons] for o in meshes}
(ASSET/'authoring/source_material_regions.json').write_text(json.dumps(source_materials,indent=2),encoding='utf-8')

# Pointiness alone spans an entire low-poly face. Restrict strong wear to the
# small edge/bevel faces, so a broad forged blade does not become cloudy camouflage.
for obj in meshes:
    hint=obj.data.attributes.get('WearRegion') or obj.data.attributes.new('WearRegion','FLOAT','CORNER')
    finish_hint=obj.data.attributes.get('FinishNormal') or obj.data.attributes.new('FinishNormal','FLOAT','CORNER')
    for face in obj.data.polygons:
        amount=max(0.0,min(1.0,(.00045-face.area)/.00032))
        for index in face.loop_indices:
            hint.data[index].value=amount
            # The forged/cutting profile already defines sharp blade facets. Avoid
            # undersampled synthetic rounding along its thin, straight cutting edge.
            finish_hint.data[index].value=0.0 if obj.name.startswith('cutter_jaw_') else 1.0

# One atlas across all separately moving parts. Vertex positions/topology stay fixed.
bpy.ops.object.select_all(action='DESELECT')
for obj in meshes:
    obj.select_set(True)
    for uv in list(obj.data.uv_layers):obj.data.uv_layers.remove(uv)
    obj.data.uv_layers.new(name='StaffAtlas')
bpy.context.view_layer.objects.active=meshes[0]
kwargs={'angle_limit':math.radians(66),'island_margin':.008,'area_weight':.25,
        'correct_aspect':True,'scale_to_bounds':True}
properties=bpy.ops.uv.smart_project.get_rna_type().properties
scene.tool_settings.mesh_select_mode=(False,False,True)
# Preserve crisp geometric material boundaries. A single smart projection can join
# a silver bevel and a dark blade in one chart, making their color boundary pixelated.
region_names=sorted({name for names in source_materials.values() for name in names})
for region_index,region_name in enumerate(region_names):
    for obj in meshes:
        for vertex in obj.data.vertices:vertex.select=False
        for edge in obj.data.edges:edge.select=False
        for face,name in zip(obj.data.polygons,source_materials[obj.name]):face.select=name==region_name
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.uv.smart_project(**{k:v for k,v in kwargs.items() if k in properties})
    bpy.ops.object.mode_set(mode='OBJECT')
    # Offset each region before the final pack so coincident chart borders cannot weld.
    for obj in meshes:
        layer=obj.data.uv_layers.active
        for face,name in zip(obj.data.polygons,source_materials[obj.name]):
            if name==region_name:
                for index in face.loop_indices:layer.data[index].uv.x+=region_index*2.0
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.select_all(action='SELECT')
bpy.ops.uv.pack_islands(rotate=True,scale=True,margin_method='FRACTION',margin=.012)
bpy.ops.object.mode_set(mode='OBJECT')

# Work in linear color. The game's color-only ambient lighting has no sky reflection;
# this stylized metalness range preserves broad value separation in its existing light.
PARAMS={
 'Enamel_Navy':{'base':(.012,.029,.057),'rough':.42,'metal':.12,'wear':(.19,.23,.23),'wear_strength':.30},
 'Aged_Brass':{'base':(.30,.165,.060),'rough':.43,'metal':.64,'wear':(.53,.34,.135),'wear_strength':.44},
 'Brass_Edge':{'base':(.43,.265,.095),'rough':.30,'metal':.70,'wear':(.64,.44,.20),'wear_strength':.26},
 'Cutting_Steel':{'base':(.39,.47,.52),'rough':.26,'metal':.68,'wear':(.64,.70,.72),'wear_strength':.18},
 'Oiled_Steel':{'base':(.022,.031,.040),'rough':.48,'metal':.64,'wear':(.15,.19,.205),'wear_strength':.24},
 'Navy_Grip':{'base':(.008,.016,.026),'rough':.80,'metal':.0,'wear':(.025,.039,.049),'wear_strength':.18},
 'Teal_Core':{'base':(.025,.22,.17),'rough':.23,'metal':.12,'wear':(.04,.32,.24),'wear_strength':.0},
}
graphs={}
def build_material(mat,params):
    mat.use_nodes=True;nodes=mat.node_tree.nodes;links=mat.node_tree.links;nodes.clear()
    def n(kind,label):
        node=nodes.new(kind);node.label=label;return node
    def set_input(node,key,value):
        if isinstance(value,bpy.types.NodeSocket):links.new(value,node.inputs[key])
        else:node.inputs[key].default_value=value
    def calc(op,a,b=0):
        node=n('ShaderNodeMath',op);node.operation=op
        set_input(node,0,a);set_input(node,1,b);return node.outputs[0]
    def mix(a,b,factor):
        node=n('ShaderNodeMixRGB','Surface layers');node.blend_type='MIX'
        set_input(node,0,factor);set_input(node,1,(*a,1) if isinstance(a,tuple) else a)
        set_input(node,2,(*b,1) if isinstance(b,tuple) else b);return node.outputs[0]
    def noise(vector,scale,detail=2):
        node=n('ShaderNodeTexNoise','Spatial surface grain');set_input(node,'Vector',vector)
        node.inputs['Scale'].default_value=scale;node.inputs['Detail'].default_value=detail
        return node.outputs['Fac']
    coord=n('ShaderNodeTexCoord','Object-space material');vector=coord.outputs['Object']
    geometry_node=n('ShaderNodeNewGeometry','Convex edge wear')
    curvature=n('ShaderNodeMapRange','Convex edges only');curvature.clamp=True
    links.new(geometry_node.outputs['Pointiness'],curvature.inputs['Value'])
    curvature.inputs['From Min'].default_value=.515;curvature.inputs['From Max'].default_value=.61
    ao=n('ShaderNodeAmbientOcclusion','Local cavity only');ao.only_local=True;ao.samples=8
    ao.inputs['Distance'].default_value=.018
    cloud=noise(vector,34,2);fine=noise(vector,950,1)
    grain_vector=n('ShaderNodeVectorMath','Brushed lengthwise');grain_vector.operation='MULTIPLY'
    links.new(vector,grain_vector.inputs[0]);grain_vector.inputs[1].default_value=(1450,1450,24)
    brush=noise(grain_vector.outputs[0],1,1)
    region=n('ShaderNodeAttribute','Small bevels carry edge wear');region.attribute_name='WearRegion'
    wear=calc('MULTIPLY',region.outputs['Fac'],calc('MULTIPLY',curvature.outputs[0],calc('MULTIPLY',cloud,params['wear_strength'])))
    color=mix(params['base'],params['wear'],wear)
    modulation=n('ShaderNodeMixRGB','Subtle material variation');modulation.blend_type='MULTIPLY'
    modulation.inputs[0].default_value=1.0;links.new(color,modulation.inputs[1])
    variation=.07 if mat.name in ('Cutting_Steel','Oiled_Steel','Enamel_Navy') else .16
    links.new(calc('ADD',1.0-variation*.5,calc('MULTIPLY',cloud,variation)),modulation.inputs[2])
    color=modulation.outputs[0]
    if mat.name in ('Aged_Brass','Brass_Edge'):
        oxidation=calc('MULTIPLY',calc('SUBTRACT',1.0,ao.outputs['AO']),calc('MULTIPLY',cloud,.40))
        color=mix(color,(.028,.100,.070),oxidation)
    cavity=n('ShaderNodeMixRGB','Light cavity staining');cavity.blend_type='MULTIPLY'
    cavity.inputs[0].default_value=.22;links.new(color,cavity.inputs[1]);links.new(ao.outputs['Color'],cavity.inputs[2])
    color=cavity.outputs[0]
    rough_grain=brush if mat.name in ('Cutting_Steel','Oiled_Steel') else cloud
    rough=calc('ADD',params['rough']-.025,calc('MULTIPLY',rough_grain,.05))
    metal=params['metal']
    if mat.name=='Enamel_Navy':metal=calc('ADD',metal,calc('MULTIPLY',wear,1.6))
    finish_region=n('ShaderNodeAttribute','Keep forged blades sharp');finish_region.attribute_name='FinishNormal'
    bevel=n('ShaderNodeBevel','Submillimetre edge normal');bevel.samples=8
    links.new(calc('MULTIPLY',finish_region.outputs['Fac'],.0008),bevel.inputs['Radius'])
    bump=n('ShaderNodeBump','Fine finish, not silhouette');bump.inputs['Strength'].default_value=.07
    bump.inputs['Distance'].default_value=.00006 if mat.name!='Navy_Grip' else .00022
    links.new(brush if mat.name=='Cutting_Steel' else fine,bump.inputs['Height']);links.new(bevel.outputs['Normal'],bump.inputs['Normal'])
    emission=(0.,0.,0.)
    if mat.name=='Teal_Core':
        # A controlled center glow; no HDR bloom requirement or gameplay light added.
        color=mix((.008,.065,.05),(.045,.30,.24),cloud)
        emission=mix((.018,.25,.18),(.18,.67,.48),calc('MULTIPLY',cloud,ao.outputs['AO']))
    bsdf=n('ShaderNodeBsdfPrincipled','Editable surface');set_input(bsdf,'Base Color',color)
    set_input(bsdf,'Metallic',metal);set_input(bsdf,'Roughness',rough)
    set_input(bsdf,'Normal',bump.outputs['Normal'])
    set_input(bsdf,'Emission Color',(*emission,1) if isinstance(emission,tuple) else emission)
    bsdf.inputs['Emission Strength'].default_value=1.0
    output=n('ShaderNodeOutputMaterial','Surface output');links.new(bsdf.outputs[0],output.inputs['Surface'])
    utility=n('ShaderNodeEmission','Bake channel');utility.inputs['Strength'].default_value=1.0
    orm=n('ShaderNodeCombineColor','R occlusion / G roughness / B metallic');orm.mode='RGB'
    set_input(orm,'Red',calc('ADD',.35,calc('MULTIPLY',ao.outputs['AO'],.65)))
    set_input(orm,'Green',rough);set_input(orm,'Blue',metal)
    target=n('ShaderNodeTexImage','Atlas bake target')
    mat.use_fake_user=True
    return {'material':mat,'output':output,'bsdf':bsdf,'utility':utility,'target':target,
            'color':color,'orm':orm.outputs[0],'emission':emission}

for name,params in PARAMS.items():graphs[name]=build_material(bpy.data.materials[name],params)
textures={};bake_seconds={}
for channel,size,space in [('color',1024,'sRGB'),('orm',512,'Non-Color'),('normal',1024,'Non-Color'),('emission',256,'sRGB')]:
    started=time.monotonic()
    image=bpy.data.images.new('Staff_'+channel,width=size,height=size,alpha=False,float_buffer=False)
    image.colorspace_settings.name=space
    for graph in graphs.values():
        mat=graph['material'];links=mat.node_tree.links
        graph['target'].image=image;mat.node_tree.nodes.active=graph['target']
        if channel=='normal':links.new(graph['bsdf'].outputs[0],graph['output'].inputs['Surface'])
        else:
            socket=graph[channel];utility=graph['utility']
            for link in list(utility.inputs['Color'].links):links.remove(link)
            if isinstance(socket,tuple):utility.inputs['Color'].default_value=(*socket,1)
            else:links.new(socket,utility.inputs['Color'])
            links.new(utility.outputs[0],graph['output'].inputs['Surface'])
    bpy.ops.object.bake(type='NORMAL' if channel=='normal' else 'EMIT',margin=max(1,size//128),use_clear=True)
    image.filepath_raw=str(ASSET/'textures'/('staff_'+channel+'.png'));image.file_format='PNG';image.save();image.pack()
    textures[channel]=image;bake_seconds[channel]=round(time.monotonic()-started,2)
    print('STAFF_BAKED',channel,bake_seconds[channel],flush=True)
for graph in graphs.values():
    graph['material'].node_tree.links.new(graph['bsdf'].outputs[0],graph['output'].inputs['Surface'])
    graph['target'].image=None

material=bpy.data.materials.new('Staff_PBR_v3');material.use_nodes=True
nodes=material.node_tree.nodes;links=material.node_tree.links
bsdf=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
for channel,image in textures.items():
    node=nodes.new('ShaderNodeTexImage');node.image=image;node.label=channel
    if channel=='color':links.new(node.outputs['Color'],bsdf.inputs['Base Color'])
    elif channel=='emission':
        links.new(node.outputs['Color'],bsdf.inputs['Emission Color']);bsdf.inputs['Emission Strength'].default_value=1.0
    elif channel=='normal':
        normal=nodes.new('ShaderNodeNormalMap');normal.uv_map='StaffAtlas'
        links.new(node.outputs['Color'],normal.inputs['Color']);links.new(normal.outputs['Normal'],bsdf.inputs['Normal'])
    else:
        separate=nodes.new('ShaderNodeSeparateColor');separate.mode='RGB'
        links.new(node.outputs['Color'],separate.inputs['Color'])
        links.new(separate.outputs['Green'],bsdf.inputs['Roughness']);links.new(separate.outputs['Blue'],bsdf.inputs['Metallic'])
        occlusion=bpy.data.node_groups.new('glTF Material Output','ShaderNodeTree')
        occlusion.interface.new_socket(name='Occlusion',in_out='INPUT',socket_type='NodeSocketFloat')
        group=nodes.new('ShaderNodeGroup');group.node_tree=occlusion
        links.new(separate.outputs['Red'],group.inputs['Occlusion'])
core_material=material.copy();core_material.name='Staff_Core_v3'
# A material boundary, not just atlas padding, prevents emissive mip bleed onto metal.
for link in list(bsdf.inputs['Emission Color'].links):links.remove(link)
bsdf.inputs['Emission Color'].default_value=(0,0,0,1);bsdf.inputs['Emission Strength'].default_value=0.0
for obj in meshes:
    regions=source_materials[obj.name]
    has_body=any(name!='Teal_Core' for name in regions);has_core='Teal_Core' in regions
    obj.data.materials.clear()
    if has_body:obj.data.materials.append(material)
    if has_core:obj.data.materials.append(core_material)
    for face,name in zip(obj.data.polygons,regions):face.material_index=int(has_body) if name=='Teal_Core' else 0
    assert geometry(obj)==before[obj.name],obj.name+' geometry changed'
scene['material_revision']='v3: shared baked PBR atlas; v2 geometry/pivots/mechanisms unchanged'
scene['material_workflow']='Seven editable procedural source materials retained as fake users; source_material_regions.json restores assignments.'
source=ASSET/'authoring/staff_material_v3.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(source))
bpy.ops.object.select_all(action='SELECT')
export=ASSET/'exports/staff_parts.glb'
bpy.ops.export_scene.gltf(filepath=str(export),export_format='GLB',use_selection=True,
                         export_animations=False,export_extras=True,export_yup=True,export_tangents=False)
shutil.copy2(export,GAME/export.name)
config=json.loads((ROOT/'assets/weapons/staff_transform_v2/parts.json').read_text(encoding='utf-8'))
config['version']=3;config['asset']='res://assets/weapons/staff_material_v3/staff_parts.glb'
config['material_revision']={'materials':2,'maps':{c:list(i.size) for c,i in textures.items()},
    'atlas':'All 52 rigid parts share one PBR set; emission is restricted to original core faces. No geometry or mechanical change.'}
for target in (ASSET/'parts.json',GAME/'parts.json'):target.write_text(json.dumps(config,indent=2)+'\n',encoding='utf-8')
report={'passed':True,'source':str(SOURCE.relative_to(ROOT)),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        'geometry_preserved_meshes':len(meshes),'triangles':sum(v['triangles'] for v in config['metrics'].values()),
        'metrics':config['metrics'],'materials':2,'maps':config['material_revision']['maps'],'bake_seconds':bake_seconds,
        'parameters':PARAMS,'asset_sha256':hashlib.sha256(export.read_bytes()).hexdigest(),
        'blend_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'blender':bpy.app.version_string,
        'texture_bytes':sum(Path(i.filepath_raw).stat().st_size for i in textures.values()),
        'uncompressed_rgba8_with_mips_estimate_bytes':sum(i.size[0]*i.size[1]*4*4/3 for i in textures.values())}
(REPORT/'build.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print('STAFF_MATERIAL_BUILD_COMPLETE '+json.dumps(report),flush=True)
