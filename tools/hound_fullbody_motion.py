"""Whole-body Quaternius wolf -> rigid mechanical hound retarget.

Run inside Blender. Full world orientation deltas drive the axial skeleton;
evaluated source segment directions drive fixed-length limb chains. Contact
cleanup follows the source knee plane, never an arbitrary world-space pole.
"""
import gzip, json, math
import numpy as np
from mathutils import Matrix, Vector

I = Matrix.Identity(4)
C = Matrix.Diagonal((1., -1., 1.))
CONTACTS = {'fore.L': (0., .275), 'fore.R': (.175, .455),
            'hind.L': (.50, .70), 'hind.R': (.625, .825)}

def smooth(t):
    t = max(0., min(1., t))
    return t*t*(3-2*t)

def frame(direction):
    y = direction.normalized()
    x = Vector((1,0,0)); x = (x-y*x.dot(y)).normalized()
    return Matrix((x, y, x.cross(y))).transposed()

def segment(a,b,aa,bb):
    r = frame(bb-aa) @ frame(b-a).transposed()
    return Matrix.Translation(aa) @ r.to_4x4() @ Matrix.Translation(-a)

def pivot(rest, at, rotation):
    return Matrix.Translation(at) @ rotation.to_4x4() @ Matrix.Translation(-rest)

class FullBodyGallop:
    def __init__(self, root, rests, geometry, points):
        path = root/'assets/actors/automation_batch2/motion_sources/quaternius/wolf_gallop_samples.json.gz'
        self.source = json.loads(gzip.decompress(path.read_bytes()))
        self.srest = {n:Matrix(b['matrix']) for n,b in self.source['rest'].items()}
        self.rests = rests; self.pivots = {n:r.translation for n,r in rests.items()}
        self.joints = {n:list(map(Vector,js)) for n,js in geometry['joints'].items()}
        self.geometry = geometry; self.points = points
        self.samples = self.source['samples']
        self.source_cache = {}
        self.raw_cache = {}
        self.height_scale = .25
        self.stats = {'max_reach_correction_m':0.,'max_ik_shortfall_m':0.,'max_contact_shortfall_m':0.}
        # Calibrate stride from the retargeted planted trajectories, not by
        # depressing the body to reach an imposed 3.25m per half second.
        design=[]; values=[]; rawheights=[]
        stems=list(self.joints)
        for k,stem in enumerate(stems):
            start,end=CONTACTS[stem]
            for ph in np.linspace(start+.025,end-.025,25):
                d,legs=self.raw(float(ph)); xyz=legs[stem][-1]
                row=[0.]*5;row[k]=1.;row[4]=-ph
                design.append(row);values.append(xyz.y)
                rawheights.append(xyz.z-self.support(stem,I.to_3x3()))
        fit=np.linalg.lstsq(design,values,rcond=None)[0]
        self.distance=float(fit[-1])
        self.intercepts={n:float(fit[i]) for i,n in enumerate(stems)}
        self.height_offset=-float(np.median(rawheights))
        self.foot_x={}
        for stem in stems:
            start,end=CONTACTS[stem]
            self.foot_x[stem]=float(np.mean([self.raw(float(p))[1][stem][-1].x for p in np.linspace(start,end,21)]))
        # Anticipate contact corrections on both sides of each stance boundary.
        # A periodic Gaussian envelope avoids dropping/rising the trunk exactly
        # when a contact flag switches. Full source body rotation is unchanged.
        count=480;needed=[]
        for ph in np.arange(count)/count:
            z=self.height_offset;raw,chains=self.raw(float(ph))
            for stem,js in self.joints.items():
                target,r,contact=self.foot_target(stem,float(ph))
                if not contact:continue
                chain=chains[stem];a=chain[0].copy();a.z+=z
                c=target-(chain[-1]-chain[-2]) if stem.startswith('hind') else target
                length=(js[1]-js[0]).length+(js[2]-js[1]).length-.004
                horiz=math.hypot(a.x-c.x,a.y-c.y)
                if horiz<length:z-=max(0.,a.z-c.z-math.sqrt(length*length-horiz*horiz))
            needed.append(self.height_offset-z)
        self.reach_curve=[]
        for i in range(count):
            dist=np.minimum(abs(np.arange(count)-i),count-abs(np.arange(count)-i))/count
            self.reach_curve.append(float(np.max(np.array(needed)*np.exp(-(dist/.055)**2))))

    def source_at(self,ph):
        ph=round(ph%1,10)
        if ph in self.source_cache:return self.source_cache[ph]
        f=ph*240;i=min(int(f),239);u=f-i
        a,b=self.samples[i]['bones'],self.samples[i+1]['bones'];s={}
        for n in a:
            ma,mb=Matrix(a[n]['matrix']),Matrix(b[n]['matrix'])
            q=ma.to_quaternion().slerp(mb.to_quaternion(),u)
            s[n]={'head':Vector(a[n]['head']).lerp(Vector(b[n]['head']),u),
                  'tail':Vector(a[n]['tail']).lerp(Vector(b[n]['tail']),u),
                  'matrix':Matrix.Translation(ma.translation.lerp(mb.translation,u))@q.to_matrix().to_4x4()}
        self.source_cache[ph]=s
        return s

    def rotation(self,s,n):
        return C@(s[n]['matrix']@self.srest[n].inverted()).to_3x3()@C

    def support(self,stem,r):
        limb,side=stem.split('.');paw=limb+'_paw.'+side;p=self.joints[stem][-1]
        return .005-min((r@(v-p)).z for v in self.points[paw])

    def raw(self,ph):
        ph=round(ph%1,10)
        if ph in self.raw_cache:return self.raw_cache[ph]
        s=self.source_at(ph);p=self.pivots;d={'root':I.copy()}
        tr=C@(s['Torso2']['head']-self.srest['Torso2'].translation)*self.height_scale
        d['chest']=pivot(p['chest'],p['chest']+tr,self.rotation(s,'Torso2'))
        spine=(p['chest']+p['pelvis'])*.5
        d['pelvis']=pivot(spine,d['chest']@spine,self.rotation(s,'Back'))
        for n,sn,parent in [('neck','Neck1','chest'),('head','Head','neck'),
                             ('tail_01','Tail1','pelvis'),('tail_02','Tail4','tail_01')]:
            d[n]=pivot(p[n],d[parent]@p[n],self.rotation(s,sn))
        d['jaw']=d['head']@pivot(p['jaw'],p['jaw'],Matrix.Rotation(math.radians(8)+.025*math.sin(math.tau*ph),3,'X'))
        d['key']=d['chest']@pivot(p['key'],p['key'],Matrix.Rotation(math.tau*ph,3,'Z'))
        legs={}
        for stem,js in self.joints.items():
            limb,side=stem.split('.');par='chest' if limb=='fore' else 'pelvis'
            ns=['FrontUpperLeg','FrontLowerLeg'] if limb=='fore' else ['BackLeg','BackUpperLeg','BackLowerLeg']
            chain=[d[par]@js[0]]
            for k,n in enumerate(ns):
                sb=s[n+'.'+side];direction=(C@(sb['tail']-sb['head'])).normalized()
                if limb=='fore' and k==0:
                    # The mechanical upper/lower leg ratio is nearly 1:1;
                    # the wolf is ~1:2.6. Its extreme recovered humerus angle
                    # would put this much longer elbow above the back. A soft
                    # downward limit preserves fold order without an IK flip.
                    z=direction.z;limit=-.10;width=.07
                    direction.z=limit-width*math.log1p(math.exp(min(60.,(limit-z)/width)))
                    direction.normalize()
                chain.append(chain[-1]+direction*(js[k+1]-js[k]).length)
            legs[stem]=chain
        self.raw_cache[ph]=(d,legs)
        return d,legs

    def foot_target(self,stem,ph):
        s=self.source_at(ph);raw,legs=self.raw(ph);a,b=CONTACTS[stem];duty=b-a
        f=(ph-a)%1;contact=f<=duty+1e-9
        limb,side=stem.split('.');sf=('IKFrontLeg.' if limb=='fore' else 'IKBackLeg.')+side
        r=self.rotation(s,sf);target=legs[stem][-1].copy();target.z+=self.height_offset
        if contact:
            r=I.to_3x3();target=Vector((self.foot_x[stem],self.intercepts[stem]-self.distance*ph,self.support(stem,r)))
        else:
            air=(f-duty)/(1-duty);w=.15*(1-duty)
            if air<.15 or air>.85:
                # Local endpoint Hermite blend preserves the original flight
                # fold without a long spline overshoot.
                at=b if air<.15 else a
                boundary=b+w if air<.15 else a-w
                q=(f-duty)/w if air<.15 else (f-1+w)/w
                def rawp(p):
                    v=self.raw(p)[1][stem][-1].copy();v.z+=self.height_offset;return v
                rawpoint=rawp(boundary);h=.0001;vel=(rawp(boundary+h)-rawp(boundary-h))/(2*h)
                plant=Vector((self.foot_x[stem],self.intercepts[stem]-self.distance*at,self.support(stem,I.to_3x3())))
                pv=Vector((0,-self.distance,0))
                p0,p1,v0,v1=(plant,rawpoint,pv,vel) if air<.15 else (rawpoint,plant,vel,pv)
                target=(2*q**3-3*q*q+1)*p0+(q**3-2*q*q+q)*w*v0+(-2*q**3+3*q*q)*p1+(q**3-q*q)*w*v1
            blend=smooth(air/.15)*(1-smooth((air-.85)/.15))
            r=I.to_quaternion().slerp(r.to_quaternion(),blend).to_matrix()
            target.z=max(target.z,self.support(stem,r))
        return target,r,contact

    @staticmethod
    def ik(a,c,l1,l2,pole):
        v=c-a;raw=v.length;length=max(abs(l1-l2)+.0002,min(l1+l2-.0002,raw))
        direction=v.normalized();c=a+direction*length
        x=(l1*l1-l2*l2+length*length)/(2*length);h=math.sqrt(max(0,l1*l1-x*x))
        p=pole-direction*pole.dot(direction)
        if p.length<1e-5:p=Vector((0,-1,0))-direction*direction.dot(Vector((0,-1,0)))
        return a+direction*x+p.normalized()*h,c,abs(raw-length)

    def pose(self,ph):
        ph=ph%1;raw,rawlegs=self.raw(ph);z=self.height_offset
        # Measured smooth correction on top of full source rotation and bob.
        feet={stem:self.foot_target(stem,ph) for stem in self.joints}
        u=ph*len(self.reach_curve);i=int(u)%len(self.reach_curve);f=u-int(u)
        z-=(1-f)*self.reach_curve[i]+f*self.reach_curve[(i+1)%len(self.reach_curve)]
        self.stats['max_reach_correction_m']=max(self.stats['max_reach_correction_m'],self.height_offset-z)
        T=Matrix.Translation((0,0,z));d={n:T@m for n,m in raw.items() if n!='root'};d['root']=I.copy()
        for stem,js in self.joints.items():
            limb,side=stem.split('.');chain=[T@p for p in rawlegs[stem]];a=chain[0]
            target,r,contact=feet[stem]
            if not contact:
                start,end=CONTACTS[stem];air=((ph-start)%1-(end-start))/(1-(end-start))
                target.z+=(z-self.height_offset)*smooth(air/.15)*(1-smooth((air-.85)/.15))
                target.z=max(target.z,self.support(stem,r))
            hv=chain[-1]-chain[-2] if limb=='hind' else Vector((0,0,0))
            # Carry the source bend PLANE into the new endpoint solve. Using
            # the raw upper-leg vector as a pole can cross the new target line
            # near extension and flip the knee during an otherwise planted foot.
            hinge=(chain[1]-a).cross(chain[2]-chain[1])
            if hinge.length<1e-6:hinge=Vector((1,0,0))
            if hinge.x<0:hinge=-hinge
            if limb=='hind':hinge=-hinge
            pole=(target-hv-a).normalized().cross(hinge.normalized())
            b,c,error=self.ik(a,target-hv,(js[1]-js[0]).length,(js[2]-js[1]).length,pole)
            self.stats['max_ik_shortfall_m']=max(self.stats['max_ik_shortfall_m'],error)
            if contact:self.stats['max_contact_shortfall_m']=max(self.stats['max_contact_shortfall_m'],error)
            target=c+hv
            d[limb+'_upper.'+side]=segment(js[0],js[1],a,b)
            d[limb+'_lower.'+side]=segment(js[1],js[2],b,c)
            if limb=='hind':d['hind_hock.'+side]=segment(js[2],js[3],c,target)
            d[limb+'_paw.'+side]=pivot(js[-1],target,r)
        for stem,p in self.geometry['pistons'].items():
            a0,b0=Vector(p['a']),Vector(p['b']);a=d[p['a_bone']]@a0;b=d[p['b_bone']]@b0
            q=(b0-a0).rotation_difference(b-a).to_matrix()
            d[p['case']]=pivot(a0,a,q);d[p['rod']]=pivot(b0,b,q)
        for n,par in [('core','head'),('core_glow','head'),('tail_glow','tail_02'),('Socket_attack','head'),('Socket_core','head'),('Socket_bar','root')]:d[n]=d[par].copy()
        return d
