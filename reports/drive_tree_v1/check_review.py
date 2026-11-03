from pathlib import Path
from html.parser import HTMLParser
import json,re
p=Path(__file__).with_name('review.html')
text=p.read_text(encoding='utf-8')
class Links(HTMLParser):
    def __init__(self):super().__init__();self.paths=[];self.cards=[]
    def handle_starttag(self,tag,attrs):
        a=dict(attrs)
        self.paths.extend(a[k] for k in ['src','href'] if k in a)
        if 'data-card' in a:self.cards.append(a)
links=Links();links.feed(text)
missing=[r for r in links.paths if not (p.parent/r).exists()]
for c in links.cards:
    q=p.parent/'review/models'/f"{c['data-card']}{c['data-suffix']}.jpg"
    if not q.exists():missing.append(str(q))
assert not missing,missing
assert not re.findall(r'__\w+__',text)
(p.parent/'review_script_check.js').write_text(text.split('<script>')[1].split('</script>')[0],encoding='utf-8')
cap=json.loads((p.parent/'review/capture.json').read_text())
for s in cap['sequences']:
    for frame in range(s['frames']):assert (p.parent/'review'/s['id']/f'{frame:03d}.jpg').is_file()
print('REVIEW_LINKS_OK',len(links.paths)+len(links.cards),'links',len(cap['sequences']),'complete sequences')
