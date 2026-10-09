# Een keer corrigeren, daarna onthouden

Status: goedgekeurd en geïmplementeerd in de desktopbron op 2026-10-09.
Native installatie en een nieuwe opname met echte AI-provider blijven apart te verifiëren.

## Bestaande basis

macOS heeft PersonalVocabulary in macos/Services/LocalTranscriber.swift. Deze
verzamelt vrije contexttermen, namen en organisaties uit het personenregister en
termen uit de gekoppelde Obsidian-contextnotitie. Maximaal 30 termen gaan naar de
spraakherkenning. OnDeviceTranscriber gebruikt ze als contextualStrings en
RecordingViewModel voegt ze toe aan de notulenprompt. Dit is een voorkeurslijst,
geen opgeslagen relatie tussen een verkeerd woord en de juiste spelling.

Windows bewaart personen met aliassen, maar services/participants.ts levert alleen
naam, rol en organisatie. services/localPipeline.ts geeft de namen van deelnemers
door aan de notulengeneratie. Een overeenkomstige persoonlijke correctielijst is
hier nog niet aangesloten. De bestaande notuleneditors slaan bewerkte HTML op;
zij leren daar momenteel geen losse woordcorrecties van.

## Aanbevolen eerste versie

Voeg in beide notuleneditors een actie 'Woord corrigeren' toe bij geselecteerde
tekst. De gebruiker ziet het oorspronkelijke woord, vult de juiste spelling in
en kan 'Onthouden voor volgende opnames' aanvinken. Sla alleen deze expliciete
woordrelatie op, niet automatisch alle wijzigingen in een herschreven alinea.
De huidige notule wordt alleen na succesvol opslaan gewijzigd. Een mislukte
woordenlijstsave mag de correctie niet als geleerd presenteren.

Voorbeeld: correcte term Yinga, goedgekeurde varianten Jengo en Django. Persoon-
en bedrijfsnamen gebruiken hetzelfde formaat. De gebruiker kan meerdere varianten
bij een term toevoegen. Instellingen > Verwerking krijgt 'Woorden en namen' met
correcte term, varianten, toepassingsbereik en verwijderen/uitschakelen.

Gebruik lokale opslag volgens de bestaande platformpatronen. Een versieerbaar
JSON-document met entries {id, canonical, variants, scope, enabled} volstaat;
geen server, account, vector database of modeltraining nodig. Schrijf atomair,
valideer lege termen en dubbele/tegenstrijdige varianten en behoud bestaande
persoonlijke context. Dezelfde JSON-specificatie werkt op beide platforms.
Synchronisatie tussen apparaten zit niet impliciet in lokale opslag.

## Toepassen

1. Geef correcte namen en termen mee aan spraakherkenning waar de gebruikte engine
   dit ondersteunt. Hergebruik de begrensde macOS-vocabulairelijst; verbind ook
   de ondersteunde Windows-herkenner. Een prompt is een voorkeur, geen garantie.
2. Bewaar de ruwe transcriptie ongewijzigd. Maak voor notulengeneratie een afgeleide
   tekst met de goedgekeurde correcties en geef een korte lijst variant -> term
   mee aan de gekozen AI-provider. Neem de correcties ook bij opnieuw genereren
   en de bestaande online/offline-routes mee.
3. Controleer na generatie tekstnodes op de exacte goedgekeurde varianten voordat
   de notule wordt opgeslagen. Bewerk nooit HTML-tags, attributen, URLs, codeblokken
   of emailadressen. Correct opgeslagen HTML voedt de bestaande export naar Obsidian.

Pas varianten hoofdletterongevoelig toe op Unicode-woordgrenzen; langste
meerwoordvariant eerst, één vervangingspassage zonder kettingvervangingen. Canonical
bepaalt de juiste hoofdletters. Geen algemene klankvergelijking of fuzzy replacement
in de eerste versie: dat zou ook correcte andere namen kunnen overschrijven.

'Django' is ook een echte technologienaam. Bied 'Alle opnames' en het huidige
opnameprofiel als bereik; leg bij een globale regel uit dat iedere passende
vermelding wordt vervangen. De gebruiker bepaalt het bereik. Alleen geselecteerde,
goedgekeurde varianten worden deterministisch vervangen. Persoonsaliassen zijn
niet automatisch verkeerde spellingen: sommige aliassen zijn rollen/initialen.

## Aansluitpunten en acceptatie

macOS: PersonalVocabulary, OnDeviceTranscriber/LocalTranscriber,
RecordingViewModel-generatiepaden, TranscriptsView.saveNotuleEdits en de bestaande
Verwerking-instellingen. Windows: transcriptiecommand, localPipeline, LLM-prompt,
regeneratiepaden, TranscriptDetail-editor en ProcessingTab. Inspecteer bij uitvoering
alle callers, inclusief cloud-upload en retry, zodat een enkele pipeline niet wordt
overgeslagen. Migreer geen bestaande notulen stilzwijgend.

Tests: Jengo/Django -> Yinga blijft na herstart actief; alleen het gekozen profiel;
hoofdletters, diakritische namen en meerwoordnamen; geen substringvervanging;
geen URL/HTML/code-wijziging; geen kettingvervanging; fout bij conflicterende
varianten; opslagfout behoudt de editorinhoud; ruwe transcriptie blijft behouden;
notulenregeneratie en Obsidian-export gebruiken de correctie op beide platforms.
Native acceptatie: dezelfde correctie eenmaal aanmaken, app opnieuw openen en een
nieuwe korte opname verwerken met zowel een lokale als een ingestelde cloudprovider.

## Ingebouwde bediening en verificatie

Selecteer in een notule een woord, kies **Woord corrigeren**, vul de correcte term
in en kies **Corrigeren**. **Onthouden voor volgende opnames** slaat de relatie
lokaal op. Extra varianten voor dezelfde term en hetzelfde bereik worden samengevoegd.
Beheer, wijzig, deactiveer of verwijder regels via **Instellingen > Verwerking >
Woorden en namen**. Bestaande notulen veranderen alleen na een expliciete correctie
of opnieuw genereren. De ruwe transcriptie blijft behouden.

Eigen providerverwerking gebruikt gecorrigeerde afgeleide invoer, een begrensde
woordenprompt en controle van de gegenereerde HTML. De bestaande accountbackendroute
krijgt geen persoonlijke woordenlijst: daarvoor corrigeert de desktopclient het
resultaat en schrijft het terug. Een mislukte terugschrijving van correcties wordt
als fout gemeld. De export gebruikt de opgeslagen gecorrigeerde notule.

Beide platforms gebruiken versie 1 van `personal-corrections.json`, met expliciete
`scope: null` voor globale regels. Opslag gebruikt atomair vervangen van een bestand.
Er is geen automatische synchronisatie tussen apparaten. Spraakherkenning krijgt
maximaal 30 correcte termen als voorkeur; die voorkeur garandeert geen juiste
herkenning. Alleen expliciete varianten worden achteraf vervangen. HTML-entiteiten
blijven ongemoeid; een naam die door entiteiten of tags wordt opgesplitst valt niet
onder de eerste exacte-vervangingsversie.

Herhaalbare broncontroles:

```sh
# Vanuit windows/
npm run build
npx vitest run
# Vanuit windows/src-tauri/
cargo test --lib
# Vanuit de repositoryroot
swiftc macos/Services/PersonalCorrections.swift scripts/check-personal-corrections.swift -o /tmp/thoughtvault-corrections-check
/tmp/thoughtvault-corrections-check
```

De UI-fixture controleerde de geselecteerde variant, opslaan in de notule en behoud
van het ruwe transcript. Componenttests controleren dat een opslagfout het formulier
behoudt en de regel niet leert. Dit vervangt de native acceptatie met echte opname,
AI-provider en Obsidian-vault niet.
