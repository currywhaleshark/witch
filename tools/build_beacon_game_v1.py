"""Semantic Tripo beacon reduction and fixed-length telescoping mechanism."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from automation_rigid_common import *
g=Geometry('beacon');center=Vector((.026,.001,0))
def pt(p):
    p=Vector(p)-center;return Vector((-p.x*1.5,-p.y*1.5,p.z*1.5+.004))
groups={
 'base':[1,7,10,14,19,25,26,37,38,44,46,52,53,56,59,61,62,63,64,66,68,70,72,74,75],
 'leg.A':[5,23,54,55,65], 'leg.B':[3,11,50,58], 'leg.C':[2,24,57,60,71],
 'key':[13,18], 'column_lower':[21,67,12], 'column_upper':[20,51,48,41,30,69],
 'rotor':[0,47,4,8,31,32,33,34,35,39,40,43,45,49],
 'lamp':[9,29], 'lamp_mount':[16,22,28], 'lens':[36], 'bell':[27,73], 'hammer':[17], 'horn':[6,42], 'antenna':[15]}
assert sorted(n for ns in groups.values() for n in ns)==sorted(g.src)
leg_pivots={'leg.A':(-.083,-.021,.212),'leg.B':(.085,-.091,.216),'leg.C':(.084,.114,.212)}
def fitted_leg(p,name):
    p=Vector(p);a=Vector(leg_pivots[name]);f=max(0.,min(1.,(a.z-p.z)/.15))
    # Static silhouette fit expands support to 0.90 m, preserving the hinge.
    p.x+=(p.x-a.x)*.48*f;p.y+=(p.y-a.y)*.48*f
    return pt(p)
for name,ids in groups.items():g.extract(name,ids,(lambda p,n=name:fitted_leg(p,n)) if name.startswith('leg.') else pt)
g.reduce({'base':740,'leg.A':240,'leg.B':240,'leg.C':240,'key':110,'column_lower':170,'column_upper':240,'rotor':950,'lamp':150,'lamp_mount':180,'lens':70,'bell':220,'hammer':100,'horn':170,'antenna':100})
# Closed sleeve volumes hide the source segmentation rims when the column moves.
g.add('column_lower',cylinder('Outer_column',pt((.026,.001,.34)),pt((.026,.001,.513)),.046,g.brass,12))
g.add('column_upper',cylinder('Sliding_inner',pt((.026,.001,.35)),pt((.026,.001,.665)),.034,g.brass,12))
# The original lens housing carries a dedicated small light surface.
g.add('core',cylinder('Cyan_glass',pt((.048,-.051,.714)),pt((.05,-.057,.714)),.025,g.cyan,12))
for name,src in leg_pivots.items():
    p=pt(src);rad=Vector((p.x,p.y,0)).normalized();axis=Vector((-rad.y,rad.x,0))
    g.add(name,cylinder('Pivot_pin',p-axis*.036,p+axis*.036,.022,g.brass,12))
g.cleanup(cap_groups=['leg.A','leg.B','leg.C','key','column_upper','hammer','antenna'])
g.bake(glow_groups=['lamp','core'],cage=.015)
g.report.update({'static_fit':'1.5 m height + 4 mm support clearance; Z rotation pi; source XY centre [0.026,0.001]; legs progressively expanded 48% from their hinge',
 'leg_pivots':{n:list(pt(p)) for n,p in leg_pivots.items()},
 'pivots':{'base':list(pt((.026,.001,.22))),'key':list(pt((.144,-.022,.278))),'column_lower':list(pt((.026,.001,.34))),'column_upper':list(pt((.026,.001,.50))),
 'lamp_mount':list(pt((.026,.001,.704))),'rotor':list(pt((.026,.001,.845))),'lamp':list(pt((.026,.001,.845))),
 'lens':list(pt((.046,-.036,.713))),'core':list(pt((.050,-.057,.714))),'bell':list(pt((-.123,-.003,.656))),'hammer':list(pt((-.017,.001,.531))),
 'horn':list(pt((.076,.001,.658))),'antenna':list(pt((.103,.001,.753)))},
 'mechanism':{'upper_column_retraction_m':.20,'rotor_axis':'Z','hammer_source_pivot':[-.017,.001,.531]}})
dump(g.base/'geometry.json',g.report)
print('BEACON_GEOMETRY',g.report['triangles'],g.report['parts'],flush=True)
