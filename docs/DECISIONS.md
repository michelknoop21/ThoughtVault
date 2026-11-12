# ThoughtVault — Architectural Decision Records

_Append-only log. Each entry records context, decision, and consequences._

_Decisions DEC-029 through DEC-038 archived to [archive/DECISIONS-DEC-029-to-DEC-038.md](archive/DECISIONS-DEC-029-to-DEC-038.md)._

_Decisions DEC-039 through DEC-053 archived to [archive/DECISIONS-DEC-039-to-DEC-053.md](archive/DECISIONS-DEC-039-to-DEC-053.md)._

---

## DEC-065: Lange meetings: dekking per deel, één verificatie per notulezin

**Date:** 2026-11-10
**Status:** Accepted

**Context:** `auditNotule` stuurt één verzoek met de hele bron en de hele notule, en weigert vooraf zodra bron plus notule boven 400 eenheden (zinnen) of 64.000 tekens komen. Het schadebezoek uit DEC-062 heeft 932 bronzinnen en 42.831 tekens; het kwam nooit verder dan die grens. Sinds DEC-063 levert zo'n meeting wel een notule op, maar altijd met de algemene regel "We konden niet automatisch controleren of alles in de notule klopt" onder "Even nalopen". Een gesprek van een uur werd dus nooit inhoudelijk gecontroleerd.

**Decision:**
1. Tot en met 400 eenheden en 64.000 tekens verandert niets: hetzelfde ene verzoek met dezelfde systeemprompt en hetzelfde gebruikersbericht, zodat de prompt-hashes van de M3-gate geldig blijven.
2. Boven die grens loopt de controle in twee stappen. **Stap 1, dekking per deel:** de transcriptiezinnen (T) gaan in volgorde in delen. Elk verzoek bevat de hele notule, één deel van de transcriptie en alle gebruikersnotities (Q), samen binnen 400 eenheden en 64.000 tekens. Het model geeft alleen bronoordelen: `covered` met de N-zinnen die de bronzin bewaren, of `non_factual`, `missing`, `uncertain` met lege evidence. Elk antwoord wordt direct gecontroleerd: precies de ID's van dat verzoek, ieder één keer, evidence alleen naar bestaande notulezinnen, `uncertain` bovenaan exact `false`. De oordelen over een Q-zin uit verschillende delen worden samengevoegd tot het strengste (`uncertain`, dan `missing`, dan `covered`, dan `non_factual`).
3. **Stap 2, één verificatie per notulezin:** uit de `covered`-oordelen volgt per notulezin welke bronzinnen hem citeren. Elke geciteerde notulezin krijgt een eigen verzoek met alleen die zin, de citerende bronzinnen als bewijs en per geciteerde T-zin de drie buren aan elke kant als aparte lijst `context`, ook over een deelgrens heen. Context mag een kwalificatie, voorwaarde, ontkenning of intrekking zichtbaar maken, maar telt nooit als steun: `supported` met een ID uit de context wordt afgewezen. Notulezinnen zonder enige citatie gaan samen in één verzoek zonder bewijs, waarin alleen koppen, opmaaklabels, begroetingen en herhalingen `non_factual` mogen zijn en de rest `unsupported` is.
4. De afwijzingen en de regels voor "Even nalopen" zijn dezelfde als in het korte pad (DEC-063). Bewijs voor een bronzin komt alleen uit notulezinnen die stap 2 als `supported` beoordeelde. Een bronzin die in stap 1 `covered` was maar geen zo'n notulezin overhoudt, wordt `missing`, zodat de melding de bronzin noemt en niet "Ontbrekend controlebewijs". Een probleem met een notulezin wordt vóór een bronprobleem gemeld.
5. Elke fout sluit af: een mislukt verzoek, onleesbare JSON, verkeerde ID's of een onzeker antwoord eindigt in een afwijzing, nooit in een goedkeuring. Een annulering (Swift `CancellationError`, Windows `AbortError`) gaat ongewijzigd door.

**Begrenzing:**
- Hoogstens 8 delen (`MAX_AUDIT_PARTS`) en hoogstens 150 notulezinnen (`MAX_NOTE_CHECKS`), dus hoogstens 8 + 150 + 1 = 159 verzoeken per controle. Is er meer nodig, of past één stap-2-verzoek met bewijs en context niet binnen 400 eenheden en 64.000 tekens, dan volgt vooraf de bestaande fout "Deze inhoud is te groot of onvolledig voor betrouwbare controle; beoordeel het concept". Bij te veel notulezinnen of delen gaat er geen enkel verzoek uit; bij een te groot stap-2-verzoek is stap 1 al gelopen en start stap 2 niet.
- Stap 1 loopt na elkaar (gewijzigd op 12 november 2026: de delen lopen tegelijk, zie de wijziging onderaan). Stap 2 draait hoogstens 4 verzoeken tegelijk en leest de uitkomsten in volgorde van de notule, zodat bij meerdere problemen steeds het eerste wordt gemeld. Na het eerste probleem start er geen nieuw verzoek meer. Verzoeken die al lopen worden afgewacht en genegeerd, niet afgebroken: op macOS leest `NotuleGenerator` een `CancellationError` uit een verzoek als annulering door de gebruiker, en op Windows neemt het verzoek geen abortsignaal aan.
- macOS en Windows delen constanten, prompts en foutteksten letterlijk (`NotuleAuditLong.swift` en het lange pad in `notuleAudit.ts`).

**Alternatives considered:**
- De bron in delen opdelen, elk deel tegen de hele notule laten beoordelen en de notuleoordelen samenvoegen (de eerste versie van deze branch). De review vond zes manieren waarop dat een foute notule goedkeurde of de verkeerde melding gaf. Een `uncertain` uit het ene deel werd overschreven door `supported` uit een ander deel. Bronoordelen werden pas na het samenvoegen gecontroleerd, dus een deel kon oordelen over ID's die het nooit had gezien. "Dit is alleen een fictief voorbeeld" in deel 1 en de actie in deel 2 werden los beoordeeld en allebei goedgekeurd. Gebruikersnotities zaten alleen in het laatste deel en werden nooit naast eerdere transcriptie gelegd. Een verzonnen actiehouder of termijn die in geen enkel deel stond, kon via het samenvoegen alsnog `supported` worden. Een tegenspraak in een later deel leverde "Ontbrekend controlebewijs" op in plaats van de tegenspraak. Het nieuwe ontwerp voegt geen notuleoordelen meer samen: elke notulezin krijgt één oordeel, op zijn eigen bewijs.
- De grens van 400 eenheden verhogen: één verzoek met 932 zinnen vraagt het model om honderden ID's foutloos terug te geven, en `gpt-oss:120b` gaf al bij 300 zinnen niet voor elke zin een oordeel (DEC-062).

**Aanvaarde beperkingen:**
- Een intrekking of herziening die meer dan drie zinnen van de geciteerde bronzin staat, ziet stap 2 niet. Stap 1 ziet hem alleen als hij in hetzelfde deel valt.
- Een tegenspraak tussen een gebruikersnotitie en de transcriptie wordt per deel gezien. Elke T-zin staat in één deel naast alle Q-zinnen, maar twee T-zinnen in verschillende delen worden nooit naast elkaar gelegd.
- `auditSource` (DEC-062) houdt zijn eigen grens: bron plus gebruikersnotities boven 64.000 tekens geeft "De bron is te groot of onvolledig". Op beide platforms vangt de notulegenerator die fout op als elke andere controlefout (`NotuleGenerator.generate` op macOS, `LLMService.generateNotulen` op Windows): `auditNotule` wordt dan niet meer aangeroepen en de notule krijgt de algemene regel. Het lange pad helpt dus alleen meetings boven 400 eenheden met hoogstens 64.000 tekens transcriptie, zoals het schadebezoek. Langere meetings blijven ongecontroleerd tot `auditSource` een eigen besluit krijgt.

**Consequences:**
- Een meeting als het schadebezoek kost met een notule van 60 zinnen 3 dekkingsverzoeken en hoogstens 60 verificatieverzoeken, in plaats van geen controle.
- Elke geciteerde notulezin is een los modelverzoek. Bij een lokaal model telt die wachttijd mee tot de notule klaar is; vier tegelijk beperkt dat, maar maakt het niet gratis.
- Tests: `NotuleAuditPartsTests.swift` en `notuleAuditParts.test.ts` dekken dezelfde scenario's, waaronder precies 8 delen, de tekenbegroting, de kwalificatie over een deelgrens, de verzonnen termijn, het verzoekenvenster van 4 en het doorgeven van een annulering.

**Wijziging 2026-11-12 (besluit eigenaar, 12 november 2026):**
- Stap 1 loopt niet meer na elkaar. De delen gaan hoogstens 4 tegelijk (`auditConcurrency`, dezelfde grens als stap 2). Reden: wachttijd. Het schadebezoek wachtte in stap 1 op drie verzoeken achter elkaar, nu op het traagste van de drie.
- De uitkomst blijft gelijk aan een run na elkaar. De delen worden pas samengevoegd als alle delen klaar zijn, in de volgorde van de delen, dus de oordelen en de evidence van een Q-zin staan in dezelfde volgorde als voorheen. De controle per deel ("Ongeldig controlebewijs") en het doorgeven van een annulering zijn ongewijzigd.
- Faalt een deel, dan wordt de eerste fout in de volgorde van de delen gemeld, ook als een later deel eerder klaar was, en start er geen nieuw deel meer. Delen die al liepen worden afgewacht en genegeerd. Een afgewezen lange controle kan daardoor tot drie verzoeken meer kosten dan voorheen.

---

## DEC-064: Foutrapporten, meldingen en bijwerken via de support-relay

**Date:** 2026-11-10
**Status:** Accepted

**Context:** Bij een fout in opnemen, transcriberen of de notule zag de gebruiker een melding en had niemand anders iets gehoord. De oude feedbackmodule hing aan een login en een backend die op n8n01 niet meer draait. Voor de pilot moeten fouten vanzelf bij de feedback-hub aankomen, moet de gebruiker antwoord krijgen en moeten updates zonder gedoe binnenkomen. Plan: `docs/plans/2026-11-10-foutrapporten-feedbackhub.md` met fasen a tot en met e. Het contract en de bediening staan in `docs/SUPPORT-RELAY.md`.

**Decision:**
1. **Geen login.** Bij de eerste start vraagt de app naam en e-mailadres, ook van bestaande gebruikers, zonder "Later" en zonder bevestigingsmail. Elke installatie maakt een willekeurig id en geheim; dat paar is de `userId` in de hub.
2. **Antwoorden** komen in de app (Mijn meldingen, teller voor ongelezen) en per e-mail van de hub.
3. **Automatische meldingen** alleen bij een crash en bij een mislukte of vastgelopen opname, transcriptie of notule. Gelijke fouten gaan in één ticket met teller. Geen schermafbeelding. Inhoud: getoonde melding, fase, ruwe fout, klikpad, versie, OS, apparaat en logbestand. De schakelaar "Foutrapporten automatisch versturen" staat standaard aan.
4. **Logbestand per platform** met maskering bij het schrijven: titels, bestandsnamen, deelnemers en e-mailadressen worden een kort `k-`-token. Nooit tekst van transcript of notule. Bewaartijd 7 dagen of 5 MB.
5. **Crashdetectie** met een markering die ook de lopende fase opslaat. Een WhisperKit-transcriptie die blijft hangen komt na herstart binnen als "gestopt tijdens transcriberen". Meldingen die niet lukken blijven in een offlinewachtrij.
6. **De relay houdt de hub-sleutel**, de apps niet. Er is geen instelscherm. De apps praten met een pad onder `thoughtvault.yinga.ai/support`.
7. **Hub:** tool `thought-vault`, prefix `TV`. Het oude feedbackmodule blijft als dode code staan. iOS deelt de Swift-code; Android bestaat niet meer.
8. **Updates:** stil downloaden, installeren bij afsluiten en nooit tijdens opnemen of verwerken, met schakelaar en "Zoek naar updates". macOS via Sparkle wacht, omdat de pilot via TestFlight loopt.
9. **Bewaartermijn** 12 maanden na sluiten, plus een privacyverklaring (fase e). De pilot start pas na fase a tot en met e.

**Alternatives considered:**
- Relay als routes in de oude backendcontainer: die container bestaat op n8n01 niet meer.
- Apps rechtstreeks naar de hub met de sleutel in de app: de sleutel is uit de binary te halen.
- Relay als n8n-workflow: geen tests, en rate limiting en dedup worden onbeheersbaar.
- Bevestigingsmail bij het eerste gebruik: extra stap en een mailroute die er niet is.
- Schermafbeelding bij automatische meldingen: vergaderinhoud zou in de hub belanden.

**Afwijkingen tijdens de uitvoering:** de relay draait als eigen container `thoughtvault-support` (niet in `n8n_transcript_studio`); de slug is `thought-vault`, omdat `thoughtvault` het prefix `TH` had gegeven; `logAttached` en `Retry-After` kwamen erbij na de branchreview; de hubsleutel is via de connectstap van de hub gemaakt en rechtstreeks in de `.env` op de server gezet.

**Consequences:**
- Fase a (relay) staat live, fase b tot en met e zijn in uitvoering. Vóór de pilot ontbreken nog de privacytekst en het automatisch opruimen van gesloten tickets in de hub.
- Elke melding kan de melder een e-mail van de hub opleveren. Testen tegen de echte relay gebeurt daarom alleen met `@example.com`.
- De relay draait met één worker met een proceslock voor dedup en een limiter in het geheugen; beide laten zich niet zonder aanpassing opschalen.

---

## DEC-063: De inhoudscontrole waarschuwt in plaats van te blokkeren

**Date:** 2026-11-10
**Status:** Accepted (vervangt punt 2 en 3 van DEC-062)

**Context:** De opname `combined_1794312568.wav` (17 minuten, 150 bronzinnen) kreeg geen notule. De melding was "Ontbrekend controlebewijs bij T9. Het concept is apart bewaard". T9 was de opvulzin "Dus ik doe zomaar met, nou ja, je pakt nou bijvoorbeeld prospect flow." `gpt-oss:120b` gaf die zin de status `covered`, terwijl geen enkele notulezin ernaar verwees, en `verdicts` wees daarop de hele notule af. Bij 150 zinnen moet elke verwijzing in het antwoord kloppen, dus een echte opname haalt die poort zelden. In de store hadden alleen de twee korte opnames (2.431 en 2.896 tekens) een notule.

**Decision:**
1. Een notule wordt altijd opgeslagen. Een fout in `auditNotule` blokkeert niet meer, maar komt als regel in de notule. Annuleren blijft annuleren, en een leeg of onbruikbaar concept blijft een fout.
2. Alle waarschuwingen staan in één laatste sectie "Even nalopen", als lijstje in gewone taal. De broncontrole van DEC-062 schrijft daar ook in; de kop "Let op: controleer de transcriptie" vervalt.
3. Bij een inhoudelijke bevinding noemt de regel wat er aan de hand is en citeert de zin, bijvoorbeeld: Dit staat in de notule, maar is misschien niet zo gezegd: “Iris belt de leverancier vóór vrijdag.” Kan de controle niet worden afgerond (ontbrekend bewijs, onvolledig antwoord, te lange bron, onzeker oordeel, opmaak), dan staat er één algemene regel. Interne codes zoals T9 komen niet meer in beeld.
4. De controle zelf (prompts, `verdicts`, foutmeldingen in de audit) is ongewijzigd. Alleen de plek die de fout opvangt (`NotuleGenerator` op macOS, `LLMService.generateNotulen` op Windows) is aangepast. De teksten zijn op beide platforms letterlijk gelijk.

**Alternatives considered:**
- Het model per zin zonder verwijzing opnieuw laten oordelen: een extra verzoek per notule, en zonder blokkade levert het weinig op.
- Een ander model (`mistral-large-4` scoorde 17 van 18 tegen 9 van 18 voor `gpt-oss:120b`): blijft de volgende stap als de algemene regel te vaak verschijnt.

**Consequences:**
- Bij lange opnames met `gpt-oss:120b` zal de algemene regel waarschijnlijk vaak onder de notule staan.
- `NotuleReviewError`, `keepRejectedDraft` en de Windows-tegenhangers worden voor nieuwe notulen niet meer gebruikt. Ze blijven staan zodat bestaande concepten zichtbaar blijven; opruimen is een apart besluit.
- Een eerder afgewezen opname krijgt een notule door hem opnieuw te genereren.
- De M3-gate telt een notule met de sectie "Even nalopen" als `review`.

---

## DEC-062: Broncontrole als waarschuwing, de inhoudscontrole blijft de poort

**Date:** 2026-11-10
**Status:** Accepted

**Context:** De lokale notule gaat door twee modelcontroles. `auditSource` beoordeelt zonder de notule of de transcriptie begrijpelijk is en wees af zodra één inhoudelijke passage niet betrouwbaar te duiden was. Daarna controleert `auditNotule` per bronzin en per notulezin. De broncontrole is gekalibreerd op een schone fictieve bron van 433 tekens (goedgekeurd) en een zwaar verhaspeld fragment van 771 tekens (afgewezen). Op een echte opname werkt dat niet. Met het exacte productieverzoek wees `mistral-large-4` het schadebezoek (Whisper, 42.831 tekens) af, net als `kimi-k2.6`, en in stukken van 4.000 tekens slaagde 0 van 11. Een schone tekst van dezelfde lengte, in dezelfde stukken, slaagde 11 van 11. Gevraagd naar de reden noemde het model in het eerste stuk acht verkeerd verstane passages, zoals "zit het bij de stadshuidloog" en "Het zit op derf". Echte spraakherkenning haalde deze poort dus nooit, en elke lokale notule van een echt gesprek werd een concept ter beoordeling.

**Decision:**
1. `auditSource` wijst niet meer af. Bij `uncertain: true` of een onbruikbaar antwoord geeft hij een waarschuwing terug; bij `uncertain: false` niets. Een lege of te grote bron blijft vóór de aanvraag een fout.
2. `auditNotule` blijft de poort. Die markeert onbegrijpelijke bronzinnen zelf als `uncertain` en wijst dan af.
3. De waarschuwing komt als laatste sectie in de notule ("Let op: controleer de transcriptie"), na de controle, zodat hij niet als bewering wordt gecontroleerd. Een afgewezen concept krijgt dezelfde sectie.
4. De prompt van de broncontrole blijft byte voor byte gelijk op macOS en Windows. Daardoor blijven de prompt-hashes in de M3-gate en de Windows-opnames geldig. Citaten van de onduidelijke passages vragen een andere prompt en dus nieuwe opnames; die zijn niet gedaan.
5. Een antwoord met lege `content` en de JSON alleen in het `reasoning`-veld (gezien bij `kimi-k2.6`) blijft een onbruikbaar antwoord. Er is geen terugval op `reasoning`: dat veld begint met denktekst, en de strikte parser die proza rond de JSON weigert blijft zo.

**Alternatives considered:**
- De broncontrole per stuk uitvoeren: bij echte opnames slaagde geen enkel stuk van 4.000 tekens, dus dat verandert niets aan de uitkomst.
- De broncontrole verwijderen: de waarschuwing is nuttige informatie voor wie de notule leest, en de aanvraag kost één verzoek.
- Terugvallen op het `reasoning`-veld (met of zonder het laatste JSON-object eruit te halen): verzwakt de strikte parser om een incidenteel modelgedrag op te vangen. Het concept ter beoordeling is de veilige uitkomst.

**Consequences:**
- Opname10, de onbegrijpelijke bron uit de QA-set, wordt nu door de inhoudscontrole afgewezen in plaats van door de broncontrole: met echte `kimi-k2.6`-antwoorden via de Windows-route 6 van 6 (`docs/qa/colleague-rollout-2026-11-09/content/kimi-k26-bronwaarschuwing/`). De M3-gate verwacht voor Opname10 nu twee aanvragen in plaats van één.
- Een transport- of HTTP-fout in de broncontrole leidt nu tot een tweede aanvraag (de inhoudscontrole), die dan ook faalt. De uitkomst blijft een concept of transportfout, nooit een goedkeuring.
- Het schadebezoek wordt hiermee nog niet goedgekeurd. Op de hele transcriptie (932 zinnen) weigert de inhoudscontrole vóór de aanvraag: de grens is 400 bron- plus notulezinnen, ongeveer 16.500 tekens transcriptie. Op de eerste 300 zinnen gaf `gpt-oss:120b` niet voor elke zin een oordeel ("Onvolledige inhoudscontrole"). Beide concepten droegen de waarschuwing. Lange gesprekken vragen een apart besluit over de inhoudscontrole.
- Elke bronzin met "niet", "geen", "nooit" of "zonder" wordt een verplicht te behouden zin. In het schadebezoek zijn dat er ongeveer 150, en de notule nam ze letterlijk over. Dat is een apart probleem, buiten dit besluit.

---

## DEC-061: Lerende context: één woordenlijst, één contextblok, voorstellen na de notule

**Date:** 2026-11-09
**Status:** Accepted

**Context:** Namen en vaktermen worden door spraakherkenning steeds opnieuw verkeerd gehoord (in het schadebezoek werd dezelfde organisatie als "SRC" en als "RSC" herkend). De app had daar drie losse mechanismen voor: een vrij tekstveld "Eigen termen" (`personalVocabulary` in UserDefaults), een lijst met correcties (`personal-corrections.json`) en een lijst van maximaal 30 namen in de notuleprompt, plus een aparte correctieprompt. Wat de gebruiker over een persoon wist (functie, organisatie, verantwoordelijkheden) kwam nergens in de notule terecht, en niets leerde uit eerdere gesprekken.

**Decision:**
1. **Woordenlijst v2.** `personal-corrections.json` krijgt `version: 2`. Een term heeft een toelichting van maximaal 200 tekens, mag zonder varianten bestaan en er is een `dismissed`-lijst voor voorstellen die de gebruiker heeft afgewezen. Versie 1 blijft laden. Het oude vrije tekstveld wordt eenmalig omgezet naar termen en daarna verwijderd. De Woordenlijst kreeg een eigen instellingentab met doorzoekbare tabel, teller en een editor met geschiedenis.
2. **Eén contextblok met vaste kop** gaat naar de notule-AI en vervangt de lijst van 30 namen en de correctieprompt. Inhoud: termen met varianten en toelichting, personen met aliassen en verantwoordelijkheden, en termen uit Obsidian-contextnotities. Rol en organisatie gaan alleen mee naar de voorstellenstap: in een echte run met mistral-large-4 (10 november 2026) nam het model ze over in de notule ("Rudy (schade-expert, Achmea)") terwijl het transcript ze niet noemde, en dat botst met de notule-audit. Volgorde: eerst wat in de transcriptie voorkomt, dan wat bij het gekozen profiel hoort, dan nieuwste eerst. Budget 6000 tekens, 1200 voor Apple Intelligence, afgekapt op hele regels. De Whisper-prompt houdt zijn limiet van 30 termen.
3. **Aparte AI-stap na de notule.** Zodra de notule is opgeslagen vraagt `LLMService.complete` op de achtergrond om termen en personen als JSON. De stap slaat over bij Apple Intelligence, bij transcripties boven 64.000 tekens en bij lokale modellen waarvan de context overschreden zou worden (`maxChunkCharacters + 8000`). Fouten worden alleen gelogd. Het parsen is defensief: think-blokken weg, snijden van eerste tot laatste accolade, soepel decoderen, varianten "a / b" splitsen, een hele-woord-match in de transcriptie eisen, bekende, afgewezen, naamloze en eigen items laten vallen, maximaal 8 termen en 8 personen. Resultaat staat in `context-suggestions.json`, per taak.
4. **Regels voor personen** (`PersonMatcher`). Koppelen op exacte naam of een meerwoordige `heardAs` tegen naam of aliassen. Een losse voornaam koppelt alleen als hij uniek is, anders is het resultaat dubbelzinnig en kiest de gebruiker. Bekende personen krijgen aanvullende velden automatisch: soort gesprek, onderwerpen (`expertiseTags`) en verantwoordelijkheden, met bron `gesprek:<taskId>` in de geschiedenis. Rol, organisatie en nieuwe aliassen veranderen alleen via een voorstel. Nieuwe personen ontstaan alleen via een voorstel. Deelnemers krijgen een `personId` en het persoonsdetail toont "Gesprekken". Er komt geen AI-samenvatting per persoon.
5. **Voorstellenbalk** boven de notule: Toevoegen, Bijwerken, een keuze bij twijfel ("Is dit A of B?") en Negeren. Wat genegeerd is komt niet terug.
6. **Geschiedenis als JSON.** `context-history.json` bewaart per persoon of term maximaal 50 versies, met een momentopname vóór elke wijziging en de bron (handmatig, gesprek, voorstel, herstel). Herstellen maakt een nieuwe versie. Opslaan zonder wijziging legt niets vast.
7. **`PersonProfile.responsibilities`** is toegevoegd. De store opent met afgeleide lichte migratie. `AppMigrationPlan` kreeg bevroren geneste modellen V2 en V3 plus V4, alleen door tests gebruikt. Een test opent een echte store in V3-vorm met `makeContainer` van de app.
8. **Testisolatie.** De testhost is de volledige gesandboxte app. Op 9 november 2026 verplaatsten testruns de echte `Local.store` en schreven ze een v2-woordenlijst die de geïnstalleerde app niet kon lezen. Onder XCTest start `AppEntry` nu een lege `TestHostApp`, wijst `AppEnvironment.supportDirectory` naar een tijdelijke map, gebruiken tests eigen watchdog-defaults en een aparte keychain-service, en geeft `PersonalCorrections.loadOrEmpty` bij een onleesbare woordenlijst een lege lijst in plaats van een mislukte notule. Dezelfde bescherming staat op `main` (cherry-pick 861d9eb).

**Alternatives considered:**
- Een tweede lijst naast de bestaande correcties: dubbel onderhoud en twee plekken waar dezelfde term kon afwijken. Eén lijst met een optionele toelichting dekt beide.
- Termen en personen laten voorstellen binnen de notuleaanroep: de notule wordt dan langer en de JSON-vraag verstoort het notuleformaat. Een aparte aanroep kan falen of wegblijven zonder dat de notule lijdt.
- Alles automatisch bijwerken: de eerste prompt gaf 22 termen (vooral gewone verkeerd verstane woorden) en 6 personen, onder wie de gebruiker zelf en personen zonder naam. Zonder bevestiging raakt de woordenlijst daarmee snel vervuild.
- Een AI-samenvatting per persoon: veroudert, is niet te controleren en kost een aanroep per gesprek.
- Geschiedenis als SwiftData `@Model`: elke extra entiteit vraagt een nieuwe schemaversie en een migratie, en de app gebruikt sinds juni 2026 (abde890) geen expliciet migratieplan meer. Een JSON-bestand staat los van het schema.
- Zwaardere migratie voor V4: het nieuwe veld is additief, dus afgeleide lichte migratie volstaat.

**Evaluation:** Op de transcriptie van het schadebezoek met `mistral-large-4` gaf de eerste prompt 22 termen en 6 personen. De aangescherpte prompt gaf 8 specifieke termen (waaronder SRC/RSC naar SAC) en 2 genoemde personen, in 75 seconden.

**Consequences:**
- Windows heeft dezelfde bestandsformaten en prompttekst, maar geen "Gesprekken" en geen koppeling van deelnemers (Windows slaat geen deelnemers op bij transcripties) en geen extra termen uit Obsidian. Nieuwe Tauri-commando's: `read_context_file`, `write_context_file` (atomisch, allowlist, grens 32 MB) en `set_aside_context_file`.
- Niet getest: of een build van vóór V4 een store opent die al naar V4 is gemigreerd. Lukt dat niet, dan zet het vangnet `moveStoreAside` de store opzij (niet verwijderd). Terug naar een oudere build na deze update is daarom af te raden.
- De kwaliteit van de voorstellen hangt af van het model. Bij zwakke of kleine modellen komen er meer ruis en gemiste termen. De stap stelt alleen voor, dus de schade blijft een negeerklik.
- De sleutel `personalVocabulary` is na de eenmalige migratie weg; terugzetten van een oudere build leest hem niet meer.

---

## DEC-060: Notuleprompt per onderwerp en chunkdrempel voor elk Ollama Cloud-model

**Date:** 2026-11-09
**Status:** Accepted

**Context:** Een notule van een schadebezoek (43.000 tekens transcriptie, Ollama Cloud met `gpt-oss:120b`, profiel Standaard) miste feiten die ChatGPT uit dezelfde tekst wel haalde: 29 juli, 11 september 2024, €425, €100 tot €200, de bouwjaren 2006, 2018 en 2022. Zeven acties stonden op "Eigenaar: Nog te bepalen". Chunking speelde in versie 1.0.270 niet mee: de drempel voor hosted gpt-oss stond al op 64.000 tekens. Wel gold die drempel alleen voor gpt-oss-modelnamen, zodat elk ander Ollama Cloud-model weer op 8.000 tekens chunkte.

Eval (zelfde transcriptie, 18 feiten uit de ChatGPT-versie, scratch-script tegen `https://ollama.com/v1/chat/completions`):

| Model | Oude prompt | Nieuwe prompt |
|-------|-------------|---------------|
| gpt-oss:120b | 7/18, 14x "Nog te bepalen" | 9/18, 0x |
| gpt-oss:120b, reasoning high | 9/18, 30x | 8/18, 0x |
| gpt-oss:120b, gechunkt op 8k | 9/18, 13x | niet gemeten |
| mistral-large-4 | 12/18, 7x | 17/18, 0x |
| kimi-k3 | 16/18, 6x | 16/18, 0x |
| glm-5.3 | niet gemeten | 15/18, 0x |
| deepseek-v4-pro | niet gemeten | 13/18, 0x |

Het model bepaalt het grootste deel van het verschil. De prompt haalt "Nog te bepalen" weg en levert bij mistral-large-4 vijf feiten extra op.

**Decision:**
1. `commonRules` (alle profielen): concrete details letterlijk overnemen, indicatie of vermoeden apart benoemen van een afspraak, sprekers bij hun rol noemen als de tekst dat eenduidig maakt, eigenaar en termijn alleen invullen als ze uit de tekst blijken, smalltalk en storingen weglaten. De regel "schrijf 'Nog te bepalen'" is geschrapt.
2. Profiel Standaard: kern, dan één h2 per besproken onderwerp (situatie, vaststelling of inschatting, afspraak), acties als tabel Wie / Actie / Wanneer, daarna openstaande punten. De generator kreeg daarvoor een optioneel `template`-veld per profiel.
3. `OpenAICompatibleLLMService`: 64.000 tekens voor elk model op `https://ollama.com`, niet alleen gpt-oss. Lokale endpoints blijven op 8.000.

**Consequences:** Een vergadering tot ongeveer een uur gaat bij Ollama Cloud in één verzoek. Voor notules op het niveau van de ChatGPT-versie is `mistral-large-4` of `kimi-k3` de aanbevolen keuze; `gpt-oss:120b` blijft bruikbaar maar oppervlakkig. Ingebouwde profielen komen bij elke start uit de bundle, dus er is geen migratie nodig. De backendkopie van de profielen wordt mee gegenereerd maar niet meer door macOS gebruikt.

---

## DEC-059 — Hardened Windows Upload Pipeline na Empirische Weerlegging python-multipart Hypothese

**Date:** 2026-05-06
**Status:** Accepted

**Context:** Bas (Windows-gebruiker) kreeg al sinds versie 1.0.119 sporadisch een 422 `field required` op `POST /tstudio/api/transcribe` bij combined recordings van 91-168 MB. Drie eerdere fixes hebben het niet weggekregen: `cd1c547` (recordings van %APPDATA% naar %LOCALAPPDATA% wegens vermoede OneDrive sync), `93d9f51` (offline-queue retry storms), en `68273fd` (pre-flight integrity check). De integrity check leest het bronbestand één keer end-to-end en stuurt de gemeten `actual_size` naar `reqwest::multipart::Part::stream_with_length()`, maar opent vervolgens een nieuwe handle voor de daadwerkelijke streaming-upload — tussen die twee `tokio::fs::File::open()`-calls kan AV/OneDrive het bestand muteren waardoor de gestreamde bytes niet matchen met de claimde Content-Length, wat python-multipart 0.0.17 in starlette als ontbrekend `file`-veld interpreteert. Tegelijk leefde de hypothese dat python-multipart 0.0.17 zelf een boundary-parsing bug had (versies 0.0.18-0.0.20 hebben relevante fixes). Een reproductie-binary (`/tmp/repro-upload/`) met exact gelijke reqwest 0.12.28 wire format heeft die hypothese empirisch weerlegd: 100 MB random binary multipart upload tegen productie gaf 422 `audio_format_unsupported` (de magic-byte check vóór audio-format-detectie), wat betekent dat het `file`-veld correct werd geëxtraheerd. Backend is dus disculpeerd; bug is client-side op Windows.

**Decision:** `do_proxy_upload()` in `windows/src-tauri/src/commands/http.rs` is herzien om een hele klasse mogelijke oorzaken tegelijk af te sluiten in plaats van één hypothese te chasen. Vijf-staps strategie:

1. **Bron stabiliseren** — bestand wordt eerst gekopieerd naar `std::env::temp_dir()` (op Windows `%LOCALAPPDATA%\Temp`, buiten OneDrive Known Folder Move) via `tempfile::Builder::tempfile_in()`. Post-copy size-verificatie. Auto-cleanup via `TempPath` Drop.
2. **In-memory upload voor ≤200 MB** — `tokio::fs::read()` + `reqwest::multipart::Part::bytes(...)`. Geen streaming, geen race-window tussen Content-Length en bytes-on-wire. Bas's failures (91-168 MB) vallen volledig binnen deze grens. Pre-9c12582 werkte dit al stabiel; we keren terug naar dat patroon, maar nu vanuit de stabiele temp-kopie.
3. **WAV-magic-byte validatie** op de in-memory bytes (`RIFF` + `WAVE`) vóór verzending. Surface AV-induced corruption als heldere client-error in plaats van obscuur server-side 422.
4. **Hardened reqwest client** — explicit `user_agent("ThoughtVault-Windows/{version}")` (ook traceability in nginx logs), `tcp_nodelay(true)`, `pool_max_idle_per_host(0)`, `http1_only()`, `no_proxy()`, `timeout(600s)`. Sluit Nagle-stalls, HTTP/2 ALPN-race, connection-pool reuse bugs en corporate-proxy MITM uit.
5. **Diagnostische correlatie** — SHA-256 prefix wordt berekend over de in-memory bytes en meegegeven als `X-Upload-Sha256` header. Backend `_log_validation_error` in `backend/src/insanely_fast_whisper_api/app/app.py` is uitgebreid om dit veld + peer IP te loggen op `[VALIDATION-422]` lines, zodat een eventuele volgende incident-failure ondubbelzinnig client-hash vs server-hash kan vergelijken.

**Consequences:**
- Files changed: `windows/src-tauri/src/commands/http.rs` (refactor `do_proxy_upload`), `windows/src-tauri/Cargo.toml` (`sha2 = "0.10"` runtime dep, `tempfile` van dev-dep naar runtime dep), `backend/src/insanely_fast_whisper_api/app/app.py:_log_validation_error` (logregel verrijkt).
- Files >200 MB blijven streamen, nu vanuit de geïntegrity-checkte temp-kopie. Voor uploads >250 MB blijft een resterende streaming-race-mogelijkheid; geen bekende klant raakt die grens.
- Geheugenfootprint van een upload is nu ~grootte van het bestand (max 200 MB) — bewust geaccepteerd; vorige streaming-architectuur (64 KB buffer) was de bron van de race.
- Backend-wijziging is harmless voor oudere clients: ontbrekende `X-Upload-Sha256` header logt simpelweg als `sha=''`.
- Productie release v1.0.123 werd nooit gebouwd door een latente YAML-syntax-bug in `.gitlab-ci.yml` (commit `be88f63`'s PowerShell heredoc-body op kolom 1 dedented het YAML block scalar). Tag v1.0.124 is de eerste werkelijke release met deze hardening.
- Reproductie-binary `/tmp/repro-upload/` (Rust, reqwest 0.12.28) blijft beschikbaar voor toekomstige Windows-upload-debug; niet ingecheckt.
- Eerdere `UploadFailureReason` veronderstellingen rond Content-Length-vs-body-divergentie zijn hiermee zowel gemitigeerd als instrumenteerbaar — als de bug terugkomt geeft de gelogde SHA direct uitsluitsel.

---

## DEC-058 — Windows MSI Build op GitLab CI met Self-Hosted Runner

**Date:** 2026-04-01
**Status:** Accepted

**Context:** De Windows MSI build draaide op GitHub Actions (`windows-latest` runner) per DEC-056. Dit werkte maar was los gekoppeld van de GitLab CI pipeline. Michel heeft een Windows PC als GitLab Runner geregistreerd (shell executor, tag `windows`), maar de eerste builds faalden omdat de runner als LocalSystem (SYSTEM account) draait. SYSTEM's `$env:USERPROFILE` is `C:\Windows\system32\config\systemprofile` — een restricted pad waar Tauri's WiX tools niet konden draaien (`candle.exe` failed), Rust/Cargo niet gevonden werd, en de SSH key voor uploads ontbrak.

**Decision:** Drie aanpassingen in `.gitlab-ci.yml` en `tauri.conf.json`:
1. **`useLocalToolsDir: true`** in `tauri.conf.json` — Tauri's officiële config optie die WiX/NSIS tools opslaat in `target/.tauri/` i.p.v. `dirs::cache_dir()`. Gedocumenteerd in Tauri source als oplossing voor exact dit scenario (Windows System user / CI). Verkende alternatieven `TAURI_TOOLS_PATH` (niet bestaand) en `LOCALAPPDATA` override (te breed) werkten niet.
2. **Fallback paden** voor Rust en SSH naar `C:\Users\michel\` naast `$env:USERPROFILE`.
3. **Relatieve paden** voor MSI search (`src-tauri\...` i.p.v. `windows\src-tauri\...`) omdat `cd windows` in GitLab's shell executor persistent is tussen script blocks.

**Consequences:**
- Windows MSI builds draaien nu volledig binnen GitLab CI, naast macOS en Android.
- GitHub Actions Windows workflow blijft beschikbaar als fallback maar is niet meer primair.
- Runner vereist Rust, Node.js en npm geïnstalleerd onder `C:\Users\michel` op de Windows PC.
- `useLocalToolsDir: true` downloadt WiX/NSIS bij elke clean build (~3 sec extra). Bij cached `target/` dir worden tools hergebruikt.

---

## DEC-057 — Claude Routing voor Handleiding-profiel via n8n IF-node

**Date:** 2026-03-23
**Status:** Accepted

**Context:** Het Ollama model (`ministral-3:8b`) in de n8n notule-flow kon de complexe handleiding-template niet verwerken — het hallucineerdde generieke content ("Krachtige Data Analyzer") in plaats van de transcriptie te gebruiken. De handleiding-template vereist gestructureerde HTML met CSS classes, genummerde secties, field-lists, en info-boxes. Andere n8n workflows (SEO Blog Pipeline, Yinga AI Weekly) gebruiken al Claude via een lokale proxy op `http://n8n_claude_code:3100/v1/chat/completions`.

**Decision:** Routing-switch in de n8n "Notule Generator" workflow (`Iq3AAf8Vk8eQ9dcZ`) via een IF-node ("Route Profile") die `profile_id === 'handleiding'` naar een Claude HTTP Request node stuurt. Alle andere profielen blijven via de bestaande Ollama AI Agent route gaan. Backend stuurt `profile_id` mee in het webhook payload (4 locaties: `transcription_service.py`, `transcription.py` ×2, `transcripts.py`). De Claude-route skipt de "Convert to HTML" node omdat handleiding-output al HTML is met eigen `<style>` block. macOS/iOS `HTMLWebView` verplaatst `<style>` blocks van `<body>` naar `<head>` via `extractStyles()` helper, omdat WKWebView CSS counters en grid layouts niet toepast vanuit body-styles.

**Consequences:**
- Handleiding-profiel genereert nu uitgebreide, goed gestructureerde HTML handleidingen via Claude.
- Alle andere profielen (zakelijk, informeel, etc.) zijn ongewijzigd — dezelfde Ollama route.
- `profile_id` is nu onderdeel van het webhook payload contract tussen backend en n8n.
- Claude proxy (`n8n_claude_code:3100`) moet beschikbaar zijn voor handleiding-verwerking; Ollama als fallback is niet geïmplementeerd.
- macOS/iOS app moet `<style>` blocks uit HTML content extraheren naar `<head>` — dit is generiek en werkt voor elk profiel dat eigen CSS meestuurt.

---

## DEC-056 — GitHub Actions Behouden Uitsluitend voor Windows MSI Builds

**Date:** 2026-03-20
**Status:** Accepted

**Context:** Na de migratie naar GitLab CI (DEC-055) moest Windows MSI builds ook ergens draaien. Drie opties: (1) Windows runner registreren op GitLab, (2) Windows builds op GitHub Actions houden, (3) Windows builds lokaal draaien. Een self-hosted Windows runner was niet beschikbaar. GitHub Actions rekent macOS builds 10x de normale prijs (10 minuten per 1 build-minuut), maar Windows builds 1:1. De macOS builds van ~13 minuten kostten dus ~130 Actions-minuten op het free tier — de voornaamste reden dat Actions-minuten uitgeput raakten. Windows builds kosten ~30 minuten per build, wat acceptabel is voor het free tier (2000 min/maand).

**Decision:** GitHub Actions behouden uitsluitend voor Windows MSI builds. Nieuw workflow bestand `.github/workflows/build-windows.yml` vervangt het Windows-gedeelte van het verwijderde `.github/workflows/release.yml`. Triggered op dezelfde `v*`/`dev-v*` tags die naar GitHub gepusht worden. Build uploadt MSI naar EC2 server en update `releases.json` Windows entries via SSH. Vereist `SSH_PRIVATE_KEY` secret in GitHub repository settings.

**Consequences:**
- GitHub Actions minuten drastisch gereduceerd: ~30 min/release (Windows only) in plaats van ~160+ min/release (alle platforms).
- Windows builds draaien onafhankelijk van GitLab CI — geen dependency op Mac runner.
- Tags moeten naar beide remotes gepusht worden: GitLab (macOS+Android+deploy) en GitHub (Windows). Deploy scripts pushen alleen naar origin (GitLab); Windows tag push is handmatig of via apart script.
- GitLab CI `build-windows` job staat op `when: never` — kan geactiveerd worden als een Windows runner beschikbaar komt.
- `SSH_PRIVATE_KEY` GitHub secret nodig voor server upload vanuit Windows runner.

---

## DEC-055 — GitLab CI als Primair CI/CD Platform met Mac als Sole Runner

**Date:** 2026-03-20
**Status:** Accepted

**Context:** GitHub Actions minuten waren uitgeput (billing error). macOS builds op GitHub Actions kosten 10x de normale prijs (10 min per build-minuut), waardoor een 13-minuten macOS build 130 Actions-minuten verbruikte. Met het free tier van 2000 min/maand waren ~15 releases per maand het maximum. GitLab op `gitlab.prezent.nl` (self-hosted) heeft geen usage limiet. Michel's Mac is al het primaire development platform en heeft Xcode, Android SDK, en SSH-toegang tot de EC2 productie-server.

**Decision:** GitLab CI als primair CI/CD platform. Michel's Mac fungeert als sole runner (shell executor, gitlab-runner 18.10.0). Pipeline in `.gitlab-ci.yml` met 5 jobs: `prepare` (versie/channel detectie), `build-macos` (Xcode archive → DMG), `build-android` (Gradle assembleRelease → APK), `build-windows` (disabled, geen runner), `deploy` (scp naar EC2 + releases.json update + GitLab Release). Mac SSHt naar EC2 voor deploys — EC2 kan GitLab niet bereiken (security group blokkeert poort 443 naar gitlab.prezent.nl). Release notes worden automatisch uit `docs/CHANGELOG.md` geextraheerd. GitLab Release creatie via `scripts/create-gitlab-release.py` (API call met `CI_JOB_TOKEN`).

**Consequences:**
- Onbeperkte CI/CD minuten voor macOS + Android builds (self-hosted runner).
- Mac moet aan staan en gitlab-runner draaien voor CI builds. Geen builds mogelijk als Mac offline is.
- EC2 ↔ GitLab security group beperking is geen probleem: Mac doet alles (build + deploy via SSH).
- `SSH_PRIVATE_KEY` CI variable niet nodig — Mac's eigen SSH key (`~/.ssh/`) wordt gebruikt voor EC2 toegang.
- Runner environment vereist: Xcode, JDK 21, Android SDK, Python 3, codesign tools. Geconfigureerd via `~/.gitlab-runner/config.toml` environment variabelen.
- Post-commit hook pusht alleen naar origin (GitLab), niet meer dual-push naar GitHub.
- `.github/workflows/release.yml` verwijderd — vervangen door `.gitlab-ci.yml`.
- Bestanden: `.gitlab-ci.yml`, `scripts/create-gitlab-release.py` (nieuw), `.githooks/post-commit` (aangepast), `scripts/deploy-*.sh` (aangepast).

---

## DEC-054 — Background Uploads with Global ProcessingBar

**Date:** 2026-03-20
**Status:** Accepted

**Context:** After a recording stopped, `uploadFile()` kept `recordingState = .uploading` until the upload completed, blocking the entire RecordingView. The user couldn't start a new recording, navigate to other tabs, or use the app at all during uploads — which could take minutes for large files over slow connections. Windows already had background task tracking via `backgroundTasks` in the Zustand store and a `ProcessingBar` component. macOS had no equivalent.

**Decision:** Make `uploadFile()` fire-and-forget: create a temporary `TranscriptTask` (ID prefixed with `upload-`) in `activeTasks`, set `recordingState = .idle` immediately, and run the upload in a background `Task`. Upload progress updates the temp task via `updateTask()`. On success, the temp task is replaced with the real server task and SSE monitoring begins. On failure, the task shows the error message inline. New `ProcessingBar.swift` component is placed in `ContentView.detailView` (above tab content), visible on all tabs. It renders each active task with filename, status, progress bar, percentage, and cancel/dismiss actions.

**Consequences:**
- User can immediately start a new recording or navigate after stopping — no more blocked UI.
- Upload progress and errors are visible on every tab via the global ProcessingBar.
- `uploadProgressView` removed from RecordingView (no longer needed).
- `cancelUpload()` now accepts an optional task ID to cancel specific uploads.
- The `uploadProgress` property on RecordingViewModel is no longer used by the upload flow but retained for widget compatibility.
- Files changed: `RecordingViewModel.swift` (background upload, `updateTask()`), `ProcessingBar.swift` (new), `ContentView.swift` (ProcessingBar placement), `RecordingView.swift` (removed uploadProgressView).
