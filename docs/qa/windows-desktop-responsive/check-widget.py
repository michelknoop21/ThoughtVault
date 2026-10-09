"""Synthetic native-sized widget: no capture, files or provider requests."""
import json, subprocess, re
from pathlib import Path
browse=str(Path.home()/'.claude/skills/gstack/browse/dist/browse')
url='http://localhost:1442/desktop-review.html?scenario=widget'
tab=str(json.loads(subprocess.check_output([browse,'newtab',url,'--json'],text=True))['tabId'])
def run(commands):
 output=subprocess.check_output([browse,'chain'],input=json.dumps(commands),text=True)
 assert 'ERROR:' not in output,output
 return output
try:
 for scale in ['1','2']:
  run([['tab',tab],['viewport','470x60','--scale',scale]])
  tab=re.search(r'→ \[(\d+)\]',subprocess.check_output([browse,'tabs'],text=True))[1]
  output=run([['tab',tab],['goto',url],['snapshot','-i'],['screenshot','/tmp/thoughtvault-widget-'+scale+'x.png'],['js',"""JSON.stringify((()=>{
const box=s=>document.querySelector(s).getBoundingClientRect();
const pill=box('.widget-pill'),wave=box('.widget-waveform'),pause=box('.widget-btn'),stop=box('.widget-btn-stop');
if(pill.width!==470||pill.height!==60||wave.width!==120||wave.height!==32||pause.width!==32||pause.height!==32)throw Error('Widget differs from native logical dimensions');
if(stop.right>470||stop.bottom>60||document.documentElement.scrollWidth>470)throw Error('Widget action clipped');
return {width:pill.width,height:pill.height,dpr:devicePixelRatio,wave:[wave.width,wave.height]};})())"""]])
  print(output.split('[js]')[-1].strip())
 print('PASS: native widget geometry at 1x and 2x')
finally:run([['closetab',tab]])
