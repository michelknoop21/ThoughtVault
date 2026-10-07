(() => {
  const visible = el => el.getClientRects().length && getComputedStyle(el).visibility !== 'hidden' && !el.closest('[inert]');
  const rect = el => { const r=el.getBoundingClientRect();return {x:Math.round(r.x),y:Math.round(r.y),width:Math.round(r.width),height:Math.round(r.height),visibleHeight:Math.round(Math.max(0,Math.min(innerHeight,r.bottom)-Math.max(0,r.top)))}; };
  const nodes=[...document.querySelectorAll('body *')].filter(visible);
  const overflow=nodes.filter(el=>{const r=el.getBoundingClientRect();return r.width>0&&(r.left < -2||r.right > innerWidth+2)}).map(el=>({tag:el.tagName,class:el.className,rect:rect(el)}));
  const scrollOwners=nodes.filter(el=>/auto|scroll/.test(getComputedStyle(el).overflowY)&&el.scrollHeight>el.clientHeight+2).map(el=>({tag:el.tagName,class:el.className,viewport:el.clientHeight,content:el.scrollHeight}));
  return {cssViewport:[innerWidth,innerHeight],dpr:devicePixelRatio,visualViewportScale:visualViewport.scale,textScale:'default browser setting',safeArea:'no display cutout in desktop browser',page:{viewport:document.documentElement.clientHeight,content:document.documentElement.scrollHeight,width:document.documentElement.scrollWidth},fixedChrome:rect(document.querySelector('.nav-shell')),landmarks:{heading:rect(document.querySelector('h1')),primaryAction:rect(document.querySelector('.hero .button')),firstVisual:rect(document.querySelector('.motion-demo'))},overflow,scrollOwners,realAppCaptureCount:document.querySelectorAll('[data-image]').length};
})()
