(async()=>{
 const assert=(ok,message)=>{if(!ok)throw new Error(message)};
 document.querySelectorAll('.reveal').forEach(el=>el.classList.add('visible'));
 const overflow=()=>assert(document.documentElement.scrollWidth<=innerWidth+2,`Overflow at ${innerWidth}`);
 overflow();assert(document.querySelectorAll('h1').length===1,'One heading');
 assert(!/Android|iOS|mobiele applicatie|\u2014/i.test(document.body.innerText),'Desktop-only copy without em dash');
 assert(document.querySelectorAll('.download-row').length===2,'macOS and Windows downloads');
 for(const link of document.querySelectorAll('a[href^="#"]'))assert(document.querySelector(link.getAttribute('href')),`Missing anchor ${link.hash}`);
 const images=[...document.images].filter(img=>img.getAttribute('src'));
 await Promise.all(images.map(async img=>{img.loading='eager';await img.decode()}));
 assert(images.every(img=>img.naturalWidth>0),'All images loaded');
 assert(images.every(img=>!/northstar|desktop-record|desktop-result|desktop-tasks|\/ios\//i.test(img.src)),'No invented app screen images');
 assert(document.querySelector('.brand img').src.includes('assets/thoughtvault-mark.png'),'Actual app logo');
 assert(document.querySelector('.signature img').src.includes('assets/yinga-logo.svg'),'Official Yinga logo');
 for(const step of ['0','1','2','3']){
  document.querySelector(`[data-step-button="${step}"]`).click();
  assert(document.querySelector('.motion-demo').dataset.step===step,'Selected animation step');
  assert(document.querySelectorAll('.chapter-scene.is-active').length===1,'One animation scene active');
  assert(document.querySelector('.motion-demo').dataset.playing==='false','Manual step pauses playback');overflow();
 }
 const first=document.querySelector('[data-step-button="0"]');first.click();first.focus();first.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowRight',bubbles:true}));assert(document.activeElement.dataset.stepButton==='1','Keyboard animation navigation');
 for(const key of ['sales','meeting','idea']){document.querySelector(`[data-profile="${key}"]`).click();assert(document.querySelector('#profile-output').children.length===3,'Profile output');overflow()}
 for(const key of ['cloud','local']){document.querySelector(`[data-mode="${key}"]`).click();assert(document.querySelector(`[data-mode="${key}"]`).getAttribute('aria-pressed')==='true','Processing choice');overflow()}
 assert(document.querySelectorAll('.feature-item').length===16,'All sixteen benefits');
 for(const key of ['process','work','control','capture']){
  document.querySelector(`[data-category="${key}"]`).click();const panel=document.querySelector(`#features-${key}`);
  assert(!panel.hidden&&panel.querySelectorAll('.feature-item').length===4,'Category content');
  const item=panel.querySelector('details');item.querySelector('summary').click();assert(item.open,'Benefit opens');overflow();item.querySelector('summary').click();
 }
 const category=document.querySelector('[data-category="capture"]');category.focus();category.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowDown',bubbles:true}));assert(document.activeElement.dataset.category==='process','Keyboard categories');document.querySelector('[data-category="capture"]').click();
 const faq=document.querySelector('.faq details');faq.querySelector('summary').click();assert(faq.open,'FAQ opens');faq.querySelector('summary').click();
 for(const button of document.querySelectorAll('[data-image]')){button.click();const dialog=document.querySelector('#image-dialog');await dialog.querySelector('img').decode();assert(dialog.open,'Real screenshot enlargement opens');const r=dialog.getBoundingClientRect();assert(r.left>=-2&&r.right<=innerWidth+2&&r.top>=-2&&r.bottom<=innerHeight+2,'Image dialog fits');dialog.querySelector('button').click();assert(!dialog.open,'Enlargement closes')}
 if(innerWidth<768){const toggle=document.querySelector('.menu-toggle');toggle.click();assert(toggle.getAttribute('aria-expanded')==='true'&&!document.querySelector('#mobile-menu').inert,'Menu opens');toggle.click();assert(document.querySelector('#mobile-menu').inert&&document.body.style.overflow==='','Menu closes')}
 document.querySelector('[data-step-button="0"]').click();document.activeElement.blur();scrollTo({top:0,behavior:'instant'});
 return {passed:true,viewport:[innerWidth,innerHeight],benefits:16,checks:'actual logos and app captures, no em dash, four motion scenes, keyboard, profiles, processing, all features, FAQ, image dialog, navigation, overflow'};
})()
