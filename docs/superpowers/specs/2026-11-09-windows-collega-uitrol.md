# ThoughtVault Windows: afronden en uitrollen

## Opdracht en afbakening

Maak ThoughtVault betrouwbaar bruikbaar voor collega's op Windows x64. Lever een
werkende installer, begrijpelijke eerste start, opname/import → transcriptie →
brongetrouwe notulen → opslaan/export, updates en aantoonbaar herstel. iOS/iPadOS
zijn door de gebruiker uitgesteld; dit traject verandert die afspraak niet.

Gebruik uitsluitend de bestaande SSH-beheerlaag van Dalf38. Geen nieuwe accounts,
servers, frameworks, toolchains of projectgebonden beheerinfrastructuur. Beperk
wijzigingen tot aantoonbare product- en releaseblokkades. Bewaar persoonlijke data
en bestaande credentials. Ontwikkelwerk, tijdelijke bestanden en bewijs staan op
de externe SSD; controleer en ruim eigen interne tijdelijke bestanden bij afronding op.

## Gecontroleerde uitgangssituatie op 9 november

- SSH werkt met een daadwerkelijk verhoogd developer-token. Centrale beheercommit:
  `b30acb7`; installatie/upgrade/rollback en beperkte desktopscenario's bestaan.
- Dalf38 heeft ThoughtVault **1.0.305** geïnstalleerd. Native build
  `19ab8be2adf747468acd886ca132f280` is geslaagd; bronhash
  `eebb546cbf76684518b952ca0dab35497efd577aab7e92de6a428c3f9a89c08a`.
- Windows `source-provenance.json` noemt basiscommit `4de88a4` en een MP4-audiospoorfix.
  De Mac-pilotworktree staat nog op `4de88a4` / 1.0.300. Deze bronafwijking moet vóór
  nieuwe productwijzigingen worden verzoend. Versienummer alleen bewijst geen bronidentiteit.
- Automatische MSI-verpakking na padverkorting slaagde voor 1.0.300, inclusief
  ICE-controle en 888 payloadhashes. Dat is geen functionele acceptatie van 1.0.305.
- Korte native ketenproef `8667a70b30584695942917a48fde7c7e` eindigde met
  `Production content audit rejected the draft; preserved without retry`.
- Uurproef `7fc986da68174dc2af71fda9c1efe862` maakte werkelijk 3650 seconden
  gecombineerde opname, maar de volledige verwerking/export slaagde niet.
  Herhaalde synthetische spraak met stilte bewijst geen echte vergadering of microfoonkwaliteit.
- MP4-proef `13e679efbf9247a0b92a1dd0af19c9c0` faalde; negatieve importproef
  `26897a20f4f64baa99452495fb9746e6` slaagde.
- Offline modelvergelijking `b87ad05bc9ec493da1b60a96bd531328` is uitgevoerd en
  vereist inhoudelijke beoordeling. Notulenproef `c752a3be521f42ae995458c10ef7b808`
  gebruikte lokaal **hermes3:8b**, met `productionGate: rejected`; zij bewijst niet
  dat de ingestelde Ollama Cloud-route met `gpt-oss:120b` werkt.
- Bij controle waren geen centrale operationsjobs actief. Er is geen actuele
  complete opname-, inhouds-, herstel- en uitrolacceptatie aangetoond.

## Productafspraken voor deze release

1. Eén bewezen standaardconfiguratie voor de eerste pilot. Begin met het bestaande
   Faster Whisper Small CPU int8 voor transcriptie en de al gekozen Ollama
   Cloud-route `gpt-oss:120b` voor notulen; keur deze combinatie eerst met echte
   resultaten goed. Geen stille model/providerwissel om een test groen te maken.
2. De eerste pilot ondersteunt opname met microfoon, systeemaudio en gecombineerd,
   pauze/hervatten, de zeven bestaande importformaten WAV/MP3/M4A/MP4/AAC/FLAC/OGG,
   transcript/notule bewerken en heropenen, TXT/PDF-export en fout/herstelgedrag.
   Een gepresenteerde optie werkt of wordt gericht uit de pilotflow gehaald met
   duidelijke uitleg. Bestaande gebruikersinstellingen worden niet overschreven.
3. Onjuiste bedragen, actiehouders, termijnen, ontkenningen en voorwaarden zijn
   releaseblokkades. Twijfel geeft een bewaard reviewconcept, nooit stilzwijgend
   een goedgekeurde notule. Ook correcte, gewone notulen moeten betrouwbaar slagen.
4. Iedere collega kan met eigen identiteit en via de bestaande gebruikersflow
   beginnen. Geen persoonlijke API-sleutels van Michel kopiëren; als de gekozen
   route credentials vereist, levert de bestaande provisioningflow die afgeschermd.
5. Uitrol: eerst twee à drie Windows-collega's, vijf werkdagen gecontroleerd
   gebruik, daarna overige Windows-collega's. Dit zijn planningsaannames; namen en
   apparaten worden vóór verzending vastgelegd. Geen algemene updaterwijziging
   voordat het bereik bekend is en de kandidaat is goedgekeurd.

## Klaar betekent

De exacte uit te leveren MSI is aan broncommit, native artifact, payloadmanifest,
hash, updaterhandtekening en acceptatierapport gekoppeld. Een verse gebruiker kan
installeren en zonder ontwikkelaar zijn eerste notule maken. De korte én ≥60 minuten
keten, broninhoud, exports, herstart en echte upgrade/rollback zijn bewezen. De eerste
pilot heeft vijf werkdagen zonder dataverlies, onterechte inhoudsgoedkeuring of
blokkerende kernflowfout gedraaid. Collega's hebben een werkende download,
startinstructie, privacy/uitleg over externe verwerking en een supportcontact.
