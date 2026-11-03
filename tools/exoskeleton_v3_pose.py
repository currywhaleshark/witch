"""Pure mechanical follower frames in Blender coordinates, shared by authoring and QA."""
from mathutils import Vector,Matrix

def frame(origin,direction,front):
    y=Vector(direction).normalized();z=Vector(front);z=(z-y*z.dot(y)).normalized();x=y.cross(z).normalized()
    m=Matrix((x,y,z)).transposed().to_4x4();m.translation=Vector(origin);return m

def solve(manifest,poses):
    rest={n:Matrix(m) for n,m in manifest['body_rest_frames'].items()}
    frames={n:Matrix(m) for n,m in manifest['rig_rest_frames'].items()}
    cfg=manifest['config'];out={};chest=poses['DEF-chest']@rest['DEF-chest'].inverted()
    for role in ['back_power','back_link_L','back_link_R']:out[role]=chest@frames[role]
    for side,sign in [('L',1),('R',-1)]:
        upper='DEF-upper_arm.'+side;fore='DEF-forearm.'+side;hand='DEF-hand.'+side;shin='DEF-shin.'+side
        s=poses[upper].translation;e=poses[fore].translation;w=poses[hand].translation
        delta=poses[upper]@rest[upper].inverted()
        preferred=delta.to_3x3()@Vector(manifest['anchors'][side]['hinge_rest'])
        a=(s-e).normalized();b=(w-e).normalized();n=a.cross(b)*sign
        if n.length<.08:n=preferred.normalized()
        else:n.normalize()
        ss=s+n*cfg['arm_offset_shoulder'];ee=e+n*cfg['arm_offset_elbow'];ww=w+n*cfg['arm_offset_wrist']
        out['upper_'+side]=frame(ss,ee-ss,n)
        out['shoulder_'+side]=frame(ss,ee-ss,delta.to_3x3()@Vector((sign,0,0)))
        out['elbow_'+side]=frame(ee,ww-ee,n)
        out['forearm_'+side]=out['elbow_'+side]
        out['wrist_'+side]=out['elbow_'+side]
        leg_delta=poses[shin]@rest[shin].inverted()
        for part in ['knee','shin']:out[part+'_'+side]=leg_delta@frames[part+'_'+side]
        if 'bridge' in manifest:
            spec=manifest['bridge'][side];start=chest@Vector(spec['start']);end=ss
            axis=(end-start).normalized();length=(end-start).length
            for i in range(spec['segments']):
                p=start+axis*(length-spec['segment_length'])*i/(spec['segments']-1)
                out['bridge_'+side+'_'+str(i)]=frame(p,axis,chest.to_3x3()@Vector((0,0,1)))
            out['mount_'+side]=chest@frames['mount_'+side]
    return out
