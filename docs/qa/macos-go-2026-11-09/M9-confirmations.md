# M9: bevestigingen bij destructieve acties

Stand na taak 15. Regelnummers verwijzen naar `macos/`.

| Actie | Platform | Code | Bevestiging | Status |
|---|---|---|---|---|
| Notule verwijderen (enkel: swipe, contextmenu, kaartmenu) | macOS, iOS | Views/TranscriptsView.swift:639,653 (nu `deleteTranscript` :759), kaartmenu :631 | Views/TranscriptsView.swift:174 | Bevestigd |
| Notules verwijderen (bulk) | macOS, iOS | Views/TranscriptsView.swift:692 (`bulkDelete` :781) | Views/TranscriptsView.swift:162 | Bevestigd |
| Detailweergave: notule verwijderen | macOS, iOS | Views/TranscriptsView.swift:951 | Views/TranscriptsView.swift:967 | Bevestigd |
| Verwijderen van notulen ouder dan 7 dagen | n.v.t. | Bestaat niet. De 7 dagen op :103 is alleen een datumgroepering in de lijst | n.v.t. | Geen actie |
| Opname annuleren (knop in opnamescherm) | macOS | Views/RecordingView+Studio.swift:370 | Views/RecordingView+Studio.swift:138 | Bevestigd |
| Opname annuleren (knop in opnamescherm) | iOS | Views/RecordingView+iOS.swift:219 | Views/RecordingView+iOS.swift:104 | Bevestigd |
| Opname annuleren via menubalk (twee plekken: opnemen en gepauzeerd) | macOS | App/ThoughtVaultApp.swift:210,231 | App/ThoughtVaultApp.swift:153 (NSAlert, een menu kan geen dialoog dragen) | Toegevoegd |
| Opname stoppen zonder verwerken | macOS, iOS | Bestaat niet. Stop leidt altijd naar `stopAndUpload` | n.v.t. | Geen actie |
| Verwerking annuleren (iOS-verwerkingsscherm) | iOS | Views/IOSProcessingView.swift:305 | Views/IOSProcessingView.swift:58 | Bevestigd |
| Taak annuleren (Taken) | macOS, iOS | Views/TasksView.swift:105,107 | Views/TasksView.swift:95 (alert) | Bevestigd |
| Taak verwijderen (Taken) | macOS, iOS | Views/TasksView.swift:133 | Views/TasksView.swift:121 (alert) | Bevestigd |
| Upload of lokale verwerking annuleren (verwerkingsbalk, widget) | macOS | Views/Components/ProcessingBar.swift:115,126; Views/Components/RecordingWidgetView.swift:291 | NONE | Bewust niet: het audiobestand blijft bewaard (zie `cancelUpload`), opnieuw verwerken kan |
| Mislukte of afgeronde taak uit de balk halen | macOS | Views/Components/ProcessingBar.swift:90,112 | NONE | Bewust niet: alleen een statusregel, geen gebruikersdata |
| Opgeslagen opname verwijderen ("Opgeslagen opnames") | macOS, iOS | Views/RecordingView.swift:551 (`deleteSavedRecording`) | Views/RecordingView.swift:556 | Toegevoegd |
| Profiel verwijderen | macOS, iOS | Views/ProfilesView.swift:89,126 | Views/ProfilesView.swift:120 (alert) | Bevestigd |
| Persoon verwijderen | macOS, iOS | Views/PeopleDirectoryView.swift:93 | Views/PeopleDirectoryView.swift:85 | Bevestigd |
| Whisper-model verwijderen (Instellingen) | macOS | Views/SettingsView+VerwerkingSide.swift:122 (`WhisperModelStore.remove`) | Views/SettingsView+VerwerkingSide.swift:130 | Toegevoegd |
| Uitloggen (Instellingen) | macOS | Views/SettingsView.swift:1464 (`logout` :145) | Views/SettingsView.swift:140 | Bevestigd |
| Uitloggen (Account) | macOS, iOS | Views/AccountView.swift:569; Views/AccountView+iOS.swift:83 | Views/AccountView.swift:68 (alert) | Bevestigd |
| Uitloggen (Home, Studio) | macOS | Views/HomeView+Studio.swift:152 | NONE | Bewust niet: wist geen data (zie onder de tabel) |
| Account verwijderen | macOS, iOS | Views/AccountView.swift:545, Views/AccountView+iOS.swift:68: verwijst naar support, wist zelf niets | n.v.t. | Geen actie |
| Beheer: gebruiker en feedback verwijderen | macOS | Views/AdminView.swift:1945,1956 | Views/AdminView.swift:117,135 (alerts) | Bevestigd |
| Eigen correctie verwijderen | macOS | Views/PersonalCorrectionsView.swift:41 | NONE | Bewust niet: een enkele regel in een lijst die de gebruiker zelf typte, geen audio of notule |
| Vault-map loskoppelen | macOS | Views/SettingsView.swift:403 (`VaultFolderStore.clear`) | NONE | Bewust niet: wist alleen de gekozen map in de instellingen, geen bestanden |
| Biometrische login uitzetten | macOS, iOS | Views/SettingsView.swift:1450 | NONE | Bewust niet: schakelaar, direct terug te zetten |
| Bewerkte notule weggooien | macOS, iOS | Bestaat niet: er is geen bewerkmodus voor de notule met een annuleerknop | n.v.t. | Geen actie |
| Woordenlijst of correcties in bulk wissen | macOS | Bestaat niet | n.v.t. | Geen actie |

## Uitloggen vanuit Home

`Views/HomeView+Studio.swift:152` staat in een eigen menu. Het is dezelfde `logout`-aanroep als in Instellingen en Account. Uitloggen wist geen lokale notulen of audio, dus er is hier geen dialoog toegevoegd. Wil je toch dezelfde dialoog als in Instellingen, dan is dat een aparte keuze.

## Toegevoegd in taak 15

- Opgeslagen opname verwijderen: dialoog "Opname verwijderen?" (Views/RecordingView.swift:556).
- Whisper-model verwijderen: dialoog "Model verwijderen?" (Views/SettingsView+VerwerkingSide.swift:130).
- Opname annuleren via de menubalk: alert "Opname annuleren?" (App/ThoughtVaultApp.swift:153).

## Cloudtaken hervatten

`RecordingViewModel.tasksToResume` (ViewModels/RecordingViewModel.swift) laat alleen actieve taken door, houdt de servervolgorde aan en neemt per `taskId` de eerste. `checkPendingTasks` gebruikt die functie.

Bij het overnemen van de Windows-regels (`uploadAndTrack.terminal.test.ts`: `failed`, `cancelled` en `error` zijn eindstanden) bleek een gat. `TaskStatus` kent geen `failed` of `cancelled`, en de decoder viel bij een onbekende status terug op `.pending`, dus zo'n taak telde als actief en kreeg een nieuwe stream. De decoder (Models/Models.swift, `TranscriptTask.init(from:)`) zet `failed`, `cancelled` en `canceled` nu op `.error`.

`startSSEStream` had al een guard tegen een bestaande client voor dezelfde `taskId` (RecordingViewModel.swift:1167, opnieuw gecontroleerd na de await op :1173). Er is niets toegevoegd.
