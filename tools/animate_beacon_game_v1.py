import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from automation_rigid_common import *
BASE=ROOT/'assets/actors/automation_batch2/beacon_game_v1';OUT=ROOT/'reports/automation_batch2_complete_v1/beacon'
bpy.ops.wm.open_mainfile(filepath=str(BASE/'beacon_geometry.blend'));sc=bpy.context.scene
mesh=next(o for o in sc.objects if o.type=='MESH');geo=json.loads((BASE/'geometry.json').read_text(encoding='utf8'))
p={n:Vector(v) for n,v in geo['pivots'].items()};p.update({n:Vector(v) for n,v in geo['leg_pivots'].items()})
spec={'root':(Vector(),None),'base':(p['base'],'root')}
for n in ['leg.A','leg.B','leg.C','key','column_lower']:spec[n]=(p[n],'base')
spec['column_upper']=(p['column_upper'],'column_lower')
for n in ['lamp_mount','bell','hammer','horn']:spec[n]=(p[n],'column_upper')
for n in ['rotor','lamp','lens','core','antenna']:spec[n]=(p[n],'lamp_mount')
spec['Socket_attack']=(p['bell']+Vector((0,.02,-.06)),'bell')
spec['Socket_core']=(p['core'],'core');spec['Socket_signal']=(p['rotor'],'lamp_mount')
spec['Socket_bar']=(Vector((0,0,1.68)),'root')
rig=make_rig(mesh,spec,'Beacon_Rigid_Rig');points=part_points(mesh)
clips={'deploy':(.5,False),'pulse':(1.,True),'hit':(.25,False),'shutdown':(.4,False),'death':(1.0,False)}
def pose(clip,t):
    duration=clips[clip][0];u=t/duration
    opening=smooth(0,.82,u) if clip=='deploy' else (1-smooth(.12,1,u) if clip=='shutdown' else 1.)
    fold=math.radians(40)*(1-opening);d={'root':I.copy(),'base':I.copy()}
    for n in ['leg.A','leg.B','leg.C']:
        radial=Vector((p[n].x,p[n].y,0)).normalized();axis=Vector((-radial.y,radial.x,0))
        d[n]=about(p[n],axis,fold)
    lift=max(0.,.004-min((d[n]@v).z for n in ['leg.A','leg.B','leg.C'] for v in points[n]))
    d['base']=Matrix.Translation((0,0,lift))
    for n in ['leg.A','leg.B','leg.C']:d[n]=d['base']@d[n]
    d['key']=d['base']@about(p['key'],'X',math.tau*t if clip=='pulse' else .7*math.sin(math.pi*u))
    sway=math.radians(5)*math.sin(math.pi*u)*math.sin(2*math.pi*u) if clip=='hit' else 0.
    d['column_lower']=d['base']@about(p['column_lower'],'Y',sway)
    d['column_upper']=d['column_lower']@Matrix.Translation((0,0,-.20*(1-opening)))
    for n in ['lamp_mount','bell','hammer','horn']:d[n]=d['column_upper'].copy()
    for n in ['rotor','lamp','lens','core','antenna']:d[n]=d['lamp_mount'].copy()
    if clip=='pulse':
        d['rotor']=d['lamp_mount']@about(p['rotor'],'Z',math.tau*t)
        d['hammer']=d['column_upper']@about(p['hammer'],'Y',.35*math.cos(math.tau*t)-.03)
        d['bell']=d['column_upper']@about(p['bell'],'Y',.04*math.sin(4*math.pi*t)*math.exp(-5*t))
    if clip=='death':
        d.update(death[min(len(death)-1,round(t*120))])
    for n,(pivot,parent) in spec.items():
        if n.startswith('Socket_'):d[n]=d[parent].copy()
    return d
death=collapse(points,pose('pulse',0),1.,.025)
report=write_actions('beacon',BASE,OUT,mesh,rig,spec,clips,pose,metadata={
 'id':'lure_beacon','shadow_radius_m':.45,'signal_seconds':0.,'signal_loop_period_seconds':1.,
 'mechanism':{'upper_column_retraction_m':.20,'leg_fold_degrees':40,'rotor_full_turn_seconds':1.,'rigid_scale':True},
 'presentation_contract':{'emission':'deploy: smooth ramp 0.35–0.50 s; pulse/hit: 1; shutdown: off by 0.12 s; death: off after 0.08 s','signal_fx':'Socket_signal at pulse 0 s; range ring and sound waves supplied by game','required_helper':'game/tests/helpers/automation_batch2_visual.gd'},
 'variants':{'base':{'scale':1.,'instances':1}}})
print('BEACON_ANIMATED',report['bones'],flush=True)
