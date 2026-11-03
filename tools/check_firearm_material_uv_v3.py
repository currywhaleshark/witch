"""Exact triangle intersections adjudicate the QA's coarse 128px UV warnings."""
from pathlib import Path
import json,collections
from package_firearm_material_assets_v3 import read_glb,accessor
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
    for asset_id in ['matchlock','rifle','shotgun']:
        d,b=read_glb(ROOT/'game/assets/weapons/firearm_material_v3'/(asset_id+'.glb'))
        for node in d['nodes']:
            if 'mesh' not in node:continue
            for p in d['meshes'][node['mesh']]['primitives']:
                uv=accessor(d,b,p['attributes']['TEXCOORD_0']);idx=[a[0] for a in accessor(d,b,p['indices'])]
                for start in range(0,len(idx),3):
                    tri=[uv[i] for i in idx[start:start+3]];ti=len(tris);tris.append(tri);labels.append(node['name'])
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
        'scope':'Exact clipped UV-triangle intersections across every part and all three assets on the shared atlas; common edges have zero area.'}
    (ROOT/'reports/firearm_material_v3/uv_intersections.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result,indent=2));assert result['passed']
if __name__=='__main__':main()
