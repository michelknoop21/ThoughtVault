import subprocess,json,re
from pathlib import Path
root=Path(__file__).resolve().parents[3]
b=str(Path.home()/'.claude/skills/gstack/browse/dist/browse')
p=subprocess.run([b,'newtab','http://127.0.0.1:1442/desktop-review.html','--json'],cwd=root/'windows',text=True,capture_output=True,check=True)
tab=str(json.loads(p.stdout)['tabId'])
def call(cmds):
 p=subprocess.run([b,'chain'],input=json.dumps([['tab',tab]]+cmds),text=True,capture_output=True,check=True,cwd=root/'windows')
 assert 'ERROR:' not in p.stdout,p.stdout
 return p.stdout
def click(label):
 s=call([['snapshot','-i']]);refs=[r for r,t in re.findall(r'(@e\d+) \[button\] "([^"]+)"',s) if t==label];assert refs,(label,s)
 call([['click','main button.btn-accent']]) if label=='Volgende' else call([['click',refs[0]]])
measure="JSON.stringify((()=>{const bad=[...document.querySelectorAll('main input,main button,main select,main textarea')].filter(e=>e.getClientRects().length).filter(e=>e.getBoundingClientRect().right>innerWidth+2);if(bad.length)throw Error('Clipped controls');return {width:innerWidth,clipped:0};})())"
try:
    for size in ['640x560','900x560','1200x800']:
     call([['viewport',size],['goto','http://127.0.0.1:1442/desktop-review.html?qa=settings#/settings'],['snapshot','-i']])
     for name in ['Algemeen','Verwerking','Notulen','Agenda','Obsidian','Account','Geavanceerd']:
      click(name);print(name,call([['js',measure]]).split('[js]')[-1].strip())
    call([['viewport','640x560'],['goto','http://127.0.0.1:1442/desktop-review.html?qa=onboarding#/onboarding'],['snapshot','-i']])
    for step in range(6):
     print('onboarding',step,call([['js',measure]]).split('[js]')[-1].strip())
     if step<5:click('Overslaan' if step==4 else 'Volgende')
    print('PASS: 21 settings tab/viewport combinations and 6 onboarding steps')
finally:
    call([["closetab",tab]])
