# Een keer corrigeren, daarna onthouden

Status: implementatievoorstel, nog niet ingebouwd. Gebaseerd op broncontrole op
2026-10-09. Geldt voor de desktopapps macOS en Windows.

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
