"""Rigid armature frames in Blender coordinates. Swing follows arm direction, never axial roll."""
from mathutils import Vector,Matrix,Quaternion
def frame(origin,direction,front):
 y=Vector(direction).normalized();z=Vector(front);z=(z-y*z.dot(y)).normalized();x=y.cross(z).normalized()
 m=Matrix((x,y,z)).transposed().to_4x4();m.translation=origin;return m
def solve(m,p,correctives=None):
 rest={n:Matrix(v) for n,v in m['body_rest_frames'].items()};rr={n:Matrix(v) for n,v in m['rig_rest_frames'].items()};cfg=m['config'];out={}
 chest=p['DEF-chest']@rest['DEF-chest'].inverted()
 for role in ['back_power','back_link_L','back_link_R']:out[role]=chest@rr[role]
 for side,sign in [('L',1),('R',-1)]:
  upper='DEF-upper_arm.'+side;fore='DEF-forearm.'+side;hand='DEF-hand.'+side;shin='DEF-shin.'+side
  s=p[upper].translation;e=p[fore].translation;w=p[hand].translation
  n=(s-e).normalized().cross((w-e).normalized())*sign
  if n.length<.08:n=(p[upper]@rest[upper].inverted()).to_3x3()@Vector(m['anchors'][side]['hinge_rest'])
  n.normalize()
  shift=Vector((0,0,0))
  if correctives and side in correctives:
   import math
   correction=correctives[side];n=Quaternion((w-e).normalized(),math.radians(correction['angle']))@n
   a=correction['shift'];shift=chest.to_3x3()@Vector((a[0],-a[2],a[1]))
  ee=e+n*cfg['arm_offset_elbow']+shift;ww=w+n*cfg['arm_offset_wrist']+shift
  ry=chest.to_3x3()@(rest[fore].translation-rest[upper].translation).normalized()
  swing=Quaternion().slerp(ry.rotation_difference((e-s).normalized()),cfg['shoulder_swing_weight'])
  offset=Vector((sign*cfg['shoulder_offset'][0],cfg['shoulder_offset'][1],cfg['shoulder_offset'][2]))
  ss=s+swing@(chest.to_3x3()@offset)
  out['shoulder_'+side]=frame(ss,swing@ry,swing@(chest.to_3x3()@Vector((sign,0,0))))
  u=frame(ss,ee-ss,n);axis=u.to_3x3().col[1];length=(ee-ss).length
  out['upper_'+side]=u
  out['upper_prox_'+side]=u
  distal=u.copy();distal.translation+=axis*(length-m['anchors'][side]['upper_length']);out['upper_dist_'+side]=distal
  spec=m['upper_slide'][side];start=ss+axis*spec['start_offset'];travel=length-spec['start_offset']-spec['end_offset']
  for i in range(spec['segments']):out['upper_slide_'+side+'_'+str(i)]=frame(start+axis*(travel-spec['segment_length'])*i/(spec['segments']-1),axis,n)
  for role in ['elbow_','forearm_','wrist_']:out[role+side]=frame(ee,ww-ee,n)
  leg=p[shin]@rest[shin].inverted()
  for role in ['knee_','shin_','calf_cuff_upper_','calf_cuff_lower_']:
   if role+side in rr:out[role+side]=leg@rr[role+side]
  spec=m['bridge'][side];start=chest@Vector(spec['start']);axis=(ss-start).normalized();length=(ss-start).length
  for i in range(spec['segments']):out['bridge_'+side+'_'+str(i)]=frame(start+axis*(length-spec['segment_length'])*i/(spec['segments']-1),axis,chest.to_3x3()@Vector((0,0,1)))
  out['mount_'+side]=chest@rr['mount_'+side]
 return out
