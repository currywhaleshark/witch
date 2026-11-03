
const LABELS={"guillotine": "낙하 단두대", "guillotine_saw": "회전 톱날형", "guillotine_lock": "고정 단두대", "compound_executor": "복합 집행기"};
const EVENTS={guillotine:[[0,'처음'],[.67,'조립 완료'],[1.12,'낙하'],[1.3,'바닥 도달']],guillotine_saw:[[0,'처음'],[.67,'조립 완료'],[1.7,'톱날 하강'],[2.6,'바닥 도달']],guillotine_lock:[[.25,'구속구만 생성'],[.58,'고정 완료'],[.92,'본체 조립'],[1.3,'조립 완료'],[1.7,'낙하 완료']],compound_executor:[[.9,'문 닫기'],[1.5,'압착'],[1.8,'프레스 상승'],[2.05,'톱 진입 시작'],[2.6,'톱 진입 완료']]};
const asset=document.querySelector('#asset'),frame=document.querySelector('#frame'),pic=document.querySelector('#motion-image'),play=document.querySelector('#play'),speed=document.querySelector('#speed'),clock=document.querySelector('#clock'),stage=document.querySelector('#stage'),moments=document.querySelector('#moments');
let running=false,elapsed=0,last=0;
function phase(id,t){if(t>3.35)return '소멸 완료';if(t>2.85)return '부품 소멸';if(id==='guillotine_lock'){if(t<.28)return '구속구만 생성';if(t<.56)return '구속구 닫힘';if(t<.60)return '고정 완료 · 본체는 아직 없음';if(t<1.25)return '고정 유지 · 나머지 본체 조립';if(t<1.4)return '조립 완료';if(t<1.64)return '칼날 낙하';return '칼날 바닥 도달';}if(id==='compound_executor'){if(t<.65)return '부품 조립';if(t<1.05)return '문 닫힘';if(t<1.45)return '프레스 압착';if(t<1.55)return '압착 유지';if(t<1.92)return '프레스 상승 · 톱 대기';if(t<2.1)return '프레스 상승 중 톱 진입';if(t<2.45)return '프레스 복귀 · 톱 진입';return '톱 진입 완료';}if(t<.65)return '부품 조립';if(t<1)return '작동 대기';if(id==='guillotine_saw')return t<2.5?'회전 톱날 하강':'톱날 바닥 도달';return t<1.24?'칼날 낙하':'칼날 바닥 도달';}
function draw(){const n=Number(frame.value),t=n/24;pic.src=`review/compare_${asset.value}/${String(n).padStart(3,'0')}.jpg`;pic.alt=`${LABELS[asset.value]}: 왼쪽 수정 v2, 오른쪽 이전 v1, ${t.toFixed(2)}초`;clock.textContent=`${t.toFixed(2)}초 / 3.96초`;stage.textContent=phase(asset.value,t);}
function stop(){running=false;play.textContent='재생';elapsed=0;}
function jump(t){stop();frame.value=Math.round(t*24);draw();}
function choose(){stop();frame.value=0;moments.replaceChildren();for(const [t,label] of EVENTS[asset.value]){const b=document.createElement('button');b.type='button';b.textContent=label;b.onclick=()=>jump(t);moments.append(b);}draw();}
asset.onchange=choose;frame.oninput=()=>{stop();draw();};play.onclick=()=>{running=!running;play.textContent=running?'일시정지':'재생';};document.querySelector('#restart').onclick=()=>jump(0);
document.addEventListener('visibilitychange',()=>{if(document.hidden)stop();});
function tick(now){if(running){elapsed+=Math.min(.1,(now-last)/1000)*Number(speed.value);const steps=Math.floor(elapsed*24);if(steps){elapsed-=steps/24;frame.value=(Number(frame.value)+steps)%96;draw();}}last=now;requestAnimationFrame(tick);}
choose();jump(14/24);requestAnimationFrame(tick);
