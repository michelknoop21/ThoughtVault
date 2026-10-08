"""Person sheets must show every field and the save action without scrolling."""
import json, subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[3]
browse = str(Path.home()/'.claude/skills/gstack/browse/dist/browse')
url = 'http://localhost:1442/desktop-review.html#/people'
tab = str(json.loads(subprocess.run([browse, 'newtab', url, '--json'], text=True, capture_output=True, check=True).stdout)['tabId'])
def call(commands):
    result = subprocess.run([browse, 'chain'], input=json.dumps([['tab', tab]] + commands), text=True, capture_output=True, check=True)
    assert 'ERROR:' not in result.stdout, result.stdout
    return result.stdout
measure = '''JSON.stringify((()=>{
const panel=document.querySelector('dialog > [role=dialog]');
const body=panel?.children[1];
if(!body)throw Error('Missing person form');
if(body.scrollHeight>body.clientHeight+1)throw Error('Person form requires scrolling');
const controls=[...panel.querySelectorAll('input,select,button')];
if(controls.length!==8)throw Error('Missing person controls');
for(const e of controls){const r=e.getBoundingClientRect();if(r.top<0||r.bottom>innerHeight||r.left<0||r.right>innerWidth)throw Error('Clipped person control');}
return {viewport:[innerWidth,innerHeight],bodyHeight:body.clientHeight,scrollHeight:body.scrollHeight,controls:controls.length};})())'''
try:
    for size in ['640x560','900x560','1200x800']:
        call([['viewport',size],['goto',url],['snapshot','-i'],['click','.page-header button[title="Persoon toevoegen"]']])
        print(size, call([['js',measure]]).split('[js]')[-1].strip())
        call([['press','Escape']])
    print('PASS: all person fields and actions fit in 3 viewport sizes')
finally:
    call([['closetab',tab]])
