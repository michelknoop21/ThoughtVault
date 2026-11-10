# Fase e: privacyverklaring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Een door Michel vastgestelde privacyverklaring op `https://thoughtvault.yinga.ai/privacy.html`, gelinkt vanuit de voettekst van de site en vanuit de apps, plus een checklist om het privacylabel in App Store Connect bij te werken.

**Architecture:** Eén statische pagina `privacy.html` naast `index.html` in `docs/design/high-end-yinga/`, op `landing.css`, meegenomen in de bestandslijst van `scripts/deploy-website.sh` en gecontroleerd door `scripts/check-website.py`. De apps linken naar de vaste URL vanaf de schermen die fase b en c aanmaken. Livegang pas na akkoord van Michel op de tekst en op de deploy.

**Tech Stack:** HTML/CSS (bestaande site), nginx-container uit `deploy/website/`, Python 3 (`check-website.py`), `pw` voor schermafbeeldingen, SwiftUI en React/Tauri voor de links.

**Spec:** `docs/plans/2026-11-10-foutrapporten-feedbackhub.md` op branch `docs/plan-foutrapporten-feedbackhub` (lezen met `git show docs/plan-foutrapporten-feedbackhub:docs/plans/2026-11-10-foutrapporten-feedbackhub.md`), hoofdstuk 2 besluiten 6, 7, 8 en hoofdstuk 5 "Fase e".

## Global Constraints

- Werk in een eigen worktree op een eigen branch vanaf `origin/main`: `git -C /Volumes/SSD/Projects/thoughtvault-native fetch && git -C /Volumes/SSD/Projects/thoughtvault-native worktree add ../thoughtvault-fase-e -b feat/fase-e-privacy origin/main`. Nooit committen op `main`: een commit daar start de releasepipeline. De hoofdwerkmap niet aanraken.
- Websitetekst en UI-tekst Nederlands, geen em-dash of en-dash als gedachtestreepje. Roep vóór het schrijven van de privacytekst de skill `anti-slop-text` aan.
- Geen nieuwe npm-pakketten.
- Windows-checks (Task 5): `cd windows && npx vitest run && npm run build` en `cd windows/src-tauri && cargo test --lib`. Zware builds via `heavy run --label <naam> -- <commando>`.
- Handelingen op servers (deploy, SSH naar n8n01, ook `check-website.py`, dat via SSH een geheim leest) alleen na akkoord van Michel.
- De tekst gaat niet live voordat Michel hem letterlijk heeft goedgekeurd (Task 3).
- De verklaring mag het automatisch opruimen in de feedback-hub niet als werkend presenteren zolang dat niet bestaat. Op 10 november heeft `feedback-hub/backend/src` geen opruimtaak; dat wordt een aparte taak in de hub-repo, waar een andere sessie actief is.
- Vaste URL van de pagina: `https://thoughtvault.yinga.ai/privacy.html`. De voettekstlink op de site gebruikt `href="/privacy.html"`.
- Vaste inhoud volgens de spec: wat (naam, e-mailadres, installatiekenmerk, app-versie, besturingssysteem en apparaat, klikpad, afgeschermd logbestand), waarvoor (fouten oplossen, meldingen beantwoorden in de app en per e-mail), wat nooit (opnames, transcripties, notules, titels), waar (n8n01 en de feedback-hub), hoe lang (twaalf maanden na het sluiten van een melding; het lokale log zeven dagen of 5 MB), uitzetten (schakelaar "Foutrapporten automatisch versturen") en bezwaar.
- Commitberichten in het Engels in de stijl van `git log origin/main`, zonder AI-attributie of trailers.

## Review Focus

1. De pagina lekt het geheime downloadpad (`/d-<token>/`) niet, ook niet via een link of voorbeeld. Controle: `/privacy.html` in de lus van `check-website.py` r.23-27 (Task 2).
2. De pagina is publiek en vindbaar: status 200, `text/html`, geen `noindex` in `X-Robots-Tag`, eigen canonical, en de voettekst van `/` linkt ernaar. Controle: nieuwe asserts in `check-website.py` (Task 2) en `curl -sI` na deploy (Task 4).
3. Op 320 px breed loopt niets buiten beeld: lange woorden zoals `thoughtvault.yinga.ai`, het e-mailadres en "installatiekenmerk" breken af in plaats van horizontaal scrollen. Controle: `pw screenshot` op de vijf breedtes, beoordeeld op 320 (Task 1) en live (Task 4).
4. De verklaring noemt de schakelaar met exact dezelfde naam als de apps, zodat iemand hem kan vinden. Controle: assert op "Foutrapporten automatisch versturen" in `check-website.py` (Task 2) en grep in de appcode (Task 5).
5. De tekst belooft geen automatische verwijdering die nog niet bestaat. Controle: `grep -n -i "automatisch" docs/design/high-end-yinga/privacy.html` in de akkoordstap, elke treffer naast Michels besluit gelegd (Task 3).

---

## Bestanden

| Bestand | Rol | Taak |
| --- | --- | --- |
| `docs/design/high-end-yinga/privacy.html` | nieuw, de verklaring | 1, 3 |
| `docs/design/high-end-yinga/index.html` | voettekstlink | 1 |
| `docs/design/high-end-yinga/landing.css` | alleen als de pagina een paar regels nodig heeft (lange woorden afbreken) | 1 |
| `scripts/deploy-website.sh:12` | `privacy.html` in de lijst | 1 |
| `deploy/website/Dockerfile`, `deploy/website/default.conf.template` | alleen als die een vaste bestandslijst of exacte locaties hebben | 1 |
| `scripts/check-website.py` | privacypagina controleren | 2 |
| Swift- en Windowsbestanden uit fase b en c | link naar de pagina | 5 |

---

### Task 1: Conceptpagina, voettekstlink en deploylijst

**Files:**
- Create: `docs/design/high-end-yinga/privacy.html`
- Modify: `docs/design/high-end-yinga/index.html` (voettekst)
- Modify: `scripts/deploy-website.sh:12`
- Modify (alleen indien nodig): `docs/design/high-end-yinga/landing.css`, `deploy/website/Dockerfile`, `deploy/website/default.conf.template`

**Interfaces:**
- Consumes: niets.
- Produces: `privacy.html` met `<link rel="canonical" href="https://thoughtvault.yinga.ai/privacy.html">`, dezelfde robots-meta als `index.html` (`content="index,follow"`), en de letterlijke tekst "Foutrapporten automatisch versturen" en "twaalf maanden". Een voettekstlink `href="/privacy.html"` met tekst "Privacyverklaring" in `index.html`. Task 2 controleert precies deze strings.

- [ ] **Step 1: Lees de bestaande opmaak**

Lees in de worktree `docs/design/high-end-yinga/index.html` (head, header, FAQ en voettekst) en `landing.css`. Noteer of de site je of u gebruikt en neem dat over. Lees `deploy/website/Dockerfile` en `deploy/website/default.conf.template` en stel vast of een nieuw bestand in `docs/design/high-end-yinga/` vanzelf op `/privacy.html` wordt geserveerd, en met welke headers (`X-Robots-Tag`, `Cache-Control`, CSP). Is er een vaste bestandslijst of een exacte `location`, voeg `privacy.html` daar toe met dezelfde headers als `/`.

- [ ] **Step 2: Schrijf het concept**

Roep `anti-slop-text` aan. Bouw `privacy.html` op uit de head van `index.html` (zelfde fonts, `landing.css`, favicon, robots-meta), een eigen `<title>Privacyverklaring ThoughtVault</title>`, eigen meta-description en canonical, dezelfde header en voettekst, en één tekstkolom. `landing.js` alleen meenemen als header of voettekst ervan afhangen.

Secties in deze volgorde, met koppen in gewone taal:

1. Wie verantwoordelijk is en hoe je contact opneemt. Naam, adres en e-mailadres laat je open als `[INVULLEN: ...]`; Michel vult ze in Task 3.
2. Wanneer ThoughtVault iets verstuurt: bij een crash en bij een opname, transcriptie of notule die mislukt of vastloopt, automatisch; en als je zelf een melding stuurt.
3. Wat er dan meegaat: naam en e-mailadres die je bij de eerste start invult, een willekeurig installatiekenmerk, app-versie, besturingssysteem en apparaat, de foutmelding, het klikpad (namen van schermen en knoppen, nooit wat je typt), en een afgeschermd logbestand waarin titels, bestandsnamen, deelnemers en e-mailadressen zijn vervangen door een kort kenmerk.
4. Wat nooit meegaat: opnames, transcripties, notules en titels.
5. Waarvoor: fouten opsporen en oplossen, en je melding beantwoorden in de app en per e-mail.
6. Waar het staat: de server n8n01, waar de doorgeefroute installaties en de koppeling tussen fout en melding bijhoudt, en de feedback-hub `feedback.yinga.ai` op dezelfde server. Plaats van de server en eventuele verwerkers laat je open als `[INVULLEN: ...]`.
7. Hoe lang: meldingen met bijlagen tot twaalf maanden na het sluiten; het lokale logbestand op je eigen apparaat maximaal zeven dagen of 5 MB. Formuleer het verwijderen na twaalf maanden voorlopig als `[BESLUIT MICHEL: ...]`, zie Task 3.
8. Uitzetten en bezwaar: de schakelaar "Foutrapporten automatisch versturen" in Instellingen, zelf melden blijft altijd mogelijk en is vrijwillig, en inzage, correctie, verwijdering of bezwaar per e-mail.

Voorbeeldzinnen in de gewenste toon (aanpassen aan je/u van de site):

- "Gaat er bij opnemen, transcriberen of het maken van een notule iets mis, dan stuurt ThoughtVault automatisch een foutrapport. Je opnames, transcripties, notules en titels gaan nooit mee."
- "Het klikpad is een lijst van de schermen en knoppen die je vlak voor de fout gebruikte, zoals 'Opnemen' en 'Stoppen'. Wat je typt, staat er niet in."
- "Wil je geen automatische foutrapporten, zet dan in Instellingen 'Foutrapporten automatisch versturen' uit. Zelf een melding sturen kan daarna nog steeds."

- [ ] **Step 3: Voettekstlink en deploylijst**

Voeg in de voettekst van `index.html` een link `<a href="/privacy.html">Privacyverklaring</a>` toe, in de stijl van de bestaande voettekstlinks. Zet in `scripts/deploy-website.sh` r.12 de lijst op `index.html privacy.html landing.css landing.js`.

- [ ] **Step 4: Lokale weergave en schermafbeeldingen**

Run: `cd docs/design/high-end-yinga && python3 -m http.server 8765` (achtergrond).
Run, voor beide pagina's (`/privacy.html` en `/`, die laatste alleen om de voettekst te zien, met `--full-page`):

```bash
for w in 1920 1440 1280 390 320; do h=$([ $w = 1920 ] && echo 1080 || echo 900); pw screenshot --full-page --viewport-size=${w},${h} http://localhost:8765/privacy.html <scratchpad>/privacy-${w}.png; done
```

Expected: op 1920 en 1440 een begrensde tekstkolom (geen regels over de volle breedte), op 320 geen horizontale scroll en geen afgesneden woorden (Review Focus 3); voettekstlink zichtbaar op `/`. Ontbreekt afbreken bij lange woorden, voeg in `landing.css` voor de tekstkolom `overflow-wrap: anywhere` toe en maak de schermafbeeldingen opnieuw. Server daarna stoppen. Schermafbeeldingen in de scratchpad, niet in de repo.

- [ ] **Step 5: Optioneel lokaal de container**

Als Step 1 een wijziging in `deploy/website/` opleverde: bouw de image lokaal (`heavy run --label fase-e-site -- docker build -f deploy/website/Dockerfile -t tv-site-test .` vanuit de repo-root, of zoals `deploy/website/README.md` voorschrijft), start hem met een nep-`DOWNLOAD_TOKEN` van 64 hex-tekens, en controleer `curl -sI http://localhost:<poort>/privacy.html`: 200, `text/html`, geen `noindex`. Container en image daarna verwijderen.

- [ ] **Step 6: Commit**

```bash
git add docs/design/high-end-yinga/privacy.html docs/design/high-end-yinga/index.html scripts/deploy-website.sh
git commit -m "Add a draft privacy statement page to the website"
```

(plus `landing.css` en `deploy/website/*` als die zijn gewijzigd)

---

### Task 2: `check-website.py` controleert de privacypagina

**Files:**
- Modify: `scripts/check-website.py:23-31`

**Interfaces:**
- Consumes: de strings uit Task 1 (`href="/privacy.html"`, canonical, `content="index,follow"`, "Foutrapporten automatisch versturen").
- Produces: een check die na de deploy in Task 4 PASS geeft en vóór de deploy faalt op `/privacy.html`.

- [ ] **Step 1: Breid de checks uit**

- In de lus van r.23 `'/privacy.html'` toevoegen. Dat dekt status 200, geen geheim in de inhoud (Review Focus 1) en geen `noindex` (Review Focus 2).
- Na r.30: `assert b'href="/privacy.html"' in public`.
- Een blok voor de pagina zelf:

```python
status, headers, privacy = get('/privacy.html')
assert 'text/html' in headers.get('Content-Type', '')
assert b'content="index,follow"' in privacy
assert b'rel="canonical" href="https://thoughtvault.yinga.ai/privacy.html"' in privacy
assert 'Foutrapporten automatisch versturen'.encode() in privacy
assert b'[INVULLEN' not in privacy and b'[BESLUIT' not in privacy
```

- De laatste `print` aanvullen met "privacy page".

- [ ] **Step 2: Syntaxcontrole**

Run: `python3 -m py_compile scripts/check-website.py`
Expected: geen uitvoer, exit 0. Het script draaien tegen de live site gebeurt pas in Task 4, omdat het via SSH een geheim van n8n01 leest.

- [ ] **Step 3: Commit**

```bash
git add scripts/check-website.py
git commit -m "Check the privacy page in the live website check"
```

---

### Task 3: Akkoordstap met Michel

**Files:**
- Modify: `docs/design/high-end-yinga/privacy.html` (alleen de wijzigingen die Michel opgeeft)

**Interfaces:**
- Consumes: concept en schermafbeeldingen uit Task 1.
- Produces: een vastgestelde tekst zonder `[INVULLEN` of `[BESLUIT`, en een notitie van Michels akkoord (datum en zijn letterlijke bericht) in het commitbericht.

- [ ] **Step 1: Leg het concept en de open besluiten voor**

Geef Michel de pagina als platte tekst plus de schermafbeeldingen op 1440 en 390, en vraag per punt een besluit:

1. Verantwoordelijke: naam (persoon of bedrijf), adres, KvK-nummer als dat erbij hoort, en het e-mailadres voor vragen, inzage en bezwaar.
2. Opruimen na twaalf maanden. Het automatisch opruimen in de hub bestaat nog niet. Keuze: (a) de pagina gaat pas live als de hub-taak af is en de tekst mag dan "automatisch" zeggen; of (b) nu live met een toezegging zonder automatiek, bijvoorbeeld "We verwijderen gesloten meldingen met bijlagen uiterlijk twaalf maanden na het sluiten.", terwijl Michel tot de hub-taak af is met de hand opruimt.
3. Wat er met de installatieregistratie in de doorgeefroute gebeurt (kenmerk, gehashte sleutel, eerste en laatste contact): geen bewaartermijn in de spec. Voorstel: twaalf maanden na het laatste contact verwijderen.
4. Plaats van de server (n8n01) en verwerkers die de pagina moet noemen, zoals de hostingpartij en de dienst waarmee de hub e-mail verstuurt.
5. Grondslag en klachtrecht: de spec noemt ze niet. Voorstel: gerechtvaardigd belang voor automatische foutrapporten (met de schakelaar om ze uit te zetten), je eigen verzoek voor zelf gestuurde meldingen, en een zin over klagen bij de Autoriteit Persoonsgegevens. Michel beslist of dit erin komt en in welke vorm.
6. Je of u, als de site daar niet eenduidig in is.

- [ ] **Step 2: Verwerk de besluiten**

Pas de pagina aan volgens Michels antwoorden.
Run: `grep -n -E "\[INVULLEN|\[BESLUIT" docs/design/high-end-yinga/privacy.html`
Expected: geen treffers.
Run: `grep -n -i "automatisch" docs/design/high-end-yinga/privacy.html`
Expected: alleen treffers over automatisch versturen van foutrapporten, en een treffer over automatisch verwijderen alleen als Michel optie (a) koos en de hub-taak af is (Review Focus 5).
Run: `grep -n -P "\x{2014}|\x{2013}" docs/design/high-end-yinga/privacy.html`
Expected: geen treffers.

- [ ] **Step 3: Laatste akkoord op de definitieve tekst**

Toon Michel de definitieve tekst en schermafbeeldingen opnieuw (Task 1 Step 4 opnieuw draaien). Ga pas door met zijn expliciete akkoord.

- [ ] **Step 4: Commit**

```bash
git add docs/design/high-end-yinga/privacy.html
git commit -m "Finalize the privacy statement text approved on <datum>"
```

---

### Task 4: Deploy naar de website

**Files:** geen wijzigingen.

**Interfaces:**
- Consumes: branch met Task 1 tot en met 3.
- Produces: `https://thoughtvault.yinga.ai/privacy.html` live, `check-website.py` PASS.

- [ ] **Step 1: Akkoord voor de deploy**

Vraag Michel om akkoord voor: een kopie van de live site op n8n01, `bash scripts/deploy-website.sh` vanaf deze branch, en `python3 scripts/check-website.py`. Zonder akkoord stopt deze taak.

- [ ] **Step 2: Backup**

Lees `scripts/deploy-website.sh` vanaf r.25 en noteer welke kopie het script zelf maakt (de spec noemt een backup van het live Caddyfile). Maak ook zelf een kopie van de map van de live website op de server:
`ssh -o BatchMode=yes n8n01 'cp -a /home/michelk/thoughtvault-website /home/michelk/thoughtvault-website.bak-$(date +%Y%m%d%H%M)'`
Expected: exit 0; noteer het backuppad.

- [ ] **Step 3: Deploy en controle**

Run: `bash scripts/deploy-website.sh`
Expected: exit 0, `caddy validate` zonder fout.
Run: `python3 scripts/check-website.py`
Expected: eindigt met de PASS-regel inclusief "privacy page".
Run: `curl -sI https://thoughtvault.yinga.ai/privacy.html`
Expected: `HTTP/2 200`, `content-type: text/html`, geen `x-robots-tag` met `noindex`.

Faalt een stap: zet de backup terug (`ssh n8n01` de map terugkopiëren en de container herstarten zoals het script dat doet) en meld het aan Michel.

- [ ] **Step 4: Live schermafbeeldingen**

Dezelfde lus als Task 1 Step 4 tegen `https://thoughtvault.yinga.ai/privacy.html`, plus `/` met `--full-page` op 1440 en 390 voor de voettekst. Beoordeel 320 opnieuw (Review Focus 3).

---

### Task 5: Links vanuit de apps (wacht op fase b, fase c en Task 4)

Start pas als fase b (`macos/Views/SupportIdentityView.swift`, `macos/Views/SettingsView+Support.swift`) en fase c (`windows/src/components/support/IdentityGate.tsx`, `windows/src/components/settings/AccountTab.tsx`) op `origin/main` staan en Task 4 live is. Maak dan een nieuwe worktree vanaf de actuele `origin/main`.

**Files:**
- Modify: `macos/Views/SupportIdentityView.swift` (link onder de twee zinnen over foutrapporten)
- Modify: `macos/Views/SettingsView+Support.swift` (link direct onder de schakelaar "Foutrapporten automatisch versturen")
- Modify: het iOS-instellingenscherm waar fase b de schakelaar zette (zoek `supportAutoReport`)
- Modify: `macos/Resources/nl.lproj/Localizable.strings` en de Engelse tegenhanger (pad volgen zoals fase b ze gebruikte)
- Modify: `windows/src/components/support/IdentityGate.tsx`, `windows/src/components/settings/AccountTab.tsx` (link onder de schakelaar, zoek `auto_report`)
- Modify: `windows/src/services/supportRelay.ts` (constante)
- Test: de bestaande testbestanden van `IdentityGate` en `AccountTab` uit fase c, of nieuwe in `windows/src/components/support/__tests__/` en `windows/src/components/settings/__tests__/`

**Interfaces:**
- Consumes: de schermen uit fase b en c.
- Produces: Swift `enum SupportLinks { static let privacy = URL(string: "https://thoughtvault.yinga.ai/privacy.html")! }` in `SupportIdentityView.swift` (geen nieuw bestand, dus geen extra target-lidmaatschap); TypeScript `export const PRIVACY_URL = "https://thoughtvault.yinga.ai/privacy.html";` in `supportRelay.ts`. Linktekst nl "Privacyverklaring", en "Privacy statement".

- [ ] **Step 1: Schrijf de falende Windows-tests**

```tsx
it("opens the privacy statement from the identity gate", ...)
  // mock @tauri-apps/plugin-shell open; render IdentityGate; klik "Privacyverklaring" → open aangeroepen met PRIVACY_URL
it("shows the privacy statement link next to the auto-report switch", ...)
  // render AccountTab; link "Privacyverklaring" aanwezig; klik → open(PRIVACY_URL)
```

Run: `cd windows && heavy run --label fase-e-vitest -- npx vitest run src/components/support src/components/settings`
Expected: FAIL, link ontbreekt.

- [ ] **Step 2: Implementeer de Windows-links**

Een `<button type="button" className="link">` of de linkstijl die fase c al gebruikt, die `open(PRIVACY_URL)` uit `@tauri-apps/plugin-shell` aanroept (zelfde import als `UpdateBanner.tsx`; `shell:allow-open` staat al in `capabilities/default.json`).

- [ ] **Step 3: Windows-checks**

Run: `heavy run --label fase-e-vitest -- npx vitest run && heavy run --label fase-e-build -- npm run build`, dan `cd src-tauri && heavy run --label fase-e-cargo -- cargo test --lib`
Expected: alles groen.

- [ ] **Step 4: Implementeer de Swift-links**

SwiftUI `Link(String(localized: "support.privacy.link"), destination: SupportLinks.privacy)` op de drie plekken, met `TS.Font`/`TS.Spacing` en `Color.brandPrimary` zoals de omliggende views. Sleutel `"support.privacy.link"` in nl en en.

- [ ] **Step 5: macOS-checks**

Run: `heavy run --label fase-e-xcode -- xcodebuild test -project ThoughtVault.xcodeproj -scheme ThoughtVault -destination 'platform=macOS'` (niet terwijl `/Applications/ThoughtVault.app` draait) en een build van schema `ThoughtVault AppStore`.
Expected: `TEST SUCCEEDED` en `BUILD SUCCEEDED`.

- [ ] **Step 6: Controle schakelaarnaam en schermafbeeldingen**

Run: `git grep -n "Foutrapporten automatisch versturen" -- macos windows/src docs/design/high-end-yinga/privacy.html`
Expected: treffers in alle drie (Review Focus 4).
Schermafbeeldingen: Windows via de `desktop-review.tsx`-pagina's met `pw screenshot` op 1920×1080, 1440, 1280, 390 en 320; macOS op een screenshotbuild in eigen container, nooit onder de echte bundle-ID; iOS in de simulator, die daarna afsluiten. Controleer dat een klik de pagina in de standaardbrowser opent.

- [ ] **Step 7: Commit**

```bash
git add macos windows/src
git commit -m "Link the privacy statement from the support screens"
```

---

### Task 6: Privacylabel in App Store Connect (handmatig, Michel)

Hangt af van fase b (`macos/PrivacyInfo.xcprivacy` bijgewerkt) en Task 4. De uitvoerder bouwt niets; hij geeft Michel deze checklist en legt Michels bevestiging vast.

- [ ] **Step 1: Vergelijk met het manifest**

Lees `macos/PrivacyInfo.xcprivacy` op `origin/main` en zet de gedeclareerde gegevenstypen naast de lijst hieronder. Meld verschillen aan Michel voordat hij begint.

- [ ] **Step 2: Checklist voor Michel in App Store Connect (App Privacy)**

- [ ] Privacy Policy URL: `https://thoughtvault.yinga.ai/privacy.html`.
- [ ] Contact Info, Name: verzameld, doel App Functionality, gekoppeld aan de gebruiker, niet voor tracking.
- [ ] Contact Info, Email Address: staat er al; doel App Functionality controleren, gekoppeld, niet voor tracking.
- [ ] Diagnostics, Crash Data: verzameld, App Functionality, gekoppeld, niet voor tracking.
- [ ] Diagnostics, Other Diagnostic Data (logbestand, app-versie, apparaat): verzameld, App Functionality, gekoppeld, niet voor tracking.
- [ ] Identifiers: het installatiekenmerk. Michel kiest tussen Device ID en User ID; het is een willekeurig kenmerk per installatie.
- [ ] Usage Data, Product Interaction: het klikpad (schermen en knoppen) valt in Apples indeling onder deze categorie. De spec noemt alleen naam en crash- of diagnosegegevens voor `PrivacyInfo.xcprivacy`. Michel beslist; kiest hij voor opnemen, dan moet het manifest uit fase b ook worden aangevuld.
- [ ] Audio Data en User Content (opnames, transcripties, notules): niet verzameld via deze route; bestaande antwoorden ongewijzigd laten.
- [ ] Publiceren van de wijziging in App Store Connect.

- [ ] **Step 3: Vastleggen**

Noteer Michels bevestiging (datum en wat hij koos bij Identifiers en Product Interaction) in het sessieverslag van die dag in `docs/sessions/`.

Afronding na alle fasen (buiten dit plan, volgens de spec): DEC-062 in `docs/DECISIONS.md`, nummer vlak voor gebruik op de remote controleren.
