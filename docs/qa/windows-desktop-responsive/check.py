#!/usr/bin/env python3
"""Run with Vite on port 1438. Uses gstack browse, no extra dependencies."""
import json, os, subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[3]
browse = Path.home()/'.claude/skills/gstack/browse/dist/browse'
url = 'http://localhost:1438/desktop-review.html'
def call(commands):
    result = subprocess.run([str(browse), 'chain'], input=json.dumps(commands), text=True, capture_output=True, cwd=root/'windows', check=True)
    if 'ERROR:' in result.stdout:
        raise AssertionError(result.stdout)
    return result.stdout
result = subprocess.run([str(browse),'newtab',url,'--json'],cwd=root/'windows',text=True,capture_output=True,check=True)
tab = json.loads(result.stdout)['tabId']
measure = '''JSON.stringify((() => {
 const selector = '.app-main,.app-main-content,.page-scroll,.recording-studio,.studio-workspace,.tl-panel,.td-panel,.page-content';
 const overflow = [...document.querySelectorAll(selector)].filter(e => e.clientWidth && e.scrollWidth > e.clientWidth + 2).map(e => ({name:e.className,width:e.clientWidth,scroll:e.scrollWidth}));
 const nav = document.querySelector('.sidebar a[href="#/settings"]')?.getBoundingClientRect();
 const controls = [...document.querySelectorAll('main button,main input,main select,main textarea')].filter(e => e.getClientRects().length).map(e => ({e,r:e.getBoundingClientRect()})).filter(({r}) => r.width && (r.left < document.querySelector('main').getBoundingClientRect().left - 2 || r.right > innerWidth + 2)).map(({e,r}) => ({name:e.getAttribute('aria-label')||e.textContent,left:r.left,right:r.right}));
 const home = document.querySelector('.thoughtvault-new-recording')?.getBoundingClientRect();
 const bar = document.querySelector('.studio-controlbar')?.getBoundingClientRect();
 const studio = document.querySelector('.studio-workspace')?.getBoundingClientRect();
 const inspector = document.querySelector('.studio-inspector')?.getBoundingClientRect();
 if (overflow.length || controls.length || !nav || nav.bottom > innerHeight+2 || (bar && bar.bottom > innerHeight+2) || (studio && inspector && inspector.left === studio.left && inspector.top < studio.bottom-2)) throw new Error(JSON.stringify({overflow,controls,nav,bar,studio,inspector}));
 return {viewport:[innerWidth,innerHeight,devicePixelRatio],overflow:0,clippedControls:0,navBottom:nav.bottom,homeHeight:home?.height,recordingControlsBottom:bar?.bottom};
})())'''
try:
    for size in ['640x560','720x560','900x560','900x600','1200x800','1280x800','1440x900','1920x1080']:
        for route in ['/','/recording','/tasks','/transcripts','/profiles','/people','/settings']:
            output = call([['tab',str(tab)],['viewport',size],['goto',url+'?size='+size+'#'+route],['snapshot','-i'],['js',measure]])
            print(route,output.split('[js] ')[-1].strip())
    print('PASS: 56 route/viewport combinations, including native-caption height allowance.')
finally:
    call([['closetab',str(tab)]])
