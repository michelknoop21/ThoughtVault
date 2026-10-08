"""Measure desktop density using the real components with synthetic data."""
import json, subprocess, re
from pathlib import Path
root=Path(__file__).resolve().parents[3]
browse=str(Path.home()/'.claude/skills/gstack/browse/dist/browse')
url='http://localhost:1442/desktop-review.html'
def run(commands):
 p=subprocess.run([browse,'chain'],input=json.dumps(commands),cwd=root/'windows',text=True,capture_output=True,check=True)
 assert 'ERROR:' not in p.stdout,p.stdout
 return p.stdout
p=subprocess.run([browse,'newtab',url,'--json'],cwd=root/'windows',text=True,capture_output=True,check=True)
tab=str(json.loads(p.stdout)['tabId'])
measure="""JSON.stringify((()=>{
const main=document.querySelector('main'),logo=document.querySelector('.brand-footer-logo'),label=document.querySelector('.brand-footer-text-compact');
const box=e=>{const r=e.getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height,visible:r.bottom>0&&r.top<innerHeight}};
const lr=box(logo),line=parseFloat(getComputedStyle(label).lineHeight);
if(lr.h>line*1.5+2)throw Error('Footer logo dominates credit: '+lr.h+'px against '+line+'px text line');
if(document.documentElement.scrollWidth>innerWidth+2)throw Error('Page overflow');
const owners=[...main.querySelectorAll('*')].filter(e=>e.clientHeight&&e.scrollHeight>e.clientHeight+2&&['auto','scroll'].includes(getComputedStyle(e).overflowY)).map(e=>({name:e.className,view:e.clientHeight,content:e.scrollHeight}));
const headings=[...main.querySelectorAll('h1,h2,h3')].filter(e=>e.getClientRects().length).map(e=>({text:e.textContent,...box(e)}));
const firstData=main.querySelector('.thoughtvault-note-row,.tl-item,.person-row,.settings-group,.task-card,.studio-workspace');
const tabs=main.querySelector('.settings-tabs'),bar=main.querySelector('.studio-controlbar');
if(location.hash==='#/'&&firstData&&box(firstData).y+box(firstData).h>innerHeight+2)throw Error('First useful Home note not fully visible: '+box(firstData).y);
return {logical:[innerWidth,innerHeight],dpr:devicePixelRatio,zoom:visualViewport.scale,raster:[innerWidth*devicePixelRatio,innerHeight*devicePixelRatio],safeArea:'0; browser fixture',textSize:getComputedStyle(main).fontSize,logo:lr,scrollOwners:owners,headings,firstData:firstData?box(firstData):null,fixedControlHeight:bar?box(bar).h:0,settingsTabsHeight:tabs?box(tabs).h:0};})())"""
try:
 for size,scale in [('640x560','1'),('900x560','1'),('1280x800','1'),('1440x900','1'),('1920x1080','1'),('1440x900','2')]:
  for route in ['/','/recording','/tasks','/transcripts','/people','/settings']:
   run([['tab',tab],['viewport',size,'--scale',scale]])
   tabs=subprocess.run([browse,'tabs'],cwd=root/'windows',text=True,capture_output=True,check=True).stdout
   tab=re.search(r'→ \[(\d+)\]',tabs)[1]
   capture='/tmp/thoughtvault-density-'+size+'-'+scale+'x-'+(route.strip('/') or 'home')+'.png'
   output=run([['tab',tab],['goto',url+'?density=1#'+route],['snapshot','-i'],['screenshot',capture],['js',measure]])
   data=json.loads(output.split('[js]')[-1].strip());data['screenshot']=capture
   print(route,json.dumps(data),flush=True)
 print('PASS: 36 route/viewport/scale density measurements')
finally:run([['closetab',tab]])
