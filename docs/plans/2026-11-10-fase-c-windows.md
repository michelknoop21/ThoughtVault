# Foutrapporten en meldingen op Windows (fase c) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** De Windows-app schrijft een afgeschermd logbestand, meldt mislukte opnames, transcripties, notules en crashes zelf bij de relay, en laat de gebruiker melden en antwoorden lezen via "Mijn meldingen".

**Architecture:** Rust krijgt `applog.rs` (logbestand met rotatie, maskeren, crashmarkering) en een panic-hook. De frontend schrijft via `invoke("log_write")`, praat met de relay uitsluitend via de bestaande Rust-command `proxy_request`, en houdt identiteit, schakelaar en wachtrij in een zustand-`persist`-store. Automatische meldingen lopen via één functie `reportFailure` in `crashReporter.ts`, aangeroepen vanuit `updateBackgroundTask`, de opnamehaken, `ErrorBoundary` en de crashcontrole bij de start.

**Tech Stack:** Tauri 2 (Rust 2021, std-bestandsfuncties, bestaande crates `sha2`, `chrono`, `tempfile`, `serde`), React 19, TypeScript, zustand 5 `persist`, vitest 4 met jsdom.

**Spec:** `docs/plans/2026-11-10-foutrapporten-feedbackhub.md` op branch `docs/plan-foutrapporten-feedbackhub` (`git show docs/plan-foutrapporten-feedbackhub:docs/plans/2026-11-10-foutrapporten-feedbackhub.md`). Leidend: hoofdstuk 2 (besluiten), 4 (relay-contract), 5 "Fase c" en 8 (risico's). Besluiten liggen vast.

## Global Constraints

- Werk in worktree `/Volumes/SSD/Projects/thoughtvault-support-windows` op branch `feat/support-windows`, gemaakt vanaf `origin/main` (Task 1 maakt hem). Nooit committen of mergen op `main`: elke commit daar start via `.githooks/post-commit` de releasepipeline. Niet pushen naar GitHub (`michelknoop21/ThoughtVault` is openbaar).
- Preflight per taak: `git fetch`, kijk of de taak al op `origin/main` of een andere branch staat (`git log origin/main --oneline -20`, `git worktree list`). Bestaat hij al, neem dat over in plaats van dubbel bouwen.
- Tauri 2, React/TypeScript. Geen nieuwe crates of npm-pakketten. Het log gebruikt std-bestandsfuncties; hashing in Rust via de bestaande `sha2`, in TypeScript via `crypto.subtle`.
- Relay-basis-URL is één constante: `SUPPORT_BASE_URL = "https://thoughtvault.yinga.ai/support"` in `windows/src/services/supportRelay.ts`. Alle relayverkeer loopt via `invoke("proxy_request", { request })` (`windows/src-tauri/src/commands/http.rs` r.26), nooit via `api.request` of `fetch`. Headers: `Content-Type: application/json`, `X-TV-Installation`, `X-TV-Secret` (behalve bij `POST /installations`). Geen `X-User-Token`, geen `Origin`.
- Relay-contract (spec hoofdstuk 4): `POST /installations` `{installationId, secret}` geeft 201 nieuw, 200 bekend, 409 zelfde id met ander geheim. `POST /reports` met `kind` (`auto`/`manual`), `category` (`BUG`/`FEATURE_REQUEST`/`QUESTION`, auto altijd `BUG`), `stage` (`opnemen`/`transcriberen`/`notule`/`crash`, leeg bij handmatig), `shownMessage` (max 5000), `errorText` (max 2000), `fingerprint` (alleen auto), `clickPath` (max 30 regels van 80 tekens), `appVersion`, `os`, `device`, `platform` (`"windows"`), `name`, `email`, `occurredAt` (ISO 8601), `log` (max 1 MB). Antwoord `{ticketId, ref, repeated, count}`. Verder `GET /tickets`, `GET /unread-count`, `GET /tickets/{id}/messages`, `POST /tickets/{id}/messages` `{body}` (max 5000).
- Vingerafdruk, gelijk aan macOS: SHA-256 over de UTF-8-string `` `${stage}|${errorText zonder de tekens 0-9}` ``, eerste 16 tekens lowercase hex. Het fase b-plan moet exact dezelfde invoerstring gebruiken.
- Geheim: 32 willekeurige bytes, base64url zonder `=`. Bewaard met `storeCredential("support_secret", ...)` / `loadCredential("support_secret")` uit `windows/src/services/tauriCommands.ts` (Windows Credential Manager). Het kenmerk is `crypto.randomUUID()` en staat in de store.
- Logbestand: `<app_data_dir>/logs/thoughtvault.log`, roteren naar `thoughtvault.1.log` bij 2 500 000 bytes, `.1` weg als hij ouder is dan zeven dagen, `log_tail` levert maximaal 1 000 000 bytes. E-mailadressen en Windows-paden worden bij het wegschrijven een kenmerk `k-` plus zes hex. Transcript- en notuletekst komen nooit in het log.
- UI-tekst Nederlands, nergens een em-dash of en-dash (gebruik dubbele punt, komma of punt). Code, comments en commitberichten Engels, in de stijl van `git log origin/main` (zin in gebiedende wijs zonder voorvoegsel, bijvoorbeeld "Add opt-in live M3 content gate for macOS"). Geen AI- of modelnamen, geen `Co-Authored-By` of andere attributie.
- Geen wijziging aan CSP of capabilities: de CSP laat `https://thoughtvault.yinga.ai` al toe en het verkeer loopt via Rust; eigen commands uit `generate_handler!` vragen geen plugin-permissie. Geeft een nieuw command in de MSI toch een permissiefout, dan is `capabilities/default.json` de eerste plek om te kijken.
- Bestanden onder ongeveer 400 regels; een bestand dat je raakt en daarboven zit, groeit niet.
- Checks: `cd windows && npx vitest run && heavy run --label tv-support-build -- npm run build` en `cd windows/src-tauri && heavy run --label tv-support-cargo -- cargo test --lib`. Losse vitest-bestanden mogen zonder `heavy`. Een taak is pas af met de groene uitvoer in het rapport.
- Bestaande tests nabootsen `invoke` met `vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }))` en zustand-stores met `useXStore.setState(...)`; `src/test-setup.ts` levert een `localStorage` voor `persist`. Volg dat patroon.
- `src/__tests__/App.recovery.test.tsx` rendert de echte `App` met gemockte modules. Elke taak die nieuwe imports aan `App.tsx`, `crashReporter.ts` of `recordingStore.ts` toevoegt, houdt die test groen door de mock aan te vullen.
- Screenshotprocedure (UI-taken): `cd windows && npx vite --host 127.0.0.1 --port 1442 --strictPort` op de achtergrond, dan per breedte `pw screenshot --viewport-size=<b>,<h> "http://127.0.0.1:1442/desktop-review.html#<route>" $TMPDIR/tv-support-shots/<naam>-<b>.png` voor 1920×1080, 1440×900, 1280×900, 390×900 en 320×900. Bekijk elke afbeelding: geen horizontale scroll op 390 en 320, beperkte inhoudsbreedte op 1920 en 1440, geen em-dash. Toon ze in het rapport, stop vite en verwijder de map daarna.
- Opruimen: eigen buildmappen, screenshots en tijdelijke kopieën direct na gebruik verwijderen; niets van andere sessies aanraken.

## Review Focus

1. Geen internet of relay onbereikbaar terwijl twee flushes tegelijk lopen (start en `online`-event): de melding blijft bewaard en gaat precies één keer weg. Test: Task 6 `sends a queued report once when two flushes overlap after reconnect`.
2. Een fout of crash vóórdat naam en e-mail zijn ingevuld: de melding wacht, vertrekt niet met lege naam, en gaat weg zodra het naamscherm is afgerond. Tests: Task 6 `waits for name and e-mail before sending`, Task 10 `stores a trimmed identity and flushes the queue`.
3. Geheim kwijt uit Credential Manager of relay kent de installatie niet meer (401, daarna 409): de app herstelt met één nieuwe aanmelding en precies één herhaling, zonder lus. Test: Task 6 `re-registers after 401 and moves to a new installation after 409`.
4. Een foutmelding met een Windows-pad of e-mailadres (`C:\Users\Jan\Documents\Overleg Gemeente.wav`, `jan.devries@example.nl`): log, `shownMessage` en `errorText` bevatten geen naam of titel. Tests: Task 2 `scrub_masks_emails_and_windows_paths_with_spaces`, Task 7 `scrubs shown and error text before queueing`.
5. Webview herladen via "Herlaad applicatie" of een dubbel uitgevoerd opstarteffect: geen valse crashmelding, alleen de eerste `session_begin` per proces kijkt naar de markering. Test: Task 2 `session_begin_once_reports_clean_on_later_calls`.

---

### Task 1: Worktree en `OfflineQueueBanner` uit `App.tsx`

`App.tsx` heeft 561 regels en wordt in latere taken aangeraakt. De banner verhuist zonder gedragswijziging.

**Files:**
- Create: `windows/src/components/OfflineQueueBanner.tsx`
- Modify: `windows/src/App.tsx:41-207` (functie `formatBytes` en `OfflineQueueBanner` eruit, import erbij)
- Test: `windows/src/components/__tests__/OfflineQueueBanner.test.tsx`

**Interfaces:**
- Produces: `export function OfflineQueueBanner(): JSX.Element | null` in `components/OfflineQueueBanner.tsx`.

- [ ] **Step 1: Worktree maken**

```bash
cd /Volumes/SSD/Projects/thoughtvault-native && git fetch
git branch -a --list '*support-windows*'   # moet leeg zijn
git worktree add /Volumes/SSD/Projects/thoughtvault-support-windows -b feat/support-windows origin/main
cd /Volumes/SSD/Projects/thoughtvault-support-windows/windows && heavy run --label tv-support-npm -- npm ci
```
Raak de werkmap `/Volumes/SSD/Projects/thoughtvault-native` niet aan: die staat op een andere branch met open wijzigingen.

- [ ] **Step 2: Write the failing test**

```tsx
// OfflineQueueBanner.test.tsx
vi.mock("../../services/offlineQueue", () => ({ getQueue: vi.fn(async () => []), processQueue: vi.fn(), clearQueue: vi.fn() }));
it("renders nothing in local mode", async () => {
  useSettingsStore.setState({ processing_mode: "local" });
  // render <OfflineQueueBanner/> with act + createRoot
  expect(host.textContent).toBe("");
});
it("shows permanently failed uploads in cloud mode", async () => {
  useSettingsStore.setState({ processing_mode: "cloud" });
  useUploadQueueStore.setState({ items: [], currentItem: null, permanentlyFailed: [{ id: "1", fileName: "opname.wav" }] as never });
  // render
  expect(host.textContent).toContain("'opname.wav' kon na meerdere pogingen niet worden geüpload");
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd windows && npx vitest run src/components/__tests__/OfflineQueueBanner.test.tsx`
Expected: FAIL, module `../OfflineQueueBanner` niet gevonden.

- [ ] **Step 4: Verplaats `formatBytes` en `OfflineQueueBanner` letterlijk naar `components/OfflineQueueBanner.tsx`**

Alleen importpaden aanpassen (`./services/offlineQueue` wordt `../services/offlineQueue`, stores `../stores/...`). `formatBytes` blijft een niet-geëxporteerde helper. In `App.tsx` de import `import { OfflineQueueBanner } from "./components/OfflineQueueBanner";` en ongebruikte imports (`useRef`, `useState` als ze nergens anders meer nodig zijn, `useUploadQueueStore`) opruimen.

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd windows && npx vitest run && heavy run --label tv-support-build -- npm run build`
Expected: alle tests PASS, build zonder TypeScript-fouten. `wc -l src/App.tsx` rond 395.

- [ ] **Step 6: Commit**

```bash
git add windows/src/App.tsx windows/src/components/OfflineQueueBanner.tsx windows/src/components/__tests__/OfflineQueueBanner.test.tsx
git commit -m "Move the offline queue banner out of App"
```

---

### Task 2: `applog.rs`: logbestand, maskeren en crashmarkering

Pure functies op een meegegeven map, zodat de tests op een `tempfile::tempdir()` draaien.

**Files:**
- Create: `windows/src-tauri/src/applog.rs`
- Modify: `windows/src-tauri/src/lib.rs:1-4` (alleen `#[macro_use] mod applog;` als eerste moduleregel, zodat `cargo test` het bestand compileert)

**Interfaces:**
- Produces (alle in `applog.rs`):
```rust
pub const MAX_BYTES: u64 = 2_500_000;
pub const TAIL_LIMIT: u64 = 1_000_000;
pub const KEEP_ROTATED: std::time::Duration = std::time::Duration::from_secs(7 * 24 * 60 * 60);
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct PreviousSession { pub crashed: bool, pub stage: Option<String> }
pub fn mask_token(value: &str) -> String;                       // "k-" + first 6 hex of SHA-256
pub fn scrub(text: &str) -> String;                             // emails and Windows paths -> mask_token
pub fn append(dir: &std::path::Path, level: &str, category: &str, message: &str) -> std::io::Result<()>;
pub fn tail(dir: &std::path::Path, max_bytes: u64) -> std::io::Result<String>;
pub fn prune(dir: &std::path::Path, now: std::time::SystemTime);
pub fn session_begin_at(dir: &std::path::Path) -> PreviousSession;
pub fn session_begin_once(dir: &std::path::Path, started: &std::sync::atomic::AtomicBool) -> PreviousSession;
pub fn session_stage_at(dir: &std::path::Path, stage: Option<&str>) -> std::io::Result<()>;
pub fn session_end_at(dir: &std::path::Path);
```
- Bestandsnamen in `dir`: `thoughtvault.log`, `thoughtvault.1.log`, `session.open`.

- [ ] **Step 1: Write the failing tests** (in `applog.rs`, `#[cfg(test)] mod tests`)

```rust
#[test]
fn append_writes_level_category_and_scrubbed_message() {
    let d = tempfile::tempdir().unwrap();
    append(d.path(), "error", "Fout", r"open C:\Users\Jan\x.wav mislukt").unwrap();
    let text = std::fs::read_to_string(d.path().join("thoughtvault.log")).unwrap();
    assert!(text.contains(" ERROR [Fout] open k-"));
    assert!(!text.contains("Jan"));
    assert!(text.ends_with(" mislukt\n"));
}

#[test]
fn rotates_when_the_next_line_would_exceed_the_limit() {
    let d = tempfile::tempdir().unwrap();
    std::fs::write(d.path().join("thoughtvault.log"), vec![b'a'; (MAX_BYTES - 10) as usize]).unwrap();
    append(d.path(), "info", "Test", "volgende regel").unwrap();
    assert_eq!(std::fs::metadata(d.path().join("thoughtvault.1.log")).unwrap().len(), MAX_BYTES - 10);
    assert!(std::fs::read_to_string(d.path().join("thoughtvault.log")).unwrap().contains("volgende regel"));
}

#[test]
fn prune_removes_rotated_file_older_than_seven_days() {
    let d = tempfile::tempdir().unwrap();
    let old = d.path().join("thoughtvault.1.log");
    std::fs::write(&old, "x").unwrap();
    let now = std::time::SystemTime::now();
    std::fs::File::options().write(true).open(&old).unwrap()
        .set_modified(now - std::time::Duration::from_secs(6 * 86_400)).unwrap();
    prune(d.path(), now);
    assert!(old.exists());
    std::fs::File::options().write(true).open(&old).unwrap()
        .set_modified(now - std::time::Duration::from_secs(8 * 86_400)).unwrap();
    prune(d.path(), now);
    assert!(!old.exists());
}

#[test]
fn tail_spans_both_files_and_starts_on_a_line_boundary() {
    let d = tempfile::tempdir().unwrap();
    let lines = |r: std::ops::Range<u32>| r.map(|i| format!("line-{i:04}\n")).collect::<String>(); // 10 bytes each
    std::fs::write(d.path().join("thoughtvault.1.log"), lines(0..5)).unwrap();
    std::fs::write(d.path().join("thoughtvault.log"), lines(5..10)).unwrap();
    let t = tail(d.path(), 75).unwrap();
    assert_eq!(t, lines(3..10));            // 70 bytes, the partial line before is dropped
    assert!(tail(d.path(), 10_000_000).unwrap().len() as u64 <= TAIL_LIMIT);
}

#[test]
fn mask_token_is_stable_and_short() {
    let a = mask_token("Overleg Gemeente");
    assert_eq!(a, mask_token("Overleg Gemeente"));
    assert_ne!(a, mask_token("Overleg Provincie"));
    assert!(a.starts_with("k-") && a.len() == 8 && a[2..].chars().all(|c| c.is_ascii_hexdigit()));
}

#[test]
fn scrub_masks_emails_and_windows_paths_with_spaces() {
    let s = scrub(r"Bestand niet gevonden: C:\Users\Jan\Documents\Overleg Gemeente.wav");
    assert!(s.starts_with("Bestand niet gevonden: k-"));
    assert!(!s.contains("Jan") && !s.contains("Overleg"));
    let q = scrub(r#"open "C:\Users\Jan\a b.wav": os error 2"#);
    assert!(q.ends_with(r#"": os error 2"#) && !q.contains("Jan"));
    let unc = scrub(r"\\server\share\Klant X\notulen.txt kon niet worden gelezen");
    assert!(!unc.contains("Klant"));
    let m = scrub("mail jan.devries@example.nl faalde");
    assert_eq!(m, format!("mail {} faalde", mask_token("jan.devries@example.nl")));
    assert_eq!(scrub("Model niet geladen na 30 s"), "Model niet geladen na 30 s");
}

#[test]
fn session_marker_reports_crash_with_running_stage() {
    let d = tempfile::tempdir().unwrap();
    assert_eq!(session_begin_at(d.path()), PreviousSession { crashed: false, stage: None });
    session_stage_at(d.path(), Some("transcriberen")).unwrap();
    assert_eq!(session_begin_at(d.path()), PreviousSession { crashed: true, stage: Some("transcriberen".into()) });
    session_end_at(d.path());
    assert_eq!(session_begin_at(d.path()), PreviousSession { crashed: false, stage: None });
    session_stage_at(d.path(), None).unwrap();
    assert_eq!(session_begin_at(d.path()), PreviousSession { crashed: true, stage: None });
}

#[test]
fn session_begin_once_reports_clean_on_later_calls() {
    let d = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(d.path()).unwrap();
    std::fs::write(d.path().join("session.open"), "notule").unwrap();
    let started = std::sync::atomic::AtomicBool::new(false);
    assert_eq!(session_begin_once(d.path(), &started), PreviousSession { crashed: true, stage: Some("notule".into()) });
    assert_eq!(session_begin_once(d.path(), &started), PreviousSession { crashed: false, stage: None });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd windows/src-tauri && heavy run --label tv-applog-test -- cargo test --lib applog`
Expected: FAIL, functies niet gedefinieerd.

- [ ] **Step 3: Implementeer de functies uit het Interfaces-blok in `applog.rs`**

- Regelopmaak: `"{tijd} {LEVEL} [{category}] {scrub(message)}\n"`, tijd via `chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true)`, level in hoofdletters. Regeleinden binnen `message` vervangen door een spatie, zodat één melding één regel is.
- `append` maakt `dir` aan als die ontbreekt en roteert met `std::fs::rename` (overschrijft een bestaande `.1`) wanneer huidige grootte plus regel groter is dan `MAX_BYTES`.
- `tail` leest `.1` en het huidige bestand achter elkaar, neemt de laatste `min(max_bytes, TAIL_LIMIT)` bytes, gooit alles tot en met de eerste `\n` weg als het begin midden in een regel valt, en decodeert met `String::from_utf8_lossy`. Ontbrekende bestanden tellen als leeg.
- `scrub`, zonder regex-crate, in één scan over de tekst:
  - E-mail: een maximale reeks `[A-Za-z0-9._%+-]`, dan `@`, dan een maximale reeks `[A-Za-z0-9.-]` met minstens één punt. De hele reeks wordt `mask_token(reeks)`.
  - Pad: begint bij `X:\` of `X:/` (X een ASCII-letter) of bij `\\`, en loopt door tot het eerste teken uit `"'<>|()\n\r\t,;` of het einde van de tekst. Spaties horen bij het pad, afsluitende spaties niet. Het pad wordt `mask_token(pad)`. Gevolg: tekst ná een pad zonder aanhalingstekens verdwijnt mee in het kenmerk. Dat is bewust: een gelekte titel weegt zwaarder dan een kortere foutregel.
- `session_begin_at`: bestaat `session.open`, dan `crashed: true` en `stage` is de getrimde inhoud (leeg wordt `None`); daarna `session.open` leeg opnieuw schrijven. `session_stage_at` overschrijft de inhoud (`None` wordt leeg). `session_end_at` verwijdert het bestand en negeert fouten.
- `session_begin_once`: alleen de eerste aanroep per `AtomicBool` (`swap(true)` gaf `false`) roept `session_begin_at` aan; volgende aanroepen geven `PreviousSession { crashed: false, stage: None }` en laten de markering staan.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd windows/src-tauri && heavy run --label tv-applog-test -- cargo test --lib applog`
Expected: 8 tests PASS. `wc -l src/applog.rs` onder 400.

- [ ] **Step 5: Commit**

```bash
git add windows/src-tauri/src/applog.rs windows/src-tauri/src/lib.rs
git commit -m "Add a masked rotating log file and session marker for Windows"
```

---

### Task 3: Commands, panic-hook, `RunEvent::Exit` en de `elog!`-macro

`eprintln!` gaat in een release verloren door `windows_subsystem = "windows"` (`main.rs` r.1). Een macro schrijft naar stderr én het logbestand.

**Files:**
- Modify: `windows/src-tauri/src/applog.rs` (globale map, `write`, `session_end`, macro, commands)
- Modify: `windows/src-tauri/src/lib.rs` (setup, `generate_handler!`, `.build(...).run(...)`)
- Modify: elk bestand onder `windows/src-tauri/src` met `eprintln!` (spec telt er 45)

**Interfaces:**
- Consumes: Task 2 (`append`, `tail`, `scrub`, `prune`, `session_begin_once`, `session_stage_at`, `session_end_at`, `PreviousSession`, `TAIL_LIMIT`).
- Produces:
```rust
pub fn init(dir: std::path::PathBuf);                     // OnceLock<PathBuf>; creates dir, calls prune(dir, now)
pub fn write(level: &str, category: &str, message: &str); // no-op before init, never panics
pub fn session_end();
macro_rules! elog { ($($arg:tt)*) => { ... } }            // eprintln! + write("info", "rust", &line)
#[tauri::command] pub fn log_write(level: String, category: String, message: String);
#[tauri::command] pub fn log_tail(max_bytes: u64) -> Result<String, String>;
#[tauri::command] pub fn log_scrub(text: String) -> String;
#[tauri::command] pub fn session_begin() -> PreviousSession;   // uses a static AtomicBool via session_begin_once
#[tauri::command] pub fn session_stage(stage: Option<String>);
```
- Frontend-namen (Tasks 4, 7, 9): `invoke("log_write", { level, category, message })`, `invoke<string>("log_tail", { maxBytes })`, `invoke<string>("log_scrub", { text })`, `invoke<{ crashed: boolean; stage: string | null }>("session_begin")`, `invoke("session_stage", { stage })`.
- Afwijking van de spec, bewust: `session_begin` geeft `PreviousSession` in plaats van `bool`, omdat de spec de lopende stap uit de markering in de crashmelding wil. `log_scrub` is extra, zodat `shownMessage` en `errorText` met dezelfde regels worden afgeschermd als het log (Review Focus 4).

- [ ] **Step 1: Write the failing test** (in `applog.rs` tests)

```rust
#[test]
fn write_before_init_is_a_no_op() {
    write("info", "Test", "voor init");   // must not panic
}

#[test]
fn log_scrub_command_uses_the_same_rules() {
    assert_eq!(log_scrub(r"C:\Users\Jan\a.wav".into()), scrub(r"C:\Users\Jan\a.wav"));
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd windows/src-tauri && heavy run --label tv-applog-test -- cargo test --lib applog`
Expected: FAIL, `write` en `log_scrub` niet gedefinieerd.

- [ ] **Step 3: Implementeer het Interfaces-blok en koppel het in `lib.rs`**

- `lib.rs`: `#[macro_use] mod applog;` blijft de eerste moduleregel, zodat `elog!` in alle andere modules bestaat.
- In `.setup(|app| ...)` als eerste: `applog::init(app.path().app_data_dir()?.join("logs"));` en daarna de panic-hook: `let default = std::panic::take_hook(); std::panic::set_hook(Box::new(move |info| { applog::write("error", "panic", &info.to_string()); default(info); }));`.
- Commands toevoegen aan `generate_handler!`: `applog::log_write, applog::log_tail, applog::log_scrub, applog::session_begin, applog::session_stage`.
- `.run(tauri::generate_context!()).expect(...)` (r.109-110) wordt `.build(tauri::generate_context!()).expect("error while building tauri application").run(|_app, event| { if let tauri::RunEvent::Exit = event { applog::session_end(); } });`.
- Vervang elke `eprintln!(` buiten `applog.rs` door `elog!(` met dezelfde argumenten. Controle vooraf en achteraf: `git grep -c "eprintln!" -- windows/src-tauri/src`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd windows/src-tauri && heavy run --label tv-support-cargo -- cargo test --lib`
Expected: alle tests PASS. `git grep -n "eprintln!" -- windows/src-tauri/src` toont alleen de regel in de macro.

- [ ] **Step 5: Commit**

```bash
git add windows/src-tauri/src
git commit -m "Write Rust diagnostics and panics to the Windows log file"
```

---

### Task 4: `appLog.ts`: logaanroepen, console-doorsturing en klikpad

**Files:**
- Create: `windows/src/services/appLog.ts`
- Modify: `windows/src/App.tsx` (r.39-gebied: installeren; `ProtectedRoutes`: route loggen)
- Modify: aanroepen van `console.warn`/`console.error` die een titel, bestandsnaam of deelnemer bevatten
- Test: `windows/src/services/__tests__/appLog.test.ts`

**Interfaces:**
- Consumes: Task 3 commands `log_write`, `log_tail`, `log_scrub`.
- Produces:
```ts
export type LogLevel = "info" | "warn" | "error";
export const log: Record<LogLevel, (category: string, message: string) => void>; // fire-and-forget, never throws
export function mask(value: string): string;              // "k-" + 6 hex, synchronous
export function installConsoleForwarding(): void;         // idempotent
export function installClickPath(): void;                 // idempotent, one capture listener on document
export function logRoute(pathname: string): void;         // log.info("Klikpad", `scherm: ${pathname}`)
export function readLogTail(maxBytes?: number): Promise<string>; // default 1_000_000, "" on failure
export function readClickPath(): Promise<string[]>;       // text after "[Klikpad] " of the last 30 such lines, each max 80 chars
export function scrubText(text: string): Promise<string>; // invoke("log_scrub"), returns text unchanged on failure
```

- [ ] **Step 1: Write the failing tests**

```ts
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async () => undefined) }));
beforeEach(() => vi.mocked(invoke).mockClear());
const writes = () => vi.mocked(invoke).mock.calls.filter(([c]) => c === "log_write").map(([, a]) => a);

it("writes through log_write and never throws when invoke rejects", async () => {
  vi.mocked(invoke).mockRejectedValueOnce(new Error("no tauri"));
  expect(() => log.error("Fout", "x")).not.toThrow();
  log.info("Klikpad", "scherm: /recording");
  expect(writes()).toContainEqual({ level: "info", category: "Klikpad", message: "scherm: /recording" });
});

it("masks to a stable short token", () => {
  expect(mask("Projectoverleg")).toMatch(/^k-[0-9a-f]{6}$/);
  expect(mask("Projectoverleg")).toBe(mask("Projectoverleg"));
  expect(mask("Projectoverleg")).not.toBe(mask("Klantgesprek"));
});

it("forwards console errors once and keeps the original output", () => {
  const original = vi.spyOn(console, "error").mockImplementation(() => {});
  installConsoleForwarding(); installConsoleForwarding();
  console.error("[OAuth] Callback error:", new Error("boom"));
  const forwarded = writes().filter((a) => a.category === "console");
  expect(forwarded).toHaveLength(1);
  expect(forwarded[0]).toMatchObject({ level: "error" });
  expect(forwarded[0].message).toContain("boom");
  expect(original).toHaveBeenCalled();
});

it("logs button clicks by aria-label or masked text", () => {
  installClickPath();
  document.body.innerHTML = '<button aria-label="Feedback openen"><span id="s">x</span></button><button id="t">Projectoverleg Gemeente</button><div id="d">niets</div>';
  document.getElementById("s")!.click();
  document.getElementById("t")!.click();
  document.getElementById("d")!.click();
  const clicks = writes().filter((a) => a.category === "Klikpad").map((a) => a.message);
  expect(clicks).toEqual(["knop: Feedback openen", `knop: ${mask("Projectoverleg Gemeente")}`]);
});

it("reads the last 30 click path lines, each at most 80 characters", async () => {
  const lines = Array.from({ length: 40 }, (_, i) => `2026-11-10T10:00:00Z INFO [Klikpad] knop: ${"x".repeat(90)}${i}`);
  vi.mocked(invoke).mockResolvedValueOnce([...lines, "2026-11-10T10:00:00Z INFO [console] y"].join("\n"));
  const path = await readClickPath();
  expect(path).toHaveLength(30);
  expect(path.every((l) => l.length <= 80)).toBe(true);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd windows && npx vitest run src/services/__tests__/appLog.test.ts`
Expected: FAIL, module niet gevonden.

- [ ] **Step 3: Implementeer `appLog.ts` volgens het Interfaces-blok**

- `mask`: FNV-1a 32-bit over de UTF-16-code-units, eerste zes hex. Het kenmerk dient alleen om dezelfde waarde in één log te herkennen; het hoeft niet gelijk te zijn aan het Rust-kenmerk.
- Klikpad-label: `aria-label` van de dichtstbijzijnde `button` (afgekapt op 40 tekens) en anders `mask(zichtbare tekst getrimd, max 40 tekens)`. Geen `title`-attribuut gebruiken: in `Sidebar.tsx` r.61 bevat dat een notuletitel. Geen getypte tekst loggen.
- Console-doorsturing: argumenten samenvoegen met spatie, een `Error` als `message` plus eerste vijf stackregels; categorie `console`; level `warn`/`error`. Binnen de doorsturing nooit zelf `console.*` aanroepen (anders een lus bij een falende `invoke`).
- `App.tsx`: naast `initCrashReporter()` (r.39) ook `installConsoleForwarding(); installClickPath();`. In `ProtectedRoutes` `useEffect(() => logRoute(location.pathname), [location.pathname]);` (alleen `pathname`, geen query).
- Loop `git grep -n "console\.\(warn\|error\)" -- windows/src ':!**/__tests__/**'` na (spec: 41 aanroepen). Waar een titel, bestandsnaam of deelnemer wordt meegegeven, die waarde in `mask(...)` zetten. Paden en e-mailadressen vangt Rust al af.
- `App.recovery.test.tsx`: werkt zonder mock omdat `log` fouten van `invoke` slikt; voeg alleen een mock toe als de test faalt.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd windows && npx vitest run`
Expected: alle tests PASS.

- [ ] **Step 5: Commit**

```bash
git add windows/src/services/appLog.ts windows/src/services/__tests__/appLog.test.ts windows/src/App.tsx <gewijzigde console-bestanden>
git commit -m "Log console errors, screens and button clicks to the Windows log"
```

---

### Task 5: `supportRelay.ts`: verzoeken naar de relay

Stateloos: elke functie krijgt de installatie mee. Herstel bij 401/409 en de wachtrij zitten in Task 6.

**Files:**
- Create: `windows/src/services/supportRelay.ts`
- Test: `windows/src/services/__tests__/supportRelay.test.ts`

**Interfaces:**
- Produces:
```ts
export const SUPPORT_BASE_URL = "https://thoughtvault.yinga.ai/support";
export type ReportCategory = "BUG" | "FEATURE_REQUEST" | "QUESTION";
export type ReportStage = "opnemen" | "transcriberen" | "notule" | "crash";
export type HubStatus = "NEW" | "IN_PROGRESS" | "WAITING_FOR_USER" | "RESOLVED" | "CLOSED";
export interface Installation { id: string; secret: string }
export interface ReportPayload {
  kind: "auto" | "manual"; category: ReportCategory; stage: ReportStage | "";
  shownMessage: string; errorText: string; fingerprint?: string; clickPath: string[];
  appVersion: string; os: string; device: string; platform: "windows";
  name: string; email: string; occurredAt: string; log: string;
}
export interface ReportResult { ticketId: string; ref: string; repeated: boolean; count: number }
export interface SupportTicket { id: string; ref: string; status: HubStatus; category: ReportCategory; description: string; createdAt: string; unread: boolean; lastMessage?: string }
export interface SupportMessage { id: string; body: string; senderRole: string; createdAt: string }
export class RelayError extends Error { constructor(public status: number, message: string) }
export function registerInstallation(id: string, secret: string): Promise<"created" | "exists" | "conflict">;
export function sendReport(inst: Installation, payload: ReportPayload): Promise<ReportResult>;
export function listTickets(inst: Installation): Promise<SupportTicket[]>;
export function unreadCount(inst: Installation): Promise<number>;
export function ticketMessages(inst: Installation, ticketId: string): Promise<SupportMessage[]>;
export function postMessage(inst: Installation, ticketId: string, body: string): Promise<SupportMessage>;
```
- Veldnamen van tickets en berichten volgen de hub-widget (`id`, `ref`, `status`, `category`, `description`, `createdAt`, `unread`, `lastMessage`; `body`, `senderRole`, `createdAt`). De relay geeft hub-JSON ongewijzigd door, zoals vastgelegd in het plan van fase a (afwijking punt 2): lijsten als `{ data: [...] }`, ongelezen als `{ data: { count } }`. Geen andere vormen ondersteunen.

- [ ] **Step 1: Write the failing tests**

```ts
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
beforeEach(() => vi.mocked(invoke).mockReset());
const inst = { id: "6f1c0d7e-0000-4000-8000-000000000001", secret: "c2VjcmV0LXNlY3JldC1zZWNyZXQtc2VjcmV0LTMyYg" };
const reply = (status: number, body: unknown) => vi.mocked(invoke).mockResolvedValueOnce({ status, body: JSON.stringify(body), headers: {} });

it("posts reports as JSON through proxy_request with installation headers", async () => {
  reply(200, { ticketId: "t1", ref: "TV-1", repeated: false, count: 1 });
  expect(await sendReport(inst, payload)).toEqual({ ticketId: "t1", ref: "TV-1", repeated: false, count: 1 });
  expect(invoke).toHaveBeenCalledWith("proxy_request", { request: expect.objectContaining({
    url: "https://thoughtvault.yinga.ai/support/reports", method: "POST",
    headers: { "Content-Type": "application/json", "X-TV-Installation": inst.id, "X-TV-Secret": inst.secret },
    body: JSON.stringify(payload),
  }) });
});

it("registers without secret headers and maps 201, 200 and 409", async () => {
  reply(201, {}); reply(200, {}); reply(409, {});
  expect(await registerInstallation(inst.id, inst.secret)).toBe("created");
  expect(await registerInstallation(inst.id, inst.secret)).toBe("exists");
  expect(await registerInstallation(inst.id, inst.secret)).toBe("conflict");
  const req = vi.mocked(invoke).mock.calls[0][1] as { request: { url: string; headers: Record<string, string>; body: string } };
  expect(req.request.url).toBe("https://thoughtvault.yinga.ai/support/installations");
  expect(req.request.headers).not.toHaveProperty("X-TV-Secret");
  expect(JSON.parse(req.request.body)).toEqual({ installationId: inst.id, secret: inst.secret });
});

it("turns relay status codes and network failures into RelayError", async () => {
  reply(429, { detail: "te veel" });
  await expect(sendReport(inst, payload)).rejects.toMatchObject({ status: 429 });
  vi.mocked(invoke).mockRejectedValueOnce("error sending request");
  await expect(listTickets(inst)).rejects.toMatchObject({ status: 0 });
});

it("reads tickets, unread count and a thread", async () => {
  reply(200, { data: [{ id: "a", ref: "TV-000002", status: "WAITING_FOR_USER", category: "BUG", description: "d", createdAt: "2026-11-10T10:00:00Z", unread: true }], pagination: {} });
  reply(200, { data: { count: 3 } });
  reply(200, { data: [{ id: "m", body: "Opgelost in 1.0.312", senderRole: "admin", createdAt: "2026-11-10T11:00:00Z" }] });
  expect((await listTickets(inst))[0].ref).toBe("TV-000002");
  expect(await unreadCount(inst)).toBe(3);
  expect((await ticketMessages(inst, "a"))[0].body).toBe("Opgelost in 1.0.312");
  expect(vi.mocked(invoke).mock.calls[2][1]).toMatchObject({ request: { url: "https://thoughtvault.yinga.ai/support/tickets/a/messages", method: "GET" } });
});
```
(`payload` is een volledig `ReportPayload`-object bovenin het testbestand.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd windows && npx vitest run src/services/__tests__/supportRelay.test.ts`
Expected: FAIL, module niet gevonden.

- [ ] **Step 3: Implementeer `supportRelay.ts` volgens het Interfaces-blok**

Eén interne helper `call<T>(method, path, inst | null, body?)` met `invoke<{ status: number; body: string }>("proxy_request", { request: { url, method, headers, body, timeout_seconds: 60 } })`. Een afgewezen `invoke` wordt `RelayError(0, String(e))`; status buiten 200-299 wordt `RelayError(status, detail of body)`. `registerInstallation` vangt 409 af als `"conflict"`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd windows && npx vitest run src/services/__tests__/supportRelay.test.ts`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add windows/src/services/supportRelay.ts windows/src/services/__tests__/supportRelay.test.ts
git commit -m "Add the support relay client for Windows"
```

---

### Task 6: `supportStore.ts`: identiteit, schakelaar, wachtrij en herstel

**Files:**
- Create: `windows/src/stores/supportStore.ts`
- Test: `windows/src/stores/__tests__/supportStore.test.ts`

**Interfaces:**
- Consumes: Task 5 (alle exports), Task 4 `readLogTail`, `log`; `storeCredential`, `loadCredential`, `getAppVersion` uit `services/tauriCommands.ts`; `invoke<{ cpu: string; memory_gb: number; os_version: string }>("get_system_specs")`.
- Produces:
```ts
export const SECRET_CREDENTIAL_KEY = "support_secret";
export interface QueuedReport {
  id: string; kind: "auto" | "manual"; category: ReportCategory; stage: ReportStage | "";
  shownMessage: string; errorText: string; fingerprint?: string; clickPath: string[]; occurredAt: string;
}
interface SupportState {
  installation_id: string | null; name: string; email: string; auto_report: boolean;
  queue: QueuedReport[]; unread_count: number;
  setIdentity: (name: string, email: string) => void;      // trims both
  setAutoReport: (value: boolean) => void;
  enqueue: (item: QueuedReport) => void;
  flushQueue: () => Promise<void>;                          // single-flight
  refreshUnread: () => Promise<void>;
  submitManual: (category: ReportCategory, description: string) => Promise<"sent" | "queued">;
}
export const useSupportStore: UseBoundStore<StoreApi<SupportState>>; // persist name "support-store"
export function isValidEmail(value: string): boolean;               // /^[^\s@]+@[^\s@]+\.[^\s@]+$/ on the trimmed value
export function withInstallation<T>(call: (inst: Installation) => Promise<T>): Promise<T>;
```
- Standaardwaarden: `installation_id: null`, `name: ""`, `email: ""`, `auto_report: true`, `queue: []`, `unread_count: 0`.

- [ ] **Step 1: Write the failing tests**

```ts
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
// Fake backend: credentials in a Map, relay answers per path from a queue.
const creds = new Map<string, string>();
const answers: Record<string, Array<number | "offline">> = {};
const sent: Array<{ path: string; body: any }> = [];
beforeEach(() => {
  creds.clear(); sent.length = 0; for (const k of Object.keys(answers)) delete answers[k];
  useSupportStore.setState({ installation_id: null, name: "Jan", email: "jan@example.nl", auto_report: true, queue: [], unread_count: 0 });
  vi.mocked(invoke).mockImplementation(async (cmd: string, args: any) => {
    if (cmd === "store_credential") { creds.set(args.key, args.value); return; }
    if (cmd === "load_credential") return creds.get(args.key) ?? null;
    if (cmd === "log_tail") return "log-tail";
    if (cmd === "get_app_version") return "1.0.312";
    if (cmd === "get_system_specs") return { cpu: "Review CPU", memory_gb: 16, os_version: "Windows 11" };
    if (cmd === "proxy_request") {
      const path = args.request.url.replace("https://thoughtvault.yinga.ai/support", "");
      sent.push({ path, body: args.request.body ? JSON.parse(args.request.body) : null });
      const status = answers[path]?.shift() ?? (path === "/installations" ? 201 : 200);
      if (status === "offline") throw "error sending request";
      return { status, body: JSON.stringify({ ticketId: "t", ref: "TV-1", repeated: false, count: 1 }), headers: {} };
    }
  });
});
const item = (over: Partial<QueuedReport> = {}): QueuedReport => ({ id: crypto.randomUUID(), kind: "auto", category: "BUG",
  stage: "notule", shownMessage: "Notule maken mislukt", errorText: "Ollama niet bereikbaar", fingerprint: "390655eba19539fc",
  clickPath: ["knop: Opnemen"], occurredAt: "2026-11-10T10:00:00.000Z", ...over });
const reports = () => sent.filter((s) => s.path === "/reports");

it("registers once and sends the report with identity, versions and log", async () => {
  useSupportStore.getState().enqueue(item());
  await useSupportStore.getState().flushQueue();
  expect(sent.filter((s) => s.path === "/installations")).toHaveLength(1);
  expect(reports()[0].body).toMatchObject({ kind: "auto", platform: "windows", name: "Jan", email: "jan@example.nl",
    appVersion: "1.0.312", os: "Windows 11", log: "log-tail", fingerprint: "390655eba19539fc" });
  expect(creds.get("support_secret")).toMatch(/^[A-Za-z0-9_-]{43}$/);
  expect(useSupportStore.getState().queue).toHaveLength(0);
});

it("sends a queued report once when two flushes overlap after reconnect", async () => {
  answers["/reports"] = ["offline"];
  useSupportStore.getState().enqueue(item());
  await useSupportStore.getState().flushQueue();
  expect(useSupportStore.getState().queue).toHaveLength(1);
  await Promise.all([useSupportStore.getState().flushQueue(), useSupportStore.getState().flushQueue()]);
  expect(reports()).toHaveLength(2);           // one failed attempt, one success
  expect(useSupportStore.getState().queue).toHaveLength(0);
});

it("waits for name and e-mail before sending", async () => {
  useSupportStore.setState({ name: "", email: "" });
  useSupportStore.getState().enqueue(item());
  await useSupportStore.getState().flushQueue();
  expect(reports()).toHaveLength(0);
  expect(useSupportStore.getState().queue).toHaveLength(1);
});

it("re-registers after 401 and moves to a new installation after 409", async () => {
  useSupportStore.setState({ installation_id: "old-id" }); creds.set("support_secret", "old-secret");
  answers["/reports"] = [401, 200]; answers["/installations"] = [409, 201];
  useSupportStore.getState().enqueue(item());
  await useSupportStore.getState().flushQueue();
  expect(reports()).toHaveLength(2);
  expect(sent.filter((s) => s.path === "/installations")).toHaveLength(2);
  expect(useSupportStore.getState().installation_id).not.toBe("old-id");
  expect(creds.get("support_secret")).not.toBe("old-secret");
  expect(useSupportStore.getState().queue).toHaveLength(0);
});

it("stops at 429 and keeps every queued report", async () => {
  answers["/reports"] = [429];
  useSupportStore.getState().enqueue(item()); useSupportStore.getState().enqueue(item({ stage: "opnemen" }));
  await useSupportStore.getState().flushQueue();
  expect(reports()).toHaveLength(1);
  expect(useSupportStore.getState().queue).toHaveLength(2);
});

it("retries a 413 once without the log", async () => {
  answers["/reports"] = [413, 200];
  useSupportStore.getState().enqueue(item());
  await useSupportStore.getState().flushQueue();
  expect(reports()[1].body.log).toBe("");
  expect(useSupportStore.getState().queue).toHaveLength(0);
});

it("drops queued automatic reports when auto_report is off but still sends manual ones", async () => {
  useSupportStore.getState().enqueue(item()); useSupportStore.getState().enqueue(item({ kind: "manual", stage: "", category: "QUESTION", fingerprint: undefined }));
  useSupportStore.getState().setAutoReport(false);
  await useSupportStore.getState().flushQueue();
  expect(reports().map((r) => r.body.kind)).toEqual(["manual"]);
  expect(useSupportStore.getState().queue).toHaveLength(0);
});

it("returns queued for a manual report while offline", async () => {
  answers["/reports"] = ["offline"];
  expect(await useSupportStore.getState().submitManual("QUESTION", "Hoe exporteer ik?")).toBe("queued");
  expect(useSupportStore.getState().queue[0]).toMatchObject({ kind: "manual", stage: "", shownMessage: "Hoe exporteer ik?", errorText: "" });
});

it("validates e-mail addresses", () => {
  expect(isValidEmail(" jan@example.nl ")).toBe(true);
  expect(["", "jan@", "jan example.nl", "jan@example"].some(isValidEmail)).toBe(false);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd windows && npx vitest run src/stores/__tests__/supportStore.test.ts`
Expected: FAIL, module niet gevonden.

- [ ] **Step 3: Implementeer `supportStore.ts` volgens het Interfaces-blok**

- `withInstallation`: zorg voor kenmerk en geheim (kenmerk ontbreekt: nieuwe `crypto.randomUUID()`; geheim ontbreekt in Credential Manager: nieuw geheim), meld aan als dit kenmerk in dit proces nog niet is aangemeld (modulevariabele met het laatst aangemelde kenmerk), roep `call` aan. Bij `RelayError` 401: opnieuw aanmelden met hetzelfde kenmerk; geeft dat `"conflict"`, dan nieuw kenmerk plus nieuw geheim en aanmelden. Daarna precies één herhaling van `call`; een tweede 401 gaat als fout terug.
- `flushQueue` is single-flight: een lopende flush-promise wordt teruggegeven aan een tweede aanroeper. Volgorde per item: geen naam of e-mail, dan stoppen zonder iets te sturen; `kind: "auto"` terwijl `auto_report` uit staat, dan item verwijderen; payload maken met `log: await readLogTail()`, `appVersion` uit `getAppVersion()`, `os` = `os_version`, `device` = `` `${cpu}, ${memory_gb} GB` ``, `platform: "windows"`; versturen via `withInstallation(i => sendReport(i, payload))`.
- Afhandeling per uitkomst: succes, item weg; 413, één herhaling met `log: ""`, daarna item weg ongeacht uitkomst; 429, status 0 of 5xx, stoppen en alles laten staan; overige 4xx, item weg en `log.warn("Melden", ...)`.
- `submitManual`: `description` afkappen op 5000, item met `kind: "manual"`, `stage: ""`, `errorText: ""`, `shownMessage: description`, `clickPath` uit `readClickPath()`; daarna `flushQueue()` en `"sent"` als het item uit de wachtrij is, anders `"queued"`. Daarna `refreshUnread()`.
- `refreshUnread`: `withInstallation(unreadCount)`; fouten laten de oude waarde staan.
- Alleen metadata in de wachtrij; het log wordt pas bij verzenden gelezen.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd windows && npx vitest run src/stores/__tests__/supportStore.test.ts`
Expected: 9 tests PASS. Als `crypto.subtle` of `crypto.randomUUID` in jsdom ontbreekt: in `src/test-setup.ts` `import { webcrypto } from "node:crypto"; Object.defineProperty(globalThis, "crypto", { value: webcrypto, configurable: true });`.

- [ ] **Step 5: Commit**

```bash
git add windows/src/stores/supportStore.ts windows/src/stores/__tests__/supportStore.test.ts windows/src/test-setup.ts
git commit -m "Queue support reports and recover the installation on Windows"
```

---

### Task 7: `crashReporter.ts`: `reportFailure`, vingerafdruk en stapbepaling

`window`-fouten en `unhandledrejection` gaan alleen nog naar het log, niet meer naar `POST /feedback`.

**Files:**
- Modify: `windows/src/services/crashReporter.ts` (geheel herschreven, 48 regels nu)
- Test: `windows/src/services/__tests__/crashReporter.test.ts`

**Interfaces:**
- Consumes: Task 4 `log`, `readClickPath`, `scrubText`; Task 6 `useSupportStore`; `TaskStatus` uit `types.ts`.
- Produces:
```ts
export function initCrashReporter(): void;        // window error + unhandledrejection -> log.error("Onverwacht", ...)
export function stageForStatus(status: TaskStatus): ReportStage | null;
export function failureFromTransition(prev: TaskStatus, next: TaskStatus, message?: string): { stage: ReportStage; message: string } | null;
export function fingerprint(stage: string, errorText: string): Promise<string>;
export function reportFailure(stage: ReportStage, shown: string, error: string): Promise<void>;
export function markStage(stage: ReportStage | null): void; // invoke("session_stage", { stage }), errors swallowed
```
- `stageForStatus`: `"generating"` wordt `"notule"`; `"pending"`, `"queued"`, `"uploading"`, `"downloading"`, `"converting"`, `"transcribing"`, `"paused"` worden `"transcriberen"`; `"completed"`, `"failed"`, `"cancelled"`, `"error"` worden `null`.
- `failureFromTransition`: alleen als `next` `"failed"` of `"error"` is en `prev` niet; stap = `stageForStatus(prev) ?? "transcriberen"`; `message` = gegeven tekst of `"Onbekende fout"`; `null` bij `message === "Geannuleerd door gebruiker."` (gelijk aan macOS).

- [ ] **Step 1: Write the failing tests**

```ts
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn(async (cmd: string, a: any) =>
  cmd === "log_scrub" ? `scrubbed(${a.text})` : cmd === "log_tail" ? "x INFO [Klikpad] knop: Opnemen" : undefined) }));

it("fingerprints stage plus error text without digits, first 16 hex", async () => {
  expect(await fingerprint("transcriberen", "Model niet geladen na 30 s (code 12)")).toBe("390655eba19539fc");
  expect(await fingerprint("transcriberen", "Model niet geladen na 45 s (code 7)")).toBe("390655eba19539fc");
  expect(await fingerprint("notule", "Model niet geladen na 30 s (code 12)")).toBe("f2990848e3a1a105");
});

it("derives the stage from the previous status", () => {
  expect(failureFromTransition("transcribing", "failed", "x")).toEqual({ stage: "transcriberen", message: "x" });
  expect(failureFromTransition("generating", "failed", "y")).toEqual({ stage: "notule", message: "y" });
  expect(failureFromTransition("uploading", "error")).toEqual({ stage: "transcriberen", message: "Onbekende fout" });
  expect(failureFromTransition("failed", "failed", "x")).toBeNull();
  expect(failureFromTransition("generating", "completed")).toBeNull();
  expect(failureFromTransition("transcribing", "failed", "Geannuleerd door gebruiker.")).toBeNull();
  expect(stageForStatus("generating")).toBe("notule");
  expect(stageForStatus("completed")).toBeNull();
});

it("scrubs shown and error text before queueing", async () => {
  const flushQueue = vi.fn(async () => {});
  useSupportStore.setState({ queue: [], auto_report: true, flushQueue });
  await reportFailure("notule", "Notule maken mislukt", "C:\\Users\\Jan\\Overleg.wav niet gevonden");
  const q = useSupportStore.getState().queue[0];
  expect(q).toMatchObject({ kind: "auto", category: "BUG", stage: "notule",
    shownMessage: "scrubbed(Notule maken mislukt)", errorText: "scrubbed(C:\\Users\\Jan\\Overleg.wav niet gevonden)",
    clickPath: ["knop: Opnemen"] });
  expect(q.fingerprint).toMatch(/^[0-9a-f]{16}$/);
  expect(flushQueue).toHaveBeenCalled();
});

it("only logs when automatic reporting is off", async () => {
  useSupportStore.setState({ queue: [], auto_report: false });
  await reportFailure("opnemen", "Opname mislukt", "device lost");
  expect(useSupportStore.getState().queue).toHaveLength(0);
  expect(invoke).toHaveBeenCalledWith("log_write", expect.objectContaining({ level: "error" }));
});

it("sends window errors only to the log", () => {
  initCrashReporter();
  window.dispatchEvent(new ErrorEvent("error", { message: "boom" }));
  expect(invoke).toHaveBeenCalledWith("log_write", expect.objectContaining({ level: "error", category: "Onverwacht" }));
  expect(invoke).not.toHaveBeenCalledWith("proxy_request", expect.anything());
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd windows && npx vitest run src/services/__tests__/crashReporter.test.ts`
Expected: FAIL, exports ontbreken.

- [ ] **Step 3: Implementeer het Interfaces-blok in `crashReporter.ts`**

- `fingerprint`: `crypto.subtle.digest("SHA-256", new TextEncoder().encode(\`${stage}|${errorText.replace(/[0-9]/g, "")}\`))`, hex, eerste 16 tekens. De vingerafdruk gaat over de ruwe foutmelding, vóór het afschermen, net als op macOS.
- `reportFailure`: altijd eerst `log.error("Fout", \`${stage}: ${error}\`)`; als `auto_report` uit staat, stoppen; anders `shownMessage` (max 5000) en `errorText` (max 2000) via `scrubText`, `clickPath` via `readClickPath()`, `enqueue` met `kind: "auto"`, `category: "BUG"`, `occurredAt: new Date().toISOString()`, `id: crypto.randomUUID()`, en `flushQueue()` zonder te wachten op het resultaat. Nooit gooien.
- De import van `api` verdwijnt; `api.submitFeedback` en verwanten blijven als dode code staan (spec hoofdstuk 6).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd windows && npx vitest run`
Expected: alle tests PASS.

- [ ] **Step 5: Commit**

```bash
git add windows/src/services/crashReporter.ts windows/src/services/__tests__/crashReporter.test.ts
git commit -m "Report failed steps automatically and keep window errors local"
```

---

### Task 8: Automatische meldingen aan de bestaande haakpunten

**Files:**
- Modify: `windows/src/stores/recordingStore.ts:141-146` (`updateBackgroundTask`)
- Modify: `windows/src/hooks/useGlobalRecordingHandler.ts:70-75` (listener `recording-error`)
- Modify: `windows/src/pages/RecordingPage.tsx:215-219` (`catch` in `handleStartRecording`)
- Modify: `windows/src/components/ui/ErrorBoundary.tsx:23` (`componentDidCatch`)
- Modify: `windows/src/__tests__/App.recovery.test.tsx` (mock van `../services/crashReporter` aanvullen)
- Test: `windows/src/stores/__tests__/recordingStore.support.test.ts`, `windows/src/hooks/__tests__/useGlobalRecordingHandler.test.tsx`, `windows/src/components/ui/__tests__/ErrorBoundary.test.tsx`

**Interfaces:**
- Consumes: Task 7 `reportFailure`, `failureFromTransition`, `stageForStatus`, `markStage`.

- [ ] **Step 1: Write the failing tests**

```ts
// recordingStore.support.test.ts
vi.mock("../../services/crashReporter", async (orig) => ({ ...(await orig<object>()), reportFailure: vi.fn(async () => {}), markStage: vi.fn() }));
it("reports a background task that fails, once, with the stage of its previous status", () => {
  const s = useRecordingStore.getState();
  s.addBackgroundTask({ task_id: "t", status: "transcribing", progress: 0, mode: "combined", created_at: "2026-11-10" } as TranscriptTask);
  s.updateBackgroundTask("t", { status: "generating" });
  expect(markStage).toHaveBeenLastCalledWith("notule");
  s.updateBackgroundTask("t", { status: "failed", error_message: "Ollama niet bereikbaar" });
  s.updateBackgroundTask("t", { status: "failed", error_message: "Ollama niet bereikbaar" });
  expect(reportFailure).toHaveBeenCalledTimes(1);
  expect(reportFailure).toHaveBeenCalledWith("notule", "Ollama niet bereikbaar", "Ollama niet bereikbaar");
  expect(markStage).toHaveBeenLastCalledWith(null);
});
```

```tsx
// useGlobalRecordingHandler.test.tsx: extra mock and test in the existing file
vi.mock("../../services/crashReporter", () => ({ reportFailure: vi.fn(async () => {}) }));
it("reports a recording error", async () => {
  const root = createRoot(document.createElement("div"));
  await act(async () => root.render(<Handler />));
  await act(async () => mocks.events.get("recording-error")!({ payload: "Microfoon niet beschikbaar" }));
  expect(reportFailure).toHaveBeenCalledWith("opnemen", "Microfoon niet beschikbaar", "Microfoon niet beschikbaar");
  await act(async () => root.unmount());
});
```

```tsx
// ErrorBoundary.test.tsx
vi.mock("../../../services/crashReporter", () => ({ reportFailure: vi.fn(async () => {}) }));
it("reports a render crash", async () => {
  vi.spyOn(console, "error").mockImplementation(() => {});
  function Boom(): never { throw new Error("boom"); }
  // render <ErrorBoundary><Boom/></ErrorBoundary> with act + createRoot
  expect(reportFailure).toHaveBeenCalledWith("crash", "Er is iets misgegaan", "boom");
  expect(host.textContent).toContain("Er is iets misgegaan");
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd windows && npx vitest run src/stores/__tests__/recordingStore.support.test.ts src/hooks/__tests__/useGlobalRecordingHandler.test.tsx src/components/ui/__tests__/ErrorBoundary.test.tsx`
Expected: FAIL, `reportFailure` niet aangeroepen.

- [ ] **Step 3: Haak de vier punten aan**

- `updateBackgroundTask`: vóór `set` de vorige taak opzoeken; na `set`, als `update.status` bestaat en verschilt: `markStage(stageForStatus(update.status))`, en `failureFromTransition(prev.status, update.status, update.error_message ?? prev.error_message)` die niet `null` is gaat naar `void reportFailure(f.stage, f.message, f.message)`. Dit dekt `localPipeline.ts` r.182, `RecordingPage.tsx` r.172 en r.183, `App.tsx` r.345 en r.357.
- `recording-error`: `void reportFailure("opnemen", event.payload, event.payload)` naast de bestaande toast.
- `RecordingPage.handleStartRecording` `catch`: `void reportFailure("opnemen", <de tekst die de toast toont>, err instanceof Error ? err.message : String(err))`. Geen eigen test: `RecordingPage` heeft geen testopzet; de reviewer controleert deze ene regel.
- `ErrorBoundary.componentDidCatch`: `void reportFailure("crash", "Er is iets misgegaan", error.message)` naast de bestaande `console.error`.
- `App.recovery.test.tsx`: mock wordt `{ initCrashReporter: vi.fn(), reportFailure: vi.fn(async () => {}), markStage: vi.fn(), stageForStatus: () => null, failureFromTransition: () => null }`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd windows && npx vitest run`
Expected: alle tests PASS.

- [ ] **Step 5: Commit**

```bash
git add windows/src/stores windows/src/hooks windows/src/pages/RecordingPage.tsx windows/src/components/ui windows/src/__tests__/App.recovery.test.tsx
git commit -m "Report failed recordings, processing and render crashes"
```

---

### Task 9: Crash- en vastloperdetectie bij de start, wachtrij en ongelezen-teller

**Files:**
- Create: `windows/src/hooks/useSupportLifecycle.ts`
- Modify: `windows/src/App.tsx` (in `App()` één regel `useSupportLifecycle();`)
- Modify: `windows/src/__tests__/App.recovery.test.tsx` (mock `../hooks/useSupportLifecycle`)
- Test: `windows/src/hooks/__tests__/useSupportLifecycle.test.tsx`

**Interfaces:**
- Consumes: Task 3 `session_begin`; Task 6 `flushQueue`, `refreshUnread`; Task 7 `reportFailure`.
- Produces:
```ts
export function useSupportLifecycle(): void;
export function reportPreviousCrash(): Promise<void>;
```
- Crashteksten: met stap `reportFailure(stage, \`ThoughtVault stopte onverwacht tijdens ${stage}.\`, \`gestopt tijdens ${stage}\`)`; zonder stap `reportFailure("crash", "ThoughtVault stopte onverwacht.", "gestopt zonder af te sluiten")`. Een onbekende stapwaarde uit de markering telt als zonder stap.

- [ ] **Step 1: Write the failing tests**

```tsx
vi.mock("@tauri-apps/api/core", () => ({ invoke: vi.fn() }));
vi.mock("../../services/crashReporter", () => ({ reportFailure: vi.fn(async () => {}) }));
beforeEach(() => { Object.assign(window, { __TAURI_INTERNALS__: {} }); });

it("reports a crash with the step that was running", async () => {
  vi.mocked(invoke).mockResolvedValueOnce({ crashed: true, stage: "transcriberen" });
  await reportPreviousCrash();
  expect(reportFailure).toHaveBeenCalledWith("transcriberen", "ThoughtVault stopte onverwacht tijdens transcriberen.", "gestopt tijdens transcriberen");
});

it("reports a bare crash and nothing after a clean exit", async () => {
  vi.mocked(invoke).mockResolvedValueOnce({ crashed: true, stage: null }).mockResolvedValueOnce({ crashed: false, stage: null });
  await reportPreviousCrash(); await reportPreviousCrash();
  expect(reportFailure).toHaveBeenCalledTimes(1);
  expect(reportFailure).toHaveBeenCalledWith("crash", "ThoughtVault stopte onverwacht.", "gestopt zonder af te sluiten");
});

it("flushes at start and when the network returns, and refreshes unread on start, focus and every 15 minutes", async () => {
  vi.useFakeTimers();
  vi.mocked(invoke).mockResolvedValue({ crashed: false, stage: null });
  const flushQueue = vi.fn(async () => {}), refreshUnread = vi.fn(async () => {});
  useSupportStore.setState({ flushQueue, refreshUnread });
  // render a component that calls useSupportLifecycle()
  expect(flushQueue).toHaveBeenCalledTimes(1); expect(refreshUnread).toHaveBeenCalledTimes(1);
  window.dispatchEvent(new Event("online")); expect(flushQueue).toHaveBeenCalledTimes(2);
  window.dispatchEvent(new Event("focus")); expect(refreshUnread).toHaveBeenCalledTimes(2);
  await act(async () => { vi.advanceTimersByTime(15 * 60 * 1000); });
  expect(refreshUnread).toHaveBeenCalledTimes(3);
  // unmount; listeners and interval are removed
  vi.useRealTimers();
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd windows && npx vitest run src/hooks/__tests__/useSupportLifecycle.test.tsx`
Expected: FAIL, module niet gevonden.

- [ ] **Step 3: Implementeer `useSupportLifecycle` en `reportPreviousCrash`**

Eén `useEffect` met `[]`: alleen als `"__TAURI_INTERNALS__" in window` (zelfde guard als de andere effecten in `App.tsx`). Daarin `void reportPreviousCrash().finally(() => flushQueue())`, `refreshUnread()`, listeners `online` (flush) en `focus` (teller), en `setInterval(refreshUnread, 15 * 60 * 1000)`; opruimen bij unmount. Een tweede `session_begin` in hetzelfde proces geeft altijd `crashed: false` (Task 2), dus herladen van de webview of een dubbel effect meldt niets.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd windows && npx vitest run`
Expected: alle tests PASS, inclusief `App.recovery.test.tsx` met `vi.mock("../hooks/useSupportLifecycle", () => ({ useSupportLifecycle: vi.fn() }))`.

- [ ] **Step 5: Commit**

```bash
git add windows/src/hooks/useSupportLifecycle.ts windows/src/hooks/__tests__/useSupportLifecycle.test.tsx windows/src/App.tsx windows/src/__tests__/App.recovery.test.tsx
git commit -m "Report the previous crash at start and keep the support queue moving"
```

---

### Task 10: `IdentityGate` vóór de onboardingcontrole

De onboardingcontrole (`App.tsx` r.378 op main) slaat de wizard in lokale modus over; de poort staat ervoor, zodat ook bestaande lokale gebruikers hem zien.

**Files:**
- Create: `windows/src/components/support/IdentityGate.tsx`
- Modify: `windows/src/App.tsx` (`ProtectedRoutes`, direct vóór `if (!has_completed_onboarding && ...)`)
- Modify: `windows/src/desktop-review.tsx` (identiteit voorvullen, route `/identity`)
- Modify: `windows/src/__tests__/App.recovery.test.tsx`
- Test: `windows/src/components/support/__tests__/IdentityGate.test.tsx`

**Interfaces:**
- Consumes: Task 6 `useSupportStore` (`name`, `email`, `setIdentity`, `flushQueue`), `isValidEmail`.
- Produces: `export function IdentityGate(): JSX.Element` (geen props).
- Vaste tekst:
  - Kop: "Even voorstellen"
  - Inleiding: "Met je naam en e-mailadres kan de ontwikkelaar je meldingen beantwoorden."
  - Uitleg (besluit 8, letterlijk): "Gaat er iets mis bij opnemen, transcriberen of de notule, dan stuurt ThoughtVault automatisch een foutrapport met app-versie, apparaat, je klikpad en een afgeschermd logbestand naar de ontwikkelaar. Je opnames, transcripties, notules en titels gaan nooit mee."
  - Regel: "Automatisch versturen zet je uit bij Instellingen, Account."
  - Velden "Naam" en "E-mailadres", knop "Doorgaan", foutregel "Vul een geldig e-mailadres in."

- [ ] **Step 1: Write the failing tests**

```tsx
it("stores a trimmed identity and flushes the queue", async () => {
  const flushQueue = vi.fn(async () => {});
  useSupportStore.setState({ name: "", email: "", flushQueue });
  // render <IdentityGate/>
  expect(host.textContent).toContain("Je opnames, transcripties, notules en titels gaan nooit mee.");
  const button = [...host.querySelectorAll("button")].find((b) => b.textContent === "Doorgaan")!;
  expect(button.disabled).toBe(true);
  await act(async () => { fill(nameInput, "Jan"); fill(emailInput, "jan@"); });
  expect(button.disabled).toBe(true);
  await act(async () => fill(emailInput, " jan@example.nl "));
  await act(async () => button.click());
  expect(useSupportStore.getState()).toMatchObject({ name: "Jan", email: "jan@example.nl" });
  expect(flushQueue).toHaveBeenCalled();
});
```
(`fill` zoals in `FeedbackWidget.test.tsx` r.16-20: waarde via de prototype-setter zetten en een `input`-event sturen.)

```tsx
// App.recovery.test.tsx: extra test
vi.mock("../components/support/IdentityGate", () => ({ IdentityGate: () => <p>naamscherm</p> }));
it("shows the identity gate before the app when name or e-mail is missing", async () => {
  useSupportStore.setState({ name: "", email: "" });
  // render <App/> as the existing tests do
  expect(document.body.textContent).toContain("naamscherm");
});
```
In de `beforeEach` van dat bestand: `useSupportStore.setState({ name: "Test", email: "test@example.test" })`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd windows && npx vitest run src/components/support/__tests__/IdentityGate.test.tsx src/__tests__/App.recovery.test.tsx`
Expected: FAIL, module niet gevonden en geen naamscherm.

- [ ] **Step 3: Implementeer `IdentityGate` en de poort**

- Formulier met de klassen die `FeedbackWidget` al gebruikt (`form-field`, `form-label`, `input`, `btn btn-accent`), gecentreerd, `maxWidth: 440`, `padding: 16`. "Doorgaan" is uitgeschakeld tot `name.trim()` niet leeg is en `isValidEmail(email)` klopt; de foutregel verschijnt na verlaten van het e-mailveld met een ongeldige waarde. Bij doorgaan `setIdentity(name, email)` en `void flushQueue()`.
- `ProtectedRoutes`: `const identityMissing = useSupportStore((s) => !s.name.trim() || !s.email.trim());` bovenaan bij de andere hooks; vóór de onboardingcontrole `if (identityMissing) return <div className="app-shell"><IdentityGate /></div>;`. De hooks daarboven (opnamehandler, herstel van taken) blijven draaien.
- `desktop-review.tsx`: naast de bestaande `useSettingsStore.setState(...)` (r.43) `useSupportStore.setState({ name: "Review", email: "review@example.test" })`; route `"/identity"` die eerst `useSupportStore.setState({ name: "", email: "" })` doet en `<IdentityGate/>` toont (de setState in de route-elementfabriek of via een kleine wrappercomponent in hetzelfde bestand).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd windows && npx vitest run && heavy run --label tv-support-build -- npm run build`
Expected: alle tests PASS, build zonder fouten.

- [ ] **Step 5: Screenshots**

Volg de screenshotprocedure uit Global Constraints met route `/identity` en naam `identity`. Controleer op 320 dat velden en knop binnen beeld vallen en de uitleg leesbaar blijft.

- [ ] **Step 6: Commit**

```bash
git add windows/src/components/support windows/src/App.tsx windows/src/desktop-review.tsx windows/src/__tests__/App.recovery.test.tsx
git commit -m "Ask for name and e-mail before the Windows app opens"
```

---

### Task 11: `FeedbackWidget` naar de relay en `SupportThread`

**Files:**
- Modify: `windows/src/components/FeedbackWidget.tsx` (443 regels; doel onder 400)
- Create: `windows/src/components/support/SupportThread.tsx`
- Modify: `windows/src/components/__tests__/FeedbackWidget.test.tsx` (klembordtest vervalt)
- Modify: `windows/src/desktop-review.tsx` (fixture voor `proxy_request`, routes `/support` en `/support-thread`)
- Test: `windows/src/components/support/__tests__/SupportThread.test.tsx`

**Interfaces:**
- Consumes: Task 5 `listTickets`, `ticketMessages`, `postMessage`, `SupportTicket`, `SupportMessage`, `ReportCategory`; Task 6 `useSupportStore` (`submitManual`, `refreshUnread`, `unread_count`), `withInstallation`.
- Produces:
```ts
export default function FeedbackWidget(props: { initialOpen?: boolean }): JSX.Element;  // initialOpen only for desktop-review
export const STATUS_LABELS: Record<HubStatus, string>;                                   // in SupportThread.tsx
export function TicketRow(props: { ticket: SupportTicket; onOpen: () => void }): JSX.Element;
export function SupportThread(props: { ticket: SupportTicket; onBack: () => void }): JSX.Element;
```
- Categorieën: `BUG` "Probleem", `FEATURE_REQUEST` "Suggestie", `QUESTION` "Vraag". Statussen: `NEW` "Nieuw", `IN_PROGRESS` "In behandeling", `WAITING_FOR_USER` "Wacht op jou", `RESOLVED` "Opgelost", `CLOSED` "Gesloten". Tabs "Nieuw" en "Mijn meldingen". Knop "Versturen". Toasts: verstuurd "Melding verstuurd."; in wachtrij "Geen verbinding. De melding wordt verstuurd zodra er weer internet is." Leeg: "Nog geen meldingen verstuurd." Thread: afzender "Jij" bij `senderRole.toLowerCase() === "user"`, anders "ThoughtVault"; antwoordknop "Antwoord versturen"; terugknop met `aria-label="Terug naar mijn meldingen"`.

- [ ] **Step 1: Write the failing tests**

```tsx
// FeedbackWidget.test.tsx (replaces the clipboard test)
vi.mock("../../services/supportRelay", async (orig) => ({ ...(await orig<object>()),
  listTickets: vi.fn(async () => [{ id: "a", ref: "TV-2", status: "WAITING_FOR_USER", category: "BUG", description: "Notule mislukt", createdAt: "2026-11-10T10:00:00Z", unread: true }]),
  ticketMessages: vi.fn(async () => []) }));
vi.mock("../../stores/supportStore", async (orig) => ({ ...(await orig<object>()), withInstallation: (fn: any) => fn({ id: "i", secret: "s" }) }));
vi.mock("../../services/api", () => ({ api: { submitFeedback: vi.fn(), getUnreadFeedbackCount: vi.fn() } }));

it("sends a manual report through the support store without a title field", async () => {
  const submitManual = vi.fn(async () => "sent" as const);
  useSupportStore.setState({ submitManual });
  // render <FeedbackWidget/>, click [aria-label="Feedback openen"]
  expect(container.querySelector('input[type="text"]')).toBeNull();
  // select FEATURE_REQUEST, fill textarea " Synthetic feedback ", click "Versturen"
  expect(submitManual).toHaveBeenCalledWith("FEATURE_REQUEST", "Synthetic feedback");
  expect(container.querySelector("textarea")?.value).toBe("");
  expect(api.submitFeedback).not.toHaveBeenCalled();
});

it("lists my reports with hub status labels and opens the thread", async () => {
  // open widget, click tab "Mijn meldingen"
  expect(container.textContent).toContain("TV-2");
  expect(container.textContent).toContain("Wacht op jou");
  // click the ticket row
  expect(container.querySelector('[aria-label="Terug naar mijn meldingen"]')).not.toBeNull();
});
```

```tsx
// SupportThread.test.tsx
vi.mock("../../../services/supportRelay", async (orig) => ({ ...(await orig<object>()),
  ticketMessages: vi.fn(async () => [
    { id: "1", body: "Notule mislukt", senderRole: "USER", createdAt: "2026-11-10T10:00:00Z" },
    { id: "2", body: "Opgelost in 1.0.312", senderRole: "ADMIN", createdAt: "2026-11-10T11:00:00Z" }]),
  postMessage: vi.fn(async () => ({ id: "3", body: "Dank je", senderRole: "USER", createdAt: "2026-11-10T12:00:00Z" })) }));
vi.mock("../../../stores/supportStore", async (orig) => ({ ...(await orig<object>()), withInstallation: (fn: any) => fn({ id: "i", secret: "s" }) }));

it("shows the thread, refreshes the unread count and sends a reply", async () => {
  const refreshUnread = vi.fn(async () => {});
  useSupportStore.setState({ refreshUnread });
  // render <SupportThread ticket={ticket} onBack={vi.fn()} />
  expect(host.textContent).toMatch(/Jij.*Notule mislukt.*ThoughtVault.*Opgelost in 1\.0\.312/s);
  expect(refreshUnread).toHaveBeenCalled();
  // fill reply "Dank je", click "Antwoord versturen"
  expect(postMessage).toHaveBeenCalledWith({ id: "i", secret: "s" }, "a", "Dank je");
  expect(host.textContent).toContain("Dank je");
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd windows && npx vitest run src/components/__tests__/FeedbackWidget.test.tsx src/components/support/__tests__/SupportThread.test.tsx`
Expected: FAIL.

- [ ] **Step 3: Bouw `SupportThread.tsx` en zet de widget om**

- `FeedbackWidget`: haalt `useSettingsStore`/`isLocal`, `title`-state en het titelveld, de klembordtak en alle `api.*Feedback*`-aanroepen weg. Teller uit `useSupportStore((s) => s.unread_count)`. Lijst via `withInstallation(listTickets)` bij openen van "Mijn meldingen"; fout geeft de lege staat plus toast "Meldingen ophalen lukt nu niet." Een gekozen ticket toont `<SupportThread>` in hetzelfde paneel. Stijl en opbouw van paneel, kop en tabs blijven zoals ze zijn.
- `SupportThread`: laadt `withInstallation(i => ticketMessages(i, ticket.id))` (markeert gelezen op de hub) en daarna `refreshUnread()`; berichten op `createdAt` oplopend; antwoord via `postMessage`, het nieuwe bericht wordt achteraan toegevoegd. `TicketRow` en `STATUS_LABELS` staan in dit bestand zodat de widget onder 400 regels blijft.
- `desktop-review.tsx`: in de nep-`invoke` een tak voor `"proxy_request"` die op `args.request.url` antwoordt met `{status: 200, body}`: `/tickets` `{data: [...], pagination: {}}` met twee tickets (`WAITING_FOR_USER` met `unread: true`, `RESOLVED`), `/tickets/<id>/messages` `{data: [...]}` met twee berichten, `/unread-count` `{data: {count: 1}}`. Routes `"/support"`: `<FeedbackWidget initialOpen />`; `"/support-thread"`: `<SupportThread ticket={reviewTicket} onBack={() => history.back()} />`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd windows && npx vitest run && heavy run --label tv-support-build -- npm run build`
Expected: alle tests PASS, build zonder fouten. `wc -l src/components/FeedbackWidget.tsx` onder 400.

- [ ] **Step 5: Screenshots**

Screenshotprocedure met routes `/support` (naam `widget`) en `/support-thread` (naam `thread`). Controleer dat het paneel op 320 niet buiten beeld valt (`Math.min(360, window.innerWidth - 40)` bestaat al).

- [ ] **Step 6: Commit**

```bash
git add windows/src/components/FeedbackWidget.tsx windows/src/components/support windows/src/components/__tests__/FeedbackWidget.test.tsx windows/src/desktop-review.tsx
git commit -m "Send Windows feedback to the support relay and show replies"
```

---

### Task 12: Schakelaar en identiteit in `AccountTab`, teller in `Sidebar`

**Files:**
- Modify: `windows/src/components/settings/AccountTab.tsx` (16 regels nu)
- Modify: `windows/src/components/layout/Sidebar.tsx:72` (instellingenitem) en `SidebarItem` (r.78-105)
- Test: `windows/src/components/settings/__tests__/AccountTab.test.tsx`, `windows/src/components/layout/__tests__/Sidebar.test.tsx`

**Interfaces:**
- Consumes: Task 6 `useSupportStore` (`auto_report`, `setAutoReport`, `name`, `email`, `setIdentity`, `unread_count`), `isValidEmail`; Task 11 `FeedbackWidget`.
- Produces: `SidebarItem` krijgt `badge?: number`; bij `badge > 0` een `<span className="sidebar-item-badge" aria-label={\`${badge} ongelezen\`}>{badge}</span>`.
- Teksten: schakelaar "Foutrapporten automatisch versturen" met onderschrift "Bij een mislukte opname, transcriptie of notule en bij een crash. Zelf melden werkt altijd."; velden "Naam" en "E-mailadres" onder kop "Contact voor meldingen".

- [ ] **Step 1: Write the failing tests**

```tsx
// AccountTab.test.tsx
vi.mock("../../FeedbackWidget", () => ({ default: () => null }));
it("toggles automatic reports and saves only a valid e-mail", async () => {
  useSupportStore.setState({ auto_report: true, name: "Jan", email: "jan@example.nl" });
  // render <AccountTab/>
  const toggle = host.querySelector<HTMLInputElement>('[aria-label="Foutrapporten automatisch versturen"]')!;
  await act(async () => toggle.click());
  expect(useSupportStore.getState().auto_report).toBe(false);
  // fill e-mail "jan@" and blur
  expect(useSupportStore.getState().email).toBe("jan@example.nl");
  // fill e-mail "jan@prezent.nl" and blur
  expect(useSupportStore.getState().email).toBe("jan@prezent.nl");
});
```

```tsx
// Sidebar.test.tsx: extra test
it("shows the unread count on Instellingen only when there is something unread", async () => {
  useSupportStore.setState({ unread_count: 2 });
  // render <MemoryRouter><Sidebar/></MemoryRouter>
  expect(host.querySelector('a[href="/settings"] .sidebar-item-badge')?.textContent).toBe("2");
  await act(async () => useSupportStore.setState({ unread_count: 0 }));
  expect(host.querySelector(".sidebar-item-badge")).toBeNull();
  expect(host.querySelectorAll(".sidebar a")).toHaveLength(6);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd windows && npx vitest run src/components/settings/__tests__/AccountTab.test.tsx src/components/layout/__tests__/Sidebar.test.tsx`
Expected: FAIL.

- [ ] **Step 3: Implementeer**

- `AccountTab`: in de groep "Feedback" de schakelaar (zelfde opbouw en klassen als de schakelaar "Automatisch bijwerken" in `GeneralTab.tsx` r.28-30, met `aria-label="Foutrapporten automatisch versturen"`), daarna "Contact voor meldingen" met twee invoervelden die bij `blur` `setIdentity` aanroepen als de naam niet leeg is en `isValidEmail` klopt; anders terugzetten naar de opgeslagen waarde. `FeedbackWidget` blijft staan.
- `Sidebar`: `badge={unread}` op het instellingenitem met `const unread = useSupportStore((s) => s.unread_count);`. Badge inline gestyled zoals de teller in `FeedbackWidget.tsx` r.137-157 (rood rondje, `var(--status-error)`), ook zichtbaar in ingeklapte stand.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd windows && npx vitest run && heavy run --label tv-support-build -- npm run build`
Expected: alle tests PASS, build zonder fouten.

- [ ] **Step 5: Screenshots**

In `desktop-review.tsx` vóór het renderen `useSupportStore.setState({ unread_count: 1 })`. Screenshotprocedure met route `/settings?tab=account` (naam `account`); de teller staat op het instellingenitem in de zijbalk.

- [ ] **Step 6: Commit**

```bash
git add windows/src/components/settings windows/src/components/layout windows/src/desktop-review.tsx
git commit -m "Add the automatic report switch and unread count on Windows"
```

---

### Task 13: MSI op de Windows-pc en bewijs van begin tot eind

Voorwaarden: Tasks 1-12 op `feat/support-windows`, volledige checks groen; fase a staat live (relay op `https://thoughtvault.yinga.ai/support`, hub-tool `thought-vault` met voorvoegsel `TV`). Controle relay: `curl -s -o /dev/null -w '%{http_code}\n' -X POST https://thoughtvault.yinga.ai/support/installations -H 'Content-Type: application/json' -d '{}'` geeft 400 of 422, geen 404 of 502.

**Files:** geen codewijziging. Bewijs in het rapport.

- [ ] **Step 1: Volledige checks op de branch**

```bash
cd /Volumes/SSD/Projects/thoughtvault-support-windows/windows && npx vitest run && heavy run --label tv-support-build -- npm run build
cd src-tauri && heavy run --label tv-support-cargo -- cargo test --lib
```
Expected: alles PASS. Uitvoer in het rapport.

- [ ] **Step 2: Testversie en bron**

Kies met Michel een versienummer dat geen andere branch al als kandidaat heeft gebouwd; synchroniseer met `scripts/sync-version.sh` in de worktree (alleen lokaal, niet committen op `main`). Bouw volgens `docs/WINDOWS-BUILD-WORKFLOW.md`, sectie "Lokale pilot-MSI met bestaande releasekey": gehashte bronkopie naar de Windows-pc, aanwezige npm-, Cargo- en WiX-caches, `npm run tauri -- build --bundles msi --ci`. Bewaar exitcode en log. Een falende updater-ondertekening na een gemaakte MSI is voor deze testinstallatie acceptabel en wordt zo gemeld; dit is geen leverbaar pakket. Geen GitHub-push, geen workflowdispatch, geen publicatie.

- [ ] **Step 3: Installeren met terugweg**

Back-up van de geïnstalleerde versie en van `%APPDATA%\nl.prezent.transcript-studio` en `%LOCALAPPDATA%\nl.prezent.transcript-studio`. MSI installeren. Starten: het naamscherm verschijnt; vul een testnaam en Michels eigen e-mailadres in.

- [ ] **Step 4: Herhaalde fout wordt één ticket met teller 2**

Zet in Instellingen de notuleverwerking op Ollama met adres `http://127.0.0.1:9`, neem een korte opname op en laat de notule twee keer mislukken. In de hub: `list_tickets` voor `thought-vault` toont precies één nieuw `TV`-ticket; `get_ticket` toont diagnostics (stap `notule`, foutmelding, klikpad, versie, OS, apparaat), een bericht met bijlage `thoughtvault-log.txt` en een vervolgbericht met teller 2. Zoek in `%APPDATA%\nl.prezent.transcript-studio\logs\thoughtvault.log` op de opnametitel en op `C:\Users\`: geen treffers.

- [ ] **Step 5: Crash tijdens transcriberen**

Start de verwerking van een lange opname en beëindig ThoughtVault via Taakbeheer terwijl hij transcribeert. Start opnieuw: in de hub verschijnt een melding met stap `transcriberen` en foutmelding "gestopt tijdens transcriberen". Sluit de app daarna netjes af en start opnieuw: geen nieuwe crashmelding.

- [ ] **Step 6: Zonder netwerk**

Zet het netwerk uit, laat de notule opnieuw mislukken, zet het netwerk aan. De melding komt binnen enkele seconden na het `online`-event alsnog binnen (teller 3 op hetzelfde ticket).

- [ ] **Step 7: Antwoord komt terug in de app**

Na akkoord van Michel `reply_ticket` op het ticket. Breng het ThoughtVault-venster naar voren: de teller op Instellingen toont 1. Open Instellingen, Account, "Probleem melden of suggestie", "Mijn meldingen", het ticket: het antwoord staat in de thread en de teller verdwijnt.

- [ ] **Step 8: Afronden**

Testtickets sluiten met `set_ticket_status` (`CLOSED`). Met Michel beslissen of de testversie blijft of de back-up terugkomt. Eigen buildmappen, bronkopieën, logs en screenshots op Mac en Windows-pc verwijderen. Rapport met: build-exitcode, MSI-hash, ticketnummers, schermafbeeldingen uit Tasks 10-12, en wat niet gelukt of niet getest is.
