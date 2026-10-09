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
const sidebar=document.querySelector('.sidebar');
if(Math.abs(box(sidebar).w-238)>1)throw Error('Sidebar differs from macOS 238pt');
if(bar){
 const workspace=main.querySelector('.studio-workspace'),wr=box(workspace),br=box(bar),inspector=main.querySelector('.studio-inspector');
 const bottom=wr.h<720?20:37;
 if(Math.abs(wr.y+wr.h-br.y-br.h-bottom)>1)throw Error('Studio bar displaced from native bottom inset');
 if(br.h!==90)throw Error('Studio bar differs from macOS 90pt');
 if(box(inspector).x>wr.x&&Math.abs(box(inspector).w-309)>1)throw Error('Inspector differs from macOS 309pt');
 const wave=box(main.querySelector('.studio-wave')),transport=box(main.querySelector('.studio-transport'));
 if(wave.y+wave.h>transport.y+1)throw Error('Waveform overlaps transport');
}
// Native Home keeps a 200pt greeting and 301pt recording card; notes scroll below them.
const greeting=main.querySelector('.thoughtvault-welcome'),record=main.querySelector('.thoughtvault-new-recording');
if(greeting&&box(greeting).h!==200)throw Error('Home greeting lost native density');
if(record&&box(record).h<301)throw Error('Home recording card too short');
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
 for size in ['640x560','900x560','1200x800']:
  run([['tab',tab],['viewport',size],['goto',url+'#/recording'],['snapshot','-i'],['js',"[...document.querySelectorAll('.studio-inspector button')].at(-1).click()"],['snapshot','-i']])
  output=run([['tab',tab],['js',"""JSON.stringify((()=>{
const dialog=document.querySelector('.studio-dialog'),list=dialog?.querySelector('.card-static > div:last-child');
if(!list)throw Error('Missing saved recording list');
list.replaceChildren(...Array.from({length:12},(_,i)=>{const row=document.createElement('div');row.textContent='Fictieve opname '+i;row.style.height='70px';return row;}));
if(dialog.scrollHeight>dialog.clientHeight+1)throw Error('Nested dialog scrollbar');
if(list.scrollHeight<=list.clientHeight)throw Error('List cannot scroll');
const close=dialog.querySelector('header button').getBoundingClientRect();
if(close.top<0||close.bottom>innerHeight)throw Error('Close action clipped');
return {viewport:[innerWidth,innerHeight],listHeight:list.clientHeight,content:list.scrollHeight};})())"""]])
  print('saved recordings',size,output.split('[js]')[-1].strip(),flush=True)
 print('PASS: 36 route/viewport/scale density measurements and 3 single-owner recording dialogs')
finally:run([['closetab',tab]])
