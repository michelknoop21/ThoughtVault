# Audiokwaliteitsproef (macOS)

Deze hulpmiddelen vergelijken kandidaten buiten de app. Er is geen normalisatie
in de transcriptieroute geactiveerd. Opname, import en opnieuw transcriberen
blijven het origineel gebruiken totdat de goedgekeurde kwaliteitsdrempel is gehaald.

Gebruik een eigen bewijsmap op de externe SSD als `$EVIDENCE`:

```sh
mkdir -p "$EVIDENCE/tmp" "$EVIDENCE/ModuleCache"
TMPDIR="$EVIDENCE/tmp" swiftc -module-cache-path "$EVIDENCE/ModuleCache" \
  scripts/audio-quality/Normalize.swift scripts/audio-quality/main.swift \
  macos/Services/AudioMixer.swift -o "$EVIDENCE/audio-quality"
TMPDIR="$EVIDENCE/tmp" swiftc -module-cache-path "$EVIDENCE/ModuleCache" \
  scripts/audio-quality/Normalize.swift scripts/audio-quality/SelfCheck.swift \
  -o "$EVIDENCE/audio-selfcheck"
"$EVIDENCE/audio-selfcheck" "$EVIDENCE/tmp"
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/audio-quality
```

De normalisator leest tweemaal in blokken van 16.384 frames, gebruikt één gain
voor alle kanalen, versterkt maximaal 12 dB en begrenst de piek op −1 dBFS.
Digitale stilte blijft nul. Samplefrequentie, kanalen en frameaantal blijven gelijk.
De uitvoer is een afgeleid float-WAV; een bestaand uitvoerbestand wordt geweigerd.
Fouten en annulering verwijderen alleen het eigen tijdelijke bestand. Ctrl-C
annuleert normalisatie per blok. De bestaande synchrone mixer wordt niet aangepast;
bij Ctrl-C tijdens mengen wordt zijn resultaat na afronding verwijderd.

Vergelijk de bestaande mixer met de twee kandidaten:

```sh
"$EVIDENCE/audio-quality" mix mic.wav system.wav 0 "$EVIDENCE/original.wav"
"$EVIDENCE/audio-quality" normalize "$EVIDENCE/original.wav" "$EVIDENCE/post-mix.wav"
"$EVIDENCE/audio-quality" normalize mic.wav "$EVIDENCE/mic-normalized.wav"
"$EVIDENCE/audio-quality" normalize system.wav "$EVIDENCE/system-normalized.wav"
"$EVIDENCE/audio-quality" mix "$EVIDENCE/mic-normalized.wav" \
  "$EVIDENCE/system-normalized.wav" 0 "$EVIDENCE/per-source.wav"
```

Vervang `0` door de werkelijk gemeten startoffset. De mixer accepteert de bestaande
16-kHz mono-opnamebronnen; converteer importbestanden via de bestaande app-route.
Een al gemengd opnamebestand kan alleen met de kandidaat na mengen worden
vergeleken: individuele sprekers worden niet uit het mengsel gereconstrueerd.

Transcribeer alle varianten met hetzelfde model en dezelfde instellingen. Gebruik
`score.py vergelijking.json` met het formaat in de modulebeschrijving. Het script
schrijft uitsluitend scores en geeft exit 1 zolang de drempel niet gehaald is.
Handmatig gecontroleerde referenties en foutaantallen voor namen, getallen en
afspraken zijn vereist. Minstens 5% relatieve WER-winst op probleemclips, maximaal
1 procentpunt achteruitgang op iedere schone clip en geen extra kritieke fouten.
Een gelijkspel houdt het origineel. Een kleine synthetische set bewijst geen
kwaliteit op echte gesprekken, overlappende sprekers of beschadigde opnames.

## App-tests

`SystemAudioStorageTests` bevat de bestaande late-formaatmeldingstest (maximaal
2 frames afwijking), een 16/24/44,1/48-kHz mono/stereo-test (maximaal 1 ms), een
versnelde twee-uursstroom met unieke bloksterktes en optionele echte spraakproeven.
De lange synthetische proef controleert 119 wissels en 359.640 blokken buiten de
wisselranden. Dit is geen twee uur opname met fysieke apparaten.

Hardwaretests zijn standaard uitgeschakeld. Plaats alleen voor een eigen proef
`/tmp/thoughtvault-system-audio-test` als symlink naar de eigen SSD-bewijsmap:

- `enabled` en `levels.wav`: bestaande korte toon- en microfoon-doorvoertest.
- `speech-enabled` en `speech.wav`: 30 seconden 16-kHz mono-spraak voor opname
  via de echte systeemuitvoer. De Bluetooth-variant opent/sluit de aangesloten
  headsetmicrofoon twee keer en pauzeert/hervat eenmaal. Microfoondata wordt
  niet bewaard; het systeemgeluid is hoorbaar in de koptelefoon.
- `soak-enabled`: versnelde synthetische twee-uursproef.

Verwijder de eigen markers en symlink na afloop. De sandbox schrijft zijn
opname-tussenbestanden in de eigen tijdelijke testmap en verwijdert die met
`defer`; blijvend audiobewijs gaat als XCTest-bijlage naar het xcresult op de SSD.
Controleer na de run ook deze interne tijdelijke testmap. Verwijder geen mappen
van andere testsessies. De tests vervangen geen menselijke luistercontrole.
