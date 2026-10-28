"""Record the per-asset ImageGen brief from GENERATION_SPEC.md (no API calls)."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'assets/environment/alley_decals_v1'
COMMON = '''Use case: historical-scene. Asset type: individual game decoration texture.
Flat front-on orthographic texture, absolutely no perspective, camera angle, tilt or lens distortion.
Early-2000s South Korean old hillside neighborhood, worn but lived-in, realistic surface detail,
muted colors. Neutral even overcast diffuse color, no cast shadows, no directional highlights,
no vignette, no sunset color, no glow or lighting baked into the image. This is a flat albedo asset,
not an object photographed in a room. No people, wall/background context, brand/logo/watermark,
real places, real phone numbers, QR codes, modern road address plates, English or extra text.
Only the explicitly requested Korean text is allowed, with exact spelling and punctuation.
Unspecified small text areas must be blank, never filled with pseudo-writing.
Use off-white around #EBEBEB and near-black around #141414 for the object (pure white only in mask backgrounds).
Generate exactly ONE asset, never a contact sheet, collage, multiple views or layout with labels.'''
items=[]
def add(name, kind, detail, text=(), size=(512,512), world=(1,1), optional=False):
    transparent = kind not in ('sign','mask')
    if kind == 'sign':
        form='''Canvas 3072x1024 pixels, landscape. Center ONE perfectly rectangular 8:1 horizontal sign board,
exactly 2560x320 pixels, with its corners at (256,352) and (2816,672). All outside pixels flat #808080.
Thin dull aluminium edging, perfectly straight edges and square corners, no depth or mounting hardware.
All typography strictly inside the central 70% width; each outer 15% plain board color.
Main title fills 55-65% of board height, subtitle 15-20%, on a separate line below.
Bold Korean gothic or rounded gothic like old acrylic/vinyl signs. Large readable lettering.
Subtle dust and restrained age, no neon or emitted light.'''
    elif kind == 'poster':
        form='''Canvas 1536x2048 pixels. A single portrait A-series sheet (1:1.414 width:height),
centered with transparent margin, genuinely transparent RGBA background. Paper almost flat,
slight wrinkles, a few torn corners and tape pieces, no drop shadow. Strong bold title and color masses.
Typography must be spelled exactly; no body text unless explicitly supplied. No wall behind the paper.'''
    elif kind == 'mask':
        form='''Canvas 1536x1536 pixels. GRAYSCALE MASK ONLY: pure white #FFFFFF background and
black/gray marks. No colored surface, no material background, no 3D depth, no text or frame.
Black is strongest stain, gray is partial opacity. Softly fade marks to white with 8% empty margins.
For a horizontally seamless asset, left/right edges must match, overriding side margins;
top/bottom should still be white. Do not tile other assets.'''
    else:
        form='''Canvas 1536x1536 pixels. One isolated flat asset centered on genuinely transparent RGBA background,
8% transparent margin, no shadow or backing plane. Keep the stated object proportions.
Do not paint a checkerboard or chroma-key background. Crisp detail with natural worn edges.'''
    items.append(dict(id=name, filename=name+'.png', kind=kind, transparent=transparent,
                      required_text=list(text), runtime_size=list(size), world_size=list(world),
                      optional=optional, prompt=COMMON+'\n'+form+'\nSubject: '+detail))

signs=[
 ('laundry','언덕세탁소','드라이 · 수선 · 운동화','navy blue board, off-white letters'),
 ('hardware','제일철물','열쇠 · 공구 · 페인트 · 보일러','desaturated red board, off-white letters'),
 ('super','행운슈퍼','생활용품 · 과일 · 아이스크림','off-white board, dark green letters'),
 ('salon','단골미용실','파마 · 커트 · 염색','pale pink board, deep purple letters'),
 ('realty','행복복덕방','전세 · 월세 · 매매 · 재개발 상담','muted yellow board, near-black letters'),
 ('snack','엄마분식','떡볶이 · 순대 · 튀김 · 김밥','muted orange board, off-white letters'),
 ('pharmacy','언덕약국','','off-white board, dark green letters; a large single Chinese character 藥 to the left of the title, within the central 70%; no subtitle'),
 ('comics','별빛만화','만화 · 소설 · 비디오 대여','purple board, muted yellow letters'),
 ('stationery','희망문방구','학용품 · 완구 · 뽑기','muted yellow board, deep red letters'),
 ('stationery_faded','희망문방구','학용품 · 완구 · 뽑기','the same muted yellow and red stationery sign, now sun-faded, some vinyl peeling and restrained rust runoff, all letters still readable')]
for name,title,subtitle,color in signs:
    text=[title]+([subtitle] if subtitle else ['藥'])
    add('sign_'+name,'sign',f'{color}. Main exact title: "{title}". '+(f'Exact subtitle: "{subtitle}".' if subtitle else ''),text,(1024,128),(4.8,.6))

posters=[
 ('redevelop_notice','재개발 조합 총회 안내','off-white official assembly notice, near-black bold Korean title arranged in two readable lines, simple thin rules, one red square seal made of abstract geometric lines with NO seal text. Blank lower body'),
 ('demolition','철거 예정 · 출입 금지','muted yellow warning paper, bold near-black and restrained brick-red heading, no hazard stripes beyond simple border'),
 ('tutoring','수학 · 영어 과외','off-white handwritten flyer, title exact. Bottom 7 tear-off strips, each prints ONLY the fictional unusable phone number 02-012-0345. No other text'),
 ('moving','이삿짐 · 용달','off-white flyer with blue title, a small simple side-view unbranded moving truck icon, blank body'),
 ('lost_cat','고양이를 찾습니다','off-white flyer, large black heading and a simple grayscale drawing of a black cat below, blank body'),
 ('volunteer','여름방학 환경정화 봉사활동 모집','off-white public office announcement with muted green rules, bold title across 3 lines, exact bottom issuer ○○동사무소. Blank body'),
 ('circus','대 서커스 공연','slightly faded colorful printed poster, large exact heading above a simple illustrated circus tent and juggling balls; no troupe name, no people, no other text'),
 ('torn_layers','','a small cluster of several overlapping torn paper layers in off-white, muted yellow and blue. No intact writing or pseudo-writing. Use blank paper fragments and torn color-block remnants only')]
for name,title,detail in posters:
    txt=[title] if title else []
    if name=='tutoring': txt+=['02-012-0345']
    if name=='volunteer': txt+=['○○동사무소']
    add('poster_'+name,'poster',detail+(' Exact title: "'+title+'".' if title else ''),txt,(256,362),(.297,.42) if name in ('tutoring','moving','lost_cat') else (.42,.594))

for name,txt,detail,world in [
 ('spray_demolish','철거','desaturated brick-red hand-sprayed Korean word 철거 surrounded by one rough spray circle, a few drips, overspray',(1.2,.8)),
 ('spray_x','','one large desaturated brick-red spray-painted X, overspray and a few drips',(1,1)),
 ('spray_vacant','공가','near-black hand-sprayed Korean word 공가, natural overspray',(1,.6)),
 ('spray_no_entry','출입금지','off-white hand-sprayed Korean word 출입금지 for a dark shutter; no dark outline',(1.2,.5)),
 ('stencil_no_parking','주차금지','off-white painted stencil word 주차금지 with visible bridge gaps in the strokes, a little paint wear, no outline',(1.4,.45)),
 ('spray_number','17-3','near-black handwritten spray demolition management number 17-3, no extra characters',(.6,.4))]:
    add(name,'spray',detail+f'. Shape width:height {world[0]}:{world[1]}.', [txt] if txt else [],(512,round(512*world[1]/world[0])),world)

masks=[
 ('grime_streak_coping',(1.5,.8),'rain runoff below a wall coping: many vertical streaks darker near top, thinning and fading downward. Seamless horizontally; 5% white padding top and bottom'),
 ('grime_streak_window',(1.2,1.4),'exactly two irregular water stain trails descending from the two ends of an invisible window sill. No window or sill object'),
 ('grime_rust_run',(.6,1),'narrow irregular rust runoff from an invisible iron hinge, strong origin tapering into thin drips'),
 ('grime_base_dirt',(2,.4),'low band of muddy splashes and moss staining at the foot of an invisible wall, dense at bottom and fading upward. Seamless horizontally; 5% white padding top and bottom'),
 ('grime_soot',(1.2,1.2),'irregular soft feathery soot smear left by a rag creature, restrained organic edges, soft transition to white'),
 ('floor_patch',(2,1.4),'a rectangular asphalt repair patch mask, mostly dark mid-gray block with subtly ragged but clearly defined boundary, soft one-pixel edge, no scene or surface'),
 ('floor_oil',(.8,.6),'small irregular thin oil stain mask, sparse soft gray edge and uneven dark middle'),
 ('floor_cracks',(2,2),'fine sparse branching network of cracks, mostly very thin black lines on white, no slab coloring or solid dark areas'),
 ('floor_puddle_stain',(1.6,1),'irregular dried puddle outline ring, thin pale gray mineral rim, mostly white inside and outside')]
for name,world,detail in masks:
    w,h=world
    size=(512,round(512*h/w)) if w>=h else (round(512*w/h),512)
    add(name,'mask',detail+f'. Mark overall width:height {w}:{h}.',(),size,world)
add('floor_manhole','color','circular flat dark cast-iron manhole cover, plain generic radial cast pattern, exact raised central Korean text "오수". Top-down albedo only; subtle relief represented without directional lighting. No surrounding pavement.', ['오수'],(256,256),(.8,.8))
add('floor_drain','color','long rectangular dark iron rainwater grate width:height 0.4:1.0, evenly spaced straight bars, dark openings, no words or maker logo. Strictly top-down flat albedo, no pavement.',(),(256,640),(.4,1))

for name,text,detail,world in [
 ('plate_dog','개조심','off-white flat rectangular tin plate with muted red exact text 개조심, a few tiny rust spots',(.3,.2)),
 ('plate_lot_number','산 12-3','old lot-number plate, dark blue background and off-white exact text 산 12-3, no neighborhood name',(.25,.12)),
 ('plate_no_flyers','광고물 사절','small paper rectangle taped by two tape pieces, black marker exact text 광고물 사절',(.25,.1)),
 ('box_meter','','flat front face of a small old gray electrical meter cabinet with little glass viewing window, abstract unlabelled meter dial, no text or numbers or brand',(.35,.5)),
 ('box_milk','','flat front face of small old generic milk delivery box attached beside a gate, a simple flap slot, muted gray blue paint, no label or brand',(.3,.3))]:
    w,h=world
    add(name,'plate',detail+f'. Object width:height {w}:{h}.',[text] if text else [],(256,round(256*h/w)),world)

add('erosion_crack_slab','erosion','a torn irregular opening in gray asphalt revealing very old gray stone paving slabs beneath, isolated top-down flat color decal. Width:height 3:2. Dark fissure, subdued detail, no glowing rim, no red/orange/teal areas.',(),(768,512),(3,2),True)
add('erosion_gear_reveal','erosion','one COMPLETE circular weathered brass gear with 6 large intact teeth, viewed top-down. It belongs beneath cracked gray stone paving; generate only the intact wheel, no stone overlapping it, so the game can rotate it behind a separate slab-opening layer. Dull aged brass, no glow, red, orange or turquoise. All 6 teeth and whole circle visible.',(),(512,512),(2.4,2.4),True)
add('erosion_blue_scorch','erosion','an irregular scorch mark left by pale-blue flame, color only with a softly lighter center #9FD8FF, no emitted glow, no actual flames, dark ash feathering at edges. Predominantly cool gray and faint pale blue, avoid teal #8DD8C4 and warm warning reds.',(),(512,512),(1.6,1.6),True)

extra_start=len(items)
for name,top,title,phone,color,ratio in [
 ('realty','복덕방','행복부동산','☎ 0233-0467','off-white board, deep blue letters',4),
 ('pharmacy','藥','언덕약국','','off-white board, dark green letters',4),
 ('gukbap','원조','순대국전문','☎ 0234-0870','navy blue board, off-white letters',4),
 ('sundries','','잡화','','muted red board, off-white letters',3),
 ('fortune','철학관','사주 · 작명','','muted yellow board, near-black letters',4),
 ('inn_broken','','언덕여인숙','','off-white board, dark red letters. The acrylic has one irregular broken hole; the character 인 is MISSING, leaving ONLY faint glue residue in its position. All other characters remain intact',4)]:
    text=[x for x in (top,title,phone) if x]
    add('sign_v_'+name,'vertical',f'ONE thin rectangular acrylic projecting sign front face, width:height 1:{ratio}, {color}. Small top header EXACTLY "{top}" (empty if not given). Main large Korean title EXACTLY "{title}", written VERTICALLY one syllable per row, dot retained between 사주 and 작명. Small horizontal bottom phone EXACTLY "{phone}" (empty if not given). Thin aluminum perimeter. No thickness, brackets, extra edges, shadow or tilt. Native board height at least 2048 pixels. Canvas portrait 1024x3072, board centered with 8% margins; outside flat #808080 gray.',text,(128,128*ratio),(.6,.6*ratio))
    items[-1]['transparent']=False

for name,text,detail in [
 ('realty',['부동산','전세 · 월세 · 매매'],'off-white metal sign face, red and blue lettering, rusty straight metal edging. Large VERTICAL title 부동산. Small horizontal footer 전세 · 월세 · 매매'),
 ('snack',['분식','떡볶이 1,000 · 순대 1,500 · 김밥 1,000'],'off-white metal sign face. Large title 분식. Beneath it the hand-corrected price list EXACTLY 떡볶이 1,000 · 순대 1,500 · 김밥 1,000; arrange one food and its price on each of three lines')]:
    add('aframe_'+name,'aframe','Flat FRONT PANEL ONLY of a pavement A-frame sign, width:height 1:2. Do not draw legs or perspective. '+detail,text,(256,512),(.5,1))
for name,text,color in [
 ('oppose','강제 철거 결사 반대','off-white cloth and desaturated red letters'),
 ('rights','세입자 생존권 보장하라','muted yellow cloth and black letters'),
 ('union','언덕길 구역 주택재개발 조합 설립 인가','off-white cloth and blue letters; add the exact small footer - 조합 - at the right end'),
 ('no_trespass','이주 완료 · 빈집 무단 출입 금지','muted yellow cloth and desaturated red letters')]:
    txt=[text]+(['- 조합 -'] if name=='union' else [])
    add('banner_'+name,'banner',f'ONE long cloth banner width:height 5.5:1, front-on. {color}. Exact large Korean text "{text}" in brush-style printed lettering, centered in one row. Subtle faded ink and very shallow sag, restrained wrinkles, one torn corner, four short tie strings at the corners. No other text. Native banner width at least 2048 pixels; landscape canvas 3072x1024.',txt,(1024,192),(5,.9))
for name,text,detail in [
 ('for_rent','임대 문의 ☎ 0233-0158','off-white vinyl lettering, 임대 large at top and 문의 ☎ 0233-0158 smaller below'),
 ('closing_sale','폐업 정리 · 전품목 할인','off-white and desaturated red vinyl lettering, title 폐업 정리 and subtitle · 전품목 할인'),
 ('open','영업중','off-white vinyl letters inside a thin rounded muted-red rectangular border')]:
    add('glass_'+name,'glass','Only flat glass-door vinyl sticker lettering, no glass, reflection, background or backing plate. Width:height 0.8:1. '+detail+'. Exact combined text: '+text,[text],(256,320),(.8,1))
for name,txt,detail,world in [
 ('boarded_window',['공가'],'two or three overlapping plywood boards nailed across an invisible square window frame, near-black spray word 공가 on one board. Straight front view, no wall or background',(1.2,1.2)),
 ('boarded_door',[],'two rough timber battens nailed as a large X across an invisible tall doorway. No door, no frame, no wall; only timber X and nail heads',(1,2)),
 ('glass_broken',[],'one square pane of cracked translucent gray glass, one irregular broken-away corner HOLE fully transparent, all crack lines slender. Glass occupies most of the square. No opaque backing, frame, reflections, text or wall',(1,1)),
 ('grille_window',[],'a flat square old Korean window security grille, wavy flower-pattern steel bars with peeling off-white paint and tiny rust spots. All spaces BETWEEN bars must be completely transparent. No window or glass',(1.2,1.2)),
 ('grille_window_green',[],'a flat square old Korean window security grille, looping diamond and wave pattern distinct from a flower pattern; peeling dull green paint and tiny rust spots. All spaces BETWEEN bars must be completely transparent. No window or glass',(1.2,1.2)),
 ('wall_gas_pipe',[],'two narrow dull yellow vertical gas pipes with simple elbows and one small unlabelled gas meter, isolated flat front elevation. No wall, brand, labels or extra pipes',(1,1.6)),
 ('wall_cables',[],'a horizontal bundle of five sagging narrow near-black electric wires attached with three small wall clips. Width:height 2:0.6; same heights of cable endpoints at left and right for horizontal repeat. No wall or poles',(2,.6))]:
    kind='window' if name.startswith(('boarded','glass_broken','grille')) else 'fixture'
    add(name,kind,detail,txt,(512,round(512*world[1]/world[0])),world)
add('floor_arrow','mask','worn painted straight forward arrow mask, width:height 0.8:2.4, strong arrowhead, peeling gaps; black arrow on pure white, black means paint in engine. No pavement.',(),(256,768),(.8,2.4))
add('floor_text_slow','mask','exact Korean road paint word 천천히, broad simple worn brush-gothic, width:height 2:0.9. Black letters on pure white mask, black means paint in engine. No pavement, no additional text.',['천천히'],(512,230),(2,.9))
add('pole_ad_strip','pole','one narrow partly torn vertical paper advertisement strip for a utility pole, width:height 1:4. Exact dark blue text 이삿짐 · 용달 written vertically. Only fictional unusable number 02-012-0345 at bottom. Flat unwrapped paper, no pole or cylindrical bending.',['이삿짐 · 용달','02-012-0345'],(128,512),(.25,1))
add('pole_number_plate','pole','one flat small rectangular utility-pole number plate, muted yellow board, near-black exact text 언덕 123, arranged on two lines. No other numbers or text. Width:height 2:3.',['언덕 123'],(128,192),(.2,.3))
for item in items[extra_start:]:
    item['spec_section']=13
    if item['kind'] not in ('mask','vertical'):
        item['transparent']=False
        item['prompt'] += '\nBackground override: OPAQUE solid pure magenta #FF00FF behind the asset, no shadows. Never use magenta in the object. This overrides all previous transparent-background instructions. Keep open gaps magenta too for later chroma key.'

for folder in ['source','raw','generation']:
    (BASE/folder).mkdir(parents=True,exist_ok=True)
data={'schema':1,'spec':'GENERATION_SPEC.md','status':'generation_in_progress','tool':'image_gen.imagegen (built-in)','model_version':'not exposed by built-in tool','seed':None,'asset_count':len(items),'assets':items}
(BASE/'generation/requests.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
print(json.dumps({'requests':len(items),'path':str(BASE/'generation/requests.json')}))
