"""Exact triangle intersections adjudicate the QA's coarse 128px UV warnings."""
from pathlib import Path
import json,collections,sys
from package_firearm_material_assets_v4 import read_glb,accessor
ROOT=Path(__file__).resolve().parents[1]

def cross(a,b):return a[0]*b[1]-a[1]*b[0]
def sub(a,b):return (a[0]-b[0],a[1]-b[1])
def area(poly):return abs(sum(cross(poly[i],poly[(i+1)%len(poly)]) for i in range(len(poly))))*.5 if len(poly)>2 else 0.
def intersect(subject,clip):
    sign=1 if cross(sub(clip[1],clip[0]),sub(clip[2],clip[0]))>=0 else -1
    poly=list(subject)
    for i,a in enumerate(clip):
        b=clip[(i+1)%3];edge=sub(b,a);result=[]
        if not poly:return 0.
        prev=poly[-1];dp=sign*cross(edge,sub(prev,a))
        for cur in poly:
            dc=sign*cross(edge,sub(cur,a))
            if (dc>=0)!=(dp>=0):
                t=dp/(dp-dc);result.append((prev[0]+t*(cur[0]-prev[0]),prev[1]+t*(cur[1]-prev[1])))
            if dc>=0:result.append(cur)
            prev=cur;dp=dc
        poly=result
    return area(poly)

def main():
    tris=[];labels=[];grid=collections.defaultdict(list)
    exported='--exported' in sys.argv
    if exported:
        for asset_id in ['powder_barrel','gatling','smoke_launcher','artillery_shell','naval_shell','smoke_canister']:
            d,b=read_glb(ROOT/'game/assets/weapons/firearm_material_v4'/(asset_id+'.glb'))
            for node in d['nodes']:
                if 'mesh' not in node:continue
                for p in d['meshes'][node['mesh']]['primitives']:
                    uv=accessor(d,b,p['attributes']['TEXCOORD_0']);idx=[a[0] for a in accessor(d,b,p['indices'])]
                    for start in range(0,len(idx),3):
                        tris.append([uv[i] for i in idx[start:start+3]]);labels.append(node['name'])
    else:
        source=json.loads((ROOT/'reports/firearm_material_v4/source_uv_triangles.json').read_text(encoding='utf-8'))
        tris=source['triangles'];labels=source['labels']
    for ti,tri in enumerate(tris):
        for x in range(int(min(p[0] for p in tri)*64),int(max(p[0] for p in tri)*64)+1):
            for y in range(int(min(p[1] for p in tri)*64),int(max(p[1] for p in tri)*64)+1):grid[(x,y)].append(ti)
    pairs=set();overlaps=[]
    for items in grid.values():
        for a,i in enumerate(items):
            for j in items[a+1:]:
                if (i,j) in pairs:continue
                pairs.add((i,j));overlap=intersect(tris[i],tris[j])*1024**2
                if overlap>1e-4:overlaps.append({'a':labels[i],'b':labels[j],'square_pixels_at_1024':overlap})
    overlaps.sort(key=lambda x:-x['square_pixels_at_1024'])
    result={'passed':not overlaps,'triangles':len(tris),'candidate_pairs':len(pairs),'overlaps_above_0_0001_texel':overlaps[:30],
        'scope':('Exported GLB' if exported else 'Saved source')+' UV-triangle intersections across every part and all six assets on the shared atlas; common edges have zero area.'}
    report_name='uv_export_intersections.json' if exported else 'uv_intersections.json'
    (ROOT/'reports/firearm_material_v4'/report_name).write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result,indent=2));assert result['passed']
if __name__=='__main__':main()
