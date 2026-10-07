const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];
const icon = name => `<svg aria-hidden="true"><use href="#${name}"/></svg>`;
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
const animate = element => { if (!reducedMotion.matches) element.animate([{opacity:0,transform:'translateY(8px)'},{opacity:1,transform:'translateY(0)'}],{duration:550,easing:'cubic-bezier(.32,.72,0,1)'}); };

const features = [
['mic','Neem het hele gesprek mee.','Microfoon, systeemgeluid of allebei. Voor fysieke meetings en videocalls, met pauze en hervatten wanneer je dat nodig hebt.'],
['note','Transcript én gestructureerde notulen.','Lees terug wat er gezegd is en pak de kern erbij. Van samenvatting tot besluiten en actiepunten, in de vorm die jij kiest.'],
['sliders','Een profiel voor iedere situatie.','Stel structuur, taal en toon in. Maak eigen profielen voor een salesgesprek, teamoverleg, interview of uitgebreide samenvatting.'],
['clock','Neem ook zonder verbinding op.','Audio wordt lokaal opgeslagen. Wachtende uploads hervatten wanneer je weer online bent, terwijl je opname beschikbaar blijft.'],
['calendar','Je agenda als startpunt.','Koppel je agenda en zie aankomende gesprekken. Op macOS helpt vergader- en videocall-detectie je herinneren om op te nemen.'],
['share','Deel in het formaat dat past.','Exporteer naar PDF, Word, Markdown, HTML of platte tekst. Neem je kennis mee naar documenten en tools die je al gebruikt.'],
['search','Van losse gesprekken naar kennis.','Zoek je notulen terug en organiseer ze met titels en tags. Bewaar waardevolle inzichten bij elkaar, klaar voor het volgende overleg.'],
['refresh','Blijf zelf aan het stuur.','Bewerk het verslag of laat het opnieuw genereren met een ander profiel. Verwerk bewaarde audio opnieuw als je een nieuw resultaat nodig hebt.'],
['video','Ook bestaande audio en video.','Importeer een opname. Met ingeschakelde YouTube-transcriptie kun je ook een videolink laten uitwerken naar tekst en notulen.'],
['desktop','Cloud of lokale AI: jouw keuze.','Gebruik serververwerking of kies lokale transcriptie en AI via een geschikte provider. Apple Intelligence, Ollama en LM Studio worden ondersteund.'],
['people','Gebouwd voor je organisatie.','Beheer deelnemers, geef gebruikers toegang en werk met uitnodigingscodes. Beheerders houden grip op accounts en de inrichting.'],
['share','Rechtstreeks naar je Obsidian-vault.','Stel de koppeling in en laat nieuwe notities en notulen automatisch als Markdown opslaan. Haal een in Obsidian bewerkte versie weer op in ThoughtVault.'],
['clock','Bedien je opname zonder te zoeken.','Op macOS gebruik je de menubalk, globale sneltoetsen en een zwevende opnamewidget. Houd het gesprek in beeld, ook buiten het hoofdvenster.'],
['note','Leg ook de snelle gedachte vast.','Spreek een korte notitie in of voeg tijdens een opname een eigen aantekening toe. Ook kleine inzichten krijgen een plek.'],
['share','Werk meerdere resultaten in één keer weg.','Verwerk opnames via de wachtrij en exporteer meerdere notulen tegelijk. Handig na een dag met meer dan één gesprek.'],
['shield','Toegang en gegevens onder controle.','Tweefactorauthenticatie, gegevensexport en accountverwijdering. Op macOS kun je ook gebruikmaken van biometrische toegang.']
];
const categories = {capture:[0,3,8,13],process:[1,2,7,9],work:[4,6,11,14],control:[5,10,12,15]};
$('#feature-grid').innerHTML = Object.entries(categories).map(([key,indices]) => `<div id="features-${key}" role="tabpanel" aria-labelledby="category-${key}" ${key==='capture'?'':'hidden'}>${indices.map(i=>{const [glyph,title,copy]=features[i];return `<details class="feature-item"><summary>${icon(glyph)}<span>${title}</span><span class="plus" aria-hidden="true">+</span></summary><p>${copy}</p></details>`;}).join('')}</div>`).join('');
function chooseCategory(key) {
  $$('[data-category]').forEach(button=>{const active=button.dataset.category===key;button.setAttribute('aria-selected',active);button.tabIndex=active?0:-1;});
  $$('.capability-panels [role=tabpanel]').forEach(panel=>panel.hidden=panel.id!==`features-${key}`);
  animate($(`#features-${key}`));
}
$$('[data-category]').forEach(button=>button.addEventListener('click',()=>chooseCategory(button.dataset.category)));
function keyboardChoices(container,selector) {
  container.addEventListener('keydown',event=>{
    if(!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown','Home','End'].includes(event.key))return;
    const choices=[...container.querySelectorAll(selector)],index=choices.indexOf(document.activeElement);if(index<0)return;
    event.preventDefault();const next=event.key==='Home'?0:event.key==='End'?choices.length-1:(index+(['ArrowRight','ArrowDown'].includes(event.key)?1:-1)+choices.length)%choices.length;
    choices[next].click();choices[next].focus();
  });
}
keyboardChoices($('.capability-tabs'),'[data-category]');

const profiles={
 meeting:{title:'Een helder plan voor de pilot.',intro:'De pilot start volgende maand. Het team bereidt de planning en eerste concepten voor.',items:['Besluit: de pilot start volgende maand.','Sophie werkt de planning uit.','Jeroen maakt de eerste concepten.']},
 sales:{title:'Van klantvraag naar voorstel.',intro:'De klant wil starten met een pilot. Planning en concepten vormen de basis voor het voorstel.',items:['Behoefte: snel beginnen met een pilot.','Afspraak: planning en concepten voorbereiden.','Vervolg: vrijdag samen de uitwerking bespreken.']},
 idea:{title:'Een idee om verder te brengen.',intro:'Begin klein met een pilot en werk het idee samen uit. De eerste concepten maken het concreet.',items:['Het idee: volgende maand een pilot starten.','Uitwerken: planning en eerste concepten.','Volgende stap: samen bespreken op vrijdag.']}
};
function chooseProfile(key){const profile=profiles[key];$('#profile-title').textContent=profile.title;$('#profile-intro').textContent=profile.intro;$('#profile-output').innerHTML=profile.items.map(item=>`<div>${icon('check')}<span>${item}</span></div>`).join('');$$('[data-profile]').forEach(button=>button.setAttribute('aria-pressed',button.dataset.profile===key));animate($('.result-paper'));}
$$('[data-profile]').forEach(button=>button.addEventListener('click',()=>chooseProfile(button.dataset.profile)));chooseProfile('idea');
const modes={local:['Dicht bij je eigen gegevens.','Met lokale transcriptie én lokale AI blijft de verwerking op je eigen computer.'],cloud:['Laat de cloud voor je werken.','Audio en transcript worden naar de gekozen server of provider gestuurd. Je volgt de voortgang in de app.']};
$$('[data-mode]').forEach(button=>button.addEventListener('click',()=>{const [title,copy]=modes[button.dataset.mode];$('#mode-copy').innerHTML=`<h3>${title}</h3><p>${copy}</p>`;$$('[data-mode]').forEach(other=>other.setAttribute('aria-pressed',other===button));animate($('#mode-copy'));}));

// A single visible, pausable sequence. No audio is recorded or played.
const demo=$('.motion-demo'),scenes=$$('[data-scene]'),steps=$$('[data-step-button]');
$('.audio-wave').innerHTML=Array.from({length:43},(_,i)=>`<i style="--h:${8+Math.round(Math.abs(Math.sin(i*1.73))*Math.sin((i+1)/44*Math.PI)*65)}px;--delay:${-i*.083}s"></i>`).join('');
let step=reducedMotion.matches?3:0,elapsed=0,lastFrame=null,frame=null,inView=false,userPaused=reducedMotion.matches;
const stepDuration=3800;
function showStep(next){step=next;demo.dataset.step=String(step);scenes.forEach((scene,index)=>{scene.classList.toggle('is-active',index===step);scene.setAttribute('aria-hidden',index!==step);});steps.forEach((button,index)=>{if(index===step)button.setAttribute('aria-current','step');else button.removeAttribute('aria-current');});demo.style.setProperty('--progress',String(elapsed/stepDuration));}
function tick(now){if(lastFrame!==null)elapsed+=Math.min(now-lastFrame,100);lastFrame=now;if(elapsed>=stepDuration){elapsed-=stepDuration;showStep((step+1)%4);}demo.style.setProperty('--progress',String(elapsed/stepDuration));frame=requestAnimationFrame(tick);}
function syncPlayback(){const playing=inView&&!document.hidden&&!userPaused;demo.dataset.playing=String(playing);$('#motion-toggle').innerHTML=icon(userPaused?'play':'pause');$('#motion-toggle').setAttribute('aria-label',userPaused?'Animatie afspelen':'Animatie pauzeren');$('#motion-toggle').setAttribute('aria-pressed',String(!userPaused));if(playing&&frame===null){lastFrame=null;frame=requestAnimationFrame(tick);}else if(!playing&&frame!==null){cancelAnimationFrame(frame);frame=null;lastFrame=null;}}
$('#motion-toggle').addEventListener('click',()=>{userPaused=!userPaused;syncPlayback();});
$('#motion-replay').addEventListener('click',()=>{elapsed=0;showStep(0);userPaused=false;syncPlayback();});
steps.forEach(button=>button.addEventListener('click',()=>{elapsed=0;showStep(Number(button.dataset.stepButton));userPaused=true;syncPlayback();}));
keyboardChoices($('.demo-timeline'),'[data-step-button]');
new IntersectionObserver(entries=>{inView=entries[0].isIntersecting;syncPlayback();},{threshold:.2}).observe(demo);
document.addEventListener('visibilitychange',syncPlayback);
reducedMotion.addEventListener('change',()=>{userPaused=true;elapsed=0;showStep(reducedMotion.matches?3:step);syncPlayback();});showStep(step);syncPlayback();

const toggle=$('.menu-toggle'),menu=$('#mobile-menu');
function setMenu(open){toggle.setAttribute('aria-expanded',String(open));toggle.setAttribute('aria-label',open?'Menu sluiten':'Menu openen');menu.classList.toggle('open',open);menu.inert=!open;document.body.style.overflow=open?'hidden':'';}
toggle.addEventListener('click',()=>setMenu(toggle.getAttribute('aria-expanded')!=='true'));menu.querySelectorAll('a').forEach(link=>link.addEventListener('click',()=>setMenu(false)));$('.nav-shell .brand').addEventListener('click',()=>setMenu(false));
document.addEventListener('keydown',event=>{if(event.key==='Escape')setMenu(false);if(event.key==='Tab'&&toggle.getAttribute('aria-expanded')==='true'){const links=[toggle,...menu.querySelectorAll('a')],first=links[0],last=links.at(-1);if(event.shiftKey&&document.activeElement===first){event.preventDefault();last.focus();}else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first.focus();}}});
matchMedia('(min-width:768px)').addEventListener('change',event=>{if(event.matches)setMenu(false);});
const dialog=$('#image-dialog');
$$('[data-image]').forEach(button=>button.addEventListener('click',()=>{$('#expanded-image').src=button.dataset.image;$('#expanded-image').alt=button.dataset.imageTitle;$('#image-title').textContent=button.dataset.imageTitle;dialog.showModal();}));dialog.querySelector('button').addEventListener('click',()=>dialog.close());
if(!reducedMotion.matches){document.documentElement.classList.add('js');const observer=new IntersectionObserver(entries=>entries.forEach(entry=>{if(entry.isIntersecting){entry.target.classList.add('visible');observer.unobserve(entry.target);}}),{threshold:.08});$$('.reveal').forEach(element=>observer.observe(element));}
