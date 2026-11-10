# Fase d: automatisch bijwerken op Windows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** De Windows-app downloadt een gevonden update stil, installeert hem bij afsluiten als er niets loopt, kijkt elke zes uur opnieuw en heeft in Instellingen een knop "Zoek naar updates".

**Architecture:** Alle logica blijft in `windows/src/hooks/useUpdateCheck.ts`: periodiek `check()`, direct `update.download()`, een `onCloseRequested`-handler op het hoofdvenster die bij een klare download en een rustige app `preventDefault()` plus `update.install()` doet. De "bezig"-voorwaarde komt als één gedeelde functie in `recordingStore.ts`, zodat banner en hook dezelfde regel gebruiken. De knop praat met de hook via een `window`-event `tv-check-updates`.

**Tech Stack:** Tauri 2, `@tauri-apps/plugin-updater ~2.10.0`, `@tauri-apps/api ~2.10.1`, React, zustand, vitest 4.

**Spec:** `docs/plans/2026-11-10-foutrapporten-feedbackhub.md` op branch `docs/plan-foutrapporten-feedbackhub` (lezen met `git show docs/plan-foutrapporten-feedbackhub:docs/plans/2026-11-10-foutrapporten-feedbackhub.md`), hoofdstuk 2 besluit 11 en hoofdstuk 5 "Fase d", deel "Windows".

Het macOS-deel van fase d (Sparkle) is uitgesteld zolang de pilot via TestFlight loopt en valt buiten dit plan.

## Global Constraints

- Werk in een eigen worktree op een eigen branch vanaf `origin/main`: `git -C /Volumes/SSD/Projects/thoughtvault-native fetch && git -C /Volumes/SSD/Projects/thoughtvault-native worktree add ../thoughtvault-fase-d -b feat/fase-d-updates-windows origin/main`. Nooit committen op `main`: een commit daar start de releasepipeline. De hoofdwerkmap (`/Volumes/SSD/Projects/thoughtvault-native`) niet aanraken, die staat op een andere branch met open wijzigingen.
- UI-tekst Nederlands, geen em-dash of en-dash als gedachtestreepje.
- Geen nieuwe npm-pakketten en geen nieuwe crates. `@tauri-apps/plugin-updater` en `@tauri-apps/api` zitten er al in.
- Windows-checks: `cd windows && npx vitest run && npm run build` en `cd windows/src-tauri && cargo test --lib`. Zware builds en testruns via `heavy run --label <naam> -- <commando>`.
- Besluit 11 (vast): stil downloaden, installeren bij afsluiten of eerstvolgende start, nooit tijdens opnemen of verwerken. Standaard aan, schakelaar plus knop "Zoek naar updates".
- "Bezig" betekent precies wat `UpdateBanner.tsx` r.16 nu zegt: `phase !== "idle"` of een achtergrondtaak met een status buiten `completed` en `failed`.
- De bestaande terugvalroute via `releases.json` (`useUpdateCheck.ts` r.46-65) en de bestaande test daarvoor blijven werken.
- Handelingen op servers (een dev-release publiceren, iets op n8n01 lezen of schrijven) alleen na expliciet akkoord van Michel.
- Commitberichten in het Engels, in de stijl van `git log origin/main` (gebiedende wijs, hoofdletter, geen prefix verplicht), zonder AI-attributie of trailers.
- `App.tsx` wordt ook door fase c aangeraakt. Raak in `App.tsx` alleen `AppShell` (r.209-233) aan.

## Review Focus

1. Installatie bij afsluiten mislukt (handtekening ongeldig, MSI-fout): de gebruiker verwacht dat het venster toch dichtgaat, niet een app die niet meer te sluiten is. Test `closes the window when install fails` in Task 2.
2. Download mislukt of er is geen netwerk: geen foutmelding, afsluiten werkt gewoon, en de volgende controle probeert opnieuw. Test `retries a failed download on the next check` in Task 1 en `closes normally when the download failed` in Task 2.
3. Een volgende zesuurscontrole vindt dezelfde versie die al gedownload is: geen tweede download van de MSI en geen verlies van de klare download. Test `does not download the same version twice` in Task 1.
4. De gebruiker zet "Automatisch bijwerken" uit nadat de download al klaar is: bij afsluiten wordt niet geïnstalleerd. Test `does not install on close when updates are switched off` in Task 2.
5. De gebruiker klikt "Nu bijwerken" terwijl de stille download nog loopt: er start geen tweede download, de klik wacht op de lopende en installeert dan. Test `installNow waits for the running download` in Task 3.

---

## Bestanden

| Bestand | Rol |
| --- | --- |
| `windows/src/stores/recordingStore.ts` | nieuwe export `isBusy`, de enige plek voor de bezig-regel |
| `windows/src/hooks/useUpdateCheck.ts` | controle, stille download, interval, event, installeren bij afsluiten, `installNow` |
| `windows/src/hooks/__tests__/useUpdateCheck.test.tsx` | bestaande test plus de nieuwe gevallen |
| `windows/src-tauri/capabilities/default.json` | permissie `core:window:allow-destroy` |
| `windows/src/components/ui/UpdateBanner.tsx` | gebruikt `isBusy`, roept `installNow` aan, tekst bij klare download |
| `windows/src/components/ui/__tests__/UpdateBanner.test.tsx` | nieuw |
| `windows/src/components/settings/GeneralTab.tsx` | tekst "Automatisch bijwerken" en knop "Zoek naar updates" |
| `windows/src/components/settings/__tests__/GeneralTab.test.tsx` | nieuw |
| `windows/src/App.tsx` | `AppShell` geeft `downloaded` en `installNow` door aan de banner |
| `docs/AUTOMATISCHE-UPDATES.md` | nieuw gedrag en bewijs |

Bestaat een van de twee nieuwe testmappen al met een ander naamgebruik (bijvoorbeeld `UpdateBanner.test.tsx` naast de component), volg dan dat patroon.

---

### Task 1: Stille download, zesuurslus en knop-event in `useUpdateCheck`

**Files:**
- Modify: `windows/src/stores/recordingStore.ts` (export toevoegen na de store-definitie)
- Modify: `windows/src/components/ui/UpdateBanner.tsx:16` (regel vervangen door `isBusy`, zonder gedragswijziging)
- Modify: `windows/src/hooks/useUpdateCheck.ts`
- Test: `windows/src/hooks/__tests__/useUpdateCheck.test.tsx`

**Interfaces:**
- Consumes: `check()` uit `@tauri-apps/plugin-updater` geeft `Update | null`; `Update` heeft `version: string`, `download(onEvent?): Promise<void>`, `install(): Promise<void>`, `downloadAndInstall(onEvent?): Promise<void>`, `close(): Promise<void>`. `install()` gooit als `download()` niet eerst klaar is. De gedownloade bytes staan in het geheugen van het proces.
- Produces:
  - `export function isBusy(s: { phase: string; backgroundTasks: { status: string }[] }): boolean` in `recordingStore.ts`.
  - `export const UPDATE_CHECK_INTERVAL_MS = 6 * 60 * 60 * 1000;` en `export const CHECK_UPDATES_EVENT = "tv-check-updates";` in `useUpdateCheck.ts`.
  - `useUpdateCheck()` geeft `{ isUpdateAvailable: boolean; latestVersion: string | null; downloadUrl: string | null; nativeUpdate: Update | null; downloaded: boolean }`. Task 2 en 3 breiden dit uit.

- [ ] **Step 1: Worktree en uitgangssituatie**

Maak de worktree uit Global Constraints, dan `cd ../thoughtvault-fase-d/windows && npm ci`.
Run: `heavy run --label fase-d-vitest -- npx vitest run src/hooks/__tests__/useUpdateCheck.test.tsx`
Expected: 1 test PASS (`uses the existing private installer URL without doubling its origin`).

- [ ] **Step 2: Maak de mock van `check` instelbaar en schrijf de falende tests**

Vervang `vi.mock("@tauri-apps/plugin-updater", () => ({check: async () => null}))` door een `vi.hoisted` `checkMock = vi.fn(async () => null)` en mock `@tauri-apps/api/window` met `getCurrentWindow: () => fakeWindow` (`onCloseRequested: vi.fn(async (cb) => { closeHandler = cb; return () => {}; })`, `destroy: vi.fn(async () => {})`). Een helper `fakeUpdate(version)` levert `{ version, download: vi.fn(async () => {}), install: vi.fn(async () => {}), downloadAndInstall: vi.fn(async () => {}), close: vi.fn(async () => {}) }`. `fetch` in alle nieuwe tests stubben met `{ ok: false }`. In `beforeEach`: `useSettingsStore.setState({ check_for_updates: true })`, `useRecordingStore.setState({ phase: "idle", backgroundTasks: [] })`, `checkMock.mockReset()`.

```tsx
it("downloads a found update without asking", async () => {
  const u = fakeUpdate("1.0.400"); checkMock.mockResolvedValue(u);
  await render();
  expect(u.download).toHaveBeenCalledTimes(1);
  expect(u.install).not.toHaveBeenCalled();
});
it("does not check or download when updates are switched off", async () => {
  useSettingsStore.setState({ check_for_updates: false });
  await render();
  expect(checkMock).not.toHaveBeenCalled();
});
it("checks again every six hours", async () => {
  vi.useFakeTimers(); checkMock.mockResolvedValue(null);
  await render();
  await act(async () => { vi.advanceTimersByTime(UPDATE_CHECK_INTERVAL_MS - 1000); });
  expect(checkMock).toHaveBeenCalledTimes(1);
  await act(async () => { vi.advanceTimersByTime(1000); });
  expect(checkMock).toHaveBeenCalledTimes(2);
});
it("checks when tv-check-updates is dispatched", async () => {
  checkMock.mockResolvedValue(null);
  await render();
  await act(async () => { window.dispatchEvent(new Event(CHECK_UPDATES_EVENT)); });
  expect(checkMock).toHaveBeenCalledTimes(2);
});
it("checks on tv-check-updates even when updates are switched off, without downloading", async () => {
  useSettingsStore.setState({ check_for_updates: false });
  const u = fakeUpdate("1.0.400"); checkMock.mockResolvedValue(u);
  await render();
  await act(async () => { window.dispatchEvent(new Event(CHECK_UPDATES_EVENT)); });
  expect(checkMock).toHaveBeenCalledTimes(1);
  expect(u.download).not.toHaveBeenCalled();
});
it("does not download the same version twice", async () => {   // Review Focus 3
  vi.useFakeTimers();
  const first = fakeUpdate("1.0.400"), second = fakeUpdate("1.0.400");
  checkMock.mockResolvedValueOnce(first).mockResolvedValueOnce(second);
  await render();
  await act(async () => { vi.advanceTimersByTime(UPDATE_CHECK_INTERVAL_MS); });
  expect(first.download).toHaveBeenCalledTimes(1);
  expect(second.download).not.toHaveBeenCalled();
  expect(second.close).toHaveBeenCalled();
});
it("retries a failed download on the next check", async () => {   // Review Focus 2
  vi.useFakeTimers();
  const bad = fakeUpdate("1.0.400"); bad.download.mockRejectedValue(new Error("offline"));
  const good = fakeUpdate("1.0.400");
  checkMock.mockResolvedValueOnce(bad).mockResolvedValueOnce(good);
  await render();
  await act(async () => { vi.advanceTimersByTime(UPDATE_CHECK_INTERVAL_MS); });
  expect(good.download).toHaveBeenCalledTimes(1);
});
it("stops the interval and the event listener on unmount", async () => {
  vi.useFakeTimers(); checkMock.mockResolvedValue(null);
  const root = await render(); await act(async () => { root.unmount(); });
  await act(async () => { vi.advanceTimersByTime(UPDATE_CHECK_INTERVAL_MS); window.dispatchEvent(new Event(CHECK_UPDATES_EVENT)); });
  expect(checkMock).toHaveBeenCalledTimes(1);
});
```

`render()` is een helper die de bestaande `Probe`-opzet (createRoot plus act) hergebruikt en de root teruggeeft; `afterEach` doet `vi.useRealTimers()` en unmount.

- [ ] **Step 3: Draai de tests en zie ze falen**

Run: `heavy run --label fase-d-vitest -- npx vitest run src/hooks/__tests__/useUpdateCheck.test.tsx`
Expected: FAIL, onder meer op ontbrekende exports `UPDATE_CHECK_INTERVAL_MS` en `CHECK_UPDATES_EVENT` en `download` niet aangeroepen.

- [ ] **Step 4: Implementeer `isBusy` en zet de banner erop**

`isBusy` in `recordingStore.ts` met de regel uit `UpdateBanner.tsx` r.16. In de banner wordt r.16 `const busy = useRecordingStore(isBusy);`. Geen andere wijziging aan de banner in deze taak.

- [ ] **Step 5: Implementeer de controle in `useUpdateCheck.ts`**

Eén interne `runCheck()` met deze regels:
- `check()`; bij `null` niets doen.
- Is er al een update in bezit met dezelfde `version` waarvan de download loopt of klaar is: de nieuwe kandidaat `close()` en stoppen. Bij een hogere versie de oude `close()` en de nieuwe nemen.
- Download starten alleen als `useSettingsStore.getState().check_for_updates` waar is. De lopende download bewaren als promise in een ref; bij succes `downloaded` op `true`, bij een fout ref en `downloaded` leegmaken en stil blijven (geen `console.error` spam: één `console.warn`).
- De bestaande `releases.json`-terugval blijft na `check()` lopen zoals nu.
- `useEffect` op `[checkForUpdates]`: bij aan direct `runCheck()` plus `setInterval(runCheck, UPDATE_CHECK_INTERVAL_MS)`.
- Een aparte `useEffect` zonder afhankelijkheden registreert `window.addEventListener(CHECK_UPDATES_EVENT, runCheck)`, zodat de knop ook werkt als de schakelaar uit staat.
- Opruimen bij unmount: interval, listener, en `close()` op een update die nog niet gedownload is.

Bewaar update, downloadpromise en `downloaded` in refs naast de React-state, zodat Task 2 ze buiten de render kan lezen.

- [ ] **Step 6: Draai de tests**

Run: `heavy run --label fase-d-vitest -- npx vitest run src/hooks/__tests__/useUpdateCheck.test.tsx`
Expected: PASS, 9 tests (de bestaande plus 8 nieuwe).

- [ ] **Step 7: Volledige frontendcheck**

Run: `heavy run --label fase-d-vitest -- npx vitest run && heavy run --label fase-d-build -- npm run build`
Expected: alle tests PASS, build zonder TypeScript-fouten.

- [ ] **Step 8: Commit**

```bash
git add windows/src/stores/recordingStore.ts windows/src/components/ui/UpdateBanner.tsx windows/src/hooks/useUpdateCheck.ts windows/src/hooks/__tests__/useUpdateCheck.test.tsx
git commit -m "Download Windows updates silently and check every six hours"
```

---

### Task 2: Installeren bij afsluiten

**Files:**
- Modify: `windows/src/hooks/useUpdateCheck.ts`
- Modify: `windows/src-tauri/capabilities/default.json:9-34` (permissie toevoegen naast `core:window:allow-close`)
- Test: `windows/src/hooks/__tests__/useUpdateCheck.test.tsx`

**Interfaces:**
- Consumes: `isBusy` uit Task 1; refs voor update en `downloaded` uit Task 1; `getCurrentWindow()` uit `@tauri-apps/api/window` met `onCloseRequested(handler: (event: { preventDefault(): void }) => void | Promise<void>): Promise<() => void>` en `destroy(): Promise<void>`.
- Produces: geen nieuwe exports. Gedrag: bij afsluiten van het hoofdvenster, met download klaar, schakelaar aan en `isBusy` onwaar, roept de hook `preventDefault()` en `update.install()` aan. Op Windows sluit de updater daarna zelf het proces af en start de MSI in `passive`-modus (`tauri.conf.json` `plugins.updater.windows.installMode`).

- [ ] **Step 1: Stel de permissie vast**

Open `windows/node_modules/@tauri-apps/api/window.js` en zoek `onCloseRequested`. Staat daar dat de handler na afloop `this.destroy()` aanroept als het event niet is tegengehouden, dan heeft de app `core:window:allow-destroy` nodig: zonder die permissie gaat het venster na het registreren van de handler niet meer dicht. `core:window:default` in `capabilities/default.json` dekt dit niet. Noteer de gevonden regel in het commitbericht van deze taak.

- [ ] **Step 2: Schrijf de falende tests**

```tsx
async function close() { const ev = { preventDefault: vi.fn() }; await act(async () => { await closeHandler(ev); }); return ev; }

it("installs on close when the download is done and nothing is busy", async () => {
  const u = fakeUpdate("1.0.400"); checkMock.mockResolvedValue(u);
  await render(); const ev = await close();
  expect(ev.preventDefault).toHaveBeenCalled();
  expect(u.install).toHaveBeenCalledTimes(1);
});
it("does not install on close while recording", async () => {
  const u = fakeUpdate("1.0.400"); checkMock.mockResolvedValue(u);
  await render(); useRecordingStore.setState({ phase: "recording" });
  const ev = await close();
  expect(ev.preventDefault).not.toHaveBeenCalled();
  expect(u.install).not.toHaveBeenCalled();
});
it("does not install on close while a task is processing", async () => {
  const u = fakeUpdate("1.0.400"); checkMock.mockResolvedValue(u);
  await render();
  useRecordingStore.setState({ backgroundTasks: [{ task_id: "t1", status: "transcribing", progress: 40 }] });
  expect((await close()).preventDefault).not.toHaveBeenCalled();
  expect(u.install).not.toHaveBeenCalled();
});
it("does not install on close before the download is finished", async () => {
  const u = fakeUpdate("1.0.400"); u.download.mockReturnValue(new Promise(() => {}));
  checkMock.mockResolvedValue(u);
  await render();
  expect((await close()).preventDefault).not.toHaveBeenCalled();
  expect(u.install).not.toHaveBeenCalled();
});
it("closes normally when the download failed", async () => {   // Review Focus 2
  const u = fakeUpdate("1.0.400"); u.download.mockRejectedValue(new Error("offline"));
  checkMock.mockResolvedValue(u);
  await render();
  expect((await close()).preventDefault).not.toHaveBeenCalled();
});
it("does not install on close when updates are switched off", async () => {   // Review Focus 4
  const u = fakeUpdate("1.0.400"); checkMock.mockResolvedValue(u);
  await render(); await act(async () => { useSettingsStore.setState({ check_for_updates: false }); });
  expect((await close()).preventDefault).not.toHaveBeenCalled();
  expect(u.install).not.toHaveBeenCalled();
});
it("closes the window when install fails", async () => {   // Review Focus 1
  const u = fakeUpdate("1.0.400"); u.install.mockRejectedValue(new Error("bad signature"));
  checkMock.mockResolvedValue(u);
  await render(); await close();
  expect(fakeWindow.destroy).toHaveBeenCalled();
});
```

Gebruik voor de taak een object dat aan `TranscriptTask` voldoet; vul ontbrekende verplichte velden aan uit `windows/src/types.ts` r.51.

- [ ] **Step 3: Draai de tests en zie ze falen**

Run: `heavy run --label fase-d-vitest -- npx vitest run src/hooks/__tests__/useUpdateCheck.test.tsx`
Expected: FAIL, `closeHandler` is niet gezet.

- [ ] **Step 4: Implementeer de handler**

In een `useEffect` zonder afhankelijkheden: buiten Tauri (`!("__TAURI_INTERNALS__" in window)`) niets doen; anders `getCurrentWindow().onCloseRequested(handler)` en de teruggegeven `unlisten` bij unmount aanroepen. De handler leest alles op het moment van sluiten: `downloadedRef`, `useSettingsStore.getState().check_for_updates` en `isBusy(useRecordingStore.getState())`. Alleen als alle drie kloppen: `event.preventDefault()`, `await update.install()`, en bij een fout `await getCurrentWindow().destroy()`.

- [ ] **Step 5: Voeg de permissie toe**

In `capabilities/default.json` de regel `"core:window:allow-destroy",` direct na `"core:window:allow-close",`.

- [ ] **Step 6: Draai alle checks**

Run: `heavy run --label fase-d-vitest -- npx vitest run && heavy run --label fase-d-build -- npm run build`
Expected: alle tests PASS, build groen.
Run: `cd ../src-tauri && heavy run --label fase-d-cargo -- cargo test --lib`
Expected: `test result: ok`. `tauri-build` valideert de capability-bestanden tijdens deze build; een onbekende permissie breekt hier.

- [ ] **Step 7: Commit**

```bash
git add windows/src/hooks/useUpdateCheck.ts windows/src/hooks/__tests__/useUpdateCheck.test.tsx windows/src-tauri/capabilities/default.json
git commit -m "Install a downloaded Windows update when the app closes"
```

---

### Task 3: Banner, instellingen en `AppShell`

**Files:**
- Modify: `windows/src/hooks/useUpdateCheck.ts` (`installNow` toevoegen)
- Modify: `windows/src/components/ui/UpdateBanner.tsx`
- Modify: `windows/src/components/settings/GeneralTab.tsx:21-22` en een knop in dezelfde `settings-row`
- Modify: `windows/src/App.tsx:210,223` (`AppShell`)
- Test: `windows/src/hooks/__tests__/useUpdateCheck.test.tsx`, `windows/src/components/ui/__tests__/UpdateBanner.test.tsx`, `windows/src/components/settings/__tests__/GeneralTab.test.tsx`

**Interfaces:**
- Consumes: `CHECK_UPDATES_EVENT` en de return van `useUpdateCheck` uit Task 1.
- Produces:
  - `useUpdateCheck()` krijgt er `installNow: () => Promise<void>` bij: wacht op een lopende download, start er een als er nog geen is, en roept dan `install()` aan. Zonder native update doet hij niets.
  - `UpdateBanner` props worden `{ version: string; downloadUrl: string | null; onDismiss: () => void; nativeUpdate?: Update | null; downloaded?: boolean; onInstall?: () => Promise<void> }`.

De spec zegt "install() als de download klaar is, anders downloadAndInstall()". `installNow` doet hetzelfde, maar hergebruikt een lopende stille download in plaats van er een tweede te starten (Review Focus 5).

- [ ] **Step 1: Schrijf de falende tests**

In `useUpdateCheck.test.tsx`:

```tsx
it("installNow waits for the running download", async () => {   // Review Focus 5
  let finish!: () => void;
  const u = fakeUpdate("1.0.400"); u.download.mockReturnValue(new Promise<void>((r) => { finish = r; }));
  checkMock.mockResolvedValue(u);
  const api = await renderAndCapture();      // Probe schrijft de hook-return naar een variabele
  const pending = api.installNow();
  expect(u.install).not.toHaveBeenCalled();
  finish(); await act(async () => { await pending; });
  expect(u.download).toHaveBeenCalledTimes(1);
  expect(u.install).toHaveBeenCalledTimes(1);
});
```

In `UpdateBanner.test.tsx` (mock `../../stores/recordingStore` niet; zet de echte store op idle):

```tsx
it("calls onInstall from Nu bijwerken", ...)              // klik op knop met tekst "Nu bijwerken" → onInstall 1x
it("tells the user a downloaded update installs on close", ...)
  // downloaded=true → tekst "Versie 1.0.400 is gedownload en wordt geïnstalleerd als je ThoughtVault afsluit"
it("keeps Nu bijwerken disabled while recording", ...)     // phase "recording" → knop disabled
it("opens the download page when there is no native update", ...)  // bestaand pad: mock @tauri-apps/plugin-shell open, aangeroepen met downloadUrl
```

In `GeneralTab.test.tsx` (mock `@tauri-apps/api/app` `getVersion` op `"1.0.400"`):

```tsx
it("labels the switch Automatisch bijwerken", ...)        // tekst aanwezig, "Controleer op updates" niet meer
it("dispatches tv-check-updates from Zoek naar updates", ...)
  // window.addEventListener(CHECK_UPDATES_EVENT, spy); klik knop "Zoek naar updates" → spy 1x
```

- [ ] **Step 2: Draai de tests en zie ze falen**

Run: `heavy run --label fase-d-vitest -- npx vitest run src/hooks src/components/ui src/components/settings`
Expected: FAIL op `installNow` ontbreekt, ontbrekende teksten en knop.

- [ ] **Step 3: Implementeer**

- `installNow` in de hook volgens de Interfaces hierboven.
- Banner: knop roept `onInstall` aan als die er is, anders het bestaande pad met `downloadUrl` en `plugin-shell` `open`. De directe aanroep `nativeUpdate.downloadAndInstall()` verdwijnt. Kopregel bij `downloaded`: "Versie {version} is gedownload en wordt geïnstalleerd als je ThoughtVault afsluit"; anders ongewijzigd "Versie {version} is beschikbaar". Foutmelding blijft "Bijwerken mislukt. Probeer opnieuw.".
- `GeneralTab`: label "Automatisch bijwerken", uitleg "Nieuwe versies worden op de achtergrond gedownload en geïnstalleerd als je ThoughtVault afsluit. Nooit tijdens een opname of verwerking.". Knop `className="btn btn-sm"` met tekst "Zoek naar updates" die `window.dispatchEvent(new Event(CHECK_UPDATES_EVENT))` doet. De knop werkt ook als de schakelaar uit staat.
- `AppShell` in `App.tsx`: `downloaded` en `installNow` uit de hook halen en als `downloaded` en `onInstall` aan `UpdateBanner` geven.
- `src/__tests__/App.recovery.test.tsx` r.28 mockt de hook; voeg daar `downloaded: false, installNow: async () => {}` toe als TypeScript erom vraagt.

- [ ] **Step 4: Draai alle checks**

Run: `heavy run --label fase-d-vitest -- npx vitest run && heavy run --label fase-d-build -- npm run build`
Expected: alle tests PASS, build groen.

- [ ] **Step 5: Schermafbeelding van instellingen en banner**

Start `npm run dev` (Vite, browser zonder Tauri; de hook doet dan niets, de UI rendert wel). Open de instellingenpagina en een staat met banner via de bestaande `desktop-review.tsx`-pagina's als die een banner-variant hebben; anders alleen Instellingen. Leg vast met `pw screenshot` op 1920×1080, 1440×900, 1280×900, 390×900 en 320×900 in de scratchpad, niet in de repo. Controleer: knop en schakelaar passen op 320 zonder horizontaal scrollen, geen em-dash in de tekst.

- [ ] **Step 6: Commit**

```bash
git add windows/src/hooks windows/src/components/ui windows/src/components/settings windows/src/App.tsx windows/src/__tests__/App.recovery.test.tsx
git commit -m "Add the update check button and install a finished download from the banner"
```

---

### Task 4: End-to-end-bewijs op het dev-kanaal en documentatie

**Files:**
- Modify: `docs/AUTOMATISCHE-UPDATES.md` (nieuwe sectie "Bijwerken op Windows" en aanvulling onder "Checks")
- Modify: `VERSION` en de platformconfigs via `bash scripts/sync-version.sh` (alleen voor de tweede release, op deze branch)

**Interfaces:**
- Consumes: de branch met Task 1 tot en met 3.
- Produces: twee gepubliceerde dev-releases N en N+1 op `https://thoughtvault.yinga.ai/releases/windows/dev.json`, een verslag met schermafbeeldingen, en bijgewerkte documentatie.

Achtergrond voor de uitvoerder:
- Een dev-build heet "ThoughtVault Dev", bundle-ID `nl.prezent.transcript-studio-dev`, en leest `dev.json`. Dat zet de GitHub-workflow via `TAURI_CONFIG` (`.github/workflows/build-windows.yml` r.61-71 en r.119). `scripts/deploy-dev.sh <ref>` start die workflow met `channel=dev`; bij `workflow_dispatch` komt de versie uit `VERSION` (r.50). De GitLab-job zet in `TAURI_CONFIG` alleen `identifier` en `productName` (`.gitlab-ci.yml` r.183), dus een dev-build uit GitLab leest `stable.json`. Gebruik voor dit bewijs de GitHub-workflow.
- De Windows-pc en de werkwijze staan in `docs/WINDOWS-BUILD-WORKFLOW.md`.
- Volgens de updater-plugin start de Windows-installer de app na installatie standaard opnieuw (`restart_after_install` is standaard `true`). Of dat met de eigen WiX-template `windows/src-tauri/installer/main.wxs` ook gebeurt, is niet vastgesteld. Leg het waargenomen gedrag vast.

- [ ] **Step 1: Akkoord van Michel**

Vraag Michel om akkoord voor: de branch naar de GitHub-spiegel pushen (de werkwijze in `docs/WINDOWS-BUILD-WORKFLOW.md` volgen), twee dev-releases publiceren op `dev.json`, en installeren op de Windows-pc. Zonder akkoord stopt deze taak hier en meld je dat terug.

- [ ] **Step 2: Release N publiceren en installeren**

Noteer `cat VERSION` als N. Run: `bash scripts/deploy-dev.sh <geverifieerde-ref>`. Wacht tot de workflow groen is en `curl -s https://thoughtvault.yinga.ai/releases/windows/dev.json` versie N toont. Installeer `ThoughtVault-Dev_N_x64.msi` op de Windows-pc. Controleer in Instellingen > Algemeen dat N wordt getoond en "Automatisch bijwerken" aan staat.

- [ ] **Step 3: Release N+1 publiceren**

Maak vanaf de featurebranch een wegwerpbranch `test/fase-d-release-n1`, zodat de versiesprong niet in de featurebranch belandt. Daarop: `VERSION` één patch hoger, `bash scripts/sync-version.sh`, `git commit -am "Bump version for the update test release"`, push naar de spiegel en `scripts/deploy-dev.sh` met die ref. Controleer dat `dev.json` N+1 toont. De wegwerpbranch na afloop lokaal en op de spiegel verwijderen.

- [ ] **Step 4: Ronde 1, afsluiten tijdens een opname installeert niet**

Start ThoughtVault Dev (N). Wacht tot de banner "Versie N+1 is gedownload en wordt geïnstalleerd als je ThoughtVault afsluit" toont. Start een opname en sluit het hoofdvenster terwijl de opname loopt.
Expected: geen voortgangsvenster van de installer; na opnieuw openen toont Instellingen nog N.
Schermafbeelding van de banner en van Instellingen na herstart.

Deze ronde komt eerst, omdat N+1 dan nog niet geïnstalleerd is en er geen derde release nodig is.

- [ ] **Step 5: Ronde 2, gewoon afsluiten installeert**

Wacht opnieuw op de banner met "gedownload". Sluit de app zonder opname of verwerking.
Expected: klein voortgangsvenster van de MSI (`passive`), daarna toont Instellingen N+1 (na zelf openen of na automatische herstart; noteer welke van de twee). Notulen en instellingen zijn er nog.
Schermafbeelding van Instellingen met N+1.

- [ ] **Step 6: Repo-checks**

Run, in de worktree:
- `python3 scripts/test-publish-release.py` → `OK`
- `cd windows && heavy run --label fase-d-vitest -- npx vitest run && heavy run --label fase-d-build -- npm run build` → groen
- `cd windows/src-tauri && heavy run --label fase-d-cargo -- cargo test --lib` → `test result: ok`

`xcodebuild test` uit `docs/AUTOMATISCHE-UPDATES.md` hoort bij het uitgestelde macOS-deel en valt hier buiten; deze taak raakt geen Swift.

- [ ] **Step 7: Documentatie**

In `docs/AUTOMATISCHE-UPDATES.md` een sectie "Bijwerken op Windows": controle bij start en elke zes uur, stille download in het geheugen (opnieuw downloaden na een herstart voordat hij klaar was), installatie bij afsluiten van het hoofdvenster behalve tijdens opnemen of verwerken, schakelaar "Automatisch bijwerken" en knop "Zoek naar updates" (event `tv-check-updates`), `passive`-installatie, het waargenomen herstartgedrag uit Step 5, en dat het dev-kanaal alleen via de GitHub-workflow `dev.json` leest. Onder "Checks" de twee rondes uit Step 4 en 5 toevoegen.

- [ ] **Step 8: Commit**

```bash
git add docs/AUTOMATISCHE-UPDATES.md
git commit -m "Document silent Windows updates and the dev-channel proof"
```

Meld terug met de schermafbeeldingen, de twee versienummers, de workflow-URL's en het herstartgedrag. Mergen naar `main` doet Michel.
