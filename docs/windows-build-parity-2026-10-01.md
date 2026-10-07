# Windows-build en vergelijking met Apple — 1 oktober 2026

## Resultaat

De Windows-app is bijgewerkt en als x64-MSI gebouwd op de bestaande Windows-pc.
De bron is de huidige werkmap bij basiscommit `b5a3575`, inclusief de goedgekeurde
ongecommitte Windows-wijzigingen. Er zijn geen Apple-bestanden gewijzigd door deze
Windows-opdracht, geen commits/tags gemaakt en geen releases gepubliceerd.

De Windows-pc is via de bestaande RDP-verbinding gebruikt. Windows 11 Pro Education,
Ryzen 7 5700X3D, 48 GB RAM. De bestaande Parallels-VM heeft Windows 11 ARM64;
`prlctl exec` vereist een andere Parallels-editie. De werkende x64-pc is daarom de
primaire build- en testomgeving. ARM64 is niet native geverifieerd.

## Bijgewerkte onderdelen

| Onderdeel | Implementatie | Verificatie |
|---|---|---|
| Logo en applicatie-iconen | Actuele Apple-AppLogo, nieuwe PNG/ICO/ICNS-assets voor Windows, login/onboarding/sidebar en systeemiconen | Assetgelijkheid en nieuwe native MSI-build |
| Home | NorthStar-layout, persoonlijke begroeting, bergillustratie, zoekfunctie, recente documenten, agenda, opnameacties | Geïnstalleerde Windows-app geopend |
| Opnamestudio | Timer, waveform, transport, bronkeuze, template, deelnemers, snelle notitie, import en opgeslagen opnamen | Native Windows-opname, pauze en bewaren uitgevoerd |
| Algemene Home-opname | Start standaard gecombineerd; expliciete fysieke vergadering blijft microfoon | Live gecombineerde opname gestart vanuit Home |
| Waveform | Drie vertraagde lobben, echte audiolevels, vlak bij stilte, compacte widgetvariant | Echte WASAPI-systeemaudio en Canvas-regressietests |
| Audiofinalisatie | Wacht op voltooide WAV, schrijft gecombineerde audio atomisch, toont fouten | Native mix-regressietest en opname bewaard zonder verwerking |
| Instellingen | Zeven tabs, concrete providers, systeemadvies, transcriptie apart van notulen | Hardwaregegevens en modeladvies zichtbaar; navigatietabs bij standaardvenster gecontroleerd |
| Lokale transcriptie | GGML Whisper op Windows; modeldownload met voortgang/status | Small-model via app gedownload; Nederlandse synthetische audio werkelijk lokaal getranscribeerd |
| Eigen API-sleutels | OpenAI en Anthropic via bestaande LLMService, Windows native keyring | Provider-/migratietests; native Credential Manager save/reopen/load/delete-test |
| API-kosten | UI vermeldt aparte API-kosten, geen ChatGPT/Claude-abonnement | Instellingen gecontroleerd; geen stil betaald fallbackpad |
| Templates | Bestaande templates onafhankelijk van provider | Alle zeven JSON-templateobjecten exact gelijk aan Apple |
| Taken/herstel | Lokale taken zichtbaar, fouten behouden, retry hergebruikt transcript, resultaat via taak-ID | Native notulengeneratorfout zichtbaar in Taken; transcript blijft lokaal bewaard; regressietests |
| Regeneratie | Templatekeuze, taakregistratie, lokale/cloud-route; ook beschikbaar bij transcript zonder notulen | UI- en pipeline-regressietests; native dialoog met alle zeven templates gecontroleerd |
| Snelle notitie | Bewaard per opnamepad, gekoppeld aan taak/transcript, meegenomen als context | Unit-tests en opname-UI |
| Obsidian | Expliciete export/import, stabiele ID-bestandsnamen, conflictcontrole en remote snapshot | Mocked roundtrip/conflicttests; reviewfixes voor gewijzigde metadata en identieke tekst |
| Build | Bestaand PowerShell-script met toolchecks, foutgates, architectuur, CMake-pad en checksum | Werkelijke MSVC/Rust/Tauri/WiX x64-MSI-build |

## Native testbevindingen

- Gecombineerde microfoon/WASAPI-opname startte zonder fout of crash.
- Tijdens de opname is een synthetische Nederlandse teststem via Windows afgespeeld.
  De waveform reageerde op systeemaudio en werd vlak bij pauze. De teststem is gestopt.
- De opname is als WAV bewaard via **Bewaar zonder verwerken**. Opnamedata is niet
  geüpload naar een LLM of backend. De testopname blijft lokaal beschikbaar.
- Een apart synthetisch audiobestand is lokaal met Whisper Small getranscribeerd.
  De tekst over de Windows-test, planning en Obsidian was zichtbaar in Notulen.
  Small herkende de productnaam niet correct; deze ene korte test bewijst geen
  algemene Nederlandse kwaliteitsgarantie.
- Ollama draaide niet op deze pc. De daaropvolgende notulenstap faalde met een
  begrijpelijke verbindingsfout. Taken toonde **Mislukt**, met opnieuw verwerken.
  Het reeds gemaakte transcript bleef behouden.
- De Windows-app herkende de werkelijke CPU/RAM/schijfruimte en adviseerde Medium.
  Voor de test is Small geselecteerd en gedownload; dat is de werkende lokale configuratie.

Bewijs: [waveform met echte systeemaudio](qa/windows-2026-10-01/system-audio-wave.png),
[nieuwe branding](qa/windows-2026-10-01/windows-branding-final.png) en
[bureaubladicoon](qa/windows-2026-10-01/desktop-icon.png) en
[templatekeuze bij regenereren](qa/windows-2026-10-01/regenerate-templates.png).
Alle screenshots in deze map bevatten uitsluitend het relevante appvenster.

## Automatische controles

- TypeScript/Vite-productiebuild: geslaagd.
- Vitest: **20 bestanden, 57 tests geslaagd**.
- Rust-tests op de Windows-pc: **20 geslaagd**, inclusief native credential-opslag,
  WAV/mix-regressies en foutafhandeling.
- Productie-dependency-audit: geen bekende kwetsbaarheden op het controlemoment.
- Code-review uitgevoerd; twee Obsidian-problemen opgelost en regressietests toegevoegd.

De native logs, bronchecksums en MSI staan lokaal in `build/windows-2026-10-01/` (gitignored).
De MSI heeft versie 1.0.255, gelijk aan de huidige repositoryversie. Bij meerdere
testbuilds met hetzelfde versienummer kan MSI onderhoud een oude executable
behouden. De geïnstalleerde executable is daarom via SHA256 vergeleken met de
executable uit een administratieve MSI-extractie; deze bestanden waren identiek.
Een cacheprobleem met het oude ingebouwde executable-icoon is gevonden: `build.rs`
volgt nu ook wijzigingen in `icons`, zodat iconen opnieuw gecompileerd worden.
De daaropvolgende MSI-build en installatie/herstel slaagden (exitcode 0). Het
nieuwe bureaubladicoon en het uit de geïnstalleerde executable geëxtraheerde icoon
zijn visueel gecontroleerd: beide bevatten het nieuwe paarse logo.
Voor een normale release gebruikt de bestaande versieprocedure een nieuw nummer.
De installer is niet publiek gepubliceerd en niet digitaal ondertekend.

MSI SHA256: `4113f1608939613f8dc59dd54f9cf54ae646c39cdbf8284a18927cf29947740e`.

## Grenzen en nog niet live geverifieerd

- OpenAI/Anthropic-aanroepen zijn automatisch getest met mocks. Er is geen betaalde
  aanvraag gedaan met een echte gebruikerssleutel.
- Obsidian-import/export is getest met mocks. Een echte Windows Obsidian Local REST
  API-koppeling is niet ingesteld of live getest. Dit is expliciet ophalen/exporteren,
  geen continue realtime-sync of synchronisatie van alle frontmattervelden terug naar de app.
- Lokale Whisper → gekozen LLM is onafhankelijk configureerbaar. Het bestaande
  ThoughtVault Cloud-verwerkingspad combineert backendtranscriptie en notulen;
  cloudtranscriptie → eigen lokale/API-LLM is nog niet geïmplementeerd.
- Apple Intelligence, WhisperKit en CoreAudio zijn Apple-specifiek. Windows gebruikt
  respectievelijk concrete API/lokale providers, GGML Whisper en WASAPI/CPAL.
- ChatGPT-plan usage/OAuth blijft geblokkeerd; geen Claude Pro/Max- of Claude Code-route.
- Parallels ARM64, CI-uitvoering, volledige agenda/account/admin-flows, GPU-transcriptie
  en een lange duurtest zijn niet als onderdeel van deze native eindtest geverifieerd.
- De automatische tests en uitgevoerde native controles bewijzen de hierboven genoemde
  routes; dit verslag claimt geen volledige gelijkheid van elk Apple-platformonderdeel.
