"""Tripo giant: 27 rigid mechanisms, fitted game proportions, shared PBR atlas."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from automation_rigid_common import *
g=Geometry('giant')
def pt(p):
    x,y,z=p;return Vector((-(x-.03)*2.46,-(y-.08)*3.0,z*(2.8/.838)+.006))
groups={
 'pelvis':[11,19], 'torso':[26,65,77,79], 'head':[18], 'gear':[5], 'key':[7], 'exhaust.L':[35],'exhaust.R':[10],
 'shoulder.L':[2,27,38,64], 'upper.L':[30,37,43], 'forearm.L':[1,41,46,52],
 'fist.L':[9,21,24,31,44,45,47,51,60,61,76],
 'shoulder.R':[3,14,54], 'upper.R':[6,48], 'forearm.R':[4,33],
 'fist.R':[32,34,39,42,53,56,57,58,63,66,67,75,78],
 'thigh.L':[12,36,40], 'shin.L':[16,22], 'foot.L':[13,29,55,59,62,68,72],
 'thigh.R':[17], 'shin.R':[8,15], 'foot.R':[28,23,49,50,69,70,71,73,74]}
replaced=[20,25]
assert sorted(n for ids in groups.values() for n in ids)+[]==sorted(set(n for ids in groups.values() for n in ids))
assert set(n for ids in groups.values() for n in ids)|set(replaced)==set(g.src)
for n,ids in groups.items():g.extract(n,ids,pt)
budget={'pelvis':440,'torso':2400,'head':390,'gear':720,'key':370,'exhaust.L':280,'exhaust.R':280,
 'shoulder.L':850,'shoulder.R':850,'upper.L':500,'upper.R':500,'forearm.L':790,'forearm.R':790,'fist.L':970,'fist.R':970,
 'thigh.L':470,'thigh.R':470,'shin.L':450,'shin.R':450,'foot.L':650,'foot.R':650}
g.reduce(budget)
joints={
 'arm.L':[(-.164,-.012,.585),(-.321,-.008,.429),(-.393,-.058,.224)],
 'arm.R':[(.235,.015,.579),(.354,.027,.429),(.404,-.072,.215)],
 'leg.L':[(-.065,.049,.324),(-.134,.029,.221),(-.138,.077,.091)],
 'leg.R':[(.126,.070,.325),(.191,.063,.213),(.192,.119,.091)]}
for stem,js in joints.items():
    limb,side=stem.split('.');names=['upper','forearm','fist'] if limb=='arm' else ['thigh','shin','foot']
    for i,(n,p) in enumerate(zip(names,js)):
        p=pt(p);r=([.115,.095,.082] if limb=='arm' else [.105,.085,.075])[i]
        g.add(n+'.'+side,cylinder('Closed_axis',p-Vector((.07,0,0)),p+Vector((.07,0,0)),r,g.steel,12))
g.add('torso',cylinder('Waist_bearing',pt((.03,.045,.33)),pt((.03,.045,.40)),.17,g.steel,16))
g.add('head',cylinder('Neck_mount',pt((.04,-.12,.56)),pt((.04,-.12,.61)),.09,g.steel,12))
# Both forearm source pistons were fused. New wrist cylinders and rods slide
# independently, joining a forearm pad to the wrist fork with fixed lengths.
pistons={}
for side in ('L','R'):
    js=[pt(p) for p in joints['arm.'+side]];a=js[1].lerp(js[2],.35)+Vector((0,.17,0));b=js[2]+Vector((0,.12,-.08))
    axis=(b-a).normalized();length=(b-a).length
    for label,o in [('piston_case.'+side,cylinder('Wrist_cylinder',a,a+axis*length*.67,.045,g.brass,12)),('piston_rod.'+side,cylinder('Wrist_rod',b-axis*length*.72,b,.022,g.steel,10))]:g.add(label,o)
    g.add('forearm.'+side,cylinder('Piston_anchor',a-Vector((0,.16,0)),a,.045,g.brass,10))
    g.add('fist.'+side,cylinder('Piston_fork',b-Vector((0,.12,0)),b,.04,g.brass,10))
    pistons[side]={'a':list(a),'b':list(b),'case_length':length*.67,'rod_length':length*.72}
core=pt((.052,-.219,.47));g.add('core',cylinder('Power_core',core-Vector((0,.012,0)),core+Vector((0,.010,0)),.050,g.cyan,16))
visor=pt((.042,-.196,.624))
vs=[visor+Vector((x,y,z)) for x,y,z in [(-.08,0,-.012),(.08,0,-.012),(.08,0,.012),(-.08,0,.012),(-.08,-.008,-.012),(.08,-.008,-.012),(.08,-.008,.012),(-.08,-.008,.012)]]
g.add('visor',mesh_object('Cyan_visor',vs,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],g.cyan))
g.cleanup(cap_groups=[n for n in groups if n.startswith(('upper.','forearm.','fist.','thigh.','shin.','foot.','shoulder.'))])
# Source toe-shell seam reduction leaves one redundant 19 mm surface over an
# existing ankle shelf. Remove the smaller coplanar face; the covering face stays.
ob=g.low['foot.L'];bm=bmesh.new();bm.from_mesh(ob.data)
target=Vector((.3321088254,.1945864409,.2047660947))
overlap=[f for f in bm.faces if (f.calc_center_median()-target).length<.0001 and f.calc_area()<.0005]
assert len(overlap)==1
g.repairs.append({'group':'foot.L','coplanar_source_seam_face_removed':{'center':list(target),'area':overlap[0].calc_area()}})
bmesh.ops.delete(bm,geom=overlap,context='FACES_ONLY');bm.to_mesh(ob.data);bm.free()
g.bake(glow_groups=['core','visor'],cage=.025)
g.report.update({'static_fit':'X 2.46, Y 3.0, Z 2.8/0.838, rotation pi, source floor support centre [0.03,0.08,0]',
 'joints':{n:[list(pt(p)) for p in js] for n,js in joints.items()},'pistons':pistons,'pistons_replaced':replaced,
 'pivots':{'pelvis':list(pt((.03,.045,.34))),'torso':list(pt((.03,.03,.40))),'head':list(pt((.04,-.12,.60))),
 'gear':list(pt((.053,-.181,.47))),'core':list(core),'visor':list(visor),'key':list(pt((.033,-.066,.724))),
 'exhaust.L':list(pt((-.110,-.05,.68))),'exhaust.R':list(pt((.176,-.047,.68)))}})
dump(g.base/'geometry.json',g.report)
print('GIANT_GEOMETRY',g.report['triangles'],g.report['parts'],flush=True)
