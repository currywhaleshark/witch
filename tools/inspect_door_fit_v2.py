"""Measure actual front-ray coverage of the closed door, independent of the builder."""
import bpy,json,sys,math
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1]
label=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'after'
OUT=ROOT/'reports/door_fit_v2'/label;OUT.mkdir(parents=True,exist_ok=True)
src=ROOT/'reports/door_fit_v2/before/door_v1.blend' if label=='before' else ROOT/'assets/actors/boss_trial_v1/authoring/door_v1.blend'
bpy.ops.wm.open_mainfile(filepath=str(src));scene=bpy.context.scene
rig=next(o for o in scene.objects if o.type=='ARMATURE');obj=next(o for o in scene.objects if o.type=='MESH')
rig.animation_data.action=bpy.data.actions['close'];scene.frame_set(25);bpy.context.view_layer.update()
leaf_names={b.name for b in rig.data.bones if b.parent and b.parent.name=='hinge'}
groups={g.index:g.name for g in obj.vertex_groups}
moving={v.index for v in obj.data.vertices if groups[v.groups[0].group] in leaf_names}
em=obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
verts=[v.co.copy() for v in em.vertices]
poly_leaf=[list(p.vertices) for p in em.polygons if p.vertices[0] in moving]
poly_frame=[list(p.vertices) for p in em.polygons if p.vertices[0] not in moving]
leaf=BVHTree.FromPolygons(verts,poly_leaf);frame=BVHTree.FromPolygons(verts,poly_frame)
dx=.002;xs=[-.8+i*dx for i in range(801)];zs=[.08+i*.01 for i in range(204)]
rows=[];open_count=0;uncovered=0
for z in zs:
    hits=[frame.ray_cast(Vector((x,3,z)),Vector((0,-1,0)),6)[0] is not None for x in xs]
    center=400
    if hits[center]:continue
    left=next((i for i in range(center,-1,-1) if hits[i]),None)
    right=next((i for i in range(center,len(xs)) if hits[i]),None)
    if left is None or right is None or not .3<xs[right]-xs[left]<1.1:continue
    covered=[leaf.ray_cast(Vector((xs[i],3,z)),Vector((0,-1,0)),6)[0] is not None for i in range(left+1,right)]
    count=len(covered);missing=covered.count(False)
    start=next((i for i,v in enumerate(covered) if v),count)
    end=next((i for i,v in enumerate(reversed(covered)) if v),count)
    rows.append({'z':round(z,4),'left':xs[left],'right':xs[right],'opening_width':xs[right]-xs[left],
        'uncovered_m':missing*dx,'left_gap_m':start*dx,'right_gap_m':end*dx})
    open_count+=count;uncovered+=missing
result={'label':label,'ray_step_m':dx,'vertical_step_m':.01,'rows':rows,
    'uncovered_aperture_fraction':uncovered/open_count,'maximum_row_uncovered_m':max(r['uncovered_m'] for r in rows),
    'central_maximum_gap_m':max(r['uncovered_m'] for r in rows if .4<r['z']<1.7),
    'leaf_closed_bounds':[[min(verts[i][axis] for i in moving) for axis in range(3)],[max(verts[i][axis] for i in moving) for axis in range(3)]],
    'hinge_head':list(rig.data.bones['hinge'].head_local)}
(OUT/'fit_measurement.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('DOOR_FIT_MEASURED',json.dumps({k:v for k,v in result.items() if k!='rows'}))
scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=640;scene.render.resolution_y=720;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='Standard'
scene.world=bpy.data.worlds.new('Door fit review');scene.world.color=(.04,.045,.055)
for mat in obj.data.materials:
    bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');color=bs.inputs['Base Color'].links[0].from_socket
    emission=mat.node_tree.nodes.new('ShaderNodeEmission');out=next(n for n in mat.node_tree.nodes if n.type=='OUTPUT_MATERIAL');mat.node_tree.links.new(color,emission.inputs['Color']);mat.node_tree.links.new(emission.outputs[0],out.inputs['Surface'])
cam=bpy.data.objects.new('DoorReviewCamera',bpy.data.cameras.new('DoorReviewCamera'));scene.collection.objects.link(cam);scene.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=2.7
target=Vector((0,0,1.15))
for view,offset in [('front',(0,5,0)),('quarter',(2.1,5,1.5)),('back',(0,-5,0))]:
    cam.location=target+Vector(offset);cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(OUT/f'closed_{view}.png');bpy.ops.render.render(write_still=True)
