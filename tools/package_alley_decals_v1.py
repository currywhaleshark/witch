"""Deterministic crop/alpha/mask/size conversion authorized by GENERATION_SPEC §§10-11.

Generation and content edits use ImageGen. Originals are preserved; this tool only prepares
texture delivery, records transformations and builds a review contact sheet.
"""
from pathlib import Path
import json, hashlib, shutil, argparse, html
from datetime import datetime, timezone
import numpy as np
from PIL import Image, ImageOps, ImageDraw, ImageFont
from scipy import ndimage

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/environment/alley_decals_v1'
DEST=ROOT/'game/assets/textures/decals_v1'
REPORT=ROOT/'reports/alley_decals_v1'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def dump(p,data): p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
def import_settings(out):
    imp=out.with_suffix('.png.import')
    if not imp.exists():
        imp.write_text('[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n\n[deps]\nsource_file="res://assets/textures/decals_v1/'+out.name+'"\n\n[params]\ncompress/mode=0\nmipmaps/generate=true\nprocess/fix_alpha_border=true\n',encoding='utf-8',newline='\n')
    else:
        text=imp.read_text(encoding='utf-8')
        if 'mipmaps/generate=false' in text:
            imp.write_text(text.replace('mipmaps/generate=false','mipmaps/generate=true'),encoding='utf-8',newline='\n')
def bbox(mask):
    y,x=np.nonzero(mask)
    return [int(x.min()),int(y.min()),int(x.max()+1),int(y.max()+1)]
def alpha_cleanup(im,notes):
    a=np.array(im.convert('RGBA')); al=a[:,:,3]
    # Native transparent output has a few chromatic pixels with alpha 1/255 outside the asset.
    count=int(((al>0)&(al<=3)).sum());al[al<=3]=0
    notes.append({'operation':'remove_nearly_invisible_alpha_fringe','threshold':3,'pixels':count})
    a[:,:,3]=al
    return Image.fromarray(a)
def key_magenta(im,notes):
    a=np.array(im.convert('RGB')).astype(float)
    bg=np.median(np.concatenate([a[:10].reshape(-1,3),a[-10:].reshape(-1,3)]),axis=0)
    dist=np.linalg.norm(a-bg,axis=2)
    core=(dist>100)&((np.minimum(a[:,:,0],a[:,:,2])-a[:,:,1])<20)
    if not core.any(): raise ValueError('No foreground after chroma key')
    # Solve the coverage against the nearest paint colour; remove magenta edge spill.
    _,idx=ndimage.distance_transform_edt(~core,return_indices=True)
    fg=a[idx[0],idx[1]];d=fg-bg
    alpha=np.clip(np.sum((a-bg)*d,axis=2)/np.maximum(np.sum(d*d,axis=2),1),0,1)
    alpha[dist<10]=0;alpha[core]=1
    col=np.clip((a-bg*(1-alpha[:,:,None]))/np.maximum(alpha[:,:,None],.02),0,255)
    out=np.dstack([col,np.rint(alpha*255)]).astype('uint8')
    out[out[:,:,3]<=3,3]=0
    notes.append({'operation':'magenta_chroma_key_and_edge_despill','background_rgb':bg.tolist()})
    return Image.fromarray(out)
def mask_prepare(im,item,notes):
    a=np.array(ImageOps.grayscale(im)).astype(float)
    # Ignore negligible off-white background quantization. Preserve all actual gray marks.
    a[a>=250]=255
    horizontal=item['id'] in ('grime_streak_coping','grime_base_dirt')
    h,w=a.shape
    yy=np.minimum(np.arange(h),np.arange(h)[::-1])/max(1,.04*h)
    edge=np.clip(yy,0,1)[:,None]
    if not horizontal:
        xx=np.minimum(np.arange(w),np.arange(w)[::-1])/max(1,.04*w)
        edge=edge*np.clip(xx,0,1)[None,:]
    a=255-(255-a)*edge
    if horizontal:
        # Blend both boundary strips to the identical average seam, without mirroring the artwork.
        n=max(4,round(w*.04));seam=(a[:,0]+a[:,-1])/2
        for i in range(n):
            t=i/n;t=t*t*(3-2*t)
            a[:,i]=seam*(1-t)+a[:,i]*t
            a[:,-1-i]=seam*(1-t)+a[:,-1-i]*t
        notes.append({'operation':'horizontal_boundary_blend','strip_px':n})
    notes.append({'operation':'grayscale_mask_white_edges','fade_border_fraction':.04})
    return Image.fromarray(np.rint(a).astype('uint8'),'L')

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--partial',action='store_true');args=ap.parse_args()
    requests=json.loads((BASE/'generation/requests.json').read_text(encoding='utf-8'))['assets']
    selected=json.loads((BASE/'generation/selection.json').read_text(encoding='utf-8')) if (BASE/'generation/selection.json').exists() else {}
    DEST.mkdir(parents=True,exist_ok=True);REPORT.mkdir(parents=True,exist_ok=True)
    assets=[];missing=[]
    for item in requests:
        id=item['id'];variant=selected.get(id,'a');meta=BASE/'generation'/f'{id}{"_"+variant if variant!="a" else ""}.json'
        if not meta.exists(): missing.append(id);continue
        receipt=json.loads(meta.read_text(encoding='utf-8'));raw=BASE/receipt['raw'];im=Image.open(raw)
        src=BASE/'source'/item['filename'];shutil.copyfile(raw,src)
        notes=[];crop=None
        if item['kind'] in ('sign','vertical'):
            a=np.array(im.convert('RGB')).astype(float)
            non_bg=(np.ptp(a,axis=2)>12)|(np.abs(a.mean(2)-128)>45)
            # Suppress isolated specks before selecting the full rectangle including edging.
            labels,n=ndimage.label(ndimage.binary_closing(non_bg,iterations=5))
            sizes=np.bincount(labels.ravel());sizes[0]=0
            crop=bbox(labels==sizes.argmax())
            crop=[max(0,crop[0]-3),max(0,crop[1]-3),min(im.width,crop[2]+3),min(im.height,crop[3]+3)]
            im=im.crop(crop).convert('RGB')
            notes.append({'operation':'crop_board_and_resample_to_spec_aspect','crop_xyxy':crop,'native_board_size':list(im.size),'target':item['runtime_size']})
            if id=='sign_v_inn_broken':
                a=np.array(im.convert('RGBA'));rgb=a[:,:,:3].astype(float)
                yy,xx=np.indices(a.shape[:2]);region=(xx>a.shape[1]*.12)&(xx<a.shape[1]*.88)&(yy>a.shape[0]*.60)&(yy<a.shape[0]*.83)
                gray=(np.ptp(rgb,axis=2)<10)&(rgb.mean(2)>100)&(rgb.mean(2)<155)
                a[gray&region,3]=0;im=Image.fromarray(a)
                notes.append({'operation':'remove_gray_background_in_broken_hole','region_fraction':[.12,.60,.88,.83],'gray_range':[100,155]})
        elif item['kind']=='mask':
            im=mask_prepare(im,item,notes)
        else:
            im=alpha_cleanup(im,notes) if receipt['transparent'] else key_magenta(im,notes)
            # World dimensions refer to the asset, not the generator's variable empty canvas.
            alpha=np.array(im)[:,:,3]
            # Ignore isolated canvas noise but retain disconnected letters and tie strings.
            labels,n=ndimage.label(alpha>=64);sizes=np.bincount(labels.ravel());sizes[0]=0
            box=bbox((alpha>=64)&(sizes[labels]>=8))
            box=[max(0,box[0]-8),max(0,box[1]-8),min(im.width,box[2]+8),min(im.height,box[3]+8)]
            notes.append({'operation':'crop_transparent_canvas_to_asset','crop_xyxy':box,'alpha_threshold':64,'min_component_px':8,'padding_px':8})
            im=im.crop(box)
            if id=='glass_broken':
                a=np.array(im);a[:,:,3]=np.rint(a[:,:,3]*.45).astype('uint8');im=Image.fromarray(a)
                notes.append({'operation':'translucent_glass_alpha_scale','factor':.45,'hole_alpha_remains_zero':True})
            if id=='wall_cables':
                a=np.array(im).astype(float);n=max(4,round(im.width*.04));seam=(a[:,0]+a[:,-1])/2
                for i in range(n):
                    t=i/n;t=t*t*(3-2*t);a[:,i]=seam*(1-t)+a[:,i]*t;a[:,-1-i]=seam*(1-t)+a[:,-1-i]*t
                im=Image.fromarray(np.rint(a).astype('uint8'))
                notes.append({'operation':'rgba_horizontal_boundary_blend','strip_px':n})
        # Source remains byte-for-byte untouched. Only the game copy is sized/normalized.
        notes.append({'operation':'runtime_resize','from':list(im.size),'to':item['runtime_size'],'filter':'Lanczos'})
        im=im.resize(tuple(item['runtime_size']),Image.Resampling.LANCZOS)
        if id=='wall_cables':
            a=np.array(im);seam=np.rint((a[:,0].astype(float)+a[:,-1])/2).astype('uint8');a[:,0]=seam;a[:,-1]=seam;im=Image.fromarray(a)
        if item['kind']=='mask' and item['id'] in ('grime_streak_coping','grime_base_dirt'):
            a=np.array(im);e=np.rint((a[:,0].astype(float)+a[:,-1])/2).astype('uint8');a[:,0]=e;a[:,-1]=e;im=Image.fromarray(a)
        if item['kind']!='mask':
            a=np.array(im);a[:,:,:3]=np.clip(a[:,:,:3],20,235);im=Image.fromarray(a)
            notes.append({'operation':'clamp_runtime_rgb','min':20,'max':235,'alpha_unchanged':True})
        out=DEST/item['filename'];im.save(out)
        derived=[]
        if item['kind']=='mask':
            mask=np.array(im)
            rgba=np.full((*mask.shape,4),255,dtype='uint8');rgba[:,:,3]=255-mask
            extra=DEST/(id+'_rgba.png');Image.fromarray(rgba).save(extra);import_settings(extra)
            derived.append({'path':str(extra.relative_to(ROOT)).replace('\\','/'),'sha256':sha(extra),'operation':'white_RGB_alpha_equals_255_minus_grayscale'})
        import_settings(out)
        a=np.array(im)
        assets.append(dict(id=id,kind=item['kind'],optional=item['optional'],world_size=item['world_size'],required_text=item['required_text'],
             tool=receipt['tool'],model_version=receipt['model_version'],seed=None,date=receipt['generated_at'],prompt=receipt['prompt'],selected_variant=variant,
             raw=receipt['raw'],source='source/'+item['filename'],source_size=list(Image.open(src).size),source_sha256=sha(src),
             runtime='game/assets/textures/decals_v1/'+item['filename'],runtime_size=list(im.size),runtime_sha256=sha(out),
             native_alpha=receipt['transparent'],manual_text_edits=[],processing=notes,derived=derived,
             generation_receipt=str(meta.relative_to(BASE)).replace('\\','/'),reference_paths=receipt.get('reference_paths',[]),
             alpha_range=[int(a[:,:,3].min()),int(a[:,:,3].max())] if im.mode=='RGBA' else None,
             horizontal_seam_error=int(np.abs(a[:,0].astype(int)-a[:,-1].astype(int)).max()) if id in ('grime_streak_coping','grime_base_dirt') else None))
    if missing and not args.partial: raise RuntimeError('Missing generation: '+', '.join(missing))
    data={'schema':1,'updated_at':datetime.now(timezone.utc).isoformat(),'spec':'GENERATION_SPEC.md','spec_sha256':sha(BASE/'GENERATION_SPEC.md'),'status':'generated_pending_visual_validation','count':len(assets),'missing':missing,
          'tool':'built-in image_gen.imagegen','license':{'commercial_game_use':True,'repository_source_storage':True,'basis':'OpenAI Terms of Use, Content/Ownership: user owns output as between user and OpenAI, to extent permitted by law; not a CC0 dedication or exclusivity guarantee. No third-party image inputs used.','url':'https://openai.com/policies/terms-of-use/','accessed':'2026-10-28'},'assets':assets}
    dump(BASE/'provenance.json',data);dump(DEST/'manifest.json',{'schema':1,'provenance':'../../../../assets/environment/alley_decals_v1/provenance.json','assets':assets})
    font=ImageFont.truetype('C:/Windows/Fonts/malgun.ttf',17)
    for kind in sorted(set(a['kind'] for a in assets)):
        group=[a for a in assets if a['kind']==kind];cols=2 if kind=='sign' else 4;cw=540 if kind=='sign' else 280;ch=155 if kind=='sign' else 320
        sheet=Image.new('RGB',(cw*cols,ch*((len(group)+cols-1)//cols)),(43,46,51));draw=ImageDraw.Draw(sheet)
        for i,a in enumerate(group):
            x=(i%cols)*cw;y=(i//cols)*ch
            thumb=Image.open(ROOT/a['runtime']).convert('RGBA');thumb.thumbnail((cw-24,ch-50))
            # Neutral background, preserves visibility of both white and dark decoration.
            tile=Image.new('RGBA',thumb.size,(128,128,128,255));tile.alpha_composite(thumb)
            sheet.paste(tile.convert('RGB'),(x+(cw-thumb.width)//2,y+7+(ch-50-thumb.height)//2))
            draw.text((x+10,y+ch-34),a['id'],font=font,fill='white')
        sheet.save(REPORT/f'{kind}_contact.png')
    print(json.dumps({'packaged':len(assets),'missing':missing,'runtime_bytes':sum((ROOT/a['runtime']).stat().st_size for a in assets)}))
if __name__=='__main__':main()
