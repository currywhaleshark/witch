"""Reopen and sample the delivered synchronized NLA playlist."""
import bpy,json
from pathlib import Path
from mathutils import Matrix
ROOT=Path(__file__).resolve().parents[1];R=ROOT/'reports/exoskeleton_v4'
s=bpy.data.scenes['ExoskeletonV4_Fit'];bpy.context.window.scene=s
m=json.loads((ROOT/'assets/equipment/exoskeleton_v4/parts.json').read_text());rows=[x for x in json.loads((R/'bake_poses.json').read_text()) if x['form']=='civilian']
rests={'body':json.loads((R/'body_rest.json').read_text()),'hair':json.loads((R/'hair_rest.json').read_text())}
rigs={'body':bpy.data.objects['ReferenceBodyRig_v29'],'exo':bpy.data.objects['ExoskeletonRig_v4'],'hair':next(o for o in s.objects if o.type=='ARMATURE' and o.name.startswith('REF_Hair_'))}
helpers=[o for o in s.objects if o.type=='MESH' and o.name.startswith(('REF_Civilian_','REF_Transformed_')) and not any(mod.type=='ARMATURE' for mod in o.modifiers)]
assert all(o.hide_get() and o.hide_render for o in helpers),'Fitting helpers must remain hidden'
C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)));CI=C.inverted()
strips={strip.action.name.removeprefix('EXO_v4_'):strip for strip in rigs['exo'].animation_data.nla_tracks['PLAYLIST_8_CURRENT_MOTIONS'].strips}
max_error=0.;samples=0;worst={};per_clip={}
for row in rows:
 strip=strips[row['motion']];f=strip.frame_start+row['phase']*row['clip_length']*24
 s.frame_set(int(f),subframe=f-int(f));bpy.context.view_layer.update()
 for kind,rig in rigs.items():
  for b in rig.data.bones:
   if kind=='exo':
    role=b.name.removeprefix('EXO-');d=Matrix.Identity(4) if role=='root' else CI@Matrix(row['mechanism'][role])@Matrix(m['mechanism_rest_godot'][role]).inverted()@C
   else:
    source=row['bones'] if kind=='body' else row['hair_bones'];d=CI@Matrix(source[b.name])@Matrix(rests[kind][b.name]).inverted()@C
   target=d@b.matrix_local;actual=rig.pose.bones[b.name].matrix
   err=max(abs(target[i][j]-actual[i][j]) for i in range(4) for j in range(4))
   per_clip[row['motion']]=max(per_clip.get(row['motion'],0),err)
   if err>max_error:max_error=err;worst={'motion':row['motion'],'phase':row['phase'],'frame':f,'rig':kind,'bone':b.name,'actual':[list(r) for r in actual],'expected':[list(r) for r in target]}
 samples+=1
out={'passed':max_error<.0002,'poses':samples,'maximum_matrix_error':max_error,'worst':worst,'per_clip_error':per_clip,'body_bones':len(rigs['body'].data.bones),'equipment_bones':len(rigs['exo'].data.bones),'playlist_clips':len(strips),'fps':s.render.fps,'strips':{name:[x.frame_start,x.frame_end,x.action_frame_start,x.action_frame_end,x.scale] for name,x in strips.items()}}
(R/'saved_preview.json').write_text(json.dumps(out,indent=2));print('V4_SAVED_PREVIEW',out,flush=True);assert out['passed']

