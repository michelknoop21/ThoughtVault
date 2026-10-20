// Run against the public landing page: gstack browse eval scripts/check-website-ui.js.
return (async () => {
  const assert = (condition, message) => { if (!condition) throw new Error(message); };
  const $ = selector => document.querySelector(selector);
  const wait = () => new Promise(resolve => setTimeout(resolve, 350));
  const mobile = innerWidth <= 767;
  assert(document.documentElement.scrollWidth <= innerWidth, 'Horizontal overflow');
  assert($('#notulen').compareDocumentPosition($('#de-app')) & Node.DOCUMENT_POSITION_FOLLOWING, 'Output must precede recording details');
  assert($('.hero-copy .access-note').textContent.includes('tarieven'), 'Access and pricing missing from opening');
  assert($('.hero-copy .primary').hash === '#notulen', 'Primary action must lead to result');
  assert($('.motion-demo').parentElement === $(mobile ? '#notulen' : '.hero-grid'), 'Demo is in the wrong responsive location');
  if (mobile) {
    const art=$('.mobile-hero-art').getBoundingClientRect();
    const copy=$('.hero-copy>p').getBoundingClientRect();
    const actions=$('.hero .actions').getBoundingClientRect();
    assert(art.height>=220 && art.top>=copy.bottom && art.bottom<=actions.top, 'Mobile hero mark missing or overlapping copy/actions');
  } else {
    assert(getComputedStyle($('.mobile-hero-art')).display==='none', 'Mobile hero art duplicated on desktop');
  }
  const requests = [...document.querySelectorAll('.download-row')];
  assert(requests.length === 2 && requests.every(a => a.protocol === 'mailto:' && a.textContent.includes('per e-mail')), 'Platform requests must explain email destination');
  assert($('.email-help').textContent.includes('Je verstuurt'), 'Email handoff needs explicit instructions');
  assert($('.platform-comparison tbody').rows.length === 5, 'Platform comparison missing');
  assert($('#notulen .section-copy').compareDocumentPosition($('.result-illustration')) & Node.DOCUMENT_POSITION_FOLLOWING, 'Result controls must precede output in reading order');
  const luminance = color => color.match(/[\d.]+/g).slice(0,3).map(Number).map(n=>n/255).map(n=>n<=.04045?n/12.92:((n+.055)/1.055)**2.4).reduce((sum,n,i)=>sum+n*[.2126,.7152,.0722][i],0);
  for (const [text, background] of [['.vault-route>span', '#notulen'], ['.demo-timeline button>span', mobile ? '.motion-demo' : 'body']]) {
    const a=luminance(getComputedStyle($(text)).color), b=luminance(getComputedStyle($(background)).backgroundColor);
    assert((Math.max(a,b)+.05)/(Math.min(a,b)+.05)>=4.5, 'Audited text contrast below AA');
  }
  for (const [profile, title] of [['sales', 'Van klantvraag'], ['idea', 'Een idee'], ['meeting', 'Een helder plan']]) {
    $(`[data-profile="${profile}"]`).click();
    assert($('#profile-title').textContent.startsWith(title), 'Profile output did not update');
    assert($(`[data-profile="${profile}"]`).getAttribute('aria-pressed') === 'true', 'Profile state missing');
  }
  for (const button of document.querySelectorAll('[data-step-button]')) {
    button.click(); await new Promise(resolve => setTimeout(resolve, 900));
    const scene=$('.chapter-scene.is-active').getBoundingClientRect();
    const canvas=$('.motion-canvas').getBoundingClientRect();
    assert(scene.top >= $('.demo-top').getBoundingClientRect().bottom, 'Demo overlaps its controls');
    assert(scene.bottom <= canvas.bottom + 1, 'Demo content exceeds canvas');
    assert(canvas.bottom <= $('.demo-timeline').getBoundingClientRect().top, 'Demo overlaps step navigation');
    for (const child of $('.chapter-scene.is-active').children) {
      const rect=child.getBoundingClientRect();
      assert(rect.top >= scene.top - 1 && rect.bottom <= scene.bottom + 1, 'Demo text escapes scene');
    }
  }
  window.scrollTo({top: 300, behavior: 'instant'}); await wait();
  assert($('.nav-shell').classList.contains('compact'), 'Header did not compact');
  const headerHeight = $('.nav-shell').getBoundingClientRect().height;
  assert(headerHeight <= 68, 'Header still oversized');
  for (const link of document.querySelectorAll('.nav-shell .brand,.footer-bottom a')) {
    const rect=link.getBoundingClientRect();
    assert(rect.height>=44 && rect.width>=44, 'Navigation/footer target smaller than 44px');
  }
  if (mobile) {
    $('.menu-toggle').click();
    assert($('.menu-toggle').getAttribute('aria-expanded') === 'true', 'Menu did not open');
    $('#mobile-menu a').focus();
    document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));
    assert($('.menu-toggle').getAttribute('aria-expanded') === 'false', 'Escape did not close menu');
    assert(document.activeElement === $('.menu-toggle'), 'Escape did not restore menu focus');
  }
  $('#notulen').scrollIntoView({behavior: 'instant'}); await wait();
  assert($('#notulen').getBoundingClientRect().top >= $('.nav-shell').getBoundingClientRect().bottom, 'Result anchor obscured by header');
  assert([...document.images].every(img => img.complete && img.naturalWidth > 0), 'Image failed to load');
  assert($('.nav-shell .brand img').getBoundingClientRect().width>=42 && $('.brand img').currentSrc.endsWith('.png'), 'Original logo must remain readable in compact navigation');
  return {passed: true, viewport: [innerWidth, innerHeight], headerHeight, resultPageY: $('#profile-title').getBoundingClientRect().top + scrollY, checks: 'reading order, AA contrast, 44px targets, menu focus restoration, original readable logo, profiles, access, platform table, header, anchor, images, overflow'};
})()
