# Functionele audit ThoughtVault — 29 september 2026

## Doel en bewijsniveau

Kernbelofte: een opname of audiobestand omzetten in een betrouwbare, bewerkbare notule. Deze audit beoordeelt de macOS- en Windows-desktopclient. **W** betekent waargenomen in de geïnstalleerde macOS-app; **C** is een conclusie uit de huidige broncode; **G** is door de gebruiker gemelde ervaring. Windows kon op deze Mac niet visueel worden gecontroleerd. Er zijn geen productfuncties gewijzigd en geen opnames of exports gemaakt.

De geïnstalleerde macOS-app is **1.0.252** (`/Applications/ThoughtVault.app/Contents/Info.plist`). De onderzochte broncode is **1.0.254** ([VERSION](../VERSION), [Xcode-project](../ThoughtVault.xcodeproj/project.pbxproj)). Schermwaarnemingen mogen daarom niet automatisch aan 1.0.254 worden toegeschreven.

De soundwave is op verzoek uitgesteld; de eerdere mock-up blijft een apart experiment en telt niet als bewijs voor het product.

## Functiematrix

Legenda: ✓ aanwezig, ◐ aanwezig met beperking, ✕ blokkeert of ontbreekt, ? niet uitvoerbaar geverifieerd. Dit is een broncodebeoordeling tenzij W vermeld staat.

| Stap | macOS lokaal | macOS cloud | Windows lokaal | Windows cloud |
|---|---|---|---|---|
| Zonder account starten | ✓ W: Home zichtbaar | ◐ login nodig | ✕ loginpoort vóór lokale schermen | ◐ login nodig |
| Microfoon/videocall opnemen | ✓ C, W: startscherm zichtbaar; rechten ontbreken op test-Mac | ✓ C | ◐ C: na login | ✓ C |
| Eigen audiobestand importeren | ✓ C, W: importactie zichtbaar | ✓ C | ✕ geen bestandskiezer gevonden | ✕ geen bestandskiezer gevonden |
| Transcriptie + notule verwerken | ◐ C: lokaal model én provider vereist | ◐ C: server/verbinding vereist | ◐ C: na login, model en provider vereist | ◐ C: server vereist |
| Voortgang en fout herstellen | ◐ C: taken, bewaarde opname en herverwerken | ◐ C: offline wachtrij en herverwerken | ◐ C: balk toont lokale fout, Taken niet | ◐ C: offline wachtrij, herverwerken via bewaarde opnames |
| Notule bekijken | ✓ C; W: bestaande notulen open | ✓ C; W: bestaande cloudnotulen open | ◐ C: na login | ✓ C |
| Betrouwbare inhoud en leesbare opmaak | ◐ C: geen inhoudelijke eindcontrole | ◐ W: opmaakprobleem; steekproef roept vragen op over besluitstatus | ◐ C: gegenereerde HTML zonder inhoudelijke eindcontrole | ? C: servergeneratie buiten deze broncode |
| Titel en notule bewerken | ◐ C: opslagfout lokaal kan onzichtbaar blijven | ✓ C | ◐ C: na login, opslag in `localStorage` | ◐ C: fout bij opslaan kan editor sluiten |
| Tags bewerken | ◐ C: lokale opslag zonder foutterugkoppeling | ✓ C | ✕ lokale tagactie roept server aan | ✓ C |
| Exporteren | ✓ C: PDF, TXT, Markdown, Obsidian | ✓ C | ◐ C: na login, PDF/TXT/MD/HTML/Obsidian | ✓ C |

Bronnen voor de hoofdroute: [macOS toegang en tabs](../macos/App/ContentView.swift#L87), [macOS dispatch](../macos/ViewModels/RecordingViewModel.swift#L486), [macOS detail](../macos/Views/TranscriptsView.swift#L1097), [Windows toegang en routes](../windows/src/App.tsx#L348), [Windows lokaal proces](../windows/src/services/localPipeline.ts#L24), [Windows detail](../windows/src/pages/TranscriptsPage.tsx#L84).

## Bevindingen op prioriteit

### P0 — Windows lokale modus is niet zelfstandig bereikbaar (C)

**Verwachting:** lokale opname en verwerking werken zonder serveraccount. **Gedrag:** `ProtectedRoutes` stuurt iedere niet ingelogde gebruiker naar `/login`, ongeacht `processing_mode`; de moduskeuze staat pas in Instellingen achter die route. De macOS-client omzeilt de loginpoort expliciet in lokale modus. Dit blokkeert de hele Windows offline reis op een nieuw apparaat of na uitloggen. Reproduceerbaar: start Windows zonder geldige sessie, probeer Instellingen of Opnemen te openen; de route eindigt op login. Visuele Windows-verificatie ontbreekt. [Windows routepoort](../windows/src/App.tsx#L348), [Windows moduskeuze](../windows/src/pages/SettingsPage.tsx#L259), [macOS tegenvoorbeeld](../macos/App/ContentView.swift#L87).

### P1 — Inhoud en opmaak van de notulen voldoen niet aan de kernbelofte (G, W, C)

**Verwachting:** de eerste blik geeft een korte, controleerbare samenvatting, echte besluiten en concrete acties; voorstellen blijven herkenbaar als voorstellen. **Gebruikersmelding:** de output is inhoudelijk en qua opmaak onvoldoende. **Waarneming op macOS 1.0.252:** een bestaande afgeronde notule van 18 september heeft dezelfde lange titel in de appkop en opnieuw als grote documentkop. Daarna volgen metadata, aanwezigen en lange tekstblokken; besluiten en acties liggen onder veel scrollwerk. Het document gebruikt een grijs/roze eigen uiterlijk in de paarse app. In deze steekproef staat een stellige formulering onder *Besluit* terwijl de bekeken ruwe transcriptie ook veel verkennende taal bevat. Of dat concrete besluit elders in het volledige gesprek expliciet is genomen, is met de beperkte steekproef **niet vastgesteld**. Dat vraagt transcript-tegen-notulecontrole, geen automatische conclusie dat het verzonnen is. Reproduceerbaar: open de afgeronde notule van 18 september in **Notulen**, vergelijk het eerste scherm en de sectie *Besluiten* met de tab **Transcriptie**. Vermijd gebruik van dit ene document als algemene kwaliteitsmeting.

**Technische aanwijzingen, zonder oorzakelijke toeschrijving aan dit cloudrecord:** de ingebouwde zakelijke prompt verbiedt verzonnen besluiten en vraagt expliciete eigenaars, maar levert tegelijk een lang HTML-sjabloon met een eigen `<style>`-blok. macOS neemt die stijlen in de WebView over; Windows rendert gesaneerde gegenereerde HTML binnen eigen `.prose`-CSS. De huidige lokale macOS- en Windows-pipelines verwijderen hoogstens code fences en slaan daarna de HTML op als afgeronde notule; er is geen controle op lege secties, placeholders, onderbouwde besluiten of actie-eigenaars. Bij lange transcripties vat macOS lokaal eerst delen samen, wat detailverlies kan geven; het is hier niet als oorzaak van de bekeken cloudnotule aangetoond. Apple Foundation Models gebruikt bovendien een korter sjabloon dan de andere lokale providers. [Zakelijk profiel](../windows/src/data/profileTemplates.json#L3), [macOS HTML-weergave](../macos/Views/Components/EditableHTMLWebView.swift#L151), [Windows weergave](../windows/src/components/transcripts/TranscriptDetail.tsx#L126), [macOS lokale voltooiing](../macos/ViewModels/RecordingViewModel.swift#L875), [Windows lokale voltooiing](../windows/src/services/localPipeline.ts#L123), [macOS lange transcripties](../macos/Services/LLMService.swift#L238), [compact Apple-sjabloon](../macos/Services/LLMService.swift#L394).

**Advies:** definieer één documentstructuur voor beide platforms en laat de app de vormgeving bepalen. Toon bovenaan maximaal enkele regels kernuitkomst, daar direct onder besluiten, acties met eigenaar en termijn, en open punten; zet het uitgebreide verslag lager. Laat het model gestructureerde inhoud aanleveren in plaats van gekopieerde CSS. Controleer vóór *Afgerond* of de notule leesbare inhoud heeft, geen sjabloonresten bevat en besluiten en actietoewijzingen herleidbaar zijn tot de transcriptie. Onzekere punten moeten expliciet als voorstel of open vraag worden weergegeven. Valideer dit met een kleine set echte transcripties, inclusief ruis, stilte, lange gesprekken en gesprekken zonder besluit, in lokale en cloudmodus. Een promptwijziging alleen is geen voldoende kwaliteitscontrole.

### P1 — Een als afgerond getoonde notule kan geen notule zijn (W)

**Verwachting:** “Afgerond” betekent dat er bruikbare bronspraak en een verslag zijn. **Waarneming op macOS 1.0.252:** in Notulen staat een afgerond item waarvan de notule om een ontbrekende transcriptie vraagt; op tab Transcriptie staat alleen `...`. Meer bestaande items in de lijst vertonen hetzelfde patroon. Reproduceerbaar zonder wijzigingen: open **Notulen → opname van 11 augustus 2026, 09:40 → Notule → Transcriptie**. De gebruikersimpact is hoog: het product presenteert mislukte verwerking als een geslaagde notule. De oorzaak ligt mogelijk in een eerder cloudverwerkingspad of de server; die is met deze clientaudit niet vastgesteld. De huidige macOS lokale broncode weigert wel een lege transcriptie en bewaart gedeeltelijke resultaten apart. [Lokale controle](../macos/ViewModels/RecordingViewModel.swift#L780), [Detailweergave](../macos/Views/TranscriptsView.swift#L1639). Advies: valideer inhoud vóór de status “afgerond”, markeer onbruikbare resultaten als herstelbaar en bied hertranscriptie aan.

### P1 — Windows kan geen willekeurig audiobestand importeren (C)

**Verwachting:** een bestaand WAV/MP3/M4A-bestand kiezen en omzetten. **Gedrag:** de Windows opnamepagina biedt opnemen, YouTube en “Opgeslagen opnames”; dat laatste leest alleen bestanden uit de eigen opnamemap. Er is in de client geen bestandskiezer of externe importactie gevonden. De macOS opnamepagina toont wel “Audiobestand” en `importAudioFile` kopieert de keuze naar de opnamemap. Reproduceerbaar: open Windows Opnemen en zoek een importactie voor een bestand buiten de eigen opnamemap; alleen eigen opnames zijn herverwerkbaar. Visuele Windows-verificatie ontbreekt. [Windows opnamepagina](../windows/src/pages/RecordingPage.tsx#L438), [Windows bewaarde opnames](../windows/src/components/recording/SavedRecordings.tsx#L42), [macOS import](../macos/ViewModels/RecordingViewModel.swift#L519).

### P1 — Windows lokale tags werken niet; lokale notulen hebben een opslaglimiet (C)

De detailpagina toont tags ook voor lokale records, maar toevoegen en verwijderen roepen uitsluitend server-API's aan. In lokale modus faalt dat of vereist alsnog een server. Scenario: maak een lokale notule, open Tags, voeg een tag toe; `handleAddTag` doet `api.updateTranscriptTags` zonder `isLocalId`-tak. [Tagacties](../windows/src/pages/TranscriptsPage.tsx#L316).

Windows bewaart complete lokale notulen en transcripties in `localStorage` (ongeveer 5–10 MB volgens de broncommentaar). Dat is kwetsbaar voor een groeiend archief en opslagquota. De lokale pipeline vangt een eventuele opslagfout niet als aparte persistentiestap af; een gedeeltelijke transcriptie moet juist behouden blijven bij generatieproblemen. macOS gebruikt SwiftData. Advies: verplaats Windows lokale documenten naar duurzame appopslag en maak schrijffouten zichtbaar. [Lokale store](../windows/src/stores/localTranscriptsStore.ts#L5), [Pipeline](../windows/src/services/localPipeline.ts#L89), [macOS opslag](../macos/Services/LocalTranscriptStore.swift#L190).

### P1 — Lokale herstelstatus is onduidelijk op Windows (C)

De lokale pipeline zet fouten in `backgroundTasks`, maar de pagina **Taken** gebruikt een aparte serverstore die in lokale modus bewust een lege lijst teruggeeft. Daardoor kan een mislukte lokale taak in de verwerkingsbalk staan terwijl Taken “Geen actieve taken” zegt. De balk biedt bij fouten alleen sluiten; herverwerken kan pas via “Opgeslagen opnames”. Scenario: laat een lokale model- of providerstap falen, open Taken en vergelijk de balk met de pagina. Visuele Windows-verificatie ontbreekt. [Lokale pipeline](../windows/src/services/localPipeline.ts#L137), [Taken-store](../windows/src/stores/tasksStore.ts#L26), [Taken-pagina](../windows/src/pages/TasksPage.tsx#L337), [Balk](../windows/src/components/ProcessingBar.tsx#L83). Advies: één taakbron en een expliciete herstelactie met de bewaarde opname.

### P2 — Bewerkacties kunnen succes suggereren ondanks opslagfout (C)

Op macOS vangt `LocalTranscriptStore.persist()` schrijffouten af en logt die alleen; lokale titel, tags en notule worden in de detailweergave direct als bewaard behandeld. Op Windows vangt `handleSaveNotule` de API-fout zelf af, maar retourneert normaal; `TranscriptDetail.saveNotuleEdit` sluit daarna de editor. De foutmelding is zichtbaar, maar de niet bewaarde tekst staat niet meer in de bewerkmodus. [macOS store](../macos/Services/LocalTranscriptStore.swift#L228), [macOS detail](../macos/Views/TranscriptsView.swift#L1953), [Windows handler](../windows/src/pages/TranscriptsPage.tsx#L153), [Windows editor](../windows/src/components/transcripts/TranscriptDetail.tsx#L109). Advies: laat opslagresultaat of fout doorlopen tot de UI en behoud de concepttekst bij mislukking.

### P2 — Zichtbare acties en benamingen spreken de route tegen (C)

- Windows toont een **Notitie**-knop tijdens opname die uitgeschakeld is. macOS heeft op die plaats een werkend notitieveld. Advies: werk de Windows actie af of verberg haar tot ze werkt. [Windows knop](../windows/src/pages/RecordingPage.tsx#L699), [macOS actie](../macos/Views/RecordingView.swift#L1323).
- Windows Home zegt “Tik om direct te beginnen met opnemen”, maar de knop navigeert alleen naar Opnemen; er volgt nog een tweede klik op de microfoon. Advies: verander de tekst naar “Ga naar Opnemen” of start echt direct. [Home knop](../windows/src/pages/HomePage.tsx#L127), [navigatie](../windows/src/pages/HomePage.tsx#L80).
- Windows Home verwijdert ook lokale records via `api.deleteTranscript`, terwijl de Notulen-pagina hiervoor wel de lokale store gebruikt. De Home-actie faalt in lokale modus zonder feedback. [Home verwijderen](../windows/src/pages/HomePage.tsx#L91), [werkende lokale tak](../windows/src/pages/TranscriptsPage.tsx#L108).
- De Windows zijbalk en login voeren nog **ThoughtVault** als productnaam, terwijl de macOS-app ThoughtVault toont. Advies: één naam in de gebruikersreis. [Zijbalk](../windows/src/components/layout/Sidebar.tsx#L39), [login](../windows/src/pages/LoginPage.tsx#L202).

### P2 — macOS opnamescherm vraagt veel scrollen in een normaal venster (W)

In het geïnstalleerde venster (ongeveer 1100 × 750) staan zes profielkeuzes en twee importverwijzingen in de linker kolom. “Opgeslagen opnames” valt onder de zichtbare onderrand, terwijl rechts onder de opnamekaart veel lege ruimte overblijft. Een herstelroute is daardoor minder vindbaar. Code heeft wel een compacte breedtevariant, maar de hoogte is niet op deze standaardvenstermaat geoptimaliseerd. Advies: beperk de eerste profielrij tot de gekozen stijl plus een uitklapper en zet import en herverwerken in één duidelijke sectie. [Opname-layout](../macos/Views/RecordingView.swift#L55), [bewaarsectie](../macos/Views/RecordingView.swift#L630).

## Bereikbare schermen en advies

| Onderdeel | macOS | Windows | Advies | Reden |
|---|---|---|---|---|
| Home | tab | route `/` | **Behouden**, CTA verduidelijken | Oriëntatie, snelle toegang en recente notulen; geen tweede opnameflow nodig. |
| Opnemen | tab; import, YouTube indien ingeschakeld | route; opname, YouTube indien ingeschakeld, eigen opnames | **Behouden**, Windows import toevoegen | Primaire ingang. |
| Taken / verwerkingsbalk | tab en balk | route en balk | **Samenvoegen** tot één taakbron; **verplaatsen** van fout-herstel naar de taak zelf | Dubbele status, lokaal op Windows inconsistent. |
| Notulenlijst en detail | tab met detailnavigatie | route met detailpaneel | **Behouden**, documentkop en inhoudshiërarchie **samenvoegen** | Kernresultaat en editor/export; titel staat nu dubbel en belangrijke uitkomsten staan te laag. |
| Profielen | via Instellingen | eigen route én blok in Instellingen | **Samenvoegen** | Ondersteunt notulekwaliteit, maar dubbele toegang en grote configuratielast. |
| Mensen/deelnemers | tab en picker | route en picker | **Behouden**, **verplaatsen** van keuze naar opnamecontext | Namen kunnen notulen verbeteren; beheer is secundair. |
| Instellingen | tab met lokaal/cloud, AI, agenda, account | route met lokaal/cloud, AI, agenda, Obsidian | **Behouden**, taakvereisten voor lokale modus vooraan | Benodigde afhankelijkheden zijn nu makkelijk te missen. |
| Account/login/2FA | LoginView en Account via Instellingen | login, Account-route | **Behouden** voor cloud; **verplaatsen** achter optionele cloudactie in lokale modus | Account hoort de lokale kernreis niet te blokkeren. |
| Admin | alleen admin-tab | alleen admin-route | **Verplaatsen** buiten de dagelijkse notulenflow | Beheerfunctie zonder direct nut bij opname → notule. |
| Zwevende opnamebediening / menubalk | beide aanwezig | opnamewidget aanwezig | **Behouden** | Bediening terwijl een vergadering elders op het scherm loopt. |
| YouTube, Microsoft 365, Obsidian | contextueel of in Instellingen | contextueel of in Instellingen | **Verplaatsen** naar optionele integraties | Nuttig, maar geen voorwaarde voor een betrouwbare basisnotule. |

Inventarisbronnen: [macOS tabs](../macos/App/ContentView.swift#L8), [macOS vensters en menubalk](../macos/App/ThoughtVaultApp.swift#L21), [macOS profiel/account-koppelingen](../macos/Views/SettingsView.swift#L662), [Windows routes](../windows/src/App.tsx#L364), [Windows zijbalk](../windows/src/components/layout/Sidebar.tsx#L66). “Verwijderen” adviseer ik nu alleen voor de uitgeschakelde Windows Notitie-knop als die niet wordt afgemaakt; er is geen productcode verwijderd.

## Eerstvolgende besluiten

1. Maak de notule zelf betrouwbaar en leesbaar: toets beslissingen en acties aan de transcriptie, verwijder dubbele titel en geef kernuitkomsten bovenaan voorrang. Controleer een vaste transcriptset in beide modi en op beide platforms.
2. Herstel de Windows lokale toegang en importeerroute; deze blokkeren de beloofde gebruikersreis.
3. Definieer “afgerond” als **bruikbare transcriptie én notule**; geef onbruikbare uitvoer een herstelstatus. Onderzoek de waargenomen macOS-cloudrecords in het serverpad.
4. Maak lokale opslag en bewerken aantoonbaar veilig: duurzame Windows-opslag, lokale tags, expliciete schrijffouten.
5. Verenig taakstatus en herstel in beide clients, daarna pas secundaire schermen vereenvoudigen.

## Verificatiegrens

Op deze Mac is de geïnstalleerde macOS-app read-only bekeken: Home, Opnemen, Notulenlijst, twee afgeronde items en hun Notule/Transcriptie-weergave. De app meldt ontbrekende microfoon-, schermopname- en spraakherkenningsrechten; er is daarom geen nieuwe opname gestart en geen volledige verwerking uitgevoerd. De inhoudsbeoordeling is een beperkte steekproef van bestaande cloudrecords, geen systematische juistheidsmeting. Cloudgedrag is uit code en bestaande records afgeleid, niet met een nieuwe upload getest. Windows-schermen, permissies, exportdialoog en echte offline verwerking zijn hier niet direct uitgevoerd. De in dit rapport genoemde Windows-scenario's zijn concrete reproductiestappen voor een Windows-testmachine.
