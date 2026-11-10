// Real separate JS heaps; only the Tauri boundary is replaced. No support modules are mocked.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { webcrypto } from 'node:crypto';
import { build } from 'esbuild';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
// Run from windows/: node scripts/support-owner-realms.mjs (uses Vite's installed esbuild).
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const bundles = {};
for (const label of ['main', 'recording-widget']) {
  const entry = label === 'main'
    ? 'export * from "./src/services/supportOwner"; export { useSupportStore } from "./src/stores/supportStore";'
    : 'export * from "./src/services/widgetSupport"; export { initCrashReporter } from "./src/services/localCrashReporter";';
  const result = await build({ stdin: { contents: entry, resolveDir: root }, bundle: true, write: false,
    format: 'iife', globalName: 'api', platform: 'browser', metafile: true,
    plugins: [{ name: 'native-boundary', setup(b) {
      b.onResolve({ filter: /^@tauri-apps\/api\/(core|event|window)$/ }, a => ({ path: a.path, namespace: 'native' }));
      b.onLoad({ filter: /.*/, namespace: 'native' }, () => ({ contents:
        'export const invoke=globalThis.native.invoke, listen=globalThis.native.listen, emitTo=globalThis.native.emitTo; export const getCurrentWindow=()=>({label:globalThis.label});' }));
    } }] });
  if (label !== 'main') assert(!Object.keys(result.metafile.inputs).some(p => /supportStore|supportOwner|crashReporter\.ts|supportRelay|tauriCommands/.test(p)), 'widget must not load C6 or credentials/relay');
  bundles[label] = result.outputFiles[0].text;
}
const drain = async () => { for (let i = 0; i < 30; i++) await new Promise(resolve => setImmediate(resolve)); };
async function fixture() {
  const values = new Map(), credentials = new Map(), listeners = new Map(), intervals = new Set();
  const writes = [], calls = [], acks = [], reports = [], requests = [];
  let failWrite = false, failRead = false, loseAck = false, holdScrub = false, rateLimit = false;
  const held = [];
  function realm(label) {
    const context = vm.createContext({ label, console, TextEncoder, Uint8Array, crypto: webcrypto,
      btoa: s => Buffer.from(s, 'binary').toString('base64'),
      setInterval: fn => { intervals.add(fn); return fn; }, clearInterval: fn => intervals.delete(fn),
      window: { addEventListener() {} },
      localStorage: {
        getItem(key) { if (failRead) throw Error('read blocked'); return values.get(key) ?? null; },
        setItem(key, value) { assert.equal(label, 'main', 'widget storage mutation'); writes.push(label); if (failWrite) throw Error('write blocked'); values.set(key, value); },
        removeItem(key) { assert.equal(label, 'main'); values.delete(key); },
      },
      native: {
        async listen(name, callback) { const key = label + ':' + name; listeners.set(key, callback); return () => { if (listeners.get(key) === callback) listeners.delete(key); }; },
        async emitTo(target, name, payload) {
          if (name === 'support-widget-failure') requests.push(structuredClone(payload));
          if (name === 'support-widget-ack') { acks.push(structuredClone(payload)); if (loseAck) { loseAck = false; throw Error('lost ACK'); } }
          listeners.get(target + ':' + name)?.({ payload: structuredClone(payload) });
        },
        async invoke(command, args) {
          calls.push([label, command]);
          if (label !== 'main') { assert.equal(command, 'log_write', 'widget credential/relay/native work'); return; }
          if (command === 'log_scrub') { if (holdScrub) await new Promise(resolve => held.push(resolve)); return args.text; }
          if (command === 'log_tail') return '';
          if (command === 'log_write') return;
          if (command === 'get_app_version') return '1.0';
          if (command === 'get_system_specs') return { cpu: 'test', memory_gb: 8, os_version: 'test' };
          if (command === 'load_credential') return credentials.get(args.key) ?? null;
          if (command === 'store_credential') { credentials.set(args.key, args.value); return; }
          if (command === 'proxy_request') {
            const path = new URL(args.request.url).pathname;
            if (path.endsWith('/installations')) return { status: 201, body: '{}' };
            if (path.endsWith('/unread-count')) return { status: 200, body: '{"data":{"count":0}}' };
            assert(path.endsWith('/reports')); reports.push(JSON.parse(args.request.body));
            return rateLimit ? { status: 429, body: '{}', headers: { 'Retry-After': '60' } } : { status: 200, body: '{}' };
          }
          throw Error('Unexpected native command: ' + command);
        },
      },
    });
    context.window.localStorage = context.localStorage;
    vm.runInContext(bundles[label], context);
    return context.api;
  }
  const main = realm('main'), widget = realm('recording-widget');
  main.useSupportStore.getState().setIdentity('Test', 'test@example.invalid');
  let stop = main.startSupportOwner(); await main.requireSupportOwner();
  return { main, widget, values, credentials, writes, calls, acks, reports, requests, intervals,
    failWrite: value => { failWrite = value; }, failRead: value => { failRead = value; },
    loseAck: () => { loseAck = true; }, hold: () => { holdScrub = true; },
    release: () => { holdScrub = false; held.splice(0).forEach(resolve => resolve()); },
    rateLimit: () => { rateLimit = true; }, tick: async () => { for (const fn of [...intervals]) fn(); await drain(); },
    replay: async payload => { listeners.get('main:support-widget-failure')?.({ payload: structuredClone(payload) }); await drain(); },
    stop: () => stop(), restart: async () => { stop = main.startSupportOwner(); await main.requireSupportOwner(); },
    close: () => { stop(); assert.equal(intervals.size, 0, 'sender timer leaked'); },
  };
}
// Race widget automatic handoff with main manual report, initial registration and queue cleanup.
{
  const f = await fixture(); f.loseAck();
  const handoff = f.widget.handoffWidgetFailure('pause_failed');
  const manual = f.main.useSupportStore.getState().submitManual('BUG', 'Manual test');
  await drain(); assert.equal(f.reports.length, 2); assert.equal(f.main.useSupportStore.getState().queue.length, 0);
  await f.tick(); assert.equal(await handoff, true); assert.equal(await manual, 'sent');
  assert.equal(f.requests[0].id, f.requests[1].id); assert.equal(f.reports.length, 2, 'lost ACK retried a sent report');
  assert.equal(f.calls.filter(([, c]) => c === 'store_credential').length, 1);
  assert.equal(f.calls.filter(([, c]) => c === 'proxy_request').length, 4); // register, two reports, unread
  f.close();
}
// Consent is rechecked after asynchronous scrubbing, before any enqueue/registration.
{
  const f = await fixture(); f.hold(); const p = f.widget.handoffWidgetFailure('resume_failed'); await drain();
  f.main.useSupportStore.getState().setAutoReport(false); f.release(); await drain();
  assert.equal(await p, true); assert.equal(f.acks[0].outcome, 'discarded'); assert.equal(f.reports.length, 0); assert.equal(f.credentials.size, 0); f.close();
}
for (const failure of ['failWrite', 'failRead']) {
  const f = await fixture(); f[failure](true); const p = f.widget.handoffWidgetFailure('pause_failed'); await drain();
  assert.equal(f.acks.length, 0); assert.equal(f.reports.length, 0);
  f[failure](false); await f.tick(); assert.equal(await p, true); assert.equal(f.requests[0].id, f.requests[1].id); f.close();
}
// Disposed owner's pending work stays durable; replacement recognizes that same ID.
{
  const f = await fixture(); f.hold(); const p = f.widget.handoffWidgetFailure('pause_failed'); await drain(); f.stop(); f.release(); await drain();
  assert.equal(f.acks.length, 0); assert.equal(f.reports.length, 0);
  assert.equal(JSON.parse(f.values.get('support-store')).state.queue.length, 1);
  await f.restart(); await f.tick(); assert.equal(await p, true); assert.equal(f.reports.length, 1); f.close();
}
// A throttled report remains queued and opt-out removes it through main alone.
{
  const f = await fixture(); f.rateLimit(); const p = f.widget.handoffWidgetFailure('pause_failed'); await drain(); assert.equal(await p, true);
  assert.equal(f.main.useSupportStore.getState().queue.length, 1); await f.main.useSupportStore.getState().flushQueue(); assert.equal(f.reports.length, 1);
  f.main.useSupportStore.getState().setAutoReport(false); assert.equal(f.main.useSupportStore.getState().queue.length, 0); f.close();
}
// Five attempts preserve one incident ID and report lack of confirmed delivery.
{
  const f = await fixture(); f.stop(); const p = f.widget.handoffWidgetFailure('pause_failed'); await drain();
  for (let i = 0; i < 5; i++) await f.tick(); assert.equal(await p, false);
  assert.equal(f.requests.length, 5); assert.equal(new Set(f.requests.map(r => r.id)).size, 1); f.close();
}
// Explicit limits: after 256 later IDs or an owner restart, flushed IDs have no tombstone.
{
  const f = await fixture();
  const first = f.widget.handoffWidgetFailure('pause_failed'); await drain(); assert.equal(await first, true);
  const original = f.requests[0];
  for (let i = 0; i < 256; i++) { const p = f.widget.handoffWidgetFailure('resume_failed'); await drain(); assert.equal(await p, true); }
  await f.replay(original); assert.equal(f.reports.length, 258, 'evicted ACK history must not imply exactly-once');
  f.stop(); await f.restart(); await f.replay(original); assert.equal(f.reports.length, 259, 'restart has no durable transfer tombstone'); f.close();
}
console.log('PASS: isolated main/widget realms, real C6 persistence/credentials/relay path at fake native boundary; ACK loss, consent, storage failure, disposal, 429 and timeout');
