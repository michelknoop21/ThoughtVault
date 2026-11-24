// Run with: node scripts/tests/download-page.test.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('deploy/website/private/download.js', 'utf8');
class Element {
  constructor() { this.children = []; this.parts = {}; this.hidden = true; }
  querySelector(selector) { return this.parts[selector] ??= new Element(); }
  setAttribute(key, value) { this[key] = value; }
  replaceChildren(...children) { this.children = children; }
  addEventListener() {}
}
async function run(platform, architecture, releases, fail = false, touch = 0) {
  const elements = {};
  const document = {querySelector: key => elements[key] ??= new Element(), createElement: () => new Element()};
  await vm.runInNewContext(source, {
    document, URL, location: {href: 'https://example.test/d-private/'},
    navigator: {platform, maxTouchPoints: touch, userAgent: '', userAgentData: {platform, getHighEntropyValues: async () => ({architecture, bitness: '64'})}},
    fetch: async () => { if (fail) throw Error('offline'); return {ok: true, json: async () => releases}; },
  });
  return elements;
}
(async () => {
  const page = fs.readFileSync('deploy/website/private/index.html', 'utf8');
  const helpHref = page.match(/<a href="([^"]+)">Hulp bij installeren/);
  assert.ok(helpHref, 'Installation help link must be present');
  const helpURL = new URL(helpHref[1], 'https://example.test/d-private/');
  assert.equal(helpURL.protocol, 'mailto:', 'Installation help must use the existing support destination, not an undeployed private route');
  assert.equal(helpURL.pathname, 'sales@yinga.nl');
  assert.equal(helpURL.searchParams.get('subject'), 'Installatiehulp ThoughtVault');
  const releases = Object.fromEntries(['macos','windows_x64','windows_arm64'].map(key => [key, {version:'1.2.3', filename: 'ThoughtVault_' + key + (key === 'macos' ? '.dmg' : '.msi')}]));
  for (const [platform, architecture, expected] of [['MacIntel',null,'macOS'],['Win32','arm','Windows ARM64'],['Win32','x86','Windows x64'],['Win32',null,'Windows x64']]) {
    const e = await run(platform, architecture, releases);
    assert.equal(e['#downloads'].children[0].querySelector('h3').textContent, expected);
    assert.equal(e['#downloads']['aria-busy'], 'false');
    assert.equal(e['#downloads'].children.length, 3);
    assert.match(e['#downloads'].children[0].querySelector('a').href, /^https:\/\/example.test\/d-private\//);
  }
  const invalid = await run('Linux', null, {macos: {filename:'../secret.dmg'}});
  assert.equal(invalid['#downloads'].children.length, 0);
  const legacyMac = await run('MacIntel', null, {macos: {version:'1.0.242', filename:'TranscriptStudio-1.0.242.dmg'}, windows_x64: releases.windows_x64});
  assert.deepEqual(legacyMac['#downloads'].children.map(c => c.querySelector('h3').textContent), ['Windows x64']);
  assert.match(legacyMac['#device-note'].textContent, /TestFlight/);
  const error = await run('Linux', null, {}, true);
  assert.equal(error['#retry'].hidden, false);
  const empty = await run('Linux', null, {});
  assert.match(empty['#status'].textContent, /geen installers/);
  const ipad = await run('MacIntel', null, releases, false, 5);
  assert.doesNotMatch(ipad['#downloads'].children[0].className, /recommended/);
  const legacy = await run('Win32','x86',{windows:releases.windows_x64});
  assert.equal(legacy['#downloads'].children.length,1);
  console.log('PASS installation help destination, OS recommendations, architecture, iPad, private URLs, invalid filenames, empty/error and legacy manifest');
})();
