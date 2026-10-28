"""Verify the saved delivery and build a local, read-only art review page."""
from pathlib import Path
import json, hashlib, html
from datetime import datetime, timezone
from PIL import Image
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'assets/environment/alley_decals_v1'
DEST=ROOT/'game/assets/textures/decals_v1'
REPORT=ROOT/'reports/alley_decals_v1'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def write(p,d): p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')

def main():
    prov=read(BASE/'provenance.json'); requests=read(BASE/'generation/requests.json')['assets']
    gpu=read(REPORT/'review/result.json'); nav=read(REPORT/'map_nav/result.json')
    checks=[]; warnings=[]
    def check(ok,label):
        checks.append({'check':label,'passed':bool(ok)})
    check(len(prov['assets'])==69 and {a['id'] for a in requests}=={a['id'] for a in prov['assets']},'all 69 specified assets delivered, including optional erosion')
    runtime=[]
    for a in prov['assets']:
        source=BASE/a['source'];raw=BASE/a['raw'];out=ROOT/a['runtime'];im=Image.open(out)
        check(sha(source)==sha(raw)==a['source_sha256'],a['id']+' selected source is byte-for-byte raw generation')
        check(sha(out)==a['runtime_sha256'] and list(im.size)==a['runtime_size'],a['id']+' runtime hash and dimensions')
        arr=np.array(im)
        if a['kind']=='mask':
            check(im.mode=='L',a['id']+' grayscale mask')
            derived=ROOT/a['derived'][0]['path'];rgba=np.array(Image.open(derived))
            check(np.array_equal(rgba[:,:,3],255-arr),a['id']+' alpha is the inverse mask')
            check(sha(derived)==a['derived'][0]['sha256'],a['id']+' derived file hash')
        elif im.mode=='RGBA':
            check(arr[:,:,3].min()==0,a['id']+' transparent background or holes')
        if a['id'] in ('grime_streak_coping','grime_base_dirt','wall_cables'):
            check(np.array_equal(arr[:,0],arr[:,-1]),a['id']+' identical horizontal boundary')
        if a['kind'] in ('sign','vertical'):
            board=a['processing'][0]['native_board_size']
            long=board[0 if a['kind']=='sign' else 1]
            if long<2048:
                warnings.append({'id':a['id'],'constraint':'native board long edge >=2048px','actual_px':long,'handling':'Original retained unchanged. Board cropped/resampled to the specified runtime dimensions. Native source-size requirement remains below target.'})
        for p in [out]+[ROOT/d['path'] for d in a.get('derived',[])]:
            check('mipmaps/generate=true' in p.with_suffix('.png.import').read_text(encoding='utf-8'),p.name+' mipmap import setting')
            runtime.append(p)
    check(gpu['passed'] and not gpu['failures'],'actual GPU review and integration assertions')
    check(not nav['failures'],'existing map navigation/combat regressions')
    for phase in ['import','review','map_nav']:
        ex=read(REPORT/phase/'execution.json')
        check(ex['exit_code']==0,phase+' engine exited successfully')
    protected={}
    for file,old in read(REPORT/'before_hashes.json').items():
        if file=='game/scripts/field_map.gd': continue
        protected[file]={'before':old,'after':sha(ROOT/file),'unchanged':old==sha(ROOT/file)}
        check(protected[file]['unchanged'],file+' unchanged')
    check(all(Image.open(REPORT/'review'/f).size==(1280,800) for f in gpu['captures']),'all actual scene captures are 1280x800')
    visual={'reviewed_at':datetime.now(timezone.utc).isoformat(),'method':'Agent visually inspected all 69 generations, selected edits, category sheets and actual GPU captures; no OCR or user art approval claimed.',
      'corrections':{'spray_demolish':'Regenerated on magenta after native alpha lost lettering.','plate_dog':'Regenerated without native-alpha halo.','sign_stationery_faded':'ImageGen edit retains the original red subtitle.','plate_no_flyers':'ImageGen edit removes unwanted final period.','sign_v_inn_broken':'ImageGen edit moves the missing 인 to the fourth syllable slot.','aframe_snack':'ImageGen edit places middle-dot separators after prices.'},
      'observations':['Large shop titles, demolition paint and banners remain legible at native 1.75x framing. Small body text and number plates are texture detail at this scale.','Generated mechanical recess uses an independent full gear texture under a separate stone-aperture shader; it is static, with an angle parameter reserved for later animation.','No real storefront photographs were supplied to generation. Blank pseudo-text areas, invented shop names and requested fictional numbers were used.','Source board dimensions have the explicitly listed deviations; the runtime dimensions are verified. Minor material-relief shading remains in generated albedo.','Reusable catalog includes six unused horizontal sign variants and any poster not selected by this map seed. Not every catalog image is placed in this single trial map.']}
    write(REPORT/'visual_review.json',visual)
    validation={'passed':all(c['passed'] for c in checks),'checks':checks,'failures':[c['check'] for c in checks if not c['passed']],
      'source_asset_count':69,'runtime_png_count':len(runtime),'runtime_png_bytes':sum(p.stat().st_size for p in runtime),'raw_candidate_count':len(list((BASE/'raw').glob('*.png'))),
      'source_native_size_deviations':warnings,'protected_files':protected,'gpu_checks':len(gpu['checks']),'map_regression_checks':len(nav['checks']),
      'gpu_scope':gpu['scope'],'status':'runtime_verified_native_source_size_deviations_documented','user_art_approval':False}
    write(REPORT/'validation.json',validation)
    if not validation['passed']: raise RuntimeError(validation['failures'])
    prov['status']=validation['status'];prov['validation']='../../../reports/alley_decals_v1/validation.json'
    prov['source_native_size_deviations']=warnings
    prov['visual_corrections']=visual['corrections']
    write(BASE/'provenance.json',prov)
    mib=validation['runtime_png_bytes']/1048576
    native_note=f"간판 {len(warnings)}종은 생성된 판의 긴 변이 요청한 2048px보다 작다. 원본은 바꾸지 않았고, 판을 잘라 지정된 게임용 크기로 리샘플했다. 실제 픽셀 수는 provenance/validation에 기록했다. 원본 해상도 조건까지 충족했다고 취급하지 않는다."
    readme=f'''# 언덕길 골목 장식 v1

2026-10-28 사용자의 「그대로 시행」 요청에 따라 GENERATION_SPEC 1–8장과 진행 중 추가된 13–15장을 적용했다. **69종 원본, 게임용 PNG {len(runtime)}개(흑백 마스크의 RGBA 파생본 11개 포함)**를 제공한다. 게임용 PNG는 합계 {mib:.2f} MiB다.

- [적용 전후와 전체 이미지 검토](../../../reports/alley_decals_v1/review.html)
- [생성·가공·이용 조건·해시 기록](provenance.json)
- [저장 파일 검증](../../../reports/alley_decals_v1/validation.json)
- [GPU 통합 검사](../../../reports/alley_decals_v1/review/result.json), [기존 맵 검사](../../../reports/alley_decals_v1/map_nav/result.json)

## 보관과 재현

`source/`는 고른 생성 원본 그대로다. `raw/`에는 탈락 후보를 포함한 {validation['raw_candidate_count']}개 PNG가 남아 있다. `generation/selection.json`은 선택한 후보, 장별 receipt JSON은 실제 사용한 프롬프트와 참조 이미지 기록이다. `requests.json`은 최초 제작 지시이며 후속 수정의 실제 지시는 receipt를 우선한다. 도구는 내장 `image_gen.imagegen`; 모델 버전과 시드는 도구가 공개하지 않아 추측해 넣지 않았다. 사진 참조를 생성기에 넣지 않았다.

`python tools/package_alley_decals_v1.py`가 원본을 보존하면서 판 자르기, 마젠타 제거/가장자리 보정, 희미한 알파 잔여물 제거, 빈 캔버스 자르기, 지정 크기 축소, RGB 20–235 정리, 마스크/반복 경계와 깨진 유리 투명도를 처리한다. 글자는 수동으로 덧그리지 않았고, 잘못된 글자/구두점은 ImageGen으로 수정했다. 패키징 후에는 검증 상태가 다시 pending이 되며 아래 검사를 실행해야 한다.

```powershell
python tools/package_alley_decals_v1.py
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_alley_decals_v1.ps1 -Phase import
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_alley_decals_v1.ps1 -Phase map_nav
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_alley_decals_v1.ps1 -Phase review
python tools/finalize_alley_decals_v1.py
```

## 실제 적용 범위

장식 배치는 `game/data/maps/alley_decals_v1.json`, 구현은 `game/scripts/alley_decoration.gd`이다. 기본 맵의 치수·충돌·적 스폰은 그대로 두고 `field_map.gd`에서 호출한다. 가로 간판은 생성 이미지의 중앙 70%를 일정 폭으로 유지하고 양 끝만 가게 폭에 맞춘다. 기존 맵에서 실제 간판이 있는 네 가게는 세탁소·슈퍼·철물점·폐문방구다. 다른 여섯 가로 간판은 재사용용으로 보관한다. 돌출 간판은 상층/인접 업종 장식으로 별도 지정했다.

별도 필지 시드로 현재 영업/거주 {gpu['occupancy']['open']}필지, 폐업 {gpu['occupancy']['closed']}필지, 빈집 {gpu['occupancy']['vacant']}필지를 나눈다. 이것은 외형 분류이며 NPC·상점 기능이 아니다. 폐업/빈집의 조명을 끄고 시트지·막음판을 붙인다. 현수막은 먼 쪽 가장자리에만 배치하며 잘린 필지에서는 높이를 낮춘다. A자 다리, 간판 브래킷, 처진 전선, 기존 소품 충돌 범위 안의 상자·마대·폐목재 조각을 추가했다. 장식은 부모 필지와 함께 투명해진다. 침식의 임시 단색 사각형 표시는 새 장식으로 대체했다. 바닥 톱니는 완전한 원본 이미지와 덮개를 분리했으며 현재는 정지 상태다.

## 검증과 한계

Godot 4.6.2 Compatibility/RTX 2060 실제 GPU 검사 {len(gpu['checks'])}개, 기존 맵 검사 {len(nav['checks'])}개, 1280×800 캡처 {gpu['capture_count']}장이 통과했다. 충돌체 전체·네비메시 꼭짓점·필지 배치·전투 RNG 보존, 모든 텍스처 밉맵, 필지 알파 복귀, 평지 전환과 재로드를 검사했다. GPU stderr에는 이 환경의 `user://` 셰이더 캐시 폴더 진단이 있으며 로그를 보존했다. 렌더 오류와 테스트 실패는 없다. 전투 규칙 전체 스위트를 반복 실행한 것은 아니며 최종 아트/플레이 감각/성능 예산 승인을 뜻하지 않는다.

{native_note}

이용 조건은 [OpenAI Terms of Use — Content/Ownership](https://openai.com/policies/terms-of-use/) 기준으로 기록했다. 상업용 게임과 저장소 보관용 생성 결과이며 CC0로 표시하지 않는다. 별도 CC0 반복 표면 재질의 출처는 기존 `alley_v1/README.md`에 유지된다.
'''
    (BASE/'README.md').write_text(readme,encoding='utf-8',newline='\n')
    (DEST/'README.md').write_text('# Alley decoration textures v1\n\n69 generated decoration assets plus 11 inverse-alpha mask copies. See [source and processing provenance](../../../../assets/environment/alley_decals_v1/README.md) and [visual review](../../../../reports/alley_decals_v1/review.html). PNG import sidecars enable mipmaps. These generated assets are not labelled CC0; the existing `../alley_v1` surfaces have their own CC0 licenses.\n',encoding='utf-8',newline='\n')
    shots=[{'id':x,'label':y} for x,y in [('a_laundry','A · 세탁소 앞'),('a_stairs','A · 슈퍼와 계단'),('b_stationery','B · 폐문방구'),('b_houses','B · 주택과 철물점'),('c_erosion','C · 침식 공터')]]
    categories={'sign':'가로 간판','vertical':'돌출 간판','poster':'벽보','spray':'스프레이','mask':'얼룩·바닥 마스크','color':'맨홀·배수구','plate':'작은 표지','erosion':'침식','aframe':'입간판','banner':'현수막','glass':'유리 시트지','window':'창·막음판','fixture':'벽 설비','pole':'전봇대'}
    cards=[]
    for a in prov['assets']:
        label=' / '.join(a['required_text']) or a['id'];src='../../'+a['runtime']
        cards.append(f'<article data-kind="{a["kind"]}" data-search="{html.escape(a["id"]+" "+label)}"><a href="{src}" target="_blank"><div class="thumb"><img loading="lazy" src="{src}" alt="{html.escape(label)}"></div></a><strong>{html.escape(label)}</strong><small>{a["id"]}<br>{a["runtime_size"][0]}×{a["runtime_size"][1]} · {a["world_size"][0]}×{a["world_size"][1]}m</small></article>')
    page='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>언덕길 골목 · 장식 v1</title><style>
    :root{color-scheme:dark;font-family:"Malgun Gothic",system-ui,sans-serif;background:#161b20;color:#ecedeb}body{margin:0}main{max-width:1280px;margin:auto;padding:28px 24px 60px}h1{font-size:30px;margin:5px 0 12px}p{color:#b5bfc6;line-height:1.75}a{color:#a8d8ce}button,select,input{font:inherit;background:#252d34;color:#ecedeb;border:1px solid #515e68;border-radius:7px;padding:10px 15px}button{cursor:pointer}button[aria-pressed=true]{background:#9ecfc4;color:#122525;border-color:#9ecfc4}.controls{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin:18px 0}.viewer{margin:0;border:1px solid #3e4852;border-radius:10px;overflow:hidden;background:#10141a}.viewer img{display:block;width:100%;aspect-ratio:1.6;object-fit:contain}figcaption{padding:12px 16px;color:#bdc8d0;font-size:14px}.stats{display:flex;gap:22px;flex-wrap:wrap;border-block:1px solid #3e4852;padding:18px 0;margin:24px 0}.stats strong{color:#a8d8ce}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:16px}.grid article{border:1px solid #3e4852;border-radius:8px;padding:14px;min-width:0}.grid strong{display:block;font-size:14px;line-height:1.55;margin:12px 0}.grid small{color:#9cabb5;line-height:1.65}.thumb{height:180px;display:flex;align-items:center;justify-content:center;background:repeating-conic-gradient(#62686a 0% 25%,#73787a 0% 50%) 0/20px 20px}.thumb img{max-height:170px;max-width:100%;object-fit:contain}h2{font-size:22px;margin-top:36px}details{border:1px solid #48525c;border-radius:8px;padding:16px;margin:22px 0}summary{cursor:pointer}article[hidden]{display:none}footer{color:#9cabb5;margin-top:32px;font-size:13px}
    </style><main><p>WITCH / ENVIRONMENT ART · 2026.10.28</p><h1>언덕길 골목 장식 v1</h1><p>기존 43종 + 사진 참고 추가분 26종. 생성 간판·벽보·현수막을 시험 맵에 연결했습니다.<br>아래 이미지는 Godot 실제 캡처입니다. 기본은 선택한 1.75배 화면, 확대는 검토용입니다.</p>
    <div class="controls"><label for="scene">장소 </label><select id="scene"></select><button data-mode="after" aria-pressed="true">적용 후 · 1.75배</button><button data-mode="before" aria-pressed="false">적용 전</button><button data-mode="close" aria-pressed="false">확대 검토</button><a id="original" target="_blank">원본 크기 열기</a></div>
    <figure class="viewer"><img id="shot" alt="골목 적용 비교"><figcaption id="caption"></figcaption></figure>
    <div class="stats"><span><strong>69종</strong> 원본 보관</span><span><strong>__INSTANCES__개</strong> 장식 판</span><span><strong>__GPU__ + __NAV__</strong> 엔진 검사 통과</span><span><strong>__MIB__ MiB</strong> 게임용 PNG</span></div>
    <details><summary>적용 범위와 남은 제한</summary><p>__NATIVE__</p><p>현재 네 가게에 쓰이지 않는 여섯 가로 간판도 카탈로그에 포함했습니다. 작은 번호·벽보 본문은 확대 확인용이고 실제 화면에서는 질감으로 보입니다. 톱니 원본은 완전한 원으로 보관하며 화면에서는 판석 덮개 아래 일부가 드러납니다. 현재는 정지 상태입니다. 최종 아트·성능 예산 승인은 별도입니다.</p><p><a href="validation.json">파일 검증</a> · <a href="review/result.json">GPU 결과</a> · <a href="map_nav/result.json">기존 맵 검사</a> · <a href="../../assets/environment/alley_decals_v1/README.md">제작 기록</a></p></details>
    <h2>전체 텍스처</h2><div class="controls"><label for="kind">분류 </label><select id="kind"><option value="">전체 69종</option>__OPTIONS__</select><label for="search">검색 </label><input id="search" placeholder="문구 또는 파일 이름"></div><section class="grid">__CARDS__</section><footer>원본·프롬프트·선택 후보·가공·해시와 이용 조건은 provenance.json에 기록했습니다. 배경 투명 확인용 격자는 실제 그림에 포함되지 않습니다.</footer></main>
    <script>const shots=__SHOTS__;const scene=document.querySelector('#scene');let mode='after';scene.innerHTML=shots.map((s,i)=>`<option value="${i}">${s.label}</option>`).join('');function render(){const s=shots[Number(scene.value)],file=`review/${mode}_${s.id}.png`;document.querySelector('#shot').src=file;document.querySelector('#original').href=file;document.querySelector('#caption').textContent=`${s.label} · ${mode==='close'?'검토용 확대':mode==='before'?'장식 적용 전 / 1.75배':'장식 적용 후 / 1.75배'} · 1280×800`;document.querySelectorAll('[data-mode]').forEach(b=>b.setAttribute('aria-pressed',b.dataset.mode===mode));}scene.onchange=render;document.querySelectorAll('[data-mode]').forEach(b=>b.onclick=()=>{mode=b.dataset.mode;render()});function filter(){let kind=document.querySelector('#kind').value,q=document.querySelector('#search').value.toLowerCase();document.querySelectorAll('article').forEach(a=>a.hidden=(kind&&a.dataset.kind!==kind)||!a.dataset.search.toLowerCase().includes(q));}document.querySelector('#kind').onchange=filter;document.querySelector('#search').oninput=filter;render();</script></html>'''
    values={'__INSTANCES__':str(gpu['instances']),'__GPU__':str(len(gpu['checks'])),'__NAV__':str(len(nav['checks'])),'__MIB__':f'{mib:.2f}','__NATIVE__':html.escape(native_note),'__OPTIONS__':''.join(f'<option value="{k}">{v}</option>' for k,v in categories.items()),'__CARDS__':'\n'.join(cards),'__SHOTS__':json.dumps(shots,ensure_ascii=False)}
    for key,value in values.items(): page=page.replace(key,value)
    (REPORT/'review.html').write_text(page,encoding='utf-8',newline='\n')
    files=[BASE/'provenance.json',BASE/'README.md',DEST/'manifest.json',REPORT/'validation.json',REPORT/'visual_review.json',REPORT/'review.html',REPORT/'review/result.json',REPORT/'map_nav/result.json',ROOT/'game/scripts/alley_decoration.gd',ROOT/'game/scripts/field_map.gd',ROOT/'game/shaders/alley_gear_reveal.gdshader',ROOT/'game/data/maps/alley_decals_v1.json']+runtime+[BASE/a['source'] for a in prov['assets']]+[REPORT/'review'/f for f in gpu['captures']]
    files += [BASE/'GENERATION_SPEC.md',ROOT/'docs/godot_prototype.md',ROOT/'game/tests/map_nav.gd',ROOT/'game/tests/review_alley_decals.gd']
    files += [ROOT/'tools'/name for name in ['prepare_alley_decals_v1.py','package_alley_decals_v1.py','finalize_alley_decals_v1.py','run_alley_decals_v1.ps1']]
    files += sorted((BASE/'generation').glob('*.json')) + sorted((BASE/'raw').glob('*.png'))
    write(REPORT/'delivery_manifest.json',{'generated_at':datetime.now(timezone.utc).isoformat(),'files':[{'path':str(p.relative_to(ROOT)).replace('\\','/'),'sha256':sha(p),'bytes':p.stat().st_size} for p in files]})
    print(json.dumps({'passed':validation['passed'],'checks':len(checks),'native_size_deviations':len(warnings),'runtime_pngs':len(runtime),'runtime_mib':mib}))
if __name__=='__main__': main()
